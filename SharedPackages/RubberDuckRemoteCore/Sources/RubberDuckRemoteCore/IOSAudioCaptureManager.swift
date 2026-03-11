#if os(iOS)
import Foundation

@MainActor
public final class IOSAudioCaptureManager {
    private let inputManager: IOSAudioInputManager

    public init(inputManager: IOSAudioInputManager = IOSAudioInputManager()) {
        self.inputManager = inputManager
    }

    public var microphonePermissionDenied: Bool {
        inputManager.microphonePermissionDenied
    }

    public func startStreaming(
        onChunk: @escaping (String) -> Void
    ) async throws {
        try await inputManager.start(onChunk: onChunk)
    }

    public func stopStreaming() {
        inputManager.stop()
    }
}
#endif
