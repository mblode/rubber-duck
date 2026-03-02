# Barge-In Architecture

How user speech interrupts the assistant mid-response in RubberDuck.

## Overview

Barge-in is the act of the user speaking while the assistant is still outputting audio. RubberDuck uses a multi-layered system to distinguish genuine user interruptions from echo (the microphone picking up the assistant's own speaker output). The layers are:

1. **Server-side VAD** -- OpenAI Realtime API detects speech onset/offset and sends `input_audio_buffer.speech_started` / `speech_stopped` events.
2. **Guard windows** -- the coordinator suppresses `speech_started` events that arrive too soon after the last assistant audio delta, since they are likely echo.
3. **Confirmation delay** -- after a `speech_started` event passes the guard window, a short timer must expire before the barge-in is committed. If `speech_stopped` fires before the timer, the barge-in is cancelled (transient noise).
4. **Truncation** -- once confirmed, assistant playback is stopped immediately and a `conversation.item.truncate` event is sent to the server so it knows what the user actually heard.

## Event Flow

```
User speaks into mic
        |
        v
OpenAI Realtime API detects speech
        |
        v
Server sends  input_audio_buffer.speech_started
        |
        v
VoiceSessionCoordinator.realtimeClientDidDetectSpeechStarted()
        |
        +-- Is input muted?                          --> ignore
        +-- Inside vadSuppressedUntil window?         --> ignore
        +-- Playback active but state != .speaking?   --> ignore
        +-- Inside assistant-audio guard window?      --> ignore (no notifySpeechDetected)
        +-- Inside post-playback suppression window?  --> ignore (no-AEC only)
        |
        v  (all guards pass)
notifySpeechDetected() called on AudioManager
        |
        +-- State is .speaking?
        |       |
        |       v
        |   scheduleConfirmedBargeIn()
        |       |
        |       +-- Pending barge-in already exists? --> no-op
        |       +-- Confirmation delay == 0?         --> handleBargeIn() immediately
        |       +-- Otherwise: start timer
        |               |
        |               +-- speech_stopped before timer? --> cancel barge-in
        |               +-- Timer fires while still .speaking:
        |                       |
        |                       v
        |                   handleBargeIn()
        |                       |
        |                       +-- stopImmediatelySnapshot() on playback manager
        |                       +-- Set suppressAssistantAudioUntilNextResponseCreated = true
        |                       +-- Send conversation.item.truncate (clamped audioEnd)
        |                       +-- Re-arm player node (startPlayback)
        |                       +-- Transition to .listening
        |
        +-- State is NOT .speaking?
                |
                v
            Cancel any pending barge-in
            Transition to .listening
```

## Guard Windows

Guard windows suppress `speech_started` events that arrive within a time threshold after the most recent assistant audio delta. This prevents the assistant's own speaker output (picked up by the mic) from being misinterpreted as user speech.

| Mode | Constant | Value | Notes |
|------|----------|-------|-------|
| Hardware AEC active | `speechStartGuardAfterAssistantAudioSecondsWithAEC` | 0.22 s | VoiceProcessingIO handles most echo; short guard for residual |
| Software AEC active | `speechStartGuardAfterAssistantAudioSecondsWithSoftwareAEC` | 0.18 s | Software subtraction is effective enough for a tight window |
| No AEC | `speechStartGuardAfterAssistantAudioSecondsWithoutAEC` | 0.45 s | Must be conservative since echo is not cancelled |

Additional no-AEC guards:

| Constant | Value | Purpose |
|----------|-------|---------|
| `postPlaybackSpeechSuppressionWithoutAECSeconds` | 0.9 s | Suppresses `speech_started` after assistant playback ends (tail echo) |
| `minimumBargeInConfirmationDelayWithoutAECSeconds` | 0.55 s | Floor on confirmation delay when no AEC is available |

The `isAnyAECActive` helper returns `true` when either hardware AEC (`isEchoCancellationActive`) or software AEC (`isSoftwareAECActive`) is active. When software AEC is on but hardware AEC is off, the coordinator selects `speechStartGuardAfterAssistantAudioSecondsWithSoftwareAEC` (0.18 s). When hardware AEC is on, it uses `speechStartGuardAfterAssistantAudioSecondsWithAEC` (0.22 s).

## VAD Configuration

The OpenAI Realtime API session is configured in `RealtimeClient.baseSessionConfig()` with the following turn detection settings:

```swift
let turnDetection: [String: Any] = [
    "type": "semantic_vad",
    "eagerness": "auto",
    "interrupt_response": true,
    "create_response": true
]
```

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `type` | `semantic_vad` | Semantic voice activity detection -- the server uses a model to detect meaningful speech boundaries rather than simple energy thresholds |
| `eagerness` | `auto` | Let the server decide how aggressively to end turns |
| `interrupt_response` | `true` | The server will emit `speech_started` events while the assistant is responding, enabling client-side barge-in |
| `create_response` | `true` | The server automatically creates a new response after detecting end of user turn |

Input audio is also configured with noise reduction (`near_field`) and transcription (`gpt-4o-mini-transcribe`).

## Software AEC

When the hardware VoiceProcessingIO audio unit fails (e.g., on devices with multi-channel input that return error -10875), RubberDuck falls back to software acoustic echo cancellation. This is implemented through `PlaybackReferenceBuffer` and signal subtraction in the capture tap.

### PlaybackReferenceBuffer

A lock-free single-producer / single-consumer (SPSC) ring buffer that stores recent playback samples as Float32.

- **Capacity:** 16384 samples at 24 kHz = ~682 ms of history
- **Writer:** `playbackQueue` (serial dispatch queue) -- `AudioPlaybackManager` writes every PCM chunk into the buffer via `write(int16Data:scheduledAt:)` just before scheduling it on the player node
- **Reader:** CoreAudio real-time audio thread -- reads reference samples via `read(into:frameCount:delaySamples:)` with zero locks or allocations
- **Synchronization:** `OSAtomicAdd64Barrier` publishes the write head with a memory barrier; the reader loads it with `OSAtomicAdd64(0, &writeHead)` for a sequentially consistent snapshot
- **Timestamp tracking:** Records `mach_absolute_time()` every 512 samples (~21 ms) for latency estimation between scheduling and capture

### How it enables barge-in

With a reference of what was played through the speaker, `AudioManager` can subtract the expected echo from the captured microphone signal using `vDSP_vsma`. This makes the server's VAD far less likely to fire on echo alone, which in turn allows the guard window to be shorter (0.18 s vs 0.45 s without AEC). The result is faster, more responsive barge-in.

The coordinator also avoids calling `notifySpeechDetected()` for suppressed `speech_started` events. This is important because `notifySpeechDetected()` pauses gain calibration in the AEC system -- calling it on echo would create a catch-22 where echo prevents calibration from ever converging.

## How Truncation Works

When a barge-in is confirmed, the coordinator must tell the server how much of the response the user actually heard. This is done via the `conversation.item.truncate` event.

### Steps

1. **Stop playback immediately** -- `AudioPlaybackManager.stopImmediatelySnapshot()` returns an `AudioPlaybackStopSnapshot` containing `itemScheduledSamples`, `itemPlayedSamples`, and `itemUnplayedSamples` for the current audio item.

2. **Compute audioEnd** -- the raw value is `itemPlayedSamples * 1000 / sampleRate` (converted to milliseconds). This is **clamped** to `[0, itemDurationMs]` to prevent out-of-range values that could cause server errors. `itemDurationMs` is `itemScheduledSamples * 1000 / sampleRate`.

3. **Send truncation event** -- `RealtimeClient.truncateResponse()` sends:
   ```json
   {
     "type": "conversation.item.truncate",
     "item_id": "<item-id>",
     "content_index": <content-index>,
     "audio_end_ms": <clamped-value>
   }
   ```
   The `audio_end_ms` is additionally floored to 0 inside `truncateResponse()` via `max(0, audioEnd)`.

4. **Suppress stale audio** -- `suppressAssistantAudioUntilNextResponseCreated` is set to `true`. Any `output_audio.delta` events that arrive for the interrupted response are dropped. The flag is cleared when the next `response.created` event arrives.

5. **Re-arm playback** -- `startPlayback()` is called to re-arm the player node so the next response can be scheduled without re-initialization.

6. **Transition to listening** -- the session state moves to `.listening` and the overlay updates.

## Key Files

| File | Role |
|------|------|
| `RubberDuck/VoiceSessionCoordinator.swift` | Orchestrates barge-in: guard windows, confirmation delay, truncation, state transitions |
| `RubberDuck/RealtimeClient.swift` | WebSocket connection to OpenAI Realtime API; sends `conversation.item.truncate` and `response.cancel`; configures `semantic_vad` |
| `RubberDuck/PlaybackReferenceBuffer.swift` | Lock-free SPSC ring buffer for software AEC playback reference |
| `RubberDuck/AudioManager.swift` | Microphone capture; software AEC subtraction using playback reference; gain calibration |
| `RubberDuck/AudioPlaybackManager.swift` | Schedules PCM audio on the player node; writes to `PlaybackReferenceBuffer`; provides `stopImmediatelySnapshot()` |
| `RubberDuckTests/VoiceSessionCoordinatorBargeInTests.swift` | Unit tests for all barge-in paths |

## Test Coverage

Tests in `VoiceSessionCoordinatorBargeInTests.swift`:

| Test | What it verifies |
|------|------------------|
| `test_transientSpeechDuringAssistantPlayback_doesNotTriggerBargeIn` | Brief speech during playback that ends before the confirmation delay expires does not trigger barge-in |
| `test_sustainedSpeechDuringAssistantPlayback_triggersBargeIn` | Speech that persists past the guard window and confirmation delay triggers truncation and transitions to `.listening` |
| `test_staleAudioDeltaAfterBargeIn_isIgnoredUntilNextResponseCreated` | Audio deltas from the interrupted response are dropped; new `response.created` re-enables audio handling |
| `test_sustainedSpeechWithSoftwareAEC_triggersBargeInAtShortGuardWindow` | With software AEC active (hardware off), barge-in fires at the shorter 0.18 s guard window |
| `test_suppressedSpeechStarted_doesNotCallNotifySpeechDetected` | A `speech_started` suppressed by the guard window does not call `notifySpeechDetected()`, avoiding gain calibration disruption |
| `test_acceptedSpeechStarted_callsNotifySpeechDetectedOnce` | A `speech_started` that passes all guards calls `notifySpeechDetected()` exactly once |
| `test_sustainedSpeechDuringSpeakingWithoutAEC_triggersDegradedBargeIn` | Without any AEC, barge-in still works but requires longer guard (0.45 s) and confirmation (0.55 s minimum) windows |
