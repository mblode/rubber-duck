import Foundation

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
    case conversationItemDone(item: [String: Any])
    case conversationItemTruncated
    case outputItemFunctionCall(call: RealtimeFunctionCallItem)
    case outputItemUpdated(itemId: String?, contentIndex: Int?)
    case rateLimitsUpdated(rateLimits: [[String: Any]])
    case unhandled(type: String)
}

struct RealtimeMessageParser {
    enum ParseError: Error {
        case invalidJSON
    }

    func parse(_ data: Data) throws -> RealtimeEvent {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            throw ParseError.invalidJSON
        }

        return dispatch(type: type, json: json, rawData: data)
    }

    private func dispatch(
        type: String,
        json: [String: Any],
        rawData: Data
    ) -> RealtimeEvent {
        switch type {
        case "session.created":
            return .sessionCreated(session: json["session"] as? [String: Any] ?? [:])
        case "session.updated":
            return .sessionUpdated(session: json["session"] as? [String: Any] ?? [:])
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
            return .responseOutputAudioDelta(
                delta: json["delta"] as? String ?? "",
                itemId: parseEventItemID(json),
                contentIndex: parseEventContentIndex(json)
            )
        case "response.output_audio.done":
            return .responseOutputAudioDone(
                itemId: json["item_id"] as? String ?? "",
                contentIndex: parseEventContentIndex(json)
            )
        case "response.output_audio_transcript.delta":
            return .responseOutputAudioTranscriptDelta(delta: json["delta"] as? String ?? "")
        case "response.output_audio_transcript.done":
            return .responseOutputAudioTranscriptDone(transcript: json["transcript"] as? String ?? "")
        case "response.output_text.delta":
            return .responseOutputTextDelta(delta: json["delta"] as? String ?? "")
        case "response.output_text.done":
            return .responseOutputTextDone(text: json["text"] as? String ?? "")
        case "response.done":
            return .responseDone(typed: try? JSONDecoder().decode(RealtimeResponseDone.self, from: rawData), rawJson: json)
        case "response.cancelled", "response.canceled":
            return .responseCancelled
        case "response.function_call_arguments.delta":
            return .functionCallArgumentsDelta(
                delta: json["delta"] as? String ?? "",
                callId: json["call_id"] as? String ?? ""
            )
        case "response.function_call_arguments.done":
            return .functionCallArgumentsDone(
                arguments: json["arguments"] as? String ?? "",
                callId: json["call_id"] as? String ?? ""
            )
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = parseInputAudioTranscriptionText(json) {
                return .inputAudioTranscriptionCompleted(
                    transcript: transcript,
                    itemId: parseEventItemID(json)
                )
            }
            return .inputAudioTranscriptionFailed
        case "conversation.item.input_audio_transcription.failed":
            return .inputAudioTranscriptionFailed
        case "conversation.item.created", "conversation.item.added":
            return .conversationItemCreated(item: json["item"] as? [String: Any] ?? [:])
        case "conversation.item.done":
            return .conversationItemDone(item: json["item"] as? [String: Any] ?? [:])
        case "conversation.item.truncated":
            return .conversationItemTruncated
        case "response.output_item.created",
            "response.output_item.added",
            "response.output_item.done",
            "response.content_part.added",
            "response.content_part.done":
            if type == "response.output_item.done",
               let item = json["item"] as? [String: Any],
               let functionCall = parseFunctionCallItem(item) {
                return .outputItemFunctionCall(call: functionCall)
            }

            return .outputItemUpdated(
                itemId: parseEventItemID(json),
                contentIndex: parseEventContentIndex(json)
            )
        case "rate_limits.updated":
            return .rateLimitsUpdated(rateLimits: json["rate_limits"] as? [[String: Any]] ?? [])
        default:
            if type.hasSuffix("_error") {
                return .error(type: type, json: json)
            }
            return .unhandled(type: type)
        }
    }

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
        if let intValue = parseOptionalInt(json["content_index"]) {
            return intValue
        }

        if let part = json["part"] as? [String: Any] {
            return parseOptionalInt(part["index"])
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

    private func parseFunctionCallItem(
        _ item: [String: Any]
    ) -> RealtimeFunctionCallItem? {
        guard let type = item["type"] as? String,
              type == "function_call",
              let callId = item["call_id"] as? String,
              let name = item["name"] as? String,
              let arguments = item["arguments"] as? String else {
            return nil
        }

        return RealtimeFunctionCallItem(
            callId: callId,
            name: name,
            arguments: arguments
        )
    }
}
