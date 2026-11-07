import AppKit

// =============================================================================
// PROJECTM VIEW - Visualization window with skin sprite support
// =============================================================================
// Follows the same pattern as EQView and PlaylistView for:
// - Coordinate transformation (skin top-down system)
// - Button hit testing and visual feedback
// - Window dragging support
// =============================================================================

/// ProjectM visualization view with full skin support
class ProjectMView: NSView, VisualizationMenuTarget {
    
    // MARK: - Properties
    
    weak var controller: ProjectMWindowController?
    
    /// The OpenGL visualization view
    private(set) var visualizationGLView: VisualizationGLView?

    /// Fullscreen mode state (hides window chrome)
    private(set) var isFullscreen = false

    /// Highlight state for drag-mode visual feedback
    private var isHighlighted = false
    
    /// Button being pressed (for visual feedback)
    private var pressedButton: SkinRenderer.ProjectMButtonType?
    
    /// Window dragging state
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    
    /// Observer for PCM data notifications
    private var pcmObserver: NSObjectProtocol?

    /// Observer for spectrum data notifications
    private var spectrumObserver: NSObjectProtocol?

    /// Observer for playback state changes
    private var playbackStateObserver: NSObjectProtocol?
    
    /// Store for persisted projectM preset ratings.
    private let presetRatingsStore = ProjectMPresetRatingsStore.shared

    /// Dismiss task for the preset rating overlay.
    private var presetRatingDismissTask: Task<Void, Never>?

    /// Whether the preset rating overlay is currently visible.
    private var isPresetRatingOverlayVisible = false
    
    // MARK: - Layout Constants
    // Reference to SkinElements.ProjectM.Layout for consistency
    
    /// Where this window's chrome ends and the visualization begins.
    ///
    /// The classic constants, unless the hosting skin lends a window frame of its own — a `.wmz`
    /// skin that builds its panels out of an eight-piece ring states its content hole exactly
    /// (`WMPHostedFrameTemplate`).
    private var Layout: SkinnedSurfaceChrome.Metrics {
        SkinnedSurfaceChrome.metrics(for: bounds, fallback: .projectM)
    }

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

        // Set up accessibility identifiers for UI testing
        setupAccessibility()

        // Create and add OpenGL visualization view
        setupVisualizationView()

        // Subscribe to PCM data notifications (low-latency direct from audio tap)
        pcmObserver = NotificationCenter.default.addObserver(
            forName: .audioPCMDataUpdated,
            object: nil,
            queue: nil  // Receive on posting thread for lowest latency
        ) { [weak self] notification in
            self?.handlePCMUpdate(notification)
        }

        // Subscribe to spectrum data notifications (for TOC Spectrum renderer)
        spectrumObserver = NotificationCenter.default.addObserver(
            forName: .audioSpectrumDataUpdated,
            object: nil,
            queue: nil  // Receive on posting thread for lowest latency
        ) { [weak self] notification in
            self?.handleSpectrumUpdate(notification)
        }
        WindowManager.shared.audioEngine.addSpectrumConsumer("projectMView")

        // Subscribe to playback state changes (for idle/active visualization mode)
        playbackStateObserver = NotificationCenter.default.addObserver(
            forName: .audioPlaybackStateChanged,
            object: nil,
            queue: .main  // UI update, use main thread
        ) { [weak self] notification in
            self?.handlePlaybackStateChange(notification)
        }
        
        // Set initial audio active state
        updateAudioActiveState()

        // Observe connected-window highlight changes for drag-mode visual feedback
        NotificationCenter.default.addObserver(self, selector: #selector(hostedSurfaceStyleDidChange),
                                               name: .hostedSurfaceStyleDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(connectedWindowHighlightDidChange(_:)),
                                               name: .connectedWindowHighlightDidChange, object: nil)
    }
    
    private func setupVisualizationView() {
        // Calculate visualization area - will be updated in layout()
        let visArea = calculateVisualizationArea()
        
        visualizationGLView = VisualizationGLView(frame: visArea, pixelFormat: nil)
        if let visView = visualizationGLView {
            // Don't use autoresizingMask - we manually update frame in layout()
            visView.autoresizingMask = []
            addSubview(visView)
            // The rating overlay rates the preset showing; any preset change closes it.
            visView.enginePresetDidChange = { [weak self] in
                guard let self, self.isPresetRatingOverlayVisible else { return }
                self.hidePresetRatingOverlay()
            }
        }
    }

    /// Lazy star rating overlay reused from art mode.
    private lazy var presetRatingOverlay: RatingOverlayView = {
        let overlay = RatingOverlayView(frame: bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.isHidden = true
        overlay.onRatingSelected = { [weak self] ratingOnTenScale in
            self?.submitCurrentPresetRating(ratingOnTenScale)
        }
        overlay.onDismiss = { [weak self] in
            self?.hidePresetRatingOverlay()
        }
        addSubview(overlay)
        return overlay
    }()
    
    private func calculateVisualizationArea() -> NSRect {
        // In fullscreen mode, visualization takes the entire bounds
        if isFullscreen {
            return bounds
        }
        
        // The visualization area is the content area inside the chrome
        // Chrome: title bar at top, thin borders on sides and bottom
        let titleHeight = WindowManager.shared.hideTitleBars ? CGFloat(0) : Layout.titleBarHeight
        let leftBorder = Layout.leftBorder
        let rightBorder = Layout.rightBorder
        let bottomBorder = Layout.bottomBorder
        
        // In macOS coordinates, y=0 is at the bottom
        // So: bottom border is at y=0, visualization starts at y=bottomBorder
        // Title bar is at the top, so visualization height = bounds.height - titleHeight - bottomBorder
        return NSRect(
            x: leftBorder,
            y: bottomBorder,
            width: max(0, bounds.width - leftBorder - rightBorder),
            height: max(0, bounds.height - titleHeight - bottomBorder)
        )
    }
    
    deinit {
        presetRatingDismissTask?.cancel()
        if let observer = pcmObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = spectrumObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = playbackStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        WindowManager.shared.audioEngine.removeSpectrumConsumer("projectMView")
        visualizationGLView?.stopRendering()
    }
    
    // MARK: - Accessibility
    
    /// Set up accessibility identifiers for UI testing
    private func setupAccessibility() {
        setAccessibilityIdentifier("visualizationView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("Visualization")
    }
    
    // MARK: - Coordinate Conversion
    
    /// Convert a point from view coordinates (macOS bottom-left origin) to skin coordinates (top-left origin)
    private func convertToSkinCoordinates(_ point: NSPoint) -> NSPoint {
        // Simply flip Y coordinate - no scaling needed for resizable window
        var skinPoint = NSPoint(x: point.x, y: bounds.height - point.y)
        // When title bars are hidden, offset to match the shifted drawing
        if WindowManager.shared.hideTitleBars {
            skinPoint.y += Layout.titleBarHeight
        }
        return skinPoint
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // In fullscreen mode, just draw black background (visualization fills the rest)
        if isFullscreen {
            context.setFillColor(NSColor.black.cgColor)
            context.fill(bounds)
            return
        }
        
        // Use current skin
        let skin = WindowManager.shared.currentSkin ?? SkinLoader.shared.loadDefault()
        let renderer = SkinRenderer(skin: skin)
        let isActive = window?.isKeyWindow ?? true
        
        // Flip coordinate system to match skin's top-down coordinates
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        
        // When hiding title bars, shift content up to clip the title bar off the top
        if WindowManager.shared.hideTitleBars {
            context.translateBy(x: 0, y: -Layout.titleBarHeight)
        }
        
        // Draw window chrome at actual window bounds (no scaling - chrome tiles to fill) — or, in a
        // mode that hosts a foreign skin, that skin's palette and its own window ring.
        if let style = WindowManager.shared.hostedSurfaceStyle {
            SkinnedSurfaceChrome(style: style,
                                 artwork: WindowManager.shared.hostedSurfaceFrameArtwork(for: bounds.size))
                .drawSpectrumFamilyWindow(
                    in: context,
                    bounds: bounds,
                    metrics: .projectM,
                    isActive: isActive,
                    isClosePressed: pressedButton == .close,
                    controlScale: WindowManager.shared.playlistChromeScale,
                    title: "VISUALIZATIONS",
                    fillBackground: true
                )
        } else {
            renderer.drawProjectMWindow(in: context, bounds: bounds, isActive: isActive,
                                        pressedButton: pressedButton,
                                        controlScale: WindowManager.shared.playlistChromeScale)
        }
        
        context.restoreGState()

        if isHighlighted {
            NSColor.white.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }
    }

    /// The hosting skin's palette or its borrowed frame has moved — a skin load, a view switch, or
    /// a ring that has finished rendering for this window's size.
    @objc private func hostedSurfaceStyleDidChange() {
        // **A borrowed frame moves the content hole, and a hole that moved is a layout, not a
        // repaint (W220).** This notification is the only edit some of these windows ever get: the
        // ring is derived asynchronously for the window's own size, so it lands *after* the view
        // has laid out against the classic fallback metrics. `needsDisplay` alone redraws the
        // chrome around subviews still framed for the old hole — on `Visualizations` that is the
        // whole GL view, which keeps the full window and buries every borrowed piece under the
        // visualization. Marking the layout dirty costs nothing where a view has no subviews.
        needsLayout = true
        updateVisualizationFrame()
        needsDisplay = true
    }

    @objc private func connectedWindowHighlightDidChange(_ notification: Notification) {
        let highlighted = notification.userInfo?["highlightedWindows"] as? Set<NSWindow> ?? []
        let newValue = highlighted.contains { $0 === window }
        if isHighlighted != newValue {
            isHighlighted = newValue
            needsDisplay = true
        }
    }

    // MARK: - Visualization Data
    
    /// Handle PCM data notification from audio tap (called on audio thread for low latency)
    private func handlePCMUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let pcm = userInfo["pcm"] as? [Float] else { return }

        // Forward PCM data directly to visualization view (thread-safe via dataLock)
        // No main thread dispatch needed - updatePCM handles thread safety internally
        visualizationGLView?.updatePCM(pcm)
    }

    /// Handle spectrum data notification from audio engine (called on audio thread for low latency)
    private func handleSpectrumUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let spectrum = userInfo["spectrum"] as? [Float] else { return }

        // Forward spectrum data directly to visualization view (thread-safe)
        visualizationGLView?.updateSpectrum(spectrum)
    }

    /// Handle playback state changes to update audio active state
    private func handlePlaybackStateChange(_ notification: Notification) {
        updateAudioActiveState()
    }
    
    /// Update the audio active state for idle mode (calmer visualization when not playing)
    private func updateAudioActiveState() {
        let audioEngine = WindowManager.shared.audioEngine
        let isPlaying = audioEngine.state == .playing
        visualizationGLView?.setAudioActive(isPlaying)
    }
    
    // MARK: - Public Methods
    
    func skinDidChange() {
        needsDisplay = true
    }
    
    /// Set fullscreen mode (hides window chrome)
    func setFullscreen(_ enabled: Bool) {
        isFullscreen = enabled
        updateVisualizationFrame()
        needsDisplay = true
    }
    
    /// Update visualization view frame after resize
    func updateVisualizationFrame() {
        let visArea = calculateVisualizationArea()
        visualizationGLView?.frame = visArea
    }

    /// Stop rendering (for window close/hide)
    func stopRendering() {
        visualizationGLView?.stopRendering()
    }

    /// Start rendering
    func startRendering() {
        visualizationGLView?.startRendering()
    }

    func resumeRenderingAfterWindowTransition() {
        visualizationGLView?.resumeRenderingAfterWindowTransition()
    }

    // MARK: - Preset Ratings

    private func starString(for rating: Int) -> String {
        let clamped = min(5, max(0, rating))
        return String(repeating: "⭐", count: clamped) + String(repeating: "☆", count: 5 - clamped)
    }

    private func currentPresetIdentity() -> (index: Int, name: String, path: String)? {
        guard let visView = visualizationGLView, visView.isProjectMAvailable else { return nil }
        let index = visView.currentPresetIndex
        let name = visView.currentPresetName
        let path = visView.presetPath(at: index)
        guard !path.isEmpty else { return nil }
        return (index, name, path)
    }
    
    private func presetIndex(forPath path: String) -> Int? {
        guard let visView = visualizationGLView else { return nil }
        let normalizedTarget = (path as NSString).standardizingPath
        guard !normalizedTarget.isEmpty else { return nil }
        
        for index in 0..<visView.presetCount {
            let candidate = (visView.presetPath(at: index) as NSString).standardizingPath
            if candidate == normalizedTarget {
                return index
            }
        }
        return nil
    }

    private func showPresetRatingOverlay() {
        guard let preset = currentPresetIdentity() else { return }
        let currentRating = presetRatingsStore.rating(forPresetPath: preset.path)
        presetRatingDismissTask?.cancel()
        presetRatingDismissTask = nil
        presetRatingOverlay.frame = bounds
        presetRatingOverlay.setRating(currentRating * 2)
        presetRatingOverlay.isHidden = false
        isPresetRatingOverlayVisible = true
        needsDisplay = true
    }

    private func hidePresetRatingOverlay() {
        presetRatingDismissTask?.cancel()
        presetRatingDismissTask = nil
        presetRatingOverlay.isHidden = true
        isPresetRatingOverlayVisible = false
        needsDisplay = true
    }

    private func submitCurrentPresetRating(_ ratingOnTenScale: Int) {
        guard let preset = currentPresetIdentity() else { return }
        let rating = min(5, max(0, ratingOnTenScale / 2))
        presetRatingsStore.setRating(rating, forPresetPath: preset.path, presetName: preset.name)

        presetRatingDismissTask?.cancel()
        presetRatingDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            await MainActor.run {
                self?.hidePresetRatingOverlay()
            }
        }
    }
    
    // MARK: - Hit Testing
    
    /// Top 1/4 of the window is the drag zone
    private func hitTestTopZone(at point: NSPoint) -> Bool {
        return point.y >= bounds.height * 0.75
    }

    /// Check if point hits title bar (for dragging)
    private func hitTestTitleBar(at skinPoint: NSPoint) -> Bool {
        if WindowManager.shared.hideTitleBars {
            // Invisible drag zone at the top of the visible window
            return skinPoint.y >= Layout.titleBarHeight && skinPoint.y < Layout.titleBarHeight + 6
        }
        // Title bar is at the top, leave room for close button on the right
        return skinPoint.y < Layout.titleBarHeight &&
               skinPoint.x < closeButtonRect.minX  // Leave room for close button area
    }
    
    /// The close box, from the one place that decides where it goes — inset by a borrowed ring's
    /// own right border so the glyph the chrome draws is the glyph a click lands on (W178).
    private var closeButtonRect: NSRect {
        SkinnedSurfaceChrome.closeButtonRect(in: bounds, captionHeight: Layout.titleBarHeight)
    }

    /// Check if point hits close button
    private func hitTestCloseButton(at skinPoint: NSPoint) -> Bool {
        if WindowManager.shared.hideTitleBars { return false }
        // A generous hit area: the whole title bar height, the last 25px of width, moved inside a
        // borrowed ring's right border where one is lent.
        return closeButtonRect.contains(skinPoint)
    }
    
    // MARK: - Mouse Events
    
    /// Allow clicking even when window is not active
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let skinPoint = convertToSkinCoordinates(point)

        // Check window control buttons
        if hitTestCloseButton(at: skinPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }

        // Top 1/4 of window: drag zone
        if hitTestTopZone(at: point) {
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
            if let window = window {
                WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
            }
            return
        }

        // Bottom 3/4: show ratings overlay for ProjectM presets only.
        if visualizationGLView?.currentEngineType == .projectM {
            showPresetRatingOverlay()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        // Handle window dragging (moves docked windows too)
        if isDraggingWindow, let window = window {
            let currentPoint = event.locationInWindow
            let deltaX = currentPoint.x - windowDragStartPoint.x
            let deltaY = currentPoint.y - windowDragStartPoint.y
            
            var newOrigin = window.frame.origin
            newOrigin.x += deltaX
            newOrigin.y += deltaY
            
            // Use WindowManager for snapping and moving docked windows
            newOrigin = WindowManager.shared.windowWillMove(window, to: newOrigin)
            window.setFrameOrigin(newOrigin)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let skinPoint = convertToSkinCoordinates(point)
        
        // End window dragging
        if isDraggingWindow {
            isDraggingWindow = false
            if let window = window {
                WindowManager.shared.windowDidFinishDragging(window)
            }
        }

        // Handle button releases
        if let pressed = pressedButton {
            switch pressed {
            case .close:
                if hitTestCloseButton(at: skinPoint) {
                    window?.close()
                }
            }

            pressedButton = nil
            needsDisplay = true
        }
    }
    
    // MARK: - Keyboard Events
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if handleVisualizationKeyDown(event) {
            return
        }
        super.keyDown(with: event)
    }

    @discardableResult
    func handleVisualizationKeyDown(_ event: NSEvent) -> Bool {
        // Preset rating overlay shortcuts:
        // - Escape dismisses
        // - Delete/Backspace clears rating
        // - Number keys 1-5 set stars
        if isPresetRatingOverlayVisible {
            switch event.keyCode {
            case 53: // Escape
                hidePresetRatingOverlay()
                return true
            case 51, 117: // Delete/Backspace or Forward Delete
                presetRatingOverlay.setRating(0)
                submitCurrentPresetRating(0)
                return true
            case 18: // 1 key (keycode 18)
                presetRatingOverlay.setRating(2)
                submitCurrentPresetRating(2)
                return true
            case 19: // 2 key (keycode 19)
                presetRatingOverlay.setRating(4)
                submitCurrentPresetRating(4)
                return true
            case 20: // 3 key (keycode 20)
                presetRatingOverlay.setRating(6)
                submitCurrentPresetRating(6)
                return true
            case 21: // 4 key (keycode 21)
                presetRatingOverlay.setRating(8)
                submitCurrentPresetRating(8)
                return true
            case 23: // 5 key (keycode 23, not 22)
                presetRatingOverlay.setRating(10)
                submitCurrentPresetRating(10)
                return true
            default:
                break
            }
        }

        // Check for modifier keys
        let hasShift = event.modifierFlags.contains(.shift)

        // ⌘↓/⌘↑: the standard engine keys (`VisualizationKey`); ⌘→/⌘← fall to the arrows below.
        if case .engine(let delta)? = VisualizationKey(event) {
            switchVisualizationEngine(to: (visualizationGLView?.currentEngineType ?? .projectM).advanced(by: delta))
            return true
        }

        switch event.keyCode {
        case 53: // Escape - exit fullscreen if in fullscreen mode
            if isFullscreen {
                controller?.toggleFullscreen()
                return true
            }
            return false
            
        case 3: // F key - toggle fullscreen
            controller?.toggleFullscreen()
            return true
            
        case 35: // P key - toggle quality mode (30fps/60fps)
            togglePerformanceMode(nil)
            return true
            
        case 124: // Right arrow - next preset/effect
            visualizationGLView?.stepEnginePreset(by: 1, hardCut: hasShift)
            return true

        case 123: // Left arrow - previous preset/effect
            visualizationGLView?.stepEnginePreset(by: -1, hardCut: hasShift)
            return true

        case 15: // R key - random preset/effect
            visualizationGLView?.randomEnginePreset(hardCut: hasShift)
            return true
            
        case 8: // C key - step the auto-cycle mode
            guard let cycler = visualizationGLView?.presetCycler else { return false }
            cycler.mode = cycler.mode.next
            return true

        default:
            return false
        }
    }
    
    // MARK: - Context Menu
    
    override func menu(for event: NSEvent) -> NSMenu? {
        buildVisualizationMenu()
    }

    /// The shared visualization menu (`VisualizationContextMenu`), which this view used to build
    /// its own identical copy of — as did `ModernProjectMView`, and as did the `.wal` skin's
    /// embedded AVS surface, with a shorter one that immediately read as truncated beside it.
    func buildVisualizationMenu() -> NSMenu {
        VisualizationContextMenu.build(target: self, options: .init(showsCast: true))
    }
    
    @objc func reconfigureTripexAction(_ sender: NSMenuItem)    { visualizationGLView?.reconfigureTripex() }
    @objc func toggleTripexAudioInfoAction(_ sender: NSMenuItem){ visualizationGLView?.toggleTripexAudioInfo() }
    @objc func toggleTripexHelpAction(_ sender: NSMenuItem)     { visualizationGLView?.toggleTripexHelp() }
    @objc func setTripexIntensity(_ sender: NSMenuItem) {
        let value = Float(sender.tag) / 100.0
        visualizationGLView?.tripexIntensityScale = value
        UserDefaults.standard.set(value, forKey: TripexEngine.DefaultsKey.intensityScale)
    }

    @objc func setCurrentPresetAsDefault(_ sender: NSMenuItem?) {
        visualizationGLView?.setCurrentPresetAsDefault()
    }

    @objc func setCurrentPresetRatingFromMenu(_ sender: NSMenuItem) {
        guard let preset = currentPresetIdentity() else { return }
        let rating = min(5, max(0, sender.tag))
        presetRatingsStore.setRating(rating, forPresetPath: preset.path, presetName: preset.name)
    }
    
    @objc func toggleCurrentPresetFavorite(_ sender: NSMenuItem?) {
        guard let preset = currentPresetIdentity() else { return }
        let isFavorite = presetRatingsStore.isFavorite(forPresetPath: preset.path)
        presetRatingsStore.setFavorite(!isFavorite, forPresetPath: preset.path, presetName: preset.name)
    }
    
    @objc func selectFavoritePresetFromMenu(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String,
              let index = presetIndex(forPath: path) else { return }
        hidePresetRatingOverlay()
        visualizationGLView?.selectPreset(at: index, hardCut: false)
    }
    
    @objc func toggleFullscreenAction(_ sender: NSMenuItem?) {
        controller?.toggleFullscreen()
    }
    
    @objc func togglePerformanceMode(_ sender: NSMenuItem?) {
        visualizationGLView?.toggleLowPowerMode()
    }
    
    @objc func closeWindow(_ sender: NSMenuItem?) {
        window?.close()
    }

    // MARK: - Geiss Menu Handlers (GeissMenuTarget protocol implementations)

    @objc func toggleBeatDetection(_ sender: NSMenuItem) {
        guard var cfg = visualizationGLView?.getGeissConfig() else { return }
        cfg.beatDetection.toggle()
        visualizationGLView?.setGeissConfig(cfg)
    }

    @objc func toggleSyncColorToSound(_ sender: NSMenuItem) {
        guard var cfg = visualizationGLView?.getGeissConfig() else { return }
        cfg.syncColorToSound.toggle()
        visualizationGLView?.setGeissConfig(cfg)
    }

    @objc func toggleSlideShift(_ sender: NSMenuItem) {
        guard var cfg = visualizationGLView?.getGeissConfig() else { return }
        cfg.slideShift.toggle()
        visualizationGLView?.setGeissConfig(cfg)
    }

    @objc func togglePaletteLock(_ sender: NSMenuItem) {
        guard var cfg = visualizationGLView?.getGeissConfig() else { return }
        cfg.paletteLocked.toggle()
        visualizationGLView?.setGeissConfig(cfg)
    }

    @objc func setSensitivity(_ sender: NSMenuItem) {
        let sensitivity = Float(sender.tag) / 100.0
        guard var cfg = visualizationGLView?.getGeissConfig() else { return }
        cfg.sensitivity = sensitivity
        visualizationGLView?.setGeissConfig(cfg)
    }

    @objc func setGamma(_ sender: NSMenuItem) {
        guard var cfg = visualizationGLView?.getGeissConfig() else { return }
        cfg.gamma = sender.tag
        visualizationGLView?.setGeissConfig(cfg)
    }

    @objc func setVisMode(_ sender: NSMenuItem) {
        guard var cfg = visualizationGLView?.getGeissConfig() else { return }
        cfg.visMode = sender.tag
        visualizationGLView?.setGeissConfig(cfg)
    }

    @objc func randomizePalette(_ sender: NSMenuItem) {
        visualizationGLView?.randomizeGeissPalette()
    }

    @objc func setAudioSensitivity(_ sender: NSMenuItem) {
        let gain = Float(sender.tag) / 10.0
        visualizationGLView?.setPCMGain(gain)
    }
    
    @objc func setBeatSensitivityAction(_ sender: NSMenuItem) {
        let sensitivity = Float(sender.tag) / 10.0
        visualizationGLView?.setNormalBeatSensitivity(sensitivity)
    }
    
    // MARK: - Visualization Engine Switching

    @objc func switchVisualizationEngine(_ sender: NSMenuItem) {
        guard let type = sender.representedObject as? VisualizationType else { return }
        switchVisualizationEngine(to: type)
    }

    private func switchVisualizationEngine(to type: VisualizationType) {
        if type != .projectM {
            hidePresetRatingOverlay()
        }
        visualizationGLView?.switchEngine(to: type)
    }

    func resetVisualizationWindowPreferences() {
        hidePresetRatingOverlay()
        visualizationGLView?.switchEngine(to: .projectM, forceReload: true)
    }

    // MARK: - Layout
    
    override func layout() {
        super.layout()
        updateVisualizationFrame()
    }
}
