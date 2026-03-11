import Foundation

public struct RemoteSessionBookmark: Codable, Equatable, Sendable {
    public let hostID: String
    public let sessionID: String?
    public let sessionName: String?
    public let workspacePath: String?
    public let updatedAt: Date

    public init(
        hostID: String,
        sessionID: String?,
        sessionName: String?,
        workspacePath: String?,
        updatedAt: Date = .now
    ) {
        self.hostID = hostID
        self.sessionID = sessionID
        self.sessionName = sessionName
        self.workspacePath = workspacePath
        self.updatedAt = updatedAt
    }
}

public struct RemotePairingSnapshot: Codable, Equatable, Sendable {
    public var hosts: [PairedRemoteHost]
    public var selectedHostID: String?
    public var sessionBookmark: RemoteSessionBookmark?

    public init(
        hosts: [PairedRemoteHost] = [],
        selectedHostID: String? = nil,
        sessionBookmark: RemoteSessionBookmark? = nil
    ) {
        self.hosts = hosts
        self.selectedHostID = selectedHostID
        self.sessionBookmark = sessionBookmark
    }
}

public final class RemotePairingStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() -> RemotePairingSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(RemotePairingSnapshot.self, from: data) else {
            return RemotePairingSnapshot()
        }

        return snapshot
    }

    public func save(_ snapshot: RemotePairingSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let redactedSnapshot = RemotePairingSnapshot(
            hosts: snapshot.hosts.map { host in
                PairedRemoteHost(
                    id: host.id,
                    displayName: host.displayName,
                    baseURL: host.baseURL,
                    authToken: "",
                    pairingCodeHint: host.pairingCodeHint,
                    pairedAt: host.pairedAt,
                    lastConnectedAt: host.lastConnectedAt
                )
            },
            selectedHostID: snapshot.selectedHostID,
            sessionBookmark: snapshot.sessionBookmark
        )

        let data = try encoder.encode(redactedSnapshot)
        let tempURL = fileURL.appendingPathExtension("tmp")
        try data.write(to: tempURL, options: .atomic)

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        try fileManager.moveItem(at: tempURL, to: fileURL)
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        return baseDirectory
            .appendingPathComponent("RubberDuckIOS", isDirectory: true)
            .appendingPathComponent("remote-pairings.json", isDirectory: false)
    }
}
