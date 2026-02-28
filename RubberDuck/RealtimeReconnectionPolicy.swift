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

    static func shouldUseMinimalStartupConfigFallback(reconnectAttempt: Int) -> Bool {
        reconnectAttempt >= 1
    }

    static func resolvedModelForConnectionAttempt(configuredModel: String, reconnectAttempt: Int) -> String {
        if reconnectAttempt >= 2, configuredModel == "gpt-realtime-1.5" {
            return "gpt-realtime-mini"
        }
        return configuredModel
    }
}
