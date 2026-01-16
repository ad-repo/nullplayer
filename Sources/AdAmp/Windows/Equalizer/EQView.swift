import AppKit

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
    private var isDragging = false
    private var dragStartPoint: NSPoint = .zero
    
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
        
        // Close button
        static let closeRect = NSRect(x: 264, y: 3, width: 9, height: 9)
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
    }
    
    private func loadCurrentEQState() {
        let engine = WindowManager.shared.audioEngine
        preamp = engine.getPreamp()
        for i in 0..<10 {
            bands[i] = engine.getEQBand(i)
        }
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Flip coordinate system to match Winamp's top-down coordinates
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        
        let skin = WindowManager.shared.currentSkin
        let renderer = SkinRenderer(skin: skin ?? SkinLoader.shared.loadDefault())
        
        let isActive = window?.isKeyWindow ?? true
        
        if isShadeMode {
            // Draw shade mode
            renderer.drawEqualizerShade(in: context, bounds: bounds, isActive: isActive, pressedButton: pressedButton)
        } else {
            // Draw normal mode
            drawNormalMode(renderer: renderer, context: context, isActive: isActive)
        }
        
        context.restoreGState()
    }
    
    /// Draw normal (non-shade) mode
    private func drawNormalMode(renderer: SkinRenderer, context: CGContext, isActive: Bool) {
        // Draw EQ background
        renderer.drawEqualizerBackground(in: context, bounds: bounds, isActive: isActive)
        
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
        
        // Draw EQ curve
        if isEnabled {
            NSColor.green.setStroke()
            context.setLineWidth(1.0)
            
            let path = NSBezierPath()
            
            for i in 0..<10 {
                let x = rect.minX + (rect.width / 9) * CGFloat(i)
                let normalizedValue = (bands[i] + 12) / 24
                let y = rect.minY + rect.height * CGFloat(normalizedValue)
                
                if i == 0 {
                    path.move(to: NSPoint(x: x, y: y))
                } else {
                    path.line(to: NSPoint(x: x, y: y))
                }
            }
            
            path.stroke()
        }
        
        // Border
        NSColor.gray.setStroke()
        context.stroke(rect)
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
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let winampPoint = NSPoint(x: point.x, y: bounds.height - point.y)
        
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
        
        // Check title bar for dragging
        if winampPoint.y < Layout.titleBarHeight && winampPoint.x < bounds.width - 15 {
            isDragging = true
            dragStartPoint = event.locationInWindow
            // Notify WindowManager that dragging is starting
            if let window = window {
                WindowManager.shared.windowWillStartDragging(window)
            }
            return
        }
        
        // Close button
        if Layout.closeRect.contains(winampPoint) {
            window?.close()
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
        
        // Check sliders
        if let sliderIndex = hitTestSlider(at: winampPoint) {
            draggingSlider = sliderIndex
            updateSlider(at: winampPoint)
        }
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
        
        // Otherwise, start dragging
        isDragging = true
        dragStartPoint = event.locationInWindow
        // Notify WindowManager that dragging is starting
        if let window = window {
            WindowManager.shared.windowWillStartDragging(window)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        if isDragging {
            guard let window = window else { return }
            let currentPoint = event.locationInWindow
            let delta = NSPoint(
                x: currentPoint.x - dragStartPoint.x,
                y: currentPoint.y - dragStartPoint.y
            )
            
            var newOrigin = window.frame.origin
            newOrigin.x += delta.x
            newOrigin.y += delta.y
            
            newOrigin = WindowManager.shared.windowWillMove(window, to: newOrigin)
            window.setFrameOrigin(newOrigin)
            return
        }
        
        if draggingSlider != nil {
            let point = convert(event.locationInWindow, from: nil)
            let winampPoint = NSPoint(x: point.x, y: bounds.height - point.y)
            updateSlider(at: winampPoint)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let winampPoint = NSPoint(x: point.x, y: bounds.height - point.y)
        
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
            
            isDragging = false
            return
        }
        
        // Handle presets button release
        if pressedButton == .eqPresets {
            if Layout.presetsRect.contains(winampPoint) {
                showPresetsMenu(at: point)
            }
            pressedButton = nil
            needsDisplay = true
        }
        
        if isDragging {
            // Notify WindowManager that dragging has ended
            if let window = window {
                WindowManager.shared.windowDidFinishDragging(window)
            }
        }
        isDragging = false
        draggingSlider = nil
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
}
