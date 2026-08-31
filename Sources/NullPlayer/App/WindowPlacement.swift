import AppKit

/// The single definition of "on screen" the whole app uses.
///
/// Every placement path in `WindowManager` used to carry its own idea of where a window may sit, and
/// they disagreed: the tiler let a column run off the right edge on purpose, the classic snap
/// measured against `screen.frame` rather than `visibleFrame`, and restore measured against nothing
/// at all. The result was windows that launched off screen with no visible way back — with a large
/// `.wal` skin the only escape was Snap To Default, and it often took several presses.
///
/// The rule these functions encode is the reversal that fixes it: **overlapping windows are
/// preferable to hidden ones.** A window on top of another is a nuisance; a window nobody can reach
/// is an unusable app.
///
/// Everything here is a pure function over `NSRect` — no `NSWindow`, no `NSScreen` lookup — so the
/// rule is directly unit-testable and every caller is provably applying the same one.
enum WindowPlacement {

    /// Is `frame`'s **top-left corner** inside any of `screens`?
    ///
    /// Reachability is defined on that corner alone, not on the whole frame or on its centre, for two
    /// reasons. It carries the title bar and the drag area in every mode, so a window whose top-left
    /// is visible can always be grabbed and pulled back by hand. And it leaves the classic habit of
    /// parking a window mostly past the bottom or right edge intact — that window is *placed*, not
    /// stranded, and a sweep that yanked it back would be the bug.
    static func isReachable(_ frame: NSRect, screens: [NSRect]) -> Bool {
        let corner = NSPoint(x: frame.minX, y: frame.maxY)
        return screens.contains { screen in
            // Not `screen.contains(corner)`: that is half-open on `maxY`, and a window snapped flush
            // to the top of the visible frame — where every rescue puts an oversized one — has
            // exactly `maxY == screen.maxY` and would be judged stranded forever. The bottom edge
            // stays exclusive for the opposite reason: a window whose top edge is the screen's
            // bottom edge has no visible height at all.
            corner.x >= screen.minX && corner.x < screen.maxX
                && corner.y > screen.minY && corner.y <= screen.maxY
        }
    }

    /// The visible frame a stranded `frame` should be rescued onto.
    ///
    /// Largest intersection first, so a window mostly on one display comes back to that display;
    /// nearest by centre distance when it intersects nothing, which is the case that matters — a
    /// frame saved on an unplugged monitor lands on whichever screen was closest to it; and the
    /// first screen as the last resort.
    static func hostScreen(for frame: NSRect, screens: [NSRect]) -> NSRect? {
        guard !screens.isEmpty else { return nil }

        var best: NSRect?
        var bestArea: CGFloat = 0
        for screen in screens {
            let overlap = screen.intersection(frame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        if let best { return best }

        return screens.min { a, b in
            distanceSquared(NSPoint(x: a.midX, y: a.midY), NSPoint(x: frame.midX, y: frame.midY))
                < distanceSquared(NSPoint(x: b.midX, y: b.midY), NSPoint(x: frame.midX, y: frame.midY))
        } ?? screens.first
    }

    /// `frame` moved so that it lies inside `visible`. **Never resized.**
    ///
    /// The size is not ours to change. A classic sub-window's size is pinned by `applyDoubleSize`
    /// (`minSize == maxSize`), and a `.wal` window's size *is* the skin — its layout is authored at
    /// that size and shrinking it tears the layout apart. So when the frame is larger than `visible`
    /// on an axis, that axis aligns to the visible top-left instead, because that is where the
    /// controls live: better to lose the bottom or the right of an oversized window than its title
    /// bar. Overlap with other windows is accepted, deliberately.
    static func rescued(_ frame: NSRect, into visible: NSRect) -> NSRect {
        var origin = frame.origin

        if frame.width > visible.width {
            origin.x = visible.minX
        } else {
            origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        }

        if frame.height > visible.height {
            // Top-aligned: `maxY` to the visible top, so the title bar survives.
            origin.y = visible.maxY - frame.height
        } else {
            origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }

        return NSRect(origin: origin, size: frame.size)
    }

    /// The one offset that brings a docked cluster back, given the `union` of its frames.
    ///
    /// A cluster is moved as a unit rather than window by window because per-window clamping is what
    /// would destroy the docking: two windows flush against each other, clamped independently against
    /// the same edge, end up overlapping instead of touching. One offset applied to every member
    /// preserves every relative position inside the group, which is the whole point of having docked
    /// them.
    ///
    /// Uses the same oversize rule as `rescued`: a cluster taller or wider than the screen anchors to
    /// the visible top-left.
    static func groupOffset(union: NSRect, into visible: NSRect) -> CGPoint {
        let target = rescued(union, into: visible)
        return CGPoint(x: target.minX - union.minX, y: target.minY - union.minY)
    }

    private static func distanceSquared(_ a: NSPoint, _ b: NSPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }
}
