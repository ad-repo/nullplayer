import Foundation

/// Coalesces Sonos/UPnP volume commands into a single-flight, latest-value-wins stream.
///
/// A fast volume-slider drag assigns `AudioEngine.volume` many times, each firing a detached
/// `Task { await CastManager.shared.setVolume(...) }`. Those SOAP requests take hundreds of
/// milliseconds each and can land at the speaker out of order, leaving it on a stale value
/// (GH #414). This type keeps at most one send outstanding; while it is in flight, newer
/// submits overwrite a single `pending` slot, so the loop only ever sends the newest value and
/// drops everything in between.
///
/// `@MainActor`-isolated so its mutable state is never raced by the multiple detached volume
/// tasks — matching how `CastManager` isolates its `inflight` serializer.
@MainActor
final class SonosVolumeCoalescer {
    /// The most recent value awaiting send; overwritten by newer submits while a send is in flight.
    private var pending: Int?
    /// True while the drain loop owns the single flight.
    private var inFlight = false
    /// Last value confirmed sent, keyed by device UDN, used to dedupe redundant sends.
    private var lastSent: (key: String, percent: Int)?

    /// Performs the actual send; returns true when the SOAP call succeeded.
    private let send: (Int) async -> Bool
    /// Identifies the active target (device UDN); nil when there is no session.
    private let currentKey: () -> String?

    /// `nonisolated` so it can be constructed from `CastManager`'s (non-MainActor) lazy property
    /// initializer; it only stores the injected closures and leaves state at its defaults.
    nonisolated init(send: @escaping (Int) async -> Bool, currentKey: @escaping () -> String?) {
        self.send = send
        self.currentKey = currentKey
    }

    /// Submit the latest desired volume percent (0–100). Coalesces with any in-flight send.
    func submit(_ percent: Int) async {
        pending = percent
        if inFlight { return }              // a drain loop is already running; it will pick up `pending`
        inFlight = true
        defer { inFlight = false }
        while let next = pending {
            pending = nil
            guard let key = currentKey() else { break }                       // no session → stop
            if lastSent?.key == key, lastSent?.percent == next { continue }    // equal-value dedupe
            if await send(next), currentKey() == key {                         // still same target after await?
                lastSent = (key, next)
            }
            // A failed send (or a target change mid-flight) leaves `lastSent` untouched, so the
            // next session's dedupe can't be poisoned by a stale completion.
        }
    }

    /// Clear all coalescer state. Call only on true teardown (device disconnect), not per-track.
    func reset() {
        pending = nil
        lastSent = nil
    }
}
