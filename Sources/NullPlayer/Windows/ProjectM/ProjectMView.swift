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
class ProjectMView: NSView, GeissMenuTarget, TripexMenuTarget, MetMuseumMenuTarget {
    
    // MARK: - Properties
    
    weak var controller: ProjectMWindowController?
    
    /// The OpenGL visualization view
    private(set) var visualizationGLView: VisualizationGLView?
    
    /// Shade mode state
    private(set) var isShadeMode = false

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
    
    /// Preset cycling mode
    enum PresetCycleMode {
        case off       // Manual only
        case cycle     // Sequential cycling
        case random    // Random on timer
    }
    
    /// Current preset cycle mode
    private var presetCycleMode: PresetCycleMode = .off

    /// Timer for preset cycling
    private var presetCycleTimer: Timer?

    /// Cycle interval in seconds
    private var presetCycleInterval: TimeInterval = 30.0

    /// Tripex cycle state — mirrors the ProjectM cycle controls for a
    /// uniform UX across visualization engines.
    private var tripexCycleMode: PresetCycleMode = .cycle
    private var tripexCycleTimer: Timer?
    private var tripexCycleInterval: TimeInterval = 30.0

    /// Store for persisted projectM preset ratings.
    private let presetRatingsStore = ProjectMPresetRatingsStore.shared

    /// Dismiss task for the preset rating overlay.
    private var presetRatingDismissTask: Task<Void, Never>?

    /// Whether the preset rating overlay is currently visible.
    private var isPresetRatingOverlayVisible = false
    
    // MARK: - Layout Constants
    // Reference to SkinElements.ProjectM.Layout for consistency
    
    private var Layout: SkinElements.ProjectM.Layout.Type {
        SkinElements.ProjectM.Layout.self
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

        // Restore Tripex cycle state from defaults; applied if/when Tripex
        // becomes the active engine (handled in switchVisualizationEngine,
        // and below for the case where Tripex is the engine at launch).
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
        stopPresetCycleTimer()
        stopTripexCycleTimer()
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
        if WindowManager.shared.hideTitleBars && !isShadeMode {
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
        if WindowManager.shared.hideTitleBars && !isShadeMode {
            context.translateBy(x: 0, y: -Layout.titleBarHeight)
        }
        
        // Draw window chrome at actual window bounds (no scaling - chrome tiles to fill)
        renderer.drawProjectMWindow(in: context, bounds: bounds, isActive: isActive,
                                    pressedButton: pressedButton, isShadeMode: isShadeMode)
        
        context.restoreGState()

        if isHighlighted {
            NSColor.white.withAlphaComponent(0.15).setFill()
            bounds.fill()
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
        guard !isShadeMode else { return }

        guard let userInfo = notification.userInfo,
              let pcm = userInfo["pcm"] as? [Float] else { return }

        // Forward PCM data directly to visualization view (thread-safe via dataLock)
        // No main thread dispatch needed - updatePCM handles thread safety internally
        visualizationGLView?.updatePCM(pcm)
    }

    /// Handle spectrum data notification from audio engine (called on audio thread for low latency)
    private func handleSpectrumUpdate(_ notification: Notification) {
        guard !isShadeMode else { return }

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
    
    /// Set shade mode externally (e.g., from controller)
    func setShadeMode(_ enabled: Bool) {
        isShadeMode = enabled
        if enabled || isPresetRatingOverlayVisible {
            hidePresetRatingOverlay()
        }
        
        // Show/hide visualization view
        visualizationGLView?.isHidden = enabled
        
        // Stop/start rendering based on mode
        if enabled {
            visualizationGLView?.stopRendering()
        } else {
            visualizationGLView?.startRendering()
            updateVisualizationFrame()
        }
        
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
    
    /// Toggle shade mode
    private func toggleShadeMode() {
        isShadeMode.toggle()
        controller?.setShadeMode(isShadeMode)
    }
    
    /// Stop rendering (for window close/hide)
    func stopRendering() {
        visualizationGLView?.stopRendering()
    }
    
    /// Start rendering
    func startRendering() {
        if !isShadeMode {
            visualizationGLView?.startRendering()
        }
    }

    func resumeRenderingAfterWindowTransition() {
        if !isShadeMode {
            visualizationGLView?.resumeRenderingAfterWindowTransition()
        }
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
               skinPoint.x < bounds.width - 25  // Leave room for close button area
    }
    
    /// Check if point hits close button
    private func hitTestCloseButton(at skinPoint: NSPoint) -> Bool {
        if WindowManager.shared.hideTitleBars { return false }
        // Close button is in the right corner of the title bar
        // The titlebar image is scaled to fit window width, so use a generous hit area
        // in the top-right corner (entire title bar height, last 25px of width)
        let titleHeight = Layout.titleBarHeight
        let closeRect = NSRect(x: bounds.width - 25, y: 0, width: 25, height: titleHeight)
        return closeRect.contains(skinPoint)
    }
    
    /// Check if point hits shade button (not currently visible in this design)
    private func hitTestShadeButton(at skinPoint: NSPoint) -> Bool {
        // Shade button not used in this design - double-click title bar instead
        return false
    }
    
    /// Hit test for shade mode close button (uses same title bar)
    private func hitTestShadeCloseButton(at skinPoint: NSPoint) -> Bool {
        // Same as normal mode since shade uses same title bar
        return hitTestCloseButton(at: skinPoint)
    }
    
    private func hitTestShadeShadeButton(at skinPoint: NSPoint) -> Bool {
        // Shade button not used - double-click to toggle
        return false
    }
    
    // MARK: - Mouse Events
    
    /// Allow clicking even when window is not active
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let skinPoint = convertToSkinCoordinates(point)
        
        // Check for double-click in top zone to toggle shade mode
        if event.clickCount == 2 && hitTestTopZone(at: point) &&
           !WindowManager.shared.effectiveHideTitleBars(for: self.window) {
            toggleShadeMode()
            return
        }

        if isShadeMode {
            handleShadeMouseDown(at: skinPoint, event: event)
            return
        }

        // Check window control buttons
        if hitTestCloseButton(at: skinPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }

        if hitTestShadeButton(at: skinPoint) {
            pressedButton = .shade
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
    
    /// Handle mouse down in shade mode
    private func handleShadeMouseDown(at skinPoint: NSPoint, event: NSEvent) {
        // Check window control buttons
        if hitTestShadeCloseButton(at: skinPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        if hitTestShadeShadeButton(at: skinPoint) {
            pressedButton = .shade
            needsDisplay = true
            return
        }
        
        // Start window drag (shade mode is all title bar, so can undock)
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
        if let window = window {
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
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
        
        if isShadeMode {
            handleShadeMouseUp(at: skinPoint)
            return
        }
        
        // Handle button releases
        if let pressed = pressedButton {
            switch pressed {
            case .close:
                if hitTestCloseButton(at: skinPoint) {
                    window?.close()
                }
            case .shade:
                if hitTestShadeButton(at: skinPoint) {
                    toggleShadeMode()
                }
            }
            
            pressedButton = nil
            needsDisplay = true
        }
    }
    
    /// Handle mouse up in shade mode
    private func handleShadeMouseUp(at skinPoint: NSPoint) {
        if let pressed = pressedButton {
            switch pressed {
            case .close:
                if hitTestShadeCloseButton(at: skinPoint) {
                    window?.close()
                }
            case .shade:
                if hitTestShadeShadeButton(at: skinPoint) {
                    toggleShadeMode()
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
            } else if visualizationGLView?.currentEngineType == .metMuseum {
                visualizationGLView?.nextMetMuseumArtwork()
            } else if hasShift {
                // Hard cut (instant switch)
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
            } else if visualizationGLView?.currentEngineType == .metMuseum {
                // Met Museum is random-only; left arrow advances like right.
                visualizationGLView?.nextMetMuseumArtwork()
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
            } else if visualizationGLView?.currentEngineType == .metMuseum {
                visualizationGLView?.nextMetMuseumArtwork()
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
                startPresetCycleTimer()
                NSLog("ProjectMView: Auto-cycle enabled")
            case .cycle:
                presetCycleMode = .random
                startPresetCycleTimer()
                NSLog("ProjectMView: Auto-random enabled")
            case .random:
                presetCycleMode = .off
                stopPresetCycleTimer()
                NSLog("ProjectMView: Auto-cycle disabled")
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

    func buildVisualizationMenu() -> NSMenu {
        let menu = NSMenu()
        
        let currentEngineType = visualizationGLView?.currentEngineType ?? .projectM
        let isProjectMAvailable = visualizationGLView?.isProjectMAvailable ?? false
        let isProjectMActive = currentEngineType == .projectM && isProjectMAvailable
        let isGeissActive = currentEngineType == .geiss
        let isTripexActive = currentEngineType == .tripex
        let isMetMuseumActive = currentEngineType == .metMuseum
        
        // Preset navigation (only when projectM is available)
        if isProjectMActive {
            let presetName = visualizationGLView?.currentPresetName ?? "Unknown"
            let currentPresetIndex = visualizationGLView?.currentPresetIndex ?? 0
            let presetIndex = currentPresetIndex + 1
            let presetCount = visualizationGLView?.presetCount ?? 0
            let currentPresetPath = visualizationGLView?.presetPath(at: currentPresetIndex) ?? ""
            let currentRating = presetRatingsStore.rating(forPresetPath: currentPresetPath)

            let currentPresetItem = NSMenuItem(
                title: "Preset: \(presetName) [\(starString(for: currentRating))] (\(presetIndex)/\(presetCount))",
                action: nil,
                keyEquivalent: ""
            )
            currentPresetItem.isEnabled = false
            menu.addItem(currentPresetItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let nextPresetItem = NSMenuItem(title: "Next Preset", action: #selector(nextPresetAction(_:)), keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!))
            nextPresetItem.target = self
            menu.addItem(nextPresetItem)
            
            let prevPresetItem = NSMenuItem(title: "Previous Preset", action: #selector(previousPresetAction(_:)), keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
            prevPresetItem.target = self
            menu.addItem(prevPresetItem)
            
            let randomPresetItem = NSMenuItem(title: "Random Preset", action: #selector(randomPresetAction(_:)), keyEquivalent: "r")
            randomPresetItem.target = self
            menu.addItem(randomPresetItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let setDefaultItem = NSMenuItem(title: "Set Current to Default", action: #selector(setCurrentPresetAsDefault(_:)), keyEquivalent: "")
            setDefaultItem.target = self
            setDefaultItem.isEnabled = presetCount > 0
            menu.addItem(setDefaultItem)

            let rateCurrentMenu = NSMenu()
            for rating in 0...5 {
                let title = rating == 0
                    ? "Clear Rating (\(starString(for: 0)))"
                    : "\(rating) Gold (\(starString(for: rating)))"
                let item = NSMenuItem(title: title, action: #selector(setCurrentPresetRatingFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.tag = rating
                item.state = currentRating == rating ? .on : .off
                rateCurrentMenu.addItem(item)
            }
            let rateCurrentMenuItem = NSMenuItem(title: "Rate Current Preset", action: nil, keyEquivalent: "")
            rateCurrentMenuItem.submenu = rateCurrentMenu
            menu.addItem(rateCurrentMenuItem)

            let favoritesMenu = NSMenu()
            let isCurrentPresetFavorite = presetRatingsStore.isFavorite(forPresetPath: currentPresetPath)
            let toggleFavoriteTitle = isCurrentPresetFavorite
                ? "Remove Current Preset from Favorites"
                : "Add Current Preset to Favorites"
            let toggleFavoriteItem = NSMenuItem(
                title: toggleFavoriteTitle,
                action: #selector(toggleCurrentPresetFavorite(_:)),
                keyEquivalent: ""
            )
            toggleFavoriteItem.target = self
            toggleFavoriteItem.isEnabled = presetCount > 0
            favoritesMenu.addItem(toggleFavoriteItem)

            let presetPaths = (0..<presetCount).map { visualizationGLView?.presetPath(at: $0) ?? "" }
            let ratingsByPath = presetRatingsStore.ratings(forPresetPaths: presetPaths)
            let favoritePaths = presetRatingsStore.favoritePresetPaths(forPresetPaths: presetPaths)

            if !favoritePaths.isEmpty {
                favoritesMenu.addItem(NSMenuItem.separator())
                for i in 0..<presetCount {
                    let name = visualizationGLView?.presetName(at: i) ?? "Preset \(i + 1)"
                    let path = (presetPaths[i] as NSString).standardizingPath
                    guard favoritePaths.contains(path) else { continue }
                    let rating = ratingsByPath[path] ?? 0
                    let title = "\(name) [\(starString(for: rating))]"
                    let item = NSMenuItem(title: title, action: #selector(selectFavoritePresetFromMenu(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = path
                    item.state = (i == currentPresetIndex) ? .on : .off
                    favoritesMenu.addItem(item)
                }
            }

            let favoritesMenuItem = NSMenuItem(title: "Favorites", action: nil, keyEquivalent: "")
            favoritesMenuItem.submenu = favoritesMenu
            menu.addItem(favoritesMenuItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // Cycle mode options
            let cycleOffItem = NSMenuItem(title: "Manual Only", action: #selector(setCycleModeOff(_:)), keyEquivalent: "")
            cycleOffItem.target = self
            cycleOffItem.state = presetCycleMode == .off ? .on : .off
            menu.addItem(cycleOffItem)
            
            let cycleSeqItem = NSMenuItem(title: "Auto-Cycle", action: #selector(setCycleModeCycle(_:)), keyEquivalent: "c")
            cycleSeqItem.target = self
            cycleSeqItem.state = presetCycleMode == .cycle ? .on : .off
            menu.addItem(cycleSeqItem)
            
            let cycleRandItem = NSMenuItem(title: "Auto-Random", action: #selector(setCycleModeRandom(_:)), keyEquivalent: "")
            cycleRandItem.target = self
            cycleRandItem.state = presetCycleMode == .random ? .on : .off
            menu.addItem(cycleRandItem)
            
            // Cycle interval submenu
            let intervalMenu = NSMenu()
            for (name, seconds) in [("5 seconds", 5.0), ("10 seconds", 10.0), ("20 seconds", 20.0), ("30 seconds", 30.0), ("60 seconds", 60.0), ("2 minutes", 120.0)] {
                let item = NSMenuItem(title: name, action: #selector(setCycleInterval(_:)), keyEquivalent: "")
                item.target = self
                item.tag = Int(seconds)
                item.state = abs(presetCycleInterval - seconds) < 0.5 ? .on : .off
                intervalMenu.addItem(item)
            }
            let intervalMenuItem = NSMenuItem(title: "Cycle Interval", action: nil, keyEquivalent: "")
            intervalMenuItem.submenu = intervalMenu
            menu.addItem(intervalMenuItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // Presets submenu - list all available presets
            if presetCount > 0 {
                let presetsMenu = NSMenu()

                for i in 0..<presetCount {
                    let name = visualizationGLView?.presetName(at: i) ?? "Preset \(i + 1)"
                    let path = presetPaths[i]
                    let rating = ratingsByPath[path] ?? 0
                    let title = "\(name) [\(starString(for: rating))]"
                    let presetItem = NSMenuItem(title: title, action: #selector(selectPresetFromMenu(_:)), keyEquivalent: "")
                    presetItem.target = self
                    presetItem.tag = i
                    presetItem.state = (i == (visualizationGLView?.currentPresetIndex ?? -1)) ? .on : .off
                    presetsMenu.addItem(presetItem)
                }
                
                let presetsMenuItem = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
                presetsMenuItem.submenu = presetsMenu
                menu.addItem(presetsMenuItem)
                
                menu.addItem(NSMenuItem.separator())
            }
        } else if isGeissActive {
            addGeissEffectsMenuItems(to: menu)
        } else if isTripexActive {
            addTripexEffectsMenuItems(to: menu)
        } else if isMetMuseumActive {
            addMetMuseumEffectsMenuItems(to: menu)
        }

        // Visualization Engine selector
        let engineMenu = NSMenu()

        for engineType in VisualizationType.allCases {
            let item = NSMenuItem(
                title: engineType.displayName,
                action: #selector(switchVisualizationEngine(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = engineType
            item.state = (currentEngineType == engineType) ? .on : .off
            engineMenu.addItem(item)
        }

        let engineMenuItem = NSMenuItem(title: "Visualization Engine", action: nil, keyEquivalent: "")
        engineMenuItem.submenu = engineMenu
        menu.addItem(engineMenuItem)

        menu.addItem(NSMenuItem.separator())
        
        // Audio Sensitivity submenu (PCM gain multiplier)
        let audioSensMenu = NSMenu()
        let currentPCMGain = visualizationGLView?.pcmGain ?? 1.0
        for (name, value) in [("Low (0.5x)", 5), ("Normal (1.0x)", 10), ("High (1.5x)", 15), ("Intense (2.0x)", 20), ("Max (3.0x)", 30)] {
            let item = NSMenuItem(title: name, action: #selector(setAudioSensitivity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value
            item.state = abs(currentPCMGain - Float(value) / 10.0) < 0.05 ? .on : .off
            audioSensMenu.addItem(item)
        }
        let audioSensMenuItem = NSMenuItem(title: "Audio Sensitivity", action: nil, keyEquivalent: "")
        audioSensMenuItem.submenu = audioSensMenu
        menu.addItem(audioSensMenuItem)
        
        // Beat Sensitivity submenu (projectM beat detection threshold) - only for ProjectM
        if isProjectMActive {
            let beatSensMenu = NSMenu()
            let currentBeatSens = visualizationGLView?.normalBeatSensitivity ?? 1.0
            for (name, value) in [("Low (0.5)", 5), ("Normal (1.0)", 10), ("High (1.5)", 15), ("Max (2.0)", 20)] {
                let item = NSMenuItem(title: name, action: #selector(setBeatSensitivityAction(_:)), keyEquivalent: "")
                item.target = self
                item.tag = value
                item.state = abs(currentBeatSens - Float(value) / 10.0) < 0.05 ? .on : .off
                beatSensMenu.addItem(item)
            }
            let beatSensMenuItem = NSMenuItem(title: "Beat Sensitivity", action: nil, keyEquivalent: "")
            beatSensMenuItem.submenu = beatSensMenu
            menu.addItem(beatSensMenuItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Performance mode toggle
        let isLowPower = visualizationGLView?.isLowPowerMode ?? true
        let perfModeItem = NSMenuItem(
            title: isLowPower ? "Quality: Optimized (30fps)" : "Quality: Full (60fps)",
            action: #selector(togglePerformanceMode(_:)),
            keyEquivalent: "p"
        )
        perfModeItem.target = self
        menu.addItem(perfModeItem)

        // Fullscreen option
        let fullscreenItem = NSMenuItem(title: "Fullscreen", action: #selector(toggleFullscreenAction(_:)), keyEquivalent: "f")
        fullscreenItem.target = self
        menu.addItem(fullscreenItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Close
        let closeItem = NSMenuItem(title: "Close", action: #selector(closeWindow(_:)), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        
        return menu
    }
    
    @objc private func nextPresetAction(_ sender: Any?) {
        hidePresetRatingOverlay()
        visualizationGLView?.nextPreset()
    }
    
    @objc private func previousPresetAction(_ sender: Any?) {
        hidePresetRatingOverlay()
        visualizationGLView?.previousPreset()
    }
    
    @objc private func randomPresetAction(_ sender: Any?) {
        hidePresetRatingOverlay()
        visualizationGLView?.randomPreset()
    }

    private func addGeissEffectsMenuItems(to menu: NSMenu) {
        let currentEffectName = visualizationGLView?.currentGeissEffectName ?? "Mode 0"
        let effectCount = visualizationGLView?.geissEffectCount ?? 0
        let currentEffectItem = NSMenuItem(
            title: "Effect: \(currentEffectName)",
            action: nil,
            keyEquivalent: ""
        )
        currentEffectItem.isEnabled = false
        menu.addItem(currentEffectItem)
        menu.addItem(NSMenuItem.separator())

        let nextEffectItem = NSMenuItem(title: "Next Effect", action: #selector(nextGeissEffectAction(_:)), keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!))
        nextEffectItem.target = self
        menu.addItem(nextEffectItem)

        let prevEffectItem = NSMenuItem(title: "Previous Effect", action: #selector(previousGeissEffectAction(_:)), keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        prevEffectItem.target = self
        menu.addItem(prevEffectItem)

        let randomEffectItem = NSMenuItem(title: "Random Effect", action: #selector(randomGeissEffectAction(_:)), keyEquivalent: "r")
        randomEffectItem.target = self
        menu.addItem(randomEffectItem)

        if effectCount > 0 {
            menu.addItem(NSMenuItem.separator())
            let effectsMenu = NSMenu()
            for index in 0..<effectCount {
                let name = visualizationGLView?.geissEffectName(at: index) ?? "Mode \(index + 1)"
                let item = NSMenuItem(title: name, action: #selector(selectGeissEffectFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.state = name == currentEffectName ? .on : .off
                effectsMenu.addItem(item)
            }
            let effectsMenuItem = NSMenuItem(title: "Effects", action: nil, keyEquivalent: "")
            effectsMenuItem.submenu = effectsMenu
            menu.addItem(effectsMenuItem)
        }

        if let glView = visualizationGLView {
            GeissMenuBuilder.addGeissConfigMenuItems(to: menu, target: self, visualizationView: glView)
        }
    }

    private func addTripexEffectsMenuItems(to menu: NSMenu) {
        guard let glView = visualizationGLView else { return }
        let mode: TripexCycleMode
        switch tripexCycleMode {
        case .off:    mode = .off
        case .cycle:  mode = .cycle
        case .random: mode = .random
        }
        TripexMenuBuilder.addTripexConfigMenuItems(to: menu,
                                                   target: self,
                                                   visualizationView: glView,
                                                   cycleMode: mode,
                                                   cycleInterval: tripexCycleInterval)
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

    private func addMetMuseumEffectsMenuItems(to menu: NSMenu) {
        guard let glView = visualizationGLView else { return }
        MetMuseumMenuBuilder.addMetMuseumEffectsMenuItems(to: menu,
                                                          target: self,
                                                          visualizationView: glView)
    }

    // MARK: - MetMuseumMenuTarget

    @objc func selectMetMuseumDepartment(_ sender: NSMenuItem) {
        let deptID = sender.tag
        let value: Int? = (deptID == -1) ? nil : deptID
        if let v = value {
            UserDefaults.standard.set(v, forKey: MetMuseumEngine.DefaultsKey.departmentID)
        } else {
            UserDefaults.standard.removeObject(forKey: MetMuseumEngine.DefaultsKey.departmentID)
        }
        if let engine = visualizationGLView?.currentEngine as? MetMuseumEngine {
            var config = engine.getConfig()
            config.departmentID = value
            engine.setConfig(config)
        }
    }

    @objc func setMetMuseumInterval(_ sender: NSMenuItem) {
        let seconds = Double(sender.tag)
        UserDefaults.standard.set(seconds, forKey: MetMuseumEngine.DefaultsKey.intervalSeconds)
        if let engine = visualizationGLView?.currentEngine as? MetMuseumEngine {
            var config = engine.getConfig()
            config.intervalSeconds = seconds
            engine.setConfig(config)
        }
    }

    @objc func setMetMuseumTransitionMode(_ sender: NSMenuItem) {
        guard let modeStr = sender.representedObject as? String,
              let mode = MetMuseumEngine.TransitionMode(rawValue: modeStr) else { return }
        UserDefaults.standard.set(modeStr, forKey: MetMuseumEngine.DefaultsKey.transitionMode)
        if let engine = visualizationGLView?.currentEngine as? MetMuseumEngine {
            var config = engine.getConfig()
            config.transitionMode = mode
            engine.setConfig(config)
        }
    }

    @objc func setMetMuseumTransitionDuration(_ sender: NSMenuItem) {
        let seconds = Double(sender.tag) / 100.0
        UserDefaults.standard.set(seconds, forKey: MetMuseumEngine.DefaultsKey.transitionDuration)
        if let engine = visualizationGLView?.currentEngine as? MetMuseumEngine {
            var config = engine.getConfig()
            config.transitionDurationSeconds = seconds
            engine.setConfig(config)
        }
    }

    @objc func setMetMuseumAspectMode(_ sender: NSMenuItem) {
        guard let aspectStr = sender.representedObject as? String,
              let aspect = MetMuseumEngine.AspectMode(rawValue: aspectStr) else { return }
        UserDefaults.standard.set(aspectStr, forKey: MetMuseumEngine.DefaultsKey.aspectMode)
        if let engine = visualizationGLView?.currentEngine as? MetMuseumEngine {
            var config = engine.getConfig()
            config.aspectMode = aspect
            engine.setConfig(config)
        }
    }

    @objc func toggleMetMuseumAudioReactive(_ sender: NSMenuItem) {
        if let engine = visualizationGLView?.currentEngine as? MetMuseumEngine {
            var config = engine.getConfig()
            config.audioReactiveEffects = !config.audioReactiveEffects
            UserDefaults.standard.set(config.audioReactiveEffects, forKey: MetMuseumEngine.DefaultsKey.audioReactive)
            engine.setConfig(config)
        }
    }

    @objc func toggleMetMuseumBeatTriggered(_ sender: NSMenuItem) {
        if let engine = visualizationGLView?.currentEngine as? MetMuseumEngine {
            var config = engine.getConfig()
            config.beatTriggeredChanges = !config.beatTriggeredChanges
            UserDefaults.standard.set(config.beatTriggeredChanges, forKey: MetMuseumEngine.DefaultsKey.beatTriggered)
            engine.setConfig(config)
        }
    }

    @objc func toggleMetMuseumShowAttribution(_ sender: NSMenuItem) {
        if let engine = visualizationGLView?.currentEngine as? MetMuseumEngine {
            var config = engine.getConfig()
            config.showAttribution = !config.showAttribution
            UserDefaults.standard.set(config.showAttribution, forKey: MetMuseumEngine.DefaultsKey.showAttribution)
            engine.setConfig(config)
        }
    }

    @objc func clearMetMuseumCache(_ sender: NSMenuItem) {
        if let engine = visualizationGLView?.currentEngine as? MetMuseumEngine {
            engine.clearCache()
        }
    }

    @objc private func nextGeissEffectAction(_ sender: Any?) {
        visualizationGLView?.nextGeissEffect()
    }

    @objc private func previousGeissEffectAction(_ sender: Any?) {
        visualizationGLView?.previousGeissEffect()
    }

    @objc private func randomGeissEffectAction(_ sender: Any?) {
        visualizationGLView?.randomGeissEffect()
    }

    @objc private func selectGeissEffectFromMenu(_ sender: NSMenuItem) {
        visualizationGLView?.selectGeissEffect(at: sender.tag)
    }
    
    @objc private func setCurrentPresetAsDefault(_ sender: Any?) {
        visualizationGLView?.setCurrentPresetAsDefault()
    }

    @objc private func setCurrentPresetRatingFromMenu(_ sender: NSMenuItem) {
        guard let preset = currentPresetIdentity() else { return }
        let rating = min(5, max(0, sender.tag))
        presetRatingsStore.setRating(rating, forPresetPath: preset.path, presetName: preset.name)
    }
    
    @objc private func toggleCurrentPresetFavorite(_ sender: Any?) {
        guard let preset = currentPresetIdentity() else { return }
        let isFavorite = presetRatingsStore.isFavorite(forPresetPath: preset.path)
        presetRatingsStore.setFavorite(!isFavorite, forPresetPath: preset.path, presetName: preset.name)
    }
    
    @objc private func selectFavoritePresetFromMenu(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String,
              let index = presetIndex(forPath: path) else { return }
        hidePresetRatingOverlay()
        visualizationGLView?.selectPreset(at: index, hardCut: false)
    }
    
    @objc private func selectPresetFromMenu(_ sender: NSMenuItem) {
        let index = sender.tag
        hidePresetRatingOverlay()
        visualizationGLView?.selectPreset(at: index, hardCut: false)
    }
    
    @objc private func toggleFullscreenAction(_ sender: Any?) {
        controller?.toggleFullscreen()
    }
    
    @objc private func togglePerformanceMode(_ sender: Any?) {
        visualizationGLView?.toggleLowPowerMode()
    }
    
    @objc private func closeWindow(_ sender: Any?) {
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

    @objc private func setAudioSensitivity(_ sender: NSMenuItem) {
        let gain = Float(sender.tag) / 10.0
        visualizationGLView?.setPCMGain(gain)
    }
    
    @objc private func setBeatSensitivityAction(_ sender: NSMenuItem) {
        let sensitivity = Float(sender.tag) / 10.0
        visualizationGLView?.setNormalBeatSensitivity(sensitivity)
    }
    
    // MARK: - Preset Cycle Mode
    
    @objc private func setCycleModeOff(_ sender: Any?) {
        presetCycleMode = .off
        stopPresetCycleTimer()
    }
    
    @objc private func setCycleModeCycle(_ sender: Any?) {
        presetCycleMode = .cycle
        startPresetCycleTimer()
    }
    
    @objc private func setCycleModeRandom(_ sender: Any?) {
        presetCycleMode = .random
        startPresetCycleTimer()
    }
    
    @objc private func setCycleInterval(_ sender: NSMenuItem) {
        presetCycleInterval = TimeInterval(sender.tag)
        if presetCycleMode != .off {
            startPresetCycleTimer()  // Restart with new interval
        }
    }

    // MARK: - Visualization Engine Switching

    @objc private func switchVisualizationEngine(_ sender: NSMenuItem) {
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
        }
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

    /// Applies the current cycle mode to Tripex: Hold ON suppresses
    /// upstream's internal cycle so the Swift timer is the sole driver.
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
    }
}
