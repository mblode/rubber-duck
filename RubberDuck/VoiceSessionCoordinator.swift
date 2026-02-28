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
    func enqueueAudio(base64Chunk: String, itemId: String?, contentIndex: Int?)
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
    private let realtimeClient: any RealtimeClientProtocol
    private let overlay: OverlayPresenting
    private let notificationCenter: NotificationCenter
    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let cliMetadataReader: CLIMetadataReader
    private var cancellables = Set<AnyCancellable>()
    private var toolOrchestrator: ToolOrchestrator?
    private var conversationHistory: ConversationHistory?
    private var autoAbortOnBargeIn = true
    private var stickyDisconnectErrorMessage: String?
    private let bargeInConfirmationDelaySeconds: TimeInterval
    private var pendingBargeInWorkItem: DispatchWorkItem?
    private var seenConversationItemIDs = Set<String>()

    // Track the current response's audio item for truncation on barge-in
    private var currentAudioItemId: String?
    private var currentAudioContentIndex: Int?

    // Track pending function calls from the current response
    private var pendingFunctionCalls: [(callId: String, name: String, arguments: String)] = []

    init(
        audioManager: VoiceAudioManaging,
        playbackManager: VoiceAudioPlayback,
        realtimeClient: any RealtimeClientProtocol,
        notificationCenter: NotificationCenter = .default,
        overlay: OverlayPresenting? = nil,
        userDefaults: UserDefaults = .standard,
        bargeInConfirmationDelaySeconds: TimeInterval = 0.35,
        fileManager: FileManager = .default
    ) {
        logInfo("VoiceSessionCoordinator: Initializing")
        self.audioManager = audioManager
        self.playbackManager = playbackManager
        self.realtimeClient = realtimeClient
        self.notificationCenter = notificationCenter
        self.overlay = overlay ?? LiveOverlayPresenter.shared
        self.userDefaults = userDefaults
        self.bargeInConfirmationDelaySeconds = max(0, bargeInConfirmationDelaySeconds)
        self.fileManager = fileManager
        self.cliMetadataReader = CLIMetadataReader(
            metadataURL: AppSupportPaths.metadataFileURL(fileManager: fileManager)
        )

        realtimeClient.delegate = self

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
        toolOrchestrator = ToolOrchestrator(toolExecutor: executor, resultSender: realtimeClient)
        realtimeClient.tools = ToolDefinitions.allTools()
        logInfo("VoiceSessionCoordinator: Workspace set to \(path.path)")
    }

    func setSession(_ session: SessionRecord?) {
        activeSessionID = session?.id
        guard let session else {
            conversationHistory = nil
            seenConversationItemIDs.removeAll()
            logInfo("VoiceSessionCoordinator: Cleared active session")
            return
        }

        let historyURL = URL(fileURLWithPath: session.historyFile)
        do {
            let history = try ConversationHistory(fileURL: historyURL, fileManager: fileManager)
            let recentEvents = try history.readRecent(limit: 50)
            conversationHistory = history
            seenConversationItemIDs.removeAll()
            logInfo("VoiceSessionCoordinator: Active session set to \(session.name) (\(recentEvents.count) history events)")
        } catch {
            conversationHistory = nil
            seenConversationItemIDs.removeAll()
            logError("VoiceSessionCoordinator: Failed to bind session history: \(error.localizedDescription)")
        }
    }

    // MARK: - Public API

    func connectAndListen(apiKey: String) {
        guard sessionState == .idle else {
            logDebug("VoiceSessionCoordinator: Not idle, ignoring connect request")
            return
        }

        if realtimeClient.connectionState != .disconnected {
            logInfo("VoiceSessionCoordinator: Transport was not disconnected while idle, forcing reset before connect")
            realtimeClient.disconnect()
        }

        stickyDisconnectErrorMessage = nil
        syncRuntimeSettings()
        setState(.connecting)
        overlay.show(state: .thinking)
        realtimeClient.connect(apiKey: apiKey)
    }

    func disconnectSession() {
        cancelPendingBargeIn(reason: "disconnectSession")
        stickyDisconnectErrorMessage = nil
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

        case .listening, .speaking, .connecting, .thinking, .toolRunning:
            // Toggle off: disconnect the session
            disconnectSession()
        }
    }

    private func handleHotkeyUp() {
        // With semantic VAD, turn detection is automatic.
        // Hotkey-up is a no-op.
    }

    // MARK: - Barge-in

    private func cancelPendingBargeIn(reason: String) {
        guard let pendingBargeInWorkItem else { return }
        pendingBargeInWorkItem.cancel()
        self.pendingBargeInWorkItem = nil
        logDebug("VoiceSessionCoordinator: Cancelled pending barge-in (\(reason))")
    }

    private func scheduleConfirmedBargeIn() {
        guard sessionState == .speaking else { return }

        if pendingBargeInWorkItem != nil {
            return
        }

        guard bargeInConfirmationDelaySeconds > 0 else {
            handleBargeIn()
            return
        }

        let delayMs = Int(bargeInConfirmationDelaySeconds * 1000)
        logDebug("VoiceSessionCoordinator: Speech started during playback, confirming for \(delayMs)ms before barge-in")

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingBargeInWorkItem = nil
            guard self.sessionState == .speaking else { return }
            self.handleBargeIn()
        }

        pendingBargeInWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + bargeInConfirmationDelaySeconds, execute: workItem)
    }

    private func handleBargeIn() {
        cancelPendingBargeIn(reason: "confirmed")
        logInfo("VoiceSessionCoordinator: Barge-in — stopping playback")

        let snapshot: AudioPlaybackStopSnapshot
        if let manager = playbackManager as? AudioPlaybackManager {
            snapshot = manager.stopImmediatelySnapshot(itemId: currentAudioItemId, contentIndex: currentAudioContentIndex)
        } else {
            let unplayedSamples = playbackManager.stopImmediately()
            let totalScheduledSamples = max(unplayedSamples, 0)
            snapshot = AudioPlaybackStopSnapshot(
                totalScheduledSamples: totalScheduledSamples,
                totalPlayedSamples: 0,
                totalUnplayedSamples: unplayedSamples,
                itemScheduledSamples: 0,
                itemPlayedSamples: 0,
                itemUnplayedSamples: 0
            )
        }

        if autoAbortOnBargeIn,
           let itemId = currentAudioItemId,
           let contentIndex = currentAudioContentIndex,
           snapshot.itemScheduledSamples > 0 {
            let rawAudioEndMs = snapshot.itemPlayedSamples * 1000 / Int(AudioConstants.sampleRate)
            let itemDurationMs = snapshot.itemScheduledSamples * 1000 / Int(AudioConstants.sampleRate)
            let clampedAudioEndMs = min(max(rawAudioEndMs, 0), itemDurationMs)

            if clampedAudioEndMs != rawAudioEndMs {
                logDebug(
                    "VoiceSessionCoordinator: Clamped truncate audioEnd from \(rawAudioEndMs)ms to \(clampedAudioEndMs)ms for item \(itemId)"
                )
            }

            // Semantic VAD already cancels active responses server-side.
            realtimeClient.truncateResponse(
                itemId: itemId,
                contentIndex: contentIndex,
                audioEnd: clampedAudioEndMs,
                sendCancel: false
            )
            logDebug(
                "VoiceSessionCoordinator: Sent truncate for item \(itemId), audioEnd: \(clampedAudioEndMs)ms, itemScheduled=\(snapshot.itemScheduledSamples), itemUnplayed=\(snapshot.itemUnplayedSamples)"
            )
        } else if !autoAbortOnBargeIn {
            logInfo("VoiceSessionCoordinator: Auto-abort on barge-in disabled, skipping truncate")
        } else {
            logDebug(
                "VoiceSessionCoordinator: Skipping truncate on barge-in (itemId=\(currentAudioItemId ?? "none"), contentIndex=\(currentAudioContentIndex.map(String.init) ?? "none"), itemScheduled=\(snapshot.itemScheduledSamples))"
            )
        }

        // Re-arm the player node so the next response can be scheduled.
        playbackManager.startPlayback()

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
                    self?.handleAudioStartupFailure(error)
                }
            }
        )
    }

    private func handleAudioStartupFailure(_ error: Error) {
        let message = "Microphone error: \(error.localizedDescription)"
        logError("VoiceSessionCoordinator: \(message)")
        stickyDisconnectErrorMessage = message
        stopAudioStreaming()
        playbackManager.stopPlayback()

        if realtimeClient.connectionState == .disconnected {
            overlay.show(state: .error(message))
            setState(.idle)
            return
        }

        realtimeClient.disconnect()
    }

    private func stopAudioStreaming() {
        if audioManager.isStreaming {
            audioManager.stopStreaming()
        }
    }

    // MARK: - Settings

    private func syncRuntimeSettings() {
        let settings = RuntimeSettingsLoader.load(from: userDefaults)
        realtimeClient.voice = settings.voice
        realtimeClient.model = settings.model
        realtimeClient.vadEagerness = settings.vadEagerness
        autoAbortOnBargeIn = settings.autoAbortOnBargeIn
        toolOrchestrator?.setSafeMode(settings.safeModeEnabled)
    }

    // MARK: - Workspace Attachment

    private func maybeAttachWorkspaceFromCLIMetadata() {
        guard let selection = cliMetadataReader.loadSelection() else {
            return
        }

        let targetPath = selection.workspaceURL.standardizedFileURL.path
        let currentPath = workspacePath?.standardizedFileURL.path
        if currentPath == targetPath {
            syncSessionFromCLIMetadata(selection.session)
            return
        }

        logInfo("VoiceSessionCoordinator: Syncing workspace from CLI metadata: \(targetPath)")
        setWorkspace(selection.workspaceURL)
        syncSessionFromCLIMetadata(selection.session)
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

    private func extractUserText(from item: [String: Any]) -> String? {
        guard (item["type"] as? String) == "message" else {
            return nil
        }

        guard (item["role"] as? String) == "user" else {
            return nil
        }

        var parts: [String] = []
        if let content = item["content"] as? [[String: Any]] {
            for part in content {
                if let text = part["text"] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        parts.append(trimmed)
                    }
                }

                if let transcript = part["transcript"] as? String {
                    let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        parts.append(trimmed)
                    }
                }

                if let inputAudio = part["input_audio"] as? [String: Any],
                   let transcript = inputAudio["transcript"] as? String {
                    let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        parts.append(trimmed)
                    }
                }

                if let inputText = part["input_text"] as? String {
                    let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        parts.append(trimmed)
                    }
                }
            }
        }

        if parts.isEmpty, let fallbackText = item["text"] as? String {
            let trimmed = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
        }

        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: "\n")
    }

    private func markConversationItemSeen(_ itemID: String?) -> Bool {
        guard let itemID, !itemID.isEmpty else {
            return true
        }

        if seenConversationItemIDs.contains(itemID) {
            return false
        }
        seenConversationItemIDs.insert(itemID)
        if seenConversationItemIDs.count > 1024 {
            seenConversationItemIDs.removeAll()
        }
        return true
    }

    private func appendUserTextIfNew(_ text: String, itemID: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        guard markConversationItemSeen(itemID) else {
            return
        }

        currentTranscript = trimmed
        appendHistoryEvent(type: .userText, text: trimmed)
    }

    private func syncSessionFromCLIMetadata(_ session: CLIMetadataFile.Session?) {
        guard let session else {
            return
        }

        if activeSessionID == session.id, conversationHistory != nil {
            return
        }

        let historyURL = AppSupportPaths.sessionsDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("\(session.id).jsonl", isDirectory: false)

        do {
            let history = try ConversationHistory(fileURL: historyURL, fileManager: fileManager)
            let recentEvents = try history.readRecent(limit: 50)
            activeSessionID = session.id
            conversationHistory = history
            seenConversationItemIDs.removeAll()
            let sessionLabel = session.name ?? session.id
            logInfo("VoiceSessionCoordinator: Synced active session from CLI metadata: \(sessionLabel) (\(recentEvents.count) history events)")
        } catch {
            logError("VoiceSessionCoordinator: Failed to sync CLI session history: \(error.localizedDescription)")
        }
    }

    // MARK: - RealtimeClientDelegate: Connection

    func realtimeClientDidConnect(_ client: any RealtimeClientProtocol) {
        logInfo("VoiceSessionCoordinator: Transport connected, waiting for session readiness")
        setState(.connecting)
        overlay.show(state: .thinking)
    }

    func realtimeClientDidBecomeReady(_ client: any RealtimeClientProtocol) {
        stickyDisconnectErrorMessage = nil
        logInfo("VoiceSessionCoordinator: Connected to Realtime API")
        setState(.listening)
        overlay.show(state: .listening)
        startAudioStreaming()
        playbackManager.startPlayback()
    }

    func realtimeClientDidDisconnect(_ client: any RealtimeClientProtocol, error: Error?) {
        cancelPendingBargeIn(reason: "transport_disconnect")
        stopAudioStreaming()
        playbackManager.stopPlayback()

        if let stickyError = stickyDisconnectErrorMessage {
            logError("VoiceSessionCoordinator: Disconnected with preserved API error: \(stickyError)")
            overlay.show(state: .error(stickyError))
        } else if let error = error {
            logError("VoiceSessionCoordinator: Disconnected with error: \(error.localizedDescription)")
            overlay.show(state: .error("Disconnected: \(error.localizedDescription)"))
        } else {
            overlay.dismiss()
        }

        setState(.idle)
    }

    func realtimeClient(_ client: any RealtimeClientProtocol, didChangeState state: RealtimeConnectionState) {
        switch state {
        case .reconnecting:
            setState(.connecting)
            overlay.show(state: .thinking)
        case .disconnected:
            cancelPendingBargeIn(reason: "state_disconnected")
            currentAudioItemId = nil
            currentAudioContentIndex = nil
            pendingFunctionCalls = []
            setState(.idle)
        default:
            break
        }
    }

    // MARK: - RealtimeClientDelegate: Speech Detection

    func realtimeClientDidDetectSpeechStarted(_ client: any RealtimeClientProtocol) {
        logDebug("VoiceSessionCoordinator: Speech started")
        appendHistoryEvent(type: .userAudio, metadata: ["state": "speech_started"])

        if sessionState == .speaking {
            scheduleConfirmedBargeIn()
        } else {
            cancelPendingBargeIn(reason: "speech_started_non_speaking")
            setState(.listening)
            overlay.show(state: .listening)
        }
        currentTranscript = ""
    }

    func realtimeClientDidDetectSpeechStopped(_ client: any RealtimeClientProtocol) {
        logDebug("VoiceSessionCoordinator: Speech stopped")
        appendHistoryEvent(type: .userAudio, metadata: ["state": "speech_stopped"])

        if pendingBargeInWorkItem != nil, sessionState == .speaking {
            cancelPendingBargeIn(reason: "speech_stopped_before_confirmation")
            return
        }

        setState(.thinking)
        overlay.show(state: .thinking)
    }

    // MARK: - RealtimeClientDelegate: Audio Response

    func realtimeClient(_ client: any RealtimeClientProtocol, didUpdateActiveAudioOutput itemId: String?, contentIndex: Int?) {
        if let itemId, !itemId.isEmpty {
            currentAudioItemId = itemId
        }
        if let contentIndex {
            currentAudioContentIndex = contentIndex
        } else if currentAudioContentIndex == nil {
            currentAudioContentIndex = 0
        }
    }

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioDelta base64Audio: String, itemId: String?, contentIndex: Int?) {
        if let itemId, !itemId.isEmpty {
            currentAudioItemId = itemId
        }
        if let contentIndex {
            currentAudioContentIndex = contentIndex
        } else if currentAudioContentIndex == nil {
            currentAudioContentIndex = 0
        }

        if sessionState != .speaking {
            setState(.speaking)
            overlay.show(state: .speaking)
        }
        playbackManager.enqueueAudio(base64Chunk: base64Audio, itemId: currentAudioItemId, contentIndex: currentAudioContentIndex)
    }

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioDone itemId: String, contentIndex: Int?) {
        if !itemId.isEmpty {
            currentAudioItemId = itemId
        }
        if let contentIndex {
            currentAudioContentIndex = contentIndex
        }
        logDebug("VoiceSessionCoordinator: Audio output done for item \(itemId)")
    }

    // MARK: - RealtimeClientDelegate: Transcripts

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioTranscriptDelta text: String) {
        lastAssistantTranscript += text
    }

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioTranscriptDone text: String) {
        lastAssistantTranscript = text
        appendHistoryEvent(type: .assistantAudio, text: text)
        logInfo("VoiceSessionCoordinator: Assistant said: \(text.prefix(80))...")
    }

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveTextDone text: String) {
        appendHistoryEvent(type: .assistantText, text: text)
    }

    // MARK: - RealtimeClientDelegate: Response Lifecycle

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveResponseCreated response: [String: Any]) {
        lastAssistantTranscript = ""
        pendingFunctionCalls = []
        currentAudioItemId = nil
        currentAudioContentIndex = nil
    }

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveTypedResponseDone response: RealtimeResponseDone) {
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

    func realtimeClientDidReceiveResponseDone(_ client: any RealtimeClientProtocol) {
        if pendingFunctionCalls.isEmpty && sessionState != .toolRunning {
            setState(.listening)
            overlay.show(state: .listening)
        }
    }

    func realtimeClientDidReceiveResponseCancelled(_ client: any RealtimeClientProtocol) {
        pendingFunctionCalls = []
        if sessionState == .thinking || sessionState == .speaking {
            setState(.listening)
            overlay.show(state: .listening)
        }
    }

    // MARK: - RealtimeClientDelegate: Function Calls

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveFunctionCallArgumentsDelta delta: String, callId: String) {
        // Could display partial arguments in overlay if needed
    }

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveFunctionCallArgumentsDone arguments: String, callId: String) {
        logDebug("VoiceSessionCoordinator: Function call arguments done for \(callId)")
    }

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveInputAudioTranscriptionDone text: String, itemId: String?) {
        appendUserTextIfNew(text, itemID: itemId)
    }

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveConversationItemCreated item: [String: Any]) {
        guard let text = extractUserText(from: item) else {
            return
        }
        appendUserTextIfNew(text, itemID: item["id"] as? String)
    }

    // MARK: - Tool Execution

    private func executePendingFunctionCalls() {
        guard !pendingFunctionCalls.isEmpty else {
            setState(.listening)
            overlay.show(state: .listening)
            return
        }

        guard let handler = toolOrchestrator else {
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
            realtimeClient.requestModelResponse()
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

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveError error: [String: Any]) {
        let message = error["message"] as? String ?? "Unknown error"
        let retryable = (error["_retryable"] as? Bool) ?? false
        let classification = (error["_classification"] as? String) ?? "unknown"
        let code = (error["code"] as? String ?? "").lowercased()
        let offendingEventType = (error["_offending_event_type"] as? String ?? "").lowercased()
        logError("VoiceSessionCoordinator: API error (retryable=\(retryable), classification=\(classification)): \(message)")

        let interruptionRaceError =
            code == "response_cancel_not_active"
            || code == "item_truncate_invalid_item_id"
            || (code == "invalid_value"
                && offendingEventType == "conversation.item.truncate"
                && message.lowercased().contains("already shorter than"))
            || (code == "invalid_value"
                && offendingEventType == "conversation.item.truncate"
                && message.lowercased().contains("item with item_id not found"))

        if interruptionRaceError {
            logInfo("VoiceSessionCoordinator: Ignoring benign interruption race error (\(code))")
            currentAudioItemId = nil
            currentAudioContentIndex = nil
            if sessionState == .thinking || sessionState == .speaking {
                setState(.listening)
                overlay.show(state: .listening)
            }
            return
        }

        stopAudioStreaming()
        playbackManager.stopPlayback()

        if retryable {
            setState(.connecting)
            overlay.show(state: .thinking)
            return
        }

        stickyDisconnectErrorMessage = message
        realtimeClient.disconnect()
    }
}

// MARK: - HotkeyManagerDelegate

extension VoiceSessionCoordinator: HotkeyManagerDelegate {
    func hotkeyManagerDidDetectKeyDown(_ manager: HotkeyManager) {
        handleHotkeyDown()
    }

    func hotkeyManagerDidDetectKeyUp(_ manager: HotkeyManager) {
        handleHotkeyUp()
    }
}
