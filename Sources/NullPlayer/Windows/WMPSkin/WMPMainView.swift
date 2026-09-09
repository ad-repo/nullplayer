import AppKit

/// Which window edges a borderless-window resize drag is moving.
struct WMPWindowEdges: OptionSet {
    let rawValue: Int
    static let left = WMPWindowEdges(rawValue: 1 << 0)
    static let right = WMPWindowEdges(rawValue: 1 << 1)
    /// Named for the *window*: `.top` is the screen-upward edge, which in this flipped view is the
    /// one nearest `bounds.minY`.
    static let top = WMPWindowEdges(rawValue: 1 << 2)
    static let bottom = WMPWindowEdges(rawValue: 1 << 3)
}

/// `NSViewToolTipOwner` is not decoration. Without the conformance declared, AppKit finds no
/// `view(_:stringForToolTip:point:userData:)` on the owner and falls back to its `description`: the
/// tooltip over every pixel of every skin read `<NullPlayer.WMPMainView: 0x…>`, reported on
/// 2026-09-08. The method below was written and correct all along — nothing was calling it.
final class WMPMainView: NSView, NSViewToolTipOwner {
    var onInteractionChanged: ((WMPInteractionState, Set<Int>) -> Void)?
    var onAction: ((WMPTransportAction, WMPHostValue?) -> Void)?
    /// `(event, authored id, stable graph id)`. The stable id is what scopes the dispatch: a
/// `.wmz` is free to leave a control unnamed, and an authored id is therefore optional.
    var onScriptEvent: ((String, String?, Int?) -> Void)?
    var onElementValueChanged: ((Int, String?, Double) -> Void)?
    /// An `<EDITBOX>`'s text, which is a string rather than a number and so cannot go through
    /// `onElementValueChanged`. Nine of the corpus's ten edit boxes are a playlist search field
    /// whose script reads this back as `plSearchEdit.value`.
    var onElementTextChanged: ((Int, String?, String) -> Void)?
    var onSpectrumDemandChanged: ((Bool) -> Void)?
    private var image: NSImage?
    private var scene: WMPScene?
    private var hitTester: WMPHitTester?
    private var interaction = WMPInteractionState()
    private var capturedTarget: WMPHitTarget?
    /// The node the pointer is over, kept alongside `WMPInteractionState.hoveredNode` because the
    /// *exit* edge has to name the node the pointer just left — and by then the interaction state
    /// has already moved on. The authored id travels with it for the same reason.
    private var hoveredTarget: WMPHitTarget?
    private var tracking: NSTrackingArea?
    private var isDraggingWindow = false
    private var dragStart = NSPoint.zero
    /// Which window edges a drag is moving, the frame it started from, and where the pointer was.
    ///
    /// A `.wmz` window is `.borderless`, and a borderless window has no frame view — so AppKit
    /// draws and hit-tests no resize edge for it, `.resizable` in the style mask notwithstanding.
    /// Before this there was simply no way to resize a skin in WMP mode: `windowWillResize` clamped
    /// a drag that could never begin, and every expression-driven layout in the corpus was stuck at
    /// the size its markup opened with.
    private var resizeEdges: WMPWindowEdges = []
    private var resizeStartFrame = NSRect.zero
    private var resizeStartMouse = NSPoint.zero
    private var widgetViews: [Int: NSView] = [:]
    private var widgetValues: [Int: Double] = [:]
    private var currentSnapshot = WMPHostSnapshot()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }


    func present(_ cgImage: CGImage, scene: WMPScene, dirtyBounds: WMPRect? = nil) {
        let previous = self.scene
        image = NSImage(cgImage: cgImage, size: bounds.size)
        self.scene = scene
        hitTester = WMPHitTester(hits: scene.hits)
        synchronizeWidgetViews(scene.widgets)
        // The AppKit overlays — playlist, equalizer, popup, effects, video — are positioned in
        // `layout()`, which AppKit will not run on its own just because a new scene arrived. Without
        // this an equalizer that the skin slid away stays on screen at its old frame.
        needsLayout = true
        removeAllToolTips(); _ = addToolTip(bounds, owner: self, userData: nil)
        window?.invalidateCursorRects(for: self)
        if let dirtyBounds {
            // The union with everything the *previous* scene drew at a different frame. A dirty
            // rect derived from the new scene alone covers where a pane has arrived and never where
            // it left, so closing a drawer repainted the destination and abandoned the drawer's own
            // pixels on screen — reported during live QA as a leftover equaliser and a second copy
            // of the transport bar.
            var dirty = dirtyBounds
            let before = previous?.geometries ?? [:]
            for stableID in Set(before.keys).union(scene.geometries.keys) {
                let old = before[stableID]?.absoluteFrame
                let new = scene.geometries[stableID]?.absoluteFrame
                guard old != new else { continue }
                if let old { dirty = dirty.union(old) }
                if let new { dirty = dirty.union(new) }
            }
            let xScale = bounds.width / scene.canvasSize.width
            let yScale = bounds.height / scene.canvasSize.height
            setNeedsDisplay(NSRect(x: dirty.x * xScale, y: dirty.y * yScale,
                                   width: dirty.width * xScale, height: dirty.height * yScale))
        } else {
            needsDisplay = true
            // A `.wmz` window is shaped by its own artwork: Corona's player block occupies the
            // right 346 of a 596-wide view and the rest is transparent, because that is where its
            // playlist pane slides in. AppKit caches a borderless window's shadow from the content
            // it first drew — which here is the *opaque* unskinned player the controller shows
            // first — so without this the skin sits inside a full-rectangle drop shadow that reads
            // as a dark box around it. Only on a full present: a dirty-rect repaint (hover, a
            // moving slider) cannot change the silhouette, and invalidating per frame is expensive.
            window?.invalidateShadow()
        }
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
            (view as? WMPEffectsSurfaceView)?.update(snapshot)
        }
    }

    /// The items a `POPUP` or `LISTBOX` holds, from the last script transaction.
    func updateListItems(_ items: [Int: [String]]) {
        for (stableID, view) in widgetViews {
            (view as? WMPPopupSurfaceView)?.update(items: items[stableID] ?? [])
            (view as? WMPListBoxSurfaceView)?.update(items: items[stableID] ?? [])
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
        image = nil; scene = nil; hitTester = nil; capturedTarget = nil; hoveredTarget = nil
        isDraggingWindow = false
        onInteractionChanged = nil; onAction = nil; onScriptEvent = nil
        onElementValueChanged = nil; onElementTextChanged = nil; onSpectrumDemandChanged = nil
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

    /// The tip for whatever is under the pointer: the control the hit tester lands on first, then
    /// the widget beneath it. Only widgets answered before 2026-09-08, so nearly every tip in the
    /// corpus was unreachable — a skin's controls are `<BUTTON>`s, and `upToolTip` is authored 4,789
    /// times across 176 of the 179 archives.
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag,
              point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let scene else { return "" }
        let skinPoint = WMPPoint(x: bounds.width > 0 ? point.x * scene.canvasSize.width / bounds.width : 0,
                                 y: bounds.height > 0 ? point.y * scene.canvasSize.height / bounds.height : 0)
        // The hit tester, not a frame scan: a mapping image gives four controls one frame and only
        // the pixel under the pointer says which of them the tip belongs to.
        if let target = hitTester?.hitTest(skinPoint) {
            if let tip = target.toolTip, !tip.isEmpty { return tip }
            if let tip = scene.hits.first(where: { $0.stableID == target.stableID })?.toolTip,
               !tip.isEmpty { return tip }
        }
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

    /// **A right-click on the skin's visualization rect opens the visualization's own menu.**
    ///
    /// The surface is click-through by design — 51 corpus skins wire an `onClick` on the
    /// `<EFFECTS>` node and that handler is the scene's, not the overlay's — so the event arrives
    /// here and the widget frames are what decide. Anywhere else on a `.wmz` there is no host menu
    /// to show: the skin draws its own controls and its own menus.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        WMPMainWindowController.traceInput("menu at=\(point) frames=[\(widgetViews.values.compactMap { ($0 as? WMPEffectsSurfaceView)?.frame }.map(String.init(describing:)).joined(separator: ", "))]")
        for view in widgetViews.values {
            guard let effects = view as? WMPEffectsSurfaceView, effects.frame.contains(point) else { continue }
            return effects.buildMenu()
        }
        return super.menu(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateResizeCursor(convert(event.locationInWindow, from: nil))
        updateHover(event)
    }
    override func mouseEntered(with event: NSEvent) { updateHover(event) }
    override func mouseExited(with event: NSEvent) { setHover(nil) }

    override func mouseDown(with event: NSEvent) {
        guard let scene else { return }
        let target = interactiveTarget(at: skinPoint(from: event, sceneSize: scene.canvasSize))
        // The edge band is consulted only where hit testing found no control, so a button sitting
        // against the window edge keeps every pixel it had.
        if target == nil {
            let edges = edges(at: convert(event.locationInWindow, from: nil))
            if !edges.isEmpty { beginWindowResize(edges); return }
        }
        guard let target else { beginWindowDrag(event); return }
        capturedTarget = target
        notify(interaction.press(target))
        onScriptEvent?("mousedown", target.nodeID, target.stableID)
        window?.makeFirstResponder(self)
        if case .beginScan = target.action { onAction?(target.action!, nil) }
        if isSlider(target) { performSlider(target, event: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        if !resizeEdges.isEmpty { dragWindowResize(); return }
        if isDraggingWindow { dragWindow(event); return }
        guard let capturedTarget else { return }
        if isSlider(capturedTarget) { performSlider(capturedTarget, event: event) }
        updateHover(event)
    }

    override func mouseUp(with event: NSEvent) {
        if !resizeEdges.isEmpty { resizeEdges = []; return }
        if isDraggingWindow { finishWindowDrag(); return }
        guard let scene else { return }
        let target = interactiveTarget(at: skinPoint(from: event, sceneSize: scene.canvasSize))
        let result = interaction.release(over: target)
        notify(result.changed)
        onScriptEvent?("mouseup", capturedTarget?.nodeID, capturedTarget?.stableID)
        defer { capturedTarget = nil }
        guard let capturedTarget else { return }
        // **`onDragEnd` is the seek commit** (W55). It is authored only on `SLIDER` (125 uses) and
        // `CUSTOMSLIDER` (16), and 111 of those 141 sources are
        // `player.controls.currentPosition = value` — the skin scrubs the thumb during the drag and
        // commits the seek once, on release. Raised for a captured slider whether or not the
        // pointer moved, because a press and release on a slider track is a completed drag in WMP:
        // `performSlider` already ran on `mouseDown` and moved the value there.
        if isSlider(capturedTarget) {
            onScriptEvent?("dragend", capturedTarget.nodeID, capturedTarget.stableID)
        }
        if case .beginScan = capturedTarget.action { onAction?(.endScan, nil); return }
        guard result.activated == capturedTarget.stableID else { return }
        onScriptEvent?("click", capturedTarget.nodeID, capturedTarget.stableID)
        guard let action = capturedTarget.action,
              action != .seek, action != .volume, action != .balance else { return }
        onAction?(action, nil)
    }

    override func cancelOperation(_ sender: Any?) {
        cancelInputCapture()
    }

    override func keyDown(with event: NSEvent) {
        guard let scene else { return super.keyDown(with: event) }
        // `tabStop="false"` is authored 544 times against `"true"`'s 170: a skin marks most of its
        // controls out of the keyboard ring and leaves a handful in, and a ring built from every
        // enabled control tabs through all of them instead.
        let targets = scene.hits.filter(\.tabStop).flatMap { hit in hit.mappingTargets.isEmpty
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
            if visualizationHandled(event) { return }
            return super.keyDown(with: event)
        }
        if event.keyCode == 49 || event.keyCode == 36 {
            if let action = target.action { onAction?(action, nil) }
            else { onScriptEvent?("click", target.nodeID, target.stableID) }
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
        if visualizationHandled(event) { return }
        super.keyDown(with: event)
    }

    /// The skin has refused the key: offer it to a hosted `<EFFECTS>` surface, which answers the
    /// same visualization keys as NullPlayer's own window. A skin's focused control always goes
    /// first — a slider's arrows are the slider's.
    private func visualizationHandled(_ event: NSEvent) -> Bool {
        widgetViews.values.compactMap { $0 as? WMPEffectsSurfaceView }
            .contains { $0.handleKeyDown(event) }
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

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let scene, scene.canvasSize.width > 0, scene.canvasSize.height > 0 else { return }
        let xScale = bounds.width / scene.canvasSize.width
        let yScale = bounds.height / scene.canvasSize.height
        // Back to front, so a control on top wins the overlap — the same order hit testing walks,
        // read the other way. AppKit resolves the last rect added for a point.
        for hit in scene.hits {
            guard hit.enabled, let cursor = hit.cursor else { continue }
            let visible = hit.clipRect.flatMap { hit.frame.intersection($0) } ?? hit.frame
            guard !visible.isEmpty else { continue }
            addCursorRect(NSRect(x: visible.x * xScale, y: visible.y * yScale,
                                 width: visible.width * xScale, height: visible.height * yScale),
                          cursor: Self.cursor(for: cursor))
        }
    }

    private static func cursor(for cursor: WMPCursor) -> NSCursor {
        switch cursor {
        case .system: return .arrow
        case .hand: return .pointingHand
        case .sizeAll: return .openHand
        case .sizeWE: return .resizeLeftRight
        case .sizeNS: return .resizeUpDown
        // macOS ships no public diagonal resize cursor, so the nearest honest answer is the axis
        // the drag mostly runs along rather than an invented bitmap.
        case .sizeNWSE, .sizeNESW: return .crosshair
        }
    }

    private func updateHover(_ event: NSEvent) {
        guard let scene else { return }
        setHover(interactiveTarget(at: skinPoint(from: event, sceneSize: scene.canvasSize)))
    }

    /// Move the hover to `target`, repaint the artwork, and raise the two authored edges.
    ///
    /// `onmouseover`/`onmouseout` are edges, not states: a skin fades a readout in on entry and
    /// back out on exit (`alx_dl.wms` does exactly that with `volumeText` and `seekText`), so a
    /// pointer crossing from one control straight to another must raise the exit on the node it
    /// left *before* the entry on the node it reached. Nothing is raised while the pointer stays
    /// inside the same node — every mouse-moved event would otherwise be a script transaction.
    private func setHover(_ target: WMPHitTarget?) {
        guard hoveredTarget?.stableID != target?.stableID else { return }
        let previous = hoveredTarget
        hoveredTarget = target
        notify(interaction.move(over: target))
        WMPMainWindowController.traceInput("hover \(previous?.nodeID ?? "-")#\(previous.map { String($0.stableID) } ?? "-")"
            + " -> \(target?.nodeID ?? "-")#\(target.map { String($0.stableID) } ?? "-")")
        if let previous { onScriptEvent?("mouseout", previous.nodeID, previous.stableID) }
        if let target { onScriptEvent?("mouseover", target.nodeID, target.stableID) }
    }

    private func interactiveTarget(at point: WMPPoint) -> WMPHitTarget? {
        guard let target = hitTester?.hitTest(point),
              interaction.visualState(for: target.stableID) != .disabled else { return nil }
        return target
    }

    private func performSlider(_ target: WMPHitTarget, event: NSEvent) {
        guard let scene else { return }
        let point = skinPoint(from: event, sceneSize: scene.canvasSize)
        let widget = scene.widgets.first { $0.stableID == target.stableID }
        let minimum = widget?.minimumValue ?? 0, maximum = widget?.maximumValue ?? 100
        // **The drag runs along the axis the skin authored.** `direction="vertical"` outnumbers
        // horizontal 1,312 to 664 in the corpus — every equaliser band is one — and measuring those
        // along `frame.width` gave a 9 px-wide bar's full range in nine pixels of sideways travel.
        // The same `WMPSliderMetrics` the scene placed the thumb with reads the pointer back, so
        // the thumb lands under the cursor instead of beside it.
        let metrics = WMPSliderMetrics(direction: widget?.direction ?? .horizontal,
            minimum: minimum, maximum: maximum, value: widget?.value ?? minimum,
            borderSize: widget?.borderSize ?? 0)
        // A `CUSTOMSLIDER` reads its value out of its own `positionImage` — the pixel under the
        // pointer *is* the fraction — which is the whole point of the element: its track need not
        // be a straight line. Everything else uses the linear metrics that placed its thumb.
        let map = scene.hits.first { $0.stableID == target.stableID }?.positionMap
        let mapped = map?.fraction(at: point, in: target.frame)
        let value = mapped.map { minimum + $0 * (maximum - minimum) }
            ?? metrics.value(at: point, in: target.frame, thumbSize: widget?.thumbSize ?? .zero)
        let span = maximum - minimum
        let fraction = span == 0 ? 0 : (value - minimum) / span
        // A skin that binds its slider's `value` to a host property has said where that control
        // writes; honour the binding it declared rather than requiring a semantic tag. 163 corpus
        // skins drive volume, seek and the ten equaliser bands entirely this way.
        if let action = target.action ?? widget?.valueBindingPath.flatMap(WMPTransportAction.boundAction) {
            switch action {
            case .balance: onAction?(action, .number(fraction * 2 - 1))
            case .seek, .volume: onAction?(action, .number(fraction))
            default: onAction?(action, .number(value))
            }
        }
        if target.kind.lowercased().contains("slider") {
            widgetValues[target.stableID] = value
            onElementValueChanged?(target.stableID, target.nodeID, value)
        }
        onScriptEvent?("change", target.nodeID, target.stableID)
    }

    private func synchronizeWidgetViews(_ widgets: [WMPWidget]) {
        // **The skin draws its own controls; an overlay is for what the scene genuinely cannot
        // paint.** `.video` left this list because `WMPVideoPlaceholderView` filled its frame with
        // opaque black over the artwork of every skin that authors a `<VIDEO>` — 167 of 178 — and
        // an audio player has no video to put there instead (W9) — which stopped being true when
        // `Windows/VideoPlayer` landed, so W102 is conditional hosting rather than a placeholder.
        // `.equalizer` left it because `EQUALIZERSETTINGS` is no longer a widget at all: the skin's
        // own bound sliders are the equaliser.
        //
        // **`.effects` reaches the whole corpus now that `<EFFECTS>` is a kind (W101).** It used
        // to reach five archives: `WMPElementKind` mapped `wmpeffects` and not `effects`, so the
        // 166 of 177 that spell the tag the other way fell to `.unknown` and were never widgets.
        let native = widgets.filter { [WMPWidgetKind.playlist, .dropdownPlaylist, .popup,
                                       .editBox, .listBox, .effects].contains($0.kind) }
        let wanted = Set(native.map(\.stableID))
        let widgetIDs = Set(widgets.map(\.stableID))
        widgetValues = widgetValues.filter { widgetIDs.contains($0.key) }
        for (id, view) in widgetViews where !wanted.contains(id) { view.removeFromSuperview(); widgetViews[id] = nil }
        for widget in native where widgetViews[widget.stableID] == nil {
            let view: NSView
            switch widget.kind {
            case .playlist: view = WMPPlaylistSurfaceView()
            case .dropdownPlaylist: view = WMPDropdownPlaylistSurfaceView(frame: .zero, pullsDown: false)
            case .popup: view = WMPPopupSurfaceView(frame: .zero)
            case .editBox: view = WMPEditBoxSurfaceView()
            // A `<LISTBOX>` is a playlist chooser the skin fills from script. The control is real;
            // what it can hold is whatever `listItems` carries, which is empty until the object
            // model can answer `player.mediaCollection` — recorded as W66 rather than faked with
            // rows this player invented.
            case .listBox: view = WMPListBoxSurfaceView()
            case .effects: view = WMPEffectsSurfaceView(frame: .zero)
            default: continue
            }
            view.toolTip = widget.toolTip
            view.setAccessibilityIdentifier("wmp.\(widget.nodeID ?? String(widget.stableID))")
            view.setAccessibilityLabel(widget.label)
            if let actionable = view as? WMPPlaylistSurfaceView { actionable.onAction = onAction }
            if let actionable = view as? WMPDropdownPlaylistSurfaceView { actionable.onAction = onAction }
            if let popup = view as? WMPPopupSurfaceView {
                let stableID = widget.stableID, nodeID = widget.nodeID
                popup.onSelect = { [weak self] index, title in
                    // The skin's handler reads `selectedItem`, so the element has to hold it before
                    // the event is raised — and the preset is applied through the host either way,
                    // because `selectedItem_onchange` is not yet a dispatched event (W51).
                    self?.onElementValueChanged?(stableID, nodeID, Double(index))
                    self?.onAction?(.setEQPreset(index), .string(title))
                    self?.onScriptEvent?("change", nodeID, stableID)
                }
            }
            if let edit = view as? WMPEditBoxSurfaceView {
                let stableID = widget.stableID, nodeID = widget.nodeID
                edit.onEdit = { [weak self] text in
                    self?.onElementTextChanged?(stableID, nodeID, text)
                    self?.onScriptEvent?("keyup", nodeID, stableID)
                }
            }
            if let list = view as? WMPListBoxSurfaceView {
                let stableID = widget.stableID, nodeID = widget.nodeID
                list.onSelect = { [weak self] index in
                    self?.onElementValueChanged?(stableID, nodeID, Double(index))
                    self?.onScriptEvent?("change", nodeID, stableID)
                }
            }
            widgetViews[widget.stableID] = view; addSubview(view)
        }
        // **What the scene handed the window, as opposed to what it drew.** The AppKit overlays are
        // not in a render dump at all, so a skin can dump a perfect frame and be missing its
        // playlist or its visualization on screen; this is the live counterpart of the harness's
        // `WIDGET` line. See `reference/harness.md` § *The one probe that is not in the test binary*.
        WMPMainWindowController.traceInput("widgets hosted=\(native.count) [\(native.map { "\($0.kind) id=\($0.nodeID ?? "-") frame=\($0.frame)" }.joined(separator: ", "))]")
        onSpectrumDemandChanged?(native.contains { $0.kind == .effects })
        layoutSubtreeIfNeeded()
        refreshHostState(currentSnapshot)
    }

    private func notify(_ changed: Set<Int>) {
        guard !changed.isEmpty else { return }
        onInteractionChanged?(interaction, changed)
    }

    // MARK: Resizing a borderless skin window

    /// The band, in view points, that counts as an edge. Wide enough to hit on a shaped window and
    /// narrow enough that it is only ever reached where no control is.
    private static let resizeBandWidth: CGFloat = 6

    private func edges(at point: NSPoint) -> WMPWindowEdges {
        guard scene?.isResizable == true, bounds.width > 0, bounds.height > 0 else { return [] }
        let band = Self.resizeBandWidth
        var edges: WMPWindowEdges = []
        if point.x <= band { edges.insert(.left) }
        if point.x >= bounds.maxX - band { edges.insert(.right) }
        // The view is flipped, so its y grows downward while the window's grows upward.
        if point.y <= band { edges.insert(.top) }
        if point.y >= bounds.maxY - band { edges.insert(.bottom) }
        return edges
    }

    private func beginWindowResize(_ edges: WMPWindowEdges) {
        guard let window else { return }
        resizeEdges = edges
        resizeStartFrame = window.frame
        resizeStartMouse = NSEvent.mouseLocation
    }

    /// Tracked in screen coordinates on purpose: dragging a left or top edge moves the window's
    /// origin, which moves `locationInWindow` under a stationary pointer and makes the drag run
    /// away from the cursor.
    private func dragWindowResize() {
        guard let window, let limits = scene?.resizeLimits else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - resizeStartMouse.x, dy = mouse.y - resizeStartMouse.y
        var width = resizeStartFrame.width, height = resizeStartFrame.height
        if resizeEdges.contains(.right) { width += dx }
        if resizeEdges.contains(.left) { width -= dx }
        if resizeEdges.contains(.top) { height += dy }
        if resizeEdges.contains(.bottom) { height -= dy }
        let clamped = limits.clamp(WMPSize(width: width, height: height))
        // The anchored edge is the one not being dragged, so it must not move when the clamp bites.
        var frame = resizeStartFrame
        frame.size = NSSize(width: clamped.width, height: clamped.height)
        if resizeEdges.contains(.left) { frame.origin.x = resizeStartFrame.maxX - clamped.width }
        if resizeEdges.contains(.bottom) { frame.origin.y = resizeStartFrame.maxY - clamped.height }
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true)
    }

    private func updateResizeCursor(_ point: NSPoint) {
        let edges = edges(at: point)
        if edges.isEmpty {
            if scene != nil { NSCursor.arrow.set() }
            return
        }
        // AppKit publishes no diagonal resize cursor, so a corner takes the axis it is widest in.
        let horizontal = edges.contains(.left) || edges.contains(.right)
        (horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
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
        case .setEQPreset: return "Equalizer preset"
        case .setPreamp: return "Equalizer preamp"
        case .setEffectType, .nextEffect, .previousEffect: return "Visualization"
        case .setEffectPreset, .nextEffectPreset: return "Visualization preset"
        }
    }
}
