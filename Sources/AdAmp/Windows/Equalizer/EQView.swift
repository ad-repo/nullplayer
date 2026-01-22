import AppKit

// =============================================================================
// EQ VIEW - Equalizer window implementation
// =============================================================================
// For skin format documentation, see: docs/SKIN_FORMAT_RESEARCH.md
//
// Color scale for sliders and graph curve:
// - RED at top (+12dB boost)
// - YELLOW at middle (0dB)
// - GREEN at bottom (-12dB cut)
// =============================================================================

/// Equalizer view - 10-band graphic equalizer with skin support
class EQView: NSView {
    
    // MARK: - Properties
    
    weak var controller: EQWindowController?
    
    /// EQ enabled state
    private var isEnabled = true
    
    /// Auto EQ state
    private var isAuto = false
    
    /// Preamp value (-12 to +12)
    private var preamp: Float = 0
    
    /// Band values (-12 to +12)
    private var bands: [Float] = Array(repeating: 0, count: 10)
    
    /// Currently dragging slider index (-1 = preamp, 0-9 = bands)
    private var draggingSlider: Int?
    
    /// Dragging state for window
    
    /// Button being pressed
    private var pressedButton: ButtonType?
    
    /// Region manager for hit testing
    private let regionManager = RegionManager.shared
    
    /// Shade mode state
    private(set) var isShadeMode = false
    
    // MARK: - Layout Constants
    
    private struct Layout {
        static let titleBarHeight: CGFloat = 14
        
        // Toggle buttons
        static let onOffRect = NSRect(x: 14, y: 18, width: 26, height: 12)
        static let autoRect = NSRect(x: 40, y: 18, width: 32, height: 12)
        
        // Presets button
        static let presetsRect = NSRect(x: 217, y: 18, width: 44, height: 12)
        
        // Preamp slider
        static let preampRect = NSRect(x: 21, y: 38, width: 14, height: 63)
        
        // EQ band sliders (left to right: 60Hz to 16kHz)
        static let bandStartX: CGFloat = 78
        static let bandSpacing: CGFloat = 18
        static let bandWidth: CGFloat = 14
        static let bandHeight: CGFloat = 63
        static let bandY: CGFloat = 38
        
        // Graph display
        static let graphRect = NSRect(x: 86, y: 17, width: 113, height: 19)
        
        // Frequency labels
        static let frequencies = ["60", "170", "310", "600", "1K", "3K", "6K", "12K", "14K", "16K"]
        
        // Window control buttons (in title bar, from right to left)
        static let closeRect = NSRect(x: 264, y: 3, width: 9, height: 9)
        static let shadeRect = NSRect(x: 254, y: 3, width: 9, height: 9)  // Toggle shade mode
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
        loadCurrentEQState()
        setupAccessibility()
    }
    
    // MARK: - Accessibility
    
    /// Set up accessibility identifiers for UI testing
    private func setupAccessibility() {
        setAccessibilityIdentifier("equalizerView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("Equalizer")
    }
    
    private func loadCurrentEQState() {
        let engine = WindowManager.shared.audioEngine
        
        // Load EQ enabled state from engine
        isEnabled = engine.isEQEnabled()
        
        // Load preamp and band values
        preamp = engine.getPreamp()
        for i in 0..<10 {
            bands[i] = engine.getEQBand(i)
        }
    }
    
    // MARK: - Scaling Support
    
    /// Calculate scale factor based on current bounds vs original size
    private var scaleFactor: CGFloat {
        let originalSize = isShadeMode ? SkinElements.EQShade.windowSize : Skin.baseEQSize
        let scaleX = bounds.width / originalSize.width
        let scaleY = bounds.height / originalSize.height
        return min(scaleX, scaleY)
    }
    
    /// Convert a point from view coordinates to original (unscaled) coordinates
    private func convertToOriginalCoordinates(_ point: NSPoint) -> NSPoint {
        let originalSize = isShadeMode ? SkinElements.EQShade.windowSize : Skin.baseEQSize
        let scale = scaleFactor
        
        if scale == 1.0 {
            return point
        }
        
        let scaledWidth = originalSize.width * scale
        let scaledHeight = originalSize.height * scale
        let offsetX = (bounds.width - scaledWidth) / 2
        let offsetY = (bounds.height - scaledHeight) / 2
        
        let x = (point.x - offsetX) / scale
        let y = (point.y - offsetY) / scale
        
        return NSPoint(x: x, y: y)
    }
    
    /// Get the original window size for hit testing
    private var originalWindowSize: NSSize {
        return isShadeMode ? SkinElements.EQShade.windowSize : Skin.baseEQSize
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let originalSize = isShadeMode ? SkinElements.EQShade.windowSize : Skin.baseEQSize
        let scale = scaleFactor
        
        // Flip coordinate system to match Winamp's top-down coordinates
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        
        // Apply scaling for resized window
        if scale != 1.0 {
            let scaledWidth = originalSize.width * scale
            let scaledHeight = originalSize.height * scale
            let offsetX = (bounds.width - scaledWidth) / 2
            let offsetY = (bounds.height - scaledHeight) / 2
            context.translateBy(x: offsetX, y: offsetY)
            context.scaleBy(x: scale, y: scale)
        }
        
        let skin = WindowManager.shared.currentSkin
        let renderer = SkinRenderer(skin: skin ?? SkinLoader.shared.loadDefault())
        
        let isActive = window?.isKeyWindow ?? true
        
        // Use original bounds for drawing (scaling is applied via transform)
        let drawBounds = NSRect(origin: .zero, size: originalSize)
        
        if isShadeMode {
            // Draw shade mode
            renderer.drawEqualizerShade(in: context, bounds: drawBounds, isActive: isActive, pressedButton: pressedButton)
        } else {
            // Draw normal mode
            drawNormalMode(renderer: renderer, context: context, isActive: isActive, drawBounds: drawBounds)
        }
        
        context.restoreGState()
    }
    
    /// Draw normal (non-shade) mode
    private func drawNormalMode(renderer: SkinRenderer, context: CGContext, isActive: Bool, drawBounds: NSRect) {
        // Draw EQ background
        renderer.drawEqualizerBackground(in: context, bounds: drawBounds, isActive: isActive)
        
        // Draw ON/OFF button
        let onState: ButtonState = isEnabled ? .active : .normal
        renderer.drawButton(.eqOnOff, state: onState,
                           at: SkinElements.Equalizer.Positions.onButton, in: context)
        
        // Draw AUTO button
        let autoState: ButtonState = isAuto ? .active : .normal
        renderer.drawButton(.eqAuto, state: autoState,
                           at: SkinElements.Equalizer.Positions.autoButton, in: context)
        
        // Draw PRESETS button
        let presetsState: ButtonState = pressedButton == .eqPresets ? .pressed : .normal
        renderer.drawButton(.eqPresets, state: presetsState,
                           at: SkinElements.Equalizer.Positions.presetsButton, in: context)
        
        // Draw preamp slider
        renderer.drawEQSlider(bandIndex: -1, value: CGFloat(preamp), isPreamp: true, in: context)
        
        // Draw EQ band sliders
        for i in 0..<10 {
            renderer.drawEQSlider(bandIndex: i, value: CGFloat(bands[i]), isPreamp: false, in: context)
        }
        
        // Draw EQ curve graph
        drawEQGraph(context: context)
    }
    
    private func drawEQGraph(context: CGContext) {
        let rect = Layout.graphRect
        
        // Background
        NSColor.black.setFill()
        context.fill(rect)
        
        // Grid lines
        NSColor(calibratedWhite: 0.2, alpha: 1.0).setStroke()
        context.setLineWidth(0.5)
        
        // Horizontal center line (0 dB)
        context.move(to: CGPoint(x: rect.minX, y: rect.midY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        context.strokePath()
        
        // Draw EQ curve with colors matching band values
        if isEnabled {
            context.setLineWidth(1.0)
            
            // Calculate all points first
            var points: [(x: CGFloat, y: CGFloat, value: Float)] = []
            for i in 0..<10 {
                let x = rect.minX + (rect.width / 9) * CGFloat(i)
                let normalizedValue = (bands[i] + 12) / 24  // 0 = -12dB, 1 = +12dB
                let y = rect.minY + rect.height * (1.0 - CGFloat(normalizedValue))
                points.append((x: x, y: y, value: bands[i]))
            }
            
            // Draw line segments with colors based on the average value of each segment
            for i in 0..<(points.count - 1) {
                let startPoint = points[i]
                let endPoint = points[i + 1]
                
                // Use average value of the two endpoints for segment color
                let avgValue = (startPoint.value + endPoint.value) / 2
                let color = eqValueToColor(avgValue)
                
                color.setStroke()
                context.move(to: CGPoint(x: startPoint.x, y: startPoint.y))
                context.addLine(to: CGPoint(x: endPoint.x, y: endPoint.y))
                context.strokePath()
            }
        }
        
        // Border
        NSColor.gray.setStroke()
        context.stroke(rect)
    }
    
    /// Convert EQ band value (-12 to +12) to color using the same scale as slider bars
    /// +12dB (top) = RED, 0dB (middle) = YELLOW, -12dB (bottom) = GREEN
    private func eqValueToColor(_ value: Float) -> NSColor {
        // Normalize to 0-1 range (0 = -12dB, 1 = +12dB)
        let normalized = CGFloat((value + 12) / 24)
        
        // Color stops: green (bottom/-12dB) → yellow (middle/0dB) → red (top/+12dB)
        let colorStops: [(position: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)] = [
            (0.0, 0.0, 0.85, 0.0),    // Green at -12dB
            (0.33, 0.5, 0.85, 0.0),   // Yellow-green
            (0.5, 0.85, 0.85, 0.0),   // Yellow at 0dB
            (0.66, 0.85, 0.5, 0.0),   // Orange
            (1.0, 0.85, 0.15, 0.0),   // Red at +12dB
        ]
        
        // Find the two stops we're between
        var lowerStop = colorStops[0]
        var upperStop = colorStops[colorStops.count - 1]
        
        for i in 0..<colorStops.count - 1 {
            if normalized >= colorStops[i].position && normalized <= colorStops[i + 1].position {
                lowerStop = colorStops[i]
                upperStop = colorStops[i + 1]
                break
            }
        }
        
        // Interpolate
        let range = upperStop.position - lowerStop.position
        let factor = range > 0 ? (normalized - lowerStop.position) / range : 0
        
        return NSColor(
            calibratedRed: lowerStop.r + (upperStop.r - lowerStop.r) * factor,
            green: lowerStop.g + (upperStop.g - lowerStop.g) * factor,
            blue: lowerStop.b + (upperStop.b - lowerStop.b) * factor,
            alpha: 1.0
        )
    }
    
    // MARK: - Public Methods
    
    func skinDidChange() {
        needsDisplay = true
    }
    
    /// Set shade mode externally (e.g., from controller)
    func setShadeMode(_ enabled: Bool) {
        isShadeMode = enabled
        needsDisplay = true
    }
    
    /// Toggle shade mode
    private func toggleShadeMode() {
        isShadeMode.toggle()
        controller?.setShadeMode(isShadeMode)
    }
    
    // MARK: - Mouse Events
    
    /// Track if we're dragging the window (not a slider)
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    
    /// Allow clicking even when window is not active (click-through)
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = convertToOriginalCoordinates(viewPoint)
        let winampPoint = NSPoint(x: point.x, y: originalWindowSize.height - point.y)
        
        // Check for double-click on title bar to toggle shade mode
        if event.clickCount == 2 {
            if winampPoint.y < Layout.titleBarHeight && winampPoint.x < bounds.width - 30 {
                toggleShadeMode()
                return
            }
        }
        
        if isShadeMode {
            handleShadeMouseDown(at: winampPoint, event: event)
            return
        }
        
        // Window dragging is handled by macOS via isMovableByWindowBackground
        
        // Close button
        if Layout.closeRect.contains(winampPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        // Shade button (toggle compact mode)
        if Layout.shadeRect.contains(winampPoint) {
            pressedButton = .shade
            needsDisplay = true
            return
        }
        
        // Toggle buttons
        if Layout.onOffRect.contains(winampPoint) {
            isEnabled.toggle()
            WindowManager.shared.audioEngine.setEQEnabled(isEnabled)
            needsDisplay = true
            return
        }
        
        if Layout.autoRect.contains(winampPoint) {
            isAuto.toggle()
            needsDisplay = true
            return
        }
        
        if Layout.presetsRect.contains(winampPoint) {
            pressedButton = .eqPresets
            needsDisplay = true
            return
        }
        
        // Check sliders - if we hit a slider, start dragging slider
        if let sliderIndex = hitTestSlider(at: winampPoint) {
            draggingSlider = sliderIndex
            updateSlider(at: winampPoint)
            return
        }
        
        // Not on any control - start window drag
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
    }
    
    /// Handle mouse down in shade mode
    private func handleShadeMouseDown(at winampPoint: NSPoint, event: NSEvent) {
        // Check window control buttons
        let closeRect = SkinElements.EQShade.Positions.closeButton
        let shadeRect = SkinElements.EQShade.Positions.shadeButton
        
        if closeRect.contains(winampPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        if shadeRect.contains(winampPoint) {
            pressedButton = .unshade
            needsDisplay = true
            return
        }
        
        // Window dragging is handled by macOS via isMovableByWindowBackground
    }
    
    override func mouseDragged(with event: NSEvent) {
        // Handle slider dragging
        if draggingSlider != nil {
            let viewPoint = convert(event.locationInWindow, from: nil)
            let point = convertToOriginalCoordinates(viewPoint)
            let winampPoint = NSPoint(x: point.x, y: originalWindowSize.height - point.y)
            updateSlider(at: winampPoint)
            return
        }
        
        // Handle window dragging
        if isDraggingWindow, let window = window {
            let currentPoint = event.locationInWindow
            let deltaX = currentPoint.x - windowDragStartPoint.x
            let deltaY = currentPoint.y - windowDragStartPoint.y
            
            var newOrigin = window.frame.origin
            newOrigin.x += deltaX
            newOrigin.y += deltaY
            
            // Use WindowManager for snapping behavior
            newOrigin = WindowManager.shared.windowWillMove(window, to: newOrigin)
            window.setFrameOrigin(newOrigin)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = convertToOriginalCoordinates(viewPoint)
        let winampPoint = NSPoint(x: point.x, y: originalWindowSize.height - point.y)
        
        if isShadeMode {
            // Handle shade mode button release
            if let pressed = pressedButton {
                var shouldPerform = false
                
                switch pressed {
                case .close:
                    shouldPerform = SkinElements.EQShade.Positions.closeButton.contains(winampPoint)
                    if shouldPerform {
                        window?.close()
                    }
                case .unshade:
                    shouldPerform = SkinElements.EQShade.Positions.shadeButton.contains(winampPoint)
                    if shouldPerform {
                        toggleShadeMode()
                    }
                default:
                    break
                }
                
                pressedButton = nil
                needsDisplay = true
            }
            return
        }
        
        // Handle button releases in normal mode
        if let pressed = pressedButton {
            switch pressed {
            case .close:
                if Layout.closeRect.contains(winampPoint) {
                    window?.close()
                }
            case .shade:
                if Layout.shadeRect.contains(winampPoint) {
                    toggleShadeMode()
                }
            case .eqPresets:
                if Layout.presetsRect.contains(winampPoint) {
                    showPresetsMenu(at: point)
                }
            default:
                break
            }
            pressedButton = nil
            needsDisplay = true
        }
        
        draggingSlider = nil
        if isDraggingWindow {
            isDraggingWindow = false
            if let window = window {
                WindowManager.shared.windowDidFinishDragging(window)
            }
        }
    }
    
    private func hitTestSlider(at point: NSPoint) -> Int? {
        // Check preamp (Winamp coordinates - y increases downward)
        let preampRect = Layout.preampRect
        if point.x >= preampRect.minX && point.x <= preampRect.maxX &&
           point.y >= preampRect.minY && point.y <= preampRect.minY + preampRect.height {
            return -1
        }
        
        // Check bands
        for i in 0..<10 {
            let rect = NSRect(
                x: Layout.bandStartX + CGFloat(i) * Layout.bandSpacing,
                y: Layout.bandY,
                width: Layout.bandWidth,
                height: Layout.bandHeight
            )
            
            if point.x >= rect.minX && point.x <= rect.maxX &&
               point.y >= rect.minY && point.y <= rect.minY + rect.height {
                return i
            }
        }
        
        return nil
    }
    
    private func updateSlider(at point: NSPoint) {
        guard let index = draggingSlider else { return }
        
        let rect: NSRect
        if index == -1 {
            rect = Layout.preampRect
        } else {
            rect = NSRect(
                x: Layout.bandStartX + CGFloat(index) * Layout.bandSpacing,
                y: Layout.bandY,
                width: Layout.bandWidth,
                height: Layout.bandHeight
            )
        }
        
        // Calculate value from position (Winamp coordinates - y=0 at top)
        // Bottom of slider = +12dB, Top of slider = -12dB
        let normalizedY = 1.0 - (point.y - rect.minY) / rect.height
        let clampedY = max(0, min(1, normalizedY))
        let value = Float(clampedY) * 24 - 12  // 0..1 to -12..+12
        
        // Apply to audio engine
        if index == -1 {
            preamp = value
            WindowManager.shared.audioEngine.setPreamp(value)
        } else {
            bands[index] = value
            WindowManager.shared.audioEngine.setEQBand(index, gain: value)
        }
        
        needsDisplay = true
    }
    
    private func showPresetsMenu(at point: NSPoint) {
        let menu = NSMenu()
        
        for preset in EQPreset.allPresets {
            let item = NSMenuItem(title: preset.name, action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            menu.addItem(item)
        }
        
        menu.popUp(positioning: nil, at: point, in: self)
    }
    
    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? EQPreset else { return }
        
        preamp = preset.preamp
        bands = preset.bands
        
        // Apply to audio engine
        WindowManager.shared.audioEngine.setPreamp(preset.preamp)
        for (index, gain) in preset.bands.enumerated() {
            WindowManager.shared.audioEngine.setEQBand(index, gain: gain)
        }
        
        needsDisplay = true
    }
    
    // MARK: - Context Menu
    
    override func menu(for event: NSEvent) -> NSMenu? {
        return ContextMenuBuilder.buildMenu()
    }
}
