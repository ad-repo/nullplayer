import AppKit

// =============================================================================
// MODERN SPECTRUM VIEW - Standalone spectrum analyzer with modern skin chrome
// =============================================================================
// Container view that draws modern skin-styled window chrome around the Metal-based
// SpectrumAnalyzerView. Follows the same pattern as ModernMainWindowView for chrome
// rendering, and SpectrumView for spectrum functionality.
//
// Has ZERO dependencies on the classic skin system (Skin/, SkinElements, SkinRenderer, etc.).
// =============================================================================

/// Modern spectrum analyzer container view with full modern skin support
class ModernSpectrumView: NSView {
    
    // MARK: - Properties
    
    weak var controller: ModernSpectrumWindowController?
    
    /// The skin renderer
    private var renderer: ModernSkinRenderer!
    
    /// The Metal-based spectrum analyzer view
    private var spectrumAnalyzerView: SpectrumAnalyzerView?
    
    /// Shade mode state
    private(set) var isShadeMode = false
    
    /// Button being pressed (for visual feedback)
    private var pressedButton: String?
    
    /// Window dragging state
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    
    /// Observer for spectrum data notifications
    private var spectrumObserver: NSObjectProtocol?
    
    /// Scale factor for hit testing (computed to track double-size changes)
    private var scale: CGFloat { ModernSkinElements.scaleFactor }
    
    // MARK: - Layout Constants
    
    private var titleBarHeight: CGFloat { WindowManager.shared.hideTitleBars ? borderWidth : ModernSkinElements.spectrumTitleBarHeight }
    private var borderWidth: CGFloat { ModernSkinElements.spectrumBorderWidth }
    
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
        
        // Initialize with current skin or fallback
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)
        
        // Create and add Metal spectrum analyzer view
        setupSpectrumAnalyzerView()
        
        // Subscribe to spectrum data notifications
        spectrumObserver = NotificationCenter.default.addObserver(
            forName: .audioSpectrumDataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSpectrumUpdate(notification)
        }
        
        // Observe skin changes
        NotificationCenter.default.addObserver(self, selector: #selector(modernSkinDidChange),
                                                name: ModernSkinEngine.skinDidChangeNotification, object: nil)
        
        // Observe double size changes
        NotificationCenter.default.addObserver(self, selector: #selector(doubleSizeChanged),
                                                name: .doubleSizeDidChange, object: nil)
        
        // Set accessibility
        setAccessibilityIdentifier("modernSpectrumView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("NullPlayer Analyzer")
    }
    
    deinit {
        if let observer = spectrumObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Setup
    
    private func setupSpectrumAnalyzerView() {
        let contentArea = calculateContentArea()
        
        spectrumAnalyzerView = SpectrumAnalyzerView(frame: contentArea)
        if let view = spectrumAnalyzerView {
            let barCount = ModernSkinElements.spectrumBarCount
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
            
            // Apply skin spectrum colors
            updateSpectrumColors()
        }
    }
    
    private func calculateContentArea() -> NSRect {
        // Content area inside the chrome (standard macOS bottom-left coordinates)
        return NSRect(
            x: borderWidth,
            y: borderWidth,
            width: max(0, bounds.width - borderWidth * 2),
            height: max(0, bounds.height - titleBarHeight - borderWidth)
        )
    }
    
    private func updateSpectrumColors() {
        guard let skin = ModernSkinEngine.shared.currentSkin ?? Optional(ModernSkinLoader.shared.loadDefault()) else { return }
        spectrumAnalyzerView?.spectrumColors = skin.spectrumColors()
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Draw window background
        renderer.drawWindowBackground(in: bounds, context: context)
        
        // Draw window border with glow
        renderer.drawWindowBorder(in: bounds, context: context)
        
        // Draw title bar (unless hidden)
        if !WindowManager.shared.hideTitleBars {
            // Use spectrum-specific title bar element if skin provides it
            let titleBarId = "spectrum_titlebar"
            if let img = renderer.skin.image(for: titleBarId) {
                let scaledTitleRect = renderer.scaledRect(ModernSkinElements.spectrumTitleBar.defaultRect)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                img.draw(in: scaledTitleRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                NSGraphicsContext.restoreGraphicsState()
            }
            // Draw title text and separator using the standard title bar renderer
            renderer.drawTitleBar(in: ModernSkinElements.spectrumTitleBar.defaultRect, title: "NULLPLAYER ANALYZER", context: context)
            
            // Draw close button
            let closeState = (pressedButton == "spectrum_btn_close") ? "pressed" : "normal"
            renderer.drawWindowControlButton("spectrum_btn_close", state: closeState,
                                             in: ModernSkinElements.spectrumBtnClose.defaultRect, context: context)
        }
        
        // Draw shade mode title bar content if in shade mode
        if isShadeMode {
            // Just the title bar - no content area
            return
        }
    }
    
    // MARK: - Skin Change
    
    func skinDidChange() {
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)
        updateSpectrumColors()
        spectrumAnalyzerView?.skinDidChange()
        needsDisplay = true
    }
    
    @objc private func modernSkinDidChange() {
        skinDidChange()
    }
    
    @objc private func doubleSizeChanged() {
        skinDidChange()
    }
    
    // MARK: - Spectrum Data
    
    private func handleSpectrumUpdate(_ notification: Notification) {
        guard !isShadeMode else { return }
        
        guard let userInfo = notification.userInfo,
              let spectrum = userInfo["spectrum"] as? [Float] else { return }
        
        // Forward spectrum data to Metal view
        spectrumAnalyzerView?.updateSpectrum(spectrum)
    }
    
    // MARK: - Public Methods
    
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
            view.barWidth = max(2.0, floor(barWidth))
        }
        
    }
    
    func stopRendering() {
        spectrumAnalyzerView?.stopDisplayLink()
    }
    
    func startRendering() {
        spectrumAnalyzerView?.startDisplayLink()
    }
    
    // MARK: - Hit Testing
    
    /// Title bar rect in view coordinates (macOS bottom-left origin)
    private var titleBarViewRect: NSRect {
        NSRect(x: 0, y: bounds.height - titleBarHeight, width: bounds.width, height: titleBarHeight)
    }
    
    private func hitTestTitleBar(at point: NSPoint) -> Bool {
        if WindowManager.shared.hideTitleBars {
            return point.y >= bounds.height - 6  // invisible drag zone
        }
        // Title bar minus close button area
        let closeWidth: CGFloat = 25 * scale
        return point.y >= bounds.height - titleBarHeight &&
               point.x < bounds.width - closeWidth
    }
    
    private func hitTestCloseButton(at point: NSPoint) -> Bool {
        if WindowManager.shared.hideTitleBars { return false }
        let closeRect = renderer.scaledRect(ModernSkinElements.spectrumBtnClose.defaultRect)
        // Expand hit area slightly for usability
        let hitRect = closeRect.insetBy(dx: -4, dy: -4)
        return hitRect.contains(point)
    }
    
    // MARK: - Mouse Events
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // Check for double-click on title bar to toggle shade mode
        if event.clickCount == 2 && hitTestTitleBar(at: point) {
            toggleShadeMode()
            return
        }
        
        if isShadeMode {
            handleShadeMouseDown(at: point, event: event)
            return
        }
        
        // Check close button
        if hitTestCloseButton(at: point) {
            pressedButton = "spectrum_btn_close"
            needsDisplay = true
            return
        }
        
        // Title bar - start window drag
        if hitTestTitleBar(at: point) {
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
        // When title bars are hidden, all drags allow undocking (no visual title bar distinction)
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
        if let window = window {
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: WindowManager.shared.hideTitleBars)
        }
    }
    
    private func handleShadeMouseDown(at point: NSPoint, event: NSEvent) {
        if hitTestCloseButton(at: point) {
            pressedButton = "spectrum_btn_close"
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
        
        // End window dragging
        if isDraggingWindow {
            isDraggingWindow = false
            if let window = window {
                WindowManager.shared.windowDidFinishDragging(window)
            }
        }
        
        if isShadeMode {
            handleShadeMouseUp(at: point)
            return
        }
        
        // Handle button releases
        if let pressed = pressedButton {
            if pressed == "spectrum_btn_close" && hitTestCloseButton(at: point) {
                window?.close()
            }
            
            pressedButton = nil
            needsDisplay = true
        }
    }
    
    private func handleShadeMouseUp(at point: NSPoint) {
        if let pressed = pressedButton {
            if pressed == "spectrum_btn_close" && hitTestCloseButton(at: point) {
                window?.close()
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
    
    // MARK: - Visualization Mode Cycling
    
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
    
    // MARK: - Menu Actions
    
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
