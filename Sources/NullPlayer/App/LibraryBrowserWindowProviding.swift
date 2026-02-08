import AppKit

/// Protocol abstracting the library browser window.
/// Both the classic `PlexBrowserWindowController` and modern `ModernLibraryBrowserWindowController`
/// conform to this protocol. `WindowManager` holds a reference to whichever is active,
/// allowing the rest of the app to be agnostic about which UI system is in use.
///
/// Follows the same pattern as `MainWindowProviding`, `PlaylistWindowProviding`,
/// `EQWindowProviding`, and `SpectrumWindowProviding`.
protocol LibraryBrowserWindowProviding: AnyObject {
    /// The underlying window
    var window: NSWindow? { get }
    
    /// Whether the window is in shade (compact) mode
    var isShadeMode: Bool { get }
    
    /// Show the window
    func showWindow(_ sender: Any?)
    
    /// Notify that the skin has changed and views should redraw
    func skinDidChange()
    
    /// Toggle shade (compact) mode
    func setShadeMode(_ enabled: Bool)
    
    /// Reload browser data (called when source changes or servers refresh)
    func reloadData()
    
    /// Show the Plex account linking sheet
    func showLinkSheet()
}
