import CoreGraphics

/// Where a playlist puts a row it scrolls to. Every skin family's playlist follows the playing track
/// through this one rule: the least scroll that brings the row on screen, or — under shuffle, where
/// the next track can land anywhere — the row centred, whether or not it was already visible.
enum PlayingRowPlacement {
    case edge
    case centre

    init(shuffle: Bool) { self = shuffle ? .centre : .edge }

    /// The new scroll offset, clamped into the content. Units are the caller's: points for the
    /// Classic and Original playlists, rows (`itemHeight` 1) for the `.wal` and `.wmz` ones.
    func offset(itemTop: CGFloat, itemHeight: CGFloat, viewport: CGFloat,
                current: CGFloat, contentHeight: CGFloat) -> CGFloat {
        var offset = current
        switch self {
        case .centre:
            offset = itemTop - (viewport - itemHeight) / 2
        case .edge:
            if itemTop < current { offset = itemTop }
            else if itemTop + itemHeight > current + viewport { offset = itemTop + itemHeight - viewport }
        }
        return max(0, min(max(0, contentHeight - viewport), offset))
    }

    /// `offset` in whole rows, for the playlists that scroll a row at a time.
    func firstRow(showing row: Int, visibleRows: Int, firstRow: Int, rowCount: Int) -> Int {
        Int(offset(itemTop: CGFloat(row), itemHeight: 1, viewport: CGFloat(visibleRows),
                   current: CGFloat(firstRow), contentHeight: CGFloat(rowCount)).rounded(.down))
    }
}
