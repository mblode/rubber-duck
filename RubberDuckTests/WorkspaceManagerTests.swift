import XCTest
@testable import RubberDuck

@MainActor
final class WorkspaceManagerTests: XCTestCase {

    // MARK: - Mock

    private final class MockSessionRepository: SessionRepository {
        var workspacesByID: [String: WorkspaceRecord] = [:]
        var sessionsByID: [String: SessionRecord] = [:]

        func upsertWorkspace(path: String, displayName: String?) throws -> WorkspaceRecord {
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            if let existing = workspacesByID.values.first(where: { $0.path == normalizedPath }) {
                return existing
            }
            let id = "ws-\(workspacesByID.count + 1)"
            let name = displayName ?? URL(fileURLWithPath: normalizedPath).lastPathComponent
            let record = WorkspaceRecord(
                id: id,
                path: normalizedPath,
                displayName: name,
                lastActiveSessionID: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
            workspacesByID[id] = record
            return record
        }

        func workspace(id: String) throws -> WorkspaceRecord? {
            workspacesByID[id]
        }

        func workspace(path: String) throws -> WorkspaceRecord? {
            workspacesByID.values.first(where: { $0.path == path })
        }

        func listWorkspaces() throws -> [WorkspaceRecord] {
            Array(workspacesByID.values).sorted { $0.updatedAt > $1.updatedAt }
        }

        func latestWorkspace() throws -> WorkspaceRecord? {
            try listWorkspaces().first
        }

        func createSession(workspaceID: String, name: String, sessionID: String, historyFile: String?) throws -> SessionRecord {
            if let existing = sessionsByID[sessionID] {
                return existing
            }
            let record = SessionRecord(
                id: sessionID,
                workspaceID: workspaceID,
                name: name,
                historyFile: historyFile ?? "/tmp/\(sessionID).jsonl",
                createdAt: Date(),
                updatedAt: Date(),
                isActive: false
            )
            sessionsByID[sessionID] = record
            return record
        }

        func session(id: String) throws -> SessionRecord? {
            sessionsByID[id]
        }

        func sessions(workspaceID: String) throws -> [SessionRecord] {
            sessionsByID.values
                .filter { $0.workspaceID == workspaceID }
                .sorted { $0.updatedAt > $1.updatedAt }
        }

        func activeSession(workspaceID: String) throws -> SessionRecord? {
            sessionsByID.values.first(where: { $0.workspaceID == workspaceID && $0.isActive })
        }

        func setActiveSession(sessionID: String, workspaceID: String) throws {
            for (id, session) in sessionsByID where session.workspaceID == workspaceID {
                sessionsByID[id] = SessionRecord(
                    id: session.id,
                    workspaceID: session.workspaceID,
                    name: session.name,
                    historyFile: session.historyFile,
                    createdAt: session.createdAt,
                    updatedAt: session.updatedAt,
                    isActive: session.id == sessionID
                )
            }
            if let ws = workspacesByID[workspaceID] {
                workspacesByID[workspaceID] = WorkspaceRecord(
                    id: ws.id,
                    path: ws.path,
                    displayName: ws.displayName,
                    lastActiveSessionID: sessionID,
                    createdAt: ws.createdAt,
                    updatedAt: Date()
                )
            }
        }

        func touchSession(id: String) throws {
            guard let session = sessionsByID[id] else { return }
            sessionsByID[id] = SessionRecord(
                id: session.id,
                workspaceID: session.workspaceID,
                name: session.name,
                historyFile: session.historyFile,
                createdAt: session.createdAt,
                updatedAt: Date(),
                isActive: session.isActive
            )
        }
    }

    // MARK: - Helpers

    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WorkspaceManagerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    private func makeWorkspacePath(name: String = "test-project") -> URL {
        let path = tempDirectory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    private func makeManager(store: MockSessionRepository) -> WorkspaceManager {
        let defaults = UserDefaults(suiteName: "WorkspaceManagerTests-\(UUID().uuidString)")!
        return WorkspaceManager(store: store, userDefaults: defaults, fileManager: .default)
    }

    // MARK: - Tests

    func test_attachWorkspace_createsWorkspaceAndSession() {
        let store = MockSessionRepository()
        let manager = makeManager(store: store)
        let path = makeWorkspacePath()

        manager.attachWorkspace(path: path)

        XCTAssertNotNil(manager.activeWorkspace, "Active workspace should be set after attach")
        XCTAssertEqual(manager.activeWorkspace?.path, path.standardizedFileURL.path)
        XCTAssertNotNil(manager.activeSession, "Active session should be created for new workspace")
        XCTAssertEqual(manager.activeSession?.name, "duck-1")
    }

    func test_attachWorkspace_returnsExistingWorkspace() {
        let store = MockSessionRepository()
        let manager = makeManager(store: store)
        let path = makeWorkspacePath()

        manager.attachWorkspace(path: path)
        let firstWorkspaceID = manager.activeWorkspace?.id

        manager.attachWorkspace(path: path)
        XCTAssertEqual(manager.activeWorkspace?.id, firstWorkspaceID, "Attaching same path should return same workspace")
    }

    func test_switchSession_updatesActiveSession() {
        let store = MockSessionRepository()
        let manager = makeManager(store: store)
        let path = makeWorkspacePath()

        manager.attachWorkspace(path: path)
        let firstSessionID = manager.activeSession?.id
        XCTAssertNotNil(firstSessionID)

        manager.createSession(name: "duck-2")
        let secondSessionID = manager.activeSession?.id
        XCTAssertNotNil(secondSessionID)
        XCTAssertNotEqual(firstSessionID, secondSessionID)
        XCTAssertEqual(manager.activeSession?.name, "duck-2")

        manager.switchSession(id: firstSessionID!)
        XCTAssertEqual(manager.activeSession?.id, firstSessionID, "Should switch back to first session")
    }

    func test_restoreState_restoresLastActiveSession() {
        let store = MockSessionRepository()
        let defaults = UserDefaults(suiteName: "WorkspaceManagerTests-\(UUID().uuidString)")!
        let path = makeWorkspacePath()

        // First manager creates the workspace + session
        let manager1 = WorkspaceManager(store: store, userDefaults: defaults, fileManager: .default)
        manager1.attachWorkspace(path: path)
        let workspaceID = manager1.activeWorkspace?.id
        let sessionID = manager1.activeSession?.id
        XCTAssertNotNil(workspaceID)
        XCTAssertNotNil(sessionID)

        // Second manager with same store + defaults should restore
        let manager2 = WorkspaceManager(store: store, userDefaults: defaults, fileManager: .default)
        XCTAssertEqual(manager2.activeWorkspace?.id, workspaceID, "Should restore workspace from UserDefaults")
        XCTAssertEqual(manager2.activeSession?.id, sessionID, "Should restore active session")
    }

    func test_createSession_incrementsName() {
        let store = MockSessionRepository()
        let manager = makeManager(store: store)
        let path = makeWorkspacePath()

        manager.attachWorkspace(path: path)
        XCTAssertEqual(manager.activeSession?.name, "duck-1")

        manager.createSession()
        XCTAssertEqual(manager.activeSession?.name, "duck-2")

        manager.createSession()
        XCTAssertEqual(manager.activeSession?.name, "duck-3")
    }

    func test_createSession_withCustomName() {
        let store = MockSessionRepository()
        let manager = makeManager(store: store)
        let path = makeWorkspacePath()

        manager.attachWorkspace(path: path)
        manager.createSession(name: "my-feature")
        XCTAssertEqual(manager.activeSession?.name, "my-feature")
    }

    func test_switchWorkspace_changesActiveWorkspace() {
        let store = MockSessionRepository()
        let manager = makeManager(store: store)
        let path1 = makeWorkspacePath(name: "project-a")
        let path2 = makeWorkspacePath(name: "project-b")

        manager.attachWorkspace(path: path1)
        let ws1ID = manager.activeWorkspace?.id
        XCTAssertNotNil(ws1ID)

        manager.attachWorkspace(path: path2)
        let ws2ID = manager.activeWorkspace?.id
        XCTAssertNotNil(ws2ID)
        XCTAssertNotEqual(ws1ID, ws2ID)

        manager.switchWorkspace(id: ws1ID!)
        XCTAssertEqual(manager.activeWorkspace?.id, ws1ID)
    }
}
