import AppKit

/// Main window view - renders the Winamp main player interface using skin sprites
class MainWindowView: NSView {
    
    // MARK: - Properties
    
    weak var controller: MainWindowController?
    
    /// Current playback time
    private var currentTime: TimeInterval = 0
    
    /// Track duration
    private var duration: TimeInterval = 0
    
    /// Current track info
    private var currentTrack: Track?
    
    /// Spectrum analyzer levels
    private var spectrumLevels: [Float] = []
    
    /// Marquee scroll offset
    private var marqueeOffset: CGFloat = 0
    
    /// Marquee timer
    private var marqueeTimer: Timer?
    
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
        
        // Start marquee scrolling
        startMarquee()
        
        // Set up tracking area for mouse events
        updateTrackingAreas()
        
        // Observe time display mode changes
        NotificationCenter.default.addObserver(self, selector: #selector(timeDisplayModeDidChange),
                                               name: .timeDisplayModeDidChange, object: nil)
    }
    
    deinit {
        marqueeTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func timeDisplayModeDidChange() {
        needsDisplay = true
    }
    
    // MARK: - Drawing
    
    /// Calculate scale factor based on current bounds vs original size
    private var scaleFactor: CGFloat {
        let originalSize = isShadeMode ? SkinElements.MainShade.windowSize : Skin.mainWindowSize
        let scaleX = bounds.width / originalSize.width
        let scaleY = bounds.height / originalSize.height
        return min(scaleX, scaleY)
    }
    
    /// Convert a point from view coordinates to original (unscaled) coordinates
    private func convertToOriginalCoordinates(_ point: NSPoint) -> NSPoint {
        let originalSize = isShadeMode ? SkinElements.MainShade.windowSize : Skin.mainWindowSize
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
    
    /// Get the original window size for hit testing
    private var originalWindowSize: NSSize {
        return isShadeMode ? SkinElements.MainShade.windowSize : Skin.mainWindowSize
    }
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let originalSize = isShadeMode ? SkinElements.MainShade.windowSize : Skin.mainWindowSize
        let scale = scaleFactor
        
        // Flip coordinate system to match Winamp's top-down coordinates
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
            let marqueeText = currentTrack?.displayTitle ?? "AdAmp"
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
        
        // Draw song title marquee
        let marqueeText = currentTrack?.displayTitle ?? "AdAmp"
        renderer.drawMarquee(text: marqueeText, offset: marqueeOffset, in: context)
        
        // Draw playback status indicator
        let playbackState = WindowManager.shared.audioEngine.state
        renderer.drawPlaybackStatus(playbackState, in: context)
        
        // Draw mono/stereo indicator
        let isStereo = (currentTrack?.channels ?? 2) >= 2
        renderer.drawMonoStereo(isStereo: isStereo, in: context)
        
        // Draw spectrum analyzer
        renderer.drawSpectrumAnalyzer(levels: spectrumLevels, in: context)
        
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
        self.duration = duration
        // Don't update currentTime or redraw if user is dragging the position slider
        if draggingSlider == .position {
            return
        }
        // Ignore stale updates briefly after seeking to let audio engine catch up
        if let lastSeek = lastSeekTime, Date().timeIntervalSince(lastSeek) < 0.3 {
            return
        }
        self.currentTime = current
        needsDisplay = true
    }
    
    func updateTrackInfo(_ track: Track?) {
        self.currentTrack = track
        marqueeOffset = 0  // Reset scroll position
        needsDisplay = true
    }
    
    func updateSpectrum(_ levels: [Float]) {
        self.spectrumLevels = levels
        // Only redraw the visualization area for performance
        setNeedsDisplay(SkinElements.Visualization.displayArea)
    }
    
    // MARK: - Marquee Animation
    
    private func startMarquee() {
        marqueeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let title = self.currentTrack?.displayTitle ?? "AdAmp"
            let charWidth = SkinElements.TextFont.charWidth
            let textWidth = CGFloat(title.count) * charWidth
            let marqueeWidth = SkinElements.TextFont.Positions.marqueeArea.width
            
            if textWidth > marqueeWidth {
                self.marqueeOffset += 1
                if self.marqueeOffset > textWidth + 50 {
                    self.marqueeOffset = 0
                }
                self.setNeedsDisplay(SkinElements.TextFont.Positions.marqueeArea)
            }
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
        
        // Check for double-click on title bar to toggle shade mode
        if event.clickCount == 2 {
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
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
    }
    
    /// Handle mouse down in shade mode
    private func handleShadeMouseDown(at point: NSPoint, event: NSEvent) {
        // Point is already in original coordinates, convert to Winamp Y-axis (top-down)
        let originalHeight = SkinElements.MainShade.windowSize.height
        let winampPoint = NSPoint(x: point.x, y: originalHeight - point.y)
        
        // Check window control buttons
        let closeRect = SkinElements.TitleBar.ShadePositions.closeButton
        let minimizeRect = SkinElements.TitleBar.ShadePositions.minimizeButton
        let unshadeRect = SkinElements.TitleBar.ShadePositions.unshadeButton
        
        if closeRect.contains(winampPoint) {
            pressedButton = .close
            needsDisplay = true
            return
        }
        
        if minimizeRect.contains(winampPoint) {
            pressedButton = .minimize
            needsDisplay = true
            return
        }
        
        if unshadeRect.contains(winampPoint) {
            pressedButton = .unshade
            needsDisplay = true
            return
        }
        
        // No button hit - start window drag
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
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
            // Convert point to Winamp coordinates
            let originalHeight = Skin.mainWindowSize.height
            let winampPoint = NSPoint(x: point.x, y: originalHeight - point.y)
            
            switch slider {
            case .position:
                // Calculate absolute position on the track
                let rect = SkinElements.PositionBar.Positions.track
                let newValue = min(1.0, max(0.0, (winampPoint.x - rect.minX) / rect.width))
                dragPositionValue = newValue
            case .volume:
                let rect = SkinElements.Volume.Positions.slider
                let newValue = min(1.0, max(0.0, (winampPoint.x - rect.minX) / rect.width))
                WindowManager.shared.audioEngine.volume = Float(newValue)
            case .balance:
                let rect = SkinElements.Balance.Positions.slider
                let normalized = min(1.0, max(0.0, (winampPoint.x - rect.minX) / rect.width))
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
                // Get duration directly from audio engine (more reliable than cached value)
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
                let winampPoint = NSPoint(x: point.x, y: originalHeight - point.y)
                var shouldPerform = false
                
                switch pressed {
                case .close:
                    shouldPerform = SkinElements.TitleBar.ShadePositions.closeButton.contains(winampPoint)
                case .minimize:
                    shouldPerform = SkinElements.TitleBar.ShadePositions.minimizeButton.contains(winampPoint)
                case .unshade:
                    shouldPerform = SkinElements.TitleBar.ShadePositions.unshadeButton.contains(winampPoint)
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
             (.togglePlaylist, .playlistToggle):
            return true
        default:
            return false
        }
    }
    
    private func performAction(for button: ButtonType) {
        let engine = WindowManager.shared.audioEngine
        
        switch button {
        case .previous:
            engine.previous()
        case .play:
            engine.play()
        case .pause:
            engine.pause()
        case .stop:
            engine.stop()
        case .next:
            engine.next()
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
            window?.close()
        case .minimize:
            window?.miniaturize(nil)
        case .shade, .unshade:
            toggleShadeMode()
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
        needsDisplay = true
    }
    
    // MARK: - Keyboard Events
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        let engine = WindowManager.shared.audioEngine
        
        switch event.keyCode {
        case 49: // Space - Play/Pause
            if engine.state == .playing {
                engine.pause()
            } else {
                engine.play()
            }
        case 7: // X - Play
            engine.play()
        case 9: // V - Stop
            engine.stop()
        case 8: // C - Pause
            engine.pause()
        case 6: // Z - Previous
            engine.previous()
        case 11: // B - Next
            engine.next()
        case 123: // Left Arrow - Seek back 5s
            let newTime = max(0, currentTime - 5)
            engine.seek(to: newTime)
        case 124: // Right Arrow - Seek forward 5s
            let newTime = min(duration, currentTime + 5)
            engine.seek(to: newTime)
        case 126: // Up Arrow - Volume up
            engine.volume = min(1.0, engine.volume + 0.05)
        case 125: // Down Arrow - Volume down
            engine.volume = max(0.0, engine.volume - 0.05)
        default:
            super.keyDown(with: event)
        }
        
        needsDisplay = true
    }
}
