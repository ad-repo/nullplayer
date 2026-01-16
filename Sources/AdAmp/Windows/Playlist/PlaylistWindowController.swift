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
        let window = ResizableWindow(
            contentRect: NSRect(origin: .zero, size: Skin.playlistMinSize),
            styleMask: [.borderless],
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
        
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = Skin.playlistMinSize
        window.title = "Playlist"
        
        // Position below main window
        if let mainWindow = WindowManager.shared.mainWindowController?.window {
            let mainFrame = mainWindow.frame
            window.setFrameOrigin(NSPoint(x: mainFrame.minX, y: mainFrame.minY - window.frame.height))
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
        
        // Enable/disable resizing via our custom window
        if let resizableWindow = window as? ResizableWindow {
            resizableWindow.resizingEnabled = !enabled
        }
        
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
        if newOrigin != window.frame.origin {
            window.setFrameOrigin(newOrigin)
        }
    }
    
    func windowDidResize(_ notification: Notification) {
        playlistView.needsDisplay = true
    }

    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
