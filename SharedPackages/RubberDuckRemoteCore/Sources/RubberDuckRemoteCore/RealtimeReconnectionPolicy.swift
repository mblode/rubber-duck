import Foundation

struct RealtimeReconnectionPolicy {
    static let maxReconnectAttempts = 3

    static func shouldReconnect(
        intentionalDisconnect: Bool,
        disposition: RealtimeErrorRetryDisposition?,
        reconnectAttempt: Int,
        maxReconnectAttempts: Int
    ) -> Bool {
        guard !intentionalDisconnect else {
            return false
        }

        if disposition == .nonRetryable {
            return false
        }

        return reconnectAttempt < maxReconnectAttempts
    }

    static func retryDelay(for reconnectAttempt: Int) -> Duration {
        switch reconnectAttempt {
        case 0:
            return .seconds(1)
        case 1:
            return .seconds(2)
        default:
            return .seconds(4)
        }
    }

    static func resolvedModelForConnectionAttempt(
        configuredModel: String,
        reconnectAttempt: Int
    ) -> String {
        _ = reconnectAttempt
        return configuredModel
    }
}
