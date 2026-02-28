import XCTest
@testable import RubberDuck

@MainActor
final class VoiceSessionCoordinatorHistoryTests: XCTestCase {

    private final class MockAudioManager: VoiceAudioManaging {
        var isStreaming: Bool = false
        var isMicrophonePermissionDenied: Bool = false

        func startStreaming(onChunk: @escaping (String) -> Void, onError: ((Error) -> Void)?) {}
        func stopStreaming() {}
    }

    private final class MockPlaybackManager: VoiceAudioPlayback {
        var isPlaying: Bool = false

        func startPlayback() {}
        func stopPlayback() {}
        func stopImmediately() -> Int { 0 }
        func enqueueAudio(base64Chunk: String, itemId: String?, contentIndex: Int?) {}
    }

    private final class MockOverlayPresenter: OverlayPresenting {
        func show(state: OverlayState) {}
        func dismiss() {}
    }

    private struct Harness {
        let coordinator: VoiceSessionCoordinator
        let realtimeClient: MockRealtimeClient  // from TestMocks.swift
        let historyURL: URL
        let tempDirectoryURL: URL
    }

    private func makeHarness() throws -> Harness {
        let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("VoiceSessionCoordinatorHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)

        let historyURL = tempDirectoryURL.appendingPathComponent("history.jsonl")
        let audioManager = MockAudioManager()
        let playbackManager = MockPlaybackManager()
        let realtimeClient = MockRealtimeClient()
        let overlay = MockOverlayPresenter()

        let coordinator = VoiceSessionCoordinator(
            audioManager: audioManager,
            playbackManager: playbackManager,
            realtimeClient: realtimeClient,
            overlay: overlay
        )

        let session = SessionRecord(
            id: UUID().uuidString,
            workspaceID: "workspace-1",
            name: "duck-1",
            historyFile: historyURL.path,
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true
        )
        coordinator.setSession(session)

        return Harness(
            coordinator: coordinator,
            realtimeClient: realtimeClient,
            historyURL: historyURL,
            tempDirectoryURL: tempDirectoryURL
        )
    }

    func test_userConversationItemPersistsUserTextEvent() throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDirectoryURL) }

        harness.coordinator.realtimeClient(
            harness.realtimeClient,
            didReceiveConversationItemCreated: [
                "id": "item-1",
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": "Hey there"
                    ]
                ]
            ]
        )

        let history = try ConversationHistory(fileURL: harness.historyURL)
        let events = try history.readRecent(limit: 10)
        let userEvents = events.filter { $0.type == .userText }
        XCTAssertEqual(userEvents.count, 1)
        XCTAssertEqual(userEvents.first?.text, "Hey there")
        XCTAssertEqual(harness.coordinator.currentTranscript, "Hey there")
    }

    func test_userConversationItemWithTranscriptPersistsUserTextEvent() throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDirectoryURL) }

        harness.coordinator.realtimeClient(
            harness.realtimeClient,
            didReceiveConversationItemCreated: [
                "id": "item-2",
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_audio",
                        "transcript": "Read me the file"
                    ]
                ]
            ]
        )

        let history = try ConversationHistory(fileURL: harness.historyURL)
        let events = try history.readRecent(limit: 10)
        let userEvents = events.filter { $0.type == .userText }
        XCTAssertEqual(userEvents.count, 1)
        XCTAssertEqual(userEvents.first?.text, "Read me the file")
    }

    func test_duplicateConversationItemIDIsNotWrittenTwice() throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDirectoryURL) }

        let item: [String: Any] = [
            "id": "item-dup",
            "type": "message",
            "role": "user",
            "content": [
                [
                    "type": "input_text",
                    "text": "Same event"
                ]
            ]
        ]

        harness.coordinator.realtimeClient(harness.realtimeClient, didReceiveConversationItemCreated: item)
        harness.coordinator.realtimeClient(harness.realtimeClient, didReceiveConversationItemCreated: item)

        let history = try ConversationHistory(fileURL: harness.historyURL)
        let events = try history.readRecent(limit: 10)
        let userEvents = events.filter { $0.type == .userText }
        XCTAssertEqual(userEvents.count, 1)
        XCTAssertEqual(userEvents.first?.text, "Same event")
    }
}
