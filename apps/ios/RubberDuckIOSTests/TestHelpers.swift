import Foundation
@testable import RubberDuckIOS
import RubberDuckRemoteCore

enum TestFixtures {
    static func makeEntry(
        role: RemoteConversationRole = .user,
        text: String = "Test message",
        metadata: [String: String] = [:]
    ) -> RemoteConversationEntry {
        RemoteConversationEntry(
            role: role,
            text: text,
            timestamp: Date(),
            metadata: metadata
        )
    }

    static func makeSession(
        id: String = "session-1",
        name: String = "rubber-duck",
        workspacePath: String = "/Users/mblode/Code/mblode/rubber-duck",
        isActive: Bool = true,
        isRunning: Bool = true
    ) -> RemoteSessionSummary {
        RemoteSessionSummary(
            id: id,
            name: name,
            workspacePath: workspacePath,
            isActive: isActive,
            isRunning: isRunning,
            lastActiveAt: Date()
        )
    }

    static func makeHost(
        id: String = "host-1",
        displayName: String = "MacBook Pro",
        baseURL: URL = URL(string: "http://192.168.1.100:3000")!,
        authToken: String = "test-token"
    ) -> PairedRemoteHost {
        PairedRemoteHost(
            id: id,
            displayName: displayName,
            baseURL: baseURL,
            authToken: authToken,
            pairingCodeHint: "abc",
            pairedAt: Date()
        )
    }

    @MainActor
    static func makeAppModel() -> RemoteDaemonAppModel {
        RemoteDaemonAppModel(transport: MockRemoteDaemonTransport())
    }
}
