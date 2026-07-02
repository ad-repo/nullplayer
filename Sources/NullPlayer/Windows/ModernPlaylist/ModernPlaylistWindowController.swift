import AppKit

/// Controller for the playlist window (modern skin).
/// Conforms to `PlaylistWindowProviding` so WindowManager can use it interchangeably
/// with the classic `PlaylistWindowController`.
///
/// This controller has ZERO dependencies on the classic skin system.
class ModernPlaylistWindowController: NSWindowController, PlaylistWindowProviding {
    
    // MARK: - Properties

    private var playlistView: ModernPlaylistView!
    
    // MARK: - Initialization
    
    convenience init() {
        let windowSize = ModernSkinElements.playlistWindowSize
        
        let window = BorderlessWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Enable vertical + horizontal stretching.
        window.allowedResizeEdges = [.bottom, .left, .right]
        
        self.init(window: window)
        
        setupWindow()
        setupView()
    }
    
    // MARK: - Setup
    
    private func setupWindow() {
        guard let window = window else { return }
        let windowSize = ModernSkinElements.playlistWindowSize
        
        // Disable automatic window dragging - we handle it manually in the view
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.title = "Playlist"
        
        // Prevent window from being released when closed - we reuse the same controller
        window.isReleasedWhenClosed = false
        
        window.minSize = NSSize(width: windowSize.width, height: windowSize.height)
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        // Initial center position - will be repositioned by WindowManager
        window.center()
        
        window.delegate = self
        
        // Enable mouse moved events for bottom-edge resize cursor
        window.acceptsMouseMovedEvents = true
        
        // Set accessibility identifier for UI testing
        window.setAccessibilityIdentifier("ModernPlaylistWindow")
        window.setAccessibilityLabel("Playlist Window")
    }
    
    private func setupView() {
        playlistView = ModernPlaylistView(frame: NSRect(origin: .zero, size: ModernSkinElements.playlistWindowSize))
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
    
}

// MARK: - NSWindowDelegate

extension ModernPlaylistWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }
    
    func windowDidResize(_ notification: Notification) {
        playlistView.needsDisplay = true
        WindowManager.shared.postWindowLayoutDidChange()
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        playlistView.needsDisplay = true
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }
    
    func windowDidResignKey(_ notification: Notification) {
        playlistView.needsDisplay = true
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
