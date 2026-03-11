import Foundation

protocol SessionRepository {
    func upsertWorkspace(path: String, displayName: String?) throws -> WorkspaceRecord
    func workspace(id: String) throws -> WorkspaceRecord?
    func workspace(path: String) throws -> WorkspaceRecord?
    func listWorkspaces() throws -> [WorkspaceRecord]
    func latestWorkspace() throws -> WorkspaceRecord?
    func createSession(workspaceID: String, name: String, sessionID: String, historyFile: String?) throws -> SessionRecord
    func session(id: String) throws -> SessionRecord?
    func sessions(workspaceID: String) throws -> [SessionRecord]
    func activeSession(workspaceID: String) throws -> SessionRecord?
    func setActiveSession(sessionID: String, workspaceID: String) throws
    func touchSession(id: String) throws
}

extension SessionRepository {
    func upsertWorkspace(path: String) throws -> WorkspaceRecord {
        try upsertWorkspace(path: path, displayName: nil)
    }

    func createSession(workspaceID: String, name: String) throws -> SessionRecord {
        try createSession(workspaceID: workspaceID, name: name, sessionID: UUID().uuidString, historyFile: nil)
    }

    func createSession(workspaceID: String, name: String, sessionID: String) throws -> SessionRecord {
        try createSession(workspaceID: workspaceID, name: name, sessionID: sessionID, historyFile: nil)
    }
}

extension SessionStore: SessionRepository {}
