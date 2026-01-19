import AppKit

/// Controller for the playlist window
class PlaylistWindowController: NSWindowController {
    
    // MARK: - Properties
    
    private var playlistView: PlaylistView!
    
    /// Whether the window is in shade mode
    private(set) var isShadeMode = false
    
    /// Stored normal mode frame for restoration
    private var normalModeFrame: NSRect?
    
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
        window.minSize = Skin.playlistMinSize
        window.title = "Playlist"
        
        // Match main window's width and position below it (or below EQ if visible)
        if let mainWindow = WindowManager.shared.mainWindowController?.window {
            let mainFrame = mainWindow.frame
            let scale = mainFrame.width / Skin.mainWindowSize.width
            // Use same width as main window to match scaling
            let playlistHeight = Skin.playlistMinSize.height * scale
            
            // Check if EQ window is visible and position below it
            var positionY = mainFrame.minY - playlistHeight
            if let eqWindow = WindowManager.shared.equalizerWindowController?.window,
               eqWindow.isVisible {
                positionY = eqWindow.frame.minY - playlistHeight
            }
            
            let newFrame = NSRect(
                x: mainFrame.minX,
                y: positionY,
                width: mainFrame.width,
                height: playlistHeight
            )
            window.setFrame(newFrame, display: true)
        } else {
            window.center()
        }
        
        window.delegate = self
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
        playlistView.needsDisplay = true
    }

    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
