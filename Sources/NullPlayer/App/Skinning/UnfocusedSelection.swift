import AppKit

/// How a NullPlayer-drawn list shows its selection while its window is not key (M54): dimmed, the way
/// a macOS list greys an unfocused selection, but in the skin's own colours, since no family except
/// `.wal` declares an inactive pair.
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

    /// Whether a list in `window` dims its selection: every family but `.wal` does, while the window
    /// is not key. `.wal` takes the skin's own inactive pair from `hostedStyle(in:)` instead, and
    /// keeps its selection when the skin declares neither.
    static func dims(in window: NSWindow?) -> Bool {
        let isKey = window?.isKeyWindow ?? true
        switch WindowManager.shared.uiMode.controllerFamily {
        case .winampModern: return false
        case .classic, .nullPlayerModern, .wmp, .audion, .sonique: return !isKey
        }
    }

    /// `WindowManager.hostedSurfaceStyle` for a surface in `window`. An unfocused `.wal` fallback
    /// window takes the skin's own inactive selection pair (`WasabiPalette.unfocused()`), as the
    /// skin's embedded surfaces do through `rowPalette`; every other answer is unchanged.
    static func hostedStyle(in window: NSWindow?) -> SkinnedSurfaceStyle? {
        let isKey = window?.isKeyWindow ?? true
        let manager = WindowManager.shared
        guard !isKey, let palette = manager.winampModernPalette else { return manager.hostedSurfaceStyle }
        return WinampModernSurfaceStyle(palette: palette.unfocused())
    }
}
