import Foundation

public struct DaemonMetadataFile: Codable, Equatable, Sendable {
    public var version: Int?
    public var activeVoiceSessionId: String?
    public var workspaces: [Workspace]
    public var sessions: [Session]

    public init(
        version: Int? = nil,
        activeVoiceSessionId: String? = nil,
        workspaces: [Workspace] = [],
        sessions: [Session] = []
    ) {
        self.version = version
        self.activeVoiceSessionId = activeVoiceSessionId
        self.workspaces = workspaces
        self.sessions = sessions
    }

    public struct Workspace: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let path: String
        public var createdAt: String?
        public var lastActiveSessionId: String?

        public init(
            id: String,
            path: String,
            createdAt: String? = nil,
            lastActiveSessionId: String? = nil
        ) {
            self.id = id
            self.path = path
            self.createdAt = createdAt
            self.lastActiveSessionId = lastActiveSessionId
        }
    }

    public struct Session: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let workspaceId: String
        public var name: String?
        public let lastActiveAt: String?
        public var createdAt: String?
        public var isVoiceActive: Bool?
        public var piSessionFile: String?

        public init(
            id: String,
            workspaceId: String,
            name: String? = nil,
            lastActiveAt: String? = nil,
            createdAt: String? = nil,
            isVoiceActive: Bool? = nil,
            piSessionFile: String? = nil
        ) {
            self.id = id
            self.workspaceId = workspaceId
            self.name = name
            self.lastActiveAt = lastActiveAt
            self.createdAt = createdAt
            self.isVoiceActive = isVoiceActive
            self.piSessionFile = piSessionFile
        }
    }
}

public struct DaemonMetadataSelection: Equatable, Sendable {
    public let workspacePath: String
    public let session: DaemonMetadataFile.Session?

    public init(workspacePath: String, session: DaemonMetadataFile.Session?) {
        self.workspacePath = workspacePath
        self.session = session
    }

    public var workspaceURL: URL {
        URL(fileURLWithPath: workspacePath, isDirectory: true)
    }
}
