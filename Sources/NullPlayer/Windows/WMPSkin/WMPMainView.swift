import AppKit

final class WMPMainView: NSView {
    var onInteractionChanged: ((WMPInteractionState, Set<Int>) -> Void)?
    var onAction: ((WMPTransportAction, WMPHostValue?) -> Void)?
    private var image: NSImage?
    private var scene: WMPScene?
    private var hitTester: WMPHitTester?
    private var interaction = WMPInteractionState()
    private var capturedTarget: WMPHitTarget?
    private var tracking: NSTrackingArea?
    private var isDraggingWindow = false
    private var dragStart = NSPoint.zero

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func present(_ cgImage: CGImage, scene: WMPScene, dirtyBounds: WMPRect? = nil) {
        image = NSImage(cgImage: cgImage, size: bounds.size)
        self.scene = scene
        hitTester = WMPHitTester(hits: scene.hits)
        if let dirtyBounds {
            let xScale = bounds.width / scene.canvasSize.width
            let yScale = bounds.height / scene.canvasSize.height
            setNeedsDisplay(NSRect(x: dirtyBounds.x * xScale, y: dirtyBounds.y * yScale,
                                   width: dirtyBounds.width * xScale, height: dirtyBounds.height * yScale))
        } else { needsDisplay = true }
        setAccessibilityChildren(nil)
    }

    func refreshHostState(_ snapshot: WMPHostSnapshot) {
        guard let scene else { return }
        var changed = Set<Int>()
        for hit in scene.hits {
            if let action = hit.action {
                changed.formUnion(interaction.setDisabled(!snapshot.isEnabled(action), node: hit.stableID))
                if hit.sticky { changed.formUnion(interaction.setStickyDown(Self.isDown(action, snapshot), node: hit.stableID)) }
            }
            for target in hit.mappingTargets {
                if let action = target.action {
                    changed.formUnion(interaction.setDisabled(!snapshot.isEnabled(action), node: target.stableID))
                    if target.sticky { changed.formUnion(interaction.setStickyDown(Self.isDown(action, snapshot), node: target.stableID)) }
                }
            }
        }
        notify(changed)
        setAccessibilityChildren(nil)
    }

    func prepareForUITeardown() {
        if !interaction.cancelCapture().isEmpty { onAction?(.endScan, nil) }
        image = nil; scene = nil; hitTester = nil; capturedTarget = nil; isDraggingWindow = false
        onInteractionChanged = nil; onAction = nil
    }

    func skinPoint(from event: NSEvent, sceneSize: WMPSize) -> WMPPoint {
        let point = convert(event.locationInWindow, from: nil)
        return WMPPoint(x: bounds.width > 0 ? point.x * sceneSize.width / bounds.width : 0,
                        y: bounds.height > 0 ? point.y * sceneSize.height / bounds.height : 0)
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
        super.updateTrackingAreas()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); dirtyRect.fill()
        image?.draw(in: bounds, from: .zero, operation: .copy, fraction: 1,
                    respectFlipped: true, hints: [.interpolation: NSImageInterpolation.low])
    }

    override func mouseMoved(with event: NSEvent) { updateHover(event) }
    override func mouseEntered(with event: NSEvent) { updateHover(event) }
    override func mouseExited(with event: NSEvent) { notify(interaction.move(over: nil)) }

    override func mouseDown(with event: NSEvent) {
        guard let scene else { return }
        let target = interactiveTarget(at: skinPoint(from: event, sceneSize: scene.canvasSize))
        guard let target else { beginWindowDrag(event); return }
        capturedTarget = target
        notify(interaction.press(target))
        window?.makeFirstResponder(self)
        if case .beginScan = target.action { onAction?(target.action!, nil) }
        if target.action == .seek || target.action == .volume || target.action == .balance { performSlider(target, event: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        if isDraggingWindow { dragWindow(event); return }
        guard let capturedTarget else { return }
        if capturedTarget.action == .seek || capturedTarget.action == .volume || capturedTarget.action == .balance { performSlider(capturedTarget, event: event) }
        updateHover(event)
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingWindow { finishWindowDrag(); return }
        guard let scene else { return }
        let target = interactiveTarget(at: skinPoint(from: event, sceneSize: scene.canvasSize))
        let result = interaction.release(over: target)
        notify(result.changed)
        defer { capturedTarget = nil }
        guard let capturedTarget else { return }
        if case .beginScan = capturedTarget.action { onAction?(.endScan, nil); return }
        guard result.activated == capturedTarget.stableID, let action = capturedTarget.action,
              action != .seek, action != .volume, action != .balance else { return }
        onAction?(action, nil)
    }

    override func cancelOperation(_ sender: Any?) {
        notify(interaction.cancelCapture()); capturedTarget = nil; onAction?(.endScan, nil)
    }

    override func accessibilityChildren() -> [Any]? {
        guard let scene else { return [] }
        return scene.hits.flatMap { hit -> [NSAccessibilityElement] in
            let targets = hit.mappingTargets.isEmpty
                ? [WMPHitTarget(stableID: hit.stableID, nodeID: hit.nodeID, kind: hit.kind,
                    frame: hit.frame, action: hit.action, sticky: hit.sticky, enabled: hit.enabled)]
                : hit.mappingTargets
            return targets.compactMap { target in
                guard let action = target.action else { return nil }
                let element = NSAccessibilityElement()
                element.setAccessibilityIdentifier("wmp.\(target.nodeID ?? String(target.stableID))")
                element.setAccessibilityLabel(Self.label(for: action))
                element.setAccessibilityRole(Self.isSlider(action) ? .slider : .button)
                element.setAccessibilityEnabled(target.enabled && interaction.visualState(for: target.stableID) != .disabled)
                element.setAccessibilityParent(self)
                element.setAccessibilityFrame(screenRect(for: target.frame))
                return element
            }
        }
    }

    private func updateHover(_ event: NSEvent) {
        guard let scene else { return }
        notify(interaction.move(over: interactiveTarget(at: skinPoint(from: event, sceneSize: scene.canvasSize))))
    }

    private func interactiveTarget(at point: WMPPoint) -> WMPHitTarget? {
        guard let target = hitTester?.hitTest(point),
              interaction.visualState(for: target.stableID) != .disabled else { return nil }
        return target
    }

    private func performSlider(_ target: WMPHitTarget, event: NSEvent) {
        guard let scene, let action = target.action else { return }
        let point = skinPoint(from: event, sceneSize: scene.canvasSize)
        let fraction = target.frame.width > 0 ? max(0, min(1, (point.x - target.frame.x) / target.frame.width)) : 0
        onAction?(action, .number(action == .balance ? Double(fraction * 2 - 1) : Double(fraction)))
    }

    private func notify(_ changed: Set<Int>) {
        guard !changed.isEmpty else { return }
        onInteractionChanged?(interaction, changed)
    }

    private func beginWindowDrag(_ event: NSEvent) {
        guard let window else { return }
        isDraggingWindow = true; dragStart = event.locationInWindow
        WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
    }

    private func dragWindow(_ event: NSEvent) {
        guard let window else { return }
        let current = event.locationInWindow
        var origin = window.frame.origin
        origin.x += current.x - dragStart.x; origin.y += current.y - dragStart.y
        window.setFrameOrigin(WindowManager.shared.windowWillMove(window, to: origin))
    }

    private func finishWindowDrag() {
        isDraggingWindow = false
        if let window { WindowManager.shared.windowDidFinishDragging(window) }
    }

    private func screenRect(for frame: WMPRect) -> NSRect {
        guard let scene, let window else { return .zero }
        let local = NSRect(x: frame.x * bounds.width / scene.canvasSize.width,
                           y: frame.y * bounds.height / scene.canvasSize.height,
                           width: frame.width * bounds.width / scene.canvasSize.width,
                           height: frame.height * bounds.height / scene.canvasSize.height)
        return window.convertToScreen(convert(local, to: nil))
    }

    private static func isSlider(_ action: WMPTransportAction) -> Bool { action == .seek || action == .volume || action == .balance }
    private static func isDown(_ action: WMPTransportAction, _ snapshot: WMPHostSnapshot) -> Bool {
        switch action {
        case .toggleMute: return snapshot.muted
        case .toggleShuffle: return snapshot.shuffle
        case .toggleRepeat: return snapshot.repeatMode
        default: return false
        }
    }
    private static func label(for action: WMPTransportAction) -> String {
        switch action {
        case .play: return "Play"; case .pause: return "Pause"; case .stop: return "Stop"
        case .previous: return "Previous"; case .next: return "Next"
        case .beginScan(.reverse): return "Rewind"; case .beginScan(.forward): return "Fast Forward"
        case .endScan: return "Stop Scanning"; case .seek: return "Seek"; case .volume: return "Volume"
        case .balance: return "Balance"; case .toggleMute: return "Mute"
        case .toggleShuffle: return "Shuffle"; case .toggleRepeat: return "Repeat"
        }
    }
}
