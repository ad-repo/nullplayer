import AppKit
import KSPlayer

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
        window.minSize = NSSize(width: 480, height: 270 + SkinElements.titleBarHeight)
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
        
        // Set up local event monitor for keyboard shortcuts (especially Escape in fullscreen)
        setupKeyboardMonitor()
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
            
            switch event.keyCode {
            case 53: // Escape
                NSLog("VideoPlayer: Escape pressed, fullscreen=%d", window.styleMask.contains(.fullScreen) ? 1 : 0)
                if window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                    return nil // Consume the event
                } else {
                    self.close()
                    return nil
                }
            case 49: // Space - toggle play/pause
                self.togglePlayPause()
                return nil
            case 3: // F key - toggle fullscreen
                window.toggleFullScreen(nil)
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
    func play(url: URL, title: String) {
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
        guard let url = PlexManager.shared.streamURL(for: movie) else {
            NSLog("Failed to get stream URL for movie: %@", movie.title)
            return
        }
        
        // Get full streaming headers (required for remote/relay connections)
        let headers = PlexManager.shared.streamingHeaders
        NSLog("Playing Plex movie: %@ with URL: %@", movie.title, url.absoluteString)
        
        currentTitle = movie.title
        window?.title = movie.title
        videoPlayerView.play(url: url, title: movie.title, isPlexURL: true, plexHeaders: headers)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isPlaying = true
        WindowManager.shared.videoPlaybackDidStart()
    }
    
    /// Play a Plex episode
    func play(episode: PlexEpisode) {
        guard let url = PlexManager.shared.streamURL(for: episode) else {
            NSLog("Failed to get stream URL for episode: %@", episode.title)
            return
        }
        
        // Get full streaming headers (required for remote/relay connections)
        let headers = PlexManager.shared.streamingHeaders
        let title = "\(episode.grandparentTitle ?? "Unknown") - \(episode.episodeIdentifier) - \(episode.title)"
        NSLog("Playing Plex episode: %@ with URL: %@", title, url.absoluteString)
        
        currentTitle = title
        window?.title = title
        videoPlayerView.play(url: url, title: title, isPlexURL: true, plexHeaders: headers)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        isPlaying = true
        WindowManager.shared.videoPlaybackDidStart()
    }
    
    /// Stop playback
    func stop() {
        guard !isClosing else { return }
        isClosing = true
        
        videoPlayerView.stop()
        isPlaying = false
        currentTitle = nil
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
            videoPlayerView.stop()
            isPlaying = false
            currentTitle = nil
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
