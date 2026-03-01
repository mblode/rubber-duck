import Foundation
import AVFoundation
import AppKit
import os

enum AudioConstants {
    static let sampleRate: Double = 24000
    static let captureBufferSize: AVAudioFrameCount = 1024
    static let channels: AVAudioChannelCount = 1
    // VoiceProcessingIO is not reliable on some multi-channel input devices.
    static let maxVoiceProcessingInputChannels: AVAudioChannelCount = 2
    /// RMS threshold below which audio is replaced with silence to prevent
    /// ambient noise from triggering server-side VAD. ~-46 dBFS, well below speech.
    static let noiseGateThreshold: Float = 0.005
    /// Stricter gate used when AEC is unavailable to reduce speaker bleed into capture.
    static let noiseGateThresholdWithoutAEC: Float = 0.012
    /// How long (in seconds) to keep sending real audio after signal drops below threshold.
    /// Prevents the gate from clipping inter-word pauses.
    static let noiseGateHoldTime: TimeInterval = 0.25
    /// Longer hold when AEC is unavailable to avoid gating real speech between words.
    static let noiseGateHoldTimeWithoutAEC: TimeInterval = 0.35
    /// Maximum time to wait for the first captured frame after engine startup.
    static let captureStartupFrameTimeout: TimeInterval = 0.6
}

enum MicrophonePermissionState: String {
    case notDetermined
    case granted
    case denied
    case restricted

    var isDenied: Bool {
        self == .denied || self == .restricted
    }

    static func from(_ status: AVAuthorizationStatus) -> MicrophonePermissionState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }
}

enum AudioEngineStartupMode: String, Equatable {
    case voiceProcessing
    case standard

    var enablesVoiceProcessing: Bool {
        self == .voiceProcessing
    }
}

struct AudioEngineStartupPlanStep: Equatable {
    let mode: AudioEngineStartupMode
    let maxStartAttempts: Int
}

enum AudioEngineStartupPlanner {
    // AVAudioEngine/AudioUnit failures that are typically configuration/hardware mismatches.
    // Retrying the same mode immediately is unlikely to help.
    static let nonRetryableEngineStartErrorCodes: Set<Int> = [
        -10868, // kAudioUnitErr_FormatNotSupported
        -66635  // kAudioUnitErr_MultipleVoiceProcessors
    ]

    static func makeStartupPlan(
        preferVoiceProcessing: Bool,
        detectedInputChannels: AVAudioChannelCount?,
        maxStartAttemptsPerMode: Int = 2
    ) -> [AudioEngineStartupPlanStep] {
        let attempts = max(1, maxStartAttemptsPerMode)
        let canUseVoiceProcessing: Bool
        if let detectedInputChannels {
            canUseVoiceProcessing = detectedInputChannels <= AudioConstants.maxVoiceProcessingInputChannels
        } else {
            // Conservative default: unknown channel topology should not start in VP mode.
            canUseVoiceProcessing = false
        }
        if preferVoiceProcessing {
            if canUseVoiceProcessing {
                return [
                    AudioEngineStartupPlanStep(mode: .voiceProcessing, maxStartAttempts: attempts),
                    AudioEngineStartupPlanStep(mode: .standard, maxStartAttempts: attempts)
                ]
            }
            return [AudioEngineStartupPlanStep(mode: .standard, maxStartAttempts: attempts)]
        }
        return [AudioEngineStartupPlanStep(mode: .standard, maxStartAttempts: attempts)]
    }

    static func shouldRetryEngineStart(
        errorCode: Int?,
        attempt: Int,
        maxAttempts: Int
    ) -> Bool {
        guard attempt < max(1, maxAttempts) else {
            return false
        }
        guard let errorCode else {
            return true
        }
        return !nonRetryableEngineStartErrorCodes.contains(errorCode)
    }

    static func retryDelayNanoseconds(afterFailedAttempt attempt: Int) -> UInt64 {
        let clampedAttempt = max(1, attempt)
        let delayMs = min(100 * (1 << (clampedAttempt - 1)), 400)
        return UInt64(delayMs) * 1_000_000
    }
}

class AudioManager: NSObject, ObservableObject {
    @Published var isStreaming = false
    @Published private(set) var isEchoCancellationActive: Bool = false
    @Published private(set) var microphonePermissionState: MicrophonePermissionState = .notDetermined
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var converter: AVAudioConverter?
    private var volumeMeter: AVAudioMixerNode?
    private let audioQueue = DispatchQueue(label: "co.blode.rubber-duck.audio")
    private let audioQueueKey = DispatchSpecificKey<Void>()
    private var streamingChunkCallback: ((String) -> Void)?
    private let isStreamingFlag = OSAllocatedUnfairLock(initialState: false)
    private let isInputMutedFlag = OSAllocatedUnfairLock(initialState: false)
    private let isCaptureStartupFlag = OSAllocatedUnfairLock(initialState: false)
    private let isEchoCancellationActiveFlag = OSAllocatedUnfairLock(initialState: false)
    private let startupFrameSemaphoreLock = NSLock()
    private var startupFrameSemaphore: DispatchSemaphore?
    private var lastSetupError: NSError?
    private var lastSetupDiagnostics: String?

    // Shared playback node — lives on the same engine as capture for AEC.
    private(set) var playerNode: AVAudioPlayerNode?
    private let pcm16PlaybackFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                                     sampleRate: AudioConstants.sampleRate,
                                                     channels: AudioConstants.channels,
                                                     interleaved: false)!

    // Noise gate state (accessed only on audioQueue)
    private var lastAboveThresholdTime: Date = .distantPast

    override init() {
        super.init()
        audioQueue.setSpecific(key: audioQueueKey, value: ())
        refreshMicrophonePermissionState()
    }

    var isCaptureEngineRunning: Bool {
        isStreamingFlag.withLock { $0 } && (audioEngine?.isRunning ?? false)
    }

    var isCaptureStartupInProgress: Bool {
        isCaptureStartupFlag.withLock { $0 }
    }

    var muteInput: Bool {
        get { isInputMutedFlag.withLock { $0 } }
        set { isInputMutedFlag.withLock { $0 = newValue } }
    }

    // MARK: - Audio Recording Setup

    func refreshMicrophonePermissionState() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let mappedState = MicrophonePermissionState.from(status)
        if Thread.isMainThread {
            microphonePermissionState = mappedState
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.microphonePermissionState = mappedState
            }
        }
    }

    var isMicrophonePermissionDenied: Bool {
        microphonePermissionState.isDenied
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func requestMicrophonePermissionIfNeeded(completion: ((Bool) -> Void)? = nil) {
        ensureMicrophonePermission { granted in
            completion?(granted)
        }
    }

    private func ensureMicrophonePermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        microphonePermissionState = MicrophonePermissionState.from(status)

        switch status {
        case .authorized:
            completion(true)

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.refreshMicrophonePermissionState()
                    completion(granted)
                }
            }

        case .denied, .restricted:
            completion(false)

        @unknown default:
            completion(false)
        }
    }

    private func setLastSetupError(
        code: Int,
        message: String,
        diagnostics: String? = nil
    ) {
        let diagnosticSuffix: String
        if let diagnostics, !diagnostics.isEmpty {
            diagnosticSuffix = " [\(diagnostics)]"
        } else {
            diagnosticSuffix = ""
        }
        lastSetupDiagnostics = diagnostics
        lastSetupError = NSError(
            domain: "co.blode.rubber-duck.audio",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: "\(message)\(diagnosticSuffix)"]
        )
    }

    private func osStatusLabel(code: Int) -> String {
        let unsignedCode = UInt32(bitPattern: Int32(code))
        let bytes = [
            UInt8((unsignedCode >> 24) & 0xFF),
            UInt8((unsignedCode >> 16) & 0xFF),
            UInt8((unsignedCode >> 8) & 0xFF),
            UInt8(unsignedCode & 0xFF)
        ]
        let isPrintable = bytes.allSatisfy { $0 >= 32 && $0 <= 126 }
        if isPrintable, let fourCC = String(bytes: bytes, encoding: .ascii) {
            return "\(code) (\(fourCC))"
        }
        return "\(code)"
    }

    private func setupAudioEngine(enableVoiceProcessing: Bool, includePlaybackNode: Bool) -> Bool {
        let graphMode = includePlaybackNode ? "shared-capture-playback" : "capture-only"
        logInfo(
            "AudioManager: Setting up audio engine (mode=\(enableVoiceProcessing ? "voice-processing" : "standard"), graph=\(graphMode))"
        )

        lastSetupError = nil
        lastSetupDiagnostics = nil

        // Clean up existing engine if any
        cleanupAudioEngine()

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            logError("AudioManager: Failed to create audio engine")
            setLastSetupError(code: -1001, message: "Failed to create audio engine", diagnostics: "graph=\(graphMode)")
            return false
        }

        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else {
            logError("AudioManager: Failed to get input node")
            setLastSetupError(code: -1002, message: "Failed to get input node", diagnostics: "graph=\(graphMode)")
            cleanupAudioEngine()
            return false
        }

        let preVoiceProcessingInputFormat = inputNode.outputFormat(forBus: 0)
        let setupDiagnostics = "graph=\(graphMode) input=\(preVoiceProcessingInputFormat)"

        if enableVoiceProcessing {
            if preVoiceProcessingInputFormat.channelCount > AudioConstants.maxVoiceProcessingInputChannels {
                logInfo(
                    "AudioManager: Skipping Voice Processing setup (input channels=\(preVoiceProcessingInputFormat.channelCount), max=\(AudioConstants.maxVoiceProcessingInputChannels))"
                )
                setLastSetupError(
                    code: -10875,
                    message: "Voice Processing disabled for multi-channel input",
                    diagnostics: setupDiagnostics
                )
                cleanupAudioEngine()
                return false
            }
            // Enable Voice Processing IO for acoustic echo cancellation + noise suppression.
            // Both capture and playback must share the same engine for AEC to have a
            // reference signal from the output path.
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                logInfo("AudioManager: Voice Processing IO enabled (AEC + noise suppression active)")
            } catch {
                logError("AudioManager: Failed to enable Voice Processing IO: \(error.localizedDescription)")
                let errorCode = (error as NSError).code
                setLastSetupError(
                    code: errorCode,
                    message: "Failed to enable Voice Processing IO",
                    diagnostics: "\(setupDiagnostics) status=\(osStatusLabel(code: errorCode))"
                )
                cleanupAudioEngine()
                return false
            }
        }

        // Set up capture path: inputNode → volumeMeter → [tap]
        volumeMeter = AVAudioMixerNode()
        guard let volumeMeter = volumeMeter else {
            logError("AudioManager: Failed to create volume meter")
            setLastSetupError(code: -1003, message: "Failed to create volume meter", diagnostics: setupDiagnostics)
            cleanupAudioEngine()
            return false
        }

        audioEngine.attach(volumeMeter)

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            logError("AudioManager: Invalid input format: \(inputFormat)")
            setLastSetupError(code: -10868, message: "Invalid input format", diagnostics: setupDiagnostics)
            cleanupAudioEngine()
            return false
        }
        let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                        sampleRate: AudioConstants.sampleRate,
                                        channels: AudioConstants.channels,
                                        interleaved: false)!

        // When VoiceProcessingIO is active on a multi-channel device, downmix to mono so
        // the audio graph is valid. VoiceProcessingIO AEC still operates on the hardware-level
        // reference signal regardless of the downstream capture format.
        let captureFormat: AVAudioFormat
        if enableVoiceProcessing && inputFormat.channelCount > AudioConstants.maxVoiceProcessingInputChannels {
            captureFormat = AVAudioFormat(
                standardFormatWithSampleRate: inputFormat.sampleRate,
                channels: 1
            ) ?? whisperFormat
            logInfo(
                "AudioManager: Voice Processing input has \(inputFormat.channelCount) channels; using mono capture format for AEC compatibility"
            )
        } else {
            captureFormat = inputFormat
        }

        logDebug("AudioManager: Input format: \(inputFormat)")
        logDebug("AudioManager: Capture format: \(captureFormat)")
        logDebug("AudioManager: Whisper format: \(whisperFormat)")

        volumeMeter.volume = 1.0
        audioEngine.connect(inputNode, to: volumeMeter, format: captureFormat)

        if includePlaybackNode {
            // Set up playback path on the SAME engine: playerNode → mainMixerNode → outputNode.
            // Sharing the engine lets VoiceProcessingIO access the output reference signal for AEC.
            let player = AVAudioPlayerNode()
            audioEngine.attach(player)
            audioEngine.connect(player, to: audioEngine.mainMixerNode, format: pcm16PlaybackFormat)
            playerNode = player
        } else {
            playerNode = nil
        }

        audioEngine.prepare()

        volumeMeter.installTap(onBus: 0, bufferSize: AudioConstants.captureBufferSize, format: captureFormat) { [weak self] (buffer, time) in
            self?.signalStartupCaptureFrameIfNeeded()
            self?.audioQueue.async { [weak self] in
                guard let self = self, self.isStreamingFlag.withLock({ $0 }) else { return }

                let convertedBuffer = self.convertToTargetFormat(buffer: buffer, inputFormat: captureFormat, targetFormat: whisperFormat)
                guard let finalBuffer = convertedBuffer else { return }

                // Software mute: zero-fill during model playback to prevent echo on
                // devices where VoiceProcessingIO is unavailable.
                if self.isInputMutedFlag.withLock({ $0 }) {
                    self.zeroFill(finalBuffer)
                    guard let base64String = self.pcmBufferToBase64(finalBuffer) else { return }
                    let callback = self.streamingChunkCallback
                    callback?(base64String)
                    return
                }

                // Noise gate: replace quiet audio with silence instead of dropping,
                // since the OpenAI Realtime API expects continuous audio input.
                let now = Date()
                let rms = self.rmsLevel(of: finalBuffer)
                let isEchoCancellationActive = self.isEchoCancellationActiveFlag.withLock { $0 }
                let activeNoiseGateThreshold = isEchoCancellationActive
                    ? AudioConstants.noiseGateThreshold
                    : AudioConstants.noiseGateThresholdWithoutAEC
                let activeNoiseGateHoldTime = isEchoCancellationActive
                    ? AudioConstants.noiseGateHoldTime
                    : AudioConstants.noiseGateHoldTimeWithoutAEC

                if rms >= activeNoiseGateThreshold {
                    self.lastAboveThresholdTime = now
                } else if now.timeIntervalSince(self.lastAboveThresholdTime) >= activeNoiseGateHoldTime {
                    self.zeroFill(finalBuffer)
                }

                guard let base64String = self.pcmBufferToBase64(finalBuffer) else { return }

                let callback = self.streamingChunkCallback
                callback?(base64String)
            }
        }

        return true
    }

    private func convertToTargetFormat(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat, targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        if converter == nil && inputFormat != targetFormat {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        }

        guard let converter = converter else {
            return buffer
        }

        let frameCount = AVAudioFrameCount(Float(buffer.frameLength) * Float(targetFormat.sampleRate) / Float(inputFormat.sampleRate))
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            return nil
        }
        convertedBuffer.frameLength = frameCount

        var error: NSError?
        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            logError("AudioManager: Conversion error: \(error)")
            return nil
        }

        return convertedBuffer
    }

    private func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let floatData = buffer.floatChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        let samples = floatData[0]
        var sumSquares: Float = 0
        for i in 0..<frameCount {
            sumSquares += samples[i] * samples[i]
        }
        return sqrt(sumSquares / Float(frameCount))
    }

    private func zeroFill(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        for ch in 0..<Int(buffer.format.channelCount) {
            for i in 0..<frameCount {
                floatData[ch][i] = 0
            }
        }
    }

    private func pcmBufferToBase64(_ buffer: AVAudioPCMBuffer) -> String? {
        guard let floatData = buffer.floatChannelData else { return nil }
        let frameCount = Int(buffer.frameLength)
        let samples = floatData[0]

        var int16Data = Data(count: frameCount * 2)
        int16Data.withUnsafeMutableBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<frameCount {
                let clamped = Int16(max(-32768, min(32767, Int32(samples[i] * 32767.0))))
                int16Buffer[i] = clamped.littleEndian
            }
        }

        return int16Data.base64EncodedString()
    }

    private func cleanupAudioEngine() {
        logInfo("AudioManager: Cleaning up audio engine")
        playerNode?.stop()
        audioEngine?.stop()
        volumeMeter?.removeTap(onBus: 0)
        audioEngine = nil
        inputNode = nil
        playerNode = nil
        volumeMeter = nil
        converter = nil
        clearStartupCaptureFrameSemaphore()
    }

    // MARK: - Streaming Control

    private func detectedInputChannelCount() -> AVAudioChannelCount? {
        let probeEngine = AVAudioEngine()
        let probeFormat = probeEngine.inputNode.outputFormat(forBus: 0)
        guard probeFormat.channelCount > 0 else {
            return nil
        }
        return probeFormat.channelCount
    }

    func startStreaming(onChunk: @escaping (String) -> Void, onError: ((Error) -> Void)? = nil) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.startStreaming(onChunk: onChunk, onError: onError)
            }
            return
        }

        ensureMicrophonePermission { [weak self] granted in
            guard let self = self else { return }

            guard granted else {
                logInfo("AudioManager: Microphone permission not granted for streaming")
                let permissionError = NSError(
                    domain: "co.blode.rubber-duck.audio",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied"]
                )
                DispatchQueue.main.async { onError?(permissionError) }
                return
            }

            self.streamingChunkCallback = onChunk

            self.audioQueue.async { [weak self] in
                guard let self = self else { return }
                self.isCaptureStartupFlag.withLock { $0 = true }
                defer { self.isCaptureStartupFlag.withLock { $0 = false } }

                let detectedChannels = self.detectedInputChannelCount()
                if let detectedChannels, detectedChannels > AudioConstants.maxVoiceProcessingInputChannels {
                    logInfo(
                        "AudioManager: Skipping Voice Processing startup (input channels=\(detectedChannels))"
                    )
                }

                let startupPlan = AudioEngineStartupPlanner.makeStartupPlan(
                    preferVoiceProcessing: true,
                    detectedInputChannels: detectedChannels
                )
                var lastError: Error?

                @discardableResult
                func attemptEngineStart(
                    step: AudioEngineStartupPlanStep,
                    includePlaybackNode: Bool
                ) -> Bool {
                    let graphMode = includePlaybackNode ? "shared-capture-playback" : "capture-only"
                    for attempt in 1...step.maxStartAttempts {
                        guard self.setupAudioEngine(
                            enableVoiceProcessing: step.mode.enablesVoiceProcessing,
                            includePlaybackNode: includePlaybackNode
                        ), let audioEngine = self.audioEngine else {
                            let setupError = self.lastSetupError ?? NSError(
                                domain: "co.blode.rubber-duck.audio",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Audio engine setup failed"]
                            )
                            lastError = setupError
                            let errorCode = setupError.code
                            let diagnostics = self.lastSetupDiagnostics.map { " diagnostics=\($0)" } ?? ""
                            logError(
                                "AudioManager: Engine setup failed (mode=\(step.mode.rawValue), graph=\(graphMode), attempt=\(attempt), code=\(self.osStatusLabel(code: errorCode))\(diagnostics)): \(setupError.localizedDescription)"
                            )

                            guard AudioEngineStartupPlanner.shouldRetryEngineStart(
                                errorCode: errorCode,
                                attempt: attempt,
                                maxAttempts: step.maxStartAttempts
                            ) else {
                                break
                            }

                            let delayNs = AudioEngineStartupPlanner.retryDelayNanoseconds(afterFailedAttempt: attempt)
                            Thread.sleep(forTimeInterval: Double(delayNs) / 1_000_000_000)
                            continue
                        }

                        let firstFrameSemaphore = DispatchSemaphore(value: 0)
                        self.setStartupCaptureFrameSemaphore(firstFrameSemaphore)

                        do {
                            self.isStreamingFlag.withLock { $0 = true }
                            try audioEngine.start()

                            let startupTimeout = DispatchTime.now() + .milliseconds(
                                Int(AudioConstants.captureStartupFrameTimeout * 1000)
                            )
                            let didReceiveFirstFrame = firstFrameSemaphore.wait(timeout: startupTimeout) == .success
                            self.clearStartupCaptureFrameSemaphore()

                            guard didReceiveFirstFrame else {
                                throw NSError(
                                    domain: "co.blode.rubber-duck.audio",
                                    code: -3,
                                    userInfo: [NSLocalizedDescriptionKey: "Microphone capture produced no frames after startup"]
                                )
                            }

                            let aecActive = step.mode == .voiceProcessing
                            self.isEchoCancellationActiveFlag.withLock { $0 = aecActive }
                            DispatchQueue.main.async {
                                self.isStreaming = true
                                self.isEchoCancellationActive = aecActive
                            }

                            logInfo(
                                "AudioManager: Streaming started successfully (mode=\(step.mode.rawValue), graph=\(graphMode), attempt=\(attempt))"
                            )
                            return true
                        } catch {
                            self.isStreamingFlag.withLock { $0 = false }
                            self.clearStartupCaptureFrameSemaphore()
                            lastError = error
                            let errorCode = (error as NSError).code
                            let diagnostics = self.lastSetupDiagnostics.map { " diagnostics=\($0)" } ?? ""
                            logError(
                                "AudioManager: Engine start failed (mode=\(step.mode.rawValue), graph=\(graphMode), attempt=\(attempt), code=\(self.osStatusLabel(code: errorCode))\(diagnostics)): \(error.localizedDescription)"
                            )
                            audioEngine.stop()
                            self.cleanupAudioEngine()

                            guard AudioEngineStartupPlanner.shouldRetryEngineStart(
                                errorCode: errorCode,
                                attempt: attempt,
                                maxAttempts: step.maxStartAttempts
                            ) else {
                                break
                            }

                            let delayNs = AudioEngineStartupPlanner.retryDelayNanoseconds(afterFailedAttempt: attempt)
                            Thread.sleep(forTimeInterval: Double(delayNs) / 1_000_000_000)
                        }
                    }

                    self.cleanupAudioEngine()
                    return false
                }

                for step in startupPlan {
                    if attemptEngineStart(step: step, includePlaybackNode: true) {
                        return
                    }
                    if step.mode == .voiceProcessing {
                        logInfo("AudioManager: Falling back to standard audio engine startup")
                    }
                }

                // Last-resort fallback for hardware/driver combinations that fail to
                // initialize a shared capture+playback graph. We keep mic capture alive;
                // playback manager will use a standalone fallback output engine.
                logInfo("AudioManager: Retrying startup in capture-only fallback mode")
                if attemptEngineStart(
                    step: AudioEngineStartupPlanStep(mode: .standard, maxStartAttempts: 2),
                    includePlaybackNode: false
                ) {
                    logInfo("AudioManager: Capture-only fallback active; playback will use fallback output engine")
                    return
                }

                self.isStreamingFlag.withLock { $0 = false }
                let startupError = lastError ?? NSError(
                    domain: "co.blode.rubber-duck.audio",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to start audio engine"]
                )
                logError("AudioManager: Failed to start streaming after startup retries/fallback")
                DispatchQueue.main.async { onError?(startupError) }
            }
        }
    }

    private func setStartupCaptureFrameSemaphore(_ semaphore: DispatchSemaphore) {
        startupFrameSemaphoreLock.lock()
        startupFrameSemaphore = semaphore
        startupFrameSemaphoreLock.unlock()
    }

    private func signalStartupCaptureFrameIfNeeded() {
        startupFrameSemaphoreLock.lock()
        let semaphore = startupFrameSemaphore
        startupFrameSemaphore = nil
        startupFrameSemaphoreLock.unlock()
        semaphore?.signal()
    }

    private func clearStartupCaptureFrameSemaphore() {
        startupFrameSemaphoreLock.lock()
        startupFrameSemaphore = nil
        startupFrameSemaphoreLock.unlock()
    }

    func stopStreaming() {
        logInfo("AudioManager: Stopping streaming")
        isStreaming = false
        isEchoCancellationActive = false
        isEchoCancellationActiveFlag.withLock { $0 = false }

        let teardown = { [weak self] in
            self?.isStreamingFlag.withLock { $0 = false }
            self?.isCaptureStartupFlag.withLock { $0 = false }
            self?.audioEngine?.stop()
            self?.volumeMeter?.removeTap(onBus: 0)
            self?.cleanupAudioEngine()
        }
        if DispatchQueue.getSpecific(key: audioQueueKey) != nil {
            teardown()
        } else {
            audioQueue.async(execute: teardown)
        }

        streamingChunkCallback = nil
    }
}
