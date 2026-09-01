import AppKit

final class WMPMainWindowController: NSWindowController, MainWindowProviding, NSWindowDelegate {
    static let unskinnedSize = NSSize(width: 440, height: 170)

    private let importer: WMPSkinImporter
    private let host: any WMPHost
    private var loadTask: Task<Void, Never>?
    private var phase5Task: Task<Void, Never>?
    private var scriptTimerTasks: [Int: Task<Void, Never>] = [:]
    private var loadedSkin: WMPLoadedSkin?
    private var imageStore: WMPImageStore?
    private var activeViewID: String?
    private var activeLimits: WMPResizeLimits?
    private var activeScene: WMPScene?
    private var sceneOverrides = WMPSceneOverrides.empty
    private var phase5Session: WMPPhase5Session?
    private var phase5Runtime: WMPJScriptRuntime?
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
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.unskinnedSize),
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
                let preferred = importer.selectedViewID
                let registration = preferred.flatMap { wanted in
                    skin.views.first { $0.id.caseInsensitiveCompare(wanted) == .orderedSame }
                } ?? skin.views.first { $0.id.caseInsensitiveCompare("vPlayer") == .orderedSame }
                    ?? skin.views.first
                guard let registration else {
                    throw WMPFailure(WMPDiagnostic(.invalidGeometry, "The skin contains no renderable WMP view."))
                }
                let store = WMPImageStore(provider: skin.archive)
                let restoredViewMatches = pendingRestoredViewID?.caseInsensitiveCompare(registration.id) == .orderedSame
                let requested = restoredViewMatches ? pendingRestoredFrame.map {
                    WMPSize(width: $0.width, height: $0.height)
                } : nil
                if pendingRestoredFrame != nil, !restoredViewMatches {
                    pendingRestoredFrame = nil
                    pendingRestoredViewID = nil
                }
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: registration.id, requestedSize: requested)
                let skinData = try await Task.detached { try Data(contentsOf: skin.archive.sourceURL) }.value
                let runtime = WMPJScriptRuntime(helperURL: WMPJScriptRuntime.bundledHelperURL())
                let phase5 = WMPPhase5Session(runtime: runtime,
                    preferences: WMPPreferenceStore(skinData: skinData, defaults: importer.defaults))
                let loadEvent = WMPJScriptEvent(name: "load", targetID: registration.id,
                    handlers: Self.handlers(in: skin, event: "load", targetID: nil))
                let output = await phase5.transact(skin: skin, viewID: registration.id,
                    size: scene.canvasSize, snapshot: host.snapshot, event: loadEvent)
                let resolved = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: registration.id, requestedSize: scene.canvasSize,
                           overrides: output.overrides)
                let rendered = try await WMPRenderer(imageStore: store).render(
                    scene: resolved, backingScale: renderBackingScale)
                try Task.checkCancellation()
                apply(skin: skin, store: store, scene: resolved, image: rendered.image,
                      phase5: phase5, runtime: runtime, overrides: output.overrides)
                let switchedView = applyHostCommands(output.hostCommands)
                if !switchedView { scheduleTimers(output.timerRequests) }
                recordScriptDiagnostics(output.diagnostics)
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
        guard let phase5Session else { return }
        Task { await phase5Session.resetPreferences() }
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
                       phase5: WMPPhase5Session, runtime: WMPJScriptRuntime,
                       overrides: WMPSceneOverrides) {
        loadedSkin = skin
        imageStore = store
        activeViewID = scene.viewID
        activeLimits = scene.resizeLimits
        activeScene = scene
        phase5Session = phase5
        phase5Runtime = runtime
        lastScriptSnapshot = host.snapshot
        sceneOverrides = overrides
        lastLoadDiagnostic = nil
        importer.defaults.set(scene.viewID, forKey: WMPSkinImporter.selectedViewIDKey)

        let view = mainView ?? WMPMainView(frame: .zero)
        mainView = view
        view.onAction = { [weak self] action, value in
            guard let self else { return }
            self.host.perform(action, value: value)
            self.refreshHostState()
        }
        view.onScriptEvent = { [weak self] name, targetID in
            self?.dispatchScriptEvent(name: name, targetID: targetID)
        }
        view.onElementValueChanged = { [weak self] stableID, targetID, value in
            guard let self, let phase5Session = self.phase5Session else { return }
            Task {
                await phase5Session.setWidgetValue(stableID: stableID, value: value)
                self.dispatchScriptEvent(name: "change", targetID: targetID)
            }
        }
        view.onSpectrumDemandChanged = { [weak self] active in
            self?.host.setSpectrumConsumerActive(active)
        }
        view.onInteractionChanged = { [weak self] state, changed in
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
            pendingRestoredFrame = nil
            pendingRestoredViewID = nil
        } else {
            setWindowSize(NSSize(width: scene.canvasSize.width, height: scene.canvasSize.height))
        }
        view.present(image, scene: scene)
        view.refreshHostState(host.snapshot)
    }

    private func presentUnskinned(message: String?) {
        loadedSkin = nil
        imageStore = nil
        activeViewID = nil
        activeLimits = nil
        activeScene = nil
        sceneOverrides = .empty
        if let phase5Session { Task { await phase5Session.teardown() } }
        phase5Runtime?.cancelAll()
        phase5Runtime = nil
        phase5Session = nil
        lastScriptSnapshot = nil
        cancelScriptTimers()
        lastLoadDiagnostic = message
        mainView?.prepareForUITeardown()
        mainView = nil

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
    }

    private func renderCurrentSize() {
        guard !isApplyingSceneSize, let skin = loadedSkin, let store = imageStore,
              let viewID = activeViewID, let window else { return }
        loadTask?.cancel()
        let requested = WMPSize(width: window.contentLayoutRect.width, height: window.contentLayoutRect.height)
        let overrides = sceneOverrides
        let phase5Session = phase5Session
        loadTask = Task { [weak self] in
            do {
                var resolvedOverrides = overrides
                var scriptOutput: WMPPhase5Output?
                if let phase5Session, let self {
                    let output = await phase5Session.transact(skin: skin, viewID: viewID,
                        size: requested, snapshot: self.host.snapshot, event: nil)
                    resolvedOverrides = output.overrides
                    scriptOutput = output
                }
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: viewID, requestedSize: requested, overrides: resolvedOverrides)
                let result = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: self?.renderBackingScale ?? 1)
                try Task.checkCancellation()
                self?.sceneOverrides = resolvedOverrides
                self?.activeScene = scene
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
        phase5Task?.cancel()
        phase5Task = nil
        cancelScriptTimers()
        phase5Runtime?.cancelAll()
        phase5Runtime = nil
        if let phase5Session { Task { await phase5Session.teardown() } }
        phase5Session = nil
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
              let phase5Session, let phase5Runtime else { return }
        loadTask?.cancel(); phase5Task?.cancel(); cancelScriptTimers()
        mainView?.cancelInputCapture(); host.stopContinuousCommands()
        let oldTopLeft = window.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) }
        let savedSize = WMPViewFrameStore(defaults: importer.defaults).size(
            skin: importer.selectedSkinName ?? "", view: registration.id)
        loadTask = Task { [weak self] in
            guard let self else { return }
            await phase5Session.prepareForViewSwitch()
            do {
                let base = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: registration.id, requestedSize: savedSize)
                let output = await phase5Session.transact(skin: skin, viewID: registration.id,
                    size: base.canvasSize, snapshot: host.snapshot, event: nil)
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: registration.id, requestedSize: base.canvasSize,
                           overrides: output.overrides)
                let rendered = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: renderBackingScale)
                try Task.checkCancellation()
                apply(skin: skin, store: store, scene: scene, image: rendered.image,
                      phase5: phase5Session, runtime: phase5Runtime, overrides: output.overrides)
                if let oldTopLeft, let window {
                    window.setFrameOrigin(NSPoint(x: oldTopLeft.x, y: oldTopLeft.y - window.frame.height))
                }
                dispatchScriptEvent(name: "viewchange", targetID: registration.id)
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
        guard loadedSkin != nil, phase5Session != nil else { return }
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
        phase5Task?.cancel()
        phase5Task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled else { return }
            self?.dispatchHostEvents(events)
        }
    }

    private func renderInteraction(state: WMPInteractionState, changed: Set<Int>) {
        guard let skin = loadedSkin, let store = imageStore, let viewID = activeViewID,
              let activeScene else { return }
        loadTask?.cancel()
        let overrides = sceneOverrides
        loadTask = Task { [weak self] in
            do {
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: viewID, requestedSize: activeScene.canvasSize,
                           interactionState: state, dirtyNodeIDs: changed,
                           overrides: overrides)
                let result = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: self?.renderBackingScale ?? 1)
                try Task.checkCancellation()
                self?.activeScene = scene
                self?.mainView?.present(result.image, scene: scene, dirtyBounds: scene.dirtyBounds)
            } catch is CancellationError {} catch { self?.lastLoadDiagnostic = error.localizedDescription }
        }
    }

    private func dispatchScriptEvent(name: String, targetID: String?) {
        guard let skin = loadedSkin else { return }
        dispatchScriptTransaction(WMPJScriptEvent(name: name, targetID: targetID,
            handlers: Self.handlers(in: skin, event: name, targetID: targetID)))
    }

    private func dispatchHostEvents(_ names: [String]) {
        guard let skin = loadedSkin else { return }
        let handlers = names.flatMap { Self.handlers(in: skin, event: $0, targetID: nil) }
        dispatchScriptTransaction(WMPJScriptEvent(name: names.joined(separator: ","),
                                                   targetID: nil, handlers: handlers))
    }

    private func dispatchScriptTransaction(_ event: WMPJScriptEvent) {
        guard let skin = loadedSkin, let store = imageStore, let viewID = activeViewID,
              let activeScene, let phase5Session else { return }
        // A binding-only transaction is still required when no authored handler exists.
        phase5Task?.cancel()
        phase5Task = Task { [weak self] in
            guard let self else { return }
            let output = await phase5Session.transact(skin: skin, viewID: viewID,
                size: activeScene.canvasSize, snapshot: host.snapshot, event: event)
            guard !Task.isCancelled else { return }
            do {
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: viewID, requestedSize: activeScene.canvasSize,
                           dirtyNodeIDs: output.repaintNodeIDs.isEmpty ? nil : output.repaintNodeIDs,
                           overrides: output.overrides)
                let result = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: renderBackingScale)
                guard !Task.isCancelled else { return }
                sceneOverrides = output.overrides
                self.activeScene = scene
                mainView?.present(result.image, scene: scene, dirtyBounds: scene.dirtyBounds)
                let switchedView = applyHostCommands(output.hostCommands)
                if !switchedView { scheduleTimers(output.timerRequests) }
                recordScriptDiagnostics(output.diagnostics)
            } catch { recordScriptDiagnostics([.init(code: "scene-transaction", message: error.localizedDescription)]) }
        }
    }

    static func handlers(in skin: WMPLoadedSkin, event: String, targetID: String?) -> [String] {
        let wanted = event.lowercased().replacingOccurrences(of: "_", with: "")
        return skin.graph.allNodes.filter { node in
            targetID == nil || node.xmlID?.caseInsensitiveCompare(targetID ?? "") == .orderedSame
                || (targetID == "view" && node.kind == .view)
        }.flatMap { node in
            node.attributes.compactMap { attribute -> String? in
                guard case let .handler(authored, source) = attribute.value else { return nil }
                let normalized = authored.lowercased().replacingOccurrences(of: "_", with: "")
                let stripped = normalized.hasPrefix("on") ? String(normalized.dropFirst(2)) : normalized
                let wantedStripped = wanted.hasPrefix("on") ? String(wanted.dropFirst(2)) : wanted
                return stripped == wantedStripped ? source : nil
            }
        }
    }

    @discardableResult
    private func applyHostCommands(_ commands: [WMPJScriptHostCommand]) -> Bool {
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
              let activeScene, let phase5Session else { return }
        phase5Task?.cancel()
        phase5Task = Task { [weak self] in
            guard let self else { return }
            let event = WMPJScriptEvent(name: "timer", targetID: nil, handlers: [request.source])
            let output = await phase5Session.transact(skin: skin, viewID: viewID,
                size: activeScene.canvasSize, snapshot: host.snapshot, event: event)
            guard !Task.isCancelled else { return }
            do {
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: viewID, requestedSize: activeScene.canvasSize, overrides: output.overrides)
                let rendered = try await WMPRenderer(imageStore: store).render(
                    scene: scene, backingScale: renderBackingScale)
                self.sceneOverrides = output.overrides; self.activeScene = scene
                self.mainView?.present(rendered.image, scene: scene, dirtyBounds: scene.dirtyBounds)
                self.applyHostCommands(output.hostCommands); self.recordScriptDiagnostics(output.diagnostics)
            } catch { self.recordScriptDiagnostics([.init(code: "timer-transaction", message: error.localizedDescription)]) }
        }
    }

    private func cancelScriptTimers() {
        scriptTimerTasks.values.forEach { $0.cancel() }
        scriptTimerTasks.removeAll()
    }

    private func recordScriptDiagnostics(_ diagnostics: [WMPJScriptDiagnostic]) {
        guard !diagnostics.isEmpty else { return }
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
