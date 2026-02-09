import AppKit

// =============================================================================
// SPECTRUM VIEW - Standalone spectrum analyzer window with skin chrome
// =============================================================================
// Container view that draws skin-styled window chrome around the Metal-based
// SpectrumAnalyzerView. Follows the same pattern as ProjectMView.
// =============================================================================

/// Spectrum analyzer container view with full skin support
class SpectrumView: NSView {
    
    // MARK: - Properties
    
    weak var controller: SpectrumWindowController?
    
    /// The Metal-based spectrum analyzer view
    private var spectrumAnalyzerView: SpectrumAnalyzerView?
    
    /// Shade mode state
    private(set) var isShadeMode = false
    
    /// Button being pressed (for visual feedback)
    private var pressedButton: SkinRenderer.ProjectMButtonType?
    
    /// Window dragging state
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    
    /// Observer for spectrum data notifications
    private var spectrumObserver: NSObjectProtocol?
    
    // MARK: - Layout Constants
    
    private var Layout: SkinElements.SpectrumWindow.Layout.Type {
        SkinElements.SpectrumWindow.Layout.self
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
        
        // Set up accessibility
        setupAccessibility()
        
        // Create and add Metal spectrum analyzer view
        setupSpectrumAnalyzerView()
        
        // Subscribe to spectrum data notifications
        spectrumObserver = NotificationCenter.default.addObserver(
            forName: .audioSpectrumDataUpdated,
            object: nil,
            queue: .main  // Process on main thread to prevent notification queue buildup
        ) { [weak self] notification in
            self?.handleSpectrumUpdate(notification)
        }
    }
    
    private func setupSpectrumAnalyzerView() {
        let contentArea = calculateContentArea()
        
        spectrumAnalyzerView = SpectrumAnalyzerView(frame: contentArea)
        if let view = spectrumAnalyzerView {
            // Configure bars to fit content area precisely
            let barCount = SkinElements.SpectrumWindow.barCount
            let spacing: CGFloat = 1.0
            
            // Calculate bar width to fit exactly in content area
            // Use floor() for crisp pixel-aligned bars (fractional widths cause jagged rendering)
            let availableWidth = contentArea.width
            let barWidth = (availableWidth - CGFloat(barCount - 1) * spacing) / CGFloat(barCount)
            
            view.barCount = barCount
            view.barWidth = max(2.0, floor(barWidth))
            view.barSpacing = spacing
            view.autoresizingMask = []  // Manual frame updates
            addSubview(view)
        }
    }
    
    private func calculateContentArea() -> NSRect {
        // Content area inside the chrome
        let titleHeight = WindowManager.shared.hideTitleBars ? CGFloat(0) : Layout.titleBarHeight
        let leftBorder = Layout.leftBorder
        let rightBorder = Layout.rightBorder
        let bottomBorder = Layout.bottomBorder
        
        // In macOS coordinates, y=0 is at the bottom
        return NSRect(
            x: leftBorder,
            y: bottomBorder,
            width: max(0, bounds.width - leftBorder - rightBorder),
            height: max(0, bounds.height - titleHeight - bottomBorder)
        )
    }
    
    deinit {
        if let observer = spectrumObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Accessibility
    
    private func setupAccessibility() {
        setAccessibilityIdentifier("spectrumView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("NullPlayer Analyzer")
    }
    
    // MARK: - Coordinate Conversion
    
    /// Convert a point from view coordinates (macOS bottom-left) to skin coordinates (top-left)
    private func convertToSkinCoordinates(_ point: NSPoint) -> NSPoint {
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
        
        // Draw window chrome with "NULLPLAYER ANALYZER" title
        renderer.drawSpectrumAnalyzerWindow(in: context, bounds: bounds, isActive: isActive,
                                            pressedButton: pressedButton, isShadeMode: isShadeMode)
        
        context.restoreGState()
    }
    
    // MARK: - Spectrum Data
    
    /// Handle spectrum data notification from audio engine
    private func handleSpectrumUpdate(_ notification: Notification) {
        guard !isShadeMode else { return }
        
        guard let userInfo = notification.userInfo,
              let spectrum = userInfo["spectrum"] as? [Float] else { return }
        
        // Forward spectrum data to Metal view
        spectrumAnalyzerView?.updateSpectrum(spectrum)
    }
    
    // MARK: - Public Methods
    
    func skinDidChange() {
        spectrumAnalyzerView?.skinDidChange()
        needsDisplay = true
    }
    
    func setShadeMode(_ enabled: Bool) {
        isShadeMode = enabled
        
        // Hide/show spectrum view
        spectrumAnalyzerView?.isHidden = enabled
        
        needsDisplay = true
    }
    
    func updateSpectrumFrame() {
        let contentArea = calculateContentArea()
        spectrumAnalyzerView?.frame = contentArea
        
        // Recalculate bar width to fit content area
        if let view = spectrumAnalyzerView {
            let barCount = view.barCount
            let spacing = view.barSpacing
            let availableWidth = contentArea.width
            let barWidth = (availableWidth - CGFloat(barCount - 1) * spacing) / CGFloat(barCount)
            view.barWidth = max(2.0, floor(barWidth))  // Floor for crisp pixel-aligned bars
        }
    }
    
    func stopRendering() {
        // Explicitly stop the Metal display link when window is hidden
        spectrumAnalyzerView?.stopDisplayLink()
    }
    
    func startRendering() {
        // Restart the Metal display link when window becomes visible
        spectrumAnalyzerView?.startDisplayLink()
    }
    
    // MARK: - Hit Testing
    
    private func hitTestTitleBar(at skinPoint: NSPoint) -> Bool {
        if WindowManager.shared.hideTitleBars {
            // Invisible drag zone at the very top of the visible window
            return skinPoint.y >= Layout.titleBarHeight && skinPoint.y < Layout.titleBarHeight + 6
        }
        return skinPoint.y < Layout.titleBarHeight &&
               skinPoint.x < bounds.width - 25
    }
    
    private func hitTestCloseButton(at skinPoint: NSPoint) -> Bool {
        if WindowManager.shared.hideTitleBars { return false }
        let titleHeight = Layout.titleBarHeight
        let closeRect = NSRect(x: bounds.width - 25, y: 0, width: 25, height: titleHeight)
        return closeRect.contains(skinPoint)
    }
    
    // MARK: - Mouse Events
    
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
        
        // Check close button
        if hitTestCloseButton(at: skinPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        // Title bar - start window drag
        if hitTestTitleBar(at: skinPoint) {
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
            if let window = window {
                WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
            }
            return
        }
        
        // Content area - double-click cycles visualization mode
        if event.clickCount == 2 {
            cycleQualityMode()
            return
        }
        
        // Content area - window dragging
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
        if let window = window {
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: WindowManager.shared.hideTitleBars)
        }
    }
    
    private func handleShadeMouseDown(at skinPoint: NSPoint, event: NSEvent) {
        if hitTestCloseButton(at: skinPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        // Start window drag
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
        if let window = window {
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
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
                break  // Not used
            }
            
            pressedButton = nil
            needsDisplay = true
        }
    }
    
    private func handleShadeMouseUp(at skinPoint: NSPoint) {
        if let pressed = pressedButton {
            switch pressed {
            case .close:
                if hitTestCloseButton(at: skinPoint) {
                    window?.close()
                }
            case .shade:
                break
            }
            
            pressedButton = nil
            needsDisplay = true
        }
    }
    
    private func toggleShadeMode() {
        isShadeMode.toggle()
        controller?.setShadeMode(isShadeMode)
    }
    
    // MARK: - Keyboard Events
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape - close window or exit fullscreen
            if window?.styleMask.contains(.fullScreen) == true {
                window?.toggleFullScreen(nil)
            } else {
                window?.close()
            }
        case 3: // F key - toggle fullscreen
            window?.toggleFullScreen(nil)
        case 123: // Left arrow - previous style (flame/lightning/matrix mode)
            if spectrumAnalyzerView?.qualityMode == .flame {
                cycleFlameStyle(forward: false)
            } else if spectrumAnalyzerView?.qualityMode == .electricity {
                cycleLightningStyle(forward: false)
            } else if spectrumAnalyzerView?.qualityMode == .matrix {
                cycleMatrixColor(forward: false)
            } else { super.keyDown(with: event) }
        case 124: // Right arrow - next style (flame/lightning/matrix mode)
            if spectrumAnalyzerView?.qualityMode == .flame {
                cycleFlameStyle(forward: true)
            } else if spectrumAnalyzerView?.qualityMode == .electricity {
                cycleLightningStyle(forward: true)
            } else if spectrumAnalyzerView?.qualityMode == .matrix {
                cycleMatrixColor(forward: true)
            } else { super.keyDown(with: event) }
        default:
            super.keyDown(with: event)
        }
    }
    
    private func cycleQualityMode() {
        guard let view = spectrumAnalyzerView else { return }
        let modes = SpectrumQualityMode.allCases
        guard let idx = modes.firstIndex(of: view.qualityMode) else { return }
        // Skip modes whose shader file is missing
        var newIdx = (idx + 1) % modes.count
        while !SpectrumAnalyzerView.isShaderAvailable(for: modes[newIdx]) && newIdx != idx {
            newIdx = (newIdx + 1) % modes.count
        }
        let newMode = modes[newIdx]
        view.qualityMode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: "spectrumQualityMode")
    }
    
    private func cycleFlameStyle(forward: Bool) {
        let styles = FlameStyle.allCases
        guard let idx = styles.firstIndex(of: spectrumAnalyzerView?.flameStyle ?? .inferno) else { return }
        let newIdx = forward ? (idx + 1) % styles.count : (idx - 1 + styles.count) % styles.count
        spectrumAnalyzerView?.flameStyle = styles[newIdx]
    }
    
    private func cycleLightningStyle(forward: Bool) {
        let styles = LightningStyle.allCases
        guard let idx = styles.firstIndex(of: spectrumAnalyzerView?.lightningStyle ?? .classic) else { return }
        let newIdx = forward ? (idx + 1) % styles.count : (idx - 1 + styles.count) % styles.count
        spectrumAnalyzerView?.lightningStyle = styles[newIdx]
    }
    
    private func cycleMatrixColor(forward: Bool) {
        let schemes = MatrixColorScheme.allCases
        guard let idx = schemes.firstIndex(of: spectrumAnalyzerView?.matrixColorScheme ?? .classic) else { return }
        let newIdx = forward ? (idx + 1) % schemes.count : (idx - 1 + schemes.count) % schemes.count
        spectrumAnalyzerView?.matrixColorScheme = schemes[newIdx]
    }
    
    // MARK: - Context Menu
    
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        
        // Quality Mode submenu
        let qualityMenu = NSMenu()
        for mode in SpectrumQualityMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(setQualityMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode
            item.state = (spectrumAnalyzerView?.qualityMode == mode) ? .on : .off
            // Disable modes whose shader file is missing
            if !SpectrumAnalyzerView.isShaderAvailable(for: mode) {
                item.isEnabled = false
            }
            qualityMenu.addItem(item)
        }
        let qualityMenuItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        qualityMenuItem.submenu = qualityMenu
        menu.addItem(qualityMenuItem)
        
        // Decay/Responsiveness submenu
        let decayMenu = NSMenu()
        for mode in SpectrumDecayMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(setDecayMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode
            item.state = (spectrumAnalyzerView?.decayMode == mode) ? .on : .off
            decayMenu.addItem(item)
        }
        let decayMenuItem = NSMenuItem(title: "Responsiveness", action: nil, keyEquivalent: "")
        decayMenuItem.submenu = decayMenu
        menu.addItem(decayMenuItem)
        
        // Normalization Mode submenu (not shown for Flame mode)
        if spectrumAnalyzerView?.qualityMode != .flame {
            let normMenu = NSMenu()
            let currentNormMode = UserDefaults.standard.string(forKey: "spectrumNormalizationMode")
                .flatMap { SpectrumNormalizationMode(rawValue: $0) } ?? .accurate
            for mode in SpectrumNormalizationMode.allCases {
                let item = NSMenuItem(title: "\(mode.displayName) - \(mode.description)", action: #selector(setNormalizationMode(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = mode
                item.state = (currentNormMode == mode) ? .on : .off
                normMenu.addItem(item)
            }
            let normMenuItem = NSMenuItem(title: "Normalization", action: nil, keyEquivalent: "")
            normMenuItem.submenu = normMenu
            menu.addItem(normMenuItem)
        }
        
        // Flame Style submenu (only when Flame mode active)
        if spectrumAnalyzerView?.qualityMode == .flame {
            let flameMenu = NSMenu()
            let curStyle = spectrumAnalyzerView?.flameStyle ?? .inferno
            for style in FlameStyle.allCases {
                let item = NSMenuItem(title: style.displayName, action: #selector(setFlameStyle(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = style
                item.state = (curStyle == style) ? .on : .off
                flameMenu.addItem(item)
            }
            let flameMenuItem = NSMenuItem(title: "Flame Style", action: nil, keyEquivalent: "")
            flameMenuItem.submenu = flameMenu
            menu.addItem(flameMenuItem)
            
            // Flame Intensity submenu
            let intensityMenu = NSMenu()
            let curIntensity = spectrumAnalyzerView?.flameIntensity ?? .mellow
            for intensity in FlameIntensity.allCases {
                let item = NSMenuItem(title: intensity.displayName, action: #selector(setFlameIntensity(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = intensity
                item.state = (curIntensity == intensity) ? .on : .off
                intensityMenu.addItem(item)
            }
            let intensityMenuItem = NSMenuItem(title: "Fire Intensity", action: nil, keyEquivalent: "")
            intensityMenuItem.submenu = intensityMenu
            menu.addItem(intensityMenuItem)
        }
        
        // Lightning Style submenu (only when Lightning mode active)
        if spectrumAnalyzerView?.qualityMode == .electricity {
            let lightningMenu = NSMenu()
            let curStyle = spectrumAnalyzerView?.lightningStyle ?? .classic
            for style in LightningStyle.allCases {
                let item = NSMenuItem(title: style.displayName, action: #selector(setLightningStyle(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = style
                item.state = (curStyle == style) ? .on : .off
                lightningMenu.addItem(item)
            }
            let lightningMenuItem = NSMenuItem(title: "Lightning Style", action: nil, keyEquivalent: "")
            lightningMenuItem.submenu = lightningMenu
            menu.addItem(lightningMenuItem)
        }
        
        // Matrix sub-menus (only when Matrix mode active)
        if spectrumAnalyzerView?.qualityMode == .matrix {
            // Matrix Color submenu
            let matrixColorMenu = NSMenu()
            let curMatrixColor = spectrumAnalyzerView?.matrixColorScheme ?? .classic
            for scheme in MatrixColorScheme.allCases {
                let item = NSMenuItem(title: scheme.displayName, action: #selector(setMatrixColor(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = scheme
                item.state = (curMatrixColor == scheme) ? .on : .off
                matrixColorMenu.addItem(item)
            }
            let matrixColorMenuItem = NSMenuItem(title: "Matrix Color", action: nil, keyEquivalent: "")
            matrixColorMenuItem.submenu = matrixColorMenu
            menu.addItem(matrixColorMenuItem)
            
            // Matrix Intensity submenu
            let matrixIntensityMenu = NSMenu()
            let curMatrixIntensity = spectrumAnalyzerView?.matrixIntensity ?? .subtle
            for intensity in MatrixIntensity.allCases {
                let item = NSMenuItem(title: intensity.displayName, action: #selector(setMatrixIntensity(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = intensity
                item.state = (curMatrixIntensity == intensity) ? .on : .off
                matrixIntensityMenu.addItem(item)
            }
            let matrixIntensityMenuItem = NSMenuItem(title: "Matrix Intensity", action: nil, keyEquivalent: "")
            matrixIntensityMenuItem.submenu = matrixIntensityMenu
            menu.addItem(matrixIntensityMenuItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Fullscreen toggle
        let isFullscreen = window?.styleMask.contains(.fullScreen) ?? false
        let fullscreenItem = NSMenuItem(
            title: isFullscreen ? "Exit Full Screen" : "Enter Full Screen",
            action: #selector(toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullscreenItem.target = self
        menu.addItem(fullscreenItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Close
        let closeItem = NSMenuItem(title: "Close", action: #selector(closeWindow(_:)), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        
        return menu
    }
    
    @objc private func toggleFullScreen(_ sender: Any?) {
        window?.toggleFullScreen(sender)
    }
    
    @objc private func setQualityMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? SpectrumQualityMode else { return }
        spectrumAnalyzerView?.qualityMode = mode
    }
    
    @objc private func setDecayMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? SpectrumDecayMode else { return }
        spectrumAnalyzerView?.decayMode = mode
    }
    
    @objc private func setNormalizationMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? SpectrumNormalizationMode else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: "spectrumNormalizationMode")
    }
    
    @objc private func setFlameStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? FlameStyle else { return }
        spectrumAnalyzerView?.flameStyle = style
    }
    
    @objc private func setLightningStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? LightningStyle else { return }
        spectrumAnalyzerView?.lightningStyle = style
    }
    
    @objc private func setFlameIntensity(_ sender: NSMenuItem) {
        guard let intensity = sender.representedObject as? FlameIntensity else { return }
        spectrumAnalyzerView?.flameIntensity = intensity
    }
    
    @objc private func setMatrixColor(_ sender: NSMenuItem) {
        guard let scheme = sender.representedObject as? MatrixColorScheme else { return }
        spectrumAnalyzerView?.matrixColorScheme = scheme
    }
    
    @objc private func setMatrixIntensity(_ sender: NSMenuItem) {
        guard let intensity = sender.representedObject as? MatrixIntensity else { return }
        spectrumAnalyzerView?.matrixIntensity = intensity
    }
    
    @objc private func closeWindow(_ sender: Any?) {
        window?.close()
    }
    
    // MARK: - Layout
    
    override func layout() {
        super.layout()
        updateSpectrumFrame()
    }
}
