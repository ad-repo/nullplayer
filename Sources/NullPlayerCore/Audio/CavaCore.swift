import Foundation
import Accelerate

/// Pure-Swift DSP implementation of the cava spectrum analyzer algorithm.
/// Cava (https://github.com/karlstav/cava) is MIT-licensed.
/// This is a clean-room reimplementation based on the documented algorithm,
/// not a direct port of cava's C code.
///
/// Two parallel FFT analyses (bass and treble) are mixed into logarithmic bars
/// with monstercat neighbor smoothing, integral/exponential smoothing (noise reduction),
/// and gravity/falloff post-processing.
public class CavaCore {

    // MARK: - Configuration

    /// Number of output bars (typically 32 or 64)
    public let numberOfBars: Int

    /// Sample rate in Hz (e.g., 44100)
    public let rate: Int

    /// Number of channels (1 = mono, 2 = stereo)
    public let channels: Int

    /// Enable automatic sensitivity adjustment
    public let autosens: Bool

    /// Noise reduction factor (0.0 .. 1.0, typically ~0.77)
    /// Higher values = more smoothing = less responsive to noise
    public let noiseReduction: Double

    /// Low-frequency cutoff in Hz (typically ~50)
    public let lowCutOff: Int

    /// High-frequency cutoff in Hz (typically ~10000)
    public let highCutOff: Int

    // MARK: - FFT Buffers and Setup

    /// Larger FFT for bass (power of 2, typically 4096 for better low-freq resolution)
    private let bassFFTSize = 4096
    /// Smaller FFT for treble (power of 2, typically 2048)
    private let trebleFFTSize = 2048

    private var bassFFTSetup: vDSP_DFT_Setup?
    private var trebleFFTSetup: vDSP_DFT_Setup?

    /// Bass FFT work buffers (interleaved real/imag)
    private var bassFFTSamples = [Float]()
    private var bassFFTWindow = [Float]()
    private var bassFFTRealIn = [Float]()
    private var bassFFTImagIn = [Float]()
    private var bassFFTRealOut = [Float]()
    private var bassFFTImagOut = [Float]()
    private var bassFFTMagnitudes = [Float]()

    /// Treble FFT work buffers
    private var trebleFFTSamples = [Float]()
    private var trebleFFTWindow = [Float]()
    private var trebleFFTRealIn = [Float]()
    private var trebleFFTImagIn = [Float]()
    private var trebleFFTRealOut = [Float]()
    private var trebleFFTImagOut = [Float]()
    private var trebleFFTMagnitudes = [Float]()

    // MARK: - Smoothing & Decay Memory

    /// Per-channel, per-bar smoothing memory (noise reduction integral)
    private var smoothedValues: [[Float]] = []

    /// Per-channel, per-bar peak memory (for gravity/falloff)
    private var peakValues: [[Float]] = []

    /// Per-channel, per-bar raw magnitudes from the last `analyze()`. `render()` post-processes
    /// these, so the FFT can run at the audio-buffer rate while post-processing advances at the
    /// (higher) display rate on the cached values.
    private var rawBarMagnitudes: [[Float]] = []

    /// Exponent for per-band bin-count normalization (`sum / count^bandExponent`), i.e. the
    /// bass↔treble tilt. 0 = `sum` (brightest), 1 = `mean` (bassiest), 0.5 = √N. Lower ⇒ less bass.
    private let bandExponent: Float

    /// Persistent autosens gain applied to magnitudes before gravity. Starts low and grows into
    /// the signal so the display ramps up at launch instead of starting pinned at full scale.
    private var sens: Float = 1e-6

    /// True during the initial gain ramp (fast convergence), cleared once the display settles.
    private var sensInit: Bool = true

    // MARK: - Cutoff Frequency Mapping

    /// Maps each bar to bass/treble FFT bin ranges
    private var barToBassRange: [(low: Int, high: Int)] = []
    private var barToTrebleRange: [(low: Int, high: Int)] = []

    /// Which FFT source each bar should primarily use (0 = bass, 1 = treble)
    private var barSource: [Int] = []

    // MARK: - Initialization

    /// Initialize CavaCore with configuration matching cava_init() parameters.
    ///
    /// - Parameters:
    ///   - numberOfBars: Number of output spectrum bars (e.g., 32, 64)
    ///   - rate: Sample rate in Hz (e.g., 44100, 48000)
    ///   - channels: Number of audio channels (1 = mono, 2 = stereo)
    ///   - autosens: Enable automatic sensitivity gain (default: true)
    ///   - noiseReduction: Smoothing factor 0..1 (default: 0.77)
    ///   - bandExponent: Per-band bin-count normalization exponent / bass↔treble tilt (default: 0.3)
    ///   - lowCutOff: Low frequency cutoff Hz (default: 50)
    ///   - highCutOff: High frequency cutoff Hz (default: 10000)
    public init(
        numberOfBars: Int,
        rate: Int,
        channels: Int,
        autosens: Bool = true,
        noiseReduction: Double = 0.77,
        bandExponent: Float = 0.3,
        lowCutOff: Int = 50,
        highCutOff: Int = 10000
    ) {
        precondition(numberOfBars > 0, "numberOfBars must be > 0")
        precondition(rate > 0, "rate must be > 0")
        precondition(channels >= 1 && channels <= 2, "channels must be 1 or 2")
        precondition(noiseReduction >= 0.0 && noiseReduction <= 1.0, "noiseReduction must be in [0, 1]")
        precondition(lowCutOff > 0 && highCutOff > lowCutOff, "lowCutOff < highCutOff required")

        self.numberOfBars = numberOfBars
        self.rate = rate
        self.channels = channels
        self.autosens = autosens
        self.noiseReduction = noiseReduction
        self.bandExponent = max(0.0, min(1.0, bandExponent))
        self.lowCutOff = lowCutOff
        self.highCutOff = highCutOff

        // Initialize FFT setups
        bassFFTSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(bassFFTSize), .FORWARD)
        guard bassFFTSetup != nil else {
            fatalError("Failed to create bass FFT setup")
        }

        trebleFFTSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(trebleFFTSize), .FORWARD)
        guard trebleFFTSetup != nil else {
            fatalError("Failed to create treble FFT setup")
        }

        // Allocate FFT buffers
        bassFFTSamples = [Float](repeating: 0, count: bassFFTSize)
        bassFFTWindow = createHannWindow(size: bassFFTSize)
        bassFFTRealIn = [Float](repeating: 0, count: bassFFTSize)
        bassFFTImagIn = [Float](repeating: 0, count: bassFFTSize)
        bassFFTRealOut = [Float](repeating: 0, count: bassFFTSize)
        bassFFTImagOut = [Float](repeating: 0, count: bassFFTSize)
        bassFFTMagnitudes = [Float](repeating: 0, count: bassFFTSize / 2)

        trebleFFTSamples = [Float](repeating: 0, count: trebleFFTSize)
        trebleFFTWindow = createHannWindow(size: trebleFFTSize)
        trebleFFTRealIn = [Float](repeating: 0, count: trebleFFTSize)
        trebleFFTImagIn = [Float](repeating: 0, count: trebleFFTSize)
        trebleFFTRealOut = [Float](repeating: 0, count: trebleFFTSize)
        trebleFFTImagOut = [Float](repeating: 0, count: trebleFFTSize)
        trebleFFTMagnitudes = [Float](repeating: 0, count: trebleFFTSize / 2)

        // Initialize smoothing memory
        smoothedValues = Array(repeating: [Float](repeating: 0, count: numberOfBars), count: channels)
        peakValues = Array(repeating: [Float](repeating: 0, count: numberOfBars), count: channels)
        rawBarMagnitudes = Array(repeating: [Float](repeating: 0, count: numberOfBars), count: channels)

        // Build frequency mapping
        buildFrequencyMapping()
    }

    deinit {
        if let setup = bassFFTSetup {
            vDSP_DFT_DestroySetup(setup)
        }
        if let setup = trebleFFTSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }

    // MARK: - Window Generation

    /// Create a Hann window of the given size
    private func createHannWindow(size: Int) -> [Float] {
        return (0..<size).map { i in
            let val = Float(i) / Float(size)
            return 0.5 * (1.0 - cos(2.0 * .pi * val))
        }
    }

    // MARK: - Frequency Mapping

    /// Build the log-spaced cutoff table mapping bars to FFT bins
    private func buildFrequencyMapping() {
        barToBassRange = Array(repeating: (0, 0), count: numberOfBars)
        barToTrebleRange = Array(repeating: (0, 0), count: numberOfBars)
        barSource = Array(repeating: 0, count: numberOfBars)

        let bassBinWidth = Double(rate) / Double(bassFFTSize)
        let trebleBinWidth = Double(rate) / Double(trebleFFTSize)

        // Contiguous, non-overlapping log-spaced bands (cava's cut_off_frequency model):
        // bar n covers [edge(n), edge(n+1)) and its value is the summed energy in that band.
        func edgeFreq(_ i: Int) -> Double {
            Double(lowCutOff) * pow(Double(highCutOff) / Double(lowCutOff), Double(i) / Double(numberOfBars))
        }

        for barIdx in 0..<numberOfBars {
            let fLow = edgeFreq(barIdx)
            let fHigh = edgeFreq(barIdx + 1)

            // Use bass FFT for lower bars, treble for higher.
            barSource[barIdx] = fLow < 4000 ? 0 : 1

            let bassLow = max(1, Int(fLow / bassBinWidth))
            let bassHigh = max(bassLow, min(bassFFTSize / 2 - 1, Int(fHigh / bassBinWidth)))
            barToBassRange[barIdx] = (bassLow, bassHigh)

            let trebleLow = max(1, Int(fLow / trebleBinWidth))
            let trebleHigh = max(trebleLow, min(trebleFFTSize / 2 - 1, Int(fHigh / trebleBinWidth)))
            barToTrebleRange[barIdx] = (trebleLow, trebleHigh)
        }
    }

    // MARK: - DSP Execution

    /// Execute the spectrum analyzer on interleaved audio samples.
    ///
    /// - Parameter interleaved: Audio samples in interleaved format (mono non-interleaved if channels=1).
    ///   For stereo, format is [L, R, L, R, ...].
    ///   Call with frame-sized chunks (e.g., 2048 samples); the function buffers internally
    ///   and processes when enough samples accumulate.
    ///
    /// - Returns: Per-channel bar array. Each inner array has length `numberOfBars`, values 0..1.
    ///   Example: stereo → [[bar0_L, bar1_L, ...], [bar0_R, bar1_R, ...]]
    ///
    /// Convenience that runs `analyze` then `render`. Callers that redraw faster than the audio
    /// buffer rate should call `analyze(_:)` once per new buffer and `render()` per display frame.
    public func execute(_ interleaved: [Float]) -> [[Float]] {
        analyze(interleaved)
        return render()
    }

    /// Run the FFTs on a new audio buffer and cache the per-channel raw bar magnitudes.
    /// The expensive step — call once per new audio buffer (~audio rate).
    public func analyze(_ interleaved: [Float]) {
        for ch in 0..<channels {
            // Extract mono or one channel from interleaved
            var monoSamples = [Float]()
            if channels == 1 {
                monoSamples = interleaved
            } else {
                for i in stride(from: ch, to: interleaved.count, by: channels) {
                    monoSamples.append(interleaved[i])
                }
            }

            // Process this channel through both FFTs and cache the combined per-bar magnitudes.
            let bassResult = processBassFFT(samples: monoSamples)
            let trebleResult = processTreebleFFT(samples: monoSamples)
            for barIdx in 0..<numberOfBars {
                let source = barSource[barIdx]
                rawBarMagnitudes[ch][barIdx] = source == 0 ? bassResult[barIdx] : trebleResult[barIdx]
            }
        }
    }

    /// Post-process the cached magnitudes into 0..1 bars, advancing smoothing/gravity/autosens by
    /// one frame. Cheap — safe to call per display frame. Re-running this on unchanged cached
    /// magnitudes is identical to re-running `execute` on the same buffer, but skips the FFTs.
    public func render() -> [[Float]] {
        var result: [[Float]] = []
        // Largest bar value produced this frame (pre-clamp, across all channels), used to
        // adjust the persistent autosens gain once per frame after the channel loop.
        var frameMax: Float = 0

        for ch in 0..<channels {
            // Apply post-processing: neighbor smoothing, noise reduction, autosens, gravity.
            // Autosens scales the magnitudes by a persistent, slowly-adjusted gain BEFORE gravity,
            // so falloff acts in the normalized (0..1) domain. The gain is near-constant frame to
            // frame, so as the smoothed magnitude decays on silence the output decays with it and
            // gravity pulls settled bars to zero (a per-frame AGC would re-inflate the decaying tail).
            var barOutput = applyMonsterCatSmoothing(rawBarMagnitudes[ch])
            barOutput = applyNoiseReduction(barOutput, forChannel: ch)

            if autosens {
                barOutput = barOutput.map { $0 * sens }
                // Track overshoot from the instantaneous scaled magnitude (before clamp/gravity).
                // Reading it after gravity would see the slowly-decaying held peak and drive the
                // gain to collapse during any sustained signal.
                frameMax = max(frameMax, barOutput.max() ?? 0)
            }

            // Clamp into [0, 1] BEFORE gravity so the falloff memory cannot be poisoned by
            // pre-convergence magnitude spikes: peakValues must stay in the normalized domain,
            // otherwise the fixed per-frame falloff can never drain a large captured peak and the
            // bar stays pinned at full height.
            barOutput = barOutput.map { min(1.0, max(0.0, $0)) }

            // Gravity/falloff in normalized space: settled bars fall smoothly toward zero.
            barOutput = applyGravityAndFalloff(barOutput, forChannel: ch)
            result.append(barOutput)
        }

        // Adjust the persistent autosens gain based on this frame's overshoot/headroom.
        if autosens {
            adjustSens(frameMax: frameMax)
        }

        return result
    }

    // MARK: - FFT Processing

    /// Process samples through the bass FFT (4096 samples)
    private func processBassFFT(samples: [Float]) -> [Float] {
        let fftSize = bassFFTSize
        let fftSetup = bassFFTSetup!

        // Extract up to fftSize samples, zero-pad if needed
        let processCount = min(fftSize, samples.count)
        for i in 0..<fftSize {
            bassFFTSamples[i] = i < processCount ? samples[samples.count - processCount + i] * bassFFTWindow[i] : 0
        }

        // Prepare for DFT_zop: split into real and imaginary
        for i in 0..<fftSize {
            bassFFTRealIn[i] = bassFFTSamples[i]
            bassFFTImagIn[i] = 0
        }

        // Compute FFT
        vDSP_DFT_Execute(
            fftSetup,
            &bassFFTRealIn, &bassFFTImagIn,
            &bassFFTRealOut, &bassFFTImagOut
        )

        // Compute magnitudes
        for i in 0..<(fftSize / 2) {
            let real = bassFFTRealOut[i]
            let imag = bassFFTImagOut[i]
            bassFFTMagnitudes[i] = sqrt(real * real + imag * imag)
        }

        // Extract bar values from bass FFT: band energy normalized by √(bin count). Plain `sum`
        // over-weights high bars (their bands span far more FFT bins than bass bands), suppressing
        // bass; √N is the balance point between `sum` (treble-heavy) and `mean` (bass-heavy).
        var barValues = [Float](repeating: 0, count: numberOfBars)
        for barIdx in 0..<numberOfBars {
            let range = barToBassRange[barIdx]
            var sum: Float = 0
            var count = 0
            for binIdx in range.low...range.high where binIdx < bassFFTMagnitudes.count {
                sum += bassFFTMagnitudes[binIdx]
                count += 1
            }
            barValues[barIdx] = count > 0 ? sum / powf(Float(count), bandExponent) : 0
        }

        return barValues
    }

    /// Process samples through the treble FFT (2048 samples)
    private func processTreebleFFT(samples: [Float]) -> [Float] {
        let fftSize = trebleFFTSize
        let fftSetup = trebleFFTSetup!

        // Extract up to fftSize samples, zero-pad if needed
        let processCount = min(fftSize, samples.count)
        for i in 0..<fftSize {
            trebleFFTSamples[i] = i < processCount ? samples[samples.count - processCount + i] * trebleFFTWindow[i] : 0
        }

        // Prepare for DFT_zop
        for i in 0..<fftSize {
            trebleFFTRealIn[i] = trebleFFTSamples[i]
            trebleFFTImagIn[i] = 0
        }

        // Compute FFT
        vDSP_DFT_Execute(
            fftSetup,
            &trebleFFTRealIn, &trebleFFTImagIn,
            &trebleFFTRealOut, &trebleFFTImagOut
        )

        // Compute magnitudes
        for i in 0..<(fftSize / 2) {
            let real = trebleFFTRealOut[i]
            let imag = trebleFFTImagOut[i]
            trebleFFTMagnitudes[i] = sqrt(real * real + imag * imag)
        }

        // Extract bar values from treble FFT: band energy normalized by √(bin count) — see the
        // bass extractor for why (prevents wide high-frequency bands from swamping bass).
        var barValues = [Float](repeating: 0, count: numberOfBars)
        for barIdx in 0..<numberOfBars {
            let range = barToTrebleRange[barIdx]
            var sum: Float = 0
            var count = 0
            for binIdx in range.low...range.high where binIdx < trebleFFTMagnitudes.count {
                sum += trebleFFTMagnitudes[binIdx]
                count += 1
            }
            barValues[barIdx] = count > 0 ? sum / powf(Float(count), bandExponent) : 0
        }

        return barValues
    }

    // MARK: - Post-Processing

    /// Apply monstercat neighbor smoothing (blur across adjacent bars)
    private func applyMonsterCatSmoothing(_ bars: [Float]) -> [Float] {
        guard numberOfBars > 1 else { return bars }

        var smoothed = bars
        for i in 1..<(numberOfBars - 1) {
            smoothed[i] = 0.4 * bars[i] + 0.3 * bars[i - 1] + 0.3 * bars[i + 1]
        }
        // Edge cases
        if numberOfBars > 1 {
            smoothed[0] = 0.6 * bars[0] + 0.4 * bars[1]
            smoothed[numberOfBars - 1] = 0.6 * bars[numberOfBars - 1] + 0.4 * bars[numberOfBars - 2]
        }
        return smoothed
    }

    /// Apply integral/exponential smoothing (noise reduction via exponential moving average)
    private func applyNoiseReduction(_ bars: [Float], forChannel ch: Int) -> [Float] {
        let alpha = Float(1.0 - noiseReduction)
        var result = [Float]()

        for i in 0..<numberOfBars {
            // Exponential moving average
            let newVal = alpha * bars[i] + (1.0 - alpha) * smoothedValues[ch][i]
            smoothedValues[ch][i] = newVal
            result.append(newVal)
        }

        return result
    }

    /// Apply gravity and falloff (peaks decay over time)
    private func applyGravityAndFalloff(_ bars: [Float], forChannel ch: Int) -> [Float] {
        let falloff: Float = 0.05  // Gravity constant: bars fall at 5% per frame
        var result = bars

        for i in 0..<numberOfBars {
            if bars[i] >= peakValues[ch][i] {
                // Rise instantly to a new (or equal) value. Using >= is essential: with a strict >,
                // a steady bar (bars == peak) falls through to the decay branch every frame and then
                // snaps back the next, producing a period-2 flicker of amplitude `falloff` on every
                // bar — the dominant jitter, worst on short bars.
                peakValues[ch][i] = bars[i]
            } else {
                // Fall under gravity, but never below the actual current value so a decaying peak
                // can't undershoot and re-trigger the same oscillation.
                peakValues[ch][i] = max(bars[i], peakValues[ch][i] - falloff)
            }
            // Use the peak as the displayed value
            result[i] = peakValues[ch][i]
        }

        return result
    }

    /// Adjust the persistent autosens gain (`sens`) based on the frame's peak bar value.
    ///
    /// Mirrors cava's sensitivity control. The gain starts LOW and grows into the signal
    /// (`sensInit`), so at launch the bars rise from small to correct rather than starting pinned
    /// at full scale while a too-high gain grinds down. On any overshoot the gain attacks fast
    /// (proportional, floored) so bars never stay pinned — at launch or on a mid-track level jump —
    /// then releases slowly to avoid visible pumping. Because `sens` moves at most a few percent
    /// per frame in the release direction, a decaying input still yields a decaying output.
    private func adjustSens(frameMax: Float) {
        if frameMax > 1.0 {
            // Gentle attack (cava's value): ease the gain down on overshoot. Kept small so a loud
            // transient doesn't duck the whole spectrum (which reads as jitter/pumping); a single
            // bar briefly touching the ceiling is normal. The low-start grow-in below handles launch,
            // so no aggressive attack is needed here.
            sens *= 0.98
            sensInit = false
        } else if sensInit {
            // Grow into the signal from the low starting gain (bars ramp up, never pin).
            sens *= 1.2
        } else if frameMax < 0.85 {
            // Recover slowly ONLY when the peak sits well below the ceiling. The [0.85, 1.0]
            // deadband below stops the gain from hunting up-into-clip and back each frame, which
            // otherwise makes the whole spectrum throb — very visible when paused on a static frame.
            sens *= 1.001
        }
        // else: peak within [0.85, 1.0] — already well-scaled, leave the gain untouched.
        sens = min(max(sens, 1e-12), 1e12)
    }

    // MARK: - Reset

    /// Reset all smoothing and decay memory to initial state
    public func reset() {
        for ch in 0..<channels {
            for i in 0..<numberOfBars {
                smoothedValues[ch][i] = 0
                peakValues[ch][i] = 0
                rawBarMagnitudes[ch][i] = 0
            }
        }
        sens = 1e-6
        sensInit = true
    }
}
