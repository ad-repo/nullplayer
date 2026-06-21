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
    
    /// Current browse mode raw value (artists, albums, playlists, movies, shows, search, radio, history).
    /// Used by AppStateManager to save/restore the active tab
    var browseModeRawValue: Int { get set }

    // MARK: - Compact Mode

    /// Smallest content width that keeps the window usable when launched in Compact Mode.
    var minimumCompactContentWidth: CGFloat { get }

    /// Enable/disable Compact Mode: embed a stripped-down player bar across the top of the
    /// browser window so it can act as the app's sole window in menu-bar (Compact) mode.
    func setCompactMode(_ enabled: Bool)

    /// Forward the engine's playback time to the embedded compact player bar.
    func updateCompactBarTime(current: TimeInterval, duration: TimeInterval)

    /// Forward the current track to the embedded compact player bar.
    func updateCompactBarTrack(_ track: Track?)

    /// Tell the embedded compact player bar that the playback state changed.
    func updateCompactBarPlaybackState()
}
