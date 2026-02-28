import XCTest
@testable import RubberDuck

final class RealtimeMessageParserTests: XCTestCase {
    let parser = RealtimeMessageParser()

    // MARK: - Helpers

    private func jsonData(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - Session Events

    func testParsesSessionCreated() throws {
        let data = jsonData([
            "type": "session.created",
            "session": ["id": "sess_abc", "model": "gpt-realtime-1.5"]
        ])
        let event = try parser.parse(data)
        guard case .sessionCreated(let session) = event else {
            return XCTFail("Expected sessionCreated, got \(event)")
        }
        XCTAssertEqual(session["id"] as? String, "sess_abc")
    }

    func testParsesSessionUpdated() throws {
        let data = jsonData([
            "type": "session.updated",
            "session": ["voice": "marin"]
        ])
        let event = try parser.parse(data)
        guard case .sessionUpdated(let session) = event else {
            return XCTFail("Expected sessionUpdated, got \(event)")
        }
        XCTAssertEqual(session["voice"] as? String, "marin")
    }

    // MARK: - Error Events

    func testParsesError() throws {
        let data = jsonData([
            "type": "error",
            "error": [
                "type": "server_error",
                "code": "internal_server_error",
                "message": "Something went wrong"
            ]
        ])
        let event = try parser.parse(data)
        guard case .error(let type, _) = event else {
            return XCTFail("Expected error, got \(event)")
        }
        XCTAssertEqual(type, "error")
    }

    func testParsesCustomErrorSuffix() throws {
        let data = jsonData([
            "type": "custom_error",
            "message": "Custom error"
        ])
        let event = try parser.parse(data)
        guard case .error(let type, _) = event else {
            return XCTFail("Expected error, got \(event)")
        }
        XCTAssertEqual(type, "custom_error")
    }

    // MARK: - Speech Events

    func testParsesSpeechStarted() throws {
        let data = jsonData(["type": "input_audio_buffer.speech_started"])
        let event = try parser.parse(data)
        guard case .inputAudioBufferSpeechStarted = event else {
            return XCTFail("Expected speechStarted, got \(event)")
        }
    }

    func testParsesSpeechStopped() throws {
        let data = jsonData(["type": "input_audio_buffer.speech_stopped"])
        let event = try parser.parse(data)
        guard case .inputAudioBufferSpeechStopped = event else {
            return XCTFail("Expected speechStopped, got \(event)")
        }
    }

    // MARK: - Audio Output Events

    func testParsesAudioDelta() throws {
        let data = jsonData([
            "type": "response.output_audio.delta",
            "delta": "AQID",
            "item_id": "item_1",
            "content_index": 0
        ])
        let event = try parser.parse(data)
        guard case .responseOutputAudioDelta(let delta, let itemId, let contentIndex) = event else {
            return XCTFail("Expected audioOutputDelta, got \(event)")
        }
        XCTAssertEqual(delta, "AQID")
        XCTAssertEqual(itemId, "item_1")
        XCTAssertEqual(contentIndex, 0)
    }

    func testParsesAudioDone() throws {
        let data = jsonData([
            "type": "response.output_audio.done",
            "item_id": "item_2",
            "content_index": 0
        ])
        let event = try parser.parse(data)
        guard case .responseOutputAudioDone(let itemId, let contentIndex) = event else {
            return XCTFail("Expected audioOutputDone, got \(event)")
        }
        XCTAssertEqual(itemId, "item_2")
        XCTAssertEqual(contentIndex, 0)
    }

    // MARK: - Transcript Events

    func testParsesAudioTranscriptDelta() throws {
        let data = jsonData([
            "type": "response.output_audio_transcript.delta",
            "delta": "Hello"
        ])
        let event = try parser.parse(data)
        guard case .responseOutputAudioTranscriptDelta(let delta) = event else {
            return XCTFail("Expected transcriptDelta, got \(event)")
        }
        XCTAssertEqual(delta, "Hello")
    }

    func testParsesAudioTranscriptDone() throws {
        let data = jsonData([
            "type": "response.output_audio_transcript.done",
            "transcript": "Hello world"
        ])
        let event = try parser.parse(data)
        guard case .responseOutputAudioTranscriptDone(let transcript) = event else {
            return XCTFail("Expected transcriptDone, got \(event)")
        }
        XCTAssertEqual(transcript, "Hello world")
    }

    // MARK: - Text Events

    func testParsesTextDelta() throws {
        let data = jsonData([
            "type": "response.output_text.delta",
            "delta": "Hi"
        ])
        let event = try parser.parse(data)
        guard case .responseOutputTextDelta(let delta) = event else {
            return XCTFail("Expected textDelta, got \(event)")
        }
        XCTAssertEqual(delta, "Hi")
    }

    func testParsesTextDone() throws {
        let data = jsonData([
            "type": "response.output_text.done",
            "text": "Hi there"
        ])
        let event = try parser.parse(data)
        guard case .responseOutputTextDone(let text) = event else {
            return XCTFail("Expected textDone, got \(event)")
        }
        XCTAssertEqual(text, "Hi there")
    }

    // MARK: - Response Done

    func testParsesResponseDone() throws {
        let data = jsonData([
            "type": "response.done",
            "response": [
                "id": "resp_1",
                "status": "completed",
                "output": []
            ]
        ])
        let event = try parser.parse(data)
        guard case .responseDone(let typed, _) = event else {
            return XCTFail("Expected responseDone, got \(event)")
        }
        XCTAssertNotNil(typed)
        XCTAssertEqual(typed?.response.status, "completed")
    }

    func testParsesResponseCancelled() throws {
        let data = jsonData(["type": "response.cancelled"])
        let event = try parser.parse(data)
        guard case .responseCancelled = event else {
            return XCTFail("Expected responseCancelled, got \(event)")
        }
    }

    func testParsesResponseCanceled_americanSpelling() throws {
        let data = jsonData(["type": "response.canceled"])
        let event = try parser.parse(data)
        guard case .responseCancelled = event else {
            return XCTFail("Expected responseCancelled, got \(event)")
        }
    }

    // MARK: - Function Call Events

    func testParsesFunctionCallArgumentsDelta() throws {
        let data = jsonData([
            "type": "response.function_call_arguments.delta",
            "delta": "{\"path\":",
            "call_id": "call_1"
        ])
        let event = try parser.parse(data)
        guard case .functionCallArgumentsDelta(let delta, let callId) = event else {
            return XCTFail("Expected functionCallArgumentsDelta, got \(event)")
        }
        XCTAssertEqual(delta, "{\"path\":")
        XCTAssertEqual(callId, "call_1")
    }

    func testParsesFunctionCallArgumentsDone() throws {
        let data = jsonData([
            "type": "response.function_call_arguments.done",
            "arguments": "{\"path\":\"/tmp\"}",
            "call_id": "call_1"
        ])
        let event = try parser.parse(data)
        guard case .functionCallArgumentsDone(let arguments, let callId) = event else {
            return XCTFail("Expected functionCallArgumentsDone, got \(event)")
        }
        XCTAssertEqual(arguments, "{\"path\":\"/tmp\"}")
        XCTAssertEqual(callId, "call_1")
    }

    // MARK: - Input Audio Transcription

    func testParsesInputAudioTranscriptionCompleted() throws {
        let data = jsonData([
            "type": "conversation.item.input_audio_transcription.completed",
            "transcript": "Hello world",
            "item_id": "item_3"
        ])
        let event = try parser.parse(data)
        guard case .inputAudioTranscriptionCompleted(let transcript, let itemId) = event else {
            return XCTFail("Expected inputAudioTranscriptionCompleted, got \(event)")
        }
        XCTAssertEqual(transcript, "Hello world")
        XCTAssertEqual(itemId, "item_3")
    }

    func testParsesInputAudioTranscriptionFailed() throws {
        let data = jsonData([
            "type": "conversation.item.input_audio_transcription.failed"
        ])
        let event = try parser.parse(data)
        guard case .inputAudioTranscriptionFailed = event else {
            return XCTFail("Expected inputAudioTranscriptionFailed, got \(event)")
        }
    }

    // MARK: - Conversation Item Events

    func testParsesConversationItemCreated() throws {
        let data = jsonData([
            "type": "conversation.item.created",
            "item": ["id": "item_4", "type": "message"]
        ])
        let event = try parser.parse(data)
        guard case .conversationItemCreated(let item) = event else {
            return XCTFail("Expected conversationItemCreated, got \(event)")
        }
        XCTAssertEqual(item["id"] as? String, "item_4")
    }

    func testParsesConversationItemAdded() throws {
        let data = jsonData([
            "type": "conversation.item.added",
            "item": ["id": "item_5", "type": "message"]
        ])
        let event = try parser.parse(data)
        guard case .conversationItemCreated(let item) = event else {
            return XCTFail("Expected conversationItemCreated, got \(event)")
        }
        XCTAssertEqual(item["id"] as? String, "item_5")
    }

    // MARK: - Rate Limits

    func testParsesRateLimitsUpdated() throws {
        let data = jsonData([
            "type": "rate_limits.updated",
            "rate_limits": [
                ["name": "requests", "limit": 100, "remaining": 99]
            ]
        ])
        let event = try parser.parse(data)
        guard case .rateLimitsUpdated(let rateLimits) = event else {
            return XCTFail("Expected rateLimitsUpdated, got \(event)")
        }
        XCTAssertEqual(rateLimits.count, 1)
        XCTAssertEqual(rateLimits[0]["name"] as? String, "requests")
    }

    // MARK: - Output Item Events

    func testParsesOutputItemCreated() throws {
        let data = jsonData([
            "type": "response.output_item.created",
            "item": ["id": "item_6"],
            "content_index": 0
        ])
        let event = try parser.parse(data)
        guard case .outputItemUpdated(let itemId, let contentIndex) = event else {
            return XCTFail("Expected outputItemUpdated, got \(event)")
        }
        XCTAssertEqual(itemId, "item_6")
        XCTAssertEqual(contentIndex, 0)
    }

    // MARK: - Unhandled Events

    func testParsesUnhandledEvent() throws {
        let data = jsonData(["type": "some.unknown.event"])
        let event = try parser.parse(data)
        guard case .unhandled(let type) = event else {
            return XCTFail("Expected unhandled, got \(event)")
        }
        XCTAssertEqual(type, "some.unknown.event")
    }

    // MARK: - Invalid Input

    func testThrowsOnInvalidJSON() {
        let data = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try parser.parse(data))
    }

    func testThrowsOnMissingType() {
        let data = jsonData(["foo": "bar"])
        XCTAssertThrowsError(try parser.parse(data))
    }

    // MARK: - JSON Helpers

    func testParseEventItemID_fromTopLevel() {
        let json: [String: Any] = ["item_id": "item_10"]
        XCTAssertEqual(parser.parseEventItemID(json), "item_10")
    }

    func testParseEventItemID_fromNestedItem() {
        let json: [String: Any] = ["item": ["id": "item_11"]]
        XCTAssertEqual(parser.parseEventItemID(json), "item_11")
    }

    func testParseEventContentIndex_fromTopLevel() {
        let json: [String: Any] = ["content_index": 2]
        XCTAssertEqual(parser.parseEventContentIndex(json), 2)
    }

    func testParseEventContentIndex_fromPart() {
        let json: [String: Any] = ["part": ["index": 3]]
        XCTAssertEqual(parser.parseEventContentIndex(json), 3)
    }

    func testParseInputAudioTranscriptionText_directTranscript() {
        let json: [String: Any] = ["transcript": "Hello"]
        XCTAssertEqual(parser.parseInputAudioTranscriptionText(json), "Hello")
    }

    func testParseInputAudioTranscriptionText_nestedInContent() {
        let json: [String: Any] = [
            "item": [
                "content": [
                    ["transcript": "  Hello  "]
                ]
            ]
        ]
        XCTAssertEqual(parser.parseInputAudioTranscriptionText(json), "Hello")
    }

    func testParseInputAudioTranscriptionText_nestedInInputAudio() {
        let json: [String: Any] = [
            "item": [
                "content": [
                    ["input_audio": ["transcript": "World"]]
                ]
            ]
        ]
        XCTAssertEqual(parser.parseInputAudioTranscriptionText(json), "World")
    }

    func testParseInputAudioTranscriptionText_emptyReturnsNil() {
        let json: [String: Any] = ["transcript": "   "]
        XCTAssertNil(parser.parseInputAudioTranscriptionText(json))
    }
}
