import Foundation
import XCTest
@testable import RubberDuckRemoteCore

final class RubberDuckRemoteCoreTests: XCTestCase {
    func testMetadataReaderPrefersActiveVoiceSession() throws {
        let metadata = DaemonMetadataFile(
            version: 1,
            activeVoiceSessionId: "session-b",
            workspaces: [
                .init(id: "ws-a", path: "/tmp/a"),
                .init(id: "ws-b", path: "/tmp/b")
            ],
            sessions: [
                .init(id: "session-a", workspaceId: "ws-a", name: "duck-a", lastActiveAt: "2026-03-10T10:00:00Z"),
                .init(id: "session-b", workspaceId: "ws-b", name: "duck-b", lastActiveAt: "2026-03-09T10:00:00Z")
            ]
        )

        let data = try JSONEncoder().encode(metadata)
        let selection = DaemonMetadataReader().loadSelection(from: data)

        XCTAssertEqual(selection?.workspacePath, "/tmp/b")
        XCTAssertEqual(selection?.session?.id, "session-b")
    }

    func testTranscriptBuilderMergesAssistantDeltas() {
        let events = [
            ConversationHistoryEvent(
                timestamp: Date(timeIntervalSince1970: 10),
                sessionID: "s1",
                type: .userText,
                text: "Summarize the daemon."
            ),
            ConversationHistoryEvent(
                timestamp: Date(timeIntervalSince1970: 11),
                sessionID: "s1",
                type: .assistantTextDelta,
                text: "It restores metadata, "
            ),
            ConversationHistoryEvent(
                timestamp: Date(timeIntervalSince1970: 12),
                sessionID: "s1",
                type: .assistantTextDelta,
                text: "then binds the socket."
            ),
            ConversationHistoryEvent(
                timestamp: Date(timeIntervalSince1970: 13),
                sessionID: "s1",
                type: .assistantTextEnd
            )
        ]

        let transcript = ConversationTranscriptBuilder.build(from: events)

        XCTAssertEqual(transcript.count, 2)
        XCTAssertEqual(transcript[0].role, .user)
        XCTAssertEqual(transcript[1].role, .assistant)
        XCTAssertEqual(transcript[1].text, "It restores metadata, then binds the socket.")
    }

    func testPairingStoreRedactsPersistedAuthToken() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let pairingURL = tempDirectory.appendingPathComponent("pairings.json")
        let pairingStore = RemotePairingStore(fileURL: pairingURL)
        let snapshot = RemotePairingSnapshot(
            hosts: [
                PairedRemoteHost(
                    id: "duck.local",
                    displayName: "Matthew's Mac",
                    baseURL: try XCTUnwrap(URL(string: "https://duck.local")),
                    authToken: "super-secret-token",
                    pairingCodeHint: "OKEN"
                )
            ],
            selectedHostID: "duck.local"
        )

        try pairingStore.save(snapshot)

        let rawData = try Data(contentsOf: pairingURL)
        let rawString = String(decoding: rawData, as: UTF8.self)
        XCTAssertFalse(rawString.contains("super-secret-token"))

        let loaded = pairingStore.load()
        XCTAssertEqual(loaded.hosts.first?.authToken, "")
        XCTAssertEqual(loaded.hosts.first?.pairingCodeHint, "OKEN")
    }

    @MainActor
    func testAppModelBootRestoresSelectedHostAndSession() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let pairingURL = tempDirectory.appendingPathComponent("pairings.json")
        let pairingStore = RemotePairingStore(fileURL: pairingURL)
        let transport = MockRemoteDaemonTransport()
        let host = try await transport.pair(
            hostURL: XCTUnwrap(URL(string: "https://duck.local")),
            displayName: "Matthew's Mac",
            authToken: "DUCK123"
        )

        try pairingStore.save(
            RemotePairingSnapshot(
                hosts: [host],
                selectedHostID: host.id,
                sessionBookmark: RemoteSessionBookmark(
                    hostID: host.id,
                    sessionID: "duck-remote-1",
                    sessionName: "duck-remote-1",
                    workspacePath: "/Users/mblode/Code/mblode/rubber-duck"
                )
            )
        )

        let model = RemoteDaemonAppModel(
            transport: transport,
            pairingStore: pairingStore
        )

        await model.boot()

        XCTAssertEqual(model.activeHost?.id, host.id)
        XCTAssertEqual(model.activeSession?.id, "duck-remote-1")
        XCTAssertFalse(model.conversation.isEmpty)
        XCTAssertEqual(model.connectionState, .connected)
    }

    @MainActor
    func testAppModelPairAcceptsBareHostnamesAndDefaultsToDirectDaemonPort() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let pairingURL = tempDirectory.appendingPathComponent("pairings.json")
        let pairingStore = RemotePairingStore(fileURL: pairingURL)
        let model = RemoteDaemonAppModel(
            transport: MockRemoteDaemonTransport(),
            pairingStore: pairingStore
        )

        await model.pair(
            hostURLString: "linktree",
            displayName: "",
            authToken: "DUCK123"
        )

        XCTAssertEqual(model.activeHost?.baseURL.absoluteString, "http://linktree:43111")
        XCTAssertNil(model.lastError)
    }

    @MainActor
    func testAppModelPairAcceptsBareTailscaleIPAddresses() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let pairingURL = tempDirectory.appendingPathComponent("pairings.json")
        let pairingStore = RemotePairingStore(fileURL: pairingURL)
        let model = RemoteDaemonAppModel(
            transport: MockRemoteDaemonTransport(),
            pairingStore: pairingStore
        )

        await model.pair(
            hostURLString: "100.96.185.34",
            displayName: "",
            authToken: "DUCK123"
        )

        XCTAssertEqual(model.activeHost?.baseURL.absoluteString, "http://100.96.185.34:43111")
        XCTAssertNil(model.lastError)
    }
}
