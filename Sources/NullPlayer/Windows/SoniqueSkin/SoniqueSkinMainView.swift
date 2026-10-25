import AppKit

/// Shows one mode of a Sonique skin: blits `SoniqueSkinRenderer`'s output, the same draw path the
/// harness measures. A press on a control runs it on release; the knobs turn with vertical or
/// horizontal motion, as Sonique's do, and an EQ slider follows the pointer; a press anywhere else inside the outline drags the window
/// through `WindowManager`, and a double-click there jumps a mode (help `02.htm` § *Jumping Between
/// Modes*). A pixel outside the outline is not part of the window.
final class SoniqueSkinMainView: NSView {
    var skin: SoniqueSkin? {
        didSet {
            dropEffects()
            // One redraw: through `state` when letting go changes it, else here.
            var released = state
            released.letGo()
            if released == state { redraw() } else { state = released }
        }
    }
    /// Everything on screen but the skin, settled after every change (`State.settle(after:)`).
    var state = SoniqueSkinScene.State() {
        didSet {
            state.settle(after: oldValue)
            guard state != oldValue else { return }
            show(state, after: oldValue)
        }
    }
    /// Window points per skin pixel.
    var uiScale: CGFloat = 1 { didSet { if uiScale != oldValue { redraw() } } }
    var onCommand: ((SoniqueSkinControl) -> Void)?
    /// A knob or slider turned to a value, 0–1.
    var onDial: ((SoniqueSkinControl, Double) -> Void)?
    var onMode: ((SoniqueSkin.Mode) -> Void)?
    /// A drawer changes the outline, so the window's shadow is rebuilt.
    var onOutlineChange: (() -> Void)?

    private var drawerClose: DispatchWorkItem?
    private var image: CGImage?
    private var drag = SkinnedWindowDrag()
    private var knobDrag: (control: SoniqueSkinControl, start: NSPoint, value: Double)?
    private let windowShadow = SkinWindowShadow()
    /// The visual mode screen's effects surface, present only while that screen shows: removing it
    /// stops its engine.
    private var effects: SkinEffectsSurfaceView?
    private var effectObserver: NSObjectProtocol?
    /// Steps `State.marqueeOffset` while a title shows.
    private var marqueeTimer: Timer?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        state.visualModeTitle = SkinEffectSelection.sonique.current.title
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityIdentifier("SoniqueSkinMainView")
        setAccessibilityRole(.group)
        effectObserver = NotificationCenter.default.addObserver(
            forName: SkinEffectSelection.didChange, object: SkinEffectSelection.sonique, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.state.visualModeTitle = SkinEffectSelection.sonique.current.title }
        }
    }

    deinit {
        effectObserver.map(NotificationCenter.default.removeObserver)
        marqueeTimer?.invalidate()
    }

    required init?(coder: NSCoder) { nil }

    /// The scene on screen: what was drawn, and what every hit reads.
    private(set) var scene: SoniqueSkinScene?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateMarqueeTimer()
        guard let window else { return windowShadow.detach() }
        windowShadow.attach(to: window, name: "sonique") { [weak self] in self?.image.map { [$0] } ?? [] }
    }

    /// What one state change does beside the redraw. A marquee step alone only repaints: the
    /// outline and the effects surface have not moved.
    private func show(_ new: SoniqueSkinScene.State, after old: SoniqueSkinScene.State) {
        if new.host != old.host {
            effects?.setActive(new.host.playState == .playing)
            updateMarqueeTimer()
        }
        guard !new.isScrolled(from: old) else { return render() }
        redraw()
        if new.navDrawerOpen != old.navDrawerOpen || new.smallDrawer != old.smallDrawer { onOutlineChange?() }
    }

    private func redraw() {
        render()
        windowShadow.invalidateShape("redraw")
        layoutEffects()
    }

    private func render() {
        scene = skin.map { SoniqueSkinScene(skin: $0, state: state) }
        image = scene.flatMap(SoniqueSkinRenderer.render)
        needsDisplay = true
    }

    /// ponytail: re-renders the whole mode 20 times a second while a title shows; render only the
    /// title lines over a cached picture if that shows up in a profile.
    private func updateMarqueeTimer() {
        let wanted = !state.host.title.isEmpty && window != nil
        guard wanted != (marqueeTimer != nil) else { return }
        marqueeTimer?.invalidate()
        marqueeTimer = wanted ? Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.state.marqueeOffset += 1 }
        } : nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutEffects()
    }

    /// The effects surface over the visual mode panel's well, cut to the display as the panel is.
    /// Placed again only when the window's size moves it; a new skin starts a new surface.
    private func layoutEffects() {
        guard let scene, let display = scene.visualScreenDisplay else { return dropEffects() }
        let well = SoniqueSkinScene.VisualScreen.effects.offset(display.bounds.left, display.bounds.top)
        let frame = viewRect(well, in: scene)
        if effects?.frame == frame { return }
        let surface = effects ?? SkinEffectsSurfaceView(frame: frame, selection: .sonique)
        if effects == nil {
            addSubview(surface)
            effects = surface
            surface.setActive(state.host.playState == .playing)
        }
        surface.frame = frame
        surface.applyClippingShape(Self.mask(display.rects, over: well), rect: surface.bounds)
    }

    /// A skin-pixel rect of the scene in this view's points.
    private func viewRect(_ rect: SoniqueSkinRegion.Rect, in scene: SoniqueSkinScene) -> CGRect {
        let scale = bounds.width / CGFloat(max(1, scene.width))
        return CGRect(x: CGFloat(rect.left - scene.canvas.left) * scale, y: CGFloat(rect.top - scene.canvas.top) * scale,
                      width: CGFloat(rect.right - rect.left) * scale, height: CGFloat(rect.bottom - rect.top) * scale)
    }

    private func dropEffects() {
        effects?.removeFromSuperview()
        effects = nil
    }

    /// `rects` as a mask over `area`, one pixel per skin pixel, its first row the top.
    private static func mask(_ rects: [SoniqueSkinRegion.Rect], over area: SoniqueSkinRegion.Rect) -> CGImage? {
        let width = area.right - area.left, height = area.bottom - area.top
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(rects.map { CGRect(x: $0.left - area.left, y: area.bottom - $0.bottom, width: $0.right - $0.left, height: $0.bottom - $0.top) })
        return context.makeImage()
    }

    func updateSpectrum(_ levels: [Float]) { effects?.updateSpectrum(levels) }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, let context = NSGraphicsContext.current?.cgContext else { return }
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = uiScale == uiScale.rounded() ? .none : .default
        context.draw(image, in: bounds)
    }

    // MARK: - Hit testing, skin pixels

    private func hit(_ event: NSEvent) -> SoniqueSkinScene.Hit {
        hit(at: convert(event.locationInWindow, from: nil))
    }

    /// With no scene yet, nothing is part of the window.
    private func hit(at point: NSPoint) -> SoniqueSkinScene.Hit {
        guard let scene, let canvas = canvasPoint(point) else { return .outside }
        return scene.hit(x: canvas.x, y: canvas.y)
    }

    private func canvasPoint(_ point: NSPoint) -> (x: Int, y: Int)? {
        guard let scene, bounds.width > 0, bounds.height > 0 else { return nil }
        return (Int(point.x * CGFloat(scene.width) / bounds.width), Int(point.y * CGFloat(scene.height) / bounds.height))
    }

    /// An EQ slider's value with its handle centred on the pointer.
    private func sliderValue(_ index: Int, at event: NSEvent) -> Double? {
        guard let scene, let point = canvasPoint(convert(event.locationInWindow, from: nil)) else { return nil }
        let track = scene.eqSliderTrack(index)
        let handle = scene.skin.settings.drawerSliders.handleHeight
        let y = Double(point.y + scene.canvas.top - track.top - handle / 2)
        return 1 - y / Double(max(1, track.bottom - track.top - handle))
    }

    /// `menu` popped up under a menu screen entry, as Sonique's own items open in place.
    func popUp(_ menu: NSMenu, under item: SoniqueSkinMenu.Item) {
        guard let scene, let rect = scene.menuEntries.first(where: { $0.item == item })?.hit else { return }
        let under = viewRect(rect, in: scene)
        let point = NSPoint(x: under.minX, y: under.maxY)
        menu.popUp(positioning: nil, at: point, in: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let local = superview.map({ convert(point, from: $0) }), bounds.contains(local) else { return super.hitTest(point) }
        return hit(at: local).isInside ? self : nil
    }

    // MARK: - Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    /// Small mode's drawer slides out while the pointer is over the bar or the open drawer, upward
    /// unless the screen's top edge leaves it no room.
    override func mouseMoved(with event: NSEvent) {
        guard state.mode == .small else { return }
        if hit(event).isInside {
            drawerClose?.cancel()
            if state.smallDrawer == nil { state.smallDrawer = roomAbove ? .top : .bottom }
        } else {
            scheduleDrawerClose()
        }
    }

    override func mouseExited(with event: NSEvent) { scheduleDrawerClose() }

    private func scheduleDrawerClose() {
        guard state.smallDrawer != nil, drawerClose == nil || drawerClose!.isCancelled else { return }
        let work = DispatchWorkItem { [weak self] in self?.state.smallDrawer = nil; self?.drawerClose = nil }
        drawerClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private var roomAbove: Bool {
        guard let window, let screen = window.screen ?? NSScreen.main else { return true }
        return window.frame.maxY <= screen.visibleFrame.maxY + 1
    }

    override func mouseDown(with event: NSEvent) {
        let hit = self.hit(event)
        guard hit.isInside else { return }
        if let control = hit.control, control.isActionable {
            state.pressed = control
            if case .eqSlider(let index) = control, let value = sliderValue(index, at: event) {
                onDial?(control, value)
            } else if let value = state.host.dial(control) {
                knobDrag = (control, event.locationInWindow, value)
            }
            return
        }
        if event.clickCount == 2 {
            onMode?(Self.mode(after: state.mode))
            return
        }
        drag.begin(event)
    }

    override func mouseDragged(with event: NSEvent) {
        if case .eqSlider(let index) = state.pressed, let value = sliderValue(index, at: event) {
            onDial?(.eqSlider(index), value)
            return
        }
        if let knobDrag {
            // Up or right turns clockwise (help `02.htm` § *Using Knobs*); 150 points spans the knob.
            let dx = event.locationInWindow.x - knobDrag.start.x, dy = event.locationInWindow.y - knobDrag.start.y
            onDial?(knobDrag.control, min(1, max(0, knobDrag.value + Double(dx + dy) / 150)))
            return
        }
        drag.move(event)
    }

    override func mouseUp(with event: NSEvent) {
        drag.end(event)
        knobDrag = nil
        guard let pressed = state.pressed else { return }
        state.pressed = nil
        guard state.host.dial(pressed) == nil, hit(event).control == pressed else { return }
        onCommand?(pressed)
    }

    /// A left double-click on the chassis: navigator to mid to small, and small back to the navigator.
    static func mode(after mode: SoniqueSkin.Mode) -> SoniqueSkin.Mode {
        switch mode {
        case .navigator: return .mid
        case .mid: return .small
        case .small: return .navigator
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if let effects, effects.frame.contains(convert(event.locationInWindow, from: nil)) { return effects.buildMenu() }
        return ContextMenuBuilder.buildMenu(includeOutputDevices: false, includeRepeatShuffle: false)
    }

    /// Command-arrows step the visual mode screen's effect (down/up) and the preset inside it
    /// (left/right); every other key is the main window's.
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let effects, effects.handleKeyDown(event) { return }
        if !MainWindowKeys.perform(event) { super.keyDown(with: event) }
    }
}
