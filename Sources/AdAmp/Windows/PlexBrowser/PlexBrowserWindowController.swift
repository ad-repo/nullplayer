import AppKit

/// Controller for the Plex browser window
class PlexBrowserWindowController: NSWindowController {
    
    // MARK: - Properties
    
    private var browserView: PlexBrowserView!
    
    /// Minimum window size (wider to fit 6 tabs)
    private static let minSize = NSSize(width: 480, height: 300)
    
    /// Default window size
    private static let defaultSize = NSSize(width: 550, height: 450)
    
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
        window.title = "Plex Browser"
        
        // Position to the right of main window or media library
        positionWindow()
        
        window.delegate = self
    }
    
    private func positionWindow() {
        guard let window = window else { return }
        
        // Try to position relative to main window
        if let mainWindow = WindowManager.shared.mainWindowController?.window {
            let mainFrame = mainWindow.frame
            window.setFrameOrigin(NSPoint(x: mainFrame.maxX, y: mainFrame.minY - window.frame.height + mainFrame.height))
        } else {
            window.center()
        }
    }
    
    private func setupView() {
        browserView = PlexBrowserView(frame: NSRect(origin: .zero, size: Self.defaultSize))
        browserView.controller = self
        browserView.autoresizingMask = [.width, .height]
        window?.contentView = browserView
    }
    
    // MARK: - Public Methods
    
    func skinDidChange() {
        browserView.skinDidChange()
    }
    
    func reloadData() {
        browserView.reloadData()
    }
    
    /// Show the Plex link sheet
    func showLinkSheet() {
        guard let window = window else { return }
        
        let linkSheet = PlexLinkSheet()
        linkSheet.showAsSheet(from: window) { [weak self] success in
            if success {
                self?.browserView.reloadData()
            }
        }
    }
    
    // MARK: - Access to Media Library Window Controller
    
    var mediaLibraryWindowController: MediaLibraryWindowController? {
        // This is a workaround - in real impl we'd get this from WindowManager
        return nil
    }
}

// MARK: - NSWindowDelegate

extension PlexBrowserWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        if newOrigin != window.frame.origin {
            window.setFrameOrigin(newOrigin)
        }
    }
    
    func windowDidResize(_ notification: Notification) {
        browserView.needsDisplay = true
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
