import Foundation

private struct RealtimeClientError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - RealtimeClient

@MainActor
class RealtimeClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var connectionState: RealtimeConnectionState = .disconnected

    weak var delegate: RealtimeClientDelegate?

    // Session configuration
    var model: String = "gpt-realtime-1.5"
    var voice: String = "marin"
    var instructions: String = ""
    var tools: [[String: Any]] = [] {
        didSet {
            guard connectionState == .connected,
                  startupSessionUpdateAcknowledged,
                  !toolsIncludedInStartupConfig else { return }
            toolsSessionUpdateSent = false
            sendToolsSessionConfigIfNeeded()
        }
    }

    private let parser = RealtimeMessageParser()
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var apiKey: String?
    private var activeModelForConnection: String = "gpt-realtime-1.5"

    // Reconnection
    private let maxReconnectAttempts = RealtimeReconnectionPolicy.maxReconnectAttempts
    private let reconnectStabilityWindowSeconds: TimeInterval = 10
    private let disconnectDispositionFreshnessWindowSeconds: TimeInterval = 2
    private var reconnectAttempt = 0
    private var intentionalDisconnect = false
    private var latestErrorDisposition: RealtimeErrorRetryDisposition?
    private var latestErrorDispositionTimestamp: Date?
    private var latestErrorMessage: String?
    private var disconnectNotified = false
    private var reconnectStabilityResetWorkItem: DispatchWorkItem?

    // Session readiness
    private let sessionReadyTimeoutSeconds: TimeInterval = 8
    private var sawSessionCreated = false
    private var sawSessionUpdated = false
    private var didNotifySessionReady = false
    private var sessionReadyTimeoutWorkItem: DispatchWorkItem?
    private var startupSessionUpdateSent = false
    private var startupSessionUpdateAcknowledged = false
    private var toolsSessionUpdateSent = false
    private var toolsSessionUpdateAcknowledged = false
    private var toolsIncludedInStartupConfig = false

    // Observability
    private var connectionTraceID = String(UUID().uuidString.prefix(8))
    private var outboundEventSequence = 0
    private var inboundEventSequence = 0
    private var connectedAt: Date?
    private var audioAppendDebugCount = 0
    private let maxLoggedAudioAppends = 5
    private let maxBufferedPreReadyAudioChunks = 24
    private let maxLoggedBufferedPreReadyAudioEvents = 5
    private var bufferedPreReadyAudioChunks: [String] = []
    private var bufferedPreReadyAudioLogCount = 0
    private var outboundEventTypesByID: [String: String] = [:]
    private var outboundEventContextsByID: [String: String] = [:]
    private var serverErrorCount = 0

    // Protect against stale callbacks from older sockets
    private var connectionGeneration = 0

    private var effectiveModelForConnectionAttempt: String {
        RealtimeReconnectionPolicy.resolvedModelForConnectionAttempt(configuredModel: model, reconnectAttempt: reconnectAttempt)
    }

    // MARK: - Connection

    func connect(apiKey: String) {
        guard connectionState == .disconnected else {
            logInfo("RealtimeClient: Already connected or connecting")
            return
        }

        self.apiKey = apiKey
        intentionalDisconnect = false
        disconnectNotified = false
        latestErrorDisposition = nil
        latestErrorDispositionTimestamp = nil
        latestErrorMessage = nil
        connectionTraceID = String(UUID().uuidString.prefix(8))
        outboundEventSequence = 0
        inboundEventSequence = 0
        connectedAt = nil
        outboundEventTypesByID.removeAll()
        outboundEventContextsByID.removeAll()
        reconnectAttempt = 0
        reconnectStabilityResetWorkItem?.cancel()
        reconnectStabilityResetWorkItem = nil
        activeModelForConnection = model
        serverErrorCount = 0
        resetSessionLifecycleState()
        setConnectionState(.connecting)

        establishConnection()
    }

    func disconnect() {
        intentionalDisconnect = true
        reconnectAttempt = 0
        latestErrorDisposition = nil
        latestErrorDispositionTimestamp = nil
        latestErrorMessage = nil
        reconnectStabilityResetWorkItem?.cancel()
        reconnectStabilityResetWorkItem = nil
        sessionReadyTimeoutWorkItem?.cancel()
        sessionReadyTimeoutWorkItem = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        completeDisconnect(error: nil)
        logInfo("RealtimeClient: Disconnected")
    }

    // MARK: - Sending Data

    func sendAudio(base64Chunk: String) {
        guard isSessionContractReadyForInputAudio else {
            bufferPreReadyAudioChunk(base64Chunk)
            return
        }

        flushBufferedPreReadyAudioIfNeeded(reason: "live_append")
        sendInputAudioAppendEvent(base64Chunk)
    }

    func commitAudioBuffer() {
        let event: [String: Any] = [
            "type": "input_audio_buffer.commit"
        ]
        logDebug("RealtimeClient[\(connectionTraceID)]: Sending manual input_audio_buffer.commit")
        sendEvent(event)
    }

    func sendToolResult(callId: String, output: String) {
        let itemEvent: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "status": "completed",
                "output": output
            ]
        ]
        sendEvent(itemEvent)
    }

    func requestModelResponse() {
        let responseEvent: [String: Any] = [
            "type": "response.create"
        ]
        sendEvent(responseEvent)
    }

    func cancelResponse() {
        let cancelEvent: [String: Any] = [
            "type": "response.cancel"
        ]
        sendEvent(cancelEvent)
    }

    func truncateResponse(itemId: String, contentIndex: Int, audioEnd: Int, sendCancel: Bool = false) {
        if sendCancel {
            cancelResponse()
        }
        let truncateEvent: [String: Any] = [
            "type": "conversation.item.truncate",
            "item_id": itemId,
            "content_index": contentIndex,
            "audio_end_ms": max(0, audioEnd)
        ]
        sendEvent(truncateEvent)
    }

    func updateSession(config: [String: Any]) {
        guard let type = config["type"] as? String, type == "realtime" else {
            logError("RealtimeClient: Ignoring session.update without session.type='realtime'")
            return
        }
        var event: [String: Any] = [
            "type": "session.update"
        ]
        event["session"] = config
        sendEvent(event)
    }

    func sendMessage(text: String) {
        let itemEvent: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": text
                    ]
                ]
            ]
        ]
        sendEvent(itemEvent)

        let responseEvent: [String: Any] = [
            "type": "response.create"
        ]
        sendEvent(responseEvent)
    }

    // MARK: - Private: Connection

    private func establishConnection() {
        guard let apiKey = apiKey else {
            logError("RealtimeClient: No API key provided")
            setConnectionState(.disconnected)
            return
        }

        let selectedModel = effectiveModelForConnectionAttempt
        activeModelForConnection = selectedModel
        let encodedModel = selectedModel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? selectedModel
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(encodedModel)") else {
            logError("RealtimeClient: Invalid WebSocket URL")
            setConnectionState(.disconnected)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.urlSession = session

        let task = session.webSocketTask(with: request)
        connectionGeneration += 1
        self.webSocketTask = task
        task.resume()

        logInfo(
            "RealtimeClient: Connecting to Realtime API (configured_model: \(model), selected_model: \(selectedModel), attempt: \(reconnectAttempt))..."
        )
    }

    private func setConnectionState(_ state: RealtimeConnectionState) {
        connectionState = state
        delegate?.realtimeClient(self, didChangeState: state)
        logDebug("RealtimeClient[\(connectionTraceID)]: State -> \(state.rawValue)")
    }

    private var isSessionContractReadyForInputAudio: Bool {
        let toolsConfigured = tools.isEmpty || !toolsSessionUpdateSent || toolsSessionUpdateAcknowledged
        return connectionState == .connected
            && didNotifySessionReady
            && sawSessionCreated
            && sawSessionUpdated
            && startupSessionUpdateAcknowledged
            && toolsConfigured
    }

    private func resetSessionLifecycleState() {
        sawSessionCreated = false
        sawSessionUpdated = false
        didNotifySessionReady = false
        startupSessionUpdateSent = false
        startupSessionUpdateAcknowledged = false
        toolsSessionUpdateSent = false
        toolsSessionUpdateAcknowledged = false
        toolsIncludedInStartupConfig = false
        audioAppendDebugCount = 0
        bufferedPreReadyAudioChunks.removeAll(keepingCapacity: true)
        bufferedPreReadyAudioLogCount = 0
        sessionReadyTimeoutWorkItem?.cancel()
        sessionReadyTimeoutWorkItem = nil
    }

    private func startSessionReadyTimeout() {
        sessionReadyTimeoutWorkItem?.cancel()
        let timeoutItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard !self.didNotifySessionReady, self.connectionState == .connected else {
                    return
                }

                let message = "Timed out waiting for Realtime session readiness"
                self.latestErrorDisposition = .retryable
                self.latestErrorDispositionTimestamp = Date()
                self.latestErrorMessage = message
                logError("RealtimeClient[\(self.connectionTraceID)]: \(message)")
                self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                self.handleDisconnection(error: RealtimeClientError(message: message))
            }
        }

        sessionReadyTimeoutWorkItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + sessionReadyTimeoutSeconds, execute: timeoutItem)
    }

    private func scheduleReconnectAttemptResetAfterStabilityWindow() {
        reconnectStabilityResetWorkItem?.cancel()
        let generationAtReady = connectionGeneration
        let errorCountAtReady = serverErrorCount
        let readyAttempt = reconnectAttempt
        let resetItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.connectionState == .connected else { return }
                guard self.connectionGeneration == generationAtReady else { return }
                guard self.serverErrorCount == errorCountAtReady else { return }
                guard self.reconnectAttempt == readyAttempt else { return }
                guard readyAttempt > 0 else { return }

                self.reconnectAttempt = 0
                logInfo(
                    "RealtimeClient[\(self.connectionTraceID)]: Cleared reconnect attempt budget after \(Int(self.reconnectStabilityWindowSeconds))s stable session"
                )
            }
        }

        reconnectStabilityResetWorkItem = resetItem
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectStabilityWindowSeconds, execute: resetItem)
    }

    private func maybeNotifySessionReady(source: String) {
        let toolsConfigured = tools.isEmpty
            || toolsIncludedInStartupConfig
            || !toolsSessionUpdateSent
            || toolsSessionUpdateAcknowledged

        guard sawSessionCreated, startupSessionUpdateAcknowledged, sawSessionUpdated, toolsConfigured, !didNotifySessionReady else {
            return
        }

        didNotifySessionReady = true
        sessionReadyTimeoutWorkItem?.cancel()
        sessionReadyTimeoutWorkItem = nil
        latestErrorMessage = nil
        scheduleReconnectAttemptResetAfterStabilityWindow()
        flushBufferedPreReadyAudioIfNeeded(reason: "session_ready_\(source)")
        logInfo("RealtimeClient[\(connectionTraceID)]: Session ready (\(source))")
        delegate?.realtimeClientDidBecomeReady(self)
    }

    private func baseSessionConfig() -> [String: Any] {
        let audioFormat: [String: Any] = [
            "type": "audio/pcm",
            "rate": Int(AudioConstants.sampleRate)
        ]
        // semantic_vad uses a language model classifier to detect turn boundaries, which is better than
        // server_vad at distinguishing real speech from filler words ("hmm", "okay") during barge-in.
        // eagerness "medium" (4s max timeout) gives responsive turn-taking for short voice commands
        // while still waiting for complete thoughts — better than "low" (8s) for a coding assistant.
        let turnDetection: [String: Any] = [
            "type": "semantic_vad",
            "eagerness": "medium",
            "interrupt_response": true,
            "create_response": true
        ]
        let inputAudio: [String: Any] = [
            "format": audioFormat,
            "turn_detection": turnDetection,
            "transcription": ["model": "gpt-4o-mini-transcribe", "language": "en"],
            "noise_reduction": ["type": "near_field"]
        ]

        var sessionConfig: [String: Any] = [
            "type": "realtime",
            "model": activeModelForConnection,
            "output_modalities": ["audio"],
            "audio": [
                "output": [
                    "format": audioFormat,
                    "voice": voice
                ],
                "input": inputAudio
            ] as [String: Any]
        ]

        if !instructions.isEmpty {
            sessionConfig["instructions"] = instructions
        }

        if !tools.isEmpty {
            sessionConfig["tools"] = tools
            sessionConfig["tool_choice"] = "auto"
        }

        return sessionConfig
    }

    private func bufferPreReadyAudioChunk(_ base64Chunk: String) {
        if bufferedPreReadyAudioChunks.count >= maxBufferedPreReadyAudioChunks {
            let overflowCount = bufferedPreReadyAudioChunks.count - maxBufferedPreReadyAudioChunks + 1
            bufferedPreReadyAudioChunks.removeFirst(overflowCount)
        }
        bufferedPreReadyAudioChunks.append(base64Chunk)

        if bufferedPreReadyAudioLogCount < maxLoggedBufferedPreReadyAudioEvents {
            bufferedPreReadyAudioLogCount += 1
            logDebug(
                "RealtimeClient[\(connectionTraceID)]: Buffering input_audio_buffer.append until session contract is ready (buffered=\(bufferedPreReadyAudioChunks.count), created=\(sawSessionCreated), updated=\(sawSessionUpdated), startupAck=\(startupSessionUpdateAcknowledged), ready=\(didNotifySessionReady))"
            )
        }
    }

    private func flushBufferedPreReadyAudioIfNeeded(reason: String) {
        guard isSessionContractReadyForInputAudio else { return }
        guard !bufferedPreReadyAudioChunks.isEmpty else { return }

        let buffered = bufferedPreReadyAudioChunks
        bufferedPreReadyAudioChunks.removeAll(keepingCapacity: true)
        logInfo(
            "RealtimeClient[\(connectionTraceID)]: Flushing \(buffered.count) buffered input_audio_buffer.append events (\(reason))"
        )
        for chunk in buffered {
            sendInputAudioAppendEvent(chunk)
        }
    }

    private func sendInputAudioAppendEvent(_ base64Chunk: String) {
        if audioAppendDebugCount < maxLoggedAudioAppends {
            audioAppendDebugCount += 1
            let byteCount = Data(base64Encoded: base64Chunk)?.count ?? 0
            let sampleCount = byteCount / MemoryLayout<Int16>.size
            let elapsedMs = connectedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
            logDebug(
                "RealtimeClient[\(connectionTraceID)]: audio append #\(audioAppendDebugCount) bytes=\(byteCount) samples=\(sampleCount) t+\(elapsedMs)ms created=\(sawSessionCreated) updated=\(sawSessionUpdated)"
            )
        }

        let event: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64Chunk
        ]
        sendEvent(event)
    }

    private func sendStartupSessionConfig() {
        guard !startupSessionUpdateSent, !startupSessionUpdateAcknowledged else { return }

        startupSessionUpdateSent = true
        toolsIncludedInStartupConfig = !tools.isEmpty
        let event: [String: Any] = [
            "type": "session.update",
            "session": baseSessionConfig()
        ]
        sendEvent(event, context: "session.update.startup")
        logInfo("RealtimeClient[\(connectionTraceID)]: Sent startup session configuration")
    }

    private func sendToolsSessionConfigIfNeeded() {
        guard !tools.isEmpty else {
            toolsSessionUpdateSent = false
            toolsSessionUpdateAcknowledged = true
            return
        }
        guard !toolsIncludedInStartupConfig else {
            toolsSessionUpdateSent = false
            toolsSessionUpdateAcknowledged = true
            return
        }
        guard !toolsSessionUpdateSent else { return }

        toolsSessionUpdateSent = true
        toolsSessionUpdateAcknowledged = false
        let sessionConfig: [String: Any] = [
            "type": "realtime",
            "tools": tools,
            "tool_choice": "auto"
        ]
        let event: [String: Any] = [
            "type": "session.update",
            "session": sessionConfig
        ]
        sendEvent(event, context: "session.update.tools")
        logInfo("RealtimeClient[\(connectionTraceID)]: Sent tools session configuration")
    }

    // MARK: - Private: Send/Receive

    @discardableResult
    private func sendEvent(_ event: [String: Any], context: String? = nil) -> String? {
        guard let task = webSocketTask, connectionState == .connected else {
            logDebug("RealtimeClient: Cannot send event, not connected")
            return nil
        }

        do {
            var outgoingEvent = event
            outboundEventSequence += 1
            let eventType = (outgoingEvent["type"] as? String) ?? "unknown"
            let eventID = (outgoingEvent["event_id"] as? String) ?? "\(connectionTraceID)-out-\(outboundEventSequence)"
            outgoingEvent["event_id"] = eventID
            outboundEventTypesByID[eventID] = eventType
            if let context {
                outboundEventContextsByID[eventID] = context
            }
            if outboundEventTypesByID.count > 512, let staleEventID = outboundEventTypesByID.keys.first {
                outboundEventTypesByID.removeValue(forKey: staleEventID)
                outboundEventContextsByID.removeValue(forKey: staleEventID)
            }

            let data = try JSONSerialization.data(withJSONObject: outgoingEvent, options: [.sortedKeys])
            logDebug("RealtimeClient[\(connectionTraceID)]: -> #\(outboundEventSequence) \(eventType) event_id=\(eventID)")
            if eventType == "session.update" {
                logDebug("RealtimeClient[\(connectionTraceID)]: Sending event payload: \(String(data: data, encoding: .utf8) ?? "?")")
            }

            guard let text = String(data: data, encoding: .utf8) else {
                logError("RealtimeClient: Failed to encode outbound event as UTF-8 text")
                return nil
            }
            let message = URLSessionWebSocketTask.Message.string(text)
            task.send(message) { error in
                if let error = error {
                    logError("RealtimeClient: Send error: \(error.localizedDescription)")
                }
            }
            return eventID
        } catch {
            logError("RealtimeClient: Failed to serialize event: \(error.localizedDescription)")
            return nil
        }
    }

    private func receiveMessages(for task: URLSessionWebSocketTask, generation: Int) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                guard self.connectionGeneration == generation, self.webSocketTask === task else {
                    return
                }

                switch result {
                case .success(let message):
                    switch message {
                    case .data(let data):
                        self.handleMessage(data: data)
                    case .string(let text):
                        if let data = text.data(using: .utf8) {
                            self.handleMessage(data: data)
                        }
                    @unknown default:
                        logDebug("RealtimeClient: Unknown message type")
                    }
                    self.receiveMessages(for: task, generation: generation)

                case .failure(let error):
                    logError("RealtimeClient: Receive error: \(error.localizedDescription)")
                    self.handleDisconnection(error: error)
                }
            }
        }
    }

    private func handleMessage(data: Data) {
        guard let event = try? parser.parse(data) else {
            logDebug("RealtimeClient: Failed to parse server event")
            return
        }

        inboundEventSequence += 1

        Task { @MainActor in
            self.dispatchParsedEvent(event)
        }
    }

    private func handleServerErrorEvent(type: String, json: [String: Any]) {
        let payload: [String: Any]
        if type == "error", let nested = json["error"] as? [String: Any] {
            payload = nested
        } else {
            payload = json
        }

        var normalizedPayload = payload
        if normalizedPayload["event_id"] == nil, let eventId = json["event_id"] as? String {
            normalizedPayload["event_id"] = eventId
        }

        let classified = classifyRealtimeErrorPayload(normalizedPayload)
        serverErrorCount += 1
        latestErrorDisposition = classified.disposition
        latestErrorDispositionTimestamp = Date()
        latestErrorMessage = classified.message
        let offendingEventType = classified.eventId.flatMap { outboundEventTypesByID[$0] } ?? "unknown"
        let offendingEventContext = classified.eventId.flatMap { outboundEventContextsByID[$0] } ?? "unknown"

        logError(
            """
            RealtimeClient[\(connectionTraceID)]: Server error type=\(classified.type) code=\(classified.code) param=\(classified.param ?? "none") event_id=\(classified.eventId ?? "none") offending_event_type=\(offendingEventType) offending_event_context=\(offendingEventContext) retryable=\(classified.disposition == .retryable) message=\(classified.message)
            """
        )

        if let jsonData = try? JSONSerialization.data(withJSONObject: normalizedPayload, options: [.sortedKeys]),
           let jsonText = String(data: jsonData, encoding: .utf8) {
            logDebug("RealtimeClient[\(connectionTraceID)]: Full server error payload: \(jsonText)")
        }

        normalizedPayload["_retryable"] = classified.disposition == .retryable
        normalizedPayload["_classification"] = classified.disposition.rawValue
        normalizedPayload["_offending_event_type"] = offendingEventType
        normalizedPayload["_offending_event_context"] = offendingEventContext
        delegate?.realtimeClient(self, didReceiveError: normalizedPayload)

        if classified.disposition == .retryable, connectionState == .connected {
            logInfo("RealtimeClient[\(connectionTraceID)]: Triggering reconnect after retryable server error")
            handleDisconnection(error: RealtimeClientError(message: classified.message))
        }
    }

    private func dispatchParsedEvent(_ event: RealtimeEvent) {
        switch event {
        case .sessionCreated(let session):
            delegate?.realtimeClient(self, didReceiveSessionCreated: session)
            sawSessionCreated = true
            sendStartupSessionConfig()
            logInfo("RealtimeClient[\(connectionTraceID)]: Session created")

        case .sessionUpdated(let session):
            delegate?.realtimeClient(self, didReceiveSessionUpdated: session)
            sawSessionUpdated = true

            if startupSessionUpdateSent && !startupSessionUpdateAcknowledged {
                startupSessionUpdateAcknowledged = true
                logInfo("RealtimeClient[\(connectionTraceID)]: Startup session configuration acknowledged")
                sendToolsSessionConfigIfNeeded()
            } else if toolsSessionUpdateSent && !toolsSessionUpdateAcknowledged {
                toolsSessionUpdateAcknowledged = true
                logInfo("RealtimeClient[\(connectionTraceID)]: Tools session configuration acknowledged")
            }

            maybeNotifySessionReady(source: "session.updated")
            logDebug("RealtimeClient[\(connectionTraceID)]: Session updated")

        case .error(let type, let json):
            handleServerErrorEvent(type: type, json: json)

        case .inputAudioBufferSpeechStarted:
            delegate?.realtimeClientDidDetectSpeechStarted(self)
            logDebug("RealtimeClient: Speech started")

        case .inputAudioBufferSpeechStopped:
            delegate?.realtimeClientDidDetectSpeechStopped(self)
            logDebug("RealtimeClient: Speech stopped")

        case .inputAudioBufferCommitted:
            logDebug("RealtimeClient: Input audio buffer committed")

        case .responseCreated(let json):
            delegate?.realtimeClient(self, didReceiveResponseCreated: json)
            logDebug("RealtimeClient: Response created")

        case .responseOutputAudioDelta(let delta, let itemId, let contentIndex):
            delegate?.realtimeClient(self, didUpdateActiveAudioOutput: itemId, contentIndex: contentIndex)
            if !delta.isEmpty {
                delegate?.realtimeClient(self, didReceiveAudioDelta: delta, itemId: itemId, contentIndex: contentIndex)
            }

        case .responseOutputAudioDone(let itemId, let contentIndex):
            delegate?.realtimeClient(self, didUpdateActiveAudioOutput: itemId.isEmpty ? nil : itemId, contentIndex: contentIndex)
            delegate?.realtimeClient(self, didReceiveAudioDone: itemId, contentIndex: contentIndex)
            logDebug("RealtimeClient: Audio output done")

        case .responseOutputAudioTranscriptDelta(let delta):
            if !delta.isEmpty {
                delegate?.realtimeClient(self, didReceiveAudioTranscriptDelta: delta)
            }

        case .responseOutputAudioTranscriptDone(let transcript):
            if !transcript.isEmpty {
                delegate?.realtimeClient(self, didReceiveAudioTranscriptDone: transcript)
                logDebug("RealtimeClient: Audio transcript done, length: \(transcript.count)")
            }

        case .responseOutputTextDelta(let delta):
            if !delta.isEmpty {
                delegate?.realtimeClient(self, didReceiveTextDelta: delta)
            }

        case .responseOutputTextDone(let text):
            if !text.isEmpty {
                delegate?.realtimeClient(self, didReceiveTextDone: text)
                logDebug("RealtimeClient: Text output done, length: \(text.count)")
            }

        case .responseDone(let typed, _):
            if let typed {
                delegate?.realtimeClient(self, didReceiveTypedResponseDone: typed)
                let normalizedStatus = typed.response.status?.lowercased()
                if normalizedStatus == "cancelled" || normalizedStatus == "canceled" {
                    delegate?.realtimeClientDidReceiveResponseCancelled(self)
                }
            } else {
                logDebug("RealtimeClient: Failed to decode typed response.done")
            }
            delegate?.realtimeClientDidReceiveResponseDone(self)
            logDebug("RealtimeClient: Response done")

        case .responseCancelled:
            delegate?.realtimeClientDidReceiveResponseCancelled(self)
            logDebug("RealtimeClient: Response cancelled")

        case .functionCallArgumentsDelta(let delta, let callId):
            if !delta.isEmpty, !callId.isEmpty {
                delegate?.realtimeClient(self, didReceiveFunctionCallArgumentsDelta: delta, callId: callId)
            }

        case .functionCallArgumentsDone(let arguments, let callId):
            if !arguments.isEmpty, !callId.isEmpty {
                delegate?.realtimeClient(self, didReceiveFunctionCallArgumentsDone: arguments, callId: callId)
                logDebug("RealtimeClient: Function call arguments done for \(callId)")
            }

        case .inputAudioTranscriptionCompleted(let transcript, let itemId):
            delegate?.realtimeClient(self, didReceiveInputAudioTranscriptionDone: transcript, itemId: itemId)
            logDebug("RealtimeClient: Input audio transcription done, length: \(transcript.count)")

        case .inputAudioTranscriptionFailed:
            logError("RealtimeClient: Input audio transcription failed")

        case .conversationItemCreated(let item):
            if !item.isEmpty {
                delegate?.realtimeClient(self, didReceiveConversationItemCreated: item)
            }

        case .conversationItemDone(let item):
            if !item.isEmpty {
                delegate?.realtimeClient(self, didReceiveConversationItemDone: item)
            }

        case .conversationItemTruncated:
            logDebug("RealtimeClient: Conversation item truncated")

        case .outputItemUpdated(let itemId, let contentIndex):
            if itemId != nil || contentIndex != nil {
                delegate?.realtimeClient(self, didUpdateActiveAudioOutput: itemId, contentIndex: contentIndex)
            }

        case .outputItemFunctionCall(let call):
            delegate?.realtimeClient(self, didReceiveFunctionCallItem: call)

        case .rateLimitsUpdated(let rateLimits):
            if !rateLimits.isEmpty {
                delegate?.realtimeClient(self, didReceiveRateLimitsUpdated: rateLimits)
                logDebug("RealtimeClient: Rate limits updated")
            }

        case .unhandled(let type):
            logDebug("RealtimeClient: Unhandled event type: \(type)")
        }
    }

    // MARK: - Private: Reconnection

    private func completeDisconnect(error: Error?) {
        guard !disconnectNotified else { return }

        disconnectNotified = true
        reconnectStabilityResetWorkItem?.cancel()
        reconnectStabilityResetWorkItem = nil
        sessionReadyTimeoutWorkItem?.cancel()
        sessionReadyTimeoutWorkItem = nil
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        setConnectionState(.disconnected)

        let finalError = error ?? latestErrorMessage.map { RealtimeClientError(message: $0) }
        delegate?.realtimeClientDidDisconnect(self, error: finalError)
    }

    private func handleDisconnection(error: Error?) {
        guard connectionState != .disconnected else { return }
        guard connectionState != .reconnecting else { return }
        guard !intentionalDisconnect else {
            completeDisconnect(error: error)
            return
        }

        let dispositionForDisconnect: RealtimeErrorRetryDisposition?
        if let disposition = latestErrorDisposition,
           let timestamp = latestErrorDispositionTimestamp,
           Date().timeIntervalSince(timestamp) <= disconnectDispositionFreshnessWindowSeconds {
            dispositionForDisconnect = disposition
        } else {
            if latestErrorDisposition != nil {
                logDebug("RealtimeClient[\(connectionTraceID)]: Ignoring stale error disposition for disconnect decision")
            }
            dispositionForDisconnect = nil
        }
        latestErrorDisposition = nil
        latestErrorDispositionTimestamp = nil

        if RealtimeReconnectionPolicy.shouldReconnect(
            intentionalDisconnect: intentionalDisconnect,
            disposition: dispositionForDisconnect,
            reconnectAttempt: reconnectAttempt,
            maxReconnectAttempts: maxReconnectAttempts
        ) {
            latestErrorMessage = nil
            reconnectAttempt += 1
            let delay = pow(2.0, Double(reconnectAttempt - 1)) // 1s, 2s, 4s
            setConnectionState(.reconnecting)
            logInfo(
                "RealtimeClient[\(connectionTraceID)]: Reconnecting in \(Int(delay))s (attempt \(reconnectAttempt)/\(maxReconnectAttempts), disposition=\(dispositionForDisconnect?.rawValue ?? "transport"), next_model=\(effectiveModelForConnectionAttempt))"
            )

            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            urlSession?.invalidateAndCancel()
            urlSession = nil
            resetSessionLifecycleState()

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.connectionState == .reconnecting else { return }
                self.disconnectNotified = false
                self.setConnectionState(.connecting)
                self.establishConnection()
            }
        } else {
            if dispositionForDisconnect == .nonRetryable {
                logError("RealtimeClient[\(connectionTraceID)]: Not reconnecting due to non-retryable error")
            } else {
                logError("RealtimeClient[\(connectionTraceID)]: Failed to reconnect after \(maxReconnectAttempts) attempts")
            }
            completeDisconnect(error: error)
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            guard self.webSocketTask === webSocketTask else {
                return
            }
            guard !self.intentionalDisconnect else {
                webSocketTask.cancel(with: .normalClosure, reason: nil)
                return
            }

            logInfo("RealtimeClient[\(self.connectionTraceID)]: WebSocket connected (model: \(self.activeModelForConnection))")
            self.connectedAt = Date()
            self.resetSessionLifecycleState()
            self.startSessionReadyTimeout()
            self.setConnectionState(.connected)
            self.receiveMessages(for: webSocketTask, generation: self.connectionGeneration)
            self.delegate?.realtimeClientDidConnect(self)
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        Task { @MainActor in
            guard self.webSocketTask === webSocketTask else {
                return
            }
            logInfo("RealtimeClient[\(self.connectionTraceID)]: WebSocket closed (code: \(closeCode.rawValue), reason: \(reasonString))")
            let closeError: Error? = closeCode == .normalClosure ? nil : RealtimeClientError(
                message: "WebSocket closed (code: \(closeCode.rawValue), reason: \(reasonString))"
            )
            self.handleDisconnection(error: closeError)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Task { @MainActor in
                guard self.webSocketTask === task else {
                    return
                }
                logError("RealtimeClient: Connection error: \(error.localizedDescription)")
                self.handleDisconnection(error: error)
            }
        }
    }
}
