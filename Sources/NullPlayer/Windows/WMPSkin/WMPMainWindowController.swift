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
    #if DEBUG
    /// `WMP_TRACE_INPUT=1` — one line per input event the window turns into a script transaction,
    /// and one per transaction that reaches the screen. Read once at process start like every other
    /// probe: exporting it at an already-running app reports nothing. Documented in
    /// `skills/wmp-skin-guide/reference/harness.md`.
    static let tracesInput = ProcessInfo.processInfo.environment["WMP_TRACE_INPUT"] != nil
    static func traceInput(_ line: @autoclosure () -> String) {
        guard tracesInput else { return }
        FileHandle.standardError.write(Data(("INPUT " + line() + "\n").utf8))
    }
    #else
    static func traceInput(_ line: @autoclosure () -> String) {}
    #endif

    private let importer: WMPSkinImporter
    private let host: any WMPHost
    private var loadTask: Task<Void, Never>?
    private var scriptTask: Task<Void, Never>?
    private var scriptTimerTasks: [Int: Task<Void, Never>] = [:]
    /// The active view's own `timerInterval`, which is a host timer rather than a scene property.
    private var viewTimerTask: Task<Void, Never>?
    /// The animation repaint loop and the instant its clock is measured from. Separate from
    /// `viewTimerTask`: that one dispatches the skin's own `onTimer` and rebuilds the scene, and an
    /// animation must not do either — it re-renders the scene that already exists.
    private var animationTask: Task<Void, Never>?
    private var animationEpoch = Date()
    /// **The view the animation clock belongs to.** An animation clock is a property of the view on
    /// screen, not of the scene object — and a scene object is rebuilt by every hover repaint,
    /// every script transaction and every `onTimer` tick. `startAnimation` used to rewind the epoch
    /// on each of those, so every GIF in the view restarted from frame zero at the rate the view
    /// was rebuilt. Once the view timers started running (Phase 7) that became continuous: a view
    /// declaring `timerInterval="100"` rewound a 2.16s one-shot intro ten times a second, and it
    /// never reached its second frame. Reported live as "the animations keep opening and closing
    /// constantly", and worse under the pointer because a hover adds transactions of its own.
    private var animationEpochViewID: String?
    private var loadedSkin: WMPLoadedSkin?
    private var imageStore: WMPImageStore?
    private var activeViewID: String?
    /// Views the skin asked to *open* on top of what was showing. WMP gives each one its own
    /// window; this app has one, so the opened view is presented and the view it covered is
    /// remembered here, which is what gives `closeView` somewhere to go back to.
    private var openedViewStack: [String] = []
    private var activeLimits: WMPResizeLimits?
    private var activeScene: WMPScene?
    private var sceneOverrides = WMPSceneOverrides.empty
    /// The pointer/keyboard state the view last reported, so a **script** transaction can rebuild
    /// the scene with it. Without it a script present erases whatever hover or pressed artwork the
    /// input that raised it had just painted — measured on 2026-09-08: Melvin's buttons swapped to
    /// their `hoverImage` and were overwritten milliseconds later by the `onMouseOver` transaction,
    /// which read as hover never working at all.
    private var interactionState = WMPInteractionState()
    private var scriptRuntime: WMPScriptRuntime?
    private var lastScriptSnapshot: WMPHostSnapshot?
    private var mainView: WMPMainView?
    private var unskinnedView: WMPUnskinnedMainView?
    private var isApplyingSceneSize = false
    private var pendingRestoredFrame: NSRect?
    private var pendingRestoredViewID: String?
    private(set) var lastLoadDiagnostic: String?

    var availableViewIDs: [String] { loadedSkin?.views.map(\.id) ?? [] }
    var selectedViewID: String? { activeViewID }
    var hasCompatibilityReport: Bool { loadedSkin != nil }

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
        configureWindow()
        presentUnskinned(message: nil)
        reloadSelectedSkin()
    }

    required init?(coder: NSCoder) { nil }

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
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let url = try importer.selectedSkinURL() else {
                    presentUnskinned(message: nil)
                    return
                }
                let skin = try await importer.loader.load(from: url)
                try Task.checkCancellation()
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
                    Self.traceInput("candidate \(registration.id) canvas=\(scene.canvasSize) "
                        + "requested=\(requested.map(String.init(describing:)) ?? "-")")
                    await runtime.prepareForViewSwitch()
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
                            $0.action == "setCurrentView" || $0.action == "openView"
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
                        scene: resolved, backingScale: renderBackingScale)
                    try Task.checkCancellation()
                    apply(skin: skin, store: store, scene: resolved, image: rendered.image,
                          runtime: runtime, overrides: output.overrides)
                    let switchedView = applyHostCommands(output.hostCommands)
                    if !switchedView { scheduleTimers(output.timerRequests) }
                    recordScriptDiagnostics(output.diagnostics)
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
            positioned.size = Self.unskinnedSize
            positioned.origin.y = safe.maxY - Self.unskinnedSize.height
            window?.setFrame(positioned, display: true)
        }
    }

    private func apply(skin: WMPLoadedSkin, store: WMPImageStore, scene: WMPScene, image: CGImage,
                       runtime: WMPScriptRuntime, overrides: WMPSceneOverrides) {
        loadedSkin = skin
        imageStore = store
        activeViewID = scene.viewID
        activeLimits = scene.resizeLimits
        activeScene = scene
        scriptRuntime = runtime
        lastScriptSnapshot = host.snapshot
        sceneOverrides = overrides
        lastLoadDiagnostic = nil
        // A `.wmz` window is genuinely shaped — Corona is transparent across the 250 px its
        // playlist slides into and the 124 px its equaliser drops into — and macOS derives a
        // borderless window's shadow from whatever content it last cached. On a shape that changes
        // with every drawer and every repaint that gets stale, and a stale shadow over a
        // transparent region reads as a dark box the size of the window. There is no drop shadow
        // in Windows Media Player to lose.
        window?.hasShadow = false
        window?.invalidateShadow()
        Self.traceInput("present-view \(scene.viewID) canvas=\(scene.canvasSize) commands=\(scene.commands.count)")
        importer.defaults.set(scene.viewID, forKey: WMPSkinImporter.selectedViewIDKey)
        setViewTimer(milliseconds: Self.authoredTimerInterval(in: skin, viewID: scene.viewID))

        let view = mainView ?? WMPMainView(frame: .zero)
        mainView = view
        view.onAction = { [weak self] action, value in
            guard let self else { return }
            self.host.perform(action, value: value)
            self.refreshHostState()
        }
        view.onScriptEvent = { [weak self] name, targetID, targetStableID in
            self?.dispatchScriptEvent(name: name, targetID: targetID, targetStableID: targetStableID,
                                      onlyWhenAuthored: Self.hoverEvents.contains(name))
        }
        view.onElementTextChanged = { [weak self] stableID, targetID, text in
            guard let self, let scriptRuntime = self.scriptRuntime else { return }
            Task {
                await scriptRuntime.setWidgetText(stableID: stableID, text: text)
                self.dispatchScriptEvent(name: "keyup", targetID: targetID, targetStableID: stableID)
            }
        }
        view.onElementValueChanged = { [weak self] stableID, targetID, value in
            guard let self, let scriptRuntime = self.scriptRuntime else { return }
            Task {
                await scriptRuntime.setWidgetValue(stableID: stableID, value: value)
                self.dispatchScriptEvent(name: "change", targetID: targetID, targetStableID: stableID)
            }
        }
        view.onSpectrumDemandChanged = { [weak self] active in
            self?.host.setSpectrumConsumerActive(active)
        }
        view.onInteractionChanged = { [weak self] state, changed in
            self?.interactionState = state
            self?.renderInteraction(state: state, changed: changed)
        }
        unskinnedView = nil
        window?.contentView = view
        if let restored = pendingRestoredFrame {
            var frame = restored
            frame.size = NSSize(width: scene.canvasSize.width, height: scene.canvasSize.height)
            frame.origin.y = restored.maxY - frame.height
            isApplyingSceneSize = true
            window?.setFrame(frame, display: true)
            isApplyingSceneSize = false
            window?.invalidateShadow()
            pendingRestoredFrame = nil
            pendingRestoredViewID = nil
        } else {
            setWindowSize(NSSize(width: scene.canvasSize.width, height: scene.canvasSize.height))
        }
        view.present(image, scene: scene)
        view.refreshHostState(host.snapshot)
        startAnimation(for: scene)
    }

    private func presentUnskinned(message: String?) {
        loadedSkin = nil
        imageStore = nil
        activeViewID = nil
        openedViewStack.removeAll()
        activeLimits = nil
        activeScene = nil
        sceneOverrides = .empty
        if let scriptRuntime { Task { await scriptRuntime.teardown() } }
        scriptRuntime = nil
        lastScriptSnapshot = nil
        stopAllTimers()
        lastLoadDiagnostic = message
        mainView?.prepareForUITeardown()
        mainView = nil

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
        setWindowSize(Self.unskinnedSize)
    }

    private func setWindowSize(_ size: NSSize) {
        guard let window else { return }
        let old = window.frame
        var frame = old
        frame.size = size
        frame.origin.y = old.maxY - size.height
        isApplyingSceneSize = true
        window.setFrame(frame, display: true)
        isApplyingSceneSize = false
        // A borderless, non-opaque window keeps the shadow it had at its previous frame. Corona
        // resizes the view when a drawer opens, so without this the old outline is left behind
        // beside the window as a ghost of the shape it used to be.
        window.invalidateShadow()
    }

    private func renderCurrentSize() {
        guard !isApplyingSceneSize, let skin = loadedSkin, let store = imageStore,
              let viewID = activeViewID, let window else { return }
        loadTask?.cancel()
        let requested = WMPSize(width: window.contentLayoutRect.width, height: window.contentLayoutRect.height)
        let overrides = sceneOverrides
        let scriptRuntime = scriptRuntime
        loadTask = Task { [weak self] in
            do {
                var resolvedOverrides = overrides
                var scriptOutput: WMPScriptOutput?
                if let scriptRuntime, let self {
                    let output = await scriptRuntime.transact(skin: skin, viewID: viewID,
                        size: requested, snapshot: self.host.snapshot, event: nil,
                        geometry: self.activeScene?.scriptGeometry ?? [:])
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
                                                before: self.activeScene, after: scene) {
                    let output = await scriptRuntime.transact(skin: skin, viewID: viewID,
                        size: scene.canvasSize, snapshot: self.host.snapshot, event: event,
                        geometry: scene.scriptGeometry)
                    resolvedOverrides = output.overrides
                    scriptOutput = output
                    scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                        .build(viewID: viewID, requestedSize: requested, overrides: resolvedOverrides)
                }
                let result = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: self?.renderBackingScale ?? 1,
                    clock: self?.animationClock(for: scene.viewID) ?? 0)
                try Task.checkCancellation()
                self?.sceneOverrides = resolvedOverrides
                self?.activeScene = scene
                self?.startAnimation(for: scene)
                if let scriptOutput { self?.mainView?.updateListItems(scriptOutput.listItems) }
                self?.mainView?.present(result.image, scene: scene)
                self?.mainView?.refreshHostState(self?.host.snapshot ?? WMPHostSnapshot())
                if let scriptOutput {
                    let switchedView = self?.applyHostCommands(scriptOutput.hostCommands) ?? false
                    if !switchedView { self?.scheduleTimers(scriptOutput.timerRequests) }
                    self?.recordScriptDiagnostics(scriptOutput.diagnostics)
                }
            } catch is CancellationError {} catch {
                self?.lastLoadDiagnostic = error.localizedDescription
            }
        }
    }

    func prepareForUITeardown() {
        loadTask?.cancel()
        loadTask = nil
        scriptTask?.cancel()
        scriptTask = nil
        stopAllTimers()
        if let scriptRuntime { Task { await scriptRuntime.teardown() } }
        scriptRuntime = nil
        lastScriptSnapshot = nil
        mainView?.prepareForUITeardown()
        mainView = nil
        unskinnedView?.onImport = nil
        unskinnedView?.onMinimize = nil
        unskinnedView?.onClose = nil
        unskinnedView?.host = nil
        unskinnedView = nil
        loadedSkin = nil
        imageStore = nil
        activeScene = nil
        sceneOverrides = .empty
        host.stopContinuousCommands()
    }

    func switchView(to requestedID: String) {
        guard let skin = loadedSkin, let store = imageStore,
              let registration = skin.views.first(where: {
                  $0.id.caseInsensitiveCompare(requestedID) == .orderedSame
              }), registration.id.caseInsensitiveCompare(activeViewID ?? "") != .orderedSame,
              let scriptRuntime else { return }
        loadTask?.cancel(); scriptTask?.cancel(); stopAllTimers()
        mainView?.cancelInputCapture(); host.stopContinuousCommands()
        let oldTopLeft = window.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) }
        let savedSize = WMPViewFrameStore(defaults: importer.defaults).size(
            skin: importer.selectedSkinName ?? "", view: registration.id)
        loadTask = Task { [weak self] in
            guard let self else { return }
            await scriptRuntime.prepareForViewSwitch()
            do {
                let base = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: registration.id, requestedSize: savedSize)
                // **A view arrived at by a switch loads exactly as one arrived at by launch.**
                // Initial load raises `load` here, honours the host commands the handler posts and
                // schedules the timers it asks for; this path did none of the three, and a
                // `.wmz` compact mode is built out of all three. Corona's `viewTiny` is authored
                // `timerInterval="0"` and animates itself into the mini player entirely from
                // `OnTinyLoad` — which registers a timer event and writes `view.timerInterval`,
                // a `setViewTimerInterval` host command. With the load event dropped, the handler
                // never ran; with the host commands dropped, the interval never arrived. So the
                // view switched and then sat at frame zero, which for Corona is drawn from the
                // same artwork at the same size as `vPlayer`: **the compact view was visually
                // indistinguishable from the player**, and the only symptom was that the playlist
                // and equaliser buttons — markup `viewTiny` does not have — stopped answering.
                // `RestorePlayer()` is driven by the same timer, so there was also no way back.
                let loadEvent = WMPJScriptEvent(name: "load", targetID: registration.id,
                    handlers: Self.handlers(in: skin, event: "load", targetID: nil,
                                            viewID: registration.id))
                let output = await scriptRuntime.transact(skin: skin, viewID: registration.id,
                    size: base.canvasSize, snapshot: host.snapshot, event: loadEvent,
                    geometry: base.scriptGeometry)
                // A windowless view — `controlView`, `pharaoh`'s `vGhost` — runs its script and
                // hands off; it must never become the presented window. Whatever it asks for next
                // is honoured, and if it asks for nothing the current view simply stays.
                //
                // A view can also declare itself windowless *in* that `onLoad` by writing zero, so
                // the same `collapsed` test initial load applies belongs here now that the handler
                // runs: `Halo 2`'s `previewView` blanks itself and redirects, and presenting it
                // would leave an empty window the size of its thumbnail.
                let collapsed = ["width", "height"].contains { property in
                    output.overrides.geometry[.init(stableID: registration.node.stableID,
                                                    property: property)] == 0
                }
                guard base.canvasSize.width > 0, base.canvasSize.height > 0, !collapsed else {
                    recordScriptDiagnostics(output.diagnostics)
                    _ = applyHostCommands(output.hostCommands)
                    return
                }
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: registration.id, requestedSize: base.canvasSize,
                           overrides: output.overrides)
                let rendered = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: renderBackingScale)
                try Task.checkCancellation()
                apply(skin: skin, store: store, scene: scene, image: rendered.image,
                      runtime: scriptRuntime, overrides: output.overrides)
                if let oldTopLeft, let window {
                    window.setFrameOrigin(NSPoint(x: oldTopLeft.x, y: oldTopLeft.y - window.frame.height))
                }
                // `apply` has just set the view timer from the markup, which is the default the
                // script's `setViewTimerInterval` overrides — so the commands run after it, in
                // that order. A command that switches again owns the timers of the view it moved
                // to, exactly as on initial load, and there is no `viewchange` to raise for a view
                // this controller is no longer on.
                let switchedAgain = applyHostCommands(output.hostCommands)
                recordScriptDiagnostics(output.diagnostics)
                guard !switchedAgain else { return }
                scheduleTimers(output.timerRequests)
                // Gated on an authored handler, like hover, and for the timers rather than the
                // cost: a transaction's `timerRequests` are what *that* transaction registered, so
                // an unconditional binding-only `viewchange` immediately posted an empty set and
                // cancelled every script timer the `load` above had just scheduled. The bindings
                // themselves have nothing left to settle — the load transaction built the scene
                // that is on screen.
                dispatchScriptEvent(name: "viewchange", targetID: registration.id,
                                    onlyWhenAuthored: true)
            } catch is CancellationError {} catch { lastLoadDiagnostic = error.localizedDescription }
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let limits = activeLimits else { return Self.unskinnedSize }
        let clamped = limits.clamp(WMPSize(width: frameSize.width, height: frameSize.height))
        return NSSize(width: clamped.width, height: clamped.height)
    }

    func windowDidResize(_ notification: Notification) {
        if let window, let viewID = activeViewID {
            WMPViewFrameStore(defaults: importer.defaults).setSize(
                WMPSize(width: window.frame.width, height: window.frame.height),
                skin: importer.selectedSkinName ?? "", view: viewID)
        }
        renderCurrentSize()
    }
    func windowDidChangeBackingProperties(_ notification: Notification) {
        renderCurrentSize()
    }
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        let origin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: origin)
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

    func updateTrackInfo(_ track: Track?) { refreshHostState() }
    func updateVideoTrackInfo(title: String, artworkTrack: Track?) {}
    func clearVideoTrackInfo() {}
    func updateTime(current: TimeInterval, duration: TimeInterval) { refreshHostState() }
    func updatePlaybackState() { refreshHostState() }
    func updateSpectrum(_ levels: [Float]) { mainView?.updateSpectrum(levels) }
    func skinDidChange() {}
    func windowVisibilityDidChange() {}
    func setNeedsDisplay() { window?.contentView?.needsDisplay = true }

    private func refreshHostState() {
        mainView?.refreshHostState(host.snapshot)
        unskinnedView?.refresh(host.snapshot)
        guard loadedSkin != nil, scriptRuntime != nil else { return }
        let snapshot = host.snapshot
        let previous = lastScriptSnapshot
        lastScriptSnapshot = snapshot
        var events: [String] = []
        if previous?.state != snapshot.state { events += ["openstatechange", "playstatechange"] }
        if previous?.currentTime != snapshot.currentTime || previous?.duration != snapshot.duration
            || previous?.metadata != snapshot.metadata { events.append("status_onchange") }
        if previous?.shuffle != snapshot.shuffle || previous?.repeatMode != snapshot.repeatMode {
            events.append("modechange")
        }
        if previous?.bufferingProgress != snapshot.bufferingProgress { events.append("buffering_onchange") }
        if previous?.receptionQuality != snapshot.receptionQuality { events.append("reception_onchange") }
        guard !events.isEmpty else { return }
        scriptTask?.cancel()
        scriptTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled else { return }
            self?.dispatchHostEvents(events)
        }
    }

    private func renderInteraction(state: WMPInteractionState, changed: Set<Int>) {
        guard let skin = loadedSkin, let store = imageStore, let viewID = activeViewID,
              let activeScene else { return }
        loadTask?.cancel()
        interactionState = state
        let overrides = sceneOverrides
        loadTask = Task { [weak self] in
            do {
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: viewID, requestedSize: activeScene.canvasSize,
                           interactionState: state, dirtyNodeIDs: changed,
                           overrides: overrides)
                let result = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: self?.renderBackingScale ?? 1,
                    clock: self?.animationClock(for: scene.viewID) ?? 0)
                try Task.checkCancellation()
                self?.activeScene = scene
                self?.startAnimation(for: scene)
                self?.mainView?.present(result.image, scene: scene, dirtyBounds: scene.dirtyBounds)
            } catch is CancellationError {} catch { self?.lastLoadDiagnostic = error.localizedDescription }
        }
    }

    /// `targetStableID` is the node the input actually landed on. It is what scopes the dispatch,
    /// because an authored `id` is optional in a `.wmz` and `targetID == nil` means "every handler
    /// in the view" — correct for `load` or `timer`, catastrophic for a click. Corona leaves its
    /// compact-mode button unnamed, so clicking it ran all 16 of the view's `onClick` handlers at
    /// once: the file dialog, both drawers, and `ToggleSuperCompact()`, which switched the skin to
    /// a compact view that renders indistinguishably from the player and persisted it.
    private func dispatchScriptEvent(name: String, targetID: String?, targetStableID: Int? = nil,
                                     onlyWhenAuthored: Bool = false) {
        guard let skin = loadedSkin else { return }
        let handlers = Self.handlers(in: skin, event: name, targetID: targetID,
                                     targetStableID: targetStableID, viewID: activeViewID)
        // **A hover edge is only worth a transaction when the skin asked for one.** Every other
        // dispatch site here is a discrete act — a click, a keystroke, a view change — and runs the
        // transaction even with no authored handler, because the bindings have to settle. Hover is
        // not: the pointer crosses a whole row of buttons on the way to the one it wants, and a
        // transaction rebuilds and re-renders the entire scene (and cancels whatever click was
        // still in flight). So `onmouseover`/`onmouseout` dispatch only where the markup carries a
        // handler for them; the hover *artwork* never went through here and is unaffected.
        Self.traceInput("dispatch \(name) target=\(targetID ?? "-")#\(targetStableID.map(String.init) ?? "-") "
            + "handlers=\(handlers.count) gated=\(onlyWhenAuthored)")
        if onlyWhenAuthored, handlers.isEmpty { return }
        dispatchScriptTransaction(WMPJScriptEvent(name: name, targetID: targetID,
                                                  handlers: handlers))
    }

    private func dispatchHostEvents(_ names: [String]) {
        guard let skin = loadedSkin else { return }
        let handlers = names.flatMap {
            Self.handlers(in: skin, event: $0, targetID: nil, viewID: activeViewID)
        }
        dispatchScriptTransaction(WMPJScriptEvent(name: names.joined(separator: ","),
                                                   targetID: nil, handlers: handlers))
    }

    private func dispatchScriptTransaction(_ event: WMPJScriptEvent) {
        guard let skin = loadedSkin, let store = imageStore, let viewID = activeViewID,
              let activeScene, let scriptRuntime else { return }
        // A binding-only transaction is still required when no authored handler exists.
        scriptTask?.cancel()
        scriptTask = Task { [weak self] in
            guard let self else { return }
            let output = await scriptRuntime.transact(skin: skin, viewID: viewID,
                size: activeScene.canvasSize, snapshot: host.snapshot, event: event,
                geometry: activeScene.scriptGeometry)
            guard !Task.isCancelled else { return }
            do {
                // No `dirtyNodeIDs`: a script transaction repaints in full.
                //
                // The dirty region a script produces cannot be derived from what it *wrote*. A
                // handler writes `svEqualizer.top` and the whole pane and every control inside it
                // moves, none of which the script mentioned — and a subview carries no hit metadata,
                // so the narrowed bounds came out as the one button that was clicked. Partial
                // repaints belong to hover and slider drags, where only artwork state changes.
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: viewID, requestedSize: activeScene.canvasSize,
                           interactionState: interactionState, overrides: output.overrides)
                let result = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: renderBackingScale,
                    clock: animationClock(for: scene.viewID))
                guard !Task.isCancelled else { return }
                sceneOverrides = output.overrides
                self.activeScene = scene
                self.startAnimation(for: scene)
                self.mainView?.updateListItems(output.listItems)
                mainView?.present(result.image, scene: scene)
                Self.traceInput("present \(event.name) geometry=\(output.overrides.geometry.count) "
                    + "properties=\(output.overrides.properties.count) commands=\(scene.commands.count) "
                    + "diagnostics=\(output.diagnostics.count)")
                let switchedView = applyHostCommands(output.hostCommands)
                if !switchedView { scheduleTimers(output.timerRequests) }
                recordScriptDiagnostics(output.diagnostics)
            } catch { recordScriptDiagnostics([.init(code: "scene-transaction", message: error.localizedDescription)]) }
        }
    }

    /// Authored handlers for one event, **inside one view**.
    ///
    /// The view scope is not tidiness. A `.wmz` declares every view in one file, so an unscoped
    /// scan ran the *other* view's `onLoad` as well: Corona's tiny view then executed the player
    /// view's setup against elements that do not exist there, and the census read the resulting
    /// `ReferenceError` as a defect in the runtime rather than in the caller.
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
        // site cannot raise one name and miss the other. **What this does not do** is raise
        // `value_onchange` when a bound host property moves the control on its own — that half has
        // no observation path yet and is recorded as still-open work in `WMP_TASKS.md` (W51).
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

    @discardableResult
    private func applyHostCommands(_ commands: [WMPJScriptHostCommand]) -> Bool {
        var switchedView = false
        for command in commands.prefix(WMPJScriptProtocol.maximumHostCommands) {
            Self.traceInput("command \(command.action) value=\(command.value?.string ?? "-")")
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
            case "setViewTimerInterval": setViewTimer(milliseconds: Int(number ?? 0))
            case "openFileDialog": presentOpenMediaPanel()
            case "closeView":
                // A view this skin opened over another one closes back to it; only the outermost
                // view closing means "close the player".
                if let previous = openedViewStack.popLast() {
                    switchedView = true; switchView(to: previous)
                } else {
                    window?.orderOut(nil)
                }
            case "minimizeWindow": window?.miniaturize(nil)
            case let action where action.hasPrefix("playPlaylistItem:"):
                if let index = Int(action.dropFirst("playPlaylistItem:".count)) {
                    host.perform(.playPlaylistItem(index), value: nil)
                }
            case "openView":
                if let id = command.value?.string,
                   loadedSkin?.views.contains(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) == true,
                   id.caseInsensitiveCompare(activeViewID ?? "") != .orderedSame {
                    if let covered = activeViewID,
                       !openedViewStack.contains(where: { $0.caseInsensitiveCompare(covered) == .orderedSame }) {
                        openedViewStack.append(covered)
                        if openedViewStack.count > 8 { openedViewStack.removeFirst() }
                    }
                    switchedView = true; switchView(to: id)
                }
            case "setCurrentView":
                if let id = command.value?.string,
                   loadedSkin?.views.contains(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) == true,
                   id.caseInsensitiveCompare(activeViewID ?? "") != .orderedSame {
                    switchedView = true; switchView(to: id)
                }
            default: continue
            }
        }
        return switchedView
    }

    private func scheduleTimers(_ requests: [WMPJScriptTimerRequest]) {
        cancelScriptTimers()
        for request in requests.prefix(WMPPhase0Limits.activeTimers) {
            let period = max(WMPPhase0Limits.minimumTimerPeriodMilliseconds, request.periodMilliseconds)
            scriptTimerTasks[request.token] = Task { [weak self] in
                repeat {
                    try? await Task.sleep(nanoseconds: UInt64(period) * 1_000_000)
                    guard !Task.isCancelled else { return }
                    self?.dispatchTimer(request)
                } while request.repeats && !Task.isCancelled
            }
        }
    }

    private func dispatchTimer(_ request: WMPJScriptTimerRequest) {
        guard let skin = loadedSkin, let store = imageStore, let viewID = activeViewID,
              let activeScene, let scriptRuntime else { return }
        scriptTask?.cancel()
        scriptTask = Task { [weak self] in
            guard let self else { return }
            let event = WMPJScriptEvent(name: "timer", targetID: nil, handlers: [request.source])
            let output = await scriptRuntime.transact(skin: skin, viewID: viewID,
                size: activeScene.canvasSize, snapshot: host.snapshot, event: event,
                geometry: activeScene.scriptGeometry)
            guard !Task.isCancelled else { return }
            do {
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: viewID, requestedSize: activeScene.canvasSize, overrides: output.overrides)
                let rendered = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: renderBackingScale,
                    clock: self.animationClock(for: scene.viewID))
                self.sceneOverrides = output.overrides; self.activeScene = scene
                self.startAnimation(for: scene)
                self.mainView?.updateListItems(output.listItems)
                self.mainView?.present(rendered.image, scene: scene)
                self.applyHostCommands(output.hostCommands); self.recordScriptDiagnostics(output.diagnostics)
            } catch { self.recordScriptDiagnostics([.init(code: "timer-transaction", message: error.localizedDescription)]) }
        }
    }

    /// The **script's** timers — what a handler asked for with `setTimeout`/`setInterval` — and
    /// nothing else.
    ///
    /// It used to stop the view's own `timerInterval` and the animation loop as well, and
    /// `scheduleTimers` calls it on every transaction to replace the previous set. So a load
    /// transaction that requested no script timers — the common case — cancelled the view timer
    /// `apply` had just started, one line earlier. **No `.wmz` view timer in the corpus had ever
    /// fired**: `Halo 2`'s `introStart()` never opened its shutter (reported 2026-09-08), and every
    /// other authored `onTimer` — clocks, seek readouts, `checkRemoteViewStatus`, ALXMorph's
    /// animations — was dead the same way. Teardown wants all three stopped and says so with
    /// `stopAllTimers()`.
    private func cancelScriptTimers() {
        scriptTimerTasks.values.forEach { $0.cancel() }
        scriptTimerTasks.removeAll()
    }

    /// Everything in this controller with a clock. Teardown and a view switch are synchronous and
    /// idempotent, and the animation loop retains the scene it draws — a repaint arriving after
    /// teardown would present into a view being discarded.
    private func stopAllTimers() {
        cancelScriptTimers()
        setViewTimer(milliseconds: 0)
        animationTask?.cancel()
        animationTask = nil
        animationEpochViewID = nil
    }

    /// Seconds of animation elapsed for `viewID`, or zero when the clock belongs to another view.
    ///
    /// **Every render of a view that is already animating has to pass this.** Preserving the epoch
    /// alone does not stop the flicker: a rebuilt scene is rendered at `clock: 0` by default, so a
    /// transaction still paints frame zero and the animation loop only catches up a frame later.
    /// At a 100ms `timerInterval` that is ten frame-zero repaints a second on top of a running GIF.
    private func animationClock(for viewID: String?) -> TimeInterval {
        guard let viewID, animationEpochViewID == viewID else { return 0 }
        return Date().timeIntervalSince(animationEpoch)
    }

    /// The `VIEW`'s own `timerInterval`, in milliseconds: zero stops it, anything else restarts it
    /// at that period and dispatches the view's authored `onTimer` handlers.
    ///
    /// This is how a skin animates. Corona's compact view registers a timed event and then writes
    /// `view.timerInterval`, and its player view declares `timerInterval="4000"` in markup to drive
    /// its own transport readouts — so without this a `.wmz` sits frozen in whatever state it was
    /// authored in, with no diagnostic anywhere to say why.
    /// `theme.openDialog('FILE_OPEN', …)`, which is how a `.wmz` skin's own Open button starts
    /// playback. Without it WMP mode has no route to a track at all: the auxiliary NullPlayer
    /// windows stay hidden in this mode until they have WMP-owned chrome.
    private func presentOpenMediaPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Open media"
        panel.allowedContentTypes = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "alac", "cue"]
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
    private func startAnimation(for scene: WMPScene) {
        animationTask?.cancel()
        animationTask = nil
        guard let store = imageStore,
              let cadence = WMPRenderer(imageStore: store).animationCadence(for: scene) else { return }
        if animationEpochViewID != scene.viewID {
            animationEpoch = Date()
            animationEpochViewID = scene.viewID
        }
        Self.traceInput("animation \(scene.viewID ?? "-") delay=\(cadence.shortestDelay)s "
            + "endsAt=\(cadence.endsAt.map { "\($0)s" } ?? "endless") "
            + "clock=\(Date().timeIntervalSince(animationEpoch))s")
        // A one-shot that has already played out needs no loop: the caller rendered this scene at
        // the same clock, so its final frame is already on screen. Without this every rebuild after
        // the animation ended would still start a task to draw that one still frame again.
        if let endsAt = cadence.endsAt, Date().timeIntervalSince(animationEpoch) >= endsAt { return }
        let period = max(WMPPhase0Limits.minimumTimerPeriodMilliseconds,
                         Int(cadence.shortestDelay * 1_000))
        let dirty = cadence.bounds
        let epoch = animationEpoch
        animationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(period) * 1_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.renderAnimationFrame(scene: scene, store: store, dirty: dirty)
                // A scene of one-shot GIFs stops moving; keeping the loop alive would re-render
                // the same still frame at the GIF's rate for as long as the view is open.
                if let endsAt = cadence.endsAt, Date().timeIntervalSince(epoch) >= endsAt { return }
            }
        }
    }

    private func renderAnimationFrame(scene: WMPScene, store: WMPImageStore, dirty: WMPRect) async {
        // Only while this is still the scene on screen: a view switch or a script transaction
        // replaces it, and repainting the old one would undo what just landed.
        guard activeScene == scene, let view = mainView else { return }
        let clock = Date().timeIntervalSince(animationEpoch)
        guard let rendered = try? await WMPRenderer(imageStore: store)
            .render(scene: scene, backingScale: renderBackingScale, clock: clock) else { return }
        guard activeScene == scene else { return }
        view.present(rendered.image, scene: scene, dirtyBounds: dirty)
    }

    private func setViewTimer(milliseconds: Int) {
        Self.traceInput("view-timer \(milliseconds)ms")
        viewTimerTask?.cancel()
        viewTimerTask = nil
        guard milliseconds > 0 else { return }

        let period = max(WMPPhase0Limits.minimumTimerPeriodMilliseconds, milliseconds)
        viewTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(period) * 1_000_000)
                guard !Task.isCancelled else { return }
                self?.dispatchScriptEvent(name: "timer", targetID: nil)
            }
        }
    }

    private func recordScriptDiagnostics(_ diagnostics: [WMPJScriptDiagnostic]) {
        guard !diagnostics.isEmpty else { return }
        // A live script error is the one thing the input trace could not see. The headless probes
        // print `SCRIPT-DIAG`; without the same line here, a handler that throws in the running app
        // is indistinguishable from one that ran and did nothing.
        for diagnostic in diagnostics { Self.traceInput("script-diag [\(diagnostic.code)] \(diagnostic.message)") }
        lastLoadDiagnostic = diagnostics.map { "[\($0.code)] \($0.message)" }.joined(separator: "\n")
    }

    private var renderBackingScale: CGFloat {
        max(1, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
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
