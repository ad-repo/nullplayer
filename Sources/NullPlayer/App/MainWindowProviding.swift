import AppKit

/// Protocol abstracting the main player window.
/// Both the classic `MainWindowController` and modern `ModernMainWindowController`
/// conform to this protocol. `WindowManager` holds a reference to whichever is active,
/// allowing the rest of the app to be agnostic about which UI system is in use.
protocol MainWindowProviding: ModeDependentWindow {
    /// The underlying window
    var window: NSWindow? { get }

    /// Whether the window is currently visible
    var isWindowVisible: Bool { get }

    /// Show the window
    func showWindow(_ sender: Any?)

    /// Update the displayed track info (title, artist, bitrate, etc.)
    func updateTrackInfo(_ track: Track?)

    /// Update video track info display
    func updateVideoTrackInfo(title: String, artworkTrack: Track?)

    /// Clear video track info and revert to audio display
    func clearVideoTrackInfo()

    /// Update the time display
    func updateTime(current: TimeInterval, duration: TimeInterval)

    /// Update playback state indicators (play/pause/stop)
    func updatePlaybackState()

    /// Feed spectrum analyzer data for visualization
    func updateSpectrum(_ levels: [Float])

    /// Notify that the skin has changed and views should redraw
    func skinDidChange()

    /// Notify that window visibility of sibling windows changed (for toggle button states)
    func windowVisibilityDidChange()

    /// Mark the window content as needing redraw
    func setNeedsDisplay()

    /// Constrain a frame restored from saved state to what this window can actually render.
    ///
    /// Classic and NullPlayer-modern main windows are fixed-size, so their saved frame is always
    /// valid. A `.wal` skin sizes itself from its own layout and is freely resizable between that
    /// layout's `minimum_*`/`maximum_*`, so a frame saved in another session (or another skin) can
    /// be smaller than anything the scene can draw. The saved top-left is always preserved.
    func clampRestoredFrame(_ frame: NSRect) -> NSRect

    /// The play queue changed. A skin that draws its own queue (`.wal`, `.wmz`) re-bases its
    /// selection onto the playing row and repaints, as the Classic and Modern playlists' `reloadData`
    /// do (M48). Classic, Original and Audion keep no queue here.
    func playlistContentDidChange()

    /// The queue's ∿ EQ profile row markers changed; the queue and its selection did not. A skin
    /// that draws its own queue repaints it.
    func playlistMarkersDidChange()
}

// MARK: - Default Implementations

extension MainWindowProviding {
    var isWindowVisible: Bool {
        window?.isVisible == true
    }

    func setNeedsDisplay() {
        window?.contentView?.needsDisplay = true
    }

    func clampRestoredFrame(_ frame: NSRect) -> NSRect { frame }

    func playlistContentDidChange() {}

    func playlistMarkersDidChange() {}
}

/// A main window whose size is its skin's own canvas (`.wal`, `.wmz`, an Audion face): UI Size
/// multiplies that canvas, not `Skin.mainWindowSize`. `WindowManager.applyDoubleSize` tells the
/// controller the scale, then sets the player's frame from `mainWindowSize(atScale:)`.
protocol SkinSizedMainWindow: MainWindowProviding {
    func applyUIScale(_ scale: CGFloat)
    /// The window size the skin wants at `scale`; nil when it cannot answer yet.
    func mainWindowSize(atScale scale: CGFloat) -> NSSize?
}

extension WinampModernMainWindowController: SkinSizedMainWindow {}
extension WMPMainWindowController: SkinSizedMainWindow {}

/// A main window that is one skin canvas and nothing else (`PlayerUIControllerFamily.isSingleCanvas`):
/// it loads the selected skin itself, and the skin decides its size, so a restored frame places only
/// its top-left. The family supplies its selection, its loader and what to show; choosing, reloading
/// and resetting the skin are shared.
protocol SingleCanvasMainWindow: NSWindowController, SkinSizedMainWindow {
    associatedtype Skin
    var skinLoad: SkinLoadTask { get }
    var skinSelection: SkinSelection { get }
    /// The skin on screen, nil while the family's fallback stands in.
    var loadedSkinURL: URL? { get }
    /// The colours NullPlayer's own windows wear beside the skin on screen.
    var surfaceStyle: SkinnedSurfaceStyle { get }
    /// `surfaceStyle` with no skin on screen, and with no window yet.
    static var unskinnedSurfaceStyle: SkinnedSurfaceStyle { get }
    /// The selected skin's location, nil when nothing is selected; throws when the selection is gone.
    func selectedSkinURL() throws -> URL?
    static func loadSkin(at url: URL) async throws -> Skin
    /// Shows `shown`, or with nil the family's fallback, saying why when `error` is set.
    func present(_ shown: (skin: Skin, url: URL)?, error: Error?)
}

extension SingleCanvasMainWindow {
    func restoreFrame(_ frame: NSRect) {
        guard frame != .zero, let window else { return }
        window.setFrameTopLeftPoint(NSPoint(x: frame.minX, y: frame.maxY))
    }

    /// Loads the saved selection off the main thread, or shows the family's fallback when there is
    /// none or it fails.
    func reloadSelectedSkin() {
        let url: URL?
        do {
            url = try selectedSkinURL()
        } catch {
            skinLoad.cancel()
            return present(nil, error: error)
        }
        guard let url else {
            skinLoad.cancel()
            return present(nil, error: nil)
        }
        skinLoad.run({ try await Self.loadSkin(at: url) },
                     done: { [weak self] skin in self?.present((skin, url), error: nil) },
                     failed: { [weak self] error in self?.present(nil, error: error) })
    }

    func selectSkin(named name: String) {
        skinSelection.select(name)
        reloadSelectedSkin()
    }

    func resetToUnskinned() {
        skinLoad.cancel()
        skinSelection.reset()
        present(nil, error: nil)
    }
}

extension AudionFaceMainWindowController: SingleCanvasMainWindow {}
extension SoniqueSkinMainWindowController: SingleCanvasMainWindow {}

/// A main window that draws the equaliser itself in every skin, so `WindowManager` routes every
/// Equalizer show and toggle to it and NullPlayer's EQ window never opens in its family.
protocol SkinDrawnEqualizer: MainWindowProviding {
    var isEqualizerShowing: Bool { get }
    /// `toggle` is an explicit toggle, which may switch the window's mode to reach the equaliser;
    /// false is a show on the restore path, which must not.
    func revealEqualizer(toggle: Bool)
}

extension SoniqueSkinMainWindowController: SkinDrawnEqualizer {}
