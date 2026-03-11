#if os(iOS)
import AVFoundation
import Foundation

@MainActor
public final class IOSAudioPlaybackManager: ObservableObject {
    public var onPlaybackIdle: (() -> Void)?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: RealtimeAudioConstants.sampleRate,
        channels: AVAudioChannelCount(RealtimeAudioConstants.channels),
        interleaved: false
    )!
    private var configured = false
    private var pendingBuffers = 0

    public init() {}

    public func enqueueAudio(base64Chunk: String) {
        do {
            try enqueue(base64Chunk: base64Chunk)
        } catch {
            logError("IOSAudioPlaybackManager: \(error.localizedDescription)")
        }
    }

    public func stopImmediately() {
        stop()
    }

    public func stop() {
        guard configured else { return }
        playerNode.stop()
        engine.stop()
        pendingBuffers = 0
        configured = false
    }

    private func startIfNeeded() throws {
        guard !configured else { return }
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        playerNode.play()
        configured = true
    }

    private func enqueue(base64Chunk: String) throws {
        try startIfNeeded()

        guard let data = Data(base64Encoded: base64Chunk) else {
            return
        }

        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(sampleCount)
              ),
              let channelData = buffer.int16ChannelData else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(sampleCount)
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            channelData[0].update(
                from: baseAddress.assumingMemoryBound(to: Int16.self),
                count: sampleCount
            )
        }

        pendingBuffers += 1
        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingBuffers = max(0, self.pendingBuffers - 1)
                if self.pendingBuffers == 0 {
                    self.onPlaybackIdle?()
                }
            }
        }
    }
}
#endif
