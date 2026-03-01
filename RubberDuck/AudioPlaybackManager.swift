import Foundation
import AVFoundation

struct AudioPlaybackStopSnapshot {
    let totalScheduledSamples: Int
    let totalPlayedSamples: Int
    let totalUnplayedSamples: Int
    let itemScheduledSamples: Int
    let itemPlayedSamples: Int
    let itemUnplayedSamples: Int
}

private struct AudioPlaybackItemKey: Hashable {
    let itemId: String
    let contentIndex: Int
}

private struct AudioPlaybackItemSamples {
    var scheduledSamples: Int = 0
    var playedSamples: Int = 0
}

class AudioPlaybackManager: ObservableObject {
    @Published var isPlaying = false

    private weak var audioManager: AudioManager?
    private let playbackQueue = DispatchQueue(label: "co.blode.rubber-duck.playback")
    private var fallbackAudioEngine: AVAudioEngine?
    private var fallbackPlayerNode: AVAudioPlayerNode?

    private let pcm16Format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                            sampleRate: AudioConstants.sampleRate,
                                            channels: AudioConstants.channels,
                                            interleaved: false)!

    private(set) var totalSamplesScheduled: Int = 0
    private(set) var totalSamplesPlayed: Int = 0
    private var firstEnqueueAt: Date?
    private var firstScheduleLatencyLogged = false
    private var droppedChunksBeforeReady = 0
    private var itemSamples: [AudioPlaybackItemKey: AudioPlaybackItemSamples] = [:]

    init(audioManager: AudioManager) {
        self.audioManager = audioManager
    }

    // MARK: - Playback Control

    func startPlayback() {
        playbackQueue.async { [weak self] in
            guard let self = self else { return }

            // The playerNode lives on AudioManager's shared engine (for AEC).
            // Just reset metrics and start the player — don't create a new engine.
            let playerNode: AVAudioPlayerNode?
            if let audioManager = self.audioManager,
               audioManager.isCaptureEngineRunning,
               let sharedPlayerNode = audioManager.playerNode {
                self.teardownFallbackPlaybackEngine()
                playerNode = sharedPlayerNode
            } else if self.audioManager?.isCaptureStartupInProgress == true {
                playerNode = nil
            } else {
                playerNode = self.ensureFallbackPlaybackNode()
            }

            guard let playerNode else {
                logError("AudioPlaybackManager: No player node available")
                self.resetPlaybackMetrics()
                DispatchQueue.main.async {
                    self.isPlaying = false
                }
                return
            }

            self.resetPlaybackMetrics()
            playerNode.play()
            DispatchQueue.main.async {
                // The player is armed, but no assistant audio is scheduled yet.
                // Report playback as active only once chunks are enqueued.
                self.isPlaying = false
            }
            logInfo("AudioPlaybackManager: Playback started")
        }
    }

    func stopPlayback() {
        playbackQueue.async { [weak self] in
            guard let self = self else { return }
            self.audioManager?.playerNode?.stop()
            self.fallbackPlayerNode?.stop()
            self.teardownFallbackPlaybackEngine()
            self.resetPlaybackMetrics()
            DispatchQueue.main.async {
                self.isPlaying = false
            }
            logInfo("AudioPlaybackManager: Playback stopped")
        }
    }

    func stopImmediately() -> Int {
        stopImmediatelySnapshot(itemId: nil, contentIndex: nil).totalUnplayedSamples
    }

    func stopImmediatelySnapshot(itemId: String?, contentIndex: Int?) -> AudioPlaybackStopSnapshot {
        playbackQueue.sync { [weak self] in
            guard let self else {
                return AudioPlaybackStopSnapshot(
                    totalScheduledSamples: 0,
                    totalPlayedSamples: 0,
                    totalUnplayedSamples: 0,
                    itemScheduledSamples: 0,
                    itemPlayedSamples: 0,
                    itemUnplayedSamples: 0
                )
            }

            let totalScheduled = self.totalSamplesScheduled
            let totalPlayed = min(self.totalSamplesPlayed, totalScheduled)
            let totalUnplayed = max(totalScheduled - totalPlayed, 0)

            let key = self.playbackKey(itemId: itemId, contentIndex: contentIndex)
            let perItem = key.flatMap { self.itemSamples[$0] }
            let itemScheduled = perItem?.scheduledSamples ?? 0
            let itemPlayed = min(perItem?.playedSamples ?? 0, itemScheduled)
            let itemUnplayed = max(itemScheduled - itemPlayed, 0)

            // Stop the player node but do NOT tear down the shared engine.
            self.audioManager?.playerNode?.stop()
            self.fallbackPlayerNode?.stop()
            self.teardownFallbackPlaybackEngine()
            self.resetPlaybackMetrics()
            DispatchQueue.main.async {
                self.isPlaying = false
            }
            logInfo("AudioPlaybackManager: Stopped immediately, \(totalUnplayed) unplayed samples")

            return AudioPlaybackStopSnapshot(
                totalScheduledSamples: totalScheduled,
                totalPlayedSamples: totalPlayed,
                totalUnplayedSamples: totalUnplayed,
                itemScheduledSamples: itemScheduled,
                itemPlayedSamples: itemPlayed,
                itemUnplayedSamples: itemUnplayed
            )
        }
    }

    func estimatedUnplayedSamples() -> Int {
        playbackQueue.sync {
            let scheduled = totalSamplesScheduled
            let played = min(totalSamplesPlayed, scheduled)
            return max(scheduled - played, 0)
        }
    }

    func estimatedUnplayedDurationSeconds() -> TimeInterval {
        TimeInterval(estimatedUnplayedSamples()) / AudioConstants.sampleRate
    }

    // MARK: - Audio Enqueueing

    func enqueueAudio(base64Chunk: String, itemId: String? = nil, contentIndex: Int? = nil) {
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
            guard let self else { return }
            let key = self.playbackKey(itemId: itemId, contentIndex: contentIndex)

            if self.firstEnqueueAt == nil {
                self.firstEnqueueAt = Date()
            }

            let playerNode: AVAudioPlayerNode?
            if let audioManager = self.audioManager,
               audioManager.isCaptureEngineRunning,
               let sharedPlayerNode = audioManager.playerNode {
                self.teardownFallbackPlaybackEngine()
                playerNode = sharedPlayerNode
            } else if self.audioManager?.isCaptureStartupInProgress == true {
                playerNode = nil
            } else {
                playerNode = self.ensureFallbackPlaybackNode()
            }

            guard let playerNode else {
                if self.audioManager?.isCaptureStartupInProgress == true {
                    logDebug("AudioPlaybackManager: Capture startup in progress, deferring fallback playback engine")
                    return
                }
                self.droppedChunksBeforeReady += 1
                logDebug("AudioPlaybackManager: No player node, dropping audio chunk (\(self.droppedChunksBeforeReady) dropped before ready)")
                return
            }

            if !playerNode.isPlaying {
                playerNode.play()
                DispatchQueue.main.async {
                    self.isPlaying = true
                }
                logDebug("AudioPlaybackManager: Player node became available; started playback lazily")
            }

            if !self.firstScheduleLatencyLogged, let firstEnqueueAt = self.firstEnqueueAt {
                let latencyMs = Int(Date().timeIntervalSince(firstEnqueueAt) * 1000)
                self.firstScheduleLatencyLogged = true
                logDebug("AudioPlaybackManager: First schedule latency \(latencyMs)ms, dropped before ready: \(self.droppedChunksBeforeReady)")
            }

            self.totalSamplesScheduled += sampleCount
            if let key {
                var stats = self.itemSamples[key, default: AudioPlaybackItemSamples()]
                stats.scheduledSamples += sampleCount
                self.itemSamples[key] = stats
            }
            DispatchQueue.main.async {
                self.isPlaying = true
            }

            playerNode.scheduleBuffer(buffer) { [weak self] in
                self?.playbackQueue.async {
                    guard let self else { return }
                    self.totalSamplesPlayed += sampleCount
                    if let key {
                        var stats = self.itemSamples[key, default: AudioPlaybackItemSamples()]
                        stats.playedSamples += sampleCount
                        self.itemSamples[key] = stats
                    }

                    if self.totalSamplesScheduled > 0 && self.totalSamplesPlayed >= self.totalSamplesScheduled {
                        self.totalSamplesPlayed = self.totalSamplesScheduled
                        DispatchQueue.main.async {
                            self.isPlaying = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Private

    private func resetPlaybackMetrics() {
        totalSamplesScheduled = 0
        totalSamplesPlayed = 0
        firstEnqueueAt = nil
        firstScheduleLatencyLogged = false
        droppedChunksBeforeReady = 0
        itemSamples.removeAll(keepingCapacity: true)
    }

    private func ensureFallbackPlaybackNode() -> AVAudioPlayerNode? {
        if let fallbackPlayerNode, fallbackAudioEngine != nil {
            return fallbackPlayerNode
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: pcm16Format)
        engine.prepare()

        do {
            try engine.start()
            fallbackAudioEngine = engine
            fallbackPlayerNode = player
            logInfo("AudioPlaybackManager: Started fallback playback engine (AEC disabled)")
            return player
        } catch {
            fallbackAudioEngine = nil
            fallbackPlayerNode = nil
            logError("AudioPlaybackManager: Failed to start fallback playback engine: \(error.localizedDescription)")
            return nil
        }
    }

    private func teardownFallbackPlaybackEngine() {
        fallbackPlayerNode?.stop()
        fallbackAudioEngine?.stop()
        fallbackPlayerNode = nil
        fallbackAudioEngine = nil
    }

    private func playbackKey(itemId: String?, contentIndex: Int?) -> AudioPlaybackItemKey? {
        guard let itemId, !itemId.isEmpty else {
            return nil
        }
        return AudioPlaybackItemKey(itemId: itemId, contentIndex: contentIndex ?? 0)
    }
}
