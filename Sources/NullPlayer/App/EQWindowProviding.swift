import AppKit

/// Protocol abstracting the equalizer window.
/// Both the classic `EQWindowController` and modern `ModernEQWindowController`
/// conform to this protocol. `WindowManager` holds a reference to whichever is active,
/// allowing the rest of the app to be agnostic about which UI system is in use.
///
/// Follows the same pattern as `MainWindowProviding`, `PlaylistWindowProviding`,
/// and `SpectrumWindowProviding`.
protocol EQWindowProviding: ModeDependentWindow {
    /// The underlying window
    var window: NSWindow? { get }

    /// Show the window
    func showWindow(_ sender: Any?)

    /// Notify that the skin has changed and views should redraw
    func skinDidChange()
}
