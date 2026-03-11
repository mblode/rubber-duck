import Foundation

enum ConversationEventType: String, Codable {
    case userAudio = "user_audio"
    case userText = "user_text"
    case assistantAudio = "assistant_audio"
    case toolCall = "tool_call"
    case assistantText = "assistant_text"
    case assistantTextDelta = "assistant_text_delta"
    case assistantTextEnd = "assistant_text_end"
    case responseComplete = "response_complete"
}

struct ConversationHistoryEvent: Codable {
    let timestamp: Date
    let sessionID: String
    let type: ConversationEventType
    let text: String?
    let metadata: [String: String]?
}

enum ConversationHistoryError: Error {
    case invalidEventLimit
}

final class ConversationHistory {
    private let fileURL: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "co.blode.rubber-duck.conversation-history")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL, fileManager: FileManager = .default) throws {
        self.fileURL = fileURL
        self.fileManager = fileManager

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try prepareFile()
    }

    func append(event: ConversationHistoryEvent) throws {
        try queue.sync {
            let data = try encoder.encode(event)
            guard let handle = try? FileHandle(forWritingTo: fileURL) else {
                try prepareFile()
                throw NSError(domain: "ConversationHistory", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Unable to open conversation history for writing"
                ])
            }
            defer {
                try? handle.close()
            }

            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
        }
    }

    func readRecent(limit: Int) throws -> [ConversationHistoryEvent] {
        guard limit > 0 else { return [] }
        return try queue.sync {
            guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }

            let fileSize = try handle.seekToEnd()
            guard fileSize > 0 else { return [] }

            let chunkSize: UInt64 = 65536
            var collectedText = ""
            var offset = fileSize

            // Read backward in chunks until we have enough lines
            while offset > 0 {
                let readSize = min(chunkSize, offset)
                offset -= readSize
                try handle.seek(toOffset: offset)
                let chunk = handle.readData(ofLength: Int(readSize))
                guard let text = String(data: chunk, encoding: .utf8) else { break }
                collectedText = text + collectedText

                // Check if we have enough lines (limit + 1 to account for partial first line)
                let lineCount = collectedText.components(separatedBy: "\n").filter { !$0.isEmpty }.count
                if lineCount > limit { break }
            }

            let lines = collectedText.components(separatedBy: "\n").filter { !$0.isEmpty }
            let recentLines = lines.suffix(limit)

            var events: [ConversationHistoryEvent] = []
            for line in recentLines {
                guard let data = line.data(using: .utf8) else {
                    logDebug("ConversationHistory: Skipping non-UTF8 line")
                    continue
                }
                do {
                    let event = try decoder.decode(ConversationHistoryEvent.self, from: data)
                    events.append(event)
                } catch {
                    logDebug("ConversationHistory: Skipping malformed event: \(error.localizedDescription)")
                }
            }
            return events
        }
    }

    private func prepareFile() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }
    }
}
