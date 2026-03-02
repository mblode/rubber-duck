import Foundation
import AVFoundation
import AppKit
import os
import Accelerate

enum AudioConstants {
    static let sampleRate: Double = 24000
    static let captureBufferSize: AVAudioFrameCount = 1024
    static let channels: AVAudioChannelCount = 1
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
        // Always attempt VP first — setupAudioEngine handles mono downmix for multi-channel
        // inputs (e.g. MacBook Pro 9-channel mic), and the planner falls back to standard
        // mode if VP engine start fails.
        let canUseVoiceProcessing: Bool = preferVoiceProcessing
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

    // MARK: - Software AEC

    /// Reference buffer populated by AudioPlaybackManager with every PCM chunk it plays.
    /// AudioManager reads from this buffer in the capture tap to subtract speaker output.
    var referenceBuffer: PlaybackReferenceBuffer?

    /// Pre-allocated scratch buffer for AEC subtraction — avoids real-time heap allocation.
    private var aecScratch = [Float](repeating: 0, count: Int(AudioConstants.captureBufferSize))

    /// Estimated round-trip delay (speaker schedule → microphone capture) in samples.
    /// Loaded from UserDefaults on init, falls back to 1440 (60 ms at 24 kHz).
    private var estimatedDelayInSamples: Int = 1440

    /// Estimated bleedthrough gain (how much of the reference signal leaks into capture).
    /// Loaded from UserDefaults, updated adaptively during playback.
    private var echoCancellationGain: Float = 0.50

    /// mach_timebase_info for converting mach_absolute_time ticks to seconds.
    private var machTimebaseInfo = mach_timebase_info_data_t(numer: 0, denom: 0)

    /// Wall-clock time of the last user speech detection event.
    /// Used to suppress gain calibration during actual user speech.
    private var lastSpeechDetectedAt: Date = .distantPast

    /// Throttle: last time delay estimate was persisted to UserDefaults.
    private var lastDelayPersistAt: Date = .distantPast

    /// Throttle: last time gain was persisted to UserDefaults.
    private var lastGainPersistAt: Date = .distantPast

    /// Whether the last AEC subtraction succeeded (reference data available).
    private var lastAECReadSucceeded = false

    /// @Published software AEC active flag (true when standard mode + referenceBuffer non-nil).
    @Published private(set) var isSoftwareAECActive: Bool = false
    private let isSoftwareAECActiveFlag = OSAllocatedUnfairLock(initialState: false)

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

        // Load persisted AEC calibration values.
        let savedDelay = UserDefaults.standard.integer(forKey: "aecDelayEstimateSamples")
        if savedDelay >= 480 && savedDelay <= 4800 {
            estimatedDelayInSamples = savedDelay
        }
        let savedGain = UserDefaults.standard.float(forKey: "aecEchoCancellationGain")
        if savedGain >= 0.01 && savedGain <= 5.0 {
            echoCancellationGain = savedGain
        }
        mach_timebase_info(&machTimebaseInfo)
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
            // Enable Voice Processing IO for acoustic echo cancellation + noise suppression.
            // Both capture and playback must share the same engine for AEC to have a
            // reference signal from the output path.
            // Multi-channel inputs (e.g. MacBook Pro 9-channel mic array) are handled via
            // mono downmix below — VoiceProcessingIO AEC still operates on the hardware
            // reference signal regardless of the downstream capture format.
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
        if enableVoiceProcessing && inputFormat.channelCount > 2 {
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

                // Software AEC: subtract known playback reference from captured signal.
                // Must run after format conversion (signal is now Float32 mono 24 kHz)
                // and before the noise gate (gate must see the echo-cancelled signal).
                if let ref = self.referenceBuffer,
                   let floatData = finalBuffer.floatChannelData {
                    let frameCount = Int(finalBuffer.frameLength)

                    // Step 1: Read reference into scratch (lock-free, no allocation).
                    let didRead = self.aecScratch.withUnsafeMutableBufferPointer { ptr in
                        ref.read(into: ptr.baseAddress!, frameCount: frameCount,
                                 delaySamples: self.estimatedDelayInSamples)
                    }
                    self.lastAECReadSucceeded = didRead

                    if didRead {
                        // Step 2: Calibrate gain using the ORIGINAL capture (before subtraction)
                        // so we measure true bleedthrough ratio, not the residual.
                        self.aecScratch.withUnsafeBufferPointer { refPtr in
                            self.updateEchoCancellationGain(
                                captureSamples: floatData[0],
                                referenceSamples: refPtr.baseAddress!,
                                frameCount: frameCount
                            )
                        }

                        // Step 3: Apply subtraction in place: capture -= reference * gain.
                        var negGain = -self.echoCancellationGain
                        vDSP_vsma(self.aecScratch, 1, &negGain,
                                  floatData[0], 1, floatData[0], 1, vDSP_Length(frameCount))
                    }
                }

                // Update delay estimate using the capture host time.
                if time.isSampleTimeValid {
                    self.updateDelayEstimate(captureHostTime: time.hostTime)
                }

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
                let isSoftwareAECActive = self.isSoftwareAECActiveFlag.withLock { $0 }
                let anyAECActive = isEchoCancellationActive || isSoftwareAECActive
                var activeNoiseGateThreshold = anyAECActive
                    ? AudioConstants.noiseGateThreshold
                    : AudioConstants.noiseGateThresholdWithoutAEC
                let activeNoiseGateHoldTime = anyAECActive
                    ? AudioConstants.noiseGateHoldTime
                    : AudioConstants.noiseGateHoldTimeWithoutAEC

                // Proportional echo gate: when reference was read this frame, raise the gate
                // threshold to 3.0× reference RMS. Residual echo after software AEC subtraction
                // is typically 1–2× reference; genuine speech is 3–6× reference at the mic.
                if self.lastAECReadSucceeded {
                    let frameCount = Int(finalBuffer.frameLength)
                    var refRMS: Float = 0
                    self.aecScratch.withUnsafeBufferPointer { ptr in
                        vDSP_rmsqv(ptr.baseAddress!, 1, &refRMS, vDSP_Length(frameCount))
                    }
                    let proportionalThreshold = refRMS * 3.0
                    if proportionalThreshold > activeNoiseGateThreshold {
                        activeNoiseGateThreshold = proportionalThreshold
                    }
                }

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
                            let softwareAECEnabled = !aecActive && self.referenceBuffer != nil
                            self.isSoftwareAECActiveFlag.withLock { $0 = softwareAECEnabled }
                            DispatchQueue.main.async {
                                self.isSoftwareAECActive = softwareAECEnabled
                            }

                            let aecSummary: String
                            if aecActive {
                                aecSummary = "hardware-AEC=on, software-AEC=off"
                            } else if softwareAECEnabled {
                                aecSummary = "hardware-AEC=off, software-AEC=on (gain=\(String(format: "%.2f", self.echoCancellationGain)), delay=\(self.estimatedDelayInSamples)smp)"
                            } else {
                                aecSummary = "hardware-AEC=off, software-AEC=off (no reference buffer)"
                            }
                            logInfo(
                                "AudioManager: Streaming started successfully (mode=\(step.mode.rawValue), graph=\(graphMode), attempt=\(attempt), \(aecSummary))"
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

                // Try VP in capture-only mode: removes the multi-channel output format conflict
                // that causes -10875 in shared-graph mode. VoiceProcessingIO uses the system
                // audio output as its AEC reference at the driver level, independent of the
                // app's AVAudioEngine graph — hardware AEC works without a playerNode present.
                logInfo("AudioManager: Retrying with voice-processing capture-only mode")
                if attemptEngineStart(
                    step: AudioEngineStartupPlanStep(mode: .voiceProcessing, maxStartAttempts: 2),
                    includePlaybackNode: false
                ) {
                    logInfo("AudioManager: VP capture-only active; hardware AEC on, playback uses fallback engine")
                    return
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
        isSoftwareAECActiveFlag.withLock { $0 = false }
        DispatchQueue.main.async {
            self.isSoftwareAECActive = false
        }

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

    // MARK: - Software AEC

    /// Notify that user speech was detected. Suppresses AEC gain calibration for 0.5 s.
    /// Called from VoiceSessionCoordinator.realtimeClientDidDetectSpeechStarted().
    func notifySpeechDetected() {
        lastSpeechDetectedAt = Date()
    }

    /// Convert mach_absolute_time ticks to seconds using the stored timebase info.
    private func machTicksToSeconds(_ ticks: UInt64) -> Double {
        guard machTimebaseInfo.denom != 0 else { return 0 }
        return Double(ticks) * Double(machTimebaseInfo.numer) / Double(machTimebaseInfo.denom) / 1_000_000_000.0
    }

    /// Update the estimated round-trip delay using the gap between the latest playback
    /// schedule timestamp and the current capture host time.
    private func updateDelayEstimate(captureHostTime: UInt64) {
        guard let ref = referenceBuffer, captureHostTime > 0 else { return }
        let refTimestamp = ref.latestScheduledAt()
        guard refTimestamp > 0, captureHostTime > refTimestamp else { return }

        let deltaSecs = machTicksToSeconds(captureHostTime - refTimestamp)
        let measured = Int(deltaSecs * AudioConstants.sampleRate)
        guard measured >= 480 && measured <= 4800 else { return }

        // Exponential moving average with slow alpha for stability.
        let alpha: Float = 0.05
        estimatedDelayInSamples = Int(Float(estimatedDelayInSamples) * (1 - alpha) + Float(measured) * alpha)

        // Persist at most once per 10 seconds.
        if Date().timeIntervalSince(lastDelayPersistAt) > 10.0 {
            UserDefaults.standard.set(estimatedDelayInSamples, forKey: "aecDelayEstimateSamples")
            lastDelayPersistAt = Date()
        }
    }

    /// Apply software echo cancellation: subtract the scaled, delayed reference signal
    /// from the captured microphone signal in place.
    ///
    /// This is `internal` (not `private`) so unit tests can call it directly.
    ///
    /// - Returns: `true` if the reference read succeeded and subtraction was applied.
    @discardableResult
    func applyEchoSubtraction(
        to samples: UnsafeMutablePointer<Float>,
        frameCount: Int,
        reference: PlaybackReferenceBuffer,
        delaySamples: Int,
        gain: Float,
        scratch: inout [Float]
    ) -> Bool {
        guard frameCount > 0, frameCount <= scratch.count else { return false }

        let didRead = scratch.withUnsafeMutableBufferPointer { ptr in
            reference.read(into: ptr.baseAddress!, frameCount: frameCount, delaySamples: delaySamples)
        }
        guard didRead else { return false }

        // In-place: samples[i] -= scratch[i] * gain   (vDSP SIMD accelerated)
        var negGain = -gain
        vDSP_vsma(scratch, 1, &negGain, samples, 1, samples, 1, vDSP_Length(frameCount))
        return true
    }

    /// Adaptively update the echo cancellation gain based on the current capture RMS
    /// vs. the reference RMS. Only runs when hardware AEC is off and no user speech
    /// has been detected recently.
    private func updateEchoCancellationGain(captureSamples: UnsafePointer<Float>,
                                             referenceSamples: UnsafePointer<Float>,
                                             frameCount: Int) {
        guard !isEchoCancellationActiveFlag.withLock({ $0 }) else { return }
        // Suppress calibration for 1.2s after speech — matches the full VAD suppression window.
        // 0.5s was too short: echo arriving after the assistant begins responding could
        // retune the gain toward the echo, degrading cancellation over time.
        guard Date().timeIntervalSince(lastSpeechDetectedAt) > 1.2 else { return }
        guard frameCount > 0 else { return }

        var captureRMS: Float = 0
        var refRMS: Float = 0
        vDSP_rmsqv(captureSamples, 1, &captureRMS, vDSP_Length(frameCount))
        vDSP_rmsqv(referenceSamples, 1, &refRMS, vDSP_Length(frameCount))

        guard captureRMS > 0.001, refRMS > 0.001 else { return }

        let measuredGain = captureRMS / refRMS
        let alpha: Float = 0.05
        echoCancellationGain = echoCancellationGain * (1 - alpha) + measuredGain * alpha
        echoCancellationGain = max(0.01, min(5.0, echoCancellationGain))

        if Date().timeIntervalSince(lastGainPersistAt) > 10.0 {
            UserDefaults.standard.set(echoCancellationGain, forKey: "aecEchoCancellationGain")
            lastGainPersistAt = Date()
        }
    }
}
