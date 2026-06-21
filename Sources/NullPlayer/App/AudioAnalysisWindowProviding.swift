import AppKit

/// Protocol abstracting the audio analysis window.
/// Both modern and classic implementations conform to this protocol.
/// `WindowManager` holds a reference to whichever is active.
protocol AudioAnalysisWindowProviding: ModeDependentWindow {
    /// The underlying window
    var window: NSWindow? { get }

    /// Show the window
    func showWindow(_ sender: Any?)

    /// Notify that the skin has changed and views should redraw
    func skinDidChange()

    /// Stop rendering when window is hidden via orderOut (saves CPU)
    func stopRenderingForHide()
}
