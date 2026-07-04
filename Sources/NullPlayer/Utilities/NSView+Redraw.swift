import AppKit

extension NSView {
    /// Recursively mark a view subtree for redraw so layer-backed skin views repaint
    /// immediately instead of showing stale cached contents.
    func markSubtreeForDisplayAndLayout() {
        needsDisplay = true
        needsLayout = true
        layer?.setNeedsDisplay()
        for subview in subviews {
            subview.markSubtreeForDisplayAndLayout()
        }
    }
}
