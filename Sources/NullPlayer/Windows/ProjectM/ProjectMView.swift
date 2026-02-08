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
class ProjectMView: NSView {
    
    // MARK: - Properties
    
    weak var controller: ProjectMWindowController?
    
    /// The OpenGL visualization view
    private(set) var visualizationGLView: VisualizationGLView?
    
    /// Shade mode state
    private(set) var isShadeMode = false
    
    /// Fullscreen mode state (hides window chrome)
    private(set) var isFullscreen = false
    
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
        if let observer = pcmObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = spectrumObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = playbackStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        stopPresetCycleTimer()
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
        
        // Use default skin if locked, otherwise use current skin
        let skin: Skin
        if WindowManager.shared.lockBrowserProjectMSkin {
            skin = SkinLoader.shared.loadDefault()
        } else {
            skin = WindowManager.shared.currentSkin ?? SkinLoader.shared.loadDefault()
        }
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
    
    // MARK: - Hit Testing
    
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
        
        // Check for double-click on title bar to toggle shade mode
        if event.clickCount == 2 && hitTestTitleBar(at: skinPoint) {
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
        
        // Title bar - start window drag (can undock)
        if hitTestTitleBar(at: skinPoint) {
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
            if let window = window {
                WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
            }
            return
        }
        
        // Content area - window dragging (removed click-to-advance preset to prevent crashes from rapid clicking)
        // Use arrow keys, context menu, or auto-cycle to change presets instead
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
        if let window = window {
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: WindowManager.shared.hideTitleBars)
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
        // Check for modifier keys
        let hasShift = event.modifierFlags.contains(.shift)
        
        switch event.keyCode {
        case 53: // Escape - exit fullscreen if in fullscreen mode
            if isFullscreen {
                controller?.toggleFullscreen()
                return
            }
            super.keyDown(with: event)
            return
            
        case 3: // F key - toggle fullscreen
            controller?.toggleFullscreen()
            
        case 35: // P key - toggle quality mode (30fps/60fps)
            togglePerformanceMode(nil)
            
        case 124: // Right arrow - next preset
            if hasShift {
                // Hard cut (instant switch)
                visualizationGLView?.nextPreset(hardCut: true)
            } else {
                visualizationGLView?.nextPreset(hardCut: false)
            }
            
        case 123: // Left arrow - previous preset
            if hasShift {
                visualizationGLView?.previousPreset(hardCut: true)
            } else {
                visualizationGLView?.previousPreset(hardCut: false)
            }
            
        case 15: // R key - random preset
            if hasShift {
                visualizationGLView?.randomPreset(hardCut: true)
            } else {
                visualizationGLView?.randomPreset(hardCut: false)
            }
            
        case 37: // L key - toggle preset lock
            if let vis = visualizationGLView {
                vis.isPresetLocked = !vis.isPresetLocked
                NSLog("ProjectMView: Preset lock %@", vis.isPresetLocked ? "enabled" : "disabled")
            }
            
        case 8: // C key - toggle cycle mode
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
            
        default:
            super.keyDown(with: event)
        }
    }
    
    // MARK: - Context Menu
    
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        
        let isProjectMAvailable = visualizationGLView?.isProjectMAvailable ?? false
        
        // Preset navigation (only when projectM is available)
        if isProjectMAvailable {
            let presetName = visualizationGLView?.currentPresetName ?? "Unknown"
            let presetIndex = (visualizationGLView?.currentPresetIndex ?? 0) + 1
            let presetCount = visualizationGLView?.presetCount ?? 0
            
            let currentPresetItem = NSMenuItem(title: "Preset: \(presetName) (\(presetIndex)/\(presetCount))", action: nil, keyEquivalent: "")
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
            
            let lockPresetItem = NSMenuItem(title: "Lock Preset", action: #selector(togglePresetLock(_:)), keyEquivalent: "l")
            lockPresetItem.target = self
            lockPresetItem.state = (visualizationGLView?.isPresetLocked ?? false) ? .on : .off
            menu.addItem(lockPresetItem)
            
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
                    let presetItem = NSMenuItem(title: name, action: #selector(selectPresetFromMenu(_:)), keyEquivalent: "")
                    presetItem.target = self
                    presetItem.tag = i
                    presetItem.state = (i == (visualizationGLView?.currentPresetIndex ?? -1)) ? .on : .off
                    presetsMenu.addItem(presetItem)
                }
                
                let presetsMenuItem = NSMenuItem(title: "Presets (\(presetCount))", action: nil, keyEquivalent: "")
                presetsMenuItem.submenu = presetsMenu
                menu.addItem(presetsMenuItem)
                
                menu.addItem(NSMenuItem.separator())
            }
        }

        // Visualization Engine selector
        let engineMenu = NSMenu()
        let currentEngineType = visualizationGLView?.currentEngineType ?? .projectM

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
        if isProjectMAvailable {
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
        visualizationGLView?.nextPreset()
    }
    
    @objc private func previousPresetAction(_ sender: Any?) {
        visualizationGLView?.previousPreset()
    }
    
    @objc private func randomPresetAction(_ sender: Any?) {
        visualizationGLView?.randomPreset()
    }
    
    @objc private func togglePresetLock(_ sender: Any?) {
        if let vis = visualizationGLView {
            vis.isPresetLocked = !vis.isPresetLocked
        }
    }
    
    @objc private func selectPresetFromMenu(_ sender: NSMenuItem) {
        let index = sender.tag
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
        visualizationGLView?.switchEngine(to: type)
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
