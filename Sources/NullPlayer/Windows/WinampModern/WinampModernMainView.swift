import AppKit

final class WinampModernMainView: NSView {
    let renderer: WasabiSceneRenderer
    let scripts: WinampModernScriptRuntime
    let host: WinampModernHost
    private weak var componentHost: WinampModernComponentHost?
    /// Live library surfaces by holder id. Typed, so each one can be told about a palette change, a
    /// UI Size change, and its own teardown (Phase 13.8).
    private var librarySurfaces: [WasabiObjectID: WinampModernLibrarySurface] = [:]

    /// UI Size, as a multiplier on the skin's own pixel grid. The scene is always laid out in skin
    /// pixels — the scale is applied once at the drawing boundary and undone once at the input
    /// boundary, so nothing in the graph, the renderer, or a script ever sees it.
    var skinScale: CGFloat = 1 {
        didSet {
            guard skinScale != oldValue else { return }
            setFrameSize(scaledCanvasSize)
            for surface in librarySurfaces.values { surface.applySkinScale(skinScale) }
            needsLayout = true
            needsDisplay = true
        }
    }

    var scaledCanvasSize: NSSize {
        NSSize(width: (renderer.canvasSize.width * skinScale).rounded(),
               height: (renderer.canvasSize.height * skinScale).rounded())
    }

    private var pressedObject: WasabiObject?
    private var pressedEQHolder: WasabiObject?
    private var draggedDivider: WasabiObject?
    private var hoveredObject: WasabiObject?
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    private var lastPlaybackState: PlaybackState = .stopped
    /// Last volume the scripts were told about, 0…255. −1 until the first update.
    private var lastPostedVolume: Int32 = -1
    private var tracking: NSTrackingArea?
    private var animationTimer: Timer?
    private(set) var isTornDown = false
    var canvasSizeDidChange: ((CGSize) -> Void)?
    /// Returns true if the skin provides a separate native window for the kind and it was toggled.
    var componentWindowToggleRequested: ((WinampModernComponentKind) -> Bool)?
    /// Ask the surface coordinator to toggle a surface — the same route the View menu takes, so a
    /// skin button and a menu item can never resolve differently. Returns false before the
    /// coordinator exists (during `scripts.start()`), where the older direct routing still applies.
    var surfaceToggleRequested: ((WinampModernComponentKind) -> Bool)?

    /// The main window drives the shared script runtime's *global* callbacks (theme, actions, mouse
    /// position, EQ). Auxiliary container windows render and take input against the same runtime but
    /// must not clobber those single-owner callbacks, so they pass `drivesScripts: false`.
    ///
    /// Layout switching and resizing are **not** in that set: they are addressed to a container, and
    /// the window controller routes them to the view that owns it (Phase 13.3).
    private let drivesScripts: Bool

    /// The container this view renders — the address a script's `switchToLayout`/`resize` carries.
    var containerID: WasabiObjectID { renderer.container.stableID }

    init(renderer: WasabiSceneRenderer, scripts: WinampModernScriptRuntime,
         host: WinampModernHost, componentHost: WinampModernComponentHost? = nil,
         drivesScripts: Bool = true) {
        self.renderer = renderer
        self.scripts = scripts
        self.host = host
        self.componentHost = componentHost
        self.drivesScripts = drivesScripts
        super.init(frame: NSRect(origin: .zero, size: renderer.canvasSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityIdentifier("winampModernMainView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("Winamp Modern skin player")
        if drivesScripts { wireScriptCallbacks() }
        // Every `.wal` window repaints on a colour-theme switch, whichever window triggered it, and
        // so does any AppKit content it hosts.
        renderer.themeCoordinator.addObserver(self) { [weak self] in
            self?.themeDidChange()
        }
        if renderer.sceneNodes().contains(where: {
            let type = $0.object.typeName.lowercased()
            if ["animatedlayer", "songticker"].contains(type) { return true }
            // A plain `text` that opts into ticker scrolling also needs the redraw clock.
            let ticker = ($0.object.attributes["ticker"] ?? "0").lowercased()
            return type == "text" && !["0", "off", "false", "no"].contains(ticker)
        }) {
            animationTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
                self?.needsDisplay = true
            }
        }
    }

    /// Switch this view's container to one of its own layouts. Returns false when the container has
    /// no such layout, so a script's `switchToLayout` on a container we do not host is a no-op rather
    /// than a resize of the wrong window.
    @discardableResult
    func activateLayout(id: String) -> Bool {
        guard (try? renderer.activateLayout(id: id)) != nil else { return false }
        setFrameSize(scaledCanvasSize)
        canvasSizeDidChange?(scaledCanvasSize)
        needsDisplay = true
        return true
    }

    /// Resize this view's canvas (clamped by the active layout) and its window with it.
    func applyCanvasResize(_ proposed: CGSize) {
        _ = renderer.resize(to: proposed)
        setFrameSize(scaledCanvasSize)
        canvasSizeDidChange?(scaledCanvasSize)
        needsDisplay = true
    }

    /// The skin switched colour theme. The renderer has already dropped its themed bitmaps.
    ///
    /// Embedded surfaces are told directly; the *fallback* windows have no handle on this view, so
    /// they learn about it from the notification (Phase 16.2). Both have to happen, because a skin
    /// can have one of each open at the same time.
    private func themeDidChange() {
        for surface in librarySurfaces.values { surface.applyPalette(renderer.palette) }
        NotificationCenter.default.post(name: .winampModernThemeDidChange, object: nil)
        needsDisplay = true
    }

    private func wireScriptCallbacks() {
        scripts.graphDidMutate = { [weak self] in
            // A script can add or remove a component holder — cPro builds its Media Library holder
            // when that tab is first opened — so a graph change has to re-run surface reconciliation,
            // not just repaint. Without this the tab opens onto an empty hole.
            self?.needsLayout = true
            self?.needsDisplay = true
        }
        scripts.actionRequested = { [weak self] action, parameter in
            self?.performAction(action: action, parameter: parameter)
        }
        scripts.themeNamesRequested = { [weak renderer] in renderer?.themes.themeNames ?? [] }
        scripts.activeThemeRequested = { [weak renderer] in renderer?.themes.activeTheme ?? "Default" }
        scripts.mousePositionRequested = { [weak self] in
            guard let self, let window else { return .zero }
            let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            return self.skinPoint(self.convert(inWindow, from: nil))
        }
        scripts.equalizerEnabledRequested = { [weak self] in
            self?.componentHost?.equalizerSnapshot().enabled ?? false
        }
        // MAKI's EQ scale is −127…127; the engine's is ±12 dB.
        scripts.equalizerBandRequested = { [weak self] band in
            guard let gains = self?.componentHost?.equalizerSnapshot().bandGainsDB,
                  gains.indices.contains(band) else { return 0 }
            return Int((gains[band] / 12 * 127).rounded())
        }
        scripts.equalizerBandSetterRequested = { [weak self] band, value in
            let clamped = max(-127, min(127, value))
            self?.componentHost?.equalizerSetBandGainDB(band, gainDB: Float(clamped) / 127 * 12)
            self?.needsDisplay = true
        }
        scripts.equalizerPreampRequested = { [weak self] in
            guard let preamp = self?.componentHost?.equalizerSnapshot().preampDB else { return 0 }
            return Int((preamp / 12 * 127).rounded())
        }
        scripts.equalizerPreampSetterRequested = { [weak self] value in
            let clamped = max(-127, min(127, value))
            self?.componentHost?.equalizerSetPreampDB(Float(clamped) / 127 * 12)
            self?.needsDisplay = true
        }
        // A skin's own right-click menus (Love is War Miku's visualization presets, MMD3's display
        // menu) are built by a script and shown through `popAtMouse`. With no presenter installed
        // that call answered 0 — "the user picked nothing" — so those menus never appeared at all.
        scripts.popupPresenter = { [weak self] items in
            self?.presentScriptPopup(items) ?? 0
        }
        scripts.themeSwitchRequested = { [weak self] name in
            guard let self else { return false }
            let changed = self.renderer.activateTheme(name)
            if changed { self.needsDisplay = true }
            return changed
        }
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Only claim the keyboard once the user has actually clicked a playlist row. A `.wal` window is
    /// borderless chrome the user drags by; taking first responder unconditionally would swallow
    /// Delete (and the app's other key equivalents) for the whole window.
    override var acceptsFirstResponder: Bool { playlistHasFocus }
    private var playlistHasFocus = false

    override func resignFirstResponder() -> Bool {
        playlistHasFocus = false
        return true
    }

    /// Delete / Forward Delete remove the selected playlist row — but only while the playlist surface
    /// in this window owns focus, so the key never reaches the queue from the player chrome.
    override func keyDown(with event: NSEvent) {
        let deleteKeys: Set<UInt16> = [51, 117]   // Delete, Forward Delete
        guard playlistHasFocus, deleteKeys.contains(event.keyCode),
              let host = componentHost else {
            super.keyDown(with: event)
            return
        }
        let snapshot = host.playlistSnapshot()
        guard snapshot.selectedIndex >= 0, snapshot.selectedIndex < snapshot.rows.count else { return }
        host.playlistRemove(row: snapshot.selectedIndex)
        clampPlaylistScroll()
        needsDisplay = true
    }

    /// Keep the scroll offset inside the list after a removal or a queue replacement, so a deleted
    /// tail does not leave the view scrolled past the end.
    func clampPlaylistScroll() {
        guard let host = componentHost,
              let holder = renderer.componentHolders().first(where: { $0.kind == .playlist }) else { return }
        renderer.scrollPlaylist(byRows: 0, rowCount: host.playlistSnapshot().rows.count,
                                in: holder.frame)
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Live host subviews (e.g. the embedded library) handle their own region.
        for sub in subviews.reversed() {
            if let hit = sub.hitTest(point) { return hit }
        }
        guard bounds.contains(point) else { return nil }
        let skin = skinPoint(point)
        if renderer.componentHolder(at: skin) != nil { return self }
        return renderer.containsVisiblePixel(at: skin) ? self : nil
    }

    override func layout() {
        super.layout()
        // Creating and adding subviews from inside `draw` is a re-entrant view-hierarchy mutation
        // during a draw cycle; reconciliation belongs here, and drawing only draws.
        reconcileHostedSurfaces()
        layoutHostedSubviews()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !isTornDown, let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        context.saveGState()
        if skinScale != 1 { context.scaleBy(x: skinScale, y: skinScale) }
        renderer.draw(in: context, pressed: pressedObject?.stableID,
                      hovered: hoveredObject?.stableID)
        context.restoreGState()
    }

    /// Create a live surface for each library holder the scene now has, and tear down the ones whose
    /// holder has gone (a layout switch, a script hiding the tab). A surface is told to stand down
    /// *before* its view leaves the hierarchy, so its in-flight server tasks and timers do not
    /// outlive it.
    private func reconcileHostedSurfaces() {
        guard !isTornDown else { return }
        var live: Set<WasabiObjectID> = []
        for holder in renderer.componentHolders() where holder.kind == .library {
            live.insert(holder.object.stableID)
            guard librarySurfaces[holder.object.stableID] == nil,
                  let surface = componentHost?.makeLibrarySurface() else { continue }
            librarySurfaces[holder.object.stableID] = surface
            surface.applySkinScale(skinScale)
            surface.applyPalette(renderer.palette)
            addSubview(surface.view)
        }
        for (id, surface) in librarySurfaces where !live.contains(id) {
            surface.prepareForUITeardown()
            librarySurfaces[id] = nil
        }
    }

    /// Position live host surfaces at their skin-provided holder frames, converting from top-left
    /// skin coordinates to the view's bottom-left ones. Positioning only — nothing is created here.
    private func layoutHostedSubviews() {
        guard !isTornDown else { return }
        for holder in renderer.componentHolders() where holder.kind == .library {
            guard let surface = librarySurfaces[holder.object.stableID] else { continue }
            surface.view.frame = viewRect(fromSkin: holder.frame)
        }
    }

    /// Top-left skin coordinates to the view's bottom-left ones, at the current UI Size.
    private func viewRect(fromSkin rect: CGRect) -> NSRect {
        NSRect(x: rect.minX * skinScale, y: bounds.height - rect.maxY * skinScale,
               width: rect.width * skinScale, height: rect.height * skinScale)
    }

    /// A splitter's grab strip gets the resize cursor, so a divider the skin draws no artwork for is
    /// still discoverable. Rects are re-derived whenever the divider moves.
    override func resetCursorRects() {
        super.resetCursorRects()
        guard !isTornDown else { return }
        for divider in renderer.frameDividers() {
            addCursorRect(viewRect(fromSkin: divider.rect),
                          cursor: divider.isVertical ? .resizeLeftRight : .resizeUpDown)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let next = renderer.object(at: skinPoint(convert(event.locationInWindow, from: nil)))
        guard next !== hoveredObject else { return }
        if let hoveredObject { _ = try? scripts.dispatch(object: hoveredObject, event: "onleavearea") }
        hoveredObject = next
        if let next { _ = try? scripts.dispatch(object: next, event: "onenterarea") }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        if let hoveredObject { _ = try? scripts.dispatch(object: hoveredObject, event: "onleavearea") }
        hoveredObject = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = skinPoint(convert(event.locationInWindow, from: nil))
        // A splitter's grab strip spans the full height of its frame, which means it crosses whatever
        // the skin has laid over that column — cPro's tab strip runs straight through the 8px seam.
        // So the divider only claims the click when nothing interactive is under it; a control the
        // user can actually see always wins, and the seam between the panes is still draggable.
        if renderer.object(at: point) == nil, let divider = renderer.frameDivider(at: point) {
            draggedDivider = divider
            return
        }
        if let holder = renderer.componentHolder(at: point) {
            switch holder.kind {
            case .playlist:
                if let row = renderer.playlistRow(at: point, in: holder.frame) {
                    if event.clickCount >= 2 { componentHost?.playlistPlay(row: row) }
                    else { componentHost?.playlistSelect(row: row) }
                    // Clicking a row is what gives this window the keyboard, and with it Delete.
                    playlistHasFocus = true
                    window?.makeFirstResponder(self)
                    needsDisplay = true
                }
                return
            case .equalizer:
                pressedEQHolder = holder.object
                updateEqualizer(holder: holder.object, frame: holder.frame, point: point)
                return
            case .library, .visualization, .video, .other:
                return
            }
        }
        guard let object = renderer.object(at: point) else { return }
        pressedObject = object
        dispatch(object: object, event: "onleftbuttondown", point: point)
        updateSlider(object, point: point)
        needsDisplay = true

        if shouldDragWindow(from: object), let window {
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = skinPoint(convert(event.locationInWindow, from: nil))
        if let draggedDivider {
            guard renderer.dragFrameDivider(draggedDivider, to: point) else { return }
            // The panes moved, so anything hosted inside one (the embedded library) has to follow,
            // and the grab strip itself is somewhere else now.
            needsLayout = true
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        }
        if let pressedEQHolder, let frame = renderer.frame(of: pressedEQHolder) {
            updateEqualizer(holder: pressedEQHolder, frame: frame, point: point)
            return
        }
        if let pressedObject {
            dispatch(object: pressedObject, event: "onmousemove", point: point)
            updateSlider(pressedObject, point: point)
        }
        if isDraggingWindow, let window {
            let current = event.locationInWindow
            var origin = window.frame.origin
            origin.x += current.x - windowDragStartPoint.x
            origin.y += current.y - windowDragStartPoint.y
            origin = WindowManager.shared.windowWillMove(window, to: origin)
            window.setFrameOrigin(origin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = skinPoint(convert(event.locationInWindow, from: nil))
        if draggedDivider != nil { draggedDivider = nil; return }
        if pressedEQHolder != nil { pressedEQHolder = nil; needsDisplay = true; return }
        let releasedOver = renderer.object(at: point)
        if let pressedObject {
            dispatch(object: pressedObject, event: "onleftbuttonup", point: point)
            if releasedOver === pressedObject {
                _ = try? scripts.dispatch(object: pressedObject, event: "onleftclick")
                performAction(for: pressedObject)
            }
        }
        if isDraggingWindow, let window { WindowManager.shared.windowDidFinishDragging(window) }
        isDraggingWindow = false
        pressedObject = nil
        needsDisplay = true
    }

    override func rightMouseUp(with event: NSEvent) {
        let point = skinPoint(convert(event.locationInWindow, from: nil))
        guard let object = renderer.object(at: point) else { return }
        dispatch(object: object, event: "onrightbuttonup", point: point)
    }

    override func scrollWheel(with event: NSEvent) {
        let point = skinPoint(convert(event.locationInWindow, from: nil))
        guard let holder = renderer.componentHolder(at: point), holder.kind == .playlist,
              let rowCount = componentHost?.playlistSnapshot().rows.count else {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.deltaY > 0 ? -1 : (event.deltaY < 0 ? 1 : 0)
        guard delta != 0 else { return }
        renderer.scrollPlaylist(byRows: delta, rowCount: rowCount, in: holder.frame)
        needsDisplay = true
    }

    private func updateEqualizer(holder: WasabiObject, frame: CGRect, point: CGPoint) {
        guard let snapshot = componentHost?.equalizerSnapshot(), frame.width > 0, frame.height > 0 else { return }
        let slots = snapshot.bandGainsDB.count + 1 // preamp + bands
        let slotWidth = frame.width / CGFloat(slots)
        let slot = max(0, min(slots - 1, Int((point.x - frame.minX) / slotWidth)))
        let normalized = max(0, min(1, 1 - (point.y - frame.minY) / frame.height))
        let gainDB = Float(normalized * 24 - 12) // 0…1 → -12…12
        if slot == 0 { componentHost?.equalizerSetPreampDB(gainDB) }
        else { componentHost?.equalizerSetBandGainDB(slot - 1, gainDB: gainDB) }
        needsDisplay = true
    }

    func updateTrackInfo() { needsDisplay = true }

    func updateTime(current: TimeInterval, duration: TimeInterval) {
        if duration > 0 {
            let posted = Int32(max(0, min(255, current / duration * 255)))
            for object in renderer.loadedSkin.runtime.graph.objects(xmlID: "HiddenSeek") {
                _ = try? scripts.dispatch(object: object, event: "onpostedposition", arguments: [.integer(posted)])
            }
        }
        needsDisplay = true
    }

    func updatePlaybackState() {
        let state = host.playbackState
        if state != lastPlaybackState {
            if state == .playing { _ = try? scripts.dispatchSystem(event: "onplay") }
            if state == .stopped { _ = try? scripts.dispatchSystem(event: "onstop") }
            lastPlaybackState = state
        }
        let postedVolume = Int32(max(0, min(255, host.volume * 255)))
        // A volume change from outside the skin (the menu bar, a keyboard shortcut, another window)
        // has to reach the scripts too, or a readout the skin drives from `onVolumeChanged` sits on a
        // stale number. `setVolume` fires its own, so this only covers what the skin did not do.
        if postedVolume != lastPostedVolume {
            lastPostedVolume = postedVolume
            _ = try? scripts.dispatchSystem(event: "onvolumechanged", arguments: [.integer(postedVolume)])
        }
        for object in renderer.loadedSkin.runtime.graph.objects(xmlID: "HiddenVolume") {
            _ = try? scripts.dispatch(object: object, event: "onpostedposition",
                                      arguments: [.integer(postedVolume)])
        }
        needsDisplay = true
    }

    func updateSpectrum(_ levels: [Float]) {
        host.spectrumLevels = levels
    }

    func teardown() {
        guard !isTornDown else { return }
        renderer.themeCoordinator.removeObserver(self)
        if let tracking { removeTrackingArea(tracking) }
        tracking = nil
        animationTimer?.invalidate()
        animationTimer = nil
        pressedObject = nil
        pressedEQHolder = nil
        draggedDivider = nil
        hoveredObject = nil
        for surface in librarySurfaces.values { surface.prepareForUITeardown() }
        librarySurfaces.removeAll()
        // Auxiliary container views share the skin's single script runtime and host; only the
        // main (script-driving) view tears those down. Every view tears down its own renderer.
        if drivesScripts { scripts.teardown() }
        renderer.teardown()
        canvasSizeDidChange = nil
        componentWindowToggleRequested = nil
        surfaceToggleRequested = nil
        isTornDown = true
    }

    private func skinPoint(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x / skinScale, y: (bounds.height - point.y) / skinScale)
    }

    private func dispatch(object: WasabiObject, event: String, point: CGPoint) {
        _ = try? scripts.dispatch(object: object, event: event,
                                  arguments: [.integer(Int32(point.x)), .integer(Int32(point.y))])
    }

    /// Whether a press on `object` moves the window. Internal so the drag policy can be tested
    /// against a real scene without synthesizing mouse events.
    func shouldDragWindow(from object: WasabiObject) -> Bool {
        let id = object.xmlID?.lowercased() ?? ""
        if ["volume1", "seek1", "title1", "title2", "title3", "title4"].contains(id) { return false }
        // `move="0"` is how a skin says "this piece of the window is not a handle" — T800's volume
        // strip is a layer whose script owns the drag, and dragging the window off it loses the drag.
        if object.attributes["move"] == "0" { return false }
        let type = object.typeName.lowercased()
        // The layout is the window's own background. A skin that paints the whole frame there and
        // hangs only controls off it (T800) otherwise has nothing to drag by at all.
        if type == "layout" { return true }
        // A bare group has no artwork of its own, so a click reaching one landed on the background it
        // covers; `move="1"` is the skin declaring that background a drag handle (MMD3's main group).
        if type == "group" { return object.attributes["move"] == "1" }
        // A layer a script hooks the mouse on is a control, not a handle — the same thing `move="0"`
        // says explicitly, for the skins that do not bother to say it. Love is War Miku's invisible
        // `visual.trigger` is one: dragging the window off it would eat the click that cycles the
        // visualization.
        if type == "layer", Self.mouseEvents.contains(where: { scripts.hasBinding(for: object, event: $0) }) {
            return false
        }
        return type == "layer" && object.attributes["action"] == nil
    }

    private static let mouseEvents = ["onleftbuttondown", "onleftbuttonup", "onleftclick",
                                      "ondoubleclick", "onrightbuttondown"]

    /// Show a script-built menu at the mouse and answer the command id the user picked (0 = nothing).
    ///
    /// `popAtMouse` is synchronous in MAKI — the script reads the answer on the next line — and
    /// `NSMenu.popUp` runs its own tracking loop, so the call blocks here exactly as the skin
    /// expects. The menu is built from the resolved tree, so submenus nest.
    private func presentScriptPopup(_ items: [WinampModernPopupMenuItem]) -> Int32 {
        let target = ScriptPopupTarget()
        let menu = build(popupMenu: items, target: target)
        guard menu.numberOfItems > 0 else { return 0 }
        let location = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        menu.popUp(positioning: nil, at: location ?? .zero, in: self)
        return target.chosen
    }

    private func build(popupMenu items: [WinampModernPopupMenuItem],
                       target: ScriptPopupTarget) -> NSMenu {
        let menu = NSMenu()
        // The skin owns whether a row is greyed out; AppKit's automatic enabling would second-guess
        // it from the action's validation.
        menu.autoenablesItems = false
        for item in items {
            if item.isSeparator {
                menu.addItem(.separator())
                continue
            }
            let entry = NSMenuItem(title: item.title, action: #selector(ScriptPopupTarget.pick(_:)),
                                   keyEquivalent: "")
            entry.target = target
            entry.tag = Int(item.commandID)
            entry.state = item.checked ? .on : .off
            entry.isEnabled = !item.disabled
            if !item.children.isEmpty {
                entry.submenu = build(popupMenu: item.children, target: target)
                entry.action = nil
            }
            menu.addItem(entry)
        }
        return menu
    }

    /// Carries the picked command out of `NSMenu.popUp`'s tracking loop.
    private final class ScriptPopupTarget: NSObject {
        var chosen: Int32 = 0
        @objc func pick(_ sender: NSMenuItem) { chosen = Int32(sender.tag) }
    }

    private func updateSlider(_ object: WasabiObject, point: CGPoint) {
        guard object.typeName.caseInsensitiveCompare("slider") == .orderedSame,
              let frame = renderer.frame(of: object), frame.width > 0, frame.height > 0 else { return }
        let vertical = object.attributes["orientation"]?.lowercased() == "vertical"
        let value = vertical ? 1 - (point.y - frame.minY) / frame.height
                             : (point.x - frame.minX) / frame.width
        let normalized = max(0, min(1, value))
        if let eq = WinampModernEQAction.decode(action: object.attributes["action"],
                                                parameter: object.attributes["param"]),
           let componentHost {
            // ±12 dB through the host, which is the same value the thumb is drawn from.
            eq.apply(normalized: normalized, to: componentHost)
            needsDisplay = true
            return
        }
        switch object.attributes["action"]?.lowercased() {
        case "seek": host.seek(to: host.duration * normalized)
        case "volume": host.volume = normalized
        default: _ = object.setAttribute("value", value: String(Int(normalized * 255)))
        }
        needsDisplay = true
    }

    private func performAction(for object: WasabiObject) {
        let action = object.attributes["action"]
        let parameter = object.attributes["param"]
        performAction(action: action, parameter: parameter)
        if action == nil {
            switch object.xmlID?.lowercased() {
            case "shuffle": host.shuffleEnabled.toggle()
            case "repeat": host.repeatEnabled.toggle()
            default: break
            }
        }
        updatePlaybackState()
    }

    private func performAction(action: String?, parameter: String?) {
        switch action?.uppercased() {
        case "PLAY": host.play()
        case "PAUSE": host.pause()
        case "STOP": host.stop()
        case "PREV": host.previous()
        case "NEXT": host.next()
        case "EJECT": host.openFiles()
        case "SWITCH":
            if let parameter { activateLayout(id: parameter) }
        // The window commands every skin puts on its titlebar. T800 draws all three (minimize,
        // shade-switch, close) as 4×5px buttons on the machine's chest.
        case "MINIMIZE": window?.miniaturize(nil)
        case "CLOSE": window?.performClose(nil)
        case "TOGGLE":
            if let kind = WinampModernComponentRegistry.kind(for: parameter) { routeComponentToggle(kind) }
        case "EQ_TOGGLE":
            // Winamp's `EQ_TOGGLE` turns the equalizer *on and off*. It is not a window command:
            // showing the equalizer is `TOGGLE guid:eq`, which routes through the surface coordinator.
            if let componentHost {
                componentHost.equalizerSetEnabled(!componentHost.equalizerSnapshot().enabled)
                needsDisplay = true
            }
        case "EQ_AUTO":
            if let componentHost {
                componentHost.equalizerSetAuto(!componentHost.equalizerSnapshot().auto)
                needsDisplay = true
            }
        case "EQ_PREAMP", "EQ_BAND":
            // A *button* carrying a band action (a reset, a nudge) has no position to read; the
            // slider path owns the values. Inert rather than wrong.
            break
        case "MENU":
            if parameter?.lowercased() == "presets" { showEqualizerPresetMenu() }
        default: break
        }
    }

    /// The skin's own "presets" button. Winamp opens the equalizer preset list from it; we build the
    /// same list from `EQPreset.allPresets` and apply through the component host, so every EQ surface
    /// (this window, an auxiliary one, the classic window) sees the change at once.
    private func showEqualizerPresetMenu() {
        guard let componentHost, let event = NSApp.currentEvent else { return }
        let menu = NSMenu(title: "Equalizer Presets")
        for preset in EQPreset.allPresets {
            let item = NSMenuItem(title: preset.name, action: #selector(applyEqualizerPreset(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = preset.name
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func applyEqualizerPreset(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        componentHost?.equalizerApplyPreset(named: name)
        WindowManager.shared.refreshWinampModernSurfaces()
        needsDisplay = true
    }

    /// Route a component toggle to the skin's own surfaces first, then fall back to the classic
    /// window. Embedded SUI components are always present, so a toggle over them must not spawn a
    /// classic auxiliary window (that was the Phase 1 behaviour Phase 5 replaces).
    func routeComponentToggle(_ kind: WinampModernComponentKind) {
        if surfaceToggleRequested?(kind) == true { return }
        if renderer.componentHolders().contains(where: { $0.kind == kind }) { return }
        if componentWindowToggleRequested?(kind) == true { return }
        componentHost?.toggleClassicWindow(for: kind)
    }
}
