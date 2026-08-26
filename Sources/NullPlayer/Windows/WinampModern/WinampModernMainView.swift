import AppKit

final class WinampModernMainView: NSView {
    let renderer: WasabiSceneRenderer
    let scripts: WinampModernScriptRuntime
    let host: WinampModernHost
    weak var componentHost: WinampModernComponentHost?
    /// Live library surfaces by holder id. Typed, so each one can be told about a palette change, a
    /// UI Size change, and its own teardown (Phase 13.8).
    private var librarySurfaces: [WasabiObjectID: WinampModernLibrarySurface] = [:]
    /// Live video surfaces by holder id, on the same typed handle for the same reasons (B20).
    private var videoSurfaces: [WasabiObjectID: WinampModernVideoSurface] = [:]
    /// Live visualization surfaces by holder id — the skin's AVS window, filled with the host's own
    /// visualization engine rather than the engine-drawn analyzer (B20a).
    private var visualizationSurfaces: [WasabiObjectID: WinampModernVisualizationSurface] = [:]
    /// Live synthesized host-window surfaces by holder id. The bridge may hand the same adapter back
    /// when a holder returns; this dictionary tracks only the holders present in this scene right now.
    private var hostedWindowSurfaces: [WasabiObjectID: WinampModernHostedSurface] = [:]
    /// Independent WebKit surfaces for `<browser>` elements. Each is non-cached and keeps its own
    /// history, completely independent from the bridge's cached Media Library surface.
    private var browserSurfaces: [WasabiObjectID: WinampModernBrowserSurface] = [:]
    /// MAKI may navigate a browser from `onScriptLoaded`, before AppKit has performed the first
    /// layout. Keep the last request per object and apply it when reconciliation creates the view.
    private var pendingBrowserRequests: [WasabiObjectID: WinampModernBrowserRequest] = [:]

    /// UI Size, as a multiplier on the skin's own pixel grid. The scene is always laid out in skin
    /// pixels — the scale is applied once at the drawing boundary and undone once at the input
    /// boundary, so nothing in the graph, the renderer, or a script ever sees it.
    var skinScale: CGFloat = 1 {
        didSet {
            guard skinScale != oldValue else { return }
            setFrameSize(scaledCanvasSize)
            pushLibraryContentScale()
            for surface in videoSurfaces.values { surface.applySkinScale(skinScale) }
            for surface in visualizationSurfaces.values { surface.applySkinScale(skinScale) }
            for surface in hostedWindowSurfaces.values { surface.applySkinScale(skinScale) }
            for surface in browserSurfaces.values { surface.applySkinScale(skinScale) }
            invalidateRectCaches()
            needsLayout = true
            needsDisplay = true
        }
    }

    var scaledCanvasSize: NSSize {
        NSSize(width: (renderer.canvasSize.width * skinScale).rounded(),
               height: (renderer.canvasSize.height * skinScale).rounded())
    }

    /// How large the embedded Media Library draws its content: UI Size, times the Text Size setting
    /// resolved against *this* scene's canvas. One number, so the library and the playlist beside it
    /// move together and cannot drift.
    var libraryContentScale: CGFloat {
        skinScale * renderer.textScale.contentScale(canvasHeight: renderer.canvasSize.height)
    }

    /// Tell every live library surface the current number.
    ///
    /// Called from everything that can move either factor — including **every canvas change**, since
    /// `auto` is keyed on canvas height: without that, resizing a Big Bento window leaves the library
    /// at a stale scale while the playlist next to it grows.
    func pushLibraryContentScale() {
        let scale = libraryContentScale
        for surface in librarySurfaces.values { surface.applyContentScale(scale) }
    }

    private var pressedObject: WasabiObject?
    private var rightPressedObject: WasabiObject?
    private var pressedEQHolder: WasabiObject?
    private var draggedDivider: WasabiObject?
    private var hoveredObject: WasabiObject?
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    private var lastPlaybackState: PlaybackState = .stopped
    /// Last volume the scripts were told about, 0…255. −1 until the first update.
    private var lastPostedVolume: Int32 = -1
    /// Last title the scripts were told about, so `onTitleChange` fires per track rather than per
    /// redraw. `nil` until the first update, which is not the same as the empty "no track" title.
    private var lastPostedTitle: String?
    private var tracking: NSTrackingArea?
    private var animationTimer: Timer?
    private(set) var isTornDown = false
    private var sceneIsVisible = false
    var canvasSizeDidChange: ((CGSize) -> Void)?
    /// A click landed in this window: dismiss any `autoclose="1"` popup that is not this one. The
    /// controller owns the windows, so it does the closing.
    var didClickInWindow: ((WasabiObjectID) -> Void)?
    /// Returns true if the skin provides a separate native window for the kind and it was toggled.
    var componentWindowToggleRequested: ((WinampModernComponentKind) -> Bool)?
    /// A web address the skin wants opened, and where it wants it. Owned by the window layer rather
    /// than answered here: the destination browser can live in another container's view, and the
    /// external route has to ask the user first (B40).
    var webNavigationRequested: ((WinampModernWebNavigationTarget, String) -> Void)?
    /// Show/hide one of the skin's *own* container windows by id, for a `TOGGLE` whose parameter
    /// names a container rather than a component.
    var containerWindowToggleRequested: ((String) -> Bool)?
    /// Ask the surface coordinator to toggle a surface — the same route the View menu takes, so a
    /// skin button and a menu item can never resolve differently. Returns false before the
    /// coordinator exists (during `scripts.start()`), where the older direct routing still applies.
    var surfaceToggleRequested: ((WinampModernComponentKind) -> Bool)?
    /// The window commands a skin draws on its titlebar, routed to whoever owns the window layer.
    ///
    /// They cannot be answered from here with the obvious AppKit calls. `performClose(_:)` *simulates
    /// a click on the close button*, and a `.wal` window is `.borderless` — it has none, so the call
    /// beeps and returns; that is why no skin's close button did anything. And Close/Minimize are
    /// Winamp's, not one window's: closing the player quits (as the classic skin's close button does),
    /// while closing a playlist window only hides that window, and minimizing takes the whole set of
    /// skin windows down together rather than leaving the rest of the skin on screen.
    var closeRequested: (() -> Void)?
    var minimizeRequested: (() -> Void)?

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
        if drivesScripts { wireScriptCallbacks() } else { wireAuxiliaryRepaint() }
        // Every `.wal` window repaints on a colour-theme switch, whichever window triggered it, and
        // so does any AppKit content it hosts.
        renderer.themeCoordinator.addObserver(self) { [weak self] in
            self?.themeDidChange()
        }
        updateAnimationTimer()
    }

    /// Run the 30 Hz repaint clock when this scene has anything that moves on its own.
    ///
    /// Re-evaluated rather than decided once: a **Layer FX** layer only becomes one when its script
    /// turns FX on, which happens in `onScriptLoaded` — after this view is built — and a skin may
    /// turn it on later still (Defix's display styles are switched from its settings window).
    func updateAnimationTimer() {
        // Cheap first: this is reachable from a script mutation, which for a warped layer happens
        // 30 times a second, and the scene walk below is not something to do on that path.
        guard !isTornDown, animationTimer == nil else { return }
        invalidateRectCaches()
        guard !animatingRects().isEmpty else { return }
        let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
            self?.animationTick()
        }
        // `.common`, not the default mode: a timer scheduled on the default mode alone stops firing
        // for as long as AppKit runs a tracking loop, so the reels froze while the window was dragged
        // or a menu was open and lurched forward when it ended.
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    /// One frame of self-driven animation: build what moved *before* asking for the paint.
    ///
    /// Evaluating a Layer FX mesh runs the skin's callbacks per grid vertex through the MAKI
    /// interpreter, and doing it lazily from the renderer put that work inside `draw`. Here it is
    /// still the main thread — a MAKI callback has to be — but it is off the paint path, so the frame
    /// AppKit is composing is not the one waiting for the interpreter.
    private func animationTick() {
        guard !isTornDown else { return }
        scripts.refreshLayerFXMeshes()
        repaintAnimatingObjects()
    }

    /// Drop every derived rect this view caches, and the renderer's memoized scene with them.
    /// Called wherever the scene may have changed shape — a layout switch, a resize, a UI Size
    /// change, a script mutating the graph.
    private func invalidateRectCaches() {
        animatingRectsCache = nil
        objectRectCache.removeAll()
        visualizationRectsCache = nil
        timeRectsCache = nil
        renderer.invalidateSceneCache()
    }

    /// The boxes of everything in this scene that moves on its own — animated layers, song tickers,
    /// ticker text, and any layer whose script has switched Layer FX on.
    ///
    /// Repainting *these* rather than the whole window is what keeps an animation smooth: Defix's
    /// player costs 19.3 ms a frame repainted whole at Retina scale and 6.9 ms clipped to its meters,
    /// and a 33 ms animation step cannot survive the first number. Cached because the scene walk is
    /// not free and the boxes only move when the scene itself does.
    private func animatingRects() -> [NSRect] {
        if let animatingRectsCache { return animatingRectsCache }
        let rects = renderer.sceneNodes().compactMap { node -> NSRect? in
            let object = node.object
            let type = object.typeName.lowercased()
            var animates = ["animatedlayer", "songticker"].contains(type)
            if !animates, type == "text" {
                // A plain `text` that opts into ticker scrolling also needs the redraw clock.
                let ticker = (object.attributes["ticker"] ?? "0").lowercased()
                animates = !["0", "off", "false", "no"].contains(ticker)
            }
            if !animates { animates = scripts.layerFXState(of: object)?.enabled == true }
            guard animates else { return nil }
            return viewRect(fromSkin: node.frame).insetBy(dx: -2, dy: -2)
        }
        animatingRectsCache = rects
        return rects
    }

    private func repaintAnimatingObjects() {
        guard !isTornDown else { return }
        let rects = animatingRects()
        // A scene with a great many moving parts is cheaper to repaint in one pass than to invalidate
        // piece by piece.
        guard !rects.isEmpty, rects.count <= 24 else {
            needsDisplay = true
            return
        }
        for rect in rects { setNeedsDisplay(rect) }
    }

    /// Dropped whenever the scene itself may have changed shape.
    private var animatingRectsCache: [NSRect]?

    /// Switch this view's container to one of its own layouts. Returns false when the container has
    /// no such layout, so a script's `switchToLayout` on a container we do not host is a no-op rather
    /// than a resize of the wrong window.
    @discardableResult
    func activateLayout(id: String) -> Bool {
        guard (try? renderer.activateLayout(id: id)) != nil else { return false }
        invalidateRectCaches()
        // A different layout is a different subtree with its own splitters, and `persistableFrames()`
        // only ever sees the active one — so without this a divider dragged in the shade layout would
        // be stored and then never restored (B44a). Placed after `activateLayout`, which has already
        // set the new canvas size the offsets are clamped against.
        renderer.restorePersistedFramePositions()
        setFrameSize(scaledCanvasSize)
        canvasSizeDidChange?(scaledCanvasSize)
        // A different layout is a different scene, so nothing carries over: every object in it hears
        // its geometry for the first time, exactly as it does when the window first comes up.
        dispatchResize(seeding: true)
        // A different layout is a different canvas height, which is what `auto` Text Size is keyed on.
        pushLibraryContentScale()
        needsDisplay = true
        return true
    }

    /// Resize this view's canvas (clamped by the active layout) and its window with it.
    func applyCanvasResize(_ proposed: CGSize) {
        invalidateRectCaches()
        _ = renderer.resize(to: proposed)
        setFrameSize(scaledCanvasSize)
        canvasSizeDidChange?(scaledCanvasSize)
        dispatchResize(seeding: false)
        // `auto` Text Size is keyed on canvas height, so a user resize moves it.
        pushLibraryContentScale()
        needsDisplay = true
    }

    /// Give the scene's scripts their geometry, once, straight after `scripts.start()`.
    ///
    /// A script that only assigns state inside `onResize` has none of it until the event has fired.
    /// ClassicPro's `beat.m` is exactly that: `showBeat`/`showPromo` are written nowhere else, so with
    /// the event never dispatched they stayed false, the beat display was visible only from its XML
    /// state, and the first `System.onPlay()` → `refreshView()` → `showGroup(0)` hid both display
    /// groups with nothing able to bring either back. That is the reported "the visualization goes away
    /// when you play a track".
    ///
    /// Not gated on `drivesScripts`: a resize is addressed to a *container*, not to the runtime's
    /// single-owner callbacks, so every container window seeds its own scene (Phase 13.3).
    /// Tell this container's scripts that its window came on screen, or left it.
    ///
    /// A `.wal` skin starts and stops its animation from `onSetVisible` — Defix's cassette reels turn
    /// their Layer FX on there, and its speaker cabinets start their timer there — so a window shown
    /// with `orderFront` alone (an AppKit call the graph never hears about) leaves the scene frozen.
    func setSceneVisible(_ visible: Bool) {
        sceneIsVisible = visible
        scripts.notifyContainerVisibility(containerID: containerID, visible: visible)
        if visible {
            updateAnimationTimer()
            // The surfaces are made during a layout pass, which for a window that opens later has
            // already happened while it was still hidden — and an engine refused a start then is
            // never asked again. This is the ask (B20a).
            layoutSubtreeIfNeeded()
            for surface in visualizationSurfaces.values { surface.resumeRendering() }
            for surface in hostedWindowSurfaces.values { surface.resume() }
            needsDisplay = true
        } else {
            for surface in hostedWindowSurfaces.values { surface.suspend() }
        }
    }

    /// Visibility of host-owned consumers is stricter than Wasabi window visibility: an occluded or
    /// miniaturized native window is still logically shown to the skin, but its timers/display links
    /// must stop until pixels can be seen again.
    func setHostedContentActive(_ active: Bool) {
        for surface in hostedWindowSurfaces.values {
            if active { surface.resume() } else { surface.suspend() }
        }
    }

    func hasHostedWindowSurface(_ id: WinampModernHostedWindowID) -> Bool {
        renderer.componentHolders().contains { holder in
            holder.hostedWindowID == id && hostedWindowSurfaces[holder.object.stableID] != nil
        }
    }

    func scriptsDidStart() {
        // Before the seeding dispatch, so a script whose state is only assigned in `onResize` is told
        // the geometry the user actually left behind rather than the skin's default and then a
        // correction (B44).
        restorePersistedFramePositions()
        dispatchResize(seeding: true)
        // A skin turns Layer FX on from `onScriptLoaded`, so only now can this scene know whether it
        // has a warped layer to keep repainting.
        updateAnimationTimer()
    }

    // MARK: - Splitter persistence (B44)

    /// Put every splitter back where the user dragged it. The scene state itself lives on the
    /// renderer, which already owns the container id and the skin's configuration store; this is the
    /// window layer's handle on it, and the one place that knows the view may be torn down.
    @discardableResult
    func restorePersistedFramePositions() -> Bool {
        guard !isTornDown else { return false }
        return renderer.restorePersistedFramePositions()
    }

    /// Tell whatever moved that it moved, after a change this view did not itself cause — a script
    /// collapsing a splitter, hiding a group, reparenting one. Cheap when nothing actually moved: the
    /// frames are compared against the last dispatch and an unchanged scene dispatches nothing.
    func dispatchResizeIfChanged() {
        dispatchResize(seeding: false)
    }

    /// Resolved frames at the last dispatch, so only an object whose own box actually moved is told
    /// about it — Wasabi does not resize what did not change.
    private var lastResizeFrames: [WasabiObjectID: CGRect] = [:]

    private func dispatchResize(seeding: Bool) {
        guard !isTornDown else { return }
        let targets = renderer.resizeTargets()
        scripts.dispatchResize(targets: targets, previous: seeding ? nil : lastResizeFrames)
        // Recorded *after* the handlers ran: a script that re-solves its own geometry from `onResize`
        // has already moved things, and the next comparison has to be against where they now are.
        lastResizeFrames = Dictionary(renderer.resizeTargets().map { ($0.object.stableID, $0.frame) },
                                      uniquingKeysWith: { _, latest in latest })
    }

    /// The skin switched colour theme. The renderer has already dropped its themed bitmaps.
    ///
    /// Embedded surfaces are told directly; the *fallback* windows have no handle on this view, so
    /// they learn about it from the notification (Phase 16.2). Both have to happen, because a skin
    /// can have one of each open at the same time.
    private func themeDidChange() {
        for surface in librarySurfaces.values { surface.applyPalette(renderer.palette) }
        for surface in videoSurfaces.values { surface.applyPalette(renderer.palette) }
        for surface in visualizationSurfaces.values { surface.applyPalette(renderer.palette) }
        let style = WinampModernSurfaceStyle(palette: renderer.palette)
        for surface in hostedWindowSurfaces.values { surface.applyPalette(style) }
        NotificationCenter.default.post(name: .winampModernThemeDidChange, object: nil)
        needsDisplay = true
    }

    /// An auxiliary container window renders the shared graph but must not clobber the single-owner
    /// callbacks, so it takes repaints — and only repaints — through a sink of its own.
    ///
    /// Without this, a script that ticks in an auxiliary container updated the graph and nothing ever
    /// redrew it: MAKI timers belong to the runtime, so `onTimer` fires wherever the object lives, but
    /// every repaint route was owned by the main window. Defix's playlist box (`Items:`/`Time:`, both
    /// written from `onTimer`) and its speaker cones (`SpeakerVis`, stepped the same way) are the two
    /// measured cases.
    private func wireAuxiliaryRepaint() {
        scripts.addAuxiliaryRepaintSink(owner: self) { [weak self] object in
            guard let self, !self.isTornDown else { return }
            // Scoped: a warped layer on the *main* window fires this 30 times a second, and this
            // window has no business repainting for it.
            if let object {
                guard self.owns(object) else { return }
                self.setNeedsDisplay(for: object)
                return
            }
            self.invalidateRectCaches()
            self.needsLayout = true
            self.needsDisplay = true
            self.updateAnimationTimer()
        }
    }

    /// Whether `object` is inside the container this view renders. Walks the retained graph's parent
    /// chain, which is cheap and is the only thing that distinguishes "not laid out yet in my scene"
    /// (repaint me) from "belongs to another window" (do not).
    private func owns(_ object: WasabiObject) -> Bool {
        var node: WasabiObject? = object
        while let current = node {
            if current === renderer.container { return true }
            node = current.parent
        }
        return false
    }

    private func wireScriptCallbacks() {
        scripts.graphDidMutate = { [weak self] in
            // A script can add or remove a component holder — cPro builds its Media Library holder
            // when that tab is first opened — so a graph change has to re-run surface reconciliation,
            // not just repaint. Without this the tab opens onto an empty hole.
            self?.invalidateRectCaches()
            self?.needsLayout = true
            self?.needsDisplay = true
            // A script can also turn Layer FX on outside load (switching Defix's display style does
            // exactly that), and the warp needs the repaint clock from that moment on.
            self?.updateAnimationTimer()
        }
        // The light path a warped layer takes 30 times a second: repaint, nothing else.
        scripts.repaintRequested = { [weak self] in self?.needsDisplay = true }
        // Lighter still when the runtime can name what moved — only that rect is repainted.
        scripts.objectRepaintRequested = { [weak self] object in self?.setNeedsDisplay(for: object) }
        scripts.actionRequested = { [weak self] action, parameter in
            self?.performAction(action: action, parameter: parameter)
        }
        scripts.focusRequested = { [weak self] object in self?.focusEdit(object) }
        scripts.themeNamesRequested = { [weak renderer] in renderer?.themes.themeNames ?? [] }
        scripts.activeThemeRequested = { [weak renderer] in renderer?.themes.activeTheme ?? "Default" }
        scripts.mousePositionRequested = { [weak self] in
            self?.currentMousePositionInSkinPixels() ?? .zero
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
        scripts.popupPresenter = { [weak self] items, point in
            self?.presentScriptPopup(items, at: point) ?? 0
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

    /// Claim the keyboard for the window, so a skin's own `System.onKeyDown` handlers can be reached
    /// at all — until Phase 43 this answered `playlistHasFocus`, and a `.wal` window that had never
    /// had a playlist row clicked was never first responder, so no key ever arrived here.
    ///
    /// Safe to take unconditionally because `keyDown` below is a *fall-through*: menu equivalents go
    /// through `performKeyEquivalent` before any of this, and anything neither the playlist nor a
    /// script consumes is handed straight back to the responder chain, which is exactly where it went
    /// when the view refused focus. Delete stays gated on `playlistHasFocus` — the queue must not be
    /// edited from the player chrome.
    override var acceptsFirstResponder: Bool { true }
    private var playlistHasFocus = false

    override func resignFirstResponder() -> Bool {
        playlistHasFocus = false
        return true
    }

    /// The keyboard, in the order the two claims on it were added.
    ///
    /// 1. Delete / Forward Delete remove the selected playlist row — but only while the playlist
    ///    surface in this window owns focus, so the key never reaches the queue from the chrome.
    /// 2. Everything else is offered to the skin as `System.onKeyDown("<accelerator>")`. Five skins
    ///    in the corpus handle it — multipass and winampmodern566 toggle their EQ drawer on `alt+g`,
    ///    winampmodern566 also shades its playlist on `ctrl+w` and its album-art window on `alt+a`,
    ///    Defix closes its playlist search line on `esc`. A handler that reached its `complete;`
    ///    consumed the key; anything else falls through to the responder chain unchanged.
    /// The `<edit>` this window's keyboard is going to, if any. A skin asks for it with `setFocus()`
    /// (Big Bento's playlist search) and a click into the box takes it too.
    private var focusedEdit: WasabiObject?

    /// Give the keyboard to an `<edit>`, or take it back (`nil`).
    ///
    /// The object a skin focuses is as often the wrapper as the control, and the box it shows in the
    /// same handler is a *descendant* — so an object that is not itself an edit is searched for one.
    func focusEdit(_ object: WasabiObject?) {
        let edit = object.flatMap { Self.editControl(in: $0) }
        guard edit !== focusedEdit else { return }
        focusedEdit = edit
        renderer.focusedEditID = edit?.stableID
        if edit != nil { window?.makeFirstResponder(self) }
        needsDisplay = true
    }

    private static func editControl(in object: WasabiObject) -> WasabiObject? {
        if object.typeName.lowercased().components(separatedBy: ":").last == "edit" { return object }
        var stack = object.children
        while let node = stack.popLast() {
            if node.typeName.lowercased().components(separatedBy: ":").last == "edit" { return node }
            stack.append(contentsOf: node.children)
        }
        return nil
    }

    /// Type into the focused `<edit>`, as Wasabi's native edit box does.
    ///
    /// Winamp's edit is a real child window and the skin never sees the keystrokes; it hears the three
    /// events instead — `onEnter` when Return is pressed (Big Bento runs its playlist search from it),
    /// `onAbort` on Escape (its own `Hidden Features.txt`: *"When in the search box, hit Escape to
    /// close it"*), and `onEditUpdate` per keystroke for a skin that filters as you type.
    ///
    /// Returns whether the key was consumed: everything printable is, so a letter typed into a search
    /// box can never also reach a skin accelerator or the playlist.
    private func typeIntoFocusedEdit(_ event: NSEvent) -> Bool {
        if ProcessInfo.processInfo.environment["WINAMP_MODERN_CALL_TRACE"] != nil {
            NSLog("EDIT key %d focused=%@", Int(event.keyCode), focusedEdit?.xmlID ?? "none")
        }
        guard let edit = focusedEdit else { return false }
        // ⌘-anything stays with the menus — Select All, Copy, Quit.
        if event.modifierFlags.contains(.command) { return false }
        var text = edit.attributes["text"] ?? ""
        switch event.keyCode {
        case 53:                                   // Escape
            focusEdit(nil)
            _ = try? scripts.dispatch(object: edit, event: "onabort")
            needsDisplay = true
            return true
        case 36, 76:                               // Return, Enter
            let reached = (try? scripts.dispatch(object: edit, event: "onenter")) ?? -1
            if ProcessInfo.processInfo.environment["WINAMP_MODERN_CALL_TRACE"] != nil {
                NSLog("EDIT onenter -> %@#%@ handlers=%d text=%@",
                      edit.typeName, edit.xmlID ?? "-", reached, text)
            }
            needsDisplay = true
            return true
        case 51:                                   // Delete
            guard !text.isEmpty else { return true }
            text.removeLast()
        default:
            guard let typed = event.characters, !typed.isEmpty,
                  typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else { return false }
            text += typed
        }
        _ = edit.setAttribute("text", value: text)
        _ = edit.setAttribute(WasabiTextMetrics.scriptTextKey, value: text)
        _ = try? scripts.dispatch(object: edit, event: "oneditupdate")
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        // The focused edit first, and unconditionally: a search box that lets `d` through to a skin
        // accelerator is not a text field.
        if typeIntoFocusedEdit(event) { return }
        let deleteKeys: Set<UInt16> = [51, 117]   // Delete, Forward Delete
        if playlistHasFocus, deleteKeys.contains(event.keyCode), let host = componentHost {
            let snapshot = host.playlistSnapshot()
            guard snapshot.selectedIndex >= 0, snapshot.selectedIndex < snapshot.rows.count else { return }
            host.playlistRemove(row: snapshot.selectedIndex)
            clampPlaylistScroll()
            needsDisplay = true
            return
        }
        if let accelerator = WinampModernKeyAccelerator.accelerator(for: event),
           scripts.dispatchKeyDown(accelerator) {
            // A handler may have moved a config attribute, a layout or a window; the same repaint the
            // click path takes after a script runs.
            needsDisplay = true
            return
        }
        // The visualization window's own keys (←/→, R, F, P, C), in the window that is showing the
        // visualization — after the skin has had its say, so a skin accelerator always wins (B20a).
        if let surface = hostedVisualizationSurface, surface.handleKeyDown(event) { return }
        super.keyDown(with: event)
    }

    /// Scroll the drawn playlist so a row is on screen — `PlEdit.showTrack(n)`. A no-op in a window
    /// whose skin embeds no playlist holder, which is most of them: the script still runs.
    func revealPlaylistRow(_ row: Int) {
        guard let host = componentHost,
              let holder = renderer.componentHolders().first(where: { $0.kind == .playlist }) else { return }
        renderer.revealPlaylistRow(row, rowCount: host.playlistSnapshot().rows.count, in: holder.frame,
                                   holder: holder.object)
        needsDisplay = true
    }

    /// Keep the scroll offset inside the list after a removal or a queue replacement, so a deleted
    /// tail does not leave the view scrolled past the end.
    func clampPlaylistScroll() {
        guard let host = componentHost,
              let holder = renderer.componentHolders().first(where: { $0.kind == .playlist }) else { return }
        renderer.scrollPlaylist(byRows: 0, rowCount: host.playlistSnapshot().rows.count,
                                in: holder.frame, holder: holder.object)
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

    /// Called at the top of every layout pass, before surfaces reconcile. The controller uses it to
    /// re-check embedded-page exclusivity: a skin script can open its tab on its own timer, *after*
    /// the reveal that forced a different page open, and a reveal-time check cannot see a page that
    /// does not exist yet.
    var willReconcileSurfaces: (() -> Void)?

    override func layout() {
        super.layout()
        willReconcileSurfaces?()
        // Creating and adding subviews from inside `draw` is a re-entrant view-hierarchy mutation
        // during a draw cycle; reconciliation belongs here, and drawing only draws.
        reconcileHostedSurfaces()
        let browsers = renderer.browserNodes()
        reconcileBrowserSurfaces(browsers)
        layoutHostedSubviews(browsers: browsers)
        cachedHolders = nil
    }

    /// Invalidate just one skin object's box (plus a pixel of slop for resampling at the edges).
    ///
    /// Falls back to the whole view when this scene does not contain the object — it belongs to
    /// another container's window, and only that window's view can place it.
    private func setNeedsDisplay(for object: WasabiObject) {
        guard !isTornDown else { return }
        // Cached: this runs on the animation path (per warped layer, per script tick), and resolving
        // geometry walks the scene.
        if let cached = objectRectCache[ObjectIdentifier(object)] {
            setNeedsDisplay(cached)
            return
        }
        guard let frame = renderer.resolvedGeometry(of: object)?.frame else {
            needsDisplay = true
            return
        }
        let rect = viewRect(fromSkin: frame).insetBy(dx: -2, dy: -2)
        objectRectCache[ObjectIdentifier(object)] = rect
        setNeedsDisplay(rect)
    }

    /// Per-object view rects for the targeted-repaint path, dropped with `animatingRectsCache`.
    private var objectRectCache: [ObjectIdentifier: NSRect] = [:]

    override func draw(_ dirtyRect: NSRect) {
        guard !isTornDown, let context = NSGraphicsContext.current?.cgContext else { return }
        // Only what is being repainted is cleared: a partial repaint (a meter that moved) must not
        // blank the rest of the window it is not going to draw again.
        context.clear(dirtyRect)
        context.saveGState()
        if skinScale != 1 { context.scaleBy(x: skinScale, y: skinScale) }
        renderer.draw(in: context, pressed: pressedObject?.stableID,
                      hovered: hoveredObject?.stableID)
        context.restoreGState()
    }

    /// Create a live surface for each library holder the scene now has, and **unmount** the ones whose
    /// holder has gone (a layout switch, a script hiding the tab).
    ///
    /// Unmount, not tear down. The bridge owns one surface of each kind per skin and re-serves that
    /// same instance when the holder comes back, so a terminal teardown here poisoned the cache: the
    /// second visit to a tab re-added an already-torn-down surface, and the third found the teardown
    /// latch already closed and never removed its view — cPro-Bento's library browser then stayed on
    /// screen over every other tab (Media Library → Playlist → Media Library → Playlist, reported
    /// 2026-08-21). The scene's own teardown still tears the surfaces down.
    private func reconcileHostedSurfaces() {
        guard !isTornDown else { return }
        let holders = renderer.componentHolders()
        var live: Set<WasabiObjectID> = []
        for holder in holders where holder.kind == .library {
            live.insert(holder.object.stableID)
            guard librarySurfaces[holder.object.stableID] == nil,
                  let surface = componentHost?.makeLibrarySurface() else { continue }
            librarySurfaces[holder.object.stableID] = surface
            surface.applyContentScale(libraryContentScale)
            surface.applyPalette(renderer.palette)
            addSubview(surface.view)
        }
        for (id, surface) in librarySurfaces where !live.contains(id) {
            surface.unmountFromHolder()
            librarySurfaces[id] = nil
        }

        var liveVideo: Set<WasabiObjectID> = []
        for holder in holders where holder.kind == .video {
            liveVideo.insert(holder.object.stableID)
            guard videoSurfaces[holder.object.stableID] == nil,
                  let surface = componentHost?.makeVideoSurface() else { continue }
            videoSurfaces[holder.object.stableID] = surface
            // `noshowcmdbar="1"` — the holder's own instruction that it draws the transport itself.
            surface.showsCommandBar =
                WinampModernVideoHolder.showsCommandBar(holderAttributes: holder.object.attributes)
            surface.applySkinScale(skinScale)
            surface.applyPalette(renderer.palette)
            addSubview(surface.view)
        }
        // Not every `{0000000A}` holder gets the engine: a letterbox strip is an analyzer's box, and
        // the bridge vends one surface per skin, so a second holder asking for it stole the picture
        // from the first. Everything not named here falls through to the renderer's analyzer (BB9).
        let engineHolderID = WinampModernVisualizationHolder.engineHolder(among: holders)
        var liveVis: Set<WasabiObjectID> = []
        for holder in holders where holder.kind == .visualization {
            guard holder.object.stableID == engineHolderID else { continue }
            liveVis.insert(holder.object.stableID)
            guard visualizationSurfaces[holder.object.stableID] == nil,
                  let surface = componentHost?.makeVisualizationSurface() else { continue }
            visualizationSurfaces[holder.object.stableID] = surface
            surface.applySkinScale(skinScale)
            surface.applyPalette(renderer.palette)
            addSubview(surface.view)
            // A surface the bridge handed back was stopped when its holder went away, and the only
            // other thing that starts an engine is a window becoming visible — which has already
            // happened for a holder that lives in a window that is on screen.
            surface.resumeRendering()
        }
        for (id, surface) in visualizationSurfaces where !liveVis.contains(id) {
            surface.unmountFromHolder()
            visualizationSurfaces[id] = nil
        }
        // What the renderer paints in the box behind them: bars are the skin's analyzer, and drawing
        // one under a live engine is a second visualization nobody can see costing a repaint a frame.
        renderer.hostedVisualizationHolders = liveVis

        for (id, surface) in videoSurfaces where !liveVideo.contains(id) {
            // Hands the picture back to its own window if a film is still running — the holder going
            // away is not a stop, and the one video view in the app must never be left orphaned in a
            // view that is about to leave the hierarchy.
            surface.unmountFromHolder()
            videoSurfaces[id] = nil
        }

        var liveHostedWindows: Set<WasabiObjectID> = []
        let hostedStyle = WinampModernSurfaceStyle(palette: renderer.palette)
        for holder in holders {
            guard case .hostWindow(let id) = holder.surfaceID else { continue }
            liveHostedWindows.insert(holder.object.stableID)
            guard hostedWindowSurfaces[holder.object.stableID] == nil,
                  let surface = componentHost?.makeHostedWindowSurface(id: id) else { continue }
            hostedWindowSurfaces[holder.object.stableID] = surface
            surface.applySkinScale(skinScale)
            surface.applyPalette(hostedStyle)
            addSubview(surface.view)
            if sceneIsVisible { surface.resume() }
        }
        for (id, surface) in hostedWindowSurfaces where !liveHostedWindows.contains(id) {
            surface.suspend()
            surface.unmountFromHolder()
            hostedWindowSurfaces[id] = nil
        }
        cachedHolders = holders
    }

    private var cachedHolders: [WinampModernComponentHolder]?

    /// Create/remove independent web surfaces for `<browser>` elements. They remain eagerly
    /// instantiated for hidden tab groups, but do not perform their initial load until visible.
    ///
    /// Surfaces are created eagerly for ALL browser elements (including hidden tab groups) so they
    /// are ready when a MAKI script toggles the parent visible. The view's `isHidden` tracks the
    /// element's scene visibility.
    private func reconcileBrowserSurfaces(_ browsers: [(object: WasabiObject, frame: CGRect)]) {
        guard !isTornDown else { return }
        var live: Set<WasabiObjectID> = []
        for browser in browsers {
            let id = browser.object.stableID
            live.insert(id)
            if browserSurfaces[id] == nil {
                let markupRequest = WinampModernBrowserRequest.initial(
                    attributes: browser.object.attributes,
                    sourceLogicalPath: browser.object.source.path)
                let request = pendingBrowserRequests.removeValue(forKey: id) ?? markupRequest
                guard let surface = componentHost?.makeBrowserSurface(initialRequest: request) else { continue }
                surface.applySkinScale(skinScale)
                addSubview(surface.view)
                browserSurfaces[id] = surface
            } else if browserSurfaces[id]?.view.superview !== self,
                      let view = browserSurfaces[id]?.view {
                addSubview(view)
            }
            let visible = renderer.isBrowserVisible(browser.object)
            browserSurfaces[id]?.setVisible(visible)
            if visible, let request = pendingBrowserRequests.removeValue(forKey: id) {
                browserSurfaces[id]?.navigate(request)
            }
        }
        var deleted: [WasabiObjectID] = []
        for (id, surface) in browserSurfaces where !live.contains(id) {
            if renderer.loadedSkin.runtime.graph.object(withID: id) == nil {
                surface.prepareForUITeardown()
                deleted.append(id)
            } else {
                // An inactive layout still owns this object. Unmount without destroying its WebKit
                // history; reconciliation reattaches the same surface if that layout returns.
                surface.setVisible(false)
                surface.unmountFromHolder()
            }
        }
        for id in deleted { browserSurfaces[id] = nil }
    }

    /// Route object-scoped MAKI navigation to this scene. A request before first layout is buffered;
    /// a request for an object owned by another container returns false so the controller can ask
    /// that container's view instead.
    @discardableResult
    func navigateBrowser(objectID: WasabiObjectID, address: String) -> Bool {
        guard !isTornDown,
              let object = renderer.loadedSkin.runtime.graph.object(withID: objectID),
              owns(object), WasabiSceneRenderer.isBrowserElement(object) else { return false }
        let request = WinampModernBrowserRequest(address: address,
                                                 sourceLogicalPath: object.source.path)
        if let surface = browserSurfaces[objectID] { surface.navigate(request) }
        else {
            pendingBrowserRequests[objectID] = request
            needsLayout = true
        }
        return true
    }

    /// The `<browser>` in this scene a *global* request should land in — `System.navigateUrlBrowser`
    /// and the `browser_search` / `browser_navigate` actions name no object at all (B40).
    ///
    /// **A visible one wins.** A skin keeps its reader in a tab that starts hidden and often ships a
    /// second browser besides (cPro-Bento's `SC:UpdateSystem` update-check widget is one), so the box
    /// the user can actually see is the one they asked to fill. With none visible the first is taken
    /// and its surface holds the request until its tab is opened — the same buffering an early
    /// `onScriptLoaded` navigation already gets.
    func globalBrowserTarget() -> (object: WasabiObject, isVisible: Bool)? {
        guard !isTornDown else { return nil }
        let nodes = renderer.browserNodes()
        if let visible = nodes.first(where: { renderer.isBrowserVisible($0.object) }) {
            return (visible.object, true)
        }
        return nodes.first.map { ($0.object, false) }
    }

    /// The video surface in this scene, if the skin's holder made one. The window layer needs it to
    /// hand the picture over before showing the skin's video window, and to size that window from
    /// the stream's own dimensions for `VID_1X` / `VID_2X`.
    ///
    /// **The biggest visible box wins.** A skin can hold the same component in several places at
    /// once — cPro-Bento's video lives in its tab, in the mini view above the playlist column *and*
    /// in the drawer — and a dictionary's first value is whichever the hash gave up, so the picture
    /// landed in a different box between runs of the same build. The largest is the one the user
    /// asked to see: the small ones are strips the skin leaves open beside it.
    var hostedVideoSurface: WinampModernVideoSurface? {
        let holders = renderer.componentHolders()
            .filter { $0.kind == .video && videoSurfaces[$0.object.stableID] != nil }
            .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
        if let best = holders.first { return videoSurfaces[best.object.stableID] }
        return videoSurfaces.values.first
    }

    /// The visualization surface in this scene, if the skin's AVS holder made one. The host actions
    /// (`VIS_NEXT`, `VIS_CFG`) and the Visualizations menu reach the running engine through it.
    var hostedVisualizationSurface: WinampModernVisualizationSurface? { visualizationSurfaces.values.first }

    /// The video holder's frame in skin pixels, for the sizing arithmetic `VID_1X` / `VID_2X` do:
    /// the window grows by the difference between the box the skin drew and the box the stream wants.
    var videoHolderFrame: CGRect? {
        renderer.componentHolders().first { $0.kind == .video }?.frame
    }

    /// Position live host surfaces at their skin-provided holder frames, converting from top-left
    /// skin coordinates to the view's bottom-left ones. Positioning only — nothing is created here.
    private func layoutHostedSubviews(browsers: [(object: WasabiObject, frame: CGRect)]) {
        guard !isTornDown else { return }
        let holders = cachedHolders ?? renderer.componentHolders()
        for holder in holders where holder.kind == .library {
            guard let surface = librarySurfaces[holder.object.stableID] else { continue }
            surface.view.frame = viewRect(fromSkin: holder.frame)
        }
        for holder in holders where holder.kind == .visualization {
            guard let surface = visualizationSurfaces[holder.object.stableID] else { continue }
            surface.view.frame = viewRect(fromSkin: holder.frame)
        }
        for holder in holders where holder.kind == .video {
            guard let surface = videoSurfaces[holder.object.stableID] else { continue }
            surface.view.frame = viewRect(fromSkin: holder.frame)
            // The picture is a child window parked on that box, and a child window follows its
            // parent's moves but not a resize of the box inside it.
            surface.updateOutputPlacement()
        }
        for holder in holders {
            guard case .hostWindow = holder.surfaceID,
                  let surface = hostedWindowSurfaces[holder.object.stableID] else { continue }
            surface.view.frame = viewRect(fromSkin: holder.frame)
        }
        for browser in browsers {
            guard let surface = browserSurfaces[browser.object.stableID] else { continue }
            let parentFrame = renderer.resolvedGeometry(of: browser.object)?.parent
            let frame = Self.browserSurfaceFrame(browserFrame: browser.frame,
                                                 browserID: browser.object.xmlID,
                                                 parentID: browser.object.parent?.xmlID,
                                                 parentFrame: parentFrame)
            surface.view.frame = viewRect(fromSkin: frame)
        }
    }

    /// Big Bento Modern's four variants inherit one reader which draws a 38px Winamp browser
    /// toolbar above `browserpro.browser`. NullPlayer supplies its own working address/navigation
    /// chrome inside the WebKit surface, so leaving that skin row exposed creates the duplicate,
    /// inert toolbar reported in BB25. Replace the exact shared reader structure's whole parent;
    /// other skins keep the browser rectangle they authored.
    static func browserSurfaceFrame(browserFrame: CGRect, browserID: String?, parentID: String?,
                                    parentFrame: CGRect?) -> CGRect {
        guard browserID?.caseInsensitiveCompare("browserpro.browser") == .orderedSame,
              parentID?.caseInsensitiveCompare("centro.browser") == .orderedSame,
              let parentFrame else { return browserFrame }
        return parentFrame
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
        let point = skinPoint(convert(event.locationInWindow, from: nil))
        // The thinger's caption names whichever icon the pointer is over, which is Winamp's own
        // behaviour and the only way a one-icon-wide bucket (Lobe's is 40×25) can be read at all.
        // Before the identity guard below: moving between two icons of the same bucket never changes
        // the hovered *object*.
        if renderer.focusComponentBucketIcon(at: point) { needsDisplay = true }
        let next = renderer.object(at: point)
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

    #if DEBUG
    /// Drive a left click at a skin point without a mouse — the app-side counterpart of the
    /// harness's `WINAMP_MODERN_RENDER_CLICK`, reached through `WINAMP_MODERN_DEBUG_CLICK`.
    ///
    /// The harness renders containers standalone and owns no windows, so a defect that lives in the
    /// *window* layer is invisible to it: Defix's playlist button measured as one clean toggle in
    /// `RENDER_CLICK` while opening and shutting the window on every press in the app. This replays
    /// exactly what `mouseUp` does, so the window layer is in the picture. Pair it with
    /// `WINAMP_MODERN_CALL_TRACE=1`, which is what turns the click into a readable chain.
    func debugClick(atSkinPoint point: CGPoint) {
        guard let object = renderer.object(at: point) else {
            NSLog("WinampModern debug click: nothing at %@", "\(point)")
            return
        }
        NSLog("WinampModern debug click: %@#%@", object.typeName, object.xmlID ?? "-")
        pressedObject = object
        dispatch(object: object, event: "onleftbuttondown", point: point)
        dispatch(object: object, event: "onleftbuttonup", point: point)
        _ = try? scripts.dispatch(object: object, event: "onleftclick")
        performAction(for: object)
        pressedObject = nil
        needsDisplay = true
        logHolders(tag: "debug click")
    }

    /// `WINAMP_MODERN_DEBUG_HOLDERS=1` — after every click: the component holders the scene actually
    /// has, and the live host subviews still in the hierarchy. A subview whose holder is gone is the
    /// tab-overlap bug as a *live* view; a holder gone with no subview left is a stale-pixel bug.
    func logHolders(tag: String) {
        guard ProcessInfo.processInfo.environment["WINAMP_MODERN_DEBUG_HOLDERS"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            let holders = self.renderer.componentHolders()
                .map { holder -> String in
                    // The holder's own id does not say which *group* it is: Big Bento declares the
                    // same `<component id="vis">` in a mini group and a full-width one, so the chain
                    // with each node's `visible` is what tells them apart — and names whoever left a
                    // `visible="0"` group open.
                    var chain: [String] = []
                    var node: WasabiObject? = holder.object.parent
                    var depth = 0
                    while let current = node, depth < 32 {
                        chain.append("\(current.xmlID ?? current.typeName)=\(current.attributes["visible"] ?? "-")")
                        node = current.parent
                        depth += 1
                    }
                    return "\(holder.kind.rawValue)#\(holder.object.xmlID ?? "-")\(holder.frame)"
                        + "<\(chain.joined(separator: "<"))"
                }
                .joined(separator: " | ")
            let subs = self.subviews
                .map { "\(type(of: $0))\($0.frame)hidden=\($0.isHidden ? 1 : 0)" }
                .joined(separator: " | ")
            NSLog("WinampModern HOLDERS after %@: lib=%d brw=%d vid=%d vis=%d holders=[%@] subviews=[%@]",
                  tag, self.librarySurfaces.count, self.browserSurfaces.count, self.videoSurfaces.count,
                  self.visualizationSurfaces.count, holders, subs)
        }
    }

    #endif

    override func mouseDown(with event: NSEvent) {
        // Before anything else this click might do: a transient popup elsewhere goes away, which is
        // what `autoclose="1"` means and the only way a chromeless one can be dismissed.
        didClickInWindow?(containerID)
        let point = skinPoint(convert(event.locationInWindow, from: nil))
        // A splitter's grab strip spans the full height of its frame, which means it crosses whatever
        // the skin has laid over that column — cPro's tab strip runs straight through the 8px seam.
        // So the divider only claims the click when nothing that outranks it is under it: a control
        // the user can actually see always wins. An invisible mousetrap and a bare window-drag surface
        // do not, or Big Bento's full-window `player.resizer.disable` layer makes its splitter
        // undraggable while the cursor promises otherwise — see `objectOverridingDivider` (BB21).
        if renderer.objectOverridingDivider(at: point) == nil,
           let divider = renderer.frameDivider(at: point) {
            draggedDivider = divider
            return
        }
        if let holder = renderer.componentHolder(at: point) {
            switch holder.kind {
            case .playlist:
                if let row = renderer.playlistRow(at: point, in: holder.frame, holder: holder.object) {
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
            case .video:
                // A filled video box is a live subview and `hitTest` already gave it the click; this
                // is the empty one (no output to lend yet), and a click on a black box does nothing.
                return
            case .visualization:
                // The GL view passes every click through (`hitTest` returns nil), so a left click on
                // a live engine is this view's to answer — and there is nothing to answer with. A
                // right click gets the controls, in `rightMouseDown`.
                return
            case .library, .other:
                return
            }
        }
        // A colour-theme list: click a row to pick it out, double-click to apply it. Winamp-faithful —
        // the skin's own `Switch` button is what a single click is *waiting* for — and the same code
        // serves every window this view class backs, so mmd3's `ctsbig`, corneramp's `colorthemes`
        // window and a drawer in the player are all one path.
        if let list = renderer.colorThemeList(at: point),
           let row = renderer.colorThemeListRow(at: point, in: list.object) {
            renderer.selectColorThemeRow(row, in: list.object)
            if event.clickCount >= 2, let name = renderer.selectedColorTheme(in: list.object) {
                applyColorTheme(name)
            }
            needsDisplay = true
            return
        }
        // A `<list>` a script filled — Big Bento's playlist search results. A click selects the row
        // (which is what `getFirstItemSelected` reads back), a double-click is the skin's own
        // `onDoubleClick`, which is how its search jumps to the track.
        if let list = renderer.guiList(at: point), let row = renderer.guiListRow(at: point, in: list) {
            WasabiGuiList.setSelection([row], on: list)
            // `onDoubleClick(item)` — one argument, the row, counted off the single store at Big
            // Bento's handler entry. It is how its search result opens the track it names.
            if event.clickCount >= 2 {
                _ = try? scripts.dispatch(object: list, event: "ondoubleclick",
                                          arguments: [.integer(Int32(row))])
            }
            needsDisplay = true
            return
        }
        // Winamp's thinger: clicking an icon in a `<componentbucket>` opens that component (B34).
        // Answered here rather than through `performAction`, as the playlist rows and the colour-theme
        // list above are, because the bucket carries no `action=` — the widget is Winamp's, and the
        // skin ships only the box.
        if let hit = renderer.componentBucketIcon(at: point) {
            renderer.componentBucket.focus(hit.index)
            routeComponentToggle(hit.icon.kind)
            needsDisplay = true
            return
        }
        guard let object = renderer.object(at: point) else { return }
        pressedObject = object
        dispatch(object: object, event: "onleftbuttondown", point: point)
        // A skin puts real commands on a double-click: cPro's beat display cycles its animation from
        // `mouseTrap.onLeftButtonDblClk`, and a tab's own dblclk suppresses the drag-to-reorder.
        if event.clickCount == 2 {
            dispatch(object: object, event: "onleftbuttondblclk", point: point)
        }
        updateSlider(object, point: point)
        // Focus follows the click, after the handlers: a skin shows its search box *from* the click
        // that opens it (Big Bento's `pl.search.edit.rect`), so the `<edit>` is only under the pointer
        // once those have run. A click that lands anywhere else gives the keyboard back.
        focusEdit(renderer.editControl(at: point))
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
            // the grab strip itself is somewhere else now, and the skin's own scripts want to know:
            // cPro re-aligns its tab strip and swaps its side-view buttons from `onResize`.
            dispatchResizeIfChanged()
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
        if let draggedDivider {
            // Where the user let go is the position that outlives the session (B44).
            renderer.persistFramePosition(of: draggedDivider)
            self.draggedDivider = nil
            return
        }
        if pressedEQHolder != nil { pressedEQHolder = nil; needsDisplay = true; return }
        let releasedOver = renderer.object(at: point)
        // The drag session is closed **before** any action runs. A titlebar mousetrap is both a drag
        // handle and a `dblclickaction="SWITCH;shade"` control, so its double-click ends in a layout
        // switch that resizes the window — and doing that inside an open drag session hands the
        // docking code a window that moved under it.
        if isDraggingWindow, let window { WindowManager.shared.windowDidFinishDragging(window) }
        isDraggingWindow = false
        if let pressedObject {
            dispatch(object: pressedObject, event: "onleftbuttonup", point: point)
            if releasedOver === pressedObject {
                _ = try? scripts.dispatch(object: pressedObject, event: "onleftclick")
                performAction(for: pressedObject)
                // The *second* click carries its own command in Wasabi, and for most objects that
                // carry one it is the only command they have: a titlebar mousetrap's
                // `dblclickaction="SWITCH;shade"`, a song title's `TRACKINFO`. It runs after the
                // normal click's action, as it does in Winamp — the two are independent attributes.
                if event.clickCount >= 2 { performClickAction(.double, for: pressedObject) }
            }
        }
        pressedObject = nil
        needsDisplay = true
        #if DEBUG
        logHolders(tag: "mouseUp")
        #endif
    }

    /// Wasabi's right button is a *pair* of events, and a skin is free to use either. Defix puts its
    /// whole "what does this button open" menu on `onRightButtonDown` — four handlers, one per round
    /// PL/EQ/ML/VD button, each building Video / Playlist Editor / Media Library / Equalizer /
    /// Visualization / Explorer window with `popAtMouse` and writing the pick to `MainBtn1..4`. The
    /// view used to send only `onrightbuttonup`, so all four menus were unreachable while the skin,
    /// the popup presenter and the script all worked. Nothing here decides *which* event a skin
    /// listens on; both are sent, as Winamp sends them.
    override func rightMouseDown(with event: NSEvent) {
        let point = skinPoint(convert(event.locationInWindow, from: nil))
        // A live visualization box answers for itself: the engine choice, the preset controls and the
        // host's Visualizations menu, at the pointer. The GL view passes its clicks through, so this
        // is the only place that right click can be caught (B20a).
        if let holder = renderer.componentHolder(at: point), holder.kind == .visualization,
           let surface = visualizationSurfaces[holder.object.stableID] {
            popUpMenu(surface.buildMenu(), from: nil, atMouse: true)
            return
        }
        guard let object = renderer.object(at: point) else { return }
        rightPressedObject = object
        dispatch(object: object, event: "onrightbuttondown", point: point)
        needsDisplay = true
    }

    override func rightMouseUp(with event: NSEvent) {
        let point = skinPoint(convert(event.locationInWindow, from: nil))
        let releasedOver = renderer.object(at: point)
        // The up goes to whatever the *down* claimed, mirroring the left button: `popAtMouse` runs
        // its own tracking loop inside the down handler, so by the time the up arrives the pointer is
        // wherever the user dismissed the menu, which is usually not over the button any more.
        let object = rightPressedObject ?? releasedOver
        rightPressedObject = nil
        guard let object else { return }
        dispatch(object: object, event: "onrightbuttonup", point: point)
        // `onRightClick` takes no arguments (a handler that pops two off an empty stack underflows),
        // and like the left one only fires when press and release agree on the target.
        if releasedOver === object {
            _ = try? scripts.dispatch(object: object, event: "onrightclick")
            performClickAction(.right, for: object)
        }
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        let point = skinPoint(convert(event.locationInWindow, from: nil))
        let delta = event.deltaY > 0 ? -1 : (event.deltaY < 0 ? 1 : 0)
        // The renderer has no scrollbar support, so the wheel is the *only* way down a colour-theme
        // list — and mmd3's has 82 rows.
        if let list = renderer.colorThemeList(at: point) {
            guard delta != 0 else { return }
            renderer.scrollColorThemeList(byRows: delta, in: list.object)
            needsDisplay = true
            return
        }
        // A script-filled `<list>` — the playlist search results. Same reason as the colour-theme
        // list above: the renderer draws no scrollbar, so the wheel is the only way down it.
        if let list = renderer.guiList(at: point) {
            guard delta != 0 else { return }
            renderer.scrollGuiList(byRows: delta, in: list)
            needsDisplay = true
            return
        }
        if let holder = renderer.componentHolder(at: point), holder.kind == .playlist,
           let rowCount = componentHost?.playlistSnapshot().rows.count {
            guard delta != 0 else { return }
            renderer.scrollPlaylist(byRows: delta, rowCount: rowCount, in: holder.frame,
                                    holder: holder.object)
            needsDisplay = true
            return
        }
        // Everything else the wheel can reach belongs to the skin, and it asks for it on the
        // **layout** rather than on a control: all 84 `onMouseWheel*` bindings across the five corpus
        // skins that declare them land on `layout#normal` or `layout#shade`, and each script decides
        // whether the turn was meant for it with `isMouseOverRect()`. Big Bento Modern declares
        // `config_vscrollbars` nine times over — once per settings page — so nine handlers run per
        // notch and eight of them correctly do nothing. Without this dispatch the settings pages had
        // no working scroll at all and anything past the fold was unreachable.
        guard delta != 0 else {
            super.scrollWheel(with: event)
            return
        }
        let handlers = (try? scripts.dispatch(object: renderer.layout,
                                              event: delta < 0 ? "onmousewheelup" : "onmousewheeldown",
                                              arguments: [.integer(1), .integer(3)])) ?? 0
        guard handlers > 0 else {
            super.scrollWheel(with: event)
            return
        }
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

    func updateTrackInfo() {
        // `onTitleChange` is per *track*, not per redraw: `beat.m` resets its running VU maximum from
        // it, so firing it on every info refresh would keep rescaling the beat animation mid-song.
        let title = host.trackDisplayTitle
        if title != lastPostedTitle {
            lastPostedTitle = title
            _ = try? scripts.dispatchSystem(event: "ontitlechange", arguments: [.string(title)])
        }
        needsDisplay = true
    }

    /// Ten times a second, for as long as a track plays.
    ///
    /// It used to end in `needsDisplay = true`, which is a **whole-window** repaint at the audio
    /// engine's clock rate — 19.3 ms of Retina bitmap drawing, ten times a second, on the same main
    /// thread the skin's 30 Hz animation is trying to use. That single line silently defeated every
    /// targeted repaint Phase 28 added, and it is the measured cause of the choppy cassette: the
    /// reels' own script was stepping evenly all along (`WINAMP_MODERN_RENDER_FX_SPIN`), the frames
    /// were not arriving evenly. Only what a clock actually moves is invalidated now; anything a
    /// *script* moves in response to `onPostedPosition` still comes back through
    /// `objectRepaintRequested` and names its own rect.
    func updateTime(current: TimeInterval, duration: TimeInterval) {
        if duration > 0 {
            let posted = Int32(max(0, min(255, current / duration * 255)))
            for object in renderer.loadedSkin.runtime.graph.objects(xmlID: "HiddenSeek") {
                _ = try? scripts.dispatch(object: object, event: "onpostedposition", arguments: [.integer(posted)])
            }
        }
        let rects = timeDependentRects()
        // An *empty* set means this scene has nothing the renderer draws from the clock, which is a
        // real answer and not a classification failure: `display="time"`, a `seek` slider and a seek
        // progress bar are the only things it draws from `host.currentTime`. A readout a *script*
        // maintains (a bitmap-font clock filled with `setText`) repaints through `graphDidMutate`
        // when the script writes it, which is the moment it actually changes.
        guard rects.count <= 24 else {
            needsDisplay = true
            return
        }
        for rect in rects { setNeedsDisplay(rect) }
    }

    /// The boxes of everything whose drawing follows the playback clock: an elapsed-time readout, a
    /// seek slider's thumb, a seek progress bar. Cached with the other rect scans.
    func timeDependentRects() -> [NSRect] {
        if let timeRectsCache { return timeRectsCache }
        let rects = renderer.sceneNodes().compactMap { node -> NSRect? in
            let object = node.object
            let type = object.typeName.lowercased()
            let display = object.attributes["display"]?.lowercased()
            let action = object.attributes["action"]?.lowercased()
            let follows: Bool
            switch type {
            case "text", "songticker": follows = display == "time"
            case "slider": follows = action == "seek"
            // A `progressgrid` with no action of its own takes its value from the slider it is
            // paired with, so it has to be treated as a possible seek bar.
            case "progressgrid": follows = action == "seek" || action == nil
            default: follows = false
            }
            guard follows else { return nil }
            return viewRect(fromSkin: node.frame).insetBy(dx: -2, dy: -2)
        }
        timeRectsCache = rects
        return rects
    }

    private var timeRectsCache: [NSRect]?

    func updatePlaybackState() {
        let state = host.playbackState
        // Play/pause/stop artwork and the shuffle/repeat/EQ toggles are read from the *host*, not
        // from the graph, so the renderer's memoized scene cannot see them change on its own.
        renderer.invalidateSceneCache()
        if state != lastPlaybackState {
            // Winamp reports the *transition*, not the level, and a skin acts differently on each:
            // ClassicPro's `beat.m` restarts its VU timer with a fresh running maximum on `onPlay` but
            // resumes the existing one on `onResume`, and stops it on `onPause`. Sending `onPlay` for a
            // resume (the previous behaviour) rescaled the animation every time the user unpaused, and
            // a pause was reported as nothing at all.
            switch (lastPlaybackState, state) {
            case (.paused, .playing): _ = try? scripts.dispatchSystem(event: "onresume")
            case (_, .playing): _ = try? scripts.dispatchSystem(event: "onplay")
            case (.playing, .paused): _ = try? scripts.dispatchSystem(event: "onpause")
            case (_, .stopped): _ = try? scripts.dispatchSystem(event: "onstop")
            default: break
            }
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
        // An equalizer change made outside the skin — a preset, the menu bar, the classic EQ window,
        // a restored session — reaches the scripts on the same beat, and only when it moved.
        scripts.refreshEqualizerState()
        for object in renderer.loadedSkin.runtime.graph.objects(xmlID: "HiddenVolume") {
            _ = try? scripts.dispatch(object: object, event: "onpostedposition",
                                      arguments: [.integer(postedVolume)])
        }
        needsDisplay = true
    }

    func updateSpectrum(_ levels: [Float]) {
        host.spectrumLevels = levels
        lastSpectrumArrival = CACurrentMediaTime()
        startVisualizationClock()
    }

    /// **The visualization's own 60 Hz clock, because the audio's rate is not a frame rate.**
    ///
    /// The boxes used to repaint only when a spectrum notification arrived, which sounds like the
    /// right beat and is not: `AudioEngine` taps `mixerNode` with a 2048-frame buffer, so a
    /// notification lands about every **46 ms — 21 fps**, and everything in a `<vis>` moved in 21
    /// steps a second however fast the display was. The bar and cap falloff are per *second*
    /// (`WasabiVisStyle`), so with frames of their own they animate the whole way down instead of
    /// stepping; and the oscilloscope has a genuinely new 576-sample chunk every 13 ms to show
    /// (`WinampModernWaveformTap` queues them and plays them out in real time), which no amount of
    /// repainting at 21 fps could ever reveal.
    ///
    /// Nothing here smooths, averages or levels the signal — that would buy motion by destroying the
    /// detail the scope exists to show. It draws more of the frames the audio already contains.
    ///
    /// Only the visualization boxes are invalidated: a full repaint at this rate costs Defix 19.3 ms
    /// a frame at Retina scale, and Big Bento Modern shows **six** boxes once its player pane is wide
    /// enough — the case (BB21) that made a repaint-per-notification stall the main thread. The clock
    /// runs only while there is something to show and stops itself once the decay is finished, so an
    /// idle player pays nothing.
    private func startVisualizationClock() {
        guard !isTornDown, visualizationClock == nil, !visualizationRects().isEmpty else { return }
        let timer = Timer(timeInterval: visualizationClockInterval, repeats: true) { [weak self] _ in
            self?.visualizationTick()
        }
        // `.common`, for the animation timer's reason: a tracking loop (a menu, a window drag) must
        // not freeze the visualization.
        RunLoop.main.add(timer, forMode: .common)
        visualizationClock = timer
        // Paint the first frame now rather than a clock tick later: this is the moment audio started
        // (or came back), and waiting up to 33 ms to acknowledge it is a visible hesitation. Not a
        // full `visualizationTick`, which would re-enter this on the rate check.
        invalidateVisualizationRects(visualizationRects())
    }

    /// **As fast as the box has new content, and no faster.** A repaint of the vis rects measured
    /// ~4 ms on Big Bento Modern, so the difference between these two rates is about 15% of a core
    /// against 4% — worth spending only where it shows.
    ///
    /// An **oscilloscope** has a genuinely new 576-sample chunk every 13 ms, so it gets the full
    /// 60 Hz; below that the trace visibly steps. An **analyzer** — which is most skins — is fed by
    /// the FFT, and `AudioEngine` taps `mixerNode` with a 2048-frame buffer, so its bands only change
    /// about 21 times a second. Frames past 30 Hz there animate nothing but the falloff between two
    /// identical sets of bars, which is not a difference anyone can see.
    private var visualizationClockInterval: CFTimeInterval {
        renderer.visualizationNeedsWaveform ? 1.0 / 60 : 1.0 / 30
    }

    private func visualizationTick() {
        guard !isTornDown else { return }
        let rects = visualizationRects()
        guard !rects.isEmpty else { return stopVisualizationClock() }
        // A skin can switch modes under the clock (its own menu, `VIS_NEXT`, a script), and the rate
        // follows the mode.
        if let clock = visualizationClock,
           abs(clock.timeInterval - visualizationClockInterval) > 0.001 {
            stopVisualizationClock()
            startVisualizationClock()
        }
        // Nothing to paint for a window nobody can see — behind another window, on another Space, or
        // miniaturised. The timer keeps running (it costs ~0.5%) so the idle check below still
        // retires it, but the repaints, which are the actual cost, stop.
        let isVisible = window?.occlusionState.contains(.visible) ?? true
        if isVisible { invalidateVisualizationRects(rects) }
        // Stop once the audio has been quiet long enough for the scope to have flattened and no bar
        // or cap is still falling. Until then the clock is what paints the decay out — and while
        // occluded there are no draws, so there is nothing to wait for.
        guard CACurrentMediaTime() - lastSpectrumArrival > Self.visualizationIdleTimeout,
              !isVisible || !renderer.hasDecayingVisualizationState else { return }
        stopVisualizationClock()
    }

    private func stopVisualizationClock() {
        visualizationClock?.invalidate()
        visualizationClock = nil
    }

    private func invalidateVisualizationRects(_ rects: [NSRect]) {
        guard rects.count <= 24 else {
            needsDisplay = true
            return
        }
        for rect in rects { setNeedsDisplay(rect) }
    }

    /// **What tells the boxes the audio went quiet.**
    ///
    /// Nothing posts a "zero": the taps simply stop when playback pauses, stops, ends or moves to a
    /// cast device, so `spectrumLevels` keeps whatever the music left in it and the analyzer would
    /// redraw those same bars forever, however fast the clock above runs.
    /// `updatePlaybackState` fires one `needsDisplay` at the transition — ~150 ms *before* either
    /// decay has finished — and it does not fire at all for a cast.
    ///
    /// So the host's level meter, the one tap that runs for **every** `.wal` skin, reports the
    /// transition (`WinampModernLevelMeter.onSilence`, on the main thread, once), and this zeroes the
    /// input. The clock then paints the fall out at the skin's own `falloff` and stops itself when
    /// nothing is left above the floor.
    func beginVisualizationSilenceDecay() {
        guard !visualizationRects().isEmpty else { return }
        // Zeroed, not emptied: an empty spectrum means "no input" and the analyzer draws nothing at
        // all, which reads as the bars vanishing rather than falling.
        if !host.spectrumLevels.isEmpty {
            host.spectrumLevels = [Float](repeating: 0, count: host.spectrumLevels.count)
        }
        startVisualizationClock()
    }

    /// How long after the last spectrum the clock may stop — past the tap's own silence timeout, so
    /// the scope's flat line is certain to have been painted at least once.
    private static let visualizationIdleTimeout: CFTimeInterval = 0.5
    private var visualizationClock: Timer?
    private var lastSpectrumArrival: CFTimeInterval = 0

    /// The boxes of every `<vis>`/`<eqvis>` in this scene, cached with the other animation rects.
    private func visualizationRects() -> [NSRect] {
        if let visualizationRectsCache { return visualizationRectsCache }
        let rects = renderer.sceneNodes().compactMap { node -> NSRect? in
            guard ["vis", "eqvis"].contains(node.object.typeName.lowercased()) else { return nil }
            return viewRect(fromSkin: node.frame).insetBy(dx: -2, dy: -2)
        }
        visualizationRectsCache = rects
        return rects
    }

    private var visualizationRectsCache: [NSRect]?

    func teardown() {
        guard !isTornDown else { return }
        renderer.themeCoordinator.removeObserver(self)
        if let tracking { removeTrackingArea(tracking) }
        tracking = nil
        animationTimer?.invalidate()
        animationTimer = nil
        stopVisualizationClock()
        pressedObject = nil
        pressedEQHolder = nil
        draggedDivider = nil
        hoveredObject = nil
        for surface in librarySurfaces.values { surface.prepareForUITeardown() }
        librarySurfaces.removeAll()
        for surface in videoSurfaces.values { surface.prepareForUITeardown() }
        videoSurfaces.removeAll()
        for surface in visualizationSurfaces.values { surface.prepareForUITeardown() }
        visualizationSurfaces.removeAll()
        for surface in hostedWindowSurfaces.values { surface.prepareForUITeardown() }
        hostedWindowSurfaces.removeAll()
        for surface in browserSurfaces.values { surface.prepareForUITeardown() }
        browserSurfaces.removeAll()
        pendingBrowserRequests.removeAll()
        // Auxiliary container views share the skin's single script runtime and host; only the
        // main (script-driving) view tears those down. Every view tears down its own renderer.
        if drivesScripts { scripts.teardown() } else { scripts.removeAuxiliaryRepaintSink(owner: self) }
        renderer.teardown()
        canvasSizeDidChange = nil
        componentWindowToggleRequested = nil
        containerWindowToggleRequested = nil
        surfaceToggleRequested = nil
        webNavigationRequested = nil
        isTornDown = true
    }

    private func skinPoint(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x / skinScale, y: (bounds.height - point.y) / skinScale)
    }

    /// Where the pointer is right now in *this* view's skin pixels, or `nil` when the view is not in a
    /// window. Every container window answers for its own scene, which is what `isMouseOverRect` needs
    /// from the window that actually renders the receiver.
    func currentMousePositionInSkinPixels() -> CGPoint? {
        guard let window else { return nil }
        return skinPoint(convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
    }

    /// A mouse event's x/y are in the receiver's **parent** coordinate space — the same space
    /// `getLeft()`/`getTop()` answer in, and *not* the window-wide space `System.getMousePos*` uses.
    ///
    /// Three skins in the corpus say so independently. Lobe's seek dial and volume knob read
    /// `map.getValue(x - anim.getLeft(), y - anim.getTop())`, and Rika's do the same: that only
    /// indexes a 48×35 map if `x` is measured from the same origin as `getLeft()`. mmd3's knob is the
    /// proof from the other side — it opens with `getMousePosX() - x + knob.getLeft() +
    /// knob.getWidth()/2`, which is the object's centre in *cursor* space only if `getMousePosX() -
    /// x` is the parent's origin. Sending the canvas point made Lobe's dial sample (213, 26) of a
    /// 48-wide map, which is 0 everywhere, so every drag seeked to zero and every knob turn set the
    /// volume to nothing.
    private func dispatch(object: WasabiObject, event: String, point: CGPoint) {
        let local = pointInParentSpace(of: object, canvasPoint: point)
        _ = try? scripts.dispatch(object: object, event: event,
                                  arguments: [.integer(Int32(local.x)), .integer(Int32(local.y))])
    }

    /// The canvas point in `object`'s parent's coordinates. Unchanged for anything whose parent sits
    /// at the origin, which is why this was invisible until a skin put a knob inside a placed group.
    func pointInParentSpace(of object: WasabiObject, canvasPoint: CGPoint) -> CGPoint {
        guard let parent = renderer.resolvedGeometry(of: object)?.parent else { return canvasPoint }
        return CGPoint(x: canvasPoint.x - parent.minX, y: canvasPoint.y - parent.minY)
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
        // `move="1"` is the skin *affirmatively* naming a drag handle, and it says so on far more
        // than groups: across the 30 installed skins it appears 981 times on 14 different element
        // types — `rect` 233, `text` 66, `grid` 36 — and honouring it only on `<group>` (421) left
        // the other 560 declarations doing nothing. Big Bento Modern is the measured case: its
        // titlebar is `<grid … move="1">` over a `<rect id="vic_mover" move="1" fitparent="1">`, so
        // the window could only be dragged by whatever bare background happened to be topmost under
        // the pointer — which is why it went undraggable after a trip through shade mode and back.
        //
        // A control is excluded even when it says `move="1"`: a button that both acts and drags
        // would swallow its own click, and the skins that declare it (17 of the 981) are relying on
        // Winamp's press-and-hold distinction, which this hit test does not model.
        if object.attributes["move"] == "1", !Self.controlTypes.contains(type) { return true }
        // The layout is the window's own background. A skin that paints the whole frame there and
        // hangs only controls off it (T800) otherwise has nothing to drag by at all.
        if type == "layout" { return true }
        // A bare group has no artwork of its own, so a click reaching one landed on the background it
        // covers, and without `move="1"` above the skin has not offered it as a handle.
        if type == "group" { return false }
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

    /// Element types whose press belongs to the control, not to the window — `move="1"` on one of
    /// these is not taken as a drag handle.
    private static let controlTypes: Set<String> = [
        "button", "togglebutton", "nstatesbutton", "wasabi:button", "slider", "menu", "list",
        "component", "browser", "edit", "editbox"
    ]

    /// Show a script-built menu at the mouse and answer the command id the user picked (0 = nothing).
    ///
    /// `popAtMouse` is synchronous in MAKI — the script reads the answer on the next line — and
    /// `NSMenu.popUp` runs its own tracking loop, so the call blocks here exactly as the skin
    /// expects. The menu is built from the resolved tree, so submenus nest.
    /// `point` is `popAtXY`'s: window-client space, top-left origin, unscaled — the inverse of
    /// `skinPoint`. `nil` is `popAtMouse`.
    private func presentScriptPopup(_ items: [WinampModernPopupMenuItem], at point: CGPoint?) -> Int32 {
        let target = ScriptPopupTarget()
        let menu = build(popupMenu: items, target: target)
        guard menu.numberOfItems > 0 else { return 0 }
        let location: NSPoint?
        if let point {
            location = NSPoint(x: point.x * skinScale, y: bounds.height - point.y * skinScale)
        } else {
            location = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        }
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
        let vertical = WasabiSceneRenderer.isVerticalOrientation(object)
        let value = vertical ? 1 - (point.y - frame.minY) / frame.height
                             : (point.x - frame.minX) / frame.width
        let normalized = max(0, min(1, value))
        if let eq = WinampModernEQAction.decode(action: object.attributes["action"],
                                                parameter: object.attributes["param"]),
           let componentHost {
            // ±12 dB through the host, which is the same value the thumb is drawn from.
            eq.apply(normalized: normalized, to: componentHost)
            // …and the skin hears its own equalizer move, as it does in Winamp. Before `notePosition`
            // below, so the drag's own position is the last thing written to this slider.
            scripts.refreshEqualizerState()
        } else if WinampModernPanAction.matches(action: object.attributes["action"]) {
            // The balance slider. The engine's unit is −1…+1 and the slider's is 0…1; both
            // conversions live in `WinampModernPanAction` so the thumb cannot disagree with the drag.
            host.balance = WinampModernPanAction.balance(normalized: normalized)
        } else if object.attributes["action"] == nil,
                  scripts.setConfigAttribute(of: object, normalized: normalized) {
            // A slider bound to a `cfgattrib` carries no action — the binding *is* what it drives.
            // mmd3's `sCrossfade` (`high="20"`) is the crossfade length, and four other skins spell
            // the same control the same way.
            WindowManager.shared.refreshWinampModernSurfaces()
        } else {
            switch object.attributes["action"]?.lowercased() {
            case "seek": host.seek(to: host.duration * normalized)
            case "volume": host.volume = normalized
            default: break
            }
        }
        // Wasabi moves the object's own position on a drag and tells the skin about it, whatever the
        // slider drives. Skins hang their only feedback off that: multipass's balance and crossfade
        // sliders print "Balance: Left +40%" on the song ticker from `onSetPosition` and nowhere else.
        notePosition(normalized, on: object)
        needsDisplay = true
    }

    /// Record a slider's position and dispatch `onSetPosition` — but only when the integer position
    /// actually moved, which is what Wasabi does and what keeps a pair of sliders that write each
    /// other's position from their own handler out of an endless round trip.
    ///
    /// The position is in the slider's **own** `low…high` unit, which defaults to Winamp's 0…255 and
    /// so is unchanged for every action-driven slider in the corpus. It matters for the two kinds
    /// that declare a range: a crossfade slider is cut `high="20"` and mmd3 prints the argument
    /// straight into its readout as seconds, and Anaheim's brightness slider is `low="-4096"
    /// high="4096"` and was being handed a 0…255 that meant nothing to the script reading it.
    private func notePosition(_ normalized: CGFloat, on object: WasabiObject) {
        let low = Double(object.attributes["low"] ?? "0") ?? 0
        let high = Double(object.attributes["high"] ?? "255") ?? 255
        let position = Int32((low + Double(normalized) * (high - low)).rounded())
        guard object.attributes["value"] != String(position) else { return }
        _ = object.setAttribute("value", value: String(position))
        _ = try? scripts.dispatch(object: object, event: "onsetposition",
                                  arguments: [.integer(position)])
    }

    private func performAction(for object: WasabiObject) {
        // A togglebutton flips itself first, then tells the skin — the whole of some skins' UI hangs
        // off that notification (multipass's bottom drawer opens from `onToggle` and nowhere else).
        // It runs alongside whatever `action=` the button also carries, as it does in Wasabi.
        if scripts.toggleActivation(of: object) { needsDisplay = true }
        let action = object.attributes["action"]
        let parameter = object.attributes["param"]
        // The object comes with the action now: `action_target=` is an attribute of the *button*, and
        // it is the only thing that says which list a colour-theme switch acts on.
        performAction(action: action, parameter: parameter, object: object)
        if action == nil {
            // A `cfgattrib`-bound control carries no `action`: the binding *is* what it does. Defix's
            // whole settings window is built this way, so without it every switch in that window
            // moved nothing.
            // Shuffle, repeat and crossfade reach the host from *inside* this call:
            // `WinampModernConfigBridge` makes their attributes the host's own state, so for a bound
            // button the write **is** the toggle, and the `xmlID` route below must not run as well —
            // doing both flipped each of them twice and left the skin's lamp disagreeing with the
            // engine.
            if scripts.toggleConfigAttribute(of: object) {
                WindowManager.shared.refreshWinampModernSurfaces()
            } else {
                // A skin that draws the buttons and binds nothing (boom names its artwork
                // `Player.shuffle-Selected` and declares no `cfgattrib` at all) still has to work,
                // and its id is the only thing that says what the button is for. The renderer reads
                // the same host flags back through the matching `id ==` case in `resolvedBitmapID`.
                switch object.xmlID?.lowercased() {
                case "shuffle": host.shuffleEnabled.toggle()
                case "repeat": host.repeatEnabled.toggle()
                default: break
                }
            }
        }
        updatePlaybackState()
    }

    /// Perform the command a skin hung on a double- or right-click, if it hung one there.
    ///
    /// Separate from `performAction(for:)` on purpose: these attributes do **not** flip a
    /// togglebutton and do not fall through to the `cfgattrib` binding — they are a second, plain
    /// command on the same object, and a mousetrap layer that carries one usually carries nothing
    /// else at all.
    private func performClickAction(_ gesture: WasabiClickGesture, for object: WasabiObject) {
        guard let resolved = WasabiClickAction.resolve(object, gesture: gesture) else { return }
        performAction(action: resolved.action, parameter: resolved.parameter, object: object)
    }

    private func performAction(action rawAction: String?, parameter rawParameter: String?, object: WasabiObject? = nil) {
        // `ACTION;PARAM` is the other way a skin writes a parameter — mmd3, ZDL and winampmodern566
        // spell every one of their layout switches that way, and winampmodern566 also writes
        // `action="SWITCHTO;optionsgroup.misc"`. An explicit `param=` still wins.
        let action: String?
        let parameter: String?
        if let rawAction {
            (action, parameter) = WasabiClickAction.split(action: rawAction, parameter: rawParameter)
        } else {
            (action, parameter) = (nil, rawParameter)
        }
        switch action?.uppercased() {
        case "PLAY": host.play()
        case "PAUSE": host.pause()
        case "STOP": host.stop()
        case "PREV": host.previous()
        case "NEXT": host.next()
        case "EJECT": host.openFiles()
        case "SWITCH":
            // The user clicked a control that switches layout — a titlebar shade button, a
            // `dblclickaction="SWITCH;shade"` mousetrap. That is a decision about how they want this
            // window, so it outlives the session; a script's own `switchToLayout` does not (B44a).
            if let parameter, activateLayout(id: parameter) { renderer.persistActiveLayout() }
        // The window commands every skin puts on its titlebar. T800 draws all three (minimize,
        // shade-switch, close) as 4×5px buttons on the machine's chest. The fallbacks are for a view
        // with no controller over it (tests): never `performClose`, which a borderless window ignores.
        case "MINIMIZE":
            if let minimizeRequested { minimizeRequested() } else { window?.miniaturize(nil) }
        case "CLOSE":
            if let closeRequested { closeRequested() } else { window?.close() }
        case "TOGGLE":
            // `TOGGLE`'s parameter is a component (`Eq`, a GUID) **or one of the skin's own container
            // ids** — Winamp toggles whichever window that names. Resolving only components left
            // every container-addressed button dead, and Defix's `CONF` button is exactly one
            // (`action="TOGGLE" param="Config"`): the whole configurator — the 31 backgrounds, the
            // nine display styles, the songticker scrolling mode — was unreachable, so a preference
            // the skin ships switched off could never be switched on.
            // Winamp's preferences dialog, Colour Themes page. multipass's "open in preferences"
            // button is `action="TOGGLE"` with this GUID as its parameter; we have no preferences
            // dialog, and the popup below is the same list that dialog would show.
            if parameter?.uppercased().contains(Self.colorThemePreferencesGUID) == true {
                showColorThemeMenu()
            } else if let kind = WinampModernComponentRegistry.kind(for: parameter) {
                routeComponentToggle(kind)
            } else if let parameter, !parameter.isEmpty {
                _ = containerWindowToggleRequested?(parameter)
            }
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
                // Switching auto-EQ on applies the track's genre preset, which moves every band.
                scripts.refreshEqualizerState()
                needsDisplay = true
            }
        case "EQ_PREAMP", "EQ_BAND":
            // A *button* carrying a band action (a reset, a nudge) has no position to read; the
            // slider path owns the values. Inert rather than wrong.
            break
        // The three colour-theme host actions. `_switch` applies whatever its list has picked out;
        // `_next`/`_previous` step the applied theme directly and drag the list's selection along, so
        // a skin that ships only the arrows (multipass) still cycles its 58 themes.
        case "COLORTHEMES_SWITCH":
            if let object, let list = renderer.colorThemeList(forAction: object),
               let name = renderer.selectedColorTheme(in: list) {
                applyColorTheme(name)
            } else {
                // No list to read: Defix's switch button names none and its skin ships none, and
                // multipass's names a group that is never instantiated. In Winamp both would land in
                // the preferences dialog; the popup is that list.
                showColorThemeMenu()
            }
        case "COLORTHEMES_NEXT": stepColorTheme(by: 1)
        case "COLORTHEMES_PREVIOUS": stepColorTheme(by: -1)
        case "MENU":
            if parameter?.lowercased() == "presets" { showEqualizerPresetMenu() }
            // A bare `MENU` is the main menu, same as the button below.
            else if Self.opensMainMenu(action: action, parameter: parameter) { showMainMenu(from: object) }
        // Winamp's **main menu** — the "≡" at the top-left of a skin's title bar (`SYSMENU`) and the
        // same menu on a window's control button (`CONTROLMENU`). Measured demand: SYSMENU in
        // multipass, CornerAmp Redux, Overdrive_2, winampmodern566 and ZDL; CONTROLMENU in multipass,
        // mmd3, Overdrive_2 and ZDL — and every one of them was dead, which reads as "the button in
        // the corner does nothing" because that is exactly what it did.
        //
        // Winamp's menu there is Play file / Preferences / Skins / Exit and the window list.
        // NullPlayer's own context menu is that menu — the one every other window in the app shows on
        // right-click — so the button opens it rather than a second, thinner imitation.
        case "SYSMENU", "CONTROLMENU":
            showMainMenu(from: object)
        // Winamp's two song-title commands, both reached through `dblclickaction=`/`rightclickaction=`
        // rather than `action=`: the file-info dialog and the track's own context menu. Here they are
        // the same File Info sheet and the same track menu the playlist windows already show, so the
        // three routes to a track's details cannot drift apart.
        // The skin's *internal* web route, and the other half of B40. A skin that offers "Web Reader"
        // against "default browser" does not call a second navigation method for it — it addresses
        // its own reader group with `sendAction(…)` (Big Bento's lyrics finder and its YouTube search
        // both do, from `fileinfo_lyrics_finder.maki`), and `sendAction` already reaches here with
        // the action and its parameter.
        //
        // **The two actions carry different things** and must not be read alike: `browser_navigate`
        // hands over a finished `https://…`, while `browser_search` hands over the bare terms and
        // leaves the engine to the reader.
        case "BROWSER_NAVIGATE":
            if let address = parameter, !address.isEmpty {
                webNavigationRequested?(.internalBrowser, address)
            }
        case "BROWSER_SEARCH":
            if let terms = parameter, !terms.isEmpty {
                webNavigationRequested?(.internalBrowserSearch, terms)
            }
        case "TRACKINFO":
            showTrackInfo()
        case "TRACKMENU":
            showTrackMenu(from: object)
        // (`opensMainMenu` is the same decision, spelled once, for a test that cannot open a menu.)
        //
        // Winamp's four host-action families — the visualization, the playlist editor, the video
        // window and the component bucket — are decoded and routed in
        // `WinampModernHostActionMenus.swift` (backlog B5): 108 declarations across 11 of the 17
        // measured skins, each of them a button whose click used to end here.
        default:
            if let action, let hostAction = WinampModernHostAction(action: action) {
                performHostAction(hostAction, object: object)
            }
        }
    }

    /// Whether this markup action asks for the host's main menu. Internal so the routing can be
    /// tested: presenting a menu runs AppKit's own tracking loop, which a headless test cannot enter.
    static func opensMainMenu(action: String?, parameter: String?) -> Bool {
        switch action?.uppercased() {
        case "SYSMENU", "CONTROLMENU": return true
        case "MENU": return parameter?.isEmpty != false
        default: return false
        }
    }

    /// The host's context menu, dropped under the button that asked for it (the mouse if that button
    /// has no resolved frame — a script can raise this from anywhere).
    private func showMainMenu(from object: WasabiObject?) {
        let menu = ContextMenuBuilder.buildMenu()
        popUpMenu(menu, from: object)
    }

    /// Drop a menu under the object that asked for it, or at the pointer.
    ///
    /// `atMouse` is what a right-click menu wants — Winamp pops it where the click was, and a
    /// song-title ticker is wide enough that its top-left corner is nowhere near the pointer.
    func popUpMenu(_ menu: NSMenu, from object: WasabiObject?, atMouse: Bool = false) {
        guard menu.numberOfItems > 0 else { return }
        let location: NSPoint
        if let frame = object.flatMap({ renderer.frame(of: $0) }), !atMouse {
            location = NSPoint(x: frame.minX * skinScale,
                               y: bounds.height - frame.maxY * skinScale)
        } else if let window {
            location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        } else {
            location = .zero
        }
        menu.popUp(positioning: nil, at: location, in: self)
    }

    /// Winamp's **File Info** for the playing track — what a song title's `dblclickaction="TRACKINFO"`
    /// asks for, in six of the seventeen measured skins.
    ///
    /// Presented as a *sheet*, never `runModal()`: this action is reachable from a script
    /// (`sendAction("TRACKINFO")`), and a skin is untrusted input — a modal run loop it can enter at
    /// will is a hang the user cannot dismiss the app out of. A sheet needs a window, so with none
    /// (the tests' detached view) it is simply inert.
    private func showTrackInfo() {
        guard let window, let track = WindowManager.shared.audioEngine.currentTrack else { return }
        let alert = NSAlert()
        alert.messageText = track.displayTitle
        var lines = ["Artist: \(track.artist ?? "Unknown")",
                     "Album: \(track.album ?? "Unknown")",
                     "Duration: \(track.formattedDuration)"]
        // The stream figures the skin's own readouts show, when the engine has them.
        if host.bitrateKbps > 0 { lines.append("Bitrate: \(host.bitrateKbps) kbps") }
        if host.sampleRateHz > 0 { lines.append("Sample rate: \(host.sampleRateHz) Hz") }
        if host.channelCount > 0 { lines.append("Channels: \(host.channelCount)") }
        lines.append(track.url.isFileURL ? "Path: \(track.url.path)" : "URL: \(track.url.absoluteString)")
        alert.informativeText = lines.joined(separator: "\n")
        alert.beginSheetModal(for: window)
    }

    /// The track's own context menu — `rightclickaction="TRACKMENU"`, five of the seventeen skins.
    ///
    /// Winamp's is a menu *about the playing track*, not the player's main menu (which is what
    /// `SYSMENU` already opens), so this is the same three commands the playlist windows offer for a
    /// row, aimed at whatever is playing. With no track the items are shown disabled rather than the
    /// menu suppressed: a right-click that produces nothing at all reads as a dead control.
    private func showTrackMenu(from object: WasabiObject?) {
        let track = WindowManager.shared.audioEngine.currentTrack
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: track?.displayTitle ?? "No Track", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        for (name, selector) in [("File Info...", #selector(showTrackInfoFromMenu(_:))),
                                 ("Copy Title", #selector(copyTrackTitleFromMenu(_:)))] {
            let item = NSMenuItem(title: name, action: selector, keyEquivalent: "")
            item.target = self
            item.isEnabled = track != nil
            menu.addItem(item)
        }
        let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(revealTrackFromMenu(_:)),
                                keyEquivalent: "")
        reveal.target = self
        reveal.isEnabled = track?.url.isFileURL == true
        menu.addItem(reveal)
        popUpMenu(menu, from: object, atMouse: true)
    }

    @objc private func showTrackInfoFromMenu(_ sender: Any?) { showTrackInfo() }

    @objc private func copyTrackTitleFromMenu(_ sender: Any?) {
        guard let track = WindowManager.shared.audioEngine.currentTrack else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(track.displayTitle, forType: .string)
    }

    @objc private func revealTrackFromMenu(_ sender: Any?) {
        guard let track = WindowManager.shared.audioEngine.currentTrack, track.url.isFileURL else { return }
        host.revealInFinder(track.url.path)
    }

    /// Winamp's preferences page for colour themes. A skin that opens it is asking for the same list
    /// the popup below shows.
    private static let colorThemePreferencesGUID = "53DE6284-7E88-4C62-9F93-22ED68E6A024"

    /// Apply a theme and repaint.
    ///
    /// `activateTheme` answers `false` for a theme that is *already* applied, and the coordinator
    /// broadcasts nothing in that case — so the repaint cannot be left to the broadcast, or clicking
    /// the row you are already wearing would leave the list's selection unpainted.
    func applyColorTheme(_ name: String) {
        _ = renderer.activateTheme(name)
        renderer.syncColorThemeLists()
        WindowManager.shared.refreshWinampModernSurfaces()
        needsDisplay = true
    }

    /// Step the applied theme, wrapping at both ends — the skin's own next/previous buttons.
    private func stepColorTheme(by delta: Int) {
        let names = renderer.colorThemeNames
        guard !names.isEmpty else { return }
        let current = renderer.activeColorThemeIndex ?? 0
        let next = ((current + delta) % names.count + names.count) % names.count
        applyColorTheme(names[next])
    }

    /// The host's own colour-theme list, as a popup.
    ///
    /// The route for every skin that defines themes and ships no list to pick them from: Defix's
    /// `colorthemes_switch` button, multipass's unresolvable target, and the preferences GUID above.
    /// The applied theme is checked, so the popup answers "which one am I wearing?" as well.
    private func showColorThemeMenu() {
        let names = renderer.colorThemeNames
        guard names.count > 1, let event = NSApp.currentEvent else { return }
        let menu = NSMenu(title: "Color Themes")
        let active = renderer.themes.activeTheme
        for name in names {
            let item = NSMenuItem(title: name, action: #selector(applyColorThemeFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = name
            if name.caseInsensitiveCompare(active) == .orderedSame { item.state = .on }
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func applyColorThemeFromMenu(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        applyColorTheme(name)
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
        // A preset moves ten bands and the preamp at once; the skin hears every one of them.
        scripts.refreshEqualizerState()
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
