import XCTest
@testable import RubberDuck

@MainActor
final class VoiceSessionCoordinatorStartupFailureTests: XCTestCase {

    private struct StartupFailure: LocalizedError {
        var errorDescription: String? { "startup failure" }
    }

    private final class FailingAudioManager: VoiceAudioManaging {
        var isStreaming: Bool = false
        var isMicrophonePermissionDenied: Bool = false

        func startStreaming(onChunk: @escaping (String) -> Void, onError: ((Error) -> Void)?) {
            onError?(StartupFailure())
        }

        func stopStreaming() {
            isStreaming = false
        }
    }

    private final class DeferredAudioManager: VoiceAudioManaging {
        var isStreaming: Bool = false
        var isMicrophonePermissionDenied: Bool = false
        private var onError: ((Error) -> Void)?

        func startStreaming(onChunk: @escaping (String) -> Void, onError: ((Error) -> Void)?) {
            self.onError = onError
        }

        func stopStreaming() {
            isStreaming = false
        }

        func emitDeferredError() {
            onError?(StartupFailure())
        }
    }

    private final class MockPlaybackManager: VoiceAudioPlayback {
        var isPlaying: Bool = false
        var stopPlaybackCallCount = 0

        func startPlayback() {
            isPlaying = true
        }

        func stopPlayback() {
            stopPlaybackCallCount += 1
            isPlaying = false
        }

        func stopImmediately() -> Int {
            isPlaying = false
            return 0
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

    func test_startupFailure_showsErrorWithoutImmediateOverlayDismiss() async throws {
        let audioManager = FailingAudioManager()
        let playbackManager = MockPlaybackManager()
        let realtimeClient = MockRealtimeClient()  // from TestMocks.swift
        let overlay = MockOverlayPresenter()
        let suiteName = "VoiceSessionCoordinatorStartupFailureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = VoiceSessionCoordinator(
            audioManager: audioManager,
            playbackManager: playbackManager,
            realtimeClient: realtimeClient,
            overlay: overlay,
            userDefaults: defaults,
            bargeInConfirmationDelaySeconds: 0.05
        )

        coordinator.realtimeClientDidBecomeReady(realtimeClient)
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(coordinator.sessionState, .idle)
        XCTAssertEqual(overlay.dismissCount, 0)
        XCTAssertTrue(
            overlay.shownStates.contains(where: {
                if case .error(let message) = $0 {
                    return message.contains("Microphone error")
                }
                return false
            }),
            "Expected microphone startup failure to surface as overlay error"
        )
    }

    func test_deferredAudioError_afterDisconnect_isIgnored() async throws {
        let audioManager = DeferredAudioManager()
        let playbackManager = MockPlaybackManager()
        let realtimeClient = MockRealtimeClient()
        realtimeClient.connectionState = .connected
        let overlay = MockOverlayPresenter()
        let suiteName = "VoiceSessionCoordinatorStartupFailureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let coordinator = VoiceSessionCoordinator(
            audioManager: audioManager,
            playbackManager: playbackManager,
            realtimeClient: realtimeClient,
            overlay: overlay,
            userDefaults: defaults,
            bargeInConfirmationDelaySeconds: 0.05
        )

        coordinator.realtimeClientDidBecomeReady(realtimeClient)
        coordinator.disconnectSession()
        audioManager.emitDeferredError()
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(coordinator.sessionState, .idle)
        XCTAssertFalse(
            overlay.shownStates.contains(where: {
                if case .error = $0 {
                    return true
                }
                return false
            }),
            "Deferred startup errors after disconnect should be ignored"
        )
    }
}
