import XCTest
@testable import NullPlayer

/// Tests for `SonosGroupSnapshotPolicy` — when a Sonos group volume send must first re-capture
/// the room ratio (`SetGroupVolume` scales from the last `SnapshotGroupVolume`).
final class SonosGroupSnapshotPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    /// Claims a snapshot if needed, then records the send; returns whether it snapshotted.
    private func send(_ policy: inout SonosGroupSnapshotPolicy, _ percent: Int, at offset: TimeInterval,
                      key: String = "A") -> Bool {
        let now = t0 + offset
        let snapshot = policy.claimSnapshot(key: key, now: now)
        policy.groupVolumeSent(key: key, percent: percent, at: now)
        return snapshot
    }

    func testSnapshotsOnceAtStartOfGesture() {
        var policy = SonosGroupSnapshotPolicy()
        // Mid-drag snapshots would flatten the ratio once a drag reached 0.
        XCTAssertEqual([send(&policy, 40, at: 0), send(&policy, 45, at: 0.2), send(&policy, 0, at: 0.4),
                        send(&policy, 50, at: 0.6)], [true, false, false, false])
    }

    func testSnapshotsAgainAfterIdleGap() {
        var policy = SonosGroupSnapshotPolicy()
        _ = send(&policy, 40, at: 0)
        XCTAssertTrue(send(&policy, 45, at: 5))     // a room may have been changed in the Sonos app
    }

    func testNoSnapshotAfterPauseAtZero() {
        var policy = SonosGroupSnapshotPolicy()
        _ = send(&policy, 0, at: 0)
        XCTAssertFalse(send(&policy, 20, at: 5))    // a snapshot at 0 would flatten the ratio
    }

    func testRoomChangeForcesSnapshotWithinGesture() {
        var policy = SonosGroupSnapshotPolicy()
        _ = send(&policy, 40, at: 0)
        policy.invalidate()                         // Sonos Rooms slider wrote a room's own volume
        XCTAssertTrue(send(&policy, 45, at: 0.2))
    }

    func testRoomChangeDuringGroupSendIsNotLost() {
        var policy = SonosGroupSnapshotPolicy()
        XCTAssertTrue(policy.claimSnapshot(key: "A", now: t0))
        policy.invalidate()                         // room write lands while the group send is in flight
        policy.groupVolumeSent(key: "A", percent: 40, at: t0 + 0.1)
        XCTAssertTrue(send(&policy, 45, at: 0.2))
    }

    func testNewTargetSnapshotsWithinGap() {
        var policy = SonosGroupSnapshotPolicy()
        _ = send(&policy, 40, at: 0, key: "A")
        XCTAssertTrue(send(&policy, 40, at: 0.2, key: "B"))
    }
}
