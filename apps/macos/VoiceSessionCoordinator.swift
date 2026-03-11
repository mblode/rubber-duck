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
    var muteInput: Bool { get set }
    var isEchoCancellationActive: Bool { get }
    var isSoftwareAECActive: Bool { get }

    func startStreaming(onChunk: @escaping (String) -> Void, onError: ((Error) -> Void)?)
    func stopStreaming()
    func notifySpeechDetected()
}

extension VoiceAudioManaging {
    var muteInput: Bool {
        get { false }
        set {}
    }
    var isEchoCancellationActive: Bool { false }
    var isSoftwareAECActive: Bool { false }
    func notifySpeechDetected() {}
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
    private let daemonClient: DaemonSocketClient?
    private var cancellables = Set<AnyCancellable>()
    private var conversationHistory: ConversationHistory?
    private var autoAbortOnBargeIn = true
    private var stickyDisconnectErrorMessage: String?
    private var audioStreamingGeneration: UInt64 = 0
    private let bargeInConfirmationDelaySeconds: TimeInterval
    private var pendingBargeInWorkItem: DispatchWorkItem?
    private var seenConversationItemIDs = Set<String>()
    private var didTeardownSessionResources = false
    private var vadSuppressedUntil: Date = .distantPast
    private var hasAcceptedSpeechStart = false
    private var lastAssistantAudioDeltaAt: Date?
    private var lastAssistantPlaybackEndedAt: Date?

    // Track the current response's audio item for truncation on barge-in
    private var currentAudioItemId: String?
    private var currentAudioContentIndex: Int?
    private var currentResponseHasAudioOutput = false
    private var currentResponseAudioDone = false
    private var pendingResponseCompletionReason: String?

    // False-interruption detection: if barge-in fires but the user stops speaking within
    // falseInterruptionWindow without producing a transcript, log it as a false positive.
    // Research: LiveKit false_interruption_timeout=2.0s, Vapi backoffSeconds=1.0s.
    private var bargeInFiredAt: Date?
    private let falseInterruptionWindowSeconds: TimeInterval = 1.5

    // Software input mute: delay unmute until audio queue has drained
    private var inputUnmuteWorkItem: DispatchWorkItem?
    private let unmutePlaybackPollIntervalSeconds: TimeInterval = 0.08
    // Guard windows: how long after the last assistant audio delta to ignore speech_started.
    // Hardware AEC eliminates echo well; software AEC is less reliable; no AEC needs the most protection.
    private let speechStartGuardAfterAssistantAudioSecondsWithAEC: TimeInterval = 0.18
    private let speechStartGuardAfterAssistantAudioSecondsWithoutAEC: TimeInterval = 0.35
    private let postPlaybackSpeechSuppressionWithoutAECSeconds: TimeInterval = 0.6
    // Barge-in confirmation delays: after speech_started fires during assistant playback, wait this long
    // before committing to the interruption. Cancels if speech_stopped arrives first (anti-bounce).
    // Research basis: PNAS linguistics study — modal human turn gap is ~200ms (universal across languages).
    // Vapi production default: 200ms. Industry target: 200–300ms. 250ms is the sweet spot.
    // No-AEC needs slightly more buffer to avoid echo false-positives triggering irreversible truncation.
    private let minimumBargeInConfirmationDelayWithoutAECSeconds: TimeInterval = 0.30
    private let minimumBargeInConfirmationDelayWithSoftwareAECSeconds: TimeInterval = 0.20
    private let speechStartGuardAfterAssistantAudioSecondsWithSoftwareAEC: TimeInterval = 0.22
    // Stall detection: if estimatedUnplayedSamples() doesn't decrease for this long, playback is stuck.
    private let playbackStallThresholdSeconds: TimeInterval = 3.0
    private var pendingListeningTransitionWorkItem: DispatchWorkItem?

    private var isAnyAECActive: Bool {
        audioManager.isEchoCancellationActive || audioManager.isSoftwareAECActive
    }
    private var suppressAssistantAudioUntilNextResponseCreated = false
    private var didHandleTypedResponseDoneForCurrentResponse = false
    private var lastPublishedVoiceState: VoiceSessionState?
    private var lastPublishedVoiceSessionID: String?
    // Track pending function calls from the current response
    private var pendingFunctionCalls: [(callId: String, name: String, arguments: String)] = []
    private var pendingFunctionCallIDs = Set<String>()

    init(
        audioManager: VoiceAudioManaging,
        playbackManager: VoiceAudioPlayback,
        realtimeClient: any RealtimeClientProtocol,
        notificationCenter: NotificationCenter = .default,
        overlay: OverlayPresenting? = nil,
        userDefaults: UserDefaults = .standard,
        bargeInConfirmationDelaySeconds: TimeInterval = 0.25,
        fileManager: FileManager = .default,
        daemonClient: DaemonSocketClient? = nil
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
        self.daemonClient = daemonClient
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
        realtimeClient.tools = ToolDefinitions.allTools()
        realtimeClient.instructions = SystemPrompt.voiceCodingAssistant(workspace: path.path)
        logInfo("VoiceSessionCoordinator: Workspace set to \(path.path)")
    }

    func setSession(_ session: SessionRecord?) {
        activeSessionID = session?.id
        guard let session else {
            conversationHistory = nil
            seenConversationItemIDs.removeAll()
            logInfo("VoiceSessionCoordinator: Cleared active session")
            publishVoiceState(sessionState, force: true)
            return
        }

        let historyURL = URL(fileURLWithPath: session.historyFile)
        do {
            let history = try ConversationHistory(fileURL: historyURL, fileManager: fileManager)
            let recentEvents = try history.readRecent(limit: 50)
            conversationHistory = history
            seenConversationItemIDs.removeAll()
            logInfo("VoiceSessionCoordinator: Active session set to \(session.name) (\(recentEvents.count) history events)")
            publishVoiceState(sessionState, force: true)
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
        didTeardownSessionResources = false
        syncRuntimeSettings()
        setState(.connecting)
        overlay.show(state: .thinking)
        realtimeClient.connect(apiKey: apiKey)

        // Register with daemon (best-effort, non-blocking)
        registerWithDaemon()
    }

    private func registerWithDaemon() {
        guard let daemonClient else { return }
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let workspacePath = workspacePath?.path

        Task {
            // Reconnect if needed (daemon may have restarted since app launched)
            if !daemonClient.isConnected {
                await daemonClient.connect()
            }
            guard daemonClient.isConnected else { return }

            do {
                let _ = try await daemonClient.request(
                    method: "voice_connect",
                    params: [
                        "clientVersion": appVersion,
                        "workspacePath": workspacePath as Any
                    ]
                )
                logInfo("VoiceSessionCoordinator: Registered with daemon")
                publishVoiceState(sessionState, force: true)
            } catch {
                logDebug("VoiceSessionCoordinator: Daemon registration skipped: \(error.localizedDescription)")
            }
        }
    }

    func handleDaemonConnectionRestored() {
        registerWithDaemon()
    }

    func disconnectSession() {
        stickyDisconnectErrorMessage = nil
        teardownSessionResourcesIfNeeded(reason: "disconnectSession", invalidateGeneration: true)
        realtimeClient.disconnect()
        setState(.idle)
        overlay.dismiss()
    }

    var isActive: Bool {
        sessionState != .idle
    }

    /// Injects a text message into the active voice session (e.g., from CLI text input).
    func sendTextMessage(_ text: String) {
        guard sessionState != .idle else {
            logDebug("VoiceSessionCoordinator: Ignoring sendTextMessage — session is idle")
            return
        }
        realtimeClient.sendMessage(text: text)
    }

    /// Starts voice capture when requested by the CLI daemon.
    /// This is start-only (never toggles an active session off).
    func startVoiceFromDaemonRequest() {
        maybeAttachWorkspaceFromCLIMetadata()

        guard sessionState == .idle else {
            logDebug("VoiceSessionCoordinator: Ignoring daemon voice_start — already \(sessionState.rawValue)")
            return
        }

        guard let apiKey = KeychainManager.loadAPIKey() else {
            logInfo("VoiceSessionCoordinator: No API key for daemon voice_start, opening settings")
            SettingsWindowController.shared.show()
            return
        }

        connectAndListen(apiKey: apiKey)
    }

    /// Stops voice capture when requested by the CLI daemon.
    /// Stop applies only when the session matches the currently active session (if provided).
    func stopVoiceFromDaemonRequest(sessionId: String?) {
        if let sessionId, let activeSessionID, sessionId != activeSessionID {
            logDebug("VoiceSessionCoordinator: Ignoring daemon voice_stop for session \(sessionId) while active session is \(activeSessionID)")
            return
        }

        guard sessionState != .idle else {
            return
        }

        disconnectSession()
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
        // Turn detection is server-driven.
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

        let confirmationDelay = effectiveBargeInConfirmationDelaySeconds()
        guard confirmationDelay > 0 else {
            handleBargeIn()
            return
        }

        let delayMs = Int(confirmationDelay * 1000)
        logDebug(
            "VoiceSessionCoordinator: Speech started during playback, confirming for \(delayMs)ms before barge-in (aec_active=\(audioManager.isEchoCancellationActive))"
        )

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingBargeInWorkItem = nil
            guard self.sessionState == .speaking else { return }
            self.handleBargeIn()
        }

        pendingBargeInWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + confirmationDelay, execute: workItem)
    }

    private func effectiveBargeInConfirmationDelaySeconds() -> TimeInterval {
        if audioManager.isSoftwareAECActive && !audioManager.isEchoCancellationActive {
            return max(bargeInConfirmationDelaySeconds, minimumBargeInConfirmationDelayWithSoftwareAECSeconds)
        }
        if isAnyAECActive {
            return bargeInConfirmationDelaySeconds
        }
        return max(bargeInConfirmationDelaySeconds, minimumBargeInConfirmationDelayWithoutAECSeconds)
    }

    private func handleBargeIn() {
        guard autoAbortOnBargeIn else {
            logInfo("VoiceSessionCoordinator: Ignoring barge-in while auto-abort is disabled")
            return
        }

        cancelPendingBargeIn(reason: "confirmed")
        bargeInFiredAt = Date()
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

        // Ignore straggling output_audio deltas from the interrupted response
        // until the server declares a new response boundary.
        suppressAssistantAudioUntilNextResponseCreated = true

        if autoAbortOnBargeIn {
            if let itemId = currentAudioItemId,
               let contentIndex = currentAudioContentIndex {
                let clampedAudioEndMs: Int
                if snapshot.itemScheduledSamples > 0 {
                    let rawAudioEndMs = snapshot.itemPlayedSamples * 1000 / Int(AudioConstants.sampleRate)
                    let itemDurationMs = snapshot.itemScheduledSamples * 1000 / Int(AudioConstants.sampleRate)
                    clampedAudioEndMs = min(max(rawAudioEndMs, 0), itemDurationMs)

                    if clampedAudioEndMs != rawAudioEndMs {
                        logDebug(
                            "VoiceSessionCoordinator: Clamped truncate audioEnd from \(rawAudioEndMs)ms to \(clampedAudioEndMs)ms for item \(itemId)"
                        )
                    }
                } else {
                    clampedAudioEndMs = 0
                }

                realtimeClient.truncateResponse(
                    itemId: itemId,
                    contentIndex: contentIndex,
                    audioEnd: clampedAudioEndMs,
                    sendCancel: false
                )
                logDebug(
                    "VoiceSessionCoordinator: Sent truncate for item \(itemId), audioEnd: \(clampedAudioEndMs)ms, itemScheduled=\(snapshot.itemScheduledSamples), itemUnplayed=\(snapshot.itemUnplayedSamples)"
                )
            } else {
                logDebug("VoiceSessionCoordinator: No active audio item metadata for truncate; relying on server interrupt")
            }
        } else if !autoAbortOnBargeIn {
            logInfo("VoiceSessionCoordinator: Auto-abort on barge-in disabled, skipping truncate")
        }

        // Re-arm the player node so the next response can be scheduled.
        playbackManager.startPlayback()

        setState(.listening)
        overlay.show(state: .listening)
    }

    // MARK: - State Management

    private func setState(_ state: VoiceSessionState) {
        let wasLeavingSpeaking = sessionState == .speaking && state != .speaking
        if state == .speaking || state == .idle || state == .connecting || state == .toolRunning {
            cancelPendingListeningTransition(reason: "state_change_\(state.rawValue)")
        }
        sessionState = state
        logDebug("VoiceSessionCoordinator: State -> \(state.rawValue)")
        publishVoiceState(state)

        if state == .idle {
            clearSpeechTurnState()
            vadSuppressedUntil = .distantPast
            suppressAssistantAudioUntilNextResponseCreated = false
            didHandleTypedResponseDoneForCurrentResponse = false
            pendingResponseCompletionReason = nil
            currentResponseHasAudioOutput = false
            currentResponseAudioDone = false
        }

        if state == .speaking {
            cancelInputUnmute()
            lastAssistantPlaybackEndedAt = nil
            // Reliability-first default: keep the mic muted during playback unless the user
            // has explicitly opted back into barge-in and hardware AEC is available.
            audioManager.muteInput = !autoAbortOnBargeIn || !audioManager.isEchoCancellationActive
        } else if wasLeavingSpeaking {
            lastAssistantPlaybackEndedAt = Date()
            if state == .idle {
                cancelInputUnmute()
                audioManager.muteInput = false
            } else {
                let unmuteDelay: TimeInterval = isAnyAECActive ? 0.4 : 0.1
                let maxAdditionalDelay: TimeInterval = isAnyAECActive ? 0.8 : 0.5
                let suppressionUntil = Date().addingTimeInterval(unmuteDelay + maxAdditionalDelay)
                if suppressionUntil > vadSuppressedUntil {
                    vadSuppressedUntil = suppressionUntil
                }
                scheduleInputUnmute(afterSeconds: unmuteDelay, maxAdditionalDelay: maxAdditionalDelay)
            }
        }
    }

    private func publishVoiceState(_ state: VoiceSessionState, force: Bool = false) {
        guard let daemonClient, daemonClient.isConnected else {
            return
        }

        let sessionID = activeSessionID
        if !force, lastPublishedVoiceState == state, lastPublishedVoiceSessionID == sessionID {
            return
        }

        lastPublishedVoiceState = state
        lastPublishedVoiceSessionID = sessionID

        Task {
            do {
                let _ = try await daemonClient.request(
                    method: "voice_state",
                    params: [
                        "state": state.rawValue,
                        "sessionId": sessionID as Any
                    ]
                )
            } catch {
                logDebug("VoiceSessionCoordinator: Failed to publish voice state: \(error.localizedDescription)")
            }
        }
    }

    private func cancelInputUnmute() {
        inputUnmuteWorkItem?.cancel()
        inputUnmuteWorkItem = nil
    }

    private func scheduleInputUnmute(afterSeconds delay: TimeInterval, maxAdditionalDelay: TimeInterval) {
        let clampedDelay = max(0, delay)
        let clampedMaxAdditionalDelay = max(0, maxAdditionalDelay)
        let deadline = Date().addingTimeInterval(clampedDelay + clampedMaxAdditionalDelay)
        scheduleInputUnmutePoll(afterSeconds: clampedDelay, deadline: deadline)
    }

    private func scheduleInputUnmutePoll(afterSeconds delay: TimeInterval, deadline: Date) {
        cancelInputUnmute()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.inputUnmuteWorkItem = nil

            if self.playbackManager.isPlaying, Date() < deadline {
                self.scheduleInputUnmutePoll(afterSeconds: self.unmutePlaybackPollIntervalSeconds, deadline: deadline)
                return
            }

            self.audioManager.muteInput = false
        }
        inputUnmuteWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelPendingListeningTransition(reason: String) {
        guard let workItem = pendingListeningTransitionWorkItem else {
            return
        }
        workItem.cancel()
        pendingListeningTransitionWorkItem = nil
        logDebug("VoiceSessionCoordinator: Cancelled pending listening transition (\(reason))")
    }

    private func transitionToListeningWhenPlaybackSettles(reason: String) {
        guard sessionState != .idle else {
            return
        }

        if !playbackManager.isPlaying {
            appendHistoryEvent(type: .responseComplete, metadata: ["reason": reason])
            setState(.listening)
            overlay.show(state: .listening)
            return
        }

        let baseMaxWait: TimeInterval = isAnyAECActive ? 0.8 : 3.0
        let cappedMaxWait: TimeInterval = 120.0
        let safetyMargin: TimeInterval = isAnyAECActive ? 0.4 : 0.8

        var maxWait = baseMaxWait
        var initialUnplayedSamples = 0
        if let manager = playbackManager as? AudioPlaybackManager {
            initialUnplayedSamples = manager.estimatedUnplayedSamples()
            let estimatedUnplayed = TimeInterval(initialUnplayedSamples) / AudioConstants.sampleRate
            let adaptiveWait = estimatedUnplayed + safetyMargin
            maxWait = min(max(baseMaxWait, adaptiveWait), cappedMaxWait)
            logInfo(
                "VoiceSessionCoordinator: Waiting for playback settle (\(reason)) timeout=\(String(format: "%.2f", maxWait))s (estimated_unplayed=\(String(format: "%.2f", estimatedUnplayed))s, aec=\(isAnyAECActive), cap=\(String(format: "%.0f", cappedMaxWait))s)"
            )
        }

        let deadline = Date().addingTimeInterval(maxWait)
        scheduleListeningTransitionPoll(
            deadline: deadline,
            reason: reason,
            lastProgressSamples: initialUnplayedSamples,
            lastProgressAt: Date()
        )
    }

    private func scheduleListeningTransitionPoll(deadline: Date, reason: String, lastProgressSamples: Int, lastProgressAt: Date) {
        cancelPendingListeningTransition(reason: "reschedule_\(reason)")

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingListeningTransitionWorkItem = nil

            guard self.sessionState != .idle else { return }
            guard self.sessionState != .toolRunning else { return }

            if self.playbackManager.isPlaying {
                var currentProgressSamples = lastProgressSamples
                var currentProgressAt = lastProgressAt

                if let manager = self.playbackManager as? AudioPlaybackManager {
                    let currentUnplayed = manager.estimatedUnplayedSamples()
                    if currentUnplayed < currentProgressSamples {
                        currentProgressSamples = currentUnplayed
                        currentProgressAt = Date()
                    }

                    let stallDuration = Date().timeIntervalSince(currentProgressAt)
                    if stallDuration >= self.playbackStallThresholdSeconds {
                        logError(
                            "VoiceSessionCoordinator: Playback stalled for \(String(format: "%.1f", stallDuration))s (unplayed=\(currentUnplayed)); forcing stop"
                        )
                        self.playbackManager.stopPlayback()
                    } else if Date() < deadline {
                        self.scheduleListeningTransitionPoll(
                            deadline: deadline,
                            reason: reason,
                            lastProgressSamples: currentProgressSamples,
                            lastProgressAt: currentProgressAt
                        )
                        return
                    } else {
                        logError(
                            "VoiceSessionCoordinator: Playback deadline exceeded (\(reason)); forcing playback stop"
                        )
                        self.playbackManager.stopPlayback()
                    }
                } else {
                    if Date() < deadline {
                        self.scheduleListeningTransitionPoll(
                            deadline: deadline,
                            reason: reason,
                            lastProgressSamples: lastProgressSamples,
                            lastProgressAt: lastProgressAt
                        )
                        return
                    }
                    logError(
                        "VoiceSessionCoordinator: Playback did not settle in time (\(reason)); forcing playback stop"
                    )
                    self.playbackManager.stopPlayback()
                }
            }

            if let manager = self.playbackManager as? AudioPlaybackManager {
                logInfo("VoiceSessionCoordinator: Playback drained naturally (\(reason), \(manager.estimatedUnplayedSamples()) samples remaining)")
            }
            self.appendHistoryEvent(type: .responseComplete, metadata: ["reason": reason])
            self.setState(.listening)
            self.overlay.show(state: .listening)
        }

        pendingListeningTransitionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + unmutePlaybackPollIntervalSeconds, execute: workItem)
    }

    private func clearSpeechTurnState() {
        hasAcceptedSpeechStart = false
        bargeInFiredAt = nil
    }

    private func completeResponseWhenPlaybackReady(reason: String) {
        guard sessionState != .idle else {
            return
        }

        let shouldWaitForAudioDone = currentResponseHasAudioOutput
            && !currentResponseAudioDone
            && playbackManager.isPlaying

        guard !shouldWaitForAudioDone else {
            pendingResponseCompletionReason = reason
            cancelPendingListeningTransition(reason: "await_audio_done_\(reason)")
            logInfo("VoiceSessionCoordinator: Delaying response completion (\(reason)) until audio_done arrives")
            return
        }

        pendingResponseCompletionReason = nil
        transitionToListeningWhenPlaybackSettles(reason: reason)
    }

    private func completePendingResponseAfterAudioDoneIfNeeded() {
        guard let reason = pendingResponseCompletionReason else {
            return
        }
        pendingResponseCompletionReason = nil
        transitionToListeningWhenPlaybackSettles(reason: reason)
    }

    private func invalidateAudioStreamingGeneration() {
        audioStreamingGeneration &+= 1
    }

    private func startNextAudioStreamingGeneration() -> UInt64 {
        invalidateAudioStreamingGeneration()
        return audioStreamingGeneration
    }

    private func isCurrentAudioStreamingGeneration(_ generation: UInt64) -> Bool {
        generation == audioStreamingGeneration
    }

    private func startAudioStreaming(onCaptureBecameReady: (() -> Void)? = nil) {
        let generation = startNextAudioStreamingGeneration()
        var captureReadyNotified = false
        audioManager.startStreaming(
            onChunk: { [weak self] base64Chunk in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.isCurrentAudioStreamingGeneration(generation) else {
                        logDebug("VoiceSessionCoordinator: Ignoring stale audio chunk for generation \(generation)")
                        return
                    }
                    if !captureReadyNotified {
                        captureReadyNotified = true
                        onCaptureBecameReady?()
                    }
                    self.realtimeClient.sendAudio(base64Chunk: base64Chunk)
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.isCurrentAudioStreamingGeneration(generation) else {
                        logDebug("VoiceSessionCoordinator: Ignoring stale audio startup error for generation \(generation)")
                        return
                    }
                    self.handleAudioStartupFailure(error)
                }
            }
        )
    }

    private func handleAudioStartupFailure(_ error: Error) {
        let message = "Microphone error: \(error.localizedDescription)"
        logError("VoiceSessionCoordinator: \(message)")
        stickyDisconnectErrorMessage = message
        teardownSessionResourcesIfNeeded(reason: "audio_startup_failure", invalidateGeneration: true)

        if realtimeClient.connectionState == .disconnected {
            overlay.show(state: .error(message))
            setState(.idle)
            return
        }

        realtimeClient.disconnect()
    }

    private func stopAudioStreaming() {
        audioManager.stopStreaming()
    }

    private func teardownSessionResourcesIfNeeded(reason: String, invalidateGeneration: Bool) {
        if didTeardownSessionResources {
            return
        }
        didTeardownSessionResources = true
        cancelPendingBargeIn(reason: "teardown_\(reason)")
        cancelPendingListeningTransition(reason: "teardown_\(reason)")
        cancelInputUnmute()
        if invalidateGeneration {
            invalidateAudioStreamingGeneration()
        }
        stopAudioStreaming()
        playbackManager.stopPlayback()
    }

    // MARK: - Settings

    private func syncRuntimeSettings() {
        let settings = RuntimeSettingsLoader.load(from: userDefaults)
        realtimeClient.voice = settings.voice
        realtimeClient.model = settings.model
        realtimeClient.interruptResponseOnBargeIn = settings.autoAbortOnBargeIn
        autoAbortOnBargeIn = settings.autoAbortOnBargeIn
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
        didTeardownSessionResources = false
        logInfo("VoiceSessionCoordinator: Connected to Realtime API")
        setState(.listening)
        overlay.show(state: .listening)
        startAudioStreaming(onCaptureBecameReady: { [weak self] in
            self?.playbackManager.startPlayback()
        })
    }

    func realtimeClientDidDisconnect(_ client: any RealtimeClientProtocol, error: Error?) {
        teardownSessionResourcesIfNeeded(reason: "transport_disconnect", invalidateGeneration: true)

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
            pendingFunctionCallIDs.removeAll()
            setState(.idle)
        default:
            break
        }
    }

    // MARK: - RealtimeClientDelegate: Speech Detection

    func realtimeClientDidDetectSpeechStarted(_ client: any RealtimeClientProtocol) {
        let now = Date()

        if audioManager.muteInput {
            logDebug("VoiceSessionCoordinator: Ignoring speech_started while input is muted")
            return
        }

        if sessionState == .speaking, !autoAbortOnBargeIn {
            logDebug("VoiceSessionCoordinator: Ignoring speech_started while auto-abort is disabled")
            return
        }

        if now < vadSuppressedUntil {
            logDebug("VoiceSessionCoordinator: Ignoring speech_started during suppression window")
            return
        }

        if playbackManager.isPlaying, sessionState != .speaking {
            logDebug("VoiceSessionCoordinator: Ignoring speech_started while playback is active outside speaking state")
            return
        }

        if !isAnyAECActive,
           let lastAssistantAudioDeltaAt,
           now.timeIntervalSince(lastAssistantAudioDeltaAt) < speechStartGuardAfterAssistantAudioSecondsWithoutAEC {
            logDebug("VoiceSessionCoordinator: Ignoring speech_started during no-AEC assistant-audio guard window")
            return
        }

        if !isAnyAECActive,
           let lastAssistantPlaybackEndedAt,
           now.timeIntervalSince(lastAssistantPlaybackEndedAt) < postPlaybackSpeechSuppressionWithoutAECSeconds {
            logDebug("VoiceSessionCoordinator: Ignoring speech_started during no-AEC post-playback suppression")
            return
        }

        if sessionState == .speaking,
           isAnyAECActive,
           let lastAssistantAudioDeltaAt,
           now.timeIntervalSince(lastAssistantAudioDeltaAt) < (audioManager.isSoftwareAECActive && !audioManager.isEchoCancellationActive ? speechStartGuardAfterAssistantAudioSecondsWithSoftwareAEC : speechStartGuardAfterAssistantAudioSecondsWithAEC) {
            logDebug("VoiceSessionCoordinator: Ignoring speech_started during assistant-audio guard window")
            return
        }

        logDebug("VoiceSessionCoordinator: Speech started")
        appendHistoryEvent(type: .userAudio, metadata: ["state": "speech_started"])
        hasAcceptedSpeechStart = true
        audioManager.notifySpeechDetected()  // only suppress calibration for confirmed real speech

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
        guard hasAcceptedSpeechStart else {
            logDebug("VoiceSessionCoordinator: Ignoring speech_stopped without accepted speech_started")
            return
        }
        hasAcceptedSpeechStart = false

        logDebug("VoiceSessionCoordinator: Speech stopped")
        appendHistoryEvent(type: .userAudio, metadata: ["state": "speech_stopped"])

        if pendingBargeInWorkItem != nil, sessionState == .speaking {
            cancelPendingBargeIn(reason: "speech_stopped_before_confirmation")
            return
        }

        // Detect false interruptions: barge-in fired but speech stopped quickly with no follow-through.
        // (TTS cannot be restored once truncated, but logging helps tune thresholds.)
        if let firedAt = bargeInFiredAt {
            bargeInFiredAt = nil
            let elapsed = Date().timeIntervalSince(firedAt)
            if elapsed < falseInterruptionWindowSeconds {
                logDebug("VoiceSessionCoordinator: Possible false interruption — speech stopped \(Int(elapsed * 1000))ms after barge-in")
            }
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
        if suppressAssistantAudioUntilNextResponseCreated {
            logDebug("VoiceSessionCoordinator: Dropping stale assistant audio delta while waiting for next response boundary")
            return
        }
        lastAssistantAudioDeltaAt = Date()
        currentResponseHasAudioOutput = true
        currentResponseAudioDone = false
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
        if pendingResponseCompletionReason != nil {
            cancelPendingListeningTransition(reason: "audio_delta_after_completion_signal")
        }
        playbackManager.enqueueAudio(base64Chunk: base64Audio, itemId: currentAudioItemId, contentIndex: currentAudioContentIndex)
    }

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioDone itemId: String, contentIndex: Int?) {
        if suppressAssistantAudioUntilNextResponseCreated {
            logDebug("VoiceSessionCoordinator: Ignoring stale audio_done while waiting for next response boundary")
            return
        }
        if !itemId.isEmpty {
            currentAudioItemId = itemId
        }
        if let contentIndex {
            currentAudioContentIndex = contentIndex
        }
        currentResponseAudioDone = true
        logDebug("VoiceSessionCoordinator: Audio output done for item \(itemId)")
        completePendingResponseAfterAudioDoneIfNeeded()
    }

    // MARK: - RealtimeClientDelegate: Transcripts

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioTranscriptDelta text: String) {
        lastAssistantTranscript += text
        if !text.isEmpty {
            appendHistoryEvent(type: .assistantTextDelta, text: text)
        }
    }

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioTranscriptDone text: String) {
        lastAssistantTranscript = text
        appendHistoryEvent(type: .assistantTextEnd)
        appendHistoryEvent(type: .assistantAudio, text: text)
        logInfo("VoiceSessionCoordinator: Assistant said: \(text.prefix(80))...")
    }

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveTextDone text: String) {
        if text != lastAssistantTranscript {
            appendHistoryEvent(type: .assistantText, text: text)
        }
        appendHistoryEvent(type: .assistantTextEnd)
    }

    // MARK: - RealtimeClientDelegate: Response Lifecycle

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveResponseCreated response: [String: Any]) {
        suppressAssistantAudioUntilNextResponseCreated = false
        didHandleTypedResponseDoneForCurrentResponse = false
        lastAssistantTranscript = ""
        pendingFunctionCalls = []
        pendingFunctionCallIDs.removeAll()
        pendingResponseCompletionReason = nil
        currentAudioItemId = nil
        currentAudioContentIndex = nil
        currentResponseHasAudioOutput = false
        currentResponseAudioDone = false
        // Keep lastAssistantAudioDeltaAt — it will be overwritten naturally by the first
        // audio delta of the new response. Clearing it here creates a guard-free window
        // between response_created and the first delta where echo can trigger false barge-in.
        lastAssistantPlaybackEndedAt = nil
        clearSpeechTurnState()
    }

    @discardableResult
    private func enqueueFunctionCallIfNeeded(callId: String, name: String, arguments: String) -> Bool {
        guard !callId.isEmpty, !name.isEmpty else {
            return false
        }
        guard !pendingFunctionCallIDs.contains(callId) else {
            return false
        }

        pendingFunctionCallIDs.insert(callId)
        pendingFunctionCalls.append((callId: callId, name: name, arguments: arguments))
        appendHistoryEvent(
            type: .toolCall,
            metadata: [
                "call_id": callId,
                "tool": name,
                "arguments": arguments
            ]
        )
        return true
    }

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveTypedResponseDone response: RealtimeResponseDone) {
        didHandleTypedResponseDoneForCurrentResponse = true

        // Check for function calls in the response output
        for call in response.functionCalls {
            _ = enqueueFunctionCallIfNeeded(callId: call.callId, name: call.name, arguments: call.arguments)
        }

        // Execute any pending function calls
        if !pendingFunctionCalls.isEmpty {
            Task { await executePendingFunctionCallsViaDaemon() }
        } else {
            completeResponseWhenPlaybackReady(reason: "typed_response_done")
        }
    }

    func realtimeClientDidReceiveResponseDone(_ client: any RealtimeClientProtocol) {
        if didHandleTypedResponseDoneForCurrentResponse {
            return
        }
        if !pendingFunctionCalls.isEmpty && sessionState != .toolRunning {
            Task { await executePendingFunctionCallsViaDaemon() }
            return
        }
        if pendingFunctionCalls.isEmpty && sessionState != .toolRunning {
            completeResponseWhenPlaybackReady(reason: "response_done")
        }
    }

    func realtimeClientDidReceiveResponseCancelled(_ client: any RealtimeClientProtocol) {
        pendingFunctionCalls = []
        pendingFunctionCallIDs.removeAll()
        pendingResponseCompletionReason = nil
        clearSpeechTurnState()
        if sessionState == .thinking || sessionState == .speaking {
            transitionToListeningWhenPlaybackSettles(reason: "response_cancelled")
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

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveConversationItemDone item: [String: Any]) {
        guard let text = extractUserText(from: item) else {
            return
        }
        appendUserTextIfNew(text, itemID: item["id"] as? String)
    }

    func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveFunctionCallItem call: RealtimeFunctionCallItem) {
        guard enqueueFunctionCallIfNeeded(callId: call.callId, name: call.name, arguments: call.arguments) else {
            return
        }
    }

    // MARK: - Tool Execution

    private func executePendingFunctionCallsViaDaemon() async {
        guard !pendingFunctionCalls.isEmpty else {
            transitionToListeningWhenPlaybackSettles(reason: "no_pending_tool_calls")
            return
        }

        let calls = pendingFunctionCalls
        pendingFunctionCalls = []
        pendingFunctionCallIDs.removeAll()
        setState(.toolRunning)

        guard let daemon = daemonClient,
              daemon.isConnected,
              let wsPath = workspacePath?.path else {
            // Daemon not connected — return error for all calls
            for call in calls {
                realtimeClient.sendToolResult(
                    callId: call.callId,
                    output: "Error: CLI daemon not running. Start it with `duck [path]`."
                )
            }
            realtimeClient.requestModelResponse()
            setState(.thinking)
            overlay.show(state: .thinking)
            return
        }

        for call in calls {
            overlay.show(state: .toolRunning(call.name))
            appendHistoryEvent(type: .toolCall, metadata: ["tool": call.name, "state": "start"])

            do {
                let data = try await daemon.request(
                    method: "voice_tool_call",
                    params: [
                        "callId": call.callId,
                        "toolName": call.name,
                        "arguments": call.arguments,
                        "workspacePath": wsPath
                    ]
                )
                let result = data["result"] as? String ?? "Error: No result from daemon"
                realtimeClient.sendToolResult(callId: call.callId, output: result)
            } catch {
                logError("VoiceSessionCoordinator: Daemon tool call failed for \(call.name): \(error.localizedDescription)")
                realtimeClient.sendToolResult(
                    callId: call.callId,
                    output: "Error: Tool execution failed: \(error.localizedDescription)"
                )
            }
        }

        logInfo("VoiceSessionCoordinator: All tool calls completed via daemon")
        appendHistoryEvent(type: .toolCall, metadata: ["state": "complete"])
        realtimeClient.requestModelResponse()
        setState(.thinking)
        overlay.show(state: .thinking)
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
            || code == "conversation_already_has_active_response"
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
                transitionToListeningWhenPlaybackSettles(reason: "benign_interruption_race_error")
            }
            return
        }

        teardownSessionResourcesIfNeeded(reason: "api_error", invalidateGeneration: true)

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
