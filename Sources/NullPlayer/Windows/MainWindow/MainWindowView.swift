import AppKit

/// Visualization mode for the main window's built-in visualization area
enum MainWindowVisMode: String, CaseIterable {
    case spectrum = "Spectrum"       // Classic 19-bar spectrum analyzer (CGContext)
    case fire = "Fire"               // GPU flame simulation (Metal overlay)
    case enhanced = "Enhanced"       // LED matrix with rainbow (Metal overlay)
    case ultra = "Ultra"             // Maximum visual quality (Metal overlay)
    case cosmic = "JWST"             // Procedural nebula (Metal overlay)
    case electricity = "Lightning"   // GPU lightning storm (Metal overlay)
    case matrix = "Matrix"           // Falling digital rain (Metal overlay)
    
    var displayName: String { rawValue }
    
    /// Whether this mode uses the Metal overlay (all modes except spectrum)
    var usesMetal: Bool { self != .spectrum }
    
    /// Map to the corresponding SpectrumQualityMode for the Metal overlay
    var spectrumQualityMode: SpectrumQualityMode? {
        switch self {
        case .spectrum: return nil
        case .fire: return .flame
        case .enhanced: return .enhanced
        case .ultra: return .ultra
        case .cosmic: return .cosmic
        case .electricity: return .electricity
        case .matrix: return .matrix
        }
    }
}

/// Main window view - renders the skin main player interface using skin sprites
class MainWindowView: NSView {
    
    // MARK: - Properties
    
    weak var controller: MainWindowController?
    
    /// Current playback time
    private var currentTime: TimeInterval = 0
    
    /// Track duration
    private var duration: TimeInterval = 0
    
    /// Current track info
    private var currentTrack: Track?
    
    /// Current video title (when video is playing)
    private var currentVideoTitle: String?
    
    /// Whether a local file cast is in progress (shows loading indicator)
    private var isCastingLocalFile: Bool = false
    
    /// Loading animation timer
    private var loadingAnimationTimer: Timer?
    
    /// Loading animation phase (0-1)
    private var loadingAnimationPhase: CGFloat = 0
    
    /// Spectrum analyzer levels
    private var spectrumLevels: [Float] = []
    
    /// Main window visualization mode (spectrum bars vs GPU-rendered modes)
    private var mainVisMode: MainWindowVisMode = .spectrum {
        didSet {
            UserDefaults.standard.set(mainVisMode.rawValue, forKey: "mainWindowVisMode")
            updateMetalOverlayVisibility()
        }
    }
    
    /// Metal-based visualization overlay for all GPU modes (created lazily on first use)
    private var metalOverlay: SpectrumAnalyzerView?
    
    /// Marquee scroll offset
    private var marqueeOffset: CGFloat = 0
    
    /// Bitrate scroll offset (for 4+ digit bitrates)
    private var bitrateScrollOffset: CGFloat = 0
    
    /// Temporary error message to display in marquee (persists until new track loads)
    private var errorMessage: String?
    
    /// Marquee timer (for bitrate scrolling and shade mode)
    private var marqueeTimer: Timer?
    
    /// Layer-based marquee for GPU-accelerated scrolling (normal mode only)
    private var marqueeLayer: MarqueeLayer?
    
    /// Timer for delayed single-click on vis area (to distinguish from double-click)
    private var visClickTimer: Timer?
    
    /// Mouse tracking area
    private var trackingArea: NSTrackingArea?
    
    /// Button being pressed
    private var pressedButton: ButtonType?
    
    /// Dragging state
    
    /// Which slider is being dragged (nil = none)
    private var draggingSlider: SliderType?
    
    /// Position slider drag value (for visual feedback during drag)
    private var dragPositionValue: CGFloat?
    
    /// Timestamp of last seek to ignore stale updates
    private var lastSeekTime: Date?
    
    /// Region manager for hit testing
    private let regionManager = RegionManager.shared
    
    /// Skin renderer
    private var renderer: SkinRenderer {
        return SkinRenderer.current
    }
    
    /// Shade mode state
    private(set) var isShadeMode = false
    
    // MARK: - Toggle States
    
    private var shuffleEnabled: Bool {
        return WindowManager.shared.audioEngine.shuffleEnabled
    }
    
    private var repeatEnabled: Bool {
        return WindowManager.shared.audioEngine.repeatEnabled
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
        
        // Enable layer-backed rendering for better performance
        layer?.backgroundColor = NSColor.clear.cgColor
        
        // Only redraw when explicitly requested via setNeedsDisplay
        // This allows macOS to cache the layer contents between updates
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        
        // Register for drag and drop
        registerForDraggedTypes([.fileURL])
        
        // Restore saved visualization mode
        if let savedMode = UserDefaults.standard.string(forKey: "mainWindowVisMode"),
           let mode = MainWindowVisMode(rawValue: savedMode) {
            mainVisMode = mode
        }
        
        // Setup layer-based marquee for normal mode
        setupMarqueeLayer()
        
        // Setup Metal overlay if a GPU-rendered mode is active
        if mainVisMode.usesMetal {
            setupMetalOverlay()
        }
        
        // Start timer for bitrate scrolling (and shade mode marquee)
        startMarquee()
        
        // Set up tracking area for mouse events
        updateTrackingAreas()
        
        // Set up accessibility identifiers for UI testing
        setupAccessibility()
        
        // Observe time display mode changes
        NotificationCenter.default.addObserver(self, selector: #selector(timeDisplayModeDidChange),
                                               name: .timeDisplayModeDidChange, object: nil)
        
        // Observe casting state changes to update the cast indicator
        NotificationCenter.default.addObserver(self, selector: #selector(castingStateDidChange),
                                               name: CastManager.sessionDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(castingStateDidChange),
                                               name: CastManager.playbackStateDidChangeNotification, object: nil)
        
        // Observe local file cast loading state
        NotificationCenter.default.addObserver(self, selector: #selector(castLoadingStateDidChange),
                                               name: CastManager.trackChangeLoadingNotification, object: nil)
        
        // Observe track load failures to show error in marquee
        NotificationCenter.default.addObserver(self, selector: #selector(trackDidFailToLoad(_:)),
                                               name: .audioTrackDidFailToLoad, object: nil)
        
        // Observe radio stream metadata changes
        NotificationCenter.default.addObserver(self, selector: #selector(radioMetadataDidChange),
                                               name: RadioManager.streamMetadataDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(radioConnectionStateDidChange),
                                               name: RadioManager.connectionStateDidChangeNotification, object: nil)
        
        // Observe window visibility changes to pause/resume timers for CPU efficiency
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidMiniaturize),
                                               name: NSWindow.didMiniaturizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidDeminiaturize),
                                               name: NSWindow.didDeminiaturizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidChangeOcclusionState),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        
        // Observe main window visualization settings changes
        NotificationCenter.default.addObserver(self, selector: #selector(mainVisSettingsChanged),
                                               name: NSNotification.Name("MainWindowVisChanged"), object: nil)
        
        // Observe playback state changes to clear/freeze spectrum on stop/pause
        NotificationCenter.default.addObserver(self, selector: #selector(playbackStateDidChange),
                                               name: .audioPlaybackStateChanged, object: nil)
    }
    
    // MARK: - Accessibility
    
    /// Set up accessibility identifiers for UI testing
    private func setupAccessibility() {
        // Set the view's accessibility identifier
        setAccessibilityIdentifier("mainWindow")
        setAccessibilityRole(.group)
        setAccessibilityLabel("Main Window")
        
        // Note: Since this view uses custom drawing for skin skins,
        // we expose accessibility elements via accessibilityChildren override
        // rather than creating separate subviews. This allows XCUITest to
        // find and interact with the custom-drawn controls.
    }
    
    // MARK: - Marquee Layer (GPU-accelerated scrolling for normal mode)
    
    private func setupMarqueeLayer() {
        wantsLayer = true  // Ensure view is layer-backed (already set in setupView)
        
        marqueeLayer = MarqueeLayer()
        marqueeLayer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        // Set anchorPoint to (0, 0) so position corresponds to top-left corner
        marqueeLayer?.anchorPoint = CGPoint(x: 0, y: 0)
        updateMarqueeLayerFrame()
        updateMarqueeContent()
        layer?.addSublayer(marqueeLayer!)
        
        // Observe display/backing scale changes
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidChangeBackingProperties(_:)),
                                               name: NSWindow.didChangeBackingPropertiesNotification, object: nil)
    }
    
    /// Called when the skin changes (via MainWindowController.skinDidChange)
    func skinDidChange() {
        updateMarqueeContent()
        metalOverlay?.skinDidChange()
    }
    
    @objc private func windowDidChangeBackingProperties(_ notification: Notification) {
        if let scale = window?.backingScaleFactor {
            marqueeLayer?.updateContentsScale(scale)
        }
    }
    
    private func updateMarqueeLayerFrame() {
        guard !isShadeMode else {
            // Hide layer in shade mode - shade mode uses timer-based marquee
            marqueeLayer?.isHidden = true
            return
        }
        
        marqueeLayer?.isHidden = false
        
        let scale = scaleFactor
        let originalSize = Skin.baseMainSize
        let marqueeArea = SkinElements.TextFont.Positions.marqueeArea
        
        // Calculate centering offset (same as in draw())
        let scaledWidth = originalSize.width * scale
        let scaledHeight = originalSize.height * scale
        let offsetX = (bounds.width - scaledWidth) / 2
        let offsetY = (bounds.height - scaledHeight) / 2
        
        // In draw(), after Y-flip and centering, skin coords (x, y) appear at:
        //   viewX (from left) = offsetX + x * scale
        //   viewY (from top) = offsetY + y * scale
        // For CALayer (Y from bottom), we need:
        //   layerY = bounds.height - (offsetY + (skinY + height) * scale)
        let skinBottom = marqueeArea.origin.y + marqueeArea.height
        let layerY = bounds.height - offsetY - skinBottom * scale
        
        // IMPORTANT: Use position/bounds/transform instead of frame/bounds
        // Setting bounds after frame causes frame to recalculate with bounds size.
        // Instead: set bounds (unscaled), position (center), and transform (scale)
        
        // Set bounds to unscaled dimensions - this is the internal coordinate system
        marqueeLayer?.bounds = CGRect(x: 0, y: 0, width: marqueeArea.width, height: marqueeArea.height)
        
        // With anchorPoint at (0,0), position is the top-left corner
        // But anchorPoint defaults to (0.5, 0.5), so position is center
        // Let's use anchorPoint (0, 0) for easier positioning
        marqueeLayer?.anchorPoint = CGPoint(x: 0, y: 0)
        marqueeLayer?.position = CGPoint(x: offsetX + marqueeArea.origin.x * scale, y: layerY)
        
        // Apply scale transform so the layer renders at scaled size on screen
        marqueeLayer?.transform = CATransform3DMakeScale(scale, scale, 1)
    }
    
    private func updateMarqueeContent() {
        guard !isShadeMode else { return }  // Shade mode uses timer-based rendering
        
        let text = getMarqueeDisplayText()
        marqueeLayer?.text = text
        marqueeLayer?.skinTextImage = WindowManager.shared.currentSkin?.text
    }
    
    // MARK: - Metal Overlay (GPU-based visualization in main window vis area)
    
    /// Create the Metal visualization overlay view (lazy initialization)
    private func setupMetalOverlay() {
        guard metalOverlay == nil else { return }
        
        let overlay = SpectrumAnalyzerView(frame: .zero)
        // Mark as embedded BEFORE setting qualityMode to prevent UserDefaults contamination
        overlay.isEmbedded = true
        // Use main window's own normalization key to avoid cross-contamination with spectrum window
        overlay.normalizationUserDefaultsKey = "mainWindowNormalizationMode"
        // Boost brightness for the small main window visualization area
        overlay.brightnessBoost = 2.0
        // Attenuate bass to prevent it overwhelming the tiny display
        overlay.bassAttenuation = 0.5
        // Set quality mode based on current main window vis mode
        if let qualityMode = mainVisMode.spectrumQualityMode {
            overlay.qualityMode = qualityMode
        }
        // Restore all mode-specific settings from main window's own UserDefaults keys
        if let savedStyle = UserDefaults.standard.string(forKey: "mainWindowFlameStyle"),
           let style = FlameStyle(rawValue: savedStyle) {
            overlay.flameStyle = style
        }
        if let savedIntensity = UserDefaults.standard.string(forKey: "mainWindowFlameIntensity"),
           let intensity = FlameIntensity(rawValue: savedIntensity) {
            overlay.flameIntensity = intensity
        }
        if let savedStyle = UserDefaults.standard.string(forKey: "mainWindowLightningStyle"),
           let style = LightningStyle(rawValue: savedStyle) {
            overlay.lightningStyle = style
        }
        if let savedScheme = UserDefaults.standard.string(forKey: "mainWindowMatrixColorScheme"),
           let scheme = MatrixColorScheme(rawValue: savedScheme) {
            overlay.matrixColorScheme = scheme
        }
        if let savedIntensity = UserDefaults.standard.string(forKey: "mainWindowMatrixIntensity"),
           let intensity = MatrixIntensity(rawValue: savedIntensity) {
            overlay.matrixIntensity = intensity
        }
        if let savedDecay = UserDefaults.standard.string(forKey: "mainWindowDecayMode"),
           let mode = SpectrumDecayMode(rawValue: savedDecay) {
            overlay.decayMode = mode
        }
        overlay.isHidden = true
        addSubview(overlay)
        metalOverlay = overlay
        
        updateMetalOverlayFrame()
    }
    
    /// Update Metal overlay position to match the visualization area in scaled skin coordinates
    private func updateMetalOverlayFrame() {
        guard let overlay = metalOverlay, !isShadeMode else {
            metalOverlay?.isHidden = true
            return
        }
        
        // Don't update if bounds are zero (view not yet laid out)
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        let scale = scaleFactor
        let originalSize = Skin.baseMainSize
        let visArea = SkinElements.Visualization.displayArea  // x: 24, y: 43, width: 76, height: 16
        
        // Calculate centering offset (same as in draw())
        let scaledWidth = originalSize.width * scale
        let scaledHeight = originalSize.height * scale
        let offsetX = (bounds.width - scaledWidth) / 2
        let offsetY = (bounds.height - scaledHeight) / 2
        
        // Convert skin coordinates (top-left origin) to macOS view coordinates (bottom-left origin)
        let macX = offsetX + visArea.origin.x * scale
        let macY = bounds.height - offsetY - (visArea.origin.y + visArea.height) * scale
        let width = visArea.width * scale
        let height = visArea.height * scale
        
        overlay.frame = NSRect(x: macX, y: macY, width: width, height: height)
    }
    
    /// Show/hide the Metal overlay based on current vis mode
    private func updateMetalOverlayVisibility() {
        if mainVisMode.usesMetal && !isShadeMode {
            // Create overlay if needed
            if metalOverlay == nil {
                setupMetalOverlay()
            }
            // Update quality mode on the overlay to match current vis mode
            if let qualityMode = mainVisMode.spectrumQualityMode {
                metalOverlay?.qualityMode = qualityMode
            }
            metalOverlay?.isHidden = false
            metalOverlay?.startDisplayLink()
            updateMetalOverlayFrame()
            
            // Force layout to ensure Metal layer gets sized properly
            metalOverlay?.needsLayout = true
            metalOverlay?.layoutSubtreeIfNeeded()
            
            // Feed current spectrum data
            if !spectrumLevels.isEmpty {
                metalOverlay?.updateSpectrum(spectrumLevels)
            }
            
        } else {
            metalOverlay?.isHidden = true
            metalOverlay?.stopDisplayLink()
        }
        needsDisplay = true
    }
    
    /// Cycle the main window visualization mode through all available modes
    private func cycleMainVisMode() {
        let allModes = MainWindowVisMode.allCases
        guard let currentIndex = allModes.firstIndex(of: mainVisMode) else {
            mainVisMode = .spectrum
            return
        }
        let nextIndex = allModes.index(after: currentIndex)
        mainVisMode = (nextIndex < allModes.endIndex) ? allModes[nextIndex] : allModes[allModes.startIndex]
    }
    
    @objc private func mainVisSettingsChanged() {
        // Reload vis mode from UserDefaults
        if let savedMode = UserDefaults.standard.string(forKey: "mainWindowVisMode"),
           let mode = MainWindowVisMode(rawValue: savedMode) {
            if mode != mainVisMode {
                mainVisMode = mode
            }
        }
        // Reload all mode-specific settings if overlay exists (uses main window's own keys)
        if let overlay = metalOverlay {
            // Update quality mode to match current vis mode
            if let qualityMode = mainVisMode.spectrumQualityMode {
                overlay.qualityMode = qualityMode
            }
            // Flame settings
            if let savedStyle = UserDefaults.standard.string(forKey: "mainWindowFlameStyle"),
               let style = FlameStyle(rawValue: savedStyle) {
                overlay.flameStyle = style
            }
            if let savedIntensity = UserDefaults.standard.string(forKey: "mainWindowFlameIntensity"),
               let intensity = FlameIntensity(rawValue: savedIntensity) {
                overlay.flameIntensity = intensity
            }
            // Lightning settings
            if let savedStyle = UserDefaults.standard.string(forKey: "mainWindowLightningStyle"),
               let style = LightningStyle(rawValue: savedStyle) {
                overlay.lightningStyle = style
            }
            // Matrix settings
            if let savedScheme = UserDefaults.standard.string(forKey: "mainWindowMatrixColorScheme"),
               let scheme = MatrixColorScheme(rawValue: savedScheme) {
                overlay.matrixColorScheme = scheme
            }
            if let savedIntensity = UserDefaults.standard.string(forKey: "mainWindowMatrixIntensity"),
               let intensity = MatrixIntensity(rawValue: savedIntensity) {
                overlay.matrixIntensity = intensity
            }
            // Decay/responsiveness
            if let savedDecay = UserDefaults.standard.string(forKey: "mainWindowDecayMode"),
               let mode = SpectrumDecayMode(rawValue: savedDecay) {
                overlay.decayMode = mode
            }
        }
    }
    
    // MARK: - Accessibility Children (for custom drawn controls)
    
    override func accessibilityChildren() -> [Any]? {
        var children: [NSAccessibilityElement] = []
        
        // Get current playback state for button states
        let playbackState = WindowManager.shared.audioEngine.state
        let isPlaying = playbackState == .playing
        
        // Transport buttons - use SkinElements.Transport.Positions
        let transportPositions = SkinElements.Transport.Positions.self
        
        // Play button (hidden when playing, shows pause instead)
        if !isPlaying {
            let playElement = createAccessibilityButton(
                identifier: "mainWindow.playButton",
                label: "Play",
                rect: transportPositions.play
            )
            children.append(playElement)
        }
        
        // Pause button (visible when playing)
        if isPlaying {
            let pauseElement = createAccessibilityButton(
                identifier: "mainWindow.pauseButton",
                label: "Pause",
                rect: transportPositions.pause
            )
            children.append(pauseElement)
        }
        
        // Stop button
        let stopElement = createAccessibilityButton(
            identifier: "mainWindow.stopButton",
            label: "Stop",
            rect: transportPositions.stop
        )
        children.append(stopElement)
        
        // Previous button
        let prevElement = createAccessibilityButton(
            identifier: "mainWindow.previousButton",
            label: "Previous",
            rect: transportPositions.previous
        )
        children.append(prevElement)
        
        // Next button
        let nextElement = createAccessibilityButton(
            identifier: "mainWindow.nextButton",
            label: "Next",
            rect: transportPositions.next
        )
        children.append(nextElement)
        
        // Eject button
        let ejectElement = createAccessibilityButton(
            identifier: "mainWindow.ejectButton",
            label: "Open File",
            rect: transportPositions.eject
        )
        children.append(ejectElement)
        
        // Toggle buttons - use SkinElements.ShuffleRepeat.Positions
        let shuffleElement = createAccessibilityButton(
            identifier: "mainWindow.shuffleButton",
            label: shuffleEnabled ? "Shuffle On" : "Shuffle Off",
            rect: SkinElements.ShuffleRepeat.Positions.shuffle
        )
        children.append(shuffleElement)
        
        let repeatElement = createAccessibilityButton(
            identifier: "mainWindow.repeatButton",
            label: repeatEnabled ? "Repeat On" : "Repeat Off",
            rect: SkinElements.ShuffleRepeat.Positions.repeatBtn
        )
        children.append(repeatElement)
        
        // Sliders
        let seekElement = createAccessibilitySlider(
            identifier: "mainWindow.seekSlider",
            label: "Seek",
            rect: SkinElements.PositionBar.Positions.track,
            value: duration > 0 ? currentTime / duration : 0
        )
        children.append(seekElement)
        
        let volumeElement = createAccessibilitySlider(
            identifier: "mainWindow.volumeSlider",
            label: "Volume",
            rect: SkinElements.Volume.Positions.slider,
            value: Double(WindowManager.shared.audioEngine.volume)
        )
        children.append(volumeElement)
        
        let balanceElement = createAccessibilitySlider(
            identifier: "mainWindow.balanceSlider",
            label: "Balance",
            rect: SkinElements.Balance.Positions.slider,
            value: (Double(WindowManager.shared.audioEngine.balance) + 1) / 2
        )
        children.append(balanceElement)
        
        return children
    }
    
    /// Create an accessibility button element for a given rect
    private func createAccessibilityButton(identifier: String, label: String, rect: NSRect) -> NSAccessibilityElement {
        let element = NSAccessibilityElement()
        element.setAccessibilityIdentifier(identifier)
        element.setAccessibilityLabel(label)
        element.setAccessibilityRole(.button)
        element.setAccessibilityParent(self)
        
        // Convert from skin coordinates (top-left origin) to screen coordinates
        let convertedRect = convertSkinRectToScreen(rect)
        element.setAccessibilityFrame(convertedRect)
        
        return element
    }
    
    /// Create an accessibility slider element for a given rect
    private func createAccessibilitySlider(identifier: String, label: String, rect: NSRect, value: Double) -> NSAccessibilityElement {
        let element = NSAccessibilityElement()
        element.setAccessibilityIdentifier(identifier)
        element.setAccessibilityLabel(label)
        element.setAccessibilityRole(.slider)
        element.setAccessibilityValue(NSNumber(value: value))
        element.setAccessibilityParent(self)
        
        // Convert from skin coordinates to screen coordinates
        let convertedRect = convertSkinRectToScreen(rect)
        element.setAccessibilityFrame(convertedRect)
        
        return element
    }
    
    /// Convert a rect from skin coordinates (top-left origin) to screen coordinates
    private func convertSkinRectToScreen(_ rect: NSRect) -> NSRect {
        let originalHeight = isShadeMode ? SkinElements.MainShade.windowSize.height : Skin.baseMainSize.height
        let scale = scaleFactor
        
        // Convert Y from skin (top-down) to macOS (bottom-up)
        let macY = originalHeight - rect.maxY
        
        // Scale the rect
        let scaledRect = NSRect(
            x: rect.origin.x * scale,
            y: macY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        
        // Convert to screen coordinates
        guard let window = window else { return scaledRect }
        let windowRect = convert(scaledRect, to: nil)
        return window.convertToScreen(windowRect)
    }
    
    deinit {
        marqueeTimer?.invalidate()
        loadingAnimationTimer?.invalidate()
        visClickTimer?.invalidate()
        marqueeLayer?.removeFromSuperlayer()
        metalOverlay?.stopDisplayLink()
        metalOverlay?.removeFromSuperview()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func timeDisplayModeDidChange() {
        needsDisplay = true
    }
    
    @objc private func castingStateDidChange() {
        needsDisplay = true
    }
    
    @objc private func playbackStateDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let state = userInfo["state"] as? PlaybackState else { return }
        
        switch state {
        case .stopped:
            // Clear spectrum bars immediately
            spectrumLevels = Array(repeating: Float(0), count: spectrumLevels.count)
            needsDisplay = true
        case .paused:
            // Freeze - just stop updating (no more updateSpectrum calls will arrive)
            break
        case .playing:
            break
        }
    }
    
    @objc private func castLoadingStateDidChange(_ notification: Notification) {
        guard let isLoading = notification.userInfo?["isLoading"] as? Bool else { return }
        
        NSLog("MainWindowView: castLoadingStateDidChange - isLoading=%d (was %d)", isLoading ? 1 : 0, isCastingLocalFile ? 1 : 0)
        
        isCastingLocalFile = isLoading
        
        if isLoading {
            // Start loading animation (only if window is visible)
            if window?.occlusionState.contains(.visible) == true {
                startLoadingAnimation()
            }
        } else {
            // Stop loading animation
            loadingAnimationTimer?.invalidate()
            loadingAnimationTimer = nil
        }
        
        needsDisplay = true
    }
    
    @objc private func trackDidFailToLoad(_ notification: Notification) {
        guard let message = notification.userInfo?["message"] as? String else { return }
        
        // Show error message in marquee - persists until user loads something else
        errorMessage = "[Error] \(message)"
        updateMarqueeContent()  // Update layer-based marquee
        if isShadeMode { marqueeOffset = 0; startMarquee() }  // Shade mode uses timer
        needsDisplay = true
    }
    
    @objc private func radioMetadataDidChange() {
        // Update marquee when radio stream metadata changes
        updateMarqueeContent()  // Update layer-based marquee
        if isShadeMode { marqueeOffset = 0; startMarquee() }  // Shade mode uses timer
        needsDisplay = true
    }
    
    @objc private func radioConnectionStateDidChange() {
        // Update marquee when radio connection state changes
        updateMarqueeContent()  // Update layer-based marquee
        if isShadeMode { startMarquee() }  // Shade mode uses timer
        needsDisplay = true
    }
    
    /// Get the current display text for the marquee
    private func getMarqueeDisplayText() -> String {
        // Priority 1: Error message
        if let error = errorMessage {
            return error
        }
        
        // Priority 2: Video title (when video is playing)
        if WindowManager.shared.isVideoActivePlayback, let videoTitle = currentVideoTitle {
            return videoTitle
        }
        
        // Priority 3: Radio status/stream title (when radio is active)
        if RadioManager.shared.isActive {
            return RadioManager.shared.statusText ?? "Radio"
        }
        
        // Priority 4: Track title
        return currentTrack?.displayTitle ?? "NullPlayer"
    }
    
    // MARK: - Drawing
    
    /// Calculate scale factor based on current bounds vs original (base) size
    private var scaleFactor: CGFloat {
        let originalSize = isShadeMode ? SkinElements.MainShade.windowSize : Skin.baseMainSize
        let scaleX = bounds.width / originalSize.width
        let scaleY = bounds.height / originalSize.height
        return min(scaleX, scaleY)
    }
    
    /// Convert a point from view coordinates to original (unscaled) coordinates
    private func convertToOriginalCoordinates(_ point: NSPoint) -> NSPoint {
        let originalSize = isShadeMode ? SkinElements.MainShade.windowSize : Skin.baseMainSize
        let scale = scaleFactor
        
        if scale == 1.0 {
            return point
        }
        
        // Calculate the offset (centering)
        let scaledWidth = originalSize.width * scale
        let scaledHeight = originalSize.height * scale
        let offsetX = (bounds.width - scaledWidth) / 2
        let offsetY = (bounds.height - scaledHeight) / 2
        
        // Transform point back to original coordinates
        let x = (point.x - offsetX) / scale
        let y = (point.y - offsetY) / scale
        
        return NSPoint(x: x, y: y)
    }
    
    /// Get the original window size for hit testing (base skin dimensions)
    private var originalWindowSize: NSSize {
        return isShadeMode ? SkinElements.MainShade.windowSize : Skin.baseMainSize
    }
    
    override func layout() {
        super.layout()
        updateMarqueeLayerFrame()
        updateMetalOverlayFrame()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let originalSize = isShadeMode ? SkinElements.MainShade.windowSize : Skin.baseMainSize
        let scale = scaleFactor
        
        // Flip coordinate system to match skin's top-down coordinates
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        
        // Apply scaling for resized window
        if scale != 1.0 {
            // Center the scaled content
            let scaledWidth = originalSize.width * scale
            let scaledHeight = originalSize.height * scale
            let offsetX = (bounds.width - scaledWidth) / 2
            let offsetY = (bounds.height - scaledHeight) / 2
            context.translateBy(x: offsetX, y: offsetY)
            context.scaleBy(x: scale, y: scale)
        }
        
        let skin = WindowManager.shared.currentSkin
        let renderer = SkinRenderer(skin: skin ?? SkinLoader.shared.loadDefault())
        
        // Determine if window is active
        let isActive = window?.isKeyWindow ?? true
        
        // Use original bounds for drawing (scaling is applied via transform)
        let drawBounds = NSRect(origin: .zero, size: originalSize)
        
        if isShadeMode {
            // Draw shade mode (compact view)
            let marqueeText = getMarqueeDisplayText()
            renderer.drawMainWindowShade(
                in: context,
                bounds: drawBounds,
                isActive: isActive,
                currentTime: currentTime,
                duration: duration,
                trackTitle: marqueeText,
                marqueeOffset: marqueeOffset,
                pressedButton: pressedButton
            )
        } else {
            // Draw normal mode with original bounds
            drawNormalModeScaled(renderer: renderer, context: context, isActive: isActive, drawBounds: drawBounds)
        }
        
        context.restoreGState()
        
        // Draw loading overlay if casting local file
        if isCastingLocalFile {
            drawLoadingOverlay(in: context)
        }
    }
    
    /// Draw a semi-transparent loading overlay with pulsing animation
    private func drawLoadingOverlay(in context: CGContext) {
        context.saveGState()
        
        // Semi-transparent dark overlay
        let overlayColor = NSColor(white: 0, alpha: 0.6)
        context.setFillColor(overlayColor.cgColor)
        context.fill(bounds)
        
        // Calculate pulsing alpha (0.5 to 1.0)
        let pulseAlpha = 0.5 + 0.5 * abs(sin(loadingAnimationPhase))
        
        // Draw "Loading..." text centered
        let text = "Loading..."
        let font = NSFont.boldSystemFont(ofSize: 14)
        let textColor = NSColor(white: 1, alpha: CGFloat(pulseAlpha))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let textX = (bounds.width - textSize.width) / 2
        let textY = (bounds.height - textSize.height) / 2
        
        // Flip context for text drawing (AppKit coordinate system)
        context.saveGState()
        text.draw(at: NSPoint(x: textX, y: textY), withAttributes: attributes)
        context.restoreGState()
        
        // Draw spinning dots around the text
        let centerX = bounds.width / 2
        let centerY = bounds.height / 2 + textSize.height + 10
        let dotRadius: CGFloat = 3
        let circleRadius: CGFloat = 15
        let numDots = 8
        
        for i in 0..<numDots {
            let angle = loadingAnimationPhase + CGFloat(i) * (2 * .pi / CGFloat(numDots))
            let dotX = centerX + cos(angle) * circleRadius
            let dotY = centerY + sin(angle) * circleRadius
            
            // Fade dots based on position in rotation
            let dotAlpha = 0.3 + 0.7 * (CGFloat(i) / CGFloat(numDots))
            context.setFillColor(NSColor(white: 1, alpha: dotAlpha).cgColor)
            
            let dotRect = CGRect(x: dotX - dotRadius, y: dotY - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
            context.fillEllipse(in: dotRect)
        }
        
        context.restoreGState()
    }
    
    /// Draw the normal (non-shade) mode with scaling support
    private func drawNormalModeScaled(renderer: SkinRenderer, context: CGContext, isActive: Bool, drawBounds: NSRect) {
        // Draw main window background
        renderer.drawMainWindowBackground(in: context, bounds: drawBounds, isActive: isActive)
        
        // Draw time display - support elapsed/remaining modes
        let displayTime: TimeInterval
        if WindowManager.shared.timeDisplayMode == .remaining && duration > 0 {
            displayTime = currentTime - duration  // Negative value
        } else {
            displayTime = currentTime
        }
        
        let isNegative = displayTime < 0
        let absTime = abs(displayTime)
        let minutes = Int(absTime) / 60
        let seconds = Int(absTime) % 60
        renderer.drawTimeDisplay(minutes: minutes, seconds: seconds, isNegative: isNegative, in: context)
        
        // Note: Song title marquee is rendered by MarqueeLayer (GPU-accelerated)
        // for better performance. The layer is positioned over the marquee area.
        
        // Draw playback status indicator - show video state if video is active
        let playbackState: PlaybackState
        if WindowManager.shared.isVideoActivePlayback {
            playbackState = WindowManager.shared.videoPlaybackState
        } else {
            playbackState = WindowManager.shared.audioEngine.state
        }
        renderer.drawPlaybackStatus(playbackState, in: context)
        
        // Draw stereo and cast indicators
        let isStereo = (currentTrack?.channels ?? 2) >= 2
        let isCasting = CastManager.shared.isCasting
        renderer.drawStereoAndCast(isStereo: isStereo, isCasting: isCasting, in: context)
        
        // Draw bitrate display (e.g., "128" kbps) - scrolls if > 3 digits
        renderer.drawBitrate(currentTrack?.bitrate, scrollOffset: bitrateScrollOffset, in: context)
        
        // Draw sample rate display (e.g., "44" kHz)
        renderer.drawSampleRate(currentTrack?.sampleRate, in: context)
        
        // Draw spectrum analyzer (only in spectrum mode; other modes use Metal overlay)
        if mainVisMode == .spectrum {
            renderer.drawSpectrumAnalyzer(levels: spectrumLevels, in: context)
        }
        // Note: In non-spectrum modes, the Metal overlay renders on top of this area
        
        // Draw position slider (seek bar)
        let positionValue: CGFloat
        if let dragValue = dragPositionValue {
            positionValue = dragValue
        } else {
            positionValue = duration > 0 ? CGFloat(currentTime / duration) : 0
        }
        let positionPressed = draggingSlider == .position
        renderer.drawPositionSlider(value: positionValue, isPressed: positionPressed, in: context)
        
        // Draw volume slider
        let volumeValue = CGFloat(WindowManager.shared.audioEngine.volume)
        let volumePressed = draggingSlider == .volume
        renderer.drawVolumeSlider(value: volumeValue, isPressed: volumePressed, in: context)
        
        // Draw balance slider
        let balanceValue = CGFloat(WindowManager.shared.audioEngine.balance)
        let balancePressed = draggingSlider == .balance
        renderer.drawBalanceSlider(value: balanceValue, isPressed: balancePressed, in: context)
        
        // Draw transport buttons
        renderer.drawTransportButtons(in: context, pressedButton: pressedButton, playbackState: playbackState)
        
        // Draw toggle buttons (shuffle, repeat, EQ, playlist)
        renderer.drawToggleButtons(
            in: context,
            shuffleOn: shuffleEnabled,
            repeatOn: repeatEnabled,
            eqVisible: WindowManager.shared.isEqualizerVisible,
            playlistVisible: WindowManager.shared.isPlaylistVisible,
            pressedButton: pressedButton
        )
        
        // Draw window controls (minimize, shade, close)
        renderer.drawWindowControls(in: context, bounds: drawBounds, pressedButton: pressedButton)
    }
    
    // MARK: - Public Methods
    
    func updateTime(current: TimeInterval, duration: TimeInterval) {
        // Don't update currentTime or redraw if user is dragging the position slider
        if draggingSlider == .position {
            return
        }
        // Ignore stale updates briefly after seeking to let audio engine catch up
        if let lastSeek = lastSeekTime, Date().timeIntervalSince(lastSeek) < 0.3 {
            return
        }
        // Only update if values actually changed (prevents flashing from redundant updates)
        let timeChanged = abs(self.currentTime - current) > 0.05
        let durationChanged = abs(self.duration - duration) > 0.1
        guard timeChanged || durationChanged else { return }
        
        self.currentTime = current
        self.duration = duration
        needsDisplay = true
    }
    
    func updateTrackInfo(_ track: Track?) {
        self.currentTrack = track
        self.currentVideoTitle = nil  // Clear video title when audio track changes
        self.errorMessage = nil  // Clear any error message when track loads successfully
        bitrateScrollOffset = 0  // Reset bitrate scroll
        updateMarqueeContent()  // Update layer-based marquee
        if isShadeMode {
            marqueeOffset = 0
        }
        startMarquee()  // Restart timer for bitrate scrolling (both modes) or shade marquee
        needsDisplay = true
    }
    
    func updateVideoTrackInfo(title: String) {
        self.currentVideoTitle = title
        updateMarqueeContent()  // Update layer-based marquee
        if isShadeMode {
            marqueeOffset = 0
        }
        startMarquee()  // Restart timer for bitrate scrolling (both modes) or shade marquee
        needsDisplay = true
    }
    
    func clearVideoTrackInfo() {
        self.currentVideoTitle = nil
        self.currentTime = 0
        self.duration = 0
        needsDisplay = true
    }
    
    func updateSpectrum(_ levels: [Float]) {
        self.spectrumLevels = levels
        
        // Feed Metal overlay when in a GPU-rendered mode
        if mainVisMode.usesMetal {
            metalOverlay?.updateSpectrum(levels)
        }
        
        // Only redraw the visualization area for performance (spectrum mode)
        if mainVisMode == .spectrum {
            setNeedsDisplay(SkinElements.Visualization.displayArea)
        }
    }
    
    // MARK: - Marquee Animation
    
    // MARK: - Marquee Timer Management
    
    /// Start the marquee timer for text scrolling (8Hz - reduced for CPU efficiency)
    private func startMarquee() {
        guard marqueeTimer == nil else { return }
        // Reduced to 8Hz (0.125s) for CPU efficiency
        // Scroll speed adjusted to maintain visual speed
        marqueeTimer = Timer.scheduledTimer(withTimeInterval: 0.125, repeats: true) { [weak self] _ in
            self?.handleMarqueeTimerTick()
        }
    }
    
    /// Stop the marquee timer to save CPU when window is not visible
    private func stopMarquee() {
        marqueeTimer?.invalidate()
        marqueeTimer = nil
    }
    
    /// Handle marquee timer tick - only for bitrate scrolling and shade mode marquee
    /// (Normal mode marquee is handled by MarqueeLayer for GPU-accelerated performance)
    private func handleMarqueeTimerTick() {
        // Skip updates if window is not visible or occluded
        guard let window = window,
              window.isVisible,
              window.occlusionState.contains(.visible) else {
            return
        }
        
        var needsScrolling = false
        let charWidth = SkinElements.TextFont.charWidth
        
        // Shade mode marquee scrolling (layer-based marquee is hidden in shade mode)
        if isShadeMode {
            let title = isCastingLocalFile ? "Loading..." : getMarqueeDisplayText()
            let textWidth = CGFloat(title.count) * charWidth
            let marqueeWidth = SkinElements.MainShade.textArea.width
            
            if textWidth > marqueeWidth {
                let separatorWidth = charWidth * 5
                let totalCycleWidth = textWidth + separatorWidth
                marqueeOffset += 3
                if marqueeOffset >= totalCycleWidth {
                    marqueeOffset = 0
                }
                needsScrolling = true
            } else if marqueeOffset != 0 {
                marqueeOffset = 0
            }
            
            if needsScrolling {
                needsDisplay = true
            }
        }
        
        // Scroll bitrate if > 3 digits (circular scroll) - both modes
        if let bitrate = currentTrack?.bitrate {
            let kbps = bitrate > 10000 ? bitrate / 1000 : bitrate
            let bitrateText = "\(kbps)"
            if bitrateText.count > 3 {
                let bitrateTextWidth = CGFloat(bitrateText.count) * charWidth
                let spacing = charWidth * 2
                let totalWidth = bitrateTextWidth + spacing
                
                bitrateScrollOffset += 0.1
                if bitrateScrollOffset >= totalWidth {
                    bitrateScrollOffset = 0
                }
                setNeedsDisplay(SkinElements.InfoDisplay.Positions.bitrate)
                needsScrolling = true
            }
        } else {
            bitrateScrollOffset = 0
        }
        
        // CPU optimization: Stop the timer when nothing needs scrolling
        // It will restart when track changes or new content arrives
        if !needsScrolling && !isShadeMode {
            stopMarquee()
        }
    }
    
    @objc private func windowDidMiniaturize(_ notification: Notification) {
        guard notification.object as? NSWindow == window else { return }
        stopMarquee()
        marqueeLayer?.pauseAnimation()
        loadingAnimationTimer?.invalidate()
        loadingAnimationTimer = nil
        // Pause Metal overlay rendering
        if mainVisMode.usesMetal { metalOverlay?.stopDisplayLink() }
    }
    
    /// Restart timers when window is restored from minimized state
    @objc private func windowDidDeminiaturize(_ notification: Notification) {
        guard notification.object as? NSWindow == window else { return }
        startMarquee()
        marqueeLayer?.resumeAnimation()
        // Restart loading animation if needed
        if isCastingLocalFile {
            startLoadingAnimation()
        }
        // Resume Metal overlay rendering
        if mainVisMode.usesMetal { metalOverlay?.startDisplayLink() }
    }
    
    /// Handle window occlusion state changes to pause/resume timers for CPU efficiency
    @objc private func windowDidChangeOcclusionState(_ notification: Notification) {
        guard notification.object as? NSWindow == window else { return }
        if window?.occlusionState.contains(.visible) == true {
            startMarquee()
            marqueeLayer?.resumeAnimation()
            if isCastingLocalFile {
                startLoadingAnimation()
            }
            // Resume Metal overlay rendering
            if mainVisMode.usesMetal { metalOverlay?.startDisplayLink() }
        } else {
            stopMarquee()
            marqueeLayer?.pauseAnimation()
            loadingAnimationTimer?.invalidate()
            loadingAnimationTimer = nil
            // Pause Metal overlay rendering
            if mainVisMode.usesMetal { metalOverlay?.stopDisplayLink() }
        }
    }
    
    /// Start the loading animation for cast loading state (10Hz)
    private func startLoadingAnimation() {
        guard loadingAnimationTimer == nil else { return }
        loadingAnimationPhase = 0
        // Reduced from 20Hz (0.05s) to 10Hz (0.1s) - still smooth enough for loading animation
        loadingAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.loadingAnimationPhase += 0.1
            if self.loadingAnimationPhase > 2 * .pi {
                self.loadingAnimationPhase = 0
            }
            self.needsDisplay = true
        }
    }
    
    // MARK: - Mouse Events
    
    /// Track if we're dragging the window
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    
    /// Allow clicking even when window is not active
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func updateTrackingAreas() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }
    
    override func cursorUpdate(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = convertToOriginalCoordinates(viewPoint)
        let cursor = regionManager.cursor(for: point, in: .main, windowSize: originalWindowSize)
        cursor.set()
    }
    
    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = convertToOriginalCoordinates(viewPoint)
        let hitTestSize = originalWindowSize
        
        // Click on visualization display area
        // Convert to skin coordinates (top-down Y axis) for comparison
        let skinY = originalWindowSize.height - point.y
        let spectrumArea = SkinElements.Visualization.displayArea  // x: 24, y: 43, width: 76, height: 16
        let spectrumRect = NSRect(x: spectrumArea.origin.x, y: spectrumArea.origin.y, 
                                   width: spectrumArea.width, height: spectrumArea.height)
        let skinPoint = NSPoint(x: point.x, y: skinY)
        if spectrumRect.contains(skinPoint) {
            if event.clickCount == 2 {
                // Double-click: cancel pending single-click and cycle vis mode
                visClickTimer?.invalidate()
                visClickTimer = nil
                cycleMainVisMode()
            } else if event.clickCount == 1 {
                // Single-click: delay to check if double-click follows
                visClickTimer?.invalidate()
                visClickTimer = Timer.scheduledTimer(withTimeInterval: NSEvent.doubleClickInterval, repeats: false) { [weak self] _ in
                    self?.visClickTimer = nil
                    WindowManager.shared.toggleSpectrum()
                }
            }
            return
        }
        
        // Check for double-click actions
        if event.clickCount == 2 {
            // Double-click on title bar to toggle shade mode
            if isShadeMode || regionManager.shouldToggleShade(at: point, windowType: .main, windowSize: hitTestSize) {
                toggleShadeMode()
                return
            }
        }
        
        if isShadeMode {
            // Shade mode mouse handling
            handleShadeMouseDown(at: point, event: event)
            return
        }
        
        // Hit test for actions
        if let action = regionManager.hitTest(point: point, in: .main, windowSize: hitTestSize) {
            handleMouseDown(action: action, at: point)
            return
        }
        
        // No action hit - start window drag
        // Only allow undocking if dragging from title bar area (top 14 pixels in skin coords)
        // skinY already calculated above for spectrum check
        let isTitleBarArea = skinY < 14  // Title bar is 14px tall
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
        if let window = window {
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: isTitleBarArea)
        }
    }
    
    /// Handle mouse down in shade mode
    private func handleShadeMouseDown(at point: NSPoint, event: NSEvent) {
        // Point is already in original coordinates, convert to skin Y-axis (top-down)
        let originalHeight = SkinElements.MainShade.windowSize.height
        let skinPoint = NSPoint(x: point.x, y: originalHeight - point.y)
        
        // Check window control buttons - close first for priority (enlarged hit areas)
        let closeRect = SkinElements.TitleBar.ShadeHitPositions.closeButton
        let unshadeRect = SkinElements.TitleBar.ShadeHitPositions.unshadeButton
        let minimizeRect = SkinElements.TitleBar.ShadeHitPositions.minimizeButton
        
        if closeRect.contains(skinPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        if unshadeRect.contains(skinPoint) {
            pressedButton = .unshade
            needsDisplay = true
            return
        }
        
        if minimizeRect.contains(skinPoint) {
            pressedButton = .minimize
            needsDisplay = true
            return
        }
        
        // No button hit - start window drag (shade mode is all title bar, so can undock)
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
        if let window = window {
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
        }
    }
    
    private func handleMouseDown(action: PlayerAction, at point: NSPoint) {
        switch action {
        // Button presses - track pressed state
        case .previous:
            pressedButton = .previous
        case .play:
            pressedButton = .play
        case .pause:
            pressedButton = .pause
        case .stop:
            pressedButton = .stop
        case .next:
            pressedButton = .next
        case .eject:
            pressedButton = .eject
        case .close:
            pressedButton = .close
        case .minimize:
            pressedButton = .minimize
        case .shade:
            pressedButton = .shade
        case .shuffle:
            pressedButton = .shuffle
        case .repeat:
            pressedButton = .repeatTrack
        case .toggleEQ:
            pressedButton = .eqToggle
        case .togglePlaylist:
            pressedButton = .playlistToggle
            
        case .openPlexBrowser:
            pressedButton = .logo
            
        case .openMainMenu:
            pressedButton = .menu
            
        // Note: cycleMainVisMode is handled via single-click in mouseDown()
            
        // Slider interactions
        case .seekPosition(let value):
            draggingSlider = .position
            dragPositionValue = value
            
        case .setVolume(let value):
            draggingSlider = .volume
            WindowManager.shared.audioEngine.volume = Float(value)
            
        case .setBalance(let value):
            draggingSlider = .balance
            WindowManager.shared.audioEngine.balance = Float(value)
            
        default:
            break
        }
        
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = convertToOriginalCoordinates(viewPoint)
        
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
            return
        }
        
        // Handle slider dragging
        if let slider = draggingSlider {
            // Convert point to skin coordinates
            let originalHeight = Skin.baseMainSize.height
            let skinPoint = NSPoint(x: point.x, y: originalHeight - point.y)
            
            switch slider {
            case .position:
                // Calculate absolute position on the track
                let rect = SkinElements.PositionBar.Positions.track
                let newValue = min(1.0, max(0.0, (skinPoint.x - rect.minX) / rect.width))
                dragPositionValue = newValue
            case .volume:
                let rect = SkinElements.Volume.Positions.slider
                let newValue = min(1.0, max(0.0, (skinPoint.x - rect.minX) / rect.width))
                WindowManager.shared.audioEngine.volume = Float(newValue)
            case .balance:
                let rect = SkinElements.Balance.Positions.slider
                let normalized = min(1.0, max(0.0, (skinPoint.x - rect.minX) / rect.width))
                let newValue = (normalized * 2.0) - 1.0  // Convert to -1...1
                WindowManager.shared.audioEngine.balance = Float(newValue)
            default:
                break
            }
            
            // Force immediate redraw during drag (needsDisplay doesn't work reliably during drag)
            display()
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = convertToOriginalCoordinates(viewPoint)
        
        // End window dragging
        if isDraggingWindow {
            isDraggingWindow = false
            if let window = window {
                WindowManager.shared.windowDidFinishDragging(window)
            }
        }
        
        if let slider = draggingSlider {
            // Complete slider interaction
            if slider == .position, let finalValue = dragPositionValue {
                let isVideoActive = WindowManager.shared.isVideoActivePlayback
                
                if isVideoActive {
                    // Video seeking
                    let videoDuration = WindowManager.shared.videoDuration
                    guard videoDuration > 0 else {
                        dragPositionValue = nil
                        draggingSlider = nil
                        needsDisplay = true
                        return
                    }
                    
                    let seekTime = videoDuration * Double(finalValue)
                    WindowManager.shared.seekVideo(to: seekTime)
                    
                    // Update display immediately
                    currentTime = seekTime
                    duration = videoDuration
                    lastSeekTime = Date()
                } else {
                    // Audio seeking - get duration directly from audio engine (more reliable than cached value)
                    let audioDuration = WindowManager.shared.audioEngine.duration
                    guard audioDuration > 0 else {
                        dragPositionValue = nil
                        draggingSlider = nil
                        needsDisplay = true
                        return
                    }
                    
                    // Seek to the final position
                    let seekTime = audioDuration * Double(finalValue)
                    WindowManager.shared.audioEngine.seek(to: seekTime)
                    
                    // Update currentTime immediately to prevent visual snap-back
                    currentTime = seekTime
                    duration = audioDuration
                    lastSeekTime = Date()
                }
                
                // Clear drag position
                dragPositionValue = nil
            }
            draggingSlider = nil
            needsDisplay = true
            return
        }
        
        // Check if mouse is still over the pressed button
        if let pressed = pressedButton {
            if isShadeMode {
                // Shade mode button release handling
                let originalHeight = SkinElements.MainShade.windowSize.height
                let skinPoint = NSPoint(x: point.x, y: originalHeight - point.y)
                var shouldPerform = false
                
                switch pressed {
                case .close:
                    shouldPerform = SkinElements.TitleBar.ShadeHitPositions.closeButton.contains(skinPoint)
                case .minimize:
                    shouldPerform = SkinElements.TitleBar.ShadeHitPositions.minimizeButton.contains(skinPoint)
                case .unshade:
                    shouldPerform = SkinElements.TitleBar.ShadeHitPositions.unshadeButton.contains(skinPoint)
                default:
                    break
                }
                
                if shouldPerform {
                    performAction(for: pressed)
                }
            } else {
                // Normal mode button release handling
                let action = regionManager.hitTest(point: point, in: .main, windowSize: originalWindowSize)
                
                // If released on the same button, perform the action
                if actionMatchesButton(action, pressed) {
                    performAction(for: pressed)
                }
            }
            
            pressedButton = nil
            needsDisplay = true
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }
    
    override func mouseEntered(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let cursor = regionManager.cursor(for: point, in: .main, windowSize: bounds.size)
        cursor.set()
    }
    
    // MARK: - Context Menu
    
    override func menu(for event: NSEvent) -> NSMenu? {
        return ContextMenuBuilder.buildMenu()
    }
    
    
    // MARK: - Action Handling
    
    private func actionMatchesButton(_ action: PlayerAction?, _ button: ButtonType) -> Bool {
        guard let action = action else { return false }
        
        switch (action, button) {
        case (.previous, .previous),
             (.play, .play),
             (.pause, .pause),
             (.stop, .stop),
             (.next, .next),
             (.eject, .eject),
             (.close, .close),
             (.minimize, .minimize),
             (.shade, .shade),
             (.shuffle, .shuffle),
             (.repeat, .repeatTrack),
             (.toggleEQ, .eqToggle),
             (.togglePlaylist, .playlistToggle),
             (.openPlexBrowser, .logo),
             (.openMainMenu, .menu):
            return true
        default:
            return false
        }
    }
    
    private func performAction(for button: ButtonType) {
        let engine = WindowManager.shared.audioEngine
        let isVideoActive = WindowManager.shared.isVideoActivePlayback
        
        switch button {
        case .previous:
            if isVideoActive {
                WindowManager.shared.skipVideoBackward(10)
            } else {
                engine.previous()
            }
        case .play:
            if isVideoActive {
                WindowManager.shared.toggleVideoPlayPause()
            } else {
                engine.play()
            }
        case .pause:
            NSLog("MainWindowView: Pause button pressed (isVideoActive=%d, isCastingLocalFile=%d)", isVideoActive ? 1 : 0, isCastingLocalFile ? 1 : 0)
            if isVideoActive {
                WindowManager.shared.toggleVideoPlayPause()
            } else {
                engine.pause()
            }
        case .stop:
            if isVideoActive {
                WindowManager.shared.stopVideo()
            } else {
                engine.stop()
            }
        case .next:
            if isVideoActive {
                WindowManager.shared.skipVideoForward(10)
            } else {
                engine.next()
            }
        case .eject:
            openFile()
        case .shuffle:
            engine.shuffleEnabled.toggle()
        case .repeatTrack:
            engine.repeatEnabled.toggle()
        case .eqToggle:
            WindowManager.shared.toggleEqualizer()
        case .playlistToggle:
            WindowManager.shared.togglePlaylist()
        case .close:
            NSApplication.shared.terminate(nil)
        case .minimize:
            window?.miniaturize(nil)
        case .shade, .unshade:
            toggleShadeMode()
        case .logo:
            WindowManager.shared.togglePlexBrowser()
        case .menu:
            WindowManager.shared.toggleProjectM()
        default:
            break
        }
        
        needsDisplay = true
    }
    
    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff]
        
        if panel.runModal() == .OK {
            WindowManager.shared.audioEngine.loadFiles(panel.urls)
        }
    }
    
    private func toggleShadeMode() {
        isShadeMode.toggle()
        controller?.setShadeMode(isShadeMode)
    }
    
    /// Set shade mode externally (e.g., from controller)
    func setShadeMode(_ enabled: Bool) {
        isShadeMode = enabled
        updateMarqueeLayerFrame()  // Hide/show layer based on mode
        updateMetalOverlayVisibility()  // Hide/show Metal overlay based on mode
        if enabled {
            marqueeOffset = 0  // Reset shade mode marquee
            startMarquee()     // Start timer for shade mode
        }
        needsDisplay = true
    }
    
    // MARK: - Keyboard Events
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        let engine = WindowManager.shared.audioEngine
        let isVideoActive = WindowManager.shared.isVideoActivePlayback
        
        switch event.keyCode {
        case 49: // Space - Play/Pause
            if isVideoActive {
                WindowManager.shared.toggleVideoPlayPause()
            } else if engine.state == .playing {
                engine.pause()
            } else {
                engine.play()
            }
        case 7: // X - Play
            if isVideoActive {
                WindowManager.shared.toggleVideoPlayPause()
            } else {
                engine.play()
            }
        case 9: // V - Stop
            if isVideoActive {
                WindowManager.shared.stopVideo()
            } else {
                engine.stop()
            }
        case 8: // C - Pause
            if isVideoActive {
                WindowManager.shared.toggleVideoPlayPause()
            } else {
                engine.pause()
            }
        case 6: // Z - Previous / Skip back
            if isVideoActive {
                WindowManager.shared.skipVideoBackward(10)
            } else {
                engine.previous()
            }
        case 11: // B - Next / Skip forward
            if isVideoActive {
                WindowManager.shared.skipVideoForward(10)
            } else {
                engine.next()
            }
        case 123: // Left Arrow - Seek back 5s
            if isVideoActive {
                WindowManager.shared.skipVideoBackward(5)
            } else {
                let newTime = max(0, currentTime - 5)
                engine.seek(to: newTime)
            }
        case 124: // Right Arrow - Seek forward 5s
            if isVideoActive {
                WindowManager.shared.skipVideoForward(5)
            } else {
                let newTime = min(duration, currentTime + 5)
                engine.seek(to: newTime)
            }
        case 126: // Up Arrow - Volume up
            engine.volume = min(1.0, engine.volume + 0.05)
        case 125: // Down Arrow - Volume down
            engine.volume = max(0.0, engine.volume - 0.05)
        default:
            super.keyDown(with: event)
        }
        
        needsDisplay = true
    }
    
    // MARK: - Drag and Drop
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        
        let audioExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "alac"]
        var mediaURLs: [URL] = []
        
        for url in items {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // Scan folder recursively for audio files
                    if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
                        while let fileURL = enumerator.nextObject() as? URL {
                            if audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                                mediaURLs.append(fileURL)
                            }
                        }
                    }
                } else {
                    // Add individual audio file
                    if audioExtensions.contains(url.pathExtension.lowercased()) {
                        mediaURLs.append(url)
                    }
                }
            }
        }
        
        // Sort files alphabetically
        mediaURLs.sort { $0.lastPathComponent < $1.lastPathComponent }
        
        if !mediaURLs.isEmpty {
            let audioEngine = WindowManager.shared.audioEngine
            let firstNewIndex = audioEngine.playlist.count  // Index where first new track will be
            audioEngine.appendFiles(mediaURLs)  // Append without replacing playlist
            audioEngine.playTrack(at: firstNewIndex)  // Start playing first dropped file
            return true
        }
        return false
    }
}
