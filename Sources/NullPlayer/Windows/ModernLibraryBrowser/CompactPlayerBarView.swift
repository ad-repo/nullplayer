import AppKit
import QuartzCore

/// A stripped-down modern player bar embedded at the top of the library browser in Compact Mode.
///
/// Renders transport controls, a seek bar with elapsed/remaining time, a scrolling track-title
/// marquee, and a volume slider — all via `ModernSkinRenderer` primitives and `ModernMarqueeLayer`.
/// Binds directly to `WindowManager.shared.audioEngine`.
///
/// Has ZERO dependencies on the classic skin system, matching the rest of `ModernLibraryBrowser/`.
///
/// Coordinate note: the renderer is created with a fixed `scaleFactor` of 1.0 so this view can lay
/// out every element in its own real pixel `bounds` (the library window is sized by
/// `ModernSkinElements.sizeMultiplier`, not the main window's base scale factor).
final class CompactPlayerBarView: NSView {

    // MARK: - Properties

    private var renderer: ModernSkinRenderer!
    private var marqueeLayer: ModernMarqueeLayer!

    private var currentTime: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var currentTrack: Track?

    // Interaction state
    private var isDraggingSeek = false
    private var isDraggingVolume = false
    private var seekDragPosition: CGFloat?
    private var pressedButton: String?

    /// Size multiplier mirrors the library browser's own scaling.
    private var m: CGFloat { ModernSkinElements.sizeMultiplier }

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

        let skin = currentSkin()
        renderer = ModernSkinRenderer(skin: skin, scaleFactor: 1.0)

        let marquee = ModernMarqueeLayer()
        marquee.configure(with: skin)
        marquee.textFont = NSFont.monospacedSystemFont(ofSize: 11 * m, weight: .medium)
        marquee.zPosition = 10
        layer?.addSublayer(marquee)
        marqueeLayer = marquee
    }

    private func currentSkin() -> ModernSkin {
        ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
    }

    // MARK: - Layout

    /// Suggested bar height for a given size multiplier.
    static func preferredHeight(for sizeMultiplier: CGFloat) -> CGFloat {
        44 * sizeMultiplier
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        marqueeLayer.frame = titleRect
        CATransaction.commit()
        needsDisplay = true
    }

    // Element rects (real pixels, bottom-left origin).
    private var pad: CGFloat { 8 * m }
    private var buttonSize: CGFloat { 18 * m }
    private var buttonGap: CGFloat { 5 * m }

    private var transportRects: (prev: NSRect, play: NSRect, stop: NSRect, next: NSRect) {
        let y = bounds.midY - buttonSize / 2
        let x0 = pad
        let step = buttonSize + buttonGap
        return (
            NSRect(x: x0, y: y, width: buttonSize, height: buttonSize),
            NSRect(x: x0 + step, y: y, width: buttonSize, height: buttonSize),
            NSRect(x: x0 + step * 2, y: y, width: buttonSize, height: buttonSize),
            NSRect(x: x0 + step * 3, y: y, width: buttonSize, height: buttonSize)
        )
    }

    private var volumeRect: NSRect {
        let w = 70 * m
        let h = 6 * m
        return NSRect(x: bounds.maxX - pad - w, y: bounds.midY - h / 2, width: w, height: h)
    }

    private var midLeft: CGFloat { transportRects.next.maxX + buttonGap * 2 }
    private var midRight: CGFloat { volumeRect.minX - buttonGap * 2 }

    private var timeRect: NSRect {
        let w = 82 * m
        return NSRect(x: midRight - w, y: 0, width: w, height: bounds.height * 0.5)
    }

    private var seekRect: NSRect {
        let h = 6 * m
        let right = timeRect.minX - buttonGap
        return NSRect(x: midLeft, y: bounds.height * 0.25 - h / 2, width: max(0, right - midLeft), height: h)
    }

    private var titleRect: NSRect {
        NSRect(x: midLeft, y: bounds.height * 0.46,
               width: max(0, midRight - midLeft), height: bounds.height * 0.5 - 2 * m)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        renderer.skin = currentSkin()

        // Background + faint bottom separator so the bar reads as a distinct strip.
        let skin = renderer.skin
        let isMetal = ModernSkinEngine.shared.currentRenderStyle == .metal
        let barFill = isMetal
            ? NSColor(calibratedRed: 0.62, green: 0.67, blue: 0.69, alpha: 0.34)
            : skin.surfaceColor.withAlphaComponent(0.18)
        context.setFillColor(barFill.cgColor)
        context.fill(bounds)
        let separator = isMetal
            ? NSColor(calibratedRed: 0.24, green: 0.27, blue: 0.29, alpha: 0.42)
            : skin.borderColor.withAlphaComponent(0.35)
        context.setStrokeColor(separator.cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: bounds.minX, y: bounds.minY + 0.5))
        context.addLine(to: CGPoint(x: bounds.maxX, y: bounds.minY + 0.5))
        context.strokePath()

        let t = transportRects
        renderer.drawTransportButton("btn_prev", state: state(for: "btn_prev"), in: t.prev, context: context)
        let playId = isPlaying ? "btn_pause" : "btn_play"
        renderer.drawTransportButton(playId, state: state(for: "btn_play"), in: t.play, context: context)
        renderer.drawTransportButton("btn_stop", state: state(for: "btn_stop"), in: t.stop, context: context)
        renderer.drawTransportButton("btn_next", state: state(for: "btn_next"), in: t.next, context: context)

        // Seek bar
        let seekFraction: CGFloat = {
            if let pos = seekDragPosition { return pos }
            guard duration > 0 else { return 0 }
            return CGFloat(currentTime / duration)
        }()
        renderer.drawSlider(trackId: "seek_track", fillId: "seek_fill", thumbId: "seek_thumb",
                            trackRect: seekRect, fillFraction: seekFraction,
                            thumbState: isDraggingSeek ? "pressed" : "normal", context: context)

        // Time label "elapsed / total"
        let timeText = "\(format(currentTime)) / \(format(duration))"
        let timeColor = isMetal ? skin.textColor : skin.timeColor
        renderer.drawLabel(timeText, in: timeRect,
                           font: NSFont.monospacedDigitSystemFont(ofSize: 10 * m, weight: .regular),
                           color: timeColor, alignment: .right, context: context)

        // Volume slider
        let volume = CGFloat(WindowManager.shared.audioEngine.volume)
        renderer.drawSlider(trackId: "volume_track", fillId: "volume_fill", thumbId: "volume_thumb",
                            trackRect: volumeRect, fillFraction: volume,
                            thumbState: isDraggingVolume ? "pressed" : "normal", context: context)
    }

    private func state(for id: String) -> String {
        pressedButton == id ? "pressed" : "normal"
    }

    private var isPlaying: Bool {
        WindowManager.shared.audioEngine.state == .playing
    }

    private func format(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "00:00" }
        let total = Int(time)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        if seekRect.insetBy(dx: 0, dy: -8 * m).contains(p) {
            isDraggingSeek = true
            updateSeekPosition(from: p)
            needsDisplay = true
            return
        }
        if volumeRect.insetBy(dx: 0, dy: -8 * m).contains(p) {
            isDraggingVolume = true
            updateVolumePosition(from: p)
            needsDisplay = true
            return
        }

        let t = transportRects
        if t.prev.contains(p) { pressedButton = "btn_prev" }
        else if t.play.contains(p) { pressedButton = "btn_play" }
        else if t.stop.contains(p) { pressedButton = "btn_stop" }
        else if t.next.contains(p) { pressedButton = "btn_next" }
        if pressedButton != nil { needsDisplay = true }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
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
            needsDisplay = true
        } else if isDraggingVolume {
            isDraggingVolume = false
            needsDisplay = true
        } else if let button = pressedButton {
            switch button {
            case "btn_prev": engine.previous()
            case "btn_play": isPlaying ? engine.pause() : engine.play()
            case "btn_stop": engine.stop()
            case "btn_next": engine.next()
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

    // MARK: - Public Update Methods

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
        marqueeLayer.text = (track?.displayTitle ?? "").uppercased()
        needsDisplay = true
    }

    func updatePlaybackState() {
        needsDisplay = true
    }

    /// Re-read skin colours/fonts after a skin change.
    func skinDidChange() {
        let skin = currentSkin()
        renderer.skin = skin
        marqueeLayer.configure(with: skin)
        marqueeLayer.textFont = NSFont.monospacedSystemFont(ofSize: 11 * m, weight: .medium)
        needsDisplay = true
    }
}
