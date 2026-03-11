#if os(iOS)
import Foundation

@MainActor
public final class RemoteIOSVoiceSessionModel: NSObject, ObservableObject, RealtimeClientDelegate {
    @Published public private(set) var liveConversation: [RemoteConversationEntry] = []
    @Published public private(set) var voiceState: RemoteDaemonVoiceState = .idle
    @Published public private(set) var isPressingToTalk = false
    @Published public private(set) var hasAPIKey = false
    @Published public private(set) var isPreparing = false
    @Published public private(set) var lastError: String?

    private let daemonChannel: RemoteVoiceDaemonChannel
    private let credentialStore: RemoteOpenAIKeychainStore
    private let realtimeClient: RealtimeClient
    private let audioCapture = IOSAudioCaptureManager()
    private let audioPlayback = IOSAudioPlaybackManager()

    private var activeHost: PairedRemoteHost?
    private var activeSession: RemoteSessionSummary?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var currentAssistantEntryID: String?
    private var seededSignature: String?
    private var hasCapturedAudio = false
    private var sessionPrepared = false
    private var pendingToolCallResponse = false

    public init(
        daemonChannel: RemoteVoiceDaemonChannel = RemoteVoiceDaemonChannel(),
        credentialStore: RemoteOpenAIKeychainStore = RemoteOpenAIKeychainStore(),
        realtimeClient: RealtimeClient = RealtimeClient()
    ) {
        self.daemonChannel = daemonChannel
        self.credentialStore = credentialStore
        self.realtimeClient = realtimeClient
        super.init()
        self.realtimeClient.delegate = self
        self.hasAPIKey = credentialStore.loadAPIKey() != nil
    }

    public func syncContext(
        host: PairedRemoteHost?,
        session: RemoteSessionSummary?,
        seedConversation: [RemoteConversationEntry]
    ) {
        let nextSignature = [
            host?.id ?? "none",
            session?.id ?? "none",
            String(seedConversation.count),
            seedConversation.last?.id ?? "empty",
        ].joined(separator: "::")

        if seededSignature != nextSignature {
            liveConversation = seedConversation
            currentAssistantEntryID = nil
            seededSignature = nextSignature
        }

        let hostChanged = activeHost?.id != host?.id
        let sessionChanged = activeSession?.id != session?.id
        activeHost = host
        activeSession = session

        if hostChanged || sessionChanged {
            Task {
                await teardownVoiceSession()
            }
        }
    }

    public func saveAPIKey(_ apiKey: String) throws {
        do {
            try credentialStore.saveAPIKey(apiKey)
            hasAPIKey = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    public func deleteAPIKey() throws {
        do {
            try credentialStore.deleteAPIKey()
            hasAPIKey = false
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    public func clearError() {
        lastError = nil
    }

    public func beginPressToTalk() async {
        guard !isPressingToTalk else {
            return
        }

        do {
            isPreparing = true
            try await prepareVoiceSessionIfNeeded()
            guard let activeSession else {
                throw RemoteDaemonError.noActiveSession
            }

            try await daemonChannel.startVoice(sessionId: activeSession.id)
            try await updateVoiceState(.listening)
            try await audioCapture.startStreaming { [weak self] chunk in
                Task { @MainActor in
                    guard let self else { return }
                    self.hasCapturedAudio = true
                    self.realtimeClient.sendAudio(base64Chunk: chunk)
                }
            }
            isPressingToTalk = true
            isPreparing = false
        } catch {
            isPreparing = false
            presentError(error)
        }
    }

    public func endPressToTalk() async {
        guard isPressingToTalk else {
            return
        }

        audioCapture.stopStreaming()
        isPressingToTalk = false

        guard hasCapturedAudio else {
            try? await updateVoiceState(.idle)
            return
        }

        hasCapturedAudio = false
        realtimeClient.commitAudioBuffer()
        realtimeClient.requestModelResponse()
        try? await updateVoiceState(.thinking)
    }

    public func teardownVoiceSession() async {
        isPressingToTalk = false
        isPreparing = false
        hasCapturedAudio = false
        sessionPrepared = false
        readyContinuation?.resume(throwing: RemoteDaemonError.transportUnavailable)
        readyContinuation = nil
        audioCapture.stopStreaming()
        audioPlayback.stop()
        realtimeClient.disconnect()
        await daemonChannel.disconnect()
        voiceState = .idle
    }

    private func prepareVoiceSessionIfNeeded() async throws {
        guard let activeHost else {
            throw RemoteDaemonError.noPairedHost
        }
        guard let activeSession else {
            throw RemoteDaemonError.noActiveSession
        }

        guard let apiKey = credentialStore.loadAPIKey() else {
            throw RemoteDaemonError.messageFailed("Add an OpenAI API key to start voice mode.")
        }
        hasAPIKey = true

        if sessionPrepared, realtimeClient.connectionState == .connected {
            return
        }

        try await daemonChannel.connect(to: activeHost) { [weak self] event in
            Task { @MainActor in
                self?.handleDaemonEvent(event)
            }
        }
        try await daemonChannel.registerVoiceClient(
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            workspacePath: activeSession.workspacePath
        )

        realtimeClient.model = "gpt-realtime-1.5"
        realtimeClient.voice = "marin"
        realtimeClient.tools = RemoteToolDefinitions.allTools()
        realtimeClient.instructions = RemoteSystemPrompt.voiceCodingAssistant(
            workspace: activeSession.workspacePath
        )
        realtimeClient.turnDetectionMode = .manual

        if realtimeClient.connectionState == .connected {
            sessionPrepared = true
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readyContinuation = continuation
            realtimeClient.connect(apiKey: apiKey)
        }

        sessionPrepared = true
    }

    private func handleDaemonEvent(_ event: RemoteVoiceDaemonEvent) {
        switch event {
        case .ready:
            return
        case .voiceStart:
            voiceState = .connecting
        case .voiceStop:
            Task {
                await teardownVoiceSession()
            }
        case .voiceSay(let text, _):
            appendConversationEntry(
                RemoteConversationEntry(
                    role: .user,
                    text: text,
                    timestamp: .now,
                    metadata: ["source": "daemon"]
                )
            )
            realtimeClient.sendMessage(text: text)
            Task {
                try? await updateVoiceState(.thinking)
            }
        }
    }

    private func appendConversationEntry(_ entry: RemoteConversationEntry) {
        liveConversation.append(entry)
        seededSignature = nil
    }

    private func updateAssistantTranscript(delta: String, isFinal: Bool) {
        guard !delta.isEmpty else {
            return
        }

        if let currentAssistantEntryID,
           let index = liveConversation.lastIndex(where: { $0.id == currentAssistantEntryID }) {
            let current = liveConversation[index]
            liveConversation[index] = RemoteConversationEntry(
                id: current.id,
                role: .assistant,
                text: isFinal ? delta : current.text + delta,
                timestamp: current.timestamp,
                metadata: current.metadata
            )
        } else {
            let entry = RemoteConversationEntry(
                role: .assistant,
                text: delta,
                timestamp: .now,
                metadata: ["source": "voice"]
            )
            currentAssistantEntryID = entry.id
            liveConversation.append(entry)
        }

        if isFinal {
            currentAssistantEntryID = nil
        }

        seededSignature = nil
    }

    private func updateVoiceState(_ state: RemoteDaemonVoiceState) async throws {
        guard let activeSession else {
            return
        }
        voiceState = state
        try await daemonChannel.updateVoiceState(state, sessionId: activeSession.id)
    }

    private func presentError(_ error: Error) {
        lastError = error.localizedDescription
    }

    private func handleToolCalls(_ calls: [(callId: String, name: String, arguments: String)]) {
        guard !calls.isEmpty,
              let activeSession else {
            return
        }

        Task {
            do {
                pendingToolCallResponse = true
                try await updateVoiceState(.toolRunning)
                for call in calls {
                    let output = try await daemonChannel.executeToolCall(
                        callId: call.callId,
                        toolName: call.name,
                        arguments: call.arguments,
                        sessionId: activeSession.id,
                        workspacePath: activeSession.workspacePath
                    )
                    realtimeClient.sendToolResult(callId: call.callId, output: output)
                    appendConversationEntry(
                        RemoteConversationEntry(
                            role: .tool,
                            text: "\(call.name) completed",
                            timestamp: .now,
                            metadata: ["tool": call.name]
                        )
                    )
                }
                pendingToolCallResponse = false
                realtimeClient.requestModelResponse()
                try await updateVoiceState(.thinking)
            } catch {
                presentError(error)
                pendingToolCallResponse = false
            }
        }
    }

    public func realtimeClientDidConnect(_ client: any RealtimeClientProtocol) {}

    public func realtimeClientDidBecomeReady(_ client: any RealtimeClientProtocol) {
        readyContinuation?.resume()
        readyContinuation = nil
    }

    public func realtimeClientDidDisconnect(_ client: any RealtimeClientProtocol, error: Error?) {
        sessionPrepared = false
        if let readyContinuation {
            self.readyContinuation = nil
            readyContinuation.resume(throwing: error ?? RemoteDaemonError.transportUnavailable)
        }
        if let error {
            presentError(error)
        }
    }

    public func realtimeClient(_ client: any RealtimeClientProtocol, didChangeState state: RealtimeConnectionState) {
        if state == .reconnecting {
            voiceState = .connecting
        }
    }

    public func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveError error: [String: Any]) {
        let message = (error["message"] as? String) ?? "Realtime session error."
        presentError(RemoteDaemonError.messageFailed(message))
    }

    public func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveResponseCreated response: [String: Any]) {
        _ = response
        Task {
            try? await updateVoiceState(.thinking)
        }
    }

    public func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioDelta base64Audio: String, itemId: String?, contentIndex: Int?) {
        _ = itemId
        _ = contentIndex
        audioPlayback.enqueueAudio(base64Chunk: base64Audio)
        Task {
            try? await updateVoiceState(.speaking)
        }
    }

    public func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioTranscriptDelta text: String) {
        updateAssistantTranscript(delta: text, isFinal: false)
    }

    public func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveAudioTranscriptDone text: String) {
        updateAssistantTranscript(delta: text, isFinal: true)
    }

    public func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveTextDelta text: String) {
        updateAssistantTranscript(delta: text, isFinal: false)
    }

    public func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveTextDone text: String) {
        updateAssistantTranscript(delta: text, isFinal: true)
    }

    public func realtimeClientDidReceiveResponseDone(_ client: any RealtimeClientProtocol) {
        if pendingToolCallResponse {
            return
        }
        Task {
            try? await updateVoiceState(.listening)
        }
    }

    public func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveTypedResponseDone response: RealtimeResponseDone) {
        if response.functionCalls.isEmpty {
            pendingToolCallResponse = false
            return
        }
        handleToolCalls(response.functionCalls)
    }

    public func realtimeClient(_ client: any RealtimeClientProtocol, didReceiveInputAudioTranscriptionDone text: String, itemId: String?) {
        _ = itemId
        appendConversationEntry(
            RemoteConversationEntry(
                role: .user,
                text: text,
                timestamp: .now,
                metadata: ["source": "voice"]
            )
        )
    }
}

#endif
