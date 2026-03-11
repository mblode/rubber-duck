import Foundation

@MainActor
public protocol RealtimeClientProtocol: AnyObject {
    var connectionState: RealtimeConnectionState { get }
    var delegate: RealtimeClientDelegate? { get set }
    var model: String { get set }
    var voice: String { get set }
    var instructions: String { get set }
    var tools: [[String: Any]] { get set }
    var interruptResponseOnBargeIn: Bool { get set }
    var turnDetectionMode: RealtimeTurnDetectionMode { get set }
    var pushToTalkMode: Bool { get set }

    func connect(apiKey: String)
    func disconnect()
    func sendAudio(base64Chunk: String)
    func commitAudioBuffer()
    func sendMessage(text: String)
    func sendToolResult(callId: String, output: String)
    func requestModelResponse()
    func cancelResponse()
    func truncateResponse(itemId: String, contentIndex: Int, audioEnd: Int, sendCancel: Bool)
    func updateSession(config: [String: Any])
}
