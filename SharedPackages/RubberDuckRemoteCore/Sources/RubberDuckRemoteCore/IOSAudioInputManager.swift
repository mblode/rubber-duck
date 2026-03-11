#if os(iOS)
import AVFoundation
import Foundation

@MainActor
public final class IOSAudioInputManager: ObservableObject {
    @Published public private(set) var isStreaming = false
    @Published public private(set) var microphonePermissionDenied = false

    private let engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!
    private var chunkHandler: ((String) -> Void)?
    private var errorHandler: ((Error) -> Void)?

    public init() {}

    public func start(
        onChunk: @escaping (String) -> Void,
        onError: ((Error) -> Void)? = nil
    ) async throws {
        if isStreaming {
            return
        }

        let granted = await requestPermission()
        microphonePermissionDenied = !granted
        guard granted else {
            throw NSError(domain: "IOSAudioInputManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Microphone permission is required."
            ])
        }

        chunkHandler = onChunk
        errorHandler = onError

        try configureSession()
        try configureEngine()
        try session.setActive(true)
        try engine.start()
        isStreaming = true
    }

    public func stop() {
        guard isStreaming else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isStreaming = false
        chunkHandler = nil
        errorHandler = nil
    }

    private func requestPermission() async -> Bool {
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func configureSession() throws {
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
        )
        try session.setPreferredSampleRate(24_000)
        try session.setPreferredInputNumberOfChannels(1)
    }

    private func configureEngine() throws {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw NSError(domain: "IOSAudioInputManager", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to configure microphone format conversion."
            ])
        }
        self.converter = converter

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.handleBuffer(buffer)
        }

        engine.prepare()
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter,
              let chunkHandler else {
            return
        }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(max(512, ceil(Double(buffer.frameLength) * ratio)))
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: frameCapacity
        ) else {
            return
        }

        var conversionError: NSError?
        var sourceConsumed = false
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, status in
            if sourceConsumed {
                status.pointee = .noDataNow
                return nil
            }
            sourceConsumed = true
            status.pointee = .haveData
            return buffer
        }

        if let conversionError {
            errorHandler?(conversionError)
            return
        }

        guard status != .error,
              outputBuffer.frameLength > 0,
              let channelData = outputBuffer.int16ChannelData else {
            return
        }

        let sampleCount = Int(outputBuffer.frameLength)
        let data = Data(
            bytes: channelData[0],
            count: sampleCount * MemoryLayout<Int16>.size
        )
        chunkHandler(data.base64EncodedString())
    }
}
#endif
