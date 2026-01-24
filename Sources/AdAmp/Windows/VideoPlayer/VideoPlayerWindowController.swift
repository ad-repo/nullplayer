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
        // Create a borderless window for skinned video playback
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
                self.onVideoFinishedForPlaylist?()
                self.onVideoFinishedForPlaylist = nil  // Clear callback after use
            }
        }
        
        // Set up local event monitor for keyboard shortcuts (especially Escape in fullscreen)
        setupKeyboardMonitor()
    }
    
    /// Whether current content is from Plex
    private var isPlexContent: Bool {
        currentPlexMovie != nil || currentPlexEpisode != nil
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
        // Report stop to Plex if currently playing Plex content (before clearing state)
        if isPlexContent {
            let position = videoPlayerView.currentPlaybackTime
            PlexVideoPlaybackReporter.shared.videoDidStop(at: position, finished: false)
        }
        
        // Clear any Plex content (this is a non-Plex video)
        currentPlexMovie = nil
        currentPlexEpisode = nil
        
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
    
    /// Play a Plex movie
    func play(movie: PlexMovie) {
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
        WindowManager.shared.videoPlaybackDidStop()
        close()
    }
    
    /// Toggle play/pause
    func togglePlayPause() {
        videoPlayerView.togglePlayPause()
    }
    
    /// Skip forward
    func skipForward(_ seconds: TimeInterval = 10) {
        videoPlayerView.skipForward(seconds)
    }
    
    /// Skip backward
    func skipBackward(_ seconds: TimeInterval = 10) {
        videoPlayerView.skipBackward(seconds)
    }
    
    /// Seek to specific time
    func seek(to time: TimeInterval) {
        videoPlayerView.seek(to: time)
    }
    
    /// Update playing state (called from VideoPlayerView)
    func updatePlayingState(_ playing: Bool) {
        isPlaying = playing
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // Only do cleanup if not already handled by stop()
        if !isClosing {
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
