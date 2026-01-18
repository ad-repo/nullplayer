import AppKit

/// Controller for the Plex browser window
class PlexBrowserWindowController: NSWindowController {
    
    // MARK: - Properties
    
    private var browserView: PlexBrowserView!
    
    /// Minimum window size (wider to fit 6 tabs)
    private static let minSize = NSSize(width: 480, height: 300)
    
    /// Default window size
    private static let defaultSize = NSSize(width: 550, height: 450)
    
    /// Shade mode height
    private static let shadeHeight: CGFloat = 14
    
    /// Shade mode state
    private var isShadeMode = false
    
    /// Normal mode frame (stored when entering shade mode)
    private var normalModeFrame: NSRect?
    
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
    
    // MARK: - Shade Mode
    
    /// Set shade mode (called from view)
    func setShadeMode(_ enabled: Bool) {
        guard let window = window else { return }
        
        isShadeMode = enabled
        
        if enabled {
            // Store current frame before entering shade mode
            normalModeFrame = window.frame
            
            // Collapse to shade height
            let shadeFrame = NSRect(
                x: window.frame.minX,
                y: window.frame.maxY - Self.shadeHeight,
                width: window.frame.width,
                height: Self.shadeHeight
            )
            window.setFrame(shadeFrame, display: true, animate: true)
            window.minSize = NSSize(width: Self.minSize.width, height: Self.shadeHeight)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: Self.shadeHeight)
        } else {
            // Restore normal frame
            let normalFrame = normalModeFrame ?? NSRect(
                x: window.frame.minX,
                y: window.frame.maxY - Self.defaultSize.height,
                width: window.frame.width,
                height: Self.defaultSize.height
            )
            window.minSize = Self.minSize
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            window.setFrame(normalFrame, display: true, animate: true)
            normalModeFrame = nil
        }
        
        browserView.setShadeMode(enabled)
    }
    
    // MARK: - Public Methods
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        
        // Refresh servers when window is shown if we're linked but have no servers
        if PlexManager.shared.isLinked && PlexManager.shared.servers.isEmpty {
            Task {
                do {
                    NSLog("PlexBrowserWindowController: No servers cached, refreshing...")
                    try await PlexManager.shared.refreshServers()
                    await MainActor.run {
                        self.browserView.reloadData()
                    }
                } catch {
                    NSLog("PlexBrowserWindowController: Failed to refresh servers: %@", error.localizedDescription)
                }
            }
        }
    }
    
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
