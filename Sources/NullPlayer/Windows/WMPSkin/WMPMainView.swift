import AppKit

final class WMPMainView: NSView {
    var onInteractionChanged: ((WMPInteractionState, Set<Int>) -> Void)?
    var onAction: ((WMPTransportAction, WMPHostValue?) -> Void)?
    var onScriptEvent: ((String, String?) -> Void)?
    var onElementValueChanged: ((Int, String?, Double) -> Void)?
    var onSpectrumDemandChanged: ((Bool) -> Void)?
    private var image: NSImage?
    private var scene: WMPScene?
    private var hitTester: WMPHitTester?
    private var interaction = WMPInteractionState()
    private var capturedTarget: WMPHitTarget?
    private var tracking: NSTrackingArea?
    private var isDraggingWindow = false
    private var dragStart = NSPoint.zero
    private var widgetViews: [Int: NSView] = [:]
    private var widgetValues: [Int: Double] = [:]
    private var currentSnapshot = WMPHostSnapshot()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func present(_ cgImage: CGImage, scene: WMPScene, dirtyBounds: WMPRect? = nil) {
        image = NSImage(cgImage: cgImage, size: bounds.size)
        self.scene = scene
        hitTester = WMPHitTester(hits: scene.hits)
        synchronizeWidgetViews(scene.widgets)
        removeAllToolTips(); _ = addToolTip(bounds, owner: self, userData: nil)
        if let dirtyBounds {
            let xScale = bounds.width / scene.canvasSize.width
            let yScale = bounds.height / scene.canvasSize.height
            setNeedsDisplay(NSRect(x: dirtyBounds.x * xScale, y: dirtyBounds.y * yScale,
                                   width: dirtyBounds.width * xScale, height: dirtyBounds.height * yScale))
        } else { needsDisplay = true }
        setAccessibilityChildren(nil)
    }

    func refreshHostState(_ snapshot: WMPHostSnapshot) {
        currentSnapshot = snapshot
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
        for view in widgetViews.values {
            (view as? WMPPlaylistSurfaceView)?.update(snapshot)
            (view as? WMPDropdownPlaylistSurfaceView)?.update(snapshot)
            (view as? WMPEqualizerSurfaceView)?.update(snapshot)
        }
    }

    func updateSpectrum(_ levels: [Float]) {
        widgetViews.values.compactMap { $0 as? WMPEffectsSurfaceView }.forEach { $0.updateSpectrum(levels) }
    }

    func cancelInputCapture() {
        notify(interaction.cancelCapture()); capturedTarget = nil; onAction?(.endScan, nil)
    }

    func prepareForUITeardown() {
        cancelInputCapture()
        onSpectrumDemandChanged?(false)
        widgetViews.values.forEach { $0.removeFromSuperview() }; widgetViews.removeAll(); widgetValues.removeAll()
        image = nil; scene = nil; hitTester = nil; capturedTarget = nil; isDraggingWindow = false
        onInteractionChanged = nil; onAction = nil; onScriptEvent = nil
        onElementValueChanged = nil; onSpectrumDemandChanged = nil
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

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag,
              point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let scene else { return "" }
        let skinPoint = WMPPoint(x: bounds.width > 0 ? point.x * scene.canvasSize.width / bounds.width : 0,
                                 y: bounds.height > 0 ? point.y * scene.canvasSize.height / bounds.height : 0)
        return scene.widgets.reversed().first { $0.frame.contains(skinPoint) }?.toolTip ?? ""
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); dirtyRect.fill()
        image?.draw(in: bounds, from: .zero, operation: .copy, fraction: 1,
                    respectFlipped: true, hints: [.interpolation: NSImageInterpolation.low])
    }

    override func layout() {
        super.layout()
        guard let scene else { return }
        let xScale = bounds.width / max(1, scene.canvasSize.width)
        let yScale = bounds.height / max(1, scene.canvasSize.height)
        for widget in scene.widgets {
            widgetViews[widget.stableID]?.frame = NSRect(x: widget.frame.x * xScale,
                y: widget.frame.y * yScale, width: widget.frame.width * xScale,
                height: widget.frame.height * yScale)
        }
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
        onScriptEvent?("mousedown", target.nodeID)
        window?.makeFirstResponder(self)
        if case .beginScan = target.action { onAction?(target.action!, nil) }
        if isSlider(target) { performSlider(target, event: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        if isDraggingWindow { dragWindow(event); return }
        guard let capturedTarget else { return }
        if isSlider(capturedTarget) { performSlider(capturedTarget, event: event) }
        updateHover(event)
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingWindow { finishWindowDrag(); return }
        guard let scene else { return }
        let target = interactiveTarget(at: skinPoint(from: event, sceneSize: scene.canvasSize))
        let result = interaction.release(over: target)
        notify(result.changed)
        onScriptEvent?("mouseup", capturedTarget?.nodeID)
        defer { capturedTarget = nil }
        guard let capturedTarget else { return }
        if case .beginScan = capturedTarget.action { onAction?(.endScan, nil); return }
        guard result.activated == capturedTarget.stableID else { return }
        onScriptEvent?("click", capturedTarget.nodeID)
        guard let action = capturedTarget.action,
              action != .seek, action != .volume, action != .balance else { return }
        onAction?(action, nil)
    }

    override func cancelOperation(_ sender: Any?) {
        cancelInputCapture()
    }

    override func keyDown(with event: NSEvent) {
        guard let scene else { return super.keyDown(with: event) }
        let targets = scene.hits.flatMap { hit in hit.mappingTargets.isEmpty
            ? [WMPHitTarget(stableID: hit.stableID, nodeID: hit.nodeID, kind: hit.kind,
                frame: hit.frame, action: hit.action, sticky: hit.sticky, enabled: hit.enabled)]
            : hit.mappingTargets }.filter(\.enabled)
        if event.keyCode == 48, !targets.isEmpty {
            let current = targets.firstIndex { $0.stableID == interaction.focusedNode } ?? -1
            let delta = event.modifierFlags.contains(.shift) ? -1 : 1
            let next = (current + delta + targets.count) % targets.count
            notify(interaction.focus(targets[next].stableID)); return
        }
        guard let target = targets.first(where: { $0.stableID == interaction.focusedNode }) else {
            return super.keyDown(with: event)
        }
        if event.keyCode == 49 || event.keyCode == 36 {
            if let action = target.action { onAction?(action, nil) }
            else { onScriptEvent?("click", target.nodeID) }
            return
        }
        if [123, 124, 125, 126].contains(event.keyCode), target.kind.lowercased().contains("slider") {
            let widget = scene.widgets.first { $0.stableID == target.stableID }
            let minimum = widget?.minimumValue ?? 0, maximum = widget?.maximumValue ?? 100
            let old = widgetValues[target.stableID] ?? minimum
            let step = max(1, (maximum - minimum) / 100)
            let value = max(minimum, min(maximum, old + ([124, 126].contains(event.keyCode) ? step : -step)))
            widgetValues[target.stableID] = value
            onElementValueChanged?(target.stableID, target.nodeID, value); return
        }
        super.keyDown(with: event)
    }

    override func accessibilityChildren() -> [Any]? {
        guard let scene else { return [] }
        return scene.hits.flatMap { hit -> [NSAccessibilityElement] in
            let targets = hit.mappingTargets.isEmpty
                ? [WMPHitTarget(stableID: hit.stableID, nodeID: hit.nodeID, kind: hit.kind,
                    frame: hit.frame, action: hit.action, sticky: hit.sticky, enabled: hit.enabled)]
                : hit.mappingTargets
            return targets.compactMap { target in
                let element = NSAccessibilityElement()
                element.setAccessibilityIdentifier("wmp.\(target.nodeID ?? String(target.stableID))")
                let widget = scene.widgets.first { $0.stableID == target.stableID }
                element.setAccessibilityLabel(widget?.label ?? target.action.map(Self.label(for:)) ?? target.kind)
                element.setAccessibilityRole(target.kind.lowercased().contains("slider") ? .slider : .button)
                element.setAccessibilityEnabled(target.enabled && interaction.visualState(for: target.stableID) != .disabled)
                element.setAccessibilityParent(self)
                element.setAccessibilityFrame(screenRect(for: target.frame))
                return element
            }
        } + scene.widgets.filter { $0.kind == .text }.map { widget in
            let element = NSAccessibilityElement()
            element.setAccessibilityIdentifier("wmp.\(widget.nodeID ?? String(widget.stableID))")
            element.setAccessibilityLabel(widget.label); element.setAccessibilityRole(.staticText)
            element.setAccessibilityParent(self); element.setAccessibilityFrame(screenRect(for: widget.frame))
            return element
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
        guard let scene else { return }
        let point = skinPoint(from: event, sceneSize: scene.canvasSize)
        let fraction = target.frame.width > 0 ? max(0, min(1, (point.x - target.frame.x) / target.frame.width)) : 0
        if let action = target.action {
            onAction?(action, .number(action == .balance ? Double(fraction * 2 - 1) : Double(fraction)))
        } else if target.kind.caseInsensitiveCompare("slider") == .orderedSame {
            let widget = scene.widgets.first { $0.stableID == target.stableID }
            let minimum = widget?.minimumValue ?? 0, maximum = widget?.maximumValue ?? 100
            let value = minimum + Double(fraction) * (maximum - minimum)
            widgetValues[target.stableID] = value
            onElementValueChanged?(target.stableID, target.nodeID, value)
        }
        onScriptEvent?("change", target.nodeID)
    }

    private func synchronizeWidgetViews(_ widgets: [WMPWidget]) {
        let native = widgets.filter { [.playlist, .dropdownPlaylist, .equalizer, .popup, .effects, .video].contains($0.kind) }
        let wanted = Set(native.map(\.stableID))
        let widgetIDs = Set(widgets.map(\.stableID))
        widgetValues = widgetValues.filter { widgetIDs.contains($0.key) }
        for (id, view) in widgetViews where !wanted.contains(id) { view.removeFromSuperview(); widgetViews[id] = nil }
        for widget in native where widgetViews[widget.stableID] == nil {
            let view: NSView
            switch widget.kind {
            case .playlist: view = WMPPlaylistSurfaceView()
            case .dropdownPlaylist: view = WMPDropdownPlaylistSurfaceView(frame: .zero, pullsDown: false)
            case .equalizer: view = WMPEqualizerSurfaceView()
            case .popup: view = WMPPopupSurfaceView(frame: .zero)
            case .effects: view = WMPEffectsSurfaceView()
            case .video: view = WMPVideoPlaceholderView()
            default: continue
            }
            view.toolTip = widget.toolTip
            view.setAccessibilityIdentifier("wmp.\(widget.nodeID ?? String(widget.stableID))")
            view.setAccessibilityLabel(widget.label)
            if let actionable = view as? WMPPlaylistSurfaceView { actionable.onAction = onAction }
            if let actionable = view as? WMPDropdownPlaylistSurfaceView { actionable.onAction = onAction }
            if let actionable = view as? WMPEqualizerSurfaceView { actionable.onAction = onAction }
            if let actionable = view as? WMPPopupSurfaceView { actionable.onAction = onAction }
            widgetViews[widget.stableID] = view; addSubview(view)
        }
        onSpectrumDemandChanged?(native.contains { $0.kind == .effects })
        layoutSubtreeIfNeeded()
        refreshHostState(currentSnapshot)
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
    private func isSlider(_ target: WMPHitTarget) -> Bool {
        target.kind.lowercased().contains("slider") || target.action.map(Self.isSlider(_:)) == true
    }
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
        case .playPlaylistItem: return "Play playlist item"
        case .removePlaylistItem: return "Remove playlist item"
        case .movePlaylistItem: return "Move playlist item"
        case .setEQEnabled: return "Enable equalizer"
        case .setEQBand: return "Equalizer band"
        case .setPreamp: return "Equalizer preamp"
        }
    }
}
