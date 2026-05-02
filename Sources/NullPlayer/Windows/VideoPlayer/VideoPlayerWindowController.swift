import AppKit
import NullPlayerCore
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

    /// Timestamp when playback of the current item started (for analytics)
    private var playbackStartTime: Date?

    /// Sum of completed playback segments for the current item.
    private var accumulatedPlaybackDuration: TimeInterval = 0

    /// Content type of the currently playing item (for analytics)
    private var currentContentType: String = "video"

    /// Current video title
    private(set) var currentTitle: String?

    /// Lightweight video track used by the main window for artwork lookup.
    private(set) var currentArtworkTrack: Track?
    
    /// Current Plex movie (if playing Plex content)
    private var currentPlexMovie: PlexMovie?
    
    /// Current Plex episode (if playing Plex content)
    private var currentPlexEpisode: PlexEpisode?
    
    /// Current Plex rating key (for playlist tracks that have plexRatingKey but not full movie/episode)
    private var currentPlexRatingKey: String?
    
    /// Current local video URL (for non-Plex video casting)
    private var currentLocalURL: URL?
    
    /// Current Jellyfin movie (if playing Jellyfin content)
    private var currentJellyfinMovie: JellyfinMovie?

    /// Current Jellyfin episode (if playing Jellyfin content)
    private var currentJellyfinEpisode: JellyfinEpisode?

    /// Current Emby movie (if playing Emby content)
    private var currentEmbyMovie: EmbyMovie?

    /// Current Emby episode (if playing Emby content)
    private var currentEmbyEpisode: EmbyEpisode?

    /// Public access to current Plex movie metadata (for About Playing)
    var plexMovie: PlexMovie? { currentPlexMovie }

    /// Public access to current Plex episode metadata (for About Playing)
    var plexEpisode: PlexEpisode? { currentPlexEpisode }

    /// Public access to current Jellyfin movie metadata
    var jellyfinMovie: JellyfinMovie? { currentJellyfinMovie }

    /// Public access to current Jellyfin episode metadata
    var jellyfinEpisode: JellyfinEpisode? { currentJellyfinEpisode }

    /// Public access to current Emby movie metadata
    var embyMovie: EmbyMovie? { currentEmbyMovie }

    /// Public access to current Emby episode metadata
    var embyEpisode: EmbyEpisode? { currentEmbyEpisode }
    
    /// Public access to current local video URL (for About Playing)
    var localVideoURL: URL? { currentLocalURL }
    
    /// Whether we're actively casting video from this player
    private(set) var isCastingVideo: Bool = false

    /// True only when THIS window initiated the current cast (not a library-menu cast)
    private var didInitiateCast: Bool = false

    /// Timer for updating main window with cast progress
    private var castUpdateTimer: Timer?

    /// Last video-cast position observed before CastManager replaces or clears its session.
    private var lastKnownVideoCastPosition: TimeInterval = 0

    /// Whether local playback should resume when this controller stops its video cast.
    private var shouldResumeLocalPlaybackAfterCast = false

    /// Suppresses session-change teardown while stopCasting() handles its own cleanup/resume flow.
    private var isStoppingOwnCast = false

    /// Duration of the video being cast (read from activeSession)
    var castDuration: TimeInterval {
        CastManager.shared.activeSession?.duration ?? 0
    }

    /// Current cast playback time (interpolated from start position)
    var castCurrentTime: TimeInterval {
        guard let session = CastManager.shared.activeSession,
              session.metadata?.mediaType == .video else {
            return lastKnownVideoCastPosition
        }
        if let startDate = session.playbackStartDate {
            let elapsed = Date().timeIntervalSince(startDate)
            let current = session.position + elapsed
            return session.duration > 0 ? min(current, session.duration) : current
        }
        return session.position
    }

    @discardableResult
    private func cacheLastKnownVideoCastPosition() -> TimeInterval {
        let position = castCurrentTime
        lastKnownVideoCastPosition = position
        return position
    }
    
    /// Start the cast update timer (updates main window with progress)
    /// Note: Timer only updates UI after first status received from Chromecast
    private func startCastUpdateTimer() {
        castUpdateTimer?.invalidate()
        castUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isCastingVideo else { return }
            // Don't update UI until we've received first status from Chromecast
            // This prevents showing stale/incorrect time before sync (especially for 4K on slow networks)
            guard CastManager.shared.activeSession?.state != .loaded else { return }
            let current = self.castCurrentTime
            self.lastKnownVideoCastPosition = current
            let duration = CastManager.shared.activeSession?.duration ?? 0
            WindowManager.shared.videoDidUpdateTime(current: current, duration: duration)
        }
        // Don't fire immediately - wait for first Chromecast status update
    }
    
    /// Stop the cast update timer
    private func stopCastUpdateTimer() {
        castUpdateTimer?.invalidate()
        castUpdateTimer = nil
    }
    
    /// Handle Chromecast media status updates for playback analytics
    @objc private func handleChromecastMediaStatusUpdate(_ notification: Notification) {
        guard isCastingVideo else { return }
        guard let status = notification.userInfo?["status"] as? CastMediaStatus else { return }

        let isPlaying = status.playerState == .playing
        let isBuffering = status.playerState == .buffering
        lastKnownVideoCastPosition = status.currentTime

        // CastManager handles all session state and first-status UI updates.
        // VPWC only drives playback analytics.
        if isBuffering {
            pausePlaybackAnalytics()
        } else if isPlaying {
            resumePlaybackAnalytics()
        } else {
            pausePlaybackAnalytics()
        }
    }
    
    /// Reset cast state when starting a new video
    /// This ensures the player doesn't think it's still casting from a previous session
    private func resetCastState() {
        guard isCastingVideo else { return }
        clearVideoCastState()
    }

    private func clearVideoCastState() {
        stopCastUpdateTimer()
        NotificationCenter.default.removeObserver(
            self,
            name: ChromecastManager.mediaStatusDidUpdateNotification,
            object: nil
        )
        isCastingVideo = false
        didInitiateCast = false
        videoPlayerView.updateCastState(isPlaying: false, deviceName: nil)
    }

    private func clearLoadedContentState() {
        currentTitle = nil
        currentArtworkTrack = nil
        currentPlexMovie = nil
        currentPlexEpisode = nil
        currentPlexRatingKey = nil
        currentJellyfinMovie = nil
        currentJellyfinEpisode = nil
        currentEmbyMovie = nil
        currentEmbyEpisode = nil
        currentLocalURL = nil
    }

    /// Close the video player window when an audio cast supersedes an active video cast.
    /// Does NOT call CastManager.stopCasting() — the audio cast is already running.
    func closeForCastTransition() {
        NSLog("VideoPlayerWindowController: closeForCastTransition — closing video player (superseded by audio cast)")
        guard !isClosing else { return }
        isClosing = true

        reportCurrentServerVideoStop(position: cacheLastKnownVideoCastPosition(), finished: false)

        // Clear cast flags before close() so windowWillClose skips the cast-stop block
        stopCastUpdateTimer()
        isCastingVideo = false
        didInitiateCast = false

        // Record analytics before clearing state, matching stop() and windowWillClose.
        recordVideoPlayEvent()

        // Stop local KSPlayer and clear content state
        videoPlayerView.stop()
        isPlaying = false
        clearLoadedContentState()

        WindowManager.shared.videoPlaybackDidStop()
        close()
    }

    @objc private func handleCastSessionChange() {
        guard case .none = CastManager.shared.currentCast else { return }
        guard !isStoppingOwnCast else {
            NSLog("VideoPlayerWindowController: Ignoring cast session .none during local stopCasting() cleanup")
            return
        }
        if isCastingVideo || didInitiateCast {
            reportCurrentServerVideoStop(position: cacheLastKnownVideoCastPosition(), finished: false)
            recordVideoPlayEvent()
            videoPlayerView.stop()
            isPlaying = false
            clearLoadedContentState()
            WindowManager.shared.videoPlaybackDidStop()
        }
        clearVideoCastState()
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCastSessionChange),
            name: CastManager.sessionDidChangeNotification,
            object: nil
        )
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
        
        // Track pause/resume for Plex/Jellyfin/Emby reporting
        videoPlayerView.onPlaybackPaused = { [weak self] position in
            guard let self = self else { return }
            self.pausePlaybackAnalytics()
            if self.isPlexContent {
                PlexVideoPlaybackReporter.shared.videoDidPause(at: position)
            } else if self.isJellyfinContent {
                JellyfinVideoPlaybackReporter.shared.videoDidPause(at: position)
            } else if self.isEmbyContent {
                EmbyVideoPlaybackReporter.shared.videoDidPause(at: position)
            }
        }

        videoPlayerView.onPlaybackResumed = { [weak self] position in
            guard let self = self else { return }
            self.resumePlaybackAnalytics()
            if self.isPlexContent {
                PlexVideoPlaybackReporter.shared.videoDidResume(at: position)
            } else if self.isJellyfinContent {
                JellyfinVideoPlaybackReporter.shared.videoDidResume(at: position)
            } else if self.isEmbyContent {
                EmbyVideoPlaybackReporter.shared.videoDidResume(at: position)
            }
        }

        // Track position updates for Plex/Jellyfin/Emby reporting
        videoPlayerView.onPositionUpdate = { [weak self] position in
            guard let self = self else { return }
            if self.isPlexContent {
                PlexVideoPlaybackReporter.shared.updatePosition(position)
            } else if self.isJellyfinContent {
                JellyfinVideoPlaybackReporter.shared.updatePosition(position)
            } else if self.isEmbyContent {
                EmbyVideoPlaybackReporter.shared.updatePosition(position)
            }
        }

        // Track playback completion for Plex/Jellyfin/Emby scrobbling and playlist advancement
        videoPlayerView.onPlaybackFinished = { [weak self] position in
            guard let self = self else { return }

            // Report to Plex if playing Plex content
            if self.isPlexContent {
                PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: true)
            } else if self.isJellyfinContent {
                JellyfinVideoPlaybackReporter.shared.videoDidStop(at: position, finished: true)
            } else if self.isEmbyContent {
                EmbyVideoPlaybackReporter.shared.videoDidStop(at: position, finished: true)
            }

            // Record analytics before advancing playlist
            self.recordVideoPlayEvent()

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
    
    /// Whether current content is from Jellyfin
    private var isJellyfinContent: Bool {
        currentJellyfinMovie != nil || currentJellyfinEpisode != nil
    }

    /// Whether current content is from Emby
    private var isEmbyContent: Bool {
        currentEmbyMovie != nil || currentEmbyEpisode != nil
    }

    private func reportCurrentServerVideoStop(position: TimeInterval, finished: Bool) {
        if isPlexContent {
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: finished)
        } else if isJellyfinContent {
            JellyfinVideoPlaybackReporter.shared.videoDidStop(at: position, finished: finished)
        } else if isEmbyContent {
            EmbyVideoPlaybackReporter.shared.videoDidStop(at: position, finished: finished)
        }
    }

    // MARK: - Playback Analytics

    private func beginPlaybackAnalyticsSession(contentType: String) {
        currentContentType = contentType
        accumulatedPlaybackDuration = 0
        playbackStartTime = Date()
    }

    private func pausePlaybackAnalytics(at timestamp: Date = Date()) {
        guard let startTime = playbackStartTime else { return }
        accumulatedPlaybackDuration += timestamp.timeIntervalSince(startTime)
        playbackStartTime = nil
    }

    private func resumePlaybackAnalytics(at timestamp: Date = Date()) {
        guard playbackStartTime == nil else { return }
        playbackStartTime = timestamp
    }

    private func totalPlaybackDuration(at timestamp: Date) -> TimeInterval {
        accumulatedPlaybackDuration + (playbackStartTime.map { timestamp.timeIntervalSince($0) } ?? 0)
    }

    private func recordVideoPlayEvent() {
        let eventTimestamp = Date()
        let duration = totalPlaybackDuration(at: eventTimestamp)
        guard duration > 0 else { return }

        let title = currentTitle
        let contentType = currentContentType

        let source: String
        if isPlexContent {
            source = PlayHistorySource.plex.rawValue
        } else if isJellyfinContent {
            source = PlayHistorySource.jellyfin.rawValue
        } else if isEmbyContent {
            source = PlayHistorySource.emby.rawValue
        } else {
            source = PlayHistorySource.local.rawValue
        }

        _ = MediaLibraryStore.shared.insertPlayEvent(
            trackId: nil,
            trackURL: nil,
            title: title,
            artist: nil,
            album: nil,
            genre: nil,
            playedAt: eventTimestamp,
            durationListened: duration,
            source: source,
            skipped: false,
            contentType: contentType,
            outputDevice: CastManager.currentPlaybackDeviceName)

        playbackStartTime = nil
        accumulatedPlaybackDuration = 0
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

        // Report stop to Plex/Jellyfin/Emby if currently playing server content (before clearing state)
        if isPlexContent {
            let position = videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isJellyfinContent {
            let position = videoPlayerView.currentPlaybackTime
            JellyfinVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isEmbyContent {
            let position = videoPlayerView.currentPlaybackTime
            EmbyVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }

        // Record analytics for the previous item before clearing state
        recordVideoPlayEvent()

        // Clear any server content (this is a local video)
        currentPlexMovie = nil
        currentPlexEpisode = nil
        currentPlexRatingKey = nil
        currentJellyfinMovie = nil
        currentJellyfinEpisode = nil
        currentEmbyMovie = nil
        currentEmbyEpisode = nil
        
        // Store local URL for casting
        currentLocalURL = url.isFileURL ? url : nil
        
        // Check if this is being played from the playlist (callback was set)
        isFromPlaylist = onVideoFinishedForPlaylist != nil
        
        currentTitle = title
        currentArtworkTrack = Track(url: url, title: title, mediaType: .video)
        window?.title = title
        videoPlayerView.play(url: url, title: title, isPlexURL: false, plexHeaders: nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isPlaying = true
        beginPlaybackAnalyticsSession(contentType: "video")
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

        // Report stop to current server content if playing
        if isPlexContent {
            let position = videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isJellyfinContent {
            let position = videoPlayerView.currentPlaybackTime
            JellyfinVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isEmbyContent {
            let position = videoPlayerView.currentPlaybackTime
            EmbyVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }

        // Record analytics for the previous item before clearing state
        recordVideoPlayEvent()

        // Clear movie/episode objects but keep track of the rating key for isPlexContent
        currentPlexMovie = nil
        currentPlexEpisode = nil
        currentPlexRatingKey = ratingKey
        currentJellyfinMovie = nil
        currentJellyfinEpisode = nil
        currentEmbyMovie = nil
        currentEmbyEpisode = nil
        currentLocalURL = nil  // Clear local URL when playing Plex content
        
        // Check if this is being played from the playlist (callback was set)
        isFromPlaylist = onVideoFinishedForPlaylist != nil
        
        // Get Plex streaming headers
        let headers = PlexManager.shared.streamingHeaders
        
        currentTitle = track.displayTitle
        currentArtworkTrack = track
        window?.title = track.displayTitle
        videoPlayerView.play(url: track.url, title: track.displayTitle, isPlexURL: true, plexHeaders: headers)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isPlaying = true
        beginPlaybackAnalyticsSession(contentType: track.playHistoryContentType)
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

        // Report stop to current server content if playing
        if isPlexContent {
            let position = videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isJellyfinContent {
            let position = videoPlayerView.currentPlaybackTime
            JellyfinVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isEmbyContent {
            let position = videoPlayerView.currentPlaybackTime
            EmbyVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }

        // Record analytics for the previous item before clearing state
        recordVideoPlayEvent()

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
        currentJellyfinMovie = nil
        currentJellyfinEpisode = nil
        currentEmbyMovie = nil
        currentEmbyEpisode = nil
        currentLocalURL = nil  // Clear local URL when playing Plex content

        currentTitle = movie.title
        currentArtworkTrack = PlexManager.shared.convertToTrack(movie)
        window?.title = movie.title
        videoPlayerView.play(url: url, title: movie.title, isPlexURL: true, plexHeaders: headers)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isPlaying = true
        beginPlaybackAnalyticsSession(contentType: "movie")
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

        // Report stop to current server content if playing
        if isPlexContent {
            let position = videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isJellyfinContent {
            let position = videoPlayerView.currentPlaybackTime
            JellyfinVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isEmbyContent {
            let position = videoPlayerView.currentPlaybackTime
            EmbyVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }

        // Record analytics for the previous item before clearing state
        recordVideoPlayEvent()

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
        currentJellyfinMovie = nil
        currentJellyfinEpisode = nil
        currentEmbyMovie = nil
        currentEmbyEpisode = nil
        currentLocalURL = nil  // Clear local URL when playing Plex content

        currentTitle = title
        currentArtworkTrack = PlexManager.shared.convertToTrack(episode)
        window?.title = title
        videoPlayerView.play(url: url, title: title, isPlexURL: true, plexHeaders: headers)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isPlaying = true
        beginPlaybackAnalyticsSession(contentType: "tv")
        WindowManager.shared.videoPlaybackDidStart()

        // Start Plex playback reporting
        PlexVideoPlaybackReporter.shared.episodeDidStart(episode)

        // Pass Plex streams for external subtitle support
        let allStreams = episode.media.flatMap { $0.parts.flatMap { $0.streams } }
        videoPlayerView.setPlexStreams(allStreams)
    }

    /// Play a Jellyfin movie
    func play(jellyfinMovie movie: JellyfinMovie) {
        // Reset any lingering cast state from previous video
        resetCastState()

        // Report stop to previous content if needed
        if isPlexContent {
            let position = videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isJellyfinContent {
            let position = videoPlayerView.currentPlaybackTime
            JellyfinVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isEmbyContent {
            let position = videoPlayerView.currentPlaybackTime
            EmbyVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }

        // Record analytics for the previous item before clearing state
        recordVideoPlayEvent()

        guard let url = JellyfinManager.shared.videoStreamURL(for: movie) else {
            NSLog("Failed to get stream URL for Jellyfin movie: %@", movie.title)
            return
        }

        NSLog("Playing Jellyfin movie: %@ with URL: %@", movie.title, url.absoluteString)

        // Store Jellyfin content for reporting
        currentJellyfinMovie = movie
        currentJellyfinEpisode = nil
        currentEmbyMovie = nil
        currentEmbyEpisode = nil
        currentPlexMovie = nil
        currentPlexEpisode = nil
        currentPlexRatingKey = nil
        currentLocalURL = nil

        currentTitle = movie.title
        currentArtworkTrack = JellyfinManager.shared.convertToTrack(movie)
        window?.title = movie.title
        videoPlayerView.play(url: url, title: movie.title, isPlexURL: false, plexHeaders: nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isPlaying = true
        beginPlaybackAnalyticsSession(contentType: "movie")
        WindowManager.shared.videoPlaybackDidStart()

        // Start Jellyfin playback reporting
        JellyfinVideoPlaybackReporter.shared.movieDidStart(movie)
    }

    /// Play a Jellyfin episode
    func play(jellyfinEpisode episode: JellyfinEpisode) {
        // Reset any lingering cast state from previous video
        resetCastState()

        // Report stop to previous content if needed
        if isPlexContent {
            let position = videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isJellyfinContent {
            let position = videoPlayerView.currentPlaybackTime
            JellyfinVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isEmbyContent {
            let position = videoPlayerView.currentPlaybackTime
            EmbyVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }

        // Record analytics for the previous item before clearing state
        recordVideoPlayEvent()

        guard let url = JellyfinManager.shared.videoStreamURL(for: episode) else {
            NSLog("Failed to get stream URL for Jellyfin episode: %@", episode.title)
            return
        }

        let title: String
        if let showName = episode.seriesName {
            title = "\(showName) - \(episode.episodeIdentifier) - \(episode.title)"
        } else {
            title = episode.title
        }
        NSLog("Playing Jellyfin episode: %@ with URL: %@", title, url.absoluteString)

        // Store Jellyfin content for reporting
        currentJellyfinMovie = nil
        currentJellyfinEpisode = episode
        currentEmbyMovie = nil
        currentEmbyEpisode = nil
        currentPlexMovie = nil
        currentPlexEpisode = nil
        currentPlexRatingKey = nil
        currentLocalURL = nil

        currentTitle = title
        currentArtworkTrack = JellyfinManager.shared.convertToTrack(episode)
        window?.title = title
        videoPlayerView.play(url: url, title: title, isPlexURL: false, plexHeaders: nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isPlaying = true
        beginPlaybackAnalyticsSession(contentType: "tv")
        WindowManager.shared.videoPlaybackDidStart()

        // Start Jellyfin playback reporting
        JellyfinVideoPlaybackReporter.shared.episodeDidStart(episode)
    }

    /// Play an Emby movie
    func play(embyMovie movie: EmbyMovie) {
        // Reset any lingering cast state from previous video
        resetCastState()

        // Report stop to previous content if needed
        if isPlexContent {
            let position = videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isJellyfinContent {
            let position = videoPlayerView.currentPlaybackTime
            JellyfinVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isEmbyContent {
            let position = videoPlayerView.currentPlaybackTime
            EmbyVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }

        // Record analytics for the previous item before clearing state
        recordVideoPlayEvent()

        guard let url = EmbyManager.shared.videoStreamURL(for: movie) else {
            NSLog("Failed to get stream URL for Emby movie: %@", movie.title)
            return
        }

        NSLog("Playing Emby movie: %@ with URL: %@", movie.title, url.absoluteString)

        // Store Emby content for reporting
        currentEmbyMovie = movie
        currentEmbyEpisode = nil
        currentJellyfinMovie = nil
        currentJellyfinEpisode = nil
        currentPlexMovie = nil
        currentPlexEpisode = nil
        currentPlexRatingKey = nil
        currentLocalURL = nil

        currentTitle = movie.title
        currentArtworkTrack = EmbyManager.shared.convertToTrack(movie)
        window?.title = movie.title
        videoPlayerView.play(url: url, title: movie.title, isPlexURL: false, plexHeaders: nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isPlaying = true
        beginPlaybackAnalyticsSession(contentType: "movie")
        WindowManager.shared.videoPlaybackDidStart()

        // Start Emby playback reporting
        EmbyVideoPlaybackReporter.shared.movieDidStart(movie)
    }

    /// Play an Emby episode
    func play(embyEpisode episode: EmbyEpisode) {
        // Reset any lingering cast state from previous video
        resetCastState()

        // Report stop to previous content if needed
        if isPlexContent {
            let position = videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isJellyfinContent {
            let position = videoPlayerView.currentPlaybackTime
            JellyfinVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isEmbyContent {
            let position = videoPlayerView.currentPlaybackTime
            EmbyVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }

        // Record analytics for the previous item before clearing state
        recordVideoPlayEvent()

        guard let url = EmbyManager.shared.videoStreamURL(for: episode) else {
            NSLog("Failed to get stream URL for Emby episode: %@", episode.title)
            return
        }

        let title: String
        if let showName = episode.seriesName {
            title = "\(showName) - \(episode.episodeIdentifier) - \(episode.title)"
        } else {
            title = episode.title
        }
        NSLog("Playing Emby episode: %@ with URL: %@", title, url.absoluteString)

        // Store Emby content for reporting
        currentEmbyMovie = nil
        currentEmbyEpisode = episode
        currentJellyfinMovie = nil
        currentJellyfinEpisode = nil
        currentPlexMovie = nil
        currentPlexEpisode = nil
        currentPlexRatingKey = nil
        currentLocalURL = nil

        currentTitle = title
        currentArtworkTrack = EmbyManager.shared.convertToTrack(episode)
        window?.title = title
        videoPlayerView.play(url: url, title: title, isPlexURL: false, plexHeaders: nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isPlaying = true
        beginPlaybackAnalyticsSession(contentType: "tv")
        WindowManager.shared.videoPlaybackDidStart()

        // Start Emby playback reporting
        EmbyVideoPlaybackReporter.shared.episodeDidStart(episode)
    }

    /// Play a Jellyfin video track from the playlist
    func play(jellyfinTrack track: Track) {
        guard let jellyfinId = track.jellyfinId else {
            play(url: track.url, title: track.displayTitle)
            return
        }

        // Reset any lingering cast state from previous video
        resetCastState()

        // Report stop to previous content if needed
        if isPlexContent {
            let position = videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isJellyfinContent {
            let position = videoPlayerView.currentPlaybackTime
            JellyfinVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isEmbyContent {
            let position = videoPlayerView.currentPlaybackTime
            EmbyVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }

        // Record analytics for the previous item before clearing state
        recordVideoPlayEvent()

        // Clear other content state
        currentPlexMovie = nil
        currentPlexEpisode = nil
        currentPlexRatingKey = nil
        currentJellyfinMovie = nil
        currentJellyfinEpisode = nil
        currentEmbyMovie = nil
        currentEmbyEpisode = nil
        currentLocalURL = nil

        // Check if this is being played from the playlist
        isFromPlaylist = onVideoFinishedForPlaylist != nil

        currentTitle = track.displayTitle
        currentArtworkTrack = track
        window?.title = track.displayTitle
        videoPlayerView.play(url: track.url, title: track.displayTitle, isPlexURL: false, plexHeaders: nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isPlaying = true
        beginPlaybackAnalyticsSession(contentType: track.playHistoryContentType)
        WindowManager.shared.videoPlaybackDidStart()

        NSLog("VideoPlayerWindowController: Playing Jellyfin track from playlist: %@ (id: %@)", track.displayTitle, jellyfinId)
    }

    /// Play an Emby video track from the playlist
    func play(embyTrack track: Track) {
        guard let embyId = track.embyId else {
            play(url: track.url, title: track.displayTitle)
            return
        }

        // Reset any lingering cast state from previous video
        resetCastState()

        // Report stop to previous content if needed
        if isPlexContent {
            let position = videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isJellyfinContent {
            let position = videoPlayerView.currentPlaybackTime
            JellyfinVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isEmbyContent {
            let position = videoPlayerView.currentPlaybackTime
            EmbyVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }

        // Record analytics for the previous item before clearing state
        recordVideoPlayEvent()

        // Clear other content state
        currentPlexMovie = nil
        currentPlexEpisode = nil
        currentPlexRatingKey = nil
        currentJellyfinMovie = nil
        currentJellyfinEpisode = nil
        currentEmbyMovie = nil
        currentEmbyEpisode = nil
        currentLocalURL = nil

        // Check if this is being played from the playlist
        isFromPlaylist = onVideoFinishedForPlaylist != nil

        currentTitle = track.displayTitle
        currentArtworkTrack = track
        window?.title = track.displayTitle
        videoPlayerView.play(url: track.url, title: track.displayTitle, isPlexURL: false, plexHeaders: nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isPlaying = true
        beginPlaybackAnalyticsSession(contentType: track.playHistoryContentType)
        WindowManager.shared.videoPlaybackDidStart()

        NSLog("VideoPlayerWindowController: Playing Emby track from playlist: %@ (id: %@)", track.displayTitle, embyId)
    }

    /// Stop playback
    func stop() {
        NSLog("VideoPlayerWindowController: stop() — isCastingVideo=%d isClosing=%d", isCastingVideo ? 1 : 0, isClosing ? 1 : 0)
        guard !isClosing else { return }
        isClosing = true
        
        // Capture cast position before stopping (for Plex reporting)
        let wasCasting = isCastingVideo
        let castPosition = wasCasting ? cacheLastKnownVideoCastPosition() : 0
        
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
            didInitiateCast = false
        }

        // Report stop to Plex/Jellyfin/Emby if playing server content
        if isPlexContent {
            let position = wasCasting ? castPosition : videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isJellyfinContent {
            let position = wasCasting ? castPosition : videoPlayerView.currentPlaybackTime
            JellyfinVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        } else if isEmbyContent {
            let position = wasCasting ? castPosition : videoPlayerView.currentPlaybackTime
            EmbyVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }

        // Record analytics before clearing state
        recordVideoPlayEvent()

        videoPlayerView.stop()
        isPlaying = false
        clearLoadedContentState()
        WindowManager.shared.videoPlaybackDidStop()
        close()
    }

    /// Toggle play/pause
    func togglePlayPause() {
        NSLog("VideoPlayerWindowController: togglePlayPause — isCastingVideo=%d", isCastingVideo ? 1 : 0)
        if isCastingVideo {
            toggleCastPlayPause()
        } else {
            videoPlayerView.togglePlayPause()
        }
    }

    /// Skip forward
    func skipForward(_ seconds: TimeInterval = 10) {
        NSLog("VideoPlayerWindowController: skipForward %.0fs — isCastingVideo=%d", seconds, isCastingVideo ? 1 : 0)
        if isCastingVideo {
            seekCastRelative(seconds)
        } else {
            videoPlayerView.skipForward(seconds)
        }
    }

    /// Skip backward
    func skipBackward(_ seconds: TimeInterval = 10) {
        NSLog("VideoPlayerWindowController: skipBackward %.0fs — isCastingVideo=%d", seconds, isCastingVideo ? 1 : 0)
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
        NSLog("VideoPlayerWindowController: toggleCastPlayPause — isPlaying=%d sessionState=%@",
              isPlaying ? 1 : 0,
              String(describing: CastManager.shared.activeSession?.state))
        Task {
            do {
                if CastManager.shared.activeSession?.state == .casting {
                    let receiverPlaying = CastManager.shared.activeSession?.isPlaying ?? isPlaying
                    if receiverPlaying {
                        NSLog("VideoPlayerWindowController: Sending cast pause")
                        try await CastManager.shared.pause()
                        await MainActor.run {
                            isPlaying = false
                            let device = CastManager.shared.activeSession?.device
                            videoPlayerView.updateCastState(isPlaying: false, deviceName: device?.name)
                        }
                    } else {
                        NSLog("VideoPlayerWindowController: Sending cast resume")
                        try await CastManager.shared.resume()
                        await MainActor.run {
                            isPlaying = true
                            let device = CastManager.shared.activeSession?.device
                            videoPlayerView.updateCastState(isPlaying: true, deviceName: device?.name)
                        }
                    }
                } else {
                    NSLog("VideoPlayerWindowController: toggleCastPlayPause skipped — sessionState=%@",
                          String(describing: CastManager.shared.activeSession?.state))
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
                let duration = CastManager.shared.activeSession?.duration ?? 0
                let requestedPosition = max(0, castCurrentTime + seconds)
                let newPosition = duration > 0 ? min(requestedPosition, duration) : requestedPosition
                if duration <= 0 {
                    NSLog("VideoPlayerWindowController: Cast relative seek without known duration (requested %.1f)", requestedPosition)
                }
                try await CastManager.shared.seek(to: newPosition)
                // CastManager has updated activeSession with new position
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
                let duration = CastManager.shared.activeSession?.duration ?? 0
                let requestedTime = max(0, time)
                let clampedTime = duration > 0 ? min(requestedTime, duration) : requestedTime
                if duration <= 0 {
                    NSLog("VideoPlayerWindowController: Cast seek without known duration (requested %.1f)", requestedTime)
                }
                try await CastManager.shared.seek(to: clampedTime)
                // CastManager has updated activeSession with new position
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
        if isCastingVideo, let device = CastManager.shared.activeSession?.device {
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
            let activeVideoId = CastManager.shared.currentCast == .video ? CastManager.shared.activeSession?.device.id : nil
            
            if !chromecasts.isEmpty {
                let headerItem = NSMenuItem(title: "Chromecast", action: nil, keyEquivalent: "")
                headerItem.isEnabled = false
                menu.addItem(headerItem)
                for device in chromecasts {
                    let title = device.id == activeVideoId ? "  ✓ \(device.name)" : "  \(device.name)"
                    let item = NSMenuItem(title: title, action: #selector(castToDevice(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = device
                    // Disable if already casting to this device
                    item.isEnabled = device.id != activeVideoId
                    menu.addItem(item)
                }
            }
            
            if !dlnaTVs.isEmpty {
                if !chromecasts.isEmpty { menu.addItem(NSMenuItem.separator()) }
                let headerItem = NSMenuItem(title: "TVs", action: nil, keyEquivalent: "")
                headerItem.isEnabled = false
                menu.addItem(headerItem)
                for device in dlnaTVs {
                    let title = device.id == activeVideoId ? "  ✓ \(device.name)" : "  \(device.name)"
                    let item = NSMenuItem(title: title, action: #selector(castToDevice(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = device
                    // Disable if already casting to this device
                    item.isEnabled = device.id != activeVideoId
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
        let selectedDevice = sender.representedObject as? CastDevice
        guard let device = selectedDevice ?? CastManager.shared.preferredVideoCastDevice else { return }

        // Prevent dual casting - check if already casting from context menu
        if case .video = CastManager.shared.currentCast, !isCastingVideo {
            NSLog("VideoPlayerWindowController: Cannot cast - already casting from context menu")
            let alert = NSAlert()
            alert.messageText = "Already Casting"
            alert.informativeText = "Stop the current cast before starting a new one."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        let wasPlaying = videoPlayerView.isPlaying
        let startPosition = videoPlayerView.currentPlaybackTime
        Task {
            do {
                try await performCast(to: device, startPosition: startPosition, savePreference: selectedDevice != nil)
            } catch {
                NSLog("VideoPlayerWindowController: Video cast failed: %@", error.localizedDescription)
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Cast Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                    self.clearVideoCastState()
                    self.shouldResumeLocalPlaybackAfterCast = false
                    if wasPlaying && !self.videoPlayerView.isPlaying {
                        self.videoPlayerView.togglePlayPause()
                    }
                }
            }
        }
    }

    /// Core cast initiation logic shared by manual cast and auto-cast.
    /// pauseLocal: false when the caller has already stopped local playback (auto-cast path).
    private func performCast(to device: CastDevice, startPosition: TimeInterval, savePreference: Bool = false, pauseLocal: Bool = true) async throws {
        let videoDuration = await MainActor.run { videoPlayerView.totalPlaybackDuration }

        // Pause local playback before handing off to Chromecast.
        // Skip for auto-cast path: the caller already called stop() synchronously.
        if pauseLocal {
            await MainActor.run {
                self.shouldResumeLocalPlaybackAfterCast = videoPlayerView.isPlaying
                if self.shouldResumeLocalPlaybackAfterCast {
                    videoPlayerView.togglePlayPause()
                }
            }
        } else {
            await MainActor.run {
                self.shouldResumeLocalPlaybackAfterCast = false
            }
        }

        // Route to the appropriate CastManager method based on loaded content
        if let movie = await MainActor.run(resultType: PlexMovie?.self, body: { self.currentPlexMovie }) {
            try await CastManager.shared.castPlexMovie(movie, to: device, startPosition: startPosition)
        } else if let episode = await MainActor.run(resultType: PlexEpisode?.self, body: { self.currentPlexEpisode }) {
            try await CastManager.shared.castPlexEpisode(episode, to: device, startPosition: startPosition)
        } else if let movie = await MainActor.run(resultType: JellyfinMovie?.self, body: { self.currentJellyfinMovie }) {
            try await CastManager.shared.castJellyfinMovie(movie, to: device, startPosition: startPosition)
        } else if let episode = await MainActor.run(resultType: JellyfinEpisode?.self, body: { self.currentJellyfinEpisode }) {
            try await CastManager.shared.castJellyfinEpisode(episode, to: device, startPosition: startPosition)
        } else if let movie = await MainActor.run(resultType: EmbyMovie?.self, body: { self.currentEmbyMovie }) {
            try await CastManager.shared.castEmbyMovie(movie, to: device, startPosition: startPosition)
        } else if let episode = await MainActor.run(resultType: EmbyEpisode?.self, body: { self.currentEmbyEpisode }) {
            try await CastManager.shared.castEmbyEpisode(episode, to: device, startPosition: startPosition)
        } else if let track = await MainActor.run(resultType: Track?.self, body: { self.currentArtworkTrack }),
                  track.mediaType == .video {
            try await CastManager.shared.castVideoTrack(
                track,
                to: device,
                startPosition: startPosition,
                duration: videoDuration > 0 ? videoDuration : track.duration
            )
        } else if let url = await MainActor.run(resultType: URL?.self, body: { self.currentURL }) {
            try await CastManager.shared.castLocalVideo(
                url,
                title: await MainActor.run { self.currentTitle ?? "Video" },
                to: device,
                startPosition: startPosition,
                duration: videoDuration > 0 ? videoDuration : nil
            )
        } else {
            throw CastError.playbackFailed("No castable content loaded")
        }

        // Update casting state and time tracking
        await MainActor.run {
            self.isCastingVideo = true
            self.didInitiateCast = true
            self.isPlaying = true
            self.lastKnownVideoCastPosition = startPosition
            self.videoPlayerView.updateCastState(isPlaying: true, deviceName: device.name)

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.handleChromecastMediaStatusUpdate),
                name: ChromecastManager.mediaStatusDidUpdateNotification,
                object: nil
            )

            self.startCastUpdateTimer()
        }

        if savePreference {
            CastManager.shared.setPreferredVideoCastDevice(device.id)
        }

        NSLog("VideoPlayerWindowController: Video cast started to %@ at %.1f / %.1f", device.name, startPosition, videoDuration)
    }

    @objc private func stopCasting() {
        Task {
            // Capture current cast position before stopping
            let resumePosition = await MainActor.run {
                self.isStoppingOwnCast = true
                return self.cacheLastKnownVideoCastPosition()
            }
            
            await CastManager.shared.stopCasting()
            
            await MainActor.run {
                let shouldResumeLocalPlayback = self.shouldResumeLocalPlaybackAfterCast
                self.clearVideoCastState()
                
                // Resume local playback from where casting left off
                if shouldResumeLocalPlayback {
                    NSLog("VideoPlayerWindowController: Resuming local playback at %.1f", resumePosition)
                    self.videoPlayerView.seek(to: resumePosition)
                    self.videoPlayerView.togglePlayPause()  // Start playback
                    self.isPlaying = true
                }
                self.shouldResumeLocalPlaybackAfterCast = false
                self.isStoppingOwnCast = false
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
        // sessionDidChangeNotification is intentionally NOT removed here.
        // WindowManager reuses this controller, so removing it on close would leave
        // handleCastSessionChange() unregistered for subsequent cast sessions.
        // deinit removes it when the controller is finally deallocated.
        NSLog("VideoPlayerWindowController: windowWillClose — keeping sessionDidChangeNotification observer (controller reused)")
        NotificationCenter.default.removeObserver(
            self,
            name: ChromecastManager.mediaStatusDidUpdateNotification,
            object: nil
        )
        
        // Only do cleanup if not already handled by stop()
        if !isClosing {
            // Stop casting only if this window initiated the cast.
            // Casts launched from a library context menu are owned by CastManager; closing an
            // unrelated player window must not interrupt them.
            if case .video = CastManager.shared.currentCast, didInitiateCast {
                let semaphore = DispatchSemaphore(value: 0)
                Task {
                    await CastManager.shared.stopCasting()
                    NSLog("VideoPlayerWindowController: Stopped video cast on TV (window closed)")
                    semaphore.signal()
                }
                // Wait up to 2 seconds for cast to stop
                _ = semaphore.wait(timeout: .now() + 2.0)

                isCastingVideo = false
                didInitiateCast = false
            }
            
            // Report stop to Plex/Jellyfin/Emby if playing server content
            if isPlexContent {
                let position = videoPlayerView.currentPlaybackTime
                PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
            } else if isJellyfinContent {
                let position = videoPlayerView.currentPlaybackTime
                JellyfinVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
            } else if isEmbyContent {
                let position = videoPlayerView.currentPlaybackTime
                EmbyVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
            }

            // Record analytics before clearing state
            recordVideoPlayEvent()

            videoPlayerView.stop()
            isPlaying = false
            clearLoadedContentState()
            WindowManager.shared.videoPlaybackDidStop()
        }
        removeKeyboardMonitor()
        isClosing = false  // Reset for potential reuse
    }

    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: CastManager.sessionDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: ChromecastManager.mediaStatusDidUpdateNotification,
            object: nil
        )
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

#if DEBUG
extension VideoPlayerWindowController {
    struct DebugCastStateSnapshot {
        let isCastingVideo: Bool
        let hasTargetDevice: Bool
        let castStartPosition: TimeInterval
        let hasPlaybackStartDate: Bool
        let castState: CastState
        let castDuration: TimeInterval
    }

    func debugSetCurrentTitleForTesting(_ title: String?) {
        currentTitle = title
    }

    func debugSetCastStateForTesting(device: CastDevice, startPosition: TimeInterval, duration: TimeInterval) {
        // For testing, set up the cast session in CastManager and mark this controller as casting
        CastManager.shared.debugSetActiveCastSessionForTesting(device: device, startPosition: startPosition, duration: duration)
        isCastingVideo = true
    }

    func debugSetDidInitiateCastForTesting(_ value: Bool) {
        didInitiateCast = value
    }

    var debugDidInitiateCast: Bool { didInitiateCast }

    func debugSetStoppingOwnCastForTesting(_ value: Bool) {
        isStoppingOwnCast = value
    }

    var debugCastStateSnapshot: DebugCastStateSnapshot {
        let session = CastManager.shared.activeSession
        return DebugCastStateSnapshot(
            isCastingVideo: isCastingVideo,
            hasTargetDevice: session?.device != nil,
            castStartPosition: session?.position ?? 0,
            hasPlaybackStartDate: session?.playbackStartDate != nil,
            castState: session?.state ?? .idle,
            castDuration: session?.duration ?? 0
        )
    }
}
#endif
