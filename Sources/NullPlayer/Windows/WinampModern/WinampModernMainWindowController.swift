import AppKit

final class WinampModernMainWindowController: NSWindowController, MainWindowProviding, NSWindowDelegate {
    private var loadedSkin: WinampModernLoadedSkin?
    private var skinView: WinampModernMainView?
    private var host: WinampModernAudioEngineHost?
    private var componentBridge: WinampModernComponentBridge?
    private var auxiliaryContainers: [AuxiliaryContainer] = []
    private var isApplyingSkinSize = false

    /// A separate visible container (the "separate windows" arrangement) rendered in its own native
    /// window with the shared script runtime + component host. cPro-Bento is a single-window SUI so
    /// this stays empty for it; skins that declare multiple visible containers populate it.
    private struct AuxiliaryContainer {
        let window: NSWindow
        let view: WinampModernMainView
        let kind: WinampModernComponentKind?
        let containerID: String
    }

    /// Every container this controller hosts, main included, addressed the way a script addresses it.
    /// One skin has one script runtime and several windows, so a `switchToLayout`/`resize` has to be
    /// delivered to the window that owns the container the script called it on — not to whichever
    /// view happened to install the callback last (Phase 13.3, R6).
    private var viewsByContainer: [WasabiObjectID: WinampModernMainView] = [:]
    private(set) var loadFailure: Error?

    convenience init() {
        let defaultSize = NSSize(width: 275, height: 116)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: defaultSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        self.init(window: window)
        setupWindow()
        #if DEBUG
        if let localPath = UserDefaults.standard.string(forKey: "winampModernSkinPath"),
           !localPath.isEmpty {
            loadSkin(at: URL(fileURLWithPath: localPath))
            return
        }
        #endif
        if let selected = WinampModernSkinImporter.shared.selectedSkin() {
            loadSkin(at: selected.archiveURL)
        } else {
            showPlaceholder("Import a .wal skin from the Winamp Modern menu")
        }
    }

    private func setupWindow() {
        guard let window else { return }
        window.title = "NullPlayer — Winamp Modern"
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.styleMask.insert(.resizable)
        window.delegate = self
        window.center()
        window.setAccessibilityIdentifier("WinampModernMainWindow")
        window.setAccessibilityLabel("Winamp Modern Main Window")
    }

    func loadSkin(at url: URL) {
        tearDownSkin()
        do {
            let loaded = try WinampModernSkinLoader().load(from: url)
            let host = WinampModernAudioEngineHost(engine: WindowManager.shared.audioEngine)
            let componentBridge = WinampModernComponentBridge(engine: WindowManager.shared.audioEngine)
            let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
            renderer.componentHost = componentBridge
            let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
            let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host,
                                            componentHost: componentBridge)

            loadedSkin = loaded
            self.host = host
            self.componentBridge = componentBridge
            skinView = view
            view.canvasSizeDidChange = { [weak self] size in
                // A layout switch swaps the active layout, and with it the limits this window obeys.
                self?.resizeWindow(to: size, reason: "canvasSizeDidChange")
                self?.applyLayoutConstraints()
            }
            viewsByContainer[view.containerID] = view
            loadFailure = nil
            view.skinScale = skinScale
            window?.contentView = view
            resizeWindow(to: view.scaledCanvasSize, reason: "loadSkin")
            setupAuxiliaryContainers(loaded: loaded, host: host, scripts: scripts,
                                     componentBridge: componentBridge)
            view.componentWindowToggleRequested = { [weak self] kind in
                self?.toggleAuxiliaryWindow(for: kind) ?? false
            }
            applyLayoutConstraints()
            // Container-scoped callbacks must exist *before* the scripts run: a skin that resizes or
            // switches a layout from `onScriptLoaded` does it during `start()`.
            wireContainerCallbacks(scripts: scripts)
            try scripts.start()
            // After `start()`: the catalog is reconciled against the containers that actually opened,
            // and against the holders the skin's own scripts built while starting.
            makeSurfaceCoordinator(loaded: loaded, scripts: scripts)
            #if DEBUG
            NSLog("WinampModern surfaces [%@]: %@", url.lastPathComponent,
                  surfaceCoordinator?.summary ?? "-")
            #endif
            #if DEBUG
            // Surface the per-skin compatibility report (Phase 7.2). After `start()`, the report also
            // reflects any unsupported MAKI methods the skin's `onscriptloaded` reached for.
            let report = loaded.compatibilityReport(withRuntime: scripts)
            if report.level != .full {
                NSLog("WinampModern compatibility [%@]:\n%@", url.lastPathComponent, report.summary)
            }
            #endif
            view.updatePlaybackState()
            view.updateTime(current: host.currentTime, duration: host.duration)
            view.needsDisplay = true
        } catch {
            loadFailure = error
            NSLog("WinampModern: Failed to load '%@': %@", url.lastPathComponent, error.localizedDescription)
            tearDownSkin()
            showPlaceholder(error.localizedDescription)
        }
    }

    /// Create one native window per visible non-main container. The main window owns the scripted
    /// scene; auxiliary containers render + take input against the shared runtime but do not drive
    /// the single-owner script callbacks (`drivesScripts: false`). Full per-container MAKI layout
    /// switching in auxiliary windows is deferred to Phase 7.
    private func setupAuxiliaryContainers(loaded: WinampModernLoadedSkin,
                                          host: WinampModernAudioEngineHost,
                                          scripts: WinampModernScriptRuntime,
                                          componentBridge: WinampModernComponentBridge) {
        let containers = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
            .filter { !$0.isMainPlayer }
        for info in containers {
            guard let renderer = try? WasabiSceneRenderer(loadedSkin: loaded, host: host,
                                                          containerID: info.id) else { continue }
            renderer.componentHost = componentBridge
            let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host,
                                            componentHost: componentBridge, drivesScripts: false)
            view.skinScale = skinScale
            let auxWindow = NSWindow(contentRect: NSRect(origin: .zero, size: view.scaledCanvasSize),
                                     styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
            auxWindow.isReleasedWhenClosed = false
            auxWindow.isOpaque = false
            auxWindow.backgroundColor = .clear
            auxWindow.hasShadow = false
            auxWindow.contentView = view
            auxWindow.setAccessibilityIdentifier("WinampModernContainer_\(info.id)")
            auxWindow.setAccessibilityLabel(info.object.attributes["name"] ?? info.id)
            auxWindow.delegate = self
            auxWindow.orderOut(nil)
            // A script resizing *this* container resizes this window, not the player's.
            view.canvasSizeDidChange = { [weak self, weak auxWindow] size in
                guard let auxWindow else { return }
                self?.resize(window: auxWindow, to: size)
                self?.applyLayoutConstraints()
            }
            // The container's own `component=` GUID, not its id — `Pledit` and `MLibrary` only look
            // like their kinds by convention (`WinampModernContainerTopology.kind(of:)`).
            auxiliaryContainers.append(AuxiliaryContainer(window: auxWindow, view: view,
                                                          kind: info.kind, containerID: info.id))
            viewsByContainer[view.containerID] = view
        }
    }

    /// Surface routing for this skin: menus, skin buttons, and restoration all resolve through it.
    private(set) var surfaceCoordinator: WinampModernSurfaceCoordinator?

    private func makeSurfaceCoordinator(loaded: WinampModernLoadedSkin,
                                        scripts: WinampModernScriptRuntime) {
        let hosted = Set(auxiliaryContainers.map(\.containerID))
        let catalog = WinampModernSurfaceCoordinator.makeCatalog(
            loadedSkin: loaded,
            hostedContainerIDs: hosted,
            embeddedContainerID: skinView?.containerID)
        surfaceCoordinator = WinampModernSurfaceCoordinator(
            catalog: catalog,
            environment: .init(
                revealEmbedded: { [weak self, weak scripts] kind, _ in
                    guard let self, let scripts else { return false }
                    window?.makeKeyAndOrderFront(nil)
                    let revealed = Self.revealEmbeddedSurface(kind, scripts: scripts)
                    skinView?.needsDisplay = true
                    return revealed
                },
                isMainWindowVisible: { [weak self] in self?.window?.isVisible == true },
                window: { [weak self] id in
                    self?.auxiliaryContainers.first { $0.containerID == id }?.window
                },
                setVisible: { [weak self] id, visible in
                    self?.setAuxiliaryWindow(id: id, visible: visible)
                },
                classicFallback: { kind, showOnly in
                    WindowManager.shared.showClassicSurfaceForWinampModern(kind, showOnly: showOnly)
                },
                redraw: { [weak self] in
                    self?.skinView?.needsDisplay = true
                    self?.auxiliaryContainers.forEach { $0.view.needsDisplay = true }
                }))
        // Every view's own `TOGGLE guid:…` now resolves through the same catalog the menu uses.
        let toggle: (WinampModernComponentKind) -> Bool = { [weak self] kind in
            guard let coordinator = self?.surfaceCoordinator, coordinator.handles(kind) else { return false }
            coordinator.toggleSurface(kind)
            return true
        }
        skinView?.surfaceToggleRequested = toggle
        auxiliaryContainers.forEach { $0.view.surfaceToggleRequested = toggle }
    }

    /// Ask the skin to bring an embedded surface to the front, the way Winamp does.
    ///
    /// Wasabi has one contract for this: when a component is about to become visible the host calls
    /// `System.onGetCancelComponent(guid, true)`, and an SUI skin uses it to switch to the tab, mini
    /// area, or drawer that holds that component — ClassicPro's `CentroSUI2.m` compares the GUID
    /// against `PL_GUID`/`ML_GUID`/`VIDEO_GUID`/`VIS_GUID` and calls `openTabNo`. Sending the same
    /// event is what actually opens cPro's Media Library tab; finding the holder and returning (the
    /// old behaviour) left the click doing nothing at all.
    private static func revealEmbeddedSurface(_ kind: WinampModernComponentKind,
                                              scripts: WinampModernScriptRuntime) -> Bool {
        guard let guid = WinampModernComponentRegistry.canonicalGUID(for: kind) else {
            // The equalizer has no component GUID; a skin-drawn EQ is already on screen wherever the
            // skin drew it, so revealing the player window is the whole job.
            return true
        }
        let handled = (try? scripts.dispatchSystem(event: "ongetcancelcomponent",
                                                   arguments: [.string(guid), .boolean(true)])) ?? 0
        return handled > 0
    }

    private func setAuxiliaryWindow(id: String, visible: Bool) {
        guard let container = auxiliaryContainers.first(where: { $0.containerID == id }) else { return }
        if visible {
            container.view.needsDisplay = true
            container.window.makeKeyAndOrderFront(nil)
        } else {
            container.window.orderOut(nil)
        }
    }

    /// One installation of the two container-addressed callbacks, owned by the controller rather than
    /// by whichever view was created last.
    private func wireContainerCallbacks(scripts: WinampModernScriptRuntime) {
        scripts.layoutSwitchRequested = { [weak self] container, layoutID in
            guard let view = self?.viewsByContainer[container] else { return false }
            return view.activateLayout(id: layoutID)
        }
        scripts.layoutResizeRequested = { [weak self] container, size in
            self?.viewsByContainer[container]?.applyCanvasResize(size)
        }
    }

    @discardableResult
    private func toggleAuxiliaryWindow(for kind: WinampModernComponentKind) -> Bool {
        guard let container = auxiliaryContainers.first(where: { $0.kind == kind }) else { return false }
        if container.window.isVisible {
            container.window.orderOut(nil)
        } else {
            container.view.needsDisplay = true
            container.window.orderFront(nil)
        }
        return true
    }

    /// Number of separate-container windows the current skin declares (0 for a single-window SUI).
    var auxiliaryContainerCount: Int { auxiliaryContainers.count }

    /// UI Size for this mode. The skin's own pixel grid never changes; the view scales at the drawing
    /// and input boundaries and every window is sized to `canvas × scale`.
    private(set) var skinScale: CGFloat = 1

    /// The size the main window wants at `scale`, used by `WindowManager.applyDoubleSize` to place
    /// this mode's window instead of the classic main-window constant.
    func mainWindowSize(atScale scale: CGFloat) -> NSSize? {
        guard let view = skinView else { return nil }
        return NSSize(width: (view.renderer.canvasSize.width * scale).rounded(),
                      height: (view.renderer.canvasSize.height * scale).rounded())
    }

    /// The main layout's own resize limits at the current UI Size. Each `.wal` container has its own
    /// pair — an auxiliary playlist window is not bounded by the player's minimum — so these are read
    /// per renderer rather than shared.
    var mainLayoutMinimumSize: NSSize? { scaled(skinView?.renderer.layoutMinimumSize) }
    var mainLayoutMaximumSize: NSSize? { scaled(skinView?.renderer.layoutMaximumSize) }

    private func scaled(_ size: CGSize?) -> NSSize? {
        guard let size else { return nil }
        return NSSize(width: (size.width * skinScale).rounded(), height: (size.height * skinScale).rounded())
    }

    /// A frame from saved state is honoured for its position but never for a size the active layout
    /// rejects: `AppStateManager` restores frames verbatim, which is how a 500×500 cPro-Bento window
    /// came back as 376×182 (R1). The saved top-left is preserved so a clamped window does not jump.
    func clampRestoredFrame(_ frame: NSRect) -> NSRect {
        guard let minimum = mainLayoutMinimumSize, let maximum = mainLayoutMaximumSize else { return frame }
        return Self.clamp(frame: frame, minimum: minimum, maximum: maximum)
    }

    /// Pure form of the restore clamp, so the rule can be tested without a live skin or window.
    static func clamp(frame: NSRect, minimum: NSSize, maximum: NSSize) -> NSRect {
        let size = NSSize(width: min(max(frame.width, minimum.width), maximum.width),
                          height: min(max(frame.height, minimum.height), maximum.height))
        guard size != frame.size else { return frame }
        return NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Give every `.wal` window the limits of the layout it is actually showing.
    private func applyLayoutConstraints() {
        if let window, let minimum = mainLayoutMinimumSize, let maximum = mainLayoutMaximumSize {
            window.contentMinSize = minimum
            window.contentMaxSize = maximum
        }
        for container in auxiliaryContainers {
            guard let minimum = scaled(container.view.renderer.layoutMinimumSize),
                  let maximum = scaled(container.view.renderer.layoutMaximumSize) else { continue }
            container.window.contentMinSize = minimum
            container.window.contentMaxSize = maximum
        }
    }

    func applyUIScale(_ scale: CGFloat) {
        skinScale = max(0.1, scale)
        skinView?.skinScale = skinScale
        if let size = skinView?.scaledCanvasSize { resizeWindow(to: size, reason: "uiScale=\(skinScale)") }
        for container in auxiliaryContainers {
            container.view.skinScale = skinScale
            let size = container.view.scaledCanvasSize
            container.window.setContentSize(size)
            container.view.setFrameSize(size)
            container.view.needsDisplay = true
        }
        applyLayoutConstraints()
        skinView?.needsDisplay = true
    }

    private func resizeWindow(to size: NSSize, reason: String = "skin") {
        guard let window else { return }
        #if DEBUG
        NSLog("WinampModern R1: resizeWindow(%@) reason=%@ from=%@",
              NSStringFromSize(size), reason, NSStringFromRect(window.frame))
        #endif
        resize(window: window, to: size)
    }

    /// Resize any `.wal` window around its top-left, which is the corner Winamp anchors to.
    private func resize(window: NSWindow, to size: NSSize) {
        guard !isApplyingSkinSize else { return }
        isApplyingSkinSize = true
        defer { isApplyingSkinSize = false }
        let oldTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        window.setFrame(NSRect(x: oldTopLeft.x, y: oldTopLeft.y - frame.height,
                               width: frame.width, height: frame.height), display: true)
    }

    private func showPlaceholder(_ message: String) {
        let size = NSSize(width: 275, height: 116)
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        let label = NSTextField(wrappingLabelWithString: "Winamp Modern (.wal)\n\(message)")
        label.font = .systemFont(ofSize: 10)
        label.textColor = NSColor(white: 0.7, alpha: 1)
        label.alignment = .center
        label.frame = NSRect(x: 12, y: 28, width: size.width - 24, height: 60)
        content.addSubview(label)
        window?.contentView = content
        resizeWindow(to: size, reason: "placeholder")
    }

    func updateTrackInfo(_ track: Track?) { skinView?.updateTrackInfo() }
    func updateVideoTrackInfo(title: String, artworkTrack: Track?) { skinView?.updateTrackInfo() }
    func clearVideoTrackInfo() { skinView?.updateTrackInfo() }
    func updateTime(current: TimeInterval, duration: TimeInterval) {
        skinView?.updateTime(current: current, duration: duration)
    }
    func updatePlaybackState() { skinView?.updatePlaybackState() }
    func updateSpectrum(_ levels: [Float]) { skinView?.updateSpectrum(levels) }
    func skinDidChange() { skinView?.needsDisplay = true }
    func windowVisibilityDidChange() { skinView?.needsDisplay = true }

    func windowDidResize(_ notification: Notification) {
        guard !isApplyingSkinSize,
              let resized = notification.object as? NSWindow,
              let view = resized.contentView as? WinampModernMainView else { return }
        // The skin resizes on its own pixel grid, so the dragged size comes back out of UI Size first
        // and the accepted size goes back in. Every `.wal` window works this way, each against the
        // limits of its own container's active layout.
        let content = resized.contentLayoutRect.size
        _ = view.renderer.resize(to: CGSize(width: content.width / skinScale,
                                            height: content.height / skinScale))
        let size = view.scaledCanvasSize
        if size != content { resize(window: resized, to: size) }
        if size != view.frame.size { view.setFrameSize(size) }
        view.needsDisplay = true
    }

    func prepareForUITeardown() { tearDownSkin() }

    private func tearDownSkin() {
        // Auxiliary views share the main view's script runtime + host, so tear them down first
        // (they only release their own renderer); the main view then tears down the shared runtime.
        for container in auxiliaryContainers {
            container.view.teardown()
            container.window.orderOut(nil)
            container.window.contentView = nil
        }
        auxiliaryContainers.removeAll()
        viewsByContainer.removeAll()
        surfaceCoordinator = nil
        skinView?.teardown()
        skinView = nil
        host?.endVisualizationConsumption()
        host = nil
        componentBridge = nil
        loadedSkin?.teardown()
        loadedSkin = nil
    }

    deinit { tearDownSkin() }
}
