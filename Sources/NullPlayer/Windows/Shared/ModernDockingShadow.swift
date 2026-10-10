import AppKit

extension NSWindow {
    /// **An Original window's drop shadow, given what it is docked to.** A seamless-docking skin
    /// drops it while the window touches another, so the stack reads as one piece. `cornersChanged`
    /// pulls the outline again: docking squares or rounds a corner without resizing the window.
    ///
    /// Only the view that owns the window's shadow calls this. The same views are embedded in other
    /// windows — a backdrop in the Library, a surface in a `.wal` hosted window — whose shadow is
    /// not theirs, and the Compact Mode window keeps AppKit's.
    func applyDockingShadow(edges: AdjacentEdges, cornersChanged: Bool) {
        let seamless = (ModernSkinEngine.shared.currentSkin?.config.window.seamlessDocking ?? 0) > 0
        hasSkinShadow = !(seamless && !edges.isEmpty)
        if cornersChanged { invalidateSkinShadowShape("corners") }
    }
}
