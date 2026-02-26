import Foundation

@MainActor
final class WorkspaceManager: ObservableObject {
    private static let cliMetadataVersion = 1
    private static let iso8601Formatter = ISO8601DateFormatter()

    @Published private(set) var workspaces: [WorkspaceRecord] = []
    @Published private(set) var sessionsForActiveWorkspace: [SessionRecord] = []
    @Published private(set) var activeWorkspace: WorkspaceRecord? {
        didSet {
            onActiveWorkspaceChanged?(activeWorkspace?.url)
        }
    }
    @Published private(set) var activeSession: SessionRecord? {
        didSet {
            onActiveSessionChanged?(activeSession)
        }
    }

    var onActiveWorkspaceChanged: ((URL?) -> Void)?
    var onActiveSessionChanged: ((SessionRecord?) -> Void)?

    private let store: SessionStore
    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let cliMetadataPath: URL
    private var cliMetadataSyncTimer: Timer?
    private var fileMonitor: DispatchSourceFileSystemObject?

    private enum Keys {
        static let activeWorkspaceID = "activeWorkspaceID"
    }

    init(
        store: SessionStore = SessionStore(),
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.cliMetadataPath = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RubberDuck/metadata.json")
        restoreState()
        startCLIMetadataFileMonitor()
    }

    deinit {
        cliMetadataSyncTimer?.invalidate()
        fileMonitor?.cancel()
    }

    // MARK: - Public API

    func attachWorkspace(path: URL) {
        attachWorkspace(path: path, preferredSession: nil)
    }

    private func attachWorkspace(path: URL, preferredSession: CLIMetadataFile.Session?) {
        let normalizedURL = path.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: normalizedURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            logError("WorkspaceManager: Invalid workspace path: \(normalizedURL.path)")
            return
        }

        do {
            let workspace = try store.upsertWorkspace(path: normalizedURL.path)
            let session = try resolveSession(for: workspace, preferredSession: preferredSession)
            userDefaults.set(workspace.id, forKey: Keys.activeWorkspaceID)
            refreshState(selectWorkspaceID: workspace.id, selectSessionID: session.id)
            logInfo("WorkspaceManager: Attached workspace \(workspace.path) with session \(session.name)")
        } catch {
            logError("WorkspaceManager: Failed to attach workspace: \(error.localizedDescription)")
        }
    }

    func createSession(name: String? = nil) {
        guard let workspace = activeWorkspace else {
            logError("WorkspaceManager: Cannot create session without an active workspace")
            return
        }

        do {
            let sessionName = name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? name!.trimmingCharacters(in: .whitespacesAndNewlines)
                : try defaultSessionName(forWorkspaceID: workspace.id)

            let session = try store.createSession(workspaceID: workspace.id, name: sessionName)
            try store.setActiveSession(sessionID: session.id, workspaceID: workspace.id)
            refreshState(selectWorkspaceID: workspace.id, selectSessionID: session.id)
            logInfo("WorkspaceManager: Created session \(session.name)")
        } catch {
            logError("WorkspaceManager: Failed to create session: \(error.localizedDescription)")
        }
    }

    func switchSession(id: String) {
        guard let workspace = activeWorkspace else {
            return
        }

        do {
            guard let session = try store.session(id: id), session.workspaceID == workspace.id else {
                logError("WorkspaceManager: Session \(id) not found in active workspace")
                return
            }
            try store.setActiveSession(sessionID: session.id, workspaceID: workspace.id)
            refreshState(selectWorkspaceID: workspace.id, selectSessionID: session.id)
            logInfo("WorkspaceManager: Switched to session \(session.name)")
        } catch {
            logError("WorkspaceManager: Failed to switch session: \(error.localizedDescription)")
        }
    }

    func switchWorkspace(id: String) {
        do {
            guard let workspace = try store.workspace(id: id) else {
                logError("WorkspaceManager: Workspace \(id) not found")
                return
            }
            let session = try ensureActiveSession(for: workspace)
            userDefaults.set(workspace.id, forKey: Keys.activeWorkspaceID)
            refreshState(selectWorkspaceID: workspace.id, selectSessionID: session.id)
            logInfo("WorkspaceManager: Switched workspace to \(workspace.path)")
        } catch {
            logError("WorkspaceManager: Failed to switch workspace: \(error.localizedDescription)")
        }
    }

    // MARK: - State Restore

    private func restoreState() {
        do {
            if let savedWorkspaceID = userDefaults.string(forKey: Keys.activeWorkspaceID),
               let workspace = try store.workspace(id: savedWorkspaceID) {
                let session = try ensureActiveSession(for: workspace)
                refreshState(selectWorkspaceID: workspace.id, selectSessionID: session.id)
                return
            }

            if let latest = try store.latestWorkspace() {
                let session = try ensureActiveSession(for: latest)
                userDefaults.set(latest.id, forKey: Keys.activeWorkspaceID)
                refreshState(selectWorkspaceID: latest.id, selectSessionID: session.id)
                return
            }

            if let selection = loadCLISelectionFromMetadata() {
                attachWorkspace(path: selection.workspaceURL, preferredSession: selection.session)
                return
            }

            refreshState()
        } catch {
            logError("WorkspaceManager: Failed to restore state: \(error.localizedDescription)")
            refreshState()
        }
    }

    private func startCLIMetadataFileMonitor() {
        let path = cliMetadataPath.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            // File doesn't exist yet, fall back to polling
            startCLIMetadataSyncPolling()
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.syncStateFromCLIMetadataIfNeeded()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileMonitor = source
    }

    private func startCLIMetadataSyncPolling() {
        cliMetadataSyncTimer?.invalidate()
        cliMetadataSyncTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncStateFromCLIMetadataIfNeeded()
            }
        }
    }

    private func syncStateFromCLIMetadataIfNeeded() {
        guard let selection = loadCLISelectionFromMetadata() else {
            return
        }

        let targetPath = selection.workspaceURL.standardizedFileURL.path
        let currentPath = activeWorkspace?.path
        let targetSessionID = selection.session?.id
        let targetSessionName = selection.session?.name?.lowercased()
        let currentSessionName = activeSession?.name.lowercased()

        if currentPath == targetPath {
            if targetSessionID == nil {
                return
            }

            if activeSession?.id == targetSessionID {
                return
            }

            if let targetSessionName, currentSessionName == targetSessionName {
                return
            }
        }

        attachWorkspace(path: selection.workspaceURL, preferredSession: selection.session)
    }

    private func refreshState(selectWorkspaceID: String? = nil, selectSessionID: String? = nil) {
        do {
            let availableWorkspaces = try store.listWorkspaces()
            workspaces = availableWorkspaces
            let allSessions = try availableWorkspaces.flatMap { workspace in
                try store.sessions(workspaceID: workspace.id)
            }

            let resolvedWorkspaceID = selectWorkspaceID
                ?? activeWorkspace?.id
                ?? availableWorkspaces.first?.id

            if let resolvedWorkspaceID {
                activeWorkspace = availableWorkspaces.first(where: { $0.id == resolvedWorkspaceID })
            } else {
                activeWorkspace = nil
            }

            if let workspace = activeWorkspace {
                let sessions = try store.sessions(workspaceID: workspace.id)
                sessionsForActiveWorkspace = sessions

                if let selectSessionID {
                    activeSession = sessions.first(where: { $0.id == selectSessionID })
                } else {
                    activeSession = sessions.first(where: { $0.isActive }) ?? sessions.first
                }
            } else {
                sessionsForActiveWorkspace = []
                activeSession = nil
            }

            syncCLIMetadata(workspaces: availableWorkspaces, sessions: allSessions)
        } catch {
            logError("WorkspaceManager: Failed to refresh state: \(error.localizedDescription)")
            workspaces = []
            sessionsForActiveWorkspace = []
            activeWorkspace = nil
            activeSession = nil
        }
    }

    private func ensureActiveSession(for workspace: WorkspaceRecord) throws -> SessionRecord {
        if let active = try store.activeSession(workspaceID: workspace.id) {
            return active
        }

        let existing = try store.sessions(workspaceID: workspace.id)
        if let firstExisting = existing.first {
            try store.setActiveSession(sessionID: firstExisting.id, workspaceID: workspace.id)
            return firstExisting
        }

        let name = try defaultSessionName(forWorkspaceID: workspace.id)
        let created = try store.createSession(workspaceID: workspace.id, name: name)
        try store.setActiveSession(sessionID: created.id, workspaceID: workspace.id)
        return created
    }

    private func resolveSession(
        for workspace: WorkspaceRecord,
        preferredSession: CLIMetadataFile.Session?
    ) throws -> SessionRecord {
        guard let preferredSession else {
            return try ensureActiveSession(for: workspace)
        }

        if let existingByID = try store.session(id: preferredSession.id),
           existingByID.workspaceID == workspace.id {
            try store.setActiveSession(sessionID: existingByID.id, workspaceID: workspace.id)
            return existingByID
        }

        let normalizedName = preferredSession.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let normalizedName,
           let existingByName = try store.sessions(workspaceID: workspace.id).first(where: {
               $0.name.lowercased() == normalizedName
           }) {
            try store.setActiveSession(sessionID: existingByName.id, workspaceID: workspace.id)
            return existingByName
        }

        let preferredName = preferredSession.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = try defaultSessionName(forWorkspaceID: workspace.id)
        let sessionName = (preferredName?.isEmpty == false) ? preferredName! : fallbackName
        let created = try store.createSession(
            workspaceID: workspace.id,
            name: sessionName,
            sessionID: preferredSession.id
        )
        try store.setActiveSession(sessionID: created.id, workspaceID: workspace.id)
        return created
    }

    private func defaultSessionName(forWorkspaceID workspaceID: String) throws -> String {
        let count = try store.sessions(workspaceID: workspaceID).count + 1
        return "duck-\(count)"
    }

    // MARK: - CLI Metadata Bridge

    private struct CLIMetadataSelection {
        let workspaceURL: URL
        let session: CLIMetadataFile.Session?
    }

    private func loadCLISelectionFromMetadata() -> CLIMetadataSelection? {
        guard let metadata = loadCLIMetadata() else {
            return nil
        }

        if let activeSessionID = metadata.activeVoiceSessionId,
           let session = metadata.sessions.first(where: { $0.id == activeSessionID }),
           let workspace = metadata.workspaces.first(where: { $0.id == session.workspaceId }) {
            return CLIMetadataSelection(
                workspaceURL: URL(fileURLWithPath: workspace.path, isDirectory: true),
                session: session
            )
        }

        if let session = metadata.sessions.max(by: {
            let d0 = $0.lastActiveAt.flatMap { Self.iso8601Formatter.date(from: $0) } ?? .distantPast
            let d1 = $1.lastActiveAt.flatMap { Self.iso8601Formatter.date(from: $0) } ?? .distantPast
            return d0 < d1
        }),
           let workspace = metadata.workspaces.first(where: { $0.id == session.workspaceId }) {
            return CLIMetadataSelection(
                workspaceURL: URL(fileURLWithPath: workspace.path, isDirectory: true),
                session: session
            )
        }

        if let workspace = metadata.workspaces.first {
            return CLIMetadataSelection(
                workspaceURL: URL(fileURLWithPath: workspace.path, isDirectory: true),
                session: nil
            )
        }

        return nil
    }

    private func loadCLIMetadata() -> CLIMetadataFile? {
        guard let data = try? Data(contentsOf: cliMetadataPath),
              let metadata = try? JSONDecoder().decode(CLIMetadataFile.self, from: data) else {
            return nil
        }
        return metadata
    }

    private func syncCLIMetadata(workspaces: [WorkspaceRecord], sessions: [SessionRecord]) {
        do {
            let existing = loadCLIMetadata() ?? CLIMetadataFile(
                version: Self.cliMetadataVersion,
                activeVoiceSessionId: nil,
                workspaces: [],
                sessions: []
            )

            var existingWorkspacesByID: [String: CLIMetadataFile.Workspace] = [:]
            for workspace in existing.workspaces {
                existingWorkspacesByID[workspace.id] = workspace
            }

            var existingSessionsByID: [String: CLIMetadataFile.Session] = [:]
            for session in existing.sessions {
                existingSessionsByID[session.id] = session
            }

            var mergedWorkspaces: [CLIMetadataFile.Workspace] = workspaces.map { workspace in
                let existingWorkspace = existingWorkspacesByID[workspace.id]
                return CLIMetadataFile.Workspace(
                    id: workspace.id,
                    path: workspace.path,
                    createdAt: existingWorkspace?.createdAt ?? Self.iso8601Formatter.string(from: workspace.createdAt),
                    lastActiveSessionId: workspace.lastActiveSessionID
                )
            }

            for workspace in existing.workspaces where
                !mergedWorkspaces.contains(where: { $0.id == workspace.id }) &&
                !mergedWorkspaces.contains(where: { $0.path == workspace.path }) {
                mergedWorkspaces.append(workspace)
            }

            var mergedSessions: [CLIMetadataFile.Session] = sessions.map { session in
                let existingSession = existingSessionsByID[session.id]
                return CLIMetadataFile.Session(
                    id: session.id,
                    workspaceId: session.workspaceID,
                    name: session.name,
                    lastActiveAt: Self.iso8601Formatter.string(from: session.updatedAt),
                    createdAt: existingSession?.createdAt ?? Self.iso8601Formatter.string(from: session.createdAt),
                    isVoiceActive: session.id == activeSession?.id,
                    piSessionFile: existingSession?.piSessionFile ?? ""
                )
            }

            func workspacePath(for workspaceID: String) -> String? {
                if let mergedWorkspace = mergedWorkspaces.first(where: { $0.id == workspaceID }) {
                    return mergedWorkspace.path
                }
                return existingWorkspacesByID[workspaceID]?.path
            }

            for session in existing.sessions where !mergedSessions.contains(where: { $0.id == session.id }) {
                var preserved = session
                preserved.isVoiceActive = activeSession == nil ? (session.isVoiceActive ?? false) : (session.id == activeSession?.id)

                if let preservedPath = workspacePath(for: session.workspaceId),
                   let preservedName = session.name?.lowercased(),
                   mergedSessions.contains(where: { candidate in
                       guard let candidatePath = workspacePath(for: candidate.workspaceId),
                             let candidateName = candidate.name?.lowercased() else {
                           return false
                       }
                       return candidatePath == preservedPath && candidateName == preservedName
                   }) {
                    continue
                }
                mergedSessions.append(preserved)
            }

            let metadata = CLIMetadataFile(
                version: existing.version ?? Self.cliMetadataVersion,
                activeVoiceSessionId: activeSession?.id ?? existing.activeVoiceSessionId,
                workspaces: mergedWorkspaces,
                sessions: mergedSessions
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let data = try encoder.encode(metadata)
            let directory = cliMetadataPath.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: cliMetadataPath, options: .atomic)
        } catch {
            logError("WorkspaceManager: Failed to sync CLI metadata: \(error.localizedDescription)")
        }
    }
}
