import AppKit

extension NSRect {
    /// Bleeds the content rect back across any docked (joined) edge so no leftover
    /// background strip shows where the shared window border has been suppressed.
    /// Applies to every render style (classic flush docking, modern seamless docking,
    /// and metal's thin border) — see issue #364.
    func expandingThroughJoinedEdges(in bounds: NSRect,
                                     borderWidth: CGFloat,
                                     adjacentEdges: AdjacentEdges) -> NSRect {
        guard borderWidth > 0, !adjacentEdges.isEmpty else { return self }

        var rect = self
        if adjacentEdges.contains(.left) {
            let delta = rect.minX - bounds.minX
            rect.origin.x = bounds.minX
            rect.size.width += delta
        }
        if adjacentEdges.contains(.right) {
            rect.size.width = bounds.maxX - rect.minX
        }
        if adjacentEdges.contains(.bottom) {
            let delta = rect.minY - bounds.minY
            rect.origin.y = bounds.minY
            rect.size.height += delta
        }
        if adjacentEdges.contains(.top) {
            rect.size.height = bounds.maxY - rect.minY
        }
        return rect
    }
}
