import AppKit

/// Controller for the Plex browser window (classic skin mode)
class PlexBrowserWindowController: NSWindowController, LibraryBrowserWindowProviding {
    
    // MARK: - Properties
    
    private var browserView: PlexBrowserView!
    
    /// Minimum window size. Width floors at the center-stack width so the window can be sized to
    /// align cleanly when docked top/bottom in a center stack (Compact Mode keeps a tab-label
    /// content floor via `minimumCompactContentWidth`).
    private static let minSize = NSSize(width: SkinElements.SpectrumWindow.minSize.width, height: 300)
    
    /// Default window size - height matches 4 stacked main windows (main + EQ + playlist + spectrum)
    private static var defaultSize: NSSize {
        let height = Skin.mainWindowSize.height * 4  // Match combined height of 4 windows
        return NSSize(width: 550, height: height)
    }
    

    /// Compact Mode state. When active the browser view is wrapped in a container with an
    /// embedded `ClassicCompactPlayerBarView` pinned across the top.
    private(set) var isCompactMode = false
    private var compactBar: ClassicCompactPlayerBarView?
    private var compactContainer: ClassicCompactContainerView?
    private var compactFooter: ClassicCompactFooterView?
    private var compactPlaylist: PlaylistView?

    /// Persisted content choice for the compact window's Library|Playlist toggle. Shares the
    /// `compactContentMode` key with the modern library window so the choice is consistent
    /// across UI families (0 = library, 1 = playlist).
    private var compactShowsPlaylist: Bool {
        get { UserDefaults.standard.integer(forKey: "compactContentMode") == 1 }
        set { UserDefaults.standard.set(newValue ? 1 : 0, forKey: "compactContentMode") }
    }

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
        
        // On non-Retina displays, use opaque window to prevent compositing artifacts
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        if backingScale < 1.5 {
            window.backgroundColor = .black
            window.isOpaque = true
        } else {
            window.backgroundColor = .clear
            window.isOpaque = false
        }
        window.hasShadow = true
        window.minSize = Self.minSize
        window.title = "Plex Browser"
        window.collectionBehavior = [.fullScreenPrimary, .managed]  // Allow fullscreen for visualizer
        
        // Initial center position - will be repositioned in showWindow()
        window.center()
        
        window.delegate = self
        
        // Set accessibility identifier for UI testing
        window.setAccessibilityIdentifier("PlexBrowserWindow")
        window.setAccessibilityLabel("Plex Browser Window")
    }
    
    /// Position the window to the RIGHT of the main window
    /// Always positions on the right side, even if partially offscreen
    private func positionWindow() {
        guard let window = window,
              let mainWindow = WindowManager.shared.mainWindowController?.window else { return }
        
        let mainFrame = mainWindow.frame
        let newX = mainFrame.maxX  // Always RIGHT of main
        let newY = mainFrame.maxY - window.frame.height  // Top-aligned
        
        window.setFrameOrigin(NSPoint(x: newX, y: newY))
    }
    
    private func setupView() {
        browserView = PlexBrowserView(frame: NSRect(origin: .zero, size: Self.defaultSize))
        browserView.controller = self
        browserView.autoresizingMask = [.width, .height]
        window?.contentView = browserView
    }
    
    /// Normal-mode frame for position memory.
    var frameForPositionMemory: NSRect? {
        guard let window else { return nil }
        return window.frame
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
        compactBar?.skinDidChange()
        compactFooter?.skinDidChange()
        compactPlaylist?.needsDisplay = true
    }

    /// Mode-dependent teardown: forward to the view so it cancels its in-flight tasks/timers
    /// before this controller is closed and niled for a UI reload.
    func prepareForUITeardown() {
        browserView?.prepareForUITeardown()
    }

    // MARK: - Compact Mode

    /// Smallest content width to keep the window usable in Compact Mode.
    var minimumCompactContentWidth: CGFloat {
        max(Self.minSize.width, browserView.minimumCompactContentWidth)
    }

    /// Enable/disable Compact Mode. The full, resizable browser is kept; the browser view is
    /// wrapped in a container with an embedded classic player bar pinned across the top.
    func setCompactMode(_ enabled: Bool) {
        guard isCompactMode != enabled, let window = window else { return }
        isCompactMode = enabled

        if enabled {
            let size = browserView.frame.size
            // Tuck the browser's own "LIBRARY" title bar up behind the opaque player bar so it
            // disappears in this view; the player bar becomes the compact window's top chrome.
            let container = ClassicCompactContainerView(frame: NSRect(origin: .zero, size: size))
            container.autoresizingMask = [.width, .height]
            container.barHeight = ClassicCompactPlayerBarView.preferredHeight()
            container.footerHeight = ClassicCompactFooterView.preferredHeight()
            container.titleBarHeight = SkinElements.PlexBrowser.Layout.titleBarHeight

            browserView.autoresizingMask = []
            let bar = ClassicCompactPlayerBarView(frame: .zero)
            bar.autoresizingMask = []

            // Embedded play queue, shown in place of the browser in Playlist mode.
            let playlist = PlaylistView(frame: .zero)
            playlist.isEmbedded = true
            playlist.autoresizingMask = []
            container.playlistTitleInset = playlist.embeddedTopInset

            // Library | Playlist toggle footer across the bottom.
            let footer = ClassicCompactFooterView(frame: .zero)
            footer.autoresizingMask = []
            footer.onSelect = { [weak self] showPlaylist in
                self?.setCompactShowsPlaylist(showPlaylist)
            }

            container.addSubview(browserView)
            container.addSubview(playlist)
            container.addSubview(bar)
            container.addSubview(footer)
            container.browser = browserView
            container.playlist = playlist
            container.playerBar = bar
            container.footer = footer
            window.contentView = container
            container.layoutChildren()
            // Initialize selection and scroll only after layout establishes the final list area.
            playlist.reloadData()

            compactContainer = container
            compactBar = bar
            compactFooter = footer
            compactPlaylist = playlist
            seedCompactBar(bar)
            applyCompactContentMode()
        } else {
            let size = (window.contentView?.frame.size) ?? browserView.frame.size
            compactBar?.removeFromSuperview()
            compactFooter?.removeFromSuperview()
            compactPlaylist?.removeFromSuperview()
            compactBar = nil
            compactFooter = nil
            compactPlaylist = nil
            compactContainer = nil
            browserView.isHidden = false
            browserView.frame = NSRect(origin: .zero, size: size)
            browserView.autoresizingMask = [.width, .height]
            window.contentView = browserView
        }
        browserView.needsDisplay = true
    }

    /// Flip the compact window between the library browser and the embedded play queue,
    /// persisting the choice, then apply the new visibility.
    private func setCompactShowsPlaylist(_ showPlaylist: Bool) {
        guard compactShowsPlaylist != showPlaylist else { return }
        compactShowsPlaylist = showPlaylist
        applyCompactContentMode()
    }

    /// Show the browser XOR the embedded playlist to match the persisted mode, and hand
    /// keyboard focus to whichever view is now visible.
    private func applyCompactContentMode() {
        let showPlaylist = compactShowsPlaylist
        compactFooter?.showingPlaylist = showPlaylist
        browserView.isHidden = showPlaylist
        compactPlaylist?.isHidden = !showPlaylist
        compactPlaylist?.needsDisplay = true
        browserView.needsDisplay = true
        if let target: NSView = showPlaylist ? compactPlaylist : browserView {
            window?.makeFirstResponder(target)
        }
    }

    /// Seed the bar with the engine's current state so it isn't blank until the next tick.
    private func seedCompactBar(_ bar: ClassicCompactPlayerBarView) {
        let engine = WindowManager.shared.audioEngine
        bar.updateTrackInfo(engine.currentTrack)
        bar.updateTime(current: engine.currentTime, duration: engine.duration)
        bar.updatePlaybackState()
    }

    func updateCompactBarTime(current: TimeInterval, duration: TimeInterval) {
        compactBar?.updateTime(current: current, duration: duration)
    }

    func updateCompactBarTrack(_ track: Track?) {
        compactBar?.updateTrackInfo(track)
    }

    func updateCompactBarPlaybackState() {
        compactBar?.updatePlaybackState()
    }

    func reloadCompactPlaylist() {
        compactPlaylist?.reloadData()
    }
    
    func reloadData() {
        browserView.reloadData()
    }
    
    /// Current browse mode raw value for state save/restore
    var browseModeRawValue: Int {
        get { browserView.browseModeRawValue }
        set { browserView.browseModeRawValue = newValue }
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
}

// MARK: - NSWindowDelegate

extension PlexBrowserWindowController: NSWindowDelegate {
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
        WindowManager.shared.rememberPlexBrowserFrameBeforeClose()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }

    /// In Compact Mode this window is the app's only surface, so closing it just hides it
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
