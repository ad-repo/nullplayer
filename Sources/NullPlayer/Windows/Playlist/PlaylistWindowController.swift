import AppKit

/// Controller for the playlist window (classic skin)
class PlaylistWindowController: NSWindowController, PlaylistWindowProviding {
    
    // MARK: - Properties

    private var playlistView: PlaylistView!

    /// Guard to prevent recursive resize callbacks while applying width snapping.
    private var isApplyingWidthSnap = false
    
    // MARK: - Initialization
    
    convenience init() {
        // Create borderless window with manual resize handling
        let window = ResizableWindow(contentRect: NSRect(origin: .zero, size: Skin.playlistMinSize))
        
        self.init(window: window)
        
        setupWindow()
        setupView()
    }
    
    // MARK: - Setup
    
    private func setupWindow() {
        guard let window = window else { return }
        
        // Disable automatic window dragging - we handle it manually in the view
        // to support moving docked windows together
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasSkinShadow = true
        window.title = "Playlist"
        
        // Match main window's width and position below it (or below EQ if visible)
        // Playlist can be expanded vertically to show more tracks
        if let mainWindow = WindowManager.shared.mainWindowController?.window {
            let mainFrame = mainWindow.frame
            let playlistHeight = Skin.playlistMinSize.height * WindowManager.shared.classicScaleMultiplier
            let playlistWidth = snappedPlaylistWidth(WindowManager.shared.nativeWindowDefaultWidth)
            
            // Keep default width aligned to main, but allow horizontal stretching.
            applySizeLimits(minimumHeight: playlistHeight)
            
            // Check if EQ window is visible and position below it
            var positionY = mainFrame.minY - playlistHeight
            if let eqWindow = WindowManager.shared.equalizerWindowController?.window,
               eqWindow.isVisible {
                positionY = eqWindow.frame.minY - playlistHeight
            }
            
            let newFrame = NSRect(
                x: mainFrame.minX,
                y: positionY,
                width: playlistWidth,
                height: playlistHeight
            )
            window.setFrame(newFrame, display: true)
        } else {
            applySizeLimits(minimumHeight: Skin.playlistMinSize.height)
            window.center()
        }
        
        window.delegate = self
        
        // Set accessibility identifier for UI testing
        window.setAccessibilityIdentifier("PlaylistWindow")
        window.setAccessibilityLabel("Playlist Window")
    }
    
    private func setupView() {
        playlistView = PlaylistView(frame: NSRect(origin: .zero, size: Skin.playlistMinSize))
        playlistView.controller = self
        playlistView.autoresizingMask = [.width, .height]
        window?.contentView = playlistView
    }
    
    // MARK: - Public Methods
    
    func skinDidChange() {
        playlistView.skinDidChange()
    }
    
    func reloadPlaylist() {
        playlistView.reloadData()
    }

    func resetToDefaultFrame() {
        guard let window, let mainWindow = WindowManager.shared.mainWindowController?.window else { return }
        let mainFrame = mainWindow.frame
        let playlistHeight = Skin.playlistMinSize.height * WindowManager.shared.classicScaleMultiplier
        let playlistWidth = snappedPlaylistWidth(WindowManager.shared.nativeWindowDefaultWidth)
        applySizeLimits(minimumHeight: playlistHeight)
        let newFrame = NSRect(
            x: mainFrame.minX,
            y: mainFrame.minY - playlistHeight,
            width: playlistWidth,
            height: playlistHeight
        )
        window.setFrame(newFrame, display: false)
    }
    
    /// Beside an Audion face or a `.wmz` player the playlist wears the gloss frame
    /// (`SkinnedSurfaceChrome.hidesPaletteTitleBar`), with no PLEDIT tiles to step its width by, so it
    /// resizes freely: no 25-pixel step and no 275-pixel minimum, either of which keeps it off the
    /// player's own width. `.wal` wears that frame too, but only once its palette loads, after these
    /// limits are set, so it keeps the step until something re-applies them on that load.
    private static var hasFreeWidth: Bool {
        switch WindowManager.shared.runningControllerFamily {
        case .audion, .wmp: return true
        case .classic, .nullPlayerModern, .winampModern: return false
        }
    }

    /// The narrowest a free-width playlist goes. It must stay at or below the narrowest player it
    /// sits beside: the narrowest Audion face is 24 pt.
    private static let freeMinimumWidth: CGFloat = 24

    /// The playlist's minimum width: `stepped`, the PLEDIT minimum, wherever PLEDIT tiles are drawn.
    static func minimumWidth(stepped: CGFloat) -> CGFloat {
        hasFreeWidth ? freeMinimumWidth : stepped
    }

    private func applySizeLimits(minimumHeight: CGFloat) {
        window?.minSize = NSSize(width: Self.minimumWidth(stepped: Skin.playlistMinSize.width), height: minimumHeight)
        window?.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    /// Snap playlist width so PLEDIT title bar tiles align cleanly.
    /// In skin coordinates this enforces: width = (N * 25) + 50.
    private func snappedPlaylistWidth(_ width: CGFloat) -> CGFloat {
        if Self.hasFreeWidth { return width }
        let scale = max(0.0001, WindowManager.shared.playlistChromeScale)
        let minSkinWidth = SkinElements.Playlist.minSize.width
        let skinWidth = max(minSkinWidth, width / scale)
        let snappedTiles = round((skinWidth - 50.0) / 25.0)
        let snappedSkinWidth = max(minSkinWidth, 50.0 + snappedTiles * 25.0)
        return snappedSkinWidth * scale
    }
    
    
    // MARK: - Private Properties
    
    private var mainWindowController: MainWindowController? {
        return nil // Will be linked via WindowManager
    }
}

// MARK: - NSWindowDelegate

extension PlaylistWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }
    
    func windowDidResize(_ notification: Notification) {
        guard let window = window else { return }

        if !isApplyingWidthSnap {
            let snappedWidth = snappedPlaylistWidth(window.frame.width)
            if abs(snappedWidth - window.frame.width) > 0.25 {
                isApplyingWidthSnap = true
                var snappedFrame = window.frame
                snappedFrame.size.width = snappedWidth
                window.setFrame(snappedFrame, display: true, animate: false)
                isApplyingWidthSnap = false
            }
        }

        playlistView.needsDisplay = true
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        playlistView.needsDisplay = true
        // Bring all app windows to front when this window gets focus
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }

    func windowWillClose(_ notification: Notification) {
        if let window { WindowManager.shared.handleCenterStackWindowWillClose(window) }
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
