import Combine
import Foundation

private let defaultDirectRemotePort = 43_111

@MainActor
public final class RemoteDaemonAppModel: ObservableObject, @unchecked Sendable {
    @Published public private(set) var pairingSnapshot: RemotePairingSnapshot
    @Published public private(set) var connectionState: RemoteConnectionState = .idle
    @Published public private(set) var activeHost: PairedRemoteHost?
    @Published public private(set) var activeSession: RemoteSessionSummary?
    @Published public private(set) var sessions: [RemoteSessionSummary] = []
    @Published public private(set) var conversation: [RemoteConversationEntry] = []
    @Published public private(set) var voiceState: RemoteDaemonVoiceState = .idle
    @Published public private(set) var lastVoiceControlEvent: RemoteVoiceControlEvent?
    @Published public private(set) var lastVoiceControlEventSequence = 0
    @Published public private(set) var isBootstrapped = false
    @Published public private(set) var lastSyncedAt: Date?
    @Published public var draftMessage = ""
    @Published public var lastError: String?

    private let transport: any RemoteDaemonTransport
    private let pairingStore: RemotePairingStore

    public init(
        transport: any RemoteDaemonTransport,
        pairingStore: RemotePairingStore = RemotePairingStore()
    ) {
        self.transport = transport
        self.pairingStore = pairingStore
        self.pairingSnapshot = pairingStore.load()
        self.activeHost = pairingSnapshot.hosts.first(where: { $0.id == pairingSnapshot.selectedHostID })
    }

    public var hasPairedHosts: Bool {
        !pairingSnapshot.hosts.isEmpty
    }

    public var selectedHostName: String {
        activeHost?.displayName ?? "No Mac paired"
    }

    public func boot() async {
        let snapshot = pairingStore.load()
        pairingSnapshot = snapshot
        activeHost = snapshot.hosts.first(where: { $0.id == snapshot.selectedHostID })

        if let bookmark = snapshot.sessionBookmark {
            activeSession = RemoteSessionSummary(
                id: bookmark.sessionID ?? "pending",
                name: bookmark.sessionName ?? "Resuming session",
                workspacePath: bookmark.workspacePath ?? "",
                isActive: true,
                isRunning: true,
                lastActiveAt: bookmark.updatedAt
            )
        }

        if activeHost != nil {
            await refresh()
        } else {
            isBootstrapped = true
        }
    }

    public func pair(
        hostURLString: String,
        displayName: String,
        authToken: String
    ) async {
        guard let hostURL = normalizedHostURL(from: hostURLString) else {
            lastError = RemoteDaemonError.invalidHostURL.localizedDescription
            connectionState = .failed
            return
        }

        guard !authToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = RemoteDaemonError.invalidAuthToken.localizedDescription
            connectionState = .failed
            return
        }

        connectionState = .pairing
        lastError = nil

        do {
            let previousHost = activeHost
            let host = try await transport.pair(
                hostURL: hostURL,
                displayName: displayName,
                authToken: authToken
            )

            if let previousHost, previousHost.id != host.id {
                await transport.unsubscribe(from: previousHost)
            }

            var snapshot = pairingSnapshot
            snapshot.hosts.removeAll(where: { $0.id == host.id })
            snapshot.hosts.insert(host, at: 0)
            snapshot.selectedHostID = host.id
            pairingSnapshot = snapshot
            activeHost = host

            try pairingStore.save(snapshot)
            await refresh()
        } catch {
            connectionState = .failed
            lastError = error.localizedDescription
        }
    }

    private func normalizedHostURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmed),
           let scheme = url.scheme,
           !scheme.isEmpty {
            return normalizedHostURL(url)
        }

        let inferredScheme = trimmed.lowercased().contains(".ts.net")
            ? "https"
            : "http"

        guard let url = URL(string: "\(inferredScheme)://\(trimmed)") else {
            return nil
        }

        return normalizedHostURL(url)
    }

    private func normalizedHostURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawScheme = components.scheme?.lowercased(),
              let host = components.host,
              rawScheme == "http" || rawScheme == "https" else {
            return nil
        }

        components.scheme = rawScheme
        components.host = host
        components.path = ""
        components.query = nil
        components.fragment = nil

        if rawScheme == "http" && components.port == nil {
            components.port = defaultDirectRemotePort
        }

        return components.url
    }

    public func selectHost(_ host: PairedRemoteHost) async {
        if let currentHost = activeHost, currentHost.id != host.id {
            await transport.unsubscribe(from: currentHost)
        }

        activeHost = host
        activeSession = nil
        conversation = []
        voiceState = .idle

        var snapshot = pairingSnapshot
        snapshot.selectedHostID = host.id
        pairingSnapshot = snapshot

        do {
            try pairingStore.save(snapshot)
        } catch {
            lastError = error.localizedDescription
        }

        await refresh()
    }

    public func refresh() async {
        guard let activeHost else {
            connectionState = .idle
            return
        }

        connectionState = .connecting
        lastError = nil

        do {
            let snapshot = try await transport.loadSnapshot(for: activeHost)
            apply(snapshot: snapshot)

            if let sessionToResume = preferredSession(from: snapshot) {
                let initialConversation = sessionToResume.id == snapshot.activeSession?.id
                    ? snapshot.conversation
                    : nil
                try await present(sessionToResume, on: snapshot.host, initialConversation: initialConversation)
            } else {
                await transport.unsubscribe(from: snapshot.host)
            }

            connectionState = .connected
            isBootstrapped = true
            saveBookmark()
        } catch {
            connectionState = .failed
            isBootstrapped = true
            lastError = error.localizedDescription
        }
    }

    public func openSession(_ session: RemoteSessionSummary) async {
        guard let activeHost else {
            lastError = RemoteDaemonError.noPairedHost.localizedDescription
            return
        }

        do {
            let activatedSession = try await transport.activateSession(session, on: activeHost)
            let refreshedSnapshot = try await transport.loadSnapshot(for: activeHost)
            apply(snapshot: refreshedSnapshot)

            let sessionToPresent = refreshedSnapshot.sessions.first(where: { $0.id == activatedSession.id }) ?? activatedSession
            try await present(sessionToPresent, on: refreshedSnapshot.host)

            connectionState = .connected
            saveBookmark()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func sendDraft() async {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        guard let activeHost else {
            lastError = RemoteDaemonError.noPairedHost.localizedDescription
            return
        }

        guard let activeSession else {
            lastError = RemoteDaemonError.noActiveSession.localizedDescription
            return
        }

        draftMessage = ""
        do {
            let appendedEntry = try await transport.sendMessage(
                trimmed,
                session: activeSession,
                on: activeHost
            )
            appendDeduplicated([appendedEntry])
            voiceState = .thinking
            lastSyncedAt = .now
            saveBookmark()
        } catch {
            draftMessage = trimmed
            lastError = error.localizedDescription
        }
    }

    public func dismissError() {
        lastError = nil
    }

    public func clearVoiceControlEvent() {
        lastVoiceControlEvent = nil
    }

    public func connectVoiceClient(clientVersion: String) async throws {
        guard let activeHost else {
            throw RemoteDaemonError.noPairedHost
        }

        guard let activeSession else {
            throw RemoteDaemonError.noActiveSession
        }

        try await transport.connectVoiceClient(
            on: activeHost,
            session: activeSession,
            clientVersion: clientVersion
        )
    }

    public func startVoiceSession() async throws {
        guard let activeHost else {
            throw RemoteDaemonError.noPairedHost
        }

        guard let activeSession else {
            throw RemoteDaemonError.noActiveSession
        }

        try await transport.startVoiceSession(activeSession, on: activeHost)
    }

    public func updateVoiceState(_ state: RemoteDaemonVoiceState) async throws {
        guard let activeHost else {
            throw RemoteDaemonError.noPairedHost
        }

        guard let activeSession else {
            throw RemoteDaemonError.noActiveSession
        }

        voiceState = state
        try await transport.updateVoiceState(
            state,
            session: activeSession,
            on: activeHost
        )
    }

    public func executeVoiceToolCall(
        callId: String,
        toolName: String,
        arguments: String
    ) async throws -> String {
        guard let activeHost else {
            throw RemoteDaemonError.noPairedHost
        }

        guard let activeSession else {
            throw RemoteDaemonError.noActiveSession
        }

        return try await transport.executeVoiceToolCall(
            callId: callId,
            toolName: toolName,
            arguments: arguments,
            session: activeSession,
            on: activeHost
        )
    }

    public func consumeVoiceControlEvent() {
        lastVoiceControlEvent = nil
    }

    public func appendLiveConversationEntry(_ entry: RemoteConversationEntry) {
        appendDeduplicated([entry])
        lastSyncedAt = .now
    }

    public func appendLiveConversationEntries(_ entries: [RemoteConversationEntry]) {
        appendDeduplicated(entries)
        lastSyncedAt = .now
    }

    private func present(
        _ session: RemoteSessionSummary,
        on host: PairedRemoteHost,
        initialConversation: [RemoteConversationEntry]? = nil
    ) async throws {
        let renderedConversation: [RemoteConversationEntry]
        if let initialConversation {
            renderedConversation = initialConversation
        } else {
            renderedConversation = try await transport.loadConversation(
                for: session,
                on: host,
                limit: 200
            )
        }

        activeHost = host
        activeSession = session
        conversation = renderedConversation
        sessions = sessions.map { item in
            RemoteSessionSummary(
                id: item.id,
                name: item.name,
                workspacePath: item.workspacePath,
                isActive: item.id == session.id,
                isRunning: item.id == session.id ? session.isRunning : item.isRunning,
                lastActiveAt: item.id == session.id ? session.lastActiveAt : item.lastActiveAt
            )
        }
        voiceState = session.isRunning ? .listening : .idle
        lastSyncedAt = .now
        saveBookmark()

        try await transport.subscribe(
            to: session,
            on: host,
            handler: makeStreamHandler(hostID: host.id, sessionID: session.id)
        )
    }

    private func preferredSession(from snapshot: RemoteDaemonSnapshot) -> RemoteSessionSummary? {
        if let bookmark = pairingSnapshot.sessionBookmark,
           bookmark.hostID == snapshot.host.id,
           let bookmarkedSessionID = bookmark.sessionID,
           let bookmarkedSession = snapshot.sessions.first(where: { $0.id == bookmarkedSessionID }) {
            return bookmarkedSession
        }

        return snapshot.activeSession
    }

    private func makeStreamHandler(
        hostID: String,
        sessionID: String
    ) -> @Sendable (RemoteDaemonStreamUpdate) -> Void {
        { [weak self] update in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                guard self.activeHost?.id == hostID,
                      self.activeSession?.id == sessionID else {
                    return
                }

                self.apply(streamUpdate: update)
            }
        }
    }

    private func apply(snapshot: RemoteDaemonSnapshot) {
        activeHost = snapshot.host
        activeSession = snapshot.activeSession
        sessions = snapshot.sessions
        conversation = snapshot.conversation
        voiceState = snapshot.voiceState
        lastSyncedAt = snapshot.lastSyncedAt

        var persisted = pairingSnapshot
        persisted.hosts.removeAll(where: { $0.id == snapshot.host.id })
        persisted.hosts.insert(snapshot.host, at: 0)
        persisted.selectedHostID = snapshot.host.id
        pairingSnapshot = persisted

        do {
            try pairingStore.save(persisted)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func apply(streamUpdate: RemoteDaemonStreamUpdate) {
        switch streamUpdate {
        case .appendEntries(let entries):
            appendDeduplicated(entries)
            lastSyncedAt = .now

        case .setVoiceState(let voiceState):
            self.voiceState = voiceState
            lastSyncedAt = .now

        case .notice(let message):
            appendDeduplicated([
                RemoteConversationEntry(
                    role: .status,
                    text: message,
                    timestamp: .now,
                    metadata: ["source": "remote"]
                )
            ])
            lastSyncedAt = .now

        case .voiceControl(let event):
            lastVoiceControlEvent = event
            lastVoiceControlEventSequence += 1
            lastSyncedAt = .now

        case .sessionChanged(let sessionID, let sessionName, let workspacePath):
            lastSyncedAt = .now
            Task {
                await handleRemoteSessionChange(
                    sessionID: sessionID,
                    sessionName: sessionName,
                    workspacePath: workspacePath
                )
            }
        }
    }

    private func handleRemoteSessionChange(
        sessionID: String,
        sessionName: String?,
        workspacePath: String?
    ) async {
        guard let activeHost else {
            return
        }

        do {
            let snapshot = try await transport.loadSnapshot(for: activeHost)
            apply(snapshot: snapshot)

            let nextSession =
                snapshot.sessions.first(where: { $0.id == sessionID }) ??
                snapshot.activeSession ??
                RemoteSessionSummary(
                    id: sessionID,
                    name: sessionName ?? "Active session",
                    workspacePath: workspacePath ?? "",
                    isActive: true,
                    isRunning: true,
                    lastActiveAt: .now
                )

            let initialConversation = nextSession.id == snapshot.activeSession?.id
                ? snapshot.conversation
                : nil
            try await present(
                nextSession,
                on: snapshot.host,
                initialConversation: initialConversation
            )
            connectionState = .connected
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func appendDeduplicated(_ entries: [RemoteConversationEntry]) {
        for entry in entries {
            if let last = conversation.last,
               last.role == entry.role,
               last.text == entry.text,
               abs(last.timestamp.timeIntervalSince(entry.timestamp)) < 3 {
                continue
            }

            conversation.append(entry)
        }
    }

    private func saveBookmark() {
        guard let activeHost else {
            return
        }

        var snapshot = pairingSnapshot
        snapshot.sessionBookmark = RemoteSessionBookmark(
            hostID: activeHost.id,
            sessionID: activeSession?.id,
            sessionName: activeSession?.name,
            workspacePath: activeSession?.workspacePath,
            updatedAt: .now
        )
        pairingSnapshot = snapshot

        do {
            try pairingStore.save(snapshot)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
