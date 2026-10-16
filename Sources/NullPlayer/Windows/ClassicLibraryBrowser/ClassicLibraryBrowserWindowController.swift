import AppKit

/// Controller for the Plex browser window (classic skin mode)
class ClassicLibraryBrowserWindowController: NSWindowController, LibraryBrowserWindowProviding {
    
    // MARK: - Properties
    
    private var browserView: ClassicLibraryBrowserView!
    /// The window's content: the browser over its Cava backdrop, as siblings
    /// so Cava repaints independently beneath the browser's translucent list.
    private var contentContainer: NSView!
    
    /// Minimum window size. Width floors at the center-stack width so the window can be sized to
    /// align cleanly when docked top/bottom in a center stack.
    private static let minSize = NSSize(width: SkinElements.SpectrumWindow.minSize.width, height: 300)
    
    /// Default window size - height matches 4 stacked main windows (main + EQ + playlist + spectrum)
    static var defaultSize: NSSize {
        let height = Skin.mainWindowSize.height * 4  // Match combined height of 4 windows
        return NSSize(width: 550, height: height)
    }
    

    // MARK: - Initialization
    
    convenience init() {
        // Create borderless window with manual resize handling
        let window = ResizableWindow(contentRect: NSRect(origin: .zero, size: Self.defaultSize))
        
        self.init(window: window)
        
        setupWindow()
        setupView()
    }
    
    // MARK: - Setup
    
    private func setupWindow() {
        guard let window = window else { return }
        
        window.isMovableByWindowBackground = false  // Custom drag handling in ClassicLibraryBrowserView
        
        // On non-Retina displays, use opaque window to prevent compositing artifacts
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        if backingScale < 1.5 {
            window.backgroundColor = .black
            window.isOpaque = true
        } else {
            window.backgroundColor = .clear
            window.isOpaque = false
        }
        window.hasSkinShadow = true
        window.minSize = Self.minSize
        window.title = "Plex Browser"
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        
        // Initial center position - will be repositioned in showWindow()
        window.center()
        
        window.delegate = self
        
        // Set accessibility identifier for UI testing
        window.setAccessibilityIdentifier("PlexBrowserWindow")
        window.setAccessibilityLabel("Plex Browser Window")
    }
    
    private func setupView() {
        browserView = ClassicLibraryBrowserView(frame: NSRect(origin: .zero, size: Self.defaultSize))
        browserView.controller = self
        browserView.autoresizingMask = [.width, .height]
        contentContainer = NSView(frame: browserView.frame)
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor
        contentContainer.addSubview(browserView)
        window?.contentView = contentContainer
    }
    
    /// Normal-mode frame for position memory.
    var frameForPositionMemory: NSRect? {
        guard let window else { return nil }
        return window.frame
    }
    
    // MARK: - Public Methods
    
    override func showWindow(_ sender: Any?) {
        // Positioning is WindowManager.showPlexBrowser's job, and it has already happened: restored,
        // remembered, or docked right of the stack. Re-docking here overwrote the remembered frame.
        super.showWindow(sender)
        
        // Only refresh servers if we're linked, have no servers, and not already connecting
        // This prevents race conditions with the startup preload
        let plexManager = PlexManager.shared
        if plexManager.isLinked && plexManager.servers.isEmpty {
            if case .connecting = plexManager.connectionState {
                NSLog("ClassicLibraryBrowserWindowController: Already connecting, skipping refresh")
            } else {
                Task {
                    do {
                        NSLog("ClassicLibraryBrowserWindowController: No servers cached, refreshing...")
                        try await plexManager.refreshServers()
                        await MainActor.run {
                            self.browserView.model.reloadData()
                        }
                    } catch {
                        NSLog("ClassicLibraryBrowserWindowController: Failed to refresh servers: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
                    }
                }
            }
        }
    }
    
    func skinDidChange() {
        browserView.skinDidChange()
    }

    /// Mode-dependent teardown: forward to the view so it cancels its in-flight tasks/timers
    /// before this controller is closed and niled for a UI reload.
    func prepareForUITeardown() {
        browserView?.prepareForUITeardown()
    }

    var libraryBackdropPresenter: CavaPresenter? {
        browserView.backdropPresenter
    }

    func refreshLibraryBackdrop() {
        browserView.refreshBackdrop()
    }

    func reloadData() {
        browserView.model.reloadData()
    }
    
    /// Current browse mode raw value for state save/restore
    var browseModeRawValue: Int {
        get { browserView.model.browseMode.rawValue }
        set { browserView.model.restoreBrowseMode(rawValue: newValue) }
    }
    
    /// Show the Plex link sheet
    func showLinkSheet() {
        guard let window = window else { return }
        
        let linkSheet = PlexLinkSheet()
        linkSheet.showAsSheet(from: window) { [weak self] success in
            if success {
                self?.browserView.model.reloadData()
            }
        }
    }
}

// MARK: - NSWindowDelegate

extension ClassicLibraryBrowserWindowController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        browserView.needsDisplay = true
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        browserView.needsDisplay = true
        // Bring all app windows to front when this window gets focus
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }
    
    func windowDidResignKey(_ notification: Notification) {
        browserView.needsDisplay = true
    }
    
    func windowWillClose(_ notification: Notification) {
        browserView.stopBackdrop()
        WindowManager.shared.rememberPlexBrowserFrameBeforeClose()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
