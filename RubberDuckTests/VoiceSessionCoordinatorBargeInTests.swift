import XCTest
@testable import RubberDuck

@MainActor
final class VoiceSessionCoordinatorBargeInTests: XCTestCase {

    private final class MockAudioManager: VoiceAudioManaging {
        var isStreaming: Bool = false
        var isMicrophonePermissionDenied: Bool = false
        var muteInput: Bool = false
        var isEchoCancellationActive: Bool = true
        var isSoftwareAECActive: Bool = false

        func startStreaming(onChunk: @escaping (String) -> Void, onError: ((Error) -> Void)?) {
            isStreaming = true
        }

        func stopStreaming() {
            isStreaming = false
        }

        var notifySpeechDetectedCallCount = 0
        func notifySpeechDetected() { notifySpeechDetectedCallCount += 1 }
    }

    private final class MockPlaybackManager: VoiceAudioPlayback {
        var isPlaying: Bool = false
        var startPlaybackCallCount = 0
        var stopPlaybackCallCount = 0
        var stopImmediatelyCallCount = 0
        var stopImmediatelySamples = 24_000

        func startPlayback() {
            startPlaybackCallCount += 1
            isPlaying = true
        }

        func stopPlayback() {
            stopPlaybackCallCount += 1
            isPlaying = false
        }

        func stopImmediately() -> Int {
            stopImmediatelyCallCount += 1
            isPlaying = false
            return stopImmediatelySamples
        }

        func enqueueAudio(base64Chunk: String, itemId: String?, contentIndex: Int?) {
            isPlaying = true
        }
    }

    private final class MockOverlayPresenter: OverlayPresenting {
        var shownStates: [OverlayState] = []
        var dismissCount = 0

        func show(state: OverlayState) {
            shownStates.append(state)
        }

        func dismiss() {
            dismissCount += 1
        }
    }

    private struct Harness {
        let coordinator: VoiceSessionCoordinator
        let audioManager: MockAudioManager
        let realtimeClient: MockRealtimeClient  // from TestMocks.swift
        let playbackManager: MockPlaybackManager
        let defaultsSuiteName: String
    }

    private func makeHarness(bargeInDelay: TimeInterval = 0.05,
                             echoCancellationActive: Bool = true,
                             softwareAECActive: Bool = false) -> Harness {
        let audioManager = MockAudioManager()
        audioManager.isEchoCancellationActive = echoCancellationActive
        audioManager.isSoftwareAECActive = softwareAECActive
        let playbackManager = MockPlaybackManager()
        let realtimeClient = MockRealtimeClient()
        let overlay = MockOverlayPresenter()

        let suiteName = "VoiceSessionCoordinatorBargeInTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: "autoAbortOnBargeIn")

        let coordinator = VoiceSessionCoordinator(
            audioManager: audioManager,
            playbackManager: playbackManager,
            realtimeClient: realtimeClient,
            overlay: overlay,
            userDefaults: defaults,
            bargeInConfirmationDelaySeconds: bargeInDelay
        )

        return Harness(
            coordinator: coordinator,
            audioManager: audioManager,
            realtimeClient: realtimeClient,
            playbackManager: playbackManager,
            defaultsSuiteName: suiteName
        )
    }

    func test_transientSpeechDuringAssistantPlayback_doesNotTriggerBargeIn() async throws {
        let harness = makeHarness(bargeInDelay: 0.08)
        defer {
            UserDefaults(suiteName: harness.defaultsSuiteName)?
                .removePersistentDomain(forName: harness.defaultsSuiteName)
        }

        harness.coordinator.realtimeClient(
            harness.realtimeClient,
            didReceiveAudioDelta: "AAAA",
            itemId: "item-1",
            contentIndex: 0
        )
        XCTAssertEqual(harness.coordinator.sessionState, .speaking)

        harness.coordinator.realtimeClientDidDetectSpeechStarted(harness.realtimeClient)
        try await Task.sleep(nanoseconds: 20_000_000)
        harness.coordinator.realtimeClientDidDetectSpeechStopped(harness.realtimeClient)
        try await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertTrue(harness.realtimeClient.truncateCalls.isEmpty)
        XCTAssertEqual(harness.playbackManager.stopImmediatelyCallCount, 0)
        XCTAssertEqual(harness.coordinator.sessionState, .speaking)
    }

    func test_sustainedSpeechDuringAssistantPlayback_triggersBargeIn() async throws {
        let harness = makeHarness(bargeInDelay: 0.03)
        defer {
            UserDefaults(suiteName: harness.defaultsSuiteName)?
                .removePersistentDomain(forName: harness.defaultsSuiteName)
        }

        harness.coordinator.realtimeClient(
            harness.realtimeClient,
            didReceiveAudioDelta: "AAAA",
            itemId: "item-42",
            contentIndex: 0
        )
        XCTAssertEqual(harness.coordinator.sessionState, .speaking)

        // Allow the assistant-audio guard window to pass before a sustained
        // user interruption is detected as barge-in.
        try await Task.sleep(nanoseconds: 260_000_000)
        harness.coordinator.realtimeClientDidDetectSpeechStarted(harness.realtimeClient)
        try await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(harness.playbackManager.stopImmediatelyCallCount, 1)
        XCTAssertGreaterThanOrEqual(harness.playbackManager.startPlaybackCallCount, 1)
        XCTAssertEqual(harness.realtimeClient.cancelResponseCallCount, 0)
        XCTAssertEqual(harness.realtimeClient.truncateCalls.count, 1)
        XCTAssertEqual(harness.realtimeClient.truncateCalls[0].itemId, "item-42")
        XCTAssertEqual(harness.realtimeClient.truncateCalls[0].contentIndex, 0)
        XCTAssertEqual(harness.realtimeClient.truncateCalls[0].audioEnd, 0)
        XCTAssertFalse(harness.realtimeClient.truncateCalls[0].sendCancel)
        XCTAssertEqual(harness.coordinator.sessionState, .listening)
    }

    func test_staleAudioDeltaAfterBargeIn_isIgnoredUntilNextResponseCreated() async throws {
        let harness = makeHarness(bargeInDelay: 0.03)
        defer {
            UserDefaults(suiteName: harness.defaultsSuiteName)?
                .removePersistentDomain(forName: harness.defaultsSuiteName)
        }

        harness.coordinator.realtimeClient(
            harness.realtimeClient,
            didReceiveAudioDelta: "AAAA",
            itemId: "item-stale",
            contentIndex: 0
        )
        XCTAssertEqual(harness.coordinator.sessionState, .speaking)

        try await Task.sleep(nanoseconds: 260_000_000)
        harness.coordinator.realtimeClientDidDetectSpeechStarted(harness.realtimeClient)
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(harness.coordinator.sessionState, .listening)

        // This delta belongs to the interrupted response and should be dropped.
        harness.coordinator.realtimeClient(
            harness.realtimeClient,
            didReceiveAudioDelta: "BBBB",
            itemId: "item-stale",
            contentIndex: 0
        )
        XCTAssertEqual(harness.coordinator.sessionState, .listening)

        // New response boundary re-enables assistant audio handling.
        harness.coordinator.realtimeClient(harness.realtimeClient, didReceiveResponseCreated: [:])
        harness.coordinator.realtimeClient(
            harness.realtimeClient,
            didReceiveAudioDelta: "CCCC",
            itemId: "item-next",
            contentIndex: 0
        )
        XCTAssertEqual(harness.coordinator.sessionState, .speaking)
    }

    /// Without hardware AEC (software AEC only), the mic must be muted during playback
    /// to prevent echo from reaching the server. Barge-in is intentionally disabled in
    /// this mode since echo suppression is not reliable enough at the scalar AEC level.
    func test_noHardwareAEC_withSoftwareAEC_mutesDuringPlayback_noBargein() async throws {
        let harness = makeHarness(bargeInDelay: 0.03, echoCancellationActive: false, softwareAECActive: true)
        defer {
            UserDefaults(suiteName: harness.defaultsSuiteName)?
                .removePersistentDomain(forName: harness.defaultsSuiteName)
        }

        harness.coordinator.realtimeClient(
            harness.realtimeClient,
            didReceiveAudioDelta: "AAAA",
            itemId: "item-sw-aec",
            contentIndex: 0
        )
        XCTAssertEqual(harness.coordinator.sessionState, .speaking)

        // Without hardware AEC, mic must be muted during playback to prevent echo loops.
        XCTAssertTrue(harness.audioManager.muteInput,
                      "Mic must be muted during playback when hardware AEC is unavailable")

        // Speech events during muted playback must not trigger barge-in.
        try await Task.sleep(nanoseconds: 260_000_000)
        harness.coordinator.realtimeClientDidDetectSpeechStarted(harness.realtimeClient)
        try await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(harness.playbackManager.stopImmediatelyCallCount, 0,
                       "Barge-in must not fire when mic is muted")
        XCTAssertEqual(harness.coordinator.sessionState, .speaking)
    }

    /// A `speech_started` event suppressed by the assistant-audio guard window must NOT call
    /// `notifySpeechDetected()` — that would block gain calibration and create the catch-22 loop
    /// where echo prevents calibration from ever converging.
    func test_suppressedSpeechStarted_doesNotCallNotifySpeechDetected() async throws {
        // Hardware AEC on — mic stays open during playback so guard window logic applies.
        let harness = makeHarness(bargeInDelay: 0.05, echoCancellationActive: true)
        defer {
            UserDefaults(suiteName: harness.defaultsSuiteName)?
                .removePersistentDomain(forName: harness.defaultsSuiteName)
        }

        // Start a response — sets lastAssistantAudioDeltaAt.
        harness.coordinator.realtimeClient(
            harness.realtimeClient,
            didReceiveAudioDelta: "AAAA",
            itemId: "item-echo",
            contentIndex: 0
        )
        XCTAssertEqual(harness.coordinator.sessionState, .speaking)

        // Fire speech_started immediately — within the hardware-AEC guard window (0.22 s).
        // The coordinator must suppress it AND must NOT call notifySpeechDetected().
        harness.coordinator.realtimeClientDidDetectSpeechStarted(harness.realtimeClient)

        XCTAssertEqual(harness.audioManager.notifySpeechDetectedCallCount, 0,
                       "notifySpeechDetected must not be called for a suppressed speech_started event")
        XCTAssertEqual(harness.coordinator.sessionState, .speaking,
                       "Session must remain in speaking state when speech_started is suppressed")
    }

    /// A `speech_started` event that passes all guard windows must call `notifySpeechDetected()`
    /// exactly once so gain calibration is paused during real user speech.
    func test_acceptedSpeechStarted_callsNotifySpeechDetectedOnce() async throws {
        // Hardware AEC on — mic stays open during playback so barge-in and notifySpeechDetected work.
        let harness = makeHarness(bargeInDelay: 0.05, echoCancellationActive: true)
        defer {
            UserDefaults(suiteName: harness.defaultsSuiteName)?
                .removePersistentDomain(forName: harness.defaultsSuiteName)
        }

        harness.coordinator.realtimeClient(
            harness.realtimeClient,
            didReceiveAudioDelta: "AAAA",
            itemId: "item-real",
            contentIndex: 0
        )
        XCTAssertEqual(harness.coordinator.sessionState, .speaking)

        // Wait past the hardware-AEC guard window (0.22 s) so the event is accepted.
        try await Task.sleep(nanoseconds: 260_000_000)
        harness.coordinator.realtimeClientDidDetectSpeechStarted(harness.realtimeClient)

        XCTAssertEqual(harness.audioManager.notifySpeechDetectedCallCount, 1,
                       "notifySpeechDetected must be called exactly once for an accepted speech_started event")
    }

    /// Without hardware AEC (no AEC at all), the mic must be muted during playback to prevent
    /// echo from reaching the server and triggering false barge-in.
    func test_speakingWithoutAEC_mutesDuringPlayback_noBargein() async throws {
        let harness = makeHarness(bargeInDelay: 0.03, echoCancellationActive: false)
        defer {
            UserDefaults(suiteName: harness.defaultsSuiteName)?
                .removePersistentDomain(forName: harness.defaultsSuiteName)
        }

        harness.coordinator.realtimeClient(
            harness.realtimeClient,
            didReceiveAudioDelta: "AAAA",
            itemId: "item-no-aec",
            contentIndex: 0
        )
        XCTAssertEqual(harness.coordinator.sessionState, .speaking)

        // Without hardware AEC, mic must be muted during playback.
        XCTAssertTrue(harness.audioManager.muteInput,
                      "Mic must be muted during playback when hardware AEC is unavailable")

        // Even with sustained speech events, barge-in must not fire while muted.
        try await Task.sleep(nanoseconds: 520_000_000)
        harness.coordinator.realtimeClientDidDetectSpeechStarted(harness.realtimeClient)
        try await Task.sleep(nanoseconds: 650_000_000)

        XCTAssertEqual(harness.playbackManager.stopImmediatelyCallCount, 0,
                       "Barge-in must not fire when mic is muted")
        XCTAssertEqual(harness.coordinator.sessionState, .speaking)
    }
}
