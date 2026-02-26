import Foundation
import CryptoKit
import SQLite3

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct WorkspaceRecord: Identifiable, Hashable {
    let id: String
    let path: String
    let displayName: String
    let lastActiveSessionID: String?
    let createdAt: Date
    let updatedAt: Date

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }
}

struct SessionRecord: Identifiable, Hashable {
    let id: String
    let workspaceID: String
    let name: String
    let historyFile: String
    let createdAt: Date
    let updatedAt: Date
    let isActive: Bool
}

enum SessionStoreError: Error {
    case databaseUnavailable
    case sqliteError(String)
}

final class SessionStore {
    private var db: OpaquePointer?
    private let fileManager: FileManager
    private let databaseURL: URL
    private let sessionsDirectoryURL: URL
    private let queue = DispatchQueue(label: "co.blode.rubber-duck.session-store")

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let sessionsDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RubberDuck/sessions", isDirectory: true)
        self.databaseURL = sessionsDirectory.appendingPathComponent("metadata.sqlite")
        self.sessionsDirectoryURL = sessionsDirectory

        do {
            try prepareDatabase(at: sessionsDirectory)
            logInfo("SessionStore: Ready at \(databaseURL.path)")
        } catch {
            logError("SessionStore: Initialization failed: \(error.localizedDescription)")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Public API

    func upsertWorkspace(path: String, displayName: String? = nil) throws -> WorkspaceRecord {
        try queue.sync {
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            let now = Date().timeIntervalSince1970
            let fallbackName = URL(fileURLWithPath: normalizedPath).lastPathComponent
            let finalDisplayName = displayName ?? (fallbackName.isEmpty ? normalizedPath : fallbackName)

            if let existing = try workspaceInternal(path: normalizedPath) {
                try execute(
                    "UPDATE workspaces SET display_name = ?, updated_at = ? WHERE id = ?",
                    binder: { stmt in
                        self.bindText(finalDisplayName, at: 1, in: stmt)
                        sqlite3_bind_double(stmt, 2, now)
                        self.bindText(existing.id, at: 3, in: stmt)
                    }
                )
                return try workspaceInternal(id: existing.id) ?? existing
            }

            let id = workspaceID(forPath: normalizedPath)
            try execute(
                "INSERT INTO workspaces (id, path, display_name, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                binder: { stmt in
                    self.bindText(id, at: 1, in: stmt)
                    self.bindText(normalizedPath, at: 2, in: stmt)
                    self.bindText(finalDisplayName, at: 3, in: stmt)
                    sqlite3_bind_double(stmt, 4, now)
                    sqlite3_bind_double(stmt, 5, now)
                }
            )

            guard let created = try workspaceInternal(id: id) else {
                throw SessionStoreError.sqliteError("Failed to fetch created workspace")
            }
            return created
        }
    }

    func workspace(id: String) throws -> WorkspaceRecord? {
        try queue.sync {
            try workspaceInternal(id: id)
        }
    }

    func workspace(path: String) throws -> WorkspaceRecord? {
        try queue.sync {
            try workspaceInternal(path: path)
        }
    }

    func listWorkspaces() throws -> [WorkspaceRecord] {
        try queue.sync {
            try queryWorkspaces(
                sql: """
                SELECT id, path, display_name, last_active_session_id, created_at, updated_at
                FROM workspaces
                ORDER BY updated_at DESC
                """
            )
        }
    }

    func latestWorkspace() throws -> WorkspaceRecord? {
        try queue.sync {
            let rows = try queryWorkspaces(
                sql: """
                SELECT id, path, display_name, last_active_session_id, created_at, updated_at
                FROM workspaces
                ORDER BY updated_at DESC
                LIMIT 1
                """
            )
            return rows.first
        }
    }

    func createSession(
        workspaceID: String,
        name: String,
        sessionID: String = UUID().uuidString,
        historyFile: String? = nil
    ) throws -> SessionRecord {
        try queue.sync {
            let now = Date().timeIntervalSince1970
            let id = sessionID
            let resolvedHistoryFile = historyFile ?? defaultHistoryFilePath(forSessionID: id)

            if let existing = try sessionInternal(id: id) {
                return existing
            }

            try execute(
                """
                INSERT INTO sessions (id, workspace_id, name, history_file, created_at, updated_at, is_active)
                VALUES (?, ?, ?, ?, ?, ?, 0)
                """,
                binder: { stmt in
                    self.bindText(id, at: 1, in: stmt)
                    self.bindText(workspaceID, at: 2, in: stmt)
                    self.bindText(name, at: 3, in: stmt)
                    self.bindText(resolvedHistoryFile, at: 4, in: stmt)
                    sqlite3_bind_double(stmt, 5, now)
                    sqlite3_bind_double(stmt, 6, now)
                }
            )

            guard let session = try sessionInternal(id: id) else {
                throw SessionStoreError.sqliteError("Failed to fetch created session")
            }
            return session
        }
    }

    func session(id: String) throws -> SessionRecord? {
        try queue.sync {
            try sessionInternal(id: id)
        }
    }

    func sessions(workspaceID: String) throws -> [SessionRecord] {
        try queue.sync {
            try querySessions(
                sql: """
                SELECT id, workspace_id, name, history_file, created_at, updated_at, is_active
                FROM sessions
                WHERE workspace_id = ?
                ORDER BY updated_at DESC
                """,
                binder: { stmt in
                    self.bindText(workspaceID, at: 1, in: stmt)
                }
            )
        }
    }

    func activeSession(workspaceID: String) throws -> SessionRecord? {
        try queue.sync {
            let direct = try querySessions(
                sql: """
                SELECT id, workspace_id, name, history_file, created_at, updated_at, is_active
                FROM sessions
                WHERE workspace_id = ? AND is_active = 1
                ORDER BY updated_at DESC
                LIMIT 1
                """,
                binder: { stmt in
                    self.bindText(workspaceID, at: 1, in: stmt)
                }
            ).first

            if let direct {
                return direct
            }

            guard let workspace = try workspaceInternal(id: workspaceID),
                  let sessionID = workspace.lastActiveSessionID else {
                return nil
            }
            return try sessionInternal(id: sessionID)
        }
    }

    func setActiveSession(sessionID: String, workspaceID: String) throws {
        try queue.sync {
            let now = Date().timeIntervalSince1970
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try execute(
                    "UPDATE sessions SET is_active = 0 WHERE workspace_id = ?",
                    binder: { stmt in
                        self.bindText(workspaceID, at: 1, in: stmt)
                    }
                )

                try execute(
                    "UPDATE sessions SET is_active = 1, updated_at = ? WHERE id = ?",
                    binder: { stmt in
                        sqlite3_bind_double(stmt, 1, now)
                        self.bindText(sessionID, at: 2, in: stmt)
                    }
                )

                try execute(
                    "UPDATE workspaces SET last_active_session_id = ?, updated_at = ? WHERE id = ?",
                    binder: { stmt in
                        self.bindText(sessionID, at: 1, in: stmt)
                        sqlite3_bind_double(stmt, 2, now)
                        self.bindText(workspaceID, at: 3, in: stmt)
                    }
                )
                try execute("COMMIT")
            } catch {
                _ = try? execute("ROLLBACK")
                throw error
            }
        }
    }

    func touchSession(id: String) throws {
        try queue.sync {
            let now = Date().timeIntervalSince1970
            try execute(
                "UPDATE sessions SET updated_at = ? WHERE id = ?",
                binder: { stmt in
                    sqlite3_bind_double(stmt, 1, now)
                    self.bindText(id, at: 2, in: stmt)
                }
            )
        }
    }

    // MARK: - Setup

    private func prepareDatabase(at directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            throw SessionStoreError.sqliteError(sqliteErrorMessage())
        }

        try execute("PRAGMA foreign_keys = ON")
        try execute(
            """
            CREATE TABLE IF NOT EXISTS workspaces (
                id TEXT PRIMARY KEY,
                path TEXT NOT NULL UNIQUE,
                display_name TEXT NOT NULL,
                last_active_session_id TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        )

        try execute(
            """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                workspace_id TEXT NOT NULL,
                name TEXT NOT NULL,
                history_file TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                is_active INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY(workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
            )
            """
        )
        try ensureColumnExists(table: "sessions", column: "history_file", definition: "TEXT")

        try execute("CREATE INDEX IF NOT EXISTS idx_sessions_workspace_id ON sessions(workspace_id)")
        try execute("CREATE INDEX IF NOT EXISTS idx_sessions_updated_at ON sessions(updated_at DESC)")
        try execute("CREATE INDEX IF NOT EXISTS idx_workspaces_updated_at ON workspaces(updated_at DESC)")
    }

    // MARK: - Query Helpers

    private func workspaceInternal(id: String? = nil, path: String? = nil) throws -> WorkspaceRecord? {
        if let id {
            return try queryWorkspaces(
                sql: """
                SELECT id, path, display_name, last_active_session_id, created_at, updated_at
                FROM workspaces
                WHERE id = ?
                LIMIT 1
                """,
                binder: { stmt in
                    self.bindText(id, at: 1, in: stmt)
                }
            ).first
        }

        if let path {
            return try queryWorkspaces(
                sql: """
                SELECT id, path, display_name, last_active_session_id, created_at, updated_at
                FROM workspaces
                WHERE path = ?
                LIMIT 1
                """,
                binder: { stmt in
                    self.bindText(path, at: 1, in: stmt)
                }
            ).first
        }

        return nil
    }

    private func sessionInternal(id: String) throws -> SessionRecord? {
        try querySessions(
            sql: """
            SELECT id, workspace_id, name, history_file, created_at, updated_at, is_active
            FROM sessions
            WHERE id = ?
            LIMIT 1
            """,
            binder: { stmt in
                self.bindText(id, at: 1, in: stmt)
            }
        ).first
    }

    private func queryWorkspaces(sql: String, binder: ((OpaquePointer?) -> Void)? = nil) throws -> [WorkspaceRecord] {
        guard let db else { throw SessionStoreError.databaseUnavailable }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SessionStoreError.sqliteError(sqliteErrorMessage())
        }
        defer { sqlite3_finalize(statement) }

        binder?(statement)

        var rows: [WorkspaceRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = columnText(statement, index: 0) ?? ""
            let path = columnText(statement, index: 1) ?? ""
            let displayName = columnText(statement, index: 2) ?? ""
            let lastActiveSessionID = columnText(statement, index: 3)
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))

            rows.append(
                WorkspaceRecord(
                    id: id,
                    path: path,
                    displayName: displayName,
                    lastActiveSessionID: lastActiveSessionID,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            )
        }
        return rows
    }

    private func querySessions(sql: String, binder: ((OpaquePointer?) -> Void)? = nil) throws -> [SessionRecord] {
        guard let db else { throw SessionStoreError.databaseUnavailable }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SessionStoreError.sqliteError(sqliteErrorMessage())
        }
        defer { sqlite3_finalize(statement) }

        binder?(statement)

        var rows: [SessionRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = columnText(statement, index: 0) ?? ""
            let workspaceID = columnText(statement, index: 1) ?? ""
            let name = columnText(statement, index: 2) ?? ""
            let historyFile = columnText(statement, index: 3) ?? defaultHistoryFilePath(forSessionID: id)
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            let isActive = sqlite3_column_int(statement, 6) == 1

            rows.append(
                SessionRecord(
                    id: id,
                    workspaceID: workspaceID,
                    name: name,
                    historyFile: historyFile,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    isActive: isActive
                )
            )
        }
        return rows
    }

    private static let validTableNames: Set<String> = ["workspaces", "sessions"]
    private static let validDefinitions: Set<String> = ["TEXT", "INTEGER", "REAL", "BLOB"]

    private static func isValidColumnName(_ name: String) -> Bool {
        name.range(of: "^[a-z_]+$", options: .regularExpression) != nil
    }

    private func ensureColumnExists(table: String, column: String, definition: String) throws {
        guard Self.validTableNames.contains(table) else {
            throw SessionStoreError.sqliteError("Invalid table name: \(table)")
        }
        guard Self.isValidColumnName(column) else {
            throw SessionStoreError.sqliteError("Invalid column name: \(column)")
        }
        guard Self.validDefinitions.contains(definition.uppercased()) else {
            throw SessionStoreError.sqliteError("Invalid column definition: \(definition)")
        }
        if try tableHasColumn(table: table, column: column) {
            return
        }
        try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }

    private func tableHasColumn(table: String, column: String) throws -> Bool {
        guard let db else { throw SessionStoreError.databaseUnavailable }
        let sql = "PRAGMA table_info(\(table))"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SessionStoreError.sqliteError(sqliteErrorMessage())
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let columnName = columnText(statement, index: 1),
               columnName == column {
                return true
            }
        }
        return false
    }

    private func execute(_ sql: String, binder: ((OpaquePointer?) -> Void)? = nil) throws {
        guard let db else { throw SessionStoreError.databaseUnavailable }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SessionStoreError.sqliteError(sqliteErrorMessage())
        }
        defer { sqlite3_finalize(statement) }

        binder?(statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SessionStoreError.sqliteError(sqliteErrorMessage())
        }
    }

    // MARK: - SQLite Helpers

    private func bindText(_ value: String?, at index: Int32, in statement: OpaquePointer?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, sqliteTransientDestructor)
    }

    private func columnText(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private func defaultHistoryFilePath(forSessionID sessionID: String) -> String {
        sessionsDirectoryURL
            .appendingPathComponent("\(sessionID).jsonl")
            .path
    }

    private func workspaceID(forPath path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private func sqliteErrorMessage() -> String {
        guard let db, let cString = sqlite3_errmsg(db) else {
            return "Unknown SQLite error"
        }
        return String(cString: cString)
    }
}
