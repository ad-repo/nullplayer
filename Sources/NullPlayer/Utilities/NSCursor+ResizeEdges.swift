import AppKit

extension NSCursor {
    /// The cursor for a resize edge or corner, or nil when the point touches neither axis.
    static func resize(horizontal: Bool, vertical: Bool, top: Bool, left: Bool) -> NSCursor? {
        switch (horizontal, vertical) {
        case (true, true): return diagonalResize(top: top, left: left)
        case (true, false): return .resizeLeftRight
        case (false, true): return .resizeUpDown
        case (false, false): return nil
        }
    }

    /// The cursor for a window corner: the system's diagonal frame-resize cursor on macOS 15+,
    /// the crosshair before it, which ships no diagonal one (#601, #741).
    static func diagonalResize(top: Bool, left: Bool) -> NSCursor {
        guard #available(macOS 15, *) else { return .crosshair }
        let position: FrameResizePosition = top ? (left ? .topLeft : .topRight) : (left ? .bottomLeft : .bottomRight)
        return .frameResize(position: position, directions: .all)
    }
}

/// A view's own resize band: shows the resize cursor over it, and puts the arrow back only on
/// leaving it, so a cursor somebody else set (a control's cursor rect) is not stomped on.
struct ResizeCursorTracker {
    private var showing = false

    mutating func update(_ cursor: NSCursor?) {
        guard let cursor else { return exit() }
        cursor.set()
        showing = true
    }

    mutating func exit() {
        guard showing else { return }
        NSCursor.arrow.set()
        showing = false
    }
}
