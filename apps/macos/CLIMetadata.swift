import Foundation

struct CLIMetadataFile: Codable {
    var version: Int?
    var activeVoiceSessionId: String?
    var workspaces: [Workspace]
    var sessions: [Session]

    struct Workspace: Codable {
        let id: String
        let path: String
        var createdAt: String?
        var lastActiveSessionId: String?
    }

    struct Session: Codable {
        let id: String
        let workspaceId: String
        var name: String?
        let lastActiveAt: String?
        var createdAt: String?
        var isVoiceActive: Bool?
        var piSessionFile: String?
    }
}
