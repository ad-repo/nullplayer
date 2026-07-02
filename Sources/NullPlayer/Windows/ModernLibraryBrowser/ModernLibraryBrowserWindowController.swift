import AppKit

/// Controller for the library browser window (modern skin).
/// Conforms to `LibraryBrowserWindowProviding` so WindowManager can use it interchangeably
/// with the classic `PlexBrowserWindowController`.
///
/// This controller has ZERO dependencies on the classic skin system.
class ModernLibraryBrowserWindowController: NSWindowController, LibraryBrowserWindowProviding {
    
    // MARK: - Properties
    
    private var browserView: ModernLibraryBrowserView!
    
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
        window.titleBarHeight = ModernSkinElements.titleBarBaseHeight * ModernSkinElements.scaleFactor

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

    /// Mode-dependent teardown: forward to the view so it cancels its in-flight tasks/timers
    /// before this controller is closed and niled for a UI reload.
    func prepareForUITeardown() {
        browserView?.prepareForUITeardown()
    }

    func skinDidChange() {
        browserView.skinDidChange()
    }
    
    func reloadData() {
        browserView.reloadData()
    }
    
    /// Current browse mode raw value for state save/restore
    var browseModeRawValue: Int {
        get { browserView.browseModeRawValue }
        set { browserView.browseModeRawValue = newValue }
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
    
    /// Window frame for position memory across restart.
    var frameForPositionMemory: NSRect? {
        return window?.frame
    }

    // MARK: - Compact Mode

    /// Whether the browser is showing the embedded compact player bar.
    private(set) var isCompactMode = false

    /// Smallest width that keeps the tab labels inside their outlines. Used to floor the
    /// Compact Mode window so it never launches too thin.
    var minimumCompactContentWidth: CGFloat {
        browserView.minimumCompactContentWidth
    }

    /// Enable/disable Compact Mode. The full, resizable library window is kept; only the
    /// embedded player bar is toggled and the list/content region shifts to make room.
    func setCompactMode(_ enabled: Bool) {
        isCompactMode = enabled
        browserView.compactMode = enabled
        browserView.needsDisplay = true
    }

    func updateCompactBarTime(current: TimeInterval, duration: TimeInterval) {
        browserView.compactBarUpdateTime(current: current, duration: duration)
    }

    func updateCompactBarTrack(_ track: Track?) {
        browserView.compactBarUpdateTrack(track)
    }

    func updateCompactBarPlaybackState() {
        browserView.compactBarUpdatePlaybackState()
    }
}

// MARK: - NSWindowDelegate

extension ModernLibraryBrowserWindowController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        browserView.needsDisplay = true
        WindowManager.shared.postWindowLayoutDidChange()
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        let newOrigin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: newOrigin)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        browserView.needsDisplay = true
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }
    
    func windowDidResignKey(_ notification: Notification) {
        browserView.needsDisplay = true
    }
    
    func windowWillClose(_ notification: Notification) {
        WindowManager.shared.rememberPlexBrowserFrameBeforeClose()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }

    /// In Compact Mode the window is the app's only surface, so closing it just hides it
    /// (the status-bar item brings it back). Exiting Compact Mode is done from the menu.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isCompactMode {
            sender.orderOut(nil)
            WindowManager.shared.compactSurfaceDidHide()
            WindowManager.shared.notifyMainWindowVisibilityChanged()
            return false
        }
        return true
    }
}
