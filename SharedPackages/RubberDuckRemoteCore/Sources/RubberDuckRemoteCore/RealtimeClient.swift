import Foundation

private struct RealtimeClientError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

@MainActor
public final class RealtimeClient: NSObject, ObservableObject, URLSessionWebSocketDelegate, RealtimeClientProtocol {
    @Published public private(set) var connectionState: RealtimeConnectionState = .disconnected

    public weak var delegate: RealtimeClientDelegate?

    public var model = "gpt-realtime-1.5"
    public var voice = "marin"
    public var interruptResponseOnBargeIn = false
    public var instructions = ""
    public var tools: [[String: Any]] = [] {
        didSet {
            guard connectionState == .connected,
                  startupSessionUpdateAcknowledged,
                  !toolsIncludedInStartupConfig else {
                return
            }

            toolsSessionUpdateSent = false
            sendToolsSessionConfigIfNeeded()
        }
    }

    public var turnDetectionMode: RealtimeTurnDetectionMode = .semanticVAD
    public var pushToTalkMode: Bool {
        get { turnDetectionMode == .manual }
        set { turnDetectionMode = newValue ? .manual : .semanticVAD }
    }

    private let parser = RealtimeMessageParser()
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var apiKey: String?
    private var activeModelForConnection = "gpt-realtime-1.5"

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

    private var connectionGeneration = 0

    private var effectiveModelForConnectionAttempt: String {
        RealtimeReconnectionPolicy.resolvedModelForConnectionAttempt(
            configuredModel: model,
            reconnectAttempt: reconnectAttempt
        )
    }

    public override init() {
        super.init()
    }

    public func connect(apiKey: String) {
        guard connectionState == .disconnected else {
            logInfo("RealtimeClient: already connected or connecting")
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
        transition(to: .connecting)
        establishConnection()
    }

    public func disconnect() {
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
        logInfo("RealtimeClient: disconnected")
    }

    public func sendAudio(base64Chunk: String) {
        guard isSessionContractReadyForInputAudio else {
            bufferPreReadyAudioChunk(base64Chunk)
            return
        }

        flushBufferedPreReadyAudioIfNeeded(reason: "live_append")
        sendInputAudioAppendEvent(base64Chunk)
    }

    public func commitAudioBuffer() {
        sendEvent(["type": "input_audio_buffer.commit"])
    }

    public func sendToolResult(callId: String, output: String) {
        sendEvent([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "status": "completed",
                "output": output
            ]
        ])
    }

    public func requestModelResponse() {
        sendEvent(["type": "response.create"])
    }

    public func cancelResponse() {
        sendEvent(["type": "response.cancel"])
    }

    public func truncateResponse(
        itemId: String,
        contentIndex: Int,
        audioEnd: Int,
        sendCancel: Bool = false
    ) {
        if sendCancel {
            cancelResponse()
        }

        sendEvent([
            "type": "conversation.item.truncate",
            "item_id": itemId,
            "content_index": contentIndex,
            "audio_end_ms": max(0, audioEnd)
        ])
    }

    public func updateSession(config: [String: Any]) {
        guard let type = config["type"] as? String, type == "realtime" else {
            logError("RealtimeClient: ignoring session.update without session.type='realtime'")
            return
        }

        sendEvent([
            "type": "session.update",
            "session": config
        ])
    }

    public func sendMessage(text: String) {
        sendEvent([
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
        ])
        requestModelResponse()
    }

    private func establishConnection() {
        guard let apiKey else {
            logError("RealtimeClient: no API key provided")
            transition(to: .disconnected)
            delegate?.realtimeClientDidDisconnect(
                self,
                error: RealtimeClientError(message: "Missing OpenAI API key.")
            )
            return
        }

        let selectedModel = effectiveModelForConnectionAttempt
        activeModelForConnection = selectedModel
        let encodedModel = selectedModel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? selectedModel
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(encodedModel)") else {
            logError("RealtimeClient: invalid WebSocket URL")
            transition(to: .disconnected)
            delegate?.realtimeClientDidDisconnect(
                self,
                error: RealtimeClientError(message: "Invalid Realtime URL.")
            )
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        urlSession = session

        let task = session.webSocketTask(with: request)
        connectionGeneration += 1
        webSocketTask = task
        task.resume()

        logInfo(
            "RealtimeClient: connecting to Realtime API (configured_model: \(model), selected_model: \(selectedModel), attempt: \(reconnectAttempt))"
        )
    }

    private func transition(to state: RealtimeConnectionState) {
        connectionState = state
        delegate?.realtimeClient(self, didChangeState: state)
        logDebug("RealtimeClient[\(connectionTraceID)]: state -> \(state.rawValue)")
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
            guard let self else {
                return
            }

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
            guard let self else {
                return
            }

            Task { @MainActor in
                guard self.connectionState == .connected else {
                    return
                }
                guard self.connectionGeneration == generationAtReady else {
                    return
                }
                guard self.serverErrorCount == errorCountAtReady else {
                    return
                }
                guard self.reconnectAttempt == readyAttempt else {
                    return
                }
                guard readyAttempt > 0 else {
                    return
                }

                self.reconnectAttempt = 0
                logInfo(
                    "RealtimeClient[\(self.connectionTraceID)]: cleared reconnect attempt budget after \(Int(self.reconnectStabilityWindowSeconds))s stable session"
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

        guard sawSessionCreated,
              startupSessionUpdateAcknowledged,
              sawSessionUpdated,
              toolsConfigured,
              !didNotifySessionReady else {
            return
        }

        didNotifySessionReady = true
        sessionReadyTimeoutWorkItem?.cancel()
        sessionReadyTimeoutWorkItem = nil
        latestErrorMessage = nil
        scheduleReconnectAttemptResetAfterStabilityWindow()
        flushBufferedPreReadyAudioIfNeeded(reason: "session_ready_\(source)")
        logInfo("RealtimeClient[\(connectionTraceID)]: session ready (\(source))")
        delegate?.realtimeClientDidBecomeReady(self)
    }

    private func baseSessionConfig() -> [String: Any] {
        let audioFormat: [String: Any] = [
            "type": "audio/pcm",
            "rate": Int(RealtimeAudioConstants.sampleRate)
        ]

        var inputAudio: [String: Any] = [
            "format": audioFormat,
            "transcription": ["model": "gpt-4o-mini-transcribe", "language": "en"],
            "noise_reduction": ["type": "near_field"]
        ]

        if turnDetectionMode == .semanticVAD {
            inputAudio["turn_detection"] = [
                "type": "semantic_vad",
                "eagerness": "medium",
                "interrupt_response": interruptResponseOnBargeIn,
                "create_response": true
            ]
        }

        var sessionConfig: [String: Any] = [
            "type": "realtime",
            "model": activeModelForConnection,
            "output_modalities": ["audio", "text"],
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
                "RealtimeClient[\(connectionTraceID)]: buffering input_audio_buffer.append until session contract is ready (buffered=\(bufferedPreReadyAudioChunks.count), created=\(sawSessionCreated), updated=\(sawSessionUpdated), startupAck=\(startupSessionUpdateAcknowledged), ready=\(didNotifySessionReady))"
            )
        }
    }

    private func flushBufferedPreReadyAudioIfNeeded(reason: String) {
        guard isSessionContractReadyForInputAudio else {
            return
        }
        guard !bufferedPreReadyAudioChunks.isEmpty else {
            return
        }

        let buffered = bufferedPreReadyAudioChunks
        bufferedPreReadyAudioChunks.removeAll(keepingCapacity: true)
        logInfo(
            "RealtimeClient[\(connectionTraceID)]: flushing \(buffered.count) buffered input_audio_buffer.append events (\(reason))"
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

        sendEvent([
            "type": "input_audio_buffer.append",
            "audio": base64Chunk
        ])
    }

    private func sendStartupSessionConfig() {
        guard !startupSessionUpdateSent, !startupSessionUpdateAcknowledged else {
            return
        }

        startupSessionUpdateSent = true
        toolsIncludedInStartupConfig = !tools.isEmpty
        sendEvent([
            "type": "session.update",
            "session": baseSessionConfig()
        ], context: "session.update.startup")
        logInfo("RealtimeClient[\(connectionTraceID)]: sent startup session configuration")
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
        guard !toolsSessionUpdateSent else {
            return
        }

        toolsSessionUpdateSent = true
        toolsSessionUpdateAcknowledged = false
        sendEvent([
            "type": "session.update",
            "session": [
                "type": "realtime",
                "tools": tools,
                "tool_choice": "auto"
            ]
        ], context: "session.update.tools")
        logInfo("RealtimeClient[\(connectionTraceID)]: sent tools session configuration")
    }

    @discardableResult
    private func sendEvent(_ event: [String: Any], context: String? = nil) -> String? {
        guard let task = webSocketTask, connectionState == .connected else {
            logDebug("RealtimeClient: cannot send event, not connected")
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
            if eventType == "session.update" {
                logDebug(
                    "RealtimeClient[\(connectionTraceID)]: sending session.update payload: \(String(decoding: data, as: UTF8.self))"
                )
            } else {
                logDebug("RealtimeClient[\(connectionTraceID)]: -> #\(outboundEventSequence) \(eventType) event_id=\(eventID)")
            }

            task.send(.string(String(decoding: data, as: UTF8.self))) { error in
                if let error {
                    Task { @MainActor in
                        self.handleDisconnection(error: error)
                    }
                }
            }
            return eventID
        } catch {
            logError("RealtimeClient: failed to serialize event: \(error.localizedDescription)")
            return nil
        }
    }

    private func receiveMessages(for task: URLSessionWebSocketTask, generation: Int) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }
                guard self.connectionGeneration == generation, self.webSocketTask === task else {
                    return
                }

                switch result {
                case .success(let message):
                    let data: Data
                    switch message {
                    case .data(let rawData):
                        data = rawData
                    case .string(let text):
                        data = Data(text.utf8)
                    @unknown default:
                        logDebug("RealtimeClient: unknown message type")
                        self.receiveMessages(for: task, generation: generation)
                        return
                    }

                    self.handleMessage(data: data)
                    self.receiveMessages(for: task, generation: generation)

                case .failure(let error):
                    logError("RealtimeClient: receive error: \(error.localizedDescription)")
                    self.handleDisconnection(error: error)
                }
            }
        }
    }

    private func handleMessage(data: Data) {
        guard let event = try? parser.parse(data) else {
            logDebug("RealtimeClient: failed to parse server event")
            return
        }

        inboundEventSequence += 1
        dispatchParsedEvent(event)
    }

    private func handleServerErrorEvent(type: String, json: [String: Any]) {
        let payload: [String: Any]
        if type == "error", let nested = json["error"] as? [String: Any] {
            payload = nested
        } else {
            payload = json
        }

        var normalizedPayload = payload
        if normalizedPayload["event_id"] == nil, let eventID = json["event_id"] as? String {
            normalizedPayload["event_id"] = eventID
        }

        let classification = classifyRealtimeErrorPayload(normalizedPayload)
        serverErrorCount += 1
        latestErrorDisposition = classification.disposition
        latestErrorDispositionTimestamp = Date()
        latestErrorMessage = classification.message
        let offendingEventType = classification.eventId.flatMap { outboundEventTypesByID[$0] } ?? "unknown"
        let offendingEventContext = classification.eventId.flatMap { outboundEventContextsByID[$0] } ?? "unknown"

        logError(
            """
            RealtimeClient[\(connectionTraceID)]: server error type=\(classification.type) code=\(classification.code) param=\(classification.param ?? "none") event_id=\(classification.eventId ?? "none") offending_event_type=\(offendingEventType) offending_event_context=\(offendingEventContext) retryable=\(classification.disposition == .retryable) message=\(classification.message)
            """
        )

        normalizedPayload["_retryable"] = classification.disposition == .retryable
        normalizedPayload["_classification"] = classification.disposition.rawValue
        normalizedPayload["_offending_event_type"] = offendingEventType
        normalizedPayload["_offending_event_context"] = offendingEventContext
        delegate?.realtimeClient(self, didReceiveError: normalizedPayload)

        if classification.disposition == .retryable, connectionState == .connected {
            handleDisconnection(error: RealtimeClientError(message: classification.message))
        }
    }

    private func dispatchParsedEvent(_ event: RealtimeEvent) {
        switch event {
        case .sessionCreated(let session):
            delegate?.realtimeClient(self, didReceiveSessionCreated: session)
            sawSessionCreated = true
            sendStartupSessionConfig()
            logInfo("RealtimeClient[\(connectionTraceID)]: session created")

        case .sessionUpdated(let session):
            delegate?.realtimeClient(self, didReceiveSessionUpdated: session)
            sawSessionUpdated = true

            if startupSessionUpdateSent && !startupSessionUpdateAcknowledged {
                startupSessionUpdateAcknowledged = true
                logInfo("RealtimeClient[\(connectionTraceID)]: startup session configuration acknowledged")
                sendToolsSessionConfigIfNeeded()
            } else if toolsSessionUpdateSent && !toolsSessionUpdateAcknowledged {
                toolsSessionUpdateAcknowledged = true
                logInfo("RealtimeClient[\(connectionTraceID)]: tools session configuration acknowledged")
            }

            maybeNotifySessionReady(source: "session.updated")

        case .error(let type, let json):
            handleServerErrorEvent(type: type, json: json)

        case .inputAudioBufferSpeechStarted:
            delegate?.realtimeClientDidDetectSpeechStarted(self)

        case .inputAudioBufferSpeechStopped:
            delegate?.realtimeClientDidDetectSpeechStopped(self)

        case .inputAudioBufferCommitted:
            logDebug("RealtimeClient: input audio buffer committed")

        case .responseCreated(let json):
            delegate?.realtimeClient(self, didReceiveResponseCreated: json)

        case .responseOutputAudioDelta(let delta, let itemId, let contentIndex):
            delegate?.realtimeClient(self, didUpdateActiveAudioOutput: itemId, contentIndex: contentIndex)
            if !delta.isEmpty {
                delegate?.realtimeClient(self, didReceiveAudioDelta: delta, itemId: itemId, contentIndex: contentIndex)
            }

        case .responseOutputAudioDone(let itemId, let contentIndex):
            delegate?.realtimeClient(self, didUpdateActiveAudioOutput: itemId.isEmpty ? nil : itemId, contentIndex: contentIndex)
            delegate?.realtimeClient(self, didReceiveAudioDone: itemId, contentIndex: contentIndex)

        case .responseOutputAudioTranscriptDelta(let delta):
            if !delta.isEmpty {
                delegate?.realtimeClient(self, didReceiveAudioTranscriptDelta: delta)
            }

        case .responseOutputAudioTranscriptDone(let transcript):
            if !transcript.isEmpty {
                delegate?.realtimeClient(self, didReceiveAudioTranscriptDone: transcript)
            }

        case .responseOutputTextDelta(let delta):
            if !delta.isEmpty {
                delegate?.realtimeClient(self, didReceiveTextDelta: delta)
            }

        case .responseOutputTextDone(let text):
            if !text.isEmpty {
                delegate?.realtimeClient(self, didReceiveTextDone: text)
            }

        case .responseDone(let typed, _):
            if let typed {
                delegate?.realtimeClient(self, didReceiveTypedResponseDone: typed)
                let normalizedStatus = typed.response.status?.lowercased()
                if normalizedStatus == "cancelled" || normalizedStatus == "canceled" {
                    delegate?.realtimeClientDidReceiveResponseCancelled(self)
                }
            }
            delegate?.realtimeClientDidReceiveResponseDone(self)

        case .responseCancelled:
            delegate?.realtimeClientDidReceiveResponseCancelled(self)

        case .functionCallArgumentsDelta(let delta, let callId):
            if !delta.isEmpty, !callId.isEmpty {
                delegate?.realtimeClient(self, didReceiveFunctionCallArgumentsDelta: delta, callId: callId)
            }

        case .functionCallArgumentsDone(let arguments, let callId):
            if !arguments.isEmpty, !callId.isEmpty {
                delegate?.realtimeClient(self, didReceiveFunctionCallArgumentsDone: arguments, callId: callId)
            }

        case .inputAudioTranscriptionCompleted(let transcript, let itemId):
            delegate?.realtimeClient(self, didReceiveInputAudioTranscriptionDone: transcript, itemId: itemId)

        case .inputAudioTranscriptionFailed:
            logError("RealtimeClient: input audio transcription failed")

        case .conversationItemCreated(let item):
            if !item.isEmpty {
                delegate?.realtimeClient(self, didReceiveConversationItemCreated: item)
            }

        case .conversationItemDone(let item):
            if !item.isEmpty {
                delegate?.realtimeClient(self, didReceiveConversationItemDone: item)
            }

        case .conversationItemTruncated:
            logDebug("RealtimeClient: conversation item truncated")

        case .outputItemUpdated(let itemId, let contentIndex):
            if itemId != nil || contentIndex != nil {
                delegate?.realtimeClient(self, didUpdateActiveAudioOutput: itemId, contentIndex: contentIndex)
            }

        case .outputItemFunctionCall(let call):
            delegate?.realtimeClient(self, didReceiveFunctionCallItem: call)

        case .rateLimitsUpdated(let rateLimits):
            if !rateLimits.isEmpty {
                delegate?.realtimeClient(self, didReceiveRateLimitsUpdated: rateLimits)
            }

        case .unhandled(let type):
            logDebug("RealtimeClient: unhandled event type \(type)")
        }
    }

    private func completeDisconnect(error: Error?) {
        guard !disconnectNotified else {
            return
        }

        disconnectNotified = true
        reconnectStabilityResetWorkItem?.cancel()
        reconnectStabilityResetWorkItem = nil
        sessionReadyTimeoutWorkItem?.cancel()
        sessionReadyTimeoutWorkItem = nil
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        transition(to: .disconnected)

        let finalError = error ?? latestErrorMessage.map { RealtimeClientError(message: $0) }
        delegate?.realtimeClientDidDisconnect(self, error: finalError)
    }

    private func handleDisconnection(error: Error?) {
        guard connectionState != .disconnected else {
            return
        }
        guard connectionState != .reconnecting else {
            return
        }
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
            let delay = RealtimeReconnectionPolicy.retryDelay(for: reconnectAttempt - 1)
            transition(to: .reconnecting)
            logInfo(
                "RealtimeClient[\(connectionTraceID)]: reconnecting in \(delay.components.seconds)s (attempt \(reconnectAttempt)/\(maxReconnectAttempts), disposition=\(dispositionForDisconnect?.rawValue ?? "transport"), next_model=\(effectiveModelForConnectionAttempt))"
            )

            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            urlSession?.invalidateAndCancel()
            urlSession = nil
            resetSessionLifecycleState()

            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(delay.components.seconds)) { [weak self] in
                guard let self, self.connectionState == .reconnecting else {
                    return
                }
                self.disconnectNotified = false
                self.transition(to: .connecting)
                self.establishConnection()
            }
        } else {
            completeDisconnect(error: error)
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
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
            self.transition(to: .connected)
            self.receiveMessages(for: webSocketTask, generation: self.connectionGeneration)
            self.delegate?.realtimeClientDidConnect(self)
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        Task { @MainActor in
            guard self.webSocketTask === webSocketTask else {
                return
            }

            logInfo("RealtimeClient[\(self.connectionTraceID)]: WebSocket closed (code: \(closeCode.rawValue), reason: \(reasonString))")
            let closeError: Error? = closeCode == .normalClosure
                ? nil
                : RealtimeClientError(message: "WebSocket closed (code: \(closeCode.rawValue), reason: \(reasonString))")
            self.handleDisconnection(error: closeError)
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else {
            return
        }

        Task { @MainActor in
            guard self.webSocketTask === task else {
                return
            }
            logError("RealtimeClient: connection error: \(error.localizedDescription)")
            self.handleDisconnection(error: error)
        }
    }
}
