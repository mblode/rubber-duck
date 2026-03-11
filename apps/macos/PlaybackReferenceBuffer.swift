import Foundation

/// Lock-free single-producer / single-consumer ring buffer for playback reference samples.
///
/// **Writer:** `playbackQueue` (serial) — the only writer, calls `write(int16Data:scheduledAt:)`.
/// **Reader:** CoreAudio real-time audio thread (via `audioQueue`) — lock-free reads, no allocation.
///
/// The buffer stores a rolling history of recently played PCM samples as Float32 (normalized
/// from Int16). AudioManager reads from this buffer during microphone capture to subtract the
/// speaker output from the captured signal, implementing software acoustic echo cancellation.
final class PlaybackReferenceBuffer {

    // MARK: - Configuration

    /// Ring buffer capacity in samples. Must be a power of 2.
    /// 16384 samples @ 24 kHz ≈ 682 ms — covers even generous round-trip delays.
    static let defaultCapacity = 16384

    /// How many samples between each recorded timestamp.
    /// 512 samples @ 24 kHz ≈ 21 ms granularity for delay estimation.
    static let timestampStride = 512

    // MARK: - Storage (set once at init, never reallocated)

    private let capacity: Int
    private let mask: Int  // capacity - 1; used for fast power-of-2 modulo
    private let samples: UnsafeMutablePointer<Float>

    /// Timestamps ring: one `mach_absolute_time` entry per `timestampStride` samples.
    private let timestampCapacity: Int
    private let timestamps: UnsafeMutablePointer<UInt64>

    // MARK: - Write head (SPSC atomic)

    /// Absolute write head (monotonically increasing). Only the writer (playbackQueue)
    /// increments this. The reader loads it with `OSAtomicAdd64(0, &writeHead)` to
    /// get a sequentially consistent snapshot without a lock.
    private var writeHead: Int64 = 0

    // MARK: - Init / Deinit

    init(capacity: Int = defaultCapacity) {
        precondition(capacity > 0 && (capacity & (capacity - 1)) == 0,
                     "PlaybackReferenceBuffer capacity must be a power of 2")
        self.capacity = capacity
        self.mask = capacity - 1
        self.samples = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.samples.initialize(repeating: 0, count: capacity)

        self.timestampCapacity = capacity / Self.timestampStride + 2
        self.timestamps = UnsafeMutablePointer<UInt64>.allocate(capacity: self.timestampCapacity)
        self.timestamps.initialize(repeating: 0, count: self.timestampCapacity)
    }

    deinit {
        samples.deallocate()
        timestamps.deallocate()
    }

    // MARK: - Writer API (playbackQueue only)

    /// Write Int16 LE PCM samples from playback into the ring buffer as normalized Float32.
    ///
    /// Must be called exclusively from `playbackQueue` (the sole writer).
    ///
    /// - Parameters:
    ///   - data: Raw PCM bytes — `sampleCount * 2` bytes of Int16 LE samples.
    ///   - scheduledAt: `mach_absolute_time()` captured just before `playerNode.scheduleBuffer`.
    func write(int16Data data: Data, scheduledAt: UInt64) {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return }

        let currentHead = Int(writeHead)  // writer owns writeHead; direct read is safe

        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            let src = base.bindMemory(to: Int16.self, capacity: sampleCount)

            for i in 0..<sampleCount {
                let slot = (currentHead + i) & mask
                let raw = Int16(littleEndian: src[i])
                samples[slot] = Float(raw) / 32768.0
            }
        }

        // Record a timestamp each time the write head crosses a stride boundary.
        let oldStrideIndex = currentHead / Self.timestampStride
        let newStrideIndex = (currentHead + sampleCount) / Self.timestampStride
        if newStrideIndex > oldStrideIndex {
            let tSlot = newStrideIndex % timestampCapacity
            timestamps[tSlot] = scheduledAt
        }

        // Publish the updated write head. The memory barrier ensures all sample writes
        // above are visible to the reader before the incremented head is.
        OSAtomicAdd64Barrier(Int64(sampleCount), &writeHead)
    }

    /// Reset the buffer. Sets the write head to 0 and zeroes all samples.
    ///
    /// Must be called from `playbackQueue` (the writer's queue).
    /// After this call, any concurrent reader will see `writeHead == 0` and return underrun.
    func reset() {
        // Direct assignment is safe: we are the writer, and we serialise this via playbackQueue.
        writeHead = 0
        samples.initialize(repeating: 0, count: capacity)
        timestamps.initialize(repeating: 0, count: timestampCapacity)
    }

    // MARK: - Reader API (real-time audio thread — lock-free)

    /// Read `frameCount` Float32 samples ending `delaySamples` before the current write head.
    ///
    /// This is lock-free and allocation-free — safe to call from a CoreAudio real-time thread.
    ///
    /// - Parameters:
    ///   - output: Caller-provided buffer of at least `frameCount` Float elements.
    ///   - frameCount: Number of samples to read.
    ///   - delaySamples: How far behind the write head the read window starts.
    ///     Typically the estimated round-trip acoustic delay in samples.
    /// - Returns: `true` if the read succeeded; `false` on underrun (not enough history).
    ///   On underrun, `output` is **not** modified.
    @discardableResult
    func read(into output: UnsafeMutablePointer<Float>, frameCount: Int, delaySamples: Int) -> Bool {
        // Load write head atomically (acquire). Using Add(0) is the standard POSIX trick
        // for an atomic load on a value that OSAtomicAdd64Barrier wrote.
        let head = Int(OSAtomicAdd64(0, &writeHead))
        let needed = delaySamples + frameCount

        guard head >= needed else { return false }  // underrun

        let startIndex = head - needed
        for i in 0..<frameCount {
            output[i] = samples[(startIndex + i) & mask]
        }
        return true
    }

    // MARK: - Timestamp query (reader / writer)

    /// Returns the most recently recorded scheduling timestamp, or 0 if none yet.
    /// Used by the latency estimator to compute the time from scheduling to capture.
    func latestScheduledAt() -> UInt64 {
        let head = Int(OSAtomicAdd64(0, &writeHead))
        guard head > 0 else { return 0 }

        // Walk backwards through the stride slots to find the most recent timestamp.
        let strideIndex = head / Self.timestampStride
        for offset in 0..<min(4, timestampCapacity) {
            let idx = ((strideIndex - offset) % timestampCapacity + timestampCapacity) % timestampCapacity
            let ts = timestamps[idx]
            if ts != 0 { return ts }
        }
        return 0
    }

    // MARK: - Diagnostics

    /// Approximate number of samples currently stored (capped to capacity).
    var availableSamples: Int {
        min(Int(OSAtomicAdd64(0, &writeHead)), capacity)
    }
}
