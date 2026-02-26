import Foundation
import AVFoundation
import AppKit
import os

enum AudioConstants {
    static let sampleRate: Double = 24000
    static let captureBufferSize: AVAudioFrameCount = 1024
    static let channels: AVAudioChannelCount = 1
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

class AudioManager: NSObject, ObservableObject {
    @Published var isStreaming = false
    @Published private(set) var microphonePermissionState: MicrophonePermissionState = .notDetermined
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var converter: AVAudioConverter?
    private var volumeMeter: AVAudioMixerNode?
    private let audioQueue = DispatchQueue(label: "co.blode.rubber-duck.audio")
    private var streamingChunkCallback: ((String) -> Void)?
    private let isStreamingFlag = OSAllocatedUnfairLock(initialState: false)

    override init() {
        super.init()
        refreshMicrophonePermissionState()
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

    private func setupAudioEngine() {
        logInfo("AudioManager: Setting up audio engine")

        // Clean up existing engine if any
        cleanupAudioEngine()

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else {
            logError("AudioManager: Failed to get input node")
            return
        }

        volumeMeter = AVAudioMixerNode()
        guard let volumeMeter = volumeMeter else { return }

        audioEngine.attach(volumeMeter)

        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            logError("AudioManager: Invalid input format: \(inputFormat)")
            return
        }

        let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                        sampleRate: AudioConstants.sampleRate,
                                        channels: AudioConstants.channels,
                                        interleaved: false)!

        logDebug("AudioManager: Input format: \(inputFormat)")
        logDebug("AudioManager: Whisper format: \(whisperFormat)")

        volumeMeter.volume = 1.0
        audioEngine.connect(inputNode, to: volumeMeter, format: inputFormat)
        audioEngine.prepare()

        volumeMeter.installTap(onBus: 0, bufferSize: AudioConstants.captureBufferSize, format: inputFormat) { [weak self] (buffer, time) in
            self?.audioQueue.async { [weak self] in
                guard let self = self, self.isStreamingFlag.withLock({ $0 }) else { return }

                let convertedBuffer = self.convertToTargetFormat(buffer: buffer, inputFormat: inputFormat, targetFormat: whisperFormat)
                guard let finalBuffer = convertedBuffer else { return }
                guard let base64String = self.pcmBufferToBase64(finalBuffer) else { return }

                let callback = self.streamingChunkCallback
                DispatchQueue.global(qos: .userInitiated).async {
                    callback?(base64String)
                }
            }
        }
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
        audioEngine?.stop()
        volumeMeter?.removeTap(onBus: 0)
        audioEngine = nil
        inputNode = nil
        volumeMeter = nil
        converter = nil
    }

    // MARK: - Streaming Control

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
                return
            }

            self.streamingChunkCallback = onChunk
            self.setupAudioEngine()

            self.audioQueue.async { [weak self] in
                guard let self = self, let audioEngine = self.audioEngine else {
                    logError("AudioManager: No audio engine available for streaming")
                    return
                }

                do {
                    self.isStreamingFlag.withLock { $0 = true }
                    try audioEngine.start()
                    DispatchQueue.main.async {
                        self.isStreaming = true
                    }
                    logInfo("AudioManager: Streaming started successfully")
                } catch {
                    self.isStreamingFlag.withLock { $0 = false }
                    logError("AudioManager: Failed to start streaming: \(error.localizedDescription)")
                    DispatchQueue.main.async { onError?(error) }
                }
            }
        }
    }

    func stopStreaming() {
        logInfo("AudioManager: Stopping streaming")
        isStreaming = false

        audioQueue.sync { [weak self] in
            self?.isStreamingFlag.withLock { $0 = false }
            self?.audioEngine?.stop()
            self?.volumeMeter?.removeTap(onBus: 0)
            self?.cleanupAudioEngine()
        }

        streamingChunkCallback = nil
    }
}
