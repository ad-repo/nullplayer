import AppKit
import NullPlayerCore
import UniformTypeIdentifiers

/// The AIMP-mode main window: one borderless window showing the selected skin's main form. Loads
/// the `.acs5`/`.acs4`/`.acs3`/`.acs` off the main thread and shows it through `AIMPSkinMainView`; with none
/// selected, or one that fails to load, the view's app-authored panel stands in. The window's size is
/// the form's natural size times the UI scale; a reload or a restored frame keeps its top-left corner.
final class AIMPSkinMainWindowController: NSWindowController, NSWindowDelegate, SingleCanvasMainWindow, SkinDrawnLists,
                                          SkinAuxiliaryWindows {
    static let placeholderSize = AIMPSkinMainView.unskinnedSize

    private let importer: AIMPSkinImporter
    private let skinView = AIMPSkinMainView()
    /// The skin's other windows (speakers, amplifier, equalizer, its own playlist and library).
    private lazy var companions = AIMPSkinCompanionWindows(delegate: self)
    private var coverArt: CGImage?
    private var artworkTrackID: Track.ID?
    private var artworkTask: Task<Void, Never>?
    let skinLoad = SkinLoadTask()
    /// The skin's level meters: each channel's RMS with VU ballistics, from the stereo tap.
    private let levelModel = PeppyMeterLevelModel(consumerId: "aimpSkinLevels")
    /// The player as this skin session sees it; a file size, the library model or a track's
    /// details fetched off the main thread refresh the skin.
    private lazy var engineHost = AIMPSkinAudioEngineHost(engine: WindowManager.shared.audioEngine) { [weak self] in
        self?.refreshHostState()
    }
    /// The skin file on screen, nil while the unskinned panel stands in.
    private(set) var loadedSkinURL: URL?
    /// The loaded skin, running; every window showing one of its forms draws from it.
    private var runtime: AIMPSkinRuntime?
    /// Set once the first skin (or the unskinned panel) is up; until then the playlist and library
    /// opens a launch restores wait in `opensAwaitingSkin`.
    private var skinPresented = false
    private var opensAwaitingSkin: [() -> Void] = []
    private var playlistRefreshPending = false
    /// NullPlayer's own windows (EQ, a skin without its own playlist or library) wear AIMP's dark
    /// grey with its orange accent beside every skin, never another family's chrome: an AIMP skin
    /// authors no palette for windows it does not draw. `SkinnedSurfaceStyle` runs every foreground
    /// through `legible`.
    let surfaceStyle = unskinnedSurfaceStyle
    static let unskinnedSurfaceStyle: SkinnedSurfaceStyle = {
        let ground = NSColor(calibratedWhite: 0.14, alpha: 1)
        let text = NSColor(calibratedWhite: 0.8, alpha: 1)
        let selection = SkinnedSurfaceStyle.blend(ground, toward: NSColor(calibratedRed: 0.94, green: 0.49, blue: 0.09, alpha: 1), by: 0.45)
        return SkinnedSurfaceStyle(roles: SkinnedSurfaceRoles(
            background: ground, text: text, currentText: .white, selectionBackground: selection, selectionText: .white,
            treeText: text, treeSelection: selection))
    }()

    /// `importer`: the installed skins and selection; a test passes its own folder.
    init(importer: AIMPSkinImporter = AIMPSkinImporter()) {
        self.importer = importer
        let window = SkinnedBorderlessWindow(contentRect: NSRect(origin: .zero, size: Self.placeholderSize),
                                             styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        // The skin casts its own, from what it draws (`AIMPSkinMainView`).
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.title = "NullPlayer — AIMP"
        window.setAccessibilityIdentifier("AIMPSkinMainWindow")
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = skinView
        skinView.extraMenuItems = { [weak self] in self?.companionMenuItems() ?? [] }
        skinView.popupMenu = { [weak self] popup in
            guard let self, let runtime = self.runtime else { return NSMenu() }
            return Self.popupMenu(popup, state: runtime.state, library: self.engineHost.librarySource.library) { [weak runtime] change in
                if let runtime { change(&runtime.state) }
            }
        }
        skinView.onDisplaySizeChange = { [weak self] in self?.fitWindow() }
        levelModel.onLevels = { [weak self] left, right in
            guard let self else { return }
            let floor = self.levelModel.floorDB
            self.runtime?.levels = (AIMPSkinAudioEngineHost.meterLevel(left, floor: floor), AIMPSkinAudioEngineHost.meterLevel(right, floor: floor))
        }
        reloadSelectedSkin()
    }

    required init?(coder: NSCoder) { nil }

    /// A runtime for `skin`, wired to the player and to this window's companions.
    private func makeRuntime(_ skin: AIMPSkin) -> AIMPSkinRuntime {
        let runtime = AIMPSkinRuntime(skin: skin, player: currentPlayer())
        runtime.onStateChange = { [weak self] in self?.updateCompanionVisibility() }
        // The meters run with the skin's clock: playing, and on screen.
        runtime.onClockChange = { [weak self] running in
            guard let self else { return }
            running ? self.levelModel.start() : self.levelModel.stop()
        }
        runtime.onAction = { [weak self] action in
            self?.engineHost.perform(action, window: self?.window)
            self?.refreshHostState()
        }
        return runtime
    }

    // MARK: - Choosing a skin (`SingleCanvasMainWindow`)

    var skinSelection: SkinSelection { importer.selection }
    func selectedSkinURL() throws -> URL? { try importer.selectedSkinURL() }
    static func loadSkin(at url: URL) async throws -> AIMPSkin { try await AIMPSkinLoader.load(file: url) }

    func importSkinFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = AIMPSkinImporter.fileExtensions.sorted().compactMap { UTType(filenameExtension: $0) } + [.zip]
        panel.message = "Select an AIMP skin (.acs5, .acs4, .acs3, .acs, or a .zip from the AIMP catalog)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        skinLoad.run({ [importer] in try await importer.importSkins(from: url) },
                     done: { [weak self] _ in self?.reloadSelectedSkin() },
                     failed: { error in
                         let alert = NSAlert()
                         alert.messageText = "“\(url.lastPathComponent)” could not be loaded."
                         alert.informativeText = "\(error.localizedDescription)"
                         alert.runModal()
                     })
    }

    // MARK: - Presenting

    func present(_ shown: (skin: AIMPSkin, url: URL)?, error: Error?) {
        if let shown {
            NSLog("AIMPSkin: loaded '%@' (%d findings)", shown.url.lastPathComponent, shown.skin.findings.count)
        }
        if let error { NSLog("AIMPSkin: %@", "\(error)") }
        loadedSkinURL = shown?.url
        skinView.message = error.map { "This AIMP skin could not be loaded:\n\($0.localizedDescription)" }
        // As with `.wal` skins, a skin switch neither opens nor closes the playlist or library: what
        // is open now (the skin's own window, or NullPlayer's for a skin with none) stays open. The
        // first skin up carries NullPlayer's windows as the outgoing mode left them, its own starting
        // closed rather than at each skin's `InitialVisible`; a launch's restored session opens them
        // after it (`deferUntilSkinLoads`).
        let carried = Self.lists.filter(isOpen)
        // One skin at a time: the outgoing one stops and its windows go, then the incoming one is
        // installed with its windows, then its load scripts run. Started beside the outgoing
        // windows, its scripts showed and hid those.
        runtime?.stop()
        rebuildCompanions(nil)
        // The host builds the library model only for a skin that shows it (its own library
        // window, or library lists on the deck).
        engineHost.librarySource.isShown = shown?.skin.index.showsLibrary ?? false
        runtime = shown.map { makeRuntime($0.skin) }
        skinView.runtime = runtime
        rebuildCompanions(shown?.skin)
        // The skin's load scripts read the player as it is (a theme by Night Mode, a restored track).
        refreshHostState()
        runtime?.start()
        let nativeOpens = carry(carried)
        fitWindow()
        // The main window may come on screen after the skin does.
        DispatchQueue.main.async { [weak self] in self?.updateCompanionVisibility() }
        // Up: the opens a launch restored, then NullPlayer's windows the skin draws none of, which
        // now open rather than wait.
        skinPresented = true
        let opens = opensAwaitingSkin
        opensAwaitingSkin = []
        opens.forEach { $0() }
        for list in nativeOpens { list == .playlist ? WindowManager.shared.showPlaylist() : WindowManager.shared.showMediaLibrary() }
    }

    // MARK: - Companion windows

    /// The skin's companion windows, made anew from `skin` (none for nil) on the running runtime.
    private func rebuildCompanions(_ skin: AIMPSkin?) {
        companions.rebuild(skin, runtime: runtime, like: skinView) { [weak self] in self?.updateCompanionVisibility() }
        updateCompanionVisibility()
    }

    /// Shows the companions the skin's state has visible (a key, a script, the menu) and hides the rest.
    private func updateCompanionVisibility() {
        guard let flow = runtime?.flow, let main = window else { return }
        companions.update(flow, beside: main)
    }

    // MARK: - The skin's own playlist and library (`SkinDrawnLists`)

    private static let lists: [SkinDrawnList] = [.playlist, .library]

    /// Whether `list` is open: the running skin's own window, else NullPlayer's.
    private func isOpen(_ list: SkinDrawnList) -> Bool {
        drawsOwnWindow(list) ? isShowingOwnWindow(list) : WindowManager.shared.isNativeWindowVisible(list)
    }

    /// Opens the incoming skin's playlist and library windows that are in `open` and closes the
    /// rest, closing NullPlayer's beside them. Returns the lists in `open` the skin draws none of,
    /// whose NullPlayer window is to open once the skin is up.
    private func carry(_ open: [SkinDrawnList]) -> [SkinDrawnList] {
        guard var state = runtime?.state else { return [] }
        var nativeOpens: [SkinDrawnList] = []
        for list in Self.lists {
            let own = ownWindows(list)
            if own.isEmpty {
                if open.contains(list), !WindowManager.shared.isNativeWindowVisible(list) { nativeOpens.append(list) }
                continue
            }
            for companion in own { state.script.visible[companion.name] = open.contains(list) }
            WindowManager.shared.closeNativeWindow(list)
        }
        runtime?.state = state
        return nativeOpens
    }

    /// The skin's windows standing for NullPlayer's `list`. An AIMP skin's equalizer is one of its
    /// companions, never a stand-in: NullPlayer's EQ window serves beside every skin.
    private func ownWindows(_ list: SkinDrawnList) -> [AIMPSkin.Companion] {
        runtime?.skin.companions(list == .playlist ? .playlist : .library) ?? []
    }

    func drawsOwnWindow(_ list: SkinDrawnList) -> Bool { !ownWindows(list).isEmpty }

    func isShowingOwnWindow(_ list: SkinDrawnList) -> Bool {
        guard let flow = runtime?.flow else { return false }
        return ownWindows(list).contains { flow.isVisible($0.name) }
    }

    /// A playlist or library show waits for the first skin.
    func deferUntilSkinLoads(_ open: @escaping () -> Void) -> Bool {
        guard !skinPresented else { return false }
        opensAwaitingSkin.append(open)
        return true
    }

    func revealOwnWindow(_ list: SkinDrawnList, toggle: Bool) {
        guard var state = runtime?.state else { return }
        let open = toggle ? !isShowingOwnWindow(list) : true
        for companion in ownWindows(list) { state.script.visible[companion.name] = open }
        runtime?.state = state
    }

    /// The companion windows, checked while shown, for the context menu (AIMP lists them in its own).
    private func companionMenuItems() -> [NSMenuItem] {
        guard let runtime else { return [] }
        return companions.menuItems(runtime.flow) { [weak runtime] name, visible in runtime?.state.script.visible[name] = visible }
    }

    func applyUIScale(_ scale: CGFloat) {
        let scale = max(0.1, scale)
        skinView.uiScale = scale
        fitWindow()
        companions.apply(scale: scale)
    }

    func mainWindowSize(atScale scale: CGFloat) -> NSSize? {
        let size = skinView.displaySize
        return NSSize(width: size.width * scale, height: size.height * scale)
    }

    /// Sizes the window to the form at the current scale, holding its top-left corner. The skin's
    /// windows docked under the deck move with its bottom edge (GX-F90's AMP key grows the deck
    /// over the playlist under it).
    private func fitWindow() {
        guard let window else { return }
        let old = window.frame
        AIMPSkinCompanionWindows.fit(window, to: skinView)
        companions.followBottomEdge(of: old, to: window.frame)
    }

    var managedAuxiliaryWindows: [NSWindow] { companions.all }

    // MARK: - Host state

    private func refreshHostState() {
        runtime?.update(player: currentPlayer())
    }

    /// The player now, with the playing track's artwork.
    private func currentPlayer() -> AIMPSkinPlayerSnapshot {
        engineHost.refreshPlaylist()
        var player = engineHost.snapshot()
        player.coverArt = coverArt
        return player
    }

    func updateTrackInfo(_ track: Track?) {
        engineHost.playbackDidChange()
        // A track's tags and duration can arrive after it was queued, under the same id.
        engineHost.playlistChanged()
        updateArtwork(for: track)
        refreshHostState()
    }

    /// The playing track's artwork, for the skin's cover-art displays, loaded once per track.
    private func updateArtwork(for track: Track?) {
        guard artworkTrackID != track?.id else { return }
        artworkTrackID = track?.id
        artworkTask?.cancel()
        coverArt = nil
        guard let track else { return refreshHostState() }
        artworkTask = Task { [weak self] in
            let image = await AIMPSkinArtworkLoader.loadArtwork(for: track)
            guard !Task.isCancelled, let self, self.artworkTrackID == track.id else { return }
            self.coverArt = image
            self.refreshHostState()
        }
    }
    func updateVideoTrackInfo(title: String, artworkTrack: Track?) {}
    func clearVideoTrackInfo() {}
    func updateTime(current: TimeInterval, duration: TimeInterval) { refreshHostState() }
    func updatePlaybackState() {
        engineHost.playbackDidChange()
        refreshHostState()
    }

    /// The playlist changed (added to, sorted, a row taken out): the skin's own list follows.
    /// A burst of playlist changes (a restore swaps thousands of streaming placeholders in one by
    /// one) refreshes once, after it.
    func playlistContentDidChange() {
        engineHost.playlistChanged()
        guard !playlistRefreshPending else { return }
        playlistRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            self?.playlistRefreshPending = false
            self?.refreshHostState()
        }
    }

    /// Show Artist / Show Album changed: the rows' text follows.
    func playlistMarkersDidChange() {
        engineHost.playlistChanged()
        refreshHostState()
    }

    func updateSpectrum(_ levels: [Float]) { runtime?.spectrum = levels.map { Double($0) } }

    func skinDidChange() {}
    func windowVisibilityDidChange() {
        runtime?.updateClock()
        refreshHostState()
        updateCompanionVisibility()
    }

    func prepareForUITeardown() {
        runtime?.stop()
        engineHost.stop()
        rebuildCompanions(nil)
        levelModel.stop()
        skinLoad.cancel()
    }

    // MARK: - Window delegate

    func windowDidChangeOcclusionState(_ notification: Notification) {
        runtime?.updateClock()
        updateCompanionVisibility()
    }

    func windowDidMove(_ notification: Notification) {
        guard let moved = notification.object as? NSWindow else { return }
        // A companion's drag has already gone through `windowWillMove`; running it again from here
        // would move its docked group a second time (as `WMPViewWindowMaterializer` notes).
        // Nor while it is being sized and placed off screen, before it shows.
        if moved !== window, WindowManager.shared.isWindowDragInProgress || !moved.isVisible { return }
        WindowManager.shared.applySnappedPosition(moved, to: WindowManager.shared.windowWillMove(moved, to: moved.frame.origin))
    }

    /// A companion brought forward brings the deck and the rest with it, as `.wmz` panels do.
    func windowDidBecomeKey(_ notification: Notification) {
        guard let key = notification.object as? NSWindow, key !== window else { return }
        DispatchQueue.main.async { [weak key] in
            guard let key, key.isKeyWindow else { return }
            WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: key)
        }
    }
}
