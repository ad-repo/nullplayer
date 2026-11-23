import NullPlayerCore
import XCTest
@testable import NullPlayer

final class EQPresetApplyTests: XCTestCase {
    /// A preset's gains are clamped to ±12 dB and its ten classic bands remapped onto the engine's
    /// layout; applying one leaves the EQ switch alone.
    func testAPresetIsClampedAndRemappedOntoTheEngine() {
        let engine = AudioEngine()
        let bands: [Float] = [20, -20, 3, 0, 0, 0, 0, 0, -5, 6]
        EQPreset(name: "Loud", preamp: 15, bands: bands).apply(to: engine)

        XCTAssertEqual(engine.getPreamp(), 12, accuracy: 0.001)
        let expected = EQBandRemapper.remap(gains: bands.map { max(-12, min(12, $0)) }, from: .classic10,
                                            to: engine.eqConfiguration)
        for (band, gain) in expected.enumerated() {
            XCTAssertEqual(engine.getEQBand(band), gain, accuracy: 0.001, "band \(band)")
        }
        XCTAssertFalse(engine.isEQEnabled())
    }
}
