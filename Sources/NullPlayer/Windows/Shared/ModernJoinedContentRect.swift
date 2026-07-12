import AppKit

extension NSRect {
    /// Bleeds the content rect back across any adjacent docked (joined) edge so no leftover
    /// background strip shows where the shared window border has been suppressed.
    /// Applies to every render style (classic flush docking, modern seamless docking,
    /// and metal's thin border) — see issue #364.
    func expandingThroughJoinedEdges(in bounds: NSRect,
                                     borderWidth: CGFloat,
                                     adjacentEdges: AdjacentEdges) -> NSRect {
        guard borderWidth > 0, !adjacentEdges.isEmpty else { return self }

        // Only bridge the chrome/border strip immediately next to the content rect.
        // A visible title bar creates a much larger top gap; expanding through that
        // would let body content paint over the title bar and close button.
        let maximumJoinGap = borderWidth + 0.5
        var rect = self
        if adjacentEdges.contains(.left), rect.minX - bounds.minX <= maximumJoinGap {
            let delta = rect.minX - bounds.minX
            rect.origin.x = bounds.minX
            rect.size.width += delta
        }
        if adjacentEdges.contains(.right), bounds.maxX - rect.maxX <= maximumJoinGap {
            rect.size.width = bounds.maxX - rect.minX
        }
        if adjacentEdges.contains(.bottom), rect.minY - bounds.minY <= maximumJoinGap {
            let delta = rect.minY - bounds.minY
            rect.origin.y = bounds.minY
            rect.size.height += delta
        }
        if adjacentEdges.contains(.top), bounds.maxY - rect.maxY <= maximumJoinGap {
            rect.size.height = bounds.maxY - rect.minY
        }
        return rect
    }
}
