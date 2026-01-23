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
    
    /// Double size mode (2x scaling) - not persisted, always starts at 1x
    var isDoubleSize: Bool = false {
        didSet {
            applyDoubleSize()
            NotificationCenter.default.post(name: .doubleSizeDidChange, object: nil)
        }
    }
    
    /// Always on top mode (floating window level)
    var isAlwaysOnTop: Bool = false {
        didSet {
            UserDefaults.standard.set(isAlwaysOnTop, forKey: "isAlwaysOnTop")
            applyAlwaysOnTop()
        }
    }
    
    /// Main player window controller
    private(set) var mainWindowController: MainWindowController?
    
    /// Playlist window controller
    private(set) var playlistWindowController: PlaylistWindowController?
    
    /// Equalizer window controller
    private(set) var equalizerWindowController: EQWindowController?
    
    /// Plex browser window controller (also handles local media library)
    private var plexBrowserWindowController: PlexBrowserWindowController?
    
    /// Video player window controller
    private var videoPlayerWindowController: VideoPlayerWindowController?
    
    /// Milkdrop visualization window controller
    private var milkdropWindowController: MilkdropWindowController?
    
    
    /// Video playback time tracking
    private(set) var videoCurrentTime: TimeInterval = 0
    private(set) var videoDuration: TimeInterval = 0
    private(set) var videoTitle: String?
    
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
        isAlwaysOnTop = UserDefaults.standard.bool(forKey: "isAlwaysOnTop")
    }
    
    // MARK: - Window Management
    
    func showMainWindow() {
        if mainWindowController == nil {
            mainWindowController = MainWindowController()
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
            playlistWindowController = PlaylistWindowController()
        }
        
        // Position newly created windows
        if isNewWindow, let playlistWindow = playlistWindowController?.window {
            if let frame = restoredFrame, frame != .zero {
                // Use restored frame from state restoration
                playlistWindow.setFrame(frame, display: true)
            } else {
                // Position relative to main window
                positionSubWindow(playlistWindow, preferBelowEQ: false)
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
            equalizerWindowController = EQWindowController()
        }
        
        // Position newly created windows
        if isNewWindow, let eqWindow = equalizerWindowController?.window {
            if let frame = restoredFrame, frame != .zero {
                // Use restored frame from state restoration
                eqWindow.setFrame(frame, display: true)
            } else {
                // Position relative to main window
                positionSubWindow(eqWindow, preferBelowEQ: true)
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
    
    /// Position a sub-window (EQ or Playlist) snapped below the main window stack
    /// - Parameters:
    ///   - window: The window to position
    ///   - preferBelowEQ: If true and EQ is visible, position below EQ. If false and Playlist is visible, position below Playlist.
    private func positionSubWindow(_ window: NSWindow, preferBelowEQ: Bool) {
        guard let mainWindow = mainWindowController?.window else { return }
        
        let mainFrame = mainWindow.frame
        
        // Match the main window's width
        let targetWidth = mainFrame.width
        let currentHeight = window.frame.height
        
        // Determine the anchor window (the window we'll position below)
        var anchorFrame = mainFrame
        
        // Check if the other sub-window is already visible
        if preferBelowEQ {
            // We're showing EQ - check if Playlist is visible
            if let playlistWindow = playlistWindowController?.window, playlistWindow.isVisible {
                anchorFrame = playlistWindow.frame
            }
        } else {
            // We're showing Playlist - check if EQ is visible
            if let eqWindow = equalizerWindowController?.window, eqWindow.isVisible {
                anchorFrame = eqWindow.frame
            }
        }
        
        // Position directly below the anchor window, left-aligned
        let newOrigin = NSPoint(
            x: anchorFrame.minX,
            y: anchorFrame.minY - currentHeight  // Below the anchor
        )
        
        // Set the frame with matched width
        let newFrame = NSRect(
            origin: newOrigin,
            size: NSSize(width: targetWidth, height: currentHeight)
        )
        
        window.setFrame(newFrame, display: true)
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
            plexBrowserWindowController = PlexBrowserWindowController()
        }
        plexBrowserWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(plexBrowserWindowController?.window)
        
        // Position newly created windows
        if isNewWindow, let window = plexBrowserWindowController?.window {
            if let frame = restoredFrame, frame != .zero {
                // Use restored frame from state restoration
                window.setFrame(frame, display: true)
            } else if let mainWindow = mainWindowController?.window {
                // Position relative to main window
                let mainFrame = mainWindow.frame
                let newFrame = NSRect(
                    x: mainFrame.maxX,
                    y: mainFrame.maxY - window.frame.height,
                    width: window.frame.width,
                    height: window.frame.height
                )
                window.setFrame(newFrame, display: true)
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
    
    /// Get the Milkdrop window frame (for state saving)
    var milkdropWindowFrame: NSRect? {
        return milkdropWindowController?.window?.frame
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
        videoPlayerWindowController?.play(url: url, title: title)
        applyAlwaysOnTopToWindow(videoPlayerWindowController?.window)
    }
    
    /// Play a Plex movie in the video player
    func playMovie(_ movie: PlexMovie) {
        if videoPlayerWindowController == nil {
            videoPlayerWindowController = VideoPlayerWindowController()
        }
        videoPlayerWindowController?.play(movie: movie)
        applyAlwaysOnTopToWindow(videoPlayerWindowController?.window)
    }
    
    /// Play a Plex episode in the video player
    func playEpisode(_ episode: PlexEpisode) {
        if videoPlayerWindowController == nil {
            videoPlayerWindowController = VideoPlayerWindowController()
        }
        videoPlayerWindowController?.play(episode: episode)
        applyAlwaysOnTopToWindow(videoPlayerWindowController?.window)
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
        videoPlayerWindowController?.currentTitle
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
        videoPlayerWindowController?.togglePlayPause()
    }
    
    /// Stop video playback
    func stopVideo() {
        videoPlayerWindowController?.stop()
    }
    
    /// Skip video forward
    func skipVideoForward(_ seconds: TimeInterval = 10) {
        videoPlayerWindowController?.skipForward(seconds)
    }
    
    /// Skip video backward
    func skipVideoBackward(_ seconds: TimeInterval = 10) {
        videoPlayerWindowController?.skipBackward(seconds)
    }
    
    /// Seek video to specific time
    func seekVideo(to time: TimeInterval) {
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
    
    /// Whether video is the active playback source (video is playing)
    var isVideoActivePlayback: Bool {
        return isVideoPlaying
    }
    
    /// Get current video playback state for main window display
    var videoPlaybackState: PlaybackState {
        guard let controller = videoPlayerWindowController else { return .stopped }
        return controller.isPlaying ? .playing : .paused
    }
    
    // MARK: - Milkdrop Visualization Window
    
    func showMilkdrop(at restoredFrame: NSRect? = nil) {
        let isNewWindow = milkdropWindowController == nil
        if isNewWindow {
            milkdropWindowController = MilkdropWindowController()
        }
        milkdropWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(milkdropWindowController?.window)
        
        // Position newly created windows
        if isNewWindow, let window = milkdropWindowController?.window {
            if let frame = restoredFrame, frame != .zero {
                // Use restored frame from state restoration
                window.setFrame(frame, display: true)
            } else if let mainWindow = mainWindowController?.window {
                // Position relative to main window
                let mainFrame = mainWindow.frame
                let newFrame = NSRect(
                    x: mainFrame.minX - window.frame.width,
                    y: mainFrame.maxY - window.frame.height,
                    width: window.frame.width,
                    height: window.frame.height
                )
                window.setFrame(newFrame, display: true)
            }
        }
    }
    
    var isMilkdropVisible: Bool {
        milkdropWindowController?.window?.isVisible == true
    }
    
    func toggleMilkdrop() {
        if let controller = milkdropWindowController, controller.window?.isVisible == true {
            controller.window?.orderOut(nil)
        } else {
            showMilkdrop()
        }
    }
    
    // MARK: - Visualization Settings
    
    /// Whether projectM visualization is available
    var isProjectMAvailable: Bool {
        milkdropWindowController?.isProjectMAvailable ?? false
    }
    
    /// Total number of visualization presets
    var visualizationPresetCount: Int {
        milkdropWindowController?.presetCount ?? 0
    }
    
    /// Get information about loaded presets (bundled count, custom count, custom path)
    var visualizationPresetsInfo: (bundledCount: Int, customCount: Int, customPath: String?) {
        milkdropWindowController?.presetsInfo ?? (0, 0, nil)
    }
    
    /// Reload all visualization presets from bundled and custom folders
    func reloadVisualizationPresets() {
        milkdropWindowController?.reloadPresets()
    }

    func notifyMainWindowVisibilityChanged() {
        mainWindowController?.windowVisibilityDidChange()
    }
    
    // MARK: - Skin Management
    
    /// When true, Browser and Milkdrop windows always use default skin (default: false - follow skin changes)
    var lockBrowserMilkdropSkin: Bool {
        get {
            // Default to false (unlocked) - windows follow skin changes by default
            if UserDefaults.standard.object(forKey: "lockBrowserMilkdropSkin") == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: "lockBrowserMilkdropSkin")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "lockBrowserMilkdropSkin")
            // Refresh these windows when setting changes
            plexBrowserWindowController?.skinDidChange()
            milkdropWindowController?.skinDidChange()
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
            notifySkinChanged()
        } catch {
            print("Failed to load skin: \(error)")
        }
    }
    
    private func loadDefaultSkin() {
        currentSkin = SkinLoader.shared.loadDefault()
    }
    
    /// Load the base/default skin (Base Skin 1)
    func loadBaseSkin() {
        currentSkin = SkinLoader.shared.loadDefault()
        currentSkinPath = nil  // Base skins don't have a custom path
        notifySkinChanged()
    }
    
    /// Load the second built-in skin (Base Skin 2)
    func loadBaseSkin2() {
        currentSkin = SkinLoader.shared.loadBaseSkin2()
        currentSkinPath = nil  // Base skins don't have a custom path
        notifySkinChanged()
    }
    
    /// Load the third built-in skin (Base Skin 3)
    func loadBaseSkin3() {
        currentSkin = SkinLoader.shared.loadBaseSkin3()
        currentSkinPath = nil  // Base skins don't have a custom path
        notifySkinChanged()
    }
    
    private func notifySkinChanged() {
        // Notify all windows to redraw with new skin
        mainWindowController?.skinDidChange()
        playlistWindowController?.skinDidChange()
        equalizerWindowController?.skinDidChange()
        plexBrowserWindowController?.skinDidChange()
        milkdropWindowController?.skinDidChange()
    }
    
    // MARK: - Skin Discovery
    
    /// Application Support directory for AdAmp
    var applicationSupportURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("AdAmp")
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
        let scale: CGFloat = isDoubleSize ? 2.0 : 1.0
        
        // Get main window position as anchor point
        guard let mainWindow = mainWindowController?.window else { return }
        
        // Store old main window frame for calculating relative positions
        let oldMainFrame = mainWindow.frame
        
        // Resize main window first (anchor top-left)
        let mainTargetSize = NSSize(width: Skin.mainWindowSize.width * scale,
                                    height: Skin.mainWindowSize.height * scale)
        var mainFrame = mainWindow.frame
        let mainTopY = mainFrame.maxY  // Keep top edge fixed
        mainFrame.size = mainTargetSize
        mainFrame.origin.y = mainTopY - mainTargetSize.height
        mainWindow.setFrame(mainFrame, display: true, animate: true)
        
        // Track the bottom edge for stacking windows below main
        var nextY = mainFrame.minY
        
        // EQ window - position below main window
        if let eqWindow = equalizerWindowController?.window, eqWindow.isVisible {
            let eqTargetSize = NSSize(width: Skin.eqWindowSize.width * scale,
                                      height: Skin.eqWindowSize.height * scale)
            let eqFrame = NSRect(
                x: mainFrame.minX,
                y: nextY - eqTargetSize.height,
                width: eqTargetSize.width,
                height: eqTargetSize.height
            )
            eqWindow.setFrame(eqFrame, display: true, animate: true)
            nextY = eqFrame.minY
        }
        
        // Playlist - position below EQ (or main if no EQ)
        if let playlistWindow = playlistWindowController?.window, playlistWindow.isVisible {
            let baseMinSize = Skin.playlistMinSize
            let minWidth = baseMinSize.width * scale
            let minHeight = baseMinSize.height * scale
            playlistWindow.minSize = NSSize(width: minWidth, height: minHeight)
            
            // Scale current size
            let currentFrame = playlistWindow.frame
            let newWidth = max(minWidth, currentFrame.width * (isDoubleSize ? 2.0 : 0.5))
            let newHeight = max(minHeight, currentFrame.height * (isDoubleSize ? 2.0 : 0.5))
            
            let playlistFrame = NSRect(
                x: mainFrame.minX,
                y: nextY - newHeight,
                width: newWidth,
                height: newHeight
            )
            playlistWindow.setFrame(playlistFrame, display: true, animate: true)
        }
        
        // Browser - maintain relative position to main window (don't scale size)
        if let plexWindow = plexBrowserWindowController?.window, plexWindow.isVisible {
            var plexFrame = plexWindow.frame
            // Calculate offset from old main window
            let offsetX = plexFrame.minX - oldMainFrame.maxX
            let offsetY = plexFrame.maxY - oldMainFrame.maxY
            // Apply same offset to new main window position
            plexFrame.origin.x = mainFrame.maxX + offsetX
            plexFrame.origin.y = mainFrame.maxY + offsetY - plexFrame.height
            plexWindow.setFrame(plexFrame, display: true, animate: true)
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
        milkdropWindowController?.window?.level = level
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
            milkdropWindowController?.window
        ]
        
        for window in windows {
            if let window = window, window.isVisible {
                window.orderFront(nil)
            }
        }
    }
    
    /// Reset all windows to their default positions
    func snapToDefaultPositions() {
        let defaults = UserDefaults.standard
        
        // Get screen for positioning
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        
        // Calculate centered main window position
        let mainSize = Skin.mainWindowSize
        let mainFrame = NSRect(
            x: screenFrame.midX - mainSize.width / 2,
            y: screenFrame.midY - mainSize.height / 2,
            width: mainSize.width,
            height: mainSize.height
        )
        
        // Calculate default positions for all windows based on main window
        // EQ goes directly below main
        let eqSize = Skin.eqWindowSize
        let eqFrame = NSRect(
            x: mainFrame.minX,
            y: mainFrame.minY - eqSize.height,
            width: mainSize.width,  // EQ width matches main
            height: eqSize.height
        )
        
        // Playlist goes below EQ
        let playlistHeight = playlistWindowController?.window?.frame.height ?? 116
        let playlistFrame = NSRect(
            x: mainFrame.minX,
            y: eqFrame.minY - playlistHeight,
            width: mainSize.width,  // Playlist width matches main
            height: playlistHeight
        )
        
        // Browser goes to the right of main, top-aligned
        let browserSize = plexBrowserWindowController?.window?.frame.size ?? NSSize(width: 550, height: mainSize.height * 3)
        let browserFrame = NSRect(
            x: mainFrame.maxX,
            y: mainFrame.maxY - browserSize.height,
            width: browserSize.width,
            height: browserSize.height
        )
        
        // Milkdrop goes to the left of main, top-aligned
        let milkdropSize = milkdropWindowController?.window?.frame.size ?? SkinElements.Milkdrop.defaultSize
        let milkdropFrame = NSRect(
            x: mainFrame.minX - milkdropSize.width,
            y: mainFrame.maxY - milkdropSize.height,
            width: milkdropSize.width,
            height: milkdropSize.height
        )
        
        // Clear any saved positions (windows will be positioned relative to main on open)
        defaults.removeObject(forKey: "MainWindowFrame")
        defaults.removeObject(forKey: "EqualizerWindowFrame")
        defaults.removeObject(forKey: "PlaylistWindowFrame")
        defaults.removeObject(forKey: "PlexBrowserWindowFrame")
        defaults.removeObject(forKey: "MilkdropWindowFrame")
        defaults.removeObject(forKey: "VideoPlayerWindowFrame")
        defaults.removeObject(forKey: "ArtVisualizerWindowFrame")
        
        // Apply positions to visible windows with animation
        if let mainWindow = mainWindowController?.window {
            mainWindow.setFrame(mainFrame, display: true, animate: true)
        }
        
        if let eqWindow = equalizerWindowController?.window, eqWindow.isVisible {
            eqWindow.setFrame(eqFrame, display: true, animate: true)
        }
        
        if let playlistWindow = playlistWindowController?.window, playlistWindow.isVisible {
            let frame = NSRect(
                x: playlistFrame.minX,
                y: playlistFrame.minY,
                width: playlistFrame.width,
                height: playlistWindow.frame.height  // Keep current height
            )
            playlistWindow.setFrame(frame, display: true, animate: true)
        }
        
        if let plexWindow = plexBrowserWindowController?.window, plexWindow.isVisible {
            plexWindow.setFrame(browserFrame, display: true, animate: true)
        }
        
        if let milkdropWindow = milkdropWindowController?.window, milkdropWindow.isVisible {
            milkdropWindow.setFrame(milkdropFrame, display: true, animate: true)
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
        // Only title bar drags can undock - interior drags always move the whole group
        if isTitleBarDrag && !dockedWindowsToMove.isEmpty {
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
        
        // Snap to screen edges first
        if let screen = window.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            
            // Left edge to screen left
            let leftDist = abs(frame.minX - screenFrame.minX)
            if leftDist < snapThreshold {
                if bestHorizontalSnap == nil || leftDist < bestHorizontalSnap!.distance {
                    bestHorizontalSnap = (leftDist, screenFrame.minX)
                }
            }
            
            // Right edge to screen right
            let rightDist = abs(frame.maxX - screenFrame.maxX)
            if rightDist < snapThreshold {
                if bestHorizontalSnap == nil || rightDist < bestHorizontalSnap!.distance {
                    bestHorizontalSnap = (rightDist, screenFrame.maxX - frame.width)
                }
            }
            
            // Bottom edge to screen bottom
            let bottomDist = abs(frame.minY - screenFrame.minY)
            if bottomDist < snapThreshold {
                if bestVerticalSnap == nil || bottomDist < bestVerticalSnap!.distance {
                    bestVerticalSnap = (bottomDist, screenFrame.minY)
                }
            }
            
            // Top edge to screen top
            let topDist = abs(frame.maxY - screenFrame.maxY)
            if topDist < snapThreshold {
                if bestVerticalSnap == nil || topDist < bestVerticalSnap!.distance {
                    bestVerticalSnap = (topDist, screenFrame.maxY - frame.height)
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
    private func findDockedWindows(to window: NSWindow) -> [NSWindow] {
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
        if let w = milkdropWindowController?.window, w.isVisible { windows.append(w) }
        return windows
    }
    
    /// Get windows that participate in docking/snapping together (classic Winamp windows)
    private func dockableWindows() -> [NSWindow] {
        var windows: [NSWindow] = []
        if let w = mainWindowController?.window, w.isVisible { windows.append(w) }
        if let w = playlistWindowController?.window, w.isVisible { windows.append(w) }
        if let w = equalizerWindowController?.window, w.isVisible { windows.append(w) }
        return windows
    }
    
    /// Check if a window participates in docking
    private func isDockableWindow(_ window: NSWindow) -> Bool {
        return window === mainWindowController?.window ||
               window === playlistWindowController?.window ||
               window === equalizerWindowController?.window
    }
    
    /// Get all visible windows
    func visibleWindows() -> [NSWindow] {
        return allWindows()
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
        if let frame = milkdropWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "MilkdropWindowFrame")
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
        if let frameString = defaults.string(forKey: "MilkdropWindowFrame"),
           let window = milkdropWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
    }
}