import Foundation
@testable import RubberDuck

// MARK: - MockRealtimeClient

@MainActor
final class MockRealtimeClient: RealtimeClientProtocol {

    // MARK: - Connection

    var connectionState: RealtimeConnectionState = .disconnected
    weak var delegate: RealtimeClientDelegate?

    var connectCallCount = 0
    var disconnectCallCount = 0

    func connect(apiKey: String) {
        connectCallCount += 1
    }

    func disconnect() {
        disconnectCallCount += 1
    }

    // MARK: - Session Configuration

    var model: String = "gpt-realtime-1.5"
    var voice: String = "marin"
    var instructions: String = ""
    var tools: [[String: Any]] = []

    // MARK: - Audio

    var sentAudioChunks: [String] = []

    func sendAudio(base64Chunk: String) {
        sentAudioChunks.append(base64Chunk)
    }

    // MARK: - Text Input

    var sentMessages: [String] = []

    func sendMessage(text: String) {
        sentMessages.append(text)
    }

    // MARK: - Tool Results

    var sentToolResults: [(callId: String, output: String)] = []

    func sendToolResult(callId: String, output: String) {
        sentToolResults.append((callId: callId, output: output))
    }

    // MARK: - Response Management

    struct TruncateCall {
        let itemId: String
        let contentIndex: Int
        let audioEnd: Int
        let sendCancel: Bool
    }

    var truncateCalls: [TruncateCall] = []
    var requestModelResponseCallCount = 0

    func requestModelResponse() {
        requestModelResponseCallCount += 1
    }

    func truncateResponse(itemId: String, contentIndex: Int, audioEnd: Int, sendCancel: Bool) {
        truncateCalls.append(
            TruncateCall(
                itemId: itemId,
                contentIndex: contentIndex,
                audioEnd: audioEnd,
                sendCancel: sendCancel
            )
        )
    }
}
