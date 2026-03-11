import Foundation

public enum RemoteConnectionState: String, Codable, Equatable, Sendable {
    case idle
    case pairing
    case connecting
    case connected
    case failed
}

public enum RemoteDaemonVoiceState: String, Codable, Equatable, Sendable {
    case idle
    case connecting
    case listening
    case thinking
    case speaking
    case toolRunning
}

public enum RemoteDaemonStreamUpdate: Equatable, Sendable {
    case appendEntries([RemoteConversationEntry])
    case setVoiceState(RemoteDaemonVoiceState)
    case notice(String)
    case voiceControl(RemoteVoiceControlEvent)
    case sessionChanged(
        sessionID: String,
        sessionName: String?,
        workspacePath: String?
    )
}

public enum RemoteVoiceControlEvent: Equatable, Sendable {
    case ready(clientID: String)
    case start(sessionID: String?)
    case stop(sessionID: String?, reason: String?)
    case say(text: String, sessionID: String?)
}

public struct PairedRemoteHost: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let baseURL: URL
    public let authToken: String
    public let pairingCodeHint: String
    public let pairedAt: Date
    public var lastConnectedAt: Date?

    public init(
        id: String,
        displayName: String,
        baseURL: URL,
        authToken: String,
        pairingCodeHint: String,
        pairedAt: Date = .now,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.authToken = authToken
        self.pairingCodeHint = pairingCodeHint
        self.pairedAt = pairedAt
        self.lastConnectedAt = lastConnectedAt
    }

    public var subtitle: String {
        baseURL.host ?? baseURL.absoluteString
    }
}

public struct RemoteSessionSummary: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let workspacePath: String
    public let isActive: Bool
    public let isRunning: Bool
    public let lastActiveAt: Date

    public init(
        id: String,
        name: String,
        workspacePath: String,
        isActive: Bool,
        isRunning: Bool,
        lastActiveAt: Date
    ) {
        self.id = id
        self.name = name
        self.workspacePath = workspacePath
        self.isActive = isActive
        self.isRunning = isRunning
        self.lastActiveAt = lastActiveAt
    }
}

public struct RemoteDaemonSnapshot: Equatable, Sendable {
    public let host: PairedRemoteHost
    public let activeSession: RemoteSessionSummary?
    public let sessions: [RemoteSessionSummary]
    public let conversation: [RemoteConversationEntry]
    public let voiceState: RemoteDaemonVoiceState
    public let lastSyncedAt: Date

    public init(
        host: PairedRemoteHost,
        activeSession: RemoteSessionSummary?,
        sessions: [RemoteSessionSummary],
        conversation: [RemoteConversationEntry],
        voiceState: RemoteDaemonVoiceState,
        lastSyncedAt: Date = .now
    ) {
        self.host = host
        self.activeSession = activeSession
        self.sessions = sessions
        self.conversation = conversation
        self.voiceState = voiceState
        self.lastSyncedAt = lastSyncedAt
    }
}

public enum RemoteDaemonError: Error, LocalizedError, Equatable {
    case invalidHostURL
    case invalidAuthToken
    case noPairedHost
    case noActiveSession
    case remoteDisabled
    case remoteNotListening
    case transportUnavailable
    case unauthorized
    case unknownSession(String)
    case websocketUnavailable
    case messageFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHostURL:
            return "Enter a host, IP, or daemon URL such as linktree, 100.96.185.34, or https://your-mac.tailnet.ts.net."
        case .invalidAuthToken:
            return "Enter the remote access token from your Mac."
        case .noPairedHost:
            return "Pair with a Mac before resuming a session."
        case .noActiveSession:
            return "No active daemon session is available yet."
        case .remoteDisabled:
            return "Remote control is disabled on that daemon."
        case .remoteNotListening:
            return "The daemon remote surface is not listening yet."
        case .transportUnavailable:
            return "The remote daemon transport is not available."
        case .unauthorized:
            return "The daemon rejected the access token."
        case .unknownSession(let sessionID):
            return "Unknown session: \(sessionID)"
        case .websocketUnavailable:
            return "The daemon did not expose a WebSocket follow URL."
        case .messageFailed(let message):
            return message
        }
    }
}

public protocol RemoteDaemonTransport: Sendable {
    func pair(
        hostURL: URL,
        displayName: String,
        authToken: String
    ) async throws -> PairedRemoteHost

    func activateSession(
        _ session: RemoteSessionSummary,
        on host: PairedRemoteHost
    ) async throws -> RemoteSessionSummary

    func loadSnapshot(for host: PairedRemoteHost) async throws -> RemoteDaemonSnapshot

    func loadConversation(
        for session: RemoteSessionSummary,
        on host: PairedRemoteHost,
        limit: Int
    ) async throws -> [RemoteConversationEntry]

    func sendMessage(
        _ message: String,
        session: RemoteSessionSummary,
        on host: PairedRemoteHost
    ) async throws -> RemoteConversationEntry

    func subscribe(
        to session: RemoteSessionSummary,
        on host: PairedRemoteHost,
        handler: @escaping @Sendable (RemoteDaemonStreamUpdate) -> Void
    ) async throws

    func connectVoiceClient(
        on host: PairedRemoteHost,
        session: RemoteSessionSummary,
        clientVersion: String
    ) async throws

    func startVoiceSession(
        _ session: RemoteSessionSummary,
        on host: PairedRemoteHost
    ) async throws

    func updateVoiceState(
        _ state: RemoteDaemonVoiceState,
        session: RemoteSessionSummary,
        on host: PairedRemoteHost
    ) async throws

    func executeVoiceToolCall(
        callId: String,
        toolName: String,
        arguments: String,
        session: RemoteSessionSummary,
        on host: PairedRemoteHost
    ) async throws -> String

    func unsubscribe(from host: PairedRemoteHost) async
}

public enum RemoteDaemonTransportFactory {
    public static func live() -> any RemoteDaemonTransport {
        RemoteDaemonHTTPTransport()
    }

    public static func mock() -> any RemoteDaemonTransport {
        MockRemoteDaemonTransport()
    }
}

public actor MockRemoteDaemonTransport: RemoteDaemonTransport {
    private struct HostState: Sendable {
        var host: PairedRemoteHost
        var activeSessionID: String
        var sessions: [RemoteSessionSummary]
        var conversations: [String: [RemoteConversationEntry]]
        var voiceState: RemoteDaemonVoiceState
        var handler: (@Sendable (RemoteDaemonStreamUpdate) -> Void)?
    }

    private var hosts: [String: HostState] = [:]

    public init() {}

    public func pair(
        hostURL: URL,
        displayName: String,
        authToken: String
    ) async throws -> PairedRemoteHost {
        guard let scheme = hostURL.scheme,
              scheme == "http" || scheme == "https" else {
            throw RemoteDaemonError.invalidHostURL
        }

        let normalizedToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else {
            throw RemoteDaemonError.invalidAuthToken
        }

        let host = PairedRemoteHost(
            id: hostURL.absoluteString.lowercased(),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (hostURL.host ?? "Rubber Duck Mac")
                : displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: hostURL,
            authToken: normalizedToken,
            pairingCodeHint: String(normalizedToken.suffix(4)).uppercased(),
            pairedAt: .now,
            lastConnectedAt: .now
        )

        hosts[host.id] = makeDefaultState(for: host)
        return host
    }

    public func activateSession(
        _ session: RemoteSessionSummary,
        on host: PairedRemoteHost
    ) async throws -> RemoteSessionSummary {
        var state = hosts[host.id] ?? makeDefaultState(for: host)

        guard state.sessions.contains(where: { $0.id == session.id }) else {
            throw RemoteDaemonError.unknownSession(session.id)
        }

        state.activeSessionID = session.id
        state.voiceState = RemoteDaemonVoiceState.listening
        state.sessions = state.sessions.map { item in
            RemoteSessionSummary(
                id: item.id,
                name: item.name,
                workspacePath: item.workspacePath,
                isActive: item.id == session.id,
                isRunning: item.id == session.id ? true : item.isRunning,
                lastActiveAt: item.id == session.id ? .now : item.lastActiveAt
            )
        }
        hosts[host.id] = state

        return state.sessions.first(where: { $0.id == session.id }) ?? session
    }

    public func loadSnapshot(for host: PairedRemoteHost) async throws -> RemoteDaemonSnapshot {
        let state = hosts[host.id] ?? makeDefaultState(for: host)
        hosts[host.id] = state

        let activeSession = state.sessions.first(where: { $0.id == state.activeSessionID })
        let conversation = state.conversations[state.activeSessionID] ?? []

        return RemoteDaemonSnapshot(
            host: state.host,
            activeSession: activeSession,
            sessions: state.sessions.sorted(by: { $0.lastActiveAt > $1.lastActiveAt }),
            conversation: conversation,
            voiceState: state.voiceState
        )
    }

    public func loadConversation(
        for session: RemoteSessionSummary,
        on host: PairedRemoteHost,
        limit: Int
    ) async throws -> [RemoteConversationEntry] {
        let state = hosts[host.id] ?? makeDefaultState(for: host)
        hosts[host.id] = state

        guard let conversation = state.conversations[session.id] else {
            throw RemoteDaemonError.unknownSession(session.id)
        }

        return Array(conversation.suffix(max(limit, 1)))
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

        guard var state = hosts[host.id] else {
            throw RemoteDaemonError.transportUnavailable
        }

        let userEntry = RemoteConversationEntry(
            role: .user,
            text: trimmed,
            timestamp: .now
        )
        let assistantEntry = RemoteConversationEntry(
            role: .assistant,
            text: "Mock daemon reply from \(host.displayName): I resumed \(session.name) and captured your prompt for the live transport.",
            timestamp: .now.addingTimeInterval(0.5),
            metadata: ["transport": "mock"]
        )

        state.conversations[session.id, default: []].append(userEntry)
        state.conversations[session.id, default: []].append(assistantEntry)
        state.activeSessionID = session.id
        state.voiceState = .listening
        state.handler?(.appendEntries([assistantEntry]))
        state.handler?(.setVoiceState(.listening))
        hosts[host.id] = state
        return userEntry
    }

    public func subscribe(
        to session: RemoteSessionSummary,
        on host: PairedRemoteHost,
        handler: @escaping @Sendable (RemoteDaemonStreamUpdate) -> Void
    ) async throws {
        guard var state = hosts[host.id] else {
            throw RemoteDaemonError.transportUnavailable
        }

        state.activeSessionID = session.id
        state.handler = handler
        state.voiceState = .listening
        hosts[host.id] = state
        handler(.setVoiceState(.listening))
    }

    public func connectVoiceClient(
        on host: PairedRemoteHost,
        session: RemoteSessionSummary,
        clientVersion: String
    ) async throws {
        guard var state = hosts[host.id] else {
            throw RemoteDaemonError.transportUnavailable
        }

        state.activeSessionID = session.id
        let handler = state.handler
        hosts[host.id] = state
        _ = clientVersion
        handler?(.voiceControl(.ready(clientID: "mock-\(host.id)")))
    }

    public func startVoiceSession(
        _ session: RemoteSessionSummary,
        on host: PairedRemoteHost
    ) async throws {
        guard var state = hosts[host.id] else {
            throw RemoteDaemonError.transportUnavailable
        }

        state.activeSessionID = session.id
        state.voiceState = .listening
        let handler = state.handler
        hosts[host.id] = state
        handler?(.voiceControl(.start(sessionID: session.id)))
        handler?(.setVoiceState(.listening))
    }

    public func updateVoiceState(
        _ stateValue: RemoteDaemonVoiceState,
        session: RemoteSessionSummary,
        on host: PairedRemoteHost
    ) async throws {
        guard var state = hosts[host.id] else {
            throw RemoteDaemonError.transportUnavailable
        }

        state.activeSessionID = session.id
        state.voiceState = stateValue
        let handler = state.handler
        hosts[host.id] = state
        handler?(.setVoiceState(stateValue))
    }

    public func executeVoiceToolCall(
        callId: String,
        toolName: String,
        arguments: String,
        session: RemoteSessionSummary,
        on host: PairedRemoteHost
    ) async throws -> String {
        _ = callId
        _ = session
        _ = host
        return "Mock \(toolName) result for \(arguments)"
    }

    public func unsubscribe(from host: PairedRemoteHost) async {
        guard var state = hosts[host.id] else {
            return
        }

        state.handler = nil
        state.voiceState = .idle
        hosts[host.id] = state
    }

    private func makeDefaultState(for host: PairedRemoteHost) -> HostState {
        let primarySession = RemoteSessionSummary(
            id: "duck-remote-1",
            name: "duck-remote-1",
            workspacePath: "/Users/mblode/Code/mblode/rubber-duck",
            isActive: true,
            isRunning: true,
            lastActiveAt: .now.addingTimeInterval(-60)
        )

        let conversation = [
            RemoteConversationEntry(
                role: .assistant,
                text: "Remote bridge paired. Resume requests will reconnect to the active daemon session.",
                timestamp: .now.addingTimeInterval(-120)
            )
        ]

        return HostState(
            host: host,
            activeSessionID: primarySession.id,
            sessions: [primarySession],
            conversations: [primarySession.id: conversation],
            voiceState: .listening,
            handler: nil
        )
    }
}
