import AppKit

extension WinampModernMainView {
    /// The arrows in the skin's visualization window are that window's own, as in every
    /// visualization window (`VisualizationKey`): a parked film first, since it is what is on screen,
    /// then the visualization's preset (←/→) and engine (↑/↓) steps. Asked ahead of the main window's
    /// seek and volume, which every other window's arrows stay; a key both refuse falls through to
    /// `keyDown`'s later asks, which refuse it again.
    func visualizationWindowTakesArrow(_ event: NSEvent) -> Bool {
        guard (123...126).contains(event.keyCode),
              WinampModernContainerTopology.kind(of: renderer.container) == .visualization else { return false }
        return hostedVideoSurface?.handleKeyDown(event) == true
            || hostedVisualizationSurface?.handleKeyDown(event) == true
    }
}
