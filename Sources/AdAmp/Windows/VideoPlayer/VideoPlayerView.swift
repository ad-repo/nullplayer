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
    
    /// Auto-hide timer for controls
    private var controlsHideTimer: Timer?
    private var controlsVisible: Bool = true
    
    /// Current playback time and duration
    private(set) var currentTime: TimeInterval = 0
    private(set) var totalDuration: TimeInterval = 0
    
    /// Public accessors for playback time
    var currentPlaybackTime: TimeInterval { currentTime }
    var totalPlaybackDuration: TimeInterval { totalDuration }
    
    /// Callback when close button is clicked
    var onClose: (() -> Void)?
    
    /// Callback when minimize button is clicked
    var onMinimize: (() -> Void)?
    
    /// Callback when playback state changes
    var onPlaybackStateChanged: ((Bool) -> Void)?
    
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
        controlBarView.onPlayPause = { [weak self] in self?.togglePlayPause() }
        controlBarView.onSeek = { [weak self] position in self?.seekToPosition(position) }
        controlBarView.onSkipBackward = { [weak self] in self?.skipBackward(10) }
        controlBarView.onSkipForward = { [weak self] in self?.skipForward(10) }
        controlBarView.onFullscreen = { [weak self] in self?.window?.toggleFullScreen(nil) }
        addSubview(controlBarView)
        
        // Create loading indicator
        setupLoadingIndicator()
        
        // Setup context menu
        setupContextMenu()
        
        // Setup mouse tracking for auto-hide controls
        setupMouseTracking()
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
        menu.addItem(withTitle: "Toggle Fullscreen", action: #selector(contextFullscreen), keyEquivalent: "f")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Close", action: #selector(contextClose), keyEquivalent: "w")
        
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
        
        // Add player view to host
        if let playerView = layer.player.view {
            playerView.frame = playerHostView.bounds
            playerView.autoresizingMask = [.width, .height]
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
            showControls()
        } else {
            layer.play()
            controlBarView.updatePlayState(isPlaying: true)
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
}

// MARK: - KSPlayerLayerDelegate

extension VideoPlayerView: KSPlayerLayerDelegate {
    func player(layer: KSPlayerLayer, state: KSPlayerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
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
            case .buffering:
                NSLog("VideoPlayerView: Buffering")
                self.showLoading(true)
            case .bufferFinished:
                NSLog("VideoPlayerView: Buffer finished")
                self.showLoading(false)
                self.onPlaybackStateChanged?(true)
            case .paused:
                NSLog("VideoPlayerView: Paused")
                self.controlBarView.updatePlayState(isPlaying: false)
                self.showControls()
                self.onPlaybackStateChanged?(false)
            case .playedToTheEnd:
                NSLog("VideoPlayerView: Played to end")
                self.controlBarView.updatePlayState(isPlaying: false)
                self.showControls()
                self.onPlaybackStateChanged?(false)
            case .error:
                NSLog("VideoPlayerView: Playback error")
                self.showLoading(false)
                self.controlBarView.updatePlayState(isPlaying: false)
                self.onPlaybackStateChanged?(false)
            }
        }
    }
    
    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            self?.currentTime = currentTime
            self?.totalDuration = totalTime
            self?.controlBarView.updateTime(current: currentTime, total: totalTime)
            
            // Report to WindowManager so main window can display video time
            WindowManager.shared.videoDidUpdateTime(current: currentTime, duration: totalTime)
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

// MARK: - VideoControlBarView

/// Control bar with play/pause, seek bar, time display, and fullscreen toggle
class VideoControlBarView: NSView {
    
    // MARK: - Properties
    
    var onPlayPause: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    var onSkipBackward: (() -> Void)?
    var onSkipForward: (() -> Void)?
    var onFullscreen: (() -> Void)?
    
    private var playButton: NSButton!
    private var skipBackButton: NSButton!
    private var skipForwardButton: NSButton!
    private var fullscreenButton: NSButton!
    private var seekSlider: NSSlider!
    private var currentTimeLabel: NSTextField!
    private var durationLabel: NSTextField!
    
    private var isPlaying: Bool = false
    private var isSeeking: Bool = false
    
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
        
        // Fullscreen button
        fullscreenButton = createButton(symbol: "arrow.up.left.and.arrow.down.right", action: #selector(fullscreenClicked))
        
        addSubview(skipBackButton)
        addSubview(playButton)
        addSubview(skipForwardButton)
        addSubview(currentTimeLabel)
        addSubview(seekSlider)
        addSubview(durationLabel)
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
            // Skip back button
            skipBackButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
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
            
            // Fullscreen button
            fullscreenButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            fullscreenButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            fullscreenButton.widthAnchor.constraint(equalToConstant: 30),
            fullscreenButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Duration label
            durationLabel.trailingAnchor.constraint(equalTo: fullscreenButton.leadingAnchor, constant: -10),
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
    
    @objc private func skipBackwardClicked() {
        onSkipBackward?()
    }
    
    @objc private func skipForwardClicked() {
        onSkipForward?()
    }
    
    @objc private func fullscreenClicked() {
        onFullscreen?()
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
        
        // Update slider position (only if not seeking)
        if total > 0 {
            seekSlider.doubleValue = current / total
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
