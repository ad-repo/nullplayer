import AppKit

/// A pane view that renders on its own clock (a display link, a paced `MTKView`) and must stop while
/// its Analyzer window is hidden, minimized or closed.
protocol AudioAnalysisPausableRenderer: NSView {
    func setRenderingPaused(_ paused: Bool)
}

extension NSView {
    /// Pause or resume every `AudioAnalysisPausableRenderer` in this view's subtree. Both Analyzer
    /// windows call it on hide and show, so a new self-clocked pane only has to conform.
    func setAudioAnalysisRenderingPaused(_ paused: Bool) {
        (self as? AudioAnalysisPausableRenderer)?.setRenderingPaused(paused)
        subviews.forEach { $0.setAudioAnalysisRenderingPaused(paused) }
    }
}
