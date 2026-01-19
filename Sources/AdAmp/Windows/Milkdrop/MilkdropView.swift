import AppKit

// =============================================================================
// MILKDROP VIEW - Visualization window with skin sprite support
// =============================================================================
// Follows the same pattern as EQView and PlaylistView for:
// - Coordinate transformation (Winamp top-down system)
// - Button hit testing and visual feedback
// - Window dragging support
// =============================================================================

/// Milkdrop visualization view with full skin support
class MilkdropView: NSView {
    
    // MARK: - Properties
    
    weak var controller: MilkdropWindowController?
    
    /// The OpenGL visualization view
    private var visualizationView: VisualizationGLView?
    
    /// Shade mode state
    private(set) var isShadeMode = false
    
    /// Button being pressed (for visual feedback)
    private var pressedButton: SkinRenderer.MilkdropButtonType?
    
    /// Window dragging state
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    
    /// Display update timer for spectrum data
    private var displayTimer: Timer?
    
    // MARK: - Layout Constants
    // Reference to SkinElements.Milkdrop.Layout for consistency
    
    private var Layout: SkinElements.Milkdrop.Layout.Type {
        SkinElements.Milkdrop.Layout.self
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
        
        // Create and add OpenGL visualization view
        setupVisualizationView()
        
        // Start display timer for spectrum updates
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.updateVisualizationData()
        }
    }
    
    private func setupVisualizationView() {
        // Calculate visualization area - will be updated in layout()
        let visArea = calculateVisualizationArea()
        
        visualizationView = VisualizationGLView(frame: visArea, pixelFormat: nil)
        if let visView = visualizationView {
            // Don't use autoresizingMask - we manually update frame in layout()
            visView.autoresizingMask = []
            addSubview(visView)
        }
    }
    
    private func calculateVisualizationArea() -> NSRect {
        // The visualization area is the content area inside the chrome
        // Chrome: title bar at top, thin borders on sides and bottom
        let titleHeight = Layout.titleBarHeight
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
        displayTimer?.invalidate()
        visualizationView?.stopRendering()
    }
    
    // MARK: - Coordinate Conversion
    
    /// Convert a point from view coordinates (macOS bottom-left origin) to Winamp coordinates (top-left origin)
    private func convertToWinampCoordinates(_ point: NSPoint) -> NSPoint {
        // Simply flip Y coordinate - no scaling needed for resizable window
        return NSPoint(x: point.x, y: bounds.height - point.y)
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let skin = WindowManager.shared.currentSkin
        let renderer = SkinRenderer(skin: skin ?? SkinLoader.shared.loadDefault())
        let isActive = window?.isKeyWindow ?? true
        
        // Flip coordinate system to match Winamp's top-down coordinates
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        
        // Draw window chrome at actual window bounds (no scaling - chrome tiles to fill)
        renderer.drawMilkdropWindow(in: context, bounds: bounds, isActive: isActive,
                                    pressedButton: pressedButton, isShadeMode: isShadeMode)
        
        context.restoreGState()
    }
    
    // MARK: - Visualization Data
    
    private func updateVisualizationData() {
        guard !isShadeMode else { return }
        
        let audioEngine = WindowManager.shared.audioEngine
        
        // Get spectrum data from audio engine
        let spectrum = audioEngine.spectrumData
        visualizationView?.updateSpectrum(spectrum)
        
        // Get PCM data from audio engine (for oscilloscope mode)
        let pcm = audioEngine.pcmData
        visualizationView?.updatePCM(pcm)
    }
    
    // MARK: - Public Methods
    
    func skinDidChange() {
        needsDisplay = true
    }
    
    /// Set shade mode externally (e.g., from controller)
    func setShadeMode(_ enabled: Bool) {
        isShadeMode = enabled
        
        // Show/hide visualization view
        visualizationView?.isHidden = enabled
        
        // Stop/start rendering based on mode
        if enabled {
            visualizationView?.stopRendering()
        } else {
            visualizationView?.startRendering()
            updateVisualizationFrame()
        }
        
        needsDisplay = true
    }
    
    /// Update visualization view frame after resize
    func updateVisualizationFrame() {
        let visArea = calculateVisualizationArea()
        visualizationView?.frame = visArea
    }
    
    /// Toggle shade mode
    private func toggleShadeMode() {
        isShadeMode.toggle()
        controller?.setShadeMode(isShadeMode)
    }
    
    /// Set visualization mode
    func setVisualizationMode(_ mode: VisualizationGLView.VisualizationMode) {
        visualizationView?.mode = mode
    }
    
    /// Stop rendering (for window close/hide)
    func stopRendering() {
        visualizationView?.stopRendering()
    }
    
    /// Start rendering
    func startRendering() {
        if !isShadeMode {
            visualizationView?.startRendering()
        }
    }
    
    // MARK: - Hit Testing
    
    /// Check if point hits title bar (for dragging)
    private func hitTestTitleBar(at winampPoint: NSPoint) -> Bool {
        // Title bar is at the top (24px), leave room for close button on the right
        return winampPoint.y < Layout.titleBarHeight && 
               winampPoint.x < bounds.width - 30  // Leave room for right corner with close button
    }
    
    /// Check if point hits close button
    private func hitTestCloseButton(at winampPoint: NSPoint) -> Bool {
        // Close button is in the right corner of 20px title bar
        let closeX = bounds.width - 14
        let buttonY: CGFloat = 5
        let closeRect = NSRect(x: closeX, y: buttonY, width: 10, height: 10)
        return closeRect.contains(winampPoint)
    }
    
    /// Check if point hits shade button (not currently visible in this design)
    private func hitTestShadeButton(at winampPoint: NSPoint) -> Bool {
        // Shade button not used in this design - double-click title bar instead
        return false
    }
    
    /// Hit test for shade mode close button (uses same title bar)
    private func hitTestShadeCloseButton(at winampPoint: NSPoint) -> Bool {
        // Same as normal mode since shade uses same title bar
        return hitTestCloseButton(at: winampPoint)
    }
    
    private func hitTestShadeShadeButton(at winampPoint: NSPoint) -> Bool {
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
        
        // Check window control buttons
        if hitTestCloseButton(at: winampPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        if hitTestShadeButton(at: winampPoint) {
            pressedButton = .shade
            needsDisplay = true
            return
        }
        
        // Title bar - start window drag
        if hitTestTitleBar(at: winampPoint) {
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
        }
    }
    
    /// Handle mouse down in shade mode
    private func handleShadeMouseDown(at winampPoint: NSPoint, event: NSEvent) {
        // Check window control buttons
        if hitTestShadeCloseButton(at: winampPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        if hitTestShadeShadeButton(at: winampPoint) {
            pressedButton = .shade
            needsDisplay = true
            return
        }
        
        // Start window drag
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
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
                if hitTestShadeButton(at: winampPoint) {
                    toggleShadeMode()
                }
            }
            
            pressedButton = nil
            needsDisplay = true
        }
    }
    
    /// Handle mouse up in shade mode
    private func handleShadeMouseUp(at winampPoint: NSPoint) {
        if let pressed = pressedButton {
            switch pressed {
            case .close:
                if hitTestShadeCloseButton(at: winampPoint) {
                    window?.close()
                }
            case .shade:
                if hitTestShadeShadeButton(at: winampPoint) {
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
        switch event.keyCode {
        case 3: // F key - toggle fullscreen
            controller?.toggleFullscreen()
            
        case 49: // Space - toggle visualization mode
            let visView = visualizationView
            if visView?.mode == .spectrum {
                visView?.mode = .oscilloscope
            } else {
                visView?.mode = .spectrum
            }
            
        case 124: // Right arrow - next preset (future)
            controller?.nextPreset()
            
        case 123: // Left arrow - previous preset (future)
            controller?.previousPreset()
            
        default:
            super.keyDown(with: event)
        }
    }
    
    // MARK: - Context Menu
    
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        
        // Visualization mode submenu
        let modeMenu = NSMenu()
        
        let spectrumItem = NSMenuItem(title: "Spectrum Analyzer", action: #selector(setSpectrumMode(_:)), keyEquivalent: "")
        spectrumItem.target = self
        spectrumItem.state = visualizationView?.mode == .spectrum ? .on : .off
        modeMenu.addItem(spectrumItem)
        
        let oscilloscopeItem = NSMenuItem(title: "Oscilloscope", action: #selector(setOscilloscopeMode(_:)), keyEquivalent: "")
        oscilloscopeItem.target = self
        oscilloscopeItem.state = visualizationView?.mode == .oscilloscope ? .on : .off
        modeMenu.addItem(oscilloscopeItem)
        
        let modeItem = NSMenuItem(title: "Visualization Mode", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)
        
        menu.addItem(NSMenuItem.separator())
        
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
    
    @objc private func setSpectrumMode(_ sender: Any?) {
        visualizationView?.mode = .spectrum
    }
    
    @objc private func setOscilloscopeMode(_ sender: Any?) {
        visualizationView?.mode = .oscilloscope
    }
    
    @objc private func toggleFullscreenAction(_ sender: Any?) {
        controller?.toggleFullscreen()
    }
    
    @objc private func closeWindow(_ sender: Any?) {
        window?.close()
    }
    
    // MARK: - Layout
    
    override func layout() {
        super.layout()
        updateVisualizationFrame()
    }
}
