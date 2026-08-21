import AppKit

// =============================================================================
// MODERN PROJECTM VIEW - Visualization window with modern skin chrome
// =============================================================================
// Container view that draws modern skin-styled window chrome around the OpenGL-based
// VisualizationGLView. Follows the same pattern as ModernSpectrumView for chrome
// rendering, and ProjectMView for visualization functionality.
//
// Has ZERO dependencies on the classic skin system (Skin/, SkinElements, SkinRenderer, etc.).
// =============================================================================

/// Modern ProjectM visualization view with full modern skin support
class ModernProjectMView: NSView, VisualizationMenuTarget {
    
    // MARK: - Properties
    
    weak var controller: ModernProjectMWindowController?

    /// The skin renderer
    private var renderer: ModernSkinRenderer!

    /// The OpenGL visualization view
    private(set) var visualizationGLView: VisualizationGLView?

    /// Fullscreen mode state (hides window chrome)
    private(set) var isFullscreen = false
    
    /// Button being pressed (for visual feedback)
    private var pressedButton: String?
    
    /// Window dragging state
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    
    /// Observer for PCM data notifications
    private var pcmObserver: NSObjectProtocol?
    
    /// Observer for spectrum data notifications
    private var spectrumObserver: NSObjectProtocol?
    
    /// Observer for playback state changes
    private var playbackStateObserver: NSObjectProtocol?
    
    /// Current preset cycle mode
    private var presetCycleMode: VisualizationCycleMode = .off

    /// Timer for preset cycling
    private var presetCycleTimer: Timer?

    /// Cycle interval in seconds
    private var presetCycleInterval: TimeInterval = 30.0

    /// Tripex cycle state — mirrors ProjectM controls for uniform UX.
    private var tripexCycleMode: VisualizationCycleMode = .cycle
    private var tripexCycleTimer: Timer?
    private var tripexCycleInterval: TimeInterval = 30.0

    /// Store for persisted projectM preset ratings.
    private let presetRatingsStore = ProjectMPresetRatingsStore.shared

    /// Dismiss task for the preset rating overlay.
    private var presetRatingDismissTask: Task<Void, Never>?

    /// Whether the preset rating overlay is currently visible.
    private var isPresetRatingOverlayVisible = false
    
    /// Scale factor for hit testing (computed to track double-size changes)
    private var scale: CGFloat { ModernSkinElements.scaleFactor }
    
    // MARK: - Layout Constants
    
    private var titleBarHeight: CGFloat {
        let hide = WindowManager.shared.effectiveHideTitleBars(for: self.window)
        return hide ? borderWidth : ModernSkinElements.projectMTitleBarHeight
    }
    private var borderWidth: CGFloat { ModernSkinElements.projectMBorderWidth }
    
    /// Which edges are adjacent to another docked window (for seamless border rendering)
    private var adjacentEdges: AdjacentEdges = [] { didSet { updateCornerMask() } }
    private var sharpCorners: CACornerMask = [] { didSet { updateCornerMask() } }
    private var edgeOcclusionSegments: EdgeOcclusionSegments = .empty

    /// Highlight state for drag-mode visual feedback
    private var isHighlighted = false
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        wantsLayer = true
        layer?.isOpaque = false
        
        // Initialize renderer with skin respecting lock setting
        let skin = resolveCurrentSkin()
        renderer = ModernSkinRenderer(skin: skin)
        
        // Set up accessibility
        setupAccessibility()
        
        // Create and add OpenGL visualization view
        setupVisualizationView()

        loadProjectMPresetCycleStateFromDefaults()
        applyProjectMPresetCycleModeIfActive()

        // Restore Tripex cycle state from defaults; applied if Tripex is
        // the active engine at launch (otherwise applied on engine switch).
        loadTripexCycleStateFromDefaults()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self,
                  self.visualizationGLView?.currentEngineType == .tripex else { return }
            self.applyTripexCycleMode()
        }

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
        WindowManager.shared.audioEngine.addSpectrumConsumer("modernProjectMView")

        // Subscribe to playback state changes (for idle/active visualization mode)
        playbackStateObserver = NotificationCenter.default.addObserver(
            forName: .audioPlaybackStateChanged,
            object: nil,
            queue: .main  // UI update, use main thread
        ) { [weak self] notification in
            self?.handlePlaybackStateChange(notification)
        }
        
        // Observe skin changes
        NotificationCenter.default.addObserver(self, selector: #selector(modernSkinDidChange),
                                                name: ModernSkinEngine.skinDidChangeNotification, object: nil)
        
        // Observe double size changes
        NotificationCenter.default.addObserver(self, selector: #selector(doubleSizeChanged),
                                                name: .doubleSizeDidChange, object: nil)
        
        // Observe window layout changes for seamless docked borders
        NotificationCenter.default.addObserver(self, selector: #selector(windowLayoutDidChange),
                                                name: .windowLayoutDidChange, object: nil)

        // Observe connected-window highlight changes for drag-mode visual feedback
        NotificationCenter.default.addObserver(self, selector: #selector(connectedWindowHighlightDidChange(_:)),
                                                name: .connectedWindowHighlightDidChange, object: nil)
        
        // Set initial audio active state
        updateAudioActiveState()
        updateCornerMask()
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
        NotificationCenter.default.removeObserver(self)
        WindowManager.shared.audioEngine.removeSpectrumConsumer("modernProjectMView")
        stopPresetCycleTimer()
        stopTripexCycleTimer()
        visualizationGLView?.stopRendering()
    }
    
    // MARK: - Setup
    
    private func setupAccessibility() {
        setAccessibilityIdentifier("modernVisualizationView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("Visualization")
    }
    
    /// Resolve which skin to use
    private func resolveCurrentSkin() -> ModernSkin {
        return ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
    }
    
    private func setupVisualizationView() {
        let visArea = calculateVisualizationArea()
        
        visualizationGLView = VisualizationGLView(frame: visArea, pixelFormat: nil)
        if let visView = visualizationGLView {
            // Don't use autoresizingMask - we manually update frame in layout()
            visView.autoresizingMask = []
            addSubview(visView)
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
        
        // Content area inside the chrome (standard macOS bottom-left coordinates)
        return NSRect(
            x: borderWidth,
            y: borderWidth,
            width: max(0, bounds.width - borderWidth * 2),
            height: max(0, bounds.height - titleBarHeight - borderWidth)
        )
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
        
        // Draw window background
        renderer.drawWindowBackground(in: bounds, context: context, adjacentEdges: adjacentEdges, sharpCorners: sharpCorners)

        // Draw window border with glow (seamless docking suppresses adjacent edges)
        renderer.drawWindowBorder(in: bounds, context: context, adjacentEdges: adjacentEdges, sharpCorners: sharpCorners, occlusionSegments: edgeOcclusionSegments)
        
        // Draw title bar (unless HT is on)
        if !WindowManager.shared.effectiveHideTitleBars(for: self.window) {
            // Compute title bar and button rects dynamically in base space
            // (window is larger than the 275x116 base, so we can't use fixed element rects)
            let baseWidth = bounds.width / scale
            let baseHeight = bounds.height / scale
            
            let tbh = ModernSkinElements.titleBarBaseHeight
            let titleBarRect = NSRect(x: 0, y: baseHeight - tbh, width: baseWidth, height: tbh)
            let closeBtnRect = NSRect(x: baseWidth - 14, y: baseHeight - tbh / 2 - 5, width: 10, height: 10)
            
            // Draw title bar with projectm prefix (handles per-window titlebar image + title text)
            renderer.drawTitleBar(in: titleBarRect, title: "Visualizations", prefix: "projectm_", context: context)
            
            // Draw close button
            let closeState = (pressedButton == "projectm_btn_close") ? "pressed" : "normal"
            renderer.drawWindowControlButton("projectm_btn_close", state: closeState,
                                             in: closeBtnRect, context: context)
        }

        if isHighlighted {
            NSColor.white.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }
    }
    
    // MARK: - Skin Change
    
    func skinDidChange() {
        let skin = resolveCurrentSkin()
        renderer = ModernSkinRenderer(skin: skin)
        updateCornerMask()
        needsDisplay = true
    }
    
    @objc private func modernSkinDidChange() {
        skinDidChange()
    }
    
    @objc private func doubleSizeChanged() {
        skinDidChange()
    }
    
    @objc private func windowLayoutDidChange() {
        guard let window = window else { return }
        let newEdges = WindowManager.shared.computeAdjacentEdges(for: window)
        let newSharp = WindowManager.shared.computeSharpCorners(for: window)
        let newSegments = WindowManager.shared.computeEdgeOcclusionSegments(for: window)
        let seamless = min(1.0, max(0.0, ModernSkinEngine.shared.currentSkin?.config.window.seamlessDocking ?? 0))
        let shouldHaveShadow = !(seamless > 0 && !newEdges.isEmpty)
        if window.hasShadow != shouldHaveShadow {
            window.hasShadow = shouldHaveShadow
            window.invalidateShadow()
        }
        if newEdges != adjacentEdges || newSharp != sharpCorners || newSegments != edgeOcclusionSegments {
            adjacentEdges = newEdges
            sharpCorners = newSharp
            edgeOcclusionSegments = newSegments
            needsDisplay = true
        }
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
    
    private func hitTestTitleBar(at point: NSPoint) -> Bool {
        return point.y >= bounds.height - titleBarHeight &&
               point.x < bounds.width - 30
    }

    /// Top 1/4 of the window is the drag zone
    private func hitTestTopZone(at point: NSPoint) -> Bool {
        return point.y >= bounds.height * 0.75
    }

    private func hitTestCloseButton(at point: NSPoint) -> Bool {
        let closeRect = NSRect(x: bounds.width - 20, y: bounds.height - titleBarHeight,
                               width: 20, height: titleBarHeight)
        return closeRect.contains(point)
    }
    
    // MARK: - Mouse Events
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Check close button (only when titlebar is visible)
        if !WindowManager.shared.effectiveHideTitleBars(for: self.window) &&
           hitTestCloseButton(at: point) {
            pressedButton = "projectm_btn_close"
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
        if isDraggingWindow, let window = window {
            let currentPoint = event.locationInWindow
            let deltaX = currentPoint.x - windowDragStartPoint.x
            let deltaY = currentPoint.y - windowDragStartPoint.y
            
            var newOrigin = window.frame.origin
            newOrigin.x += deltaX
            newOrigin.y += deltaY
            
            newOrigin = WindowManager.shared.windowWillMove(window, to: newOrigin)
            window.setFrameOrigin(newOrigin)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // End window dragging
        if isDraggingWindow {
            isDraggingWindow = false
            if let window = window {
                WindowManager.shared.windowDidFinishDragging(window)
            }
        }

        // Handle button releases
        if let pressed = pressedButton {
            if pressed == "projectm_btn_close" && hitTestCloseButton(at: point) {
                window?.close()
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
            case 18...22: // 1-5 keys
                let starRating = Int(event.keyCode - 17)
                let ratingOnTenScale = starRating * 2
                presetRatingOverlay.setRating(ratingOnTenScale)
                submitCurrentPresetRating(ratingOnTenScale)
                return true
            default:
                break
            }
        }

        // Check for modifier keys
        let hasShift = event.modifierFlags.contains(.shift)
        
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
            if visualizationGLView?.currentEngineType == .geiss {
                visualizationGLView?.nextGeissEffect()
            } else if visualizationGLView?.currentEngineType == .tripex {
                visualizationGLView?.nextTripexEffect()
            } else if hasShift {
                visualizationGLView?.nextPreset(hardCut: true)
            } else {
                visualizationGLView?.nextPreset(hardCut: false)
            }
            return true

        case 123: // Left arrow - previous preset/effect
            if visualizationGLView?.currentEngineType == .geiss {
                visualizationGLView?.previousGeissEffect()
            } else if visualizationGLView?.currentEngineType == .tripex {
                visualizationGLView?.previousTripexEffect()
            } else if hasShift {
                visualizationGLView?.previousPreset(hardCut: true)
            } else {
                visualizationGLView?.previousPreset(hardCut: false)
            }
            return true

        case 15: // R key - random preset/effect
            if visualizationGLView?.currentEngineType == .geiss {
                visualizationGLView?.randomGeissEffect()
            } else if visualizationGLView?.currentEngineType == .tripex {
                visualizationGLView?.randomTripexEffect()
            } else if hasShift {
                visualizationGLView?.randomPreset(hardCut: true)
            } else {
                visualizationGLView?.randomPreset(hardCut: false)
            }
            return true
            
        case 8: // C key - toggle cycle mode
            guard visualizationGLView?.currentEngineType == .projectM else { return false }
            switch presetCycleMode {
            case .off:
                presetCycleMode = .cycle
                saveProjectMPresetCycleStateToDefaults()
                applyProjectMPresetCycleMode()
                NSLog("ModernProjectMView: Auto-cycle enabled")
            case .cycle:
                presetCycleMode = .random
                saveProjectMPresetCycleStateToDefaults()
                applyProjectMPresetCycleMode()
                NSLog("ModernProjectMView: Auto-random enabled")
            case .random:
                presetCycleMode = .off
                saveProjectMPresetCycleStateToDefaults()
                applyProjectMPresetCycleMode()
                NSLog("ModernProjectMView: Auto-cycle disabled")
            }
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
        VisualizationContextMenu.build(target: self, options: .init(
            cycleMode: presetCycleMode,
            cycleInterval: presetCycleInterval,
            tripexCycleMode: tripexCycleMode,
            tripexCycleInterval: tripexCycleInterval))
    }
    
    // MARK: - Menu Actions
    
    @objc func nextPresetAction(_ sender: NSMenuItem?) {
        hidePresetRatingOverlay()
        visualizationGLView?.nextPreset()
    }
    
    @objc func previousPresetAction(_ sender: NSMenuItem?) {
        hidePresetRatingOverlay()
        visualizationGLView?.previousPreset()
    }
    
    @objc func randomPresetAction(_ sender: NSMenuItem?) {
        hidePresetRatingOverlay()
        visualizationGLView?.randomPreset()
    }

    // MARK: - TripexMenuTarget

    @objc func nextTripexEffectAction(_ sender: NSMenuItem)     { visualizationGLView?.nextTripexEffect() }
    @objc func previousTripexEffectAction(_ sender: NSMenuItem) { visualizationGLView?.previousTripexEffect() }
    @objc func randomTripexEffectAction(_ sender: NSMenuItem)   { visualizationGLView?.randomTripexEffect() }
    @objc func reconfigureTripexAction(_ sender: NSMenuItem)    { visualizationGLView?.reconfigureTripex() }
    @objc func toggleTripexHoldAction(_ sender: NSMenuItem)     { visualizationGLView?.toggleTripexHold() }
    @objc func toggleTripexAudioInfoAction(_ sender: NSMenuItem){ visualizationGLView?.toggleTripexAudioInfo() }
    @objc func toggleTripexHelpAction(_ sender: NSMenuItem)     { visualizationGLView?.toggleTripexHelp() }
    @objc func selectTripexEffectFromMenu(_ sender: NSMenuItem) {
        visualizationGLView?.selectTripexEffect(at: sender.tag)
    }
    @objc func setTripexIntensity(_ sender: NSMenuItem) {
        let value = Float(sender.tag) / 100.0
        visualizationGLView?.tripexIntensityScale = value
        UserDefaults.standard.set(value, forKey: TripexEngine.DefaultsKey.intensityScale)
    }

    @objc func nextGeissEffectAction(_ sender: NSMenuItem?) {
        visualizationGLView?.nextGeissEffect()
    }

    @objc func previousGeissEffectAction(_ sender: NSMenuItem?) {
        visualizationGLView?.previousGeissEffect()
    }

    @objc func randomGeissEffectAction(_ sender: NSMenuItem?) {
        visualizationGLView?.randomGeissEffect()
    }

    @objc func selectGeissEffectFromMenu(_ sender: NSMenuItem) {
        visualizationGLView?.selectGeissEffect(at: sender.tag)
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
    
    @objc func selectPresetFromMenu(_ sender: NSMenuItem) {
        let index = sender.tag
        hidePresetRatingOverlay()
        visualizationGLView?.selectPreset(at: index, hardCut: false)
    }
    
    @objc func toggleFullscreenAction(_ sender: NSMenuItem?) {
        controller?.toggleFullscreen()
    }
    
    @objc func togglePerformanceMode(_ sender: NSMenuItem?) {
        visualizationGLView?.toggleLowPowerMode()
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

    @objc func toggleModeLock(_ sender: NSMenuItem) {
        guard var cfg = visualizationGLView?.getGeissConfig() else { return }
        cfg.modeLocked.toggle()
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

    @objc func setAutoSwitch(_ sender: NSMenuItem) {
        guard var cfg = visualizationGLView?.getGeissConfig() else { return }
        cfg.autoSwitchSeconds = sender.tag
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

    @objc func closeWindow(_ sender: NSMenuItem?) {
        window?.close()
    }
    
    @objc func setAudioSensitivity(_ sender: NSMenuItem) {
        let gain = Float(sender.tag) / 10.0
        visualizationGLView?.setPCMGain(gain)
    }
    
    @objc func setBeatSensitivityAction(_ sender: NSMenuItem) {
        let sensitivity = Float(sender.tag) / 10.0
        visualizationGLView?.setNormalBeatSensitivity(sensitivity)
    }
    
    @objc func switchVisualizationEngine(_ sender: NSMenuItem) {
        guard let type = sender.representedObject as? VisualizationType else { return }
        if type != .projectM {
            hidePresetRatingOverlay()
            presetCycleMode = .off
            stopPresetCycleTimer()
        }
        if type != .tripex {
            stopTripexCycleTimer()
        }
        visualizationGLView?.switchEngine(to: type)
        if type == .tripex {
            loadTripexCycleStateFromDefaults()
            applyTripexCycleMode()
        } else if type == .projectM {
            loadProjectMPresetCycleStateFromDefaults()
            applyProjectMPresetCycleMode()
        }
    }

    func resetVisualizationWindowPreferences() {
        hidePresetRatingOverlay()
        stopPresetCycleTimer()
        stopTripexCycleTimer()
        loadProjectMPresetCycleStateFromDefaults()
        loadTripexCycleStateFromDefaults()
        visualizationGLView?.switchEngine(to: .projectM, forceReload: true)
        applyProjectMPresetCycleMode()
    }

    // MARK: - Tripex cycle controls (uniform with ProjectM)

    private func loadTripexCycleStateFromDefaults() {
        let raw = UserDefaults.standard.string(forKey: TripexEngine.DefaultsKey.cycleMode) ?? "cycle"
        switch raw {
        case "off":    tripexCycleMode = .off
        case "random": tripexCycleMode = .random
        default:       tripexCycleMode = .cycle
        }
        let stored = UserDefaults.standard.double(forKey: TripexEngine.DefaultsKey.cycleInterval)
        tripexCycleInterval = stored > 0 ? stored : 30.0
    }

    private func saveTripexCycleStateToDefaults() {
        let raw: String
        switch tripexCycleMode {
        case .off:    raw = "off"
        case .cycle:  raw = "cycle"
        case .random: raw = "random"
        }
        UserDefaults.standard.set(raw, forKey: TripexEngine.DefaultsKey.cycleMode)
        UserDefaults.standard.set(tripexCycleInterval, forKey: TripexEngine.DefaultsKey.cycleInterval)
    }

    private func applyTripexCycleMode() {
        visualizationGLView?.setTripexHold(true)
        if tripexCycleMode == .off {
            stopTripexCycleTimer()
        } else {
            startTripexCycleTimer()
        }
    }

    private func startTripexCycleTimer() {
        stopTripexCycleTimer()
        tripexCycleTimer = Timer.scheduledTimer(withTimeInterval: tripexCycleInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            switch self.tripexCycleMode {
            case .cycle:  self.visualizationGLView?.nextTripexEffect()
            case .random: self.visualizationGLView?.randomTripexEffect()
            case .off:    break
            }
        }
    }

    private func stopTripexCycleTimer() {
        tripexCycleTimer?.invalidate()
        tripexCycleTimer = nil
    }

    @objc func setTripexCycleModeCycle(_ sender: Any?) {
        if (sender as? NSMenuItem)?.state == .on {
            tripexCycleMode = .off
        } else {
            tripexCycleMode = .cycle
        }
        saveTripexCycleStateToDefaults()
        applyTripexCycleMode()
    }

    @objc func setTripexCycleModeRandom(_ sender: Any?) {
        if (sender as? NSMenuItem)?.state == .on {
            tripexCycleMode = .off
        } else {
            tripexCycleMode = .random
        }
        saveTripexCycleStateToDefaults()
        applyTripexCycleMode()
    }

    @objc func setTripexCycleIntervalFromMenu(_ sender: NSMenuItem) {
        tripexCycleInterval = TimeInterval(sender.tag)
        saveTripexCycleStateToDefaults()
        if tripexCycleMode != .off { startTripexCycleTimer() }
    }
    
    // MARK: - Preset Cycle Mode

    private func loadProjectMPresetCycleStateFromDefaults() {
        presetCycleMode = ProjectMPresetCycleSettings.loadMode()
        presetCycleInterval = ProjectMPresetCycleSettings.loadInterval()
    }

    private func saveProjectMPresetCycleStateToDefaults() {
        ProjectMPresetCycleSettings.save(mode: presetCycleMode, interval: presetCycleInterval)
    }

    private func applyProjectMPresetCycleModeIfActive() {
        guard visualizationGLView?.currentEngineType == .projectM else {
            stopPresetCycleTimer()
            return
        }
        applyProjectMPresetCycleMode()
    }

    private func applyProjectMPresetCycleMode() {
        if presetCycleMode == .off {
            stopPresetCycleTimer()
        } else {
            startPresetCycleTimer()
        }
    }
    
    @objc func setCycleModeOff(_ sender: NSMenuItem?) {
        presetCycleMode = .off
        saveProjectMPresetCycleStateToDefaults()
        applyProjectMPresetCycleMode()
    }
    
    @objc func setCycleModeCycle(_ sender: NSMenuItem?) {
        presetCycleMode = .cycle
        saveProjectMPresetCycleStateToDefaults()
        applyProjectMPresetCycleMode()
    }
    
    @objc func setCycleModeRandom(_ sender: NSMenuItem?) {
        presetCycleMode = .random
        saveProjectMPresetCycleStateToDefaults()
        applyProjectMPresetCycleMode()
    }
    
    @objc func setCycleInterval(_ sender: NSMenuItem) {
        presetCycleInterval = TimeInterval(sender.tag)
        saveProjectMPresetCycleStateToDefaults()
        applyProjectMPresetCycleMode()
    }
    
    private func startPresetCycleTimer() {
        stopPresetCycleTimer()
        presetCycleTimer = Timer.scheduledTimer(withTimeInterval: presetCycleInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            switch self.presetCycleMode {
            case .cycle:
                self.visualizationGLView?.nextPreset(hardCut: false)
            case .random:
                self.visualizationGLView?.randomPreset(hardCut: false)
            case .off:
                break
            }
        }
    }
    
    private func stopPresetCycleTimer() {
        presetCycleTimer?.invalidate()
        presetCycleTimer = nil
    }
    
    // MARK: - Layout
    
    override func layout() {
        super.layout()
        updateVisualizationFrame()
        updateCornerMask()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.isOpaque = false
        updateCornerMask()
    }

    private func updateCornerMask() {
        guard let layer = self.layer else { return }
        let cornerRadius = (ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()).config.window.cornerRadius ?? 0
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = cornerRadius > 0
        guard cornerRadius > 0 else { return }
        let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                         .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer.maskedCorners = allCorners.subtracting(sharpCorners)
    }
}
