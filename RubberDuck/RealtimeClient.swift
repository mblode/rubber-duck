import Foundation

// MARK: - Connection State

enum RealtimeConnectionState: String {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

// MARK: - Typed Response Models

struct RealtimeResponseDone: Decodable {
    let response: ResponseBody

    struct ResponseBody: Decodable {
        let id: String?
        let status: String?
        let output: [OutputItem]?
    }

    struct OutputItem: Decodable {
        let type: String?
        let callId: String?
        let name: String?
        let arguments: String?

        enum CodingKeys: String, CodingKey {
            case type
            case callId = "call_id"
            case name
            case arguments
        }
    }

    var functionCalls: [(callId: String, name: String, arguments: String)] {
        guard let output = response.output else { return [] }
        return output.compactMap { item in
            guard item.type == "function_call",
                  let callId = item.callId,
                  let name = item.name,
                  let arguments = item.arguments else {
                return nil
            }
            return (callId: callId, name: name, arguments: arguments)
        }
    }
}

// MARK: - Delegate Protocol

@MainActor
protocol RealtimeClientDelegate: AnyObject {
    func realtimeClientDidConnect(_ client: RealtimeClient)
    func realtimeClientDidDisconnect(_ client: RealtimeClient, error: Error?)
    func realtimeClient(_ client: RealtimeClient, didChangeState state: RealtimeConnectionState)

    func realtimeClient(_ client: RealtimeClient, didReceiveSessionCreated session: [String: Any])
    func realtimeClient(_ client: RealtimeClient, didReceiveSessionUpdated session: [String: Any])
    func realtimeClient(_ client: RealtimeClient, didReceiveError error: [String: Any])

    func realtimeClientDidDetectSpeechStarted(_ client: RealtimeClient)
    func realtimeClientDidDetectSpeechStopped(_ client: RealtimeClient)

    func realtimeClient(_ client: RealtimeClient, didReceiveResponseCreated response: [String: Any])
    func realtimeClient(_ client: RealtimeClient, didReceiveAudioDelta base64Audio: String)
    func realtimeClient(_ client: RealtimeClient, didReceiveAudioDone itemId: String)
    func realtimeClient(_ client: RealtimeClient, didReceiveAudioTranscriptDelta text: String)
    func realtimeClient(_ client: RealtimeClient, didReceiveAudioTranscriptDone text: String)
    func realtimeClient(_ client: RealtimeClient, didReceiveTextDelta text: String)
    func realtimeClient(_ client: RealtimeClient, didReceiveTextDone text: String)
    @available(*, deprecated, message: "Use didReceiveTypedResponseDone instead")
    func realtimeClient(_ client: RealtimeClient, didReceiveResponseDone response: [String: Any])
    func realtimeClient(_ client: RealtimeClient, didReceiveTypedResponseDone response: RealtimeResponseDone)

    func realtimeClient(_ client: RealtimeClient, didReceiveFunctionCallArgumentsDelta delta: String, callId: String)
    func realtimeClient(_ client: RealtimeClient, didReceiveFunctionCallArgumentsDone arguments: String, callId: String)

    func realtimeClient(_ client: RealtimeClient, didReceiveConversationItemCreated item: [String: Any])
    func realtimeClient(_ client: RealtimeClient, didReceiveRateLimitsUpdated rateLimits: [[String: Any]])
}

// MARK: - Default Delegate Implementations

extension RealtimeClientDelegate {
    func realtimeClientDidConnect(_ client: RealtimeClient) {}
    func realtimeClientDidDisconnect(_ client: RealtimeClient, error: Error?) {}
    func realtimeClient(_ client: RealtimeClient, didChangeState state: RealtimeConnectionState) {}
    func realtimeClient(_ client: RealtimeClient, didReceiveSessionCreated session: [String: Any]) {}
    func realtimeClient(_ client: RealtimeClient, didReceiveSessionUpdated session: [String: Any]) {}
    func realtimeClient(_ client: RealtimeClient, didReceiveError error: [String: Any]) {}
    func realtimeClientDidDetectSpeechStarted(_ client: RealtimeClient) {}
    func realtimeClientDidDetectSpeechStopped(_ client: RealtimeClient) {}
    func realtimeClient(_ client: RealtimeClient, didReceiveResponseCreated response: [String: Any]) {}
    func realtimeClient(_ client: RealtimeClient, didReceiveAudioDelta base64Audio: String) {}
    func realtimeClient(_ client: RealtimeClient, didReceiveAudioDone itemId: String) {}
    func realtimeClient(_ client: RealtimeClient, didReceiveAudioTranscriptDelta text: String) {}
    func realtimeClient(_ client: RealtimeClient, didReceiveAudioTranscriptDone text: String) {}
    func realtimeClient(_ client: RealtimeClient, didReceiveTextDelta text: String) {}
    func realtimeClient(_ client: RealtimeClient, didReceiveTextDone text: String) {}
    func realtimeClient(_ client: RealtimeClient, didReceiveResponseDone response: [String: Any]) {}
    func realtimeClient(_ client: RealtimeClient, didReceiveTypedResponseDone response: RealtimeResponseDone) {}
    func realtimeClient(_ client: RealtimeClient, didReceiveFunctionCallArgumentsDelta delta: String, callId: String) {}
    func realtimeClient(_ client: RealtimeClient, didReceiveFunctionCallArgumentsDone arguments: String, callId: String) {}
    func realtimeClient(_ client: RealtimeClient, didReceiveConversationItemCreated item: [String: Any]) {}
    func realtimeClient(_ client: RealtimeClient, didReceiveRateLimitsUpdated rateLimits: [[String: Any]]) {}
}

// MARK: - RealtimeClient

@MainActor
class RealtimeClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {

    @Published var connectionState: RealtimeConnectionState = .disconnected

    weak var delegate: RealtimeClientDelegate?

    // Session configuration
    var model: String = "gpt-4o-mini-realtime-preview"
    var voice: String = "marin"
    var vadEagerness: String = "medium"
    var instructions: String = ""
    var tools: [[String: Any]] = []

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var apiKey: String?

    // Reconnection
    private let maxReconnectAttempts = 3
    private var reconnectAttempt = 0
    private var intentionalDisconnect = false

    // MARK: - Connection

    func connect(apiKey: String) {
        guard connectionState == .disconnected else {
            logInfo("RealtimeClient: Already connected or connecting")
            return
        }

        self.apiKey = apiKey
        intentionalDisconnect = false
        reconnectAttempt = 0
        setConnectionState(.connecting)

        establishConnection()
    }

    func disconnect() {
        intentionalDisconnect = true
        reconnectAttempt = 0
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        setConnectionState(.disconnected)
        delegate?.realtimeClientDidDisconnect(self, error: nil)
        logInfo("RealtimeClient: Disconnected")
    }

    // MARK: - Sending Data

    func sendAudio(base64Chunk: String) {
        let event: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64Chunk
        ]
        sendEvent(event)
    }

    func commitAudioBuffer() {
        let event: [String: Any] = [
            "type": "input_audio_buffer.commit"
        ]
        sendEvent(event)
    }

    func sendToolResult(callId: String, output: String) {
        let itemEvent: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": output
            ]
        ]
        sendEvent(itemEvent)

        let responseEvent: [String: Any] = [
            "type": "response.create"
        ]
        sendEvent(responseEvent)
    }

    func truncateResponse(itemId: String, contentIndex: Int, audioEnd: Int) {
        let cancelEvent: [String: Any] = [
            "type": "response.cancel"
        ]
        sendEvent(cancelEvent)

        let truncateEvent: [String: Any] = [
            "type": "conversation.item.truncate",
            "item_id": itemId,
            "content_index": contentIndex,
            "audio_end_ms": audioEnd
        ]
        sendEvent(truncateEvent)
    }

    func updateSession(config: [String: Any]) {
        var event: [String: Any] = [
            "type": "session.update"
        ]
        event["session"] = config
        sendEvent(event)
    }

    func sendMessage(text: String) {
        let itemEvent: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": text
                    ]
                ]
            ]
        ]
        sendEvent(itemEvent)

        let responseEvent: [String: Any] = [
            "type": "response.create"
        ]
        sendEvent(responseEvent)
    }

    // MARK: - Private: Connection

    private func establishConnection() {
        guard let apiKey = apiKey else {
            logError("RealtimeClient: No API key provided")
            setConnectionState(.disconnected)
            return
        }

        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? model
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(encodedModel)") else {
            logError("RealtimeClient: Invalid WebSocket URL")
            setConnectionState(.disconnected)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.urlSession = session

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        logInfo("RealtimeClient: Connecting to Realtime API (model: \(model))...")
    }

    private func setConnectionState(_ state: RealtimeConnectionState) {
        connectionState = state
        delegate?.realtimeClient(self, didChangeState: state)
        logDebug("RealtimeClient: State -> \(state.rawValue)")
    }

    private func sendSessionConfig() {
        var sessionConfig: [String: Any] = [
            "modalities": ["audio", "text"],
            "input_audio_format": "pcm16",
            "output_audio_format": "pcm16",
            "input_audio_transcription": [
                "model": "gpt-4o-mini-transcribe"
            ],
            "turn_detection": [
                "type": "semantic_vad",
                "eagerness": vadEagerness,
                "create_response": true,
                "interrupt_response": true
            ],
            "voice": voice,
            "tool_choice": "auto"
        ]

        if !instructions.isEmpty {
            sessionConfig["instructions"] = instructions
        }

        if !tools.isEmpty {
            sessionConfig["tools"] = tools
        }

        let event: [String: Any] = [
            "type": "session.update",
            "session": sessionConfig
        ]
        sendEvent(event)
        logInfo("RealtimeClient: Sent session configuration")
    }

    // MARK: - Private: Send/Receive

    private func sendEvent(_ event: [String: Any]) {
        guard let task = webSocketTask, connectionState == .connected else {
            logDebug("RealtimeClient: Cannot send event, not connected")
            return
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: event)
            let message = URLSessionWebSocketTask.Message.data(data)
            task.send(message) { error in
                if let error = error {
                    logError("RealtimeClient: Send error: \(error.localizedDescription)")
                }
            }
        } catch {
            logError("RealtimeClient: Failed to serialize event: \(error.localizedDescription)")
        }
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.handleMessage(data: data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        self.handleMessage(data: data)
                    }
                @unknown default:
                    logDebug("RealtimeClient: Unknown message type")
                }
                self.receiveMessages()

            case .failure(let error):
                logError("RealtimeClient: Receive error: \(error.localizedDescription)")
                Task { @MainActor in
                    self.handleDisconnection(error: error)
                }
            }
        }
    }

    private func handleMessage(data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            logDebug("RealtimeClient: Failed to parse server event")
            return
        }

        Task { @MainActor in
            self.dispatchEvent(type: type, json: json, rawData: data)
        }
    }

    private func dispatchEvent(type: String, json: [String: Any], rawData: Data) {
        switch type {
        case "session.created":
            if let session = json["session"] as? [String: Any] {
                delegate?.realtimeClient(self, didReceiveSessionCreated: session)
            }
            logInfo("RealtimeClient: Session created")

        case "session.updated":
            if let session = json["session"] as? [String: Any] {
                delegate?.realtimeClient(self, didReceiveSessionUpdated: session)
            }
            logDebug("RealtimeClient: Session updated")

        case "error":
            if let error = json["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Unknown error"
                logError("RealtimeClient: Server error: \(message)")
                delegate?.realtimeClient(self, didReceiveError: error)
            }

        case "input_audio_buffer.speech_started":
            delegate?.realtimeClientDidDetectSpeechStarted(self)
            logDebug("RealtimeClient: Speech started")

        case "input_audio_buffer.speech_stopped":
            delegate?.realtimeClientDidDetectSpeechStopped(self)
            logDebug("RealtimeClient: Speech stopped")

        case "response.created":
            delegate?.realtimeClient(self, didReceiveResponseCreated: json)
            logDebug("RealtimeClient: Response created")

        case "response.output_audio.delta":
            if let delta = json["delta"] as? String {
                delegate?.realtimeClient(self, didReceiveAudioDelta: delta)
            }

        case "response.output_audio.done":
            let itemId = json["item_id"] as? String ?? ""
            delegate?.realtimeClient(self, didReceiveAudioDone: itemId)
            logDebug("RealtimeClient: Audio output done")

        case "response.output_audio_transcript.delta":
            if let delta = json["delta"] as? String {
                delegate?.realtimeClient(self, didReceiveAudioTranscriptDelta: delta)
            }

        case "response.output_audio_transcript.done":
            if let transcript = json["transcript"] as? String {
                delegate?.realtimeClient(self, didReceiveAudioTranscriptDone: transcript)
                logDebug("RealtimeClient: Audio transcript done, length: \(transcript.count)")
            }

        case "response.output_text.delta":
            if let delta = json["delta"] as? String {
                delegate?.realtimeClient(self, didReceiveTextDelta: delta)
            }

        case "response.output_text.done":
            if let text = json["text"] as? String {
                delegate?.realtimeClient(self, didReceiveTextDone: text)
                logDebug("RealtimeClient: Text output done, length: \(text.count)")
            }

        case "response.done":
            delegate?.realtimeClient(self, didReceiveResponseDone: json)
            if let typed = try? JSONDecoder().decode(RealtimeResponseDone.self, from: rawData) {
                delegate?.realtimeClient(self, didReceiveTypedResponseDone: typed)
            } else {
                logDebug("RealtimeClient: Failed to decode typed response.done")
            }
            logDebug("RealtimeClient: Response done")

        case "response.function_call_arguments.delta":
            if let delta = json["delta"] as? String,
               let callId = json["call_id"] as? String {
                delegate?.realtimeClient(self, didReceiveFunctionCallArgumentsDelta: delta, callId: callId)
            }

        case "response.function_call_arguments.done":
            if let arguments = json["arguments"] as? String,
               let callId = json["call_id"] as? String {
                delegate?.realtimeClient(self, didReceiveFunctionCallArgumentsDone: arguments, callId: callId)
                logDebug("RealtimeClient: Function call arguments done for \(callId)")
            }

        case "conversation.item.created":
            if let item = json["item"] as? [String: Any] {
                delegate?.realtimeClient(self, didReceiveConversationItemCreated: item)
            }

        case "rate_limits.updated":
            if let rateLimits = json["rate_limits"] as? [[String: Any]] {
                delegate?.realtimeClient(self, didReceiveRateLimitsUpdated: rateLimits)
                logDebug("RealtimeClient: Rate limits updated")
            }

        default:
            logDebug("RealtimeClient: Unhandled event type: \(type)")
        }
    }

    // MARK: - Private: Reconnection

    private func handleDisconnection(error: Error?) {
        guard !intentionalDisconnect else { return }

        if reconnectAttempt < maxReconnectAttempts {
            reconnectAttempt += 1
            let delay = pow(2.0, Double(reconnectAttempt - 1)) // 1s, 2s, 4s
            setConnectionState(.reconnecting)
            logInfo("RealtimeClient: Reconnecting in \(Int(delay))s (attempt \(reconnectAttempt)/\(maxReconnectAttempts))")

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.connectionState == .reconnecting else { return }
                self.webSocketTask = nil
                self.urlSession?.invalidateAndCancel()
                self.urlSession = nil
                self.setConnectionState(.connecting)
                self.establishConnection()
            }
        } else {
            logError("RealtimeClient: Failed to reconnect after \(maxReconnectAttempts) attempts")
            setConnectionState(.disconnected)
            delegate?.realtimeClientDidDisconnect(self, error: error)
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        logInfo("RealtimeClient: WebSocket connected")
        Task { @MainActor in
            self.reconnectAttempt = 0
            self.setConnectionState(.connected)
            self.delegate?.realtimeClientDidConnect(self)
            self.sendSessionConfig()
            self.receiveMessages()
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        logInfo("RealtimeClient: WebSocket closed (code: \(closeCode.rawValue), reason: \(reasonString))")
        Task { @MainActor in
            self.handleDisconnection(error: nil)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            logError("RealtimeClient: Connection error: \(error.localizedDescription)")
            Task { @MainActor in
                self.handleDisconnection(error: error)
            }
        }
    }
}
