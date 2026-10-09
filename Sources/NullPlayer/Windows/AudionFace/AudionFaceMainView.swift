import AppKit

/// Shows a face: blits `AudionFaceRenderer`'s output for the current state, the same draw path the
/// harness measures. A press on a button runs it; a press on a time digit opens the position
/// slider; a press anywhere else the face is opaque drags the window through `WindowManager`, so
/// docking and snapping see it; a transparent pixel is not part of the window at all.
final class AudionFaceMainView: NSView {
    var face: AudionFace? { didSet { interaction = .init(); accessibilityElements = [:]; redraw() } }
    var host = AudionFaceHostState() { didSet { if host != oldValue { redraw() } } }
    /// Window points per face pixel.
    var uiScale: CGFloat = 1 { didSet { if uiScale != oldValue { redraw() } } }
    var onCommand: ((AudionFaceCommand) -> Void)?

    private var interaction = AudionFaceInteractionState() { didSet { if interaction != oldValue { redraw() } } }
    /// The face's pixels, redrawn only where a new scene differs from the last.
    private var canvas = AudionFaceCanvas()
    private var drag = AudionFaceWindowDrag()
    /// FaceKit's 60 Hz tick count. The clock runs only while `AudionFaceScene.isAnimated` and the
    /// window is on screen.
    private var tick = 0 { didSet { redraw() } }
    private var clock: Timer?
    /// FaceKit's two popups, at FaceKit's sizes.
    private let volumeSlider = AudionFaceSliderWindow(size: NSSize(width: 19, height: 96), vertical: true, label: "Volume")
    private let positionSlider = AudionFaceSliderWindow(size: NSSize(width: 192, height: 19), vertical: false,
                                                        label: "Position")
    private var playingBeforeScrub = false
    /// Kept across `accessibilityChildren()` calls, by identifier, so VoiceOver's focus survives a
    /// redraw; a new face drops them.
    private var accessibilityElements: [String: AudionFaceAccessibilityElement] = [:]

    override var isFlipped: Bool { true }
    /// The face drags itself, through `WindowManager`; AppKit's background drag would bypass docking.
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Drawn in `draw(_:)`, so a redraw updates only the rects marked: new layer contents would
        // be copied and colour-converted whole every tick.
        wantsLayer = true
        setAccessibilityIdentifier("AudionFaceMainView")
        setAccessibilityRole(.group)
        volumeSlider.onChange = { [weak self] value, _ in self?.onCommand?(.volume(value)) }
        // FaceKit disables the volume button while its slider is up.
        volumeSlider.onClose = { [weak self] in self?.interaction.disabled.remove(.volume) }
        positionSlider.onChange = { [weak self] value, finished in self?.scrub(to: value, finished: finished) }
        positionSlider.onClose = { [weak self] in self?.endScrub() }
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        redraw()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateClock()
    }

    /// Rendered at the device scale (rounded up to an integer), so text stays sharp on a 2x display.
    /// Only what changed is redrawn, and the shadow is recomputed only when the outline moved.
    private func redraw() {
        defer { updateClock() }
        guard let face else { canvas = AudionFaceCanvas(); needsDisplay = true; return }
        let backing = window?.backingScaleFactor ?? 2
        let scale = max(1, Int((uiScale * backing).rounded(.up)))
        let change = canvas.draw(AudionFaceScene(face: face, host: host, interaction: interaction, frame: tick, scale: scale))
        for rect in change.rects { setNeedsDisplay(localRect(rect)) }
        guard change.outlineChanged else { return }
        displayIfNeeded()
        window?.invalidateShadow()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image = canvas.image, let context = NSGraphicsContext.current?.cgContext else { return }
        // The view is flipped and the image is not.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        // Device pixel for device pixel at an integer UI size; smoothed at a fractional one.
        context.interpolationQuality = uiScale == uiScale.rounded() ? .none : .default
        context.draw(image, in: bounds)
    }

    /// Starts or stops the frame clock for the state on screen; the controller calls it when the
    /// window's occlusion changes.
    func updateClock() {
        let animates = face.map { AudionFaceScene.isAnimated($0, host) } == true
            && window?.occlusionState.contains(.visible) == true
        guard animates else { clock?.invalidate(); clock = nil; return }
        guard clock == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                self.tick += 1
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    // MARK: - Geometry: face pixels, top-left origin

    private func facePoint(_ event: NSEvent) -> (x: Int, y: Int)? {
        guard let face, bounds.width > 0, bounds.height > 0 else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        return (Int(point.x * CGFloat(face.base.width) / bounds.width),
                Int(point.y * CGFloat(face.base.height) / bounds.height))
    }

    private func localRect(_ rect: AudionFaceRect) -> NSRect {
        guard let face else { return .zero }
        let sx = bounds.width / CGFloat(face.base.width), sy = bounds.height / CGFloat(face.base.height)
        return NSRect(x: CGFloat(rect.x) * sx, y: CGFloat(rect.y) * sy,
                      width: CGFloat(rect.width) * sx, height: CGFloat(rect.height) * sy)
    }

    private func screenRect(_ rect: AudionFaceRect) -> NSRect {
        window?.convertToScreen(convert(localRect(rect), to: nil)) ?? .zero
    }

    private func button(at event: NSEvent) -> AudionFace.ButtonRole? {
        guard let face, let point = facePoint(event),
              let role = AudionFaceScene.button(atX: point.x, y: point.y, face: face, host: host),
              AudionFaceScene.isEnabled(role, host: host, interaction: interaction) else { return nil }
        return role
    }

    /// The time digit under the event, while there is a duration to scrub (FaceKit `showTimeSlider`).
    private func timeDigit(at event: NSEvent) -> AudionFaceRect? {
        guard let face, host.isSeekable, let point = facePoint(event) else { return nil }
        return AudionFaceScene.timeDigitRects(face).first { $0.contains(x: point.x, y: point.y) }
    }

    /// The window shape is the rendered alpha: a click on a clear pixel goes to whatever is behind.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let image = canvas.image, let local = superview.map({ convert(point, from: $0) }),
              bounds.contains(local) else { return super.hitTest(point) }
        let x = Int(local.x * CGFloat(image.width) / bounds.width)
        let y = Int(local.y * CGFloat(image.height) / bounds.height)
        return canvas.isOpaque(x: x, y: y) ? self : nil
    }

    // MARK: - Actions

    /// A button's press. Volume and info open this view's popups beneath the button; the rest are
    /// `AudionFaceCommand`s.
    private func press(_ role: AudionFace.ButtonRole) {
        guard let rect = face?.buttons[role]?.rect else { return }
        switch role {
        case .volume:
            interaction.disabled.insert(.volume)
            let below = screenRect(rect)
            volumeSlider.show(topLeft: NSPoint(x: below.maxX, y: below.minY),
                              value: Double(WindowManager.shared.audioEngine.volume), range: 0...1)
        case .info:
            showInfoMenu(below: rect)
        default:
            onCommand?(.button(role))
        }
    }

    private func showPositionSlider(below rect: AudionFaceRect) {
        guard host.isSeekable else { return }
        let below = screenRect(rect)
        positionSlider.show(topLeft: NSPoint(x: below.maxX, y: below.minY), value: Double(host.elapsedSeconds),
                            range: 0...Double(host.durationSeconds))
    }

    /// FaceKit `adjustTime`: scrubbing pauses a playing track and resumes it on mouse-up.
    private func scrub(to seconds: Double, finished: Bool) {
        if host.isPlaying {
            playingBeforeScrub = true
            onCommand?(.button(.pause))
        }
        onCommand?(.seek(seconds))
        if finished { endScrub() }
    }

    /// Resumes what the scrub paused: on mouse-up, or when the popup closes after a change that had
    /// no mouse-up (the keyboard, VoiceOver).
    private func endScrub() {
        guard playingBeforeScrub else { return }
        playingBeforeScrub = false
        onCommand?(.button(.play))
    }

    private func showInfoMenu(below rect: AudionFaceRect) {
        let menu = NSMenu()
        let playing = NSMenuItem(title: "About Playing…", action: #selector(MenuActions.showAboutPlaying), keyEquivalent: "")
        playing.target = MenuActions.shared
        let about = NSMenuItem(title: "About This Face…", action: #selector(showFaceAbout), keyEquivalent: "")
        about.target = self
        menu.items = [playing, about]
        let below = localRect(rect)
        menu.popUp(positioning: nil, at: NSPoint(x: below.minX, y: below.maxY), in: self)
    }

    /// The face's credit: `faceInfo` as text, `about.png` beside it.
    @objc private func showFaceAbout() {
        guard let face else { return }
        let alert = NSAlert()
        alert.messageText = "About This Face"
        alert.informativeText = face.faceInfo.isEmpty ? "The face carries no credit." : face.faceInfo.joined(separator: "\n")
        if let about = face.about {
            let view = NSImageView(image: NSImage(cgImage: about, size: .zero))
            view.imageScaling = .scaleProportionallyDown
            view.frame.size = NSSize(width: min(about.width, 480), height: min(about.height, 480))
            alert.accessoryView = view
        }
        alert.runModal()
    }

    // MARK: - Mouse and keyboard

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
        } else if let digit = timeDigit(at: event) {
            showPositionSlider(below: digit)
        } else {
            drag.begin(event)
        }
    }

    override func mouseDragged(with event: NSEvent) { drag.move(event) }

    override func mouseUp(with event: NSEvent) {
        drag.end(event)
        guard let pressed = interaction.pressed else { return }
        interaction.pressed = nil
        if button(at: event) == pressed { press(pressed) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        ContextMenuBuilder.buildMenu(includeOutputDevices: false, includeRepeatShuffle: false)
    }

    override func keyDown(with event: NSEvent) {
        if !MainWindowKeys.perform(event) { super.keyDown(with: event) }
    }

    // MARK: - Accessibility (FaceKit: a button per face button, the time digits, the two labels)

    override func accessibilityChildren() -> [Any]? {
        guard let face else { return [] }
        var children = AudionFaceScene.visibleButtons(face, host).map { role, button in
            let element = accessibilityElement("audion.\(role.sprite)", role: .button) { [weak self] in self?.press(role) }
            element.setAccessibilityLabel(Self.title(for: role))
            element.setAccessibilityEnabled(AudionFaceScene.isEnabled(role, host: host, interaction: interaction))
            element.setAccessibilityFrame(screenRect(button.rect))
            return element
        }
        let digits = AudionFaceScene.timeDigitRects(face)
        if let first = digits.first {
            let element = accessibilityElement("Time Digits", role: .button) { [weak self] in
                self?.showPositionSlider(below: first)
            }
            let time = String(format: "%02d:%02d", host.elapsedSeconds / 60, host.elapsedSeconds % 60)
            element.setAccessibilityLabel("\(time) — Show Position Slider")
            element.setAccessibilityEnabled(host.isSeekable)
            element.setAccessibilityFrame(digits.dropFirst().map(screenRect).reduce(screenRect(first)) { $0.union($1) })
            children.append(element)
        }
        let labels: [(String, AudionFace.TextLine?, String?)] = [
            ("Artist", face.artist, host.artistLine), ("Album", face.album, host.albumLine),
        ]
        for (identifier, line, text) in labels {
            guard let line, let text else { continue }
            let element = accessibilityElement(identifier, role: .staticText, press: nil)
            element.setAccessibilityLabel(text)
            element.setAccessibilityValue(text)
            element.setAccessibilityFrame(screenRect(line.rect))
            children.append(element)
        }
        return children
    }

    private func accessibilityElement(_ identifier: String, role: NSAccessibility.Role,
                                      press: (() -> Void)?) -> AudionFaceAccessibilityElement {
        if let element = accessibilityElements[identifier] { return element }
        let element = AudionFaceAccessibilityElement(role: role, press: press)
        element.setAccessibilityIdentifier(identifier)
        element.setAccessibilityParent(self)
        accessibilityElements[identifier] = element
        return element
    }

    /// FaceKit's tooltips, naming NullPlayer's action where the button maps to one of its own.
    private static func title(for role: AudionFace.ButtonRole) -> String {
        switch role {
        case .play: "Play"
        case .pause: "Pause"
        case .stop: "Stop"
        case .rewind: "Previous Track"
        case .fastForward: "Next Track"
        case .eject: "Open Files"
        case .close: "Quit"
        case .info: "Info"
        case .volume: "Show Volume Slider"
        case .playlist: "Playlist"
        case .mode: "Play Mode"
        }
    }
}

/// One of the face's accessibility children; a button presses through `press`.
private final class AudionFaceAccessibilityElement: NSAccessibilityElement {
    private let press: (() -> Void)?

    init(role: NSAccessibility.Role, press: (() -> Void)?) {
        self.press = press
        super.init()
        setAccessibilityRole(role)
        setAccessibilityElement(true)
    }

    override func accessibilityPerformPress() -> Bool {
        press?()
        return press != nil
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
