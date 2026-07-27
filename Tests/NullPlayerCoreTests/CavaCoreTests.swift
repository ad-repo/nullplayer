import XCTest
@testable import NullPlayerCore

final class CavaCoreTests: XCTestCase {

    // MARK: - Frequency Localization Tests

    func testFrequencyLocalizationMono1kHz() {
        // Feed a 1 kHz sine at 44100 Hz in mono.
        // After enough frames, energy should concentrate in the bar
        // corresponding to ~1 kHz (roughly bar 17 in a 32-bar 50-10kHz range).
        let cava = CavaCore(numberOfBars: 32, rate: 44100, channels: 1)

        // Generate 1 kHz sine
        let sine1kHz = generateSineWave(frequency: 1000, duration: 0.5, sampleRate: 44100, amplitude: 0.8)

        // Run multiple frames to reach steady state (smoothing ramps up)
        var lastResult: [[Float]] = []
        let framesPerChunk = 2048
        for i in stride(from: 0, to: sine1kHz.count, by: framesPerChunk) {
            let chunk = Array(sine1kHz[i..<min(i + framesPerChunk, sine1kHz.count)])
            lastResult = cava.execute(chunk)
        }

        // After steady state, one channel (mono), find max bar
        XCTAssertEqual(lastResult.count, 1, "Mono should return 1 channel")
        let bars = lastResult[0]
        XCTAssertEqual(bars.count, 32, "Should have 32 bars")

        // Find the bar with maximum energy
        let maxIdx = bars.indices.max(by: { bars[$0] < bars[$1] }) ?? 0
        let maxValue = bars[maxIdx]

        // For a 1 kHz tone in 50-10kHz log-spaced 32 bars,
        // 1 kHz is roughly at bar index 17-18 (log10(1000/50) / log10(10000/50) ≈ 0.565)
        // Assert peak is in expected region and is significantly higher than distant bars
        XCTAssertGreaterThanOrEqual(maxIdx, 15)
        XCTAssertLessThanOrEqual(maxIdx, 20)
        XCTAssertGreaterThan(maxValue, 0.3, "Peak bar should have substantial energy for 0.8 amplitude sine")

        // Assert peak is significantly higher than bar 0 (50 Hz region)
        XCTAssertGreaterThan(maxValue, bars[0] + 0.1, "1kHz tone should concentrate away from 50Hz region")
        // Assert peak is significantly higher than bar 31 (10kHz region)
        XCTAssertGreaterThan(maxValue, bars[31] + 0.1, "1kHz tone should concentrate away from 10kHz region")
    }

    func testFrequencyLocalizationMono5kHz() {
        // Feed a 5 kHz sine. At 4 kHz threshold, cava switches to treble FFT.
        // 5 kHz should map to a higher bar index than 1 kHz.
        let cava = CavaCore(numberOfBars: 32, rate: 44100, channels: 1)

        let sine5kHz = generateSineWave(frequency: 5000, duration: 0.5, sampleRate: 44100, amplitude: 0.8)

        var lastResult: [[Float]] = []
        let framesPerChunk = 2048
        for i in stride(from: 0, to: sine5kHz.count, by: framesPerChunk) {
            let chunk = Array(sine5kHz[i..<min(i + framesPerChunk, sine5kHz.count)])
            lastResult = cava.execute(chunk)
        }

        let bars = lastResult[0]
        let maxIdx = bars.indices.max(by: { bars[$0] < bars[$1] }) ?? 0
        let maxValue = bars[maxIdx]

        // 5 kHz in log-spaced 50-10k over 32 bars:
        // log10(5000/50) / log10(10000/50) = log10(100) / log10(200) ≈ 2.0 / 2.301 ≈ 0.869
        // barIdx ≈ 0.869 * 31 ≈ 26-27
        XCTAssertGreaterThanOrEqual(maxIdx, 24)
        XCTAssertLessThanOrEqual(maxIdx, 29)
        XCTAssertGreaterThan(maxValue, 0.3, "Peak bar should have substantial energy")
    }

    // MARK: - Stereo Panning Tests

    func testStereoPanningLeftOnly() {
        // Stereo with 2 channels. Feed a 1 kHz tone hard-panned to LEFT (right silent).
        // Left channel bars should have energy; right should be ~0.
        let cava = CavaCore(numberOfBars: 32, rate: 44100, channels: 2)

        // Generate 1 kHz sine for left channel
        let sine1kHz = generateSineWave(frequency: 1000, duration: 0.5, sampleRate: 44100, amplitude: 0.8)

        // Create stereo interleaved: [L, R, L, R, ...]
        var stereoInterleaved = [Float]()
        for sample in sine1kHz {
            stereoInterleaved.append(sample)  // Left
            stereoInterleaved.append(0.0)      // Right (silent)
        }

        // Run multiple frames
        var lastResult: [[Float]] = []
        let framesPerChunk = 2048
        for i in stride(from: 0, to: stereoInterleaved.count, by: framesPerChunk * 2) {
            let end = min(i + framesPerChunk * 2, stereoInterleaved.count)
            let chunk = Array(stereoInterleaved[i..<end])
            lastResult = cava.execute(chunk)
        }

        XCTAssertEqual(lastResult.count, 2, "Stereo should return 2 channels")
        let leftBars = lastResult[0]
        let rightBars = lastResult[1]

        // Left channel should have peak energy
        let leftMaxIdx = leftBars.indices.max(by: { leftBars[$0] < leftBars[$1] }) ?? 0
        let leftMaxValue = leftBars[leftMaxIdx]
        XCTAssertGreaterThan(leftMaxValue, 0.2, "Left channel should have energy for left-panned tone")

        // Right channel should be nearly silent
        let rightMax = rightBars.max() ?? 0
        XCTAssertLessThan(rightMax, 0.15, "Right channel should be silent for left-panned tone")

        // Left peak should be significantly higher than right
        XCTAssertGreaterThan(leftMaxValue, rightMax + 0.1, "Left should dominate right for left-panned tone")
    }

    func testStereoPanningRightOnly() {
        // Stereo with right-panned tone (left silent).
        // Right channel bars should have energy; left should be ~0.
        let cava = CavaCore(numberOfBars: 32, rate: 44100, channels: 2)

        let sine1kHz = generateSineWave(frequency: 1000, duration: 0.5, sampleRate: 44100, amplitude: 0.8)

        // Create stereo interleaved: [L, R, L, R, ...]
        var stereoInterleaved = [Float]()
        for sample in sine1kHz {
            stereoInterleaved.append(0.0)      // Left (silent)
            stereoInterleaved.append(sample)   // Right
        }

        var lastResult: [[Float]] = []
        let framesPerChunk = 2048
        for i in stride(from: 0, to: stereoInterleaved.count, by: framesPerChunk * 2) {
            let end = min(i + framesPerChunk * 2, stereoInterleaved.count)
            let chunk = Array(stereoInterleaved[i..<end])
            lastResult = cava.execute(chunk)
        }

        let leftBars = lastResult[0]
        let rightBars = lastResult[1]

        // Right channel should have peak energy
        let rightMaxIdx = rightBars.indices.max(by: { rightBars[$0] < rightBars[$1] }) ?? 0
        let rightMaxValue = rightBars[rightMaxIdx]
        XCTAssertGreaterThan(rightMaxValue, 0.2, "Right channel should have energy for right-panned tone")

        // Left channel should be nearly silent
        let leftMax = leftBars.max() ?? 0
        XCTAssertLessThan(leftMax, 0.15, "Left channel should be silent for right-panned tone")

        // Right peak should be significantly higher than left
        XCTAssertGreaterThan(rightMaxValue, leftMax + 0.1, "Right should dominate left for right-panned tone")
    }

    // MARK: - Autosens Bounds Tests

    func testAutosenseKeepsOutputInBounds() {
        // With autosens enabled (default), output should always be [0, 1].
        let cava = CavaCore(numberOfBars: 32, rate: 44100, channels: 1, autosens: true)

        // Test with varying amplitudes: quiet, normal, and loud
        let amplitudes: [Float] = [0.1, 0.5, 1.0, 2.0]

        for amplitude in amplitudes {
            let sine = generateSineWave(frequency: 1000, duration: 0.1, sampleRate: 44100, amplitude: amplitude)
            let result = cava.execute(sine)

            let bars = result[0]
            for (barIdx, value) in bars.enumerated() {
                XCTAssertGreaterThanOrEqual(value, 0.0, "Bar \(barIdx) value should be >= 0")
                XCTAssertLessThanOrEqual(value, 1.0, "Bar \(barIdx) value should be <= 1")
            }
        }
    }

    func testAutosenseVeryLoudSignal() {
        // Even a very loud signal (amplitude 5.0, well above typical [0,1] range)
        // should be normalized by autosens to [0, 1].
        let cava = CavaCore(numberOfBars: 32, rate: 44100, channels: 1, autosens: true)

        let loudSine = generateSineWave(frequency: 2000, duration: 0.2, sampleRate: 44100, amplitude: 5.0)

        // Run multiple frames to let autosens adjust
        var lastResult: [[Float]] = []
        let framesPerChunk = 2048
        for i in stride(from: 0, to: loudSine.count, by: framesPerChunk) {
            let chunk = Array(loudSine[i..<min(i + framesPerChunk, loudSine.count)])
            lastResult = cava.execute(chunk)
        }

        let bars = lastResult[0]
        for value in bars {
            XCTAssertGreaterThanOrEqual(value, 0.0, "Very loud signal should still be bounded >= 0")
            XCTAssertLessThanOrEqual(value, 1.0, "Very loud signal should be bounded <= 1 via autosens")
        }
    }

    func testNoAutosenseStillClampsOutput() {
        // With autosens disabled, output may exceed 1.0 on very loud signals.
        // But clamping in execute() should still enforce [0, 1].
        // (CavaCore clamps at the end: `barOutput.map { min(1.0, max(0.0, $0)) }`)
        let cava = CavaCore(numberOfBars: 32, rate: 44100, channels: 1, autosens: false)

        let loudSine = generateSineWave(frequency: 2000, duration: 0.2, sampleRate: 44100, amplitude: 2.0)

        var lastResult: [[Float]] = []
        let framesPerChunk = 2048
        for i in stride(from: 0, to: loudSine.count, by: framesPerChunk) {
            let chunk = Array(loudSine[i..<min(i + framesPerChunk, loudSine.count)])
            lastResult = cava.execute(chunk)
        }

        let bars = lastResult[0]
        for value in bars {
            // Even without autosens, clamping in execute() ensures [0, 1]
            XCTAssertGreaterThanOrEqual(value, 0.0)
            XCTAssertLessThanOrEqual(value, 1.0)
        }
    }

    // MARK: - Gravity/Falloff Decay Tests

    func testSilenceDecaysViaGravity() {
        // Drive with a signal until bars rise, then feed silence for many frames.
        // Bars should monotonically decrease toward 0 due to gravity falloff.
        let cava = CavaCore(numberOfBars: 32, rate: 44100, channels: 1)

        // Phase 1: Drive with 1 kHz sine for ~0.2 sec
        let sine1kHz = generateSineWave(frequency: 1000, duration: 0.2, sampleRate: 44100, amplitude: 0.8)

        var result = [[Float]]()
        let framesPerChunk = 2048
        for i in stride(from: 0, to: sine1kHz.count, by: framesPerChunk) {
            let chunk = Array(sine1kHz[i..<min(i + framesPerChunk, sine1kHz.count)])
            result = cava.execute(chunk)
        }

        let barsAfterSignal = result[0]
        let maxAfterSignal = barsAfterSignal.max() ?? 0
        XCTAssertGreaterThan(maxAfterSignal, 0.2, "Signal should drive bars up")

        // Phase 2: Feed silence for ~0.2 sec (200 ms = 8820 samples at 44100)
        let silenceFrames = [Float](repeating: 0, count: 8820)

        var silenceResults: [Float] = barsAfterSignal
        for i in stride(from: 0, to: silenceFrames.count, by: framesPerChunk) {
            let chunk = Array(silenceFrames[i..<min(i + framesPerChunk, silenceFrames.count)])
            let silenceResult = cava.execute(chunk)
            silenceResults = silenceResult[0]
        }

        // After silence, bars should have decayed significantly
        let maxAfterSilence = silenceResults.max() ?? 0
        XCTAssertLessThan(maxAfterSilence, maxAfterSignal, "Bars should decay during silence")
        XCTAssertLessThan(maxAfterSilence, 0.05, "After prolonged silence, max bar should approach 0")

        // Verify monotonic decrease: check a few frames during silence decay
        cava.reset()
        // Re-drive
        for i in stride(from: 0, to: sine1kHz.count, by: framesPerChunk) {
            let chunk = Array(sine1kHz[i..<min(i + framesPerChunk, sine1kHz.count)])
            result = cava.execute(chunk)
        }

        var previousMax = result[0].max() ?? 0
        for i in stride(from: 0, to: 5 * framesPerChunk, by: framesPerChunk) {
            let chunk = Array(silenceFrames[i..<min(i + framesPerChunk, silenceFrames.count)])
            result = cava.execute(chunk)
            let currentMax = result[0].max() ?? 0
            // Allow small floating-point tolerance
            XCTAssertLessThanOrEqual(currentMax, previousMax + 0.001,
                                    "Max bar during silence should monotonically decrease")
            previousMax = currentMax
        }
    }

    // MARK: - Reset Tests

    func testResetClearsInternalState() {
        // After reset(), internal decay memory is cleared.
        // A subsequent silent frame should yield ~0 bars.
        let cava = CavaCore(numberOfBars: 32, rate: 44100, channels: 1)

        // Drive with signal
        let sine = generateSineWave(frequency: 1000, duration: 0.1, sampleRate: 44100, amplitude: 0.8)
        let framesPerChunk = 2048
        for i in stride(from: 0, to: sine.count, by: framesPerChunk) {
            let chunk = Array(sine[i..<min(i + framesPerChunk, sine.count)])
            _ = cava.execute(chunk)
        }

        // Without reset, feed silence and bars decay gradually
        let silence = [Float](repeating: 0, count: framesPerChunk)
        let resultBeforeReset = cava.execute(silence)
        let maxBeforeReset = resultBeforeReset[0].max() ?? 0
        XCTAssertGreaterThan(maxBeforeReset, 0.0, "Bars should still have residual peak before reset")

        // Call reset()
        cava.reset()

        // Now feed silence: bars should immediately drop to ~0
        let resultAfterReset = cava.execute(silence)
        let maxAfterReset = resultAfterReset[0].max() ?? 0
        XCTAssertLessThan(maxAfterReset, 0.01, "After reset(), silent input should yield ~0 bars")
    }

    func testResetInStereo() {
        // Reset should clear state for all channels.
        let cava = CavaCore(numberOfBars: 32, rate: 44100, channels: 2)

        // Drive both channels with different tones
        let sine1kHz = generateSineWave(frequency: 1000, duration: 0.1, sampleRate: 44100, amplitude: 0.8)
        let sine5kHz = generateSineWave(frequency: 5000, duration: 0.1, sampleRate: 44100, amplitude: 0.8)

        var stereoInterleaved = [Float]()
        for i in 0..<sine1kHz.count {
            stereoInterleaved.append(sine1kHz[i])
            stereoInterleaved.append(sine5kHz[i])
        }

        let framesPerChunk = 2048
        for i in stride(from: 0, to: stereoInterleaved.count, by: framesPerChunk * 2) {
            let end = min(i + framesPerChunk * 2, stereoInterleaved.count)
            let chunk = Array(stereoInterleaved[i..<end])
            _ = cava.execute(chunk)
        }

        // Feed silence and verify residual peaks exist
        let silence = [Float](repeating: 0, count: framesPerChunk * 2)
        var result = cava.execute(silence)
        let leftMaxBefore = result[0].max() ?? 0
        let rightMaxBefore = result[1].max() ?? 0
        XCTAssertGreaterThan(leftMaxBefore, 0.0)
        XCTAssertGreaterThan(rightMaxBefore, 0.0)

        // Reset and check both channels
        cava.reset()
        result = cava.execute(silence)
        let leftMaxAfter = result[0].max() ?? 0
        let rightMaxAfter = result[1].max() ?? 0
        XCTAssertLessThan(leftMaxAfter, 0.01, "Left channel should be ~0 after reset")
        XCTAssertLessThan(rightMaxAfter, 0.01, "Right channel should be ~0 after reset")
    }

    func testLeadingSilenceDoesNotPoisonAutosensitivity() {
        let cava = CavaCore(numberOfBars: 32, rate: 44100, channels: 1)
        let silence = [Float](repeating: 0, count: 2048)

        // Four seconds of live silent PCM still drives the display-rate render loop.
        // Sensitivity must remain parked until an audible frame arrives.
        cava.analyze(silence)
        for _ in 0..<240 {
            _ = cava.render()
        }

        let tone = generateSineWave(
            frequency: 1000,
            duration: Double(2048) / 44100.0,
            sampleRate: 44100,
            amplitude: 0.8
        )
        cava.analyze(tone)
        let firstSignalFrame = cava.render()[0]

        XCTAssertLessThan(
            firstSignalFrame.max() ?? 0,
            0.99,
            "Leading silence must not pre-amplify the first audible frame to full scale"
        )
    }

    // MARK: - Configuration Tests

    func testInitializationWithCustomParameters() {
        // Test that CavaCore accepts custom cutoff frequencies and noise reduction.
        let cava = CavaCore(
            numberOfBars: 64,
            rate: 48000,
            channels: 1,
            autosens: false,
            noiseReduction: 0.5,
            lowCutOff: 100,
            highCutOff: 5000
        )

        XCTAssertEqual(cava.numberOfBars, 64)
        XCTAssertEqual(cava.rate, 48000)
        XCTAssertEqual(cava.channels, 1)
        XCTAssertEqual(cava.autosens, false)
        XCTAssertEqual(cava.noiseReduction, 0.5)
        XCTAssertEqual(cava.lowCutOff, 100)
        XCTAssertEqual(cava.highCutOff, 5000)
    }

    func testExecuteReturnsCorrectNumberOfChannels() {
        // Mono CavaCore should return 1 channel.
        let monoCava = CavaCore(numberOfBars: 32, rate: 44100, channels: 1)
        let monoSine = generateSineWave(frequency: 1000, duration: 0.01, sampleRate: 44100, amplitude: 0.8)
        let monoResult = monoCava.execute(monoSine)
        XCTAssertEqual(monoResult.count, 1, "Mono should return 1 channel")
        XCTAssertEqual(monoResult[0].count, 32, "Channel should have 32 bars")

        // Stereo CavaCore should return 2 channels.
        let stereoCava = CavaCore(numberOfBars: 32, rate: 44100, channels: 2)
        var stereoSine = [Float]()
        for sample in monoSine {
            stereoSine.append(sample)
            stereoSine.append(sample)
        }
        let stereoResult = stereoCava.execute(stereoSine)
        XCTAssertEqual(stereoResult.count, 2, "Stereo should return 2 channels")
        XCTAssertEqual(stereoResult[0].count, 32, "Each channel should have 32 bars")
        XCTAssertEqual(stereoResult[1].count, 32, "Each channel should have 32 bars")
    }

    func testSmallAndLargeBarCounts() {
        // Test with different bar counts.
        let small = CavaCore(numberOfBars: 8, rate: 44100, channels: 1)
        let smallSine = generateSineWave(frequency: 1000, duration: 0.01, sampleRate: 44100, amplitude: 0.8)
        let smallResult = small.execute(smallSine)
        XCTAssertEqual(smallResult[0].count, 8)

        let large = CavaCore(numberOfBars: 128, rate: 44100, channels: 1)
        let largeResult = large.execute(smallSine)
        XCTAssertEqual(largeResult[0].count, 128)
    }

    // MARK: - Helper Functions

    /// Generate a sine wave at a specified frequency.
    private func generateSineWave(
        frequency: Double,
        duration: Double,
        sampleRate: Double,
        amplitude: Float
    ) -> [Float] {
        let sampleCount = Int(duration * sampleRate)
        var samples = [Float](repeating: 0, count: sampleCount)
        let tau = 2.0 * .pi
        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            samples[i] = amplitude * Float(sin(tau * frequency * t))
        }
        return samples
    }
}
