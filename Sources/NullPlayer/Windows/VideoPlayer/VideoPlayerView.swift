import AppKit
import NullPlayerCore
import VLCKit

/// Lightweight descriptor for a VLCKit media track. VLCKit exposes tracks as
/// parallel index/name arrays rather than objects, so we carry the VLC track
/// index (the value from `audioTrackIndexes` / `videoSubTitlesIndexes`, not the
/// array position) alongside its display name.
private struct VideoTrackInfo {
    let index: Int32
    let name: String
}

/// Video player view using VLCKit (libVLC), skinned title bar, and controls
class VideoPlayerView: NSView {

    // MARK: - Properties

    private var mediaPlayer: VLCMediaPlayer?
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
    
    /// Available audio tracks (from VLCKit)
    private var availableAudioTracks: [VideoTrackInfo] = []

    /// Available subtitle tracks (from VLCKit)
    private var availableSubtitleTracks: [VideoTrackInfo] = []
    
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

    /// Whether playback is actively running, tracked from the player delegate.
    /// Used to gate control auto-hide instead of polling `mediaPlayer.isPlaying`,
    /// whose value isn't reliable at arbitrary times with VLCKit.
    private var isActivelyPlaying: Bool = false
    
    /// Resize zone handling for borderless window
    private var resizeZone: ResizeZone = .none
    private var isResizing: Bool = false
    private var initialMouseLocation: NSPoint?
    private var initialWindowFrame: NSRect?
    private let resizeMargin: CGFloat = 8  // Width of resize zones at edges
    
    /// Center overlay for click-to-play/pause (large centered icons)
    private var centerOverlayView: VideoCenterOverlayView?
    private var centerOverlayHideTimer: Timer?
    
    /// Current playback time and duration
    private(set) var currentTime: TimeInterval = 0
    private(set) var totalDuration: TimeInterval = 0
    
    /// Public accessors for playback time
    var currentPlaybackTime: TimeInterval { currentTime }
    var totalPlaybackDuration: TimeInterval { totalDuration }
    var isPlaying: Bool { mediaPlayer?.isPlaying == true }

    /// Volume level (0.0 - 1.0)
    var volume: Float = 1.0 {
        didSet {
            // VLCKit expresses volume as 0–100 (up to 200 for boost).
            mediaPlayer?.audio?.volume = Int32(max(0, min(1, volume)) * 100)
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
    private var previousState: VLCMediaPlayerState?
    
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
        mediaPlayer?.pause()
        mediaPlayer?.stop()
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
        // Route through callback if set (for casting intercept), otherwise handle locally
        if let callback = onPlayPauseToggled {
            callback()
        } else {
            togglePlayPause()
        }
    }
    
    @objc private func contextSkipBackward() {
        // Route through callback if set (for casting intercept), otherwise handle locally
        if let callback = onSkipBackwardRequested {
            callback(10)
        } else {
            skipBackward(10)
        }
    }
    
    @objc private func contextSkipForward() {
        // Route through callback if set (for casting intercept), otherwise handle locally
        if let callback = onSkipForwardRequested {
            callback(10)
        } else {
            skipForward(10)
        }
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
            mediaPlayer?.currentAudioTrackIndex = track.index
            NSLog("VideoPlayerView: Selected audio track from menu: %@", track.name)
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
            mediaPlayer?.currentVideoSubTitleIndex = track.index
            NSLog("VideoPlayerView: Selected subtitle track from menu: %@", track.name)
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
        guard isActivelyPlaying else { return }

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
        let location = convert(event.locationInWindow, from: nil)
        
        // Check if in resize zone
        let zone = resizeZoneAt(location)
        if zone != .none {
            isResizing = true
            resizeZone = zone
            initialMouseLocation = NSEvent.mouseLocation
            initialWindowFrame = window?.frame
            return
        }
        
        showControls()
        // Make this view the first responder to capture keyboard events
        window?.makeFirstResponder(self)

        if event.clickCount == 2 {
            // Double-click toggles play/pause
            if let callback = onPlayPauseToggled {
                callback()
            } else {
                togglePlayPause()
            }
            return
        }

        // Single click: show the center overlay, then hand the event to the
        // window so a drag moves it. The borderless window isn't movable by
        // background and VLCKit's drawable subview doesn't pass through window
        // moves the way KSPlayer's view did, so we drive the drag explicitly.
        // performDrag only moves the window if the pointer actually moves, so a
        // plain click still just shows the overlay.
        showCenterOverlay()
        window?.performDrag(with: event)
    }
    
    override func mouseDragged(with event: NSEvent) {
        if isResizing {
            performResize()
            return
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if isResizing {
            isResizing = false
            resizeZone = .none
            initialMouseLocation = nil
            initialWindowFrame = nil
            return
        }
    }
    
    // MARK: - Center Overlay
    
    private func showCenterOverlay() {
        guard let overlay = centerOverlayView else { return }
        
        // Update overlay state
        overlay.updatePlayState(isPlaying: mediaPlayer?.isPlaying ?? false)
        
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
        
        // Update cursor for resize zones
        let location = convert(event.locationInWindow, from: nil)
        let zone = resizeZoneAt(location)
        updateCursor(for: zone)
    }
    
    override func mouseEntered(with event: NSEvent) {
        showControls()
        
        // Update cursor for resize zones
        let location = convert(event.locationInWindow, from: nil)
        let zone = resizeZoneAt(location)
        updateCursor(for: zone)
    }
    
    override func mouseExited(with event: NSEvent) {
        resetControlsHideTimer()
        NSCursor.arrow.set()
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
    
    // MARK: - Window Resize Handling
    
    /// Resize zones for borderless window
    private enum ResizeZone {
        case none
        case left, right, top, bottom
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    /// Determine which resize zone the point is in
    private func resizeZoneAt(_ point: NSPoint) -> ResizeZone {
        let inLeft = point.x < resizeMargin
        let inRight = point.x > bounds.width - resizeMargin
        let inTop = point.y < resizeMargin  // Flipped coordinates
        let inBottom = point.y > bounds.height - resizeMargin
        
        // Corners take priority
        if inTop && inLeft { return .topLeft }
        if inTop && inRight { return .topRight }
        if inBottom && inLeft { return .bottomLeft }
        if inBottom && inRight { return .bottomRight }
        
        // Edges
        if inLeft { return .left }
        if inRight { return .right }
        if inTop { return .top }
        if inBottom { return .bottom }
        
        return .none
    }
    
    /// Update cursor based on resize zone
    private func updateCursor(for zone: ResizeZone) {
        switch zone {
        case .none:
            NSCursor.arrow.set()
        case .left, .right:
            NSCursor.resizeLeftRight.set()
        case .top, .bottom:
            NSCursor.resizeUpDown.set()
        case .topLeft, .bottomRight:
            // macOS doesn't have diagonal resize cursors built-in, use a workaround
            NSCursor.crosshair.set()
        case .topRight, .bottomLeft:
            NSCursor.crosshair.set()
        }
    }
    
    /// Perform window resize based on current mouse position
    private func performResize() {
        guard let window = window,
              let initialMouse = initialMouseLocation,
              let initialFrame = initialWindowFrame else { return }
        
        let currentMouse = NSEvent.mouseLocation
        let deltaX = currentMouse.x - initialMouse.x
        let deltaY = currentMouse.y - initialMouse.y
        
        var newFrame = initialFrame
        let minSize = window.minSize
        
        switch resizeZone {
        case .none:
            return
            
        case .right:
            newFrame.size.width = max(minSize.width, initialFrame.width + deltaX)
            
        case .left:
            let newWidth = max(minSize.width, initialFrame.width - deltaX)
            let widthDelta = newWidth - initialFrame.width
            newFrame.origin.x = initialFrame.origin.x - widthDelta
            newFrame.size.width = newWidth
            
        case .top:
            // Top edge resize: bottom edge (origin.y) stays fixed, only height changes
            // Positive deltaY = dragging up = height increases
            newFrame.size.height = max(minSize.height, initialFrame.height + deltaY)
            
        case .bottom:
            // Bottom edge resize: top edge stays fixed, origin.y moves with height change
            newFrame.size.height = max(minSize.height, initialFrame.height - deltaY)
            newFrame.origin.y = initialFrame.origin.y + (initialFrame.height - newFrame.size.height)
            
        case .topRight:
            // Top-right corner: bottom-left corner stays fixed
            newFrame.size.width = max(minSize.width, initialFrame.width + deltaX)
            newFrame.size.height = max(minSize.height, initialFrame.height + deltaY)
            
        case .topLeft:
            // Top-left corner: bottom-right corner stays fixed
            // Left edge moves, bottom edge stays fixed
            let newWidth = max(minSize.width, initialFrame.width - deltaX)
            let widthDelta = newWidth - initialFrame.width
            newFrame.origin.x = initialFrame.origin.x - widthDelta
            newFrame.size.width = newWidth
            newFrame.size.height = max(minSize.height, initialFrame.height + deltaY)
            
        case .bottomRight:
            newFrame.size.width = max(minSize.width, initialFrame.width + deltaX)
            newFrame.size.height = max(minSize.height, initialFrame.height - deltaY)
            newFrame.origin.y = initialFrame.origin.y + (initialFrame.height - newFrame.size.height)
            
        case .bottomLeft:
            let newWidth = max(minSize.width, initialFrame.width - deltaX)
            let widthDelta = newWidth - initialFrame.width
            newFrame.origin.x = initialFrame.origin.x - widthDelta
            newFrame.size.width = newWidth
            newFrame.size.height = max(minSize.height, initialFrame.height - deltaY)
            newFrame.origin.y = initialFrame.origin.y + (initialFrame.height - newFrame.size.height)
        }
        
        window.setFrame(newFrame, display: true)
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
        
        // Stop existing player if any
        mediaPlayer?.stop()
        mediaPlayer = nil
        previousState = nil
        isActivelyPlaying = false
        availableAudioTracks = []
        availableSubtitleTracks = []
        // Clear Plex external-subtitle entries so a stale set can't carry into
        // the next item; callers re-populate via setPlexStreams() after play().
        plexStreams = []

        // Build the media. VLC has no arbitrary-header API; for remote/relay Plex
        // the auth token rides in the URL query string, and only the user-agent
        // maps to a VLC option. Map what VLC supports and rely on query-param auth.
        let media = VLCMedia(url: url)
        if isPlexURL, let headers = plexHeaders {
            var options: [String: Any] = [:]
            if let userAgent = headers["User-Agent"] ?? headers["user-agent"] {
                options[":http-user-agent"] = userAgent
            }
            if !options.isEmpty {
                media.addOptions(options)
            }
            NSLog("VideoPlayerView: Plex stream — mapped %d of %d headers to VLC options (auth via URL query)",
                  options.count, headers.count)
        }

        // VLCKit renders directly into the NSView assigned to `drawable`; no
        // subview insertion or sublayer black-out walk is needed. Keeping the
        // host layer black avoids a white flash before the first frame.
        let player = VLCMediaPlayer()
        player.drawable = playerHostView
        player.delegate = self
        player.media = media
        player.audio?.volume = Int32(max(0, min(1, volume)) * 100)
        mediaPlayer = player
        player.play()

        // Redact auth query params (e.g. Plex X-Plex-Token) — the token rides in
        // the URL for query-param auth and must not leak into system logs.
        NSLog("VideoPlayerView: Playing %@ from %@", title, url.redacted)
    }
    
    /// Stop playback
    func stop() {
        controlsHideTimer?.invalidate()
        isActivelyPlaying = false
        mediaPlayer?.pause()
        mediaPlayer?.stop()
        showLoading(false)
        controlBarView.updatePlayState(isPlaying: false)
    }

    /// Ensure VLCKit is producing audio: an audio track is selected, output is
    /// unmuted, and the volume matches `volume`. Safe to call repeatedly; the
    /// `audio` controller is nil until the audio pipeline exists, so this becomes
    /// effective once an audio elementary stream has been added.
    private func applyAudioOutput() {
        guard let player = mediaPlayer else { return }
        // If VLC hasn't auto-selected an audio track, pick the first real one.
        if player.currentAudioTrackIndex < 0 {
            let audioIndexes = (player.audioTrackIndexes as? [NSNumber]) ?? []
            if let first = audioIndexes.map({ $0.int32Value }).first(where: { $0 >= 0 }) {
                player.currentAudioTrackIndex = first
            }
        }
        if let audio = player.audio {
            audio.isMuted = false
            audio.volume = Int32(max(0, min(1, volume)) * 100)
        }
    }

    /// Handle the player actually running. VLCKit reports either `.playing` or
    /// `.buffering` (with `isPlaying == true`) during smooth playback, so this is
    /// driven off `isPlaying`, not a single state. Idempotent: the one-time
    /// "just started" work (hide-timer start, track discovery, resume callback)
    /// runs only on the transition into playing, so the controls-hide countdown
    /// and track list aren't reset on every buffering notification.
    private func markPlaying() {
        showLoading(false)
        controlBarView.updatePlayState(isPlaying: true)
        guard !isActivelyPlaying else { return }
        NSLog("VideoPlayerView: Playing")
        let wasPaused = (previousState == .paused)
        isActivelyPlaying = true
        resetControlsHideTimer()
        applyAudioOutput()
        onPlaybackStateChanged?(true)
        if wasPaused {
            onPlaybackResumed?(currentTime)
        }
        discoverTracks()
    }

    /// Toggle play/pause
    func togglePlayPause() {
        guard let player = mediaPlayer else { return }

        if player.isPlaying {
            player.pause()
            controlBarView.updatePlayState(isPlaying: false)
            centerOverlayView?.updatePlayState(isPlaying: false)
            showControls()
        } else {
            player.play()
            controlBarView.updatePlayState(isPlaying: true)
            centerOverlayView?.updatePlayState(isPlaying: true)
            resetControlsHideTimer()
        }
    }

    // Note: VLCKit's `player.time` / `player.position` setters don't change the
    // play/pause state — a playing player keeps playing after a seek and a paused
    // one stays paused. These helpers deliberately do NOT force play(), so a
    // caller that seeks and then resumes explicitly (e.g. stopCasting: seek +
    // togglePlayPause) isn't flipped back to paused by an implicit resume here.

    /// Seek to normalized position (0-1)
    func seekToPosition(_ position: Double) {
        guard let player = mediaPlayer else { return }
        player.position = Float(position)
    }

    /// Seek to time
    func seek(to time: TimeInterval) {
        guard let player = mediaPlayer else { return }
        player.time = VLCTime(int: Int32(max(0, time) * 1000))
    }

    /// Skip forward by seconds
    func skipForward(_ seconds: TimeInterval = 10) {
        guard let player = mediaPlayer else { return }
        let current = Double(player.time.intValue) / 1000.0
        let newTime = totalDuration > 0 ? min(current + seconds, totalDuration) : current + seconds
        player.time = VLCTime(int: Int32(newTime * 1000))
    }

    /// Skip backward by seconds
    func skipBackward(_ seconds: TimeInterval = 10) {
        guard let player = mediaPlayer else { return }
        let current = Double(player.time.intValue) / 1000.0
        let newTime = max(0, current - seconds)
        player.time = VLCTime(int: Int32(newTime * 1000))
    }
    
    // MARK: - Track Selection
    
    /// Set Plex streams for external subtitle support
    func setPlexStreams(_ streams: [PlexStream]) {
        plexStreams = streams
        updateTrackSelectionPanel()
    }
    
    /// Discover available tracks from VLCKit.
    ///
    /// VLCKit exposes tracks as parallel index/name arrays that are only
    /// populated once playback has started, so this is driven from the player
    /// delegate (`.playing` / `.esAdded`), not synchronously from `play()`.
    /// VLC includes a built-in "Disable" pseudo-entry (index −1) in both arrays;
    /// we filter it out because the UI supplies its own "Off" affordance.
    private func discoverTracks() {
        guard let player = mediaPlayer else { return }

        func tracks(indexes: [Any]?, names: [Any]?) -> [VideoTrackInfo] {
            let idx = (indexes as? [NSNumber]) ?? []
            let nms = (names as? [String]) ?? []
            return zip(idx, nms).compactMap { number, name in
                let index = number.int32Value
                return index >= 0 ? VideoTrackInfo(index: index, name: name) : nil
            }
        }

        availableAudioTracks = tracks(indexes: player.audioTrackIndexes, names: player.audioTrackNames)
        availableSubtitleTracks = tracks(indexes: player.videoSubTitlesIndexes, names: player.videoSubTitlesNames)

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

        let currentAudioIndex = mediaPlayer?.currentAudioTrackIndex ?? -1
        let currentSubtitleIndex = mediaPlayer?.currentVideoSubTitleIndex ?? -1

        // Convert VLCKit audio tracks to SelectableTracks
        let audioTracks = availableAudioTracks.map { track in
            SelectableTrack(
                id: "audio_\(track.index)",
                type: .audio,
                name: track.name,
                language: nil,
                codec: nil,
                isSelected: track.index == currentAudioIndex,
                isExternal: false,
                externalURL: nil,
                vlcTrackIndex: track.index,
                plexStream: nil
            )
        }

        // Convert VLCKit subtitle tracks to SelectableTracks
        var subtitleTracks = availableSubtitleTracks.map { track in
            SelectableTrack(
                id: "subtitle_\(track.index)",
                type: .subtitle,
                name: track.name,
                language: nil,
                codec: nil,
                isSelected: track.index == currentSubtitleIndex,
                isExternal: false,
                externalURL: nil,
                vlcTrackIndex: track.index,
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
                vlcTrackIndex: nil,
                plexStream: stream
            )
        }
        subtitleTracks.append(contentsOf: externalSubtitles)

        panel.updateTracks(audioTracks: audioTracks, subtitleTracks: subtitleTracks)
    }
    
    /// Select an audio track
    func selectAudioTrack(_ track: SelectableTrack?) {
        guard let player = mediaPlayer, let track = track, let vlcIndex = track.vlcTrackIndex else { return }
        player.currentAudioTrackIndex = vlcIndex
        NSLog("VideoPlayerView: Selected audio track: %@", track.name)
        updateTrackSelectionPanel()
    }

    /// Select a subtitle track (nil to disable subtitles)
    func selectSubtitleTrack(_ track: SelectableTrack?) {
        guard let player = mediaPlayer else { return }

        if let track = track {
            if let vlcIndex = track.vlcTrackIndex {
                // Embedded subtitle
                player.currentVideoSubTitleIndex = vlcIndex
                NSLog("VideoPlayerView: Selected subtitle track: %@", track.name)
            } else if let externalURL = track.externalURL, externalURL.scheme != nil {
                // External subtitle from an absolute URL (e.g. a sidecar file).
                player.addPlaybackSlave(externalURL, type: .subtitle, enforce: true)
                NSLog("VideoPlayerView: Loaded external subtitle from: %@", externalURL.redacted)
            } else {
                // Plex external-subtitle keys are server-relative API paths; loading
                // them needs the Plex server base URL + token, which lives in
                // PlexManager rather than this view. Left as a follow-up.
                NSLog("VideoPlayerView: External subtitle '%@' has no absolute URL; skipping", track.name)
            }
        } else {
            // Real "Off" — VLCKit disables subtitles at index -1.
            player.currentVideoSubTitleIndex = -1
            NSLog("VideoPlayerView: Subtitles disabled")
        }
        updateTrackSelectionPanel()
    }

    /// Cycle to next audio track
    func cycleAudioTrack() {
        guard !availableAudioTracks.isEmpty, let player = mediaPlayer else { return }

        let currentVLCIndex = player.currentAudioTrackIndex
        let currentPosition = availableAudioTracks.firstIndex { $0.index == currentVLCIndex } ?? -1
        let nextPosition = (currentPosition + 1) % availableAudioTracks.count
        let nextTrack = availableAudioTracks[nextPosition]

        player.currentAudioTrackIndex = nextTrack.index
        NSLog("VideoPlayerView: Cycled to audio track: %@", nextTrack.name)
        updateTrackSelectionPanel()
    }

    /// Cycle to next subtitle track (including "Off")
    func cycleSubtitleTrack() {
        guard let player = mediaPlayer else { return }
        let totalOptions = availableSubtitleTracks.count + 1  // +1 for "Off"
        guard totalOptions > 1 else { return }

        let currentVLCIndex = player.currentVideoSubTitleIndex
        let currentPosition = availableSubtitleTracks.firstIndex { $0.index == currentVLCIndex } ?? -1
        let nextPosition = currentPosition + 1  // -1 -> 0 (first subtitle), last -> off

        if nextPosition >= availableSubtitleTracks.count {
            // Select "Off" - disable subtitles
            selectSubtitleTrack(nil)
            NSLog("VideoPlayerView: Subtitles turned off")
        } else {
            let nextTrack = availableSubtitleTracks[nextPosition]
            player.currentVideoSubTitleIndex = nextTrack.index
            NSLog("VideoPlayerView: Cycled to subtitle track: %@", nextTrack.name)
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

// MARK: - VLCMediaPlayerDelegate

extension VideoPlayerView: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let player = self.mediaPlayer else { return }
            let state = player.state

            switch state {
            case .opening:
                NSLog("VideoPlayerView: Opening")
                self.showLoading(true)
            case .buffering:
                // VLCKit reports `.buffering` during smooth playback in this
                // build (not only while pre-buffering), so gate on whether
                // libVLC is actually playing rather than on the state alone.
                if player.isPlaying {
                    self.markPlaying()
                } else {
                    NSLog("VideoPlayerView: Buffering")
                    self.showLoading(true)
                }
            case .playing:
                self.markPlaying()
            case .esAdded:
                // An elementary stream was added — refresh the track list and
                // (re)apply audio, since the audio ES may have just appeared.
                self.discoverTracks()
                self.applyAudioOutput()
                if player.isPlaying { self.markPlaying() }
            case .paused:
                NSLog("VideoPlayerView: Paused")
                let wasPlaying = self.isActivelyPlaying
                self.isActivelyPlaying = false
                self.showLoading(false)
                self.controlBarView.updatePlayState(isPlaying: false)
                self.showControls()
                self.onPlaybackStateChanged?(false)
                if wasPlaying {
                    self.onPlaybackPaused?(self.currentTime)
                }
            case .ended:
                NSLog("VideoPlayerView: Played to end")
                self.isActivelyPlaying = false
                self.showLoading(false)
                self.controlBarView.updatePlayState(isPlaying: false)
                self.showControls()
                self.onPlaybackStateChanged?(false)
                // Report finished
                self.onPlaybackFinished?(self.currentTime)
            case .stopped:
                NSLog("VideoPlayerView: Stopped")
                self.isActivelyPlaying = false
                self.showLoading(false)
                self.controlBarView.updatePlayState(isPlaying: false)
                self.onPlaybackStateChanged?(false)
            case .error:
                NSLog("VideoPlayerView: Playback error")
                self.isActivelyPlaying = false
                self.showLoading(false)
                self.controlBarView.updatePlayState(isPlaying: false)
                self.onPlaybackStateChanged?(false)
            @unknown default:
                break
            }

            self.previousState = state
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let player = self.mediaPlayer else { return }

            // Robust playing signal: time only advances during playback, and
            // VLCKit's state enum is unreliable here — so if we haven't yet
            // registered playback, do it now (stops the spinner, starts the
            // controls-hide countdown).
            if !self.isActivelyPlaying && player.isPlaying {
                self.markPlaying()
            }

            let current = Double(player.time.intValue) / 1000.0

            // VLCMedia.length may be 0 until parsed; fall back to time / position.
            var total = self.totalDuration
            if let lengthMs = player.media?.length.intValue, lengthMs > 0 {
                total = Double(lengthMs) / 1000.0
            } else if player.position > 0 {
                total = current / Double(player.position)
            }

            self.currentTime = current
            self.totalDuration = total
            self.controlBarView.updateTime(current: current, total: total)

            // Report to WindowManager so main window can display video time
            WindowManager.shared.videoDidUpdateTime(current: current, duration: total)

            // Report position update for Plex tracking
            self.onPositionUpdate?(current)
        }
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
        // VLCKit expresses subtitle delay in microseconds.
        mediaPlayer?.currentVideoSubTitleDelay = Int(delay * 1_000_000)
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
            let currentAudioIndex = mediaPlayer?.currentAudioTrackIndex ?? -1
            if availableAudioTracks.isEmpty {
                let noTracksItem = NSMenuItem(title: "No Audio Tracks", action: nil, keyEquivalent: "")
                noTracksItem.isEnabled = false
                menu.addItem(noTracksItem)
            } else {
                for (index, track) in availableAudioTracks.enumerated() {
                    let item = NSMenuItem(title: track.name, action: #selector(contextSelectAudioTrack(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = index
                    item.state = track.index == currentAudioIndex ? .on : .off
                    menu.addItem(item)
                }
            }
        } else if parentItem.tag == 101 {
            // Subtitles submenu
            let currentSubtitleIndex = mediaPlayer?.currentVideoSubTitleIndex ?? -1
            // "Off" option
            let offItem = NSMenuItem(title: "Off", action: #selector(contextSelectSubtitleTrack(_:)), keyEquivalent: "")
            offItem.target = self
            offItem.tag = -1
            offItem.state = currentSubtitleIndex == -1 ? .on : .off
            menu.addItem(offItem)

            if !availableSubtitleTracks.isEmpty {
                menu.addItem(NSMenuItem.separator())

                for (index, track) in availableSubtitleTracks.enumerated() {
                    let item = NSMenuItem(title: track.name, action: #selector(contextSelectSubtitleTrack(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = index
                    item.state = track.index == currentSubtitleIndex ? .on : .off
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
