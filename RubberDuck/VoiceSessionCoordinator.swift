import SwiftUI
import Combine

// MARK: - Voice Session State

enum VoiceSessionState: String {
    case idle
    case connecting
    case listening
    case thinking
    case speaking
    case toolRunning
}

// MARK: - Protocols for Dependency Injection

protocol VoiceAudioManaging: AnyObject {
    var isStreaming: Bool { get }
    var isMicrophonePermissionDenied: Bool { get }

    func startStreaming(onChunk: @escaping (String) -> Void, onError: ((Error) -> Void)?)
    func stopStreaming()
}

extension AudioManager: VoiceAudioManaging {}

protocol VoiceAudioPlayback: AnyObject {
    var isPlaying: Bool { get }

    func startPlayback()
    func stopPlayback()
    func stopImmediately() -> Int
    func enqueueAudio(base64Chunk: String)
}

extension AudioPlaybackManager: VoiceAudioPlayback {}

// MARK: - VoiceSessionCoordinator

@MainActor
class VoiceSessionCoordinator: ObservableObject, RealtimeClientDelegate {

    @Published var sessionState: VoiceSessionState = .idle
    @Published var currentTranscript: String = ""
    @Published var lastAssistantTranscript: String = ""
    @Published var workspacePath: URL?
    @Published var activeSessionID: String?

    private let audioManager: VoiceAudioManaging
    private let playbackManager: VoiceAudioPlayback
    private let realtimeClient: RealtimeClient
    private let overlay: OverlayPresenting
    private let notificationCenter: NotificationCenter
    private let userDefaults: UserDefaults
    private static let iso8601Formatter = ISO8601DateFormatter()
    private let fileManager: FileManager
    private var cancellables = Set<AnyCancellable>()
    private var toolCallHandler: ToolCallHandler?
    private var conversationHistory: ConversationHistory?
    private var autoAbortOnBargeIn = true

    // Track the current response's audio item for truncation on barge-in
    private var currentAudioItemId: String?
    private var currentAudioContentIndex: Int = 0

    // Track pending function calls from the current response
    private var pendingFunctionCalls: [(callId: String, name: String, arguments: String)] = []

    init(
        audioManager: VoiceAudioManaging,
        playbackManager: VoiceAudioPlayback,
        realtimeClient: RealtimeClient,
        notificationCenter: NotificationCenter = .default,
        overlay: OverlayPresenting? = nil,
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        logInfo("VoiceSessionCoordinator: Initializing")
        self.audioManager = audioManager
        self.playbackManager = playbackManager
        self.realtimeClient = realtimeClient
        self.notificationCenter = notificationCenter
        self.overlay = overlay ?? LiveOverlayPresenter.shared
        self.userDefaults = userDefaults
        self.fileManager = fileManager

        realtimeClient.delegate = self

        notificationCenter.publisher(for: NSNotification.Name("HotkeyKeyDown"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleHotkeyDown() }
            .store(in: &cancellables)

        notificationCenter.publisher(for: NSNotification.Name("HotkeyKeyUp"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleHotkeyUp() }
            .store(in: &cancellables)

        notificationCenter.publisher(for: UserDefaults.didChangeNotification, object: userDefaults)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncRuntimeSettings() }
            .store(in: &cancellables)

        syncRuntimeSettings()
    }

    func setWorkspace(_ path: URL) {
        workspacePath = path
        let workspace = WorkspaceContext(rootPath: path)
        let executor = ToolExecutor(workspace: workspace)
        executor.safeMode = userDefaults.bool(forKey: "safeModeEnabled")
        toolCallHandler = ToolCallHandler(toolExecutor: executor, realtimeClient: realtimeClient)
        realtimeClient.tools = ToolDefinitions.allTools()
        logInfo("VoiceSessionCoordinator: Workspace set to \(path.path)")
    }

    func setSession(_ session: SessionRecord?) {
        activeSessionID = session?.id
        guard let session else {
            conversationHistory = nil
            logInfo("VoiceSessionCoordinator: Cleared active session")
            return
        }

        let historyURL = URL(fileURLWithPath: session.historyFile)
        do {
            let history = try ConversationHistory(fileURL: historyURL, fileManager: fileManager)
            let recentEvents = try history.readRecent(limit: 50)
            conversationHistory = history
            logInfo("VoiceSessionCoordinator: Active session set to \(session.name) (\(recentEvents.count) history events)")
        } catch {
            conversationHistory = nil
            logError("VoiceSessionCoordinator: Failed to bind session history: \(error.localizedDescription)")
        }
    }

    // MARK: - Public API

    func connectAndListen(apiKey: String) {
        guard sessionState == .idle else {
            logDebug("VoiceSessionCoordinator: Not idle, ignoring connect request")
            return
        }

        syncRuntimeSettings()
        setState(.connecting)
        overlay.show(state: .thinking)
        realtimeClient.connect(apiKey: apiKey)
    }

    func disconnectSession() {
        stopAudioStreaming()
        playbackManager.stopPlayback()
        realtimeClient.disconnect()
        setState(.idle)
        overlay.dismiss()
    }

    var isActive: Bool {
        sessionState != .idle
    }

    // MARK: - Hotkey Handling

    private func handleHotkeyDown() {
        switch sessionState {
        case .idle:
            maybeAttachWorkspaceFromCLIMetadata()

            guard let apiKey = KeychainManager.loadAPIKey() else {
                logInfo("VoiceSessionCoordinator: No API key, opening settings")
                SettingsWindowController.shared.show()
                return
            }
            connectAndListen(apiKey: apiKey)

        case .speaking:
            // Barge-in: stop playback and let VAD handle the new speech
            handleBargeIn()

        case .listening:
            // Already listening, nothing to do
            break

        case .connecting, .thinking, .toolRunning:
            // Busy, ignore
            break
        }
    }

    private func handleHotkeyUp() {
        // With semantic VAD, turn detection is automatic.
        // Hotkey-up is a no-op.
    }

    // MARK: - Barge-in

    private func handleBargeIn() {
        logInfo("VoiceSessionCoordinator: Barge-in — stopping playback")

        // Capture total scheduled before stopping (stopImmediately returns unplayed count)
        let totalScheduled = (playbackManager as? AudioPlaybackManager)?.totalSamplesScheduled ?? 0
        let unplayedSamples = playbackManager.stopImmediately()
        let playedSamples = max(0, totalScheduled - unplayedSamples)

        if autoAbortOnBargeIn, let itemId = currentAudioItemId {
            // Convert played samples to milliseconds
            let audioEndMs = playedSamples * 1000 / Int(AudioConstants.sampleRate)
            realtimeClient.truncateResponse(itemId: itemId, contentIndex: currentAudioContentIndex, audioEnd: audioEndMs)
            logDebug("VoiceSessionCoordinator: Sent truncate for item \(itemId), audioEnd: \(audioEndMs)ms, unplayed: \(unplayedSamples) samples")
        } else if !autoAbortOnBargeIn {
            logInfo("VoiceSessionCoordinator: Auto-abort on barge-in disabled, skipping truncate")
        }

        setState(.listening)
        overlay.show(state: .listening)
    }

    // MARK: - State Management

    private func setState(_ state: VoiceSessionState) {
        sessionState = state
        logDebug("VoiceSessionCoordinator: State -> \(state.rawValue)")
    }

    private func startAudioStreaming() {
        audioManager.startStreaming(
            onChunk: { [weak self] base64Chunk in
                Task { @MainActor in
                    self?.realtimeClient.sendAudio(base64Chunk: base64Chunk)
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.overlay.show(state: .error("Microphone error: \(error.localizedDescription)"))
                    self?.disconnectSession()
                }
            }
        )
    }

    private func stopAudioStreaming() {
        if audioManager.isStreaming {
            audioManager.stopStreaming()
        }
    }

    // MARK: - Settings

    private func syncRuntimeSettings() {
        realtimeClient.voice = userDefaults.string(forKey: "voiceAgentVoice") ?? "marin"
        realtimeClient.model = userDefaults.string(forKey: "voiceAgentModel") ?? "gpt-4o-mini-realtime-preview"
        realtimeClient.vadEagerness = userDefaults.string(forKey: "vadEagerness") ?? "medium"

        if userDefaults.object(forKey: "autoAbortOnBargeIn") == nil {
            autoAbortOnBargeIn = true
        } else {
            autoAbortOnBargeIn = userDefaults.bool(forKey: "autoAbortOnBargeIn")
        }

        let safeModeEnabled = userDefaults.bool(forKey: "safeModeEnabled")
        toolCallHandler?.setSafeMode(safeModeEnabled)
    }

    // MARK: - Workspace Attachment

    private func maybeAttachWorkspaceFromCLIMetadata() {
        guard workspacePath == nil else {
            return
        }

        guard let path = loadWorkspaceFromCLIMetadata() else {
            return
        }

        setWorkspace(path)
    }

    private func appendHistoryEvent(type: ConversationEventType, text: String? = nil, metadata: [String: String]? = nil) {
        guard let sessionID = activeSessionID,
              let conversationHistory else {
            return
        }

        let event = ConversationHistoryEvent(
            timestamp: Date(),
            sessionID: sessionID,
            type: type,
            text: text,
            metadata: metadata
        )

        do {
            try conversationHistory.append(event: event)
        } catch {
            logError("VoiceSessionCoordinator: Failed to append history event: \(error.localizedDescription)")
        }
    }

    private func loadWorkspaceFromCLIMetadata() -> URL? {
        let metadataPath = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RubberDuck/metadata.json")

        guard let data = try? Data(contentsOf: metadataPath),
              let metadata = try? JSONDecoder().decode(CLIMetadataFile.self, from: data) else {
            return nil
        }

        if let activeSessionId = metadata.activeVoiceSessionId,
           let session = metadata.sessions.first(where: { $0.id == activeSessionId }),
           let workspace = metadata.workspaces.first(where: { $0.id == session.workspaceId }) {
            return URL(fileURLWithPath: workspace.path, isDirectory: true)
        }

        if let session = metadata.sessions.max(by: {
            let d0 = $0.lastActiveAt.flatMap { Self.iso8601Formatter.date(from: $0) } ?? .distantPast
            let d1 = $1.lastActiveAt.flatMap { Self.iso8601Formatter.date(from: $0) } ?? .distantPast
            return d0 < d1
        }),
           let workspace = metadata.workspaces.first(where: { $0.id == session.workspaceId }) {
            return URL(fileURLWithPath: workspace.path, isDirectory: true)
        }

        if let workspace = metadata.workspaces.first {
            return URL(fileURLWithPath: workspace.path, isDirectory: true)
        }

        return nil
    }

    // MARK: - RealtimeClientDelegate: Connection

    func realtimeClientDidConnect(_ client: RealtimeClient) {
        logInfo("VoiceSessionCoordinator: Connected to Realtime API")
        setState(.listening)
        overlay.show(state: .listening)
        startAudioStreaming()
        playbackManager.startPlayback()
    }

    func realtimeClientDidDisconnect(_ client: RealtimeClient, error: Error?) {
        stopAudioStreaming()
        playbackManager.stopPlayback()

        if let error = error {
            logError("VoiceSessionCoordinator: Disconnected with error: \(error.localizedDescription)")
            overlay.show(state: .error("Disconnected: \(error.localizedDescription)"))
        } else {
            overlay.dismiss()
        }

        setState(.idle)
    }

    func realtimeClient(_ client: RealtimeClient, didChangeState state: RealtimeConnectionState) {
        switch state {
        case .reconnecting:
            overlay.show(state: .thinking)
        case .disconnected:
            setState(.idle)
        default:
            break
        }
    }

    // MARK: - RealtimeClientDelegate: Speech Detection

    func realtimeClientDidDetectSpeechStarted(_ client: RealtimeClient) {
        logDebug("VoiceSessionCoordinator: Speech started")
        appendHistoryEvent(type: .userAudio, metadata: ["state": "speech_started"])

        if sessionState == .speaking {
            handleBargeIn()
        } else {
            setState(.listening)
            overlay.show(state: .listening)
        }
        currentTranscript = ""
    }

    func realtimeClientDidDetectSpeechStopped(_ client: RealtimeClient) {
        logDebug("VoiceSessionCoordinator: Speech stopped")
        appendHistoryEvent(type: .userAudio, metadata: ["state": "speech_stopped"])
        setState(.thinking)
        overlay.show(state: .thinking)
    }

    // MARK: - RealtimeClientDelegate: Audio Response

    func realtimeClient(_ client: RealtimeClient, didReceiveAudioDelta base64Audio: String) {
        if sessionState != .speaking {
            setState(.speaking)
            overlay.show(state: .speaking)
        }
        playbackManager.enqueueAudio(base64Chunk: base64Audio)
    }

    func realtimeClient(_ client: RealtimeClient, didReceiveAudioDone itemId: String) {
        currentAudioItemId = itemId
        logDebug("VoiceSessionCoordinator: Audio output done for item \(itemId)")
    }

    // MARK: - RealtimeClientDelegate: Transcripts

    func realtimeClient(_ client: RealtimeClient, didReceiveAudioTranscriptDelta text: String) {
        lastAssistantTranscript += text
    }

    func realtimeClient(_ client: RealtimeClient, didReceiveAudioTranscriptDone text: String) {
        lastAssistantTranscript = text
        appendHistoryEvent(type: .assistantAudio, text: text)
        logInfo("VoiceSessionCoordinator: Assistant said: \(text.prefix(80))...")
    }

    func realtimeClient(_ client: RealtimeClient, didReceiveTextDone text: String) {
        appendHistoryEvent(type: .assistantText, text: text)
    }

    // MARK: - RealtimeClientDelegate: Response Lifecycle

    func realtimeClient(_ client: RealtimeClient, didReceiveResponseCreated response: [String: Any]) {
        lastAssistantTranscript = ""
        pendingFunctionCalls = []
    }

    func realtimeClient(_ client: RealtimeClient, didReceiveTypedResponseDone response: RealtimeResponseDone) {
        // Check for function calls in the response output
        for call in response.functionCalls {
            pendingFunctionCalls.append(call)
            appendHistoryEvent(
                type: .toolCall,
                metadata: [
                    "call_id": call.callId,
                    "tool": call.name,
                    "arguments": call.arguments
                ]
            )
        }

        // Execute any pending function calls
        if !pendingFunctionCalls.isEmpty {
            executePendingFunctionCalls()
        } else {
            // No function calls — go back to listening
            setState(.listening)
            overlay.show(state: .listening)
        }
    }

    // MARK: - RealtimeClientDelegate: Function Calls

    func realtimeClient(_ client: RealtimeClient, didReceiveFunctionCallArgumentsDelta delta: String, callId: String) {
        // Could display partial arguments in overlay if needed
    }

    func realtimeClient(_ client: RealtimeClient, didReceiveFunctionCallArgumentsDone arguments: String, callId: String) {
        logDebug("VoiceSessionCoordinator: Function call arguments done for \(callId)")
    }

    // MARK: - Tool Execution

    private func executePendingFunctionCalls() {
        guard !pendingFunctionCalls.isEmpty else {
            setState(.listening)
            overlay.show(state: .listening)
            return
        }

        guard let handler = toolCallHandler else {
            // No workspace set — return errors for all calls
            for call in pendingFunctionCalls {
                logError("VoiceSessionCoordinator: No workspace, cannot execute \(call.name)")
                realtimeClient.sendToolResult(callId: call.callId, output: "Error: No workspace attached. Use 'duck attach' to set a workspace.")
                appendHistoryEvent(
                    type: .toolCall,
                    metadata: [
                        "tool": call.name,
                        "error": "No workspace attached"
                    ]
                )
            }
            pendingFunctionCalls = []
            return
        }

        let calls = pendingFunctionCalls
        pendingFunctionCalls = []

        setState(.toolRunning)

        handler.handleFunctionCalls(calls, onToolStart: { [weak self] name in
            self?.overlay.show(state: .toolRunning(name))
            self?.appendHistoryEvent(type: .toolCall, metadata: ["tool": name, "state": "start"])
        }, completion: { [weak self] in
            // State will transition when the next response arrives from the model
            logInfo("VoiceSessionCoordinator: All tool calls completed")
            self?.appendHistoryEvent(type: .toolCall, metadata: ["state": "complete"])
            self?.setState(.thinking)
            self?.overlay.show(state: .thinking)
        })
    }

    // MARK: - RealtimeClientDelegate: Errors

    func realtimeClient(_ client: RealtimeClient, didReceiveError error: [String: Any]) {
        let message = error["message"] as? String ?? "Unknown error"
        logError("VoiceSessionCoordinator: API error: \(message)")
        overlay.show(state: .error(message))
    }
}
