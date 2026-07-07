import AppKit

extension NSRect {
    func expandingThroughMetalJoinedEdges(in bounds: NSRect,
                                          borderWidth: CGFloat,
                                          adjacentEdges: AdjacentEdges) -> NSRect {
        guard ModernSkinEngine.shared.currentRenderStyle == .metal else { return self }
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
