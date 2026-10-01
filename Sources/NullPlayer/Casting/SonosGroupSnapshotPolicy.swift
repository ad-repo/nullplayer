import Foundation

/// Decides when a Sonos group volume send must first re-capture the room ratio.
///
/// Sonos `SetGroupVolume` scales each room from the ratio captured by the last
/// `SnapshotGroupVolume`, not from current levels, so a room changed on its own since then is put
/// back. Snapshot once per gesture (no group send for `gestureGap`), never per send: a snapshot
/// at 0 flattens the ratio, so a drag through 0 — or a pause there — must not take one.
struct SonosGroupSnapshotPolicy {
    static let gestureGap: TimeInterval = 1.5

    /// Set by a room's own volume write or a failed snapshot; survives an in-flight group send.
    private var stale = true
    private var lastSend: (key: String, percent: Int, at: Date)?

    /// The ratio may have changed: a room's own volume was written, or a snapshot failed.
    mutating func invalidate() {
        stale = true
    }

    /// True when a snapshot must precede the group send to `key`. Claims the snapshot, so an
    /// `invalidate()` that lands while it is in flight still forces the next one.
    mutating func claimSnapshot(key: String, now: Date) -> Bool {
        let needed: Bool
        if stale {
            needed = true
        } else if let lastSend, lastSend.key == key {
            needed = lastSend.percent != 0 && now.timeIntervalSince(lastSend.at) > Self.gestureGap
        } else {
            needed = true
        }
        if needed { stale = false }
        return needed
    }

    mutating func groupVolumeSent(key: String, percent: Int, at: Date) {
        lastSend = (key, percent, at)
    }
}
