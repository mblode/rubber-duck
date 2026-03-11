import Foundation

public enum ConversationEventType: String, Codable, Sendable {
    case userAudio = "user_audio"
    case userText = "user_text"
    case assistantAudio = "assistant_audio"
    case toolCall = "tool_call"
    case assistantText = "assistant_text"
    case assistantTextDelta = "assistant_text_delta"
    case assistantTextEnd = "assistant_text_end"
    case responseComplete = "response_complete"
}

public struct ConversationHistoryEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let sessionID: String
    public let type: ConversationEventType
    public let text: String?
    public let metadata: [String: String]?

    public init(
        timestamp: Date,
        sessionID: String,
        type: ConversationEventType,
        text: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.type = type
        self.text = text
        self.metadata = metadata
    }
}

public final class ConversationHistoryLog {
    private let fileURL: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "co.blode.rubber-duck.remote-history")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL, fileManager: FileManager = .default) throws {
        self.fileURL = fileURL
        self.fileManager = fileManager

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try prepareFile()
    }

    public func append(event: ConversationHistoryEvent) throws {
        try queue.sync {
            let data = try encoder.encode(event)
            guard let handle = try? FileHandle(forWritingTo: fileURL) else {
                try prepareFile()
                throw NSError(
                    domain: "ConversationHistoryLog",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to open history log for writing"]
                )
            }

            defer {
                try? handle.close()
            }

            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
        }
    }

    public func readAll() throws -> [ConversationHistoryEvent] {
        try queue.sync {
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return []
            }

            let data = try Data(contentsOf: fileURL)
            if data.isEmpty {
                return []
            }

            return try decodeEvents(from: data)
        }
    }

    public func readRecent(limit: Int) throws -> [ConversationHistoryEvent] {
        guard limit > 0 else {
            return []
        }

        return try queue.sync {
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return []
            }

            let handle = try FileHandle(forReadingFrom: fileURL)
            defer {
                try? handle.close()
            }

            let fileSize = try handle.seekToEnd()
            guard fileSize > 0 else {
                return []
            }

            let chunkSize: UInt64 = 65_536
            var collectedText = ""
            var offset = fileSize

            while offset > 0 {
                let readSize = min(chunkSize, offset)
                offset -= readSize
                try handle.seek(toOffset: offset)
                let chunk = handle.readData(ofLength: Int(readSize))
                guard let text = String(data: chunk, encoding: .utf8) else {
                    break
                }
                collectedText = text + collectedText

                let lineCount = collectedText
                    .components(separatedBy: "\n")
                    .filter { !$0.isEmpty }
                    .count
                if lineCount > limit {
                    break
                }
            }

            let lines = collectedText
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .suffix(limit)

            var events: [ConversationHistoryEvent] = []
            for line in lines {
                guard let data = line.data(using: .utf8) else {
                    continue
                }
                events.append(try decoder.decode(ConversationHistoryEvent.self, from: data))
            }
            return events
        }
    }

    private func prepareFile() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: fileURL.path) {
            _ = fileManager.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    private func decodeEvents(from data: Data) throws -> [ConversationHistoryEvent] {
        let lines = String(decoding: data, as: UTF8.self)
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var events: [ConversationHistoryEvent] = []
        for line in lines {
            guard let lineData = line.data(using: .utf8) else {
                continue
            }
            events.append(try decoder.decode(ConversationHistoryEvent.self, from: lineData))
        }
        return events
    }
}
