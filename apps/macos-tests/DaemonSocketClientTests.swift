import XCTest
@testable import RubberDuck

@MainActor
final class DaemonSocketClientTests: XCTestCase {

    func test_isConnected_falseByDefault() {
        let client = DaemonSocketClient(socketPath: "/nonexistent/daemon.sock")
        XCTAssertFalse(client.isConnected)
        XCTAssertEqual(client.connectionState, .disconnected)
    }

    func test_connect_silentlyFailsWhenSocketAbsent() async {
        let client = DaemonSocketClient(socketPath: "/nonexistent/\(UUID().uuidString)/daemon.sock", timeoutSeconds: 2)
        await client.connect()
        XCTAssertFalse(client.isConnected, "Connect to absent socket should leave client disconnected")
        XCTAssertEqual(client.connectionState, .disconnected)
    }

    func test_request_throwsDaemonUnavailableWhenDisconnected() async {
        let client = DaemonSocketClient(socketPath: "/nonexistent/daemon.sock")
        do {
            _ = try await client.request(method: "ping")
            XCTFail("Expected daemonUnavailable error")
        } catch DaemonSocketClient.ClientError.daemonUnavailable {
            // Expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_disconnect_isIdempotent() {
        let client = DaemonSocketClient(socketPath: "/nonexistent/daemon.sock")
        // Should not crash when called on an already-disconnected client
        client.disconnect()
        client.disconnect()
        XCTAssertFalse(client.isConnected)
    }

    func test_connect_canBeCalledMultipleTimes() async {
        let client = DaemonSocketClient(socketPath: "/nonexistent/daemon.sock", timeoutSeconds: 1)
        await client.connect()
        XCTAssertFalse(client.isConnected)
        // Second connect on a disconnected client should also succeed without crashing
        await client.connect()
        XCTAssertFalse(client.isConnected)
    }
}
