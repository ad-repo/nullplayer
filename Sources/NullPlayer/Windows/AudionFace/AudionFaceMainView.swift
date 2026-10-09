import AppKit

/// Shows a face: blits `AudionFaceRenderer`'s output for the current state, the same draw path the
/// harness measures. A press on a button runs it; a press anywhere else the face is opaque drags
/// the window through `WindowManager`, so docking and snapping see it; a transparent pixel is not
/// part of the window at all.
final class AudionFaceMainView: NSView {
    var face: AudionFace? { didSet { interaction = .init(); redraw() } }
    var host = AudionFaceHostState() { didSet { if host != oldValue { redraw() } } }
    /// Window points per face pixel.
    var uiScale: CGFloat = 1 { didSet { if uiScale != oldValue { redraw() } } }
    var onButton: ((AudionFace.ButtonRole) -> Void)?

    private var interaction = AudionFaceInteractionState() { didSet { if interaction != oldValue { redraw() } } }
    private var image: CGImage?
    private var drag = AudionFaceWindowDrag()

    override var isFlipped: Bool { true }
    /// The face drags itself, through `WindowManager`; AppKit's background drag would bypass docking.
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .nearest
        setAccessibilityIdentifier("AudionFaceMainView")
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        redraw()
    }

    /// Rendered at the device scale (rounded up to an integer), so text stays sharp on a 2x display.
    private func redraw() {
        guard let face else { image = nil; layer?.contents = nil; return }
        let backing = window?.backingScaleFactor ?? 2
        let scale = max(1, Int((uiScale * backing).rounded(.up)))
        image = AudionFaceRenderer.render(AudionFaceScene(face: face, host: host, interaction: interaction,
                                                          scale: scale))
        layer?.contents = image
        layer?.contentsScale = backing
        window?.invalidateShadow()
    }

    // MARK: - Hit testing, in face pixels with a top-left origin

    private func facePoint(_ event: NSEvent) -> (x: Int, y: Int)? {
        guard let face, bounds.width > 0, bounds.height > 0 else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        return (Int(point.x * CGFloat(face.base.width) / bounds.width),
                Int(point.y * CGFloat(face.base.height) / bounds.height))
    }

    private func button(at event: NSEvent) -> AudionFace.ButtonRole? {
        guard let face, let point = facePoint(event),
              let role = AudionFaceScene.button(atX: point.x, y: point.y, face: face, host: host),
              AudionFaceScene.isEnabled(role, host: host, interaction: interaction) else { return nil }
        return role
    }

    /// The window shape is the rendered alpha: a click on a clear pixel goes to whatever is behind.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let image, let local = superview.map({ convert(point, from: $0) }),
              bounds.contains(local) else { return super.hitTest(point) }
        let x = Int(local.x * CGFloat(image.width) / bounds.width)
        let y = Int(local.y * CGFloat(image.height) / bounds.height)
        return Self.alpha(of: image, x: x, y: y) > 0 ? self : nil
    }

    private static func alpha(of image: CGImage, x: Int, y: Int) -> UInt8 {
        var pixel: UInt8 = 0
        guard (0..<image.width).contains(x), (0..<image.height).contains(y),
              let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 1,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
        else { return 0 }
        // Shift the image so (x, y) — top-left origin — lands on the one-pixel canvas.
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return pixel
    }

    // MARK: - Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) { interaction.hovered = button(at: event) }
    override func mouseExited(with event: NSEvent) { interaction.hovered = nil }

    override func mouseDown(with event: NSEvent) {
        if let role = button(at: event) {
            interaction.pressed = role
        } else {
            drag.begin(event)
        }
    }

    override func mouseDragged(with event: NSEvent) { drag.move(event) }

    override func mouseUp(with event: NSEvent) {
        drag.end(event)
        guard let pressed = interaction.pressed else { return }
        interaction.pressed = nil
        if button(at: event) == pressed { onButton?(pressed) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        ContextMenuBuilder.buildMenu(includeOutputDevices: false, includeRepeatShuffle: false)
    }
}

/// A drag of the borderless Audion window, through `WindowManager` so docking and snapping see it;
/// AppKit's own background drag would bypass both. Both of the mode's views drag with it.
struct AudionFaceWindowDrag {
    private var start: NSPoint?

    mutating func begin(_ event: NSEvent) {
        guard let window = event.window else { return }
        start = event.locationInWindow
        WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
    }

    func move(_ event: NSEvent) {
        guard let start, let window = event.window else { return }
        var origin = window.frame.origin
        origin.x += event.locationInWindow.x - start.x
        origin.y += event.locationInWindow.y - start.y
        window.setFrameOrigin(WindowManager.shared.windowWillMove(window, to: origin))
    }

    mutating func end(_ event: NSEvent) {
        guard start != nil, let window = event.window else { return }
        start = nil
        WindowManager.shared.windowDidFinishDragging(window)
    }
}
