import AppKit

/// Controller for the library browser window (modern skin).
/// Conforms to `LibraryBrowserWindowProviding` so WindowManager can use it interchangeably
/// with the classic `PlexBrowserWindowController`.
///
/// This controller has ZERO dependencies on the classic skin system.
class ModernLibraryBrowserWindowController: NSWindowController, LibraryBrowserWindowProviding {
    
    // MARK: - Properties
    
    private var browserView: ModernLibraryBrowserView!
    
    /// Whether the window is in shade mode
    private(set) var isShadeMode = false
    
    /// Stored normal mode frame for restoration
    private var normalModeFrame: NSRect?
    
    // MARK: - Initialization
    
    convenience init() {
        let windowSize = ModernSkinElements.libraryDefaultSize
        
        let window = BorderlessWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Enable multi-edge resizing (all edges + corners)
        window.allowedResizeEdges = [.left, .right, .top, .bottom]
        
        self.init(window: window)
        
        setupWindow()
        setupView()
    }
    
    // MARK: - Setup
    
    private func setupWindow() {
        guard let window = window else { return }
        
        // Disable automatic window dragging - we handle it manually in the view
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.title = "Library Browser"
        
        // Prevent window from being released when closed - we reuse the same controller
        window.isReleasedWhenClosed = false
        
        // Resizable in all directions
        window.minSize = ModernSkinElements.libraryMinSize
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        // Allow fullscreen for art-only / visualizer mode
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        
        // Initial center position - will be repositioned by WindowManager
        window.center()
        
        window.delegate = self
        
        // Enable mouse moved events for edge resize cursors
        window.acceptsMouseMovedEvents = true
        
        // Set accessibility identifier for UI testing
        window.setAccessibilityIdentifier("ModernLibraryBrowserWindow")
        window.setAccessibilityLabel("Library Browser Window")
    }
    
    private func setupView() {
        browserView = ModernLibraryBrowserView(frame: NSRect(origin: .zero, size: ModernSkinElements.libraryDefaultSize))
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
    
    func showLinkSheet() {
        guard let window = window else { return }
        
        let linkSheet = PlexLinkSheet()
        linkSheet.showAsSheet(from: window) { [weak self] success in
            if success {
                self?.browserView.reloadData()
            }
        }
    }
    
    // MARK: - Shade Mode
    
    func setShadeMode(_ enabled: Bool) {
        guard let window = window else { return }
        
        isShadeMode = enabled
        
        if enabled {
            // Store current frame for restoration
            normalModeFrame = window.frame
            
            // Calculate new shade mode frame (keep width, reduce height)
            let shadeHeight = ModernSkinElements.libraryShadeHeight
            let newFrame = NSRect(
                x: window.frame.origin.x,
                y: window.frame.origin.y + window.frame.height - shadeHeight,
                width: window.frame.width,
                height: shadeHeight
            )
            
            // Lock size in shade mode
            window.minSize = NSSize(width: ModernSkinElements.libraryMinSize.width, height: shadeHeight)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: shadeHeight)
            
            // Resize window
            window.setFrame(newFrame, display: true, animate: true)
            browserView.frame = NSRect(origin: .zero, size: newFrame.size)
        } else {
            // Restore normal mode frame
            let newFrame: NSRect
            
            if let storedFrame = normalModeFrame {
                newFrame = storedFrame
            } else {
                let normalSize = ModernSkinElements.libraryDefaultSize
                newFrame = NSRect(
                    x: window.frame.origin.x,
                    y: window.frame.origin.y + window.frame.height - normalSize.height,
                    width: window.frame.width,
                    height: normalSize.height
                )
            }
            
            // Restore size constraints
            window.minSize = ModernSkinElements.libraryMinSize
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            
            // Resize window
            window.setFrame(newFrame, display: true, animate: true)
            browserView.frame = NSRect(origin: .zero, size: newFrame.size)
            normalModeFrame = nil
        }
        
        browserView.setShadeMode(enabled)
    }
}

// MARK: - NSWindowDelegate

extension ModernLibraryBrowserWindowController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        browserView.needsDisplay = true
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        browserView.needsDisplay = true
        WindowManager.shared.bringAllWindowsToFront()
    }
    
    func windowDidResignKey(_ notification: Notification) {
        browserView.needsDisplay = true
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
