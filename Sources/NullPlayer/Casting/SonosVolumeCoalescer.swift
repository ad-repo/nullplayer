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
    /// Incremented on reset so an older in-flight completion cannot restore cleared dedupe state.
    private var generation: UInt = 0

    /// Performs the actual send; returns true when the SOAP call succeeded.
    private let send: @MainActor (Int) async -> Bool
    /// Identifies the active target (device UDN); nil when there is no session.
    private let currentKey: @MainActor () -> String?

    init(send: @escaping @MainActor (Int) async -> Bool,
         currentKey: @escaping @MainActor () -> String?) {
        self.send = send
        self.currentKey = currentKey
    }

    /// Submit the latest desired volume percent (0–100). Coalesces with any in-flight send.
    func submit(_ percent: Int) async {
        NSLog("CastManager: [CLOCKDBG] volume submit=%d inFlight=%d", percent, inFlight ? 1 : 0)
        pending = percent
        if inFlight { return }              // a drain loop is already running; it will pick up `pending`
        inFlight = true
        defer { inFlight = false }
        while let next = pending {
            pending = nil
            guard let key = currentKey() else { break }                       // no session → stop
            if lastSent?.key == key, lastSent?.percent == next { continue }    // equal-value dedupe
            let sendGeneration = generation
            let t0 = Date()
            let ok = await send(next)
            NSLog("CastManager: [CLOCKDBG] volume send=%d ok=%d %.0fms", next, ok ? 1 : 0, Date().timeIntervalSince(t0) * 1000)
            if ok,
               generation == sendGeneration,
               currentKey() == key {                                           // still same session generation + target?
                lastSent = (key, next)
            }
            // A failed send, target change, or reset while in flight leaves `lastSent` untouched,
            // so the next session's dedupe can't be poisoned by a stale completion.
        }
    }

    /// Clear all coalescer state. Call only on true teardown (device disconnect), not per-track.
    func reset() {
        generation &+= 1
        pending = nil
        lastSent = nil
    }
}
