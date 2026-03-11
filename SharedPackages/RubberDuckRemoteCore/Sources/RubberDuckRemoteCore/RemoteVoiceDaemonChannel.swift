import Foundation

public enum RemoteVoiceDaemonEvent: Equatable, Sendable {
    case ready(clientId: String)
    case voiceStart(sessionId: String?)
    case voiceStop(sessionId: String?, reason: String?)
    case voiceSay(text: String, sessionId: String?)
}

public actor RemoteVoiceDaemonChannel {
    private let session: URLSession
    private let credentialStore: RemoteCredentialStore
    private var socketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var currentHostID: String?
    private var eventHandler: (@Sendable (RemoteVoiceDaemonEvent) -> Void)?
    private var pendingResponses: [String: CheckedContinuation<[String: Any], Error>] = [:]

    public init(
        session: URLSession = .shared,
        credentialStore: RemoteCredentialStore = RemoteCredentialStore()
    ) {
        self.session = session
        self.credentialStore = credentialStore
    }

    deinit {
        socketTask?.cancel(with: .goingAway, reason: nil)
        receiveTask?.cancel()
    }

    public func connect(
        to host: PairedRemoteHost,
        handler: @escaping @Sendable (RemoteVoiceDaemonEvent) -> Void
    ) async throws {
        if currentHostID == host.id, socketTask != nil {
            eventHandler = handler
            return
        }

        await disconnect()

        var request = URLRequest(url: try websocketURL(for: host))
        request.timeoutInterval = 15
        request.setValue(
            "Bearer \(try credentialStore.loadToken(for: host.id))",
            forHTTPHeaderField: "Authorization"
        )

        let socketTask = session.webSocketTask(with: request)
        socketTask.resume()

        self.socketTask = socketTask
        self.currentHostID = host.id
        self.eventHandler = handler
        self.receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    public func disconnect() async {
        let pending = pendingResponses.values
        pendingResponses.removeAll()
        for continuation in pending {
            continuation.resume(throwing: RemoteDaemonError.websocketUnavailable)
        }

        receiveTask?.cancel()
        receiveTask = nil
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        currentHostID = nil
        eventHandler = nil
    }

    public func registerVoiceClient(
        version: String,
        workspacePath: String?
    ) async throws {
        var params: [String: Any] = [
            "clientType": "remote-ios",
            "clientVersion": version,
            "takeover": true,
        ]
        if let workspacePath, !workspacePath.isEmpty {
            params["workspacePath"] = workspacePath
        }
        _ = try await rpc(method: "voice_connect", params: params)
    }

    public func startVoice(sessionId: String) async throws {
        _ = try await rpc(method: "voice_start", params: ["sessionId": sessionId])
    }

    public func updateVoiceState(
        _ state: RemoteDaemonVoiceState,
        sessionId: String
    ) async throws {
        _ = try await rpc(
            method: "voice_state",
            params: [
                "sessionId": sessionId,
                "state": state.rawValue,
            ]
        )
    }

    public func executeToolCall(
        callId: String,
        toolName: String,
        arguments: String,
        sessionId: String,
        workspacePath: String
    ) async throws -> String {
        let payload = try await rpc(
            method: "voice_tool_call",
            params: [
                "callId": callId,
                "toolName": toolName,
                "arguments": arguments,
                "sessionId": sessionId,
                "workspacePath": workspacePath,
            ]
        )

        guard let data = payload["data"] as? [String: Any],
              let result = data["result"] else {
            throw RemoteDaemonError.messageFailed("Voice tool \(toolName) returned no result.")
        }

        if let text = result as? String {
            return text
        }

        let jsonData = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        return String(decoding: jsonData, as: UTF8.self)
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            guard let socketTask else {
                return
            }

            do {
                let message = try await socketTask.receive()
                switch message {
                case .string(let text):
                    await handleSocketText(text)
                case .data(let data):
                    await handleSocketText(String(decoding: data, as: UTF8.self))
                @unknown default:
                    continue
                }
            } catch {
                break
            }
        }

        await disconnect()
    }

    private func handleSocketText(_ text: String) async {
        guard let payload = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            return
        }

        if let responseID = payload["id"] as? String,
           let continuation = pendingResponses.removeValue(forKey: responseID) {
            continuation.resume(returning: payload)
            return
        }

        guard let eventName = payload["event"] as? String else {
            return
        }

        let data = payload["data"] as? [String: Any]
        let sessionId = payload["sessionId"] as? String

        switch eventName {
        case "remote_ready":
            if let clientId = data?["clientId"] as? String {
                eventHandler?(.ready(clientId: clientId))
            }
        case "voice_start":
            eventHandler?(.voiceStart(sessionId: sessionId))
        case "voice_stop":
            eventHandler?(
                .voiceStop(
                    sessionId: sessionId,
                    reason: data?["reason"] as? String
                )
            )
        case "voice_say":
            if let text = data?["text"] as? String, !text.isEmpty {
                eventHandler?(.voiceSay(text: text, sessionId: sessionId))
            }
        default:
            break
        }
    }

    private func rpc(
        method: String,
        params: [String: Any]
    ) async throws -> [String: Any] {
        guard let socketTask else {
            throw RemoteDaemonError.websocketUnavailable
        }

        let requestID = UUID().uuidString
        let payloadData = try JSONSerialization.data(withJSONObject: [
            "id": requestID,
            "method": method,
            "params": params,
        ])
        let payloadText = String(decoding: payloadData, as: UTF8.self)

        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
            pendingResponses[requestID] = continuation
            socketTask.send(.string(payloadText)) { [weak self] error in
                guard let self else {
                    continuation.resume(throwing: RemoteDaemonError.websocketUnavailable)
                    return
                }
                if let error {
                    Task {
                        await self.failPendingResponse(requestID: requestID, error: error)
                    }
                }
            }
        }

        if let ok = response["ok"] as? Bool, ok == false {
            throw RemoteDaemonError.messageFailed(
                response["error"] as? String ?? "Voice daemon request \(method) failed."
            )
        }

        return response
    }

    private func failPendingResponse(requestID: String, error: Error) {
        guard let continuation = pendingResponses.removeValue(forKey: requestID) else {
            return
        }
        continuation.resume(throwing: error)
    }

    private func websocketURL(for host: PairedRemoteHost) throws -> URL {
        guard var components = URLComponents(url: host.baseURL, resolvingAgainstBaseURL: false) else {
            throw RemoteDaemonError.invalidHostURL
        }

        components.scheme = host.baseURL.scheme == "https" ? "wss" : "ws"
        components.path = "/ws"
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw RemoteDaemonError.invalidHostURL
        }

        return url
    }
}
