import CoreGraphics

/// The state of one `<ColorThemes:List>` — which row the user has picked out, and how far down the
/// list is scrolled.
///
/// `<ColorThemes:List>` is Winamp's colour-theme picker: a plain list of the skin's `<gammaset>`
/// names. Six of the sixteen measured `.wal` skins ship one and it is an *unregistered* XUI tag, so
/// before Phase 32 it expanded to a leaf object with no bitmap — invisible to `isRenderable`,
/// rejected by `isInteractive`, and every one of those screens came up as an empty box.
///
/// The state is per **object**, not per renderer: a skin may put a list in its player *and* in a
/// standalone window (mmd3 does), and each keeps its own selection and scroll. It is deliberately a
/// value type with no reference to the graph — the renderer owns a dictionary keyed by
/// `WasabiObjectID`, exactly as it owns `playlistScrollOffset` for the embedded playlist.
///
/// Selection and *activation* are two different things here, as they are in Winamp: clicking a row
/// selects it, and the skin's `Switch` button (or a double-click) is what applies it. The renderer
/// draws the two differently, so "the one I am pointing at" and "the one the skin is wearing" stay
/// distinguishable.
struct WasabiColorThemeListState: Equatable {
    /// Row height in skin pixels. The same 12px the embedded playlist uses: no measured skin declares
    /// a row height on its list, and 12 is what Winamp's own list metrics come out at.
    static let rowHeight: CGFloat = 12

    /// The row the user has picked out. Not necessarily the applied theme.
    var selectedIndex = 0
    /// First visible row.
    var scrollOffset = 0
    /// Whether the first draw has already scrolled the applied theme into view. mmd3 has 83 themes
    /// and multipass 58, so a list that always opens at row 0 tells the user nothing about which one
    /// is currently on.
    private(set) var isSeeded = false

    static func visibleRowCount(in frame: CGRect) -> Int {
        max(0, Int(frame.height / rowHeight))
    }

    /// The row under a point, or nil when the point is outside the list or past its last row.
    func row(at point: CGPoint, in frame: CGRect, rowCount: Int) -> Int? {
        guard frame.contains(point), Self.rowHeight > 0 else { return nil }
        let row = Int((point.y - frame.minY) / Self.rowHeight) + scrollOffset
        return (0..<rowCount).contains(row) ? row : nil
    }

    mutating func scroll(byRows delta: Int, rowCount: Int, in frame: CGRect) {
        scrollOffset = Self.clampedOffset(scrollOffset + delta, rowCount: rowCount, in: frame)
    }

    /// Pick a row out, bringing it into view if it is not already.
    mutating func select(_ index: Int, rowCount: Int, in frame: CGRect) {
        guard rowCount > 0 else { return }
        selectedIndex = max(0, min(rowCount - 1, index))
        scrollIntoView(selectedIndex, rowCount: rowCount, in: frame)
    }

    /// The first draw: put the selection on the applied theme and scroll it into view, once.
    mutating func seed(activeIndex: Int, rowCount: Int, in frame: CGRect) {
        guard !isSeeded, rowCount > 0, Self.visibleRowCount(in: frame) > 0 else { return }
        isSeeded = true
        select(activeIndex, rowCount: rowCount, in: frame)
    }

    /// Follow a theme applied from somewhere else (the skin's own next/previous buttons, the host
    /// menu, a script) so the list never disagrees with the window it is sitting in.
    mutating func follow(activeIndex: Int, rowCount: Int, in frame: CGRect) {
        isSeeded = true
        select(activeIndex, rowCount: rowCount, in: frame)
    }

    mutating func scrollIntoView(_ index: Int, rowCount: Int, in frame: CGRect) {
        let visible = Self.visibleRowCount(in: frame)
        guard visible > 0 else { return }
        if index < scrollOffset {
            scrollOffset = index
        } else if index >= scrollOffset + visible {
            scrollOffset = index - visible + 1
        }
        scrollOffset = Self.clampedOffset(scrollOffset, rowCount: rowCount, in: frame)
    }

    static func clampedOffset(_ offset: Int, rowCount: Int, in frame: CGRect) -> Int {
        max(0, min(max(0, rowCount - visibleRowCount(in: frame)), offset))
    }
}
