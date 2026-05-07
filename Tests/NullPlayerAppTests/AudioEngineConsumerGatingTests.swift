import XCTest
@testable import NullPlayer

final class AudioEngineConsumerGatingTests: XCTestCase {
    func testSpectrumAndWaveformConsumersAreTrackedSeparately() {
        let engine = AudioEngine()

        XCTAssertFalse(engine.spectrumNeeded)
        XCTAssertFalse(engine.waveformNeeded)

        engine.addSpectrumConsumer("spectrum")
        XCTAssertTrue(engine.spectrumNeeded)
        XCTAssertFalse(engine.waveformNeeded)

        engine.addWaveformConsumer("waveform")
        XCTAssertTrue(engine.spectrumNeeded)
        XCTAssertTrue(engine.waveformNeeded)

        engine.removeSpectrumConsumer("spectrum")
        XCTAssertFalse(engine.spectrumNeeded)
        XCTAssertTrue(engine.waveformNeeded)

        engine.removeWaveformConsumer("waveform")
        XCTAssertFalse(engine.spectrumNeeded)
        XCTAssertFalse(engine.waveformNeeded)
    }
}
