import AppKit
import NullPlayerCore

// =============================================================================
// MODERN EQ VIEW - Equalizer with modern skin chrome
// =============================================================================
// Renders the modern 21-band graphic equalizer with an integrated preamp control,
// preset buttons, EQ curve graph, and compact frequency labels using the modern skin system.
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
    private var bands: [Float] = Array(repeating: 0, count: EQConfiguration.modern21.bandCount)
    
    /// Currently dragging control index (-1 = preamp control, 0... = band faders)
    private var draggingSlider: Int?
    
    /// Button being pressed (for visual feedback)
    private var pressedButton: String?

    /// Active preset button index (index into EQPreset.buttonPresets), nil if none lit
    private var activePresetIndex: Int? = nil
    
    /// Window dragging state
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    
    /// Shade mode state
    private(set) var isShadeMode = false
    
    /// Scale factor for layout (computed to track double-size changes)
    private var scale: CGFloat { ModernSkinElements.scaleFactor }
    
    /// Glow multiplier from skin config
    private var glowMultiplier: CGFloat = 1.0
    
    /// Which edges are adjacent to another docked window (for seamless border rendering)
    private var adjacentEdges: AdjacentEdges = [] { didSet { updateCornerMask() } }
    private var sharpCorners: CACornerMask = [] { didSet { updateCornerMask() } }
    private var edgeOcclusionSegments: EdgeOcclusionSegments = .empty

    /// Highlight state for drag-mode visual feedback
    private var isHighlighted = false

    // MARK: - Layout Constants
    
    private var titleBarHeight: CGFloat {
        let hide = WindowManager.shared.effectiveHideTitleBars(for: self.window) && !isShadeMode
        return hide ? borderWidth : ModernSkinElements.eqTitleBarHeight
    }
    private var borderWidth: CGFloat { ModernSkinElements.eqBorderWidth }

    private var eqConfiguration: EQConfiguration {
        WindowManager.shared.audioEngine.eqConfiguration
    }
    
    // Layout matching classic EQ (macOS bottom-left origin, Y increases upward)
    //
    // Visual layout (top to bottom on screen = high Y to low Y):
    //   title bar
    //   [ON] [AUTO] [FLAT][ROCK][POP][ELEC][HIP][JAZZ][CLSC]  <- button row
    //   [PRE][--- EQ curve graph ---]
    //   sliders (21 bands)
    //   frequency labels
    //   border
    
    /// Button row height
    private var btnHeight: CGFloat { 12 * scale }
    
    /// Button row Y (just below title bar)
    private var buttonRowY: CGFloat { bounds.height - titleBarHeight - 2 * scale - btnHeight }
    
    /// Graph height
    private var graphHeight: CGFloat { 22 * scale }
    
    /// Graph Y (below button row)
    private var graphY: CGFloat { buttonRowY - 2 * scale - graphHeight }
    
    /// Compact preamp control integrated into the graph strip.
    private var preampControlRect: NSRect {
        NSRect(x: borderWidth + 4 * scale, y: graphY, width: 42 * scale, height: graphHeight)
    }

    /// Graph area rect (to the right of the integrated preamp control)
    private var graphRect: NSRect {
        let graphX = preampControlRect.maxX + 4 * scale
        let graphWidth = bounds.width - graphX - borderWidth - 4 * scale
        return NSRect(x: graphX, y: graphY, width: graphWidth, height: graphHeight)
    }
    
    /// Slider area top Y (below graph)
    private var sliderTopY: CGFloat { graphY - 2 * scale }
    
    /// Frequency label height
    private var freqLabelHeight: CGFloat { 12 * scale }
    
    /// Slider bottom Y (above freq labels)
    private var sliderBottomY: CGFloat { borderWidth + 2 * scale + freqLabelHeight + 1 * scale }
    
    /// Frequency label Y (bottom, above border)
    private var freqLabelY: CGFloat { borderWidth + 2 * scale }
    
    /// Slider height
    private var sliderHeight: CGFloat { sliderTopY - sliderBottomY }
    
    private var bandStartX: CGFloat { borderWidth + 4 * scale }

    private var bandGap: CGFloat { max(1.0, 1.1 * scale) }

    private var sliderWidth: CGFloat {
        let count = CGFloat(eqConfiguration.bandCount)
        let availableWidth = bounds.width - bandStartX - borderWidth - 4 * scale
        return max(4.5 * scale, (availableWidth - bandGap * (count - 1)) / count)
    }

    private var bandSpacing: CGFloat {
        sliderWidth + bandGap
    }

    private func bandX(_ index: Int) -> CGFloat {
        bandStartX + CGFloat(index) * bandSpacing
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
        glowMultiplier = skin.elementGlowMultiplier
        
        // Load current EQ state from audio engine
        loadCurrentEQState()
        
        // Observe skin changes
        NotificationCenter.default.addObserver(self, selector: #selector(modernSkinDidChange),
                                                name: ModernSkinEngine.skinDidChangeNotification, object: nil)
        
        // Observe double size changes
        NotificationCenter.default.addObserver(self, selector: #selector(doubleSizeChanged),
                                                name: .doubleSizeDidChange, object: nil)
        
        // Observe window layout changes for seamless docked borders
        NotificationCenter.default.addObserver(self, selector: #selector(windowLayoutDidChange),
                                                name: .windowLayoutDidChange, object: nil)
        
        // Observe track changes for Auto EQ
        NotificationCenter.default.addObserver(self, selector: #selector(handleTrackChange(_:)),
                                                name: .audioTrackDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(connectedWindowHighlightDidChange(_:)),
                                                name: .connectedWindowHighlightDidChange, object: nil)

        // Set accessibility
        setAccessibilityIdentifier("modernEqualizerView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("Equalizer")
        updateCornerMask()
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
        if bands.count != eqConfiguration.bandCount {
            bands = Array(repeating: 0, count: eqConfiguration.bandCount)
        }
        for i in 0..<eqConfiguration.bandCount {
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
        bands = Array(preset.bands.prefix(eqConfiguration.bandCount))
        if bands.count < eqConfiguration.bandCount {
            bands.append(contentsOf: Array(repeating: 0, count: eqConfiguration.bandCount - bands.count))
        }
        
        // Apply to audio engine
        WindowManager.shared.audioEngine.setPreamp(preset.preamp)
        for (index, gain) in preset.bands.enumerated() {
            WindowManager.shared.audioEngine.setEQBand(index, gain: gain)
        }
        
        needsDisplay = true
    }
    
    @objc private func connectedWindowHighlightDidChange(_ notification: Notification) {
        let highlighted = notification.userInfo?["highlightedWindows"] as? Set<NSWindow> ?? []
        let newValue = highlighted.contains { $0 === window }
        if isHighlighted != newValue {
            isHighlighted = newValue
            needsDisplay = true
        }
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
        
        // For Jellyfin tracks without genre, try to fetch it
        if let jellyfinId = track.jellyfinId {
            NSLog("Auto EQ: Track '%@' has no genre, fetching from Jellyfin...", track.title)
            Task { await fetchAndApplyJellyfinGenre(itemId: jellyfinId, trackTitle: track.title) }
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
    
    private func fetchAndApplyJellyfinGenre(itemId: String, trackTitle: String) async {
        guard let client = JellyfinManager.shared.serverClient else { return }
        do {
            if let song = try await client.fetchSong(id: itemId), let genre = song.genre {
                await MainActor.run { self.applyPresetForGenre(genre) }
            }
        } catch {
            NSLog("Auto EQ: Failed to fetch Jellyfin track details: %@", error.localizedDescription)
        }
    }
    
    // MARK: - Notification Handlers
    
    @objc private func modernSkinDidChange() {
        skinDidChange()
    }
    
    @objc private func doubleSizeChanged() {
        skinDidChange()
    }
    
    @objc private func windowLayoutDidChange() {
        guard let window = window else { return }
        let newEdges = WindowManager.shared.computeAdjacentEdges(for: window)
        let newSharp = WindowManager.shared.computeSharpCorners(for: window)
        let newSegments = WindowManager.shared.computeEdgeOcclusionSegments(for: window)
        let seamless = min(1.0, max(0.0, ModernSkinEngine.shared.currentSkin?.config.window.seamlessDocking ?? 0))
        let shouldHaveShadow = !(seamless > 0 && !newEdges.isEmpty)
        if window.hasShadow != shouldHaveShadow {
            window.hasShadow = shouldHaveShadow
            window.invalidateShadow()
        }
        if newEdges != adjacentEdges || newSharp != sharpCorners || newSegments != edgeOcclusionSegments {
            adjacentEdges = newEdges
            sharpCorners = newSharp
            edgeOcclusionSegments = newSegments
            needsDisplay = true
        }
    }

    // MARK: - Drawing

    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let mainOpacity = renderer.skin.resolvedOpacity(for: .mainWindow)
        
        // Draw window background
        renderer.drawWindowBackground(
            in: bounds,
            context: context,
            adjacentEdges: adjacentEdges,
            sharpCorners: sharpCorners,
            backgroundOpacity: mainOpacity.background
        )

        // Draw window border with glow (seamless docking suppresses adjacent edges)
        renderer.drawWindowBorder(
            in: bounds,
            context: context,
            adjacentEdges: adjacentEdges,
            sharpCorners: sharpCorners,
            occlusionSegments: edgeOcclusionSegments,
            borderOpacity: mainOpacity.border
        )

        // Draw title bar (unless hidden by docking)
        withContextAlpha(mainOpacity.content, context: context) {
            if !WindowManager.shared.effectiveHideTitleBars(for: self.window) {
                renderer.drawTitleBar(in: titleBarBaseRect, title: "NULLPLAYER EQUALIZER", prefix: "eq_", context: context)

                // Draw close button
                let closeState = (pressedButton == "eq_btn_close") ? "pressed" : "normal"
                renderer.drawWindowControlButton("eq_btn_close", state: closeState,
                                                 in: closeBtnBaseRect, context: context)

                // Draw shade button
                let shadeState = (pressedButton == "eq_btn_shade") ? "pressed" : "normal"
                renderer.drawWindowControlButton("eq_btn_shade", state: shadeState,
                                                 in: shadeBtnBaseRect, context: context)
            }

            if isShadeMode {
                return
            }

            // Draw EQ content
            drawEQContent(in: context)
        }

        if isHighlighted {
            NSColor.white.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }
    }
    
    /// Base rects in the 275x116 coordinate space (renderer scales them)
    private var titleBarBaseRect: NSRect {
        let tbh = ModernSkinElements.titleBarBaseHeight
        return NSRect(x: 0, y: (bounds.height / scale) - tbh, width: 275, height: tbh)
    }

    private var closeBtnBaseRect: NSRect {
        let tbh = ModernSkinElements.titleBarBaseHeight
        return NSRect(x: 261, y: (bounds.height / scale) - tbh / 2 - 5, width: 10, height: 10)
    }

    private var shadeBtnBaseRect: NSRect {
        let tbh = ModernSkinElements.titleBarBaseHeight
        return NSRect(x: 249, y: (bounds.height / scale) - tbh / 2 - 5, width: 10, height: 10)
    }
    
    // MARK: - EQ Content Drawing
    
    private func drawEQContent(in context: CGContext) {
        let skin = renderer.skin
        let font = skin.eqLabelFont()
        let tinyFont = skin.eqValueFont()
        let faderOpacity = skin.resolvedOpacity(for: .eqFaderBackground)
        let curveOpacity = skin.resolvedOpacity(for: .curveBackground)

        // == 1. Sliders (clip so glow doesn't bleed up) ==
        context.saveGState()
        context.clip(to: NSRect(x: 0, y: 0, width: bounds.width, height: sliderTopY))

        for i in bands.indices {
            let x = bandX(i)
            drawSlider(index: i, x: x, opacityStyle: faderOpacity, context: context)
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
        
        // Compact preset toggle buttons — stretched to fill remaining horizontal space
        let presetStartX = autoX + autoWidth + 3 * scale
        let presetEndX = bounds.width - borderWidth - 4 * scale
        let presetTotalWidth = presetEndX - presetStartX
        let presetCount = CGFloat(EQPreset.buttonPresets.count)
        let presetBtnGap: CGFloat = 2 * scale
        let presetBtnWidth = (presetTotalWidth - presetBtnGap * (presetCount - 1)) / presetCount
        for (i, (_, label)) in EQPreset.buttonPresets.enumerated() {
            let isActive = activePresetIndex == i
            let presetX = presetStartX + CGFloat(i) * (presetBtnWidth + presetBtnGap)
            drawToggleButton(label: label, isActive: isActive,
                             rect: NSRect(x: presetX, y: btnY, width: presetBtnWidth, height: btnHeight),
                             font: font, context: context)
        }

        drawPreampControl(font: font, tinyFont: tinyFont, context: context)

        // EQ curve graph
        drawEQGraph(opacityStyle: curveOpacity, context: context)

        // == 3. Frequency labels (bottom) ==

        for i in bands.indices {
            let x = bandX(i)
            let sliderCenterX = x + sliderWidth / 2
            let labelY = freqLabelY + (i.isMultiple(of: 2) ? freqLabelHeight * 0.72 : freqLabelHeight * 0.28)
            drawGlowText(eqConfiguration.displayLabels[i],
                         at: NSPoint(x: sliderCenterX, y: labelY),
                         font: tinyFont,
                         color: skin.primaryColor.withAlphaComponent(0.55),
                         glow: false,
                         context: context)
        }
    }
    
    // MARK: - Glow Text Helper
    
    private func drawGlowText(_ text: String, at center: NSPoint, font: NSFont,
                               color: NSColor, glow: Bool, context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: renderer.skin.applyTextOpacity(to: color)
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        
        if glow {
            context.saveGState()
            context.setShadow(offset: .zero, blur: 4 * scale * glowMultiplier,
                              color: color.withAlphaComponent(0.8).cgColor)
            drawTextUnattenuated(in: context) {
                str.draw(at: origin)
            }
            context.restoreGState()
        }
        drawTextUnattenuated(in: context) {
            str.draw(at: origin)
        }
    }

    private func withContextAlpha(_ alpha: CGFloat, context: CGContext, draw: () -> Void) {
        let resolvedAlpha = min(1.0, max(0.0, alpha))
        context.saveGState()
        context.setAlpha(resolvedAlpha)
        draw()
        context.restoreGState()
    }

    private func drawTextUnattenuated(in context: CGContext, draw: () -> Void) {
        context.saveGState()
        context.setAlpha(1.0)
        draw()
        context.restoreGState()
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
            context.setShadow(offset: .zero, blur: 6 * scale * glowMultiplier,
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
            context.setShadow(offset: .zero, blur: 4 * scale * glowMultiplier,
                              color: color.withAlphaComponent(0.8).cgColor)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: skin.applyTextOpacity(to: color)
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let size = str.size()
        let textOrigin = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        drawTextUnattenuated(in: context) {
            str.draw(at: textOrigin)
        }
        context.restoreGState()
        if isActive { // second pass for crisp text
            let attrs2: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: skin.applyTextOpacity(to: color)
            ]
            let crisp = NSAttributedString(string: label, attributes: attrs2)
            drawTextUnattenuated(in: context) {
                crisp.draw(at: textOrigin)
            }
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
            context.setShadow(offset: .zero, blur: 5 * scale * glowMultiplier,
                              color: skin.accentColor.withAlphaComponent(0.5).cgColor)
        }
        context.setStrokeColor(color.withAlphaComponent(isPressed ? 0.8 : 0.3).cgColor)
        context.setLineWidth(isPressed ? 1.0 : 0.5)
        context.stroke(rect)
        context.restoreGState()
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: skin.applyTextOpacity(to: color)
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let size = str.size()
        drawTextUnattenuated(in: context) {
            str.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
    }

    private func drawPreampControl(font: NSFont, tinyFont: NSFont, context: CGContext) {
        let skin = renderer.skin
        let rect = preampControlRect
        let dialSize = min(rect.height - 4 * scale, 16 * scale)
        let dialRect = NSRect(x: rect.minX + 2 * scale, y: rect.midY - dialSize / 2, width: dialSize, height: dialSize)
        let center = CGPoint(x: dialRect.midX, y: dialRect.midY)
        let color = eqValueToColor(preamp)
        let normalized = CGFloat((preamp + 12) / 24)
        let startAngle = CGFloat.pi * 0.75
        let sweep = CGFloat.pi * 1.5
        let indicatorAngle = startAngle - sweep * normalized
        let capsulePath = CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)

        context.saveGState()
        context.setFillColor(NSColor(calibratedWhite: 0.02, alpha: 0.92).cgColor)
        context.addPath(capsulePath)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(skin.primaryColor.withAlphaComponent(0.18).cgColor)
        context.setLineWidth(max(0.5, 0.75 * scale))
        context.addPath(capsulePath)
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(skin.textDimColor.withAlphaComponent(0.25).cgColor)
        context.setLineWidth(max(1.2, 1.4 * scale))
        context.addEllipse(in: dialRect)
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.setLineWidth(max(1.2, 1.5 * scale))
        context.setLineCap(.round)
        context.setShadow(offset: .zero, blur: 5 * scale * glowMultiplier, color: color.withAlphaComponent(0.75).cgColor)
        context.setStrokeColor(color.withAlphaComponent(0.9).cgColor)
        context.addArc(center: center, radius: dialRect.width / 2, startAngle: startAngle, endAngle: indicatorAngle, clockwise: true)
        context.strokePath()
        context.restoreGState()

        let indicatorRadius = dialRect.width / 2
        let indicatorCenter = CGPoint(
            x: center.x + cos(indicatorAngle) * indicatorRadius,
            y: center.y + sin(indicatorAngle) * indicatorRadius
        )
        let indicatorRect = NSRect(x: indicatorCenter.x - 1.5 * scale, y: indicatorCenter.y - 1.5 * scale, width: 3 * scale, height: 3 * scale)
        context.saveGState()
        context.setShadow(offset: .zero, blur: 4 * scale * glowMultiplier, color: color.withAlphaComponent(0.8).cgColor)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: indicatorRect)
        context.restoreGState()

        drawGlowText("PRE",
                     at: NSPoint(x: rect.maxX - 10 * scale, y: rect.midY + 4 * scale),
                     font: font,
                     color: skin.primaryColor.withAlphaComponent(0.75),
                     glow: false,
                     context: context)

        let dbValue = String(format: "%+.0f", preamp)
        drawGlowText(dbValue,
                     at: NSPoint(x: rect.maxX - 10 * scale, y: rect.midY - 4 * scale),
                     font: tinyFont,
                     color: color,
                     glow: true,
                     context: context)
    }
    
    // MARK: - Slider Drawing
    
    /// Uses `window.areaOpacity.eqFaderBackground` channels.
    private func drawSlider(index: Int, x: CGFloat, opacityStyle: ResolvedAreaOpacityStyle, context: CGContext) {
        let value = bands[index]
        let skin = renderer.skin
        
        let trackRect = NSRect(x: x, y: sliderBottomY, width: sliderWidth, height: sliderHeight)
        let centerY = trackRect.midY
        let normalizedValue = CGFloat((value + 12) / 24) // 0..1
        let thumbY = sliderBottomY + normalizedValue * sliderHeight
        let fillColor = eqValueToColor(value)
        
        // Track background - deep black
        context.saveGState()
        context.setFillColor(NSColor(calibratedWhite: 0.03, alpha: opacityStyle.background).cgColor)
        context.fill(trackRect)
        if opacityStyle.border > 0 {
            // Subtle vertical dividers only — no full rect border to avoid harsh grid look
            let dividerAlpha = opacityStyle.border * 0.4
            context.setStrokeColor(skin.borderColor.withAlphaComponent(dividerAlpha).cgColor)
            context.setLineWidth(max(0.5, 0.5 * scale))
            context.move(to: CGPoint(x: trackRect.minX, y: trackRect.minY))
            context.addLine(to: CGPoint(x: trackRect.minX, y: trackRect.maxY))
            context.strokePath()
        }
        context.restoreGState()

        withContextAlpha(opacityStyle.content, context: context) {
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
                context.setShadow(offset: .zero, blur: 10 * scale * glowMultiplier,
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
                context.setShadow(offset: .zero, blur: 5 * scale * glowMultiplier,
                                  color: fillColor.withAlphaComponent(1.0).cgColor)
                context.setStrokeColor(fillColor.withAlphaComponent(0.9).cgColor)
                context.setLineWidth(2.0)
                context.move(to: CGPoint(x: lineX, y: fillRect.minY))
                context.addLine(to: CGPoint(x: lineX, y: fillRect.maxY))
                context.strokePath()
                // Second pass for extra brightness
                context.setShadow(offset: .zero, blur: 2 * scale * glowMultiplier,
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
            context.setShadow(offset: .zero, blur: 3 * scale * glowMultiplier,
                              color: skin.primaryColor.withAlphaComponent(0.3).cgColor)
            context.setStrokeColor(skin.primaryColor.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: trackRect.minX, y: centerY))
            context.addLine(to: CGPoint(x: trackRect.maxX, y: centerY))
            context.strokePath()
            context.restoreGState()
            
            // === THUMB - the big glowing indicator ===
            let thumbHeight: CGFloat = max(3 * scale, 3.5 * scale)
            let thumbOverhang: CGFloat = min(2 * scale, sliderWidth * 0.4)
            let thumbRect = NSRect(x: x - thumbOverhang, y: thumbY - thumbHeight / 2,
                                   width: sliderWidth + thumbOverhang * 2, height: thumbHeight)
            
            // Massive outer bloom
            context.saveGState()
            context.setShadow(offset: .zero, blur: 12 * scale * glowMultiplier,
                              color: fillColor.withAlphaComponent(0.8).cgColor)
            context.setFillColor(fillColor.cgColor)
            context.fill(thumbRect)
            context.restoreGState()
            
            // Second bloom pass for intensity
            context.saveGState()
            context.setShadow(offset: .zero, blur: 6 * scale * glowMultiplier,
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
    }
    
    // MARK: - EQ Graph Drawing
    
    /// Uses `window.areaOpacity.curveBackground` channels.
    private func drawEQGraph(opacityStyle: ResolvedAreaOpacityStyle, context: CGContext) {
        let rect = graphRect
        let skin = renderer.skin
        
        // Dark recessed background
        context.saveGState()
        context.setFillColor(NSColor(calibratedWhite: 0.01, alpha: opacityStyle.background).cgColor)
        context.fill(rect)
        context.restoreGState()
        
        // Glowing border
        withContextAlpha(opacityStyle.border, context: context) {
            context.saveGState()
            context.setShadow(offset: .zero, blur: 4 * scale * glowMultiplier,
                              color: skin.accentColor.withAlphaComponent(0.3).cgColor)
            context.setStrokeColor(skin.accentColor.withAlphaComponent(0.4).cgColor)
            context.setLineWidth(1.0)
            context.stroke(rect)
            context.restoreGState()
        }
        guard opacityStyle.content > 0 else { return }
        
        // Always draw the curve (even when flat it shows the center line as the curve)
        let insetRect = rect.insetBy(dx: 2, dy: 2)
        var points: [(x: CGFloat, y: CGFloat)] = []
        let divisor = max(1, eqConfiguration.bandCount - 1)
        for i in bands.indices {
            let px = insetRect.minX + (insetRect.width / CGFloat(divisor)) * CGFloat(i)
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
        
        withContextAlpha(opacityStyle.content, context: context) {
            let centerY = rect.midY
            let miniTrackWidth = min(3.0 * scale, max(1.4 * scale, insetRect.width / CGFloat(max(1, eqConfiguration.bandCount)) * 0.26))
            let cornerRadius = miniTrackWidth / 2

            for point in points {
                let trackRect = NSRect(
                    x: point.x - miniTrackWidth / 2,
                    y: insetRect.minY,
                    width: miniTrackWidth,
                    height: insetRect.height
                )
                let trackPath = CGPath(roundedRect: trackRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

                context.saveGState()
                context.clip(to: rect)
                context.setFillColor(NSColor(calibratedWhite: 0.03, alpha: 0.85).cgColor)
                context.addPath(trackPath)
                context.fillPath()
                context.restoreGState()

                context.saveGState()
                context.clip(to: rect)
                context.setStrokeColor(skin.primaryColor.withAlphaComponent(0.18).cgColor)
                context.setLineWidth(max(0.35, 0.45 * scale))
                context.addPath(trackPath)
                context.strokePath()
                context.restoreGState()

                let activeMinY = min(centerY, point.y)
                let activeHeight = max(abs(point.y - centerY), 1.2 * scale)
                let activeRect = NSRect(
                    x: point.x - miniTrackWidth / 2,
                    y: activeMinY,
                    width: miniTrackWidth,
                    height: activeHeight
                )
                let activePath = CGPath(roundedRect: activeRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

                context.saveGState()
                context.clip(to: rect)
                context.setShadow(offset: .zero, blur: 4 * scale * glowMultiplier,
                                  color: skin.accentColor.withAlphaComponent(0.45).cgColor)
                context.setFillColor(skin.accentColor.withAlphaComponent(0.34).cgColor)
                context.addPath(activePath)
                context.fillPath()
                context.restoreGState()
            }
            
            // Curve - wide glow
            context.saveGState()
            context.clip(to: rect)
            context.setShadow(offset: .zero, blur: 8 * scale * glowMultiplier,
                              color: skin.accentColor.withAlphaComponent(0.8).cgColor)
            context.setStrokeColor(skin.accentColor.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(1.8 * scale)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.addPath(curvePath)
            context.strokePath()
            context.restoreGState()
            
            // Curve - bright core
            context.saveGState()
            context.clip(to: rect)
            context.setStrokeColor(skin.accentColor.cgColor)
            context.setLineWidth(1.1 * scale)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.addPath(curvePath)
            context.strokePath()
            context.restoreGState()
            
            // White-hot center of curve
            context.saveGState()
            context.clip(to: rect)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
            context.setLineWidth(max(0.3, 0.45 * scale))
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.addPath(curvePath)
            context.strokePath()
            context.restoreGState()
            
            // Glowing dots at each band point
            for point in points {
                let dotR: CGFloat = bands.count > 12 ? 1.25 * scale : 2.5 * scale
                let dotRect = NSRect(x: point.x - dotR, y: point.y - dotR,
                                     width: dotR * 2, height: dotR * 2)
                context.saveGState()
                context.clip(to: rect)
                context.setShadow(offset: .zero, blur: 6 * scale * glowMultiplier,
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
    }
    
    // MARK: - Color Mapping
    
    /// Convert EQ band value (-12 to +12) to color
    /// Uses skin palette: eqLow (-12dB), eqMid (0dB), eqHigh (+12dB)
    private func eqValueToColor(_ value: Float) -> NSColor {
        let normalized = CGFloat((value + 12) / 24) // 0..1
        let skin = renderer.skin
        
        // Extract RGB components from skin EQ colors
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0
        var mr: CGFloat = 0, mg: CGFloat = 0, mb: CGFloat = 0
        var hr: CGFloat = 0, hg: CGFloat = 0, hb: CGFloat = 0
        (skin.eqLowColor.usingColorSpace(.sRGB) ?? skin.eqLowColor).getRed(&lr, green: &lg, blue: &lb, alpha: nil)
        (skin.eqMidColor.usingColorSpace(.sRGB) ?? skin.eqMidColor).getRed(&mr, green: &mg, blue: &mb, alpha: nil)
        (skin.eqHighColor.usingColorSpace(.sRGB) ?? skin.eqHighColor).getRed(&hr, green: &hg, blue: &hb, alpha: nil)
        
        // 5-stop gradient derived from 3 skin colors with smooth interpolation
        let colorStops: [(position: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)] = [
            (0.0,  lr, lg, lb),                                                    // Low at -12dB
            (0.33, lr + (mr - lr) * 0.66, lg + (mg - lg) * 0.66, lb + (mb - lb) * 0.66), // Low-Mid blend
            (0.5,  mr, mg, mb),                                                    // Mid at 0dB
            (0.66, mr + (hr - mr) * 0.66, mg + (hg - mg) * 0.66, mb + (hb - mb) * 0.66), // Mid-High blend
            (1.0,  hr, hg, hb),                                                    // High at +12dB
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
        glowMultiplier = skin.elementGlowMultiplier
        updateCornerMask()
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
        if WindowManager.shared.effectiveHideTitleBars(for: self.window) {
            return point.y >= bounds.height - 6  // invisible drag zone
        }
        let closeWidth: CGFloat = 28 * scale
        return point.y >= bounds.height - titleBarHeight &&
               point.x < bounds.width - closeWidth
    }
    
    private func hitTestCloseButton(at point: NSPoint) -> Bool {
        if WindowManager.shared.effectiveHideTitleBars(for: self.window) { return false }
        let closeRect = NSRect(x: bounds.width - 16 * scale,
                               y: bounds.height - titleBarHeight + 2 * scale,
                               width: 14 * scale, height: 12 * scale)
        return closeRect.contains(point)
    }
    
    private func hitTestShadeButton(at point: NSPoint) -> Bool {
        if WindowManager.shared.effectiveHideTitleBars(for: self.window) { return false }
        let shadeRect = NSRect(x: bounds.width - 28 * scale,
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

    private func hitTestPreampControl(at point: NSPoint) -> Bool {
        preampControlRect.insetBy(dx: -2 * scale, dy: -2 * scale).contains(point)
    }
    
    /// Hit test band sliders. Returns the band index or nil if miss.
    private func hitTestSlider(at point: NSPoint) -> Int? {
        for i in bands.indices {
            let x = bandX(i)
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
                if !isEnabled {
                    isEnabled = true
                    WindowManager.shared.audioEngine.setEQEnabled(true)
                }
                applyAutoEQForCurrentTrack()
            }
            
            needsDisplay = true
            return
        }
        
        // Compact preset toggle buttons — same layout math as draw path
        let presetStartX = borderWidth + 4 * scale + 26 * scale + 3 * scale + 34 * scale + 3 * scale
        let presetEndX = bounds.width - borderWidth - 4 * scale
        let presetTotalWidth = presetEndX - presetStartX
        let presetCount = CGFloat(EQPreset.buttonPresets.count)
        let presetBtnGap: CGFloat = 2 * scale
        let presetBtnWidth = (presetTotalWidth - presetBtnGap * (presetCount - 1)) / presetCount
        for (i, (preset, _)) in EQPreset.buttonPresets.enumerated() {
            let x = presetStartX + CGFloat(i) * (presetBtnWidth + presetBtnGap)
            let btnRect = NSRect(x: x, y: buttonRowY, width: presetBtnWidth, height: btnHeight)
            if btnRect.contains(point) {
                if activePresetIndex == i {
                    activePresetIndex = nil
                    applyPreset(.flat)
                } else {
                    activePresetIndex = i
                    applyPreset(preset)
                    if !isEnabled {
                        isEnabled = true
                        WindowManager.shared.audioEngine.setEQEnabled(true)
                    }
                }
                needsDisplay = true
                return
            }
        }

        // Double-click integrated PRE control -> reset preamp
        if event.clickCount == 2, hitTestPreampControl(at: point) {
            preamp = 0
            WindowManager.shared.audioEngine.setPreamp(0)
            activePresetIndex = nil
            needsDisplay = true
            return
        }

        // Double-click slider area -> reset only that band
        if event.clickCount == 2, let index = hitTestSlider(at: point) {
            bands[index] = 0
            WindowManager.shared.audioEngine.setEQBand(index, gain: 0)
            activePresetIndex = nil
            needsDisplay = true
            return
        }

        if hitTestPreampControl(at: point) {
            draggingSlider = -1
            updateSliderFromPoint(point)
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
        
        // Anywhere else -> window drag
        // When title bar is hidden (docked + HT on), all drags allow undocking
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
        if let window = window {
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: WindowManager.shared.effectiveHideTitleBars(for: window))
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

        // Clear active preset highlight when user manually adjusts a slider
        activePresetIndex = nil

        if index == -1 {
            let normalizedY = (point.y - preampControlRect.minY) / preampControlRect.height
            let clampedY = max(0, min(1, normalizedY))
            let value = Float(clampedY) * 24 - 12
            preamp = value
            WindowManager.shared.audioEngine.setPreamp(value)
        } else {
            // sliderBottomY = -12dB, sliderTopY (sliderBottomY + sliderHeight) = +12dB
            let normalizedY = (point.y - sliderBottomY) / sliderHeight
            let clampedY = max(0, min(1, normalizedY))
            let value = Float(clampedY) * 24 - 12
            bands[index] = value
            WindowManager.shared.audioEngine.setEQBand(index, gain: value)
        }

        needsDisplay = true
    }
    
    // MARK: - Context Menu
    
    override func menu(for event: NSEvent) -> NSMenu? {
        return ContextMenuBuilder.buildMenu()
    }
    
    // MARK: - Layout

    override func layout() {
        super.layout()
        updateCornerMask()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.isOpaque = false
        updateCornerMask()
    }

    private func updateCornerMask() {
        guard let layer = self.layer else { return }
        let cornerRadius = (ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()).config.window.cornerRadius ?? 0
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = cornerRadius > 0
        guard cornerRadius > 0 else { return }
        let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                         .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer.maskedCorners = allCorners.subtracting(sharpCorners)
    }
}
