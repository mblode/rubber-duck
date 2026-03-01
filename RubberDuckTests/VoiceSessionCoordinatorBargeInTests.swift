import XCTest
@testable import RubberDuck

@MainActor
final class VoiceSessionCoordinatorBargeInTests: XCTestCase {

    private final class MockAudioManager: VoiceAudioManaging {
        var isStreaming: Bool = false
        var isMicrophonePermissionDenied: Bool = false
        var muteInput: Bool = false
        var isEchoCancellationActive: Bool = true

        func startStreaming(onChunk: @escaping (String) -> Void, onError: ((Error) -> Void)?) {
            isStreaming = true
        }

        func stopStreaming() {
            isStreaming = false
        }
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

    private func makeHarness(bargeInDelay: TimeInterval = 0.05, echoCancellationActive: Bool = true) -> Harness {
        let audioManager = MockAudioManager()
        audioManager.isEchoCancellationActive = echoCancellationActive
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
        XCTAssertEqual(harness.realtimeClient.cancelResponseCallCount, 1)
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

    func test_speechStartedDuringSpeakingWithoutAEC_isIgnoredEvenIfMuteRaceOccurs() async throws {
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

        // Simulate a transient mute race on hardware without AEC.
        harness.audioManager.muteInput = false

        harness.coordinator.realtimeClientDidDetectSpeechStarted(harness.realtimeClient)
        try await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(harness.playbackManager.stopImmediatelyCallCount, 0)
        XCTAssertTrue(harness.realtimeClient.truncateCalls.isEmpty)
        XCTAssertEqual(harness.coordinator.sessionState, .speaking)
    }
}
