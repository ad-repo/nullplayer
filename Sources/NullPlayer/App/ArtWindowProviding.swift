import AppKit

/// The Art window (the playing track's cover, rating and VIS effects). The classic and modern
/// controllers conform so `WindowManager` can manage either without knowing the UI mode.
protocol ArtWindowProviding: ModeDependentWindow {
    var window: NSWindow? { get }
    var isFullscreen: Bool { get }
    func showWindow(_ sender: Any?)
    func skinDidChange()
    func toggleFullscreen()
    /// Stop the VIS timers and the spectrum feed.
    func tearDown()
}

extension ArtWindowProviding {
    func prepareForUITeardown() { tearDown() }
}
