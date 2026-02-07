import AppKit
@preconcurrency import KSPlayer

/// Window controller for video playback with KSPlayer and skinned UI
class VideoPlayerWindowController: NSWindowController, NSWindowDelegate {
    
    // MARK: - Properties
    
    private var videoPlayerView: VideoPlayerView!
    
    /// Local event monitor for keyboard shortcuts
    private var localEventMonitor: Any?
    
    /// Whether video is currently playing
    private(set) var isPlaying: Bool = false
    
    /// Flag to prevent recursive stop/close calls
    private var isClosing: Bool = false
    
    /// Current video title
    private(set) var currentTitle: String?
    
    /// Current Plex movie (if playing Plex content)
    private var currentPlexMovie: PlexMovie?
    
    /// Current Plex episode (if playing Plex content)
    private var currentPlexEpisode: PlexEpisode?
    
    /// Current Plex rating key (for playlist tracks that have plexRatingKey but not full movie/episode)
    private var currentPlexRatingKey: String?
    
    /// Current local video URL (for non-Plex video casting)
    private var currentLocalURL: URL?
    
    /// Public access to current Plex movie metadata (for About Playing)
    var plexMovie: PlexMovie? { currentPlexMovie }
    
    /// Public access to current Plex episode metadata (for About Playing)
    var plexEpisode: PlexEpisode? { currentPlexEpisode }
    
    /// Public access to current local video URL (for About Playing)
    var localVideoURL: URL? { currentLocalURL }
    
    /// Whether we're actively casting video from this player
    private(set) var isCastingVideo: Bool = false
    
    /// The device we're casting to (if any)
    private var castTargetDevice: CastDevice?
    
    /// Cast playback position tracking
    private var castStartPosition: TimeInterval = 0
    private var castPlaybackStartDate: Date?
    
    /// Duration of the video being cast (stored from local player before casting)
    private(set) var castDuration: TimeInterval = 0
    
    /// Timer for updating main window with cast progress
    private var castUpdateTimer: Timer?
    
    /// Whether we've received the first status update from Chromecast (prevents UI flash before sync)
    private var castHasReceivedStatus: Bool = false
    
    /// Current cast playback time (interpolated from start position)
    var castCurrentTime: TimeInterval {
        if let startDate = castPlaybackStartDate {
            let elapsed = Date().timeIntervalSince(startDate)
            return min(castStartPosition + elapsed, castDuration)
        }
        return castStartPosition
    }
    
    /// Start the cast update timer (updates main window with progress)
    /// Note: Timer only updates UI after first status received from Chromecast
    private func startCastUpdateTimer() {
        castUpdateTimer?.invalidate()
        castUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isCastingVideo else { return }
            // Don't update UI until we've received first status from Chromecast
            // This prevents showing stale/incorrect time before sync (especially for 4K on slow networks)
            guard self.castHasReceivedStatus else { return }
            let current = self.castCurrentTime
            let duration = self.castDuration
            WindowManager.shared.videoDidUpdateTime(current: current, duration: duration)
        }
        // Don't fire immediately - wait for first Chromecast status update
    }
    
    /// Stop the cast update timer
    private func stopCastUpdateTimer() {
        castUpdateTimer?.invalidate()
        castUpdateTimer = nil
    }
    
    /// Handle Chromecast media status updates for position syncing
    @objc private func handleChromecastMediaStatusUpdate(_ notification: Notification) {
        guard isCastingVideo else { return }
        guard let status = notification.userInfo?["status"] as? CastMediaStatus else { return }
        
        let isPlaying = status.playerState == .playing
        let isBuffering = status.playerState == .buffering
        
        // Mark that we've received status from Chromecast (enables UI updates)
        let isFirstStatus = !castHasReceivedStatus
        castHasReceivedStatus = true
        
        // Sync position from Chromecast
        castStartPosition = status.currentTime
        
        if isBuffering {
            // Pause interpolation during buffering
            castPlaybackStartDate = nil
        } else if isPlaying {
            // Playing - start/restart interpolation from this position
            castPlaybackStartDate = Date()
        } else {
            // Paused or idle
            castPlaybackStartDate = nil
        }
        
        // Update duration if provided
        if let duration = status.duration, duration > 0 {
            castDuration = duration
        }
        
        // On first status, immediately update UI with correct position
        if isFirstStatus {
            WindowManager.shared.videoDidUpdateTime(current: castCurrentTime, duration: castDuration)
        }
    }
    
    /// Reset cast state when starting a new video
    /// This ensures the player doesn't think it's still casting from a previous session
    private func resetCastState() {
        if isCastingVideo {
            stopCastUpdateTimer()
            // Unsubscribe from Chromecast status updates
            NotificationCenter.default.removeObserver(
                self,
                name: ChromecastManager.mediaStatusDidUpdateNotification,
                object: nil
            )
            isCastingVideo = false
            castTargetDevice = nil
            castStartPosition = 0
            castPlaybackStartDate = nil
            castHasReceivedStatus = false
            castDuration = 0
        }
    }
    
    /// Callback for when video finishes playing (for playlist integration)
    var onVideoFinishedForPlaylist: (() -> Void)?
    
    /// Flag to track if this video was started from the playlist
    private var isFromPlaylist: Bool = false
    
    /// Current playback time
    var currentTime: TimeInterval {
        return videoPlayerView.currentPlaybackTime
    }
    
    /// Video duration
    var duration: TimeInterval {
        return videoPlayerView.totalPlaybackDuration
    }
    
    /// Volume level (0.0 - 1.0)
    var volume: Float {
        get { videoPlayerView.volume }
        set { videoPlayerView.volume = newValue }
    }
    
    // MARK: - Static Configuration
    
    /// Configure KSPlayer globally (call once at app startup)
    static func configureKSPlayer() {
        // Use FFmpeg-only backend for consistent behavior across all formats
        // KSMEPlayer is the FFmpeg-based player, KSAVPlayer is the AVPlayer-based one
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = nil  // No fallback - use FFmpeg only
        
        // Enable hardware acceleration
        KSOptions.hardwareDecode = true
        
        // Configure playback behavior
        KSOptions.isAutoPlay = true
        KSOptions.isSecondOpen = false
        
        NSLog("VideoPlayerWindowController: KSPlayer configured for FFmpeg-only playback")
    }
    
    // MARK: - Initialization
    
    init() {
        // Create a borderless resizable window for video playback
        let contentRect = NSRect(x: 0, y: 0, width: 854, height: 480)
        let styleMask: NSWindow.StyleMask = [.borderless, .resizable, .fullSizeContentView]
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        window.title = "Video Player"
        window.minSize = NSSize(width: 480, height: 270)
        window.isReleasedWhenClosed = false
        window.center()
        
        // Dark appearance for video
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        
        // Allow window to be moved by dragging anywhere (though we handle title bar specifically)
        window.isMovableByWindowBackground = false
        
        // Allow resizing from edges
        window.isOpaque = true
        window.hasShadow = true
        
        // Enable fullscreen support for borderless window
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        
        super.init(window: window)
        
        setupVideoView()
        window.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupVideoView() {
        // Ensure content view has black background to prevent any white pixels
        window?.contentView?.wantsLayer = true
        window?.contentView?.layer?.backgroundColor = NSColor.black.cgColor
        
        videoPlayerView = VideoPlayerView(frame: window!.contentView!.bounds)
        videoPlayerView.autoresizingMask = [.width, .height]
        window?.contentView?.addSubview(videoPlayerView)
        
        // Set up callbacks for window controls
        videoPlayerView.onClose = { [weak self] in
            self?.close()
        }
        
        videoPlayerView.onMinimize = { [weak self] in
            self?.window?.miniaturize(nil)
        }
        
        // Track playback state changes
        videoPlayerView.onPlaybackStateChanged = { [weak self] playing in
            self?.updatePlayingState(playing)
        }
        
        // Track pause/resume for Plex reporting
        videoPlayerView.onPlaybackPaused = { [weak self] position in
            guard let self = self, self.isPlexContent else { return }
            PlexVideoPlaybackReporter.shared.videoDidPause(at: position)
        }
        
        videoPlayerView.onPlaybackResumed = { [weak self] position in
            guard let self = self, self.isPlexContent else { return }
            PlexVideoPlaybackReporter.shared.videoDidResume(at: position)
        }
        
        // Track position updates for Plex reporting
        videoPlayerView.onPositionUpdate = { [weak self] position in
            guard let self = self, self.isPlexContent else { return }
            PlexVideoPlaybackReporter.shared.updatePosition(position)
        }
        
        // Track playback completion for Plex scrobbling and playlist advancement
        videoPlayerView.onPlaybackFinished = { [weak self] position in
            guard let self = self else { return }
            
            // Report to Plex if playing Plex content
            if self.isPlexContent {
                PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: true)
            }
            
            // Advance playlist if this video was from the playlist
            if self.isFromPlaylist {
                NSLog("VideoPlayer: Video finished from playlist, invoking callback")
                self.isFromPlaylist = false
                // Capture and clear callback BEFORE invoking to prevent clearing a newly-set callback
                // (the callback may load the next video which sets a new callback)
                let callback = self.onVideoFinishedForPlaylist
                self.onVideoFinishedForPlaylist = nil
                callback?()
            }
        }
        
        // Cast button callback
        videoPlayerView.onCast = { [weak self] in
            self?.showCastMenu()
        }
        
        // Stop button callback
        videoPlayerView.onStop = { [weak self] in
            self?.stop()
        }
        
        // Control callbacks for casting intercept
        videoPlayerView.onPlayPauseToggled = { [weak self] in
            self?.togglePlayPause()
        }
        videoPlayerView.onSeekRequested = { [weak self] position in
            self?.handleSeekRequest(position)
        }
        videoPlayerView.onSkipForwardRequested = { [weak self] seconds in
            self?.skipForward(seconds)
        }
        videoPlayerView.onSkipBackwardRequested = { [weak self] seconds in
            self?.skipBackward(seconds)
        }
        
        // Set up local event monitor for keyboard shortcuts (especially Escape in fullscreen)
        setupKeyboardMonitor()
    }
    
    /// Whether current content is from Plex
    private var isPlexContent: Bool {
        currentPlexMovie != nil || currentPlexEpisode != nil || currentPlexRatingKey != nil
    }
    
    private func setupKeyboardMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  let window = self.window else {
                return event
            }
            
            // Check if our window is the main window or is in fullscreen
            let isOurWindow = window.isKeyWindow || window.isMainWindow || window.styleMask.contains(.fullScreen)
            guard isOurWindow else {
                return event
            }
            
            NSLog("VideoPlayer keyDown: keyCode=%d, isFullScreen=%d", event.keyCode, window.styleMask.contains(.fullScreen) ? 1 : 0)
            
            // Check for Cmd+S to open track selection panel
            if event.keyCode == 1 && event.modifierFlags.contains(.command) { // Cmd+S
                self.videoPlayerView.showTrackSelectionPanel()
                return nil
            }
            
            switch event.keyCode {
            case 53: // Escape
                NSLog("VideoPlayer: Escape pressed, fullscreen=%d", window.styleMask.contains(.fullScreen) ? 1 : 0)
                if window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                    return nil // Consume the event
                } else {
                    // If track selection panel is visible, close it instead of the window
                    if self.videoPlayerView.trackSelectionPanelVisible {
                        self.videoPlayerView.hideTrackSelectionPanel()
                        return nil
                    }
                    self.close()
                    return nil
                }
            case 49: // Space - toggle play/pause
                self.togglePlayPause()
                return nil
            case 3: // F key - toggle fullscreen
                window.toggleFullScreen(nil)
                return nil
            case 1: // S key - cycle subtitles
                self.videoPlayerView.cycleSubtitleTrack()
                return nil
            case 0: // A key - cycle audio tracks
                self.videoPlayerView.cycleAudioTrack()
                return nil
            case 123: // Left arrow - skip back
                self.skipBackward(10)
                return nil
            case 124: // Right arrow - skip forward
                self.skipForward(10)
                return nil
            default:
                return event
            }
        }
    }
    
    private func removeKeyboardMonitor() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
    
    // MARK: - Playback Control
    
    /// Play a video from URL with optional title
    /// If called from WindowManager.playVideoTrack, the onVideoFinishedForPlaylist callback will be set
    func play(url: URL, title: String) {
        // Reset any lingering cast state from previous video
        resetCastState()
        
        // Report stop to Plex if currently playing Plex content (before clearing state)
        if isPlexContent {
            let position = videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }
        
        // Clear any Plex content (this is a non-Plex video)
        currentPlexMovie = nil
        currentPlexEpisode = nil
        currentPlexRatingKey = nil
        
        // Store local URL for casting
        currentLocalURL = url.isFileURL ? url : nil
        
        // Check if this is being played from the playlist (callback was set)
        isFromPlaylist = onVideoFinishedForPlaylist != nil
        
        currentTitle = title
        window?.title = title
        videoPlayerView.play(url: url, title: title, isPlexURL: false, plexHeaders: nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isPlaying = true
        WindowManager.shared.videoPlaybackDidStart()
    }
    
    /// Play a Plex video track from the playlist
    /// Used when the Track has a plexRatingKey but we don't have the full PlexMovie/PlexEpisode
    func play(plexTrack track: Track) {
        guard let ratingKey = track.plexRatingKey else {
            // Fall back to regular play if no Plex rating key
            play(url: track.url, title: track.displayTitle)
            return
        }
        
        // Reset any lingering cast state from previous video
        resetCastState()
        
        // Report stop to Plex if currently playing Plex content
        if isPlexContent {
            let position = videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }
        
        // Clear movie/episode objects but keep track of the rating key for isPlexContent
        currentPlexMovie = nil
        currentPlexEpisode = nil
        currentPlexRatingKey = ratingKey
        currentLocalURL = nil  // Clear local URL when playing Plex content
        
        // Check if this is being played from the playlist (callback was set)
        isFromPlaylist = onVideoFinishedForPlaylist != nil
        
        // Get Plex streaming headers
        let headers = PlexManager.shared.streamingHeaders
        
        currentTitle = track.displayTitle
        window?.title = track.displayTitle
        videoPlayerView.play(url: track.url, title: track.displayTitle, isPlexURL: true, plexHeaders: headers)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isPlaying = true
        WindowManager.shared.videoPlaybackDidStart()
        
        // Start Plex playback reporting
        PlexVideoPlaybackReporter.shared.videoTrackDidStart(
            ratingKey: ratingKey,
            title: track.displayTitle,
            durationSeconds: track.duration ?? 0
        )
        
        NSLog("VideoPlayerWindowController: Playing Plex track from playlist: %@ (key: %@)", track.displayTitle, ratingKey)
    }
    
    /// Play a Plex movie
    func play(movie: PlexMovie) {
        // Reset any lingering cast state from previous video
        resetCastState()
        
        // Report stop to Plex if currently playing Plex content (before starting new video)
        if isPlexContent {
            let position = videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }
        
        guard let url = PlexManager.shared.streamURL(for: movie) else {
            NSLog("Failed to get stream URL for movie: %@", movie.title)
            return
        }
        
        // Get full streaming headers (required for remote/relay connections)
        let headers = PlexManager.shared.streamingHeaders
        NSLog("Playing Plex movie: %@ with URL: %@", movie.title, url.absoluteString)
        
        // Store Plex content for reporting
        currentPlexMovie = movie
        currentPlexEpisode = nil
        currentPlexRatingKey = nil
        currentLocalURL = nil  // Clear local URL when playing Plex content
        
        currentTitle = movie.title
        window?.title = movie.title
        videoPlayerView.play(url: url, title: movie.title, isPlexURL: true, plexHeaders: headers)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isPlaying = true
        WindowManager.shared.videoPlaybackDidStart()
        
        // Start Plex playback reporting
        PlexVideoPlaybackReporter.shared.movieDidStart(movie)
        
        // Pass Plex streams for external subtitle support
        let allStreams = movie.media.flatMap { $0.parts.flatMap { $0.streams } }
        videoPlayerView.setPlexStreams(allStreams)
    }
    
    /// Play a Plex episode
    func play(episode: PlexEpisode) {
        // Reset any lingering cast state from previous video
        resetCastState()
        
        // Report stop to Plex if currently playing Plex content (before starting new video)
        if isPlexContent {
            let position = videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }
        
        guard let url = PlexManager.shared.streamURL(for: episode) else {
            NSLog("Failed to get stream URL for episode: %@", episode.title)
            return
        }
        
        // Get full streaming headers (required for remote/relay connections)
        let headers = PlexManager.shared.streamingHeaders
        let title = "\(episode.grandparentTitle ?? "Unknown") - \(episode.episodeIdentifier) - \(episode.title)"
        NSLog("Playing Plex episode: %@ with URL: %@", title, url.absoluteString)
        
        // Store Plex content for reporting
        currentPlexMovie = nil
        currentPlexEpisode = episode
        currentPlexRatingKey = nil
        currentLocalURL = nil  // Clear local URL when playing Plex content
        
        currentTitle = title
        window?.title = title
        videoPlayerView.play(url: url, title: title, isPlexURL: true, plexHeaders: headers)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isPlaying = true
        WindowManager.shared.videoPlaybackDidStart()
        
        // Start Plex playback reporting
        PlexVideoPlaybackReporter.shared.episodeDidStart(episode)
        
        // Pass Plex streams for external subtitle support
        let allStreams = episode.media.flatMap { $0.parts.flatMap { $0.streams } }
        videoPlayerView.setPlexStreams(allStreams)
    }
    
    /// Stop playback
    func stop() {
        guard !isClosing else { return }
        isClosing = true
        
        // Capture cast position before stopping (for Plex reporting)
        let wasCasting = isCastingVideo
        let castPosition = wasCasting ? castCurrentTime : 0
        
        // Stop casting if active (this will exit the movie on the TV)
        // Use semaphore to wait for cast stop to complete before closing
        if isCastingVideo {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await CastManager.shared.stopCasting()
                NSLog("VideoPlayerWindowController: Stopped video cast on TV")
                semaphore.signal()
            }
            // Wait up to 2 seconds for cast to stop
            _ = semaphore.wait(timeout: .now() + 2.0)
            
            stopCastUpdateTimer()
            isCastingVideo = false
            castTargetDevice = nil
            castStartPosition = 0
            castPlaybackStartDate = nil
            castDuration = 0
        }
        
        // Report stop to Plex if playing Plex content
        if isPlexContent {
            let position = wasCasting ? castPosition : videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }
        
        videoPlayerView.stop()
        isPlaying = false
        currentTitle = nil
        currentPlexMovie = nil
        currentPlexEpisode = nil
        currentPlexRatingKey = nil
        WindowManager.shared.videoPlaybackDidStop()
        close()
    }
    
    /// Toggle play/pause
    func togglePlayPause() {
        if isCastingVideo {
            toggleCastPlayPause()
        } else {
            videoPlayerView.togglePlayPause()
        }
    }
    
    /// Skip forward
    func skipForward(_ seconds: TimeInterval = 10) {
        if isCastingVideo {
            seekCastRelative(seconds)
        } else {
            videoPlayerView.skipForward(seconds)
        }
    }
    
    /// Skip backward
    func skipBackward(_ seconds: TimeInterval = 10) {
        if isCastingVideo {
            seekCastRelative(-seconds)
        } else {
            videoPlayerView.skipBackward(seconds)
        }
    }
    
    /// Seek to specific time
    func seek(to time: TimeInterval) {
        NSLog("VideoPlayerWindowController.seek: time=%.1f, isCastingVideo=%d", time, isCastingVideo ? 1 : 0)
        if isCastingVideo {
            seekCast(to: time)
        } else {
            videoPlayerView.seek(to: time)
        }
    }
    
    /// Handle seek request from slider (normalized 0-1 position)
    private func handleSeekRequest(_ position: Double) {
        if isCastingVideo {
            // For casting, we need to convert position to time
            // Use duration from the original video
            let time = position * duration
            seekCast(to: time)
        } else {
            videoPlayerView.seekToPosition(position)
        }
    }
    
    // MARK: - Cast Playback Control
    
    /// Toggle play/pause on the cast device
    private func toggleCastPlayPause() {
        Task {
            do {
                if CastManager.shared.activeSession?.state == .casting {
                    if isPlaying {
                        try await CastManager.shared.pause()
                        await MainActor.run {
                            // Save current position before pausing
                            if let startDate = castPlaybackStartDate {
                                castStartPosition += Date().timeIntervalSince(startDate)
                            }
                            castPlaybackStartDate = nil
                            isPlaying = false
                            videoPlayerView.updateCastState(isPlaying: false, deviceName: castTargetDevice?.name)
                        }
                    } else {
                        try await CastManager.shared.resume()
                        await MainActor.run {
                            // Resume time tracking
                            castPlaybackStartDate = Date()
                            isPlaying = true
                            videoPlayerView.updateCastState(isPlaying: true, deviceName: castTargetDevice?.name)
                        }
                    }
                }
            } catch {
                NSLog("VideoPlayerWindowController: Cast toggle failed: %@", error.localizedDescription)
            }
        }
    }
    
    /// Seek relative on cast device (for skip forward/backward)
    private func seekCastRelative(_ seconds: TimeInterval) {
        Task {
            do {
                let newPosition = max(0, min(castCurrentTime + seconds, castDuration))
                try await CastManager.shared.seek(to: newPosition)
                
                // Update local tracking
                await MainActor.run {
                    castStartPosition = newPosition
                    castPlaybackStartDate = isPlaying ? Date() : nil
                }
                
                NSLog("VideoPlayerWindowController: Cast seek to %.1f (relative %.1f)", newPosition, seconds)
            } catch {
                NSLog("VideoPlayerWindowController: Cast seek failed: %@", error.localizedDescription)
            }
        }
    }
    
    /// Seek to absolute position on cast device
    private func seekCast(to time: TimeInterval) {
        Task {
            do {
                let clampedTime = max(0, min(time, castDuration))
                try await CastManager.shared.seek(to: clampedTime)
                
                // Update local tracking
                await MainActor.run {
                    castStartPosition = clampedTime
                    castPlaybackStartDate = isPlaying ? Date() : nil
                }
                
                NSLog("VideoPlayerWindowController: Cast seek to %.1f", clampedTime)
            } catch {
                NSLog("VideoPlayerWindowController: Cast seek failed: %@", error.localizedDescription)
            }
        }
    }
    
    /// Update playing state (called from VideoPlayerView)
    func updatePlayingState(_ playing: Bool) {
        isPlaying = playing
    }
    
    // MARK: - Video Casting
    
    /// Show cast device menu
    private func showCastMenu() {
        let menu = NSMenu()
        
        // If currently casting, show stop option first
        if isCastingVideo, let device = castTargetDevice {
            let castingItem = NSMenuItem(title: "Casting to \(device.name)", action: nil, keyEquivalent: "")
            castingItem.isEnabled = false
            menu.addItem(castingItem)
            
            let stopItem = NSMenuItem(title: "Stop Casting", action: #selector(stopCasting), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
            
            menu.addItem(NSMenuItem.separator())
        }
        
        // Get video-capable devices
        let devices = CastManager.shared.videoCapableDevices
        
        if devices.isEmpty {
            let item = NSMenuItem(title: "No devices found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            // Group by type
            let chromecasts = devices.filter { $0.type == .chromecast }
            let dlnaTVs = devices.filter { $0.type == .dlnaTV }
            
            if !chromecasts.isEmpty {
                let headerItem = NSMenuItem(title: "Chromecast", action: nil, keyEquivalent: "")
                headerItem.isEnabled = false
                menu.addItem(headerItem)
                for device in chromecasts {
                    let title = device.id == castTargetDevice?.id ? "  ✓ \(device.name)" : "  \(device.name)"
                    let item = NSMenuItem(title: title, action: #selector(castToDevice(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = device
                    // Disable if already casting to this device
                    item.isEnabled = device.id != castTargetDevice?.id
                    menu.addItem(item)
                }
            }
            
            if !dlnaTVs.isEmpty {
                if !chromecasts.isEmpty { menu.addItem(NSMenuItem.separator()) }
                let headerItem = NSMenuItem(title: "TVs", action: nil, keyEquivalent: "")
                headerItem.isEnabled = false
                menu.addItem(headerItem)
                for device in dlnaTVs {
                    let title = device.id == castTargetDevice?.id ? "  ✓ \(device.name)" : "  \(device.name)"
                    let item = NSMenuItem(title: title, action: #selector(castToDevice(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = device
                    // Disable if already casting to this device
                    item.isEnabled = device.id != castTargetDevice?.id
                    menu.addItem(item)
                }
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Refresh Devices", action: #selector(refreshCastDevices), keyEquivalent: ""))
        
        // Show menu at cast button location
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: videoPlayerView)
        }
    }
    
    @objc private func castToDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? CastDevice else { return }
        
        // Prevent dual casting - check if already casting from context menu
        if CastManager.shared.isVideoCasting {
            NSLog("VideoPlayerWindowController: Cannot cast - already casting from context menu")
            let alert = NSAlert()
            alert.messageText = "Already Casting"
            alert.informativeText = "Stop the current cast before starting a new one."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        
        Task {
            do {
                // Capture position and duration before pausing local playback
                let currentPosition = videoPlayerView.currentPlaybackTime
                let videoDuration = videoPlayerView.totalPlaybackDuration
                
                // Pause local playback (don't stop - we want to resume later)
                videoPlayerView.togglePlayPause()  // Will pause if playing
                
                // Cast based on content type
                if let movie = currentPlexMovie {
                    try await CastManager.shared.castPlexMovie(movie, to: device, startPosition: currentPosition)
                } else if let episode = currentPlexEpisode {
                    try await CastManager.shared.castPlexEpisode(episode, to: device, startPosition: currentPosition)
                } else if let url = currentURL {
                    // Local video file
                    try await CastManager.shared.castLocalVideo(url, title: currentTitle ?? "Video", to: device, startPosition: currentPosition)
                }
                
                // Update casting state and time tracking
                await MainActor.run {
                    self.isCastingVideo = true
                    self.castTargetDevice = device
                    self.isPlaying = true
                    self.castStartPosition = currentPosition
                    // Don't set castPlaybackStartDate yet - wait for PLAYING status from Chromecast
                    self.castPlaybackStartDate = nil
                    self.castHasReceivedStatus = false
                    self.castDuration = videoDuration
                    self.videoPlayerView.updateCastState(isPlaying: true, deviceName: device.name)
                    
                    // Subscribe to Chromecast status updates for position syncing
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(self.handleChromecastMediaStatusUpdate),
                        name: ChromecastManager.mediaStatusDidUpdateNotification,
                        object: nil
                    )
                    
                    self.startCastUpdateTimer()
                }
                
                NSLog("VideoPlayerWindowController: Video cast started to %@ at %.1f / %.1f", device.name, currentPosition, videoDuration)
            } catch {
                NSLog("VideoPlayerWindowController: Video cast failed: %@", error.localizedDescription)
                // Show error alert
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Cast Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    @objc private func stopCasting() {
        Task {
            // Capture current cast position before stopping
            let resumePosition = await MainActor.run { self.castCurrentTime }
            
            await CastManager.shared.stopCasting()
            
            await MainActor.run {
                self.stopCastUpdateTimer()
                self.isCastingVideo = false
                self.castTargetDevice = nil
                self.castStartPosition = 0
                self.castPlaybackStartDate = nil
                self.castDuration = 0
                self.videoPlayerView.updateCastState(isPlaying: false, deviceName: nil)
                
                // Resume local playback from where casting left off
                if resumePosition > 0 {
                    NSLog("VideoPlayerWindowController: Resuming local playback at %.1f", resumePosition)
                    self.videoPlayerView.seek(to: resumePosition)
                    self.videoPlayerView.togglePlayPause()  // Start playback
                    self.isPlaying = true
                }
            }
            
            NSLog("VideoPlayerWindowController: Video casting stopped")
        }
    }
    
    @objc private func refreshCastDevices() {
        CastManager.shared.refreshDevices()
    }
    
    /// Current URL for local video casting
    private var currentURL: URL? {
        // If we have Plex content, we don't need the local URL
        if currentPlexMovie != nil || currentPlexEpisode != nil { return nil }
        // Return the stored local URL
        return currentLocalURL
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // Stop cast update timer
        stopCastUpdateTimer()
        
        // Only do cleanup if not already handled by stop()
        if !isClosing {
            // Stop casting if active (exit movie on TV)
            // Use semaphore to wait for cast stop to complete
            if isCastingVideo {
                let semaphore = DispatchSemaphore(value: 0)
                Task {
                    await CastManager.shared.stopCasting()
                    NSLog("VideoPlayerWindowController: Stopped video cast on TV (window closed)")
                    semaphore.signal()
                }
                // Wait up to 2 seconds for cast to stop
                _ = semaphore.wait(timeout: .now() + 2.0)
                
                isCastingVideo = false
                castTargetDevice = nil
                castStartPosition = 0
                castPlaybackStartDate = nil
                castDuration = 0
            }
            
            // Report stop to Plex if playing Plex content
            if isPlexContent {
                let position = videoPlayerView.currentPlaybackTime
                PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
            }
            
            videoPlayerView.stop()
            isPlaying = false
            currentTitle = nil
            currentPlexMovie = nil
            currentPlexEpisode = nil
            currentPlexRatingKey = nil
            WindowManager.shared.videoPlaybackDidStop()
        }
        removeKeyboardMonitor()
        isClosing = false  // Reset for potential reuse
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        videoPlayerView.updateActiveState(true)
    }
    
    func windowDidResignKey(_ notification: Notification) {
        videoPlayerView.updateActiveState(false)
    }
    
    // MARK: - Keyboard Shortcuts
    
    @objc func toggleFullScreen(_ sender: Any?) {
        window?.toggleFullScreen(sender)
    }
    
    /// Handle Escape key via standard macOS cancel operation
    @objc func cancel(_ sender: Any?) {
        if let window = window, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        } else {
            close()
        }
    }
}
