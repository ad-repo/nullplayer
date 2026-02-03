import AppKit

// =============================================================================
// SPECTRUM VIEW - Standalone spectrum analyzer window with skin chrome
// =============================================================================
// Container view that draws skin-styled window chrome around the Metal-based
// SpectrumAnalyzerView. Follows the same pattern as MilkdropView.
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
    private var pressedButton: SkinRenderer.MilkdropButtonType?
    
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
            queue: nil  // Receive on posting thread for lowest latency
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
            // totalWidth = barCount * barWidth + (barCount - 1) * spacing
            // barWidth = (totalWidth - (barCount - 1) * spacing) / barCount
            let availableWidth = contentArea.width
            let barWidth = (availableWidth - CGFloat(barCount - 1) * spacing) / CGFloat(barCount)
            
            view.barCount = barCount
            view.barWidth = max(2.0, floor(barWidth))  // At least 2px, use whole pixels
            view.barSpacing = spacing
            view.autoresizingMask = []  // Manual frame updates
            addSubview(view)
        }
    }
    
    private func calculateContentArea() -> NSRect {
        // Content area inside the chrome
        let titleHeight = Layout.titleBarHeight
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
        setAccessibilityLabel("Spectrum Analyzer")
    }
    
    // MARK: - Coordinate Conversion
    
    /// Convert a point from view coordinates (macOS bottom-left) to Winamp coordinates (top-left)
    private func convertToWinampCoordinates(_ point: NSPoint) -> NSPoint {
        return NSPoint(x: point.x, y: bounds.height - point.y)
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Use default skin if locked, otherwise use current skin
        let skin: Skin
        if WindowManager.shared.lockBrowserMilkdropSkin {
            skin = SkinLoader.shared.loadDefault()
        } else {
            skin = WindowManager.shared.currentSkin ?? SkinLoader.shared.loadDefault()
        }
        let renderer = SkinRenderer(skin: skin)
        let isActive = window?.isKeyWindow ?? true
        
        // Flip coordinate system to match Winamp's top-down coordinates
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        
        // Draw window chrome with "SPECTRUM ANALYZER" title
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
            view.barWidth = max(2.0, floor(barWidth))
        }
    }
    
    func stopRendering() {
        // SpectrumAnalyzerView handles its own display link
    }
    
    func startRendering() {
        // SpectrumAnalyzerView handles its own display link
    }
    
    // MARK: - Hit Testing
    
    private func hitTestTitleBar(at winampPoint: NSPoint) -> Bool {
        return winampPoint.y < Layout.titleBarHeight &&
               winampPoint.x < bounds.width - 25
    }
    
    private func hitTestCloseButton(at winampPoint: NSPoint) -> Bool {
        let titleHeight = Layout.titleBarHeight
        let closeRect = NSRect(x: bounds.width - 25, y: 0, width: 25, height: titleHeight)
        return closeRect.contains(winampPoint)
    }
    
    // MARK: - Mouse Events
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let winampPoint = convertToWinampCoordinates(point)
        
        // Check for double-click on title bar to toggle shade mode
        if event.clickCount == 2 && hitTestTitleBar(at: winampPoint) {
            toggleShadeMode()
            return
        }
        
        if isShadeMode {
            handleShadeMouseDown(at: winampPoint, event: event)
            return
        }
        
        // Check close button
        if hitTestCloseButton(at: winampPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        // Title bar - start window drag
        if hitTestTitleBar(at: winampPoint) {
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
            if let window = window {
                WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
            }
            return
        }
        
        // Content area - allow window dragging
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
        if let window = window {
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: false)
        }
    }
    
    private func handleShadeMouseDown(at winampPoint: NSPoint, event: NSEvent) {
        if hitTestCloseButton(at: winampPoint) {
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
        let winampPoint = convertToWinampCoordinates(point)
        
        // End window dragging
        if isDraggingWindow {
            isDraggingWindow = false
            if let window = window {
                WindowManager.shared.windowDidFinishDragging(window)
            }
        }
        
        if isShadeMode {
            handleShadeMouseUp(at: winampPoint)
            return
        }
        
        // Handle button releases
        if let pressed = pressedButton {
            switch pressed {
            case .close:
                if hitTestCloseButton(at: winampPoint) {
                    window?.close()
                }
            case .shade:
                break  // Not used
            }
            
            pressedButton = nil
            needsDisplay = true
        }
    }
    
    private func handleShadeMouseUp(at winampPoint: NSPoint) {
        if let pressed = pressedButton {
            switch pressed {
            case .close:
                if hitTestCloseButton(at: winampPoint) {
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
        case 53: // Escape - close window
            window?.close()
        default:
            super.keyDown(with: event)
        }
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
            qualityMenu.addItem(item)
        }
        let qualityMenuItem = NSMenuItem(title: "Quality", action: nil, keyEquivalent: "")
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
        
        menu.addItem(NSMenuItem.separator())
        
        // Close
        let closeItem = NSMenuItem(title: "Close", action: #selector(closeWindow(_:)), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        
        return menu
    }
    
    @objc private func setQualityMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? SpectrumQualityMode else { return }
        spectrumAnalyzerView?.qualityMode = mode
    }
    
    @objc private func setDecayMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? SpectrumDecayMode else { return }
        spectrumAnalyzerView?.decayMode = mode
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
