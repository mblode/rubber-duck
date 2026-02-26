import Foundation
import AVFoundation

class AudioPlaybackManager: ObservableObject {
    @Published var isPlaying = false

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let playbackQueue = DispatchQueue(label: "co.blode.rubber-duck.playback")

    private let pcm16Format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                            sampleRate: AudioConstants.sampleRate,
                                            channels: AudioConstants.channels,
                                            interleaved: false)!

    private(set) var totalSamplesScheduled: Int = 0
    private(set) var totalSamplesPlayed: Int = 0

    // MARK: - Playback Control

    func startPlayback() {
        playbackQueue.async { [weak self] in
            guard let self = self else { return }

            self.cleanupEngine()

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()

            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: self.pcm16Format)
            engine.prepare()

            do {
                try engine.start()
                player.play()
                self.audioEngine = engine
                self.playerNode = player
                self.totalSamplesScheduled = 0
                self.totalSamplesPlayed = 0
                DispatchQueue.main.async {
                    self.isPlaying = true
                }
                logInfo("AudioPlaybackManager: Playback started")
            } catch {
                logError("AudioPlaybackManager: Failed to start engine: \(error.localizedDescription)")
            }
        }
    }

    func stopPlayback() {
        playbackQueue.async { [weak self] in
            guard let self = self else { return }
            self.cleanupEngine()
            DispatchQueue.main.async {
                self.isPlaying = false
            }
            logInfo("AudioPlaybackManager: Playback stopped")
        }
    }

    func stopImmediately() -> Int {
        return playbackQueue.sync { [weak self] () -> Int in
            guard let self = self else { return 0 }

            let unplayed = self.totalSamplesScheduled - self.totalSamplesPlayed
            self.playerNode?.stop()
            self.cleanupEngine()
            DispatchQueue.main.async {
                self.isPlaying = false
            }
            logInfo("AudioPlaybackManager: Stopped immediately, \(unplayed) unplayed samples")
            return max(unplayed, 0)
        }
    }

    // MARK: - Audio Enqueueing

    func enqueueAudio(base64Chunk: String) {
        guard let data = Data(base64Encoded: base64Chunk) else {
            logError("AudioPlaybackManager: Failed to decode base64 audio chunk")
            return
        }

        let sampleCount = data.count / MemoryLayout<Int16>.size

        guard sampleCount > 0 else {
            logDebug("AudioPlaybackManager: Empty audio chunk, skipping")
            return
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: pcm16Format,
                                            frameCapacity: AVAudioFrameCount(sampleCount)) else {
            logError("AudioPlaybackManager: Failed to create PCM buffer")
            return
        }

        buffer.frameLength = AVAudioFrameCount(sampleCount)

        guard let int16ChannelData = buffer.int16ChannelData else {
            logError("AudioPlaybackManager: Failed to get int16 channel data")
            return
        }

        data.withUnsafeBytes { rawBuffer in
            let source = rawBuffer.bindMemory(to: Int16.self)
            int16ChannelData[0].update(from: source.baseAddress!, count: sampleCount)
        }

        playbackQueue.async { [weak self] in
            guard let self = self, let playerNode = self.playerNode else {
                logDebug("AudioPlaybackManager: No player node, dropping audio chunk")
                return
            }

            self.totalSamplesScheduled += sampleCount

            playerNode.scheduleBuffer(buffer) { [weak self] in
                self?.playbackQueue.async {
                    self?.totalSamplesPlayed += sampleCount
                }
            }
        }
    }

    // MARK: - Cleanup

    private func cleanupEngine() {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
    }
}
