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

    func testLocalStopSurvivesPlayingPollThatRacedStopRequest() {
        var state = SonosLocalStopState()
        state.requestStop()

        state.observePlaying()

        XCTAssertTrue(state.suppressesNaturalFinish)
    }

    func testLocalStopSurvivesRepeatedStoppedPolls() {
        var state = SonosLocalStopState()
        state.requestStop()

        for _ in 0..<10 {
            state.observeStopped()
            XCTAssertTrue(state.suppressesNaturalFinish)
        }
    }

    func testPlayingAfterObservedStopClearsIntent() {
        var state = SonosLocalStopState()
        state.requestStop()
        state.observeStopped()

        state.observePlaying()

        XCTAssertFalse(state.suppressesNaturalFinish)
    }

    func testExplicitPlaybackResetClearsIntent() {
        var state = SonosLocalStopState()
        state.requestStop()

        state.clear()

        XCTAssertFalse(state.suppressesNaturalFinish)
    }

    func testPrematureStopAfterReproducedNearEndSeekIsFinish() {
        XCTAssertTrue(CastManager.sonosStopFollowsNearEndSeek(
            position: 372.6,
            expectedDuration: 389.8,
            seekTarget: 368.2,
            elapsedSinceSeek: 4.4,
            nearEndWindow: 30,
            stopGraceInterval: 12))
    }

    func testStopAfterSeekOutsideNearEndWindowIsNotFinish() {
        XCTAssertFalse(CastManager.sonosStopFollowsNearEndSeek(
            position: 360,
            expectedDuration: 400,
            seekTarget: 355,
            elapsedSinceSeek: 4,
            nearEndWindow: 30,
            stopGraceInterval: 12))
    }

    func testStopLongAfterNearEndSeekIsNotFinish() {
        XCTAssertFalse(CastManager.sonosStopFollowsNearEndSeek(
            position: 390,
            expectedDuration: 400,
            seekTarget: 385,
            elapsedSinceSeek: 13,
            nearEndWindow: 30,
            stopGraceInterval: 12))
    }

    func testStopBeforeSeekTargetIsObservedIsNotFinish() {
        XCTAssertFalse(CastManager.sonosStopFollowsNearEndSeek(
            position: 350,
            expectedDuration: 400,
            seekTarget: 385,
            elapsedSinceSeek: 4,
            nearEndWindow: 30,
            stopGraceInterval: 12))
    }

    func testShortTrackNearEndSeekRequiresHalfwayPoint() {
        XCTAssertFalse(CastManager.sonosStopFollowsNearEndSeek(
            position: 3,
            expectedDuration: 20,
            seekTarget: 2,
            elapsedSinceSeek: 2,
            nearEndWindow: 30,
            stopGraceInterval: 12))
        XCTAssertTrue(CastManager.sonosStopFollowsNearEndSeek(
            position: 16,
            expectedDuration: 20,
            seekTarget: 15,
            elapsedSinceSeek: 2,
            nearEndWindow: 30,
            stopGraceInterval: 12))
    }
}
