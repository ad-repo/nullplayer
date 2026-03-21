import AppKit
import QuartzCore

/// The main window view for the modern skin system.
/// Renders all UI elements using `ModernSkinRenderer`, handles mouse interaction,
/// marquee scrolling, spectrum visualization, drag-and-drop, and context menus.
///
/// Has ZERO dependencies on the classic skin system (Skin/, SkinElements, SkinRenderer, etc.).
class ModernMainWindowView: NSView {
    
    // MARK: - Properties
    
    /// Reference to controller
    weak var controller: ModernMainWindowController?
    
    /// The skin renderer
    private var renderer: ModernSkinRenderer!
    
    /// Grid background layer
    private var gridLayer: GridBackgroundLayer?
    
    /// Marquee layer for scrolling text
    private var marqueeLayer: ModernMarqueeLayer!
    
    /// Current time values
    private var currentTime: TimeInterval = 0
    private var duration: TimeInterval = 0
    
    /// Current track info
    private var currentTrack: Track?
    
    /// Video title override
    private var videoTitle: String?
    
    /// Spectrum levels (downsampled to 8 bars for mini display)
    private var spectrumLevels: [Float] = Array(repeating: 0, count: 8)
    
    /// Main window visualization mode (persisted)
    private var mainVisMode: MainWindowVisMode = .spectrum {
        didSet {
            UserDefaults.standard.set(mainVisMode.rawValue, forKey: "modernMainWindowVisMode")
            UserDefaults.standard.set(mainVisMode.rawValue, forKey: "mainWindowVisMode")
            updateMetalOverlay()
        }
    }
    
    /// Metal overlay for GPU-rendered spectrum modes
    private var metalOverlay: SpectrumAnalyzerView?
    
    /// Mouse tracking state
    private var pressedElement: String?
    private var isDraggingSeek = false
    private var isDraggingVolume = false
    private var isDraggingWindow = false
    private var dragStartPoint: NSPoint = .zero
    
    /// Seek position during drag (0-1)
    private var seekDragPosition: CGFloat?
    
    /// Whether in shade (compact) mode
    var isShadeMode = false
    
    /// Current detected BPM (nil = not yet detected, 0 = no confidence)
    private var currentBPM: Int?
    
    /// BPM multiplier cycle state: 0 = normal, 1 = 2x, 2 = 0.5x
    private var bpmMultiplierState: Int = 2
    
    /// Scale factor for hit testing (computed to track double-size changes)
    private var scale: CGFloat { ModernSkinElements.scaleFactor }
    
    /// Timer for distinguishing single vs double click on vis area
    private var visClickTimer: Timer?
    
    /// Throttle timestamp for CPU-rendered mini spectrum updates (20Hz)
    private var lastMiniSpectrumUpdate: CFAbsoluteTime = 0
    
    /// Tracking area for cursor updates
    private var mainTrackingArea: NSTrackingArea?
    
    /// Which edges are adjacent to another docked window (for seamless border rendering)
    private var adjacentEdges: AdjacentEdges = [] { didSet { updateCornerMask() } }
    private var sharpCorners: CACornerMask = [] { didSet { updateCornerMask() } }
    private var edgeOcclusionSegments: EdgeOcclusionSegments = .empty

    /// Highlight state for drag-mode visual feedback
    private var isHighlighted = false

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
        
        // Set up grid background
        setupGridBackground(skin: skin)
        
        // Set up marquee
        setupMarquee(skin: skin)
        
        // Register for drag and drop
        registerForDraggedTypes([.fileURL])
        
        // Observe skin changes
        NotificationCenter.default.addObserver(self, selector: #selector(modernSkinDidChange),
                                                name: ModernSkinEngine.skinDidChangeNotification, object: nil)
        
        // Observe double size changes
        NotificationCenter.default.addObserver(self, selector: #selector(doubleSizeChanged),
                                                name: .doubleSizeDidChange, object: nil)
        
        // Observe BPM detection updates
        NotificationCenter.default.addObserver(self, selector: #selector(bpmDidUpdate(_:)),
                                                name: .bpmUpdated, object: nil)
        
        // Observe window layout changes for seamless docked borders
        NotificationCenter.default.addObserver(self, selector: #selector(windowLayoutDidChange),
                                                name: .windowLayoutDidChange, object: nil)

        // Observe radio metadata/connection updates for marquee now-playing text.
        NotificationCenter.default.addObserver(self, selector: #selector(radioMetadataDidChange),
                                                name: RadioManager.streamMetadataDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(radioConnectionStateDidChange),
                                                name: RadioManager.connectionStateDidChangeNotification, object: nil)

        // Observe playback option changes so menu-triggered toggles update button state.
        NotificationCenter.default.addObserver(self, selector: #selector(playbackOptionsDidChange),
                                                name: .audioPlaybackOptionsChanged, object: nil)

        // Observe main window vis mode changes from context menu
        NotificationCenter.default.addObserver(self, selector: #selector(mainVisSettingsChanged),
                                                name: NSNotification.Name("MainWindowVisChanged"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleVisClassicProfileCommand(_:)),
                                                name: .visClassicProfileCommand, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(connectedWindowHighlightDidChange(_:)),
                                                name: .connectedWindowHighlightDidChange, object: nil)

        // Set accessibility
        setAccessibilityIdentifier("ModernMainWindowView")
        setAccessibilityRole(.group)
        
        // Restore saved visualization mode
        restoreVisMode()
        updateCornerMask()
    }
    
    deinit {
        visClickTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Setup
    
    private func setupGridBackground(skin: ModernSkin) {
        gridLayer?.removeFromSuperlayer()
        
        if let gridConfig = skin.config.background.grid {
            let grid = GridBackgroundLayer()
            grid.configure(with: gridConfig)
            grid.frame = bounds
            grid.zPosition = 1  // Above the view's background drawing
            layer?.addSublayer(grid)
            gridLayer = grid
        }
    }
    
    private func setupMarquee(skin: ModernSkin) {
        marqueeLayer?.removeFromSuperlayer()
        
        let marquee = ModernMarqueeLayer()
        marquee.configure(with: skin)
        
        // Position marquee in the upper portion of the marquee background panel
        let marqueeRect = scaledRect(ModernSkinElements.marqueeBackground.defaultRect)
        let inset: CGFloat = 4 * scale
        marquee.frame = NSRect(x: marqueeRect.minX + inset,
                                y: marqueeRect.minY + marqueeRect.height * 0.35,
                                width: marqueeRect.width - inset * 2,
                                height: marqueeRect.height * 0.55)
        marquee.zPosition = 10  // Above grid
        
        // Use the skin's marquee font (configurable via fonts.marqueeSize)
        marquee.textFont = skin.marqueeFont()
        
        layer?.addSublayer(marquee)
        marqueeLayer = marquee
        updateMarqueeOpacity()
    }
    
    // MARK: - Layout

    override func layout() {
        super.layout()
        gridLayer?.frame = bounds
        updateMarqueeForMode()
        updateMainSpectrumOverlayGeometryAndStyle()
        updateCornerMask()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.isOpaque = false
        updateCornerMask()
        // Register/unregister occlusion observer when window association changes
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        if let window = window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidChangeOcclusionState(_:)),
                name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
    }

    @objc private func windowDidChangeOcclusionState(_ notification: Notification) {
        guard notification.object as? NSWindow == window else { return }
        if window?.occlusionState.contains(.visible) == true {
            ModernSkinEngine.shared.animationEngine.resumeFromOcclusion()
            marqueeLayer.resumeScrolling()
            needsDisplay = true
        } else {
            ModernSkinEngine.shared.animationEngine.pauseForOcclusion()
            marqueeLayer.pauseScrolling()
        }
    }

    @objc private func playbackOptionsDidChange() {
        needsDisplay = true
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

    // MARK: - Tracking Areas (cursor hover)
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = mainTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .activeInKeyWindow, .cursorUpdate],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        mainTrackingArea = area
    }
    
    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let element = hitTest(point: point) {
            switch element {
            case _ where element.hasPrefix("btn_"), "time_display", "spectrum_area", "logo":
                NSCursor.pointingHand.set()
            case "seek_track", "volume_track":
                NSCursor.resizeLeftRight.set()
            default:
                NSCursor.arrow.set()
            }
        } else {
            // Title bar area → open hand for dragging
            let base = basePoint(from: point)
            if WindowManager.shared.effectiveHideTitleBars(for: self.window) || ModernSkinElements.titleBar.defaultRect.contains(base) {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    /// True when main-window content should be remapped to reclaim hidden titlebar space.
    private var isTitleBarHiddenForLayout: Bool {
        !isShadeMode && WindowManager.shared.effectiveHideTitleBars(for: self.window)
    }

    /// Vertical remap factor for HT mode: scale 98-base-unit content to full 116-base-unit frame.
    private var contentLayoutScaleY: CGFloat {
        guard isTitleBarHiddenForLayout else { return 1.0 }
        let fullHeight = ModernSkinElements.baseMainSize.height
        let contentHeight = fullHeight - ModernSkinElements.titleBarBaseHeight
        guard contentHeight > 0 else { return 1.0 }
        return fullHeight / contentHeight
    }

    /// Apply HT-only content reflow so controls fill reclaimed titlebar space while frame size stays constant.
    private func withMainContentLayoutTransform(context: CGContext, draw: () -> Void) {
        guard isTitleBarHiddenForLayout else {
            draw()
            return
        }
        context.saveGState()
        context.scaleBy(x: 1.0, y: contentLayoutScaleY)
        draw()
        context.restoreGState()
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let windowBounds = bounds
        let mainOpacity = renderer.skin.resolvedOpacity(for: .mainWindow)
        let timeOpacity = renderer.skin.resolvedOpacity(for: .timeDisplay)
        let trackOpacity = renderer.skin.resolvedOpacity(for: .trackDisplay)
        let volumeOpacity = renderer.skin.resolvedOpacity(for: .volumeArea)
        let spectrumOpacity = renderer.skin.resolvedOpacity(for: .spectrumArea)
        // Keep panel fill/border tied to true skin opacity; only content uses main-spectrum override.
        let spectrumBackgroundOpacity = spectrumOpacity.background
        let spectrumBorderOpacity = spectrumOpacity.border
        let spectrumContentOpacity = renderer.skin.applyMainSpectrumOpacity(to: spectrumOpacity.content)
        
        if isShadeMode {
            drawShadeMode(in: windowBounds, context: context)
            if isHighlighted {
                NSColor.white.withAlphaComponent(0.15).setFill()
                bounds.fill()
            }
            return
        }
        
        // 1. Window background + border -- clip to dirtyRect to avoid full-bounds fill
        context.saveGState()
        context.clip(to: dirtyRect)
        renderer.drawWindowBackground(
            in: windowBounds,
            context: context,
            adjacentEdges: adjacentEdges,
            sharpCorners: sharpCorners,
            backgroundOpacity: mainOpacity.background
        )
        renderer.drawWindowBorder(
            in: windowBounds,
            context: context,
            adjacentEdges: adjacentEdges,
            sharpCorners: sharpCorners,
            occlusionSegments: edgeOcclusionSegments,
            borderOpacity: mainOpacity.border
        )
        context.restoreGState()

        // 2..9. Foreground content under the main window content opacity channel.
        withContextAlpha(mainOpacity.content, context: context) {
            withMainContentLayoutTransform(context: context) {
                // 2. Title bar -- only if not hidden and dirty rect overlaps
                if !WindowManager.shared.effectiveHideTitleBars(for: self.window) {
                    let titleScaled = scaledRect(ModernSkinElements.titleBar.defaultRect)
                    if dirtyRect.intersects(titleScaled) {
                        renderer.drawTitleBar(in: ModernSkinElements.titleBar.defaultRect, title: "NULLPLAYER", context: context)
                        drawWindowControls(context: context)
                    }
                }

                // 3. Time display + status indicator
                let timeScaled = scaledRect(ModernSkinElements.timeDisplay.defaultRect)
                let statusScaled = scaledRect(ModernSkinElements.statusPlay.defaultRect)
                let timeStatusRegion = timeScaled.union(statusScaled)
                if dirtyRect.intersects(timeStatusRegion) {
                    // `window.areaOpacity.timeDisplay` controls panel fill/border/content.
                    renderer.drawInsetPanel(
                        in: NSRect(x: 6, y: 60, width: 84, height: 34),
                        backgroundOpacity: timeOpacity.background,
                        borderOpacity: timeOpacity.border,
                        context: context
                    )
                    withContextAlpha(timeOpacity.content, context: context) {
                        drawTimeDisplay(context: context)
                        let state = effectivePlaybackState()
                        renderer.drawStatusIndicator(state, in: ModernSkinElements.statusPlay.defaultRect, context: context)
                    }
                }

                // 4. Info panel (marquee background + info labels)
                let infoPanelScaled = scaledRect(ModernSkinElements.marqueeBackground.defaultRect)
                if dirtyRect.intersects(infoPanelScaled) {
                    // `window.areaOpacity.trackDisplay` controls this panel region.
                    if renderer.skin.image(for: "marquee_bg") != nil {
                        renderer.drawElement(
                            "marquee_bg",
                            in: ModernSkinElements.marqueeBackground.defaultRect,
                            contentOpacity: trackOpacity.background,
                            context: context
                        )
                        if trackOpacity.border > 0 {
                            let panelRect = scaledRect(ModernSkinElements.marqueeBackground.defaultRect)
                            context.saveGState()
                            context.setStrokeColor(renderer.skin.borderColor.withAlphaComponent(trackOpacity.border).cgColor)
                            context.setLineWidth(max(0.5, 0.5 * scale))
                            let path = CGPath(
                                roundedRect: panelRect,
                                cornerWidth: 4 * scale,
                                cornerHeight: 4 * scale,
                                transform: nil
                            )
                            context.addPath(path)
                            context.strokePath()
                            context.restoreGState()
                        }
                    } else {
                        renderer.drawInsetPanel(
                            in: ModernSkinElements.marqueeBackground.defaultRect,
                            backgroundOpacity: trackOpacity.background,
                            borderOpacity: trackOpacity.border,
                            context: context
                        )
                    }
                    withContextAlpha(trackOpacity.content, context: context) {
                        drawInfoLabels(context: context)
                    }
                }

                // 5. Spectrum area panel + content
                let specScaled = scaledRect(ModernSkinElements.spectrumArea.defaultRect)
                if dirtyRect.intersects(specScaled) {
                    let drawSpectrumArea = { [self] in
                        if self.mainVisMode == .spectrum {
                            // `window.areaOpacity.spectrumArea` controls panel + bars.
                            // `window.mainSpectrumOpacity` (if set) overrides the resolved spectrum alpha.
                            self.renderer.drawMiniSpectrum(
                                self.spectrumLevels,
                                in: ModernSkinElements.spectrumArea.defaultRect,
                                panelBackgroundOpacity: spectrumBackgroundOpacity,
                                panelBorderOpacity: spectrumBorderOpacity,
                                contentOpacity: spectrumContentOpacity,
                                context: context
                            )
                        } else {
                            // For Metal modes, vis_classic transparent background keeps border
                            // from skin opacity but clears panel fill behind the analyzer.
                            let panelBgOpacity: CGFloat
                            if self.mainVisMode == .visClassicExact && self.isMainVisClassicTransparentEnabled() {
                                panelBgOpacity = 0
                            } else {
                                panelBgOpacity = spectrumBackgroundOpacity
                            }
                            self.renderer.drawInsetPanel(
                                in: ModernSkinElements.spectrumArea.defaultRect,
                                backgroundOpacity: panelBgOpacity,
                                borderOpacity: spectrumBorderOpacity,
                                context: context
                            )
                        }
                    }
                    drawSpectrumArea()
                }

                // 6. EQ & Playlist toggle buttons (above seek bar)
                let toggleRegion = scaledRect(NSRect(x: 93, y: 42, width: 176, height: 14))
                if dirtyRect.intersects(toggleRegion) {
                    drawEQPlaylistButtons(context: context)
                }

                // 7. Seek bar (track + thumb padding)
                let seekScaled = scaledRect(ModernSkinElements.seekTrack.defaultRect).insetBy(dx: 0, dy: -6 * scale)
                if dirtyRect.intersects(seekScaled) {
                    drawSeekBar(context: context)
                }

                // 8. Transport buttons
                let transportRegion = scaledRect(NSRect(x: 6, y: 3, width: 168, height: 24))
                if dirtyRect.intersects(transportRegion) {
                    drawTransportButtons(context: context)
                }

                // 9. Volume slider (track + thumb padding)
                let volumeScaled = scaledRect(ModernSkinElements.volumeTrack.defaultRect).insetBy(dx: 0, dy: -6 * scale)
                if dirtyRect.intersects(volumeScaled) {
                    // `window.areaOpacity.volumeArea` controls panel + slider content.
                    renderer.drawInsetPanel(
                        in: NSRect(x: 177, y: 6, width: 92, height: 17),
                        backgroundOpacity: volumeOpacity.background,
                        borderOpacity: volumeOpacity.border,
                        context: context
                    )
                    withContextAlpha(volumeOpacity.content, context: context) {
                        drawVolumeSlider(context: context)
                    }
                }
            }
        }

        if isHighlighted {
            NSColor.white.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }
    }
    
    // MARK: - Shade Mode Drawing
    
    /// Draw compact shade mode: single strip with title, scrolling track name, and controls
    private func drawShadeMode(in bounds: NSRect, context: CGContext) {
        let mainOpacity = renderer.skin.resolvedOpacity(for: .mainWindow)
        // Background
        renderer.drawWindowBackground(
            in: bounds,
            context: context,
            adjacentEdges: adjacentEdges,
            sharpCorners: sharpCorners,
            backgroundOpacity: mainOpacity.background
        )
        renderer.drawWindowBorder(
            in: bounds,
            context: context,
            adjacentEdges: adjacentEdges,
            sharpCorners: sharpCorners,
            occlusionSegments: edgeOcclusionSegments,
            borderOpacity: mainOpacity.border
        )

        // In shade mode, draw a compact horizontal layout in the available space
        // The window is 18 base units tall (22.5px scaled)
        // Layout: [unshade btn] [title text / marquee] [close btn]
        let baseH: CGFloat = 18  // base height of shade window
        withContextAlpha(mainOpacity.content, context: context) {
            // Title text "NULLPLAYER" on left (using renderer for image text support)
            let titleRect = NSRect(x: 4, y: 0, width: 70, height: baseH)
            renderer.drawTitleBar(in: titleRect, title: "NULLPLAYER", context: context)

            // Scrolling track name in the middle
            // (marquee layer handles this, it's positioned by setupMarquee)

            // Window controls on right
            let btnSize: CGFloat = 8
            let btnY = (baseH - btnSize) / 2

            // Unshade button (□ to restore)
            renderer.drawWindowControlButton("btn_shade",
                                              state: pressedElement == "btn_shade" ? "pressed" : "normal",
                                              in: NSRect(x: 255, y: btnY, width: btnSize, height: btnSize),
                                              context: context)

            // Close button
            renderer.drawWindowControlButton("btn_close",
                                              state: pressedElement == "btn_close" ? "pressed" : "normal",
                                              in: NSRect(x: 265, y: btnY, width: btnSize, height: btnSize),
                                              context: context)
        }
    }
    
    // MARK: - Sub-Drawing Methods
    
    private func drawWindowControls(context: CGContext) {
        let controls: [(ModernSkinElements.Element, String)] = [
            (ModernSkinElements.btnMinimize, "btn_minimize"),
            (ModernSkinElements.btnShade, "btn_shade"),
            (ModernSkinElements.btnClose, "btn_close"),
        ]
        
        for (element, id) in controls {
            let state = pressedElement == id ? "pressed" : "normal"
            renderer.drawWindowControlButton(id, state: state, in: element.defaultRect, context: context)
        }
    }
    
    private func drawTimeDisplay(context: CGContext) {
        let timeDisplayRect = ModernSkinElements.timeDisplay.defaultRect
        let digitWidth = ModernSkinElements.timeDigitSize.width
        let colonWidth = ModernSkinElements.timeColonSize.width
        let digitHeight = ModernSkinElements.timeDigitSize.height
        
        let displayTime: TimeInterval
        let showMinus: Bool
        
        let mode = WindowManager.shared.timeDisplayMode
        if mode == .remaining && duration > 0 {
            displayTime = duration - currentTime
            showMinus = true
        } else {
            displayTime = currentTime
            showMinus = false
        }
        
        let totalSeconds = Int(abs(displayTime))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        // Build character sequence: [-]M:SS
        var chars: [String] = []
        if showMinus { chars.append("-") }
        chars.append("\(minutes)")
        chars.append(":")
        chars.append(String(format: "%02d", seconds))
        
        // Calculate total width to center within time display area
        let allChars = chars.joined()
        var totalWidth: CGFloat = 0
        let digitGap: CGFloat = 1
        for char in allChars {
            totalWidth += (String(char) == ":" ? colonWidth : digitWidth) + digitGap
        }
        totalWidth -= digitGap
        
        // Center horizontally in the time display area, vertically centered
        var x = timeDisplayRect.minX + (timeDisplayRect.width - totalWidth) / 2
        let y = timeDisplayRect.minY + (timeDisplayRect.height - digitHeight) / 2
        
        for char in allChars {
            let charStr = String(char)
            let charWidth = charStr == ":" ? colonWidth : digitWidth
            let rect = NSRect(x: x, y: y, width: charWidth, height: digitHeight)
            renderer.drawTimeDigit(charStr, in: rect, context: context)
            x += charWidth + digitGap
        }
    }
    
    private func drawInfoLabels(context: CGContext) {
        let skin = renderer.skin
        // Use an explicitly small font for info labels to match reference dot-matrix style
        let smallFont = skin.infoFont()
        // Brighter dim color for info labels (more visible than textDim)
        let infoColor = skin.textDimColor
        
        // Bitrate
        if let track = currentTrack, let bitrate = track.bitrate {
            renderer.drawLabel("\(bitrate) kbps",
                               in: ModernSkinElements.infoBitrate.defaultRect,
                               font: smallFont, color: infoColor, context: context)
        }
        
        // Sample rate
        if let track = currentTrack, let sampleRate = track.sampleRate {
            let rateKHz = sampleRate >= 1000 ? "\(sampleRate / 1000) khz" : "\(sampleRate) hz"
            renderer.drawLabel(rateKHz,
                               in: ModernSkinElements.infoSampleRate.defaultRect,
                               font: smallFont, color: infoColor, context: context)
        }
        
        // BPM (with optional multiplier from double-click cycling)
        if let bpm = currentBPM, bpm > 0 {
            let displayBPM: Int
            switch bpmMultiplierState {
            case 1:  displayBPM = bpm * 2
            case 2:  displayBPM = max(1, bpm / 2)
            default: displayBPM = bpm
            }
            renderer.drawLabel("\(displayBPM) bpm",
                               in: ModernSkinElements.infoBPM.defaultRect,
                               font: smallFont, color: infoColor, context: context)
        }
        
        // Stereo/Mono -- brighter, with glow
        let isStereo = currentTrack?.channels ?? 2 >= 2
        let stereoLabel = isStereo ? "STEREO" : "MONO"
        renderer.drawLabelWithGlow(stereoLabel,
                                   in: ModernSkinElements.infoStereo.defaultRect,
                                   font: smallFont, color: skin.textColor,
                                   alignment: .right, context: context)
        
        // Casting indicator -- bright accent when active, hidden when off
        let isCasting = CastManager.shared.isCasting
        if isCasting {
            let castColor = skin.elementColor(for: "info_cast")
            renderer.drawLabelWithGlow("CASTING",
                                       in: ModernSkinElements.infoCast.defaultRect,
                                       font: smallFont, color: castColor,
                                       alignment: .right, context: context)
        }
    }
    
    private func drawSeekBar(context: CGContext) {
        let trackRect = ModernSkinElements.seekTrack.defaultRect
        let position: CGFloat
        
        if let dragPos = seekDragPosition {
            position = dragPos
        } else if duration > 0 {
            position = CGFloat(currentTime / duration)
        } else {
            position = 0
        }
        
        // Seek bar fill color: use element override if set, otherwise accent color
        let seekColor = renderer.skin.elementColor(for: "seek_fill")
        renderer.drawSlider(trackId: "seek_track", fillId: "seek_fill", thumbId: "seek_thumb",
                            trackRect: trackRect, fillFraction: position,
                            thumbState: isDraggingSeek ? "pressed" : "normal",
                            context: context,
                            gradient: (seekColor, seekColor))
    }
    
    private func drawVolumeSlider(context: CGContext) {
        let trackRect = ModernSkinElements.volumeTrack.defaultRect
        let volume = CGFloat(WindowManager.shared.audioEngine.volume)
        
        // Use same color as seek bar fill for visual consistency
        let volColor = renderer.skin.elementColor(for: "seek_fill")
        renderer.drawSlider(trackId: "volume_track", fillId: "volume_fill", thumbId: "volume_thumb",
                            trackRect: trackRect, fillFraction: volume,
                            thumbState: isDraggingVolume ? "pressed" : "normal",
                            context: context,
                            gradient: (volColor, volColor))
    }
    
    private func drawTransportButtons(context: CGContext) {
        let buttons: [(ModernSkinElements.Element, String)] = [
            (ModernSkinElements.btnPrev, "btn_prev"),
            (ModernSkinElements.btnPlay, "btn_play"),
            (ModernSkinElements.btnPause, "btn_pause"),
            (ModernSkinElements.btnStop, "btn_stop"),
            (ModernSkinElements.btnNext, "btn_next"),
            (ModernSkinElements.btnEject, "btn_eject"),
        ]
        
        for (element, id) in buttons {
            let state = pressedElement == id ? "pressed" : "normal"
            renderer.drawTransportButton(id, state: state, in: element.defaultRect, context: context)
        }
    }
    
    private func drawEQPlaylistButtons(context: CGContext) {
        let audioEngine = WindowManager.shared.audioEngine
        
        // 10 toggle buttons aligned with marquee panel (x:93 to x:267)
        let y: CGFloat = 42
        let h: CGFloat = 14
        let leftEdge: CGFloat = 93   // Match marquee left edge
        let rightEdge: CGFloat = 269  // Match marquee right edge
        let w: CGFloat = 16
        let spacing = (rightEdge - leftEdge - 10 * w) / 9  // ~1.56
        let startX = leftEdge
        
        let buttonDefs: [(String, String, Bool)] = [
            ("btn_shuffle", "SH", audioEngine.shuffleEnabled),
            ("btn_repeat", "RP", audioEngine.repeatEnabled),
            ("btn_cast", "CA", CastManager.shared.isCasting),
            ("btn_sk", "SK", false),
            ("btn_projectm", "pM", WindowManager.shared.isProjectMVisible),
            ("btn_eq", "EQ", WindowManager.shared.isEqualizerVisible),
            ("btn_playlist", "PL", WindowManager.shared.isPlaylistVisible),
            ("btn_spectrum", "SP", WindowManager.shared.isSpectrumVisible),
            ("btn_waveform", "WV", WindowManager.shared.isWaveformVisible),
            ("btn_library", "LB", WindowManager.shared.isPlexBrowserVisible),
        ]
        
        for (i, (id, label, isOn)) in buttonDefs.enumerated() {
            let x = startX + CGFloat(i) * (w + spacing)
            let rect = NSRect(x: x, y: y, width: w, height: h)
            renderer.drawToggleButton(id, isOn: isOn, isPressed: pressedElement == id,
                                      label: label, in: rect, context: context)
        }
    }
    
    // MARK: - State Helpers
    
    private func effectivePlaybackState() -> PlaybackState {
        if WindowManager.shared.isVideoActivePlayback {
            return WindowManager.shared.videoPlaybackState
        }
        return WindowManager.shared.audioEngine.state
    }
    
    // MARK: - Public Update Methods
    
    func updateTime(current: TimeInterval, duration: TimeInterval) {
        // Change detection: only redraw when seconds digit actually changes
        let oldSeconds = Int(self.currentTime)
        let newSeconds = Int(current)
        let durationChanged = abs(self.duration - duration) > 0.5
        
        self.currentTime = current
        self.duration = duration
        
        guard oldSeconds != newSeconds || durationChanged else { return }
        
        // Invalidate only the time display and seek bar regions (not the entire window)
        let timeRect = scaledRect(ModernSkinElements.timeDisplay.defaultRect)
        setNeedsDisplay(timeRect.insetBy(dx: -2, dy: -2))
        
        let seekRect = scaledRect(ModernSkinElements.seekTrack.defaultRect).insetBy(dx: 0, dy: -6 * scale)
        setNeedsDisplay(seekRect)
    }
    
    func updateTrackInfo(_ track: Track?) {
        self.currentTrack = track
        self.videoTitle = nil
        self.currentBPM = nil  // Reset BPM for new track
        self.bpmMultiplierState = 2  // Reset multiplier for new track (default to 0.5x)
        refreshMarqueeText()
        needsDisplay = true
    }
    
    func updateVideoTrackInfo(title: String) {
        self.videoTitle = title
        refreshMarqueeText()
        needsDisplay = true
    }
    
    func clearVideoTrackInfo() {
        self.videoTitle = nil
        refreshMarqueeText()
        needsDisplay = true
    }
    
    func updateSpectrum(_ levels: [Float]) {
        guard !levels.isEmpty else { return }
        
        // Always forward to Metal overlay (it has its own frame pacing via CVDisplayLink)
        if mainVisMode.usesMetal {
            metalOverlay?.updateSpectrum(levels)
        }
        
        // Throttle CPU-rendered mini spectrum to 20Hz (the 8-bar display doesn't need 60Hz)
        guard mainVisMode == .spectrum else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastMiniSpectrumUpdate >= 0.05 else { return }
        lastMiniSpectrumUpdate = now
        
        // Downsample the full spectrum (75 bins) to 8 bars for mini display
        let barCount = 8
        let binCount = levels.count
        var downsampled = [Float](repeating: 0, count: barCount)
        
        for i in 0..<barCount {
            // Use logarithmic distribution for more musical frequency representation
            let startFrac = Float(i) / Float(barCount)
            let endFrac = Float(i + 1) / Float(barCount)
            
            // Logarithmic mapping: more bins for lower frequencies
            let logStart = Int(pow(startFrac, 0.7) * Float(binCount))
            let logEnd = max(logStart + 1, Int(pow(endFrac, 0.7) * Float(binCount)))
            
            let start = min(logStart, binCount - 1)
            let end = min(logEnd, binCount)
            
            // Average across the range — peak-of-peak causes bars to pin high
            // since adaptive normalization already compresses toward 1.0.
            var sum: Float = 0
            for j in start..<end { sum += levels[j] }
            downsampled[i] = end > start ? sum / Float(end - start) : 0
        }
        
        self.spectrumLevels = downsampled
        
        // Only invalidate the spectrum area, not the whole window
        let specRect = scaledRect(ModernSkinElements.spectrumArea.defaultRect)
        setNeedsDisplay(specRect.insetBy(dx: -2, dy: -2))
    }
    
    func skinDidChange() {
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)
        setupGridBackground(skin: skin)
        marqueeLayer.configure(with: skin)
        updateMarqueeOpacity()
        updateSpectrumOverlayOpacity()
        refreshMarqueeText()
        updateMarqueeForMode()
        updateCornerMask()
        
        // Reposition metal overlay to match new scale
        if let overlay = metalOverlay {
            overlay.frame = currentMainSpectrumOverlayRect()
            updateMainSpectrumOverlayGeometryAndStyle()
        }
        
        needsDisplay = true
    }
    
    /// Reposition the marquee for normal or shade mode
    private func updateMarqueeForMode() {
        if isShadeMode {
            // In shade mode, place marquee in the middle of the compact strip
            let shadeH = ModernMainWindowController.shadeHeight
            let marqueeX: CGFloat = 80 * scale  // after "NULLPLAYER" title
            let marqueeW: CGFloat = 160 * scale  // space before close buttons
            marqueeLayer.frame = NSRect(x: marqueeX, y: 2 * scale, width: marqueeW, height: shadeH - 4 * scale)
            marqueeLayer.isHidden = false
            gridLayer?.isHidden = true
            metalOverlay?.isHidden = true
        } else {
            // Normal mode marquee positioning
            let marqueeRect = scaledRect(ModernSkinElements.marqueeBackground.defaultRect)
            let inset: CGFloat = 4 * scale
            marqueeLayer.frame = NSRect(x: marqueeRect.minX + inset,
                                        y: marqueeRect.minY + marqueeRect.height * 0.35,
                                        width: marqueeRect.width - inset * 2,
                                        height: marqueeRect.height * 0.55)
            marqueeLayer.isHidden = false
            gridLayer?.isHidden = false
            if mainVisMode.usesMetal {
                metalOverlay?.isHidden = false
            }
        }
        // Force re-render text at new size
        marqueeLayer.text = marqueeLayer.text
    }

    /// Apply `window.areaOpacity.trackDisplay.content` (and `mainWindow.content`) to the marquee layer,
    /// which is rendered as a separate CALayer outside CGContext draw passes.
    private func updateMarqueeOpacity() {
        // Keep marquee text opacity independent from window/content alpha channels.
        // Text opacity is applied through text color (`window.textOpacity`) in ModernMarqueeLayer.
        marqueeLayer?.opacity = 1.0
    }

    /// Apply spectrum content opacity to the optional Metal overlay view.
    private func updateSpectrumOverlayOpacity() {
        if mainVisMode == .visClassicExact && isMainVisClassicTransparentEnabled() {
            let visClassicOpacity = CGFloat(VisClassicBridge.opacityDefault(for: .mainWindow) ?? 1.0)
            let clamped = min(1.0, max(0.0, visClassicOpacity))
            metalOverlay?.alphaValue = clamped
            metalOverlay?.layer?.opacity = Float(clamped)
            return
        }

        let skin = renderer.skin
        if let spectrumOverride = skin.mainSpectrumOpacityOverride {
            metalOverlay?.alphaValue = spectrumOverride
            metalOverlay?.layer?.opacity = Float(spectrumOverride)
        } else {
            let mainContentOpacity = skin.resolvedOpacity(for: .mainWindow).content
            let spectrumContentOpacity = skin.resolvedOpacity(for: .spectrumArea).content
            let alpha = min(1.0, max(0.0, mainContentOpacity * spectrumContentOpacity))
            metalOverlay?.alphaValue = alpha
            metalOverlay?.layer?.opacity = Float(alpha)
        }
    }

    private func drawContentUnattenuated(context: CGContext, draw: () -> Void) {
        context.saveGState()
        context.setAlpha(1.0)
        draw()
        context.restoreGState()
    }

    private func withContextAlpha(_ alpha: CGFloat, context: CGContext, draw: () -> Void) {
        let resolvedAlpha = min(1.0, max(0.0, alpha))
        context.saveGState()
        context.setAlpha(resolvedAlpha)
        draw()
        context.restoreGState()
    }
    
    @objc private func modernSkinDidChange() {
        skinDidChange()
    }
    
    @objc private func doubleSizeChanged() {
        skinDidChange()
    }
    
    @objc private func bpmDidUpdate(_ notification: Notification) {
        guard let bpm = notification.userInfo?["bpm"] as? Int else { return }
        let newBPM = bpm > 0 ? bpm : nil
        guard newBPM != currentBPM else { return }
        currentBPM = newBPM
        // Only invalidate the info panel area where BPM is displayed
        let infoRect = scaledRect(ModernSkinElements.marqueeBackground.defaultRect)
        setNeedsDisplay(infoRect)
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

    @objc private func radioMetadataDidChange() {
        guard RadioManager.shared.isActive else { return }
        refreshMarqueeText()
        needsDisplay = true
    }

    @objc private func radioConnectionStateDidChange() {
        guard RadioManager.shared.isActive else { return }
        refreshMarqueeText()
        needsDisplay = true
    }

    private func marqueeDisplayText() -> String {
        if let title = videoTitle {
            return title
        }

        if RadioManager.shared.isActive {
            if let status = RadioManager.shared.statusText, !status.isEmpty {
                return status
            }
            return currentTrack?.displayTitle ?? "Radio"
        }

        return currentTrack?.displayTitle ?? ""
    }

    private func refreshMarqueeText() {
        marqueeLayer.text = marqueeDisplayText().uppercased()
    }
    
    
    // MARK: - Visualization Mode
    
    /// Cycle through visualization modes on the mini spectrum area
    private func cycleMainVisMode() {
        let allModes = MainWindowVisMode.allCases
        guard let currentIndex = allModes.firstIndex(of: mainVisMode) else {
            mainVisMode = .spectrum
            return
        }
        // Skip modes whose shader file is missing
        var nextIndex = allModes.index(after: currentIndex)
        if nextIndex >= allModes.endIndex { nextIndex = allModes.startIndex }
        let startIndex = nextIndex
        while true {
            let mode = allModes[nextIndex]
            if let qualityMode = mode.spectrumQualityMode,
               !SpectrumAnalyzerView.isShaderAvailable(for: qualityMode) {
                nextIndex = allModes.index(after: nextIndex)
                if nextIndex >= allModes.endIndex { nextIndex = allModes.startIndex }
                if nextIndex == startIndex { break }  // All modes checked, none available
                continue
            }
            mainVisMode = mode
            NSLog("ModernMainWindow: Vis mode changed to %@", mainVisMode.rawValue)
            return
        }
        mainVisMode = .spectrum  // Fallback if nothing available
    }
    
    /// Set up or update the Metal overlay for GPU-rendered modes
    private func updateMetalOverlay() {
        if mainVisMode.usesMetal {
            if metalOverlay == nil {
                let specRect = currentMainSpectrumOverlayRect()
                let overlay = SpectrumAnalyzerView(frame: specRect)
                overlay.isEmbedded = true  // prevent contamination of "spectrumQualityMode" UserDefaults
                overlay.wantsLayer = true
                overlay.layer?.cornerRadius = 4 * scale
                overlay.layer?.masksToBounds = true
                overlay.layer?.backgroundColor = NSColor.clear.cgColor
                overlay.layer?.isOpaque = false

                // Set spectrum colors from modern skin
                if let skin = ModernSkinEngine.shared.currentSkin {
                    overlay.spectrumColors = skin.spectrumColors()
                }

                // Load mode-specific settings from main-window-specific keys
                if let savedStyle = UserDefaults.standard.string(forKey: "mainWindowFlameStyle"),
                   let style = FlameStyle(rawValue: savedStyle) { overlay.flameStyle = style }
                if let savedIntensity = UserDefaults.standard.string(forKey: "mainWindowFlameIntensity"),
                   let intensity = FlameIntensity(rawValue: savedIntensity) { overlay.flameIntensity = intensity }
                if let savedStyle = UserDefaults.standard.string(forKey: "mainWindowLightningStyle"),
                   let style = LightningStyle(rawValue: savedStyle) { overlay.lightningStyle = style }
                if let savedScheme = UserDefaults.standard.string(forKey: "mainWindowMatrixColorScheme"),
                   let scheme = MatrixColorScheme(rawValue: savedScheme) { overlay.matrixColorScheme = scheme }
                if let savedIntensity = UserDefaults.standard.string(forKey: "mainWindowMatrixIntensity"),
                   let intensity = MatrixIntensity(rawValue: savedIntensity) { overlay.matrixIntensity = intensity }
                if let savedDecay = UserDefaults.standard.string(forKey: "mainWindowDecayMode"),
                   let mode = SpectrumDecayMode(rawValue: savedDecay) { overlay.decayMode = mode }

                addSubview(overlay)
                metalOverlay = overlay
            }

            if let qualityMode = mainVisMode.spectrumQualityMode {
                metalOverlay?.qualityMode = qualityMode
            }
            if mainVisMode == .visClassicExact {
                let enabled = VisClassicBridge.transparentBgDefault(for: .mainWindow)
                _ = metalOverlay?.setVisClassicTransparentBackground(enabled)
            }
            updateMainSpectrumOverlayGeometryAndStyle()
            updateSpectrumOverlayOpacity()
            metalOverlay?.isHidden = false
            metalOverlay?.startDisplayLink()
        } else {
            metalOverlay?.isHidden = true
            metalOverlay?.stopDisplayLink()
        }
        needsDisplay = true
    }
    
    private func restoreVisMode() {
        if let savedMode = UserDefaults.standard.string(forKey: "modernMainWindowVisMode"),
           let mode = MainWindowVisMode(rawValue: savedMode) {
            // Validate shader availability before restoring a GPU mode — if the shader file
            // is missing (e.g., not included in DMG), fall back to Spectrum to prevent crashes
            if let qualityMode = mode.spectrumQualityMode,
               !SpectrumAnalyzerView.isShaderAvailable(for: qualityMode) {
                NSLog("ModernMainWindowView: Shader unavailable for \(mode.rawValue), falling back to Spectrum")
                mainVisMode = .spectrum
            } else {
                mainVisMode = mode
            }
        }
    }
    
    @objc private func connectedWindowHighlightDidChange(_ notification: Notification) {
        let highlighted = notification.userInfo?["highlightedWindows"] as? Set<NSWindow> ?? []
        let newValue = highlighted.contains { $0 === window }
        if isHighlighted != newValue {
            isHighlighted = newValue
            needsDisplay = true
        }
    }

    @objc private func mainVisSettingsChanged() {
        if let savedMode = UserDefaults.standard.string(forKey: "mainWindowVisMode"),
           let mode = MainWindowVisMode(rawValue: savedMode) {
            if let qualityMode = mode.spectrumQualityMode,
               !SpectrumAnalyzerView.isShaderAvailable(for: qualityMode) {
                return
            }
            if mode != mainVisMode {
                mainVisMode = mode
            }
        }
        if let overlay = metalOverlay {
            if let qualityMode = mainVisMode.spectrumQualityMode {
                overlay.qualityMode = qualityMode
            }
            if let savedStyle = UserDefaults.standard.string(forKey: "mainWindowFlameStyle"),
               let style = FlameStyle(rawValue: savedStyle) { overlay.flameStyle = style }
            if let savedIntensity = UserDefaults.standard.string(forKey: "mainWindowFlameIntensity"),
               let intensity = FlameIntensity(rawValue: savedIntensity) { overlay.flameIntensity = intensity }
            if let savedStyle = UserDefaults.standard.string(forKey: "mainWindowLightningStyle"),
               let style = LightningStyle(rawValue: savedStyle) { overlay.lightningStyle = style }
            if let savedScheme = UserDefaults.standard.string(forKey: "mainWindowMatrixColorScheme"),
               let scheme = MatrixColorScheme(rawValue: savedScheme) { overlay.matrixColorScheme = scheme }
            if let savedIntensity = UserDefaults.standard.string(forKey: "mainWindowMatrixIntensity"),
               let intensity = MatrixIntensity(rawValue: savedIntensity) { overlay.matrixIntensity = intensity }
            if let savedDecay = UserDefaults.standard.string(forKey: "mainWindowDecayMode"),
               let mode = SpectrumDecayMode(rawValue: savedDecay) { overlay.decayMode = mode }
            if mainVisMode == .visClassicExact {
                let enabled = VisClassicBridge.transparentBgDefault(for: .mainWindow)
                _ = overlay.setVisClassicTransparentBackground(enabled)
            }
            updateMainSpectrumOverlayGeometryAndStyle()
        }
        updateSpectrumOverlayOpacity()
    }

    @objc private func handleVisClassicProfileCommand(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let command = userInfo["command"] as? String,
              (command == "transparentBg" || command == "opacity"),
              (userInfo["target"] as? String) == "mainWindow" else { return }

        let enabled = (userInfo["enabled"] as? Bool)
            ?? VisClassicBridge.transparentBgDefault(for: .mainWindow)
        if mainVisMode == .visClassicExact {
            _ = metalOverlay?.setVisClassicTransparentBackground(enabled)
        }
        updateMainSpectrumOverlayGeometryAndStyle()
        updateSpectrumOverlayOpacity()
        invalidateElement("spectrum_area")
    }

    // MARK: - Hit Testing
    
    /// Scale and convert a point from view coordinates to base coordinates
    private func basePoint(from viewPoint: NSPoint) -> NSPoint {
        let yScale = scale * contentLayoutScaleY
        return NSPoint(x: viewPoint.x / scale, y: viewPoint.y / yScale)
    }
    
    /// Scale a rect from base to view coordinates
    private func scaledRect(_ rect: NSRect) -> NSRect {
        let yScale = contentLayoutScaleY
        return NSRect(x: rect.origin.x * scale, y: rect.origin.y * scale * yScale,
                      width: rect.size.width * scale, height: rect.size.height * scale * yScale)
    }

    private func isMainVisClassicTransparentEnabled() -> Bool {
        if let overlay = metalOverlay {
            return overlay.visClassicTransparentBackgroundEnabled()
                || VisClassicBridge.transparentBgDefault(for: .mainWindow)
        }
        return VisClassicBridge.transparentBgDefault(for: .mainWindow)
    }

    private func currentMainSpectrumOverlayRect() -> NSRect {
        var baseRect = ModernSkinElements.spectrumArea.defaultRect
        if mainVisMode == .visClassicExact && isMainVisClassicTransparentEnabled() {
            baseRect = baseRect.insetBy(dx: 2, dy: 2)
        }
        return scaledRect(baseRect)
    }

    private func updateMainSpectrumOverlayGeometryAndStyle() {
        guard let overlay = metalOverlay else { return }
        overlay.frame = currentMainSpectrumOverlayRect()
        overlay.layer?.cornerRadius = 4 * scale
        overlay.layer?.masksToBounds = true
        overlay.layer?.backgroundColor = NSColor.clear.cgColor
        overlay.layer?.isOpaque = false
    }
    
    /// Invalidate the screen region for a given element ID (for targeted partial redraws)
    private func invalidateElement(_ elementId: String) {
        let rect: NSRect
        switch elementId {
        case "seek_track":
            rect = scaledRect(ModernSkinElements.seekTrack.defaultRect).insetBy(dx: 0, dy: -6 * scale)
        case "volume_track":
            rect = scaledRect(ModernSkinElements.volumeTrack.defaultRect).insetBy(dx: 0, dy: -6 * scale)
        case "time_display":
            rect = scaledRect(ModernSkinElements.timeDisplay.defaultRect).insetBy(dx: -2, dy: -2)
        case "info_bpm":
            rect = scaledRect(ModernSkinElements.marqueeBackground.defaultRect)
        case "spectrum_area":
            rect = scaledRect(ModernSkinElements.spectrumArea.defaultRect)
        case "btn_prev", "btn_play", "btn_pause", "btn_stop", "btn_next", "btn_eject":
            rect = scaledRect(NSRect(x: 6, y: 3, width: 168, height: 24))
        case "btn_close", "btn_minimize", "btn_shade":
            rect = scaledRect(ModernSkinElements.titleBar.defaultRect)
        case let id where id.hasPrefix("btn_"):
            // Toggle buttons (EQ, PL, SH, 2X, etc.)
            rect = scaledRect(NSRect(x: 93, y: 42, width: 176, height: 14))
        default:
            needsDisplay = true
            return
        }
        setNeedsDisplay(rect)
    }
    
    private func hitTest(point: NSPoint) -> String? {
        let base = basePoint(from: point)
        
        // In shade mode, only close and shade buttons are active
        if isShadeMode {
            let baseH: CGFloat = 18
            let btnSize: CGFloat = 8
            let btnY = (baseH - btnSize) / 2
            let shadeRect = NSRect(x: 255, y: btnY, width: btnSize, height: btnSize)
            let closeRect = NSRect(x: 265, y: btnY, width: btnSize, height: btnSize)
            if closeRect.contains(base) { return "btn_close" }
            if shadeRect.contains(base) { return "btn_shade" }
            return nil
        }
        
        // Check elements in priority order (front to back)
        var hitTargets: [(String, NSRect)] = []
        
        // Window controls
        if !WindowManager.shared.effectiveHideTitleBars(for: self.window) {
            hitTargets.append(contentsOf: [
                ("btn_close", ModernSkinElements.btnClose.defaultRect),
                ("btn_minimize", ModernSkinElements.btnMinimize.defaultRect),
                ("btn_shade", ModernSkinElements.btnShade.defaultRect),
            ])
        }
        
        hitTargets.append(contentsOf: [
            // Transport
            ("btn_prev", ModernSkinElements.btnPrev.defaultRect),
            ("btn_play", ModernSkinElements.btnPlay.defaultRect),
            ("btn_pause", ModernSkinElements.btnPause.defaultRect),
            ("btn_stop", ModernSkinElements.btnStop.defaultRect),
            ("btn_next", ModernSkinElements.btnNext.defaultRect),
            ("btn_eject", ModernSkinElements.btnEject.defaultRect),
            // Toggle button row (10 buttons aligned with marquee panel x:93–267)
        ])
        do {
            let leftEdge: CGFloat = 93
            let rightEdge: CGFloat = 269
            let bw: CGFloat = 16
            let bs = (rightEdge - leftEdge - 10 * bw) / 9
            let ids = ["btn_shuffle", "btn_repeat", "btn_cast", "btn_sk",
                       "btn_projectm", "btn_eq", "btn_playlist", "btn_spectrum", "btn_waveform", "btn_library"]
            for (i, id) in ids.enumerated() {
                hitTargets.append((id, NSRect(x: leftEdge + CGFloat(i) * (bw + bs), y: 42, width: bw, height: 14)))
            }
        }
        hitTargets.append(contentsOf: [
            // Sliders
            ("seek_track", ModernSkinElements.seekTrack.defaultRect.insetBy(dx: 0, dy: -4)),  // expand vertical hit area
            ("volume_track", ModernSkinElements.volumeTrack.defaultRect.insetBy(dx: 0, dy: -4)),  // expand vertical hit area
            // BPM display (double-click to cycle multiplier)
            ("info_bpm", ModernSkinElements.infoBPM.defaultRect),
            // Time display (click to toggle elapsed/remaining)
            ("time_display", ModernSkinElements.timeDisplay.defaultRect),
            // Spectrum area (click to toggle spectrum window, double-click to cycle vis mode)
            ("spectrum_area", ModernSkinElements.spectrumArea.defaultRect),
        ])
        
        for (id, rect) in hitTargets {
            if rect.contains(base) {
                return id
            }
        }
        
        return nil
    }
    
    // MARK: - Mouse Events
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // Handle double-click: in shade mode anywhere unshades, in normal mode title bar toggles shade
        if event.clickCount == 2 {
            if isShadeMode {
                controller?.toggleShadeMode()
                updateMarqueeForMode()
                return
            }
            let base = basePoint(from: point)
            let isTitleBarDblClick = ModernSkinElements.titleBar.defaultRect.contains(base)
            if isTitleBarDblClick && !WindowManager.shared.effectiveHideTitleBars(for: self.window) {
                controller?.toggleShadeMode()
                updateMarqueeForMode()
                return
            }
        }
        
        if let element = hitTest(point: point) {
            pressedElement = element
            
            if element == "seek_track" {
                isDraggingSeek = true
                updateSeekPosition(from: point)
            } else if element == "volume_track" {
                isDraggingVolume = true
                updateVolumePosition(from: point)
            } else if element == "time_display" {
                // Toggle time display mode
                let mode = WindowManager.shared.timeDisplayMode
                WindowManager.shared.timeDisplayMode = (mode == .elapsed) ? .remaining : .elapsed
            } else if element == "info_bpm" {
                if event.clickCount == 2 {
                    // Cycle: normal → 2x → 0.5x → normal
                    bpmMultiplierState = (bpmMultiplierState + 1) % 3
                    let infoRect = scaledRect(ModernSkinElements.marqueeBackground.defaultRect)
                    setNeedsDisplay(infoRect)
                }
            } else if element == "spectrum_area" {
                // Handle single-click vs double-click on spectrum area
                if event.clickCount == 2 {
                    visClickTimer?.invalidate()
                    visClickTimer = nil
                    // Double-click: cycle visualization mode
                    cycleMainVisMode()
                } else {
                    // Delayed single-click: toggle spectrum window
                    visClickTimer?.invalidate()
                    visClickTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.doubleClickInterval, repeats: false) { [weak self] _ in
                        self?.visClickTimer = nil
                        WindowManager.shared.toggleSpectrum()
                    }
                }
            }
            
            // Invalidate only the area of the pressed element
            invalidateElement(element)
        } else {
            let base = basePoint(from: point)
            let hideTitleBar = WindowManager.shared.effectiveHideTitleBars(for: self.window)
            let isTitleBar = hideTitleBar || ModernSkinElements.titleBar.defaultRect.contains(base)
            if isTitleBar {
                isDraggingWindow = true
                dragStartPoint = event.locationInWindow
                if let window = window {
                    WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
                }
            }
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        if isDraggingSeek {
            let point = convert(event.locationInWindow, from: nil)
            updateSeekPosition(from: point)
            // Invalidate seek bar + time display only
            let seekRect = scaledRect(ModernSkinElements.seekTrack.defaultRect).insetBy(dx: 0, dy: -6 * scale)
            setNeedsDisplay(seekRect)
            let timeRect = scaledRect(ModernSkinElements.timeDisplay.defaultRect).insetBy(dx: -2, dy: -2)
            setNeedsDisplay(timeRect)
        } else if isDraggingVolume {
            let point = convert(event.locationInWindow, from: nil)
            updateVolumePosition(from: point)
            // Invalidate volume slider area only
            let volRect = scaledRect(ModernSkinElements.volumeTrack.defaultRect).insetBy(dx: 0, dy: -6 * scale)
            setNeedsDisplay(volRect)
        } else if isDraggingWindow, let window = window {
            // Delta-based dragging: apply mouse delta to current window origin each frame
            let currentPoint = event.locationInWindow
            let deltaX = currentPoint.x - dragStartPoint.x
            let deltaY = currentPoint.y - dragStartPoint.y
            
            var newOrigin = window.frame.origin
            newOrigin.x += deltaX
            newOrigin.y += deltaY
            
            newOrigin = WindowManager.shared.windowWillMove(window, to: newOrigin)
            window.setFrameOrigin(newOrigin)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if isDraggingVolume {
            isDraggingVolume = false
            let volRect = scaledRect(ModernSkinElements.volumeTrack.defaultRect).insetBy(dx: 0, dy: -6 * scale)
            setNeedsDisplay(volRect)
        } else if isDraggingSeek {
            isDraggingSeek = false
            if let pos = seekDragPosition {
                let seekTime = Double(pos) * duration
                if WindowManager.shared.isVideoActivePlayback {
                    WindowManager.shared.seekVideo(to: seekTime)
                } else {
                    WindowManager.shared.audioEngine.seek(to: seekTime)
                }
                seekDragPosition = nil
            }
        } else if isDraggingWindow {
            isDraggingWindow = false
            if let window = window {
                WindowManager.shared.windowDidFinishDragging(window)
            }
        } else if let element = pressedElement {
            // Handle button click (skip spectrum_area - handled in mouseDown with timer)
            if element != "spectrum_area" {
                handleButtonClick(element)
            }
        }
        
        if let element = pressedElement {
            pressedElement = nil
            invalidateElement(element)
        } else {
            pressedElement = nil
        }
    }
    
    // MARK: - Slider Interaction
    
    private func updateSeekPosition(from viewPoint: NSPoint) {
        let trackRect = scaledRect(ModernSkinElements.seekTrack.defaultRect)
        let fraction = (viewPoint.x - trackRect.minX) / trackRect.width
        seekDragPosition = min(max(fraction, 0), 1)
    }
    
    private func updateVolumePosition(from viewPoint: NSPoint) {
        let trackRect = scaledRect(ModernSkinElements.volumeTrack.defaultRect)
        let fraction = (viewPoint.x - trackRect.minX) / trackRect.width
        let volume = Float(min(max(fraction, 0), 1))
        WindowManager.shared.audioEngine.volume = volume
    }
    
    // MARK: - Button Actions
    
    private func handleButtonClick(_ elementId: String) {
        let audioEngine = WindowManager.shared.audioEngine
        
        switch elementId {
        case "btn_prev":
            if WindowManager.shared.isVideoActivePlayback {
                WindowManager.shared.skipVideoBackward(10)
            } else {
                audioEngine.previous()
            }
            
        case "btn_play":
            if WindowManager.shared.isVideoActivePlayback {
                WindowManager.shared.toggleVideoPlayPause()
            } else {
                audioEngine.play()
            }
            
        case "btn_pause":
            if WindowManager.shared.isVideoActivePlayback {
                WindowManager.shared.toggleVideoPlayPause()
            } else {
                audioEngine.pause()
            }
            
        case "btn_stop":
            if WindowManager.shared.isVideoActivePlayback {
                WindowManager.shared.stopVideo()
            } else {
                audioEngine.stop()
            }
            
        case "btn_next":
            if WindowManager.shared.isVideoActivePlayback {
                WindowManager.shared.skipVideoForward(10)
            } else {
                audioEngine.next()
            }
            
        case "btn_eject":
            openFileDialog()
            
        case "btn_sk":
            showModernSkinsMenu()
            
        case "btn_shuffle":
            audioEngine.shuffleEnabled.toggle()
            
        case "btn_repeat":
            audioEngine.repeatEnabled.toggle()
            
        case "btn_eq":
            WindowManager.shared.toggleEqualizer()
            
        case "btn_playlist":
            WindowManager.shared.togglePlaylist()
            
        case "btn_close":
            window?.close()
            NSApp.terminate(nil)
            
        case "btn_minimize":
            window?.miniaturize(nil)
            
        case "btn_shade":
            controller?.toggleShadeMode()
            updateMarqueeForMode()
            
        case "btn_library":
            WindowManager.shared.togglePlexBrowser()
            
        case "btn_projectm":
            WindowManager.shared.toggleProjectM()
            
        case "btn_spectrum":
            WindowManager.shared.toggleSpectrum()

        case "btn_waveform":
            WindowManager.shared.toggleWaveform()
            
        case "btn_cast":
            // Show the Output Devices menu at the cast button location
            showCastMenu()
            
        default:
            break
        }
    }
    
    // MARK: - Cast Menu
    
    private func showCastMenu() {
        let menu = ContextMenuBuilder.buildOutputDevicesMenu()
        let btnRect = scaledRect(NSRect(x: 147, y: 42, width: 18, height: 14))
        let menuPoint = NSPoint(x: btnRect.minX, y: btnRect.maxY)
        menu.popUp(positioning: nil, at: menuPoint, in: self)
    }

    private func showModernSkinsMenu() {
        let menu = ContextMenuBuilder.buildModernSkinsMenu()
        let btnRect = scaledRect(NSRect(x: 163, y: 42, width: 18, height: 14))
        let menuPoint = NSPoint(x: btnRect.minX, y: btnRect.maxY)
        menu.popUp(positioning: nil, at: menuPoint, in: self)
    }
    
    // MARK: - File Dialog
    
    private func openFileDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            LocalFileDiscovery.discoverMediaURLsAsync(from: panel.urls, includeVideo: false) { urls in
                guard !urls.isEmpty else { return }
                WindowManager.shared.audioEngine.loadFiles(urls)
                WindowManager.shared.audioEngine.play()
            }
            _ = self
        }
    }
    
    // MARK: - Keyboard Events
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        let audioEngine = WindowManager.shared.audioEngine

        if mainVisMode == .visClassicExact,
           let overlay = metalOverlay,
           let chars = event.charactersIgnoringModifiers {
            if chars == "," {
                _ = overlay.loadPreviousVisClassicProfile()
                return
            }
            if chars == "." {
                _ = overlay.loadNextVisClassicProfile()
                return
            }
        }
        
        switch event.keyCode {
        case 49: // Space - play/pause
            if WindowManager.shared.isVideoActivePlayback {
                WindowManager.shared.toggleVideoPlayPause()
            } else if audioEngine.state == .playing {
                audioEngine.pause()
            } else {
                audioEngine.play()
            }
            
        case 123: // Left arrow - seek backward 5s
            if WindowManager.shared.isVideoActivePlayback {
                WindowManager.shared.skipVideoBackward(5)
            } else {
                audioEngine.seek(to: max(0, audioEngine.currentTime - 5))
            }
            
        case 124: // Right arrow - seek forward 5s
            if WindowManager.shared.isVideoActivePlayback {
                WindowManager.shared.skipVideoForward(5)
            } else {
                audioEngine.seek(to: min(audioEngine.duration, audioEngine.currentTime + 5))
            }
            
        case 125: // Down arrow - volume down
            audioEngine.volume = max(0, audioEngine.volume - 0.05)
            
        case 126: // Up arrow - volume up
            audioEngine.volume = min(1, audioEngine.volume + 0.05)
            
        case 36: // Return - stop
            if WindowManager.shared.isVideoActivePlayback {
                WindowManager.shared.stopVideo()
            } else {
                audioEngine.stop()
            }
            
        default:
            if let chars = event.characters {
                switch chars {
                case "z": audioEngine.previous()
                case "x": audioEngine.play()
                case "c": audioEngine.pause()
                case "v": audioEngine.stop()
                case "b": audioEngine.next()
                case "s": audioEngine.shuffleEnabled.toggle()
                case "r": audioEngine.repeatEnabled.toggle()
                case "l": WindowManager.shared.togglePlexBrowser()
                case "e": WindowManager.shared.toggleEqualizer()
                case "p": WindowManager.shared.togglePlaylist()
                default:
                    super.keyDown(with: event)
                }
            } else {
                super.keyDown(with: event)
            }
        }
        setNeedsDisplay(bounds)
    }

    // MARK: - Context Menu
    
    override func menu(for event: NSEvent) -> NSMenu? {
        return ContextMenuBuilder.buildMenu(includeOutputDevices: false, includeRepeatShuffle: false)
    }
    
    // MARK: - Drag and Drop
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else {
            return false
        }

        guard LocalFileDiscovery.hasSupportedDropContent(items, includeVideo: false) else {
            return false
        }

        LocalFileDiscovery.discoverMediaURLsAsync(from: items, includeVideo: false) { audioURLs in
            guard !audioURLs.isEmpty else { return }
            WindowManager.shared.audioEngine.loadFiles(audioURLs)
            WindowManager.shared.audioEngine.play()
        }
        return true
    }
}
