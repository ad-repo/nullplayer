import AppKit

// =============================================================================
// EQ VIEW - Equalizer window implementation
// =============================================================================
// For skin format documentation, see: skills/ui-guide/SKILL.md
//
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
    private var isHighlighted = false
    
    /// Region manager for hit testing
    private let regionManager = RegionManager.shared

    /// Set when this view is mounted inside a `.wal` skin's own standard frame (B55). The frame
    /// draws the title bar, the close button and the window drag, so this view draws and hit-tests
    /// only the equalizer itself.
    private var hostedContext: WinampModernHostedSurfaceContext?
    /// The window drag the body keeps while the skin's frame owns the chrome (B57).
    private var hostedDrag = WinampModernHostedWindowDrag()
    
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
        
        // Frequency labels
        static let frequencies = ["60", "170", "310", "600", "1K", "3K", "6K", "12K", "14K", "16K"]
        
        // Window control buttons - draw positions (in title bar, from right to left)
        static let closeRect = NSRect(x: 264, y: 3, width: 9, height: 9)

        // Enlarged hit-test areas for easier clicking
        static let closeHitRect = NSRect(x: 257, y: 0, width: 18, height: 14)
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
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupView() {
        wantsLayer = true
        loadCurrentEQState()
        setupAccessibility()
        setupAutoEQNotification()
    }
    
    /// Subscribe to track change notifications for Auto EQ
    private func setupAutoEQNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTrackChange(_:)),
            name: .audioTrackDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(self, selector: #selector(connectedWindowHighlightDidChange(_:)),
                                               name: .connectedWindowHighlightDidChange, object: nil)
        // A `.wal` colour-theme switch recolours this window when it is a Winamp Modern fallback
        // (Phase 16); the style is re-derived on each draw, so a repaint is the whole job.
        NotificationCenter.default.addObserver(self, selector: #selector(skinDidChange),
                                               name: .winampModernThemeDidChange, object: nil)
    }
    
    /// Handle track change for Auto EQ
    @objc private func connectedWindowHighlightDidChange(_ notification: Notification) {
        let highlighted = notification.userInfo?["highlightedWindows"] as? Set<NSWindow> ?? []
        let newValue = highlighted.contains { $0 === window }
        if isHighlighted != newValue {
            isHighlighted = newValue
            needsDisplay = true
        }
    }

    @objc private func handleTrackChange(_ notification: Notification) {
        applyAutoEQForCurrentTrack()
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
        
        // Load Auto EQ state from UserDefaults only if "Remember State" is enabled
        // Otherwise default to off (Auto EQ doesn't persist across restarts)
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
        // This handles the case where a track was loaded before the EQ view was created
        if isAuto {
            // Delay slightly to ensure audio engine has fully loaded the track
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.applyAutoEQForCurrentTrack()
            }
        }
    }
    
    /// Apply Auto EQ for the currently playing track (if genre matches)
    private func applyAutoEQForCurrentTrack() {
        guard isAuto else { return }
        
        guard let track = WindowManager.shared.audioEngine.currentTrack else {
            NSLog("Auto EQ: No track currently playing")
            return
        }
        
        // If track has genre, apply preset directly
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
    
    /// Apply preset for a given genre string
    private func applyPresetForGenre(_ genre: String) {
        guard let preset = EQPreset.forGenre(genre) else {
            NSLog("Auto EQ: No preset match for genre '%@'", genre)
            return
        }
        
        NSLog("Auto EQ: Applying '%@' preset for genre '%@'", preset.name, genre)
        
        // Enable EQ if it's off
        if !isEnabled {
            isEnabled = true
            WindowManager.shared.audioEngine.setEQEnabled(true)
        }
        
        applyPreset(preset)
    }
    
    /// Fetch genre from Plex and apply preset
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
    
    /// Fetch genre from Subsonic and apply preset
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
    
    // MARK: - Scaling Support
    
    /// The classic layout minus its title bar — what a hosted view draws, since the skin's frame
    /// supplies the chrome around it.
    private static let hostedContentSize = NSSize(width: Skin.baseEQSize.width,
                                                  height: Skin.baseEQSize.height - Layout.titleBarHeight)

    /// Where every control sits, in classic layout units. Vertical positions never move — only the
    /// horizontal ones, and only for a hosted view, which is as wide as the player it docks under
    /// (B55) rather than the 275 the classic artwork was cut for. Drawing and hit testing both read
    /// this, so they cannot disagree about where a slider is.
    private struct Metrics {
        let onOff: NSRect
        let auto: NSRect
        let presets: NSRect
        let preamp: NSRect
        let graph: NSRect
        let bands: [NSRect]

        static let classic = Metrics(width: Skin.baseEQSize.width)

        /// The classic margins are preserved and the *gaps* absorb the extra width: the buttons and
        /// the preamp stay left-anchored, PRESETS keeps its 14px right margin, the graph well spans
        /// what is left between them, and the ten bands spread evenly across the same span the
        /// classic layout gives them (78 → 21 from the right edge).
        init(width: CGFloat) {
            let rightMargin = Skin.baseEQSize.width - (Layout.presetsRect.maxX)
            onOff = Layout.onOffRect
            auto = Layout.autoRect
            presets = NSRect(x: max(auto.maxX, width - rightMargin - Layout.presetsRect.width),
                             y: Layout.presetsRect.minY,
                             width: Layout.presetsRect.width, height: Layout.presetsRect.height)
            preamp = Layout.preampRect
            let graphGap = SkinElements.Equalizer.graphRect.minX - Layout.autoRect.maxX
            graph = NSRect(x: SkinElements.Equalizer.graphRect.minX,
                           y: SkinElements.Equalizer.graphRect.minY,
                           width: max(0, presets.minX - graphGap - SkinElements.Equalizer.graphRect.minX),
                           height: SkinElements.Equalizer.graphRect.height)
            let lastClassicBandX = Layout.bandStartX + 9 * Layout.bandSpacing
            let bandsRightMargin = Skin.baseEQSize.width - (lastClassicBandX + Layout.bandWidth)
            let lastX = max(Layout.bandStartX,
                            width - bandsRightMargin - Layout.bandWidth)
            let spacing = (lastX - Layout.bandStartX) / 9
            bands = (0..<10).map { index in
                NSRect(x: Layout.bandStartX + CGFloat(index) * spacing, y: Layout.bandY,
                       width: Layout.bandWidth, height: Layout.bandHeight)
            }
        }
    }

    /// The classic constants unchanged for a standalone window; widened for a hosted one.
    private var metrics: Metrics {
        guard hostedContext != nil, scaleFactor > 0 else { return .classic }
        return Metrics(width: bounds.width / scaleFactor)
    }

    /// Calculate scale factor based on current bounds vs original size
    private var scaleFactor: CGFloat {
        // Hosted: the width is the skin frame's to give, so only the height sets the scale and the
        // layout spreads to fill what is left.
        if hostedContext != nil {
            return bounds.height / Self.hostedContentSize.height
        }
        let originalSize = Skin.baseEQSize
        let scaleX = bounds.width / originalSize.width
        let scaleY = bounds.height / originalSize.height
        return min(scaleX, scaleY)
    }
    
    /// Convert a point from view coordinates to original (unscaled) coordinates
    private func convertToOriginalCoordinates(_ point: NSPoint) -> NSPoint {
        let originalSize = Skin.baseEQSize
        let scale = scaleFactor

        // Hosted: the drawing is the title-bar-less content, centred in the holder. Invert exactly
        // that transform, and answer in the *classic* frame of reference so every Layout rect — all
        // of which include the title bar in their y — keeps working unchanged.
        if hostedContext != nil {
            guard scale > 0 else { return point }
            let fromTop = bounds.height - point.y
            return NSPoint(x: point.x / scale,
                           y: Self.hostedContentSize.height - fromTop / scale)
        }

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
        return Skin.baseEQSize
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let originalSize = Skin.baseEQSize
        let scale = scaleFactor

        // Flip coordinate system to match skin's top-down coordinates
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        // Mounted in a `.wal` skin's own frame (B55): the frame draws the chrome, so this view draws
        // the controls only, scaled into the client area the holder gave it.
        if hostedContext != nil {
            let style = WindowManager.shared.winampModernSurfaceStyle ?? .fallback
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 0, y: -Layout.titleBarHeight)
            let layoutWidth = scale > 0 ? bounds.width / scale : Skin.baseEQSize.width
            drawWinampModernNormalMode(
                style: style, context: context, isActive: true,
                drawBounds: NSRect(x: 0, y: 0, width: layoutWidth, height: Skin.baseEQSize.height),
                drawsChrome: false)
            context.restoreGState()
            return
        }

        // When hiding title bars, shift content up to clip the title bar off the top
        let hidingTitleBar = WindowManager.shared.hideTitleBars

        // Apply scaling for resized window
        if scale != 1.0 {
            let scaledWidth = originalSize.width * scale
            let scaledHeight = originalSize.height * scale
            let offsetX = (bounds.width - scaledWidth) / 2
            let offsetY: CGFloat
            if hidingTitleBar {
                offsetY = -Layout.titleBarHeight * scale
            } else {
                offsetY = (bounds.height - scaledHeight) / 2
            }
            context.translateBy(x: offsetX, y: offsetY)
            context.scaleBy(x: scale, y: scale)
        } else if hidingTitleBar {
            context.translateBy(x: 0, y: -Layout.titleBarHeight)
        }

        let skin = WindowManager.shared.currentSkin
        let renderer = SkinRenderer(skin: skin ?? SkinLoader.shared.loadDefault())

        let isActive = window?.isKeyWindow ?? true

        // Use original bounds for drawing (scaling is applied via transform)
        let drawBounds = NSRect(origin: .zero, size: originalSize)

        // Draw normal mode — the flat palette version when this window is a `.wal` skin's fallback
        // equalizer (Phase 16), the classic sprites otherwise.
        if let style = WindowManager.shared.winampModernSurfaceStyle {
            drawWinampModernNormalMode(style: style, context: context, isActive: isActive,
                                       drawBounds: drawBounds, drawsChrome: true)
        } else {
            drawNormalMode(renderer: renderer, context: context, isActive: isActive, drawBounds: drawBounds)
        }

        context.restoreGState()

        if isHighlighted {
            NSColor.white.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }
    }

    /// Draw the window
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
        
        // Draw EQ curve graph over the skin-provided graph well.
        renderer.drawEQGraph(bands: bands, isEnabled: isEnabled, in: context)
    }
    
    // MARK: - Winamp Modern drawing (Phase 16)

    /// The equalizer for a `.wal` skin that declares none of its own.
    ///
    /// Every rect comes from this view's own `Layout` — the same numbers `hitTestSlider`,
    /// `updateSlider`, and the button hit tests use — so the controls stay exactly where they were
    /// and only their appearance changes. dB runs +12 at the top of a slider to −12 at the bottom,
    /// matching `updateSlider`.
    ///
    /// `drawsChrome` is false when the view is mounted in a skin's own standard frame (B55): the
    /// frame already draws the border, the title and the close button, so drawing them again would
    /// put a second title bar inside the window's real one.
    private func drawWinampModernNormalMode(style: WinampModernSurfaceStyle, context: CGContext,
                                            isActive: Bool, drawBounds: NSRect, drawsChrome: Bool) {
        let body = drawsChrome
            ? drawBounds
            : NSRect(x: 0, y: Layout.titleBarHeight, width: drawBounds.width,
                     height: drawBounds.height - Layout.titleBarHeight)
        context.setFillColor(style.background.cgColor)
        context.fill(body)

        if drawsChrome {
            context.setFillColor(style.barBackground.cgColor)
            context.fill(NSRect(x: 0, y: 0, width: drawBounds.width, height: Layout.titleBarHeight))
            context.setStrokeColor(style.border.cgColor)
            context.setLineWidth(1)
            context.stroke(drawBounds.insetBy(dx: 0.5, dy: 0.5))

            // Guarded against the bar it lands on (B48).
            let titleColor = isActive ? style.legibleText(style.currentText, on: style.barBackground)
                                      : style.legibleDimText(on: style.barBackground)
            let title = "EQUALIZER"
            let titleWidth = WinampModernSurfaceStyle.measuredWidth(title, scale: 1.4)
            WinampModernSurfaceStyle.drawText(
                title,
                at: NSPoint(x: (drawBounds.width - titleWidth) / 2,
                            y: (Layout.titleBarHeight - WinampModernSurfaceStyle.classicCharHeight * 1.4) / 2),
                scale: 1.4, color: titleColor, in: context)

            if !WindowManager.shared.hideTitleBars {
                let close = Layout.closeHitRect
                if pressedButton == .close {
                    context.setFillColor(style.pressedFill.cgColor)
                    context.fill(close)
                }
                let glyph = close.insetBy(dx: 6, dy: 4)
                context.setStrokeColor(titleColor.cgColor)
                context.beginPath()
                context.move(to: CGPoint(x: glyph.minX, y: glyph.minY))
                context.addLine(to: CGPoint(x: glyph.maxX, y: glyph.maxY))
                context.move(to: CGPoint(x: glyph.maxX, y: glyph.minY))
                context.addLine(to: CGPoint(x: glyph.minX, y: glyph.maxY))
                context.strokePath()
            }
        }

        let metrics = self.metrics
        drawWinampModernEQButton("ON", rect: metrics.onOff, on: isEnabled,
                                 pressed: false, style: style, context: context)
        drawWinampModernEQButton("AUTO", rect: metrics.auto, on: isAuto,
                                 pressed: false, style: style, context: context)
        drawWinampModernEQButton("PRESETS", rect: metrics.presets, on: false,
                                 pressed: pressedButton == .eqPresets, style: style, context: context)

        drawWinampModernEQGraph(style: style, context: context, rect: metrics.graph)

        drawWinampModernEQSlider(value: CGFloat(preamp), rect: metrics.preamp,
                                 label: "PRE", style: style, context: context)
        for (index, rect) in metrics.bands.enumerated() {
            drawWinampModernEQSlider(value: CGFloat(bands[index]), rect: rect,
                                     label: Layout.frequencies[index], style: style, context: context)
        }
    }

    private func drawWinampModernEQButton(_ label: String, rect: NSRect, on: Bool, pressed: Bool,
                                          style: WinampModernSurfaceStyle, context: CGContext) {
        let fill: NSColor = pressed ? style.pressedFill : (on ? style.selectionBackground : style.background)
        context.setFillColor(fill.cgColor)
        context.fill(rect)
        context.setStrokeColor(style.divider.cgColor)
        context.setLineWidth(1)
        context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        let color = on ? style.selectionText : style.text
        let width = WinampModernSurfaceStyle.measuredWidth(label, scale: 1)
        WinampModernSurfaceStyle.drawText(
            label,
            at: NSPoint(x: rect.midX - width / 2,
                        y: rect.midY - WinampModernSurfaceStyle.classicCharHeight / 2),
            scale: 1, color: color, in: context)
    }

    /// A vertical track with a thumb at the band's dB, plus the band label beneath it.
    private func drawWinampModernEQSlider(value: CGFloat, rect: NSRect, label: String,
                                          style: WinampModernSurfaceStyle, context: CGContext) {
        let track = NSRect(x: rect.midX - 1.5, y: rect.minY + 2, width: 3, height: rect.height - 4)
        context.setFillColor(style.divider.cgColor)
        context.fill(track)

        // Centre line: 0 dB, so a flat band reads as flat at a glance.
        context.setFillColor(style.border.cgColor)
        context.fill(NSRect(x: rect.minX, y: rect.midY - 0.5, width: rect.width, height: 1))

        let normalized = min(1, max(0, (value + 12) / 24))
        let thumbCenterY = track.maxY - track.height * normalized
        let thumb = NSRect(x: rect.minX, y: thumbCenterY - 3, width: rect.width, height: 6)
        context.setFillColor((isEnabled ? style.selectionBackground : style.divider).cgColor)
        context.fill(thumb)
        context.setStrokeColor(style.text.cgColor)
        context.setLineWidth(1)
        context.stroke(thumb.insetBy(dx: 0.5, dy: 0.5))

        let labelWidth = WinampModernSurfaceStyle.measuredWidth(label, scale: 0.8)
        WinampModernSurfaceStyle.drawText(label,
                                          at: NSPoint(x: rect.midX - labelWidth / 2, y: rect.maxY + 2),
                                          scale: 0.8, color: style.dimText, in: context)
    }

    /// The response curve, in the same well and with the same interpolation the classic graph uses,
    /// drawn in the skin's own colours.
    private func drawWinampModernEQGraph(style: WinampModernSurfaceStyle, context: CGContext,
                                         rect: NSRect) {
        context.setFillColor(style.background.cgColor)
        context.fill(rect)
        context.setStrokeColor(style.divider.cgColor)
        context.setLineWidth(1)
        context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        context.setFillColor(style.divider.cgColor)
        context.fill(NSRect(x: rect.minX, y: rect.midY - 0.5, width: rect.width, height: 1))

        guard isEnabled, bands.count >= 10 else { return }
        context.saveGState()
        context.clip(to: rect)
        context.setStrokeColor(style.text.cgColor)
        context.setLineWidth(1)
        context.beginPath()
        let maxXIndex = max(1, Int(rect.width.rounded(.down)) - 1)
        for xIndex in 0...maxXIndex {
            let bandPosition = CGFloat(xIndex) / CGFloat(maxXIndex) * 9.0
            let lowerBand = min(8, Int(floor(bandPosition)))
            let upperBand = min(9, lowerBand + 1)
            let t = bandPosition - CGFloat(lowerBand)
            let value = CGFloat(bands[lowerBand])
                + (CGFloat(bands[upperBand]) - CGFloat(bands[lowerBand])) * t
            let normalized = min(1, max(0, (value + 12) / 24))
            let point = CGPoint(x: rect.minX + CGFloat(xIndex),
                                y: rect.minY + rect.height * (1 - normalized))
            if xIndex == 0 { context.move(to: point) } else { context.addLine(to: point) }
        }
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - Public Methods

    @objc func skinDidChange() {
        needsDisplay = true
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
        let skinPoint = NSPoint(x: point.x, y: originalWindowSize.height - point.y)
        
        // Window dragging is handled by macOS via isMovableByWindowBackground
        
        // Close button (checked first for priority, enlarged hit area) - skip when title bars hidden,
        // and when the skin's own frame owns the chrome (B55).
        if hostedContext == nil && !WindowManager.shared.hideTitleBars
            && Layout.closeHitRect.contains(skinPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        
        // Toggle buttons
        let metrics = self.metrics
        if metrics.onOff.contains(skinPoint) {
            isEnabled.toggle()
            WindowManager.shared.audioEngine.setEQEnabled(isEnabled)
            needsDisplay = true
            return
        }
        
        if metrics.auto.contains(skinPoint) {
            isAuto.toggle()
            
            // Only persist Auto EQ state if "Remember State" is enabled
            if AppStateManager.shared.isEnabled {
                UserDefaults.standard.set(isAuto, forKey: "EQAutoEnabled")
            }
            
            // If Auto was just enabled, immediately apply genre preset for current track
            if isAuto {
                applyAutoEQForCurrentTrack()
            }
            
            needsDisplay = true
            return
        }
        
        if metrics.presets.contains(skinPoint) {
            pressedButton = .eqPresets
            needsDisplay = true
            return
        }
        
        // Double-click slider area -> reset to flat
        if event.clickCount == 2, hitTestSlider(at: skinPoint) != nil {
            applyPreset(.flat)
            return
        }
        
        // Check sliders - if we hit a slider, start dragging slider
        if let sliderIndex = hitTestSlider(at: skinPoint) {
            draggingSlider = sliderIndex
            updateSlider(at: skinPoint)
            return
        }
        
        // Not on any control - start window drag. Hosted, the skin's frame owns the chrome but not
        // the drag: its title strip is 15–45px, so the body stays a handle here as it is standalone
        // (B57, correcting B55).
        if hostedContext != nil {
            hostedDrag.prime(event, context: hostedContext)
            return
        }

        // Only allow undocking if dragging from title bar area
        // When title bars are hidden, all drags allow undocking
        let isTitleBarArea: Bool
        if WindowManager.shared.hideTitleBars {
            isTitleBarArea = true
        } else {
            isTitleBarArea = skinPoint.y < Layout.titleBarHeight
        }
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
        if let window = window {
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: isTitleBarArea)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        // Handle slider dragging
        if draggingSlider != nil {
            let viewPoint = convert(event.locationInWindow, from: nil)
            let point = convertToOriginalCoordinates(viewPoint)
            let skinPoint = NSPoint(x: point.x, y: originalWindowSize.height - point.y)
            updateSlider(at: skinPoint)
            return
        }
        
        if hostedContext != nil {
            hostedDrag.drag(event)
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
        // A press that moved the window is not also a click on whatever it started over.
        if hostedContext != nil, hostedDrag.end() { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = convertToOriginalCoordinates(viewPoint)
        let skinPoint = NSPoint(x: point.x, y: originalWindowSize.height - point.y)

        // Handle button releases
        if let pressed = pressedButton {
            switch pressed {
            case .close:
                if Layout.closeHitRect.contains(skinPoint) {
                    window?.close()
                }
            case .eqPresets:
                if metrics.presets.contains(skinPoint) {
                    // The menu positions itself in *view* coordinates, so it must be given the click
                    // where it actually landed, not the unscaled layout point.
                    showPresetsMenu(at: viewPoint)
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
        let metrics = self.metrics
        // Check preamp (skin coordinates - y increases downward)
        let preampRect = metrics.preamp
        if point.x >= preampRect.minX && point.x <= preampRect.maxX &&
           point.y >= preampRect.minY && point.y <= preampRect.minY + preampRect.height {
            return -1
        }
        
        // Check bands
        for (index, rect) in metrics.bands.enumerated() {
            if point.x >= rect.minX && point.x <= rect.maxX &&
               point.y >= rect.minY && point.y <= rect.minY + rect.height {
                return index
            }
        }
        
        return nil
    }
    
    private func updateSlider(at point: NSPoint) {
        guard let index = draggingSlider else { return }
        
        let metrics = self.metrics
        let rect = index == -1 ? metrics.preamp : metrics.bands[index]
        
        // Calculate value from position (skin coordinates - y=0 at top)
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
        applyPreset(preset)
    }
    
    // MARK: - Context Menu
    
    override func menu(for event: NSEvent) -> NSMenu? {
        return ContextMenuBuilder.buildMenu()
    }
}

// MARK: - Winamp Modern hosted surface (B55)

/// Mounted inside the skin's own standard frame when a `.wal` skin declares no equalizer of its own.
/// The whole equalizer goes in — bands, preamp, ON/AUTO/PRESETS and the curve — rather than the
/// `drawEqualizerComponent` stub a synthesized `<component guid:eq>` holder would resolve to.
extension EQView: WinampModernHostedSurface {
    var view: NSView { self }

    func configureForHostedSurface(context: WinampModernHostedSurfaceContext) {
        hostedContext = context
        autoresizingMask = [.width, .height]
        loadCurrentEQState()
        needsDisplay = true
    }

    func applyPalette(_ style: WinampModernSurfaceStyle) { needsDisplay = true }

    func applySkinScale(_ scale: CGFloat) { needsDisplay = true }

    /// The equalizer draws only when something changes, so there is no render loop to run or stop.
    func resume() {
        loadCurrentEQState()
        needsDisplay = true
    }

    func suspend() {}

    func unmountFromHolder() { removeFromSuperview() }

    func prepareForUITeardown() {
        removeFromSuperview()
        hostedContext = nil
    }
}
