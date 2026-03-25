import Foundation

public actor RemoteDaemonHTTPTransport: RemoteDaemonTransport {
    private final class JSONObjectBox: @unchecked Sendable {
        let value: [String: Any]

        init(_ value: [String: Any]) {
            self.value = value
        }
    }

    private struct ErrorEnvelope: Decodable {
        let error: String?
    }

    private struct RemoteStatusPayload: Decodable {
        let connectedClients: Int?
        let enabled: Bool
        let host: String
        let httpUrl: String?
        let lastError: String?
        let listening: Bool
        let port: Int
        let protocolName: String
        let tlsEnabled: Bool
        let tokenConfigured: Bool
        let tokenUpdatedAt: String?
        let wsUrl: String?

        enum CodingKeys: String, CodingKey {
            case connectedClients
            case enabled
            case host
            case httpUrl
            case lastError
            case listening
            case port
            case protocolName = "protocol"
            case tlsEnabled
            case tokenConfigured
            case tokenUpdatedAt
            case wsUrl
        }
    }

    private struct RemoteRPCEnvelope<Payload: Decodable>: Decodable {
        let id: String
        let ok: Bool
        let data: Payload?
        let error: String?
    }

    private struct HistoryEnvelope: Decodable {
        let events: [HistoryEventDTO]
        let sessionId: String
    }

    private struct HistoryEventDTO: Decodable {
        let timestamp: String?
        let sessionID: String?
        let type: String
        let text: String?
        let metadata: [String: String]?
    }

    private struct SessionsRPCData: Decodable {
        let sessions: [SessionDTO]
    }

    private struct SessionDTO: Decodable {
        let id: String
        let name: String
        let workspacePath: String
        let isActive: Bool
        let isRunning: Bool
        let lastActiveAt: String?
    }

    private struct GetStateRPCData: Decodable {
        let sessionId: String
        let sessionName: String
        let isRunning: Bool
        let piState: PiStateDTO?
    }

    private struct PiModelDTO: Decodable {
        let id: String?
        let name: String?
    }

    private enum FlexibleModel: Decodable {
        case string(String)
        case object(PiModelDTO)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let stringValue = try? container.decode(String.self) {
                self = .string(stringValue)
            } else if let objectValue = try? container.decode(PiModelDTO.self) {
                self = .object(objectValue)
            } else {
                self = .string("unknown")
            }
        }

        var displayName: String {
            switch self {
            case .string(let value): return value
            case .object(let dto): return dto.id ?? dto.name ?? "unknown"
            }
        }
    }

    private struct PiStateDTO: Decodable {
        let isStreaming: Bool?
        let messageCount: Int?
        let model: FlexibleModel?
        let pendingMessageCount: Int?
        let sessionId: String?
        let sessionName: String?
        let thinkingLevel: String?
    }

    private struct ActivateSessionRPCData: Decodable {
        let session: SessionRefDTO
        let workspace: WorkspaceRefDTO
    }

    private struct SessionRefDTO: Decodable {
        let id: String
        let name: String
        let workspaceId: String
    }

    private struct WorkspaceRefDTO: Decodable {
        let id: String
        let path: String
    }

    private struct FollowRPCData: Decodable {
        let sessionId: String
        let sessionName: String
        let workspacePath: String
        let isRunning: Bool
    }

    private struct SessionsParams: Encodable {
        let all = true
        let workspaceId: String? = nil
    }

    private struct ActivateSessionParams: Encodable {
        let sessionId: String
    }

    private struct SayParams: Encodable {
        let message: String
        let preferPi = false
        let sessionId: String
    }

    private struct GetStateParams: Encodable {
        let sessionId: String
    }

    private struct WebSocketState {
        let task: URLSessionWebSocketTask
        let followedSessionID: String
        let handler: @Sendable (RemoteDaemonStreamUpdate) -> Void
        var receiveTask: Task<Void, Never>?
    }

    private final class PendingWebSocketResponse: @unchecked Sendable {
        private var continuation: CheckedContinuation<JSONObjectBox, Error>?

        init(_ continuation: CheckedContinuation<JSONObjectBox, Error>) {
            self.continuation = continuation
        }

        func succeed(_ payload: [String: Any]) {
            continuation?.resume(returning: JSONObjectBox(payload))
            continuation = nil
        }

        func fail(_ error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    private struct PendingAssistantBuffer {
        var text: String
        var timestamp: Date
        var metadata: [String: String]
    }

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let iso8601Formatter = ISO8601DateFormatter()
    private let credentialStore: RemoteCredentialStore
    private let session: URLSession
    private var pendingAssistantBuffers: [String: PendingAssistantBuffer] = [:]
    private var transcripts: [String: [String: [RemoteConversationEntry]]] = [:]
    private var webSockets: [String: WebSocketState] = [:]
    private var pendingWebSocketResponses: [String: [String: PendingWebSocketResponse]] = [:]

    public init(
        session: URLSession = .shared,
        credentialStore: RemoteCredentialStore = RemoteCredentialStore()
    ) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        self.credentialStore = credentialStore
        self.session = session
    }

    public func pair(
        hostURL: URL,
        displayName: String,
        authToken: String
    ) async throws -> PairedRemoteHost {
        let normalizedToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw RemoteDaemonError.invalidAuthToken
        }

        guard let baseURL = normalizedBaseURL(from: hostURL) else {
            throw RemoteDaemonError.invalidHostURL
        }

        var host = PairedRemoteHost(
            id: baseURL.absoluteString.lowercased(),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (baseURL.host ?? "Rubber Duck Mac")
                : displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL,
            authToken: "",
            pairingCodeHint: String(normalizedToken.suffix(4)).uppercased(),
            pairedAt: .now,
            lastConnectedAt: .now
        )

        try credentialStore.saveToken(normalizedToken, for: host.id)
        _ = try await fetchStatus(for: host)
        host = refreshedHost(host)
        return host
    }

    public func activateSession(
        _ session: RemoteSessionSummary,
        on host: PairedRemoteHost
    ) async throws -> RemoteSessionSummary {
        let envelope: RemoteRPCEnvelope<ActivateSessionRPCData> = try await rpc(
            on: host,
            method: "activate_session",
            params: ActivateSessionParams(sessionId: session.id)
        )

        guard envelope.ok else {
            throw RemoteDaemonError.messageFailed(envelope.error ?? "Failed to activate \(session.name).")
        }

        let sessions = try await fetchSessions(for: host)
        return sessions.first(where: { $0.id == session.id }) ?? RemoteSessionSummary(
            id: session.id,
            name: envelope.data?.session.name ?? session.name,
            workspacePath: envelope.data?.workspace.path ?? session.workspacePath,
            isActive: true,
            isRunning: session.isRunning,
            lastActiveAt: .now
        )
    }

    public func loadSnapshot(for host: PairedRemoteHost) async throws -> RemoteDaemonSnapshot {
        let status = try await fetchStatus(for: host)

        guard status.enabled else {
            throw RemoteDaemonError.remoteDisabled
        }

        guard status.listening else {
            throw RemoteDaemonError.remoteNotListening
        }

        let sessions = try await fetchSessions(for: host)
        let activeSession = sessions.first(where: \.isActive) ?? sessions.first(where: \.isRunning) ?? sessions.first

        let conversation: [RemoteConversationEntry]
        if let activeSession {
            conversation = try await loadConversation(for: activeSession, on: host, limit: 200)
        } else {
            conversation = []
        }

        let voiceState: RemoteDaemonVoiceState = activeSession?.isRunning == true ? .listening : .idle

        return RemoteDaemonSnapshot(
            host: refreshedHost(host),
            activeSession: activeSession,
            sessions: sessions,
            conversation: conversation,
            voiceState: voiceState,
            lastSyncedAt: .now
        )
    }

    public func loadConversation(
        for session: RemoteSessionSummary,
        on host: PairedRemoteHost,
        limit: Int
    ) async throws -> [RemoteConversationEntry] {
        if let cachedTranscript = transcripts[host.id]?[session.id], !cachedTranscript.isEmpty {
            return Array(cachedTranscript.suffix(max(limit, 1)))
        }

        if let historyEvents = try await fetchHistory(for: session, on: host, limit: limit),
           !historyEvents.isEmpty {
            let transcript = ConversationTranscriptBuilder.build(from: historyEvents)
            if !transcript.isEmpty {
                setTranscript(transcript, hostId: host.id, sessionId: session.id)
                return transcript
            }
        }

        let state = try await fetchState(for: session, on: host)
        let seededTranscript = seededConversation(for: session, state: state)
        setTranscript(seededTranscript, hostId: host.id, sessionId: session.id)
        return seededTranscript
    }

    public func sendMessage(
        _ message: String,
        session: RemoteSessionSummary,
        on host: PairedRemoteHost
    ) async throws -> RemoteConversationEntry {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RemoteDaemonError.messageFailed("Type a message before sending.")
        }

        let optimisticEntry = RemoteConversationEntry(
            role: .user,
            text: trimmed,
            timestamp: .now,
            metadata: [
                "delivery": "accepted",
                "transport": "rpc"
            ]
        )

        _ = appendEntries([optimisticEntry], hostId: host.id, sessionId: session.id)

        let envelope: RemoteRPCEnvelope<SessionResponseStub> = try await rpc(
            on: host,
            method: "say",
            params: SayParams(message: trimmed, sessionId: session.id)
        )

        guard envelope.ok else {
            throw RemoteDaemonError.messageFailed(envelope.error ?? "Failed to send the prompt.")
        }

        return optimisticEntry
    }

    public func subscribe(
        to session: RemoteSessionSummary,
        on host: PairedRemoteHost,
        handler: @escaping @Sendable (RemoteDaemonStreamUpdate) -> Void
    ) async throws {
        await unsubscribe(from: host)

        let webSocketURL = try await resolveWebSocketURL(for: host)
        var request = URLRequest(url: webSocketURL)
        let authToken = try credentialStore.loadToken(for: host.id)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let webSocketTask = self.session.webSocketTask(with: request)
        webSocketTask.resume()

        var socketState = WebSocketState(
            task: webSocketTask,
            followedSessionID: session.id,
            handler: handler,
            receiveTask: nil
        )

        webSockets[host.id] = socketState
        handler(.setVoiceState(.connecting))

        socketState.receiveTask = Task { [host, sessionID = session.id] in
            await self.receiveLoop(for: host, sessionId: sessionID)
        }
        webSockets[host.id] = socketState

        let payload = try await sendWebSocketRequest(
            method: "follow",
            params: ["sessionId": session.id],
            on: host
        )

        let followData = decodeFollowData(from: payload["data"])
        let notice = followData.map {
            "Following \($0.sessionName) in \($0.workspacePath)."
        } ?? "Following the selected session."
        handler(.notice(notice))
        handler(.setVoiceState(followData?.isRunning == true ? .listening : .idle))
    }

    public func unsubscribe(from host: PairedRemoteHost) async {
        guard let socketState = webSockets.removeValue(forKey: host.id) else {
            clearPendingAssistantBuffers(for: host.id)
            failPendingWebSocketResponses(for: host.id, error: RemoteDaemonError.websocketUnavailable)
            return
        }

        socketState.receiveTask?.cancel()
        socketState.task.cancel(with: .goingAway, reason: nil)
        clearPendingAssistantBuffers(for: host.id)
        failPendingWebSocketResponses(for: host.id, error: RemoteDaemonError.websocketUnavailable)
    }

    public func connectVoiceClient(
        on host: PairedRemoteHost,
        session: RemoteSessionSummary,
        clientVersion: String
    ) async throws {
        let payload = try await sendWebSocketRequest(
            method: "voice_connect",
            params: [
                "clientType": "remote-ios",
                "clientVersion": clientVersion,
                "takeover": true,
                "workspacePath": session.workspacePath
            ],
            on: host
        )
        if (payload["ok"] as? Bool) != true {
            throw RemoteDaemonError.messageFailed(
                payload["error"] as? String ?? "Failed to connect the voice control channel."
            )
        }
    }

    public func startVoiceSession(
        _ session: RemoteSessionSummary,
        on host: PairedRemoteHost
    ) async throws {
        let payload = try await sendWebSocketRequest(
            method: "voice_start",
            params: ["sessionId": session.id],
            on: host
        )
        if (payload["ok"] as? Bool) != true {
            throw RemoteDaemonError.messageFailed(
                payload["error"] as? String ?? "Failed to start the remote voice session."
            )
        }
    }

    public func updateVoiceState(
        _ state: RemoteDaemonVoiceState,
        session: RemoteSessionSummary,
        on host: PairedRemoteHost
    ) async throws {
        let payload = try await sendWebSocketRequest(
            method: "voice_state",
            params: [
                "sessionId": session.id,
                "state": state.rawValue
            ],
            on: host
        )
        if (payload["ok"] as? Bool) != true {
            throw RemoteDaemonError.messageFailed(
                payload["error"] as? String ?? "Failed to update the remote voice state."
            )
        }
    }

    public func executeVoiceToolCall(
        callId: String,
        toolName: String,
        arguments: String,
        session: RemoteSessionSummary,
        on host: PairedRemoteHost
    ) async throws -> String {
        let payload = try await sendWebSocketRequest(
            method: "voice_tool_call",
            params: [
                "callId": callId,
                "toolName": toolName,
                "arguments": arguments,
                "sessionId": session.id,
                "workspacePath": session.workspacePath
            ],
            on: host
        )

        guard (payload["ok"] as? Bool) == true else {
            throw RemoteDaemonError.messageFailed(
                payload["error"] as? String ?? "The daemon tool call failed."
            )
        }

        if let data = payload["data"] as? [String: Any],
           let output = data["result"] as? String {
            return output
        }

        if let data = payload["data"] as? [String: Any] {
            if let serialized = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]),
               let output = String(data: serialized, encoding: .utf8) {
                return output
            }
        }

        return ""
    }

    // MARK: - HTTP

    private func fetchStatus(for host: PairedRemoteHost) async throws -> RemoteStatusPayload {
        let request = try authorizedRequest(on: host, path: "/status", method: "GET")
        return try await perform(request, as: RemoteStatusPayload.self)
    }

    private func fetchSessions(for host: PairedRemoteHost) async throws -> [RemoteSessionSummary] {
        let envelope: RemoteRPCEnvelope<SessionsRPCData> = try await rpc(
            on: host,
            method: "sessions",
            params: SessionsParams()
        )

        let sessions = envelope.data?.sessions ?? []
        return sessions
            .map { item in
                RemoteSessionSummary(
                    id: item.id,
                    name: item.name,
                    workspacePath: item.workspacePath,
                    isActive: item.isActive,
                    isRunning: item.isRunning,
                    lastActiveAt: date(from: item.lastActiveAt)
                )
            }
            .sorted(by: { $0.lastActiveAt > $1.lastActiveAt })
    }

    private func fetchState(
        for session: RemoteSessionSummary,
        on host: PairedRemoteHost
    ) async throws -> GetStateRPCData {
        let envelope: RemoteRPCEnvelope<GetStateRPCData> = try await rpc(
            on: host,
            method: "get_state",
            params: GetStateParams(sessionId: session.id)
        )

        guard let data = envelope.data else {
            throw RemoteDaemonError.messageFailed("Daemon did not return state for \(session.name).")
        }

        return data
    }

    private func fetchHistory(
        for session: RemoteSessionSummary,
        on host: PairedRemoteHost,
        limit: Int
    ) async throws -> [ConversationHistoryEvent]? {
        var request = try authorizedRequest(on: host, path: "/history", method: "GET")
        guard var components = URLComponents(url: request.url ?? host.baseURL, resolvingAgainstBaseURL: false) else {
            throw RemoteDaemonError.invalidHostURL
        }

        components.queryItems = [
            URLQueryItem(name: "sessionId", value: session.id),
            URLQueryItem(name: "limit", value: String(max(limit, 1)))
        ]
        request.url = components.url

        do {
            let envelope = try await perform(request, as: HistoryEnvelope.self)
            let events: [ConversationHistoryEvent] = envelope.events.compactMap {
                item -> ConversationHistoryEvent? in
                guard let eventType = ConversationEventType(rawValue: item.type) else {
                    return nil
                }

                return ConversationHistoryEvent(
                    timestamp: date(from: item.timestamp),
                    sessionID: item.sessionID ?? envelope.sessionId,
                    type: eventType,
                    text: item.text,
                    metadata: item.metadata
                )
            }
            return events
        } catch let error as RemoteDaemonError {
            if case .messageFailed(let message) = error,
               message.contains("HTTP 404") || message.contains("History not found for session") {
                return nil
            }
            throw error
        }
    }

    @discardableResult
    private func rpc<Payload: Decodable, Params: Encodable>(
        on host: PairedRemoteHost,
        method: String,
        params: Params
    ) async throws -> RemoteRPCEnvelope<Payload> {
        let body = try encoder.encode(RPCRequest(method: method, params: params))
        let request = try authorizedRequest(on: host, path: "/rpc", method: "POST", body: body)
        return try await perform(request, as: RemoteRPCEnvelope<Payload>.self)
    }

    private func authorizedRequest(
        on host: PairedRemoteHost,
        path: String,
        method: String,
        body: Data? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: host.baseURL) else {
            throw RemoteDaemonError.invalidHostURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = method == "GET" ? 15 : 30
        let authToken = try credentialStore.loadToken(for: host.id)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func perform<Response: Decodable>(
        _ request: URLRequest,
        as responseType: Response.Type
    ) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        let httpResponse = try requireHTTPResponse(response)

        if httpResponse.statusCode == 401 {
            throw RemoteDaemonError.unauthorized
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorEnvelope = try? decoder.decode(ErrorEnvelope.self, from: data)
            throw RemoteDaemonError.messageFailed(
                errorEnvelope?.error ?? "The remote daemon returned HTTP \(httpResponse.statusCode)."
            )
        }

        do {
            return try decoder.decode(responseType, from: data)
        } catch {
            throw RemoteDaemonError.messageFailed(
                "Failed to decode the remote daemon response: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - WebSocket

    private func resolveWebSocketURL(for host: PairedRemoteHost) async throws -> URL {
        let status = try await fetchStatus(for: host)

        if let wsUrl = status.wsUrl,
           let resolved = URL(string: wsUrl) {
            return resolved
        }

        guard var components = URLComponents(url: host.baseURL, resolvingAgainstBaseURL: false) else {
            throw RemoteDaemonError.websocketUnavailable
        }

        components.scheme = host.baseURL.scheme == "https" ? "wss" : "ws"
        components.path = "/ws"
        components.query = nil
        components.fragment = nil

        guard let fallbackURL = components.url else {
            throw RemoteDaemonError.websocketUnavailable
        }

        return fallbackURL
    }

    private func receiveLoop(for host: PairedRemoteHost, sessionId: String) async {
        while !Task.isCancelled {
            guard let socketState = webSockets[host.id] else {
                return
            }

            do {
                let message = try await socketState.task.receive()
                let text: String

                switch message {
                case .string(let value):
                    text = value
                case .data(let data):
                    text = String(decoding: data, as: UTF8.self)
                @unknown default:
                    continue
                }

                await handleWebSocketText(text, host: host, sessionId: sessionId)
            } catch {
                if Task.isCancelled {
                    return
                }

                if let handler = webSockets[host.id]?.handler {
                    handler(.notice("Follow channel disconnected: \(error.localizedDescription)"))
                    handler(.setVoiceState(.idle))
                }

                failPendingWebSocketResponses(for: host.id, error: error)
                await unsubscribe(from: host)
                return
            }
        }
    }

    private func handleWebSocketText(
        _ text: String,
        host: PairedRemoteHost,
        sessionId: String
    ) async {
        guard let payload = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            return
        }

        if let eventName = payload["event"] as? String {
            let eventSessionId = payload["sessionId"] as? String
            await handleDaemonEvent(
                eventName,
                payload: payload["data"] as? [String: Any] ?? [:],
                eventSessionId: eventSessionId,
                host: host
            )
            return
        }

        guard let responseId = payload["id"] as? String else {
            return
        }

        if let response = pendingWebSocketResponses[host.id]?[responseId] {
            pendingWebSocketResponses[host.id]?.removeValue(forKey: responseId)
            if pendingWebSocketResponses[host.id]?.isEmpty == true {
                pendingWebSocketResponses.removeValue(forKey: host.id)
            }
            response.succeed(payload)
        }
    }

    private func handleDaemonEvent(
        _ eventName: String,
        payload: [String: Any],
        eventSessionId: String?,
        host: PairedRemoteHost
    ) async {
        switch eventName {
        case "remote_ready":
            if let clientId = payload["clientId"] as? String {
                webSockets[host.id]?.handler(.voiceControl(.ready(clientID: clientId)))
            }

        case "voice_start":
            webSockets[host.id]?.handler(.voiceControl(.start(sessionID: eventSessionId)))

        case "voice_stop":
            webSockets[host.id]?.handler(
                .voiceControl(
                    .stop(
                        sessionID: eventSessionId,
                        reason: payload["reason"] as? String
                    )
                )
            )
            webSockets[host.id]?.handler(.setVoiceState(.idle))

        case "voice_say":
            if let text = payload["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                webSockets[host.id]?.handler(
                    .voiceControl(.say(text: text, sessionID: eventSessionId))
                )
            }

        case "voice_session_changed":
            if let eventSessionId {
                webSockets[host.id]?.handler(
                    .sessionChanged(
                        sessionID: eventSessionId,
                        sessionName: payload["sessionName"] as? String,
                        workspacePath: payload["workspacePath"] as? String
                    )
                )
            }

        case "message_start":
            if let eventSessionId,
               let entry = makeMessageEntry(from: payload) {
                emitEntries([entry], hostId: host.id, sessionId: eventSessionId)
            }

        case "message_update":
            if let eventSessionId {
                handleMessageUpdate(payload, hostId: host.id, sessionId: eventSessionId)
            }

        case "message_end":
            if let eventSessionId {
                if let entry = flushPendingAssistant(hostId: host.id, sessionId: eventSessionId) {
                    emitEntries([entry], hostId: host.id, sessionId: eventSessionId)
                } else if let entry = makeMessageEntry(from: payload) {
                    emitEntries([entry], hostId: host.id, sessionId: eventSessionId)
                }
            }

        case "tool_execution_start":
            webSockets[host.id]?.handler(.setVoiceState(.toolRunning))
            if let eventSessionId,
               let entry = makeToolEntry(from: payload, state: "started") {
                emitEntries([entry], hostId: host.id, sessionId: eventSessionId)
            }

        case "tool_execution_end":
            if let eventSessionId,
               let entry = makeToolEntry(from: payload, state: "completed") {
                emitEntries([entry], hostId: host.id, sessionId: eventSessionId)
            }
            webSockets[host.id]?.handler(.setVoiceState(.thinking))

        case "extension_ui_request":
            if let method = payload["method"] as? String,
               method == "setStatus",
               let message = payload["message"] as? String,
               message.hasPrefix("voice:") {
                let rawValue = String(message.dropFirst("voice:".count))
                if let voiceState = RemoteDaemonVoiceState(rawValue: rawValue) {
                    webSockets[host.id]?.handler(.setVoiceState(voiceState))
                }
            }

        default:
            break
        }
    }

    private func sendWebSocketRequest(
        method: String,
        params: [String: Any],
        on host: PairedRemoteHost
    ) async throws -> [String: Any] {
        guard let socketTask = webSockets[host.id]?.task else {
            throw RemoteDaemonError.websocketUnavailable
        }

        let id = UUID().uuidString
        let payload: [String: Any] = [
            "id": id,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let text = String(decoding: data, as: UTF8.self)

        let box = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONObjectBox, Error>) in
            let response = PendingWebSocketResponse(continuation)
            pendingWebSocketResponses[host.id, default: [:]][id] = response

            Task {
                do {
                    try await socketTask.send(.string(text))
                } catch {
                    self.resumePendingWebSocketResponse(
                        for: host.id,
                        id: id,
                        payload: nil,
                        error: error
                    )
                }
            }
        }

        return box.value
    }

    private func resumePendingWebSocketResponse(
        for hostID: String,
        id: String,
        payload: [String: Any]?,
        error: Error?
    ) {
        guard let response = pendingWebSocketResponses[hostID]?[id] else {
            return
        }
        pendingWebSocketResponses[hostID]?.removeValue(forKey: id)
        if pendingWebSocketResponses[hostID]?.isEmpty == true {
            pendingWebSocketResponses.removeValue(forKey: hostID)
        }
        if let payload {
            response.succeed(payload)
        } else if let error {
            response.fail(error)
        }
    }

    private func failPendingWebSocketResponses(
        for hostID: String,
        error: Error
    ) {
        let pending = pendingWebSocketResponses.removeValue(forKey: hostID) ?? [:]
        for response in pending.values {
                response.fail(error)
        }
    }

    // MARK: - Event Mapping

    private func decodeFollowData(from payload: Any?) -> FollowRPCData? {
        guard let payload else {
            return nil
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }

        return try? decoder.decode(FollowRPCData.self, from: data)
    }

    private func makeMessageEntry(from payload: [String: Any]) -> RemoteConversationEntry? {
        guard let message = payload["message"] as? [String: Any],
              let role = message["role"] as? String,
              let text = extractMessageText(from: message),
              !text.isEmpty else {
            return nil
        }

        let remoteRole: RemoteConversationRole
        switch role {
        case "assistant":
            remoteRole = .assistant
        case "user":
            remoteRole = .user
        default:
            remoteRole = .status
        }

        return RemoteConversationEntry(
            role: remoteRole,
            text: text,
            timestamp: date(from: message["timestamp"] as? String),
            metadata: ["source": "follow"]
        )
    }

    private func handleMessageUpdate(
        _ payload: [String: Any],
        hostId: String,
        sessionId: String
    ) {
        guard let assistantMessageEvent = payload["assistantMessageEvent"] as? [String: Any],
              let type = assistantMessageEvent["type"] as? String else {
            return
        }

        switch type {
        case "thinking_start":
            webSockets[hostId]?.handler(.setVoiceState(.thinking))

        case "text_start":
            pendingAssistantBuffers[pendingAssistantKey(hostId: hostId, sessionId: sessionId)] = PendingAssistantBuffer(
                text: "",
                timestamp: .now,
                metadata: ["source": "follow"]
            )

        case "text_delta":
            let key = pendingAssistantKey(hostId: hostId, sessionId: sessionId)
            var buffer = pendingAssistantBuffers[key] ?? PendingAssistantBuffer(
                text: "",
                timestamp: .now,
                metadata: ["source": "follow"]
            )
            buffer.text += assistantMessageEvent["delta"] as? String ?? ""
            pendingAssistantBuffers[key] = buffer

        case "text_end", "done":
            if let entry = flushPendingAssistant(hostId: hostId, sessionId: sessionId) {
                emitEntries([entry], hostId: hostId, sessionId: sessionId)
            }
            webSockets[hostId]?.handler(.setVoiceState(.listening))

        default:
            break
        }
    }

    private func flushPendingAssistant(hostId: String, sessionId: String) -> RemoteConversationEntry? {
        let key = pendingAssistantKey(hostId: hostId, sessionId: sessionId)
        guard let buffer = pendingAssistantBuffers.removeValue(forKey: key) else {
            return nil
        }

        let text = buffer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }

        return RemoteConversationEntry(
            role: .assistant,
            text: text,
            timestamp: buffer.timestamp,
            metadata: buffer.metadata
        )
    }

    private func makeToolEntry(from payload: [String: Any], state: String) -> RemoteConversationEntry? {
        guard let toolName = payload["toolName"] as? String else {
            return nil
        }

        let summaryText: String
        if let result = payload["result"] as? [String: Any],
           let content = result["content"] as? [[String: Any]] {
            let rendered = content
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            summaryText = rendered.isEmpty ? "\(toolName) \(state)" : "\(toolName): \(rendered)"
        } else {
            summaryText = "\(toolName) \(state)"
        }

        return RemoteConversationEntry(
            role: .tool,
            text: summaryText,
            timestamp: .now,
            metadata: [
                "state": state,
                "tool": toolName
            ]
        )
    }

    private func extractMessageText(from message: [String: Any]) -> String? {
        if let content = message["content"] as? String {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        guard let contentBlocks = message["content"] as? [[String: Any]] else {
            return nil
        }

        let rendered = contentBlocks
            .compactMap { block -> String? in
                guard let type = block["type"] as? String else {
                    return nil
                }

                if type == "text" || type == "thinking" || type == "tool_result" {
                    return block["text"] as? String
                }

                return nil
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return rendered.isEmpty ? nil : rendered
    }

    private func seededConversation(
        for session: RemoteSessionSummary,
        state: GetStateRPCData
    ) -> [RemoteConversationEntry] {
        var entries = [
            RemoteConversationEntry(
                role: .status,
                text: "Following \(session.name) in \(session.workspacePath). History is empty, so new activity will appear live from the daemon follow stream.",
                timestamp: .now,
                metadata: [
                    "session": session.id,
                    "transport": "https+wss"
                ]
            )
        ]

        if state.isRunning, let piState = state.piState {
            entries.append(
                RemoteConversationEntry(
                    role: .status,
                    text: "Pi is running \(piState.model?.displayName ?? "the default model") with \(piState.messageCount ?? 0) messages and \(piState.pendingMessageCount ?? 0) pending.",
                    timestamp: .now.addingTimeInterval(0.1),
                    metadata: [
                        "model": piState.model?.displayName ?? "unknown",
                        "thinking": piState.thinkingLevel ?? "unknown"
                    ]
                )
            )
        } else {
            entries.append(
                RemoteConversationEntry(
                    role: .status,
                    text: "This session is idle. Sending a prompt will resume Pi and stream new output here.",
                    timestamp: .now.addingTimeInterval(0.1)
                )
            )
        }

        return entries
    }

    private func emitEntries(_ entries: [RemoteConversationEntry], hostId: String, sessionId: String) {
        let insertedEntries = appendEntries(entries, hostId: hostId, sessionId: sessionId)
        guard !insertedEntries.isEmpty,
              let handler = webSockets[hostId]?.handler else {
            return
        }

        handler(.appendEntries(insertedEntries))
    }

    private func appendEntries(
        _ entries: [RemoteConversationEntry],
        hostId: String,
        sessionId: String
    ) -> [RemoteConversationEntry] {
        var hostTranscripts = transcripts[hostId] ?? [:]
        var sessionTranscript = hostTranscripts[sessionId] ?? []
        var insertedEntries: [RemoteConversationEntry] = []

        for entry in entries {
            if let last = sessionTranscript.last,
               last.role == entry.role,
               last.text == entry.text,
               abs(last.timestamp.timeIntervalSince(entry.timestamp)) < 3 {
                continue
            }

            sessionTranscript.append(entry)
            insertedEntries.append(entry)
        }

        hostTranscripts[sessionId] = sessionTranscript
        transcripts[hostId] = hostTranscripts
        return insertedEntries
    }

    private func setTranscript(
        _ entries: [RemoteConversationEntry],
        hostId: String,
        sessionId: String
    ) {
        var hostTranscripts = transcripts[hostId] ?? [:]
        hostTranscripts[sessionId] = entries
        transcripts[hostId] = hostTranscripts
    }

    // MARK: - Helpers

    private func pendingAssistantKey(hostId: String, sessionId: String) -> String {
        "\(hostId)::\(sessionId)"
    }

    private func clearPendingAssistantBuffers(for hostId: String) {
        pendingAssistantBuffers = pendingAssistantBuffers.filter { key, _ in
            !key.hasPrefix("\(hostId)::")
        }
    }

    private func refreshedHost(_ host: PairedRemoteHost) -> PairedRemoteHost {
        PairedRemoteHost(
            id: host.id,
            displayName: host.displayName,
            baseURL: host.baseURL,
            authToken: "",
            pairingCodeHint: host.pairingCodeHint,
            pairedAt: host.pairedAt,
            lastConnectedAt: .now
        )
    }

    private func normalizedBaseURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme,
              let host = components.host,
              scheme == "http" || scheme == "https" else {
            return nil
        }

        components.scheme = scheme
        components.host = host
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func requireHTTPResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteDaemonError.transportUnavailable
        }

        return httpResponse
    }

    private func date(from value: String?) -> Date {
        guard let value else {
            return .now
        }

        return iso8601Formatter.date(from: value) ?? .now
    }
}

public typealias HTTPRemoteDaemonTransport = RemoteDaemonHTTPTransport

private struct RPCRequest<Params: Encodable>: Encodable {
    let id = UUID().uuidString
    let method: String
    let params: Params
}

private struct SessionResponseStub: Decodable {}
