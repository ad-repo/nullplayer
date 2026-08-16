import AppKit

final class WinampModernMainView: NSView {
    let renderer: WasabiSceneRenderer
    let scripts: WinampModernScriptRuntime
    let host: WinampModernHost
    private weak var componentHost: WinampModernComponentHost?
    private var libraryHostViews: [WasabiObjectID: NSView] = [:]

    private var pressedObject: WasabiObject?
    private var pressedEQHolder: WasabiObject?
    private var hoveredObject: WasabiObject?
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    private var lastPlaybackState: PlaybackState = .stopped
    private var tracking: NSTrackingArea?
    private var animationTimer: Timer?
    private(set) var isTornDown = false
    var canvasSizeDidChange: ((CGSize) -> Void)?
    /// Returns true if the skin provides a separate native window for the kind and it was toggled.
    var componentWindowToggleRequested: ((WinampModernComponentKind) -> Bool)?

    /// The main window drives the shared script runtime's callbacks (layout switching, theme,
    /// actions). Auxiliary container windows render + take input but must not clobber those
    /// single-owner callbacks, so they pass `drivesScripts: false`.
    private let drivesScripts: Bool

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

    private func wireScriptCallbacks() {
        scripts.graphDidMutate = { [weak self] in self?.needsDisplay = true }
        scripts.layoutSwitchRequested = { [weak self] layoutID in
            guard let self, let size = try? self.renderer.activateLayout(id: layoutID) else { return false }
            self.setFrameSize(size)
            self.canvasSizeDidChange?(size)
            self.needsDisplay = true
            return true
        }
        scripts.layoutResizeRequested = { [weak self] proposed in
            guard let self else { return }
            let size = self.renderer.resize(to: proposed)
            self.setFrameSize(size)
            self.canvasSizeDidChange?(size)
            self.needsDisplay = true
        }
        scripts.actionRequested = { [weak self] action, parameter in
            self?.performAction(action: action, parameter: parameter)
        }
        scripts.themeNamesRequested = { [weak renderer] in renderer?.themes.themeNames ?? [] }
        scripts.activeThemeRequested = { [weak renderer] in renderer?.themes.activeTheme ?? "Default" }
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

    override func draw(_ dirtyRect: NSRect) {
        guard !isTornDown, let context = NSGraphicsContext.current?.cgContext else { return }
        layoutHostedSubviews()
        context.clear(bounds)
        renderer.draw(in: context, pressed: pressedObject?.stableID,
                      hovered: hoveredObject?.stableID)
    }

    /// Position live host subviews (the embedded library) at their skin-provided holder frames,
    /// converting from top-left skin coordinates to the view's bottom-left coordinates. Holders that
    /// vanish (layout switch) have their subviews removed.
    private func layoutHostedSubviews() {
        guard !isTornDown else { return }
        var live: Set<WasabiObjectID> = []
        for holder in renderer.componentHolders() where holder.kind == .library {
            var view = libraryHostViews[holder.object.stableID]
            if view == nil, let created = componentHost?.makeLibraryContentView() {
                libraryHostViews[holder.object.stableID] = created
                addSubview(created)
                view = created
            }
            guard let view else { continue }
            live.insert(holder.object.stableID)
            view.frame = NSRect(x: holder.frame.minX, y: bounds.height - holder.frame.maxY,
                                width: holder.frame.width, height: holder.frame.height)
        }
        for (id, view) in libraryHostViews where !live.contains(id) {
            view.removeFromSuperview()
            libraryHostViews[id] = nil
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
        if let holder = renderer.componentHolder(at: point) {
            switch holder.kind {
            case .playlist:
                if let row = renderer.playlistRow(at: point, in: holder.frame) {
                    if event.clickCount >= 2 { componentHost?.playlistPlay(row: row) }
                    else { componentHost?.playlistSelect(row: row) }
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
        if let tracking { removeTrackingArea(tracking) }
        tracking = nil
        animationTimer?.invalidate()
        animationTimer = nil
        pressedObject = nil
        pressedEQHolder = nil
        hoveredObject = nil
        for view in libraryHostViews.values { view.removeFromSuperview() }
        libraryHostViews.removeAll()
        // Auxiliary container views share the skin's single script runtime and host; only the
        // main (script-driving) view tears those down. Every view tears down its own renderer.
        if drivesScripts { scripts.teardown() }
        renderer.teardown()
        canvasSizeDidChange = nil
        componentWindowToggleRequested = nil
        isTornDown = true
    }

    private func skinPoint(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: bounds.height - point.y)
    }

    private func dispatch(object: WasabiObject, event: String, point: CGPoint) {
        _ = try? scripts.dispatch(object: object, event: event,
                                  arguments: [.integer(Int32(point.x)), .integer(Int32(point.y))])
    }

    private func shouldDragWindow(from object: WasabiObject) -> Bool {
        let id = object.xmlID?.lowercased() ?? ""
        if ["volume1", "seek1", "title1", "title2", "title3", "title4"].contains(id) { return false }
        let type = object.typeName.lowercased()
        return type == "layer" && object.attributes["action"] == nil
    }

    private func updateSlider(_ object: WasabiObject, point: CGPoint) {
        guard object.typeName.caseInsensitiveCompare("slider") == .orderedSame,
              let frame = renderer.frame(of: object), frame.width > 0, frame.height > 0 else { return }
        let vertical = object.attributes["orientation"]?.lowercased() == "vertical"
        let value = vertical ? 1 - (point.y - frame.minY) / frame.height
                             : (point.x - frame.minX) / frame.width
        let normalized = max(0, min(1, value))
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
            if let parameter, let size = try? renderer.activateLayout(id: parameter) {
                setFrameSize(size)
                canvasSizeDidChange?(size)
                needsDisplay = true
            }
        case "TOGGLE":
            if let kind = WinampModernComponentRegistry.kind(for: parameter) { routeComponentToggle(kind) }
        case "EQ_TOGGLE":
            // ClassicPro's embedded EQ drawer: toggle the equalizer surface (embedded → skin window →
            // classic window), consistent with `TOGGLE guid:eq`.
            routeComponentToggle(.equalizer)
        case "EQ_AUTO":
            if let host = componentHost {
                host.equalizerSetAuto(!host.equalizerSnapshot().auto)
                needsDisplay = true
            }
        default: break
        }
    }

    /// Route a component toggle to the skin's own surfaces first, then fall back to the classic
    /// window. Embedded SUI components are always present, so a toggle over them must not spawn a
    /// classic auxiliary window (that was the Phase 1 behaviour Phase 5 replaces).
    func routeComponentToggle(_ kind: WinampModernComponentKind) {
        if renderer.componentHolders().contains(where: { $0.kind == kind }) { return }
        if componentWindowToggleRequested?(kind) == true { return }
        componentHost?.toggleClassicWindow(for: kind)
    }
}
