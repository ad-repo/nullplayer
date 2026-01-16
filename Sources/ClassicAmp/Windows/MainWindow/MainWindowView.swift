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
    
    /// Marquee scroll offset
    private var marqueeOffset: CGFloat = 0
    
    /// Marquee timer
    private var marqueeTimer: Timer?
    
    /// Mouse tracking area
    private var trackingArea: NSTrackingArea?
    
    /// Button being pressed
    private var pressedButton: ButtonType?
    
    /// Dragging state
    private var isDragging = false
    private var dragStartPoint: NSPoint = .zero
    
    /// Slider drag tracker
    private let sliderTracker = SliderDragTracker()
    
    /// Region manager for hit testing
    private let regionManager = RegionManager.shared
    
    /// Skin renderer
    private var renderer: SkinRenderer {
        return SkinRenderer.current
    }
    
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
    }
    
    deinit {
        marqueeTimer?.invalidate()
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
        
        // Determine if window is active
        let isActive = window?.isKeyWindow ?? true
        
        // Draw main window background
        renderer.drawMainWindowBackground(in: context, bounds: bounds, isActive: isActive)
        
        // Draw time display
        let minutes = Int(currentTime) / 60
        let seconds = Int(currentTime) % 60
        renderer.drawTimeDisplay(minutes: minutes, seconds: seconds, in: context)
        
        // Draw song title marquee
        let marqueeText = currentTrack?.displayTitle ?? "ClassicAmp"
        renderer.drawMarquee(text: marqueeText, offset: marqueeOffset, in: context)
        
        // Draw playback status indicator
        let playbackState = WindowManager.shared.audioEngine.state
        renderer.drawPlaybackStatus(playbackState, in: context)
        
        // Draw mono/stereo indicator
        let isStereo = (currentTrack?.channels ?? 2) >= 2
        renderer.drawMonoStereo(isStereo: isStereo, in: context)
        
        // Draw position slider (seek bar)
        let positionValue = duration > 0 ? CGFloat(currentTime / duration) : 0
        let positionPressed = sliderTracker.isDragging && sliderTracker.sliderType == .position
        renderer.drawPositionSlider(value: positionValue, isPressed: positionPressed, in: context)
        
        // Draw volume slider
        let volumeValue = CGFloat(WindowManager.shared.audioEngine.volume)
        let volumePressed = sliderTracker.isDragging && sliderTracker.sliderType == .volume
        renderer.drawVolumeSlider(value: volumeValue, isPressed: volumePressed, in: context)
        
        // Draw balance slider
        let balanceValue = CGFloat(WindowManager.shared.audioEngine.balance)
        let balancePressed = sliderTracker.isDragging && sliderTracker.sliderType == .balance
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
        renderer.drawWindowControls(in: context, bounds: bounds, pressedButton: pressedButton)
        
        context.restoreGState()
    }
    
    // MARK: - Public Methods
    
    func updateTime(current: TimeInterval, duration: TimeInterval) {
        self.currentTime = current
        self.duration = duration
        needsDisplay = true
    }
    
    func updateTrackInfo(_ track: Track?) {
        self.currentTrack = track
        marqueeOffset = 0  // Reset scroll position
        needsDisplay = true
    }
    
    // MARK: - Marquee Animation
    
    private func startMarquee() {
        marqueeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let title = self.currentTrack?.displayTitle ?? "ClassicAmp"
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
        let point = convert(event.locationInWindow, from: nil)
        let cursor = regionManager.cursor(for: point, in: .main, windowSize: bounds.size)
        cursor.set()
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // Check for double-click on title bar to toggle shade mode
        if event.clickCount == 2 {
            if regionManager.shouldToggleShade(at: point, windowType: .main, windowSize: bounds.size) {
                toggleShadeMode()
                return
            }
        }
        
        // Check if in title bar for dragging
        if regionManager.isInTitleBar(point, windowType: .main, windowSize: bounds.size) {
            isDragging = true
            dragStartPoint = event.locationInWindow
            return
        }
        
        // Hit test for actions
        if let action = regionManager.hitTest(point: point, in: .main, windowSize: bounds.size) {
            handleMouseDown(action: action, at: point)
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
            
        // Slider interactions
        case .seekPosition(let value):
            sliderTracker.beginDrag(slider: .position, at: point, currentValue: value)
            
        case .setVolume(let value):
            sliderTracker.beginDrag(slider: .volume, at: point, currentValue: value)
            WindowManager.shared.audioEngine.volume = Float(value)
            
        case .setBalance(let value):
            sliderTracker.beginDrag(slider: .balance, at: point, currentValue: value)
            WindowManager.shared.audioEngine.balance = Float(value)
            
        default:
            break
        }
        
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        if isDragging {
            // Window dragging
            guard let window = window else { return }
            let currentPoint = event.locationInWindow
            let delta = NSPoint(
                x: currentPoint.x - dragStartPoint.x,
                y: currentPoint.y - dragStartPoint.y
            )
            
            var newOrigin = window.frame.origin
            newOrigin.x += delta.x
            newOrigin.y += delta.y
            
            // Apply snapping
            newOrigin = WindowManager.shared.windowWillMove(window, to: newOrigin)
            window.setFrameOrigin(newOrigin)
        } else if sliderTracker.isDragging {
            // Slider dragging
            let rect: NSRect
            switch sliderTracker.sliderType {
            case .position:
                rect = SkinElements.PositionBar.Positions.track
            case .volume:
                rect = SkinElements.Volume.Positions.slider
            case .balance:
                rect = SkinElements.Balance.Positions.slider
            default:
                return
            }
            
            // Convert point to Winamp coordinates for calculation
            let winampPoint = NSPoint(x: point.x, y: bounds.height - point.y)
            let newValue = sliderTracker.updateDrag(to: winampPoint, in: rect)
            
            switch sliderTracker.sliderType {
            case .position:
                // Don't seek during drag, just update display
                break
            case .volume:
                WindowManager.shared.audioEngine.volume = Float(newValue)
            case .balance:
                WindowManager.shared.audioEngine.balance = Float(newValue)
            default:
                break
            }
            
            needsDisplay = true
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        if isDragging {
            isDragging = false
            return
        }
        
        if sliderTracker.isDragging {
            // Complete slider interaction
            if sliderTracker.sliderType == .position {
                let rect = SkinElements.PositionBar.Positions.track
                let winampPoint = NSPoint(x: point.x, y: bounds.height - point.y)
                let finalValue = sliderTracker.updateDrag(to: winampPoint, in: rect)
                
                // Seek to the final position
                let seekTime = duration * Double(finalValue)
                WindowManager.shared.audioEngine.seek(to: seekTime)
            }
            sliderTracker.endDrag()
            needsDisplay = true
            return
        }
        
        // Check if mouse is still over the pressed button
        if let pressed = pressedButton {
            let action = regionManager.hitTest(point: point, in: .main, windowSize: bounds.size)
            
            // If released on the same button, perform the action
            if actionMatchesButton(action, pressed) {
                performAction(for: pressed)
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
        case .shade:
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
        // TODO: Implement shade mode toggle
        // This will resize the window to shade height and show compact view
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
