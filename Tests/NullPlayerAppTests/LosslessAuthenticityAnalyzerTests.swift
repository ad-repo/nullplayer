import XCTest
@testable import NullPlayer

final class LosslessAuthenticityAnalyzerTests: XCTestCase {
    private let sampleRate = 44_100.0
    private let analysisSeconds = 4.2

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "fakeLosslessReportingEnabled")
        super.tearDown()
    }

    func testFullBandNoiseScoresHigh() {
        let signal = makeWhiteNoise(frameCount: Int(sampleRate * analysisSeconds))

        let result = LosslessAuthenticityAnalyzer.analyze(
            channels: [signal],
            sampleRate: sampleRate,
            coverage: .sampledFile
        )

        XCTAssertEqual(result.classification, .highConfidenceGenuine)
        XCTAssertGreaterThanOrEqual(result.confidencePercent, 85)
    }

    func testLowPassAt16kScoresLow() {
        let signal = makeDenseSignal(sampleRate: sampleRate, seconds: analysisSeconds, maxFrequency: 16_000)

        let result = LosslessAuthenticityAnalyzer.analyze(
            channels: [signal],
            sampleRate: sampleRate,
            coverage: .sampledFile
        )

        XCTAssertLessThanOrEqual(result.confidencePercent, 59)
        XCTAssertEqual(result.classification, .lowConfidencePossibleLossySource)
    }

    func testLowPassAt19kIsNotSevere() {
        let signal = makeDenseSignal(sampleRate: sampleRate, seconds: analysisSeconds, maxFrequency: 19_000)

        let result = LosslessAuthenticityAnalyzer.analyze(
            channels: [signal],
            sampleRate: sampleRate,
            coverage: .sampledFile
        )

        XCTAssertGreaterThanOrEqual(result.confidencePercent, 55)
        XCTAssertNotEqual(result.classification, .veryLowConfidenceLikelyLossyOrUpsampled)
    }

    func testLowHighBandEnergyAloneDoesNotForceLowConfidence() {
        let features = LosslessSpectralFeatures(
            usefulFrameCount: 32,
            analyzedDuration: 89.0,
            effectiveCutoffHz: 22_050,
            highBandEnergyRatio: 0.001,
            ultrasonicEnergyRatio: 0,
            cutoffSharpnessDbPerKhz: 0,
            spectralHoleScore: 0.2,
            activeBandwidthHz: 22_050,
            activeGroupCount: 12,
            peakDb: 0
        )

        let result = LosslessAuthenticityAnalyzer.score(
            features: features,
            sampleRate: sampleRate,
            channelCount: 2,
            coverage: .sampledFile
        )

        XCTAssertEqual(result.confidencePercent, 50)
        XCTAssertEqual(result.classification, .inconclusive)
        XCTAssertTrue(result.evidence.contains { $0.label == "High-band energy" && $0.severity == .warning })
        XCTAssertTrue(result.evidence.contains { $0.label == "Scan coverage" && $0.value == "high-band energy alone is not decisive" })
    }

    func testSilenceAndSparseSineAreInconclusive() {
        let frameCount = Int(sampleRate * analysisSeconds)
        let silence = [Float](repeating: 0, count: frameCount)
        let sine = makeSine(sampleRate: sampleRate, seconds: analysisSeconds, frequency: 1_000)

        let silenceResult = LosslessAuthenticityAnalyzer.analyze(
            channels: [silence],
            sampleRate: sampleRate,
            coverage: .sampledFile
        )
        let sineResult = LosslessAuthenticityAnalyzer.analyze(
            channels: [sine],
            sampleRate: sampleRate,
            coverage: .sampledFile
        )

        XCTAssertEqual(silenceResult.classification, .inconclusive)
        XCTAssertEqual(sineResult.classification, .inconclusive)
    }

    func testHiResWithoutUltrasonicContentProducesUpsampleEvidence() {
        let hiResSampleRate = 96_000.0
        let signal = makeDenseSignal(sampleRate: hiResSampleRate, seconds: analysisSeconds, maxFrequency: 20_000)

        let result = LosslessAuthenticityAnalyzer.analyze(
            channels: [signal],
            sampleRate: hiResSampleRate,
            coverage: .sampledFile
        )

        XCTAssertTrue(result.evidence.contains { $0.label == "Upsample check" && $0.severity == .warning })
    }

    func testNonLosslessExtensionReturnsNotApplicable() {
        let track = Track(url: URL(fileURLWithPath: "/tmp/example.mp3"), title: "Example")
        let aac = Track(url: URL(string: "https://example.com/stream")!, title: "Example", contentType: "audio/aac")

        let status = LosslessAuthenticityAnalyzer.notApplicableStatus(for: track)
        let contentTypeStatus = LosslessAuthenticityAnalyzer.notApplicableStatus(for: aac)

        XCTAssertEqual(status, .notApplicable(reason: "lossy format"))
        XCTAssertEqual(contentTypeStatus, .notApplicable(reason: "lossy format"))
    }

    func testOutOfPhaseStereoHighFrequenciesDoNotCauseFalseCutoff() {
        let base = makeDenseSignal(sampleRate: sampleRate, seconds: analysisSeconds, maxFrequency: 14_000)
        let high = makeDenseSignal(sampleRate: sampleRate, seconds: analysisSeconds, minFrequency: 16_200, maxFrequency: 20_000)
        let left = zip(base, high).map(+)
        let right = zip(base, high).map { $0 - $1 }

        let result = LosslessAuthenticityAnalyzer.analyze(
            channels: [left, right],
            sampleRate: sampleRate,
            coverage: .sampledFile
        )

        XCTAssertGreaterThanOrEqual(result.confidencePercent, 60)
        XCTAssertNotEqual(result.classification, .veryLowConfidenceLikelyLossyOrUpsampled)
    }

    func testNaturallyBandLimitedContentIsNotVeryLowConfidence() {
        let signal = makeDenseSignal(sampleRate: sampleRate, seconds: analysisSeconds, maxFrequency: 18_000, highFrequencyScale: 0.35)

        let result = LosslessAuthenticityAnalyzer.analyze(
            channels: [signal],
            sampleRate: sampleRate,
            coverage: .sampledFile
        )

        XCTAssertNotEqual(result.classification, .veryLowConfidenceLikelyLossyOrUpsampled)
    }

    func testBrickwallBoundaryAt19500IsDeterministic() {
        let signal = makeDenseSignal(sampleRate: sampleRate, seconds: analysisSeconds, maxFrequency: 19_500)

        let first = LosslessAuthenticityAnalyzer.analyze(
            channels: [signal],
            sampleRate: sampleRate,
            coverage: .sampledFile
        )
        let second = LosslessAuthenticityAnalyzer.analyze(
            channels: [signal],
            sampleRate: sampleRate,
            coverage: .sampledFile
        )

        XCTAssertEqual(first.confidencePercent, second.confidencePercent)
        XCTAssertEqual(first.classification, second.classification)
    }

    func testFFTScaleWindowRegressionForFullScaleTone() {
        let db = LosslessAuthenticityAnalyzer.normalizedToneDB(amplitude: 1.0)

        XCTAssertEqual(db, 0.0, accuracy: 0.5)
    }

    func testAudioEngineTogglePersistsAndPostsNotifications() {
        UserDefaults.standard.removeObject(forKey: "fakeLosslessReportingEnabled")
        let engine = AudioEngine()
        let optionsExpectation = expectation(description: "options notification")
        let losslessExpectation = expectation(description: "lossless notification")
        optionsExpectation.assertForOverFulfill = false
        losslessExpectation.assertForOverFulfill = false

        let optionsObserver = NotificationCenter.default.addObserver(
            forName: .audioPlaybackOptionsChanged,
            object: engine,
            queue: .main
        ) { _ in optionsExpectation.fulfill() }
        let losslessObserver = NotificationCenter.default.addObserver(
            forName: .losslessAuthenticityDidChange,
            object: engine,
            queue: .main
        ) { _ in losslessExpectation.fulfill() }
        engine.fakeLosslessReportingEnabled = true

        wait(for: [optionsExpectation, losslessExpectation], timeout: 1)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "fakeLosslessReportingEnabled"))
        XCTAssertEqual(engine.currentLosslessAuthenticityStatus, .notApplicable(reason: "No track loaded"))

        NotificationCenter.default.removeObserver(optionsObserver)
        NotificationCenter.default.removeObserver(losslessObserver)
        engine.fakeLosslessReportingEnabled = false
        XCTAssertEqual(engine.currentLosslessAuthenticityStatus, .disabled)
    }

    private func makeDenseSignal(
        sampleRate: Double,
        seconds: Double,
        minFrequency: Double = 180,
        maxFrequency: Double,
        highFrequencyScale: Float = 1.0
    ) -> [Float] {
        let frameCount = Int(sampleRate * seconds)
        let frequencies = stride(from: minFrequency, through: maxFrequency, by: 271).map { $0 }
        var samples = [Float](repeating: 0, count: frameCount)

        for (index, frequency) in frequencies.enumerated() {
            let phase = Float(index % 17) * 0.37
            let scale: Float = frequency > 16_000 ? highFrequencyScale : 1.0
            for frame in samples.indices {
                samples[frame] += scale * sinf((2 * .pi * Float(frequency) * Float(frame) / Float(sampleRate)) + phase)
            }
        }

        let peak = max(samples.map { abs($0) }.max() ?? 1, 1)
        return samples.map { 0.8 * $0 / peak }
    }

    private func makeWhiteNoise(frameCount: Int) -> [Float] {
        var state: UInt64 = 0x5eed
        return (0..<frameCount).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let unit = Float((state >> 33) & 0x7fff_ffff) / Float(0x7fff_ffff)
            return (unit * 2 - 1) * 0.5
        }
    }

    private func makeSine(sampleRate: Double, seconds: Double, frequency: Double) -> [Float] {
        (0..<Int(sampleRate * seconds)).map { frame in
            0.8 * sinf(2 * .pi * Float(frequency) * Float(frame) / Float(sampleRate))
        }
    }
}
