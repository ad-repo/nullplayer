import AppKit

/// Protocol abstracting the spectrum analyzer window.
/// Both the classic `SpectrumWindowController` and modern `ModernSpectrumWindowController`
/// conform to this protocol. `WindowManager` holds a reference to whichever is active,
/// allowing the rest of the app to be agnostic about which UI system is in use.
///
/// Follows the same pattern as `MainWindowProviding`.
protocol SpectrumWindowProviding: AnyObject {
    /// The underlying window
    var window: NSWindow? { get }
    
    /// Whether the window is in shade (compact) mode
    var isShadeMode: Bool { get }
    
    /// Show the window
    func showWindow(_ sender: Any?)
    
    /// Notify that the skin has changed and views should redraw
    func skinDidChange()
    
    /// Stop rendering when window is hidden via orderOut (saves CPU)
    func stopRenderingForHide()
    
    /// Toggle shade (compact) mode
    func setShadeMode(_ enabled: Bool)
}
