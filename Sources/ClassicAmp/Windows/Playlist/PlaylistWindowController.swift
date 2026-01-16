import AppKit

/// Controller for the playlist window
class PlaylistWindowController: NSWindowController {
    
    // MARK: - Properties
    
    private var playlistView: PlaylistView!
    
    // MARK: - Initialization
    
    convenience init() {
        let window = NSWindow(
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
