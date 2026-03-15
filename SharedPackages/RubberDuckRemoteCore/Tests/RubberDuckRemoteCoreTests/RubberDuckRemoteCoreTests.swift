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

    func testFileBackedRemoteCredentialStorePersistsAndDeletesTokens() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let credentialURL = tempDirectory.appendingPathComponent("remote-credentials.json")
        let credentialStore = RemoteCredentialStore(fileURL: credentialURL)

        try credentialStore.saveToken("DUCK123", for: "duck.local")
        XCTAssertEqual(try credentialStore.loadToken(for: "duck.local"), "DUCK123")

        let persistedData = try Data(contentsOf: credentialURL)
        let persistedString = String(decoding: persistedData, as: UTF8.self)
        XCTAssertTrue(persistedString.contains("DUCK123"))

        try credentialStore.deleteToken(for: "duck.local")
        XCTAssertThrowsError(try credentialStore.loadToken(for: "duck.local")) { error in
            XCTAssertEqual(error as? RemoteCredentialStoreError, .missingToken)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: credentialURL.path))
    }

    func testHTTPTransportFallsBackToStateWhenSessionHistoryIsMissing() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let credentialURL = tempDirectory.appendingPathComponent("remote-credentials.json")
        let credentialStore = RemoteCredentialStore(fileURL: credentialURL)
        let host = PairedRemoteHost(
            id: "http://duck.local:43111",
            displayName: "Duck Local",
            baseURL: try XCTUnwrap(URL(string: "http://duck.local:43111")),
            authToken: "",
            pairingCodeHint: "1234"
        )
        try credentialStore.saveToken("DUCK123", for: host.id)

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)

        StubURLProtocol.handler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            switch url.path {
            case "/status":
                return StubURLProtocol.response(
                    url: url,
                    statusCode: 200,
                    json: [
                        "connectedClients": 0,
                        "enabled": true,
                        "host": "duck.local",
                        "httpUrl": "http://duck.local:43111",
                        "listening": true,
                        "port": 43_111,
                        "protocol": "http",
                        "tlsEnabled": false,
                        "tokenConfigured": true,
                        "wsUrl": "ws://duck.local:43111/ws"
                    ]
                )

            case "/history":
                return StubURLProtocol.response(
                    url: url,
                    statusCode: 404,
                    json: [
                        "error": "History not found for session session-1"
                    ]
                )

            case "/rpc":
                let rpcBody = try XCTUnwrap(request.httpBody)
                let payload = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: rpcBody) as? [String: Any]
                )
                let requestID = payload["id"] as? String ?? "rpc-id"
                let method = payload["method"] as? String ?? ""

                switch method {
                case "sessions":
                    return StubURLProtocol.response(
                        url: url,
                        statusCode: 200,
                        json: [
                            "id": requestID,
                            "ok": true,
                            "data": [
                                "sessions": [
                                    [
                                        "id": "session-1",
                                        "name": "duck-1",
                                        "workspacePath": "/tmp/workspace",
                                        "isActive": true,
                                        "isRunning": true,
                                        "lastActiveAt": "2026-03-12T05:00:00Z"
                                    ]
                                ]
                            ]
                        ]
                    )

                case "get_state":
                    return StubURLProtocol.response(
                        url: url,
                        statusCode: 200,
                        json: [
                            "id": requestID,
                            "ok": true,
                            "data": [
                                "sessionId": "session-1",
                                "sessionName": "duck-1",
                                "isRunning": true,
                                "piState": [
                                    "isStreaming": false,
                                    "messageCount": 0,
                                    "model": "gpt-4o-mini",
                                    "pendingMessageCount": 0,
                                    "sessionId": "session-1",
                                    "sessionName": "duck-1",
                                    "thinkingLevel": "off"
                                ]
                            ]
                        ]
                    )

                default:
                    return StubURLProtocol.response(
                        url: url,
                        statusCode: 400,
                        json: [
                            "error": "Unexpected RPC method \(method)"
                        ]
                    )
                }

            default:
                return StubURLProtocol.response(
                    url: url,
                    statusCode: 404,
                    json: [
                        "error": "Unhandled path \(url.path)"
                    ]
                )
            }
        }

        let transport = RemoteDaemonHTTPTransport(
            session: session,
            credentialStore: credentialStore
        )

        let snapshot = try await transport.loadSnapshot(for: host)

        XCTAssertEqual(snapshot.activeSession?.id, "session-1")
        XCTAssertEqual(snapshot.sessions.count, 1)
        XCTAssertTrue(
            snapshot.conversation.contains(where: { $0.text.contains("History is empty") })
        )
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

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func response(
        url: URL,
        statusCode: Int,
        json: [String: Any]
    ) -> (HTTPURLResponse, Data) {
        let data = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }
}
