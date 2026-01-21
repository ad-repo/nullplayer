import AppKit

/// Controller for the Plex browser window
class PlexBrowserWindowController: NSWindowController {
    
    // MARK: - Properties
    
    private var browserView: PlexBrowserView!
    
    /// Minimum window size (wider to fit 6 tabs)
    private static let minSize = NSSize(width: 480, height: 300)
    
    /// Default window size - height matches 3 stacked main windows (main + EQ + playlist)
    private static var defaultSize: NSSize {
        let height = Skin.mainWindowSize.height * 3  // Match combined height of 3 windows
        return NSSize(width: 550, height: height)
    }
    
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
        
        window.isMovableByWindowBackground = false  // Custom drag handling in PlexBrowserView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = Self.minSize
        window.title = "Plex Browser"
        
        // Initial center position - will be repositioned in showWindow()
        window.center()
        
        window.delegate = self
    }
    
    /// Position the window to the RIGHT of the main window
    private func positionWindow() {
        guard let window = window,
              let mainWindow = WindowManager.shared.mainWindowController?.window else { return }
        
        let mainFrame = mainWindow.frame
        var newX = mainFrame.maxX  // RIGHT of main
        let newY = mainFrame.maxY - window.frame.height  // Top-aligned
        
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
        // Position relative to main window's CURRENT location every time
        positionWindow()
        super.showWindow(sender)
        
        // Only refresh servers if we're linked, have no servers, and not already connecting
        // This prevents race conditions with the startup preload
        let plexManager = PlexManager.shared
        if plexManager.isLinked && plexManager.servers.isEmpty {
            if case .connecting = plexManager.connectionState {
                NSLog("PlexBrowserWindowController: Already connecting, skipping refresh")
            } else {
                Task {
                    do {
                        NSLog("PlexBrowserWindowController: No servers cached, refreshing...")
                        try await plexManager.refreshServers()
                        await MainActor.run {
                            self.browserView.reloadData()
                        }
                    } catch {
                        NSLog("PlexBrowserWindowController: Failed to refresh servers: %@", error.localizedDescription)
                    }
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
    func windowDidResize(_ notification: Notification) {
        browserView.needsDisplay = true
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        browserView.needsDisplay = true
    }
    
    func windowDidResignKey(_ notification: Notification) {
        browserView.needsDisplay = true
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
