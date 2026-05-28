import XCTest
@testable import NullPlayer

final class PitchTuningControllerTests: XCTestCase {

    func testOffsetCents_440to432_isApproximatelyMinus31p766() {
        let c = PitchTuningController()
        c.setReferences(source: 440, target: 432)
        XCTAssertEqual(c.offsetCents, -31.766654, accuracy: 0.001)
    }

    func testOffsetCents_440to440_isZero() {
        let c = PitchTuningController()
        c.setReferences(source: 440, target: 440)
        XCTAssertEqual(c.offsetCents, 0, accuracy: 1e-9)
    }

    func testOffsetCents_432to440_isApproximatelyPlus31p766() {
        let c = PitchTuningController()
        c.setReferences(source: 432, target: 440)
        XCTAssertEqual(c.offsetCents, 31.766654, accuracy: 0.001)
    }

    func testAppliedCentsZeroWhenDisabled() {
        let c = PitchTuningController()
        c.applyPreset(.hz432)
        XCTAssertTrue(c.appliedCents < 0)

        c.setEnabled(false)
        XCTAssertEqual(c.appliedCents, 0)
    }

    func testAppliedCentsClampedToRange() {
        let c = PitchTuningController()
        // 440 → 10000 Hz is ~5400 cents, well past the +2400 ceiling.
        c.applyPreset(.custom(source: 440, target: 10000))
        XCTAssertEqual(c.appliedCents, PitchTuningController.maxCents, accuracy: 1e-9)
    }

    func testCurrentPresetReflectsExactMatch() {
        let c = PitchTuningController()
        c.applyPreset(.hz432)
        XCTAssertEqual(c.currentPreset, .hz432)
        c.applyPreset(.off)
        XCTAssertEqual(c.currentPreset, .off)
    }

    func testStreamingPitchNodesAreIndependentAndFollowControllerState() {
        let c = PitchTuningController()
        let first = c.makeStreamingPitchNode()

        c.applyPreset(.hz432)
        XCTAssertFalse(first.bypass)
        XCTAssertEqual(first.pitch, Float(c.appliedCents), accuracy: 0.001)

        let second = c.makeStreamingPitchNode()
        XCTAssertFalse(first === second)
        XCTAssertFalse(second.bypass)
        XCTAssertEqual(second.pitch, Float(c.appliedCents), accuracy: 0.001)

        c.applyPreset(.off)
        XCTAssertTrue(first.bypass)
        XCTAssertTrue(second.bypass)
        XCTAssertEqual(first.pitch, 0, accuracy: 0.001)
        XCTAssertEqual(second.pitch, 0, accuracy: 0.001)
    }
}
