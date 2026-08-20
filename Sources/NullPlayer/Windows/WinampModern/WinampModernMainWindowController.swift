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
    private var boundTextTimer: Timer?

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
        /// `default_visible="1"`: this window opens with the skin unless the user has since closed
        /// it (Phase 40, B6). Already net of the suppressions — a notifier and an empty browser frame
        /// arrive here as `false`, with the reason recorded in the skin's diagnostics.
        let opensByDefault: Bool
        /// Where the skin's own arrangement puts this window, **relative to the player's** own
        /// `default_x`/`default_y`, in skin pixels with y downward. `nil` when the skin says nothing,
        /// which is when the window is stacked under whatever is already on screen instead.
        let defaultOffset: CGPoint?
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
            // …and then the windows the skin says open *with* it. After `scriptsDidStart`, so a
            // window that opens at launch is told `onSetVisible` with its geometry already dispatched.
            applyDefaultContainerVisibility()
            // After `start()`: the catalog is reconciled against the containers that actually opened,
            // and against the holders the skin's own scripts built while starting.
            makeSurfaceCoordinator(loaded: loaded, scripts: scripts)
            revealEmbeddedLibraryAtStartup()
            // The host-bound readouts get their opening value here — the queue is usually already
            // populated by now — and a slow poll keeps them honest through playlist edits.
            refreshBoundText()
            startBoundTextPolling()
            #if DEBUG
            // `WINAMP_MODERN_SHOW_WINDOWS=SPEAKER1,SPEAKER2` opens skin windows at launch, the way
            // the user does from the Skin Windows menu. The counterpart of the harness's
            // `WINAMP_MODERN_RENDER_SHOW`: a defect confined to a window that ships
            // `default_visible="0"` cannot be reproduced from a cold launch without it.
            if let spec = ProcessInfo.processInfo.environment["WINAMP_MODERN_SHOW_WINDOWS"] {
                for name in spec.split(separator: ",") {
                    let id = name.trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty else { continue }
                    NSLog("WinampModern: opening skin window %@ (debug hook)", id)
                    _ = toggleSkinWindow(id: id)
                }
            }
            #endif
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
        let all = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
        // The player's own declared spot is the origin the rest of the arrangement is measured from:
        // a skin puts its playlist at `default_x="354"` *beside a player at 0*, and our player is
        // wherever the user (or a restored session) left it.
        let playerOrigin = all.first(where: \.isMainPlayer)?.defaultOrigin ?? .zero
        let containers = all.filter { !$0.isMainPlayer }
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
            // `default_visible="1"` on a window we cannot fill is recorded, once, rather than acted
            // on — so a compatibility report says why Rika's HOME window did not open with the skin.
            let suppression = WinampModernContainerTopology.defaultVisibilitySuppression(of: info)
            if let suppression {
                loaded.runtime.record(WalDiagnostic(
                    .unsupportedElement,
                    "container '\(info.id)' declares default_visible=\"1\" and is not opened with "
                        + "the skin: \(suppression.reason).",
                    severity: .warning))
            }
            auxiliaryContainers.append(AuxiliaryContainer(
                window: auxWindow, view: view, kind: info.kind, containerID: info.id,
                displayName: WinampModernContainerTopology.displayName(of: info),
                isListedInWindowMenu: WinampModernContainerTopology.isListedInWindowMenu(info),
                opensByDefault: info.opensByDefault && suppression == nil,
                defaultOffset: info.defaultOrigin.map {
                    CGPoint(x: $0.x - playerOrigin.x, y: $0.y - playerOrigin.y)
                }))
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

    // MARK: - Colour themes (Phase 32)

    /// The colour themes the loaded skin defines, in Winamp's own order, with the applied one.
    ///
    /// Empty for a skin that declares no `<gammaset>` — the catalog still reports an active theme of
    /// "Default" in that case, so the *names* are what the menu has to gate on, not the active one.
    var colorThemes: (names: [String], active: String) {
        guard let renderer = skinView?.renderer else { return ([], "") }
        return (renderer.colorThemeNames, renderer.themes.activeTheme)
    }

    /// Apply one. Goes through the view so the skin's own lists follow the pick and every surface
    /// repaints, exactly as a click on the skin's own picker does.
    func selectColorTheme(_ name: String) {
        skinView?.applyColorTheme(name)
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
                    // A menu item or a skin button asked: an explicit decision, remembered.
                    self?.setAuxiliaryWindow(id: id, visible: visible, record: true)
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
            setAuxiliaryWindow(id: container.containerID, visible: !container.window.isVisible,
                               record: true)
            return true
        }
        skinView?.containerWindowToggleRequested = toggleContainer
        auxiliaryContainers.forEach { $0.view.containerWindowToggleRequested = toggleContainer }
        // `getContainer("SUI").show()` — a skin opening one of its own windows from script rather
        // than from markup. Defix's four round buttons reach their targets only this way, and the
        // request is idempotent on purpose: the skin also calls `show()` from timers, and acting on
        // one that asks for the state the window is already in would re-front it 30 times a second.
        scripts.containerVisibilityRequested = { [weak self] id, visible in
            guard let self,
                  let matchedID = Self.matchingContainerID(id,
                                                           in: auxiliaryContainers.map(\.containerID)),
                  let container = auxiliaryContainers.first(where: { $0.containerID == matchedID }),
                  container.window.isVisible != visible
            else { return }
            setAuxiliaryWindow(id: matchedID, visible: visible)
        }
        // And the read side: `getContainer(id).toggle()` / `.isVisible()` must be answered by the
        // window, not by the graph attribute — `setAuxiliaryWindow` and the close button both move a
        // window without writing it.
        scripts.containerVisibilityQuery = { [weak self] id in
            guard let self,
                  let matchedID = Self.matchingContainerID(id,
                                                           in: auxiliaryContainers.map(\.containerID)),
                  let container = auxiliaryContainers.first(where: { $0.containerID == matchedID })
            else { return nil }
            return container.window.isVisible
        }
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

    private func setAuxiliaryWindow(id: String, visible: Bool, record: Bool = false,
                                    activate: Bool = true) {
        guard let container = auxiliaryContainers.first(where: { $0.containerID == id }) else { return }
        if visible {
            container.view.needsDisplay = true
            place(container)
            if activate {
                container.window.makeKeyAndOrderFront(nil)
            } else {
                container.window.orderFront(nil)
            }
        } else {
            container.window.orderOut(nil)
        }
        container.view.setSceneVisible(visible)
        if record { rememberContainerVisibility(id: id, visible: visible) }
    }

    // MARK: - `default_visible` (Phase 40, B6)

    /// The section a container's remembered open/closed state lives in, inside the *skin's own*
    /// namespaced configuration — so two skins that both declare a `Config` window do not share one
    /// answer, and nothing here reaches arbitrary preferences.
    private static let windowVisibilitySection = "@nullplayer.windows"

    /// Open the windows the skin declares as `default_visible="1"`.
    ///
    /// Winamp opens these *with* the skin: Defix's configurator is on screen the moment its skin
    /// loads, and here it was only ever reachable. The declaration is a **default**, not a command —
    /// a window the user has since closed from the menu, from the skin's own button, or from its
    /// close box stays closed on the next launch, which is the whole reason a settings window opening
    /// at every launch was worse than not honouring the attribute at all.
    ///
    /// Non-activating: the player window is what the user should be looking at after a load, not the
    /// configurator that happened to open behind it.
    private func applyDefaultContainerVisibility() {
        var opened = false
        for container in auxiliaryContainers where !container.window.isVisible {
            guard Self.opensAtLoad(opensByDefault: container.opensByDefault,
                                   remembered: rememberedContainerVisibility(id: container.containerID))
            else { continue }
            setAuxiliaryWindow(id: container.containerID, visible: true, activate: false)
            opened = true
        }
        // Everything that just opened was ordered in front; the player belongs on top of its own
        // auxiliary windows. Only if it is already on screen — at launch this runs *before*
        // `WindowManager` has placed and shown it, and fronting it here would flash it at the frame
        // a restored session is about to replace.
        if opened, window?.isVisible == true { window?.orderFront(nil) }
    }

    /// The precedence, in one testable place: what the user last decided about this window wins over
    /// what the skin declares, and the skin's declaration wins over "closed". A user who has never
    /// touched the window has `remembered == nil`, which is not the same as having closed it.
    static func opensAtLoad(opensByDefault: Bool, remembered: Bool?) -> Bool {
        remembered ?? opensByDefault
    }

    /// What the user last did with this window, or `nil` when they have never said.
    private func rememberedContainerVisibility(id: String) -> Bool? {
        guard let configuration = loadedSkin?.configuration else { return nil }
        let stored = configuration.integer(section: Self.windowVisibilitySection, key: id, default: -1)
        return stored < 0 ? nil : stored != 0
    }

    /// Record an explicit user decision — a menu item, a skin button, a close box. Script-driven
    /// `show()`/`hide()` and the startup default deliberately do **not** write here: a skin that
    /// opens one of its own windows from a timer is describing this run, not the next one.
    private func rememberContainerVisibility(id: String, visible: Bool) {
        loadedSkin?.configuration.setInteger(visible ? 1 : 0,
                                             section: Self.windowVisibilitySection, key: id)
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
            // Through `setAuxiliaryWindow`, not `orderOut` directly: closing a window is a scene
            // becoming invisible, and the skin is listening. Ujola Cat's console buttons light up
            // from their window's layout `onSetVisible`, so a close that bypassed the scene left the
            // button lit with nothing on screen.
            container.view.closeRequested = { [weak self, id = container.containerID] in
                self?.setAuxiliaryWindow(id: id, visible: false, record: true)
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
        var origin: NSPoint
        if let offset = container.defaultOffset {
            // The skin's own arrangement: Winamp Modern's playlist sits at `default_x="354"` beside a
            // player at 0, its album art under that at `default_y="165"`. Measured from the player's
            // top-left, at the current UI Size, with the skin's downward y flipped into AppKit's.
            origin = Self.arrangedOrigin(playerFrame: anchor, size: size, offset: offset,
                                         scale: skinScale)
        } else {
            // The skin says nothing: stack under whatever it already has on screen, so opening the
            // playlist and then the library does not put one on top of the other.
            let occupied = auxiliaryContainers
                .filter { $0.containerID != container.containerID && $0.window.isVisible }
                .reduce(0) { $0 + $1.window.frame.height }
            origin = NSPoint(x: anchor.minX, y: anchor.minY - occupied - size.height)
        }
        if let visible = (window?.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
            origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        }
        container.window.setFrameOrigin(origin)
    }

    /// Where the skin's own arrangement puts a window, in AppKit coordinates: `offset` skin pixels
    /// right of and *below* the player's top-left, scaled to the current UI Size.
    static func arrangedOrigin(playerFrame: NSRect, size: NSSize, offset: CGPoint,
                               scale: CGFloat) -> NSPoint {
        NSPoint(x: playerFrame.minX + offset.x * scale,
                y: playerFrame.maxY - offset.y * scale - size.height)
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
        rememberContainerVisibility(id: container.containerID, visible: container.window.isVisible)
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
        rememberContainerVisibility(id: container.containerID, visible: container.window.isVisible)
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

    /// A slow safety poll for the host-bound readouts.
    ///
    /// The event hooks above cover playback, but the playlist's own length and duration change on
    /// edits we get no callback for — and the queue is usually populated *before* the first poll, so
    /// without a beat of its own a skin can miss its opening value entirely. A handful of text objects
    /// and a string compare each, once a second; the dispatch only happens when something actually
    /// moved.
    private func startBoundTextPolling() {
        boundTextTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refreshBoundText() }
        RunLoop.main.add(timer, forMode: .common)
        boundTextTimer = timer
    }
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
        boundTextTimer?.invalidate()
        boundTextTimer = nil
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
