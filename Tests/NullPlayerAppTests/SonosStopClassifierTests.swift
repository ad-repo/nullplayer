import XCTest
@testable import NullPlayer

/// Pure-logic tests for `CastManager.sonosStopIsNaturalFinish` — the classifier that decides whether
/// a Sonos STOPPED report is a natural end-of-track finish (advance) or an external/intended stop
/// (pause). See GH #415.
final class SonosStopClassifierTests: XCTestCase {

    private let tolerance: TimeInterval = 6.0

    func testNearEndIsNaturalFinish() {
        // Long track stopped ~2s before its metadata duration → natural finish → advance.
        XCTAssertTrue(CastManager.sonosStopIsNaturalFinish(
            position: 238.0, expectedDuration: 240.0, tolerance: tolerance, locallyStopped: false))
    }

    func testMidTrackStopIsNotFinish() {
        // Stopped well before the end (external stop) → not a finish.
        XCTAssertFalse(CastManager.sonosStopIsNaturalFinish(
            position: 100.0, expectedDuration: 240.0, tolerance: tolerance, locallyStopped: false))
    }

    func testLocallyStoppedNearEndIsNotFinish() {
        // Even at the very end, an app-initiated Stop in its grace window must not advance.
        XCTAssertFalse(CastManager.sonosStopIsNaturalFinish(
            position: 239.0, expectedDuration: 240.0, tolerance: tolerance, locallyStopped: true))
    }

    func testShortTrackStoppedNearStartIsNotFinish() {
        // 5s track stopped at t=1: within tolerance of the end numerically, but below the 50% floor.
        XCTAssertFalse(CastManager.sonosStopIsNaturalFinish(
            position: 1.0, expectedDuration: 5.0, tolerance: tolerance, locallyStopped: false))
    }

    func testShortTrackStoppedNearEndIsFinish() {
        // Same 5s track stopped at t=5 (its true end) → past the 50% floor → natural finish.
        XCTAssertTrue(CastManager.sonosStopIsNaturalFinish(
            position: 5.0, expectedDuration: 5.0, tolerance: tolerance, locallyStopped: false))
    }

    func testUnknownDurationIsNotFinish() {
        // expectedDuration == 0 (metadata unknown) → cannot classify as a finish.
        XCTAssertFalse(CastManager.sonosStopIsNaturalFinish(
            position: 0.0, expectedDuration: 0.0, tolerance: tolerance, locallyStopped: false))
    }

    func testExactlyAtDurationIsFinish() {
        XCTAssertTrue(CastManager.sonosStopIsNaturalFinish(
            position: 240.0, expectedDuration: 240.0, tolerance: tolerance, locallyStopped: false))
    }
}
