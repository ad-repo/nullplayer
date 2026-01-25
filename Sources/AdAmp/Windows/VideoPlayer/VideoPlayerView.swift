import AppKit
@preconcurrency import KSPlayer

/// Video player view using KSPlayer with FFmpeg backend, skinned title bar, and controls
class VideoPlayerView: NSView {
    
    // MARK: - Properties
    
    private var playerLayer: KSPlayerLayer?
    private var playerHostView: NSView!
    private var loadingIndicator: NSProgressIndicator?
    private var currentTitle: String = ""
    private var currentURL: URL?
    
    /// Whether this is a Plex stream (for header attachment)
    private var isPlexStream: Bool = false
    
    /// Title bar removed - video player is borderless
    
    /// Control bar at bottom
    private var controlBarView: VideoControlBarView!
    
    /// Track selection panel
    private var trackSelectionPanel: TrackSelectionPanelView?
    
    /// Available audio tracks (from KSPlayer)
    private var availableAudioTracks: [MediaPlayerTrack] = []
    
    /// Available subtitle tracks (from KSPlayer)
    private var availableSubtitleTracks: [MediaPlayerTrack] = []
    
    /// Plex streams for external subtitles
    private var plexStreams: [PlexStream] = []
    
    /// Current subtitle delay
    private var currentSubtitleDelay: TimeInterval = 0
    
    /// Whether the track selection panel is currently visible
    var trackSelectionPanelVisible: Bool {
        trackSelectionPanel?.isVisible ?? false
    }
    
    /// Auto-hide timer for controls
    private var controlsHideTimer: Timer?
    private var controlsVisible: Bool = true
    
    /// Center overlay for click-to-play/pause (large centered icons)
    private var centerOverlayView: VideoCenterOverlayView?
    private var centerOverlayHideTimer: Timer?
    
    /// Current playback time and duration
    private(set) var currentTime: TimeInterval = 0
    private(set) var totalDuration: TimeInterval = 0
    
    /// Public accessors for playback time
    var currentPlaybackTime: TimeInterval { currentTime }
    var totalPlaybackDuration: TimeInterval { totalDuration }
    
    /// Volume level (0.0 - 1.0)
    var volume: Float = 1.0 {
        didSet {
            playerLayer?.player.playbackVolume = volume
        }
    }
    
    /// Callback when close button is clicked
    var onClose: (() -> Void)?
    
    /// Callback when minimize button is clicked
    var onMinimize: (() -> Void)?
    
    /// Callback when playback state changes (playing/not playing)
    var onPlaybackStateChanged: ((Bool) -> Void)?
    
    /// Callback when playback is paused (with current position)
    var onPlaybackPaused: ((TimeInterval) -> Void)?
    
    /// Callback when playback is resumed (with current position)
    var onPlaybackResumed: ((TimeInterval) -> Void)?
    
    /// Callback for position updates (called periodically during playback)
    var onPositionUpdate: ((TimeInterval) -> Void)?
    
    /// Callback when playback finishes naturally (with final position)
    var onPlaybackFinished: ((TimeInterval) -> Void)?
    
    /// Callback when track selection panel is requested
    var onTrackSelectionRequested: (() -> Void)?
    
    /// Callback when cast button is clicked
    var onCast: (() -> Void)?
    
    /// Callback when stop button is clicked
    var onStop: (() -> Void)?
    
    /// Callback when play/pause is toggled (for casting intercept)
    var onPlayPauseToggled: (() -> Void)?
    
    /// Callback when seek is requested (for casting intercept) - normalized 0-1 position
    var onSeekRequested: ((Double) -> Void)?
    
    /// Callback when skip forward is requested (for casting intercept)
    var onSkipForwardRequested: ((TimeInterval) -> Void)?
    
    /// Callback when skip backward is requested (for casting intercept)
    var onSkipBackwardRequested: ((TimeInterval) -> Void)?
    
    /// Track previous state to detect pause/resume transitions
    private var previousState: KSPlayerState?
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    deinit {
        controlsHideTimer?.invalidate()
        playerLayer?.pause()
        playerLayer?.stop()
    }
    
    // MARK: - Setup
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        
        let controlBarHeight: CGFloat = 40
        
        // Create a host view for the player layer - fills entire view
        playerHostView = NSView(frame: bounds)
        playerHostView.wantsLayer = true
        playerHostView.layer?.backgroundColor = NSColor.black.cgColor
        playerHostView.autoresizingMask = [.width, .height]
        addSubview(playerHostView)
        
        // Title bar removed - video player is now borderless
        
        // Create control bar at bottom (overlays on bottom)
        controlBarView = VideoControlBarView(frame: NSRect(x: 0, y: bounds.height - controlBarHeight, 
                                                            width: bounds.width, height: controlBarHeight))
        controlBarView.autoresizingMask = [.width, .minYMargin]
        controlBarView.onPlayPause = { [weak self] in
            // Call external callback if set (for casting intercept), otherwise handle locally
            if let callback = self?.onPlayPauseToggled {
                callback()
            } else {
                self?.togglePlayPause()
            }
        }
        controlBarView.onSeek = { [weak self] position in
            if let callback = self?.onSeekRequested {
                callback(position)
            } else {
                self?.seekToPosition(position)
            }
        }
        controlBarView.onSkipBackward = { [weak self] in
            if let callback = self?.onSkipBackwardRequested {
                callback(10)
            } else {
                self?.skipBackward(10)
            }
        }
        controlBarView.onSkipForward = { [weak self] in
            if let callback = self?.onSkipForwardRequested {
                callback(10)
            } else {
                self?.skipForward(10)
            }
        }
        controlBarView.onFullscreen = { [weak self] in self?.window?.toggleFullScreen(nil) }
        controlBarView.onTrackSettings = { [weak self] in self?.showTrackSelectionPanel() }
        controlBarView.onCast = { [weak self] in self?.onCast?() }
        controlBarView.onStop = { [weak self] in self?.onStop?() }
        addSubview(controlBarView)
        
        // Create center overlay for click-to-play/pause
        setupCenterOverlay()
        
        // Create loading indicator
        setupLoadingIndicator()
        
        // Setup context menu
        setupContextMenu()
        
        // Setup mouse tracking for auto-hide controls
        setupMouseTracking()
        
        // Setup track selection panel
        setupTrackSelectionPanel()
    }
    
    private func setupTrackSelectionPanel() {
        trackSelectionPanel = TrackSelectionPanelView(frame: bounds)
        trackSelectionPanel?.autoresizingMask = [.width, .height]
        trackSelectionPanel?.delegate = self
        trackSelectionPanel?.isHidden = true
        addSubview(trackSelectionPanel!)
    }
    
    private func setupCenterOverlay() {
        centerOverlayView = VideoCenterOverlayView(frame: bounds)
        centerOverlayView?.autoresizingMask = [.width, .height]
        centerOverlayView?.alphaValue = 0
        centerOverlayView?.isHidden = true
        centerOverlayView?.onPlayPause = { [weak self] in
            if let callback = self?.onPlayPauseToggled {
                callback()
            } else {
                self?.togglePlayPause()
            }
        }
        centerOverlayView?.onClose = { [weak self] in
            self?.onStop?()
        }
        addSubview(centerOverlayView!)
    }
    
    private func setupLoadingIndicator() {
        let indicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        indicator.style = .spinning
        indicator.controlSize = .regular
        indicator.isIndeterminate = true
        indicator.isHidden = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indicator)
        
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        loadingIndicator = indicator
    }
    
    private func setupContextMenu() {
        let menu = NSMenu(title: "Video")
        
        menu.addItem(withTitle: "Play/Pause", action: #selector(contextPlayPause), keyEquivalent: " ")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Skip Backward 10s", action: #selector(contextSkipBackward), keyEquivalent: "")
        menu.addItem(withTitle: "Skip Forward 10s", action: #selector(contextSkipForward), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        
        // Audio submenu
        let audioItem = NSMenuItem(title: "Audio", action: nil, keyEquivalent: "")
        audioItem.submenu = NSMenu(title: "Audio")
        audioItem.submenu?.delegate = self
        audioItem.tag = 100  // Tag to identify audio submenu
        menu.addItem(audioItem)
        
        // Subtitles submenu
        let subtitleItem = NSMenuItem(title: "Subtitles", action: nil, keyEquivalent: "")
        subtitleItem.submenu = NSMenu(title: "Subtitles")
        subtitleItem.submenu?.delegate = self
        subtitleItem.tag = 101  // Tag to identify subtitle submenu
        menu.addItem(subtitleItem)
        
        // Track settings panel
        menu.addItem(withTitle: "Track Settings...", action: #selector(contextTrackSettings), keyEquivalent: "")
        
        menu.addItem(NSMenuItem.separator())
        
        // Always on Top toggle
        let alwaysOnTopItem = NSMenuItem(title: "Always on Top", action: #selector(contextToggleAlwaysOnTop), keyEquivalent: "")
        alwaysOnTopItem.target = self
        menu.addItem(alwaysOnTopItem)
        
        menu.addItem(withTitle: "Toggle Fullscreen", action: #selector(contextFullscreen), keyEquivalent: "f")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Close", action: #selector(contextClose), keyEquivalent: "w")
        
        // Set delegate to update menu state
        menu.delegate = self
        
        self.menu = menu
    }
    
    private func setupMouseTracking() {
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    
    // MARK: - Context Menu Actions
    
    @objc private func contextPlayPause() {
        togglePlayPause()
    }
    
    @objc private func contextSkipBackward() {
        skipBackward(10)
    }
    
    @objc private func contextSkipForward() {
        skipForward(10)
    }
    
    @objc private func contextFullscreen() {
        window?.toggleFullScreen(nil)
    }
    
    @objc private func contextClose() {
        stop()
        window?.close()
    }
    
    @objc private func contextTrackSettings() {
        showTrackSelectionPanel()
    }
    
    @objc private func contextToggleAlwaysOnTop() {
        guard let window = window else { return }
        
        if window.level == .floating {
            window.level = .normal
            NSLog("VideoPlayerView: Always on Top disabled")
        } else {
            window.level = .floating
            NSLog("VideoPlayerView: Always on Top enabled")
        }
    }
    
    @objc private func contextSelectAudioTrack(_ sender: NSMenuItem) {
        let index = sender.tag
        if index >= 0 && index < availableAudioTracks.count {
            let track = availableAudioTracks[index]
            playerLayer?.player.select(track: track)
            NSLog("VideoPlayerView: Selected audio track from menu: %@", track.name ?? "Track \(index + 1)")
            updateTrackSelectionPanel()
        }
    }
    
    @objc private func contextSelectSubtitleTrack(_ sender: NSMenuItem) {
        let index = sender.tag
        if index == -1 {
            // "Off" selected
            selectSubtitleTrack(nil)
            NSLog("VideoPlayerView: Subtitles turned off from menu")
        } else if index >= 0 && index < availableSubtitleTracks.count {
            let track = availableSubtitleTracks[index]
            playerLayer?.player.select(track: track)
            NSLog("VideoPlayerView: Selected subtitle track from menu: %@", track.name ?? "Track \(index + 1)")
            updateTrackSelectionPanel()
        }
    }
    
    // MARK: - Controls Visibility
    
    private func showControls() {
        controlsVisible = true
        controlBarView.alphaValue = 1.0
        resetControlsHideTimer()
        // Ensure we're first responder to capture keyboard events
        window?.makeFirstResponder(self)
    }
    
    private func hideControls() {
        guard playerLayer?.state.isPlaying == true else { return }
        
        controlsVisible = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            controlBarView.animator().alphaValue = 0.0
        }
    }
    
    private func resetControlsHideTimer() {
        controlsHideTimer?.invalidate()
        controlsHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hideControls()
            }
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        showControls()
        // Make this view the first responder to capture keyboard events
        window?.makeFirstResponder(self)
        
        // Show center overlay on single click
        if event.clickCount == 1 {
            showCenterOverlay()
        } else if event.clickCount == 2 {
            // Double-click toggles play/pause
            if let callback = onPlayPauseToggled {
                callback()
            } else {
                togglePlayPause()
            }
        }
    }
    
    // MARK: - Center Overlay
    
    private func showCenterOverlay() {
        guard let overlay = centerOverlayView else { return }
        
        // Update overlay state
        overlay.updatePlayState(isPlaying: playerLayer?.state.isPlaying ?? false)
        
        // Show with animation
        overlay.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            overlay.animator().alphaValue = 1.0
        }
        
        // Auto-hide after delay
        centerOverlayHideTimer?.invalidate()
        centerOverlayHideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hideCenterOverlay()
            }
        }
    }
    
    private func hideCenterOverlay() {
        guard let overlay = centerOverlayView else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            overlay.animator().alphaValue = 0
        }, completionHandler: {
            overlay.isHidden = true
        })
    }
    
    override func mouseMoved(with event: NSEvent) {
        showControls()
    }
    
    override func mouseEntered(with event: NSEvent) {
        showControls()
    }
    
    override func mouseExited(with event: NSEvent) {
        resetControlsHideTimer()
    }
    
    // MARK: - Layout
    
    override func layout() {
        super.layout()
        
        let controlBarHeight: CGFloat = 40
        
        // Video fills entire view
        playerHostView.frame = bounds
        
        // Control bar at bottom
        controlBarView.frame = NSRect(x: 0, y: bounds.height - controlBarHeight, 
                                       width: bounds.width, height: controlBarHeight)
    }
    
    override var isFlipped: Bool { true }
    
    // MARK: - Playback
    
    /// Play video from URL with title
    /// - Parameters:
    ///   - url: The video URL
    ///   - title: Display title
    ///   - isPlexURL: Whether this is a Plex stream
    ///   - plexHeaders: Full Plex headers for streaming (required for remote/relay connections)
    func play(url: URL, title: String, isPlexURL: Bool = false, plexHeaders: [String: String]? = nil) {
        currentTitle = title
        currentURL = url
        isPlexStream = isPlexURL
        
        // Title removed - update window title instead
        window?.title = title
        
        // Show loading indicator
        showLoading(true)
        
        // Reset time display
        currentTime = 0
        totalDuration = 0
        controlBarView.updateTime(current: 0, total: 0)
        controlBarView.updatePlayState(isPlaying: false)
        
        // Reset cast state when starting a new video (ensures UI shows local playback)
        controlBarView.updateCastState(isPlaying: false, deviceName: nil)
        
        // Configure options
        let options = KSOptions()
        if isPlexURL, let headers = plexHeaders {
            // Remote/relay Plex connections require full client identification headers
            options.appendHeader(headers)
            NSLog("VideoPlayerView: Attaching %d Plex headers for streaming", headers.count)
        }
        
        // Stop existing player if any
        playerLayer?.stop()
        playerLayer = nil
        
        // Create new player layer with the URL
        let layer = KSPlayerLayer(url: url, options: options, delegate: self)
        playerLayer = layer
        
        // Apply current volume to the new player
        layer.player.playbackVolume = volume
        
        // Add player view to host
        if let playerView = layer.player.view {
            playerView.frame = playerHostView.bounds
            playerView.autoresizingMask = [.width, .height]
            // Set background to black on all layers to prevent white line flashing
            playerView.wantsLayer = true
            playerView.layer?.backgroundColor = NSColor.black.cgColor
            // Also set black background on any sublayers (KSPlayer internal views)
            func setBlackBackground(on view: NSView) {
                view.wantsLayer = true
                view.layer?.backgroundColor = NSColor.black.cgColor
                for subview in view.subviews {
                    setBlackBackground(on: subview)
                }
            }
            setBlackBackground(on: playerView)
            playerHostView.subviews.forEach { $0.removeFromSuperview() }
            playerHostView.addSubview(playerView)
        }
        
        NSLog("VideoPlayerView: Playing %@ from %@", title, url.absoluteString)
    }
    
    /// Stop playback
    func stop() {
        controlsHideTimer?.invalidate()
        playerLayer?.pause()
        playerLayer?.stop()
        showLoading(false)
        controlBarView.updatePlayState(isPlaying: false)
    }
    
    /// Toggle play/pause
    func togglePlayPause() {
        guard let layer = playerLayer else { return }
        
        if layer.state.isPlaying {
            layer.pause()
            controlBarView.updatePlayState(isPlaying: false)
            centerOverlayView?.updatePlayState(isPlaying: false)
            showControls()
        } else {
            layer.play()
            controlBarView.updatePlayState(isPlaying: true)
            centerOverlayView?.updatePlayState(isPlaying: true)
            resetControlsHideTimer()
        }
    }
    
    /// Seek to normalized position (0-1)
    func seekToPosition(_ position: Double) {
        guard totalDuration > 0 else { return }
        let time = position * totalDuration
        playerLayer?.seek(time: time, autoPlay: true) { _ in }
    }
    
    /// Seek to time
    func seek(to time: TimeInterval) {
        playerLayer?.seek(time: time, autoPlay: true) { _ in }
    }
    
    /// Skip forward by seconds
    func skipForward(_ seconds: TimeInterval = 10) {
        guard let layer = playerLayer else { return }
        let newTime = min(layer.player.currentPlaybackTime + seconds, totalDuration)
        layer.seek(time: newTime, autoPlay: true) { _ in }
    }
    
    /// Skip backward by seconds
    func skipBackward(_ seconds: TimeInterval = 10) {
        guard let layer = playerLayer else { return }
        let newTime = max(0, layer.player.currentPlaybackTime - seconds)
        layer.seek(time: newTime, autoPlay: true) { _ in }
    }
    
    // MARK: - Track Selection
    
    /// Set Plex streams for external subtitle support
    func setPlexStreams(_ streams: [PlexStream]) {
        plexStreams = streams
        updateTrackSelectionPanel()
    }
    
    /// Discover available tracks from KSPlayer
    private func discoverTracks() {
        guard let layer = playerLayer else { return }
        
        availableAudioTracks = layer.player.tracks(mediaType: .audio)
        availableSubtitleTracks = layer.player.tracks(mediaType: .subtitle)
        
        NSLog("VideoPlayerView: Discovered %d audio tracks, %d subtitle tracks", 
              availableAudioTracks.count, availableSubtitleTracks.count)
        
        updateTrackSelectionPanel()
    }
    
    /// Show the track selection panel
    func showTrackSelectionPanel() {
        trackSelectionPanel?.show()
        onTrackSelectionRequested?()
    }
    
    /// Hide the track selection panel
    func hideTrackSelectionPanel() {
        trackSelectionPanel?.hide()
    }
    
    /// Toggle track selection panel visibility
    func toggleTrackSelectionPanel() {
        trackSelectionPanel?.toggle()
    }
    
    /// Update the track selection panel with current tracks
    private func updateTrackSelectionPanel() {
        guard let panel = trackSelectionPanel else { return }
        
        // Convert KSPlayer audio tracks to SelectableTracks
        let audioTracks = availableAudioTracks.enumerated().map { index, track in
            SelectableTrack(
                id: "audio_\(index)",
                type: .audio,
                name: track.name ?? "Audio Track \(index + 1)",
                language: track.language,
                codec: nil,
                isSelected: track.isEnabled,
                isExternal: false,
                externalURL: nil,
                ksTrack: track,
                plexStream: nil
            )
        }
        
        // Convert KSPlayer subtitle tracks to SelectableTracks
        var subtitleTracks = availableSubtitleTracks.enumerated().map { index, track in
            SelectableTrack(
                id: "subtitle_\(index)",
                type: .subtitle,
                name: track.name ?? "Subtitle Track \(index + 1)",
                language: track.language,
                codec: nil,
                isSelected: track.isEnabled,
                isExternal: false,
                externalURL: nil,
                ksTrack: track,
                plexStream: nil
            )
        }
        
        // Add Plex external subtitles
        let externalSubtitles = plexStreams.filter { $0.streamType == .subtitle && $0.isExternal }.map { stream in
            SelectableTrack(
                id: "plex_sub_\(stream.id)",
                type: .subtitle,
                name: stream.localizedDisplayTitle,
                language: stream.language,
                codec: stream.codec,
                isSelected: false,  // External subtitles need to be explicitly selected
                isExternal: true,
                externalURL: stream.key.flatMap { URL(string: $0) },
                ksTrack: nil,
                plexStream: stream
            )
        }
        subtitleTracks.append(contentsOf: externalSubtitles)
        
        panel.updateTracks(audioTracks: audioTracks, subtitleTracks: subtitleTracks)
    }
    
    /// Select an audio track
    func selectAudioTrack(_ track: SelectableTrack?) {
        guard let layer = playerLayer, let track = track, let ksTrack = track.ksTrack else { return }
        layer.player.select(track: ksTrack)
        NSLog("VideoPlayerView: Selected audio track: %@", track.name)
        updateTrackSelectionPanel()
    }
    
    /// Select a subtitle track (nil to disable subtitles)
    func selectSubtitleTrack(_ track: SelectableTrack?) {
        guard let layer = playerLayer else { return }
        
        if let track = track {
            if let ksTrack = track.ksTrack {
                // Embedded subtitle
                layer.player.select(track: ksTrack)
                NSLog("VideoPlayerView: Selected subtitle track: %@", track.name)
            } else if let plexStream = track.plexStream, let subtitleKey = plexStream.key {
                // External Plex subtitle - need to load from URL
                NSLog("VideoPlayerView: Loading external subtitle from: %@", subtitleKey)
                // KSPlayer handles external subtitles via subtitleDataSource
                // This would need additional implementation for external subtitle loading
            }
        } else {
            // Disable all subtitles
            for track in availableSubtitleTracks {
                if track.isEnabled {
                    // KSPlayer doesn't have a direct "disable" - select another track or implement disable
                    NSLog("VideoPlayerView: Subtitles disabled")
                }
            }
        }
        updateTrackSelectionPanel()
    }
    
    /// Cycle to next audio track
    func cycleAudioTrack() {
        guard !availableAudioTracks.isEmpty else { return }
        
        let currentIndex = availableAudioTracks.firstIndex { $0.isEnabled } ?? -1
        let nextIndex = (currentIndex + 1) % availableAudioTracks.count
        let nextTrack = availableAudioTracks[nextIndex]
        
        playerLayer?.player.select(track: nextTrack)
        NSLog("VideoPlayerView: Cycled to audio track: %@", nextTrack.name ?? "Track \(nextIndex + 1)")
        updateTrackSelectionPanel()
    }
    
    /// Cycle to next subtitle track (including "Off")
    func cycleSubtitleTrack() {
        let totalOptions = availableSubtitleTracks.count + 1  // +1 for "Off"
        guard totalOptions > 1 else { return }
        
        let currentIndex = availableSubtitleTracks.firstIndex { $0.isEnabled } ?? -1
        let nextIndex = currentIndex + 1  // -1 -> 0 (first subtitle), last -> totalOptions-1 (off)
        
        if nextIndex >= availableSubtitleTracks.count {
            // Select "Off" - disable subtitles
            selectSubtitleTrack(nil)
            NSLog("VideoPlayerView: Subtitles turned off")
        } else {
            let nextTrack = availableSubtitleTracks[nextIndex]
            playerLayer?.player.select(track: nextTrack)
            NSLog("VideoPlayerView: Cycled to subtitle track: %@", nextTrack.name ?? "Track \(nextIndex + 1)")
        }
        updateTrackSelectionPanel()
    }
    
    // MARK: - Loading Indicator
    
    private func showLoading(_ show: Bool) {
        DispatchQueue.main.async { [weak self] in
            if show {
                self?.loadingIndicator?.isHidden = false
                self?.loadingIndicator?.startAnimation(nil)
            } else {
                self?.loadingIndicator?.stopAnimation(nil)
                self?.loadingIndicator?.isHidden = true
            }
        }
    }
    
    // MARK: - Keyboard Events
    
    override var acceptsFirstResponder: Bool { true }
    
    /// Handle Escape key via standard macOS cancel operation
    @objc override func cancelOperation(_ sender: Any?) {
        if let window = window, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        } else {
            stop()
            window?.close()
        }
    }
    
    /// Intercept key events before they reach subviews
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Escape - exit fullscreen or close
            cancelOperation(nil)
            return true
        case 49: // Space - toggle play/pause
            togglePlayPause()
            return true
        case 3: // F key - toggle fullscreen
            window?.toggleFullScreen(nil)
            return true
        case 123: // Left arrow - skip back
            skipBackward(10)
            return true
        case 124: // Right arrow - skip forward
            skipForward(10)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: // Space - toggle play/pause
            togglePlayPause()
        case 123: // Left arrow - skip back
            skipBackward(10)
        case 124: // Right arrow - skip forward
            skipForward(10)
        case 53: // Escape - exit fullscreen or close
            cancelOperation(nil)
        case 3: // F key - toggle fullscreen
            window?.toggleFullScreen(nil)
        default:
            super.keyDown(with: event)
        }
    }
    
    // MARK: - Window Active State
    
    func updateActiveState(_ isActive: Bool) {
        // No title bar to update
    }
    
    // MARK: - Cast State
    
    /// Update the view to show casting state
    /// - Parameters:
    ///   - isPlaying: Whether the cast is currently playing
    ///   - deviceName: Name of the device being cast to, or nil if not casting
    func updateCastState(isPlaying: Bool, deviceName: String?) {
        controlBarView.updateCastState(isPlaying: isPlaying, deviceName: deviceName)
        centerOverlayView?.updatePlayState(isPlaying: isPlaying)
    }
}

// MARK: - KSPlayerLayerDelegate

// MARK: - KSPlayerLayerDelegate

extension VideoPlayerView: KSPlayerLayerDelegate {
    func player(layer: KSPlayerLayer, state: KSPlayerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let previousWasPlaying = self.previousState == .readyToPlay || self.previousState == .bufferFinished
            
            switch state {
            case .initialized:
                NSLog("VideoPlayerView: Initialized")
            case .preparing:
                NSLog("VideoPlayerView: Preparing to play")
                self.showLoading(true)
            case .readyToPlay:
                NSLog("VideoPlayerView: Ready to play")
                self.showLoading(false)
                self.controlBarView.updatePlayState(isPlaying: true)
                self.resetControlsHideTimer()
                self.onPlaybackStateChanged?(true)
                // Check if resuming from pause
                if self.previousState == .paused {
                    self.onPlaybackResumed?(self.currentTime)
                }
                // Discover available tracks
                self.discoverTracks()
            case .buffering:
                NSLog("VideoPlayerView: Buffering")
                self.showLoading(true)
            case .bufferFinished:
                NSLog("VideoPlayerView: Buffer finished")
                self.showLoading(false)
                self.onPlaybackStateChanged?(true)
                // Check if resuming from pause
                if self.previousState == .paused {
                    self.onPlaybackResumed?(self.currentTime)
                }
            case .paused:
                NSLog("VideoPlayerView: Paused")
                self.controlBarView.updatePlayState(isPlaying: false)
                self.showControls()
                self.onPlaybackStateChanged?(false)
                // Report pause if was playing
                if previousWasPlaying {
                    self.onPlaybackPaused?(self.currentTime)
                }
            case .playedToTheEnd:
                NSLog("VideoPlayerView: Played to end")
                self.controlBarView.updatePlayState(isPlaying: false)
                self.showControls()
                self.onPlaybackStateChanged?(false)
                // Report finished
                self.onPlaybackFinished?(self.currentTime)
            case .error:
                NSLog("VideoPlayerView: Playback error")
                self.showLoading(false)
                self.controlBarView.updatePlayState(isPlaying: false)
                self.onPlaybackStateChanged?(false)
            }
            
            self.previousState = state
        }
    }
    
    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentTime = currentTime
            self.totalDuration = totalTime
            self.controlBarView.updateTime(current: currentTime, total: totalTime)
            
            // Report to WindowManager so main window can display video time
            WindowManager.shared.videoDidUpdateTime(current: currentTime, duration: totalTime)
            
            // Report position update for Plex tracking
            self.onPositionUpdate?(currentTime)
        }
    }
    
    func player(layer: KSPlayerLayer, finish error: Error?) {
        if let error = error {
            NSLog("VideoPlayerView: Finished with error - %@", error.localizedDescription)
        } else {
            NSLog("VideoPlayerView: Finished playback")
        }
        showLoading(false)
    }
    
    func player(layer: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {
        // Buffering progress
    }
}

// MARK: - VideoCenterOverlayView

/// Center overlay with large play/pause button and close button for click-to-control
class VideoCenterOverlayView: NSView {
    
    // MARK: - Properties
    
    var onPlayPause: (() -> Void)?
    var onClose: (() -> Void)?
    
    private var playPauseButton: NSButton!
    private var closeButton: NSButton!
    private var isPlaying: Bool = false
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.4).cgColor
        
        // Large center play/pause button
        playPauseButton = NSButton(frame: .zero)
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.bezelStyle = .regularSquare
        playPauseButton.isBordered = false
        playPauseButton.target = self
        playPauseButton.action = #selector(playPauseClicked)
        if let image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play") {
            let config = NSImage.SymbolConfiguration(pointSize: 60, weight: .regular)
            playPauseButton.image = image.withSymbolConfiguration(config)
            playPauseButton.contentTintColor = .white
        }
        addSubview(playPauseButton)
        
        // Close button in top-right corner
        closeButton = NSButton(frame: .zero)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .regularSquare
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        if let image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close") {
            let config = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
            closeButton.image = image.withSymbolConfiguration(config)
            closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        }
        addSubview(closeButton)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Center play/pause button
            playPauseButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 80),
            playPauseButton.heightAnchor.constraint(equalToConstant: 80),
            
            // Close button in top-right
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }
    
    // MARK: - Actions
    
    @objc private func playPauseClicked() {
        onPlayPause?()
    }
    
    @objc private func closeClicked() {
        onClose?()
    }
    
    // MARK: - Update State
    
    func updatePlayState(isPlaying: Bool) {
        self.isPlaying = isPlaying
        let symbol = isPlaying ? "pause.fill" : "play.fill"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: isPlaying ? "Pause" : "Play") {
            let config = NSImage.SymbolConfiguration(pointSize: 60, weight: .regular)
            playPauseButton.image = image.withSymbolConfiguration(config)
        }
    }
    
    // MARK: - Flipped coordinate system for macOS
    
    override var isFlipped: Bool { true }
}

// MARK: - VideoControlBarView

/// Control bar with play/pause, stop, seek bar, time display, and fullscreen toggle
class VideoControlBarView: NSView {
    
    // MARK: - Properties
    
    var onPlayPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    var onSkipBackward: (() -> Void)?
    var onSkipForward: (() -> Void)?
    var onFullscreen: (() -> Void)?
    var onTrackSettings: (() -> Void)?
    var onCast: (() -> Void)?
    
    private var playButton: NSButton!
    private var stopButton: NSButton!
    private var skipBackButton: NSButton!
    private var skipForwardButton: NSButton!
    private var fullscreenButton: NSButton!
    private var trackSettingsButton: NSButton!
    private var castButton: NSButton!
    private var seekSlider: NSSlider!
    private var currentTimeLabel: NSTextField!
    private var durationLabel: NSTextField!
    private var castingLabel: NSTextField!
    
    private var isPlaying: Bool = false
    private var isSeeking: Bool = false
    private var isCasting: Bool = false
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.7).cgColor
        
        // Stop button
        stopButton = createButton(symbol: "stop.fill", action: #selector(stopClicked))
        stopButton.toolTip = "Stop"
        
        // Skip backward button
        skipBackButton = createButton(symbol: "gobackward.10", action: #selector(skipBackwardClicked))
        
        // Play/Pause button
        playButton = createButton(symbol: "play.fill", action: #selector(playPauseClicked))
        
        // Skip forward button
        skipForwardButton = createButton(symbol: "goforward.10", action: #selector(skipForwardClicked))
        
        // Time labels
        currentTimeLabel = createTimeLabel()
        durationLabel = createTimeLabel()
        
        // Seek slider
        seekSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: self, action: #selector(seekChanged))
        seekSlider.translatesAutoresizingMaskIntoConstraints = false
        seekSlider.isContinuous = true
        
        // Track settings button (subtitles/audio)
        trackSettingsButton = createButton(symbol: "text.bubble", action: #selector(trackSettingsClicked))
        trackSettingsButton.toolTip = "Audio & Subtitle Settings"
        
        // Cast button (for casting to TVs/Chromecast)
        castButton = createButton(symbol: "tv", action: #selector(castClicked))
        castButton.toolTip = "Cast to TV"
        
        // Fullscreen button
        fullscreenButton = createButton(symbol: "arrow.up.left.and.arrow.down.right", action: #selector(fullscreenClicked))
        
        // Casting indicator label (hidden by default)
        castingLabel = NSTextField(labelWithString: "")
        castingLabel.translatesAutoresizingMaskIntoConstraints = false
        castingLabel.textColor = NSColor.systemBlue
        castingLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        castingLabel.alignment = .center
        castingLabel.isHidden = true
        
        addSubview(stopButton)
        addSubview(skipBackButton)
        addSubview(playButton)
        addSubview(skipForwardButton)
        addSubview(currentTimeLabel)
        addSubview(castingLabel)
        addSubview(seekSlider)
        addSubview(durationLabel)
        addSubview(castButton)
        addSubview(trackSettingsButton)
        addSubview(fullscreenButton)
        
        setupConstraints()
    }
    
    private func createButton(symbol: String, action: Selector) -> NSButton {
        let button = NSButton(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.target = self
        button.action = action
        
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            button.image = image
            button.contentTintColor = .white
        }
        
        return button
    }
    
    private func createTimeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "0:00")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.alignment = .center
        return label
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Stop button
            stopButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stopButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: 30),
            stopButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Skip back button
            skipBackButton.leadingAnchor.constraint(equalTo: stopButton.trailingAnchor, constant: 5),
            skipBackButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            skipBackButton.widthAnchor.constraint(equalToConstant: 30),
            skipBackButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Play button
            playButton.leadingAnchor.constraint(equalTo: skipBackButton.trailingAnchor, constant: 5),
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 30),
            playButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Skip forward button
            skipForwardButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 5),
            skipForwardButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            skipForwardButton.widthAnchor.constraint(equalToConstant: 30),
            skipForwardButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Current time label
            currentTimeLabel.leadingAnchor.constraint(equalTo: skipForwardButton.trailingAnchor, constant: 10),
            currentTimeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 50),
            
            // Casting indicator label (centered in the control bar)
            castingLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            castingLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            // Fullscreen button
            fullscreenButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            fullscreenButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            fullscreenButton.widthAnchor.constraint(equalToConstant: 30),
            fullscreenButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Track settings button
            trackSettingsButton.trailingAnchor.constraint(equalTo: fullscreenButton.leadingAnchor, constant: -5),
            trackSettingsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            trackSettingsButton.widthAnchor.constraint(equalToConstant: 30),
            trackSettingsButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Cast button
            castButton.trailingAnchor.constraint(equalTo: trackSettingsButton.leadingAnchor, constant: -5),
            castButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            castButton.widthAnchor.constraint(equalToConstant: 30),
            castButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Duration label
            durationLabel.trailingAnchor.constraint(equalTo: castButton.leadingAnchor, constant: -10),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 50),
            
            // Seek slider
            seekSlider.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 10),
            seekSlider.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -10),
            seekSlider.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    
    // MARK: - Actions
    
    @objc private func playPauseClicked() {
        onPlayPause?()
    }
    
    @objc private func stopClicked() {
        onStop?()
    }
    
    @objc private func skipBackwardClicked() {
        onSkipBackward?()
    }
    
    @objc private func skipForwardClicked() {
        onSkipForward?()
    }
    
    @objc private func fullscreenClicked() {
        onFullscreen?()
    }
    
    @objc private func trackSettingsClicked() {
        onTrackSettings?()
    }
    
    @objc private func castClicked() {
        onCast?()
    }
    
    @objc private func seekChanged() {
        onSeek?(seekSlider.doubleValue)
    }
    
    // MARK: - Updates
    
    func updatePlayState(isPlaying: Bool) {
        self.isPlaying = isPlaying
        let symbol = isPlaying ? "pause.fill" : "play.fill"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            playButton.image = image
        }
    }
    
    func updateTime(current: TimeInterval, total: TimeInterval) {
        currentTimeLabel.stringValue = formatTime(current)
        durationLabel.stringValue = formatTime(total)
        
        // Update slider position (only if not seeking and not casting)
        if total > 0 && !isCasting {
            seekSlider.doubleValue = current / total
        }
    }
    
    /// Update the cast state display
    /// - Parameters:
    ///   - isPlaying: Whether the cast is playing
    ///   - deviceName: Name of the device being cast to, or nil if not casting
    func updateCastState(isPlaying: Bool, deviceName: String?) {
        isCasting = deviceName != nil
        
        if let deviceName = deviceName {
            // Show casting indicator, hide seek slider
            castingLabel.stringValue = "Casting to \(deviceName)"
            castingLabel.isHidden = false
            seekSlider.isHidden = true
            currentTimeLabel.isHidden = true
            durationLabel.isHidden = true
            
            // Update cast button to show active state
            if let image = NSImage(systemSymbolName: "tv.fill", accessibilityDescription: nil) {
                castButton.image = image
                castButton.contentTintColor = .systemBlue
            }
            
            // Update play button for cast state
            let symbol = isPlaying ? "pause.fill" : "play.fill"
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                playButton.image = image
            }
            self.isPlaying = isPlaying
        } else {
            // Hide casting indicator, show seek slider
            castingLabel.isHidden = true
            seekSlider.isHidden = false
            currentTimeLabel.isHidden = false
            durationLabel.isHidden = false
            
            // Reset cast button
            if let image = NSImage(systemSymbolName: "tv", accessibilityDescription: nil) {
                castButton.image = image
                castButton.contentTintColor = .white
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - VideoTitleBarView

/// Skinned title bar view using Winamp TITLEBAR.BMP sprites
class VideoTitleBarView: NSView {
    
    // MARK: - Properties
    
    var title: String = "" {
        didSet { needsDisplay = true }
    }
    
    var isWindowActive: Bool = true {
        didSet { needsDisplay = true }
    }
    
    var onClose: (() -> Void)?
    var onMinimize: (() -> Void)?
    
    private var pressedButton: ButtonType?
    private var mouseInsideButton: Bool = false
    private var initialMouseLocationInScreen: NSPoint?
    private var initialWindowOrigin: NSPoint?
    
    // MARK: - Button Hit Rects
    
    private var closeButtonRect: NSRect {
        NSRect(x: bounds.width - 12, y: 3, width: 9, height: 9)
    }
    
    private var minimizeButtonRect: NSRect {
        NSRect(x: bounds.width - 23, y: 3, width: 9, height: 9)
    }
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    // MARK: - Drawing
    
    override var isFlipped: Bool { true }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let skin = WindowManager.shared.currentSkin ?? SkinLoader.shared.loadDefault()
        let renderer = SkinRenderer(skin: skin)
        
        drawTitleBarBackground(renderer: renderer, context: context)
        drawWindowButtons(renderer: renderer, context: context)
    }
    
    private func drawTitleBarBackground(renderer: SkinRenderer, context: CGContext) {
        guard let titlebarImage = renderer.skin.titlebar else {
            let gradient = NSGradient(colors: [
                isWindowActive ? NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.6, alpha: 1.0) : NSColor(calibratedWhite: 0.3, alpha: 1.0),
                isWindowActive ? NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.3, alpha: 1.0) : NSColor(calibratedWhite: 0.2, alpha: 1.0)
            ])
            gradient?.draw(in: bounds, angle: 0)
            return
        }
        
        let sourceRect = isWindowActive ? SkinElements.TitleBar.active : SkinElements.TitleBar.inactive
        let tileWidth = sourceRect.width
        
        var x: CGFloat = 0
        while x < bounds.width {
            let drawWidth = min(tileWidth, bounds.width - x)
            let destRect = NSRect(x: x, y: 0, width: drawWidth, height: bounds.height)
            let clippedSource = NSRect(x: sourceRect.minX, y: sourceRect.minY, 
                                        width: drawWidth, height: sourceRect.height)
            renderer.drawSprite(from: titlebarImage, sourceRect: clippedSource, to: destRect, in: context)
            x += tileWidth
        }
    }
    
    private func drawWindowButtons(renderer: SkinRenderer, context: CGContext) {
        let minimizeState: ButtonState = (pressedButton == .minimize && mouseInsideButton) ? .pressed : .normal
        renderer.drawButton(.minimize, state: minimizeState, at: minimizeButtonRect, in: context)
        
        let closeState: ButtonState = (pressedButton == .close && mouseInsideButton) ? .pressed : .normal
        renderer.drawButton(.close, state: closeState, at: closeButtonRect, in: context)
    }
    
    // MARK: - Mouse Handling
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        
        if closeButtonRect.contains(location) {
            pressedButton = .close
            mouseInsideButton = true
            needsDisplay = true
            return
        }
        
        if minimizeButtonRect.contains(location) {
            pressedButton = .minimize
            mouseInsideButton = true
            needsDisplay = true
            return
        }
        
        guard let window = window else { return }
        initialMouseLocationInScreen = NSEvent.mouseLocation
        initialWindowOrigin = window.frame.origin
    }
    
    override func mouseDragged(with event: NSEvent) {
        if pressedButton != nil {
            let location = convert(event.locationInWindow, from: nil)
            let buttonRect = pressedButton == .close ? closeButtonRect : minimizeButtonRect
            let wasInside = mouseInsideButton
            mouseInsideButton = buttonRect.contains(location)
            if wasInside != mouseInsideButton {
                needsDisplay = true
            }
            return
        }
        
        guard let window = window,
              let initialMouse = initialMouseLocationInScreen,
              let initialOrigin = initialWindowOrigin else { return }
        
        let currentMouse = NSEvent.mouseLocation
        let deltaX = currentMouse.x - initialMouse.x
        let deltaY = currentMouse.y - initialMouse.y
        
        let newOrigin = NSPoint(x: initialOrigin.x + deltaX, y: initialOrigin.y + deltaY)
        window.setFrameOrigin(newOrigin)
    }
    
    override func mouseUp(with event: NSEvent) {
        defer {
            pressedButton = nil
            mouseInsideButton = false
            initialMouseLocationInScreen = nil
            initialWindowOrigin = nil
            needsDisplay = true
        }
        
        guard let button = pressedButton else { return }
        
        let location = convert(event.locationInWindow, from: nil)
        let buttonRect = button == .close ? closeButtonRect : minimizeButtonRect
        
        if buttonRect.contains(location) {
            switch button {
            case .close:
                onClose?()
            case .minimize:
                onMinimize?()
            default:
                break
            }
        }
    }
}

// MARK: - TrackSelectionPanelDelegate

extension VideoPlayerView: TrackSelectionPanelDelegate {
    func trackSelectionPanel(_ panel: TrackSelectionPanelView, didSelectAudioTrack track: SelectableTrack?) {
        selectAudioTrack(track)
    }
    
    func trackSelectionPanel(_ panel: TrackSelectionPanelView, didSelectSubtitleTrack track: SelectableTrack?) {
        selectSubtitleTrack(track)
    }
    
    func trackSelectionPanel(_ panel: TrackSelectionPanelView, didChangeSubtitleDelay delay: TimeInterval) {
        currentSubtitleDelay = delay
        // KSPlayer uses subtitleDelay option - this would need to be set on the options
        // For now, just store the value
        NSLog("VideoPlayerView: Subtitle delay changed to: %.1fs", delay)
    }
    
    func trackSelectionPanelDidRequestClose(_ panel: TrackSelectionPanelView) {
        hideTrackSelectionPanel()
    }
}

// MARK: - NSMenuDelegate

extension VideoPlayerView: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Update Always on Top checkmark when main context menu opens
        if menu === self.menu {
            if let alwaysOnTopItem = menu.items.first(where: { $0.action == #selector(contextToggleAlwaysOnTop) }) {
                alwaysOnTopItem.state = (window?.level == .floating) ? .on : .off
            }
        }
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Find the parent menu item to determine which submenu this is
        guard let parentItem = self.menu?.items.first(where: { $0.submenu === menu }) else { return }
        
        menu.removeAllItems()
        
        if parentItem.tag == 100 {
            // Audio submenu
            if availableAudioTracks.isEmpty {
                let noTracksItem = NSMenuItem(title: "No Audio Tracks", action: nil, keyEquivalent: "")
                noTracksItem.isEnabled = false
                menu.addItem(noTracksItem)
            } else {
                for (index, track) in availableAudioTracks.enumerated() {
                    let title = track.name ?? "Audio Track \(index + 1)"
                    let item = NSMenuItem(title: title, action: #selector(contextSelectAudioTrack(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = index
                    item.state = track.isEnabled ? .on : .off
                    menu.addItem(item)
                }
            }
        } else if parentItem.tag == 101 {
            // Subtitles submenu
            // "Off" option
            let offItem = NSMenuItem(title: "Off", action: #selector(contextSelectSubtitleTrack(_:)), keyEquivalent: "")
            offItem.target = self
            offItem.tag = -1
            offItem.state = availableSubtitleTracks.allSatisfy { !$0.isEnabled } ? .on : .off
            menu.addItem(offItem)
            
            if !availableSubtitleTracks.isEmpty {
                menu.addItem(NSMenuItem.separator())
                
                for (index, track) in availableSubtitleTracks.enumerated() {
                    let title = track.name ?? "Subtitle Track \(index + 1)"
                    let item = NSMenuItem(title: title, action: #selector(contextSelectSubtitleTrack(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = index
                    item.state = track.isEnabled ? .on : .off
                    menu.addItem(item)
                }
            }
            
            // Add Plex external subtitles if available
            let externalSubs = plexStreams.filter { $0.streamType == .subtitle && $0.isExternal }
            if !externalSubs.isEmpty {
                menu.addItem(NSMenuItem.separator())
                
                let headerItem = NSMenuItem(title: "External Subtitles", action: nil, keyEquivalent: "")
                headerItem.isEnabled = false
                menu.addItem(headerItem)
                
                for stream in externalSubs {
                    let title = stream.localizedDisplayTitle
                    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                    item.isEnabled = false  // External subtitle loading needs additional implementation
                    menu.addItem(item)
                }
            }
        }
    }
}
