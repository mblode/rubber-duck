import Foundation

// MARK: - Parsed Realtime Events

enum RealtimeEvent {
    case sessionCreated(session: [String: Any])
    case sessionUpdated(session: [String: Any])
    case error(type: String, json: [String: Any])
    case inputAudioBufferSpeechStarted
    case inputAudioBufferSpeechStopped
    case inputAudioBufferCommitted
    case responseCreated(json: [String: Any])
    case responseOutputAudioDelta(delta: String, itemId: String?, contentIndex: Int?)
    case responseOutputAudioDone(itemId: String, contentIndex: Int?)
    case responseOutputAudioTranscriptDelta(delta: String)
    case responseOutputAudioTranscriptDone(transcript: String)
    case responseOutputTextDelta(delta: String)
    case responseOutputTextDone(text: String)
    case responseDone(typed: RealtimeResponseDone?, rawJson: [String: Any])
    case responseCancelled
    case functionCallArgumentsDelta(delta: String, callId: String)
    case functionCallArgumentsDone(arguments: String, callId: String)
    case inputAudioTranscriptionCompleted(transcript: String, itemId: String?)
    case inputAudioTranscriptionFailed
    case conversationItemCreated(item: [String: Any])
    case conversationItemDone
    case conversationItemTruncated
    case outputItemUpdated(itemId: String?, contentIndex: Int?)
    case rateLimitsUpdated(rateLimits: [[String: Any]])
    case unhandled(type: String)
}

// MARK: - RealtimeMessageParser

struct RealtimeMessageParser {

    enum ParseError: Error {
        case invalidJSON
        case missingType
    }

    func parse(_ data: Data) throws -> RealtimeEvent {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            throw ParseError.invalidJSON
        }
        return dispatch(type: type, json: json, rawData: data)
    }

    // MARK: - Private

    private func dispatch(type: String, json: [String: Any], rawData: Data) -> RealtimeEvent {
        switch type {
        case "session.created":
            let session = json["session"] as? [String: Any] ?? [:]
            return .sessionCreated(session: session)

        case "session.updated":
            let session = json["session"] as? [String: Any] ?? [:]
            return .sessionUpdated(session: session)

        case "error":
            return .error(type: type, json: json)

        case "input_audio_buffer.speech_started":
            return .inputAudioBufferSpeechStarted

        case "input_audio_buffer.speech_stopped":
            return .inputAudioBufferSpeechStopped

        case "input_audio_buffer.committed":
            return .inputAudioBufferCommitted

        case "response.created":
            return .responseCreated(json: json)

        case "response.output_audio.delta":
            let itemId = parseEventItemID(json)
            let contentIndex = parseEventContentIndex(json)
            let delta = json["delta"] as? String ?? ""
            return .responseOutputAudioDelta(delta: delta, itemId: itemId, contentIndex: contentIndex)

        case "response.output_audio.done":
            let itemId = json["item_id"] as? String ?? ""
            let contentIndex = parseEventContentIndex(json)
            return .responseOutputAudioDone(itemId: itemId, contentIndex: contentIndex)

        case "response.output_audio_transcript.delta":
            let delta = json["delta"] as? String ?? ""
            return .responseOutputAudioTranscriptDelta(delta: delta)

        case "response.output_audio_transcript.done":
            let transcript = json["transcript"] as? String ?? ""
            return .responseOutputAudioTranscriptDone(transcript: transcript)

        case "response.output_text.delta":
            let delta = json["delta"] as? String ?? ""
            return .responseOutputTextDelta(delta: delta)

        case "response.output_text.done":
            let text = json["text"] as? String ?? ""
            return .responseOutputTextDone(text: text)

        case "response.done":
            let typed = try? JSONDecoder().decode(RealtimeResponseDone.self, from: rawData)
            return .responseDone(typed: typed, rawJson: json)

        case "response.cancelled", "response.canceled":
            return .responseCancelled

        case "response.function_call_arguments.delta":
            let delta = json["delta"] as? String ?? ""
            let callId = json["call_id"] as? String ?? ""
            return .functionCallArgumentsDelta(delta: delta, callId: callId)

        case "response.function_call_arguments.done":
            let arguments = json["arguments"] as? String ?? ""
            let callId = json["call_id"] as? String ?? ""
            return .functionCallArgumentsDone(arguments: arguments, callId: callId)

        case "conversation.item.input_audio_transcription.completed":
            let itemId = parseEventItemID(json)
            let transcript = parseInputAudioTranscriptionText(json)
            if let transcript {
                return .inputAudioTranscriptionCompleted(transcript: transcript, itemId: itemId)
            }
            return .inputAudioTranscriptionFailed

        case "conversation.item.input_audio_transcription.failed":
            return .inputAudioTranscriptionFailed

        case "conversation.item.created", "conversation.item.added":
            let item = json["item"] as? [String: Any] ?? [:]
            return .conversationItemCreated(item: item)

        case "conversation.item.done":
            return .conversationItemDone

        case "conversation.item.truncated":
            return .conversationItemTruncated

        case "response.output_item.created", "response.output_item.added", "response.output_item.done",
             "response.content_part.added", "response.content_part.done":
            let itemId = parseEventItemID(json)
            let contentIndex = parseEventContentIndex(json)
            return .outputItemUpdated(itemId: itemId, contentIndex: contentIndex)

        case "rate_limits.updated":
            let rateLimits = json["rate_limits"] as? [[String: Any]] ?? []
            return .rateLimitsUpdated(rateLimits: rateLimits)

        default:
            if type.hasSuffix("_error") {
                return .error(type: type, json: json)
            }
            return .unhandled(type: type)
        }
    }

    // MARK: - JSON Helpers

    func parseEventItemID(_ json: [String: Any]) -> String? {
        if let itemId = json["item_id"] as? String, !itemId.isEmpty {
            return itemId
        }
        if let item = json["item"] as? [String: Any],
           let itemId = item["id"] as? String,
           !itemId.isEmpty {
            return itemId
        }
        return nil
    }

    func parseEventContentIndex(_ json: [String: Any]) -> Int? {
        if let index = parseOptionalInt(json["content_index"]) {
            return index
        }
        if let part = json["part"] as? [String: Any],
           let index = parseOptionalInt(part["index"]) {
            return index
        }
        return nil
    }

    func parseInputAudioTranscriptionText(_ json: [String: Any]) -> String? {
        if let transcript = json["transcript"] as? String {
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let item = json["item"] as? [String: Any],
           let content = item["content"] as? [[String: Any]] {
            for part in content {
                if let transcript = part["transcript"] as? String {
                    let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }

                if let inputAudio = part["input_audio"] as? [String: Any],
                   let transcript = inputAudio["transcript"] as? String {
                    let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }

        return nil
    }

    private func parseOptionalInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let text = value as? String {
            return Int(text)
        }
        return nil
    }
}
