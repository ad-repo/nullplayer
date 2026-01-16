import AppKit

/// Equalizer view - 10-band graphic equalizer
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
    
    // MARK: - Layout
    
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
        
        let skin = WindowManager.shared.currentSkin
        
        // Draw background
        if let eqImage = skin?.eqmain {
            drawImage(eqImage, in: bounds, context: context)
        } else {
            drawDefaultBackground(context: context)
        }
        
        // Draw title bar
        drawTitleBar(context: context)
        
        // Draw toggle buttons
        drawToggleButtons(context: context)
        
        // Draw preamp slider
        drawPreampSlider(context: context)
        
        // Draw EQ band sliders
        drawBandSliders(context: context)
        
        // Draw EQ curve graph
        drawEQGraph(context: context)
    }
    
    private func drawDefaultBackground(context: CGContext) {
        // Dark background
        NSColor(calibratedWhite: 0.15, alpha: 1.0).setFill()
        context.fill(bounds)
    }
    
    private func drawTitleBar(context: CGContext) {
        let titleRect = NSRect(x: 0, y: bounds.height - Layout.titleBarHeight,
                               width: bounds.width, height: Layout.titleBarHeight)
        
        // Gradient title bar
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.4, alpha: 1.0),
            NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.2, alpha: 1.0)
        ])
        gradient?.draw(in: titleRect, angle: 90)
        
        // Title text
        let title = "EQUALIZER"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.boldSystemFont(ofSize: 8)
        ]
        let titleSize = title.size(withAttributes: attrs)
        let titlePoint = NSPoint(x: 6, y: bounds.height - Layout.titleBarHeight + 2)
        title.draw(at: titlePoint, withAttributes: attrs)
        
        // Close button
        NSColor.red.withAlphaComponent(0.8).setFill()
        context.fillEllipse(in: Layout.closeRect)
    }
    
    private func drawToggleButtons(context: CGContext) {
        // ON/OFF button
        drawToggleButton(
            in: Layout.onOffRect,
            title: "ON",
            isActive: isEnabled,
            context: context
        )
        
        // AUTO button
        drawToggleButton(
            in: Layout.autoRect,
            title: "AUTO",
            isActive: isAuto,
            context: context
        )
        
        // PRESETS button
        drawButton(
            in: Layout.presetsRect,
            title: "PRESETS",
            context: context
        )
    }
    
    private func drawToggleButton(in rect: NSRect, title: String, isActive: Bool, context: CGContext) {
        // Background
        let bgColor = isActive ? NSColor.green.withAlphaComponent(0.3) : NSColor(calibratedWhite: 0.2, alpha: 1.0)
        bgColor.setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        path.fill()
        
        // Border
        let borderColor = isActive ? NSColor.green : NSColor.gray
        borderColor.setStroke()
        path.stroke()
        
        // Text
        let textColor = isActive ? NSColor.green : NSColor.gray
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .font: NSFont.boldSystemFont(ofSize: 7)
        ]
        let textSize = title.size(withAttributes: attrs)
        let textPoint = NSPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
        )
        title.draw(at: textPoint, withAttributes: attrs)
    }
    
    private func drawButton(in rect: NSRect, title: String, context: CGContext) {
        // Background
        NSColor(calibratedWhite: 0.2, alpha: 1.0).setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        path.fill()
        
        // Border
        NSColor.gray.setStroke()
        path.stroke()
        
        // Text
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.lightGray,
            .font: NSFont.systemFont(ofSize: 7)
        ]
        let textSize = title.size(withAttributes: attrs)
        let textPoint = NSPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
        )
        title.draw(at: textPoint, withAttributes: attrs)
    }
    
    private func drawPreampSlider(context: CGContext) {
        drawSlider(
            in: Layout.preampRect,
            value: preamp,
            label: "PRE",
            context: context
        )
    }
    
    private func drawBandSliders(context: CGContext) {
        for i in 0..<10 {
            let rect = NSRect(
                x: Layout.bandStartX + CGFloat(i) * Layout.bandSpacing,
                y: Layout.bandY,
                width: Layout.bandWidth,
                height: Layout.bandHeight
            )
            
            drawSlider(
                in: rect,
                value: bands[i],
                label: Layout.frequencies[i],
                context: context
            )
        }
    }
    
    private func drawSlider(in rect: NSRect, value: Float, label: String, context: CGContext) {
        // Track background
        let trackRect = NSRect(x: rect.midX - 2, y: rect.minY, width: 4, height: rect.height)
        NSColor(calibratedWhite: 0.1, alpha: 1.0).setFill()
        context.fill(trackRect)
        
        // Center line (0 dB)
        NSColor.gray.setStroke()
        let centerY = rect.midY
        context.move(to: CGPoint(x: rect.minX, y: centerY))
        context.addLine(to: CGPoint(x: rect.maxX, y: centerY))
        context.strokePath()
        
        // Slider thumb position
        let normalizedValue = (value + 12) / 24  // -12..+12 to 0..1
        let thumbY = rect.minY + rect.height * CGFloat(normalizedValue)
        let thumbRect = NSRect(x: rect.minX, y: thumbY - 5, width: rect.width, height: 10)
        
        // Draw fill from center to thumb
        let fillColor = value >= 0 ? NSColor.green : NSColor.orange
        fillColor.withAlphaComponent(0.5).setFill()
        
        if value >= 0 {
            let fillRect = NSRect(x: rect.midX - 2, y: centerY, width: 4, height: thumbY - centerY)
            context.fill(fillRect)
        } else {
            let fillRect = NSRect(x: rect.midX - 2, y: thumbY, width: 4, height: centerY - thumbY)
            context.fill(fillRect)
        }
        
        // Thumb
        fillColor.setFill()
        let thumbPath = NSBezierPath(roundedRect: thumbRect, xRadius: 2, yRadius: 2)
        thumbPath.fill()
        
        // Label
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.gray,
            .font: NSFont.systemFont(ofSize: 6)
        ]
        let labelSize = label.size(withAttributes: attrs)
        let labelPoint = NSPoint(
            x: rect.midX - labelSize.width / 2,
            y: rect.minY - 10
        )
        label.draw(at: labelPoint, withAttributes: attrs)
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
    
    private func drawImage(_ image: NSImage, in rect: NSRect, context: CGContext) {
        image.draw(in: rect,
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: 1.0)
    }
    
    // MARK: - Mouse Events
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // Check title bar for dragging
        let titleRect = NSRect(x: 0, y: bounds.height - Layout.titleBarHeight,
                               width: bounds.width - 15, height: Layout.titleBarHeight)
        
        if titleRect.contains(point) {
            isDragging = true
            dragStartPoint = event.locationInWindow
            return
        }
        
        // Close button
        if Layout.closeRect.contains(point) {
            window?.close()
            return
        }
        
        // Toggle buttons
        if Layout.onOffRect.contains(point) {
            isEnabled.toggle()
            WindowManager.shared.audioEngine.setEQEnabled(isEnabled)
            needsDisplay = true
            return
        }
        
        if Layout.autoRect.contains(point) {
            isAuto.toggle()
            needsDisplay = true
            return
        }
        
        if Layout.presetsRect.contains(point) {
            showPresetsMenu(at: point)
            return
        }
        
        // Check sliders
        if let sliderIndex = hitTestSlider(at: point) {
            draggingSlider = sliderIndex
            updateSlider(at: point)
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
            updateSlider(at: point)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        draggingSlider = nil
    }
    
    private func hitTestSlider(at point: NSPoint) -> Int? {
        // Check preamp
        if Layout.preampRect.contains(point) {
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
            
            if rect.contains(point) {
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
        
        // Calculate value from position
        let normalizedY = (point.y - rect.minY) / rect.height
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
