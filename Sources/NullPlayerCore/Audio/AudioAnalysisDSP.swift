import Foundation
import Accelerate

/// Pure-Swift DSP utilities for audio analysis.
/// All functions are deterministic with no side effects and no global state — suitable for unit testing.
/// No per-call heap allocations beyond the caller's responsibility.
public enum AudioAnalysisDSP {

    // MARK: - Level Measurement

    /// Calculate peak decibels full-scale (dB FS) from audio samples.
    /// - Parameter samples: Array of floating-point audio samples.
    /// - Returns: Peak level in dB FS, floored at -120 dB for silence.
    ///
    /// Formula: 20 * log10(maxAbs(samples)), clamped to [-120, 0] dB.
    public static func peakDBFS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -120.0 }

        var maxAbs: Float = 0.0
        vDSP_maxmgv(samples, 1, &maxAbs, vDSP_Length(samples.count))

        guard maxAbs > 0 else { return -120.0 }
        let dB = 20.0 * log10(maxAbs)
        return max(dB, -120.0)
    }

    /// Calculate RMS (root mean square) level in decibels full-scale (dB FS) from audio samples.
    /// - Parameter samples: Array of floating-point audio samples.
    /// - Returns: RMS level in dB FS, floored at -120 dB for silence.
    ///
    /// Formula: 20 * log10(sqrt(mean(samples²))), clamped to [-120, 0] dB.
    /// Useful for loudness estimation; responds more smoothly than peak to transients.
    public static func rmsDBFS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -120.0 }

        var sum: Float = 0.0
        vDSP_svesq(samples, 1, &sum, vDSP_Length(samples.count))

        let meanSquare = sum / Float(samples.count)
        guard meanSquare > 0 else { return -120.0 }
        let rms = sqrt(meanSquare)
        let dB = 20.0 * log10(rms)
        return max(dB, -120.0)
    }

    // MARK: - Octave Band Analysis

    /// Re-bin linear FFT magnitudes into logarithmic octave or sub-octave bands.
    ///
    /// - Parameters:
    ///   - magnitudes: Linear FFT magnitude spectrum (half-spectrum, typically fftSize/2 elements).
    ///   - sampleRate: Sample rate of the audio in Hz.
    ///   - fftSize: FFT size used to compute magnitudes (e.g., 2048).
    ///   - bandsPerOctave: Bands per octave; common values are 1 (octave), 3 (1/3 octave), 12 (1/12 octave).
    ///   - minFreq: Lowest center frequency to include (Hz), typically 20.
    ///   - maxFreq: Highest center frequency to include (Hz), typically 20000.
    ///
    /// - Returns: Array of tuples with center frequency (Hz) and level (normalized 0–1).
    ///
    /// Returns an empty array if inputs are invalid (empty magnitudes, invalid freq range, etc.).
    ///
    /// **Note on frequency resolution:** At 2048-point FFT, 44.1 kHz sample rate, the bin width is ~21.5 Hz.
    /// Sub-200 Hz bands will have sparse bin coverage and lower frequency resolution. For reliable sub-bass analysis,
    /// use larger FFT sizes (e.g., 4096 or 8192).
    public static func octaveBands(
        magnitudes: [Float],
        sampleRate: Double,
        fftSize: Int,
        bandsPerOctave: Int,
        minFreq: Double,
        maxFreq: Double
    ) -> [(centerHz: Double, level: Float)] {
        guard !magnitudes.isEmpty, bandsPerOctave > 0, fftSize > 0 else { return [] }
        guard minFreq > 0, maxFreq > minFreq, sampleRate > 0 else { return [] }

        let binWidth = sampleRate / Double(fftSize)
        guard binWidth > 0 else { return [] }

        var bands: [(centerHz: Double, level: Float)] = []

        let octaveRatio = pow(2.0, 1.0 / Double(bandsPerOctave))
        var freq = minFreq

        while freq <= maxFreq {
            let centerFreq = freq
            let lowFreq = centerFreq / sqrt(octaveRatio)
            let highFreq = centerFreq * sqrt(octaveRatio)

            let lowBin = max(0, Int(lowFreq / binWidth))
            let highBin = min(magnitudes.count - 1, Int(highFreq / binWidth))

            var bandLevel: Float = 0.0
            for bin in lowBin...highBin {
                if magnitudes[bin] > bandLevel {
                    bandLevel = magnitudes[bin]
                }
            }

            // Normalize to [0, 1] assuming typical peak magnitudes around 1.0
            let normalized = min(1.0, max(0.0, bandLevel))
            bands.append((centerHz: centerFreq, level: normalized))

            freq *= octaveRatio
        }

        return bands
    }

    // MARK: - Pitch Estimation

    /// Estimate the fundamental frequency (pitch) of an audio signal using autocorrelation.
    ///
    /// - Parameters:
    ///   - samples: Array of floating-point audio samples. For robust low-frequency detection, use at least
    ///     a 2048-sample window (typical 44.1 kHz ≈ 46 ms).
    ///   - sampleRate: Sample rate in Hz.
    ///   - minHz: Lowest frequency to consider (Hz), typically 50.
    ///   - maxHz: Highest frequency to consider (Hz), typically 2000 (speech/singing range).
    ///
    /// - Returns: Estimated fundamental frequency in Hz, or nil if confidence is low (silence, noise, polyphonic).
    ///
    /// Uses normalized autocorrelation; returns nil if the peak autocorrelation is weak (< 0.5 typically indicates noise or polyphony).
    /// The search is bounded to the lag range corresponding to [minHz, maxHz].
    public static func estimatePitchHz(
        samples: [Float],
        sampleRate: Double,
        minHz: Double,
        maxHz: Double
    ) -> Double? {
        guard !samples.isEmpty, minHz > 0, maxHz > minHz, sampleRate > 0 else { return nil }

        let minLag = max(1, Int(sampleRate / maxHz))
        let maxLag = min(samples.count / 2, Int(sampleRate / minHz))

        guard minLag <= maxLag else { return nil }

        // Compute mean and standard deviation for normalization
        var mean: Float = 0.0
        vDSP_meanv(samples, 1, &mean, vDSP_Length(samples.count))

        var sumSquares: Float = 0.0
        for sample in samples {
            let diff = sample - mean
            sumSquares += diff * diff
        }
        let stdDev = sqrt(sumSquares / Float(samples.count))

        guard stdDev > 1e-6 else { return nil }  // Near silence

        // Normalize samples
        var normalized = [Float](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            normalized[i] = (samples[i] - mean) / stdDev
        }

        // Compute autocorrelation at key lags
        var bestLag = minLag
        var bestAutocorr: Float = 0.0

        for lag in minLag...maxLag {
            var autocorr: Float = 0.0
            for i in 0..<(samples.count - lag) {
                autocorr += normalized[i] * normalized[i + lag]
            }
            autocorr /= Float(samples.count - lag)

            if autocorr > bestAutocorr {
                bestAutocorr = autocorr
                bestLag = lag
            }
        }

        // Require high confidence (empirical threshold; lower values may work for cleaner signals)
        guard bestAutocorr > 0.5 else { return nil }

        let pitchHz = sampleRate / Double(bestLag)
        return pitchHz
    }

    // MARK: - Cross-Correlation (Delay Estimation)

    /// Estimate the time delay (lag in samples) of the right channel relative to the left using cross-correlation.
    ///
    /// - Parameters:
    ///   - left: Left-channel audio samples.
    ///   - right: Right-channel audio samples (must be same length as left).
    ///   - maxLagSamples: Maximum lag to search (samples). Limits the resolvable delay range.
    ///     Only lags within ±maxLagSamples are considered.
    ///
    /// - Returns: Lag in samples (positive = right lags left; negative = left lags right), or 0 if no clear delay detected.
    ///
    /// Uses normalized cross-correlation; returns 0 if the peak is weak (similarity < 0.5).
    /// **Frequency aliasing:** Delays beyond ±maxLagSamples are unresolvable and mapped to ±maxLag.
    /// For reliable sub-millisecond delay estimation, use high sample rates (≥ 48 kHz).
    public static func estimateDelaySamples(left: [Float], right: [Float], maxLagSamples: Int) -> Int {
        guard left.count == right.count, !left.isEmpty, maxLagSamples > 0 else { return 0 }

        // Compute means
        var leftMean: Float = 0.0
        var rightMean: Float = 0.0
        vDSP_meanv(left, 1, &leftMean, vDSP_Length(left.count))
        vDSP_meanv(right, 1, &rightMean, vDSP_Length(right.count))

        // Compute standard deviations
        var leftSumSq: Float = 0.0
        var rightSumSq: Float = 0.0
        for i in 0..<left.count {
            let lDiff = left[i] - leftMean
            let rDiff = right[i] - rightMean
            leftSumSq += lDiff * lDiff
            rightSumSq += rDiff * rDiff
        }

        let leftStd = sqrt(leftSumSq / Float(left.count))
        let rightStd = sqrt(rightSumSq / Float(right.count))

        guard leftStd > 1e-6, rightStd > 1e-6 else { return 0 }

        // Compute normalized cross-correlation at positive and negative lags.
        // Seed with the zero-lag correlation so perfectly aligned channels report 0;
        // a real delay only wins if its correlation exceeds the aligned case.
        let searchLag = min(maxLagSamples, left.count / 2)

        var zeroCorr: Float = 0.0
        for i in 0..<left.count {
            zeroCorr += (left[i] - leftMean) * (right[i] - rightMean)
        }
        zeroCorr /= (Float(left.count) * leftStd * rightStd)

        var bestLag = 0
        var bestCorr: Float = zeroCorr

        // Test positive lags (right lags left)
        for lag in 1...searchLag {
            var xcorr: Float = 0.0
            let limit = left.count - lag
            for i in 0..<limit {
                xcorr += (left[i] - leftMean) * (right[i + lag] - rightMean)
            }
            xcorr /= (Float(limit) * leftStd * rightStd)

            if xcorr > bestCorr {
                bestCorr = xcorr
                bestLag = lag
            }
        }

        // Test negative lags (left lags right)
        for lag in 1...searchLag {
            var xcorr: Float = 0.0
            let limit = left.count - lag
            for i in 0..<limit {
                xcorr += (left[i + lag] - leftMean) * (right[i] - rightMean)
            }
            xcorr /= (Float(limit) * leftStd * rightStd)

            if xcorr > bestCorr {
                bestCorr = xcorr
                bestLag = -lag
            }
        }

        // Require strong correlation
        guard bestCorr > 0.5 else { return 0 }

        return bestLag
    }
}
