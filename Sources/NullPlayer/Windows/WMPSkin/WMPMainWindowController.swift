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
}

final class WMPMainWindowController: NSWindowController, MainWindowProviding, NSWindowDelegate {
    static let unskinnedSize = NSSize(width: 440, height: 170)
    /// The two events raised on the pointer crossing a control's edge, dispatched only where the
    /// markup authored a handler for them. See `dispatchScriptEvent(name:targetID:…)`.
    static let hoverEvents: Set<String> = ["mouseover", "mouseout"]

    private let importer: WMPSkinImporter
    private let host: any WMPHost
    /// **The effect selection is the one host property nothing else refreshes for.** Every other
    /// path into `refreshHostState` is a track, a clock tick, a transport action or a file open;
    /// choosing a visualization from NullPlayer's own menu goes through `WMPEffectSelection` and
    /// touches none of them. With a track playing the 10 Hz position tick hides that — the event
    /// lands within 100 ms and looks immediate — and with the player stopped the skin's
    /// `currentEffectType_onchange` would never be raised at all (W129).
    private var effectSelectionObserver: NSObjectProtocol?
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

    /// The colours NullPlayer's *own* windows are drawn in while this skin is presented — see
    /// `WMPSurfacePalette`. Nil whenever the app-authored unskinned player is up, which is what makes
    /// `WindowManager.hostedSurfaceStyle` nil there and sends those windows back to their own drawing.
    private(set) var currentSurfacePalette: WMPSurfacePalette?
    private var scriptRuntime: WMPScriptRuntime?
    private var lastScriptSnapshot: WMPHostSnapshot?
    private var unskinnedView: WMPUnskinnedMainView?

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
    /// `video reordered above parent` traces in `SKILL.md` § W102 are the check that this is not
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
        effectSelectionObserver = NotificationCenter.default.addObserver(
            forName: WMPEffectSelection.didChange, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshHostState() } }
        configureWindow()
        presentUnskinned(message: nil)
        reloadSelectedSkin()
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let effectSelectionObserver {
            NotificationCenter.default.removeObserver(effectSelectionObserver)
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

    func reloadSelectedSkin() {
        loadTask?.cancel()
        stopDispatcher()
        materializer.teardown()
        bindingCache.removeAll()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let url = try importer.selectedSkinURL() else {
                    presentUnskinned(message: nil)
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
                var candidates: [String] = []
                if let preferred = importer.selectedViewID { candidates.append(preferred) }
                candidates.append("vPlayer")
                candidates.append(contentsOf: skin.views.map(\.id))
                var visited = Set<String>()
                var index = 0
                var presented = false
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
                        geometry: scene.scriptGeometry)
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
                        // The only host command a view with no window can honour is where to go
                        // next; the rest need the presented controller state this view never gets.
                        // A windowless `controlView` opens the real player with `openView`
                        // exactly as often as it redirects with `currentViewID`; both are a
                        // request for which view to show next, and neither can do more than that
                        // from a view that never becomes a window.
                        if let next = output.hostCommands.last(where: {
                            $0.action == "setCurrentView" || $0.action.hasPrefix("openView")
                        })?.value?.string {
                            candidates.insert(next, at: index)
                        }
                        continue
                    }
                    if pendingRestoredFrame != nil, !restoredViewMatches {
                        pendingRestoredFrame = nil
                        pendingRestoredViewID = nil
                    }
                    let resolved = try await builder.build(viewID: registration.id,
                        requestedSize: scene.canvasSize, overrides: output.overrides)
                    let rendered = try await WMPRenderer(imageStore: store).render(
                        scene: resolved, backingScale: renderScale(for: resolved.canvasSize))
                    try Task.checkCancellation()
                    // The first view with a canvas binds the app's own window and becomes the
                    // player; everything the skin opens after it gets a window of its own.
                    guard let presentation = materializer.materialize(
                        viewID: resolved.viewID,
                        size: NSSize(width: resolved.canvasSize.width,
                                     height: resolved.canvasSize.height),
                        opener: nil, offset: nil) else { continue }
                    apply(skin: skin, store: store, scene: resolved, image: rendered.image,
                          overlay: rendered.overlayImage,
                          runtime: runtime, overrides: output.overrides, into: presentation)
                    // **Before the load transaction's commands, so a skin that re-opens its own
                    // panels does not end up with two.** A dispatcher skin reads
                    // `theme.loadPreference('plViewer')` and calls `theme.openView` for each panel
                    // it had open; `show` on a view that is already open is a raise, so whichever
                    // of the two runs first wins and the other is a no-op.
                    restoreOpenAuxiliaryViews(skin: skin, store: store, runtime: runtime)
                    let switchedView = applyHostCommands(output.hostCommands, from: presentation)
                    if !switchedView {
                        applyTimerDelta(presentation, registered: output.timerRequests,
                                        cleared: output.clearedTimerTokens)
                    }
                    recordScriptDiagnostics(output.diagnostics)
                    await adoptDispatcher(in: skin, store: store, presenting: resolved.viewID)
                    presented = true
                    break
                }
                guard presented else {
                    throw WMPFailure(WMPDiagnostic(.invalidGeometry,
                        "The skin contains no renderable WMP view."))
                }
            } catch is CancellationError {
                return
            } catch {
                presentUnskinned(message: error.localizedDescription)
            }
        }
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
        pendingRestoredFrame = WMPWindowRestorePolicy.safeFrame(frame, screens: NSScreen.screens.map(\.visibleFrame))
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
                       overlay: CGImage? = nil,
                       runtime: WMPScriptRuntime, overrides: WMPSceneOverrides,
                       into presentation: WMPViewPresentation) {
        loadedSkin = skin
        imageStore = store
        materializer.rekey(presentation, to: scene.viewID)
        presentation.activeLimits = scene.resizeLimits
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
        view.onScriptEvent = { [weak self, weak presentation] name, targetID, targetStableID in
            guard let self, let presentation else { return }
            self.dispatchScriptEvent(presentation, name: name, targetID: targetID,
                                     targetStableID: targetStableID,
                                     onlyWhenAuthored: Self.hoverEvents.contains(name))
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
        view.onElementValueChanged = { [weak self, weak presentation] stableID, targetID, value in
            guard let self, let presentation, let scriptRuntime = self.scriptRuntime else { return }
            Task {
                await scriptRuntime.setWidgetValue(stableID: stableID, value: value,
                                                   viewID: presentation.viewID)
                self.dispatchScriptEvent(presentation, name: "change", targetID: targetID,
                                         targetStableID: stableID)
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
        view.present(image, overlay: overlay, scene: scene)
        view.refreshHostState(host.snapshot)
        startAnimation(presentation, for: scene)
        arbitrateVideoSurface()
        if presentation.isPlayer {
            publishSurfacePalette(skin: skin, viewID: scene.viewID, rendered: image)
        }
        skinSurfaces = WMPSkinSurfaces(skin: skin)
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
        guard palette != currentSurfacePalette else { return }
        currentSurfacePalette = palette
        NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
    }

    private func clearSurfacePalette() {
        skinSurfaces = .empty
        guard currentSurfacePalette != nil else { return }
        currentSurfacePalette = nil
        NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
    }

    private func presentUnskinned(message: String?) {
        clearSurfacePalette()
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
                    .build(viewID: viewID, requestedSize: requested, overrides: resolvedOverrides)
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
                        .build(viewID: viewID, requestedSize: requested, overrides: resolvedOverrides)
                }
                let result = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: self?.renderScale(for: scene.canvasSize) ?? 1,
                    clock: presentation?.animationClock(for: scene.viewID) ?? 0)
                try Task.checkCancellation()
                guard let self, let presentation else { return }
                presentation.sceneOverrides = resolvedOverrides
                presentation.activeScene = scene
                self.startAnimation(presentation, for: scene)
                if let scriptOutput { presentation.mainView?.updateListItems(scriptOutput.listItems) }
                presentation.mainView?.present(result.image, overlay: result.overlayImage, scene: scene)
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
        let savedSize = frameStore.size(skin: skinName, view: registration.id)
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
                    geometry: base.scriptGeometry)
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
                    // against whoever asked for it.
                    if let target = existing ?? opener ?? materializer.playerPresentation {
                        _ = applyHostCommands(output.hostCommands, from: target)
                    }
                    return
                }
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: registration.id, requestedSize: base.canvasSize,
                           overrides: output.overrides)
                let rendered = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: renderScale(for: scene.canvasSize),
                    clock: existing?.animationClock(for: scene.viewID) ?? 0)
                try Task.checkCancellation()
                let size = NSSize(width: scene.canvasSize.width, height: scene.canvasSize.height)
                guard let presentation = existing ?? materializer.materialize(
                    viewID: registration.id, size: size, opener: opener, offset: offset,
                    storedTopLeft: savedOrigin) else { return }
                apply(skin: skin, store: store, scene: scene, image: rendered.image,
                      overlay: rendered.overlayImage,
                      runtime: scriptRuntime, overrides: output.overrides, into: presentation)
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

    /// **Close one window.** `view.close()`, `theme.closeView(name)` and the macOS close control all
    /// arrive here.
    ///
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
            for other in materializer.openPresentations where other !== presentation {
                closeAuxiliaryWindow(other)
            }
            materializer.remove(presentation, closing: true)
            let viewID = presentation.viewID
            if let scriptRuntime { Task { await scriptRuntime.discardView(viewID) } }
            persistOpenViews()
            return true
        }
        closeAuxiliaryWindow(presentation)
        persistOpenViews()
        return true
    }

    private func closeAuxiliaryWindow(_ presentation: WMPViewPresentation) {
        let viewID = presentation.viewID
        if let view = presentation.mainView { setSpectrumDemand(false, from: ObjectIdentifier(view)) }
        materializer.remove(presentation)
        if let scriptRuntime { Task { await scriptRuntime.discardView(viewID) } }
        arbitrateVideoSurface()
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
        guard let limits = materializer.presentation(for: sender)?.activeLimits else {
            return NSSize(width: Self.unskinnedSize.width * uiScale,
                          height: Self.unskinnedSize.height * uiScale)
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
        presentation.skinSpaceSize = NSSize(width: presentation.window.frame.width / uiScale,
                                            height: presentation.window.frame.height / uiScale)
        // Persisted in skin space as well, so a size the user dragged out at 200% is not restored
        // as a scene twice that size the next time the skin loads.
        WMPViewFrameStore(defaults: importer.defaults).setSize(
            WMPSize(width: presentation.skinSpaceSize.width,
                    height: presentation.skinSpaceSize.height),
            skin: importer.selectedSkinName ?? "", view: presentation.viewID)
        renderCurrentSize(presentation)
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        guard let presentation = materializer.playerPresentation else { return }
        renderCurrentSize(presentation)
    }
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        let origin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: origin)
        persistViewFrame(for: window)
    }
    func windowWillMiniaturize(_ notification: Notification) {
        if let window { WindowManager.shared.attachDockedWindowsForMiniaturize(mainWindow: window) }
    }
    func windowDidDeminiaturize(_ notification: Notification) {
        if let window { WindowManager.shared.detachDockedWindowsAfterDeminiaturize(mainWindow: window) }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
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

    func updateTrackInfo(_ track: Track?) { refreshHostState() }
    func updateVideoTrackInfo(title: String, artworkTrack: Track?) { refreshHostState() }
    func clearVideoTrackInfo() { refreshHostState() }
    func updateTime(current: TimeInterval, duration: TimeInterval) { refreshHostState() }
    func updatePlaybackState() { refreshHostState() }
    func updateSpectrum(_ levels: [Float]) {
        for presentation in materializer.openPresentations {
            presentation.mainView?.updateSpectrum(levels)
        }
    }
    func skinDidChange() {}
    func windowVisibilityDidChange() {}
    func setNeedsDisplay() { window?.contentView?.needsDisplay = true }

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
        if previous?.state != snapshot.state { events += ["openstatechange", "playstatechange"] }
        // **`status_onchange` is WMP's "the status string changed", and a clock tick is not that
        // (W119).** The bindings do have to settle ten times a second — the elapsed readout of 108
        // archives is `<TEXT value="wmpprop:player.controls.currentPositionString">` and 89 hang a
        // seek slider off `player.controls.currentPosition` — so a position tick still runs a
        // transaction. What it must not do is raise the skin's *authored* handler: `status_onchange`
        // is authored by **70 of the 177 measurable archives and every one of its 75 sources is a
        // metadata updater**, 35 of them `updateMetadata()`, whose whole body is
        // `metadata.value = player.status`. `player.status` is inert and empty here (there is no
        // status string behind it), so raising it on every tick overwrote the track readout with ""
        // ten times a second: `9SeriesDefault` runs `ShowStatus(player.status)` and drew an empty
        // metadata line beside a correct clock, reported as no track information. It also ran a
        // whole script transaction, scene rebuild and render at 10 Hz in every skin, cancelling
        // whatever click or `onTimer` transaction was still in flight.
        //
        // `positionchange` is a name **no corpus archive authors** (measured: 0 uses), which is the
        // point — it resolves to no handler anywhere, so the transaction it raises is the
        // binding-only one `dispatchScriptTransaction` already documents. A duration that changes
        // is a media that opened rather than a clock that ticked, so that keeps the status raise.
        if previous?.metadata != snapshot.metadata || previous?.duration != snapshot.duration {
            events.append("status_onchange")
        }
        if previous?.currentTime != snapshot.currentTime { events.append("positionchange") }
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
        if previous?.currentTime != snapshot.currentTime { events.append("currentposition_onchange") }
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
                                         "positionchange", "currentposition_onchange", "modechange",
                                         "buffering_onchange", "reception_onchange"]

    private func renderInteraction(_ presentation: WMPViewPresentation,
                                   state: WMPInteractionState, changed: Set<Int>) {
        guard let skin = loadedSkin, let store = imageStore,
              let activeScene = presentation.activeScene else { return }
        let viewID = presentation.viewID
        presentation.loadTask?.cancel()
        presentation.interactionState = state
        let overrides = presentation.sceneOverrides
        presentation.loadTask = Task { [weak self, weak presentation] in
            do {
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: viewID, requestedSize: activeScene.canvasSize,
                           interactionState: state, dirtyNodeIDs: changed,
                           overrides: overrides)
                let result = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: self?.renderBackingScale(for: presentation) ?? 1,
                    clock: presentation?.animationClock(for: scene.viewID) ?? 0)
                try Task.checkCancellation()
                guard let presentation else { return }
                presentation.activeScene = scene
                self?.startAnimation(presentation, for: scene)
                presentation.mainView?.present(result.image, overlay: result.overlayImage,
                                               scene: scene, dirtyBounds: scene.dirtyBounds)
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
                                     onlyWhenAuthored: Bool = false) {
        guard let skin = loadedSkin else { return }
        let handlers = Self.handlers(in: skin, event: name, targetID: targetID,
                                     targetStableID: targetStableID, viewID: presentation.viewID)
        // **A hover edge is only worth a transaction when the skin asked for one.** Every other
        // dispatch site here is a discrete act — a click, a keystroke, a view change — and runs the
        // transaction even with no authored handler, because the bindings have to settle. Hover is
        // not: the pointer crosses a whole row of buttons on the way to the one it wants, and a
        // transaction rebuilds and re-renders the entire scene (and cancels whatever click was
        // still in flight). So `onmouseover`/`onmouseout` dispatch only where the markup carries a
        // handler for them; the hover *artwork* never went through here and is unaffected.
        if onlyWhenAuthored, handlers.isEmpty { return }
        dispatchScriptTransaction(presentation,
                                  WMPJScriptEvent(name: name, targetID: targetID,
                                                  handlers: handlers))
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
    /// `player.status`, which this engine has nothing behind and answers as the empty string.
    private static func arguments(for event: String,
                                  _ snapshot: WMPHostSnapshot) -> [String: WMPJSONValue] {
        switch event {
        case "openstatechange":
            return ["NewState": .number(Double(snapshot.playlistCount > 0
                ? WMPScriptConstants.osMediaOpen : WMPScriptConstants.osUndefined))]
        case "playstatechange":
            return ["NewState": .number(Double(WMPScriptConstants.playState(for: snapshot.state)))]
        case "status_onchange":
            return ["status": .string("")]
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

    private func dispatchScriptTransaction(_ presentation: WMPViewPresentation,
                                           _ event: WMPJScriptEvent) {
        guard let skin = loadedSkin, let store = imageStore,
              let activeScene = presentation.activeScene, let scriptRuntime else { return }
        let viewID = presentation.viewID
        // A binding-only transaction is still required when no authored handler exists.
        presentation.scriptTask?.cancel()
        presentation.scriptTask = Task { [weak self, weak presentation] in
            guard let self, let presentation else { return }
            let output = await scriptRuntime.transact(skin: skin, viewID: viewID,
                size: activeScene.canvasSize, snapshot: host.snapshot, event: event,
                geometry: activeScene.scriptGeometry)
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
            let switchedView = applyHostCommands(output.hostCommands, from: presentation)
            if let assigned = output.viewSize, !switchedView {
                presentation.scriptViewSize = assigned
                setWindowSize(presentation,
                              NSSize(width: assigned.width, height: assigned.height))
            }
            if !switchedView {
                applyTimerDelta(presentation, registered: output.timerRequests,
                                cleared: output.clearedTimerTokens)
            }
            recordScriptDiagnostics(output.diagnostics)
            guard !switchedView, !Task.isCancelled else { return }
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
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: viewID,
                           requestedSize: presentation.scriptViewSize ?? activeScene.canvasSize,
                           interactionState: presentation.interactionState,
                           overrides: output.overrides)
                let result = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: renderBackingScale(for: presentation),
                    clock: presentation.animationClock(for: scene.viewID))
                guard !Task.isCancelled else { return }
                presentation.sceneOverrides = output.overrides
                presentation.activeScene = scene
                self.startAnimation(presentation, for: scene)
                presentation.mainView?.updateListItems(output.listItems)
                presentation.mainView?.present(result.image, overlay: result.overlayImage, scene: scene)
                self.arbitrateVideoSurface()
            } catch { recordScriptDiagnostics([.init(code: "scene-transaction", message: error.localizedDescription)]) }
        }
    }

    /// The `timerInterval` the view declares in markup, which starts the view timer before any
    /// script has had a chance to change it.
    static func authoredTimerInterval(in skin: WMPLoadedSkin, viewID: String) -> Int {
        guard let view = skin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        })?.node, let attribute = view.attributes.first(where: {
            $0.name.caseInsensitiveCompare("timerInterval") == .orderedSame
        }), case let .literal(raw) = attribute.value,
              let milliseconds = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return 0 }
        return max(0, milliseconds)
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
        case "change", "onchange": accepted = ["change", "valueonchange"]
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
                let duration = max(host.snapshot.duration, 0.001)
                host.perform(.seek, value: .number(max(0, min(1, (number ?? 0) / duration))))
            case "volumePercent": host.perform(.volume, value: .number(max(0, min(1, (number ?? 0) / 100))))
            case "balancePercent": host.perform(.balance, value: .number(max(-1, min(1, (number ?? 0) / 100))))
            case "setMute": if (command.value?.number ?? 0) != (host.snapshot.muted ? 1 : 0) { host.perform(.toggleMute, value: nil) }
            case "setShuffle": if (command.value?.number ?? 0) != (host.snapshot.shuffle ? 1 : 0) { host.perform(.toggleShuffle, value: nil) }
            case "setRepeat": if (command.value?.number ?? 0) != (host.snapshot.repeatMode ? 1 : 0) { host.perform(.toggleRepeat, value: nil) }
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
            let event = WMPJScriptEvent(name: "timer", targetID: nil, handlers: [request.source])
            let output = await scriptRuntime.transact(skin: skin, viewID: viewID,
                size: activeScene.canvasSize, snapshot: host.snapshot, event: event,
                geometry: activeScene.scriptGeometry)
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
            }
            self.recordScriptDiagnostics(output.diagnostics)
            guard !switchedView, !Task.isCancelled else { return }
            do {
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: viewID, requestedSize: activeScene.canvasSize,
                           overrides: output.overrides)
                let rendered = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: self.renderBackingScale(for: presentation),
                    clock: presentation.animationClock(for: scene.viewID))
                presentation.sceneOverrides = output.overrides
                presentation.activeScene = scene
                self.startAnimation(presentation, for: scene)
                presentation.mainView?.updateListItems(output.listItems)
                presentation.mainView?.present(rendered.image, overlay: rendered.overlayImage,
                                               scene: scene)
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

    /// Drive the scene's animated artwork, if it has any.
    ///
    /// 90 of the 180 corpus archives carry a multi-frame GIF. The loop re-renders at the shortest
    /// frame delay the scene actually uses — no fixed frame rate — and does not exist at all for a
    /// scene with no animation, which is the other half of the corpus and every static view.
    private func startAnimation(_ presentation: WMPViewPresentation, for scene: WMPScene) {
        presentation.animationTask?.cancel()
        presentation.animationTask = nil
        guard let store = imageStore,
              let cadence = WMPRenderer(imageStore: store).animationCadence(for: scene) else { return }
        if presentation.animationEpochViewID != scene.viewID {
            presentation.animationEpoch = Date()
            presentation.animationEpochViewID = scene.viewID
        }
        // A one-shot that has already played out needs no loop: the caller rendered this scene at
        // the same clock, so its final frame is already on screen. Without this every rebuild after
        // the animation ended would still start a task to draw that one still frame again.
        if let endsAt = cadence.endsAt,
           Date().timeIntervalSince(presentation.animationEpoch) >= endsAt { return }
        let period = max(WMPPhase0Limits.minimumTimerPeriodMilliseconds,
                         Int(cadence.shortestDelay * 1_000))
        let dirty = cadence.bounds
        let epoch = presentation.animationEpoch
        presentation.animationTask = Task { [weak self, weak presentation] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(period) * 1_000_000)
                guard !Task.isCancelled, let self, let presentation else { return }
                await self.renderAnimationFrame(presentation, scene: scene, store: store, dirty: dirty)
                // A scene of one-shot GIFs stops moving; keeping the loop alive would re-render
                // the same still frame at the GIF's rate for as long as the view is open.
                if let endsAt = cadence.endsAt, Date().timeIntervalSince(epoch) >= endsAt { return }
            }
        }
    }

    private func renderAnimationFrame(_ presentation: WMPViewPresentation, scene: WMPScene,
                                      store: WMPImageStore, dirty: WMPRect) async {
        // Only while this is still the scene in this window: a view switch or a script transaction
        // replaces it, and repainting the old one would undo what just landed.
        guard presentation.activeScene == scene, let view = presentation.mainView else { return }
        let clock = Date().timeIntervalSince(presentation.animationEpoch)
        guard let rendered = try? await WMPRenderer(imageStore: store)
            .render(scene: scene, backingScale: renderBackingScale(for: presentation),
                    clock: clock) else { return }
        guard presentation.activeScene == scene else { return }
        view.present(rendered.image, overlay: rendered.overlayImage, scene: scene, dirtyBounds: dirty)
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
                                 presenting viewID: String) async {
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
            startDispatcherTimer(in: skin)
            return
        }
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
                                   targetID: viewID, handlers: videoHandlers + dispatcherHandlers)
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

enum WMPWindowRestorePolicy {
    static func safeFrame(_ frame: NSRect, screens: [NSRect]) -> NSRect {
        guard let screen = screens.first(where: { $0.intersects(frame) }) ?? screens.first else { return frame }
        var result = frame
        // Preserve the saved top-left anchor where possible while keeping a usable strip visible.
        let visibleStrip: CGFloat = min(80, max(24, frame.width))
        result.origin.x = min(screen.maxX - visibleStrip, max(screen.minX - frame.width + visibleStrip, result.origin.x))
        result.origin.y = min(screen.maxY - frame.height, max(screen.minY - frame.height + 24, result.origin.y))
        return result
    }
}
