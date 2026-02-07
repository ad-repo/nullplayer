import AppKit

/// Protocol abstracting the playlist window.
/// Both the classic `PlaylistWindowController` and modern `ModernPlaylistWindowController`
/// conform to this protocol. `WindowManager` holds a reference to whichever is active,
/// allowing the rest of the app to be agnostic about which UI system is in use.
///
/// Follows the same pattern as `MainWindowProviding` and `SpectrumWindowProviding`.
protocol PlaylistWindowProviding: AnyObject {
    /// The underlying window
    var window: NSWindow? { get }
    
    /// Whether the window is in shade (compact) mode
    var isShadeMode: Bool { get }
    
    /// Show the window
    func showWindow(_ sender: Any?)
    
    /// Notify that the skin has changed and views should redraw
    func skinDidChange()
    
    /// Reload playlist data (called when tracks are added/removed/reordered)
    func reloadPlaylist()
    
    /// Toggle shade (compact) mode
    func setShadeMode(_ enabled: Bool)
}
