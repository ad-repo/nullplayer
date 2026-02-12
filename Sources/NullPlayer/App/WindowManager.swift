import AppKit

// MARK: - Notifications

extension Notification.Name {
    static let timeDisplayModeDidChange = Notification.Name("timeDisplayModeDidChange")
    static let doubleSizeDidChange = Notification.Name("doubleSizeDidChange")
}

// MARK: - Time Display Mode

enum TimeDisplayMode: String {
    case elapsed
    case remaining
}

/// Manages all application windows and their interactions
/// Handles window docking, snapping, and coordinated movement
class WindowManager {
    
    // MARK: - Singleton
    
    static let shared = WindowManager()
    
    // MARK: - Properties
    
    /// The audio engine instance
    let audioEngine = AudioEngine()
    
    /// The currently loaded skin
    private(set) var currentSkin: Skin?
    
    /// Path to the currently loaded custom skin (nil if using a base skin)
    private(set) var currentSkinPath: String?
    
    
    // MARK: - User Preferences
    
    /// Time display mode (elapsed vs remaining)
    var timeDisplayMode: TimeDisplayMode = .elapsed {
        didSet {
            UserDefaults.standard.set(timeDisplayMode.rawValue, forKey: "timeDisplayMode")
            NotificationCenter.default.post(name: .timeDisplayModeDidChange, object: nil)
        }
    }
    
    /// Double size mode (2x scaling) - not persisted, always starts at 1x (modern UI only)
    var isDoubleSize: Bool = false {
        didSet {
            guard isModernUIEnabled else { isDoubleSize = false; return }
            applyDoubleSize()
            NotificationCenter.default.post(name: .doubleSizeDidChange, object: nil)
        }
    }
    
    /// Always on top mode (floating window level)
    var isAlwaysOnTop: Bool = false {
        didSet {
            UserDefaults.standard.set(isAlwaysOnTop, forKey: "isAlwaysOnTop")
            NSLog("WindowManager: isAlwaysOnTop changed to %d, applying to windows", isAlwaysOnTop ? 1 : 0)
            applyAlwaysOnTop()
        }
    }
    
    /// Main player window controller (classic or modern, accessed via protocol)
    private(set) var mainWindowController: MainWindowProviding?
    
    /// Whether the modern UI is enabled (requires restart to take effect)
    var isModernUIEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "modernUIEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "modernUIEnabled") }
    }
    
    /// Whether title bars are hidden on all windows (only applies in modern UI mode)
    var hideTitleBars: Bool {
        get { isModernUIEnabled && UserDefaults.standard.bool(forKey: "hideTitleBars") }
        set { UserDefaults.standard.set(newValue, forKey: "hideTitleBars") }
    }
    
    /// Toggle hide title bars mode and resize all visible windows (modern UI only)
    func toggleHideTitleBars() {
        guard isModernUIEnabled else { return }
        let wasHidden = hideTitleBars
        hideTitleBars = !wasHidden
        let hiding = !wasHidden
        
        // Build ordered list of stack windows (top to bottom) with their deltas
        let stackEntries: [(NSWindowController?, CGFloat)] = [
            (mainWindowController as? NSWindowController, isModernUIEnabled ? ModernSkinElements.playlistTitleBarHeight : 14 * Skin.scaleFactor),
            (equalizerWindowController as? NSWindowController, isModernUIEnabled ? ModernSkinElements.eqTitleBarHeight : 14 * Skin.scaleFactor),
            (playlistWindowController as? NSWindowController, isModernUIEnabled ? ModernSkinElements.playlistTitleBarHeight : 20 * Skin.scaleFactor),
            (spectrumWindowController as? NSWindowController, isModernUIEnabled ? ModernSkinElements.spectrumTitleBarHeight : 14 * Skin.scaleFactor),
        ]
        
        // Get visible stack windows sorted top-to-bottom by their current frame
        var visibleStack: [(NSWindow, CGFloat)] = []
        for (controller, delta) in stackEntries {
            if let w = controller?.window, w.isVisible {
                visibleStack.append((w, delta))
            }
        }
        visibleStack.sort { $0.0.frame.maxY > $1.0.frame.maxY }
        
        // Process stack windows keeping the main window's top edge fixed.
        // Track cumulative shift so each window below accommodates the growth/shrink of windows above.
        if let first = visibleStack.first {
            let topEdge = first.0.frame.maxY  // Pin this
            var nextTop = topEdge
            
            for (w, delta) in visibleStack {
                adjustWindowSizeConstraints(w, delta: delta, hiding: hiding)
                
                var newHeight = w.frame.height
                if hiding {
                    newHeight -= delta
                } else {
                    newHeight += delta
                }
                let newY = nextTop - newHeight
                w.setFrame(NSRect(x: w.frame.origin.x, y: newY, width: w.frame.width, height: newHeight), display: false)
                w.contentView?.needsDisplay = true
                nextTop = newY  // Next window's top = this window's bottom
            }
        }
        
        // Side windows: match the new stack height
        let stackBounds = verticalStackBounds()
        let sideWindowControllers: [(NSWindowController?, CGFloat)] = [
            (projectMWindowController as? NSWindowController, isModernUIEnabled ? ModernSkinElements.projectMTitleBarHeight : 20 * Skin.scaleFactor),
            (plexBrowserWindowController as? NSWindowController, isModernUIEnabled ? ModernSkinElements.libraryTitleBarHeight : 20 * Skin.scaleFactor),
        ]
        
        for (controller, delta) in sideWindowControllers {
            guard let w = controller?.window, w.isVisible else { continue }
            adjustWindowSizeConstraints(w, delta: delta, hiding: hiding)
            
            if stackBounds != .zero {
                // Match stack height and alignment
                var frame = w.frame
                frame.origin.y = stackBounds.minY
                frame.size.height = stackBounds.height
                w.setFrame(frame, display: false)
            }
            w.contentView?.needsDisplay = true
        }
    }
    
    /// Adjust a window's minSize/maxSize constraints for title bar hide/show
    private func adjustWindowSizeConstraints(_ window: NSWindow, delta: CGFloat, hiding: Bool) {
        var minSize = window.minSize
        if hiding {
            minSize.height = max(0, minSize.height - delta)
        } else {
            minSize.height += delta
        }
        window.minSize = minSize
        if window.maxSize.height < CGFloat.greatestFiniteMagnitude {
            var maxSize = window.maxSize
            if hiding {
                maxSize.height = max(0, maxSize.height - delta)
            } else {
                maxSize.height += delta
            }
            window.maxSize = maxSize
        }
    }
    
    /// Adjust a window's frame for hidden title bars (shrink by title bar height, pin top edge).
    /// Call after creating a window when hideTitleBars is already true.
    func adjustWindowForHiddenTitleBars(_ window: NSWindow, titleBarHeight: CGFloat) {
        guard hideTitleBars else { return }
        // Relax size constraints so the window can shrink
        var minSize = window.minSize
        minSize.height = max(0, minSize.height - titleBarHeight)
        window.minSize = minSize
        if window.maxSize.height < CGFloat.greatestFiniteMagnitude {
            var maxSize = window.maxSize
            maxSize.height = max(0, maxSize.height - titleBarHeight)
            window.maxSize = maxSize
        }
        var frame = window.frame
        frame.origin.y += titleBarHeight
        frame.size.height -= titleBarHeight
        window.setFrame(frame, display: false)
    }
    
    /// Playlist window controller (classic or modern, accessed via protocol)
    private(set) var playlistWindowController: PlaylistWindowProviding?
    
    /// Equalizer window controller (classic or modern, accessed via protocol)
    private(set) var equalizerWindowController: EQWindowProviding?
    
    /// Library browser window controller (classic or modern, accessed via protocol)
    private var plexBrowserWindowController: LibraryBrowserWindowProviding?
    
    /// Video player window controller
    private var videoPlayerWindowController: VideoPlayerWindowController?
    
    /// ProjectM visualization window controller (classic or modern, accessed via protocol)
    private var projectMWindowController: ProjectMWindowProviding?
    
    /// Spectrum analyzer window controller (classic or modern, accessed via protocol)
    private var spectrumWindowController: SpectrumWindowProviding?
    
    /// Debug console window controller
    private var debugWindowController: DebugWindowController?
    
    /// Video playback time tracking
    private(set) var videoCurrentTime: TimeInterval = 0
    private var _videoDuration: TimeInterval = 0
    private(set) var videoTitle: String?
    
    /// Video duration - returns cast duration when video casting is active
    var videoDuration: TimeInterval {
        get {
            if isVideoCastingActive {
                // First check VideoPlayerWindowController (for casts from video player)
                if let controller = videoPlayerWindowController, controller.isCastingVideo {
                    return controller.castDuration
                }
                // Then check CastManager (for casts from context menu)
                if CastManager.shared.isVideoCasting {
                    return CastManager.shared.videoCastDuration
                }
            }
            return _videoDuration
        }
        set {
            _videoDuration = newValue
        }
    }
    
    /// Snap threshold in pixels - how close windows need to be to snap
    private let snapThreshold: CGFloat = 15
    
    /// Docking threshold - windows closer than this are considered docked
    /// Should be >= snapThreshold to ensure snapped windows are detected as docked
    private let dockThreshold: CGFloat = 20
    
    /// Undock threshold - how far you need to drag a window to break it free from the group
    private let undockThreshold: CGFloat = 30
    
    /// Track which window is currently being dragged
    private var draggingWindow: NSWindow?
    
    /// Track original position at drag start for undock detection
    private var dragStartOrigin: NSPoint = .zero
    
    /// Track if current drag is from title bar (only title bar drags can undock)
    private var isTitleBarDrag = false
    
    /// Track the last drag delta for grouped movement
    private var lastDragDelta: NSPoint = .zero
    
    /// Windows that should move together with the dragging window
    private var dockedWindowsToMove: [NSWindow] = []
    
    /// Store relative offsets of docked windows from the dragging window's origin
    /// This prevents drift during fast movement by maintaining exact relative positions
    private var dockedWindowOffsets: [ObjectIdentifier: NSPoint] = [:]
    
    /// Flag to prevent feedback loop when moving docked windows programmatically
    private var isMovingDockedWindows = false
    
    /// Flag to prevent feedback loop when snapping windows
    private var isSnappingWindow = false
    
    /// Windows that were attached as children for coordinated minimize (for restore)
    private var coordinatedMiniaturizedWindows: [NSWindow] = []
    
    // MARK: - Initialization
    
    private init() {
        // Register and load preferences
        registerPreferenceDefaults()
        loadPreferences()
        
        // Load default skin
        loadDefaultSkin()
    }
    
    /// Register default preference values
    private func registerPreferenceDefaults() {
        UserDefaults.standard.register(defaults: [
            "timeDisplayMode": TimeDisplayMode.elapsed.rawValue,
            "isAlwaysOnTop": false
        ])
    }
    
    /// Load preferences from UserDefaults
    private func loadPreferences() {
        if let mode = UserDefaults.standard.string(forKey: "timeDisplayMode"),
           let displayMode = TimeDisplayMode(rawValue: mode) {
            timeDisplayMode = displayMode
        }
        // Note: isDoubleSize always starts false - windows are created at 1x size
        // and we apply double size after they're created if needed
        let savedAlwaysOnTop = UserDefaults.standard.bool(forKey: "isAlwaysOnTop")
        isAlwaysOnTop = savedAlwaysOnTop
        NSLog("WindowManager: Loaded isAlwaysOnTop = %d from UserDefaults", savedAlwaysOnTop ? 1 : 0)
    }
    
    // MARK: - Window Management
    
    func showMainWindow() {
        let isNew = mainWindowController == nil
        if isNew {
            if isModernUIEnabled {
                let modern = ModernMainWindowController()
                mainWindowController = modern
            } else {
                mainWindowController = MainWindowController()
            }
        }
        // Adjust for hidden title bars on first creation (before positioning/showing)
        if isNew, let window = mainWindowController?.window {
            let tbHeight = isModernUIEnabled ? ModernSkinElements.playlistTitleBarHeight : 14 * Skin.scaleFactor
            adjustWindowForHiddenTitleBars(window, titleBarHeight: tbHeight)
        }
        mainWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(mainWindowController?.window)
    }
    
    func toggleMainWindow() {
        if let controller = mainWindowController, controller.window?.isVisible == true {
            controller.window?.orderOut(nil)
        } else {
            showMainWindow()
        }
    }
    
    func showPlaylist(at restoredFrame: NSRect? = nil) {
        let isNewWindow = playlistWindowController == nil
        if isNewWindow {
            if isModernUIEnabled {
                playlistWindowController = ModernPlaylistWindowController()
            } else {
                playlistWindowController = PlaylistWindowController()
            }
        }
        
        // Position BEFORE showing (unless restoring from saved state)
        if let playlistWindow = playlistWindowController?.window {
            if let frame = restoredFrame, frame != .zero {
                playlistWindow.setFrame(frame, display: true)
            } else {
                positionSubWindow(playlistWindow)
                let tbHeight = isModernUIEnabled ? ModernSkinElements.playlistTitleBarHeight : 20 * Skin.scaleFactor
                adjustWindowForHiddenTitleBars(playlistWindow, titleBarHeight: tbHeight)
            }
            NSLog("showPlaylist: window frame = \(playlistWindow.frame)")
        }
        
        playlistWindowController?.showWindow(nil)
        playlistWindowController?.window?.makeKeyAndOrderFront(nil)
        applyAlwaysOnTopToWindow(playlistWindowController?.window)
        notifyMainWindowVisibilityChanged()
    }

    var isPlaylistVisible: Bool {
        playlistWindowController?.window?.isVisible == true
    }
    
    func togglePlaylist() {
        if let controller = playlistWindowController, controller.window?.isVisible == true {
            controller.window?.orderOut(nil)
        } else {
            showPlaylist()
        }
        notifyMainWindowVisibilityChanged()
    }
    
    func showEqualizer(at restoredFrame: NSRect? = nil) {
        let isNewWindow = equalizerWindowController == nil
        if isNewWindow {
            if isModernUIEnabled {
                equalizerWindowController = ModernEQWindowController()
            } else {
                equalizerWindowController = EQWindowController()
            }
        }
        
        // Position BEFORE showing (unless restoring from saved state)
        if let eqWindow = equalizerWindowController?.window {
            if let frame = restoredFrame, frame != .zero {
                eqWindow.setFrame(frame, display: true)
            } else {
                positionSubWindow(eqWindow)
                let tbHeight = isModernUIEnabled ? ModernSkinElements.eqTitleBarHeight : 14 * Skin.scaleFactor
                adjustWindowForHiddenTitleBars(eqWindow, titleBarHeight: tbHeight)
            }
        }
        
        equalizerWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(equalizerWindowController?.window)
        notifyMainWindowVisibilityChanged()
    }

    var isEqualizerVisible: Bool {
        equalizerWindowController?.window?.isVisible == true
    }
    
    func toggleEqualizer() {
        if let controller = equalizerWindowController, controller.window?.isVisible == true {
            controller.window?.orderOut(nil)
        } else {
            showEqualizer()
        }
        notifyMainWindowVisibilityChanged()
    }
    
    /// Position a sub-window (EQ, Playlist, or Spectrum) in the vertical stack.
    /// Fills the first gap between visible stack windows if one exists,
    /// otherwise positions below the lowest visible window in the stack.
    private func positionSubWindow(_ window: NSWindow, preferBelowEQ: Bool = false) {
        guard let mainWindow = mainWindowController?.window else { return }
        
        let mainFrame = mainWindow.frame
        let newHeight = window.frame.size.height
        let newWidth = window.frame.size.width
        
        // Collect all visible stack windows except the one being positioned
        var visibleWindows: [NSWindow] = [mainWindow]
        if let w = equalizerWindowController?.window, w.isVisible, w !== window { visibleWindows.append(w) }
        if let w = playlistWindowController?.window, w.isVisible, w !== window { visibleWindows.append(w) }
        if let w = spectrumWindowController?.window, w.isVisible, w !== window { visibleWindows.append(w) }
        
        // Sort top-to-bottom (highest minY first, since macOS Y increases upward)
        visibleWindows.sort { $0.frame.minY > $1.frame.minY }
        
        // Scan for gaps between adjacent windows (first gap from top wins)
        var targetY: CGFloat? = nil
        for i in 0..<(visibleWindows.count - 1) {
            let upper = visibleWindows[i]
            let lower = visibleWindows[i + 1]
            let gap = upper.frame.minY - lower.frame.maxY
            if gap >= newHeight {
                targetY = upper.frame.minY - newHeight
                NSLog("positionSubWindow: Found gap (%.0f px) between windows at minY=%.0f and maxY=%.0f, placing at y=%.0f",
                      gap, upper.frame.minY, lower.frame.maxY, targetY!)
                break
            }
        }
        
        // No gap found: position below the lowest visible window
        if targetY == nil {
            let lowest = visibleWindows.last!
            targetY = lowest.frame.minY - newHeight
            NSLog("positionSubWindow: No gap found, positioning below lowest window (minY=%.0f), placing at y=%.0f",
                  lowest.frame.minY, targetY!)
        }
        
        let newFrame = NSRect(
            x: mainFrame.minX,  // Always align with main window
            y: targetY!,
            width: newWidth,
            height: newHeight
        )
        
        // Disable snapping during programmatic frame changes to prevent docking logic
        // from moving the entire window stack
        isSnappingWindow = true
        window.setFrame(newFrame, display: true)
        isSnappingWindow = false
    }
    
    /// Show local media library (redirects to unified browser in local mode)
    func showMediaLibrary() {
        // Redirect to unified browser - it handles both Plex and local files
        showPlexBrowser()
    }
    
    var isMediaLibraryVisible: Bool {
        // Redirects to unified browser visibility
        isPlexBrowserVisible
    }
    
    func toggleMediaLibrary() {
        // Redirect to unified browser toggle
        togglePlexBrowser()
    }
    
    // MARK: - Plex Browser Window
    
    func showPlexBrowser(at restoredFrame: NSRect? = nil) {
        let isNewWindow = plexBrowserWindowController == nil
        if isNewWindow {
            if isModernUIEnabled {
                plexBrowserWindowController = ModernLibraryBrowserWindowController()
            } else {
                plexBrowserWindowController = PlexBrowserWindowController()
            }
        }
        plexBrowserWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(plexBrowserWindowController?.window)
        
        // Position window to match the vertical stack
        if let window = plexBrowserWindowController?.window {
            if isNewWindow, let frame = restoredFrame, frame != .zero {
                // Use restored frame from state restoration (first creation only)
                window.setFrame(frame, display: true)
            } else {
                // Position to the right of the vertical stack
                // Only match stack height if there's more than just the main window
                let stackBounds = verticalStackBounds()
                let mainWindow = mainWindowController?.window
                let mainActualHeight = mainWindow?.frame.height ?? 0
                let stackHasMultipleWindows = stackBounds.height > mainActualHeight + 1
                // Scale width for double-size mode
                let sideWidth = window.frame.width * (isModernUIEnabled ? ModernSkinElements.sizeMultiplier : 1.0)
                
                if stackBounds != .zero && stackHasMultipleWindows {
                    // Match stack height when multiple windows are stacked
                    // No adjustWindowForHiddenTitleBars needed - stack height already accounts for it
                    let newFrame = NSRect(
                        x: stackBounds.maxX,
                        y: stackBounds.minY,
                        width: sideWidth,
                        height: stackBounds.height
                    )
                    window.setFrame(newFrame, display: true)
                } else if let mainWindow = mainWindow {
                    // Use default height (4× main) when only main window is visible
                    // Side window matches stack height, so use 4× actual main height
                    let mainFrame = mainWindow.frame
                    let defaultHeight = mainFrame.height * 4
                    let newFrame = NSRect(
                        x: mainFrame.maxX,
                        y: mainFrame.maxY - defaultHeight,
                        width: sideWidth,
                        height: defaultHeight
                    )
                    window.setFrame(newFrame, display: true)
                }
            }
        }
    }
    
    var isPlexBrowserVisible: Bool {
        plexBrowserWindowController?.window?.isVisible == true
    }
    
    /// Get the Plex Browser window frame if visible (for positioning other windows)
    var plexBrowserWindowFrame: NSRect? {
        guard let window = plexBrowserWindowController?.window, window.isVisible else { return nil }
        return window.frame
    }
    
    /// Get the ProjectM window frame (for state saving)
    var projectMWindowFrame: NSRect? {
        return projectMWindowController?.window?.frame
    }
    
    func togglePlexBrowser() {
        if let controller = plexBrowserWindowController, controller.window?.isVisible == true {
            controller.window?.orderOut(nil)
        } else {
            showPlexBrowser()
        }
    }
    
    /// Show the Plex account linking sheet
    func showPlexLinkSheet() {
        // Show from main window if available, otherwise standalone
        if let mainWindow = mainWindowController?.window {
            let linkSheet = PlexLinkSheet()
            linkSheet.showAsSheet(from: mainWindow) { [weak self] success in
                if success {
                    self?.plexBrowserWindowController?.reloadData()
                }
            }
        } else {
            let linkSheet = PlexLinkSheet()
            linkSheet.showAsWindow { [weak self] success in
                if success {
                    self?.plexBrowserWindowController?.reloadData()
                }
            }
        }
    }
    
    /// Unlink the Plex account
    func unlinkPlexAccount() {
        PlexManager.shared.unlinkAccount()
        plexBrowserWindowController?.reloadData()
    }
    
    // MARK: - Subsonic Sheets
    
    /// Subsonic dialogs
    private var subsonicLinkSheet: SubsonicLinkSheet?
    private var subsonicServerListSheet: SubsonicServerListSheet?
    
    /// Show the Subsonic server add dialog
    func showSubsonicLinkSheet() {
        subsonicLinkSheet = SubsonicLinkSheet()
        subsonicLinkSheet?.showDialog { [weak self] server in
            self?.subsonicLinkSheet = nil
            if server != nil {
                self?.plexBrowserWindowController?.reloadData()
            }
        }
    }
    
    /// Show the Subsonic server list management dialog
    func showSubsonicServerList() {
        subsonicServerListSheet = SubsonicServerListSheet()
        subsonicServerListSheet?.showDialog { [weak self] _ in
            self?.subsonicServerListSheet = nil
            self?.plexBrowserWindowController?.reloadData()
        }
    }
    
    // MARK: - Video Player Window
    
    /// Show the video player with a URL and title
    func showVideoPlayer(url: URL, title: String) {
        if videoPlayerWindowController == nil {
            videoPlayerWindowController = VideoPlayerWindowController()
        }
        videoPlayerWindowController?.volume = audioEngine.volume
        videoPlayerWindowController?.play(url: url, title: title)
        applyAlwaysOnTopToWindow(videoPlayerWindowController?.window)
    }
    
    /// Play a Plex movie in the video player
    func playMovie(_ movie: PlexMovie) {
        if videoPlayerWindowController == nil {
            videoPlayerWindowController = VideoPlayerWindowController()
        }
        videoPlayerWindowController?.volume = audioEngine.volume
        videoPlayerWindowController?.play(movie: movie)
        applyAlwaysOnTopToWindow(videoPlayerWindowController?.window)
    }
    
    /// Play a Plex episode in the video player
    func playEpisode(_ episode: PlexEpisode) {
        if videoPlayerWindowController == nil {
            videoPlayerWindowController = VideoPlayerWindowController()
        }
        videoPlayerWindowController?.volume = audioEngine.volume
        videoPlayerWindowController?.play(episode: episode)
        applyAlwaysOnTopToWindow(videoPlayerWindowController?.window)
    }
    
    /// Play a video Track from the playlist
    /// Called by AudioEngine when it encounters a video track
    func playVideoTrack(_ track: Track) {
        guard track.mediaType == .video else {
            NSLog("WindowManager: playVideoTrack called with non-video track")
            return
        }
        
        if videoPlayerWindowController == nil {
            videoPlayerWindowController = VideoPlayerWindowController()
        }
        
        // Set up callback for when video finishes (to advance playlist)
        videoPlayerWindowController?.onVideoFinishedForPlaylist = { [weak self] in
            self?.videoTrackDidFinish()
        }
        
        videoPlayerWindowController?.volume = audioEngine.volume
        
        // Use Plex-aware playback if track has a plexRatingKey (for scrobbling/progress)
        if track.plexRatingKey != nil {
            videoPlayerWindowController?.play(plexTrack: track)
        } else {
            videoPlayerWindowController?.play(url: track.url, title: track.displayTitle)
        }
        
        applyAlwaysOnTopToWindow(videoPlayerWindowController?.window)
        NSLog("WindowManager: Playing video track from playlist: %@", track.title)
    }
    
    /// Called when a video track from the playlist finishes playing
    private func videoTrackDidFinish() {
        NSLog("WindowManager: Video track finished, advancing playlist")
        audioEngine.next()
    }
    
    var isVideoPlayerVisible: Bool {
        videoPlayerWindowController?.window?.isVisible == true
    }
    
    /// Whether video is currently playing
    var isVideoPlaying: Bool {
        videoPlayerWindowController?.isPlaying ?? false
    }
    
    /// Current video title (if playing)
    var currentVideoTitle: String? {
        // First check video player window (for local playback or casts from player)
        if let title = videoPlayerWindowController?.currentTitle {
            return title
        }
        // Then check CastManager (for video casts from library browser menu)
        if CastManager.shared.isVideoCasting {
            return CastManager.shared.videoCastTitle
        }
        return nil
    }
    
    /// Public access to video player controller (for About Playing feature)
    var currentVideoPlayerController: VideoPlayerWindowController? {
        videoPlayerWindowController
    }
    
    func toggleVideoPlayer() {
        if let controller = videoPlayerWindowController, controller.window?.isVisible == true {
            controller.window?.orderOut(nil)
        } else if videoPlayerWindowController != nil {
            videoPlayerWindowController?.showWindow(nil)
        }
    }
    
    /// Toggle video play/pause
    func toggleVideoPlayPause() {
        // Path 1: Casting from video player window
        if let controller = videoPlayerWindowController, controller.isCastingVideo {
            controller.togglePlayPause()
            return
        }
        
        // Path 2: Casting from menu (no video player window)
        if CastManager.shared.isVideoCasting {
            Task {
                if CastManager.shared.isVideoCastPlaying {
                    try? await CastManager.shared.pause()
                } else {
                    try? await CastManager.shared.resume()
                }
            }
            return
        }
        
        // Local video player (not casting)
        videoPlayerWindowController?.togglePlayPause()
    }
    
    /// Stop video playback
    func stopVideo() {
        // Path 1: Casting from video player window
        if let controller = videoPlayerWindowController, controller.isCastingVideo {
            controller.stop()
            return
        }
        
        // Path 2: Casting from menu (no video player window)
        if CastManager.shared.isVideoCasting {
            Task {
                await CastManager.shared.stopCasting()
                await MainActor.run {
                    WindowManager.shared.videoPlaybackDidStop()
                }
            }
            return
        }
        
        // Local video player (not casting)
        videoPlayerWindowController?.stop()
    }
    
    /// Set video player volume
    func setVideoVolume(_ volume: Float) {
        videoPlayerWindowController?.volume = volume
    }
    
    /// Whether video casting is currently active
    var isVideoCastingActive: Bool {
        // Check both VideoPlayerWindowController (for casts initiated from video player)
        // and CastManager (for casts initiated from context menu)
        (videoPlayerWindowController?.isCastingVideo ?? false) || CastManager.shared.isVideoCasting
    }
    
    /// Set volume on video cast device
    func setVideoCastVolume(_ volume: Float) {
        guard isVideoCastingActive else { return }
        Task {
            try? await CastManager.shared.setVolume(volume)
        }
    }
    
    /// Toggle play/pause on video cast
    func toggleVideoCastPlayPause() {
        // Path 1: Casting from video player window
        if let controller = videoPlayerWindowController, controller.isCastingVideo {
            controller.togglePlayPause()
            return
        }
        
        // Path 2: Casting from menu (no video player window)
        if CastManager.shared.isVideoCasting {
            Task {
                if CastManager.shared.isVideoCastPlaying {
                    try? await CastManager.shared.pause()
                } else {
                    try? await CastManager.shared.resume()
                }
            }
        }
    }
    
    /// Seek video cast (normalized 0-1 position)
    func seekVideoCast(position: Double) {
        // Path 1: Casting from video player window
        if let controller = videoPlayerWindowController, controller.isCastingVideo {
            let time = position * controller.duration
            controller.seek(to: time)
            return
        }
        
        // Path 2: Casting from menu (no video player window)
        if CastManager.shared.isVideoCasting {
            let time = position * CastManager.shared.videoCastDuration
            Task {
                try? await CastManager.shared.seek(to: time)
            }
        }
    }
    
    /// Skip video forward
    func skipVideoForward(_ seconds: TimeInterval = 10) {
        // Path 1: Casting from video player window
        if let controller = videoPlayerWindowController, controller.isCastingVideo {
            controller.skipForward(seconds)
            return
        }
        
        // Path 2: Casting from menu (no video player window)
        if CastManager.shared.isVideoCasting {
            let newTime = min(CastManager.shared.videoCastCurrentTime + seconds, CastManager.shared.videoCastDuration)
            Task {
                try? await CastManager.shared.seek(to: newTime)
            }
            return
        }
        
        // Local video player (not casting)
        videoPlayerWindowController?.skipForward(seconds)
    }
    
    /// Skip video backward
    func skipVideoBackward(_ seconds: TimeInterval = 10) {
        // Path 1: Casting from video player window
        if let controller = videoPlayerWindowController, controller.isCastingVideo {
            controller.skipBackward(seconds)
            return
        }
        
        // Path 2: Casting from menu (no video player window)
        if CastManager.shared.isVideoCasting {
            let newTime = max(CastManager.shared.videoCastCurrentTime - seconds, 0)
            Task {
                try? await CastManager.shared.seek(to: newTime)
            }
            return
        }
        
        // Local video player (not casting)
        videoPlayerWindowController?.skipBackward(seconds)
    }
    
    /// Seek video to specific time
    func seekVideo(to time: TimeInterval) {
        // Path 1: Casting from video player window
        if let controller = videoPlayerWindowController, controller.isCastingVideo {
            controller.seek(to: time)
            return
        }
        
        // Path 2: Casting from menu (no video player window)
        if CastManager.shared.isVideoCasting {
            Task {
                try? await CastManager.shared.seek(to: time)
            }
            return
        }
        
        // Local video player (not casting)
        videoPlayerWindowController?.seek(to: time)
    }
    
    /// Called when video playback starts - pause audio
    func videoPlaybackDidStart() {
        if audioEngine.state == .playing {
            audioEngine.pause()
        }
        // Update main window with video title
        if let title = videoPlayerWindowController?.currentTitle {
            videoTitle = title
            mainWindowController?.updateVideoTrackInfo(title: title)
        }
        mainWindowController?.updatePlaybackState()
    }
    
    /// Called when video playback stops
    func videoPlaybackDidStop() {
        videoCurrentTime = 0
        videoDuration = 0
        videoTitle = nil
        // If audio was paused (by video starting), stop it so main window shows stopped state
        if audioEngine.state == .paused {
            audioEngine.stop()
        }
        mainWindowController?.clearVideoTrackInfo()
        mainWindowController?.updateTime(current: 0, duration: 0)
        mainWindowController?.updatePlaybackState()
    }
    
    /// Called by video player to update time (for main window display)
    func videoDidUpdateTime(current: TimeInterval, duration: TimeInterval) {
        videoCurrentTime = current
        videoDuration = duration
        mainWindowController?.updateTime(current: current, duration: duration)
    }
    
    /// Whether video is the active playback source (video session is active)
    /// Returns true when a video is loaded in the video player (even if paused) OR when video casting is active
    /// This is used by playlist mini controls to route commands correctly
    var isVideoActivePlayback: Bool {
        // Video casting is active - controls should route to video cast
        if isVideoCastingActive {
            return true
        }
        
        // A video session is active if the video player is visible AND has a video loaded
        // (indicated by currentTitle being set). This is different from isVideoPlaying
        // which only returns true when actively playing (not paused).
        guard let controller = videoPlayerWindowController,
              let window = controller.window,
              window.isVisible else {
            return false
        }
        return controller.currentTitle != nil
    }
    
    /// Get current video playback state for main window display
    var videoPlaybackState: PlaybackState {
        guard let controller = videoPlayerWindowController else { return .stopped }
        return controller.isPlaying ? .playing : .paused
    }
    
    // MARK: - ProjectM Visualization Window
    
    func showProjectM(at restoredFrame: NSRect? = nil) {
        let isNewWindow = projectMWindowController == nil
        if isNewWindow {
            if isModernUIEnabled {
                projectMWindowController = ModernProjectMWindowController()
            } else {
                projectMWindowController = ProjectMWindowController()
            }
        }
        projectMWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(projectMWindowController?.window)
        
        // Position newly created windows
        if isNewWindow, let window = projectMWindowController?.window {
            if let frame = restoredFrame, frame != .zero {
                // Use restored frame from state restoration
                window.setFrame(frame, display: true)
            } else {
                // Position to the left of the vertical stack
                // Only match stack height if there's more than just the main window
                let stackBounds = verticalStackBounds()
                let mainWindow = mainWindowController?.window
                let mainActualHeight = mainWindow?.frame.height ?? 0
                let stackHasMultipleWindows = stackBounds.height > mainActualHeight + 1
                if stackBounds != .zero && stackHasMultipleWindows {
                    // Match stack height when multiple windows are stacked
                    // No adjustWindowForHiddenTitleBars needed - stack height already accounts for it
                    let newFrame = NSRect(
                        x: stackBounds.minX - window.frame.width,
                        y: stackBounds.minY,
                        width: window.frame.width,
                        height: stackBounds.height
                    )
                    window.setFrame(newFrame, display: true)
                } else if let mainWindow = mainWindow {
                    // Use default height (4× main) when only main window is visible
                    // Side window matches stack height, so use 4× actual main height
                    let mainFrame = mainWindow.frame
                    let defaultHeight = mainFrame.height * 4
                    let newFrame = NSRect(
                        x: mainFrame.minX - window.frame.width,
                        y: mainFrame.maxY - defaultHeight,
                        width: window.frame.width,
                        height: defaultHeight
                    )
                    window.setFrame(newFrame, display: true)
                }
            }
        }
    }
    
    var isProjectMVisible: Bool {
        projectMWindowController?.window?.isVisible == true
    }
    
    /// Whether ProjectM is in fullscreen mode
    var isProjectMFullscreen: Bool {
        projectMWindowController?.isFullscreen ?? false
    }
    
    /// Toggle ProjectM fullscreen
    func toggleProjectMFullscreen() {
        projectMWindowController?.toggleFullscreen()
    }
    
    /// Whether the debug console window is visible
    var isDebugWindowVisible: Bool {
        debugWindowController?.window?.isVisible == true
    }
    
    func toggleProjectM() {
        if let controller = projectMWindowController, controller.window?.isVisible == true {
            // Stop rendering before hiding to save CPU (orderOut doesn't trigger windowWillClose)
            controller.stopRenderingForHide()
            controller.window?.orderOut(nil)
        } else {
            showProjectM()
        }
    }
    
    // MARK: - Spectrum Analyzer Window
    
    func showSpectrum(at restoredFrame: NSRect? = nil) {
        let isNewWindow = spectrumWindowController == nil
        if isNewWindow {
            if isModernUIEnabled {
                spectrumWindowController = ModernSpectrumWindowController()
            } else {
                spectrumWindowController = SpectrumWindowController()
            }
        }
        
        // Position BEFORE showing (unless restoring from saved state)
        if let window = spectrumWindowController?.window {
            if let frame = restoredFrame, frame != .zero {
                window.setFrame(frame, display: true)
            } else {
                positionSubWindow(window)
                let tbHeight = isModernUIEnabled ? ModernSkinElements.spectrumTitleBarHeight : 20 * Skin.scaleFactor
                adjustWindowForHiddenTitleBars(window, titleBarHeight: tbHeight)
            }
        }
        
        spectrumWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(spectrumWindowController?.window)
        notifyMainWindowVisibilityChanged()
    }
    
    var isSpectrumVisible: Bool {
        spectrumWindowController?.window?.isVisible == true
    }
    
    /// Get the Spectrum window frame (for state saving)
    var spectrumWindowFrame: NSRect? {
        return spectrumWindowController?.window?.frame
    }
    
    func toggleSpectrum() {
        if let controller = spectrumWindowController, controller.window?.isVisible == true {
            // Stop rendering before hiding to save CPU (orderOut doesn't trigger windowWillClose)
            controller.stopRenderingForHide()
            controller.window?.orderOut(nil)
        } else {
            showSpectrum()
        }
        notifyMainWindowVisibilityChanged()
    }
    
    // MARK: - Debug Window
    
    /// Show the debug console window
    func showDebugWindow() {
        if debugWindowController == nil {
            // Start capturing BEFORE creating the window so toolbar shows correct state
            DebugConsoleManager.shared.startCapturing()
            debugWindowController = DebugWindowController()
        }
        debugWindowController?.showWindow(nil)
        debugWindowController?.window?.makeKeyAndOrderFront(nil)
    }
    
    /// Toggle debug console window visibility
    func toggleDebugWindow() {
        if isDebugWindowVisible {
            debugWindowController?.window?.orderOut(nil)
        } else {
            showDebugWindow()
        }
    }
    
    // MARK: - Visualization Settings
    
    /// Whether projectM visualization is available
    var isProjectMAvailable: Bool {
        projectMWindowController?.isProjectMAvailable ?? false
    }
    
    /// Total number of visualization presets
    var visualizationPresetCount: Int {
        projectMWindowController?.presetCount ?? 0
    }
    
    /// Current visualization preset index
    var visualizationPresetIndex: Int? {
        projectMWindowController?.currentPresetIndex
    }
    
    /// Get information about loaded presets (bundled count, custom count, custom path)
    var visualizationPresetsInfo: (bundledCount: Int, customCount: Int, customPath: String?) {
        projectMWindowController?.presetsInfo ?? (0, 0, nil)
    }
    
    /// Reload all visualization presets from bundled and custom folders
    func reloadVisualizationPresets() {
        projectMWindowController?.reloadPresets()
    }
    
    /// Select a visualization preset by index
    func selectVisualizationPreset(at index: Int) {
        projectMWindowController?.selectPreset(at: index, hardCut: false)
    }

    func notifyMainWindowVisibilityChanged() {
        mainWindowController?.windowVisibilityDidChange()
    }
    
    // MARK: - Skin Management
    
    /// When true, Browser and ProjectM windows always use default skin (default: false - follow skin changes)
    var lockBrowserProjectMSkin: Bool {
        get {
            // Default to false (unlocked) - windows follow skin changes by default
            if UserDefaults.standard.object(forKey: "lockBrowserProjectMSkin") == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: "lockBrowserProjectMSkin")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "lockBrowserProjectMSkin")
            // Refresh these windows when setting changes
            plexBrowserWindowController?.skinDidChange()
            projectMWindowController?.skinDidChange()
        }
    }
    
    /// When true, shows album art as transparent background in browser window (default: true)
    var showBrowserArtworkBackground: Bool {
        get {
            // Default to true (enabled) if not set
            if UserDefaults.standard.object(forKey: "showBrowserArtworkBackground") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "showBrowserArtworkBackground")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "showBrowserArtworkBackground")
            // Trigger browser redraw
            plexBrowserWindowController?.window?.contentView?.needsDisplay = true
        }
    }
    
    func loadSkin(from url: URL) {
        do {
            let skin = try SkinLoader.shared.load(from: url)
            currentSkin = skin
            currentSkinPath = url.path
            // Persist last used classic skin for easy reload when switching UI modes
            UserDefaults.standard.set(url.path, forKey: "lastClassicSkinPath")
            notifySkinChanged()
        } catch {
            print("Failed to load skin: \(error)")
        }
    }
    
    private func loadDefaultSkin() {
        // 1. Try last used skin from UserDefaults
        if let lastPath = UserDefaults.standard.string(forKey: "lastClassicSkinPath"),
           FileManager.default.fileExists(atPath: lastPath) {
            do {
                currentSkin = try SkinLoader.shared.load(from: URL(fileURLWithPath: lastPath))
                currentSkinPath = lastPath
                return
            } catch {
                NSLog("Failed to restore last skin: \(error)")
            }
        }
        
        // 2. Try bundled default skin from app resources
        if let bundledURL = findBundledClassicSkin("NullPlayer-Silver") {
            do {
                currentSkin = try SkinLoader.shared.load(from: bundledURL)
                return
            } catch {
                NSLog("Failed to load bundled skin: \(error)")
            }
        }
        
        // 3. Fallback: unskinned native macOS rendering
        currentSkin = SkinLoader.shared.loadDefault()
    }
    
    private func findBundledClassicSkin(_ name: String) -> URL? {
        let bundle = Bundle.main
        guard let resourceURL = bundle.resourceURL else { return nil }
        // Mirror search paths from ModernSkinLoader.findBundledSkinDirectory()
        let searchPaths = [
            resourceURL.appendingPathComponent("Resources/Skins/\(name).wsz"),
            resourceURL.appendingPathComponent("NullPlayer_NullPlayer.bundle/Resources/Skins/\(name).wsz"),
            resourceURL.appendingPathComponent("Skins/\(name).wsz"),
        ]
        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }
        return nil
    }
    
    /// Load the bundled default classic skin (NullPlayer-Silver) at runtime
    func loadBundledDefaultSkin() {
        if let bundledURL = findBundledClassicSkin("NullPlayer-Silver") {
            do {
                currentSkin = try SkinLoader.shared.load(from: bundledURL)
                currentSkinPath = nil
                UserDefaults.standard.removeObject(forKey: "lastClassicSkinPath")
                notifySkinChanged()
                return
            } catch {
                NSLog("Failed to load bundled default skin: \(error)")
            }
        }
        // Fallback: unskinned
        currentSkin = SkinLoader.shared.loadDefault()
        currentSkinPath = nil
        UserDefaults.standard.removeObject(forKey: "lastClassicSkinPath")
        notifySkinChanged()
    }
    
    private func notifySkinChanged() {
        // Notify all windows to redraw with new skin
        mainWindowController?.skinDidChange()
        playlistWindowController?.skinDidChange()
        equalizerWindowController?.skinDidChange()
        plexBrowserWindowController?.skinDidChange()
        projectMWindowController?.skinDidChange()
        spectrumWindowController?.skinDidChange()
    }
    
    // MARK: - Skin Discovery
    
    /// Application Support directory for NullPlayer
    var applicationSupportURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("NullPlayer")
    }
    
    /// Skins directory
    var skinsDirectoryURL: URL {
        applicationSupportURL.appendingPathComponent("Skins")
    }
    
    /// Get list of available skins (name, URL)
    func availableSkins() -> [(name: String, url: URL)] {
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: skinsDirectoryURL, withIntermediateDirectories: true)
        
        guard let contents = try? FileManager.default.contentsOfDirectory(at: skinsDirectoryURL, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return contents
            .filter { $0.pathExtension.lowercased() == "wsz" }
            .map { (name: $0.deletingPathExtension().lastPathComponent, url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - Double Size
    
    /// Apply double size scaling to all windows
    private func applyDoubleSize() {
        // For modern UI, set the sizeMultiplier so all ModernSkinElements computed
        // sizes (window sizes, title bar heights, border widths, etc.) reflect 2x.
        // This must happen BEFORE reading any ModernSkinElements sizes.
        if isModernUIEnabled {
            ModernSkinElements.sizeMultiplier = isDoubleSize ? 2.0 : 1.0
        }
        
        let scale: CGFloat = isDoubleSize ? 2.0 : 1.0
        
        // Get main window position as anchor point
        guard let mainWindow = mainWindowController?.window else { return }
        
        // Store old main window frame for calculating relative positions
        let oldMainFrame = mainWindow.frame
        
        // For modern UI, sizes already include the multiplier via scaleFactor.
        // For classic UI, sizes are base sizes that need explicit * scale.
        let mainTargetSize: NSSize
        if isModernUIEnabled {
            mainTargetSize = ModernSkinElements.mainWindowSize
        } else {
            mainTargetSize = NSSize(width: Skin.mainWindowSize.width * scale,
                                    height: Skin.mainWindowSize.height * scale)
        }
        
        // Account for hidden title bars
        var mainAdjustedSize = mainTargetSize
        if hideTitleBars {
            let titleDelta: CGFloat = isModernUIEnabled ? ModernSkinElements.playlistTitleBarHeight : 14 * Skin.scaleFactor * scale
            mainAdjustedSize.height -= titleDelta
        }
        
        // Update minSize
        mainWindow.minSize = mainAdjustedSize
        
        // Resize main window (anchor top-left)
        var mainFrame = mainWindow.frame
        let mainTopY = mainFrame.maxY  // Keep top edge fixed
        mainFrame.size = mainAdjustedSize
        mainFrame.origin.y = mainTopY - mainAdjustedSize.height
        mainWindow.setFrame(mainFrame, display: true, animate: true)
        
        // Track the bottom edge for stacking windows below main
        var nextY = mainFrame.minY
        
        // EQ window - position below main window
        if let eqWindow = equalizerWindowController?.window, eqWindow.isVisible {
            let eqTargetSize: NSSize
            if isModernUIEnabled {
                eqTargetSize = ModernSkinElements.eqWindowSize
            } else {
                eqTargetSize = NSSize(width: Skin.eqWindowSize.width * scale,
                                      height: Skin.eqWindowSize.height * scale)
            }
            var eqAdjustedSize = eqTargetSize
            if hideTitleBars {
                let titleDelta: CGFloat = isModernUIEnabled ? ModernSkinElements.eqTitleBarHeight : 14 * Skin.scaleFactor * scale
                eqAdjustedSize.height -= titleDelta
            }
            eqWindow.minSize = eqAdjustedSize
            eqWindow.maxSize = eqAdjustedSize
            let eqFrame = NSRect(
                x: mainFrame.minX,
                y: nextY - eqAdjustedSize.height,
                width: eqAdjustedSize.width,
                height: eqAdjustedSize.height
            )
            eqWindow.setFrame(eqFrame, display: true, animate: true)
            nextY = eqFrame.minY
        }
        
        // Playlist - position below EQ (or main if no EQ)
        if let playlistWindow = playlistWindowController?.window, playlistWindow.isVisible {
            let baseMinSize: NSSize = isModernUIEnabled ? ModernSkinElements.playlistMinSize : Skin.playlistMinSize
            var minHeight = baseMinSize.height * (isModernUIEnabled ? 1.0 : scale)
            if hideTitleBars {
                let titleDelta: CGFloat = isModernUIEnabled ? ModernSkinElements.playlistTitleBarHeight : 20 * Skin.scaleFactor * scale
                minHeight -= titleDelta
            }
            
            let targetWidth = mainFrame.width
            playlistWindow.minSize = NSSize(width: targetWidth, height: minHeight)
            playlistWindow.maxSize = NSSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
            
            // Scale height proportionally
            let currentFrame = playlistWindow.frame
            let newHeight = max(minHeight, currentFrame.height * (isDoubleSize ? 2.0 : 0.5))
            
            let playlistFrame = NSRect(
                x: mainFrame.minX,
                y: nextY - newHeight,
                width: targetWidth,
                height: newHeight
            )
            playlistWindow.setFrame(playlistFrame, display: true, animate: true)
            nextY = playlistFrame.minY
        }
        
        // Spectrum window - position below playlist (or previous window)
        if let spectrumWindow = spectrumWindowController?.window, spectrumWindow.isVisible {
            let spectrumTargetSize: NSSize
            if isModernUIEnabled {
                spectrumTargetSize = ModernSkinElements.spectrumWindowSize
            } else {
                spectrumTargetSize = NSSize(width: Skin.mainWindowSize.width * scale,
                                            height: Skin.mainWindowSize.height * scale)
            }
            var spectrumAdjustedSize = spectrumTargetSize
            if hideTitleBars {
                let titleDelta: CGFloat = isModernUIEnabled ? ModernSkinElements.spectrumTitleBarHeight : 14 * Skin.scaleFactor * scale
                spectrumAdjustedSize.height -= titleDelta
            }
            spectrumWindow.minSize = spectrumAdjustedSize
            spectrumWindow.maxSize = spectrumAdjustedSize
            let spectrumFrame = NSRect(
                x: mainFrame.minX,
                y: nextY - spectrumAdjustedSize.height,
                width: spectrumAdjustedSize.width,
                height: spectrumAdjustedSize.height
            )
            spectrumWindow.setFrame(spectrumFrame, display: true, animate: true)
            nextY = spectrumFrame.minY
        }
        
        // Side windows - match the vertical stack height and reposition
        let stackTopY = mainFrame.maxY
        let stackHeight = stackTopY - nextY
        
        if let plexWindow = plexBrowserWindowController?.window, plexWindow.isVisible {
            // Scale width: when going to 2x double it, when going to 1x halve it
            let newWidth = isDoubleSize ? plexWindow.frame.width * 2.0 : plexWindow.frame.width / 2.0
            let plexFrame = NSRect(
                x: mainFrame.maxX,
                y: nextY,
                width: newWidth,
                height: stackHeight
            )
            plexWindow.setFrame(plexFrame, display: true, animate: true)
        }
        
        if let projectMWindow = projectMWindowController?.window, projectMWindow.isVisible {
            // Scale width: when going to 2x double it, when going to 1x halve it
            let newWidth = isDoubleSize ? projectMWindow.frame.width * 2.0 : projectMWindow.frame.width / 2.0
            let projectMFrame = NSRect(
                x: mainFrame.minX - (isDoubleSize ? projectMWindow.frame.width * 2.0 : projectMWindow.frame.width / 2.0),
                y: nextY,
                width: newWidth,
                height: stackHeight
            )
            projectMWindow.setFrame(projectMFrame, display: true, animate: true)
        }
    }
    
    private func applyAlwaysOnTop() {
        let level: NSWindow.Level = isAlwaysOnTop ? .floating : .normal
        
        // Apply to all app windows
        mainWindowController?.window?.level = level
        equalizerWindowController?.window?.level = level
        playlistWindowController?.window?.level = level
        plexBrowserWindowController?.window?.level = level
        videoPlayerWindowController?.window?.level = level
        projectMWindowController?.window?.level = level
        spectrumWindowController?.window?.level = level
    }
    
    /// Apply always on top level to a single window (used when showing windows)
    private func applyAlwaysOnTopToWindow(_ window: NSWindow?) {
        guard let window = window else { return }
        window.level = isAlwaysOnTop ? .floating : .normal
    }
    
    /// Bring all visible app windows to front (called when any app window gets focus)
    func bringAllWindowsToFront() {
        // Order all visible windows to front without making them key
        let windows: [NSWindow?] = [
            mainWindowController?.window,
            equalizerWindowController?.window,
            playlistWindowController?.window,
            plexBrowserWindowController?.window,
            videoPlayerWindowController?.window,
            projectMWindowController?.window,
            spectrumWindowController?.window
        ]
        
        for window in windows {
            if let window = window, window.isVisible {
                window.orderFront(nil)
            }
        }
    }
    
    /// Calculate the bounding box of the vertical window stack (main + EQ + playlist + spectrum)
    /// Returns the combined bounds of all visible windows in the vertical stack
    private func verticalStackBounds() -> NSRect {
        guard let mainFrame = mainWindowController?.window?.frame else { return .zero }
        
        let topY = mainFrame.maxY
        var bottomY = mainFrame.minY
        let x = mainFrame.minX
        let width = mainFrame.width
        
        // Check each window in the stack and expand bounds
        if let eqWindow = equalizerWindowController?.window, eqWindow.isVisible {
            bottomY = min(bottomY, eqWindow.frame.minY)
        }
        if let playlistWindow = playlistWindowController?.window, playlistWindow.isVisible {
            bottomY = min(bottomY, playlistWindow.frame.minY)
        }
        if let spectrumWindow = spectrumWindowController?.window, spectrumWindow.isVisible {
            bottomY = min(bottomY, spectrumWindow.frame.minY)
        }
        
        return NSRect(x: x, y: bottomY, width: width, height: topY - bottomY)
    }
    
    /// Reset all windows to their default positions
    /// Only stacks currently visible windows with no gaps, preserving their current sizes
    func snapToDefaultPositions() {
        let defaults = UserDefaults.standard
        
        // Get screen for positioning - use the screen the main window is on, or fall back to main screen
        // Use full screen frame (not visibleFrame) so windows aren't constrained by menu bar/dock
        guard let screen = mainWindowController?.window?.screen ?? NSScreen.main else { return }
        let screenFrame = screen.frame
        
        // Use current main window size (preserves user scaling)
        let mainSize = mainWindowController?.window?.frame.size ??
            (isModernUIEnabled ? ModernSkinElements.mainWindowSize : Skin.mainWindowSize)
        let mainFrame = NSRect(
            x: screenFrame.midX - mainSize.width / 2,
            y: screenFrame.midY - mainSize.height / 2,
            width: mainSize.width,
            height: mainSize.height
        )
        
        // Build a tight vertical stack of only visible windows below main
        // Each window preserves its current size and aligns left with main
        var nextY = mainFrame.minY  // Bottom of previous window in stack
        
        // Collect frames for visible stack windows (order: EQ, Playlist, Spectrum)
        var eqFrame: NSRect?
        var playlistFrame: NSRect?
        var spectrumFrame: NSRect?
        
        if let eqWindow = equalizerWindowController?.window, eqWindow.isVisible {
            let h = eqWindow.frame.height
            let w = eqWindow.frame.width
            nextY -= h
            eqFrame = NSRect(x: mainFrame.minX, y: nextY, width: w, height: h)
        }
        
        if let playlistWindow = playlistWindowController?.window, playlistWindow.isVisible {
            let h = playlistWindow.frame.height
            let w = playlistWindow.frame.width
            nextY -= h
            playlistFrame = NSRect(x: mainFrame.minX, y: nextY, width: w, height: h)
        }
        
        if let spectrumWindow = spectrumWindowController?.window, spectrumWindow.isVisible {
            let h = spectrumWindow.frame.height
            let w = spectrumWindow.frame.width
            nextY -= h
            spectrumFrame = NSRect(x: mainFrame.minX, y: nextY, width: w, height: h)
        }
        
        // Side windows span the full stack height
        let stackTopY = mainFrame.maxY
        let stackBottomY = nextY
        let stackHeight = stackTopY - stackBottomY
        
        var browserFrame: NSRect?
        var projectMFrame: NSRect?
        
        if let plexWindow = plexBrowserWindowController?.window, plexWindow.isVisible {
            let w = plexWindow.frame.width
            browserFrame = NSRect(x: mainFrame.maxX, y: stackBottomY, width: w, height: stackHeight)
        }
        
        if let projectMWindow = projectMWindowController?.window, projectMWindow.isVisible {
            let w = projectMWindow.frame.width
            projectMFrame = NSRect(x: mainFrame.minX - w, y: stackBottomY, width: w, height: stackHeight)
        }
        
        // Clear any saved positions (windows will be positioned relative to main on open)
        defaults.removeObject(forKey: "MainWindowFrame")
        defaults.removeObject(forKey: "EqualizerWindowFrame")
        defaults.removeObject(forKey: "PlaylistWindowFrame")
        defaults.removeObject(forKey: "PlexBrowserWindowFrame")
        defaults.removeObject(forKey: "ProjectMWindowFrame")
        defaults.removeObject(forKey: "VideoPlayerWindowFrame")
        defaults.removeObject(forKey: "ArtVisualizerWindowFrame")
        defaults.removeObject(forKey: "SpectrumWindowFrame")
        
        // Disable snapping during programmatic frame changes to prevent interference
        isSnappingWindow = true
        defer { isSnappingWindow = false }
        
        // Apply positions to visible windows
        if let mainWindow = mainWindowController?.window {
            mainWindow.setFrame(mainFrame, display: true, animate: false)
        }
        if let frame = eqFrame, let window = equalizerWindowController?.window {
            window.setFrame(frame, display: true, animate: false)
        }
        if let frame = playlistFrame, let window = playlistWindowController?.window {
            window.setFrame(frame, display: true, animate: false)
        }
        if let frame = spectrumFrame, let window = spectrumWindowController?.window {
            window.setFrame(frame, display: true, animate: false)
        }
        if let frame = browserFrame, let window = plexBrowserWindowController?.window {
            window.setFrame(frame, display: true, animate: false)
        }
        if let frame = projectMFrame, let window = projectMWindowController?.window {
            window.setFrame(frame, display: true, animate: false)
        }
        if let videoWindow = videoPlayerWindowController?.window, videoWindow.isVisible {
            videoWindow.center()
        }
    }
    
    // MARK: - Window Snapping & Docking
    
    /// Called when a window drag begins
    /// - Parameters:
    ///   - window: The window being dragged
    ///   - fromTitleBar: If true, this drag can undock the window from its group
    func windowWillStartDragging(_ window: NSWindow, fromTitleBar: Bool = false) {
        draggingWindow = window
        dragStartOrigin = window.frame.origin
        isTitleBarDrag = fromTitleBar
        
        // Find all windows that are docked to this window
        dockedWindowsToMove = findDockedWindows(to: window)
        
        // Store relative offsets from dragging window's origin
        // This ensures we maintain exact relative positions during fast movement
        dockedWindowOffsets.removeAll()
        let dragOrigin = window.frame.origin
        for dockedWindow in dockedWindowsToMove {
            let offset = NSPoint(
                x: dockedWindow.frame.origin.x - dragOrigin.x,
                y: dockedWindow.frame.origin.y - dragOrigin.y
            )
            dockedWindowOffsets[ObjectIdentifier(dockedWindow)] = offset
        }
    }
    
    /// Called when a window drag ends
    func windowDidFinishDragging(_ window: NSWindow) {
        draggingWindow = nil
        dockedWindowsToMove.removeAll()
        dockedWindowOffsets.removeAll()
    }
    
    /// Safely apply snapped position to a window without triggering feedback loop
    func applySnappedPosition(_ window: NSWindow, to position: NSPoint) {
        guard position != window.frame.origin else { return }
        isSnappingWindow = true
        window.setFrameOrigin(position)
        isSnappingWindow = false
    }
    
    /// Called when a window is being dragged - handle snapping and move docked windows
    func windowWillMove(_ window: NSWindow, to newOrigin: NSPoint) -> NSPoint {
        // Ignore if we're already in the middle of snapping (prevents feedback loop)
        if isSnappingWindow {
            return newOrigin
        }
        
        // Ignore if this is a docked window being moved programmatically
        if isMovingDockedWindows && dockedWindowsToMove.contains(where: { $0 === window }) {
            return newOrigin
        }
        
        // If this is a new drag, find docked windows
        if draggingWindow !== window {
            windowWillStartDragging(window)
        }
        
        // Check if we should undock (break free from the group)
        // Only non-main windows can undock when dragged by title bar
        // Main window ALWAYS moves the entire docked group - it never detaches
        let isMainWindow = window === mainWindowController?.window
        if !isMainWindow && isTitleBarDrag && !dockedWindowsToMove.isEmpty {
            let dragDistance = hypot(newOrigin.x - dragStartOrigin.x, newOrigin.y - dragStartOrigin.y)
            if dragDistance > undockThreshold {
                // Break the dock - this window now moves alone
                dockedWindowsToMove.removeAll()
                dockedWindowOffsets.removeAll()
            }
        }
        
        // Apply snap to screen edges and other windows
        let snappedOrigin = applySnapping(for: window, to: newOrigin)
        
        // Move all docked windows using stored offsets (prevents drift during fast movement)
        if !dockedWindowsToMove.isEmpty {
            isMovingDockedWindows = true
            for dockedWindow in dockedWindowsToMove {
                if let offset = dockedWindowOffsets[ObjectIdentifier(dockedWindow)] {
                    // Use stored offset from drag start to maintain exact relative position
                    let newDockedOrigin = NSPoint(
                        x: snappedOrigin.x + offset.x,
                        y: snappedOrigin.y + offset.y
                    )
                    dockedWindow.setFrameOrigin(newDockedOrigin)
                }
            }
            isMovingDockedWindows = false
        }
        
        return snappedOrigin
    }
    
    /// Calculate the bounding box of the dragging window and all its docked windows
    /// - Parameters:
    ///   - window: The window being dragged
    ///   - newOrigin: The proposed new origin for the dragging window
    /// - Returns: The bounding rectangle of the entire window group
    private func calculateGroupBounds(for window: NSWindow, at newOrigin: NSPoint) -> NSRect {
        var bounds = NSRect(origin: newOrigin, size: window.frame.size)
        
        // Include all docked windows in the bounds calculation
        for dockedWindow in dockedWindowsToMove {
            if let offset = dockedWindowOffsets[ObjectIdentifier(dockedWindow)] {
                let dockedOrigin = NSPoint(
                    x: newOrigin.x + offset.x,
                    y: newOrigin.y + offset.y
                )
                let dockedFrame = NSRect(origin: dockedOrigin, size: dockedWindow.frame.size)
                bounds = bounds.union(dockedFrame)
            }
        }
        
        return bounds
    }
    
    /// Check if the window group spans multiple screens
    /// - Parameter groupBounds: The bounding rectangle of the entire group
    /// - Returns: true if the group is currently crossing monitor boundaries
    private func groupSpansMultipleScreens(_ groupBounds: NSRect) -> Bool {
        var containingScreen: NSScreen? = nil
        
        for screen in NSScreen.screens {
            let intersection = groupBounds.intersection(screen.frame)
            if !intersection.isEmpty {
                if containingScreen != nil {
                    // Group intersects multiple screens
                    return true
                }
                containingScreen = screen
            }
        }
        
        return false
    }
    
    /// Check if snapping would cause any docked window to end up on a different screen
    /// - Parameters:
    ///   - mainOrigin: The proposed origin for the main/dragging window after snapping
    ///   - mainSize: The size of the main/dragging window
    /// - Returns: true if any docked window would end up on a different screen than main
    private func wouldSnapCauseScreenSeparation(mainOrigin: NSPoint, mainSize: NSSize) -> Bool {
        guard !dockedWindowsToMove.isEmpty else { return false }
        
        let mainFrame = NSRect(origin: mainOrigin, size: mainSize)
        
        // Find which screen the main window would be on after snapping
        var mainScreen: NSScreen? = nil
        var maxIntersection: CGFloat = 0
        for screen in NSScreen.screens {
            let intersection = mainFrame.intersection(screen.frame)
            let area = intersection.width * intersection.height
            if area > maxIntersection {
                maxIntersection = area
                mainScreen = screen
            }
        }
        
        guard let targetScreen = mainScreen else { return false }
        
        // Check if any docked window would end up primarily on a different screen
        for dockedWindow in dockedWindowsToMove {
            guard let offset = dockedWindowOffsets[ObjectIdentifier(dockedWindow)] else { continue }
            
            let dockedOrigin = NSPoint(
                x: mainOrigin.x + offset.x,
                y: mainOrigin.y + offset.y
            )
            let dockedFrame = NSRect(origin: dockedOrigin, size: dockedWindow.frame.size)
            
            // Find which screen this docked window would be on
            var dockedScreen: NSScreen? = nil
            var dockedMaxIntersection: CGFloat = 0
            for screen in NSScreen.screens {
                let intersection = dockedFrame.intersection(screen.frame)
                let area = intersection.width * intersection.height
                if area > dockedMaxIntersection {
                    dockedMaxIntersection = area
                    dockedScreen = screen
                }
            }
            
            // If docked window would be on a different screen, snapping would cause separation
            if dockedScreen !== targetScreen {
                return true
            }
        }
        
        return false
    }
    
    /// Apply snapping to other windows and screen edges
    private func applySnapping(for window: NSWindow, to newOrigin: NSPoint) -> NSPoint {
        var snappedX = newOrigin.x
        var snappedY = newOrigin.y
        let frame = NSRect(origin: newOrigin, size: window.frame.size)
        
        // Track best snaps (closest distance)
        var bestHorizontalSnap: (distance: CGFloat, value: CGFloat)? = nil
        var bestVerticalSnap: (distance: CGFloat, value: CGFloat)? = nil
        
        // Helper to check if ranges overlap (with tolerance for snapping)
        func rangesOverlap(_ min1: CGFloat, _ max1: CGFloat, _ min2: CGFloat, _ max2: CGFloat) -> Bool {
            return max1 > min2 - snapThreshold && min1 < max2 + snapThreshold
        }
        
        // Track if we're dragging a group (for screen separation checks)
        let isDraggingGroup = !dockedWindowsToMove.isEmpty
        let windowSize = window.frame.size
        
        // Snap to screen edges (with special handling for groups to prevent separation)
        if let screen = window.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            
            // Left edge to screen left
            let leftDist = abs(frame.minX - screenFrame.minX)
            if leftDist < snapThreshold {
                let candidateOrigin = NSPoint(x: screenFrame.minX, y: newOrigin.y)
                // Only snap if it won't cause docked windows to end up on different screen
                if !isDraggingGroup || !wouldSnapCauseScreenSeparation(mainOrigin: candidateOrigin, mainSize: windowSize) {
                    if bestHorizontalSnap == nil || leftDist < bestHorizontalSnap!.distance {
                        bestHorizontalSnap = (leftDist, screenFrame.minX)
                    }
                }
            }
            
            // Right edge to screen right
            let rightDist = abs(frame.maxX - screenFrame.maxX)
            if rightDist < snapThreshold {
                let candidateX = screenFrame.maxX - frame.width
                let candidateOrigin = NSPoint(x: candidateX, y: newOrigin.y)
                if !isDraggingGroup || !wouldSnapCauseScreenSeparation(mainOrigin: candidateOrigin, mainSize: windowSize) {
                    if bestHorizontalSnap == nil || rightDist < bestHorizontalSnap!.distance {
                        bestHorizontalSnap = (rightDist, candidateX)
                    }
                }
            }
            
            // Bottom edge to screen bottom
            let bottomDist = abs(frame.minY - screenFrame.minY)
            if bottomDist < snapThreshold {
                let candidateOrigin = NSPoint(x: newOrigin.x, y: screenFrame.minY)
                if !isDraggingGroup || !wouldSnapCauseScreenSeparation(mainOrigin: candidateOrigin, mainSize: windowSize) {
                    if bestVerticalSnap == nil || bottomDist < bestVerticalSnap!.distance {
                        bestVerticalSnap = (bottomDist, screenFrame.minY)
                    }
                }
            }
            
            // Top edge to screen top
            let topDist = abs(frame.maxY - screenFrame.maxY)
            if topDist < snapThreshold {
                let candidateY = screenFrame.maxY - frame.height
                let candidateOrigin = NSPoint(x: newOrigin.x, y: candidateY)
                if !isDraggingGroup || !wouldSnapCauseScreenSeparation(mainOrigin: candidateOrigin, mainSize: windowSize) {
                    if bestVerticalSnap == nil || topDist < bestVerticalSnap!.distance {
                        bestVerticalSnap = (topDist, candidateY)
                    }
                }
            }
        }
        
        // All windows can snap to dockable windows (main, playlist, EQ)
        // But non-dockable windows don't participate in docking (moving together)
        let windowsToSnapTo = dockableWindows()
        for otherWindow in windowsToSnapTo {
            guard otherWindow != window else { continue }
            // Skip docked windows as they're moving with us
            guard !dockedWindowsToMove.contains(otherWindow) else { continue }
            
            let otherFrame = otherWindow.frame
            
            // Check if windows overlap or are close vertically (for horizontal snapping)
            let verticallyClose = rangesOverlap(frame.minY, frame.maxY, otherFrame.minY, otherFrame.maxY)
            
            // Check if windows overlap or are close horizontally (for vertical snapping)
            let horizontallyClose = rangesOverlap(frame.minX, frame.maxX, otherFrame.minX, otherFrame.maxX)
            
            // HORIZONTAL SNAPPING (only if vertically aligned)
            if verticallyClose {
                // Priority 1: Edge-to-edge docking (most intuitive)
                // Snap right edge to left edge (dock side by side)
                let rightToLeftDist = abs(frame.maxX - otherFrame.minX)
                if rightToLeftDist < snapThreshold {
                    if bestHorizontalSnap == nil || rightToLeftDist < bestHorizontalSnap!.distance {
                        bestHorizontalSnap = (rightToLeftDist, otherFrame.minX - frame.width)
                    }
                }
                
                // Snap left edge to right edge (dock side by side)
                let leftToRightDist = abs(frame.minX - otherFrame.maxX)
                if leftToRightDist < snapThreshold {
                    if bestHorizontalSnap == nil || leftToRightDist < bestHorizontalSnap!.distance {
                        bestHorizontalSnap = (leftToRightDist, otherFrame.maxX)
                    }
                }
                
                // Priority 2: Edge alignment (only if not already snapping to edge-to-edge)
                // Snap left edges together
                let leftToLeftDist = abs(frame.minX - otherFrame.minX)
                if leftToLeftDist < snapThreshold && leftToLeftDist > 0 {
                    if bestHorizontalSnap == nil || leftToLeftDist < bestHorizontalSnap!.distance * 0.8 {
                        // Only use alignment snap if significantly closer (0.8 factor)
                        bestHorizontalSnap = (leftToLeftDist, otherFrame.minX)
                    }
                }
                
                // Snap right edges together
                let rightToRightDist = abs(frame.maxX - otherFrame.maxX)
                if rightToRightDist < snapThreshold && rightToRightDist > 0 {
                    if bestHorizontalSnap == nil || rightToRightDist < bestHorizontalSnap!.distance * 0.8 {
                        bestHorizontalSnap = (rightToRightDist, otherFrame.maxX - frame.width)
                    }
                }
            }
            
            // VERTICAL SNAPPING (only if horizontally aligned)
            if horizontallyClose {
                // Priority 1: Edge-to-edge docking
                // Snap bottom edge to top edge (stack below)
                let bottomToTopDist = abs(frame.minY - otherFrame.maxY)
                if bottomToTopDist < snapThreshold {
                    if bestVerticalSnap == nil || bottomToTopDist < bestVerticalSnap!.distance {
                        bestVerticalSnap = (bottomToTopDist, otherFrame.maxY)
                    }
                }
                
                // Snap top edge to bottom edge (stack above)
                let topToBottomDist = abs(frame.maxY - otherFrame.minY)
                if topToBottomDist < snapThreshold {
                    if bestVerticalSnap == nil || topToBottomDist < bestVerticalSnap!.distance {
                        bestVerticalSnap = (topToBottomDist, otherFrame.minY - frame.height)
                    }
                }
                
                // Priority 2: Edge alignment
                // Snap top edges together
                let topToTopDist = abs(frame.maxY - otherFrame.maxY)
                if topToTopDist < snapThreshold && topToTopDist > 0 {
                    if bestVerticalSnap == nil || topToTopDist < bestVerticalSnap!.distance * 0.8 {
                        bestVerticalSnap = (topToTopDist, otherFrame.maxY - frame.height)
                    }
                }
                
                // Snap bottom edges together
                let bottomToBottomDist = abs(frame.minY - otherFrame.minY)
                if bottomToBottomDist < snapThreshold && bottomToBottomDist > 0 {
                    if bestVerticalSnap == nil || bottomToBottomDist < bestVerticalSnap!.distance * 0.8 {
                        bestVerticalSnap = (bottomToBottomDist, otherFrame.minY)
                    }
                }
            }
        }
        
        // Apply best snaps
        if let hSnap = bestHorizontalSnap {
            snappedX = hSnap.value
        }
        if let vSnap = bestVerticalSnap {
            snappedY = vSnap.value
        }
        
        return NSPoint(x: snappedX, y: snappedY)
    }
    
    /// Find all windows that are docked (touching) the given window
    /// When dragging a dockable window (main, playlist, EQ), all touching windows move together
    /// When dragging a non-dockable window (Plex browser), it moves alone
    func findDockedWindows(to window: NSWindow) -> [NSWindow] {
        // Non-dockable windows don't drag other windows with them
        guard isDockableWindow(window) else { return [] }
        
        var dockedWindows: [NSWindow] = []
        var windowsToCheck: [NSWindow] = [window]
        var checkedWindows: Set<ObjectIdentifier> = [ObjectIdentifier(window)]
        
        // Use BFS to find all transitively docked windows
        // Include all visible windows so Plex browser moves with the group
        while !windowsToCheck.isEmpty {
            let currentWindow = windowsToCheck.removeFirst()
            
            for otherWindow in allWindows() {
                let otherId = ObjectIdentifier(otherWindow)
                if checkedWindows.contains(otherId) { continue }
                
                if areWindowsDocked(currentWindow, otherWindow) {
                    dockedWindows.append(otherWindow)
                    // Only continue BFS through dockable windows (don't chain through Plex browser)
                    if isDockableWindow(otherWindow) {
                        windowsToCheck.append(otherWindow)
                    }
                    checkedWindows.insert(otherId)
                }
            }
        }
        
        return dockedWindows
    }
    
    /// Check if two windows are docked (touching edges)
    private func areWindowsDocked(_ window1: NSWindow, _ window2: NSWindow) -> Bool {
        let frame1 = window1.frame
        let frame2 = window2.frame
        
        // Check if windows are touching horizontally (side by side)
        let horizontallyAligned = (frame1.minY < frame2.maxY && frame1.maxY > frame2.minY)
        let hGap1 = abs(frame1.maxX - frame2.minX)
        let hGap2 = abs(frame1.minX - frame2.maxX)
        let touchingHorizontally = horizontallyAligned && (hGap1 <= dockThreshold || hGap2 <= dockThreshold)
        
        // Check if windows are touching vertically (stacked)
        let verticallyAligned = (frame1.minX < frame2.maxX && frame1.maxX > frame2.minX)
        let vGap1 = abs(frame1.maxY - frame2.minY)
        let vGap2 = abs(frame1.minY - frame2.maxY)
        let touchingVertically = verticallyAligned && (vGap1 <= dockThreshold || vGap2 <= dockThreshold)
        
        return touchingHorizontally || touchingVertically
    }
    
    /// Get all managed windows
    private func allWindows() -> [NSWindow] {
        var windows: [NSWindow] = []
        if let w = mainWindowController?.window, w.isVisible { windows.append(w) }
        if let w = playlistWindowController?.window, w.isVisible { windows.append(w) }
        if let w = equalizerWindowController?.window, w.isVisible { windows.append(w) }
        if let w = plexBrowserWindowController?.window, w.isVisible { windows.append(w) }
        if let w = videoPlayerWindowController?.window, w.isVisible { windows.append(w) }
        if let w = projectMWindowController?.window, w.isVisible { windows.append(w) }
        if let w = spectrumWindowController?.window, w.isVisible { windows.append(w) }
        return windows
    }
    
    /// Get windows that participate in docking/snapping together (classic skin windows)
    private func dockableWindows() -> [NSWindow] {
        var windows: [NSWindow] = []
        if let w = mainWindowController?.window, w.isVisible { windows.append(w) }
        if let w = playlistWindowController?.window, w.isVisible { windows.append(w) }
        if let w = equalizerWindowController?.window, w.isVisible { windows.append(w) }
        if let w = spectrumWindowController?.window, w.isVisible { windows.append(w) }
        return windows
    }
    
    /// Check if a window participates in docking
    private func isDockableWindow(_ window: NSWindow) -> Bool {
        return window === mainWindowController?.window ||
               window === playlistWindowController?.window ||
               window === equalizerWindowController?.window ||
               window === spectrumWindowController?.window
    }
    
    /// Get all visible windows
    func visibleWindows() -> [NSWindow] {
        return allWindows()
    }
    
    // MARK: - Coordinated Miniaturize
    
    /// Temporarily attach all docked windows as child windows of the main window
    /// so they animate together into the dock as a group.
    /// Called from windowWillMiniaturize (before the animation starts).
    func attachDockedWindowsForMiniaturize(mainWindow: NSWindow) {
        let docked = findDockedWindows(to: mainWindow)
        coordinatedMiniaturizedWindows = docked
        for window in docked {
            mainWindow.addChildWindow(window, ordered: .above)
        }
    }
    
    /// Remove child window relationships after the main window is restored from dock,
    /// so windows become independent again for normal docking/dragging behavior.
    /// Called from windowDidDeminiaturize.
    func detachDockedWindowsAfterDeminiaturize(mainWindow: NSWindow) {
        for window in coordinatedMiniaturizedWindows {
            mainWindow.removeChildWindow(window)
        }
        coordinatedMiniaturizedWindows.removeAll()
    }
    
    // MARK: - State Persistence
    
    func saveWindowPositions() {
        let defaults = UserDefaults.standard
        
        if let frame = mainWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "MainWindowFrame")
        }
        if let frame = playlistWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "PlaylistWindowFrame")
        }
        if let frame = equalizerWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "EqualizerWindowFrame")
        }
        if let frame = plexBrowserWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "PlexBrowserWindowFrame")
        }
        if let frame = videoPlayerWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "VideoPlayerWindowFrame")
        }
        if let frame = projectMWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "ProjectMWindowFrame")
        }
        if let frame = spectrumWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "SpectrumWindowFrame")
        }
    }
    
    func restoreWindowPositions() {
        let defaults = UserDefaults.standard
        
        if let frameString = defaults.string(forKey: "MainWindowFrame"),
           let window = mainWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
        if let frameString = defaults.string(forKey: "PlaylistWindowFrame"),
           let window = playlistWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
        if let frameString = defaults.string(forKey: "EqualizerWindowFrame"),
           let window = equalizerWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
        if let frameString = defaults.string(forKey: "PlexBrowserWindowFrame"),
           let window = plexBrowserWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
        if let frameString = defaults.string(forKey: "VideoPlayerWindowFrame"),
           let window = videoPlayerWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
        if let frameString = defaults.string(forKey: "ProjectMWindowFrame"),
           let window = projectMWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
        if let frameString = defaults.string(forKey: "SpectrumWindowFrame"),
           let window = spectrumWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
    }
}