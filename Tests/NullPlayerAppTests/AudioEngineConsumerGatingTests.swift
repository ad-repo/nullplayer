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
}
