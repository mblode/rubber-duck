import Foundation

public struct DaemonMetadataReader: Sendable {
    public init() {}

    public func loadMetadata(from data: Data) -> DaemonMetadataFile? {
        try? JSONDecoder().decode(DaemonMetadataFile.self, from: data)
    }

    public func loadMetadata(from fileURL: URL) -> DaemonMetadataFile? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return loadMetadata(from: data)
    }

    public func loadSelection(from data: Data) -> DaemonMetadataSelection? {
        guard let metadata = loadMetadata(from: data) else {
            return nil
        }

        if let activeSessionId = metadata.activeVoiceSessionId,
           let session = metadata.sessions.first(where: { $0.id == activeSessionId }),
           let workspace = metadata.workspaces.first(where: { $0.id == session.workspaceId }) {
            return DaemonMetadataSelection(
                workspacePath: workspace.path,
                session: session
            )
        }

        if let session = metadata.sessions.max(by: {
            date(from: $0.lastActiveAt) < date(from: $1.lastActiveAt)
        }),
           let workspace = metadata.workspaces.first(where: { $0.id == session.workspaceId }) {
            return DaemonMetadataSelection(
                workspacePath: workspace.path,
                session: session
            )
        }

        if let workspace = metadata.workspaces.first {
            return DaemonMetadataSelection(
                workspacePath: workspace.path,
                session: nil
            )
        }

        return nil
    }

    public func loadSelection(from fileURL: URL) -> DaemonMetadataSelection? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return loadSelection(from: data)
    }

    private func date(from value: String?) -> Date {
        guard let value else {
            return .distantPast
        }
        return ISO8601DateFormatter().date(from: value) ?? .distantPast
    }
}
