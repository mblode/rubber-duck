import Foundation

struct CLIMetadataSelection {
    let workspaceURL: URL
    let session: CLIMetadataFile.Session?
}

struct CLIMetadataReader {
    static let iso8601Formatter = ISO8601DateFormatter()

    private let metadataURL: URL

    init(metadataURL: URL) {
        self.metadataURL = metadataURL
    }

    func loadMetadata() -> CLIMetadataFile? {
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(CLIMetadataFile.self, from: data) else {
            return nil
        }
        return metadata
    }

    func loadSelection() -> CLIMetadataSelection? {
        guard let metadata = loadMetadata() else {
            return nil
        }

        if let activeSessionId = metadata.activeVoiceSessionId,
           let session = metadata.sessions.first(where: { $0.id == activeSessionId }),
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
}
