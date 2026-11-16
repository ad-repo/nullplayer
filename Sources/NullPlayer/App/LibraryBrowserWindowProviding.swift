import AppKit

/// Protocol abstracting the library browser window.
/// Both `ClassicLibraryBrowserWindowController` and `ModernLibraryBrowserWindowController`
/// conform to this protocol. `WindowManager` holds a reference to whichever is active,
/// allowing the rest of the app to be agnostic about which UI system is in use.
///
/// Follows the same pattern as `MainWindowProviding`, `PlaylistWindowProviding`,
/// `EQWindowProviding`, and `SpectrumWindowProviding`.
/// A library browser that can show the Library Window backdrop: a library window, or a `.wal`
/// skin's embedded library. The defaults are for a host without one.
protocol LibraryBackdropHosting: AnyObject {
    var libraryBackdropPresenter: CavaPresenter? { get }
    /// Re-read the backdrop mode: show, restyle or remove the backdrop.
    func refreshLibraryBackdrop()
}

extension LibraryBackdropHosting {
    var libraryBackdropPresenter: CavaPresenter? { nil }
    func refreshLibraryBackdrop() {}
}

protocol LibraryBrowserWindowProviding: ModeDependentWindow, LibraryBackdropHosting {
    /// The underlying window
    var window: NSWindow? { get }

    /// Window frame for position memory across restart. nil if there is no window.
    var frameForPositionMemory: NSRect? { get }

    /// Show the window
    func showWindow(_ sender: Any?)

    /// Notify that the skin has changed and views should redraw
    func skinDidChange()

    /// Reload browser data (called when source changes or servers refresh)
    func reloadData()

    /// Show the Plex account linking sheet
    func showLinkSheet()

    /// Current browse mode raw value (artists, albums, playlists, movies, shows, search, radio, history).
    /// Used by AppStateManager to save/restore the active tab
    var browseModeRawValue: Int { get set }
}
