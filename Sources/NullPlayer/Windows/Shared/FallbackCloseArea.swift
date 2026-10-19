import AppKit

/// The base window rule: **every window closes from its top-right corner.**
///
/// A skin that draws its own close keeps it. Where a window has none — an Original/Metal window
/// under Hide Title Bars or docked without its title bar, a `.wal` frame that declares no `CLOSE`
/// control — this square just inside the top-right corner stands in for it. Nothing is drawn; it is
/// only a hit target, and it outranks whatever content sits under it. See `ui-guide` § *Every window
/// closes*.
///
/// The hosted families' frames — a `.wmz` palette window, a `.wal` container in NullPlayer's glass
/// chrome — draw a close and keep `SkinnedSurfaceChrome.closeButtonRect`, flush in the corner where
/// that art paints its ×. This square is for the windows with no close art at all, so it sits clear
/// of the corner pixels a window cannot answer (`inset`).
enum FallbackCloseArea {
    /// Points along each side.
    static let size: CGFloat = 14
    /// Points in from the top and right edges. The outermost few points are not the window's to
    /// answer: a skin's rounded corner is transparent there, and the window server sends a press on a
    /// transparent pixel to the window behind; and AppKit takes a press that close to a `.resizable`
    /// borderless window's edge for its own resize loop.
    static let inset: CGFloat = 6

    static func rect(in bounds: NSRect, flipped: Bool) -> NSRect {
        NSRect(x: bounds.maxX - inset - size,
               y: flipped ? bounds.minY + inset : bounds.maxY - inset - size,
               width: size, height: size)
    }

    /// `point` in `view`'s own coordinates.
    static func contains(_ point: NSPoint, in view: NSView) -> Bool {
        rect(in: view.bounds, flipped: view.isFlipped).contains(point)
    }
}
