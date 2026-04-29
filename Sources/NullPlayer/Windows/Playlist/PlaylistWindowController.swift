import AppKit

/// Controller for the playlist window (classic skin)
class PlaylistWindowController: NSWindowController, PlaylistWindowProviding {
    
    // MARK: - Properties
    
    private var playlistView: PlaylistView!
    
    /// Whether the window is in shade mode
    private(set) var isShadeMode = false
    
    /// Stored normal mode frame for restoration
    private var normalModeFrame: NSRect?
    
    /// Guard to prevent recursive resize callbacks while applying width snapping.
    private var isApplyingWidthSnap = false
    
    // MARK: - Initialization
    
    convenience init() {
        // Create borderless window with manual resize handling
        let window = ResizableWindow(
            contentRect: NSRect(origin: .zero, size: Skin.playlistMinSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        
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
        window.hasShadow = true
        window.title = "Playlist"
        
        // Match main window's width and position below it (or below EQ if visible)
        // Playlist can be expanded vertically to show more tracks
        if let mainWindow = WindowManager.shared.mainWindowController?.window {
            let mainFrame = mainWindow.frame
            let playlistHeight = Skin.playlistMinSize.height * WindowManager.shared.classicScaleMultiplier
            let playlistWidth = snappedPlaylistWidth(mainFrame.width)
            
            // Keep default width aligned to main, but allow horizontal stretching.
            window.minSize = NSSize(width: Skin.playlistMinSize.width, height: playlistHeight)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            
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
            window.minSize = Skin.playlistMinSize
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
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
        let playlistWidth = snappedPlaylistWidth(mainFrame.width)
        window.minSize = NSSize(width: Skin.playlistMinSize.width, height: playlistHeight)
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let newFrame = NSRect(
            x: mainFrame.minX,
            y: mainFrame.minY - playlistHeight,
            width: playlistWidth,
            height: playlistHeight
        )
        window.setFrame(newFrame, display: false)
    }
    
    /// Snap playlist width so PLEDIT title bar tiles align cleanly.
    /// In skin coordinates this enforces: width = (N * 25) + 50.
    private func snappedPlaylistWidth(_ width: CGFloat) -> CGFloat {
        let scaleFromMain = (WindowManager.shared.mainWindowController?.window?.frame.width ?? 0) / Skin.baseMainSize.width
        let scale = max(0.0001, scaleFromMain > 0 ? scaleFromMain : (Skin.scaleFactor * WindowManager.shared.classicScaleMultiplier))
        let minSkinWidth = SkinElements.Playlist.minSize.width
        let skinWidth = max(minSkinWidth, width / scale)
        let snappedTiles = round((skinWidth - 50.0) / 25.0)
        let snappedSkinWidth = max(minSkinWidth, 50.0 + snappedTiles * 25.0)
        return snappedSkinWidth * scale
    }
    
    // MARK: - Shade Mode
    
    /// Toggle shade mode on/off
    func setShadeMode(_ enabled: Bool) {
        guard let window = window else { return }
        
        isShadeMode = enabled
        
        if enabled {
            // Store current frame for restoration
            normalModeFrame = window.frame
            
            // Calculate new shade mode frame (keep width, reduce height)
            let shadeHeight = SkinElements.PlaylistShade.height
            let newFrame = NSRect(
                x: window.frame.origin.x,
                y: window.frame.origin.y + window.frame.height - shadeHeight,
                width: window.frame.width,
                height: shadeHeight
            )
            
            // Resize window
            window.setFrame(newFrame, display: true, animate: true)
            playlistView.frame = NSRect(origin: .zero, size: newFrame.size)
        } else {
            // Restore normal mode frame
            let newFrame: NSRect
            
            if let storedFrame = normalModeFrame {
                newFrame = storedFrame
            } else {
                let normalSize = Skin.playlistMinSize
                newFrame = NSRect(
                    x: window.frame.origin.x,
                    y: window.frame.origin.y + window.frame.height - normalSize.height,
                    width: window.frame.width,
                    height: normalSize.height
                )
            }
            
            // Resize window
            window.setFrame(newFrame, display: true, animate: true)
            playlistView.frame = NSRect(origin: .zero, size: newFrame.size)
            normalModeFrame = nil
        }
        
        playlistView.setShadeMode(enabled)
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
        
        if !isShadeMode && !isApplyingWidthSnap {
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
