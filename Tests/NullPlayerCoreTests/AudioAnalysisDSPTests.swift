import XCTest
@testable import NullPlayerCore

final class AudioAnalysisDSPTests: XCTestCase {

    // MARK: - peakDBFS Tests

    func testPeakDBFSWithEmptyArray() {
        let result = AudioAnalysisDSP.peakDBFS([])
        XCTAssertEqual(result, -120.0)
    }

    func testPeakDBFSWithAllZeros() {
        let result = AudioAnalysisDSP.peakDBFS([0, 0, 0, 0, 0])
        XCTAssertEqual(result, -120.0)
    }

    func testPeakDBFSWithFullScale() {
        // Full scale (1.0) should give peak ≈ 0 dB
        // 20 * log10(1.0) = 0.0
        let result = AudioAnalysisDSP.peakDBFS([1.0])
        XCTAssertEqual(result, 0.0, accuracy: 0.01)
    }

    func testPeakDBFSWithHalfAmplitude() {
        // 20 * log10(0.5) ≈ -6.02 dB
        let result = AudioAnalysisDSP.peakDBFS([0.5])
        XCTAssertEqual(result, -6.02, accuracy: 0.2)
    }

    func testPeakDBFSWithMixedAmplitudes() {
        // Max abs should be 0.8, so 20 * log10(0.8) ≈ -1.94 dB
        let result = AudioAnalysisDSP.peakDBFS([0.1, -0.3, 0.8, -0.2])
        XCTAssertEqual(result, 20.0 * log10(0.8), accuracy: 0.1)
    }

    func testPeakDBFSClampedToMinimum() {
        // Very small amplitude should be clamped to -120
        let result = AudioAnalysisDSP.peakDBFS([1e-8])
        XCTAssertEqual(result, -120.0)
    }

    func testPeakDBFSClampedToFullScale() {
        XCTAssertEqual(AudioAnalysisDSP.peakDBFS([2.0]), 0.0)
    }

    // MARK: - rmsDBFS Tests

    func testRmsDBFSWithEmptyArray() {
        let result = AudioAnalysisDSP.rmsDBFS([])
        XCTAssertEqual(result, -120.0)
    }

    func testRmsDBFSWithAllZeros() {
        let result = AudioAnalysisDSP.rmsDBFS([0, 0, 0, 0, 0])
        XCTAssertEqual(result, -120.0)
    }

    func testRmsDBFSWithFullScale() {
        // Full scale RMS of a constant 1.0 is 1.0
        // 20 * log10(1.0) = 0.0
        let result = AudioAnalysisDSP.rmsDBFS([1.0, 1.0, 1.0])
        XCTAssertEqual(result, 0.0, accuracy: 0.01)
    }

    func testRmsDBFSWithSineWave() {
        // For a sine wave with amplitude 1.0, RMS ≈ 1.0 / sqrt(2) ≈ 0.707
        // 20 * log10(0.707) ≈ -3.01 dB
        let sine = generateSineWave(frequency: 440, duration: 1.0, sampleRate: 44100, amplitude: 1.0)
        let result = AudioAnalysisDSP.rmsDBFS(sine)
        XCTAssertEqual(result, -3.01, accuracy: 0.2)
    }

    func testRmsLessThanPeakForSine() {
        // RMS should always be less than or equal to peak for audio
        let sine = generateSineWave(frequency: 1000, duration: 0.5, sampleRate: 44100, amplitude: 0.8)
        let peak = AudioAnalysisDSP.peakDBFS(sine)
        let rms = AudioAnalysisDSP.rmsDBFS(sine)
        XCTAssertLessThan(rms, peak)
    }

    func testRmsDBFSWithMixedAmplitudes() {
        let samples: [Float] = [0.5, -0.3, 0.4, -0.2]
        // mean(square) = (0.25 + 0.09 + 0.16 + 0.04) / 4 = 0.54 / 4 = 0.135
        // RMS = sqrt(0.135) ≈ 0.367
        // 20 * log10(0.367) ≈ -8.70
        let result = AudioAnalysisDSP.rmsDBFS(samples)
        XCTAssertEqual(result, 20.0 * log10(sqrt(0.135)), accuracy: 0.1)
    }

    func testRmsDBFSClampedToFullScale() {
        XCTAssertEqual(AudioAnalysisDSP.rmsDBFS([2.0, -2.0]), 0.0)
    }

    // MARK: - octaveBands Tests

    func testOctaveBandsWithEmptyMagnitudes() {
        let result = AudioAnalysisDSP.octaveBands(
            magnitudes: [],
            sampleRate: 44100,
            fftSize: 2048,
            bandsPerOctave: 3,
            minFreq: 20,
            maxFreq: 20000
        )
        XCTAssertEqual(result.count, 0)
    }

    func testOctaveBandsWithInvalidBandsPerOctave() {
        let magnitudes = [Float](repeating: 0.5, count: 1024)
        let result = AudioAnalysisDSP.octaveBands(
            magnitudes: magnitudes,
            sampleRate: 44100,
            fftSize: 2048,
            bandsPerOctave: 0,
            minFreq: 20,
            maxFreq: 20000
        )
        XCTAssertEqual(result.count, 0)
    }

    func testOctaveBandsWithInvalidFreqRange() {
        let magnitudes = [Float](repeating: 0.5, count: 1024)
        // maxFreq <= minFreq should return empty
        let result = AudioAnalysisDSP.octaveBands(
            magnitudes: magnitudes,
            sampleRate: 44100,
            fftSize: 2048,
            bandsPerOctave: 3,
            minFreq: 20000,
            maxFreq: 20
        )
        XCTAssertEqual(result.count, 0)
    }

    func testOctaveBandsWithZeroMinFreq() {
        let magnitudes = [Float](repeating: 0.5, count: 1024)
        let result = AudioAnalysisDSP.octaveBands(
            magnitudes: magnitudes,
            sampleRate: 44100,
            fftSize: 2048,
            bandsPerOctave: 3,
            minFreq: 0,
            maxFreq: 20000
        )
        XCTAssertEqual(result.count, 0)
    }

    func testOctaveBandsWithZeroSampleRate() {
        let magnitudes = [Float](repeating: 0.5, count: 1024)
        let result = AudioAnalysisDSP.octaveBands(
            magnitudes: magnitudes,
            sampleRate: 0,
            fftSize: 2048,
            bandsPerOctave: 3,
            minFreq: 20,
            maxFreq: 20000
        )
        XCTAssertEqual(result.count, 0)
    }

    func testOctaveBandsRejectsNonFiniteParameters() {
        let magnitudes = [Float](repeating: 0.5, count: 16)
        XCTAssertTrue(AudioAnalysisDSP.octaveBands(
            magnitudes: magnitudes,
            sampleRate: .infinity,
            fftSize: 32,
            bandsPerOctave: 3,
            minFreq: 20,
            maxFreq: 20000
        ).isEmpty)
    }

    func testOctaveBandsSkipsBandsAboveAvailableSpectrum() {
        let result = AudioAnalysisDSP.octaveBands(
            magnitudes: [0.5],
            sampleRate: 44100,
            fftSize: 2048,
            bandsPerOctave: 3,
            minFreq: 1000,
            maxFreq: 2000
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testOctaveBandsWithSinglePeakAt1000Hz() {
        // Create a synthetic magnitude spectrum with a peak at ~1000 Hz
        let fftSize = 2048
        let sampleRate = 44100.0
        let binWidth = sampleRate / Double(fftSize)  // ~21.5 Hz per bin
        let targetFreq = 1000.0
        let targetBin = Int(targetFreq / binWidth)

        var magnitudes = [Float](repeating: 0.1, count: fftSize / 2)
        magnitudes[targetBin] = 1.0  // Peak at 1000 Hz

        let result = AudioAnalysisDSP.octaveBands(
            magnitudes: magnitudes,
            sampleRate: sampleRate,
            fftSize: fftSize,
            bandsPerOctave: 3,
            minFreq: 100,
            maxFreq: 10000
        )

        XCTAssertGreaterThan(result.count, 0, "Should return bands for valid range")

        // Find the band with highest level
        let maxBand = result.max { $0.level < $1.level }
        XCTAssertNotNil(maxBand)

        if let maxBand = maxBand {
            // The peak band's center should be near 1000 Hz
            XCTAssertLessThan(abs(maxBand.centerHz - 1000.0), 200.0, "Peak band should be close to 1000 Hz")
        }

        // Frequencies should be monotonically increasing
        for i in 1..<result.count {
            XCTAssertGreaterThan(result[i].centerHz, result[i - 1].centerHz)
        }
    }

    func testOctaveBandsMonotonicFrequencies() {
        let magnitudes = [Float](repeating: 0.5, count: 1024)
        let result = AudioAnalysisDSP.octaveBands(
            magnitudes: magnitudes,
            sampleRate: 44100,
            fftSize: 2048,
            bandsPerOctave: 1,
            minFreq: 20,
            maxFreq: 20000
        )

        XCTAssertGreaterThan(result.count, 0)
        for i in 1..<result.count {
            XCTAssertGreaterThan(result[i].centerHz, result[i - 1].centerHz)
        }
    }

    func testOctaveBandsHigherBandsPerOctaveYieldsMoreBands() {
        let magnitudes = [Float](repeating: 0.5, count: 1024)

        let bands1 = AudioAnalysisDSP.octaveBands(
            magnitudes: magnitudes,
            sampleRate: 44100,
            fftSize: 2048,
            bandsPerOctave: 1,
            minFreq: 100,
            maxFreq: 1600
        )

        let bands3 = AudioAnalysisDSP.octaveBands(
            magnitudes: magnitudes,
            sampleRate: 44100,
            fftSize: 2048,
            bandsPerOctave: 3,
            minFreq: 100,
            maxFreq: 1600
        )

        XCTAssertGreaterThan(bands3.count, bands1.count)
    }

    // MARK: - estimatePitchHz Tests

    func testEstimatePitchHzWithEmptySamples() {
        let result = AudioAnalysisDSP.estimatePitchHz(
            samples: [],
            sampleRate: 44100,
            minHz: 50,
            maxHz: 2000
        )
        XCTAssertNil(result)
    }

    func testEstimatePitchHzWithSilence() {
        let silence = [Float](repeating: 0, count: 2048)
        let result = AudioAnalysisDSP.estimatePitchHz(
            samples: silence,
            sampleRate: 44100,
            minHz: 50,
            maxHz: 2000
        )
        XCTAssertNil(result)
    }

    func testEstimatePitchHzWithConstantDC() {
        // Constant non-zero DC should not have detectable pitch
        let dc = [Float](repeating: 0.5, count: 2048)
        let result = AudioAnalysisDSP.estimatePitchHz(
            samples: dc,
            sampleRate: 44100,
            minHz: 50,
            maxHz: 2000
        )
        XCTAssertNil(result)
    }

    func testEstimatePitchHzWith440HzSine() {
        // 440 Hz is A4 (concert pitch), 2048 samples at 44100 Hz ≈ 46 ms
        let samples = generateSineWave(frequency: 440, duration: 0.046, sampleRate: 44100, amplitude: 1.0)
        let result = AudioAnalysisDSP.estimatePitchHz(
            samples: Array(samples.prefix(2048)),
            sampleRate: 44100,
            minHz: 100,
            maxHz: 2000
        )

        XCTAssertNotNil(result)
        if let pitch = result {
            // Within ~3% of true frequency
            let tolerance = 440 * 0.03
            XCTAssertEqual(pitch, 440, accuracy: tolerance)
        }
    }

    func testEstimatePitchHzWith220HzSine() {
        // 220 Hz is A3
        let samples = generateSineWave(frequency: 220, duration: 0.046, sampleRate: 44100, amplitude: 1.0)
        let result = AudioAnalysisDSP.estimatePitchHz(
            samples: Array(samples.prefix(2048)),
            sampleRate: 44100,
            minHz: 100,
            maxHz: 2000
        )

        XCTAssertNotNil(result)
        if let pitch = result {
            let tolerance = 220 * 0.03
            XCTAssertEqual(pitch, 220, accuracy: tolerance)
        }
    }

    func testEstimatePitchHzWithRandomNoise() {
        // White noise should not yield a stable pitch
        let noise = generateDeterministicNoise(count: 2048, seed: 42)
        let result = AudioAnalysisDSP.estimatePitchHz(
            samples: noise,
            sampleRate: 44100,
            minHz: 50,
            maxHz: 2000
        )
        XCTAssertNil(result, "Deterministic white noise should not produce a stable pitch")
    }

    func testEstimatePitchHzInvalidMinMaxHz() {
        let samples = generateSineWave(frequency: 440, duration: 0.046, sampleRate: 44100, amplitude: 1.0)

        // maxHz <= minHz
        let result = AudioAnalysisDSP.estimatePitchHz(
            samples: Array(samples.prefix(2048)),
            sampleRate: 44100,
            minHz: 2000,
            maxHz: 100
        )
        XCTAssertNil(result)
    }

    func testEstimatePitchHzInvalidZeroMinHz() {
        let samples = generateSineWave(frequency: 440, duration: 0.046, sampleRate: 44100, amplitude: 1.0)
        let result = AudioAnalysisDSP.estimatePitchHz(
            samples: Array(samples.prefix(2048)),
            sampleRate: 44100,
            minHz: 0,
            maxHz: 2000
        )
        XCTAssertNil(result)
    }

    func testEstimatePitchHzInvalidZeroSampleRate() {
        let samples = generateSineWave(frequency: 440, duration: 0.046, sampleRate: 44100, amplitude: 1.0)
        let result = AudioAnalysisDSP.estimatePitchHz(
            samples: Array(samples.prefix(2048)),
            sampleRate: 0,
            minHz: 50,
            maxHz: 2000
        )
        XCTAssertNil(result)
    }

    func testEstimatePitchHzRejectsNonFiniteParameters() {
        let samples = [Float](repeating: 0.5, count: 2048)
        XCTAssertNil(AudioAnalysisDSP.estimatePitchHz(
            samples: samples,
            sampleRate: .infinity,
            minHz: 50,
            maxHz: 2000
        ))
    }

    func testEstimatePitchHzLowFreqIn512SampleWindow() {
        // DOCUMENTED LIMIT: sub-100 Hz in a 512-sample window is unreliable.
        // For 50 Hz at 44100 Hz sample rate, period = 44100 / 50 = 882 samples.
        // A 512-sample window captures ~0.58 periods, which is insufficient for autocorrelation
        // to reliably detect the fundamental. We assert that it either returns nil or a result
        // that is not within 3% of the true 50 Hz.
        let samples = generateSineWave(frequency: 50, duration: 512.0 / 44100.0, sampleRate: 44100, amplitude: 1.0)
        let result = AudioAnalysisDSP.estimatePitchHz(
            samples: samples,
            sampleRate: 44100,
            minHz: 40,
            maxHz: 200
        )

        if let pitch = result {
            // The pitch estimate may be octave-shifted or inaccurate for such a short window at low frequency.
            // We assert that it's either far off OR the test documents the limitation.
            let tolerance = 50 * 0.03
            let isWithinTolerance = abs(pitch - 50) <= tolerance
            XCTAssertFalse(isWithinTolerance, "Low-freq pitch in 512-sample window should be unreliable")
        }
    }

    // MARK: - estimateDelaySamples Tests

    func testEstimateDelaySamplesWithMismatchedLengths() {
        let left = [Float](repeating: 0.5, count: 100)
        let right = [Float](repeating: 0.5, count: 50)
        let result = AudioAnalysisDSP.estimateDelaySamples(left: left, right: right, maxLagSamples: 20)
        XCTAssertEqual(result, 0)
    }

    func testEstimateDelaySamplesWithEmptyArrays() {
        let result = AudioAnalysisDSP.estimateDelaySamples(left: [], right: [], maxLagSamples: 20)
        XCTAssertEqual(result, 0)
    }

    func testEstimateDelaySamplesWithSingleSample() {
        let result = AudioAnalysisDSP.estimateDelaySamples(left: [1], right: [1], maxLagSamples: 1)
        XCTAssertEqual(result, 0)
    }

    func testEstimateDelaySamplesWithZeroMaxLag() {
        let left = generateSineWave(frequency: 440, duration: 0.01, sampleRate: 44100, amplitude: 1.0)
        let right = left
        let result = AudioAnalysisDSP.estimateDelaySamples(left: left, right: right, maxLagSamples: 0)
        XCTAssertEqual(result, 0)
    }

    func testEstimateDelaySamplesWithNegativeMaxLag() {
        let left = generateSineWave(frequency: 440, duration: 0.01, sampleRate: 44100, amplitude: 1.0)
        let right = left
        let result = AudioAnalysisDSP.estimateDelaySamples(left: left, right: right, maxLagSamples: -10)
        XCTAssertEqual(result, 0)
    }

    func testEstimateDelaySamplesWithZeroDelay() {
        // Right is identical to left
        let left = generateSineWave(frequency: 440, duration: 0.01, sampleRate: 44100, amplitude: 1.0)
        let right = left
        let result = AudioAnalysisDSP.estimateDelaySamples(left: left, right: right, maxLagSamples: 64)
        XCTAssertEqual(result, 0)
    }

    func testEstimateDelaySamplesWithPositiveDelay() {
        // Right lags left by 10 samples
        let delay = 10
        let left = generateSineWave(frequency: 440, duration: 0.01, sampleRate: 44100, amplitude: 1.0)

        var right = [Float](repeating: 0, count: left.count)
        for i in 0..<left.count {
            if i >= delay {
                right[i] = left[i - delay]
            }
        }

        let result = AudioAnalysisDSP.estimateDelaySamples(left: left, right: right, maxLagSamples: 64)
        // Positive = right lags left
        XCTAssertEqual(result, delay, accuracy: 2)
    }

    func testEstimateDelaySamplesWithNegativeDelay() {
        // Left lags right by 15 samples (right leads)
        let delay = 15
        let right = generateSineWave(frequency: 440, duration: 0.01, sampleRate: 44100, amplitude: 1.0)

        var left = [Float](repeating: 0, count: right.count)
        for i in 0..<right.count {
            if i >= delay {
                left[i] = right[i - delay]
            }
        }

        let result = AudioAnalysisDSP.estimateDelaySamples(left: left, right: right, maxLagSamples: 64)
        // Negative = left lags right
        XCTAssertEqual(result, -delay, accuracy: 2)
    }

    func testEstimateDelaySamplesFrequencyAliasing() {
        // When true delay exceeds maxLagSamples, the estimate should NOT equal the true delay.
        // Instead, it should wrap/alias to ±maxLag.
        let delay = 40
        let maxLag = 8
        let left = generateSineWave(frequency: 440, duration: 0.01, sampleRate: 44100, amplitude: 1.0)

        var right = [Float](repeating: 0, count: left.count)
        for i in 0..<left.count {
            if i >= delay {
                right[i] = left[i - delay]
            }
        }

        let result = AudioAnalysisDSP.estimateDelaySamples(left: left, right: right, maxLagSamples: maxLag)
        // Result should not equal the true 40-sample delay
        XCTAssertNotEqual(result, delay)
        // Result should be clamped to ±maxLag
        XCTAssertLessThanOrEqual(abs(result), maxLag)
    }

    func testEstimateDelaySamplesWithWeakCorrelation() {
        // Two unrelated signals should return 0 (weak correlation)
        let left = generateDeterministicNoise(count: 512, seed: 42)
        let right = generateDeterministicNoise(count: 512, seed: 99)

        let result = AudioAnalysisDSP.estimateDelaySamples(left: left, right: right, maxLagSamples: 64)
        XCTAssertEqual(result, 0, "Unrelated signals should return 0 correlation")
    }

    // MARK: - Helper Functions

    /// Generate a sine wave at a specified frequency.
    /// - Parameters:
    ///   - frequency: Frequency in Hz
    ///   - duration: Duration in seconds
    ///   - sampleRate: Sample rate in Hz
    ///   - amplitude: Amplitude (default 1.0)
    /// - Returns: Array of audio samples
    private func generateSineWave(frequency: Double, duration: Double, sampleRate: Double, amplitude: Float) -> [Float] {
        let sampleCount = Int(duration * sampleRate)
        var samples = [Float](repeating: 0, count: sampleCount)
        let tau = 2.0 * .pi
        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            samples[i] = amplitude * Float(sin(tau * frequency * t))
        }
        return samples
    }

    /// Generate deterministic pseudo-random noise using a simple LCG.
    /// - Parameters:
    ///   - count: Number of samples
    ///   - seed: LCG seed for determinism
    /// - Returns: Array of pseudo-random samples in [-1, 1]
    private func generateDeterministicNoise(count: Int, seed: UInt32) -> [Float] {
        var samples = [Float](repeating: 0, count: count)
        var state = seed

        for i in 0..<count {
            state = state &* 1103515245 &+ 12345  // LCG constants
            let normalized = Float(state) / Float(UInt32.max)
            samples[i] = (normalized * 2.0) - 1.0  // Scale to [-1, 1]
        }

        return samples
    }
}
