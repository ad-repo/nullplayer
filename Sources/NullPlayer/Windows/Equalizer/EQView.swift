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
    
    /// Calculate scale factor based on current bounds vs original size
    private var scaleFactor: CGFloat {
        let originalSize = Skin.baseEQSize
        let scaleX = bounds.width / originalSize.width
        let scaleY = bounds.height / originalSize.height
        return min(scaleX, scaleY)
    }
    
    /// Convert a point from view coordinates to original (unscaled) coordinates
    private func convertToOriginalCoordinates(_ point: NSPoint) -> NSPoint {
        let originalSize = Skin.baseEQSize
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

        // Draw normal mode
        drawNormalMode(renderer: renderer, context: context, isActive: isActive, drawBounds: drawBounds)

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
    
    // MARK: - Public Methods
    
    func skinDidChange() {
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
        
        // Close button (checked first for priority, enlarged hit area) - skip when title bars hidden
        if !WindowManager.shared.hideTitleBars && Layout.closeHitRect.contains(skinPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        
        // Toggle buttons
        if Layout.onOffRect.contains(skinPoint) {
            isEnabled.toggle()
            WindowManager.shared.audioEngine.setEQEnabled(isEnabled)
            needsDisplay = true
            return
        }
        
        if Layout.autoRect.contains(skinPoint) {
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
        
        if Layout.presetsRect.contains(skinPoint) {
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
        
        // Not on any control - start window drag
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
        let skinPoint = NSPoint(x: point.x, y: originalWindowSize.height - point.y)

        // Handle button releases
        if let pressed = pressedButton {
            switch pressed {
            case .close:
                if Layout.closeHitRect.contains(skinPoint) {
                    window?.close()
                }
            case .eqPresets:
                if Layout.presetsRect.contains(skinPoint) {
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
        // Check preamp (skin coordinates - y increases downward)
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
