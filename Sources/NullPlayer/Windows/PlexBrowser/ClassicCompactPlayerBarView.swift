import AppKit

/// A stripped-down classic-skin player bar embedded at the top of the library browser in
/// Compact Mode (classic UI).
///
/// Renders transport controls, a position (seek) bar with elapsed/remaining time, a scrolling
/// track-title marquee, and a volume slider — all from authentic classic skin sprites
/// (CBUTTONS, posbar, volume) and the classic bitmap text font, via `SkinRenderer`.
/// Binds directly to `WindowManager.shared.audioEngine`.
///
/// This is the classic-UI analogue of `CompactPlayerBarView` (modern UI). It has ZERO
/// dependency on the modern skin system.
///
/// Coordinate note: like `MainWindowView`, the view lays everything out in classic *native*
/// pixel units (where transport buttons are 23×18, the text font 5×6, etc.) and applies a
/// single uniform scale transform so the bar fills its on-screen frame. Hit-testing converts
/// mouse points back into the same native unit space.
final class ClassicCompactPlayerBarView: NSView {

    // MARK: - Layout constants (classic native pixels)

    /// Design height in native units. Tall enough for transport buttons (18) plus a two-row
    /// title/seek middle column, with `topPad` of breathing room above so the controls don't
    /// sit jammed against the macOS menu bar.
    private let designHeight: CGFloat = 24
    /// Empty space (native units) reserved above the control row.
    private let topPad: CGFloat = 4
    /// Height of the interactive control row, below `topPad`.
    private var rowHeight: CGFloat { designHeight - topPad }
    private let pad: CGFloat = 5
    private let buttonHeight: CGFloat = 18
    /// Native widths of the CBUTTONS transport sprites: prev, play/pause, stop, next.
    private let buttonWidths: [CGFloat] = [23, 23, 23, 22]
    private let volumeSize = NSSize(width: 68, height: 13)
    private let seekHeight: CGFloat = 10
    private let posThumbSize = NSSize(width: 29, height: 10)
    private let volThumbSize = NSSize(width: 14, height: 11)

    /// Suggested on-screen bar height.
    static func preferredHeight() -> CGFloat { 33 }

    // MARK: - State

    private var currentTime: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var currentTrack: Track?

    private var isDraggingSeek = false
    private var isDraggingVolume = false
    private var seekDragPosition: CGFloat?
    private var pressedButton: ButtonType?

    private var marqueeOffset: CGFloat = 0
    private var marqueeTimer: Timer?

    // MARK: - Init

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
        startMarquee()
    }

    deinit {
        marqueeTimer?.invalidate()
    }

    // MARK: - Coordinate helpers

    /// Uniform scale from native units → view points.
    private var nativeScale: CGFloat {
        guard designHeight > 0 else { return 1 }
        return bounds.height / designHeight
    }

    /// Bar width in native units.
    private var designWidth: CGFloat {
        let s = nativeScale
        return s > 0 ? bounds.width / s : bounds.width
    }

    private func currentSkin() -> Skin {
        WindowManager.shared.currentSkin ?? SkinLoader.shared.loadDefault()
    }

    // MARK: - Element rects (native units, top-left origin, y grows downward)

    /// Transport button rects keyed prev/play/stop/next.
    private var transportRects: [NSRect] {
        let y = topPad + (rowHeight - buttonHeight) / 2
        var rects: [NSRect] = []
        var x = pad
        for w in buttonWidths {
            rects.append(NSRect(x: x, y: y, width: w, height: buttonHeight))
            x += w
        }
        return rects
    }

    private var transportEndX: CGFloat {
        (transportRects.last?.maxX ?? pad) + 4
    }

    private var volumeRect: NSRect {
        NSRect(x: designWidth - pad - volumeSize.width,
               y: topPad + (rowHeight - volumeSize.height) / 2,
               width: volumeSize.width, height: volumeSize.height)
    }

    private var timeRect: NSRect {
        // "00:00 / 00:00" = 13 chars × 5px native.
        let w = 13 * SkinElements.TextFont.charWidth
        return NSRect(x: volumeRect.minX - 6 - w,
                      y: topPad + (rowHeight - SkinElements.TextFont.charHeight) / 2,
                      width: w, height: SkinElements.TextFont.charHeight)
    }

    /// Flexible middle region between transport and the time readout.
    private var middleRect: NSRect {
        let left = transportEndX
        let right = timeRect.minX - 4
        return NSRect(x: left, y: 0, width: max(0, right - left), height: designHeight)
    }

    private var titleRect: NSRect {
        NSRect(x: middleRect.minX, y: topPad + 1, width: middleRect.width, height: SkinElements.TextFont.charHeight)
    }

    private var seekRect: NSRect {
        NSRect(x: middleRect.minX, y: designHeight - seekHeight - 1,
               width: middleRect.width, height: seekHeight)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let skin = currentSkin()
        let renderer = SkinRenderer(skin: skin)
        let scale = nativeScale

        // Flip to top-left origin, then scale into native units.
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: scale, y: scale)

        let designRect = NSRect(x: 0, y: 0, width: designWidth, height: designHeight)

        // Background strip + faint bottom separator so the bar reads as its own surface.
        context.setFillColor(NSColor(calibratedWhite: 0.07, alpha: 1.0).cgColor)
        context.fill(designRect)
        context.setStrokeColor(NSColor(calibratedWhite: 0.0, alpha: 0.6).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: 0, y: designHeight - 0.5))
        context.addLine(to: CGPoint(x: designWidth, y: designHeight - 0.5))
        context.strokePath()

        // Transport buttons (prev, play/pause, stop, next).
        let rects = transportRects
        let buttons: [ButtonType] = [.previous, isPlaying ? .pause : .play, .stop, .next]
        for (button, rect) in zip(buttons, rects) {
            let state: ButtonState = (pressedButton == button) ? .pressed : .normal
            renderer.drawButton(button, state: state, at: rect, in: context)
        }

        // Seek bar (classic posbar groove + thumb).
        let seekFraction: CGFloat = {
            if let pos = seekDragPosition { return pos }
            guard duration > 0 else { return 0 }
            return CGFloat(min(max(currentTime / duration, 0), 1))
        }()
        drawPositionBar(fraction: seekFraction, renderer: renderer, skin: skin, context: context)

        // Time readout in the classic bitmap font.
        let timeText = "\(format(currentTime)) / \(format(duration))"
        renderer.drawSkinText(timeText, at: NSPoint(x: timeRect.minX, y: timeRect.minY), in: context)

        // Scrolling title marquee, clipped to its region.
        drawTitle(renderer: renderer, context: context)

        // Volume slider (classic volume sprite + thumb).
        let volume = CGFloat(WindowManager.shared.audioEngine.volume)
        drawVolumeBar(fraction: volume, renderer: renderer, skin: skin, context: context)

        context.restoreGState()
    }

    private func drawTitle(renderer: SkinRenderer, context: CGContext) {
        let region = titleRect
        guard region.width > 0 else { return }
        let title = (currentTrack?.displayTitle ?? "").uppercased()
        guard !title.isEmpty else { return }

        context.saveGState()
        context.clip(to: region)
        let textWidth = CGFloat(title.count) * SkinElements.TextFont.charWidth
        if textWidth <= region.width {
            renderer.drawSkinText(title, at: NSPoint(x: region.minX, y: region.minY), in: context)
        } else {
            // Scroll: draw the title twice with a gap so it wraps continuously.
            let gap: CGFloat = 6 * SkinElements.TextFont.charWidth
            let cycle = textWidth + gap
            var x = region.minX - marqueeOffset.truncatingRemainder(dividingBy: cycle)
            while x < region.maxX {
                renderer.drawSkinText(title, at: NSPoint(x: x, y: region.minY), in: context)
                x += cycle
            }
        }
        context.restoreGState()
    }

    private func drawPositionBar(fraction: CGFloat, renderer: SkinRenderer, skin: Skin, context: CGContext) {
        let track = seekRect
        guard track.width > 0 else { return }
        guard let posbar = skin.posbar else {
            drawFallbackTrack(track, fraction: fraction, context: context)
            return
        }
        renderer.drawSprite(from: posbar, sourceRect: SkinElements.PositionBar.background, to: track, in: context)
        let thumbX = track.minX + (track.width - posThumbSize.width) * fraction
        let thumbRect = NSRect(x: thumbX, y: track.minY + (track.height - posThumbSize.height) / 2,
                               width: posThumbSize.width, height: posThumbSize.height)
        let thumbSrc = isDraggingSeek ? SkinElements.PositionBar.thumbPressed : SkinElements.PositionBar.thumbNormal
        renderer.drawSprite(from: posbar, sourceRect: thumbSrc, to: thumbRect, in: context)
    }

    private func drawVolumeBar(fraction: CGFloat, renderer: SkinRenderer, skin: Skin, context: CGContext) {
        let slider = volumeRect
        guard let volume = skin.volume else {
            drawFallbackTrack(slider, fraction: fraction, context: context)
            return
        }
        let level = Int(fraction * 27)
        renderer.drawSprite(from: volume, sourceRect: SkinElements.Volume.background(level: level), to: slider, in: context)
        let thumbX = slider.minX + (slider.width - volThumbSize.width) * fraction
        let thumbRect = NSRect(x: thumbX, y: slider.minY + (slider.height - volThumbSize.height) / 2,
                               width: volThumbSize.width, height: volThumbSize.height)
        let thumbSrc = isDraggingVolume ? SkinElements.Volume.thumbPressed : SkinElements.Volume.thumbNormal
        renderer.drawSprite(from: volume, sourceRect: thumbSrc, to: thumbRect, in: context)
    }

    private func drawFallbackTrack(_ rect: NSRect, fraction: CGFloat, context: CGContext) {
        context.setFillColor(NSColor.darkGray.cgColor)
        context.fill(rect)
        context.setFillColor(NSColor.systemGreen.cgColor)
        context.fill(NSRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height))
    }

    private var isPlaying: Bool {
        WindowManager.shared.audioEngine.state == .playing
    }

    private func format(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "00:00" }
        let total = Int(time)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Mouse handling

    /// Convert a window-space event point into native-unit (top-left origin) coordinates.
    private func nativePoint(_ event: NSEvent) -> NSPoint {
        let p = convert(event.locationInWindow, from: nil)
        let s = nativeScale
        guard s > 0 else { return p }
        return NSPoint(x: p.x / s, y: (bounds.height - p.y) / s)
    }

    override func mouseDown(with event: NSEvent) {
        let p = nativePoint(event)

        if seekRect.insetBy(dx: 0, dy: -6).contains(p) {
            isDraggingSeek = true
            updateSeekPosition(from: p)
            needsDisplay = true
            return
        }
        if volumeRect.insetBy(dx: 0, dy: -6).contains(p) {
            isDraggingVolume = true
            updateVolumePosition(from: p)
            needsDisplay = true
            return
        }

        let rects = transportRects
        let playButton: ButtonType = isPlaying ? .pause : .play
        let buttons: [ButtonType] = [.previous, playButton, .stop, .next]
        for (button, rect) in zip(buttons, rects) where rect.contains(p) {
            pressedButton = button
            needsDisplay = true
            return
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = nativePoint(event)
        if isDraggingSeek {
            updateSeekPosition(from: p)
            needsDisplay = true
        } else if isDraggingVolume {
            updateVolumePosition(from: p)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let engine = WindowManager.shared.audioEngine
        if isDraggingSeek {
            isDraggingSeek = false
            if let pos = seekDragPosition, duration > 0 {
                engine.seek(to: Double(pos) * duration)
            }
            seekDragPosition = nil
        } else if isDraggingVolume {
            isDraggingVolume = false
        } else if let button = pressedButton {
            switch button {
            case .previous: engine.previous()
            case .play: engine.play()
            case .pause: engine.pause()
            case .stop: engine.stop()
            case .next: engine.next()
            default: break
            }
        }
        pressedButton = nil
        needsDisplay = true
    }

    private func updateSeekPosition(from point: NSPoint) {
        guard seekRect.width > 0 else { return }
        let fraction = (point.x - seekRect.minX) / seekRect.width
        seekDragPosition = min(max(fraction, 0), 1)
    }

    private func updateVolumePosition(from point: NSPoint) {
        guard volumeRect.width > 0 else { return }
        let fraction = (point.x - volumeRect.minX) / volumeRect.width
        WindowManager.shared.audioEngine.volume = Float(min(max(fraction, 0), 1))
    }

    // MARK: - Marquee

    private func startMarquee() {
        marqueeTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            let title = (self.currentTrack?.displayTitle ?? "").uppercased()
            guard !title.isEmpty else { return }
            let textWidth = CGFloat(title.count) * SkinElements.TextFont.charWidth
            guard self.titleRect.width > 0, textWidth > self.titleRect.width else { return }
            self.marqueeOffset += 1
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        marqueeTimer = timer
    }

    // MARK: - Public update entry points

    func updateTime(current: TimeInterval, duration: TimeInterval) {
        let oldSeconds = Int(currentTime)
        let durationChanged = abs(self.duration - duration) > 0.5
        currentTime = current
        self.duration = duration
        guard !isDraggingSeek else { return }
        if oldSeconds != Int(current) || durationChanged {
            needsDisplay = true
        }
    }

    func updateTrackInfo(_ track: Track?) {
        currentTrack = track
        marqueeOffset = 0
        needsDisplay = true
    }

    func updatePlaybackState() {
        needsDisplay = true
    }

    func skinDidChange() {
        needsDisplay = true
    }
}
