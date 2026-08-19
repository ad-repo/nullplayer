import AppKit

final class WinampModernMainWindowController: NSWindowController, MainWindowProviding, NSWindowDelegate {

    /// Repaints every `.wal` window when a track's cover finishes loading.
    private var artworkObserver: NSObjectProtocol?
    private var loadedSkin: WinampModernLoadedSkin?
    private var skinView: WinampModernMainView?
    private var host: WinampModernAudioEngineHost?
    private var componentBridge: WinampModernComponentBridge?
    private var auxiliaryContainers: [AuxiliaryContainer] = []
    /// Containers whose window has been given a position. Placement happens once, on first show, so
    /// re-opening a window the user has moved never yanks it back.
    private var placedAuxiliaryWindows: Set<String> = []
    private var isApplyingSkinSize = false

    /// A separate visible container (the "separate windows" arrangement) rendered in its own native
    /// window with the shared script runtime + component host. cPro-Bento is a single-window SUI so
    /// this stays empty for it; skins that declare multiple visible containers populate it.
    private struct AuxiliaryContainer {
        let window: NSWindow
        let view: WinampModernMainView
        let kind: WinampModernComponentKind?
        let containerID: String
        /// The skin's own `name=` for this container, and whether it belongs in the host's window
        /// menu (Phase 27.7). A skin declares windows it binds no button to — Defix's two speaker
        /// cabinets and its configurator — and in Winamp those are opened from *Winamp's* Windows
        /// menu. Without the equivalent here they exist, render, and cannot be reached at all.
        let displayName: String
        let isListedInWindowMenu: Bool
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
        // Cover art arrives asynchronously and often *after* the scene has settled — with playback
        // paused nothing else would repaint, so an `<AlbumArt>` would sit on its "no cover art"
        // placeholder until something unrelated invalidated the window.
        artworkObserver = NotificationCenter.default.addObserver(
            forName: NowPlayingManager.artworkDidLoadNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.skinView?.needsDisplay = true
                self?.auxiliaryContainers.forEach { $0.view.needsDisplay = true }
            }
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
        // `.miniaturizable` on a window with no chrome to draw it: nothing appears, but AppKit will
        // only miniaturize a window whose mask allows it, and a skin's own Minimize button is the
        // only way into the Dock for a `.borderless` window.
        window.styleMask.insert(.miniaturizable)
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
            // Every renderer asks the one runtime for a `cfgattrib` control's state, so a switch in
            // the settings window and the control it mirrors in another window always agree.
            renderer.configStateProvider = { [weak scripts] in scripts?.configValue(of: $0) ?? false }
            renderer.layerFXProvider = { [weak scripts] in scripts?.layerFXMesh(for: $0) }
            let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host,
                                            componentHost: componentBridge)

            loadedSkin = loaded
            self.host = host
            self.componentBridge = componentBridge
            componentBridge.skinScaleProvider = { [weak self] in self?.skinScale ?? 1 }
            componentBridge.linkSheetPresenter = { [weak self] in
                self?.presentEmbeddedLibraryLinkSheet()
            }
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
            installWindowCommands()
            applyLayoutConstraints()
            // Container-scoped callbacks must exist *before* the scripts run: a skin that resizes or
            // switches a layout from `onScriptLoaded` does it during `start()`.
            // `PE_Info` is filled from the playlist component, and both the renderer and a script's
            // `getAutoWidth()` read it from here so they agree on the string.
            WasabiTextMetrics.componentTextProvider = { [weak componentBridge] in
                componentBridge?.playlistSnapshot()
            }
            wireContainerCallbacks(scripts: scripts)
            try scripts.start()
            // Immediately after `start()` — so after `onScriptLoaded` and XUI param delivery, and
            // before the first `updatePlaybackState()` can send `onPlay`: every scene tells its scripts
            // their geometry once. A script whose state is only assigned in `onResize` has none of it
            // until then (see `scriptsDidStart`).
            view.scriptsDidStart()
            auxiliaryContainers.forEach { $0.view.scriptsDidStart() }
            // The player's window is on screen from here; the auxiliary ones were ordered out at
            // creation and say so when they open. A skin that starts its animation from
            // `onSetVisible` (Defix's cassette reels) needs to be told.
            view.setSceneVisible(true)
            auxiliaryContainers.forEach { $0.view.setSceneVisible($0.window.isVisible) }
            // After `start()`: the catalog is reconciled against the containers that actually opened,
            // and against the holders the skin's own scripts built while starting.
            makeSurfaceCoordinator(loaded: loaded, scripts: scripts)
            revealEmbeddedLibraryAtStartup()
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
            renderer.configStateProvider = { [weak scripts] in scripts?.configValue(of: $0) ?? false }
            renderer.layerFXProvider = { [weak scripts] in scripts?.layerFXMesh(for: $0) }
            let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host,
                                            componentHost: componentBridge, drivesScripts: false)
            view.skinScale = skinScale
            let auxWindow = NSWindow(contentRect: NSRect(origin: .zero, size: view.scaledCanvasSize),
                                     styleMask: [.borderless, .resizable, .miniaturizable],
                                     backing: .buffered, defer: false)
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
            auxiliaryContainers.append(AuxiliaryContainer(
                window: auxWindow, view: view, kind: info.kind, containerID: info.id,
                displayName: WinampModernContainerTopology.displayName(of: info),
                isListedInWindowMenu: WinampModernContainerTopology.isListedInWindowMenu(info)))
            viewsByContainer[view.containerID] = view
        }
    }

    /// Surface routing for this skin: menus, skin buttons, and restoration all resolve through it.
    private(set) var surfaceCoordinator: WinampModernSurfaceCoordinator?

    // MARK: - Skin settings (Phase 27.3)

    private var skinSettingsController: WinampModernSkinSettingsWindowController?

    /// What the loaded skin registered with `newAttribute` and a person can actually set. Empty when
    /// no skin is loaded or the skin registered nothing — which is what keeps the menu entry out of a
    /// skin that has no settings.
    var registeredSkinSettings: [WinampModernScriptRuntime.RegisteredSetting] {
        skinView?.scripts.presentableSettings ?? []
    }

    func showSkinSettings() {
        guard let scripts = skinView?.scripts, !scripts.presentableSettings.isEmpty else { return }
        if skinSettingsController == nil {
            skinSettingsController = WinampModernSkinSettingsWindowController(runtime: scripts)
        }
        skinSettingsController?.refreshValues()
        skinSettingsController?.showWindow(nil)
        skinSettingsController?.window?.makeKeyAndOrderFront(nil)
    }

    /// The loaded skin's live palette, for the surfaces NullPlayer draws in windows of its own
    /// (Phase 16). Nil before a skin loads and while the placeholder is showing, which is exactly
    /// when a fallback window should keep its own defaults rather than guess at a theme.
    var currentPalette: WasabiPalette? { skinView?.renderer.palette }

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
                    // A replaced or shortened queue must not leave a surface scrolled past its end.
                    self?.skinView?.clampPlaylistScroll()
                    self?.skinView?.needsDisplay = true
                    self?.auxiliaryContainers.forEach {
                        $0.view.clampPlaylistScroll()
                        $0.view.needsDisplay = true
                    }
                }))
        // Every view's own `TOGGLE guid:…` now resolves through the same catalog the menu uses.
        let toggle: (WinampModernComponentKind) -> Bool = { [weak self] kind in
            guard let coordinator = self?.surfaceCoordinator, coordinator.handles(kind) else { return false }
            coordinator.toggleSurface(kind)
            return true
        }
        skinView?.surfaceToggleRequested = toggle
        auxiliaryContainers.forEach { $0.view.surfaceToggleRequested = toggle }
        // `TOGGLE <container-id>`: the skin's own windows, addressed by name. Case-insensitive
        // because a skin writes the id as it likes and its own container declaration is the match.
        let toggleContainer: (String) -> Bool = { [weak self] id in
            guard let self,
                  let matchedID = Self.matchingContainerID(id,
                                                           in: auxiliaryContainers.map(\.containerID)),
                  let container = auxiliaryContainers.first(where: { $0.containerID == matchedID })
            else { return false }
            setAuxiliaryWindow(id: container.containerID, visible: !container.window.isVisible)
            return true
        }
        skinView?.containerWindowToggleRequested = toggleContainer
        auxiliaryContainers.forEach { $0.view.containerWindowToggleRequested = toggleContainer }
    }

    static func matchingContainerID(_ requestedID: String, in containerIDs: [String]) -> String? {
        containerIDs.first { $0.caseInsensitiveCompare(requestedID) == .orderedSame }
    }

    /// Show the library in the skin's own window at launch, instead of waiting for the user to pick
    /// Windows → Library Browser.
    ///
    /// cPro-Bento opens on its Media Library tab, but the holder that tab displays is only built when
    /// the component is *revealed* — so the default view was an empty pane until you opened the
    /// library from the menu. Revealing it once here is the same route the menu takes, so there is no
    /// second code path to keep in step. Only for a skin that actually embeds the library: one that
    /// declares its own library window, or falls back to the classic one, is left alone so nothing
    /// pops open a window at launch.
    private func revealEmbeddedLibraryAtStartup() {
        guard let coordinator = surfaceCoordinator, coordinator.isEmbedded(.library) else { return }
        coordinator.showSurface(.library)
        skinView?.needsLayout = true
        skinView?.needsDisplay = true
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
        let opened = Self.openHolders(for: kind, in: scripts.loadedSkin.runtime.graph)
        #if DEBUG
        NSLog("WinampModern reveal %@ guid=%@ handlers=%d opened=%d", kind.rawValue, guid, handled, opened)
        #endif
        return handled > 0 || opened > 0
    }

    /// Wasabi's `windowholder autoopen="1"`: when the component a holder holds becomes visible, the
    /// holder brings its own surroundings on screen with it.
    ///
    /// This is the half of the contract a script cannot do for us. ClassicPro's SUI *does* switch
    /// tabs from `onGetCancelComponent`, but only `if (active_tab != 0)` — and at startup its
    /// `active_tab` is already 0, so asking for the Media Library made it decide it was already
    /// showing one while `centro.library` had never actually been shown. Winamp does not rely on the
    /// script here; the holder itself opens. So do we: reveal the hidden ancestors between an
    /// `autoopen` holder of this kind and its layout, and nothing else.
    ///
    /// Returns how many holders were opened.
    @discardableResult
    private static func openHolders(for kind: WinampModernComponentKind,
                                    in graph: WasabiObjectGraph) -> Int {
        var opened = 0
        func isAutoOpen(_ object: WasabiObject) -> Bool {
            switch object.attributes["autoopen"]?.lowercased() {
            case "1", "true", "yes": return true
            default: return false
            }
        }
        func visit(_ object: WasabiObject) {
            if WinampModernComponentRegistry.isHolderElement(object.typeName),
               WasabiSceneRenderer.componentKind(of: object) == kind, isAutoOpen(object) {
                var node: WasabiObject? = object
                var depth = 0
                while let current = node, depth < 64 {
                    if current.typeName.caseInsensitiveCompare("layout") == .orderedSame { break }
                    switch current.attributes["visible"]?.lowercased() {
                    case "0", "false", "no": _ = current.setAttribute("visible", value: "1")
                    default: break
                    }
                    node = current.parent
                    depth += 1
                }
                opened += 1
            }
            for child in object.children { visit(child) }
        }
        for root in graph.roots { visit(root) }
        return opened
    }

    /// The skin's embedded library surface, for browse-mode save/restore. Nil until a holder for it
    /// has actually appeared in a scene.
    var embeddedLibrarySurface: WinampModernLibrarySurface? { componentBridge?.currentLibrarySurface }

    /// The embedded browser's "link a server" flow. It has no classic controller to present from, so
    /// the sheet is attached to whichever `.wal` window is hosting it.
    private func presentEmbeddedLibraryLinkSheet() {
        guard let window else { return }
        let sheet = PlexLinkSheet()
        sheet.showAsSheet(from: window) { [weak self] success in
            guard success else { return }
            self?.componentBridge?.currentLibrarySurface?.reloadData()
        }
    }

    private func setAuxiliaryWindow(id: String, visible: Bool) {
        guard let container = auxiliaryContainers.first(where: { $0.containerID == id }) else { return }
        if visible {
            container.view.needsDisplay = true
            place(container)
            container.window.makeKeyAndOrderFront(nil)
        } else {
            container.window.orderOut(nil)
        }
        container.view.setSceneVisible(visible)
    }

    /// Close / Minimize as Winamp means them, wired to every window this skin owns.
    ///
    /// Not left to the view: `performClose(_:)` simulates a click on a close *button*, which a
    /// `.borderless` window does not have — it beeps and returns, which is why no skin's close button
    /// worked. And the commands are about the player, not one window: closing the player quits (the
    /// classic skin's close button does the same), closing an auxiliary window hides just it, and
    /// minimize takes the whole set down together instead of leaving the rest of the skin on screen.
    private func installWindowCommands() {
        skinView?.closeRequested = { NSApplication.shared.terminate(nil) }
        skinView?.minimizeRequested = { [weak self] in self?.minimizeAllWindows() }
        for container in auxiliaryContainers {
            container.view.closeRequested = { [weak auxWindow = container.window] in
                auxWindow?.orderOut(nil)
            }
            container.view.minimizeRequested = { [weak self] in self?.minimizeAllWindows() }
        }
    }

    private func minimizeAllWindows() {
        window?.miniaturize(nil)
        for container in auxiliaryContainers where container.window.isVisible {
            container.window.miniaturize(nil)
        }
    }

    /// Put an auxiliary window somewhere the user can see the first time it opens, then never move it
    /// again — a window created at `NSRect(origin: .zero, …)` sits at the **bottom-left corner of the
    /// screen**, which is where every one of these opened. Winamp stacks its extra windows under the
    /// player, so they go there: below the main window, each under the last, clamped to the screen.
    private func place(_ container: AuxiliaryContainer) {
        guard !placedAuxiliaryWindows.contains(container.containerID) else { return }
        placedAuxiliaryWindows.insert(container.containerID)
        let size = container.window.frame.size
        guard let anchor = window?.frame ?? NSScreen.main?.visibleFrame else { return }
        // Stack under whatever this skin already has on screen, so opening the playlist and then the
        // library does not put one on top of the other.
        let occupied = auxiliaryContainers
            .filter { $0.containerID != container.containerID && $0.window.isVisible }
            .reduce(0) { $0 + $1.window.frame.height }
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - occupied - size.height)
        if let visible = (window?.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
            origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        }
        container.window.setFrameOrigin(origin)
    }

    /// One installation of the two container-addressed callbacks, owned by the controller rather than
    /// by whichever view was created last.
    private func wireContainerCallbacks(scripts: WinampModernScriptRuntime) {
        scripts.layoutSwitchRequested = { [weak self] container, layoutID in
            guard let view = self?.viewsByContainer[container] else { return false }
            let switched = view.activateLayout(id: layoutID)
            // A different layout is a different set of component holders.
            if switched { view.needsLayout = true }
            return switched
        }
        scripts.layoutResizeRequested = { [weak self] container, size in
            self?.viewsByContainer[container]?.applyCanvasResize(size)
        }
        // A script moved something. Every container diffs its own scene and notifies what moved; a
        // container nothing happened in dispatches nothing.
        scripts.geometryDidSettle = { [weak self] in
            self?.viewsByContainer.values.forEach { $0.dispatchResizeIfChanged() }
        }
        // Only a scene knows where an object landed, and an object belongs to exactly one container —
        // so ask each container's renderer in turn and take the first that can place it.
        scripts.resolvedGeometryRequested = { [weak self] object in
            guard let self else { return nil }
            for view in viewsByContainer.values where !view.isTornDown {
                if let geometry = view.renderer.resolvedGeometry(of: object) { return geometry }
            }
            return nil
        }
        // Same ownership question, answered for the cursor: the window that can place the object is
        // the window whose pixel space its rect is in, so that is the one asked where the mouse is.
        scripts.mousePositionInObjectSpaceRequested = { [weak self] object in
            guard let self else { return nil }
            for view in viewsByContainer.values where !view.isTornDown {
                guard view.renderer.resolvedGeometry(of: object) != nil else { continue }
                return view.currentMousePositionInSkinPixels()
            }
            return nil
        }
    }

    @discardableResult
    private func toggleAuxiliaryWindow(for kind: WinampModernComponentKind) -> Bool {
        guard let container = auxiliaryContainers.first(where: { $0.kind == kind }) else { return false }
        if container.window.isVisible {
            container.window.orderOut(nil)
        } else {
            container.view.needsDisplay = true
            place(container)
            container.window.orderFront(nil)
        }
        container.view.setSceneVisible(container.window.isVisible)
        return true
    }

    /// The windows this skin declares that only the host can open: named, not `nomenu`, and not one
    /// of the surfaces the catalog already routes. Empty for a single-window SUI.
    var skinWindows: [(id: String, name: String, isVisible: Bool)] {
        // The catalog's own containers are excluded here rather than in the markup rule: whether a
        // container is *routed* is a runtime fact (Defix's `pledit` carries no component GUID and is
        // recognized from the declarative inventory), and the catalog is the only thing that knows it.
        let routed = surfaceCoordinator?.catalog.routedContainerIDs ?? []
        return auxiliaryContainers
            .filter { $0.isListedInWindowMenu && !routed.contains($0.containerID.lowercased()) }
            .map { ($0.containerID, $0.displayName, $0.window.isVisible) }
    }

    /// Show or hide one of them. Deliberately *not* routed through `WinampModernSurfaceCoordinator`:
    /// that catalog resolves a playback surface (playlist/EQ/library/video) across embedded, declared
    /// and classic-fallback homes, and these containers are none of those — they are skin windows with
    /// no NullPlayer surface behind them.
    @discardableResult
    func toggleSkinWindow(id: String) -> Bool {
        guard let container = auxiliaryContainers.first(where: { $0.containerID == id }) else { return false }
        if container.window.isVisible {
            container.window.orderOut(nil)
        } else {
            container.view.needsDisplay = true
            place(container)
            container.window.orderFront(nil)
        }
        container.view.setSceneVisible(container.window.isVisible)
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
    var mainLayoutMinimumSize: NSSize? { scaled(skinView?.renderer.userResizeLimits.minimum) }
    var mainLayoutMaximumSize: NSSize? { scaled(skinView?.renderer.userResizeLimits.maximum) }

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
            let limits = container.view.renderer.userResizeLimits
            guard let minimum = scaled(limits.minimum), let maximum = scaled(limits.maximum) else { continue }
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

    func updateTrackInfo(_ track: Track?) {
        skinView?.updateTrackInfo()
        refreshBoundText()
    }
    func updateVideoTrackInfo(title: String, artworkTrack: Track?) { skinView?.updateTrackInfo() }
    func clearVideoTrackInfo() { skinView?.updateTrackInfo() }
    func updateTime(current: TimeInterval, duration: TimeInterval) {
        skinView?.updateTime(current: current, duration: duration)
        // The queue's own length and duration can change while the clock is the only thing ticking
        // (the user edits the playlist mid-track), and this is the cheapest regular beat that sees it.
        refreshBoundText()
    }
    func updatePlaybackState() {
        skinView?.updatePlaybackState()
        refreshBoundText()
    }

    /// Poll the host-bound text objects and raise `onTextChanged` on the ones that moved.
    ///
    /// Driven from the host-state hooks rather than from a timer of its own, because that is exactly
    /// when a bound readout can change: the queue was edited, the track changed, the clock ticked.
    /// Defix's playlist box updates its `Items:`/`Time:` readouts from a subroutine whose only caller
    /// is `onTextChanged`, so without this the box never leaves its XML placeholders.
    private func refreshBoundText() { skinView?.scripts.refreshBoundText() }
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
        // A layout the skin gave no resize range is fixed, and a frame can still arrive at one
        // without a drag — `AppStateManager` restores saved frames, and a stale one is how T800 came
        // back stretched. Clamp here as well as in `contentMinSize`/`contentMaxSize`.
        let limits = view.renderer.userResizeLimits
        let proposed = CGSize(width: content.width / skinScale, height: content.height / skinScale)
        _ = view.renderer.resize(to: CGSize(
            width: min(max(proposed.width, limits.minimum.width), limits.maximum.width),
            height: min(max(proposed.height, limits.minimum.height), limits.maximum.height)))
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
        // The settings list belongs to the runtime that is about to go away; a window left open
        // would be listing a skin that no longer exists.
        skinSettingsController?.close()
        skinSettingsController = nil
        auxiliaryContainers.removeAll()
        placedAuxiliaryWindows.removeAll()
        viewsByContainer.removeAll()
        surfaceCoordinator = nil
        WasabiTextMetrics.componentTextProvider = nil
        // Views tear their own surfaces down; this releases the bridge's reference behind them.
        componentBridge?.releaseLibrarySurface()
        skinView?.teardown()
        skinView = nil
        host?.endVisualizationConsumption()
        host = nil
        componentBridge = nil
        loadedSkin?.teardown()
        loadedSkin = nil
    }

    deinit {
        if let artworkObserver { NotificationCenter.default.removeObserver(artworkObserver) }
        tearDownSkin()
    }
}
