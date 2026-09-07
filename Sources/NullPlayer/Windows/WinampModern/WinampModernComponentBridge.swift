import AppKit
import Foundation
import NullPlayerCore

/// Production `WinampModernComponentHost` that bridges embedded skin components to real NullPlayer
/// state. It exposes only the typed playlist/EQ/library operations the Wasabi runtime needs; the
/// skin never gains filesystem, network, or arbitrary app access through this seam. Playlist and EQ
/// bind to the shared `AudioEngine`; unavailable surfaces fall back to the classic WindowManager
/// windows (the Phase 1 auxiliary-window policy) rather than failing.
final class WinampModernComponentBridge: WinampModernComponentHost {
    private let engine: AudioEngine
    private let browserVFS: WalVirtualFileSystem?
    private let eqLayout = EQConfiguration.classic10
    private var selectedRow = -1
    /// The multi-row selection `PE_SEL`/`PE_REM` work on. `selectedRow` is its anchor — a plain click
    /// collapses both to one row, which is what every other list in the app does.
    private var selectedRows: Set<Int> = []

    /// The `.wal` window's current UI Size, read live so a scale change needs no re-creation.
    ///
    /// This is only the **fallback** the embedded library uses before the view layer pushes it a
    /// resolved content scale (UI Size × Text Size). It cannot be the whole answer, because Text Size
    /// is resolved against the *hosting scene's* canvas and the bridge is shared by every window.
    var libraryContentScaleFallback: (() -> CGFloat)?
    /// How the embedded browser asks for the server-link sheet, since it has no classic controller.
    var linkSheetPresenter: (() -> Void)?
    private var librarySurface: WinampModernLibrarySurface?
    private var videoSurface: WinampModernVideoSurface?
    private var visualizationSurface: WinampModernVisualizationSurface?
    private var hostedWindowSurfaces: [WinampModernHostedWindowID: WinampModernHostedSurface] = [:]
    /// The visualization surface if one has been created, without creating one.
    var currentVisualizationSurface: WinampModernVisualizationSurface? { visualizationSurface }
    /// The video surface if one has been created, without creating one.
    var currentVideoSurface: WinampModernVideoSurface? { videoSurface }
    /// The surface if one has been created, without creating one — session restore must not
    /// instantiate a browser for a skin that never asked for it.
    var currentLibrarySurface: WinampModernLibrarySurface? { librarySurface }
    /// A future `WindowManager` route must be able to inspect a hosted adapter without creating it.
    func currentHostedWindowSurface(id: WinampModernHostedWindowID) -> WinampModernHostedSurface? {
        hostedWindowSurfaces[id]
    }
    var hostedWindowSurfaceContextProvider: ((WinampModernHostedWindowID)
        -> WinampModernHostedSurfaceContext)?

    init(engine: AudioEngine, browserVFS: WalVirtualFileSystem? = nil) {
        self.engine = engine
        self.browserVFS = browserVFS
    }

    // MARK: - Playlist

    func playlistSnapshot() -> WinampModernPlaylistSnapshot {
        let rows = engine.playlist.enumerated().map { index, track in
            WinampModernPlaylistRow(
                title: track.title,
                secondary: [track.artist, track.album].compactMap { $0 }.joined(separator: " — "),
                duration: track.duration ?? 0,
                isCurrent: index == engine.currentIndex,
                artist: track.artist ?? "",
                album: track.album ?? "",
                filePath: track.url.isFileURL ? track.url.path : track.url.absoluteString
            )
        }
        return WinampModernPlaylistSnapshot(rows: rows,
                                            currentIndex: engine.currentIndex,
                                            selectedIndex: selectedRow < rows.count ? selectedRow : -1,
                                            selectedRows: selectedRows.filter { $0 < rows.count })
    }

    func playlistSelect(row: Int) {
        guard row >= 0, row < engine.playlist.count else { return }
        selectedRow = row
        selectedRows = [row]
    }

    /// Move the selection onto the playing track, the way the classic and modern playlists do on
    /// `.audioTrackDidChange`: the drawn selection bar *is* the "now playing" indicator in skins
    /// whose palette names no distinct current-row colour, so leaving it behind on the previous row
    /// made every advance look like nothing had happened. Returns the row so the caller can scroll
    /// it into view, `nil` when there is no current track.
    @discardableResult
    func playlistFollowCurrentTrack() -> Int? {
        let index = engine.currentIndex
        guard index >= 0, index < engine.playlist.count else { return nil }
        selectedRow = index
        selectedRows = [index]
        return index
    }

    func playlistSetSelection(_ rows: Set<Int>) {
        let valid = rows.filter { $0 >= 0 && $0 < engine.playlist.count }
        selectedRows = valid
        // The anchor follows the selection: emptied by Select None, and pinned to the first row of
        // whatever Select All or Invert just produced, so Delete and the skin's own readouts have a
        // row to name.
        selectedRow = valid.min() ?? -1
    }

    func playlistRemoveRows(_ rows: Set<Int>) {
        let valid = Set(rows.filter { $0 >= 0 && $0 < engine.playlist.count })
        guard !valid.isEmpty else { return }
        let count = engine.playlist.count
        for row in WinampModernPlaylistSelection.removalOrder(valid) { engine.removeTrack(at: row) }
        selectedRow = WinampModernPlaylistSelection.selectionAfterRemoval(of: valid, count: count)
        selectedRows = selectedRow >= 0 ? [selectedRow] : []
    }

    func playlistPlay(row: Int) {
        guard row >= 0, row < engine.playlist.count else { return }
        selectedRow = row
        engine.playTrack(at: row)
    }

    /// `PlEdit.moveTo(from, to)`. Both indices name rows in the queue as it stands, and the engine
    /// carries `currentIndex` across the move, so the playing track keeps playing wherever it lands.
    func playlistMove(row: Int, to destination: Int) {
        let count = engine.playlist.count
        guard row >= 0, row < count, destination >= 0, destination < count, row != destination else { return }
        engine.moveTrack(from: row, to: destination)
        // The anchor follows the row it was on, so a script that moves a selection and then reads it
        // back is not left pointing at whatever slid into the vacated slot.
        if selectedRow == row {
            selectedRow = destination
            selectedRows = [destination]
        }
    }

    func playlistClear() {
        engine.clearPlaylist()
        selectedRow = -1
        selectedRows = []
    }

    /// `PlEdit.enqueueFile(path)` / `System.playFile(path)`. The runtime has already decided the URL
    /// is admissible; this only appends it and, for `playFile`, starts it.
    ///
    /// `AudioEngine.appendFiles` is deliberately not the route: it raises a modal alert for anything
    /// it rejects, and a skin's script is not a place a user asked a question from. The engine's own
    /// full validation still runs at playback time, so a file that passed the extension check and
    /// then turns out to be unplayable fails exactly where any other queued track would.
    func playlistAppend(mediaAt url: URL, play: Bool) {
        let row = engine.playlist.count
        engine.appendTracks([Track(lightweightURL: url)])
        guard play, row < engine.playlist.count else { return }
        selectedRow = row
        selectedRows = [row]
        engine.playTrack(at: row)
    }

    // MARK: - Saved playlists (`MLPlaylists`)

    /// The library's saved playlists, in its own sort order. Read fresh rather than cached: a skin
    /// builds its menu at the moment of the click, and a scan may have landed since the last one.
    func savedPlaylistNames() -> [String] {
        MediaLibrary.shared.playlistsSnapshot.map(\.title)
    }

    /// `MLPlaylists.playItem(i)` — the same thing the Media Library window's *Play Playlist* does.
    /// Parsing is off the main thread because a playlist file is disk I/O and this runs inside a
    /// menu pick; the queue swap goes back to the main actor.
    func playSavedPlaylist(at index: Int) {
        let playlists = MediaLibrary.shared.playlistsSnapshot
        guard playlists.indices.contains(index) else { return }
        let url = playlists[index].url
        Task.detached {
            let parsed: Playlist?
            switch url.pathExtension.lowercased() {
            case "m3u", "m3u8": parsed = try? Playlist.fromM3U(url: url)
            case "pls": parsed = try? Playlist.fromPLS(url: url)
            default: parsed = nil
            }
            guard let parsed, !parsed.trackURLs.isEmpty else { return }
            let tracks = parsed.trackURLs.map { trackURL in
                MediaLibrary.shared.findTrack(byURL: trackURL)?.toTrack() ?? Track(lightweightURL: trackURL)
            }
            await MainActor.run { [weak self] in
                self?.engine.playNow(tracks)
                self?.selectedRow = 0
                self?.selectedRows = [0]
            }
        }
    }

    func playlistRemove(row: Int) {
        guard row >= 0, row < engine.playlist.count else { return }
        engine.removeTrack(at: row)
        if selectedRow >= engine.playlist.count { selectedRow = engine.playlist.count - 1 }
        selectedRows = selectedRow >= 0 ? [selectedRow] : []
    }

    // MARK: - Equalizer (classic10)

    func equalizerSnapshot() -> WinampModernEQSnapshot {
        WinampModernEQSnapshot(
            bandGainsDB: (0..<eqLayout.bandCount).map { engine.getEQBand($0) },
            preampDB: engine.getPreamp(),
            enabled: engine.isEQEnabled(),
            auto: UserDefaults.standard.bool(forKey: "EQAutoEnabled"),
            presetNames: EQPreset.allPresets.map(\.name)
        )
    }

    func equalizerSetBandGainDB(_ band: Int, gainDB: Float) {
        engine.setEQBand(band, gain: gainDB)
    }

    func equalizerSetPreampDB(_ gainDB: Float) {
        engine.setPreamp(gainDB)
    }

    func equalizerSetEnabled(_ enabled: Bool) {
        engine.setEQEnabled(enabled)
    }

    func equalizerSetAuto(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "EQAutoEnabled")
        guard enabled, let genre = engine.currentTrack?.genre,
              let preset = EQPreset.forGenre(genre) else { return }
        applyPreset(preset)
    }

    func equalizerApplyPreset(named name: String) {
        guard let preset = EQPreset.allPresets.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else { return }
        applyPreset(preset)
    }

    private func applyPreset(_ preset: EQPreset) {
        engine.setPreamp(preset.preamp)
        for (index, gain) in preset.bands.enumerated() where index < eqLayout.bandCount {
            engine.setEQBand(index, gain: gain)
        }
    }

    // MARK: - Library

    /// The real library browser, embedded in the skin's own holder (Phase 13.8).
    ///
    /// The bridge owns it rather than the view layer, so it survives a layout switch that removes and
    /// re-adds the holder's subview, and so browse mode can be saved and restored through the
    /// provider protocol. One per skin: a second holder for the same component reuses this surface's
    /// state rather than opening a second browser against the same servers.
    func makeLibrarySurface() -> WinampModernLibrarySurface? {
        if let librarySurface { return librarySurface }
        let surface = WinampModernLibrarySurfaceView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 300),
            contentScaleFallback: { [weak self] in self?.libraryContentScaleFallback?() ?? 1 },
            presentLinkSheet: { [weak self] in self?.linkSheetPresenter?() })
        librarySurface = surface
        return surface
    }

    /// One non-persistent WebKit instance per `<browser>` object. The view layer owns it; the bridge
    /// supplies only the loaded skin's read-only VFS for local HTML and related resources.
    @MainActor
    func makeBrowserSurface(initialRequest: WinampModernBrowserRequest?) -> WinampModernBrowserSurface? {
        let surface = WinampModernBrowserSurfaceView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 300), vfs: browserVFS)
        if let initialRequest { surface.navigate(initialRequest) }
        return surface
    }

    /// Release the embedded browser. The view layer tears the surface down first; this only drops the
    /// bridge's own reference, and is safe to call twice.
    func releaseLibrarySurface() {
        librarySurface?.prepareForUITeardown()
        librarySurface = nil
    }

    // MARK: - Video

    /// The skin's video box, filled with the app's own video output (B20).
    ///
    /// One per skin, and owned here for the same two reasons the library surface is: it must survive
    /// a layout switch that removes and re-adds the holder's subview, and a second holder for the
    /// same component must reuse it rather than fight over the one video view the app has.
    func makeVideoSurface() -> WinampModernVideoSurface? {
        if let videoSurface { return videoSurface }
        let surface = WinampModernVideoSurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        videoSurface = surface
        return surface
    }

    /// Hand the video output back and drop the surface. The view layer tears the surface down first;
    /// this only drops the bridge's own reference, and is safe to call twice.
    func releaseVideoSurface() {
        videoSurface?.prepareForUITeardown()
        videoSurface = nil
    }

    // MARK: - Visualization

    /// The skin's AVS/visualization box, filled with the host's real visualization engine (B20a).
    ///
    /// One per skin, owned here for the library surface's reasons: it must survive a layout switch
    /// that removes and re-adds the holder's subview, and a second holder for the same component
    /// must reuse it rather than stand up a second OpenGL engine against the same audio.
    func makeVisualizationSurface() -> WinampModernVisualizationSurface? {
        if let visualizationSurface { return visualizationSurface }
        guard let surface = WinampModernVisualizationSurfaceView(
            surfaceFrame: NSRect(x: 0, y: 0, width: 320, height: 240)) else { return nil }
        visualizationSurface = surface
        return surface
    }

    /// Stop the engine and drop the surface. The view layer tears the surface down first; this only
    /// drops the bridge's own reference, and is safe to call twice.
    func releaseVisualizationSurface() {
        visualizationSurface?.prepareForUITeardown()
        visualizationSurface = nil
    }

    // MARK: - Hosted windows

    func makeHostedWindowSurface(id: WinampModernHostedWindowID) -> WinampModernHostedSurface? {
        if let surface = hostedWindowSurfaces[id] { return surface }
        guard let definition = WinampModernHostedWindowRegistry.entry(id: id),
              let makeSurface = definition.makeSurface,
              let context = hostedWindowSurfaceContextProvider?(id) else { return nil }
        let surface = makeSurface(context)
        hostedWindowSurfaces[id] = surface
        return surface
    }

    /// Hosted views own terminal teardown. The bridge only releases its cache afterwards so an
    /// adapter cannot receive `prepareForUITeardown()` twice during a skin switch.
    func releaseHostedWindowSurfaces() {
        hostedWindowSurfaces.removeAll()
        hostedWindowSurfaceContextProvider = nil
    }

    // MARK: - Classic-window fallback

    func toggleClassicWindow(for kind: WinampModernComponentKind) {
        switch kind {
        case .playlist: WindowManager.shared.togglePlaylist()
        case .equalizer: WindowManager.shared.toggleEqualizer()
        case .library: WindowManager.shared.togglePlexBrowser()
        // The skin declares no visualization window of its own: NullPlayer's is the fallback, the
        // same window the Visualizations menu opens.
        case .visualization: WindowManager.shared.toggleProjectM()
        // No standalone window to fall back to: the seeker exists only as a strip inside a
        // skin's own layout.
        case .video, .waveformSeeker, .other: break
        }
    }
}
