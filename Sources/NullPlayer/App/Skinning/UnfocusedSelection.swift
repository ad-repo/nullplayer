import AppKit

/// How a NullPlayer-drawn list shows its selection while its window is not key (M54): dimmed, the way
/// a macOS list greys an unfocused selection, but in the skin's own colours, since no family except
/// `.wal` declares an inactive pair. Whether a list dims is `WindowManager.dimsSelection(isKey:)`.
enum UnfocusedSelection {
    /// How far an unfocused selection falls back toward an unselected row.
    static let dim: CGFloat = 0.5

    /// A selection fill at half strength. Over the list it composites to the fill blended halfway to
    /// whatever is behind it — the list colour, album art or the Cava backdrop alike — so no caller
    /// has to know its background.
    static func fill(_ fill: NSColor) -> NSColor {
        fill.withAlphaComponent(fill.alphaComponent * (1 - dim))
    }

    /// Selected-row text moved halfway back to the unselected row's colour.
    static func text(_ selected: NSColor, toward row: NSColor) -> NSColor {
        SkinnedSurfaceStyle.blend(selected, toward: row, by: dim)
    }
}
