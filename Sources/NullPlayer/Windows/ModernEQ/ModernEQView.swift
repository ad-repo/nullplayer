import AppKit

// =============================================================================
// MODERN EQ VIEW - Equalizer with modern skin chrome
// =============================================================================
// Renders a 10-band graphic equalizer with preamp, ON/OFF toggle, AUTO toggle,
// PRESETS menu, EQ curve graph, and frequency labels using the modern skin system.
//
// Color scale for sliders and graph curve:
// - RED at top (+12dB boost)
// - YELLOW at middle (0dB)
// - GREEN at bottom (-12dB cut)
//
// Has ZERO dependencies on the classic skin system (Skin/, SkinElements, SkinRenderer, etc.).
// =============================================================================

/// Modern equalizer view with full modern skin support
class ModernEQView: NSView {
    
    // MARK: - Properties
    
    weak var controller: ModernEQWindowController?
    
    /// The skin renderer
    private var renderer: ModernSkinRenderer!
    
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
    
    /// Button being pressed (for visual feedback)
    private var pressedButton: String?
    
    /// Window dragging state
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    
    /// Shade mode state
    private(set) var isShadeMode = false
    
    /// Scale factor for layout
    private let scale = ModernSkinElements.scaleFactor
    
    // MARK: - Layout Constants
    
    private var titleBarHeight: CGFloat { ModernSkinElements.eqTitleBarHeight }
    private var borderWidth: CGFloat { ModernSkinElements.eqBorderWidth }
    
    /// Frequency labels for the 10 bands
    private let frequencies = ["60", "170", "310", "600", "1K", "3K", "6K", "12K", "14K", "16K"]
    
    // Layout matching classic EQ (macOS bottom-left origin, Y increases upward)
    //
    // Visual layout (top to bottom on screen = high Y to low Y):
    //   title bar
    //   [ON] [AUTO]  [PRESETS]   <- button row
    //   [--- EQ curve graph ---] <- full-width graph
    //   sliders (preamp + 10 bands)
    //   frequency labels
    //   border
    
    /// Button row height
    private var btnHeight: CGFloat { 12 * scale }
    
    /// Button row Y (just below title bar)
    private var buttonRowY: CGFloat { bounds.height - titleBarHeight - 2 * scale - btnHeight }
    
    /// Graph height
    private var graphHeight: CGFloat { 20 * scale }
    
    /// Graph Y (below button row)
    private var graphY: CGFloat { buttonRowY - 2 * scale - graphHeight }
    
    /// Graph area rect (full width below buttons)
    private var graphRect: NSRect {
        let graphX = borderWidth + 4 * scale
        let graphWidth = bounds.width - graphX - borderWidth - 4 * scale
        return NSRect(x: graphX, y: graphY, width: graphWidth, height: graphHeight)
    }
    
    /// Slider area top Y (below graph)
    private var sliderTopY: CGFloat { graphY - 2 * scale }
    
    /// Frequency label height
    private var freqLabelHeight: CGFloat { 8 * scale }
    
    /// Slider bottom Y (above freq labels)
    private var sliderBottomY: CGFloat { borderWidth + 2 * scale + freqLabelHeight + 1 * scale }
    
    /// Frequency label Y (bottom, above border)
    private var freqLabelY: CGFloat { borderWidth + 2 * scale }
    
    /// Slider height
    private var sliderHeight: CGFloat { sliderTopY - sliderBottomY }
    
    /// Preamp slider X position
    private var preampX: CGFloat { borderWidth + 8 * scale }
    
    /// Preamp slider width
    private var sliderWidth: CGFloat { 12 * scale }
    
    /// Band sliders start X
    private var bandStartX: CGFloat { borderWidth + 46 * scale }
    
    /// Band spacing
    private var bandSpacing: CGFloat {
        let availableWidth = bounds.width - bandStartX - borderWidth - 4 * scale
        return availableWidth / 10
    }
    
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
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        
        // Initialize with current skin
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)
        
        // Load current EQ state from audio engine
        loadCurrentEQState()
        
        // Observe skin changes
        NotificationCenter.default.addObserver(self, selector: #selector(modernSkinDidChange),
                                                name: ModernSkinEngine.skinDidChangeNotification, object: nil)
        
        // Observe track changes for Auto EQ
        NotificationCenter.default.addObserver(self, selector: #selector(handleTrackChange(_:)),
                                                name: .audioTrackDidChange, object: nil)
        
        // Set accessibility
        setAccessibilityIdentifier("modernEqualizerView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("Equalizer")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - EQ State
    
    private func loadCurrentEQState() {
        let engine = WindowManager.shared.audioEngine
        
        // Load EQ enabled state from engine
        isEnabled = engine.isEQEnabled()
        
        // Load Auto EQ state from UserDefaults only if "Remember State" is enabled
        if AppStateManager.shared.isEnabled {
            isAuto = UserDefaults.standard.bool(forKey: "EQAutoEnabled")
        } else {
            isAuto = false
        }
        
        // Load preamp and band values
        preamp = engine.getPreamp()
        for i in 0..<10 {
            bands[i] = engine.getEQBand(i)
        }
        
        // If Auto EQ is enabled and a track is already playing, apply the genre preset
        if isAuto {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.applyAutoEQForCurrentTrack()
            }
        }
    }
    
    /// Apply an EQ preset (updates UI and audio engine)
    private func applyPreset(_ preset: EQPreset) {
        preamp = preset.preamp
        bands = preset.bands
        
        // Apply to audio engine
        WindowManager.shared.audioEngine.setPreamp(preset.preamp)
        for (index, gain) in preset.bands.enumerated() {
            WindowManager.shared.audioEngine.setEQBand(index, gain: gain)
        }
        
        needsDisplay = true
    }
    
    // MARK: - Auto EQ
    
    @objc private func handleTrackChange(_ notification: Notification) {
        applyAutoEQForCurrentTrack()
    }
    
    private func applyAutoEQForCurrentTrack() {
        guard isAuto else { return }
        
        guard let track = WindowManager.shared.audioEngine.currentTrack else {
            NSLog("Auto EQ: No track currently playing")
            return
        }
        
        if let genre = track.genre {
            applyPresetForGenre(genre)
            return
        }
        
        // For Plex tracks without genre, try to fetch it from the server
        if let ratingKey = track.plexRatingKey {
            NSLog("Auto EQ: Track '%@' has no genre, fetching from Plex...", track.title)
            Task {
                await fetchAndApplyPlexGenre(ratingKey: ratingKey, trackTitle: track.title)
            }
            return
        }
        
        // For Subsonic tracks without genre, try to fetch it
        if let subsonicId = track.subsonicId {
            NSLog("Auto EQ: Track '%@' has no genre, fetching from Subsonic...", track.title)
            Task {
                await fetchAndApplySubsonicGenre(songId: subsonicId, trackTitle: track.title)
            }
            return
        }
        
        NSLog("Auto EQ: Track '%@' has no genre metadata", track.title)
    }
    
    private func applyPresetForGenre(_ genre: String) {
        guard let preset = EQPreset.forGenre(genre) else {
            NSLog("Auto EQ: No preset match for genre '%@'", genre)
            return
        }
        
        NSLog("Auto EQ: Applying '%@' preset for genre '%@'", preset.name, genre)
        
        if !isEnabled {
            isEnabled = true
            WindowManager.shared.audioEngine.setEQEnabled(true)
        }
        
        applyPreset(preset)
    }
    
    private func fetchAndApplyPlexGenre(ratingKey: String, trackTitle: String) async {
        guard let client = PlexManager.shared.serverClient else { return }
        
        do {
            if let detailedTrack = try await client.fetchTrackDetails(trackID: ratingKey),
               let genre = detailedTrack.genre {
                await MainActor.run {
                    NSLog("Auto EQ: Fetched genre '%@' for '%@'", genre, trackTitle)
                    self.applyPresetForGenre(genre)
                }
            } else {
                NSLog("Auto EQ: Plex track '%@' has no genre even in detailed metadata", trackTitle)
            }
        } catch {
            NSLog("Auto EQ: Failed to fetch Plex track details: %@", error.localizedDescription)
        }
    }
    
    private func fetchAndApplySubsonicGenre(songId: String, trackTitle: String) async {
        guard let client = SubsonicManager.shared.serverClient else { return }
        
        do {
            if let song = try await client.fetchSong(id: songId),
               let genre = song.genre {
                await MainActor.run {
                    NSLog("Auto EQ: Fetched genre '%@' for '%@'", genre, trackTitle)
                    self.applyPresetForGenre(genre)
                }
            } else {
                NSLog("Auto EQ: Subsonic track '%@' has no genre", trackTitle)
            }
        } catch {
            NSLog("Auto EQ: Failed to fetch Subsonic song details: %@", error.localizedDescription)
        }
    }
    
    // MARK: - Notification Handlers
    
    @objc private func modernSkinDidChange() {
        skinDidChange()
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Draw window background
        renderer.drawWindowBackground(in: bounds, context: context)
        
        // Draw window border with glow
        renderer.drawWindowBorder(in: bounds, context: context)
        
        // Draw title bar
        renderer.drawTitleBar(in: titleBarBaseRect, title: "NULLPLAYER EQUALIZER", context: context)
        
        // Draw close button
        let closeState = (pressedButton == "eq_btn_close") ? "pressed" : "normal"
        renderer.drawWindowControlButton("eq_btn_close", state: closeState,
                                         in: closeBtnBaseRect, context: context)
        
        // Draw shade button
        let shadeState = (pressedButton == "eq_btn_shade") ? "pressed" : "normal"
        renderer.drawWindowControlButton("eq_btn_shade", state: shadeState,
                                         in: shadeBtnBaseRect, context: context)
        
        if isShadeMode {
            return
        }
        
        // Draw EQ content
        drawEQContent(in: context)
    }
    
    /// Base rects in the 275x116 coordinate space (renderer scales them)
    private var titleBarBaseRect: NSRect {
        return NSRect(x: 0, y: (bounds.height / scale) - 14, width: 275, height: 14)
    }
    
    private var closeBtnBaseRect: NSRect {
        return NSRect(x: 256, y: (bounds.height / scale) - 12, width: 10, height: 10)
    }
    
    private var shadeBtnBaseRect: NSRect {
        return NSRect(x: 244, y: (bounds.height / scale) - 12, width: 10, height: 10)
    }
    
    // MARK: - EQ Content Drawing
    
    private func drawEQContent(in context: CGContext) {
        let skin = renderer.skin
        let font = skin.smallFont?.withSize(7 * scale) ?? NSFont.monospacedSystemFont(ofSize: 7 * scale, weight: .regular)
        let tinyFont = skin.smallFont?.withSize(6 * scale) ?? NSFont.monospacedSystemFont(ofSize: 6 * scale, weight: .regular)
        
        // == 1. Sliders (clip so glow doesn't bleed up) ==
        let preampCenterX = preampX + sliderWidth / 2
        
        context.saveGState()
        context.clip(to: NSRect(x: 0, y: 0, width: bounds.width, height: sliderTopY))
        
        // Preamp slider
        drawSlider(index: -1, x: preampX, context: context)
        
        // Separator line between preamp and bands
        let sepX = bandStartX - 5 * scale
        context.saveGState()
        context.setShadow(offset: .zero, blur: 3 * scale,
                          color: skin.primaryColor.withAlphaComponent(0.3).cgColor)
        context.setStrokeColor(skin.primaryColor.withAlphaComponent(0.2).cgColor)
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: sepX, y: sliderBottomY))
        context.addLine(to: CGPoint(x: sepX, y: sliderTopY))
        context.strokePath()
        context.restoreGState()
        
        // 10 band sliders
        for i in 0..<10 {
            let x = bandStartX + CGFloat(i) * bandSpacing
            drawSlider(index: i, x: x, context: context)
        }
        
        context.restoreGState() // end slider clip
        
        // == 2. Button row + EQ graph (same horizontal strip, on top of everything) ==
        let btnY = buttonRowY
        
        // ON/OFF button (left side)
        let onOffX = borderWidth + 4 * scale
        let onOffWidth: CGFloat = 26 * scale
        drawToggleButton(label: "ON", isActive: isEnabled,
                         rect: NSRect(x: onOffX, y: btnY, width: onOffWidth, height: btnHeight),
                         font: font, context: context)
        
        // AUTO button
        let autoX = onOffX + onOffWidth + 3 * scale
        let autoWidth: CGFloat = 34 * scale
        drawToggleButton(label: "AUTO", isActive: isAuto,
                         rect: NSRect(x: autoX, y: btnY, width: autoWidth, height: btnHeight),
                         font: font, context: context)
        
        // PRESETS button (right side)
        let presetsWidth: CGFloat = 48 * scale
        let presetsX = bounds.width - borderWidth - presetsWidth - 4 * scale
        let isPresetsPressed = pressedButton == "eq_presets"
        drawPushButton(label: "PRESETS", isPressed: isPresetsPressed,
                       rect: NSRect(x: presetsX, y: btnY, width: presetsWidth, height: btnHeight),
                       font: font, context: context)
        
        // EQ curve graph (between AUTO and PRESETS)
        drawEQGraph(context: context)
        
        // == 3. Frequency labels (bottom) ==
        // PRE dB value under preamp
        let dbValue = String(format: "%+.0f", preamp)
        drawGlowText(dbValue, at: NSPoint(x: preampCenterX, y: freqLabelY + freqLabelHeight / 2),
                     font: tinyFont, color: eqValueToColor(preamp), glow: true, context: context)
        
        // Band frequency labels
        for i in 0..<10 {
            let x = bandStartX + CGFloat(i) * bandSpacing
            let sliderCenterX = x + sliderWidth / 2
            drawGlowText(frequencies[i], at: NSPoint(x: sliderCenterX, y: freqLabelY + freqLabelHeight / 2),
                         font: tinyFont, color: skin.primaryColor.withAlphaComponent(0.5), glow: false, context: context)
        }
    }
    
    // MARK: - Glow Text Helper
    
    private func drawGlowText(_ text: String, at center: NSPoint, font: NSFont,
                               color: NSColor, glow: Bool, context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        
        if glow {
            context.saveGState()
            context.setShadow(offset: .zero, blur: 4 * scale,
                              color: color.withAlphaComponent(0.8).cgColor)
            str.draw(at: origin)
            context.restoreGState()
        }
        str.draw(at: origin)
    }
    
    // MARK: - Toggle/Push Button Drawing
    
    private func drawToggleButton(label: String, isActive: Bool, rect: NSRect,
                                   font: NSFont, context: CGContext) {
        let skin = renderer.skin
        let color = isActive ? skin.accentColor : skin.textDimColor
        
        context.saveGState()
        
        if isActive {
            // Glowing active state
            context.setFillColor(skin.accentColor.withAlphaComponent(0.12).cgColor)
            context.fill(rect)
            
            // Glow border
            context.setShadow(offset: .zero, blur: 6 * scale,
                              color: skin.accentColor.withAlphaComponent(0.6).cgColor)
            context.setStrokeColor(skin.accentColor.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(1.0)
            context.stroke(rect)
            context.restoreGState()
            
            // Crisp border on top
            context.saveGState()
            context.setStrokeColor(skin.accentColor.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(1.0)
            context.stroke(rect)
        } else {
            // Dim inactive state
            context.setStrokeColor(skin.textDimColor.withAlphaComponent(0.3).cgColor)
            context.setLineWidth(0.5)
            context.stroke(rect)
        }
        context.restoreGState()
        
        // Text with glow when active
        context.saveGState()
        if isActive {
            context.setShadow(offset: .zero, blur: 4 * scale,
                              color: color.withAlphaComponent(0.8).cgColor)
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = NSAttributedString(string: label, attributes: attrs)
        let size = str.size()
        str.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        context.restoreGState()
        if isActive { // second pass for crisp text
            let attrs2: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            NSAttributedString(string: label, attributes: attrs2).draw(
                at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
    }
    
    private func drawPushButton(label: String, isPressed: Bool, rect: NSRect,
                                 font: NSFont, context: CGContext) {
        let skin = renderer.skin
        let color = isPressed ? skin.accentColor : skin.textDimColor
        
        context.saveGState()
        if isPressed {
            context.setFillColor(skin.accentColor.withAlphaComponent(0.15).cgColor)
            context.fill(rect)
            context.setShadow(offset: .zero, blur: 5 * scale,
                              color: skin.accentColor.withAlphaComponent(0.5).cgColor)
        }
        context.setStrokeColor(color.withAlphaComponent(isPressed ? 0.8 : 0.3).cgColor)
        context.setLineWidth(isPressed ? 1.0 : 0.5)
        context.stroke(rect)
        context.restoreGState()
        
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = NSAttributedString(string: label, attributes: attrs)
        let size = str.size()
        str.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }
    
    // MARK: - Slider Drawing
    
    private func drawSlider(index: Int, x: CGFloat, context: CGContext) {
        let value = index == -1 ? preamp : bands[index]
        let skin = renderer.skin
        
        let trackRect = NSRect(x: x, y: sliderBottomY, width: sliderWidth, height: sliderHeight)
        let centerY = trackRect.midY
        let normalizedValue = CGFloat((value + 12) / 24) // 0..1
        let thumbY = sliderBottomY + normalizedValue * sliderHeight
        let fillColor = eqValueToColor(value)
        
        // Track background - deep black
        context.saveGState()
        context.setFillColor(NSColor(calibratedWhite: 0.03, alpha: 1.0).cgColor)
        context.fill(trackRect)
        context.restoreGState()
        
        // Colored fill from center to thumb
        let fillAmount = abs(value)
        if fillAmount > 0.3 {
            let fillRect: NSRect
            if value >= 0 {
                fillRect = NSRect(x: x, y: centerY, width: sliderWidth, height: thumbY - centerY)
            } else {
                fillRect = NSRect(x: x, y: thumbY, width: sliderWidth, height: centerY - thumbY)
            }
            
            // Wide outer bloom
            context.saveGState()
            context.setShadow(offset: .zero, blur: 10 * scale,
                              color: fillColor.withAlphaComponent(0.5).cgColor)
            context.setFillColor(fillColor.withAlphaComponent(0.4).cgColor)
            context.fill(fillRect)
            context.restoreGState()
            
            // Inner fill
            context.saveGState()
            context.setFillColor(fillColor.withAlphaComponent(0.5).cgColor)
            context.fill(fillRect)
            context.restoreGState()
            
            // Hot neon center line through fill
            let lineX = x + sliderWidth / 2
            context.saveGState()
            context.setShadow(offset: .zero, blur: 5 * scale,
                              color: fillColor.withAlphaComponent(1.0).cgColor)
            context.setStrokeColor(fillColor.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(2.0)
            context.move(to: CGPoint(x: lineX, y: fillRect.minY))
            context.addLine(to: CGPoint(x: lineX, y: fillRect.maxY))
            context.strokePath()
            // Second pass for extra brightness
            context.setShadow(offset: .zero, blur: 2 * scale,
                              color: NSColor.white.withAlphaComponent(0.4).cgColor)
            context.setStrokeColor(fillColor.withAlphaComponent(0.7).cgColor)
            context.setLineWidth(1.0)
            context.move(to: CGPoint(x: lineX, y: fillRect.minY))
            context.addLine(to: CGPoint(x: lineX, y: fillRect.maxY))
            context.strokePath()
            context.restoreGState()
        }
        
        // Center line (0 dB) - subtle glow
        context.saveGState()
        context.setShadow(offset: .zero, blur: 3 * scale,
                          color: skin.primaryColor.withAlphaComponent(0.3).cgColor)
        context.setStrokeColor(skin.primaryColor.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: trackRect.minX, y: centerY))
        context.addLine(to: CGPoint(x: trackRect.maxX, y: centerY))
        context.strokePath()
        context.restoreGState()
        
        // === THUMB - the big glowing indicator ===
        let thumbHeight: CGFloat = 4 * scale
        let thumbOverhang: CGFloat = 3 * scale
        let thumbRect = NSRect(x: x - thumbOverhang, y: thumbY - thumbHeight / 2,
                               width: sliderWidth + thumbOverhang * 2, height: thumbHeight)
        
        // Massive outer bloom
        context.saveGState()
        context.setShadow(offset: .zero, blur: 12 * scale,
                          color: fillColor.withAlphaComponent(0.8).cgColor)
        context.setFillColor(fillColor.cgColor)
        context.fill(thumbRect)
        context.restoreGState()
        
        // Second bloom pass for intensity
        context.saveGState()
        context.setShadow(offset: .zero, blur: 6 * scale,
                          color: fillColor.withAlphaComponent(0.9).cgColor)
        context.setFillColor(fillColor.cgColor)
        context.fill(thumbRect)
        context.restoreGState()
        
        // Solid thumb
        context.saveGState()
        context.setFillColor(fillColor.cgColor)
        context.fill(thumbRect)
        context.restoreGState()
        
        // White-hot center highlight
        let hotLine = NSRect(x: thumbRect.minX + 2, y: thumbRect.midY - 0.5,
                             width: thumbRect.width - 4, height: 1.0)
        context.saveGState()
        context.setFillColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        context.fill(hotLine)
        context.restoreGState()
    }
    
    // MARK: - EQ Graph Drawing
    
    private func drawEQGraph(context: CGContext) {
        let rect = graphRect
        let skin = renderer.skin
        
        // Dark recessed background
        context.saveGState()
        context.setFillColor(NSColor(calibratedWhite: 0.01, alpha: 1.0).cgColor)
        context.fill(rect)
        context.restoreGState()
        
        // Glowing border
        context.saveGState()
        context.setShadow(offset: .zero, blur: 4 * scale,
                          color: skin.accentColor.withAlphaComponent(0.3).cgColor)
        context.setStrokeColor(skin.accentColor.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(1.0)
        context.stroke(rect)
        context.restoreGState()
        
        // Always draw the curve (even when flat it shows the center line as the curve)
        let insetRect = rect.insetBy(dx: 2, dy: 2)
        var points: [(x: CGFloat, y: CGFloat)] = []
        for i in 0..<10 {
            let px = insetRect.minX + (insetRect.width / 9) * CGFloat(i)
            let bandValue = isEnabled ? bands[i] : Float(0)
            let normalizedValue = (bandValue + 12) / 24
            let py = insetRect.minY + insetRect.height * CGFloat(normalizedValue)
            points.append((x: px, y: py))
        }
        
        guard points.count >= 2 else { return }
        
        // Build smooth path
        let curvePath = CGMutablePath()
        curvePath.move(to: CGPoint(x: points[0].x, y: points[0].y))
        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            let midX = (prev.x + curr.x) / 2
            curvePath.addCurve(to: CGPoint(x: curr.x, y: curr.y),
                               control1: CGPoint(x: midX, y: prev.y),
                               control2: CGPoint(x: midX, y: curr.y))
        }
        
        // Filled area between curve and center line
        let fillPath = curvePath.mutableCopy()!
        fillPath.addLine(to: CGPoint(x: points.last!.x, y: rect.midY))
        fillPath.addLine(to: CGPoint(x: points.first!.x, y: rect.midY))
        fillPath.closeSubpath()
        
        context.saveGState()
        context.clip(to: rect)
        context.addPath(fillPath)
        context.clip()
        context.setFillColor(skin.accentColor.withAlphaComponent(0.3).cgColor)
        context.fill(rect)
        context.restoreGState()
        
        // Curve - wide glow
        context.saveGState()
        context.clip(to: rect)
        context.setShadow(offset: .zero, blur: 8 * scale,
                          color: skin.accentColor.withAlphaComponent(0.8).cgColor)
        context.setStrokeColor(skin.accentColor.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(2.5 * scale)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.addPath(curvePath)
        context.strokePath()
        context.restoreGState()
        
        // Curve - bright core
        context.saveGState()
        context.clip(to: rect)
        context.setStrokeColor(skin.accentColor.cgColor)
        context.setLineWidth(1.5 * scale)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.addPath(curvePath)
        context.strokePath()
        context.restoreGState()
        
        // White-hot center of curve
        context.saveGState()
        context.clip(to: rect)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(0.5 * scale)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.addPath(curvePath)
        context.strokePath()
        context.restoreGState()
        
        // Glowing dots at each band point
        for point in points {
            let dotR: CGFloat = 2.5 * scale
            let dotRect = NSRect(x: point.x - dotR, y: point.y - dotR,
                                 width: dotR * 2, height: dotR * 2)
            context.saveGState()
            context.clip(to: rect)
            context.setShadow(offset: .zero, blur: 6 * scale,
                              color: skin.accentColor.withAlphaComponent(0.9).cgColor)
            context.setFillColor(skin.accentColor.cgColor)
            context.fillEllipse(in: dotRect)
            context.restoreGState()
            
            // White center
            let innerDot = dotRect.insetBy(dx: dotR * 0.4, dy: dotR * 0.4)
            context.saveGState()
            context.clip(to: rect)
            context.setFillColor(NSColor.white.withAlphaComponent(0.8).cgColor)
            context.fillEllipse(in: innerDot)
            context.restoreGState()
        }
    }
    
    // MARK: - Color Mapping
    
    /// Convert EQ band value (-12 to +12) to color
    /// +12dB (top) = RED, 0dB (middle) = YELLOW, -12dB (bottom) = GREEN
    private func eqValueToColor(_ value: Float) -> NSColor {
        let normalized = CGFloat((value + 12) / 24) // 0..1
        
        let colorStops: [(position: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)] = [
            (0.0, 0.0, 0.85, 0.0),    // Green at -12dB
            (0.33, 0.5, 0.85, 0.0),   // Yellow-green
            (0.5, 0.85, 0.85, 0.0),   // Yellow at 0dB
            (0.66, 0.85, 0.5, 0.0),   // Orange
            (1.0, 0.85, 0.15, 0.0),   // Red at +12dB
        ]
        
        var lowerStop = colorStops[0]
        var upperStop = colorStops[colorStops.count - 1]
        
        for i in 0..<colorStops.count - 1 {
            if normalized >= colorStops[i].position && normalized <= colorStops[i + 1].position {
                lowerStop = colorStops[i]
                upperStop = colorStops[i + 1]
                break
            }
        }
        
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
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)
        needsDisplay = true
    }
    
    func setShadeMode(_ enabled: Bool) {
        isShadeMode = enabled
        needsDisplay = true
    }
    
    private func toggleShadeMode() {
        isShadeMode.toggle()
        controller?.setShadeMode(isShadeMode)
    }
    
    // MARK: - Hit Testing
    
    private func hitTestTitleBar(at point: NSPoint) -> Bool {
        let closeWidth: CGFloat = 30 * scale
        return point.y >= bounds.height - titleBarHeight &&
               point.x < bounds.width - closeWidth
    }
    
    private func hitTestCloseButton(at point: NSPoint) -> Bool {
        let closeRect = NSRect(x: bounds.width - 18 * scale,
                               y: bounds.height - titleBarHeight + 2 * scale,
                               width: 14 * scale, height: 12 * scale)
        return closeRect.contains(point)
    }
    
    private func hitTestShadeButton(at point: NSPoint) -> Bool {
        let shadeRect = NSRect(x: bounds.width - 32 * scale,
                               y: bounds.height - titleBarHeight + 2 * scale,
                               width: 12 * scale, height: 12 * scale)
        return shadeRect.contains(point)
    }
    
    /// Hit test ON/OFF button
    private func hitTestOnOff(at point: NSPoint) -> Bool {
        let onOffX = borderWidth + 4 * scale
        let rect = NSRect(x: onOffX, y: buttonRowY, width: 26 * scale, height: btnHeight)
        return rect.contains(point)
    }
    
    /// Hit test AUTO button
    private func hitTestAuto(at point: NSPoint) -> Bool {
        let autoX = borderWidth + 4 * scale + 26 * scale + 3 * scale
        let rect = NSRect(x: autoX, y: buttonRowY, width: 34 * scale, height: btnHeight)
        return rect.contains(point)
    }
    
    /// Hit test PRESETS button
    private func hitTestPresets(at point: NSPoint) -> Bool {
        let presetsWidth: CGFloat = 48 * scale
        let presetsX = bounds.width - borderWidth - presetsWidth - 4 * scale
        let rect = NSRect(x: presetsX, y: buttonRowY, width: presetsWidth, height: btnHeight)
        return rect.contains(point)
    }
    
    /// Hit test sliders. Returns -1 for preamp, 0-9 for bands, nil if miss.
    private func hitTestSlider(at point: NSPoint) -> Int? {
        // Check preamp
        let preampRect = NSRect(x: preampX - 2 * scale, y: sliderBottomY,
                                width: sliderWidth + 4 * scale, height: sliderHeight)
        if preampRect.contains(point) {
            return -1
        }
        
        // Check bands
        for i in 0..<10 {
            let x = bandStartX + CGFloat(i) * bandSpacing
            let bandRect = NSRect(x: x - 2 * scale, y: sliderBottomY,
                                  width: sliderWidth + 4 * scale, height: sliderHeight)
            if bandRect.contains(point) {
                return i
            }
        }
        
        return nil
    }
    
    // MARK: - Mouse Events
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // Double-click title bar -> shade mode
        if event.clickCount == 2 && hitTestTitleBar(at: point) {
            toggleShadeMode()
            return
        }
        
        if isShadeMode {
            handleShadeMouseDown(at: point, event: event)
            return
        }
        
        // Close button
        if hitTestCloseButton(at: point) {
            pressedButton = "eq_btn_close"
            needsDisplay = true
            return
        }
        
        // Shade button
        if hitTestShadeButton(at: point) {
            pressedButton = "eq_btn_shade"
            needsDisplay = true
            return
        }
        
        // ON/OFF toggle (immediate action)
        if hitTestOnOff(at: point) {
            isEnabled.toggle()
            WindowManager.shared.audioEngine.setEQEnabled(isEnabled)
            needsDisplay = true
            return
        }
        
        // AUTO toggle (immediate action)
        if hitTestAuto(at: point) {
            isAuto.toggle()
            
            if AppStateManager.shared.isEnabled {
                UserDefaults.standard.set(isAuto, forKey: "EQAutoEnabled")
            }
            
            if isAuto {
                applyAutoEQForCurrentTrack()
            }
            
            needsDisplay = true
            return
        }
        
        // PRESETS button (press-and-release)
        if hitTestPresets(at: point) {
            pressedButton = "eq_presets"
            needsDisplay = true
            return
        }
        
        // Sliders
        if let sliderIndex = hitTestSlider(at: point) {
            draggingSlider = sliderIndex
            updateSliderFromPoint(point)
            return
        }
        
        // Title bar -> window drag
        if hitTestTitleBar(at: point) {
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
            if let window = window {
                WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
            }
            return
        }
        
        // Anywhere else -> window drag (non-title-bar)
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
        if let window = window {
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: false)
        }
    }
    
    private func handleShadeMouseDown(at point: NSPoint, event: NSEvent) {
        if hitTestCloseButton(at: point) {
            pressedButton = "eq_btn_close"
            needsDisplay = true
            return
        }
        if hitTestShadeButton(at: point) {
            pressedButton = "eq_btn_shade"
            needsDisplay = true
            return
        }
        
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
        if let window = window {
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        // Handle slider dragging
        if draggingSlider != nil {
            let point = convert(event.locationInWindow, from: nil)
            updateSliderFromPoint(point)
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
            
            newOrigin = WindowManager.shared.windowWillMove(window, to: newOrigin)
            window.setFrameOrigin(newOrigin)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
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
        
        if let pressed = pressedButton {
            switch pressed {
            case "eq_btn_close":
                if hitTestCloseButton(at: point) { window?.close() }
            case "eq_btn_shade":
                if hitTestShadeButton(at: point) { toggleShadeMode() }
            case "eq_presets":
                if hitTestPresets(at: point) { showPresetsMenu(at: point) }
            default:
                break
            }
            
            pressedButton = nil
            needsDisplay = true
        }
        
        draggingSlider = nil
    }
    
    private func handleShadeMouseUp(at point: NSPoint) {
        if let pressed = pressedButton {
            switch pressed {
            case "eq_btn_close":
                if hitTestCloseButton(at: point) { window?.close() }
            case "eq_btn_shade":
                if hitTestShadeButton(at: point) { toggleShadeMode() }
            default:
                break
            }
            pressedButton = nil
            needsDisplay = true
        }
    }
    
    // MARK: - Slider Interaction
    
    private func updateSliderFromPoint(_ point: NSPoint) {
        guard let index = draggingSlider else { return }
        
        // Calculate value from Y position
        // sliderBottomY = -12dB, sliderTopY (sliderBottomY + sliderHeight) = +12dB
        let normalizedY = (point.y - sliderBottomY) / sliderHeight
        let clampedY = max(0, min(1, normalizedY))
        let value = Float(clampedY) * 24 - 12 // 0..1 -> -12..+12
        
        if index == -1 {
            preamp = value
            WindowManager.shared.audioEngine.setPreamp(value)
        } else {
            bands[index] = value
            WindowManager.shared.audioEngine.setEQBand(index, gain: value)
        }
        
        needsDisplay = true
    }
    
    // MARK: - Presets Menu
    
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
        applyPreset(preset)
    }
    
    // MARK: - Context Menu
    
    override func menu(for event: NSEvent) -> NSMenu? {
        return ContextMenuBuilder.buildMenu()
    }
    
    // MARK: - Layout
    
    override func layout() {
        super.layout()
    }
}
