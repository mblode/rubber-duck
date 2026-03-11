import Foundation

public enum RealtimeAudioConstants {
    public static let sampleRate: Double = 24_000
    public static let channels: UInt32 = 1
    public static let captureBufferSize: UInt32 = 1_024
}

private let remoteRealtimeLogQueue = DispatchQueue(
    label: "co.blode.rubber-duck.remote-realtime-log"
)

private func remoteRealtimeLog(
    level: String,
    message: String
) {
    remoteRealtimeLogQueue.async {
        let timestamp = ISO8601DateFormatter().string(from: .now)
        fputs("[\(timestamp)] [\(level)] \(message)\n", stderr)
    }
}

func logInfo(_ message: String) {
    remoteRealtimeLog(level: "INFO", message: message)
}

func logError(_ message: String) {
    remoteRealtimeLog(level: "ERROR", message: message)
}

func logDebug(_ message: String) {
    guard ProcessInfo.processInfo.environment["RUBBER_DUCK_REMOTE_DEBUG"] == "1" else {
        return
    }

    remoteRealtimeLog(level: "DEBUG", message: message)
}
