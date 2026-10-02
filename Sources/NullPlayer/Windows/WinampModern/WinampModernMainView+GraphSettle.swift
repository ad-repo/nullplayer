import AppKit

/// The scene readers a script's graph write owes a `.wal` window, run once at the end of the runloop
/// turn rather than once per write.
///
/// A graph write's cheap half — dropping the rect caches, asking for layout and display — stays
/// synchronous: it is idempotent, and later code in the same turn reads those caches. The half that
/// walks the scene is deferred, because a skin's scripts write the graph hundreds of times while they
/// load, and the shadow gate's fingerprint walk after every write was a third of a skin switch. The
/// animation clock's check walks the same scene for as long as nothing in it animates, so it waits
/// too. Neither loses anything: the shadow pulls at most every `shadowShapeInterval`, and a clock
/// started one turn late is invisible at 30 Hz.
struct WinampModernGraphSettle: OptionSet {
    let rawValue: UInt8
    /// Start the repaint clock if the scene now has something that moves (`updateAnimationTimer`).
    static let animationClock = Self(rawValue: 1 << 0)
    /// Ask the shadow gate whether this window's outline moved (`graphMayHaveMovedShadowOutline`).
    static let shadowOutline = Self(rawValue: 1 << 1)
}

extension WinampModernMainView {
    func scheduleGraphSettle(_ work: WinampModernGraphSettle) {
        let isQueued = !pendingGraphSettle.isEmpty
        pendingGraphSettle.formUnion(work)
        guard !isQueued, !pendingGraphSettle.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let work = pendingGraphSettle
            pendingGraphSettle = []
            guard !isTornDown else { return }
            if work.contains(.animationClock) { updateAnimationTimer() }
            if work.contains(.shadowOutline) { graphMayHaveMovedShadowOutline() }
        }
    }
}
