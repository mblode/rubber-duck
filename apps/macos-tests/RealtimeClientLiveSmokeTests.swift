import XCTest
@testable import RubberDuck

@MainActor
final class RealtimeClientLiveSmokeTests: XCTestCase {
    @MainActor
    private final class Probe: RealtimeClientDelegate {
        let readyExpectation: XCTestExpectation
        let serverErrorExpectation: XCTestExpectation
        let disconnectWithErrorExpectation: XCTestExpectation
        var responseExpectation: XCTestExpectation?
        var capturedResponse: String = ""
        private var didFulfillReady = false
        private var didFulfillServerError = false
        private var didFulfillDisconnectWithError = false
        private var didFulfillResponse = false

        init(
            readyExpectation: XCTestExpectation,
            serverErrorExpectation: XCTestExpectation,
            disconnectWithErrorExpectation: XCTestExpectation
        ) {
            self.readyExpectation = readyExpectation
            self.serverErrorExpectation = serverErrorExpectation
            self.disconnectWithErrorExpectation = disconnectWithErrorExpectation
        }

        func realtimeClientDidBecomeReady(_ client: any RealtimeClientProtocol) {
            guard !didFulfillReady else { return }
            didFulfillReady = true
            readyExpectation.fulfill()
        }

        func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveError error: [String: Any]) {
            guard !didFulfillServerError else { return }
            didFulfillServerError = true
            serverErrorExpectation.fulfill()
        }

        func realtimeClientDidDisconnect(_ client: any RealtimeClientProtocol, error: Error?) {
            if error != nil, !didFulfillDisconnectWithError {
                didFulfillDisconnectWithError = true
                disconnectWithErrorExpectation.fulfill()
            }
        }

        func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveTextDone text: String) {
            guard !didFulfillResponse else { return }
            didFulfillResponse = true
            capturedResponse = text
            responseExpectation?.fulfill()
        }

        func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioTranscriptDone text: String) {
            guard !didFulfillResponse, capturedResponse.isEmpty else { return }
            didFulfillResponse = true
            capturedResponse = text
            responseExpectation?.fulfill()
        }
    }

    func test_liveRealtimeSession_reachesReady_andAcceptsInitialAudio() async throws {
        let liveTestFlagPath = "/tmp/rubber-duck-live-realtime-test"
        guard FileManager.default.fileExists(atPath: liveTestFlagPath),
              let keyFileContents = try? String(contentsOfFile: liveTestFlagPath, encoding: .utf8) else {
            throw XCTSkip("Write an API key into \(liveTestFlagPath) to run live Realtime smoke test")
        }
        let lines = keyFileContents
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let apiKey = lines.first ?? ""
        let modelOverride = lines.dropFirst().first
        guard !apiKey.isEmpty else {
            throw XCTSkip("Write an API key into \(liveTestFlagPath) to run live Realtime smoke test")
        }

        let readyExpectation = expectation(description: "Realtime session ready")
        readyExpectation.assertForOverFulfill = false
        let serverErrorExpectation = expectation(description: "No server error during smoke window")
        serverErrorExpectation.isInverted = true
        serverErrorExpectation.assertForOverFulfill = false
        let disconnectWithErrorExpectation = expectation(description: "No disconnect-with-error during smoke window")
        disconnectWithErrorExpectation.isInverted = true
        disconnectWithErrorExpectation.assertForOverFulfill = false

        let client = RealtimeClient()
        client.model = modelOverride ?? "gpt-realtime-1.5"
        client.voice = "marin"
        client.instructions = "You are a test assistant. Keep responses short."
        client.tools = []

        let probe = Probe(
            readyExpectation: readyExpectation,
            serverErrorExpectation: serverErrorExpectation,
            disconnectWithErrorExpectation: disconnectWithErrorExpectation
        )
        client.delegate = probe
        client.connect(apiKey: apiKey)

        await fulfillment(of: [readyExpectation], timeout: 20)

        // 100ms of silence at 24kHz PCM16 mono.
        let silentChunkBytes = Data(repeating: 0, count: 2400 * MemoryLayout<Int16>.size)
        client.sendAudio(base64Chunk: silentChunkBytes.base64EncodedString())

        await fulfillment(of: [serverErrorExpectation, disconnectWithErrorExpectation], timeout: 5)
        client.disconnect()
    }

    func test_liveRealtimeSession_textMessage_receivesAIResponse() async throws {
        let liveTestFlagPath = "/tmp/rubber-duck-live-realtime-test"
        guard FileManager.default.fileExists(atPath: liveTestFlagPath),
              let keyFileContents = try? String(contentsOfFile: liveTestFlagPath, encoding: .utf8) else {
            throw XCTSkip("Write an API key into \(liveTestFlagPath) to run live Realtime conversation test")
        }
        let lines = keyFileContents
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let apiKey = lines.first ?? ""
        let modelOverride = lines.dropFirst().first
        guard !apiKey.isEmpty else {
            throw XCTSkip("Write an API key into \(liveTestFlagPath) to run live Realtime conversation test")
        }

        let readyExpectation = expectation(description: "Realtime session ready")
        readyExpectation.assertForOverFulfill = false
        let serverErrorExpectation = expectation(description: "No server error during conversation test")
        serverErrorExpectation.isInverted = true
        serverErrorExpectation.assertForOverFulfill = false
        let disconnectWithErrorExpectation = expectation(description: "No disconnect-with-error during conversation test")
        disconnectWithErrorExpectation.isInverted = true
        disconnectWithErrorExpectation.assertForOverFulfill = false
        let responseExpectation = expectation(description: "AI response received")
        responseExpectation.assertForOverFulfill = false

        let client = RealtimeClient()
        client.model = modelOverride ?? "gpt-realtime-1.5"
        client.voice = "marin"
        client.instructions = "You are a test assistant. Keep responses short."
        client.tools = []

        let probe = Probe(
            readyExpectation: readyExpectation,
            serverErrorExpectation: serverErrorExpectation,
            disconnectWithErrorExpectation: disconnectWithErrorExpectation
        )
        probe.responseExpectation = responseExpectation
        client.delegate = probe
        client.connect(apiKey: apiKey)

        await fulfillment(of: [readyExpectation], timeout: 20)

        client.sendMessage(text: "Reply with exactly the word PONG and nothing else.")

        await fulfillment(of: [responseExpectation], timeout: 30)

        XCTAssertFalse(probe.capturedResponse.isEmpty, "Expected a non-empty AI response")
        XCTAssertTrue(
            probe.capturedResponse.lowercased().contains("pong"),
            "Expected response to contain 'pong', got: \(probe.capturedResponse)"
        )

        await fulfillment(of: [serverErrorExpectation, disconnectWithErrorExpectation], timeout: 3)
        client.disconnect()
    }
}
