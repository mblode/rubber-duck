import Foundation

struct RealtimeReconnectionPolicy {
    static let maxReconnectAttempts = 3

    static func shouldReconnect(
        intentionalDisconnect: Bool,
        disposition: RealtimeErrorRetryDisposition?,
        reconnectAttempt: Int,
        maxReconnectAttempts: Int
    ) -> Bool {
        guard !intentionalDisconnect else { return false }
        if disposition == .nonRetryable { return false }
        return reconnectAttempt < maxReconnectAttempts
    }

    static func resolvedModelForConnectionAttempt(configuredModel: String, reconnectAttempt: Int) -> String {
        _ = reconnectAttempt
        return configuredModel
    }
}
