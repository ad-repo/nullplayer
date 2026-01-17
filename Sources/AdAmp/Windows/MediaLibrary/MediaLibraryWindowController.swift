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
        
        // Position to the right of main window
        if let mainWindow = WindowManager.shared.mainWindowController?.window {
            let mainFrame = mainWindow.frame
            window.setFrameOrigin(NSPoint(x: mainFrame.maxX, y: mainFrame.minY - window.frame.height + mainFrame.height))
        } else {
            window.center()
        }
        
        window.delegate = self
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
        if newOrigin != window.frame.origin {
            window.setFrameOrigin(newOrigin)
        }
    }
    
    func windowDidResize(_ notification: Notification) {
        libraryView.needsDisplay = true
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
