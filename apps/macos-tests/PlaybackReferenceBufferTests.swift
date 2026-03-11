import XCTest
import Foundation
@testable import RubberDuck

final class PlaybackReferenceBufferTests: XCTestCase {

    // MARK: - Helpers

    private func makeInt16Data(count: Int, fill: Int16 = 0) -> Data {
        var samples = [Int16](repeating: fill, count: count)
        return Data(bytes: &samples, count: count * MemoryLayout<Int16>.size)
    }

    private func makeSineData(count: Int, amplitude: Int16 = 16000) -> Data {
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            samples[i] = Int16(Double(amplitude) * sin(Double(i) * 0.1))
        }
        return Data(bytes: &samples, count: count * MemoryLayout<Int16>.size)
    }

    private func readIntoArray(buf: PlaybackReferenceBuffer, frameCount: Int, delay: Int) -> (success: Bool, samples: [Float]) {
        var out = [Float](repeating: -999, count: frameCount)
        let ok = out.withUnsafeMutableBufferPointer { ptr in
            buf.read(into: ptr.baseAddress!, frameCount: frameCount, delaySamples: delay)
        }
        return (ok, out)
    }

    // MARK: - Tests

    /// An empty buffer must return false (underrun) without touching the output array.
    func test_initialRead_underruns() {
        let buf = PlaybackReferenceBuffer(capacity: 1024)
        let (ok, out) = readIntoArray(buf: buf, frameCount: 64, delay: 100)

        XCTAssertFalse(ok, "Underrun expected on empty buffer")
        XCTAssertTrue(out.allSatisfy { $0 == -999 }, "Output must be untouched on underrun")
    }

    /// Written Int16 LE samples must round-trip as normalised Float32.
    func test_writeAndRead_roundtrips() {
        let buf = PlaybackReferenceBuffer(capacity: 4096)
        let sampleCount = 512

        // Write 512 samples: 0, 1, 2, …, 511
        var int16Samples = (0..<sampleCount).map { Int16($0 % 32767) }
        let data = Data(bytes: &int16Samples, count: sampleCount * 2)
        buf.write(int16Data: data, scheduledAt: 0)

        // Read the first 256 samples with a delay of 256.
        let (ok, out) = readIntoArray(buf: buf, frameCount: 256, delay: 256)

        XCTAssertTrue(ok, "Read should succeed after sufficient data is written")
        XCTAssertEqual(out[0], Float(int16Samples[0]) / 32768.0, accuracy: 1e-5)
        XCTAssertEqual(out[1], Float(int16Samples[1]) / 32768.0, accuracy: 1e-5)
        XCTAssertEqual(out[100], Float(int16Samples[100]) / 32768.0, accuracy: 1e-5)
    }

    /// reset() must cause all subsequent reads to underrun.
    func test_reset_causesUnderrun() {
        let buf = PlaybackReferenceBuffer(capacity: 1024)
        let data = makeInt16Data(count: 512, fill: 1000)
        buf.write(int16Data: data, scheduledAt: 0)

        // Sanity: first read succeeds.
        let (okBefore, _) = readIntoArray(buf: buf, frameCount: 64, delay: 64)
        XCTAssertTrue(okBefore, "Precondition: read should succeed before reset")

        buf.reset()

        let (okAfter, out) = readIntoArray(buf: buf, frameCount: 64, delay: 0)
        XCTAssertFalse(okAfter, "Read must underrun after reset")
        // Output should be untouched.
        XCTAssertTrue(out.allSatisfy { $0 == -999 })
    }

    /// Writing more than `capacity` samples must not corrupt the ring — the most
    /// recent data should be readable correctly after wrap-around.
    func test_wrapAround_doesNotCorrupt() {
        let capacity = 256
        let buf = PlaybackReferenceBuffer(capacity: capacity)

        // Write 300 samples — 44 past the wrap boundary.
        let count = 300
        let fillValue: Int16 = 1000
        let data = makeInt16Data(count: count, fill: fillValue)
        buf.write(int16Data: data, scheduledAt: 0)

        // The last 64 samples should all be `fillValue`.
        let (ok, out) = readIntoArray(buf: buf, frameCount: 64, delay: 64)
        XCTAssertTrue(ok)
        let expected = Float(fillValue) / 32768.0
        for sample in out {
            XCTAssertEqual(sample, expected, accuracy: 1e-4)
        }
    }

    /// Subtracting the reference from a pure-bleed capture should reduce RMS to near zero.
    func test_subtraction_reducesRMS() {
        let buf = PlaybackReferenceBuffer(capacity: 4096)
        let frameCount = 1024
        let delay = 512

        // Write more samples than we'll read so the read-window is valid.
        let totalWritten = frameCount + delay
        let sineData = makeSineData(count: totalWritten)
        buf.write(int16Data: sineData, scheduledAt: 0)

        // Read reference into a local array.
        var ref = [Float](repeating: 0, count: frameCount)
        let ok = ref.withUnsafeMutableBufferPointer { ptr in
            buf.read(into: ptr.baseAddress!, frameCount: frameCount, delaySamples: delay)
        }
        XCTAssertTrue(ok, "Reference read should succeed")

        // Simulate pure bleedthrough: capture = reference × 0.5
        var capture = ref.map { $0 * 0.5 }

        // Apply subtraction: capture -= reference × 0.5
        let gain: Float = 0.5
        for i in 0..<frameCount { capture[i] -= ref[i] * gain }

        // Residual RMS should be essentially zero.
        let residualRMS = sqrt(capture.reduce(Float(0)) { $0 + $1 * $1 } / Float(frameCount))
        XCTAssertLessThan(residualRMS, 0.001, "Subtraction should eliminate pure-bleed signal")
    }

    /// `latestScheduledAt()` should return 0 before any writes, and non-zero after.
    func test_latestScheduledAt_returnsTimestamp() {
        let buf = PlaybackReferenceBuffer(capacity: 1024)
        XCTAssertEqual(buf.latestScheduledAt(), 0, "No timestamp before any write")

        let ts: UInt64 = 123_456_789
        // Write enough samples to cross the stride boundary (stride = 512 samples)
        let data = makeInt16Data(count: 600, fill: 0)
        buf.write(int16Data: data, scheduledAt: ts)

        XCTAssertNotEqual(buf.latestScheduledAt(), 0, "Timestamp should be recorded after write crosses stride")
    }

    /// `availableSamples` should not exceed the buffer capacity.
    func test_availableSamples_cappedAtCapacity() {
        let capacity = 512
        let buf = PlaybackReferenceBuffer(capacity: capacity)

        // Write 1024 samples — double the capacity.
        let data = makeInt16Data(count: 1024, fill: 0)
        buf.write(int16Data: data, scheduledAt: 0)

        XCTAssertLessThanOrEqual(buf.availableSamples, capacity)
    }
}
