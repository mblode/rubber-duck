import XCTest
import AVFoundation
import Accelerate
@testable import RubberDuck

/// Unit tests for AudioManager's software AEC subtraction logic.
///
/// These tests call `applyEchoSubtraction(to:frameCount:reference:delaySamples:gain:scratch:)`
/// directly, bypassing the audio engine, to verify the DSP math in isolation.
final class AudioManagerAECTests: XCTestCase {

    // MARK: - Helpers

    private func makeAudioManager() -> AudioManager {
        AudioManager()
    }

    private func makeReferenceBuffer(capacity: Int = 4096) -> PlaybackReferenceBuffer {
        PlaybackReferenceBuffer(capacity: capacity)
    }

    /// Write a sine wave (Int16) into a PlaybackReferenceBuffer.
    private func writeSine(into buf: PlaybackReferenceBuffer,
                           count: Int,
                           amplitude: Int16 = 16000) {
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            samples[i] = Int16(Double(amplitude) * sin(Double(i) * 0.1))
        }
        let data = Data(bytes: &samples, count: count * 2)
        buf.write(int16Data: data, scheduledAt: 0)
    }

    private func rms(_ samples: UnsafePointer<Float>, count: Int) -> Float {
        var result: Float = 0
        vDSP_rmsqv(samples, 1, &result, vDSP_Length(count))
        return result
    }

    // MARK: - Tests

    /// Subtracting an exact-gain reference from a pure-bleed capture signal should
    /// reduce residual RMS to near zero (≪ noise gate threshold of 0.005).
    func test_applyEchoSubtraction_withKnownSignal_reducesBleed() {
        let frameCount = 512
        let delaySamples = 1440  // 60 ms @ 24 kHz (default delay estimate)
        let gain: Float = 0.4

        let ref = makeReferenceBuffer()
        writeSine(into: ref, count: frameCount + delaySamples + 64)

        // Build a capture buffer that is pure reference × gain (perfect echo scenario).
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                  sampleRate: 24000, channels: 1, interleaved: false)!
        let capBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        capBuf.frameLength = AVAudioFrameCount(frameCount)
        let floatData = capBuf.floatChannelData![0]

        // Populate capture as reference × gain.
        var refSlice = [Float](repeating: 0, count: frameCount)
        let ok = refSlice.withUnsafeMutableBufferPointer { ptr in
            ref.read(into: ptr.baseAddress!, frameCount: frameCount, delaySamples: delaySamples)
        }
        XCTAssertTrue(ok, "Reference read should succeed")
        for i in 0..<frameCount { floatData[i] = refSlice[i] * gain }

        let rmsBefore = rms(floatData, count: frameCount)
        XCTAssertGreaterThan(rmsBefore, 0.01, "Precondition: non-trivial input signal")

        // Apply AEC subtraction.
        let audio = makeAudioManager()
        var scratch = [Float](repeating: 0, count: frameCount)
        let applied = audio.applyEchoSubtraction(
            to: floatData,
            frameCount: frameCount,
            reference: ref,
            delaySamples: delaySamples,
            gain: gain,
            scratch: &scratch
        )

        XCTAssertTrue(applied, "Subtraction should succeed when reference data is available")

        let rmsAfter = rms(floatData, count: frameCount)
        XCTAssertLessThan(rmsAfter, rmsBefore * 0.05,
                          "Residual RMS should be < 5% of input (echo well cancelled)")
        XCTAssertLessThan(rmsAfter, 0.001,
                          "Residual RMS should be below noise gate threshold")
    }

    /// Subtraction must be skipped gracefully when the reference buffer has no data
    /// (underrun). The capture signal must be unchanged.
    func test_applyEchoSubtraction_withEmptyReference_returnsfalse() {
        let frameCount = 256
        let ref = makeReferenceBuffer()  // empty

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                  sampleRate: 24000, channels: 1, interleaved: false)!
        let capBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        capBuf.frameLength = AVAudioFrameCount(frameCount)
        let floatData = capBuf.floatChannelData![0]
        for i in 0..<frameCount { floatData[i] = 0.5 }  // fill with known value

        let audio = makeAudioManager()
        var scratch = [Float](repeating: 0, count: frameCount)
        let applied = audio.applyEchoSubtraction(
            to: floatData,
            frameCount: frameCount,
            reference: ref,
            delaySamples: 1440,
            gain: 0.4,
            scratch: &scratch
        )

        XCTAssertFalse(applied, "Must return false on reference underrun")
        // Capture must be unchanged.
        for i in 0..<frameCount {
            XCTAssertEqual(floatData[i], 0.5, accuracy: 1e-6)
        }
    }

    /// With a zero-amplitude reference (silence), subtraction should not alter the
    /// capture signal (no NaN, no change).
    func test_applyEchoSubtraction_withSilentReference_leavesCaptureSilent() {
        let frameCount = 256
        let ref = makeReferenceBuffer()

        // Write silence.
        var zeros = [Int16](repeating: 0, count: frameCount + 512)
        let data = Data(bytes: &zeros, count: zeros.count * 2)
        ref.write(int16Data: data, scheduledAt: 0)

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                  sampleRate: 24000, channels: 1, interleaved: false)!
        let capBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        capBuf.frameLength = AVAudioFrameCount(frameCount)
        let floatData = capBuf.floatChannelData![0]
        for i in 0..<frameCount { floatData[i] = 0.1 }

        let audio = makeAudioManager()
        var scratch = [Float](repeating: 0, count: frameCount)
        let applied = audio.applyEchoSubtraction(
            to: floatData,
            frameCount: frameCount,
            reference: ref,
            delaySamples: 256,
            gain: 1.0,
            scratch: &scratch
        )

        XCTAssertTrue(applied)
        for i in 0..<frameCount {
            XCTAssertFalse(floatData[i].isNaN)
            XCTAssertEqual(floatData[i], 0.1, accuracy: 1e-5,
                           "Silent reference should not change the capture signal")
        }
    }

    /// The proportional echo gate: `referenceRMS * 1.5` must exceed the residual RMS after
    /// partial-gain subtraction, confirming that the gate formula would correctly silence
    /// echo residual without blocking user speech significantly louder than the echo.
    func test_proportionalGateThreshold_echoResidualIsBelowProportionalThreshold() {
        let frameCount = 512
        let trueGain: Float = 0.5
        let appliedGain: Float = 0.3  // deliberately under-subtract

        let ref = makeReferenceBuffer()
        writeSine(into: ref, count: frameCount + 1440 + 64)

        var refSlice = [Float](repeating: 0, count: frameCount)
        _ = refSlice.withUnsafeMutableBufferPointer { ptr in
            ref.read(into: ptr.baseAddress!, frameCount: frameCount, delaySamples: 1440)
        }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                  sampleRate: 24000, channels: 1, interleaved: false)!
        let capBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        capBuf.frameLength = AVAudioFrameCount(frameCount)
        let floatData = capBuf.floatChannelData![0]
        for i in 0..<frameCount { floatData[i] = refSlice[i] * trueGain }

        let audio = makeAudioManager()
        var scratch = [Float](repeating: 0, count: frameCount)
        _ = audio.applyEchoSubtraction(
            to: floatData,
            frameCount: frameCount,
            reference: ref,
            delaySamples: 1440,
            gain: appliedGain,
            scratch: &scratch
        )

        // scratch now holds the reference samples used for subtraction.
        var refRMS: Float = 0
        scratch.withUnsafeBufferPointer { ptr in
            vDSP_rmsqv(ptr.baseAddress!, 1, &refRMS, vDSP_Length(frameCount))
        }
        let proportionalThreshold = refRMS * 1.5

        let residualRMS = rms(floatData, count: frameCount)

        XCTAssertGreaterThan(proportionalThreshold, 0.005,
                             "Proportional threshold must exceed base noise gate during active playback")
        XCTAssertLessThan(residualRMS, proportionalThreshold,
                          "Echo residual after partial subtraction must fall below the proportional gate threshold")
    }

    /// Partial cancellation: with gain set to half the true bleedthrough, residual
    /// should be ~half the original, not zero.
    func test_applyEchoSubtraction_partialGain_leavesResiual() {
        let frameCount = 512
        let trueGain: Float = 0.4
        let appliedGain: Float = 0.2  // under-subtract on purpose

        let ref = makeReferenceBuffer()
        writeSine(into: ref, count: frameCount + 1440 + 64)

        var refSlice = [Float](repeating: 0, count: frameCount)
        _ = refSlice.withUnsafeMutableBufferPointer { ptr in
            ref.read(into: ptr.baseAddress!, frameCount: frameCount, delaySamples: 1440)
        }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                  sampleRate: 24000, channels: 1, interleaved: false)!
        let capBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        capBuf.frameLength = AVAudioFrameCount(frameCount)
        let floatData = capBuf.floatChannelData![0]
        for i in 0..<frameCount { floatData[i] = refSlice[i] * trueGain }

        let rmsBefore = rms(floatData, count: frameCount)

        let audio = makeAudioManager()
        var scratch = [Float](repeating: 0, count: frameCount)
        _ = audio.applyEchoSubtraction(
            to: floatData,
            frameCount: frameCount,
            reference: ref,
            delaySamples: 1440,
            gain: appliedGain,
            scratch: &scratch
        )

        let rmsAfter = rms(floatData, count: frameCount)
        // Applied gain = 0.2, true gain = 0.4, so residual = capture × (1 - appliedGain/trueGain) = 0.5 × original.
        XCTAssertGreaterThan(rmsAfter, 0.001, "Partial subtraction should leave residual")
        XCTAssertLessThan(rmsAfter, rmsBefore * 0.7, "Residual should be meaningfully reduced")
    }
}
