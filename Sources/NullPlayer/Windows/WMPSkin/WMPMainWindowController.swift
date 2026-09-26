import AppKit
import NullPlayerCore
import UniformTypeIdentifiers

/// A `.wmz` skin's window. Borderless, and therefore refused the keyboard **and the mouse-moved
/// stream** by AppKit's default `canBecomeKey`.
///
/// Found on 2026-09-08 driving Melvin: clicks dispatched and hover did nothing, because
/// `WMPMainView`'s tracking area is `.activeInKeyWindow` and this window was never key — so
/// `mouseMoved`, `mouseEntered` and `mouseExited` were never delivered at all. That silenced hover
/// *artwork* (every `hoverImage` in the corpus) as well as the authored `onMouseOver`/`onMouseOut`
/// handlers, and `keyDown` with them. The `.wal` engine found the same thing in its Phase 43 and
/// carries the same two-line override (`WinampModernSkinWindow`); the modern-skin windows carry it
/// as `BorderlessWindow`.
final class WMPSkinWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// AppKit keeps even a borderless window's frame below the visible top, and the frame includes
    /// every transparent row a skin keeps for its drawers. Clamp the first *drawn* row instead
    /// (`WMPMainView.transparentTopInset`), so a skin whose closed drawers leave the top empty
    /// can be dragged up to the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        var constrained = super.constrainFrameRect(frameRect, to: screen)
        guard let inset = (contentView as? WMPMainView)?.transparentTopInset, inset > 0,
              let visible = (screen ?? self.screen)?.visibleFrame,
              frameRect.maxY > constrained.maxY else { return constrained }
        constrained.origin.y = min(frameRect.origin.y, visible.maxY + inset - frameRect.height)
        return constrained
    }

    /// Whether the drag in flight is the edge band's, taken before AppKit could see it.
    private var isResizingFromEdgeBand = false

    /// Whether the gesture in flight is a press the band refused — a *control* drawn inside the
    /// window's edge, forwarded to the view by hand because `super.sendEvent` would not have
    /// delivered it at all. See the `leftMouseDown` case below.
    private var isForwardingEdgePress = false

    /// **The window edge is ours, and it has to be taken before AppKit takes it (W227).**
    ///
    /// `WMPMainView` has carried an edge band since W193, and for a real drag it has never once
    /// run. A `.wmz` window is `[.borderless, .resizable]`, and `.resizable` is enough: AppKit
    /// claims a press near the frame edge in `super.sendEvent` and runs its own modal resize loop,
    /// so the view is sent no `mouseDown` and the window is then resized entirely outside the
    /// skin. Measured 2026-09-18 on `Compact` — a `leftMouseDown` at the left edge arrives here,
    /// nothing arrives at the view, no `leftMouseDragged` or `leftMouseUp` arrives at all, and the
    /// window grows by exactly the drag. A *click* on the same pixel does reach the view, which is
    /// why the band read as live and why W227 recorded `edge-band press` as this path's
    /// instrument: it only ever printed for gestures that resized nothing.
    ///
    /// Claiming the press here — and returning without `super` — puts the band back under the
    /// view's own rules: the skin's `minWidth`/`maxWidth` clamp, the anchored edge, the relayout,
    /// and the grip handler the skin wraps around its own resize. A control drawn against the
    /// window edge keeps every pixel it had — the band never claims a press that lands on one.
    ///
    /// **Declining the band is not enough: the whole margin has to be taken, or AppKit takes what
    /// is left of it (W235).** The rule above claims a press the *band* wants. A press inside the
    /// same margin that lands on a **control** — `NVIDIA`'s volume slider runs the full height of
    /// its window, three points inside the right edge — is declined by `claimsEdgeBandResize`, and
    /// declining it used to mean `super.sendEvent`, which is the one path this override exists to
    /// keep AppKit off. `-[NSWindow _handleMouseDownEvent:]` then reached `_resize:` and ran
    /// `-[NSWindow _resizeWithEvent:]`, **a modal tracking loop on the main thread**: the control
    /// was never sent the press, and a gesture that loop did not see the end of left the whole
    /// application wedged — no clicks, no repaints, a frozen visualizer, and a `sample` showing
    /// 2,279 of 2,293 samples blocked in `nextEventMatchingMask:` under `_resizeWithEvent:`.
    /// Reported as *"the window is not accessible, it is crashed"*, and it is the same press W227
    /// already proved AppKit will claim — only on the half this override was letting through.
    ///
    /// So the margin is taken whole and then routed: the band's press resizes, and a control's
    /// press is handed to the view by hand, with the drag and the release that follow it kept on
    /// the same path. `super` never sees the gesture, so AppKit has nothing to start a loop from.
    /// Outside the margin nothing changes — every press goes to `super` exactly as before.
    override func sendEvent(_ event: NSEvent) {
        guard let view = contentView as? WMPMainView else { return super.sendEvent(event) }
        // A press is proof no earlier drag is still running; see `discardStaleResize`.
        if event.type == .leftMouseDown { view.discardStaleResize() }
        switch event.type {
        case .leftMouseDown where view.claimsEdgeBandResize(at: event.locationInWindow):
            isResizingFromEdgeBand = view.beginEdgeBandResize(at: event.locationInWindow)
            if isResizingFromEdgeBand { return }
        case .leftMouseDown where view.isInsideResizeBand(at: event.locationInWindow):
            wmpResizeTrace("edge-margin press forwarded at \(event.locationInWindow) "
                + "clicks=\(event.clickCount)")
            // A control inside the margin. Forwarded rather than dropped: it is an ordinary press
            // on an ordinary control and must behave as one — the slider tracks, the button
            // dispatches — it simply cannot be allowed to reach AppKit's frame first.
            isForwardingEdgePress = true
            view.mouseDown(with: event)
            return
        case .leftMouseDragged where isResizingFromEdgeBand:
            view.continueWindowResize(); return
        case .leftMouseUp where isResizingFromEdgeBand:
            isResizingFromEdgeBand = false
            if view.endWindowResize() { view.onScriptResizeEnded?() }
            return
        // **The rest of a forwarded gesture stays forwarded.** `super.sendEvent` is what tracks
        // which view took a press and routes the drag and the release to it, and it never saw this
        // one — so a slider pressed inside the margin would take the press and then never move.
        case .leftMouseDragged where isForwardingEdgePress:
            view.mouseDragged(with: event); return
        case .leftMouseUp where isForwardingEdgePress:
            isForwardingEdgePress = false
            view.mouseUp(with: event)
            return
        default: break
        }
        super.sendEvent(event)
    }
}

final class WMPMainWindowController: NSWindowController, MainWindowProviding, NSWindowDelegate {
    static let unskinnedSize = NSSize(width: 440, height: 170)
    /// The two events raised on the pointer crossing a control's edge, dispatched only where the
    /// markup authored a handler for them. See `dispatchScriptEvent(name:targetID:…)`.
    static let hoverEvents: Set<String> = ["mouseover", "mouseout"]

    /// The events WMP raises with a mouse button behind them, so `event.button` is answered on
    /// those and absent on everything else (W121). A view timer and a host state change carry no
    /// button at all, and `digitaldj`'s `if (event.button != 1) return;` has to be able to tell
    /// those apart from a click of the wrong button — see `WMPJScriptEvent.button`.
    static let mouseEvents: Set<String> = ["mousedown", "mouseup", "click", "dblclick",
                                           "dragbegin", "dragend", "mousemove",
                                           "mouseover", "mouseout"]

    /// IE's left button, which is what WMP's `event.button` answers, or nil where no mouse raised
    /// the event. **Only the left button ever reaches a script event** — `WMPMainView` overrides
    /// `mouseDown` and not `rightMouseDown` — so the constant is honest rather than a guess.
    static func mouseButton(for event: String) -> Int? {
        mouseEvents.contains(event) ? 1 : nil
    }

    /// Where the pointer is, in the view's own skin-space top-left coordinates: WMP's
    /// `event.clientX`/`event.clientY`.
    ///
    /// **Answered on every transaction, not only a mouse one**, because WMP's `event` object is
    /// ambient rather than per-dispatch: `LostPlanet`'s `menuTicker()` is an `onTimer` that opens
    /// and closes its drop-down by testing the pointer against the menu's rectangle on every tick,
    /// so confining this to mouse events would leave that handler dead in a different way. Read
    /// live here rather than carried up from an `NSEvent` for the reason
    /// `currentEventModifiers` gives: the callbacks that raise these transactions have none.
    static func currentPointer(_ presentation: WMPViewPresentation) -> WMPPoint? {
        guard let view = presentation.mainView, let window = view.window,
              let scene = presentation.activeScene else { return nil }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return view.skinPoint(fromWindowPoint: windowPoint, sceneSize: scene.canvasSize)
    }

    private let importer: WMPSkinImporter
    private let host: any WMPHost
    /// **The effect selection is the one host property nothing else refreshes for.** Every other
    /// path into `refreshHostState` is a track, a clock tick, a transport action or a file open;
    /// choosing a visualization from NullPlayer's own menu goes through `WMPEffectSelection` and
    /// touches none of them. With a track playing the 10 Hz position tick hides that — the event
    /// lands within 100 ms and looks immediate — and with the player stopped the skin's
    /// `currentEffectType_onchange` would never be raised at all (W129).
    private var effectSelectionObserver: NSObjectProtocol?
    /// **The effects slot's settings belong to the skin that authored the slot.** The selection and
    /// the WMP-scoped Cava / vis_classic preferences are restored when a skin loads and captured
    /// whenever they change, against the skin that is showing. See `WMPVisualizationSettingsStore`.
    private lazy var visualizationSettings = WMPVisualizationSettingsStore(defaults: importer.defaults)
    /// Capture is driven off the defaults domain rather than off each menu item, because the Cava
    /// and vis_classic controls in the slot's menu write their own keys and offer no callback.
    private var visualizationSettingsObserver: NSObjectProtocol?
    private var isCapturingVisualizationSettings = false
    /// The skin a captured change belongs to. It is the skin that was showing when the change was
    /// made, not `importer.selectedSkinName` at the moment the notification is delivered: the
    /// defaults notification arrives on the main queue asynchronously, so a change made just before
    /// a skin switch would otherwise be filed against the skin being switched *to*. Nil until the
    /// first restore, so nothing is captured before anything has been put in place.
    private var visualizationSettingsSkin: String?
    /// The skin *session's* load — the archive, the candidate walk, the first present. Per-view work
    /// has its own task on the presentation it belongs to.
    private var loadTask: Task<Void, Never>?
    /// **The windowless view the skin keeps running alongside the player, and its clock.**
    ///
    /// 24 of the 180 corpus archives author a `controlView` that is never a window and poll it at
    /// 100 ms; their panel, minimize and close buttons do not call the host at all, they write a
    /// preference and let this view's `onTimer` read it back and act (W89). It outlives a view
    /// switch on purpose — it is the way back from the panel it opened — so only teardown and a
    /// skin reload stop it.
    private var dispatcherViewID: String?
    private var dispatcherTimerTask: Task<Void, Never>?
    /// The dispatcher's `onTimer` sources, resolved once. `handlers` walks the whole graph, and at
    /// the 100 ms this idiom is authored at that is ten walks a second for an answer the markup
    /// fixed before the skin loaded.
    private var dispatcherHandlers: [String] = []
    private var dispatcherVideoSnapshot: WMPVideoSnapshot?
    private var loadedSkin: WMPLoadedSkin?
    private var imageStore: WMPImageStore?
    /// Which surfaces the loaded skin provides itself (`WMPSkinSurfaces`). Empty while the
    /// app-authored unskinned player is up, which is what makes NullPlayer's playlist and equalizer
    /// available there.
    private(set) var skinSurfaces = WMPSkinSurfaces.empty
    /// **Whether a skin load is still on its way to the hosted-frame provider (W250).** Set when a
    /// load starts and cleared the moment the provider has been told what the skin lends — with a
    /// donor or with nothing. Deliberately *not* cleared on cancellation: a cancelled load is one a
    /// newer load replaced, and that newer load has already set this again.
    private(set) var isResolvingHostedFrames = false

    /// The colours NullPlayer's *own* windows are drawn in while this skin is presented — see
    /// `WMPSurfacePalette`. Nil whenever the app-authored unskinned player is up, which is what makes
    /// `WindowManager.hostedSurfaceStyle` nil there and sends those windows back to their own drawing.
    private(set) var currentSurfacePalette: WMPSurfacePalette?

    /// The skin's own window *shape* for those same windows, where it draws one — see
    /// `WMPHostedFrameTemplate`. The palette above is what a `.wmz` could always lend us; this is
    /// the eight-piece ring that 85 of the 180 corpus archives build their panels out of, rendered
    /// for whatever size each of our windows is open at.
    let hostedFrames = WMPHostedFrameProvider()
    private var scriptRuntime: WMPScriptRuntime?
    /// What the skin's `mediaCollection`/`playlistCollection` read, and the tracks behind it (W136).
    private let librarySource = WMPLibrarySource()
    private var libraryBuiltFor: ModernBrowserSource = .local
    /// The latest library play request; see `fetchLibraryDemands`.
    private var libraryPlayTicket = 0
    private var libraryObservers: [NSObjectProtocol] = []
    /// The in-flight fetch for WMP's built-in album-art images. It is cancelled on a track change
    /// and session teardown, so a slow server cannot replace a newer track's artwork.
    private var artworkLoadTask: Task<Void, Never>?
    private var artworkTrackID: UUID?
    private var lastScriptSnapshot: WMPHostSnapshot?
    private var unskinnedView: WMPUnskinnedMainView?
    /// **The player is held transparent until its first skin load settles.** `init` has to present
    /// the unskinned player so the window has content, but `showMainWindow` and the launch path
    /// order the window front straight after — and several callers do it through
    /// `window.makeKeyAndOrderFront` rather than `showWindow`, so the hold is on the window's alpha
    /// rather than on any one reveal. Without it the app-authored player showed for the one or two
    /// seconds a `.wmz` takes to load. Released by `releaseLaunchHold`: on the skin, on a failed or
    /// missing selection (which do want the unskinned player), or by the timeout, so a load that
    /// never returns cannot leave the app windowless. The same held-transparent state hosted
    /// windows use while they wait for their frame (W250).
    private var launchHoldTimeout: Task<Void, Never>?
    /// Opens of NullPlayer's fallback playlist/equalizer asked for during the launch hold, replayed
    /// when it ends — by then the skin has said whether it draws that surface itself, which 171 and
    /// 164 of the 180 corpus skins do. Opened at once, the fallback stood on screen beside the
    /// hidden player until `dismissWMPFallbackSurfacesTheSkinProvides` put it away.
    private var launchHoldDeferred: [() -> Void] = []

    /// Holds `open` until the launch hold ends; false when there is no hold, and the caller opens
    /// now.
    func deferUntilLaunchSettles(_ open: @escaping () -> Void) -> Bool {
        guard launchHoldTimeout != nil else { return false }
        launchHoldDeferred.append(open)
        return true
    }

    /// **The windows this skin has open, and the one bound to the app's own.**
    ///
    /// `theme.openView` opens an additional window in WMP and leaves the opener alone. Every field
    /// that used to be a singleton on this controller and is really per-window now lives on a
    /// `WMPViewPresentation`; this is where they are.
    private var materializer: WMPViewWindowMaterializer!
    /// A window being opened that has no presentation yet — the scene is built before the window is
    /// created, so its size is known when it is placed. Keyed by folded view id so a second
    /// `theme.openView` for the same panel while the first is still building is a no-op rather than
    /// a second window.
    private var pendingOpenTasks: [String: Task<Void, Never>] = [:]

    /// **One video surface for the whole session, lent to whichever window is showing the picture.**
    ///
    /// `WMPVideoSurface.update(in:…)` already re-parents the VLC child window to `view.window` on
    /// every tick, so moving it between windows needs an arbiter rather than new plumbing — and
    /// `Halo 2`'s `<VIDEO>` is in `videoView`, a window of its own. The `video reparented` /
    /// `video reordered above parent` traces in `skills/wmp-skin-guide/reference/rendering/video.md` § W102 are the check that this is not
    /// thrashing: they must fire once per incident, not continuously.
    private let videoSurface = WMPVideoSurface()

    /// **The spectrum consumer is ref-counted across windows, not a Bool.**
    ///
    /// `WMPMainView` reports whether *its* view hosts an `<EFFECTS>` rect. With one window that was
    /// the whole answer; with several, the player reporting `false` would switch the tap off under a
    /// visualisation panel that is still drawing. Identity of the reporting view, so a window that
    /// closes takes its own claim with it.
    private var spectrumConsumers: Set<ObjectIdentifier> = []

    /// The host's **UI Size** as a multiplier on every WMP window.
    ///
    /// A `.wmz` view is not resizable in the sense UI Size means: its size is authored, most of the
    /// corpus pins `WMPResizeLimits` to exactly it, and growing the window re-*lays out* the scene
    /// at the larger size (`renderCurrentSize`) rather than magnifying it — which for a fixed skin
    /// is refused outright by `windowWillResize`. So UI Size is kept out of skin space entirely:
    /// only the window frame and the rasterization scale carry it. `WMPMainView` already maps
    /// drawing, hit testing, cursor rects and widget frames through `bounds / canvasSize`, so input
    /// and the AppKit overlays follow the zoom with nothing further.
    private(set) var uiScale: CGFloat = 1
    private var pendingRestoredFrame: NSRect?
    private var pendingRestoredViewID: String?
    private(set) var lastLoadDiagnostic: String?

    /// How many windows one skin may have open at once. The covered-view stack this replaces was
    /// bounded at the same number, and `Halo 2` — the skin that found this row — opens six.
    static let maximumOpenViews = 8

    var availableViewIDs: [String] { loadedSkin?.views.map(\.id) ?? [] }

    /// The views this skin has open, player first.
    var openViewIDs: [String] { materializer?.openPresentations.map(\.viewID) ?? [] }
    /// The **player's** view. A panel in a window of its own is not the session's view (W96), and
    /// every caller of this — the restore path, the menu's checked state, the diagnostics — means
    /// the player.
    var selectedViewID: String? { materializer?.playerPresentation?.viewID }
    var hasCompatibilityReport: Bool { loadedSkin != nil }

    /// The player window's size in the skin's own pixels.
    private var skinSpaceSize: NSSize {
        materializer?.playerPresentation?.skinSpaceSize ?? Self.unskinnedSize
    }

    /// NVIDIA implements playlist and video as modes inside `mainView`, but its global close
    /// button still calls `view.close()`. In either embedded mode, close returns to audio mode.
    ///
    /// **This is the drawer exception in its purest form and it is deliberately untouched.** An
    /// in-place mode is a `<SUBVIEW>` of the presented view's own canvas; it never reaches
    /// `theme.openView` and it has no window of its own to close. The guard that used to read
    /// "nothing has been opened over the player" now reads "this *is* the player and it is the only
    /// window open", which is the same statement made in the new vocabulary.
    private func closeNVIDIAEmbeddedMode(_ presentation: WMPViewPresentation) -> Bool {
        guard importer.selectedSkinName?.caseInsensitiveCompare("NVIDIA") == .orderedSame,
              presentation.isPlayer, materializer.openPresentations.count == 1,
              let widgets = presentation.activeScene?.widgets,
              widgets.contains(where: { $0.kind == .playlist || $0.kind == .video })
        else { return false }
        dispatchScriptTransaction(presentation,
                                  WMPJScriptEvent(name: "hostRestoreMainLayout", targetID: nil,
                                                  handlers: ["theme.savePreference('videoItem','false');audioModeToggle()"]))
        return true
    }

    convenience init() {
        self.init(importer: WMPSkinImporter(), host: WMPAudioEngineHost(audioEngine: WindowManager.shared.audioEngine))
    }

    init(importer: WMPSkinImporter, host: (any WMPHost)? = nil) {
        self.importer = importer
        self.host = host ?? WMPAudioEngineHost(audioEngine: WindowManager.shared.audioEngine)
        let window = WMPSkinWindow(contentRect: NSRect(origin: .zero, size: Self.unskinnedSize),
                                   styleMask: [.borderless, .resizable, .miniaturizable],
                                   backing: .buffered, defer: false)
        super.init(window: window)
        materializer = WMPViewWindowMaterializer(controller: self, playerWindow: window)
        // A skin switch is staged against the windows that are open, at the sizes the border
        // layout will give them — both of which belong to `HostedWindowBorderLayout`.
        hostedFrames.openWindowTargets = { insets in
            WindowManager.shared.hostedWindowTargets(for: insets)
        }
        hostedFrames.hostedWindowsVisible = { WindowManager.shared.hasVisibleHostedWindows }
        effectSelectionObserver = NotificationCenter.default.addObserver(
            forName: WMPEffectSelection.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshHostState()
                self?.captureVisualizationSettings()
            }
        }
        visualizationSettingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: importer.defaults, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.captureVisualizationSettings() } }
        // The catalog is a copy of the browser's selected source (W136), so it is rebuilt when that
        // source changes, when a local rescan lands, and when a server finishes loading its
        // lists. `BrowserSource` has no notification of its own: the browser writes it to
        // defaults, and a defaults change is compared against the source last built.
        // Each notification rebuilds only when it is about the selected source: every server
        // announces its own preload, and rebuilding the Plex catalog because Emby finished
        // loading re-listed playlists and refreshed every window for nothing.
        let sources: [(Notification.Name, (ModernBrowserSource) -> Bool)] = [
            (MediaLibrary.libraryDidChangeNotification, { if case .local = $0 { true } else { false } }),
            (PlexManager.libraryContentDidPreloadNotification, { if case .plex = $0 { true } else { false } }),
            (SubsonicManager.libraryContentDidPreloadNotification, { if case .subsonic = $0 { true } else { false } }),
            (JellyfinManager.libraryContentDidPreloadNotification, { if case .jellyfin = $0 { true } else { false } }),
            (EmbyManager.libraryContentDidPreloadNotification, { if case .emby = $0 { true } else { false } }),
        ]
        for (name, concerns) in sources {
            libraryObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let runtime = self.scriptRuntime,
                          concerns(ModernBrowserSource.load() ?? .local) else { return }
                    Task { await self.refreshLibrary(runtime) }
                }
            })
        }
        libraryObservers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let runtime = self.scriptRuntime,
                      (ModernBrowserSource.load() ?? .local) != self.libraryBuiltFor else { return }
                Task { await self.refreshLibrary(runtime) }
            }
        })
        configureWindow()
        presentUnskinned(message: nil)
        window.alphaValue = 0
        launchHoldTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.releaseLaunchHold()
        }
        reloadSelectedSkin()
    }

    /// Ends the launch hold; see `launchHoldTimeout`. Idempotent — only the first call restores
    /// the alpha, so a later skin switch cannot undo a video surface's own alpha.
    private func releaseLaunchHold() {
        guard let timeout = launchHoldTimeout else { return }
        timeout.cancel()
        launchHoldTimeout = nil
        window?.alphaValue = 1
        let deferred = launchHoldDeferred
        launchHoldDeferred = []
        deferred.forEach { $0() }
    }

    required init?(coder: NSCoder) { nil }

    /// **One `<LISTBOX>` event at a time, in the order the user made them.** A click is a
    /// selection and its `selectedItem_onChange`; a double-click is `onDblClick`, which reads what
    /// the click set up — `WoW`'s `playSelPlaylist()` plays `playlist1.playlist`, which
    /// `getSelPlaylist()` assigns. Dispatched independently, the double-click's transaction could
    /// run first and play the playlist chosen before. Each event now waits for the previous one's
    /// transaction to finish, so fast clicking resolves in order.
    private func enqueueListEvent(_ presentation: WMPViewPresentation,
                                  _ dispatch: @escaping @MainActor () async -> Void) {
        let previous = presentation.listEventTail
        presentation.listEventTail = Task { [weak presentation] in
            await previous?.value
            await dispatch()
            // The handle `dispatchScriptEvent` just stored is this event's own transaction.
            await presentation?.scriptTask?.value
        }
    }

    /// Make a library playlist the current one and play it from `row` — WMP's
    /// `player.currentPlaylist = …` and a double-click in a `<PLAYLIST>` showing one (W136). The
    /// queue is replaced, not added to: the assignment names the whole playlist.
    private func playLibraryTracks(_ indices: [Int], from row: Int) {
        // A direct play supersedes any play still waiting on a fetch.
        libraryPlayTicket += 1
        let playables = librarySource.playables
        let tracks = indices.compactMap { playables.indices.contains($0) ? playables[$0] : nil }
        guard !tracks.isEmpty else { return }
        let engine = WindowManager.shared.audioEngine
        engine.setPlaylistTracks(tracks)
        engine.playTrack(at: max(0, min(tracks.count - 1, row)))
    }

    /// Hand the script runtime the library the browser's selected source holds (W136). `initial`
    /// is the skin's first load, which has no windows to refresh yet: its `onLoad` is still to run.
    private func refreshLibrary(_ runtime: WMPScriptRuntime, initial: Bool = false) async {
        libraryBuiltFor = ModernBrowserSource.load() ?? .local
        let playlistsChanged = await librarySource.rebuild()
        await runtime.setLibrary(librarySource.catalog)
        guard !initial else { return }
        await refreshLibraryViews(runtime, reloadFillers: playlistsChanged)
    }

    /// Fetch what a skin asked for that the catalog does not hold — a server playlist's tracks, an
    /// album, an artist — and let the windows showing it redraw (W136).
    private func fetchLibraryDemands(_ demands: Set<String>, viewID: String,
                                     event: WMPJScriptEvent?) async {
        guard let runtime = scriptRuntime else { return }
        var fetched = false
        var searchLanded = false
        for demand in demands.sorted() where !demand.hasPrefix("play:") {
            guard await librarySource.fetch(demand) else { continue }
            fetched = true
            if demand.hasPrefix("query:search:"),
               librarySource.catalog.queryResults[String(demand.dropFirst("query:".count))]?.isEmpty == false {
                searchLanded = true
            }
        }
        if fetched { await runtime.setLibrary(librarySource.catalog) }
        // A skin's search ran against an answer that was still on its way. Run the same event —
        // the Return in the search box, the click on its button — again now that the server's
        // results are in: this time `getAll()` answers with them and the skin's own loop fills
        // its results list. Once only: the second run finds the answer cached and asks for nothing.
        if searchLanded, let event, event.name != "load",
           let presentation = materializer.openPresentations.first(where: {
               $0.viewID.caseInsensitiveCompare(viewID) == .orderedSame }) {
            dispatchScriptTransaction(presentation, event)
        }
        // `player.currentPlaylist = <a playlist still loading>`: the assignment withheld its
        // `play()`, and this is where it happens instead — once, and only if the playlist has
        // tracks. A failed fetch plays nothing rather than the queue that was there before.
        //
        // **Only the latest request plays** (fast clicking): each pending play takes a ticket, and
        // a later request — or any change to the queue made some other way while this one was
        // loading — makes it stale, so a slow first fetch cannot land over a second choice.
        for demand in demands where demand.hasPrefix("play:") {
            let reference = String(demand.dropFirst("play:".count))
            guard let id = WMPObjectModel.libraryPlaylistID(inReference: reference) else { continue }
            libraryPlayTicket += 1
            let ticket = libraryPlayTicket
            let queueAtRequest = WindowManager.shared.audioEngine.playlist.map(\.url)
            if await librarySource.fetch("playlist:" + id) {
                await runtime.setLibrary(librarySource.catalog)
                fetched = true
            }
            guard ticket == libraryPlayTicket,
                  WindowManager.shared.audioEngine.playlist.map(\.url) == queueAtRequest else { continue }
            let catalog = librarySource.catalog
            guard let index = catalog.playlistIndex(id: id), catalog.playlists[index].loaded,
                  !catalog.playlists[index].tracks.isEmpty else { continue }
            await runtime.adoptCurrentLibraryPlaylist(reference)
            playLibraryTracks(catalog.playlists[index].tracks, from: 0)
        }
        if fetched { await refreshLibraryViews(runtime, reloadFillers: false) }
    }

    /// **A skin fills its chooser once, in `onLoad`**, from a library WMP always has ready. A
    /// server's lists arrive later and the source can change under an open skin, so a view whose
    /// `onLoad` read the library is loaded again when the playlist list changes — the same load it
    /// would have run had the library been there. Every other open view runs a transaction with
    /// no handlers, which is what redraws a pane whose playlist's tracks just arrived.
    ///
    /// **A skin that fills its chooser from a click refills it from `CdromMediaChange` (W274).**
    /// `NVIDIA` fills in `plModeToggle()`, not `onLoad`, so a reload never refills it and
    /// re-dispatching the click would toggle the mode back off. All nine `<LISTBOX>` chooser skins
    /// author `CdromMediaChange="onCdRomChange()"`, whose body is their refill — `fillListBox()`, or
    /// in `NVIDIA`'s case that when the list is showing and a reset of its `loadList` latch when
    /// it is not — so a changed playlist list raises it in every view that authors one and is not
    /// being loaded again anyway.
    ///
    /// **The view's own `onResize` runs in the same transaction, after the refill.** Eight of the
    /// nine size the list inside `fillListBox()`; `NVIDIA` does not — it sizes it in
    /// `plModeToggle()` and `onPlayerResize()` — so its refilled 1,850 rows stayed in the two-row
    /// box the previous source had left.
    private func refreshLibraryViews(_ runtime: WMPScriptRuntime, reloadFillers: Bool) async {
        let fillers = reloadFillers ? await runtime.viewsThatFillFromLibrary() : []
        for presentation in materializer.openPresentations {
            let reload = fillers.contains(WMPPath.fold(presentation.viewID))
            if reloadFillers, !reload, let skin = loadedSkin {
                let refill = Self.handlers(in: skin, event: "cdrommediachange", targetID: nil,
                                           viewID: presentation.viewID)
                if !refill.isEmpty {
                    let layout = Self.handlers(in: skin, event: "onResize", targetID: "view",
                                               viewID: presentation.viewID)
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["WMP_CLICK_TRACE"] == "1" {
                        NSLog("[wmp/dispatch] cdrommediachange view=%@ playlists=%d handlers=%d",
                              presentation.viewID, librarySource.catalog.playlists.count,
                              refill.count + layout.count)
                    }
                    #endif
                    dispatchScriptTransaction(presentation,
                        WMPJScriptEvent(name: "cdrommediachange", targetID: nil,
                                        handlers: refill + layout))
                    continue
                }
            }
            dispatchScriptEvent(presentation, name: reload ? "load" : "librarychange", targetID: nil)
        }
    }

    deinit {
        for observer in [effectSelectionObserver, visualizationSettingsObserver].compactMap({ $0 })
            + libraryObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func configureWindow() {
        guard let window else { return }
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.title = "NullPlayer — Windows Media Player"
        window.minSize = Self.unskinnedSize
        window.delegate = self
        window.center()
        window.setAccessibilityIdentifier("WMPMainWindow")
        window.setAccessibilityLabel("Windows Media Player Main Window")
    }

    /// Files the live effects-slot settings against the skin they were made in. Cheap enough to run
    /// on every defaults change: it reads ~12 keys and writes only when the record actually moved,
    /// which is also what stops the write from re-triggering this through `didChangeNotification`.
    private func captureVisualizationSettings() {
        guard let skin = visualizationSettingsSkin, !isCapturingVisualizationSettings else { return }
        isCapturingVisualizationSettings = true
        defer { isCapturingVisualizationSettings = false }
        visualizationSettings.capture(skin: skin,
                                      effect: WMPEffectSelection.shared.current.id,
                                      preset: WMPEffectSelection.shared.preset)
    }

    /// Puts the incoming skin's effect, preset and WMP-scoped Cava / vis_classic preferences in
    /// place before its scene — and therefore its `<EFFECTS>` surface — is built. The outgoing
    /// skin's pending change is flushed first, because the defaults notification that would have
    /// captured it may not have been delivered yet.
    private func restoreVisualizationSettings() {
        captureVisualizationSettings()
        let skin = importer.selectedSkinName ?? ""
        visualizationSettingsSkin = skin
        isCapturingVisualizationSettings = true
        let selection = visualizationSettings.restore(skin: skin)
        isCapturingVisualizationSettings = false
        WMPEffectSelection.shared.restore(effect: selection.effect, preset: selection.preset)
    }

    func reloadSelectedSkin() {
        restoreVisualizationSettings()
        // **A skin on its way is not a skin that lends nothing (W250).** The frame provider is only
        // configured once the player has *rendered*, so between here and there it has no template
        // and answers every hosted window "I lend no frame" — which is indistinguishable from the
        // settled truth for a skin that really lends none, and is how a restored hosted window came
        // up at launch wearing palette chrome: measured on `ALXVortex` 2026-09-21, Cava and the
        // library drew 155 times on the palette before the donor's borders had resolved. This flag
        // is the third state, and `HostedWindowBorderLayout` holds an open while it is set.
        isResolvingHostedFrames = true
        loadTask?.cancel()
        stopDispatcher()
        materializer.teardown()
        bindingCache.removeAll()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let url = try importer.selectedSkinURL() else {
                    presentUnskinned(message: nil)
                    releaseLaunchHold()
                    return
                }
                let skin = try await importer.loader.load(from: url)
                try Task.checkCancellation()
                // The skin's markup is where its equaliser is switched on, and it is stated once
                // per skin rather than once per view: applying it in `apply(skin:…)` would re-run
                // on every `switchView` and undo a user who had turned the equaliser off.
                if let equalizerEnabled = WMPDeclaredHostState.equalizerEnabled(in: skin) {
                    host.perform(.setEQEnabled, value: .number(equalizerEnabled ? 1 : 0))
                }
                // A `.wmz` names views that are never windows. 25 corpus skins author a
                // `controlView` holding only `<player>` and a hidden `<video>`, and `pharaoh`
                // writes two explicit 0x0 `vGhost` views: each exists so that an `onLoad` can run
                // with host bindings and then hand off to the view the user actually sees. Such a
                // view builds and scripts like any other and is simply never presented, so the
                // candidate list is walked until one of them has a canvas to draw.
                let store = WMPImageStore(provider: skin.archive)
                let skinData = try await Task.detached { try Data(contentsOf: skin.archive.sourceURL) }.value
                let runtime = WMPScriptRuntime(
                    preferences: WMPPreferenceStore(skinData: skinData, defaults: importer.defaults))
                // Before the first `onLoad`: that is where a skin fills its playlist chooser (W136).
                await runtime.setLibraryDemandHandler { [weak self] demands, viewID, event in
                    Task { @MainActor in
                        await self?.fetchLibraryDemands(demands, viewID: viewID, event: event)
                    }
                }
                await refreshLibrary(runtime, initial: true)
                // A borrowed frame is drawn with what the donor's `onLoad` makes of these (W145).
                let runtimeID = ObjectIdentifier(runtime)
                await runtime.setPreferencesChangedHandler { [weak self] in
                    Task { @MainActor in self?.hostedFrameAppearanceNeedsRefresh(from: runtimeID) }
                }
                await runtime.setScreen(Self.screenSize(for: window),
                                        usable: Self.usableScreenSize(for: window))
                var candidates = Self.startupCandidates(
                    persisted: importer.selectedViewID,
                    declared: WMPDeclaredHostState.authoredStartupViewID(in: skin),
                    declarationOrder: skin.views.map(\.id))
                var visited = Set<String>()
                var index = 0
                var presented = false
                // The panels a windowless dispatcher asked for that did not become the player.
                // They are opened beside it once it is on screen — see the collapsed branch below.
                var deferredWindowCommands: [WMPJScriptHostCommand] = []
                let declarationOrder = skin.views.map(\.id)
                while index < candidates.count {
                    let candidate = candidates[index]
                    index += 1
                    guard visited.insert(WMPPath.fold(candidate)).inserted,
                          let registration = skin.views.first(where: {
                              $0.id.caseInsensitiveCompare(candidate) == .orderedSame
                          }) else { continue }
                    let restoredViewMatches =
                        pendingRestoredViewID?.caseInsensitiveCompare(registration.id) == .orderedSame
                    let requested = restoredViewMatches ? pendingRestoredFrame.map {
                        WMPSize(width: $0.width, height: $0.height)
                    } : nil
                    let builder = WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    let scene = try await builder.build(viewID: registration.id,
                                                        requestedSize: requested)
                    await runtime.discardView(registration.id)
                    let loadEvent = WMPJScriptEvent(name: "load", targetID: registration.id,
                        handlers: Self.handlers(in: skin, event: "load", targetID: nil,
                                                viewID: registration.id))
                    let output = await runtime.transact(skin: skin, viewID: registration.id,
                        size: scene.canvasSize, snapshot: host.snapshot, event: loadEvent,
                        geometry: scene.scriptGeometry, animatesTweens: Self.animatesLoadTweens)
                    try Task.checkCancellation()
                    // **A view can declare itself windowless in its own `onLoad`, and the corpus
                    // does it by writing zero.** `Halo 2` opens on `previewView` — the skin-chooser
                    // thumbnail, sized 280x348 by its own `preview.png` — whose
                    // `onLoadSkinPreview()` sets `view.width = 0`, `view.height = 0` and
                    // `view.backgroundImage = ""` before redirecting to `controlView`, which opens
                    // the real player. Judging the view only on the canvas it had *before* the
                    // script ran presented that thumbnail and then let the handler blank it: an
                    // empty window, reported on 2026-09-08 as "Halo 2 has no UI at all", on a skin
                    // whose `mainView` renders perfectly. Its size was then saved under
                    // `wmpViewSizes` and handed back on every launch after. The same shape is
                    // authored by the ten `mediaSwitcherView`s W75 uncovered.
                    let collapsed = ["width", "height"].contains { property in
                        output.overrides.geometry[.init(stableID: registration.node.stableID,
                                                        property: property)] == 0
                    }
                    guard scene.canvasSize.width > 0, scene.canvasSize.height > 0, !collapsed else {
                        recordScriptDiagnostics(output.diagnostics)
                        let successors = Self.windowlessSuccessors(
                            of: output.hostCommands, declarationOrder: declarationOrder)
                        deferredWindowCommands += successors.opened
                        candidates.insert(contentsOf: successors.next, at: index)
                        continue
                    }
                    if pendingRestoredFrame != nil, !restoredViewMatches {
                        pendingRestoredFrame = nil
                        pendingRestoredViewID = nil
                    }
                    var resolved = try await builder.build(viewID: registration.id,
                        requestedSize: Self.loadedCanvas(assigned: output.viewSize,
                                                         opened: scene.canvasSize),
                        overrides: output.overrides)
                    var overrides = output.overrides
                    // The player view opens under the same rule as every other one (W211): a view
                    // laid out at a size it was not authored at has been resized, and the skin's
                    // own `onResize` is part of reaching that size. Overrides only — the load's
                    // host commands and timers are applied below.
                    if Self.opensResized(in: skin, viewID: registration.id, opened: resolved) {
                        let authored = try await builder.build(viewID: registration.id,
                            requestedSize: Self.authoredCanvas(in: skin, viewID: registration.id),
                            overrides: Self.unclampedOverrides(output.overrides, in: skin,
                                                               viewID: registration.id))
                        if let event = Self.resizeEvent(in: skin, viewID: registration.id,
                                                        before: authored, after: resolved) {
                            let sized = await runtime.transact(skin: skin, viewID: registration.id,
                                size: resolved.canvasSize, snapshot: host.snapshot, event: event,
                                geometry: resolved.scriptGeometry)
                            overrides = sized.overrides
                            resolved = try await builder.build(viewID: registration.id,
                                                               requestedSize: resolved.canvasSize,
                                                               overrides: overrides)
                            recordScriptDiagnostics(sized.diagnostics)
                        }
                    }
                    let rendered = try await WMPRenderer(imageStore: store).render(
                        scene: resolved, backingScale: renderScale(for: resolved.canvasSize))
                    try Task.checkCancellation()
                    // **The player waits for the hosted windows' frames, so they change skin
                    // together.** The new skin's frames are built at the size every open hosted
                    // window will be under its border while the old skin stays up — player and
                    // frames alike — and `publishSurfacePalette` below commits the switch in the
                    // same turn as the player is presented. Nothing happens here when no hosted
                    // window is on screen, or the skin lends none.
                    await hostedFrames.refreshScriptedAppearance(
                        skin: skin, playerViewID: resolved.viewID,
                        preferences: await runtime.preferenceValues(), snapshot: host.snapshot)
                    await hostedFrames.stage(skin: skin, playerViewID: resolved.viewID)
                    try Task.checkCancellation()
                    // The first view with a canvas binds the app's own window and becomes the
                    // player; everything the skin opens after it gets a window of its own.
                    guard let presentation = materializer.materialize(
                        viewID: resolved.viewID,
                        size: NSSize(width: resolved.canvasSize.width,
                                     height: resolved.canvasSize.height),
                        opener: nil, offset: nil) else { continue }
                    apply(skin: skin, store: store, scene: resolved, image: rendered.image,
                          overlay: rendered.overlayImage, silhouette: rendered.silhouetteMask,
                          runtime: runtime, overrides: overrides, into: presentation)
                    // **Before the load transaction's commands, so a skin that re-opens its own
                    // panels does not end up with two.** A dispatcher skin reads
                    // `theme.loadPreference('plViewer')` and calls `theme.openView` for each panel
                    // it had open; `show` on a view that is already open is a raise, so whichever
                    // of the two runs first wins and the other is a no-op.
                    restoreOpenAuxiliaryViews(skin: skin, store: store, runtime: runtime)
                    // Everything the dispatcher opened that is not the player itself. Replayed
                    // through the ordinary command path, so `openViewRelative`'s displacement and
                    // the open-view bound both still apply, and a panel already restored above is
                    // a raise rather than a second window.
                    applyHostCommands(deferredWindowCommands.filter {
                        $0.value?.string?.caseInsensitiveCompare(resolved.viewID) != .orderedSame
                    }, from: presentation)
                    let switchedView = applyHostCommands(output.hostCommands, from: presentation)
                    if !switchedView {
                        applyTimerDelta(presentation, registered: output.timerRequests,
                                        cleared: output.clearedTimerTokens)
                        WMPTweenTrace.log("load view=\(resolved.viewID)"
                            + " clock=\(Self.animatesLoadTweens)"
                            + " hasActiveTweens=\(output.hasActiveTweens)")
                        startTweenLoop(presentation, hasActiveTweens: output.hasActiveTweens)
                    }
                    recordScriptDiagnostics(output.diagnostics)
                    await adoptDispatcher(in: skin, store: store, presenting: resolved.viewID,
                                          loaded: visited)
                    presented = true
                    break
                }
                guard presented else {
                    throw WMPFailure(WMPDiagnostic(.invalidGeometry,
                        "The skin contains no renderable WMP view."))
                }
                releaseLaunchHold()
                // The one moment a `.wmz` skin load is finished: the player is bound, its panels
                // are materialized and the dispatcher has been adopted. A `.wmz` window's size
                // *is* the skin, so switching to a larger one grows the player in place around its
                // top-left and re-tiles its panels around that — off the display, for a skin wide
                // or tall enough. This is the `.wal` skin-load sweep's counterpart (W217 G3); the
                // three menu entry points all funnel through here, so there is one site rather
                // than three.
                WindowManager.shared.ensureAllWindowsOnScreen()
            } catch is CancellationError {
                return
            } catch {
                presentUnskinned(message: error.localizedDescription)
                releaseLaunchHold()
            }
        }
    }

    /// The order the walk tries views in, before any of them has been built.
    ///
    /// Four sources, ranked: **the user's persisted view**, then the skin's own
    /// `<THEME currentViewID>`, then `vPlayer`, then document order. The first three are
    /// statements about which view is the player; the fourth is a fallback for the skins that make
    /// none, and `portals` is what happens when it decides on their behalf — it defines `mode2`
    /// before it declares `mode1`, so the player opened on the skin's info mode and the mode button
    /// was not where anyone was clicking (W153).
    ///
    /// **A host-opened notice view is refused as a seed, wherever it appears (W176).** Not from the
    /// persisted slot either: landing on one is how it came to be persisted, so honouring it there
    /// makes the defect survive its own fix. Within document order it sorts last rather than being
    /// dropped, so a skin whose *only* view is a notice still opens.
    ///
    /// The skin's own `currentViewID` is the one place a notice view is still honoured, because
    /// that is the skin stating it on purpose rather than the walk choosing on its behalf. It stays
    /// reachable the other way too: a successor from a windowless view's `theme.openView` or
    /// `theme.currentViewID` is inserted into the walk *after* this list is built, which is how
    /// `WALL-E`'s `preview.js` reaches `upgradeView` when it decides the player is too old.
    ///
    /// Duplicates are left in. The walk folds each id through `WMPPath.fold` into a visited set as
    /// it goes, so a view named twice here is tried once, and leaving them makes each rank readable
    /// on its own.
    static func startupCandidates(persisted: String?, declared: String?,
                                  declarationOrder: [String]) -> [String] {
        var candidates: [String] = []
        if let persisted, !WMPDeclaredHostState.isHostOpenedNotice(viewID: persisted) {
            candidates.append(persisted)
        }
        if let declared { candidates.append(declared) }
        candidates.append("vPlayer")
        candidates += declarationOrder.filter { !WMPDeclaredHostState.isHostOpenedNotice(viewID: $0) }
        candidates += declarationOrder.filter { WMPDeclaredHostState.isHostOpenedNotice(viewID: $0) }
        return candidates
    }

    /// What a view with **no window** asked for next.
    ///
    /// The only host command such a view can honour is where to go next; the rest need the
    /// presented controller state it never gets. A windowless `controlView` opens the real player
    /// with `theme.openView` exactly as often as it redirects with `theme.currentViewID`.
    ///
    /// **The two are not the same request and must not be collapsed into one `last` (W175).**
    /// `currentViewID` is a redirect and the last write wins. `openView` is not a redirect at all —
    /// WMP opens a window per call and leaves the caller alone — so a dispatcher that opens its
    /// player, its playlist and its equaliser is asking for three windows. Taking the last of them
    /// opened `XBOX Music Mixer` on the equaliser its `onLoadSkin()` opens *after* `mainView`, and
    /// the player it never presented is the only one of its views with a route back to the others.
    ///
    /// **The player is the earliest of them in the skin's own declaration order** — every one of the
    /// 21 corpus archives that declares both a `mainView` and a panel view declares `mainView`
    /// first (`reference/skins/xbox-music-mixer.md` carries the scan) — and the rest are opened
    /// beside it once it is on screen. Every one of them stays
    /// in `next`, so a player that turns out to be windowless in its turn still falls through to the
    /// one after it.
    ///
    /// - Returns: `next`, the view ids to try presenting, in order; and `opened`, the `openView`
    ///   commands to replay against the player once there is one. A view id appears in both: the
    ///   caller drops the one that became the player.
    static func windowlessSuccessors(of commands: [WMPJScriptHostCommand],
                                     declarationOrder: [String])
        -> (next: [String], opened: [WMPJScriptHostCommand]) {
        func order(of viewID: String) -> Int {
            declarationOrder.firstIndex { $0.caseInsensitiveCompare(viewID) == .orderedSame }
                ?? Int.max
        }
        let opened = commands
            .filter { $0.action.hasPrefix("openView") && $0.value?.string?.isEmpty == false }
            .enumerated()
            // `sorted(by:)` is not stable, and document order ties on every id the skin does not
            // declare: the authored call order is the tiebreak.
            .sorted {
                let (lhs, rhs) = (order(of: $0.element.value?.string ?? ""),
                                  order(of: $1.element.value?.string ?? ""))
                return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
            }
            .map(\.element)
        if let redirect = commands.last(where: { $0.action == "setCurrentView" })?.value?.string,
           !redirect.isEmpty {
            return ([redirect], opened)
        }
        return (opened.compactMap { $0.value?.string }, opened)
    }

    /// Re-open the panels the user last had open, following `.wal`'s rule that **what the user last
    /// decided wins over what the skin declares**.
    ///
    /// Runs after the player is on screen — an auxiliary window is placed relative to it — and
    /// before the load transaction's host commands, so a skin that re-opens its own panels from a
    /// preference raises the window this restored rather than opening a second one.
    private func restoreOpenAuxiliaryViews(skin: WMPLoadedSkin, store: WMPImageStore,
                                           runtime: WMPScriptRuntime) {
        let stored = WMPViewFrameStore(defaults: importer.defaults)
            .openViews(skin: importer.selectedSkinName ?? "")
        guard !stored.isEmpty, let player = materializer.playerPresentation else { return }
        for viewID in stored.prefix(Self.maximumOpenViews)
        where !materializer.isOpen(viewID)
            && viewID.caseInsensitiveCompare(player.viewID) != .orderedSame {
            openView(viewID, from: player, offset: nil)
        }
    }

    func importSkinFromPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "wmz")!]
        panel.message = "Select a Windows Media Player .wmz skin"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importSkin(from: url)
    }

    func importSkin(from url: URL) {
        loadTask?.cancel()
        presentUnskinned(message: "Validating and importing \(url.lastPathComponent)…")
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await importer.importSkin(from: url)
                try Task.checkCancellation()
                reloadSelectedSkin()
            } catch is CancellationError {
                return
            } catch {
                presentUnskinned(message: error.localizedDescription)
            }
        }
    }

    func selectInstalledSkin(named name: String) {
        guard let skin = importer.installedSkins().first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            presentUnskinned(message: WMPSkinImportError.selectionMissing(name).localizedDescription)
            return
        }
        importer.select(skin)
        reloadSelectedSkin()
    }

    func resetToUnskinned() {
        loadTask?.cancel()
        importer.resetSelection()
        presentUnskinned(message: nil)
    }

    func resetScriptPreferences() {
        guard let scriptRuntime else { return }
        Task { await scriptRuntime.resetPreferences() }
        lastLoadDiagnostic = "WMP skin script preferences were reset."
    }

    func saveCompatibilityReportFromPanel() {
        guard let report = loadedSkin?.compatibilityReport else {
            let alert = NSAlert()
            alert.messageText = "No WMP Skin Report Available"
            alert.informativeText = "Import and load a valid .wmz skin before saving a compatibility report."
            alert.runModal()
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "WMP-Skin-Compatibility.json"
        panel.message = "Save a bounded compatibility report for the active WMP skin"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await Task.detached(priority: .utility) {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(report).write(to: url, options: .atomic)
                }.value
            } catch {
                _ = await MainActor.run { NSAlert(error: error).runModal() }
            }
        }
    }

    func restoreFrame(_ frame: NSRect, skinName: String?, viewID: String?) {
        guard frame != .zero else { return }
        let selectedName = importer.selectedSkinName
        let nameMatches = selectedName?.caseInsensitiveCompare(skinName ?? "") == .orderedSame
            || (selectedName == nil && skinName == nil)
        let selectedView = importer.selectedViewID
        let viewMatches = selectedView?.caseInsensitiveCompare(viewID ?? "") == .orderedSame
            || (selectedView == nil && viewID == nil)
        guard nameMatches, viewMatches else { return }
        // The saved rect, not a locally re-derived "safe" one (W217 G1). There used to be a
        // second definition of on-screen here — an 80 pt strip and a 24 pt bottom margin,
        // picking its screen by first intersection — and it was wrong three times over: it is
        // not `WindowPlacement`'s top-left-corner rule, the strip it guarantees on a
        // borderless `.wmz` window can be pure artwork with nothing to grab, and it clamped
        // against the *saved* size when the size that lands is the skin's (see the
        // `pendingRestoredFrame` apply below, which keeps only the top-left). Reachability is
        // owned by the two seams that run either side of this one: the whole-session group
        // correction before it (G2, `AppStateManager.correctedRestoredFrames`, which is what
        // `restoreWindowFrames` hands us) and `ensureAllWindowsOnScreen()` after the skin has
        // sized the window (G3, the load site above and the post-restore settle).
        pendingRestoredFrame = frame
        pendingRestoredViewID = viewID
        if loadedSkin != nil { reloadSelectedSkin() }
        else if skinName == nil, let safe = pendingRestoredFrame {
            // The unskinned player owns a fixed safe size; restore position only.
            var positioned = safe
            positioned.size = NSSize(width: Self.unskinnedSize.width * uiScale,
                                     height: Self.unskinnedSize.height * uiScale)
            positioned.origin.y = safe.maxY - positioned.height
            window?.setFrame(positioned, display: true)
            unskinnedView?.setBoundsSize(Self.unskinnedSize)
        }
    }

    private func apply(skin: WMPLoadedSkin, store: WMPImageStore, scene: WMPScene, image: CGImage,
                       overlay: CGImage? = nil, silhouette: CGImage? = nil,
                       runtime: WMPScriptRuntime, overrides: WMPSceneOverrides,
                       into presentation: WMPViewPresentation) {
        loadedSkin = skin
        imageStore = store
        materializer.rekey(presentation, to: scene.viewID)
        presentation.activeLimits = scene.resizeLimits
        applyWindowSizeLimits(presentation, scene: scene)
        presentation.activeScene = scene
        scriptRuntime = runtime
        lastScriptSnapshot = host.snapshot
        // A newly loaded view must receive video readiness even when decoding preceded its load.
        lastScriptSnapshot?.videoEvent = WMPVideoSnapshot()
        lastScriptSnapshot?.video = WMPVideoSnapshot()
        presentation.sceneOverrides = overrides
        lastLoadDiagnostic = nil
        // A `.wmz` window is genuinely shaped — Corona is transparent across the 250 px its
        // playlist slides into and the 124 px its equaliser drops into — and macOS derives a
        // borderless window's shadow from whatever content it last cached. On a shape that changes
        // with every drawer and every repaint that gets stale, and a stale shadow over a
        // transparent region reads as a dark box the size of the window. There is no drop shadow
        // in Windows Media Player to lose.
        presentation.window.hasShadow = false
        presentation.window.invalidateShadow()
        // **Only the player is the session's view (W96).** `theme.openView` opens a second window,
        // so persisting whatever is presented recorded a panel as the thing to restore: `WoW` opens
        // its playlist that way, and quitting with it open restored a playlist panel with an empty
        // listbox and no player at all — reported as "the skin is empty and shows no player". This
        // used to be spelled "nothing has been opened over the player"; with real windows it is
        // simply the player's own presentation.
        if presentation.isPlayer {
            importer.defaults.set(scene.viewID, forKey: WMPSkinImporter.selectedViewIDKey)
        }
        setViewTimer(presentation,
                     milliseconds: Self.authoredTimerInterval(in: skin, viewID: scene.viewID))

        let view = presentation.mainView ?? WMPMainView(frame: .zero)
        presentation.mainView = view
        // Native playlist rows are the one WMP-owned surface the scene cannot paint.  Feed them
        // this skin's palette before they are installed, never a palette from another UI mode.
        view.surfaceStyle = WMPSurfacePalette(skin: skin, viewID: scene.viewID).surfaceStyle
        // **The grips this view authors for its own resize (W227).** Identified here rather than in
        // the scene, because a grip is a node whose mouse handler reaches `view.size` and the
        // handler routinely reaches it through a function in the skin's scripts — which the scene
        // builder does not have. Computed once per view, from markup that cannot change under it.
        view.resizeGrips = skin.views
            .first { $0.id.caseInsensitiveCompare(scene.viewID) == .orderedSame }
            .map { WMPResizeGrip.grips(in: $0.node, scriptSources: skin.scriptSources) } ?? []
        // The container shape a windowless `<EFFECTS>` is confined to. Decoded through the same
        // store the scene draws from, so it is cached alongside the artwork it comes from.
        view.regionMaskProvider = { [weak store] mask in
            try? store?.regionMask(for: mask.resourcePath, keyedOut: mask.keyedOut)
        }
        view.videoController = { WMPAudioEngineHost.localVideoController }
        view.onAction = { [weak self] action, value in
            guard let self else { return }
            // **A direct button press is the one input that reached the host untraced.** `INPUT
            // command` covers only script-issued commands, so a skin that commits through JScript
            // (Cablemusic's seek slider posts `seekSeconds`) was visible while a plain transport
            // button was not — and "no play in the log" then reads as "play was never pressed",
            // which it does not mean. Traced here, at the one place every widget action passes.
            self.host.perform(action, value: value)
            self.refreshHostState()
        }
        view.onScriptResizeEnded = { [weak self, weak presentation] in
            guard let self, let presentation else { return }
            self.resumeAfterScriptResize(presentation)
        }
        view.onScriptEvent = { [weak self, weak presentation] name, targetID, targetStableID in
            guard let self, let presentation else { return }
            self.dispatchScriptEvent(presentation, name: name, targetID: targetID,
                                     targetStableID: targetStableID,
                                     onlyWhenAuthored: Self.hoverEvents.contains(name))
        }
        // **One transaction per keystroke, and the answer the view needs is synchronous** (W53).
        //
        // `keydown` carries `keypress`'s handlers with it: WMP raises both for one press, and
        // dispatching them as two transactions would cancel the first before it ran — the hazard
        // `onSliderRelease` documents above. They can share the one `event.keyCode` because the
        // corpus compares both cases of every letter it tests in an `onkeypress`, so the VK matches
        // either way; `WMPVirtualKeyCode` carries that measurement.
        //
        // The return value is the whole ordering rule: it says whether the skin authored a handler,
        // so `WMPMainView` knows whether to also run its own built-in arrow stepping. It has to be
        // answered now, from the loaded skin's graph, not after the script actor has run.
        view.onKeyEvent = { [weak self, weak presentation] name, targetID, targetStableID, keyCode in
            guard let self, let presentation, let skin = self.loadedSkin else { return false }
            let names = name == "keydown" ? ["keydown", "keypress"] : [name]
            let handlers = names.flatMap {
                Self.handlers(in: skin, event: $0, targetID: targetID,
                              targetStableID: targetStableID, viewID: presentation.viewID)
            }
            // **An arrow is the skin's only where its handler compares that arrow.** Everything
            // else a handler is authored for stays the skin's: see `WMPKeyHandlerScan`.
            let authored = !handlers.isEmpty && (!(37...40).contains(keyCode)
                || WMPKeyHandlerScan.handlers(handlers, compare: keyCode,
                                              in: [skin.definitionSource] + Array(skin.scriptSources.values)))
            #if DEBUG
            if ProcessInfo.processInfo.environment["WMP_CLICK_TRACE"] == "1" {
                NSLog("[wmp/key] offer %@ keyCode=%d targetID=%@ stable=%@ authored=%d",
                      name, keyCode, targetID ?? "-", targetStableID.map(String.init) ?? "-",
                      authored ? 1 : 0)
            }
            #endif
            guard authored else { return false }
            self.dispatchScriptTransaction(presentation,
                WMPJScriptEvent(name: name, targetID: targetID, targetStableID: targetStableID,
                                handlers: handlers, modifiers: Self.currentEventModifiers(),
                                keyCode: keyCode,
                                pointer: Self.currentPointer(presentation)))
            return true
        }
        view.onElementTextChanged = { [weak self, weak presentation] stableID, targetID, text in
            guard let self, let presentation, let scriptRuntime = self.scriptRuntime else { return }
            Task {
                await scriptRuntime.setWidgetText(stableID: stableID, text: text,
                                                  viewID: presentation.viewID)
                self.dispatchScriptEvent(presentation, name: "keyup", targetID: targetID,
                                         targetStableID: stableID)
            }
        }
        view.onElementTextReturn = { [weak self, weak presentation] stableID, targetID, text in
            guard let self, let presentation, let scriptRuntime = self.scriptRuntime else { return }
            Task {
                await scriptRuntime.setWidgetText(stableID: stableID, text: text,
                                                  viewID: presentation.viewID)
                self.dispatchScriptEvent(presentation, name: "keyup", targetID: targetID,
                                         targetStableID: stableID,
                                         keyCode: WMPVirtualKeyCode.keyDown(keyCode: 36,
                                                    charactersIgnoringModifiers: "\r"))
            }
        }
        view.onPlayLibraryTracks = { [weak self] playlist, row in
            guard let self else { return }
            self.playLibraryTracks(playlist.tracks, from: row)
            if let scriptRuntime = self.scriptRuntime {
                Task { await scriptRuntime.adoptCurrentLibraryPlaylist(playlist.reference) }
            }
        }
        view.onListSelected = { [weak self, weak presentation] stableID, targetID, index in
            guard let self, let presentation, let scriptRuntime = self.scriptRuntime else { return }
            self.enqueueListEvent(presentation) {
                await scriptRuntime.setWidgetSelection(stableID: stableID, index: index,
                                                      viewID: presentation.viewID)
                self.dispatchScriptEvent(presentation, name: "selecteditem_onchange",
                                         targetID: targetID, targetStableID: stableID)
            }
        }
        view.onListDoubleClicked = { [weak self, weak presentation] stableID, targetID, index in
            guard let self, let presentation, let scriptRuntime = self.scriptRuntime else { return }
            self.enqueueListEvent(presentation) {
                // `onDblClick` reads `selectedItem`, so it is the row that was double-clicked.
                await scriptRuntime.setWidgetSelection(stableID: stableID, index: index,
                                                      viewID: presentation.viewID)
                self.dispatchScriptEvent(presentation, name: "dblclick",
                                         targetID: targetID, targetStableID: stableID)
            }
        }
        view.onElementValueChanged = { [weak self, weak presentation] stableID, targetID, value in
            guard let self, let presentation, let scriptRuntime = self.scriptRuntime else { return }
            Task {
                await scriptRuntime.setWidgetValue(stableID: stableID, value: value,
                                                   viewID: presentation.viewID)
                self.dispatchScriptEvent(presentation, name: "change", targetID: targetID,
                                         targetStableID: stableID)
            }
        }
        // One task, three steps, in order: the value the user left the control at, then the two
        // handlers that read it. See W151.
        view.onSliderCaptureChanged = { [weak self] active, stableID in
            guard let self else { return }
            self.sliderCaptureActive = active
            guard let scriptRuntime = self.scriptRuntime else { return }
            Task { active ? await scriptRuntime.holdElement(stableID: stableID)
                          : await scriptRuntime.releaseElement(stableID: stableID) }
        }
        // **One transaction, not two.** `dispatchScriptTransaction` cancels the presentation's
        // previous script task, so dispatching `mouseup` and then `dragend` cancels the first
        // before it runs. Both handler sets go into a single event, after the value the user left
        // the control at — and the capture gate is only released once that has been sent, so no
        // position tick can land between the value and the handlers that read it.
        view.onSliderRelease = { [weak self, weak presentation] stableID, targetID, value, pendingSeek in
            guard let self, let presentation, let scriptRuntime = self.scriptRuntime,
                  let skin = self.loadedSkin else {
                self?.sliderCaptureActive = false
                if let pendingSeek { self?.host.perform(.seek, value: pendingSeek) }
                return
            }
            Task {
                await scriptRuntime.setWidgetValue(stableID: stableID, value: value,
                                                   viewID: presentation.viewID)
                let handlers = ["mouseup", "dragend"].flatMap {
                    Self.handlers(in: skin, event: $0, targetID: targetID,
                                  targetStableID: stableID, viewID: presentation.viewID)
                }
                #if DEBUG
                wmpSeekTrace("onSliderRelease committed value=\(value) handlers=\(handlers.count)")
                #endif
                self.scriptDidCommitSeek = false
                self.dispatchScriptTransaction(presentation,
                    WMPJScriptEvent(name: "mouseup", targetID: targetID,
                                    targetStableID: stableID, handlers: handlers,
                                    modifiers: Self.currentEventModifiers(),
                                    button: Self.mouseButton(for: "mouseup"),
                                    pointer: Self.currentPointer(presentation)))
                // **The hold outlives the dispatch, not the call that made it.**
                // `dispatchScriptTransaction` only *creates* a task, so releasing here released the
                // element before the transaction ran — and the transaction then settled the
                // implicit `player.controls.currentPosition` binding over the user's value before
                // the handler read it. Measured: dragged to 521s, committed `seekSeconds=18.95`,
                // which was the live position, so the seek landed exactly where it already was and
                // the thumb snapped back on release.
                await presentation.scriptTask?.value
                // **The seek the gesture asked for, committed once, here** (W156). It waits for the
                // skin's own handlers because 111 of the corpus's 141 `onDragEnd` sources are
                // `player.controls.currentPosition = value` and would otherwise make this a second
                // seek to the same second — two `AudioEngine.seek` restarts where the user asked
                // for one. `scriptDidCommitSeek` is what the transaction reports back; a slider
                // whose skin authors no release handler at all (`corona`'s bare `<SEEKSLIDER>`,
                // and every seek slider that binds `value` and nothing else) is committed here and
                // nowhere else, which is why coalescing cannot simply drop the per-move commits.
                if let pendingSeek, !self.scriptDidCommitSeek {
                    self.host.perform(.seek, value: pendingSeek)
                    self.refreshHostState()
                }
                self.sliderCaptureActive = false
                await scriptRuntime.releaseElement(stableID: stableID)
            }
        }
        view.onSpectrumDemandChanged = { [weak self, weak view] active in
            guard let self, let view else { return }
            self.setSpectrumDemand(active, from: ObjectIdentifier(view))
        }
        view.onInteractionChanged = { [weak self, weak presentation] state, changed in
            guard let self, let presentation else { return }
            presentation.interactionState = state
            self.renderInteraction(presentation, state: state, changed: changed)
        }
        if presentation.isPlayer { unskinnedView = nil }
        // A present is a new view (or a reload of this one): the previous view's scripted size is
        // not this one's, and `apply` sizes the window from the scene it was handed.
        presentation.scriptViewSize = nil
        presentation.window.contentView = view
        if presentation.isPlayer, let restored = pendingRestoredFrame {
            presentation.skinSpaceSize = NSSize(width: scene.canvasSize.width,
                                                height: scene.canvasSize.height)
            var frame = restored
            frame.size = NSSize(width: presentation.skinSpaceSize.width * uiScale,
                                height: presentation.skinSpaceSize.height * uiScale)
            frame.origin.y = restored.maxY - frame.height
            presentation.isApplyingSceneSize = true
            presentation.window.setFrame(frame, display: true)
            presentation.isApplyingSceneSize = false
            presentation.window.invalidateShadow()
            pendingRestoredFrame = nil
            pendingRestoredViewID = nil
        } else {
            setWindowSize(presentation,
                          NSSize(width: scene.canvasSize.width, height: scene.canvasSize.height))
        }
        view.present(image, overlay: overlay, silhouette: silhouette, scene: scene, traceSource: "initial")
        view.refreshHostState(host.snapshot)
        // A mode switch can create this WMP session while audio (or local video) is already
        // playing. `lastScriptSnapshot` is deliberately seeded above so normal host events do not
        // replay on every skin reload, but that also means no later snapshot diff can raise the one
        // `currentMedia_onchange` which assigns WMPImage_AlbumArtLarge. Seed the WMP-only artwork
        // surface and dispatch that authored event once, now that its store and presentation exist.
        if let audioHost = host as? WMPAudioEngineHost {
            updateArtwork(for: audioHost.artworkTrack)
        }
        dispatchHostEvents(presentation, ["currentmedia_onchange"])
        startAnimation(presentation, for: scene)
        arbitrateVideoSurface()
        if presentation.isPlayer {
            publishSurfacePalette(skin: skin, viewID: scene.viewID, rendered: image)
        }
        skinSurfaces = WMPSkinSurfaces(skin: skin)
        // A fallback window opened under the *previous* skin is not a fallback under this one.
        WindowManager.shared.dismissWMPFallbackSurfacesTheSkinProvides()
        if !presentation.isPlayer { presentation.window.orderFront(nil) }
        persistOpenViews()
    }

    /// **One `WMPVideoSurface`, handed to whichever window is showing the picture.**
    ///
    /// `Halo 2`'s `<VIDEO>` lives in `videoView`, a window of its own, while its player draws in
    /// another — so ownership has to be decided rather than assumed. The surface re-parents the VLC
    /// child window to its host view's window on every tick, so a transfer is this assignment plus a
    /// detach; everything else already self-heals. Every other window holds no surface at all, which
    /// is what keeps `WMPMainView.refreshHostState` from two views fighting over the same picture.
    private func arbitrateVideoSurface() {
        let owner = materializer.openPresentations.first { presentation in
            presentation.activeScene?.widgets.contains {
                $0.kind == .video && ($0.videoPresentation?.alpha ?? 1) > 0
            } == true
        }
        for presentation in materializer.openPresentations {
            guard let view = presentation.mainView else { continue }
            if presentation === owner {
                if view.videoSurface !== videoSurface {
                    videoSurface.detach(reveal: false)
                    view.videoSurface = videoSurface
                }
            } else if view.videoSurface != nil {
                view.videoSurface = nil
            }
        }
        if owner == nil { videoSurface.detach(reveal: false) }
    }

    /// **The spectrum tap is ref-counted, not a Bool.** With one window, "this view has no
    /// `<EFFECTS>`" meant "nobody does"; with several it must not switch the tap off under a
    /// visualisation panel that is still drawing. The last claim to go is what stops it.
    private func setSpectrumDemand(_ active: Bool, from view: ObjectIdentifier) {
        let before = spectrumConsumers.isEmpty
        if active { spectrumConsumers.insert(view) } else { spectrumConsumers.remove(view) }
        guard before != spectrumConsumers.isEmpty else { return }
        host.setSpectrumConsumerActive(!spectrumConsumers.isEmpty)
    }

    /// Whether the skin owns this surface, and — when asked to switch — showing it the way the skin
    /// itself would.
    ///
    /// Returns `true` when the skin provides the surface at all, which is the signal to NullPlayer
    /// not to open a window of its own: 171 of the 180 corpus skins declare a playlist and 164 an
    /// equaliser, so a second copy is the common case, not the exception.
    ///
    /// - Parameter switchingViews: when the surface lives in a view that is *not* on screen, open
    ///   that view — the same thing the skin's own button does through `theme.openView`. False for
    ///   the restore path, which must never move the user to a different view at launch, and true
    ///   for an explicit toggle from a menu.
    @discardableResult
    func revealSkinSurface(_ surface: WMPSkinSurface, switchingViews: Bool) -> Bool {
        guard skinSurfaces.provides(surface) else { return false }
        // Already on screen in one of this skin's windows: nothing to open, and nothing of ours to
        // add. With real windows this is a question about the whole session rather than about the
        // one view that used to be presented.
        if materializer.anyOpenView(where: { skinSurfaces.view($0, provides: surface) }) { return true }
        if switchingViews, let target = skinSurfaces.viewIDs(for: surface).first,
           let player = materializer.playerPresentation {
            // The same call the skin's own button makes. Routing a menu toggle through `openView`
            // rather than a view *switch* is what keeps the player up beside the panel — and it is
            // the panel's own `view.close()` that takes it away again.
            _ = applyHostCommands([.init(action: "openView", value: .string(target))], from: player)
        }
        return true
    }

    /// Hand `WMPSurfacePalette` to NullPlayer's own windows, and tell the open ones to repaint.
    ///
    /// The rendered bitmap is only *sampled* when the markup declared no background — 84 of the 180
    /// corpus archives declare no colour at all — and the sample is taken from the same image the
    /// window is showing, so what our chrome is coloured from is literally what the user is looking
    /// at. **Only the player's bitmap**: NullPlayer's own windows must not be recoloured by
    /// whichever panel the skin happened to open last.
    private func publishSurfacePalette(skin: WMPLoadedSkin, viewID: String, rendered: CGImage) {
        var palette = WMPSurfacePalette(skin: skin, viewID: viewID)
        if palette.background == nil {
            palette.sampledBackground = WMPSurfacePalette.dominantColor(of: rendered)
        }
        // The frame is adopted whether or not the palette moved: they answer different questions
        // and a view switch can leave the colours identical while the ring changes.
        hostedFrames.configure(skin: skin, playerViewID: viewID)
        // The provider now knows what this skin lends, so a held window's question has a real
        // answer even if that answer is "nothing".
        isResolvingHostedFrames = false
        guard palette != currentSurfacePalette else { return }
        currentSurfacePalette = palette
        NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
    }

    private var appearanceRefresh: Task<Void, Never>?
    private var appearanceRefreshPending = false

    /// **The skin wrote a preference, so its donor's `onLoad` may now choose a different frame
    /// (W145).** `xsn_sports` moves `htcpID` on its own colour cycle. Coalesced: one off-screen run
    /// at a time, and one more after it if anything was written meanwhile. The frame is rebuilt only
    /// when the appearance actually moved, through the same staged switch a skin change uses.
    private func hostedFrameAppearanceNeedsRefresh(from source: ObjectIdentifier) {
        guard let runtime = scriptRuntime, ObjectIdentifier(runtime) == source,
              let skin = loadedSkin, hostedFrames.lendsFrame else { return }
        guard appearanceRefresh == nil else {
            appearanceRefreshPending = true
            return
        }
        appearanceRefresh = Task { [weak self] in
            guard let self else { return }
            let viewID = selectedViewID
            let moved = await hostedFrames.refreshScriptedAppearance(
                skin: skin, playerViewID: viewID,
                preferences: await runtime.preferenceValues(), snapshot: host.snapshot)
            if moved, loadedSkin === skin, scriptRuntime === runtime {
                hostedFrames.configure(skin: skin, playerViewID: viewID)
            }
            appearanceRefresh = nil
            if appearanceRefreshPending {
                appearanceRefreshPending = false
                hostedFrameAppearanceNeedsRefresh(from: source)
            }
        }
    }

    private func clearSurfacePalette() {
        skinSurfaces = .empty
        hostedFrames.reset()
        isResolvingHostedFrames = false
        guard currentSurfacePalette != nil else { return }
        currentSurfacePalette = nil
        NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
    }

    private func presentUnskinned(message: String?) {
        clearSurfacePalette()
        artworkLoadTask?.cancel()
        artworkLoadTask = nil
        artworkTrackID = nil
        loadedSkin = nil
        imageStore = nil
        materializer.teardown()
        bindingCache.removeAll()
        spectrumConsumers.removeAll()
        host.setSpectrumConsumerActive(false)
        videoSurface.detach(reveal: false)
        if let scriptRuntime { Task { await scriptRuntime.teardown() } }
        scriptRuntime = nil
        lastScriptSnapshot = nil
        stopDispatcher()
        lastLoadDiagnostic = message

        // The app-authored player is an ordinary opaque rectangle and keeps its shadow.
        window?.hasShadow = true
        window?.invalidateShadow()
        // The floor and ceiling go back with the view that owns them; see `applyWindowSizeLimits`.
        window?.minSize = Self.unskinnedSize
        window?.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                 height: CGFloat.greatestFiniteMagnitude)
        let view = unskinnedView ?? WMPUnskinnedMainView(frame: NSRect(origin: .zero, size: Self.unskinnedSize))
        unskinnedView = view
        view.onImport = { [weak self] in self?.importSkinFromPanel() }
        view.onMinimize = { [weak self] in self?.window?.miniaturize(nil) }
        view.onClose = { [weak self] in self?.window?.orderOut(nil) }
        view.host = host
        view.show(message: message)
        window?.contentView = view
        guard let window else { return }
        let scaled = NSSize(width: Self.unskinnedSize.width * uiScale,
                            height: Self.unskinnedSize.height * uiScale)
        var frame = window.frame
        frame.size = scaled
        frame.origin.y = window.frame.maxY - scaled.height
        window.setFrame(frame, display: true)
        view.setBoundsSize(Self.unskinnedSize)
        window.invalidateShadow()
    }

    /// **The window's own floor and ceiling, which belong to the view on screen and not to the
    /// player we show when there is no skin (W213).**
    ///
    /// `configureWindow` sets `minSize` to `unskinnedSize` — 440x170 — and nothing ever moved it
    /// again, so every `.wmz` window in the corpus smaller than that carried a floor four times its
    /// own size. AppKit enforces `minSize` *after* the delegate answers, so no amount of refusing in
    /// `windowWillResize` helps: the first edge drag on `circle`'s 192x82 player snapped the window
    /// to 440x170 while the scene stayed 192x82, and the two reported symptoms are both that one
    /// state. The artwork is rasterized at the scene's size and sat in the corner; everything laid
    /// out from `bounds / canvasSize` — the hosted surfaces, and **`skinPoint(from:sceneSize:)`,
    /// which is where every click is resolved** — stretched to the window. So the visualization
    /// "popped out and stretched but the app didn't", and every control moved out from under the
    /// pointer, which is why *"the volume doesnt seem to work"*.
    ///
    /// A fixed view pins both ends: it has one size, and a window that cannot be resized should not
    /// be nudged to another by a pass that reads these.
    private func applyWindowSizeLimits(_ presentation: WMPViewPresentation, scene: WMPScene) {
        let window = presentation.window
        let limits = WMPWindowSizeLimits.forScene(scene)
        window.minSize = NSSize(width: limits.minimum.width * uiScale,
                                height: limits.minimum.height * uiScale)
        window.maxSize = NSSize(
            width: (limits.maximum?.width).map { $0 * uiScale } ?? .greatestFiniteMagnitude,
            height: (limits.maximum?.height).map { $0 * uiScale } ?? .greatestFiniteMagnitude)
        #if DEBUG
        if ProcessInfo.processInfo.environment["WMP_SIZE_TRACE"] != nil,
           let breakage = limits.breakage(for: scene.canvasSize) {
            NSLog("[wmp/size] MISMATCH \(scene.viewID) canvas=\(scene.canvasSize) "
                + "floor=\(limits.minimum) verdict=\(breakage.rawValue)")
        }
        #endif
    }

    /// `size` is in the skin's own pixels. UI Size is applied here and in `windowWillResize`, and
    /// nowhere else.
    private func setWindowSize(_ presentation: WMPViewPresentation, _ size: NSSize) {
        let window = presentation.window
        presentation.skinSpaceSize = size
        let scaled = NSSize(width: size.width * uiScale, height: size.height * uiScale)
        let old = window.frame
        var frame = old
        frame.size = scaled
        frame.origin.y = old.maxY - scaled.height
        presentation.isApplyingSceneSize = true
        window.setFrame(frame, display: true)
        presentation.isApplyingSceneSize = false
        // A borderless, non-opaque window keeps the shadow it had at its previous frame. Corona
        // resizes the view when a drawer opens, so without this the old outline is left behind
        // beside the window as a ghost of the shape it used to be.
        window.invalidateShadow()
    }

    func renderCurrentSize(_ presentation: WMPViewPresentation) {
        guard !presentation.isApplyingSceneSize, let skin = loadedSkin, let store = imageStore
        else { return }
        let viewID = presentation.viewID
        let window = presentation.window
        // The user has just chosen a size, which retires whatever the script last asked for.
        presentation.scriptViewSize = nil
        presentation.loadTask?.cancel()
        let requested = WMPSize(width: window.contentLayoutRect.width / uiScale,
                                height: window.contentLayoutRect.height / uiScale)
        // **A window that is not the user's to size does not get laid out at whatever size it was
        // left at (W213).** The resize edges are already gated on `isResizable`, so a fixed view
        // reaching here is an app-level pass having moved its frame — and building at that size is
        // how `circle` ended up drawing its `<EFFECTS jscript:vMain.height>` down a 63 px strip
        // below the skin. Built at the authored canvas instead, the size comparison below then
        // finds a mismatch and snaps the window back to it.
        let layoutSize = Self.authoredResizable(in: skin, viewID: viewID) ? requested : nil
        let overrides = presentation.sceneOverrides
        let scriptRuntime = scriptRuntime
        presentation.loadTask = Task { [weak self, weak presentation] in
            do {
                var resolvedOverrides = overrides
                var scriptOutput: WMPScriptOutput?
                if let scriptRuntime, let self {
                    let output = await scriptRuntime.transact(skin: skin, viewID: viewID,
                        size: requested, snapshot: self.host.snapshot, event: nil,
                        geometry: presentation?.activeScene?.scriptGeometry ?? [:])
                    resolvedOverrides = output.overrides
                    scriptOutput = output
                }
                var scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: viewID, requestedSize: layoutSize, overrides: resolvedOverrides)
                // The resize is now laid out, so what moved is a fact rather than a guess, and the
                // skin's own `onResize` can run against it. Corona's `EqResize` re-spaces its ten
                // sliders from `svEqualizerTopMiddle.width`; without this they stay at the spacing
                // the window opened with and slide out from under their labels.
                if let scriptRuntime, let self,
                   let event = Self.resizeEvent(in: skin, viewID: viewID,
                                                before: presentation?.activeScene, after: scene) {
                    let output = await scriptRuntime.transact(skin: skin, viewID: viewID,
                        size: scene.canvasSize, snapshot: self.host.snapshot, event: event,
                        geometry: scene.scriptGeometry)
                    resolvedOverrides = output.overrides
                    scriptOutput = output
                    scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                        .build(viewID: viewID, requestedSize: layoutSize, overrides: resolvedOverrides)
                }
                let result = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: self?.renderScale(for: scene.canvasSize) ?? 1,
                    clock: presentation?.animationClock(for: scene.viewID) ?? 0,
                    slotClocks: Self.slotClocks(presentation, for: scene, store: store))
                try Task.checkCancellation()
                guard let self, let presentation else { return }
                // The same rule the transaction path applies: a canvas the builder clamped away
                // from what the window asked for is the skin's floor, and the window follows it.
                // `windowWillResize` already holds a live drag inside the limits, so this is for
                // the window that was already outside them when the limits moved (W196).
                if scene.canvasSize != requested {
                    self.setWindowSize(presentation, NSSize(width: scene.canvasSize.width,
                                                            height: scene.canvasSize.height))
                }
                presentation.sceneOverrides = resolvedOverrides
                presentation.activeScene = scene
                self.startAnimation(presentation, for: scene)
                if let scriptOutput {
                    presentation.presentedListItems = scriptOutput.listItems
                    presentation.presentedWidgetState = scriptOutput.widgetState
                    presentation.mainView?.updateListItems(scriptOutput.listItems)
                    presentation.mainView?.updateWidgetState(scriptOutput.widgetState)
                }
                presentation.mainView?.present(result.image, overlay: result.overlayImage, silhouette: result.silhouetteMask, scene: scene, traceSource: "load")
                presentation.mainView?.refreshHostState(self.host.snapshot)
                if let scriptOutput {
                    let switchedView = self.applyHostCommands(scriptOutput.hostCommands,
                                                              from: presentation)
                    if !switchedView {
                        self.applyTimerDelta(presentation, registered: scriptOutput.timerRequests,
                                             cleared: scriptOutput.clearedTimerTokens)
                    }
                    self.recordScriptDiagnostics(scriptOutput.diagnostics)
                }
            } catch is CancellationError {} catch {
                self?.lastLoadDiagnostic = error.localizedDescription
            }
        }
    }

    func prepareForUITeardown() {
        loadTask?.cancel()
        loadTask = nil
        artworkLoadTask?.cancel()
        artworkLoadTask = nil
        artworkTrackID = nil
        // The materializer first, so no auxiliary window outlives the mode.
        materializer.invalidate()
        stopDispatcher()
        if let scriptRuntime { Task { await scriptRuntime.teardown() } }
        scriptRuntime = nil
        lastScriptSnapshot = nil
        spectrumConsumers.removeAll()
        videoSurface.detach(reveal: false)
        unskinnedView?.onImport = nil
        unskinnedView?.onMinimize = nil
        unskinnedView?.onClose = nil
        unskinnedView?.host = nil
        unskinnedView = nil
        clearSurfacePalette()
        loadedSkin = nil
        imageStore = nil
        host.stopContinuousCommands()
    }

    // MARK: - Opening, switching and closing a window

    /// **`theme.openView` opens an additional window and leaves the opener alone.**
    ///
    /// A view already open is *raised*, never opened twice — which is what lets a dispatcher skin
    /// re-open its own panels from `theme.loadPreference` at load without ending up with two of
    /// each, and what makes a NullPlayer menu toggle for an already-visible surface inert.
    ///
    /// `offset` is `theme.openViewRelative`'s displacement in skin pixels from `opener`'s top-left.
    private func openView(_ requestedID: String, from opener: WMPViewPresentation?,
                          offset: CGPoint?) {
        guard let skin = loadedSkin, skin.views.contains(where: {
            $0.id.caseInsensitiveCompare(requestedID) == .orderedSame
        }) else { return }
        if let existing = materializer.presentation(for: requestedID) {
            materializer.raise(existing)
            return
        }
        // Bounded like the covered-view stack it replaces. A skin that opens a window on every tick
        // of its own dispatcher must not be able to open an unbounded number of them.
        guard materializer.openPresentations.count < Self.maximumOpenViews else { return }
        loadView(requestedID, into: nil, opener: opener, offset: offset)
    }

    /// `theme.currentViewID` replaces the view inside the **calling** window. The window survives;
    /// the view it was showing does not, so its script scope is discarded.
    func switchView(to requestedID: String) {
        guard let player = materializer.playerPresentation else { return }
        switchView(player, to: requestedID)
    }

    func switchView(_ presentation: WMPViewPresentation, to requestedID: String) {
        guard let skin = loadedSkin, skin.views.contains(where: {
                  $0.id.caseInsensitiveCompare(requestedID) == .orderedSame
              }), requestedID.caseInsensitiveCompare(presentation.viewID) != .orderedSame
        else { return }
        loadView(requestedID, into: presentation, opener: presentation, offset: nil)
    }

    /// Present a view — into the window that is already showing another one, or into a new window of
    /// its own when `existing` is nil.
    ///
    /// **A view arrived at by either route loads exactly as one arrived at by launch.** Initial load
    /// raises `load`, honours the host commands the handler posts and schedules the timers it asks
    /// for; this path did none of the three for a long time (W46), and a `.wmz` compact mode is
    /// built out of all three. Corona's `viewTiny` is authored `timerInterval="0"` and animates
    /// itself into the mini player entirely from `OnTinyLoad` — which registers a timed event and
    /// writes `view.timerInterval`, a `setViewTimerInterval` host command. With the load event
    /// dropped the handler never ran; with the commands dropped the interval never arrived. So the
    /// view switched and then sat at frame zero, which for Corona is drawn from the same artwork at
    /// the same size as `vPlayer`: **the compact view was visually indistinguishable from the
    /// player**, and the only symptom was that the playlist and equaliser buttons stopped answering.
    ///
    /// **There is no `restoring` parameter any more.** It existed to put a *covered* view back as it
    /// was left, because `theme.openView` presented over it in the one window there was. A covered
    /// view is now genuinely never touched — it is in its own window, still running — which is what
    /// that restore was simulating (W90).
    private func loadView(_ requestedID: String, into existing: WMPViewPresentation?,
                          opener: WMPViewPresentation?, offset: CGPoint?) {
        guard let skin = loadedSkin, let store = imageStore,
              let registration = skin.views.first(where: {
                  $0.id.caseInsensitiveCompare(requestedID) == .orderedSame
              }), let scriptRuntime else { return }
        let key = WMPPath.fold(registration.id)
        let previousViewID = existing?.viewID
        if let existing {
            existing.loadTask?.cancel()
            existing.scriptTask?.cancel()
            existing.stopAllTimers()
            existing.mainView?.cancelInputCapture()
        } else if pendingOpenTasks[key] != nil {
            return
        }
        host.stopContinuousCommands()
        let oldTopLeft = existing.map {
            NSPoint(x: $0.window.frame.minX, y: $0.window.frame.maxY)
        }
        let frameStore = WMPViewFrameStore(defaults: importer.defaults)
        let skinName = importer.selectedSkinName ?? ""
        // **A stored size belongs to a view the user can size, and to no other (W213).** The store
        // keeps whatever the window came to rest at, and `windowDidResize` files it on any resize —
        // including one this app made rather than the user. A fixed view then re-opens at it: the
        // builder honours `requestedSize` by design (it is also how a donor view is rendered at
        // *our* window's size for a hosted frame, W209), and the limits do not refuse it either,
        // since `minimum` falls back to the authored size and most of the corpus authors no
        // maximum. `circle`'s 192x82 `vMain` came back **192x145**, with its
        // `<EFFECTS height="jscript:vMain.height">` filling the extra 63 px as a bar spectrum
        // hanging off the bottom of the skin (reported 2026-09-17). The origin is not gated the
        // same way: where the user put a window is the user's decision at any size.
        // **And a stored size is only worth restoring while it is still a window on this machine.**
        // The store files whatever the window came to rest at, so a skin that sized its own video
        // view from the decoder left that size behind for every later launch — the defect outlived
        // its own fix, because the window no longer *grows* but was still *restored* huge. A size
        // at or past the display is not a size a user chose (macOS clamps a drag at the screen
        // edge), so it is dropped and the view opens at its own canvas again.
        let savedSize = Self.authoredResizable(in: skin, viewID: registration.id)
            ? frameStore.size(skin: skinName, view: registration.id)
                .flatMap { Self.restorableViewSize($0, for: window) } : nil
        let savedOrigin = frameStore.origin(skin: skinName, view: registration.id)
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.pendingOpenTasks.removeValue(forKey: key) }
            if let previousViewID { await scriptRuntime.discardView(previousViewID) }
            await scriptRuntime.discardView(registration.id)
            do {
                let base = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: registration.id, requestedSize: savedSize)
                let loadEvent = WMPJScriptEvent(
                    name: "load", targetID: registration.id,
                    handlers: Self.handlers(in: skin, event: "load", targetID: nil,
                                            viewID: registration.id))
                let output = await scriptRuntime.transact(skin: skin, viewID: registration.id,
                    size: base.canvasSize, snapshot: host.snapshot, event: loadEvent,
                    geometry: base.scriptGeometry, animatesTweens: Self.animatesLoadTweens)
                // A windowless view — `controlView`, `pharaoh`'s `vGhost` — runs its script and
                // hands off; it must never become a window. Whatever it asks for next is honoured,
                // and if it asks for nothing nothing happens. A view can also declare itself
                // windowless *in* that `onLoad` by writing zero, so the same `collapsed` test
                // initial load applies belongs here: `Halo 2`'s `previewView` blanks itself and
                // redirects, and presenting it would leave an empty window the size of a thumbnail.
                let collapsed = ["width", "height"].contains { property in
                    output.overrides.geometry[.init(stableID: registration.node.stableID,
                                                    property: property)] == 0
                }
                guard base.canvasSize.width > 0, base.canvasSize.height > 0, !collapsed else {
                    recordScriptDiagnostics(output.diagnostics)
                    // A windowless view has no window to run the commands against, so they run
                    // against whoever asked for it — **except the ones that are about a window**,
                    // when the view was asked for by `theme.openView`. See `redirectedToOwnWindow`.
                    let commands = existing == nil
                        ? Self.redirectedToOwnWindow(output.hostCommands) : output.hostCommands
                    if let target = existing ?? opener ?? materializer.playerPresentation {
                        _ = applyHostCommands(commands, from: target)
                    }
                    return
                }
                var scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: registration.id,
                           requestedSize: Self.loadedCanvas(assigned: output.viewSize,
                                                            opened: base.canvasSize),
                           overrides: output.overrides)
                var overrides = output.overrides
                // **The window opened at a size the view was never authored at, which is a resize
                // (W211).** See `opensResized`. Only the overrides are taken from this pass: the
                // load's own host commands and timer set are what the code below applies, and a
                // second transaction's empty `timerRequests` would cancel the timers `onLoad` had
                // just registered — the trap the `viewchange` dispatch at the end of this method
                // already records.
                if Self.opensResized(in: skin, viewID: registration.id, opened: scene) {
                    let builder = WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    let authored = try await builder.build(viewID: registration.id,
                        requestedSize: Self.authoredCanvas(in: skin, viewID: registration.id),
                        overrides: Self.unclampedOverrides(output.overrides, in: skin,
                                                           viewID: registration.id))
                    if let event = Self.resizeEvent(in: skin, viewID: registration.id,
                                                    before: authored, after: scene) {
                        let resized = await scriptRuntime.transact(skin: skin,
                            viewID: registration.id, size: scene.canvasSize,
                            snapshot: host.snapshot, event: event, geometry: scene.scriptGeometry)
                        overrides = resized.overrides
                        scene = try await builder.build(viewID: registration.id,
                                                        requestedSize: scene.canvasSize,
                                                        overrides: overrides)
                        recordScriptDiagnostics(resized.diagnostics)
                    }
                }
                let rendered = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: renderScale(for: scene.canvasSize),
                    clock: existing?.animationClock(for: scene.viewID) ?? 0,
                    slotClocks: Self.slotClocks(existing, for: scene, store: store))
                try Task.checkCancellation()
                let size = NSSize(width: scene.canvasSize.width, height: scene.canvasSize.height)
                guard let presentation = existing ?? materializer.materialize(
                    viewID: registration.id, size: size, opener: opener, offset: offset,
                    storedTopLeft: savedOrigin) else { return }
                apply(skin: skin, store: store, scene: scene, image: rendered.image,
                      overlay: rendered.overlayImage, silhouette: rendered.silhouetteMask,
                      runtime: scriptRuntime, overrides: overrides, into: presentation)
                if let oldTopLeft {
                    presentation.window.setFrameOrigin(
                        NSPoint(x: oldTopLeft.x, y: oldTopLeft.y - presentation.window.frame.height))
                }
                // `apply` has just set the view timer from the markup, which is the default the
                // script's `setViewTimerInterval` overrides — so the commands run after it, in
                // that order. A command that switches again owns the timers of the view it moved
                // to, exactly as on initial load.
                let switchedAgain = applyHostCommands(output.hostCommands, from: presentation)
                recordScriptDiagnostics(output.diagnostics)
                guard !switchedAgain else { return }
                applyTimerDelta(presentation, registered: output.timerRequests,
                                cleared: output.clearedTimerTokens)
                WMPTweenTrace.log("load view=\(registration.id)"
                    + " clock=\(Self.animatesLoadTweens) hasActiveTweens=\(output.hasActiveTweens)")
                startTweenLoop(presentation, hasActiveTweens: output.hasActiveTweens)
                // Gated on an authored handler, like hover, and for the timers rather than the
                // cost: a transaction's `timerRequests` are what *that* transaction registered, so
                // an unconditional binding-only `viewchange` immediately posted an empty set and
                // cancelled every script timer the `load` above had just scheduled. A window that
                // has just opened has not changed its view, so it raises nothing.
                guard existing != nil else { return }
                dispatchScriptEvent(presentation, name: "viewchange", targetID: registration.id,
                                    onlyWhenAuthored: true)
            } catch is CancellationError {} catch { lastLoadDiagnostic = error.localizedDescription }
        }
        if let existing { existing.loadTask = task } else { pendingOpenTasks[key] = task }
    }

    /// A windowless view that was asked for by `theme.openView` is asking for **its own window**,
    /// so the window-scoped commands its `onLoad` posts belong to that window — not to the one that
    /// opened it.
    ///
    /// `theme.openView` opens a window beside the opener and leaves the opener alone; a view with no
    /// canvas has no window to leave anything in, and running its commands against the *opener*
    /// turns every one of them into something the skin never asked for. `pharaoh` is the whole
    /// case and it states both halves:
    ///
    /// - `<view id="vGhostAutoDetect" width="0" height="0"
    ///    onLoad="…theme.currentViewID='vRos';…">` — its transport's *Audio controls/Playlist/Video*
    ///   button calls `theme.openView('vGhostAutoDetect')`, and the redirect landed on the player,
    ///   so the 400x249 sphinx **became** the 197x194 rosetta panel. `CloseRos()`'s `vRos.close()`
    ///   then closed the app's only window: reported as *"you can get trapped in the mini windows
    ///   with no way back to the main window"*, and it is sticky, because the skin saves
    ///   `paneOpen` and reads it back at the next launch.
    /// - `<view id="vGhost" …  onLoad="…else view.close();">` — opened from `OnLoad()` on every
    ///   launch, and with `paneOpen` false that `view.close()` closed the player before the user
    ///   ever saw it.
    ///
    /// So a redirect becomes an `openView` of its own, and a close or a minimise of a window that
    /// was never made is dropped. `theme.closeView('name')` is untouched: it names its target, and
    /// naming one is not the same as meaning your own. Everything else — transport, preferences,
    /// timers — is host-level and runs against the opener exactly as before.
    ///
    /// **Two archives reach this at all**: `pharaoh`'s two ghosts and `cyberchannel`'s `playView`
    /// are the corpus's only `openView` targets with no canvas (scan of 185 installed archives,
    /// decoded as `WMPTextDecoder` does: 158 UTF-16, 146 cp1252, 89 UTF-8, 9 UTF-8-BOM). A view
    /// that *becomes* windowless in its own `onLoad` — `Halo 2`'s `previewView` — is reached by a
    /// switch, has an `existing` window, and is not redirected.
    static func redirectedToOwnWindow(_ commands: [WMPJScriptHostCommand]) -> [WMPJScriptHostCommand] {
        commands.compactMap { command in
            switch command.action {
            case "setCurrentView":
                return WMPJScriptHostCommand(action: "openView", value: command.value)
            case "closeView" where command.value?.string == nil, "minimizeWindow", "sizeWindow":
                return nil
            default:
                return command
            }
        }
    }

    /// **Close one window.** `view.close()`, `theme.closeView(name)` and the macOS close control all
    /// arrive here.
    ///
    /// How closing the player quits the app. **A seam only so a unit test can close a player
    /// window without taking the test runner down with it** — `WMPPhase9Tests` asserts that the
    /// panels go with the player, which means driving the real close path. The app never replaces
    /// it.
    static var terminateApplication: () -> Void = { NSApp.terminate(nil) }

    /// Closing the **player** closes the whole skin UI: the player window is the one WMP's own close
    /// control means, and leaving panels up with no player behind them is the W96 class of defect
    /// this change exists to delete. Closing an auxiliary window closes only it, and the player —
    /// still running, still animating, still holding its own overrides — is untouched, which is what
    /// the covered-view stack used to simulate.
    @discardableResult
    func closeViewWindow(_ presentation: WMPViewPresentation) -> Bool {
        // NVIDIA's close is an in-place mode transition, not a window closing at all.
        if closeNVIDIAEmbeddedMode(presentation) { return false }
        if presentation.isPlayer {
            // **Closing the player closes NullPlayer, as it does in every other family.** Classic
            // and Original both terminate from their own close button
            // (`MainWindowView`/`ModernMainWindowView` — `NSApplication.terminate`), and real WMP
            // quits when its player window is closed. `applicationShouldTerminateAfterLastWindowClosed`
            // is false, so ordering this window out left the app running with nothing on screen
            // and nothing but the Dock to get it back. Reported 2026-09-19 as "the close button
            // does not exit"; before that it was reported as a *frozen* skin, because the window
            // the controller keeps for its whole life outlived the presentation and could be
            // ordered back in with no scene, no hit map and no timer behind it (`Disney_Mix_Central`
            // and the 23 other Skins Factory archives, whose close button writes a preference that
            // their windowless `controlView` dispatcher turns into this call 100 ms later).
            // Quitting answers both, and the corpse state it used to leave no longer exists.
            //
            // **The close handlers are flushed before the teardown, not after it.** Every open
            // view's `onClose` is where a `.wmz` saves its state, and the teardown posts them as a
            // `Task` that a process on its way out never gets to run.
            flushCloseHandlersOnTermination()
            for other in materializer.openPresentations where other !== presentation {
                closeAuxiliaryWindow(other)
            }
            let viewID = presentation.viewID
            let size = presentation.activeScene?.canvasSize
            materializer.remove(presentation, closing: true)
            closeScriptView(viewID, size: size)
            persistOpenViews()
            Self.terminateApplication()
            return true
        }
        closeAuxiliaryWindow(presentation)
        persistOpenViews()
        return true
    }

    private func closeAuxiliaryWindow(_ presentation: WMPViewPresentation) {
        let viewID = presentation.viewID
        let size = presentation.activeScene?.canvasSize
        if let view = presentation.mainView { setSpectrumDemand(false, from: ObjectIdentifier(view)) }
        materializer.remove(presentation)
        closeScriptView(viewID, size: size)
        arbitrateVideoSurface()
    }

    /// **`onClose` is a view's last transaction, and it is where a `.wmz` saves its state.**
    ///
    /// It had no dispatch site at all: `discardView` dropped the view's scope and its live elements
    /// and the handler never ran, so **373 `onClose` handlers across 133 of the 180 archives** were
    /// dead. What they do is persist — `xsn_sports` closes with
    /// `saveVisPrefs()`/`saveVidPrefs()`, which write `visDrawerStatus` and the view's own size
    /// through `theme.savePreference`, and its `onLoad` restores both. With nothing saved,
    /// `theme.loadPreference` answered the `--` absent sentinel on every launch and `loadVisPrefs`
    /// took its first-run branch, so the settings drawer opened itself every single time and no
    /// window remembered its size. Reported as "when the skin launches it is open" (W144).
    ///
    /// The transaction runs *before* `discardView`, because the handler needs the view's elements
    /// and the skin's globals, and the preference writes it posts are committed inside `transact`.
    /// It renders nothing: the window is already gone, and a scene built for it would have nowhere
    /// to go. A view with no authored handler skips straight to the discard, which is what every
    /// close did before.
    private func closeScriptView(_ viewID: String, size: WMPSize?) {
        guard let scriptRuntime else { return }
        let handlers = loadedSkin.map {
            Self.handlers(in: $0, event: "close", targetID: nil, viewID: viewID)
        } ?? []
        let skin = loadedSkin
        let snapshot = host.snapshot
        Task { [weak self] in
            if let skin, let size, !handlers.isEmpty {
                let output = await scriptRuntime.transact(
                    skin: skin, viewID: viewID, size: size, snapshot: snapshot,
                    event: WMPJScriptEvent(name: "close", targetID: nil, handlers: handlers))
                await MainActor.run { self?.recordScriptDiagnostics(output.diagnostics) }
            }
            await scriptRuntime.discardView(viewID)
        }
    }

    /// **Quitting is a close too, and the app does not come back to finish an asynchronous one.**
    ///
    /// `applicationWillTerminate` returns and the process exits, so the `Task` an ordinary close
    /// posts never gets to run: a skin that saves its state in `onClose` saved nothing unless the
    /// user had closed its window by hand first, which is most of the time nobody. This runs the
    /// same transaction for every open view and *waits* for it.
    ///
    /// Waiting on the main thread is safe here and nowhere else: nothing on the script path touches
    /// `MainActor` — no `MainActor.run`, no main-actor-isolated type in `WMPScriptRuntime`,
    /// `WMPScriptContext` or `WMPObjectModel` — so the wait cannot deadlock against the thread it
    /// blocks. It is bounded anyway, and each handler is separately capped by
    /// `WMPPhase0Limits.scriptExecutionSeconds`.
    func flushCloseHandlersOnTermination(timeout: TimeInterval = 2) {
        guard let scriptRuntime, let skin = loadedSkin else { return }
        let snapshot = host.snapshot
        let pending: [(String, WMPSize, [String])] = materializer.openPresentations
            .compactMap { presentation in
                let handlers = Self.handlers(in: skin, event: "close", targetID: nil,
                                             viewID: presentation.viewID)
                guard !handlers.isEmpty, let size = presentation.activeScene?.canvasSize
                else { return nil }
                return (presentation.viewID, size, handlers)
            }
        guard !pending.isEmpty else { return }
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            for (viewID, size, handlers) in pending {
                _ = await scriptRuntime.transact(
                    skin: skin, viewID: viewID, size: size, snapshot: snapshot,
                    event: WMPJScriptEvent(name: "close", targetID: nil, handlers: handlers))
            }
            finished.signal()
        }
        _ = finished.wait(timeout: .now() + timeout)
    }

    /// Which auxiliary views are open, so the next launch can put them back. The player's view is
    /// not one of them — that is `WMPSkinImporter.selectedViewIDKey`.
    private func persistOpenViews() {
        guard loadedSkin != nil else { return }
        let open = materializer.openPresentations.filter { !$0.isPlayer }.map(\.viewID)
        WMPViewFrameStore(defaults: importer.defaults)
            .setOpenViews(open, skin: importer.selectedSkinName ?? "")
    }

    /// Persist one window's size and origin, so the user's own arrangement survives a relaunch.
    func persistViewFrame(for window: NSWindow) {
        guard let presentation = materializer.presentation(for: window), loadedSkin != nil else { return }
        let store = WMPViewFrameStore(defaults: importer.defaults)
        let skinName = importer.selectedSkinName ?? ""
        store.setOrigin(CGPoint(x: presentation.window.frame.minX,
                                y: presentation.window.frame.maxY),
                        skin: skinName, view: presentation.viewID)
    }

    // MARK: - Window delegate (the player window; the materializer owns the panels')

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // The skin's own limits are in the skin's own pixels, so the drag is measured there and the
        // answer scaled back. A fixed skin stays fixed at every UI Size; a resizable one keeps the
        // range it authored, expressed at the current zoom.
        guard let presentation = materializer.presentation(for: sender),
              let limits = presentation.activeLimits else {
            return NSSize(width: Self.unskinnedSize.width * uiScale,
                          height: Self.unskinnedSize.height * uiScale)
        }
        // **A view that declares no `resizAble` refuses the resize rather than undoing it (W213).**
        // The window is borderless but carries `.resizable`, so AppKit offers edge drags whatever
        // `WMPMainView.edges(at:)` decides, and the limits alone do not refuse one: `minimum` is the
        // authored size and most of the corpus authors no maximum. Snapping back afterwards is not
        // the same thing — the window is live-resized first, and everything laid out from
        // `bounds / canvasSize` follows it while the skin's own raster does not, which is the
        // reported *"the visualization popped out and stretched but the app didn't"*. Refusing here
        // is the only place the stretch never happens at all.
        if presentation.activeScene?.isResizable == false {
            let scale = uiScale
            return NSSize(width: presentation.skinSpaceSize.width * scale,
                          height: presentation.skinSpaceSize.height * scale)
        }

        let clamped = limits.clamp(WMPSize(width: frameSize.width / uiScale,
                                           height: frameSize.height / uiScale))
        return NSSize(width: clamped.width * uiScale, height: clamped.height * uiScale)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let presentation = materializer.presentation(for: window) else { return }
        windowDidResize(presentation)
    }

    func windowDidResize(_ presentation: WMPViewPresentation) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["WMP_SIZE_TRACE"] != nil {
            NSLog("[wmp/size] \(presentation.viewID) -> \(presentation.window.frame.size) "
                + "applying=\(presentation.isApplyingSceneSize)\n"
                + Thread.callStackSymbols.prefix(14).joined(separator: "\n"))
        }
        #endif
        presentation.skinSpaceSize = NSSize(width: presentation.window.frame.width / uiScale,
                                            height: presentation.window.frame.height / uiScale)
        // Persisted in skin space as well, so a size the user dragged out at 200% is not restored
        // as a scene twice that size the next time the skin loads — and only for a view the user
        // can size at all. A fixed view has no size of the user's to keep, and every resize it sees
        // is this app's (W213); filing those is how `circle`'s 192x82 player had 192x145 on record.
        if let skin = loadedSkin, Self.authoredResizable(in: skin, viewID: presentation.viewID) {
            WMPViewFrameStore(defaults: importer.defaults).setSize(
                WMPSize(width: presentation.skinSpaceSize.width,
                        height: presentation.skinSpaceSize.height),
                skin: importer.selectedSkinName ?? "", view: presentation.viewID)
        }
        renderCurrentSize(presentation)
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        guard let presentation = materializer.playerPresentation else { return }
        renderCurrentSize(presentation)
    }
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        // A window dragged to another display changes what `event.screenWidth` means, and a skin
        // reads it to decide how far it may grow itself — `Compact`'s drawers do it on every open.
        if let scriptRuntime {
            let size = Self.screenSize(for: window)
            let usable = Self.usableScreenSize(for: window)
            Task { await scriptRuntime.setScreen(size, usable: usable) }
        }
        let origin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: origin)
        persistViewFrame(for: window)
    }
    /// What a skin means by `event.screenWidth`: the resolution of the display its window is on,
    /// in points, falling back to the main display and then to the harness default so the number is
    /// never zero — a skin divides by it and clamps its own window against it.
    /// The modifiers held right now, for WMP's `event.shiftKey` and its siblings. Read at dispatch
    /// rather than carried up from the `NSEvent`, because the script events that need it arrive
    /// from widget callbacks — an `<EDITBOX>`'s text, a slider's value — which have no event of
    /// their own by the time they reach here.
    static func currentEventModifiers() -> WMPEventModifiers {
        let flags = NSEvent.modifierFlags
        var modifiers: WMPEventModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.alt) }
        return modifiers
    }

    static func screenSize(for window: NSWindow?) -> WMPSize {
        guard let frame = (window?.screen ?? NSScreen.main)?.frame else {
            return WMPObjectModel.defaultScreen
        }
        return WMPSize(width: frame.width, height: frame.height)
    }

    /// How big a `.wmz` window may be and still be reachable: the display's visible frame, which is
    /// the desktop minus the menu bar and the Dock. **Not `screenSize`** — a borderless window
    /// clamped to the full frame hangs its bottom edge under the Dock, and the corpus draws its
    /// video drawer, its zoom and its resize grip along that edge. Every view size the skin or its
    /// script asks for is fitted into this; see `WMPSize.fitted(within:)`.
    /// A stored view size, or nil where it is one this display cannot show as a window.
    ///
    /// Two shapes are refused: past the usable area in either axis — the raw decoder size, 2580x1532
    /// for a 1440p film under `Combat_Flight_Simulator_3` — and *filling* it in both, which is what
    /// the same size looks like once it has been fitted to the display and filed away. Nobody drags
    /// a borderless skin window to exactly the whole desktop; macOS clamps the drag at the edge, so
    /// this is the fingerprint of a size the skin set rather than one the user chose. A window
    /// genuinely dragged to the full height *or* the full width of the screen keeps its restore.
    ///
    /// `WMPSize.fitted(within:)` is the other half: it stops the size being created, and this stops
    /// the ones already on disk being handed back. Without both, the fix outlives nothing — the
    /// window stops growing and goes on *opening* at the size an earlier session filed.
    static func restorableViewSize(_ size: WMPSize, for window: NSWindow?) -> WMPSize? {
        let ceiling = usableScreenSize(for: window)
        guard size.width > 0, size.height > 0 else { return nil }
        if size.width > ceiling.width || size.height > ceiling.height { return nil }
        if size.width >= ceiling.width, size.height >= ceiling.height { return nil }
        return size
    }

    static func usableScreenSize(for window: NSWindow?) -> WMPSize {
        guard let frame = (window?.screen ?? NSScreen.main)?.visibleFrame else {
            return WMPObjectModel.defaultScreen
        }
        return WMPSize(width: frame.width, height: frame.height)
    }

    func windowWillMiniaturize(_ notification: Notification) {
        if let window { WindowManager.shared.attachDockedWindowsForMiniaturize(mainWindow: window) }
    }
    func windowDidDeminiaturize(_ notification: Notification) {
        if let window { WindowManager.shared.detachDockedWindowsAfterDeminiaturize(mainWindow: window) }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        // Deferred a turn: raised while a click is still activating the app, the window server
        // takes only some of the reorders, leaving panels behind another app's window and one
        // above the window that was clicked (W273).
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, window.isKeyWindow else { return }
            WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
        }
    }

    /// **The macOS close control closes the window it is on, like every other close route.**
    ///
    /// It used to mean `closeView` whenever anything had been opened over the player, because the
    /// one window was standing in for two and letting AppKit order it out stranded the user on a
    /// playlist with no route back (Plus! Professional, W127). With the panel in its own window
    /// that compensation has no job: this is the player, and closing the player closes the skin.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window,
              let presentation = materializer.presentation(for: sender) else { return true }
        return closeViewWindow(presentation)
    }

    // MARK: - Host state

    func updateTrackInfo(_ track: Track?) {
        updateArtwork(for: track)
        refreshHostState()
    }
    func updateVideoTrackInfo(title: String, artworkTrack: Track?) {
        updateArtwork(for: artworkTrack)
        refreshHostState()
    }
    func clearVideoTrackInfo() {
        updateArtwork(for: nil)
        refreshHostState()
    }
    func updateTime(current: TimeInterval, duration: TimeInterval) { refreshHostState() }
    func updatePlaybackState() { refreshHostState() }

    /// The skin has already assigned a reserved pseudo-resource name by the time this completes.
    /// Rebuilding changes only that resource's pixels; it never exposes a track URL to JScript.
    private func updateArtwork(for track: Track?) {
        let newID = track?.id
        guard artworkTrackID != newID else { return }
        artworkLoadTask?.cancel()
        artworkLoadTask = nil
        artworkTrackID = newID
        imageStore?.setAlbumArtwork(nil)
        renderAlbumArtwork()
        guard let track else { return }
        artworkLoadTask = Task { [weak self] in
            let image = await WMPArtworkLoader.loadArtwork(for: track)
            guard !Task.isCancelled, let self, self.artworkTrackID == track.id else { return }
            self.imageStore?.setAlbumArtwork(image)
            self.renderAlbumArtwork()
            self.artworkLoadTask = nil
        }
    }

    private func renderAlbumArtwork() {
        for presentation in materializer.openPresentations where presentation.activeScene != nil {
            renderInteraction(presentation, state: presentation.interactionState, changed: [])
        }
    }
    func updateSpectrum(_ levels: [Float]) {
        for presentation in materializer.openPresentations {
            presentation.mainView?.updateSpectrum(levels)
        }
    }
    func skinDidChange() {}
    func windowVisibilityDidChange() {}

    func setNeedsDisplay() { window?.contentView?.needsDisplay = true }

    /// **`WMP_VIDEO_TRACE=1` — the live instrument for W252**, and the only one that reaches it:
    /// `WMP_CALL_TRACE` is a `swift test` harness flag and prints nothing in the running app, while
    /// a sweep's host snapshot never transitions, so no headless probe can see this edge at all.
    /// One line per host refresh that changes the open state, the play state or the picture size —
    /// which is the whole of what `Revert`'s `vwPlayer_SelectVideoOrVis()` branches on.
    static func traceVideoOpenEdge(previous: WMPHostSnapshot?, current: WMPHostSnapshot,
                                   events: [String]) {
        #if DEBUG
        guard videoTraceEnabled else { return }
        guard previous?.state != current.state
                || openState(previous) != openState(current)
                || previous?.video != current.video else { return }
        let line = "VIDEOEDGE state=\(previous?.state.rawValue ?? "nil")->\(current.state.rawValue)"
            + " openState=\(openState(previous))->\(openState(current))"
            + " imageSource=\(Int(current.video.width))x\(Int(current.video.height))"
            + " latched=\(current.videoEvent.hasVideo) events=\(events)\n"
        FileHandle.standardError.write(Data(line.utf8))
        #endif
    }

    #if DEBUG
    private static let videoTraceEnabled = ProcessInfo.processInfo.environment["WMP_VIDEO_TRACE"] == "1"
    #endif

    /// The `os*` value `player.openState` answers. The derivation itself lives beside the
    /// enumeration it answers from — `WMPScriptConstants.openState(for:)`, which is also what the
    /// object model's `player.openState` reads, so the property, the argument and this edge can
    /// never disagree. A nil snapshot is the state before anything was open.
    static func openState(_ snapshot: WMPHostSnapshot?) -> Int {
        WMPScriptConstants.openState(for: snapshot)
    }

    /// The two events that ride a host *state* edge, as a rule a test can drive.
    ///
    /// **An open state and a play state are two different quantities, and pausing changes only one
    /// of them.** These were raised together off `state`, so a pause told every skin that a media
    /// had just opened when none had. Reported live as *"pressing pause does not pause the
    /// stream"* and *"stop does not stop"*: `Plus! HueShifter`, `Plus! Plasma Ball` and
    /// `Plus! SlimLine` share an `OnOpenStateChange` whose `osMediaOpen` arm ends in
    /// `player.controls.play()`, so 16 ms after every pause the skin started playback again — and
    /// after a stop, the re-play found the player stopped and reloaded the track from zero. **109
    /// of the 180 installed archives author this handler**, so the wrong edge reached all of them;
    /// those three are the ones that answer it by playing. Invisible to every headless probe,
    /// because a sweep's host snapshot never transitions — W73's class.
    static func stateEdgeEvents(previous: WMPHostSnapshot?, current: WMPHostSnapshot) -> [String] {
        var events: [String] = []
        if previous?.state != current.state { events.append("playstatechange") }
        // **A new media opening is an open edge even when the queue never emptied (W275).** WMP
        // steps through `osMediaChanging` … `osMediaOpen` for every track, while `openState(for:)`
        // answers `osMediaOpen` for as long as the queue is non-empty, so a track change raised
        // nothing and `pharaoh`, which writes its title only from `OnOpenStateChange`, kept the
        // first track's name all session. Keyed on `sourceURL`, not on either half alone: a sort or
        // move changes `playlistIndex` with nothing opened, and a stream's ICY title changes the
        // rest of the metadata with nothing opened. The tracks of one cue sheet share a file, so
        // for them it is the index and the metadata moving together.
        let mediaChanged: Bool = {
            guard let previous, openState(current) == WMPScriptConstants.osMediaOpen,
                  !current.metadata.sourceURL.isEmpty else { return false }
            if previous.metadata.sourceURL != current.metadata.sourceURL { return true }
            return previous.playlistIndex != current.playlistIndex && previous.metadata != current.metadata
        }()
        if openState(previous) != openState(current) || mediaChanged { events.append("openstatechange") }
        return events
    }

    /// **The comparison happens once; the dispatch fans out to every open window.**
    ///
    /// The snapshot is the session's, so deciding what changed twice would be wrong as well as
    /// wasteful. What is per window is the transaction: each runs in its own view scope, against its
    /// own elements, producing its own overrides.
    ///
    /// Two bounds matter. The runtime's 120-transactions-per-second limit is shared across the
    /// session — `Halo 2` with five panels plus its dispatcher at 10 Hz is about 60/s, under but not
    /// by much — so a window with nothing to settle is **skipped** rather than run: no `wmpprop:` or
    /// `wmpenabled:` binding in its view and no authored handler for anything being raised means the
    /// transaction can have no effect. And `WMPScriptContext` is one serial queue, so N windows'
    /// transactions serialize; that is already true of the dispatcher and is the isolation boundary
    /// rather than a cost to design away.
    private func refreshHostState() {
        let snapshot = host.snapshot
        for presentation in materializer.openPresentations {
            presentation.mainView?.refreshHostState(snapshot)
        }
        unskinnedView?.refresh(snapshot)
        guard let skin = loadedSkin, scriptRuntime != nil else { return }
        let previous = lastScriptSnapshot
        lastScriptSnapshot = snapshot
        var events: [String] = []
        events += WMPVideoPresentation.events(previous: previous?.videoEvent, current: snapshot.videoEvent)
        events += Self.stateEdgeEvents(previous: previous, current: snapshot)
        Self.traceVideoOpenEdge(previous: previous, current: snapshot, events: events)
        // **`status_onchange` is WMP's "the status string changed", and a clock tick is not that
        // (W119).** The bindings do have to settle ten times a second — the elapsed readout of 108
        // archives is `<TEXT value="wmpprop:player.controls.currentPositionString">` and 89 hang a
        // seek slider off `player.controls.currentPosition` — so a position tick still runs a
        // transaction. What it must not do is raise the skin's *authored* handler: `status_onchange`
        // is authored by **70 of the 177 measurable archives and every one of its 75 sources is a
        // metadata updater**, 35 of them `updateMetadata()`, whose whole body is
        // `metadata.value = player.status`, so raising it on every tick ran that updater ten times
        // a second: `9SeriesDefault` runs `ShowStatus(player.status)` and drew an empty metadata
        // line beside a correct clock, reported as no track information. **`player.status` is a
        // real sentence since 2026-09-14 and the trap is unchanged** — the cost was the rate, not
        // the emptiness, and a status string that moves with the clock is still not a thing. It also ran a
        // whole script transaction, scene rebuild and render at 10 Hz in every skin, cancelling
        // whatever click or `onTimer` transaction was still in flight.
        //
        // `hostsettle` is a name **no corpus archive authors**, which is the point — it resolves to
        // no handler anywhere, so the transaction it raises is the binding-only one
        // `dispatchScriptTransaction` already documents. It used to be spelled `positionchange` on
        // the claim that nothing authored *that* either, and that was wrong: `onPositionChange` is
        // the CUSTOMSLIDER handler WMP raises when the **user** moves the control, and **24 of the
        // 180 installed archives author 71 of them** — every `srs_slider`/`eq` slider in the
        // Halo 2, STALKER, Catwoman, Alienware and Plus! families. `handlers(in:event:)` strips the
        // `on` prefix, so a clock tick was raising all of them ten times a second with `value`
        // unbound (the transaction carries no target), which is a whole script transaction per tick
        // per slider for a handler whose only correct trigger is a drag. A duration that changes is
        // a media that opened rather than a clock that ticked, so that keeps the status raise.
        // The status *string* changing is the event's own subject, and it moves only on a state
        // transition — `WMPHostSnapshot.statusText` is derived from `state` and whether anything is
        // open, so this is bounded by the same edges `playstatechange` already rides and can never
        // become a tick. It was missing only because the string was empty in every state.
        if previous?.metadata != snapshot.metadata || previous?.duration != snapshot.duration
            || previous?.statusText != snapshot.statusText {
            events.append("status_onchange")
        }
        // **A control the user is holding is the user's.** `Plus! Pulsar` authors
        // `<controls currentPosition_onchange="seekMain.value=player.controls.currentPosition;">`,
        // so every tick of the clock writes the live position into the element its own
        // `onmouseup="player.controls.currentPosition=seekMain.value;"` is about to read. Raising
        // these two while a slider is captured makes the seek commit to wherever the track already
        // was — measured live: dragged to 36s, committed 79s. The clock stops updating for the
        // length of the drag, which is what WMP does and what a scrub looks like everywhere else.
        if previous?.currentTime != snapshot.currentTime, !sliderCaptureActive {
            events.append("hostsettle")
        }
        // **A host change the skin drove through a command still has to settle its own bindings.**
        // `eq.*` is the one host surface a `.wmz` both writes and binds: Halo 2's SRS button posts
        // `eq.enhancedAudio = !eq.enhancedAudio` and its TruBass and WOW sliders carry
        // `enabled="wmpprop:eq.enhancedAudio"`, so the transaction that flipped it resolved that
        // binding against the snapshot it started with — `false` — and no later event re-resolved
        // it. The two sliders drew, and hit-testing refused every click on them because the scene
        // said disabled; with a track playing the clock tick settled them a tenth of a second later
        // and they worked, which is what "sometimes" meant in the report. Volume, transport and the
        // rest never showed this because every one of their edges is already an event above.
        if previous?.equalizer != snapshot.equalizer { events.append("hostsettle") }
        // **The host half of the SDK's ambient `<attribute>_onchange` mechanism (W129).** The
        // element half is raised inside the transaction that wrote the attribute
        // (`WMPScriptContext.raiseAttributeChangeHandlers`); these four are attributes of the
        // *player*, which no script writes and which move underneath the skin — and they carry the
        // measured reach: `currentPosition_onchange` 77 skins, `currentEffectType_onchange` 57,
        // `currentPlaylist_onchange` 48, `currentMedia_onchange` 9, out of 387 authored handlers
        // across 104 of the 177 measured archives.
        //
        // Each rides the snapshot field the engine actually has behind the WMP name, so a raise
        // and a subsequent read can never disagree: `currentMedia` is the metadata of the open
        // media, `currentPlaylist` the queue's own items, `currentEffectType` the selection W101
        // made live and writable. Position is a clock tick, so this raise lands ten times a second
        // — which is what the skins authoring it are for (a readout painter), and it costs no new
        // transaction because `positionchange` already ran one on the same edge. **The W119 trap is
        // the opposite mistake and is not repeated here**: that was a clock tick raising
        // `status_onchange`, an event about a different quantity.
        if previous?.currentTime != snapshot.currentTime, !sliderCaptureActive {
            events.append("currentposition_onchange")
        }
        if previous?.metadata != snapshot.metadata { events.append("currentmedia_onchange") }
        if previous?.playlistItems != snapshot.playlistItems { events.append("currentplaylist_onchange") }
        if previous?.effects.type != snapshot.effects.type { events.append("currenteffecttype_onchange") }
        // `currentPreset_onchange` is the same element, the same idiom and the same write-back: all
        // 40 corpus uses are `mediacenter.effectPreset=currentPreset`. It is safe because
        // `WMPEffectSelection.setPreset` early-returns on an unchanged value, so the handler
        // handing the host back the number it was just given cannot loop or restart the visualizer
        // — the same settling argument W51's write-backs rest on.
        if previous?.effects.preset != snapshot.effects.preset {
            events.append("currentpreset_onchange")
        }
        if previous?.shuffle != snapshot.shuffle || previous?.repeatMode != snapshot.repeatMode {
            events.append("modechange")
        }
        if previous?.bufferingProgress != snapshot.bufferingProgress { events.append("buffering_onchange") }
        if previous?.receptionQuality != snapshot.receptionQuality { events.append("reception_onchange") }
        guard !events.isEmpty else { return }
        for presentation in materializer.openPresentations
        where hasSomethingToSettle(skin: skin, viewID: presentation.viewID, events: events) {
            for name in events where !presentation.pendingHostEvents.contains(name) {
                presentation.pendingHostEvents.append(name)
            }
            presentation.scriptTask?.cancel()
            presentation.scriptTask = Task { [weak self, weak presentation] in
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard !Task.isCancelled, let self, let presentation else { return }
                // Open, play, status, mode, buffering, then reception order — the dispatch order
                // the host contract fixes, whichever refresh each event was decided by.
                let names = Self.hostEventOrder.filter { presentation.pendingHostEvents.contains($0) }
                presentation.pendingHostEvents.removeAll()
                self.dispatchHostEvents(presentation, names)
            }
        }
    }

    /// Whether a host refresh can change anything in this view: a `wmpprop:`/`wmpenabled:` binding
    /// to settle, or an authored handler for one of the events being raised.
    ///
    /// With one window this question never had to be asked — the window either existed or the skin
    /// was not loaded. With several it is what keeps a skin that opens five panels inside the
    /// session's shared 120 transactions a second. The player, which has the bindings, is never the
    /// one skipped.
    private func hasSomethingToSettle(skin: WMPLoadedSkin, viewID: String,
                                      events: [String]) -> Bool {
        if declaresHostBinding(in: skin, viewID: viewID) { return true }
        return events.contains {
            !Self.handlers(in: skin, event: $0, targetID: nil, viewID: viewID).isEmpty
        }
    }

    /// Whether any node in this view binds to the host. Cached per skin and view: the answer is
    /// fixed by the markup before the skin loads, and this is asked on every host tick.
    private var bindingCache: [String: Bool] = [:]
    private func declaresHostBinding(in skin: WMPLoadedSkin, viewID: String) -> Bool {
        let viewKey = WMPPath.fold(viewID)
        if let cached = bindingCache[viewKey] { return cached }
        var included = Set<Int>()
        if let view = skin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        })?.node {
            func include(_ node: WMPNode) { included.insert(node.stableID); node.children.forEach(include) }
            include(view)
        }
        let answer = skin.graph.allNodes.contains { node in
            included.contains(node.stableID) && node.attributes.contains {
                if case .binding = $0.value { return true }
                return false
            }
        }
        bindingCache[viewKey] = answer
        return answer
    }

    private static let hostEventOrder = ["openstatechange", "playstatechange", "videostart", "videoend", "status_onchange",
                                         "currentmedia_onchange", "currentplaylist_onchange",
                                         "currenteffecttype_onchange", "currentpreset_onchange",
                                         "hostsettle", "currentposition_onchange", "modechange",
                                         "buffering_onchange", "reception_onchange"]

    private func renderInteraction(_ presentation: WMPViewPresentation,
                                   state: WMPInteractionState, changed: Set<Int>) {
        guard let skin = loadedSkin, let store = imageStore,
              let activeScene = presentation.activeScene else { return }
        let viewID = presentation.viewID
        presentation.loadTask?.cancel()
        presentation.interactionState = state
        presentation.loadTask = Task { [weak self, weak presentation] in
            do {
                // **An artwork repaint must never present the pane state a script transaction has
                // already replaced.** This path draws one thing — the hover/down image of the
                // control under the pointer — and it reads the *pane* state from
                // `presentation.sceneOverrides`, which the click's own transaction is writing at
                // the same moment. Reading it before the task and presenting whatever came back
                // put a scene built on `pl.visible=false` on screen 11 ms after the transaction
                // had opened the playlist: `claw`'s list appeared, the visualizer was recreated
                // over it, and the next transaction brought the list back ~300 ms later —
                // reported as "it displays, then goes black, then displays".
                //
                // So the overrides are read per attempt and re-checked after the render; a
                // transaction that landed in between owns the pane, and this repaint rebuilds
                // against what it wrote. Giving up after a few attempts is safe rather than a
                // compromise: `state` is stored on `presentation.interactionState` above, and
                // every other build path passes it, so the down/hover image is drawn by whichever
                // present lands next.
                for _ in 0..<3 {
                    guard let presentation else { return }
                    let overrides = presentation.sceneOverrides
                    let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                        .build(viewID: viewID, requestedSize: activeScene.canvasSize,
                               interactionState: state, dirtyNodeIDs: changed,
                               overrides: overrides)
                    let result = try await WMPRenderer(imageStore: store).render(
                        scene: scene, backingScale: self?.renderBackingScale(for: presentation) ?? 1,
                        clock: presentation.animationClock(for: scene.viewID),
                        slotClocks: Self.slotClocks(presentation, for: scene, store: store))
                    try Task.checkCancellation()
                    guard presentation.sceneOverrides == overrides else { continue }
                    presentation.activeScene = scene
                    self?.startAnimation(presentation, for: scene)
                    presentation.mainView?.present(result.image, overlay: result.overlayImage, silhouette: result.silhouetteMask,
                                                   scene: scene, dirtyBounds: scene.dirtyBounds,
                                                   traceSource: "interaction")
                    return
                }
            } catch is CancellationError {} catch { self?.lastLoadDiagnostic = error.localizedDescription }
        }
    }

    /// `targetStableID` is the node the input actually landed on. It is what scopes the dispatch,
    /// because an authored `id` is optional in a `.wmz` and `targetID == nil` means "every handler
    /// in the view" — correct for `load` or `timer`, catastrophic for a click. Corona leaves its
    /// compact-mode button unnamed, so clicking it ran all 16 of the view's `onClick` handlers at
    /// once: the file dialog, both drawers, and `ToggleSuperCompact()`, which switched the skin to
    /// a compact view that renders indistinguishably from the player and persisted it.
    private func dispatchScriptEvent(_ presentation: WMPViewPresentation, name: String,
                                     targetID: String?, targetStableID: Int? = nil,
                                     onlyWhenAuthored: Bool = false, keyCode: Int? = nil) {
        guard let skin = loadedSkin else { return }
        let handlers = Self.handlers(in: skin, event: name, targetID: targetID,
                                     targetStableID: targetStableID, viewID: presentation.viewID)
        #if DEBUG
        if ProcessInfo.processInfo.environment["WMP_CLICK_TRACE"] == "1", name != "timer" {
            NSLog("[wmp/dispatch] %@ targetID=%@ stable=%@ view=%@ handlers=%d %@",
                  name, targetID ?? "-", targetStableID.map(String.init) ?? "-",
                  presentation.viewID, handlers.count,
                  handlers.map { String($0.prefix(70)) }.joined(separator: " | "))
        }
        #endif
        // **A hover edge is only worth a transaction when the skin asked for one.** Every other
        // dispatch site here is a discrete act — a click, a keystroke, a view change — and runs the
        // transaction even with no authored handler, because the bindings have to settle. Hover is
        // not: the pointer crosses a whole row of buttons on the way to the one it wants, and a
        // transaction rebuilds and re-renders the entire scene (and cancels whatever click was
        // still in flight). So `onmouseover`/`onmouseout` dispatch only where the markup carries a
        // handler for them; the hover *artwork* never went through here and is unaffected.
        if onlyWhenAuthored, handlers.isEmpty { return }
        // **A `<RETURNBUTTON>` is WMP's route back to the library, and it carries no handler.**
        // The element *is* the command — 15 of the 19 in the corpus author no `onClick` at all —
        // so with the kind treated as an ordinary button the control was a hit target that did
        // nothing: `Compact`'s toggle, `corona`'s and `9SeriesDefault`'s two system-bar buttons,
        // `cerulean`, `claw`, `circle`, `polygon`, `aoe`, `bluegrid`, `Cubist`, `Optik`,
        // `digitaldj` and `Plus! Professional`. Reported as "the library button does not call the
        // library" (W191). **Only when the markup authored nothing**: `anemone` and `modernblue`
        // spell `onClick="view.returnToMediaCenter();"` on theirs, and posting the command here as
        // well would toggle the library open and shut again on one click.
        if name == "click", handlers.isEmpty, let targetStableID,
           presentation.activeScene?.hits.first(where: { $0.stableID == targetStableID })?
               .kind.caseInsensitiveCompare("returnButton") == .orderedSame {
            _ = applyHostCommands([WMPJScriptHostCommand(action: "toggleLibrary", value: nil)],
                                  from: presentation)
            return
        }
        dispatchScriptTransaction(presentation,
                                  WMPJScriptEvent(name: name, targetID: targetID,
                                                  targetStableID: targetStableID,
                                                  handlers: handlers,
                                                  modifiers: Self.currentEventModifiers(),
                                                  keyCode: keyCode,
                                                  button: Self.mouseButton(for: name),
                                                  pointer: Self.currentPointer(presentation)),
                                  stickyLatch: name == "click"
                                      ? Self.stickyLatch(presentation, targetStableID) : nil)
    }

    /// The latch a `sticky="true"` button was left in by the press that is now raising its
    /// `onClick`, or nil for every other control. **WMP flips it before the handler runs** and the
    /// corpus's drawer idiom reads it straight back, so the handler has to see the pointer's answer
    /// rather than the markup's — see `WMPScriptRuntime.setWidgetDown` (W206). The state is read
    /// from the presentation rather than passed down from the view because `WMPMainView.mouseUp`
    /// notifies the toggle before it raises the click.
    private static func stickyLatch(_ presentation: WMPViewPresentation,
                                    _ targetStableID: Int?) -> (stableID: Int, down: Bool)? {
        guard let targetStableID, let scene = presentation.activeScene else { return nil }
        let sticky = scene.hits.contains { hit in
            (hit.stableID == targetStableID && hit.sticky)
                || hit.mappingTargets.contains { $0.stableID == targetStableID && $0.sticky }
        }
        guard sticky else { return nil }
        return (targetStableID,
                presentation.interactionState.stickyDownNodes.contains(targetStableID))
    }

    private func dispatchHostEvents(_ presentation: WMPViewPresentation, _ names: [String]) {
        guard let skin = loadedSkin else { return }
        let snapshot = host.snapshot
        let handlers = names.flatMap { name in
            Self.handlers(in: skin, event: name, targetID: nil,
                          viewID: presentation.viewID).map {
                WMPJScriptEvent.Handler(source: $0, arguments: Self.arguments(for: name, snapshot))
            }
        }
        dispatchScriptTransaction(presentation,
                                  WMPJScriptEvent(name: names.joined(separator: ","),
                                                  targetID: nil, handlers: handlers))
    }

    /// The implicit arguments WMP raises a host event with, per event rather than per transaction.
    ///
    /// `NewState` is the whole of the measured demand — 6 of the 180 installed archives name it in
    /// a handler attribute and 5 name `status` — and it is a *different* enumeration in the two
    /// events that carry it: an open state (`os*`) in `openstatechange` and a play state (`ps*`) in
    /// `playstatechange`. Both are answered from the same members `player.openState` and
    /// `player.playState` answer, so the argument and the property can never disagree. `status` is
    /// `player.status` and rides `WMPHostSnapshot.statusText` for exactly that reason — an
    /// argument that disagreed with the property the same handler can read is worse than none.
    static func arguments(for event: String,
                          _ snapshot: WMPHostSnapshot) -> [String: WMPJSONValue] {
        switch event {
        case "openstatechange":
            return ["NewState": .number(Double(WMPScriptConstants.openState(for: snapshot)))]
        case "playstatechange":
            return ["NewState": .number(Double(WMPScriptConstants.playState(for: snapshot.state)))]
        case "status_onchange":
            return ["status": .string(snapshot.statusText)]
        // **An ambient handler reads the attribute that changed by its own name** — the SDK's
        // per-handler argument, and the whole of what these two handlers are made of: 68 of the
        // corpus's 77 `currentEffectType_onchange` uses are
        // `mediacenter.effectType=currentEffectType`, which without this binding is a
        // `ReferenceError` on the first statement and a handler that dies silently (W129).
        //
        // `currentMedia` and `currentPlaylist` are deliberately **not** bound: WMP's are objects,
        // this engine has no JS object to stand for either, and every one of their 77 corpus
        // sources calls a skin function (`updateAlbumArt()`, `getVisMeta()`,
        // `updateMetadata('playlist')`) rather than reading the bare name. Binding a scalar in
        // their place would answer a question the skin never asked, wrongly.
        case "currenteffecttype_onchange":
            return ["currentEffectType": .string(snapshot.effects.type)]
        case "currentposition_onchange":
            return ["currentPosition": .number(snapshot.currentTime)]
        case "currentpreset_onchange":
            return ["currentPreset": .number(Double(snapshot.effects.preset))]
        default:
            return [:]
        }
    }

    /// True while the pointer is holding a slider. The host's position write-backs are suppressed
    /// for the duration, so the value the user is setting cannot be overwritten underneath them.
    private var sliderCaptureActive = false

    /// Set by `applyHostCommands` when a script transaction issued `seekSeconds`, read by the
    /// slider release path so a skin that commits its own seek is not seeked twice (W156).
    private var scriptDidCommitSeek = false

    /// **The release that ends a skin's own resize drag (W225).** `view.size(corner)` blocks in
    /// WMP, so the statements after it are the skin putting its layout back — `Compact` unpins both
    /// drawers from the edges it had them ride — and they belong to the mouse-up, not to the press.
    /// Runs against the size the window finished at, which is the canvas those writes measure from.
    func resumeAfterScriptResize(_ presentation: WMPViewPresentation) {
        wmpResizeTrace("resumeAfterScriptResize \(presentation.viewID) "
            + "scene=\(presentation.activeScene?.canvasSize.width ?? -1)"
            + "x\(presentation.activeScene?.canvasSize.height ?? -1)")
        dispatchScriptTransaction(presentation, nil, resumingWindowResize: true)
    }

    private func dispatchScriptTransaction(_ presentation: WMPViewPresentation,
                                           _ event: WMPJScriptEvent?,
                                           stickyLatch: (stableID: Int, down: Bool)? = nil,
                                           resumingWindowResize: Bool = false) {
        guard let skin = loadedSkin, let store = imageStore,
              let activeScene = presentation.activeScene, let scriptRuntime else { return }
        let viewID = presentation.viewID
        // A binding-only transaction is still required when no authored handler exists.
        presentation.scriptTask?.cancel()
        presentation.scriptTask = Task { [weak self, weak presentation] in
            guard let self, let presentation else { return }
            // Before the handlers, in the same task, so the two cannot be reordered: the latch is
            // an input to the click it belongs to, not a consequence of it (W206).
            if let stickyLatch {
                await scriptRuntime.setWidgetDown(stableID: stickyLatch.stableID,
                                                  down: stickyLatch.down, viewID: viewID)
            }
            let resumed = resumingWindowResize
                ? await scriptRuntime.resumeAfterWindowResize(skin: skin, viewID: viewID,
                    size: activeScene.canvasSize, snapshot: host.snapshot,
                    geometry: activeScene.scriptGeometry)
                : nil
            // A resume with nothing held is every grip in the corpus whose handler is the call and
            // nothing else; there is no transaction to run for it.
            if resumingWindowResize, resumed == nil { return }
            let output: WMPScriptOutput
            if let resumed {
                output = resumed
            } else {
                output = await scriptRuntime.transact(skin: skin, viewID: viewID,
                    size: activeScene.canvasSize, snapshot: host.snapshot, event: event,
                    geometry: activeScene.scriptGeometry, animatesTweens: true)
            }
            // **A host command is the script's output, not the drawing's, so it is applied the
            // moment the transaction returns — before the scene is built rather than after it is
            // presented.**
            //
            // Everything below this line can be superseded: the scene build and the render are the
            // slow half of a transaction, and a view timer that fires during them cancels this
            // task. That is correct for the *drawing* — a newer transaction is already building a
            // newer scene — and it silently discarded the commands with it.
            //
            // `Alienware Invader` is the case. Its 568-frame intro ends on the heaviest tick in the
            // skin: `toggleShutter()` swaps `mainBack` to `main_back.png`, turns `mainBackGroup1`
            // on, and posts `view.timerInterval = 0` to stop its own animation. Building that frame
            // decodes the whole player's artwork and takes longer than the 50 ms period, so the
            // next tick cancelled it after `render` and before `guard !Task.isCancelled`. The
            // reveal was never presented and the `0` was never applied — and the timer that should
            // have stopped kept firing with the skin's own `introStatus` now true, so the next tick
            // took the *other* branch of `toggleShutter()` and closed the shutter it had just
            // opened, 82 frames down to the closed state. Reported as "it opens and then closes".
            //
            // A command that switches this window's view owns everything after it, exactly as on
            // initial load, so this transaction's scene is abandoned rather than drawn over the new
            // view's.
            // **A command this transaction posted changes what its own bindings resolve to, and
            // nothing else was going to notice.** `refreshHostState` diffs the snapshot and raises
            // the settle, so taking the reading either side of the commands is all this needs. It
            // runs at scope exit, so the scene this transaction is already building is the one
            // presented.
            //
            // **Only a transaction that posted a command takes the reading at all (W157).**
            // `host.snapshot` is computed live off the engine and carries `currentTime`
            // (`WMPAudioEngineHost.snapshot`), so with a track playing the two readings differ by
            // however long the transaction took — the diff was non-empty on *every* pass, whether
            // or not a command had been applied. `refreshHostState` then raised
            // `currentposition_onchange`, which dispatched another transaction, whose own `defer`
            // raised another: a self-feeding loop that ran as fast as the pipeline could rebuild
            // and re-render the whole view. Measured live on `NVIDIA` in a release build with one
            // local MP3 playing: `refreshHostState` called **39.9x/s from here against 9.9x/s from
            // the real 10 Hz clock tick**, and every one of those transactions posted **zero**
            // commands — roughly three quarters of all repaint work in the engine was this loop
            // chasing its own tail. A pass with no commands cannot have moved the host, so there is
            // nothing for it to notice; the clock tick that genuinely moved is already delivered by
            // `updateTime`.
            let hostStateBeforeCommands = output.hostCommands.isEmpty ? nil : host.snapshot
            defer {
                if let hostStateBeforeCommands, host.snapshot != hostStateBeforeCommands {
                    refreshHostState()
                }
            }
            let switchedView = applyHostCommands(output.hostCommands, from: presentation)
            // **The window is resized with the picture that fits it, not ahead of it.** The size
            // is recorded here — `rebuildSize` below needs it to build the scene the skin asked
            // for — but the frame itself is set in the same main-actor turn as `present`, further
            // down. Setting it here instead resized the window around the *old* image, which
            // AppKit then stretched to fill until the new one arrived a frame or two later:
            // `Compact`'s player visibly ballooned to 601 wide and snapped back to 422 every time
            // a drawer opened. Reported as "a big UI flash when the drawer opens" (W190).
            let assignedWindowSize = switchedView ? nil : output.viewSize
            if let assignedWindowSize { presentation.scriptViewSize = assignedWindowSize }
            if !switchedView {
                applyTimerDelta(presentation, registered: output.timerRequests,
                                cleared: output.clearedTimerTokens)
                // **Before the early return below, not after it.** A transaction that only started
                // a tween has moved nothing *yet* — the endpoint is held back, so its overrides
                // equal the presented scene's and W158 correctly declines to redraw. The motion
                // still has to begin (W194).
                startTweenLoop(presentation, hasActiveTweens: output.hasActiveTweens)
            }
            recordScriptDiagnostics(output.diagnostics)
            // **The latch is the artwork's as well as the script's, and it is written from both
            // ends (W206).** A sticky button drawn `down` by `WMPInteractionState` stays down until
            // the pointer presses it again, so a handler that clears it by name — `anemone`'s
            // `setVisibility('closePlaylist')`, raised by the × *inside* the tray, writes
            // `plb.down=false` — left the player's own button lit over a closed drawer, and the
            // next press on it toggled the stale latch to *false* and closed the drawer again
            // rather than opening it. Only a control the markup made sticky: a `down` written to
            // an ordinary button is state the skin keeps for itself.
            if let view = presentation.mainView {
                var latches: [Int: Bool] = [:]
                for (address, value) in output.overrides.properties
                where address.property.caseInsensitiveCompare("down") == .orderedSame {
                    guard Self.stickyLatch(presentation, address.stableID) != nil else { continue }
                    latches[address.stableID] = value.truth
                }
                if !latches.isEmpty {
                    presentation.interactionState = view.applyScriptedStickyLatches(latches)
                }
            }
            // **A `<LISTBOX>` selection the script wrote is not part of the scene, so it is not
            // dropped with it (W300).** A selection is reported only by the transaction that wrote
            // it, and `playSelPlaylist()`'s `plListBox1.selectedItem = 0` is written beside the
            // `play()` whose host refresh starts the next transaction — which cancels this one
            // before the guard below, every time. The played row stayed highlighted.
            if !switchedView, !output.widgetState.listSelections.isEmpty {
                presentation.mainView?.updateListSelections(output.widgetState.listSelections)
            }
            guard !switchedView, !Task.isCancelled else { return }
            // **A transaction whose script moved nothing has nothing to draw (W158).**
            //
            // `transact` returns the view's *cumulative* committed overrides, not a delta, so an
            // output equal to the ones the presented scene was built from is a statement that every
            // geometry value, every property and every `wmpprop:` binding resolved exactly as it
            // already had — including the readouts, because a clock that advanced moves
            // `currentPositionString` and a bound slider's `value` through the same registry. There
            // is no third source: `WMPSceneBuilder.build` takes no host snapshot, only these.
            //
            // Without this, a skin's own `onTimer` cost a full scene rebuild and a full-window
            // re-render per tick no matter what its handler did. `NVIDIA` authors
            // `timerInterval="100"` and its handler only pokes `btnEq.down`, so its playlist mode
            // burned 17 ms of build-and-render ten times a second — measured in release — to
            // redraw an identical picture; **442 `timerInterval`/`onTimer` uses across 91 archives**
            // are in the same position. Hover and press artwork are not affected: those never come
            // through here, they come through `renderInteraction`, which presents on its own task.
            // Animation is likewise untouched — `startAnimation` runs its own loop and a *skipped*
            // rebuild is one fewer epoch rewind (W85), not a frozen GIF.
            // **The size to rebuild at is the window's, not the last scene's.** `activeScene` is
            // only a proxy for the window and it goes stale exactly when the window moved without
            // a script transaction — a user resize. A transaction already in flight across that
            // resize (or the view's own 4 s timer afterwards) then re-presented the pre-resize
            // canvas *and* stored it as `activeScene`, so every later transaction read the stale
            // size back and the window never recovered: `Compact` drawn 750 wide inside a 601
            // window, its player body stretched over the drawer it had just opened (W187).
            let windowSize = WMPSize(
                width: presentation.window.contentLayoutRect.width / uiScale,
                height: presentation.window.contentLayoutRect.height / uiScale)
            let rebuildSize = presentation.scriptViewSize ?? windowSize
            if output.viewSize == nil,
               output.overrides == presentation.sceneOverrides,
               output.listItems == presentation.presentedListItems,
               output.widgetState == presentation.presentedWidgetState,
               let presented = presentation.activeScene,
               presented.canvasSize == rebuildSize,
               // …and the window is already wearing that canvas. Skipping the rebuild is only safe
               // while the picture on screen is the right size for the frame it is in; a frame that
               // never caught up with a cancelled assignment (W197) must not be left there by a
               // transaction that had nothing else to say.
               presented.canvasSize == windowSize {
                return
            }
            do {
                // No `dirtyNodeIDs`: a script transaction repaints in full.
                //
                // The dirty region a script produces cannot be derived from what it *wrote*. A
                // handler writes `svEqualizer.top` and the whole pane and every control inside it
                // moves, none of which the script mentioned — and a subview carries no hit metadata,
                // so the narrowed bounds came out as the one button that was clicked. Partial
                // repaints belong to hover and slider drags, where only artwork state changes.
                // **A `.wmz` compact mode is a script resizing its own window.** Every other
                // transaction rebuilds at the size the window already has, because that size is the
                // user's; a transaction that *assigned* `view.width`/`view.height` is the one case
                // where the skin is asking for a different one, and pinning `requestedSize` to the
                // old canvas made `SwitchSmall()` draw a 475x373 player inside a 593x600 window
                // with two hundred empty pixels around it.
                var scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: viewID,
                           requestedSize: rebuildSize,
                           interactionState: presentation.interactionState,
                           overrides: output.overrides)
                // **A skin that resizes its own view is resized, and its `onResize` runs on the
                // way (W274).** The drag path and the open path (W211) raise it; this one did not,
                // so a handler reading a stretched pane in the transaction that grew the window
                // kept the stale size for good. `NVIDIA`'s `plModeToggle()` takes the window from
                // 285x301 to 700x480 and then sizes its playlist chooser off `plListBoxSub.height`
                // — still the audio mode's −95 inside that click — so the list got a negative
                // height, was never hosted, and the Media Library panel stayed empty.
                // `onPlayerResize()` → `resizeListBox()` is the skin's own correction, reading the
                // laid-out 84.
                //
                // **Keyed on the canvas changing, not on this transaction's assignment.** The view
                // timer cancels the click's task mid-build often enough (W197); the size survives
                // on `scriptViewSize`, and the transaction that finally presents it is the timer's,
                // which assigned nothing — so tying the raise to `output.viewSize` lost it about
                // half the time.
                var presented = output
                if let before = presentation.activeScene, before.canvasSize != scene.canvasSize,
                   let event = Self.resizeEvent(in: skin, viewID: viewID,
                                                before: presentation.activeScene, after: scene) {
                    presented = await scriptRuntime.transact(skin: skin, viewID: viewID,
                        size: scene.canvasSize, snapshot: host.snapshot, event: event,
                        geometry: scene.scriptGeometry)
                    recordScriptDiagnostics(presented.diagnostics)
                    scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                        .build(viewID: viewID,
                               requestedSize: rebuildSize,
                               interactionState: presentation.interactionState,
                               overrides: presented.overrides)
                }
                let result = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: renderBackingScale(for: presentation),
                    clock: presentation.animationClock(for: scene.viewID),
                    slotClocks: Self.slotClocks(presentation, for: scene, store: store))
                guard !Task.isCancelled else { return }
                // Frame and picture together: see `assignedWindowSize` above. **The test is the
                // canvas against the window, not the assignment against nil (W197).** A script's
                // size assignment is recorded on `scriptViewSize` before the build and the frame is
                // set after the render, and between those two points the task can be cancelled by
                // the next transaction — which for `NVIDIA` is certain rather than unlucky: the skin
                // holds `timerInterval="100"`, its playlist switch takes ~45 ms to build and render,
                // and the tick that lands inside that window cancels it. The assignment survived on
                // `scriptViewSize`, so every later transaction rebuilt a 730x574 picture and
                // presented it into the 285x301 window it was still in, where AppKit stretched it —
                // the reported "opening very small size now and possibly distorting the aspect
                // ratio", and the exact shape of it. Asking whether the window matches the picture
                // is a question any transaction can answer, so the *next* one recovers the frame
                // instead of the assignment being lost with the task that carried it.
                //
                // `canvasSize` and not `assignedWindowSize` because `WMPSceneBuilder` clamps what it
                // was handed against the view's resize limits, and since W196 those are the limits
                // the script is holding right now rather than the ones the markup opened with.
                // `windowSize` is read before the build, so a user resize that landed since is
                // reconciled by that resize's own `renderCurrentSize` (W187) rather than fought
                // over here — both paths agree that the window's size is the user's.
                if scene.canvasSize != windowSize {
                    setWindowSize(presentation, NSSize(width: scene.canvasSize.width,
                                                       height: scene.canvasSize.height))
                }
                presentation.sceneOverrides = presented.overrides
                presentation.activeScene = scene
                self.startAnimation(presentation, for: scene)
                presentation.presentedListItems = presented.listItems
                presentation.presentedWidgetState = presented.widgetState
                presentation.mainView?.updateListItems(presented.listItems)
                presentation.mainView?.updateWidgetState(presented.widgetState)
                presentation.mainView?.present(result.image, overlay: result.overlayImage, silhouette: result.silhouetteMask, scene: scene, traceSource: "transaction")
                self.arbitrateVideoSurface()
            } catch { recordScriptDiagnostics([.init(code: "scene-transaction", message: error.localizedDescription)]) }
        }
    }

    /// The `timerInterval` the view declares in markup, which starts the view timer before any
    /// script has had a chance to change it.
    ///
    /// **An `onTimer` with no `timerInterval` beside it ticks at WMP's default second, not never.**
    /// The SDK's default for the attribute is 1000 ms, and a view that asks for the event and
    /// leaves the period unstated is asking for that — which is exactly the period a clock wants.
    /// Answering 0 there read as "this view has no timer" at every caller, so the handler was
    /// registered and never once raised: `Stealth`'s `OnTimerTick()` is the only thing that writes
    /// its elapsed readout, so the skin sat at the authored `00:00` through a whole track while the
    /// visualizer ran beside it — reported as the skin not playing at all. **7 views in 7 archives**
    /// author the shape (`Stealth`, `digitaldj`, `Revert`/`Revert (1)`, `Grinch`, `Erektorset`,
    /// `Josie_and_the_Pussycats`), measured over 184.
    ///
    /// **An authored `0` still means off**, and stays off: that is WMP's meaning for it and the
    /// corpus writes it deliberately — `corona`'s `viewTiny` opens stopped and starts its own clock
    /// from a script. Only an *absent* attribute takes the default, and only where the view
    /// authors the handler, so a view with no `onTimer` keeps costing nothing.
    static func authoredTimerInterval(in skin: WMPLoadedSkin, viewID: String) -> Int {
        guard let view = skin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        })?.node else { return 0 }
        guard let attribute = view.attributes.first(where: {
            $0.name.caseInsensitiveCompare("timerInterval") == .orderedSame
        }) else {
            return view.attributes.contains {
                $0.name.caseInsensitiveCompare("onTimer") == .orderedSame
            } ? Self.defaultTimerIntervalMilliseconds : 0
        }
        guard case let .literal(raw) = attribute.value,
              let milliseconds = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return 0 }
        return max(0, milliseconds)
    }

    /// WMP's own default for `VIEW.timerInterval`.
    static let defaultTimerIntervalMilliseconds = 1_000

    /// **The view's authored canvas, before its own floor is applied to it.**
    ///
    /// `minWidth`/`minHeight` are a floor on the *window*, and a skin routinely declares one well
    /// above the size it authored the view at — `Alienware Invader`'s `plView` is written 331x277
    /// with `minWidth="531" minHeight="291"`, `Back to the Future Trilogy`'s the same shape. The
    /// builder clamps, correctly, so this is the only place the authored pair is still readable.
    static func authoredCanvas(in skin: WMPLoadedSkin, viewID: String) -> WMPSize? {
        guard let view = skin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        })?.node else { return nil }
        func literal(_ name: String) -> CGFloat? {
            guard let attribute = view.attributes.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }), case let .literal(raw) = attribute.value,
                  let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
                  value.isFinite, value > 0 else { return nil }
            return CGFloat(value)
        }
        guard let width = literal("width"), let height = literal("height") else { return nil }
        return WMPSize(width: width, height: height)
    }

    /// Whether the view lets the user size its window at all — `WMPScene.isResizable`, read from
    /// the markup before a scene exists, which is what deciding whether to *request* a size needs.
    /// `resizAble` is the corpus's dominant spelling and `resizable` the other; both appear in the
    /// same archive, and absent is false.
    static func authoredResizable(in skin: WMPLoadedSkin, viewID: String) -> Bool {
        guard let view = skin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        })?.node else { return false }
        for name in ["resizAble", "resizable"] {
            guard let attribute = view.attributes.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }), case let .literal(raw) = attribute.value else { continue }
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("true") == .orderedSame
        }
        return false
    }

    /// Overrides that lift a view's own declared floor for one build, so the **authored** layout
    /// can be resolved next to the one the window opened at.
    static func unclampedOverrides(_ base: WMPSceneOverrides, in skin: WMPLoadedSkin,
                                   viewID: String) -> WMPSceneOverrides {
        guard let node = skin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        })?.node else { return base }
        var overrides = base
        for name in ["minwidth", "minheight"] {
            overrides.properties[WMPScenePropertyAddress(stableID: node.stableID,
                                                         property: name)] = .number(1)
        }
        return overrides
    }

    /// **The canvas a view's first scene is built at: the size its own `onLoad` asked for, or
    /// failing that the one it opened with (W244).**
    ///
    /// `WMPSceneBuilder` resolves its canvas as `resizeLimits.clamp(requestedSize ?? defaultSize)`,
    /// and a script's `view.width`/`view.height` assignment lives in `defaultSize` — so handing the
    /// builder the *pre*-`onLoad` canvas silently discarded the assignment, and the scene, the
    /// window and `activeScene` were all built at the authored size. `Xbox Live Skin`'s `eqView` is
    /// `width="423" height="343" minWidth="429" minHeight="197"` and its `loadEQPrefs()` is three
    /// lines — `view.width = view.minWidth; view.height = view.minHeight` — the compact equaliser
    /// its artwork is drawn for. Measured live: the window stayed **429x343** while the scene the
    /// harness dumps is 429x197, so the frame pieces pinned `top="jscript:view.height-181"`
    /// travelled to a bottom that was not there and left a black band with two white seams where
    /// the rails and corners no longer meet.
    ///
    /// **The handler path has honoured this since W113/W190** (`assignedWindowSize`); the two load
    /// paths never did, which is the whole of the defect. `viewSize` is nil unless *this*
    /// transaction assigned the root's own width or height, and the runtime has already clamped it
    /// to the view's limits and refused it outright for a decoder-driven size (W99) — so a view
    /// whose `onLoad` sizes nothing is built exactly as before.
    nonisolated static func loadedCanvas(assigned: WMPSize?, opened: WMPSize) -> WMPSize {
        assigned ?? opened
    }

    /// **A view that opens at a size it was never authored at has already been resized, and its
    /// `onResize` has to run before anyone sees it (W211).**
    ///
    /// `Alienware Invader` authors `plView` at 331x277 and floors it at 531x291, and states its two
    /// side rails in three pieces each: a top, a centred piece, and a tile whose height only
    /// `onPlResize()` ever sets — `plLeftStretch.height = view.height / 2`. The window opens at the
    /// floor, no resize is raised there, so that tile keeps its bitmap's own 51pt and both rails
    /// have a 58pt band of bare window punched through them. Reported 2026-09-17 on the playlist,
    /// and visible on every skin of this shape: the load pass alone is not the layout WMP shows,
    /// because WMP reaches the floor *by resizing* and the skin's handler runs on the way.
    ///
    /// The before-layout is the authored one with the floor lifted, so the changed set is measured
    /// rather than assumed and `resizeEvent`'s rule — a handler goes to the object whose own box
    /// moved — decides the dispatch exactly as it does on a user drag.
    ///
    /// Gated on the view declaring an `onResize` at all: 161 of 180 archives do not, and they must
    /// not pay a second scene build to open a window.
    static func opensResized(in skin: WMPLoadedSkin, viewID: String, opened: WMPScene) -> Bool {
        guard !handlers(in: skin, event: "onResize", targetID: nil, viewID: viewID).isEmpty,
              let authored = authoredCanvas(in: skin, viewID: viewID) else { return false }
        return authored != opened.canvasSize
    }

    /// The `onResize` dispatch for one completed relayout, or `nil` when there is nothing to say.
    ///
    /// WMP hands `onResize` to an object whose *own* box changed, not to every object in the view:
    /// 19 corpus skins author 49 of these, and Corona alone authors one on the view (its transport
    /// readout) and one on the equaliser subview (`EqResize`, which re-spaces the ten sliders from
    /// `svEqualizerTopMiddle.width`). Firing both on every window resize would run the equaliser's
    /// layout pass while the drawer is shut; firing neither leaves the sliders where the window
    /// opened. So the changed set is read off the two scenes — the frames the builder actually
    /// resolved — rather than inferred from which attributes carry an expression.
    ///
    /// Handlers are collected in document order, and the whole thing is skipped when the view
    /// declares no `onResize` at all, which is 161 of the 180 archives: a resize then costs one
    /// scene build exactly as it did before.
    nonisolated static func resizeEvent(in skin: WMPLoadedSkin, viewID: String,
                            before: WMPScene?, after: WMPScene) -> WMPJScriptEvent? {
        guard !handlers(in: skin, event: "onResize", targetID: nil, viewID: viewID).isEmpty,
              let before, before.viewID.caseInsensitiveCompare(after.viewID) == .orderedSame
        else { return nil }
        var changed = Set<Int>()
        if before.canvasSize != after.canvasSize, let view = skin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        })?.node {
            changed.insert(view.stableID)
        }
        for (stableID, geometry) in after.geometries
        where before.geometries[stableID]?.localFrame != geometry.localFrame {
            changed.insert(stableID)
        }
        guard !changed.isEmpty else { return nil }
        let sources = skin.graph.allNodes.filter { changed.contains($0.stableID) }.flatMap {
            handlers(in: skin, event: "onResize", targetID: nil,
                     targetStableID: $0.stableID, viewID: viewID)
        }
        guard !sources.isEmpty else { return nil }
        return WMPJScriptEvent(name: "resize", targetID: nil, handlers: sources)
    }

    /// Authored handlers for one event, **inside one view**.
    ///
    /// The view scope is not tidiness. A `.wmz` declares every view in one file, so an unscoped
    /// scan ran the *other* view's `onLoad` as well: Corona's tiny view then executed the player
    /// view's setup against elements that do not exist there, and the census read the resulting
    /// `ReferenceError` as a defect in the runtime rather than in the caller.
    static func handlers(in skin: WMPLoadedSkin, event: String, targetID: String?,
                         targetStableID: Int? = nil, viewID: String? = nil) -> [String] {
        let wanted = event.lowercased().replacingOccurrences(of: "_", with: "")
        // **The corpus authors these events under WMP's other spelling, by an order of magnitude.**
        // The engine dispatches `openstatechange` and `playstatechange`, which 7 and 11 archives
        // write; 144 and 139 write `OpenState_onchange` and `PlayState_onchange`, on the same
        // `<PLAYER>` element, calling the same handler — `<player PlayState_onchange="…"
        // OpenState_onchange="…" status_onChange="…">` is the standard template, and `status_onchange`
        // was already carried in the `_onchange` spelling. `value_onchange` is the same shape at
        // 175 of 179 archives, raised where `change` already is: the user moved the control.
        //
        // Aliasing here rather than at the dispatch sites keeps one rule for both spellings, so a
        // site cannot raise one name and miss the other.
        let accepted: Set<String>
        switch wanted {
        // `positionchange` rides `change` because it is the same edge: WMP raises a
        // `CUSTOMSLIDER`'s `onPositionChange` when the user moves it, which is exactly where
        // `value_onchange` is raised, and the corpus's `eq.truBassLevel`/`eq.wowLevel` writes are
        // authored in that spelling rather than the other. The event carries the element, so the
        // bare `value` those handlers read is bound.
        case "change", "onchange": accepted = ["change", "valueonchange", "positionchange"]
        case "openstatechange": accepted = ["openstatechange", "openstateonchange"]
        case "playstatechange": accepted = ["playstatechange", "playstateonchange"]
        default: accepted = []
        }
        var scope: Set<Int>?
        if let viewID, let view = skin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        })?.node {
            var included = Set<Int>()
            func include(_ node: WMPNode) { included.insert(node.stableID); node.children.forEach(include) }
            include(view)
            scope = included
        }
        return skin.graph.allNodes.filter { node in
            scope?.contains(node.stableID) != false
        }.filter { node in
            // An exact node beats an authored id: the id may be absent, and absent must mean
            // "this one node", never "all of them".
            if let targetStableID { return node.stableID == targetStableID }
            return targetID == nil
                || node.xmlID?.caseInsensitiveCompare(targetID ?? "") == .orderedSame
                || (targetID == "view" && node.kind == .view)
        }.flatMap { node in
            node.attributes.compactMap { attribute -> String? in
                guard case let .handler(authored, source) = attribute.value else { return nil }
                let normalized = authored.lowercased().replacingOccurrences(of: "_", with: "")
                let stripped = normalized.hasPrefix("on") ? String(normalized.dropFirst(2)) : normalized
                let wantedStripped = wanted.hasPrefix("on") ? String(wanted.dropFirst(2)) : wanted
                if accepted.contains(normalized) || accepted.contains(stripped) { return source }
                return stripped == wantedStripped ? source : nil
            }
        }
    }

    /// Apply one transaction's host commands. Transport, EQ, effect, video and file-dialog commands
    /// are the session's; the six window commands belong to `presentation`, the window whose script
    /// posted them.
    ///
    /// The return value means "this window's view was replaced", which is what abandons the scene
    /// the caller was about to draw. **`openView` deliberately returns false**: opening a panel no
    /// longer abandons the opener's scene, because the opener is still on screen.
    @discardableResult
    private func applyHostCommands(_ commands: [WMPJScriptHostCommand],
                                   from presentation: WMPViewPresentation) -> Bool {
        var switchedView = false
        for command in commands.prefix(WMPJScriptProtocol.maximumHostCommands) {
            let number = command.value?.number
            switch command.action {
            case "play": host.perform(.play, value: nil)
            case "pause": host.perform(.pause, value: nil)
            case "stop": host.perform(.stop, value: nil)
            case "previous": host.perform(.previous, value: nil)
            case "next": host.perform(.next, value: nil)
            case "scanForward": host.perform(.beginScan(.forward), value: nil)
            case "scanReverse": host.perform(.beginScan(.reverse), value: nil)
            case "seekSeconds":
                // Read by the slider release path, which commits its own seek only where the skin's
                // handlers did not (W156).
                scriptDidCommitSeek = true
                let duration = max(host.snapshot.duration, 0.001)
                #if DEBUG
                wmpSeekTrace("hostCommand seekSeconds=\(number ?? -1) duration=\(duration)")
                #endif
                host.perform(.seek, value: .number(max(0, min(1, (number ?? 0) / duration))))
            case "volumePercent": host.perform(.volume, value: .number(max(0, min(1, (number ?? 0) / 100))))
            case "balancePercent": host.perform(.balance, value: .number(max(-1, min(1, (number ?? 0) / 100))))
            case "setMute": if (command.value?.number ?? 0) != (host.snapshot.muted ? 1 : 0) { host.perform(.toggleMute, value: nil) }
            case "setShuffle": if (command.value?.number ?? 0) != (host.snapshot.shuffle ? 1 : 0) { host.perform(.toggleShuffle, value: nil) }
            case "setRepeat": if (command.value?.number ?? 0) != (host.snapshot.repeatMode ? 1 : 0) { host.perform(.toggleRepeat, value: nil) }
            case "setWOWEnabled": host.perform(.setWOWEnabled, value: command.value.map { .number($0.number ?? 0) })
            case "setTruBassLevel": host.perform(.setTruBassLevel, value: command.value.map { .number($0.number ?? 0) })
            case "setSpeakerSize": host.perform(.setSpeakerSize, value: command.value.map { .number($0.number ?? 0) })
            case "setWOWLevel": host.perform(.setWOWLevel, value: command.value.map { .number($0.number ?? 0) })
            case "setCrossFade": host.perform(.setCrossFade, value: command.value.map { .number($0.number ?? 0) })
            case "setCrossFadeWindow": host.perform(.setCrossFadeWindow, value: command.value.map { .number($0.number ?? 0) })
            case "setNormalization": host.perform(.setNormalization, value: command.value.map { .number($0.number ?? 0) })
            case "setEQEnabled": host.perform(.setEQEnabled, value: command.value.map { .number($0.number ?? 0) })
            case let action where action.hasPrefix("setEQBand:"):
                if let index = Int(action.dropFirst("setEQBand:".count)) {
                    host.perform(.setEQBand(index), value: command.value.map { .number($0.number ?? 0) })
                }
            case "setEffectType": host.perform(.setEffectType(command.value?.string ?? ""), value: nil)
            case "setVideoFullScreen":
                guard let video = WMPAudioEngineHost.localVideoController, video.hasVideoOutput else { break }
                let requested = command.value?.truth == true
                let current = video.window?.styleMask.contains(.fullScreen) == true
                if requested && !current && !video.isVideoFullScreenTransition {
                    video.enterFullScreenReclaimingOutput()
                    videoSurface.detach(reveal: true)
                } else if !requested && current {
                    video.window?.toggleFullScreen(nil)
                }
            case "setEffectPreset": host.perform(.setEffectPreset(Int(number ?? 0)), value: nil)
            case "stepEffect":
                host.perform((number ?? 1) < 0 ? .previousEffect : .nextEffect, value: nil)
            case "stepEffectPreset": host.perform(.nextEffectPreset, value: nil)
            case "setViewTimerInterval": setViewTimer(presentation, milliseconds: Int(number ?? 0))
            case "openFileDialog": presentOpenMediaPanel()
            case "closeView":
                // **By name, or the window the handler is running in.** `theme.closeView('plView')`
                // names a window; `view.close()` posts this with no value and means its own. 84 of
                // the 180 archives call the named form and every one of them has been aborting the
                // handler that does it — `Halo 2`'s `checkRemoteViewStatus()` dies on
                // `theme.closeView('vidRemoteView')` and never reaches the statements after it.
                if let id = command.value?.string {
                    if let target = materializer.presentation(for: id) { closeViewWindow(target) }
                } else {
                    closeViewWindow(presentation)
                    switchedView = true
                }
            case "minimizeWindow": presentation.window.miniaturize(nil)
            // **The skin's own resize grip (W193).** A `.wmz` window is borderless and the macOS
            // frame the user would otherwise drag is not the resize the skin authored, so the
            // press that called `view.size(corner)` is handed straight to the same edge drag the
            // window band runs — clamped by the view's `minWidth`/`maxWidth`, relaid out by
            // `windowDidResize` like any other.
            case "sizeWindow":
                // **And the rest of the handler waits for the drag (W225).** A grip that did not
                // start one — the button is already up, or the view is not resizable — has no
                // release coming, so the held tail is run at once rather than stranding the skin
                // with its drawers still pinned.
                if presentation.mainView?.beginScriptResize(corner: command.value?.string ?? "")
                    != true {
                    resumeAfterScriptResize(presentation)
                }
            // `view.returnToMediaCenter()` toggles the library beside the active skin — **except on
            // a notice view, where the same call is spelled on a close box.** Reported as "the X to
            // close the 'latest version' window opens the media library rather than close".
            //
            // W100 measured the call where it lives and its answer stands: 204 uses across 169
            // archives, almost all on the skin's own player view, where "return to full mode" means
            // the shell the library stands in for. **What decides this is the artwork, not the
            // window's role** — the tooltip says "Return To Full Mode" on every one of the 204, so
            // it cannot. The five `upgradeView`/`versionView` buttons are `f_close_no.png` /
            // `wmp_close_no.png`, an X in the panel's top-right corner; the seven `videoView` ones
            // are `v_full_no.png`, `fullmode_no.gif` and mapped colours, a genuine full-mode
            // control that still means the library. A rule of "not the player" would have caught
            // both and broken the second seven, which is why this names the view instead.
            case "toggleLibrary":
                if WMPDeclaredHostState.isHostOpenedNotice(viewID: presentation.viewID) {
                    closeViewWindow(presentation)
                } else {
                    WindowManager.shared.togglePlexBrowser()
                }
            // `player.currentPlaylist = <a library playlist>` (W136): catalog indices, resolved
            // against the locations the catalog was built with.
            case "loadLibraryTracks":
                playLibraryTracks((command.value?.string ?? "").split(separator: ",")
                    .compactMap { Int($0) }, from: 0)
            case let action where action.hasPrefix("playPlaylistItem:"):
                if let index = Int(action.dropFirst("playPlaylistItem:".count)) {
                    host.perform(.playPlaylistItem(index), value: nil)
                }
            case "openView":
                if let id = command.value?.string {
                    openView(id, from: presentation, offset: nil)
                }
            case let action where action.hasPrefix("openViewRelative:"):
                // `openViewRelative:<dx>,<dy>` — the offset rides the action, the way
                // `setEQBand:<n>` does, because a host command carries exactly one value and the
                // view id is it.
                let parts = action.dropFirst("openViewRelative:".count).split(separator: ",")
                if let id = command.value?.string, parts.count == 2,
                   let dx = Double(parts[0]), let dy = Double(parts[1]) {
                    openView(id, from: presentation, offset: CGPoint(x: dx, y: dy))
                }
            case "setCurrentView":
                if let id = command.value?.string,
                   loadedSkin?.views.contains(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) == true,
                   id.caseInsensitiveCompare(presentation.viewID) != .orderedSame {
                    switchedView = true; switchView(presentation, to: id)
                }
            default: continue
            }
        }
        return switchedView
    }

    /// **A transaction's timers are a delta, not the live set (W119).** `setTimeout` is what a
    /// skin's own clock loop is built out of, and this used to cancel every running one and start
    /// the survivors' sleeps again from zero — so a transaction that registered none, which is
    /// nearly all of them, stopped the skin's timers outright. That is invisible until something
    /// else is running transactions: with a track playing, the host's position tick reaches this
    /// controller ten times a second, so every script timer in the skin died within 100 ms of the
    /// user pressing play, and any timer with a period longer than that could never have fired at
    /// all. Registering is additive, `clearTimeout` is what removes one, and a token already
    /// running is left alone rather than restarted.
    ///
    /// The Phase 0 active-timer limit is enforced on the **resulting** set, which is the quantity
    /// the limit is about; a per-transaction cap could never see the total. It is per window,
    /// because the tokens are: two open panels each run their own chain.
    private func applyTimerDelta(_ presentation: WMPViewPresentation,
                                 registered: [WMPJScriptTimerRequest], cleared: [Int]) {
        for token in cleared {
            presentation.scriptTimerTasks.removeValue(forKey: token)?.cancel()
        }
        for request in registered {
            guard presentation.scriptTimerTasks[request.token] == nil,
                  presentation.scriptTimerTasks.count < WMPPhase0Limits.activeTimers else { continue }
            let period = max(WMPPhase0Limits.minimumTimerPeriodMilliseconds, request.periodMilliseconds)
            presentation.scriptTimerTasks[request.token] = Task { [weak self, weak presentation] in
                repeat {
                    try? await Task.sleep(nanoseconds: UInt64(period) * 1_000_000)
                    guard !Task.isCancelled, let presentation else { return }
                    // A one-shot retires itself: the context reported it once, and nothing else
                    // would ever take it out of the running set.
                    if !request.repeats { presentation.scriptTimerTasks.removeValue(forKey: request.token) }
                    self?.dispatchTimer(presentation, request)
                } while request.repeats && !Task.isCancelled
            }
        }
    }

    private func dispatchTimer(_ presentation: WMPViewPresentation, _ request: WMPJScriptTimerRequest) {
        guard let skin = loadedSkin, let store = imageStore,
              let activeScene = presentation.activeScene, let scriptRuntime else { return }
        let viewID = presentation.viewID
        presentation.scriptTask?.cancel()
        presentation.scriptTask = Task { [weak self, weak presentation] in
            guard let self, let presentation else { return }
            let event = WMPJScriptEvent(name: "timer", targetID: nil, handlers: [request.source],
                                        pointer: Self.currentPointer(presentation))
            let output = await scriptRuntime.transact(skin: skin, viewID: viewID,
                size: activeScene.canvasSize, snapshot: host.snapshot, event: event,
                geometry: activeScene.scriptGeometry, animatesTweens: true)
            // Commands before drawing, and for the reason in `dispatchScriptTransaction`: the
            // build and the render are what a later tick cancels, and the commands are not theirs.
            let switchedView = self.applyHostCommands(output.hostCommands, from: presentation)
            // **A timer handler is where the next timer is registered.** The WMP idiom is a chain:
            // the callback does its step and calls `setTimeout` again for the next one. This path
            // used to drop what the tick asked for, so a chain fired exactly once and stopped —
            // and it is the only transaction site that could ever see a chained request (W119).
            if !switchedView {
                self.applyTimerDelta(presentation, registered: output.timerRequests,
                                     cleared: output.clearedTimerTokens)
                self.startTweenLoop(presentation, hasActiveTweens: output.hasActiveTweens)
            }
            self.recordScriptDiagnostics(output.diagnostics)
            guard !switchedView, !Task.isCancelled else { return }
            do {
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: viewID, requestedSize: activeScene.canvasSize,
                           overrides: output.overrides)
                let rendered = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: self.renderBackingScale(for: presentation),
                    clock: presentation.animationClock(for: scene.viewID),
                    slotClocks: Self.slotClocks(presentation, for: scene, store: store))
                presentation.sceneOverrides = output.overrides
                presentation.activeScene = scene
                self.startAnimation(presentation, for: scene)
                presentation.mainView?.updateListItems(output.listItems)
                presentation.mainView?.updateWidgetState(output.widgetState)
                presentation.mainView?.present(rendered.image, overlay: rendered.overlayImage, silhouette: rendered.silhouetteMask,
                                               scene: scene, traceSource: "timer")
                self.arbitrateVideoSurface()
            } catch { self.recordScriptDiagnostics([.init(code: "timer-transaction", message: error.localizedDescription)]) }
        }
    }

    /// `theme.openDialog('FILE_OPEN', …)`, which is how a `.wmz` skin's own Open button starts
    /// playback. Without it WMP mode has no route to a track at all.
    private func presentOpenMediaPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Open media"
        panel.allowedContentTypes = AudioFileValidator.supportedExtensions
            .union(AudioFileValidator.supportedVideoExtensions).union(["cue"]).sorted()
            .compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        var tracks: [Track] = []
        var seenCueSources = Set<String>()
        for url in panel.urls {
            if let expanded = AudioEngine.tracksForCueOrSibling(url: url), !expanded.isEmpty {
                if let source = expanded.first?.cueSourceURL?.standardizedFileURL.path,
                   !seenCueSources.insert(source).inserted { continue }
                tracks.append(contentsOf: expanded)
            } else {
                tracks.append(Track(url: url))
            }
        }
        guard !tracks.isEmpty else { return }
        WindowManager.shared.audioEngine.loadTracks(tracks)
        WindowManager.shared.audioEngine.play()
        refreshHostState()
    }

    /// **Drive whatever the skin asked to animate, one frame at a time (W194).**
    ///
    /// `moveTo`/`resizeTo`/`alphaBlendTo` name a duration and nothing in the corpus ever moved over
    /// it: the endpoint landed at the handler boundary and `onEndMove` was raised in the same
    /// transaction, so a 1,000 ms slide took one frame — reported against `Compact`'s drawers as
    /// *"its not a smooth opening"*. The runtime holds the motion and this is the clock it runs on.
    ///
    /// **It is deliberately not the animation loop.** That one paces to the shortest GIF delay in
    /// the scene and exists only for scenes that have artwork frames; a tween is motion the script
    /// asked for, runs for a known length of time, and re-renders because the *geometry* moved. A
    /// scene can be doing both at once and neither cadence is the other's.
    ///
    /// One loop per view, started by whichever transaction first reports motion and left running
    /// while frames are still owed — a tween started by a completion handler is picked up by the
    /// frame it was raised from, so a chained sequence keeps the loop it is already in rather than
    /// starting a second one. It stops with the view's other clocks (`stopAllTimers`).
    private func startTweenLoop(_ presentation: WMPViewPresentation, hasActiveTweens: Bool) {
        guard hasActiveTweens, presentation.tweenTask == nil else { return }
        let interval = TimeInterval(WMPJScriptProtocol.tweenFramePeriodMilliseconds) / 1_000
        presentation.tweenTask = Task { [weak self, weak presentation] in
            defer { presentation?.tweenTask = nil }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, let self, let presentation else { return }
                guard await self.presentTweenFrame(presentation) else { return }
            }
        }
    }

    /// One tween frame: step the motion, then draw the view it moved.
    ///
    /// Answers whether another frame is owed. **A frame is a full transaction and a full rebuild**,
    /// for the same reason a script transaction is (see `dispatchScriptTransaction`): a handler
    /// writes one pane's `top` and a whole subtree moves with it, and the dirty region that would
    /// describe cannot be derived from what the tween wrote.
    ///
    /// The window can change size inside a frame, and `Compact` is why the row called the callback
    /// the risk rather than the tween: its drawer's `onEndMove` shrinks the player, so the last
    /// frame of a closing slide is the frame that resizes the window — which now happens a beat
    /// after the drawer starts moving, exactly as it does in WMP, instead of in the click.
    private func presentTweenFrame(_ presentation: WMPViewPresentation) async -> Bool {
        guard let skin = loadedSkin, let store = imageStore, let scriptRuntime,
              let activeScene = presentation.activeScene else { return false }
        let viewID = presentation.viewID
        guard let output = await scriptRuntime.tweenFrame(
            skin: skin, viewID: viewID, size: activeScene.canvasSize,
            snapshot: host.snapshot, geometry: activeScene.scriptGeometry) else { return false }
        // A completion handler is a handler like any other: it can post commands, register timers
        // and switch the view, and a switch owns everything after it.
        let switchedView = applyHostCommands(output.hostCommands, from: presentation)
        recordScriptDiagnostics(output.diagnostics)
        guard !switchedView, presentation.viewID == viewID else { return false }
        if let assigned = output.viewSize { presentation.scriptViewSize = assigned }
        applyTimerDelta(presentation, registered: output.timerRequests,
                        cleared: output.clearedTimerTokens)
        let windowSize = WMPSize(
            width: presentation.window.contentLayoutRect.width / uiScale,
            height: presentation.window.contentLayoutRect.height / uiScale)
        let rebuildSize = presentation.scriptViewSize ?? windowSize
        do {
            let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                .build(viewID: viewID, requestedSize: rebuildSize,
                       interactionState: presentation.interactionState,
                       overrides: output.overrides)
            let rendered = try await WMPRenderer(imageStore: store).render(
                scene: scene, backingScale: renderBackingScale(for: presentation),
                clock: presentation.animationClock(for: scene.viewID),
                slotClocks: Self.slotClocks(presentation, for: scene, store: store))
            guard presentation.viewID == viewID else { return false }
            if scene.canvasSize != windowSize {
                setWindowSize(presentation, NSSize(width: scene.canvasSize.width,
                                                   height: scene.canvasSize.height))
            }
            presentation.sceneOverrides = output.overrides
            presentation.activeScene = scene
            startAnimation(presentation, for: scene)
            presentation.presentedListItems = output.listItems
            presentation.presentedWidgetState = output.widgetState
            presentation.mainView?.updateListItems(output.listItems)
            presentation.mainView?.updateWidgetState(output.widgetState)
            presentation.mainView?.present(rendered.image, overlay: rendered.overlayImage, silhouette: rendered.silhouetteMask,
                                           scene: scene, traceSource: "tween")
            arbitrateVideoSurface()
        } catch {
            recordScriptDiagnostics([.init(code: "tween-frame",
                                           message: error.localizedDescription)])
            return false
        }
        return output.hasActiveTweens
    }

    /// Drive the scene's animated artwork, if it has any.
    ///
    /// 90 of the 180 corpus archives carry a multi-frame GIF. The loop re-renders at the shortest
    /// frame delay the scene actually uses — no fixed frame rate — and does not exist at all for a
    /// scene with no animation, which is the other half of the corpus and every static view.
    ///
    /// **Two things here decide the frame rate the user actually sees, and both were wrong.**
    /// Measured live on `AlienMorph` with `WMP_ANIM_TRACE=1`: `want=25.0fps got=20.0fps frames=21
    /// restarts=10 sleep=42.3ms render=4.5ms`.
    ///
    /// * **A rebuild must not restart the loop.** This is called by *every* rebuild, and a `.wmz`
    ///   rebuilds constantly — AlienMorph's 100 ms view timer alone restarted it 10x a second.
    ///   Cancelling mid-sleep throws the elapsed part of that sleep away, so with a 40 ms frame
    ///   period inside a 100 ms rebuild window exactly two frames landed per window: 20 fps for a
    ///   scene asking for 25, and the shortfall grows as the rebuild period approaches the frame
    ///   period. The loop now keeps running while the cadence is unchanged, and renders
    ///   `presentation.activeScene` rather than the scene it was started with — a rebuild replaces
    ///   what it draws without interrupting when it draws. A cadence change, a view change and
    ///   teardown still stop it.
    /// * **Frames are scheduled against the epoch, not against "now + period".** `Task.sleep`
    ///   overshoots (42.3 ms for a 40 ms request) and the render that follows it is serial, so
    ///   sleeping a period per frame accumulated 4.5 ms of render into every frame interval.
    ///   Deadlines off the animation epoch absorb both, and are the same clock
    ///   `WMPImageAnimation.frame(at:)` picks the frame with — so a frame that runs late draws the
    ///   frame it was late for rather than putting the animation behind. Falling a whole period
    ///   behind skips to the next boundary instead of bursting to catch up.
    /// Each animated slot's own clock for this render, seeding any slot that has just appeared.
    ///
    /// Static so the escaping render closures can call it without capturing the controller; the
    /// state it advances belongs to the presentation.
    private static func slotClocks(_ presentation: WMPViewPresentation?, for scene: WMPScene,
                                   store: WMPImageStore) -> [WMPRenderer.WMPAnimationSlot: TimeInterval] {
        guard let presentation else { return [:] }
        return presentation.animationSlotClocks(
            for: WMPRenderer(imageStore: store).animatedSlots(in: scene))
    }

    private func startAnimation(_ presentation: WMPViewPresentation, for scene: WMPScene) {
        guard let store = imageStore,
              let cadence = WMPRenderer(imageStore: store).animationCadence(for: scene) else {
            presentation.stopAnimation()
            return
        }
        if presentation.animationEpochViewID != scene.viewID {
            presentation.stopAnimation()
            presentation.animationEpoch = Date()
            presentation.animationEpochViewID = scene.viewID
        }
        // **When the last animation in the scene stops, measured from each one's own epoch** (W182).
        // `cadence.endsAt` still decides *whether* there is an end at all — it is the half that
        // knows about a marquee, which never ends and is not an image slot — and the per-slot walk
        // decides *when*. A single end measured from the view's epoch stopped the loop while a
        // GIF the script had just assigned still had frames to draw.
        let slots = WMPRenderer(imageStore: store).animatedSlots(in: scene)
        let endsAt = cadence.endsAt == nil ? nil : presentation.animationsEnd(for: slots)
        // A one-shot that has already played out needs no loop: the caller rendered this scene at
        // the same clock, so its final frame is already on screen. Without this every rebuild after
        // the animation ended would still start a task to draw that one still frame again.
        if let endsAt, Date() >= endsAt {
            presentation.animationTask?.cancel()
            presentation.animationTask = nil
            presentation.animationCadence = nil
            presentation.animationEndsAt = nil
            return
        }
        // The loop is already driving exactly this cadence, for animations that still finish when
        // it was told they would. Restarting it here is what cost the frames; the scene it renders
        // is read per frame, so there is nothing to hand it.
        if presentation.animationTask != nil, presentation.animationCadence == cadence,
           presentation.animationEndsAt == endsAt { return }
        presentation.animationTask?.cancel()
        presentation.animationCadence = cadence
        presentation.animationEndsAt = endsAt
        let period = max(WMPPhase0Limits.minimumTimerPeriodMilliseconds,
                         Int(cadence.shortestDelay * 1_000))
        let interval = TimeInterval(period) / 1_000
        let dirty = cadence.bounds
        let epoch = presentation.animationEpoch
        if Self.animationTrace { presentation.animationTraceRestarts += 1 }
        presentation.animationTask = Task { [weak self, weak presentation] in
            var deadline = (Date().timeIntervalSince(epoch) / interval).rounded(.down)
            while !Task.isCancelled {
                deadline += 1
                var wait = epoch.addingTimeInterval(deadline * interval).timeIntervalSinceNow
                if wait <= 0 {
                    // A whole period behind — a stalled main thread, a slow render, a sleeping
                    // machine. Rejoin the schedule at the next boundary; bursting through the
                    // frames that were missed would render them all to draw the last one.
                    deadline = (Date().timeIntervalSince(epoch) / interval).rounded(.down) + 1
                    wait = epoch.addingTimeInterval(deadline * interval).timeIntervalSinceNow
                }
                try? await Task.sleep(nanoseconds: UInt64(max(0, wait) * 1_000_000_000))
                guard !Task.isCancelled, let self, let presentation else { return }
                await self.renderAnimationFrame(presentation, store: store, dirty: dirty)
                if Self.animationTrace {
                    presentation.animationTraceFrames += 1
                    presentation.animationTraceSleepSeconds += max(0, wait)
                    self.emitAnimationTrace(presentation, period: period)
                }
                // A scene of one-shot GIFs stops moving; keeping the loop alive would re-render
                // the same still frame at the GIF's rate for as long as the view is open.
                if let endsAt, Date() >= endsAt { return }
            }
        }
    }

    /// The scene comes from the presentation rather than from the caller: the loop outlives any one
    /// rebuild now, so what it draws is whatever this window currently holds.
    private func renderAnimationFrame(_ presentation: WMPViewPresentation,
                                      store: WMPImageStore, dirty: WMPRect) async {
        // Only while this is still the scene in this window: a view switch or a script transaction
        // replaces it, and repainting the old one would undo what just landed.
        guard let scene = presentation.activeScene, let view = presentation.mainView else { return }
        let clock = Date().timeIntervalSince(presentation.animationEpoch)
        let slotClocks = Self.slotClocks(presentation, for: scene, store: store)
        let renderStarted = Date()
        guard let rendered = try? await WMPRenderer(imageStore: store)
            .render(scene: scene, backingScale: renderBackingScale(for: presentation),
                    clock: clock, slotClocks: slotClocks) else { return }
        let presentStarted = Date()
        guard presentation.activeScene == scene else { return }
        view.present(rendered.image, overlay: rendered.overlayImage, silhouette: rendered.silhouetteMask, scene: scene, dirtyBounds: dirty, traceSource: "animation")
        if Self.animationTrace {
            presentation.animationTraceRenderSeconds += presentStarted.timeIntervalSince(renderStarted)
            presentation.animationTracePresentSeconds += Date().timeIntervalSince(presentStarted)
        }
    }

    /// `WMP_ANIM_TRACE=1`: what the repaint loop achieved over the last second — the period it asked
    /// for against the one it got, and where the difference went. One line a second, never one a
    /// frame: an animated view repaints 20-30x/s and a per-frame line buries every other trace.
    static let animationTrace = ProcessInfo.processInfo.environment["WMP_ANIM_TRACE"] == "1"

    /// **The `load` transaction carries a clock like every other window transaction (W253).**
    ///
    /// W194 gave the tween trio a real duration by promising `animatesTweens:` from the click and
    /// view-timer paths, and left `load` out: an `onLoad` sequence chained through `onEndMove`
    /// would present its pre-tween state and complete a beat later. But a window is a window
    /// whichever transaction is running in it, and `startTweenLoop` was never reached from the
    /// open path at all — so a tween a skin authored in `onLoad` landed its endpoint in one frame.
    /// `Revert (1)`'s `onLoad="vwPlayer_OnLoad();alphaBlendTo(40,9000);"` is the clean case: a
    /// nine-second fade to translucent that arrives fully faded before the window is shown.
    ///
    /// Nothing about the headless callers changes — a render dump, the corpus census and the
    /// windowless dispatcher still promise no clock, so the settled state a sweep measures is what
    /// it always was. This is the *window's* load only.
    ///
    /// `WMP_LOAD_TWEENS=0` puts the load transaction back on the instant path, so the question
    /// "did this row cause what I am looking at?" is one launch rather than one build.
    static let animatesLoadTweens = ProcessInfo.processInfo.environment["WMP_LOAD_TWEENS"] != "0"

    private func emitAnimationTrace(_ presentation: WMPViewPresentation, period: Int) {
        let elapsed = Date().timeIntervalSince(presentation.animationTraceWindowStart)
        guard elapsed >= 1, presentation.animationTraceFrames > 0 else { return }
        let frames = Double(presentation.animationTraceFrames)
        NSLog("[wmp/anim] %@ want=%.1ffps got=%.1ffps frames=%d restarts=%d sleep=%.1fms render=%.1fms present=%.1fms",
              presentation.viewID, 1_000 / Double(period), frames / elapsed,
              presentation.animationTraceFrames, presentation.animationTraceRestarts,
              presentation.animationTraceSleepSeconds / frames * 1_000,
              presentation.animationTraceRenderSeconds / frames * 1_000,
              presentation.animationTracePresentSeconds / frames * 1_000)
        presentation.animationTraceWindowStart = Date()
        presentation.animationTraceFrames = 0
        presentation.animationTraceRestarts = 0
        presentation.animationTraceRenderSeconds = 0
        presentation.animationTracePresentSeconds = 0
        presentation.animationTraceSleepSeconds = 0
    }

    /// The `VIEW`'s own `timerInterval`, in milliseconds: zero stops it, anything else restarts it
    /// at that period and dispatches the view's authored `onTimer` handlers.
    ///
    /// This is how a skin animates. Corona's compact view registers a timed event and then writes
    /// `view.timerInterval`, and its player view declares `timerInterval="4000"` in markup to drive
    /// its own transport readouts — so without this a `.wmz` sits frozen in whatever state it was
    /// authored in, with no diagnostic anywhere to say why.
    private func setViewTimer(_ presentation: WMPViewPresentation, milliseconds: Int) {
        presentation.viewTimerTask?.cancel()
        presentation.viewTimerTask = nil
        presentation.viewTimerMilliseconds = max(0, milliseconds)
        guard milliseconds > 0 else { return }

        let period = max(WMPPhase0Limits.minimumTimerPeriodMilliseconds, milliseconds)
        presentation.viewTimerTask = Task { [weak self, weak presentation] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(period) * 1_000_000)
                guard !Task.isCancelled, let self, let presentation else { return }
                self.dispatchScriptEvent(presentation, name: "timer", targetID: nil)
            }
        }
    }

    /// **Find the windowless view the skin keeps running alongside the player, and start it (W89).**
    ///
    /// 24 of the 180 corpus archives — the whole Skins Factory family and everything built from its
    /// template — author `<view id="controlView" timerInterval="100" onTimer="checkRemoteViewStatus()">`
    /// with no window of its own, and route their panel, minimize and close buttons through it: the
    /// button writes a preference and this handler is what reads it back and answers with
    /// `theme.openView`, `theme.closeView`, `view.minimize()` or `view.close()`. Real WMP keeps it
    /// open beside the player. Here it never becomes a window, so nothing ticked it and every one of
    /// those buttons was dead — reported live, and recorded in the user's own defaults as four
    /// `remoteCall*` flags stuck `true`, written by clicks that nothing consumed.
    ///
    /// **This is a scan, not a by-product of the candidate walk, because the walk usually never
    /// gets there.** `wmpSkinViewID` is persisted on every present, so the second launch onward
    /// starts at the player and stops — `controlView` is behind it in the list and is never
    /// visited. The first fix keyed off the walk and did nothing on any launch but the first.
    ///
    /// Three things identify it, and all three are needed. A live `timerInterval` and an authored
    /// `onTimer` are what make it a dispatcher; not being the presented view is what makes it a
    /// *background* one; and a zero canvas is what makes it windowless — without that last test an
    /// equaliser panel that happens to declare a clock would be run while it is off screen. The
    /// markup prefilter is only to bound the cost: a view sized by its own artwork or by the union
    /// of its subtree declares none of the three attributes either, so the build is what decides.
    private func adoptDispatcher(in skin: WMPLoadedSkin, store: WMPImageStore,
                                 presenting viewID: String, loaded: Set<String>) async {
        stopDispatcher()
        for registration in skin.views
        where registration.id.caseInsensitiveCompare(viewID) != .orderedSame {
            let declares = { (name: String) in
                registration.node.attributes.contains {
                    $0.name.caseInsensitiveCompare(name) == .orderedSame
                }
            }
            guard !declares("width"), !declares("height"), !declares("backgroundImage"),
                  Self.authoredTimerInterval(in: skin, viewID: registration.id) > 0,
                  !Self.handlers(in: skin, event: "timer", targetID: nil,
                                 viewID: registration.id).isEmpty,
                  let scene = try? await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                      .build(viewID: registration.id),
                  scene.canvasSize.width <= 0 || scene.canvasSize.height <= 0 else { continue }
            dispatcherViewID = registration.id
            if !loaded.contains(WMPPath.fold(registration.id)) {
                await runSkippedDispatcherLoad(in: skin, viewID: registration.id,
                                               size: scene.canvasSize, player: viewID)
            }
            startDispatcherTimer(in: skin)
            return
        }
    }

    /// **The dispatcher's `onLoad` is the skin's launch, and the walk skips it on every launch but
    /// the first (W299).** The same persisted `wmpSkinViewID` that keeps the walk from reaching the
    /// timer keeps it from reaching `onLoad` — and the Skins Factory family's `onLoadSkin()` is
    /// where the panels the user left open are re-opened from their `plViewer`/`eqViewer`/…
    /// preferences. Skipping it left `plViewer` saying `"true"` over no window, so `btnPl`'s
    /// `toggleView` "closed" it and the second click was the first to open anything. Run here, its
    /// commands take the same route as the walk's deferred ones: against the player, minus the
    /// player's own `openView`.
    private func runSkippedDispatcherLoad(in skin: WMPLoadedSkin, viewID: String, size: WMPSize,
                                          player playerViewID: String) async {
        guard let scriptRuntime, let player = materializer.playerPresentation else { return }
        let event = WMPJScriptEvent(name: "load", targetID: viewID,
            handlers: Self.handlers(in: skin, event: "load", targetID: nil, viewID: viewID))
        guard !event.handlers.isEmpty else { return }
        await scriptRuntime.discardView(viewID)
        let output = await scriptRuntime.transact(skin: skin, viewID: viewID, size: size,
                                                  snapshot: host.snapshot, event: event)
        guard dispatcherViewID == viewID else { return }
        applyHostCommands(output.hostCommands.filter {
            $0.value?.string?.caseInsensitiveCompare(playerViewID) != .orderedSame
        }, from: player)
        recordScriptDiagnostics(output.diagnostics)
    }

    /// Start the background dispatcher's clock. Its period is the `timerInterval` the view authors,
    /// which is 100 ms in all 24 corpus skins that use this idiom. Unlike the view timer, a tick
    /// builds no scene and renders nothing — it runs one handler and applies whatever host commands
    /// it posts — so it neither cancels a window's `scriptTask` nor competes with its animation.
    private func startDispatcherTimer(in skin: WMPLoadedSkin) {
        dispatcherTimerTask?.cancel()
        dispatcherTimerTask = nil
        guard let viewID = dispatcherViewID else { return }
        let milliseconds = Self.authoredTimerInterval(in: skin, viewID: viewID)
        dispatcherHandlers = Self.handlers(in: skin, event: "timer", targetID: nil, viewID: viewID)
        guard milliseconds > 0, !dispatcherHandlers.isEmpty else { return }
        let period = max(WMPPhase0Limits.minimumTimerPeriodMilliseconds, milliseconds)
        dispatcherTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(period) * 1_000_000)
                guard !Task.isCancelled else { return }
                await self?.dispatchDispatcherTick()
            }
        }
    }

    private func dispatchDispatcherTick() async {
        guard let skin = loadedSkin, let scriptRuntime, let viewID = dispatcherViewID,
              let player = materializer.playerPresentation, !dispatcherHandlers.isEmpty else { return }
        let snapshot = host.snapshot
        let videoEvents = WMPVideoPresentation.events(previous: dispatcherVideoSnapshot, current: snapshot.videoEvent)
        dispatcherVideoSnapshot = snapshot.videoEvent
        let videoHandlers = videoEvents.flatMap {
            Self.handlers(in: skin, event: $0, targetID: nil, viewID: viewID)
        }
        let event = WMPJScriptEvent(name: (["timer"] + videoEvents).joined(separator: ","),
                                   targetID: viewID, handlers: videoHandlers + dispatcherHandlers,
                                   pointer: Self.currentPointer(player))
        let output = await scriptRuntime.dispatch(skin: skin, viewID: viewID,
                                                  currentViewID: player.viewID,
                                                  snapshot: snapshot, event: event)
        guard !Task.isCancelled, dispatcherViewID == viewID else { return }
        // `timerRequests` are deliberately dropped rather than scheduled. `applyTimerDelta` owns a
        // *window's* set and `dispatchTimer` runs what it schedules against that window — so
        // honouring a dispatcher's `setTimeout` here would attach it to a window it does not belong
        // to. No corpus dispatcher asks for one; if one ever does, it needs its own schedule.
        //
        // The player is the window a dispatcher's commands run against: it is the one the user is
        // looking at, which is what `theme.currentViewID` answers from here, and its `openView`
        // calls are the whole point of the idiom.
        _ = applyHostCommands(output.hostCommands, from: player)
        recordScriptDiagnostics(output.diagnostics)
    }

    private func stopDispatcher() {
        dispatcherTimerTask?.cancel()
        dispatcherTimerTask = nil
        dispatcherViewID = nil
        dispatcherHandlers = []
        dispatcherVideoSnapshot = nil
    }

    private func recordScriptDiagnostics(_ diagnostics: [WMPJScriptDiagnostic]) {
        guard !diagnostics.isEmpty else { return }
        // A live script error is the one thing the input trace could not see. The headless probes
        // print `SCRIPT-DIAG`; without the same line here, a handler that throws in the running app
        // is indistinguishable from one that ran and did nothing.
        lastLoadDiagnostic = diagnostics.map { "[\($0.code)] \($0.message)" }.joined(separator: "\n")
        #if DEBUG
        // **The line the comment above promised, which was never printed.** `WMP_SCRIPT_TRACE=1`
        // emits it; the field alone is only readable from the debug window, so a handler throwing
        // once per timer tick in the running app left no trace at all.
        if ProcessInfo.processInfo.environment["WMP_SCRIPT_TRACE"] == "1" {
            for diagnostic in diagnostics {
                NSLog("[wmp/script] %@: %@", diagnostic.code, diagnostic.message)
            }
        }
        #endif
    }

    private func renderBackingScale(for presentation: WMPViewPresentation?) -> CGFloat {
        max(1, presentation?.window.backingScaleFactor
            ?? window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
    }

    /// What the scene is rasterized at: the display's backing scale multiplied by UI Size, so a
    /// zoomed window is drawn from a larger bitmap rather than a magnified one.
    ///
    /// Clamped to the renderer's own pixel ceiling. `WMPRenderer` *throws* `oversizedImage` past
    /// it, and a throw here leaves the window showing the frame it already had — a large skin at
    /// 300% on a Retina display would simply stop repainting. Losing sharpness at the top of the
    /// ladder is the right trade against that.
    private func renderScale(for canvas: WMPSize) -> CGFloat {
        let requested = renderBackingScale(for: materializer.playerPresentation) * uiScale
        let pixels = canvas.width * canvas.height
        guard pixels > 0, requested > 1 else { return max(1, requested) }
        let ceiling = (CGFloat(WMPPhase0Limits.imagePixels) / pixels).squareRoot()
        return max(1, min(requested, ceiling))
    }

    // MARK: - UI Size

    /// Applies the host's UI Size to every WMP window: each frame becomes its skin-space size times
    /// the multiplier, anchored at its top-left, and its scene is re-rasterized at the new scale.
    ///
    /// `WindowManager.applyDoubleSize` calls this and then sets the player's frame itself from
    /// `mainWindowSize(atScale:)`; the two agree, so the second set is a no-op.
    func applyUIScale(_ scale: CGFloat) {
        let target = max(0.1, scale)
        guard target != uiScale else { return }
        uiScale = target
        guard !materializer.isEmpty else {
            guard let window else { return }
            let scaled = NSSize(width: Self.unskinnedSize.width * target,
                                height: Self.unskinnedSize.height * target)
            var frame = window.frame
            frame.size = scaled
            frame.origin.y = window.frame.maxY - scaled.height
            window.setFrame(frame, display: true)
            unskinnedView?.setBoundsSize(Self.unskinnedSize)
            window.invalidateShadow()
            return
        }
        for presentation in materializer.openPresentations {
            setWindowSize(presentation, presentation.skinSpaceSize)
            presentation.window.invalidateShadow()
            renderCurrentSize(presentation)
        }
    }

    /// The window size this skin wants at `scale` — its skin-space size times the multiplier. The
    /// unskinned player answers the same way, from its own fixed size.
    func mainWindowSize(atScale scale: CGFloat) -> NSSize? {
        NSSize(width: skinSpaceSize.width * scale, height: skinSpaceSize.height * scale)
    }

    /// The windows this skin has open, for `WindowManager`'s docking branch.
    var materializedAuxiliaryWindows: [NSWindow] { materializer?.auxiliaryWindows ?? [] }

    /// Whether any open WMP window is showing a view that provides `surface`.
    func anyOpenViewProvides(_ surface: WMPSkinSurface) -> Bool {
        materializer?.anyOpenView(where: { skinSurfaces.view($0, provides: surface) }) ?? false
    }
}
