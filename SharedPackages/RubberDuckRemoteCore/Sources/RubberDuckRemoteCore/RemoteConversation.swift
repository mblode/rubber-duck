import Foundation

public enum RemoteConversationRole: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case tool
    case status
}

public struct RemoteConversationEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let role: RemoteConversationRole
    public let text: String
    public let timestamp: Date
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        role: RemoteConversationRole,
        text: String,
        timestamp: Date,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

public enum ConversationTranscriptBuilder {
    public static func build(from events: [ConversationHistoryEvent]) -> [RemoteConversationEntry] {
        let sortedEvents = events.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.type.rawValue < rhs.type.rawValue
            }
            return lhs.timestamp < rhs.timestamp
        }

        var entries: [RemoteConversationEntry] = []
        var pendingAssistantText = ""
        var pendingAssistantTimestamp: Date?
        var pendingAssistantMetadata: [String: String] = [:]

        func flushPendingAssistant() {
            let normalized = pendingAssistantText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                pendingAssistantText = ""
                pendingAssistantTimestamp = nil
                pendingAssistantMetadata = [:]
                return
            }

            entries.append(
                RemoteConversationEntry(
                    role: .assistant,
                    text: normalized,
                    timestamp: pendingAssistantTimestamp ?? .now,
                    metadata: pendingAssistantMetadata
                )
            )

            pendingAssistantText = ""
            pendingAssistantTimestamp = nil
            pendingAssistantMetadata = [:]
        }

        for event in sortedEvents {
            switch event.type {
            case .assistantTextDelta:
                pendingAssistantTimestamp = pendingAssistantTimestamp ?? event.timestamp
                pendingAssistantMetadata.merge(event.metadata ?? [:], uniquingKeysWith: { _, new in new })
                pendingAssistantText += event.text ?? ""

            case .assistantText, .assistantAudio:
                flushPendingAssistant()
                if let text = normalizedText(for: event) {
                    entries.append(
                        RemoteConversationEntry(
                            role: .assistant,
                            text: text,
                            timestamp: event.timestamp,
                            metadata: event.metadata ?? [:]
                        )
                    )
                }

            case .assistantTextEnd, .responseComplete:
                flushPendingAssistant()
                if let text = normalizedText(for: event) {
                    entries.append(
                        RemoteConversationEntry(
                            role: .status,
                            text: text,
                            timestamp: event.timestamp,
                            metadata: event.metadata ?? [:]
                        )
                    )
                }

            case .userText, .userAudio:
                flushPendingAssistant()
                if let text = normalizedText(for: event) {
                    entries.append(
                        RemoteConversationEntry(
                            role: .user,
                            text: text,
                            timestamp: event.timestamp,
                            metadata: event.metadata ?? [:]
                        )
                    )
                }

            case .toolCall:
                flushPendingAssistant()
                if let text = normalizedText(for: event) ?? toolSummary(for: event.metadata) {
                    entries.append(
                        RemoteConversationEntry(
                            role: .tool,
                            text: text,
                            timestamp: event.timestamp,
                            metadata: event.metadata ?? [:]
                        )
                    )
                }
            }
        }

        flushPendingAssistant()
        return entries
    }

    private static func normalizedText(for event: ConversationHistoryEvent) -> String? {
        guard let text = event.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private static func toolSummary(for metadata: [String: String]?) -> String? {
        guard let metadata else {
            return nil
        }

        if let tool = metadata["tool"], let state = metadata["state"] {
            return "\(tool) \(state)"
        }

        if let tool = metadata["tool"] {
            return tool
        }

        return metadata.first.map { "\($0.key): \($0.value)" }
    }
}
