import XCTest
@testable import NullPlayer

final class AudioEngineConsumerGatingTests: XCTestCase {
    func testAnalysisConsumersAreTrackedSeparately() {
        let engine = AudioEngine()

        XCTAssertFalse(engine.spectrumNeeded)
        XCTAssertFalse(engine.waveformNeeded)
        XCTAssertFalse(engine.stereoNeeded)

        engine.addSpectrumConsumer("spectrum")
        XCTAssertTrue(engine.spectrumNeeded)
        XCTAssertEqual(engine.spectrumConsumerRegistrationCount, 1)
        XCTAssertFalse(engine.waveformNeeded)
        XCTAssertFalse(engine.stereoNeeded)

        engine.addWaveformConsumer("waveform")
        XCTAssertTrue(engine.spectrumNeeded)
        XCTAssertTrue(engine.waveformNeeded)
        XCTAssertFalse(engine.stereoNeeded)

        engine.addStereoConsumer("stereo")
        XCTAssertTrue(engine.spectrumNeeded)
        XCTAssertTrue(engine.waveformNeeded)
        XCTAssertTrue(engine.stereoNeeded)

        engine.removeSpectrumConsumer("spectrum")
        XCTAssertFalse(engine.spectrumNeeded)
        XCTAssertEqual(engine.spectrumConsumerRegistrationCount, 0)
        XCTAssertTrue(engine.waveformNeeded)
        XCTAssertTrue(engine.stereoNeeded)

        engine.removeWaveformConsumer("waveform")
        XCTAssertFalse(engine.spectrumNeeded)
        XCTAssertFalse(engine.waveformNeeded)
        XCTAssertTrue(engine.stereoNeeded)

        engine.removeStereoConsumer("stereo")
        XCTAssertFalse(engine.spectrumNeeded)
        XCTAssertFalse(engine.waveformNeeded)
        XCTAssertFalse(engine.stereoNeeded)
    }

    func testDuplicateConsumerRegistrationsAreReferenceCounted() {
        let engine = AudioEngine()

        engine.addWaveformConsumer("replacement-safe")
        engine.addWaveformConsumer("replacement-safe")
        XCTAssertTrue(engine.waveformNeeded)

        engine.removeWaveformConsumer("replacement-safe")
        XCTAssertTrue(engine.waveformNeeded)

        engine.removeWaveformConsumer("replacement-safe")
        XCTAssertFalse(engine.waveformNeeded)
    }

    func testSpectrumRegistrationCountTracksReplacementSafeReferenceCounts() {
        let engine = AudioEngine()

        engine.addSpectrumConsumer("replacement-safe")
        engine.addSpectrumConsumer("replacement-safe")
        XCTAssertEqual(engine.spectrumConsumerRegistrationCount, 2)

        engine.removeSpectrumConsumer("replacement-safe")
        XCTAssertEqual(engine.spectrumConsumerRegistrationCount, 1)
        engine.removeSpectrumConsumer("replacement-safe")
        XCTAssertEqual(engine.spectrumConsumerRegistrationCount, 0)
    }
}
