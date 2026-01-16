import AppKit

/// Main window view - renders the Winamp main player interface
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
    private var pressedButton: PlayerAction?
    
    /// Dragging state
    private var isDragging = false
    private var dragStartPoint: NSPoint = .zero
    
    // MARK: - Sprite Positions (Classic Winamp 275x116)
    
    private struct Layout {
        // Title bar
        static let titleBarHeight: CGFloat = 14
        
        // Clutterbar (left side menu buttons)
        static let clutterbarRect = NSRect(x: 0, y: 72, width: 8, height: 43)
        
        // Time display (LED digits)
        static let timeRect = NSRect(x: 48, y: 26, width: 63, height: 13)
        
        // Song title marquee
        static let marqueeRect = NSRect(x: 111, y: 24, width: 154, height: 13)
        
        // Bitrate display
        static let bitrateRect = NSRect(x: 111, y: 43, width: 15, height: 9)
        
        // Sample rate display
        static let sampleRateRect = NSRect(x: 156, y: 43, width: 10, height: 9)
        
        // Mono/Stereo indicator
        static let monoStereoRect = NSRect(x: 212, y: 41, width: 56, height: 12)
        
        // Position slider (seek bar)
        static let positionRect = NSRect(x: 16, y: 72, width: 248, height: 10)
        
        // Volume slider
        static let volumeRect = NSRect(x: 107, y: 57, width: 68, height: 13)
        
        // Balance slider
        static let balanceRect = NSRect(x: 177, y: 57, width: 38, height: 13)
        
        // Transport buttons (from left to right)
        static let transportY: CGFloat = 88
        static let transportHeight: CGFloat = 18
        
        static let previousRect = NSRect(x: 16, y: 88, width: 23, height: 18)
        static let playRect = NSRect(x: 39, y: 88, width: 23, height: 18)
        static let pauseRect = NSRect(x: 62, y: 88, width: 23, height: 18)
        static let stopRect = NSRect(x: 85, y: 88, width: 23, height: 18)
        static let nextRect = NSRect(x: 108, y: 88, width: 22, height: 18)
        static let ejectRect = NSRect(x: 136, y: 89, width: 22, height: 16)
        
        // Shuffle/Repeat buttons
        static let shuffleRect = NSRect(x: 164, y: 89, width: 46, height: 15)
        static let repeatRect = NSRect(x: 210, y: 89, width: 28, height: 15)
        
        // Window control buttons (top right)
        static let minimizeRect = NSRect(x: 244, y: 3, width: 9, height: 9)
        static let shadeRect = NSRect(x: 254, y: 3, width: 9, height: 9)
        static let closeRect = NSRect(x: 264, y: 3, width: 9, height: 9)
        
        // EQ/Playlist toggle buttons
        static let eqToggleRect = NSRect(x: 219, y: 58, width: 23, height: 12)
        static let plToggleRect = NSRect(x: 242, y: 58, width: 23, height: 12)
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
        
        let skin = WindowManager.shared.currentSkin
        
        // Draw main background
        if let mainImage = skin?.main {
            drawImage(mainImage, in: bounds, context: context)
        } else {
            // Fallback: draw default dark background
            drawDefaultBackground(context: context)
        }
        
        // Draw time display
        drawTimeDisplay(context: context)
        
        // Draw song title marquee
        drawMarquee(context: context)
        
        // Draw position slider
        drawPositionSlider(context: context)
        
        // Draw volume slider
        drawVolumeSlider(context: context)
        
        // Draw transport buttons (with pressed state)
        drawTransportButtons(context: context)
        
        // Draw status indicators
        drawStatusIndicators(context: context)
    }
    
    private func drawDefaultBackground(context: CGContext) {
        // Classic Winamp dark gray background
        NSColor(calibratedWhite: 0.2, alpha: 1.0).setFill()
        context.fill(bounds)
        
        // Title bar gradient
        let titleRect = NSRect(x: 0, y: bounds.height - Layout.titleBarHeight,
                               width: bounds.width, height: Layout.titleBarHeight)
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.4, alpha: 1.0),
            NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.2, alpha: 1.0)
        ])
        gradient?.draw(in: titleRect, angle: 90)
        
        // Title text
        let title = currentTrack?.displayTitle ?? "ClassicAmp"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.boldSystemFont(ofSize: 9)
        ]
        let titleSize = title.size(withAttributes: attrs)
        let titlePoint = NSPoint(x: 6, y: bounds.height - Layout.titleBarHeight + 2)
        title.draw(at: titlePoint, withAttributes: attrs)
        
        // Draw button outlines
        drawDefaultButtons(context: context)
    }
    
    private func drawDefaultButtons(context: CGContext) {
        NSColor.darkGray.setStroke()
        
        // Transport buttons area
        let transportRects = [
            Layout.previousRect, Layout.playRect, Layout.pauseRect,
            Layout.stopRect, Layout.nextRect, Layout.ejectRect
        ]
        
        for rect in transportRects {
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            
            // Highlight if pressed
            if let pressed = pressedButton, hitTest(for: pressed) == rect {
                NSColor(calibratedWhite: 0.3, alpha: 1.0).setFill()
            } else {
                NSColor(calibratedWhite: 0.15, alpha: 1.0).setFill()
            }
            path.fill()
            path.stroke()
        }
        
        // Draw button symbols
        drawTransportSymbols(context: context)
    }
    
    private func drawTransportSymbols(context: CGContext) {
        NSColor.lightGray.setFill()
        
        // Previous: |<<
        drawPreviousSymbol(in: Layout.previousRect)
        
        // Play: >
        drawPlaySymbol(in: Layout.playRect)
        
        // Pause: ||
        drawPauseSymbol(in: Layout.pauseRect)
        
        // Stop: square
        drawStopSymbol(in: Layout.stopRect)
        
        // Next: >>|
        drawNextSymbol(in: Layout.nextRect)
        
        // Eject: triangle + line
        drawEjectSymbol(in: Layout.ejectRect)
    }
    
    private func drawPreviousSymbol(in rect: NSRect) {
        let path = NSBezierPath()
        let cx = rect.midX
        let cy = rect.midY
        
        // Bar
        path.move(to: NSPoint(x: cx - 6, y: cy - 5))
        path.line(to: NSPoint(x: cx - 6, y: cy + 5))
        path.line(to: NSPoint(x: cx - 4, y: cy + 5))
        path.line(to: NSPoint(x: cx - 4, y: cy - 5))
        path.close()
        
        // Triangles
        path.move(to: NSPoint(x: cx - 2, y: cy))
        path.line(to: NSPoint(x: cx + 3, y: cy - 5))
        path.line(to: NSPoint(x: cx + 3, y: cy + 5))
        path.close()
        
        path.move(to: NSPoint(x: cx + 3, y: cy))
        path.line(to: NSPoint(x: cx + 8, y: cy - 5))
        path.line(to: NSPoint(x: cx + 8, y: cy + 5))
        path.close()
        
        path.fill()
    }
    
    private func drawPlaySymbol(in rect: NSRect) {
        let path = NSBezierPath()
        let cx = rect.midX
        let cy = rect.midY
        
        path.move(to: NSPoint(x: cx - 4, y: cy - 5))
        path.line(to: NSPoint(x: cx - 4, y: cy + 5))
        path.line(to: NSPoint(x: cx + 5, y: cy))
        path.close()
        path.fill()
    }
    
    private func drawPauseSymbol(in rect: NSRect) {
        let path = NSBezierPath()
        let cx = rect.midX
        let cy = rect.midY
        
        // Left bar
        path.appendRect(NSRect(x: cx - 5, y: cy - 5, width: 3, height: 10))
        // Right bar
        path.appendRect(NSRect(x: cx + 2, y: cy - 5, width: 3, height: 10))
        path.fill()
    }
    
    private func drawStopSymbol(in rect: NSRect) {
        let path = NSBezierPath()
        let cx = rect.midX
        let cy = rect.midY
        
        path.appendRect(NSRect(x: cx - 4, y: cy - 4, width: 8, height: 8))
        path.fill()
    }
    
    private func drawNextSymbol(in rect: NSRect) {
        let path = NSBezierPath()
        let cx = rect.midX
        let cy = rect.midY
        
        // Triangles
        path.move(to: NSPoint(x: cx - 7, y: cy - 5))
        path.line(to: NSPoint(x: cx - 7, y: cy + 5))
        path.line(to: NSPoint(x: cx - 2, y: cy))
        path.close()
        
        path.move(to: NSPoint(x: cx - 2, y: cy - 5))
        path.line(to: NSPoint(x: cx - 2, y: cy + 5))
        path.line(to: NSPoint(x: cx + 3, y: cy))
        path.close()
        
        // Bar
        path.appendRect(NSRect(x: cx + 4, y: cy - 5, width: 2, height: 10))
        
        path.fill()
    }
    
    private func drawEjectSymbol(in rect: NSRect) {
        let path = NSBezierPath()
        let cx = rect.midX
        let cy = rect.midY
        
        // Triangle
        path.move(to: NSPoint(x: cx - 5, y: cy - 2))
        path.line(to: NSPoint(x: cx + 5, y: cy - 2))
        path.line(to: NSPoint(x: cx, y: cy + 4))
        path.close()
        
        // Line
        path.appendRect(NSRect(x: cx - 5, y: cy - 5, width: 10, height: 2))
        
        path.fill()
    }
    
    private func drawTimeDisplay(context: CGContext) {
        // Convert time to MM:SS format
        let minutes = Int(currentTime) / 60
        let seconds = Int(currentTime) % 60
        let timeString = String(format: "%02d:%02d", minutes, seconds)
        
        // Draw with LED-style font or fallback
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.green,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        ]
        
        timeString.draw(in: Layout.timeRect, withAttributes: attrs)
    }
    
    private func drawMarquee(context: CGContext) {
        guard let title = currentTrack?.displayTitle else {
            "ClassicAmp".draw(in: Layout.marqueeRect, withAttributes: [
                .foregroundColor: NSColor.green,
                .font: NSFont.systemFont(ofSize: 8)
            ])
            return
        }
        
        // Clip to marquee area
        context.saveGState()
        context.clip(to: Layout.marqueeRect)
        
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.green,
            .font: NSFont.systemFont(ofSize: 8)
        ]
        
        let textSize = title.size(withAttributes: attrs)
        let drawPoint = NSPoint(
            x: Layout.marqueeRect.minX - marqueeOffset,
            y: Layout.marqueeRect.minY + 2
        )
        
        title.draw(at: drawPoint, withAttributes: attrs)
        
        // Draw again for seamless scrolling if needed
        if marqueeOffset > 0 && textSize.width > Layout.marqueeRect.width {
            let secondPoint = NSPoint(
                x: drawPoint.x + textSize.width + 50,
                y: drawPoint.y
            )
            title.draw(at: secondPoint, withAttributes: attrs)
        }
        
        context.restoreGState()
    }
    
    private func drawPositionSlider(context: CGContext) {
        let rect = Layout.positionRect
        
        // Background track
        NSColor.darkGray.setFill()
        context.fill(rect)
        
        // Progress
        if duration > 0 {
            let progress = CGFloat(currentTime / duration)
            let progressRect = NSRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width * progress,
                height: rect.height
            )
            NSColor.green.setFill()
            context.fill(progressRect)
        }
        
        // Border
        NSColor.gray.setStroke()
        context.stroke(rect)
    }
    
    private func drawVolumeSlider(context: CGContext) {
        let rect = Layout.volumeRect
        let volume = WindowManager.shared.audioEngine.volume
        
        // Background
        NSColor.darkGray.setFill()
        context.fill(rect)
        
        // Level
        let levelRect = NSRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width * CGFloat(volume),
            height: rect.height
        )
        NSColor.green.setFill()
        context.fill(levelRect)
        
        // Border
        NSColor.gray.setStroke()
        context.stroke(rect)
    }
    
    private func drawTransportButtons(context: CGContext) {
        // Already handled in drawDefaultButtons for now
    }
    
    private func drawStatusIndicators(context: CGContext) {
        // Play/Pause/Stop status
        let state = WindowManager.shared.audioEngine.state
        let statusRect = NSRect(x: 26, y: 28, width: 9, height: 9)
        
        switch state {
        case .playing:
            NSColor.green.setFill()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: statusRect.minX, y: statusRect.minY))
            path.line(to: NSPoint(x: statusRect.minX, y: statusRect.maxY))
            path.line(to: NSPoint(x: statusRect.maxX, y: statusRect.midY))
            path.close()
            path.fill()
        case .paused:
            NSColor.yellow.setFill()
            context.fill(NSRect(x: statusRect.minX, y: statusRect.minY,
                               width: 3, height: statusRect.height))
            context.fill(NSRect(x: statusRect.minX + 5, y: statusRect.minY,
                               width: 3, height: statusRect.height))
        case .stopped:
            NSColor.gray.setFill()
            context.fill(statusRect.insetBy(dx: 1, dy: 1))
        }
    }
    
    private func drawImage(_ image: NSImage, in rect: NSRect, context: CGContext) {
        image.draw(in: rect,
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: 1.0)
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
            
            if let title = self.currentTrack?.displayTitle {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 8)
                ]
                let textWidth = title.size(withAttributes: attrs).width
                
                if textWidth > Layout.marqueeRect.width {
                    self.marqueeOffset += 1
                    if self.marqueeOffset > textWidth + 50 {
                        self.marqueeOffset = 0
                    }
                    self.setNeedsDisplay(Layout.marqueeRect)
                }
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
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // Check if in title bar for dragging
        let titleBarRect = NSRect(x: 0, y: bounds.height - Layout.titleBarHeight,
                                  width: bounds.width - 30, height: Layout.titleBarHeight)
        
        if titleBarRect.contains(point) {
            isDragging = true
            dragStartPoint = event.locationInWindow
            return
        }
        
        // Check button clicks
        if let action = hitTestAction(at: point) {
            pressedButton = action
            needsDisplay = true
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
            
            // Apply snapping
            newOrigin = WindowManager.shared.windowWillMove(window, to: newOrigin)
            window.setFrameOrigin(newOrigin)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            return
        }
        
        let point = convert(event.locationInWindow, from: nil)
        
        if let action = pressedButton, hitTestAction(at: point) == action {
            performAction(action)
        }
        
        pressedButton = nil
        needsDisplay = true
    }
    
    private func hitTestAction(at point: NSPoint) -> PlayerAction? {
        // Window controls
        if Layout.closeRect.contains(point) { return .close }
        if Layout.minimizeRect.contains(point) { return .minimize }
        if Layout.shadeRect.contains(point) { return .shade }
        
        // Transport controls
        if Layout.previousRect.contains(point) { return .previous }
        if Layout.playRect.contains(point) { return .play }
        if Layout.pauseRect.contains(point) { return .pause }
        if Layout.stopRect.contains(point) { return .stop }
        if Layout.nextRect.contains(point) { return .next }
        if Layout.ejectRect.contains(point) { return .eject }
        
        // Toggle buttons
        if Layout.shuffleRect.contains(point) { return .shuffle }
        if Layout.repeatRect.contains(point) { return .repeat }
        if Layout.eqToggleRect.contains(point) { return .toggleEQ }
        if Layout.plToggleRect.contains(point) { return .togglePlaylist }
        
        return nil
    }
    
    private func hitTest(for action: PlayerAction) -> NSRect? {
        switch action {
        case .previous: return Layout.previousRect
        case .play: return Layout.playRect
        case .pause: return Layout.pauseRect
        case .stop: return Layout.stopRect
        case .next: return Layout.nextRect
        case .eject: return Layout.ejectRect
        case .shuffle: return Layout.shuffleRect
        case .repeat: return Layout.repeatRect
        case .toggleEQ: return Layout.eqToggleRect
        case .togglePlaylist: return Layout.plToggleRect
        case .close: return Layout.closeRect
        case .minimize: return Layout.minimizeRect
        case .shade: return Layout.shadeRect
        default: return nil
        }
    }
    
    private func performAction(_ action: PlayerAction) {
        let engine = WindowManager.shared.audioEngine
        
        switch action {
        case .previous: engine.previous()
        case .play: engine.play()
        case .pause: engine.pause()
        case .stop: engine.stop()
        case .next: engine.next()
        case .eject: openFile()
        case .shuffle: engine.shuffleEnabled.toggle()
        case .repeat: engine.repeatEnabled.toggle()
        case .toggleEQ: WindowManager.shared.toggleEqualizer()
        case .togglePlaylist: WindowManager.shared.togglePlaylist()
        case .close: window?.close()
        case .minimize: window?.miniaturize(nil)
        case .shade: toggleShadeMode()
        default: break
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
    }
}

// MARK: - Player Actions

enum PlayerAction {
    case previous
    case play
    case pause
    case stop
    case next
    case eject
    case shuffle
    case `repeat`
    case toggleEQ
    case togglePlaylist
    case close
    case minimize
    case shade
    case seek
    case volume
    case balance
}
