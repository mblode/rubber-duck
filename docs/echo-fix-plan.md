# Echo-Triggered False Barge-In Loop: Diagnosis and Fix Plan

## 1. Problem Description

### What the infinite loop looks like

1. The assistant begins speaking a response through the Mac speaker.
2. The microphone picks up that audio (echo).
3. The server-side VAD classifies the echo as user speech starting.
4. Barge-in fires: the current response is cancelled and the session resets.
5. The assistant begins a new response, usually confused or partial.
6. That new response is itself echoed back into the mic.
7. Go to step 3. The loop continues indefinitely.

### Why this is hard

The system must keep the microphone open during playback. A user might genuinely want to interrupt the assistant mid-sentence — that is the entire purpose of barge-in. Muting the mic during assistant speech would fix the echo loop but destroy the feature. The problem is therefore one of discrimination: the system must distinguish "user's voice" from "echo of assistant's voice" while they overlap in the same audio stream.

### Three layers of protection and why each can fail

**Layer 1: Hardware Acoustic Echo Cancellation (VoiceProcessingIO)**
CoreAudio's `kAudioUnitSubType_VoiceProcessingIO` runs AEC in the kernel with very low latency. When it works, it removes the echo before the capture tap ever sees it. It fails on multi-channel aggregate devices (USB audio interfaces, Scarlett, etc.) with error -10875 because VoiceProcessingIO does not support more than two input channels, causing a silent fallback to standard I/O with no AEC.

**Layer 2: Software AEC (PlaybackReferenceBuffer)**
When hardware AEC is unavailable, `AudioManager` maintains a ring buffer of recently played PCM samples and subtracts them from the capture stream using `vDSP_vsma`. This attenuates echo but is imperfect: it depends on accurate delay estimation and gain calibration, both of which can drift. It also suffers from underruns if the buffer has not yet accumulated enough history (e.g. at the very start of playback).

**Layer 3: Guard windows and confirmation delays in VoiceSessionCoordinator**
After the assistant produces audio, the coordinator enforces a minimum duration before a barge-in can be accepted. If speech is detected within that window, it is ignored. A secondary confirmation delay requires the VAD to sustain "speech active" for a minimum period before committing to a barge-in. Both windows have configuration constants that must be tuned correctly relative to echo propagation time.

Any single layer failing while the others are insufficient will produce the loop.

---

## 2. Root Cause Analysis

### Bug A — Timestamps cleared at response boundary (CRITICAL)

**File:** `RubberDuck/VoiceSessionCoordinator.swift`, `didReceiveResponseCreated()`

When the server sends a `response.created` event, the coordinator reset `lastAssistantAudioDeltaAt` to `nil`. This fires before the first audio delta of the new response arrives.

During that interval — which can be several hundred milliseconds while the model generates tokens and the server buffers audio — both `lastAssistantAudioDeltaAt` and `lastAssistantAudioEndedAt` are `nil`. The guard check in `shouldAllowBargeIn()` computes elapsed time as "forever ago" and immediately allows barge-in. Any echo from the tail end of the previous response (which is still audible) can trigger an interrupt during this window.

**Fix applied:** Removed the `lastAssistantAudioDeltaAt = nil` assignment from `didReceiveResponseCreated()`. The timestamp now persists and is only overwritten when the first audio delta of the new response arrives, closing the gap completely.

---

### Bug B — Software AEC guard window shorter than hardware AEC (HIGH)

**File:** `RubberDuck/VoiceSessionCoordinator.swift`, line 97

```swift
// Before
let speechStartGuardAfterAssistantAudioSecondsWithSoftwareAEC: TimeInterval = 0.18

// After
let speechStartGuardAfterAssistantAudioSecondsWithSoftwareAEC: TimeInterval = 0.30
```

The hardware AEC guard window was 0.22s, and the software AEC guard was 0.18s — shorter, despite software AEC being less reliable. Users who cannot use VoiceProcessingIO (any USB audio device) always fall through to software AEC and therefore had a smaller margin than users on the built-in mic.

Echo takes time to travel from speaker to mic, and further time for the buffer to accumulate. The 0.18s window was not long enough to cover the initial underrun period where no subtraction is applied.

**Fix applied:** Increased from 0.18s to 0.30s.

---

### Bug C — VAD eagerness too aggressive (HIGH)

**File:** `RubberDuck/RealtimeClient.swift`, `baseSessionConfig()`

```swift
// Before
"eagerness": "auto"

// After
"eagerness": "low"
```

The `turn_detection` object in the session configuration included `"eagerness": "auto"`. The OpenAI Realtime API documentation notes that higher eagerness causes the model to "jump in as soon as it thinks you might be done speaking." In auto mode the server selects eagerness based on context, and in a voice agent scenario it tends toward high to minimize latency.

This means the server-side VAD fires on the leading edge of an echo onset — the brief transient as the speaker begins to produce sound. That transient does not need to be very loud to cross the detection threshold when eagerness is high.

**Fix applied:** Changed to `"eagerness": "low"`. The server now waits for more sustained audio before committing to a speech start event.

---

### Bug D — AEC reference buffer underrun not reflected in guard (MEDIUM)

**File:** `RubberDuck/AudioManager.swift` and `RubberDuck/VoiceSessionCoordinator.swift`

`PlaybackReferenceBuffer.read()` returns `false` when there is not enough buffered history (underrun). When that happens, `AudioManager` skips the subtraction step — the capture audio passes through without echo cancellation. However, `isSoftwareAECActive` remains `true` because it reflects configuration state, not runtime effectiveness.

The coordinator checks `isSoftwareAECActive` to decide which guard window to use. When underrun is occurring, the shorter software AEC guard is applied even though AEC is not actually running. The echo passes through at full strength during what the coordinator thinks is a protected window.

**Partial mitigation:** Bug B's increase to 0.30s reduces the window during which an underrun matters, since the buffer typically fills within that interval after playback starts.

**Future fix (not yet applied):** See Section 6.

---

### Bug E — Gain calibration resumes too quickly (MEDIUM)

**File:** `RubberDuck/AudioManager.swift`, `updateEchoCancellationGain()`

```swift
// Before: suppress calibration for 0.5s after speech detected
// After: suppress calibration for 1.2s after speech detected
```

The AEC gain is calibrated continuously by comparing the energy of the raw capture signal to the reference buffer. When the user is genuinely speaking, the capture has voice energy that should not be used to tune the echo cancellation gain. The code suppressed calibration for 0.5s after user speech was detected.

The problem: when the user stops speaking and the assistant begins responding, there is often a 0.5–1.0s gap. The calibration would resume, see the echo arriving in the capture stream, and tune the gain downward to match it — interpreting the echo as "quiet room" rather than "echo to cancel." On the next speech event, the AEC gain was too low to cancel the echo effectively.

**Fix applied:** Increased suppression from 0.5s to 1.2s, which covers the gap between user speech end and assistant audio start.

---

### Bug F — Confirmation delay not extended for software AEC (LOW-MEDIUM)

**File:** `RubberDuck/VoiceSessionCoordinator.swift`, `effectiveBargeInConfirmationDelaySeconds()`

```swift
// Before: minimum 0.55s confirmation only when no AEC at all
// After: minimum 0.45s confirmation when using software AEC only
```

The confirmation delay is how long the system waits after barge-in detection before actually committing the interrupt. A longer delay gives echo to fade, the VAD to reconsider, and the guard to potentially re-engage. The 0.55s minimum was only applied in the no-AEC code path. Software AEC mode used the default 0.35s delay.

Software AEC is weaker than hardware VoiceProcessingIO. It produces residual echo that can sustain a VAD "speech active" signal long enough to survive a 0.35s confirmation window.

**Fix applied:** Added `minimumBargeInConfirmationDelayWithSoftwareAECSeconds = 0.45` and applied it in `effectiveBargeInConfirmationDelaySeconds()` when the mode is software AEC only.

---

## 3. Fixes Applied

- [x] Bug A: Keep `lastAssistantAudioDeltaAt` across response boundaries
- [x] Bug B: Software AEC guard window 0.18s → 0.30s
- [x] Bug C: VAD eagerness `"auto"` → `"low"`
- [ ] Bug D: Expose `isAECCurrentlyEffective` on protocol (future)
- [x] Bug E: Gain calibration suppression 0.5s → 1.2s
- [x] Bug F: Add 0.45s minimum confirmation delay for software AEC

---

## 4. Files Changed

| File | Change |
|------|--------|
| `RubberDuck/VoiceSessionCoordinator.swift` | Bugs A, B, F |
| `RubberDuck/RealtimeClient.swift` | Bug C |
| `RubberDuck/AudioManager.swift` | Bug E |

---

## 5. Verification

**Build and install:**

```bash
xcodebuild -scheme Commandment -configuration Debug -destination 'generic/platform=macOS' build -derivedDataPath /tmp/rubber-duck-build
rsync -a --delete "/tmp/rubber-duck-build/Build/Products/Debug/Rubber Duck.app/" "/Applications/Rubber Duck.app/"
open "/Applications/Rubber Duck.app"
```

**Test 1 — No false barge-in (regression test for the loop):**

1. Start a voice session.
2. Ask a question that produces a long response (e.g. "Explain how TCP handshakes work").
3. Do not say anything while the assistant speaks.
4. Verify the assistant completes its response without interruption.
5. Repeat with speaker volume at maximum to maximise echo.

**Test 2 — Genuine barge-in still works:**

1. Start a session and ask for a long response.
2. Wait ~2s for the assistant to start speaking.
3. Speak clearly — say "stop" or ask a new question.
4. Verify the assistant stops and processes the new input.

**Test 3 — Software AEC path specifically (USB audio device users):**

1. Connect a USB audio interface or aggregate device that triggers the -10875 error.
2. Verify `isSoftwareAECActive` is `true` in logs.
3. Run test 1 and test 2 on this device.

**Test 4 — Barge-in latency check:**

After applying `"eagerness": "low"`, genuine barge-in may feel slightly slower. Measure subjectively: from the moment you start speaking to the moment the assistant stops. This should remain under ~800ms on a typical connection.

---

## 6. Future Improvements

**Bug D: Runtime AEC effectiveness signal**

Add `isAECCurrentlyEffective: Bool` to the `VoiceAudioManaging` protocol. `AudioManager` implements this as:

```swift
var isAECCurrentlyEffective: Bool {
    isSoftwareAECActive && lastAECReadSucceeded
}
```

where `lastAECReadSucceeded` is an `_Atomic(Bool)` (or `os_unfair_lock`-protected `Bool`) set by the CoreAudio real-time capture tap each time `PlaybackReferenceBuffer.read()` is called. When this is `false`, `VoiceSessionCoordinator` falls back to the no-AEC guard window (the widest one) rather than the software AEC guard window.

Thread safety consideration: the capture tap runs on a real-time audio thread; `VoiceSessionCoordinator` reads on the main actor. Use `_Atomic` or an `os_unfair_lock`-protected struct. Do not use a `DispatchQueue` from the audio thread.

**Alternative VAD configuration for severe echo environments**

For users who report persistent echo even after the above fixes, expose a `vadThreshold` slider in Settings > Audio. The OpenAI Realtime API `server_vad` turn detection object accepts a `threshold` parameter (0.0–1.0, default 0.5). Raising it to 0.7–0.8 can eliminate echo-triggered VAD events at the cost of needing slightly louder speech to trigger detection.

**Diagnostic logging for AEC effectiveness**

Add a `logDebug` call in `AudioManager` that emits AEC read success rate once per second:

```
[AEC] read_success_rate=0.94 gain=0.15 delay_samples=1440
```

This would allow correlating false barge-in events with AEC underrun rates in the log file (`~/Library/Application Support/RubberDuck/duck-daemon.log` equivalent for the Swift side), making future regressions easier to diagnose without requiring a live debug session.
