import AppKit

extension NSCursor {
    /// The cursor for a window corner: the system's diagonal frame-resize cursor on macOS 15+,
    /// the crosshair before it, which ships no diagonal one (#601, #741).
    static func diagonalResize(top: Bool, left: Bool) -> NSCursor {
        guard #available(macOS 15, *) else { return .crosshair }
        let position: FrameResizePosition = top ? (left ? .topLeft : .topRight) : (left ? .bottomLeft : .bottomRight)
        return .frameResize(position: position, directions: .all)
    }
}
