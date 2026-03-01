import Foundation

// MARK: - RealtimeClientProtocol

/// Protocol abstracting the Realtime API client so that VoiceSessionCoordinator
/// and ToolOrchestrator can be tested without a live WebSocket connection.
@MainActor
protocol RealtimeClientProtocol: AnyObject {
    // Connection
    var connectionState: RealtimeConnectionState { get }
    func connect(apiKey: String)
    func disconnect()

    // Delegate
    var delegate: RealtimeClientDelegate? { get set }

    // Session configuration
    var model: String { get set }
    var voice: String { get set }
    var instructions: String { get set }
    var tools: [[String: Any]] { get set }

    // Audio
    func sendAudio(base64Chunk: String)

    // Text input
    func sendMessage(text: String)

    // Tool results
    func sendToolResult(callId: String, output: String)

    // Response management
    func requestModelResponse()
    func cancelResponse()
    func truncateResponse(itemId: String, contentIndex: Int, audioEnd: Int, sendCancel: Bool)
}

// MARK: - RealtimeClient Conformance

extension RealtimeClient: RealtimeClientProtocol {}
