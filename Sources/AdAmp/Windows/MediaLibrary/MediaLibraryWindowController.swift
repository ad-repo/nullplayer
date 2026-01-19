import AppKit

/// Controller for the media library window
class MediaLibraryWindowController: NSWindowController {
    
    // MARK: - Properties
    
    private var libraryView: MediaLibraryView!
    
    /// Minimum window size
    private static let minSize = NSSize(width: 400, height: 300)
    
    /// Default window size
    private static let defaultSize = NSSize(width: 500, height: 400)
    
    // MARK: - Initialization
    
    convenience init() {
        // Create borderless window with manual resize handling
        let window = ResizableWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
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
        
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = Self.minSize
        window.title = "Media Library"
        
        // Initial center position - will be repositioned in showWindow()
        window.center()
        
        window.delegate = self
    }
    
    // MARK: - Window Display
    
    override func showWindow(_ sender: Any?) {
        // Position relative to main window's CURRENT location every time
        positionWindow()
        super.showWindow(sender)
    }
    
    /// Position the window to the RIGHT of the main window, below Plex Browser if visible
    private func positionWindow() {
        guard let window = window,
              let mainWindow = WindowManager.shared.mainWindowController?.window else { return }
        
        let mainFrame = mainWindow.frame
        var newX = mainFrame.maxX  // RIGHT of main
        var newY = mainFrame.maxY - window.frame.height  // Top-aligned by default
        
        // If Plex Browser is visible, position below it
        if let plexFrame = WindowManager.shared.plexBrowserWindowFrame {
            newY = plexFrame.minY - window.frame.height
        }
        
        // Screen bounds check - don't go off right edge
        if let screen = mainWindow.screen ?? NSScreen.main {
            if newX + window.frame.width > screen.visibleFrame.maxX {
                // Fall back to left side if no room on right
                newX = mainFrame.minX - window.frame.width
            }
        }
        
        window.setFrameOrigin(NSPoint(x: newX, y: newY))
    }
    
    private func setupView() {
        libraryView = MediaLibraryView(frame: NSRect(origin: .zero, size: Self.defaultSize))
        libraryView.controller = self
        libraryView.autoresizingMask = [.width, .height]
        window?.contentView = libraryView
    }
    
    // MARK: - Public Methods
    
    func skinDidChange() {
        libraryView.skinDidChange()
    }
    
    func reloadLibrary() {
        libraryView.reloadData()
    }
}

// MARK: - NSWindowDelegate

extension MediaLibraryWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }
    
    func windowDidResize(_ notification: Notification) {
        libraryView.needsDisplay = true
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
