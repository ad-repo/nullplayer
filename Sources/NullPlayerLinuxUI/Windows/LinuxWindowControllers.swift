#if os(Linux)
import Foundation
import NullPlayerCore
import CGTK4

class LinuxBaseWindowController {
    let window: LinuxWindowHandle?
    private(set) var isShadeMode: Bool = false

    init(title: String, width: Int32, height: Int32, subtitle: String? = nil) {
        let createdWindow = title.withCString { np_linux_ui_make_window($0, width, height) }
        window = createdWindow

        if let createdWindow, let subtitle {
            let panel = title.withCString { heading in
                subtitle.withCString { body in
                    np_linux_ui_make_placeholder_panel(heading, body)
                }
            }
            if let panel {
                np_linux_ui_window_set_child(createdWindow, panel)
            }
        }
    }

    func showWindow(_ sender: Any?) {
        _ = sender
        guard let window else { return }
        np_linux_ui_window_present(window)
    }

    func hideWindow() {
        guard let window else { return }
        np_linux_ui_window_hide(window)
    }

    func windowIsVisible() -> Bool {
        guard let window else { return false }
        return np_linux_ui_window_is_visible(window) != 0
    }

    func setShadeMode(_ enabled: Bool) {
        isShadeMode = enabled
    }
}

final class LinuxMainWindowController: LinuxBaseWindowController, MainWindowProviding {
    weak var transportCommands: (any LinuxTransportCommanding)? {
        didSet { syncFromCommands() }
    }
    weak var windowCommands: (any LinuxWindowVisibilityCommanding)?
    weak var outputCommands: (any LinuxOutputDeviceCommanding)? {
        didSet { updateOutputLabel() }
    }
    weak var dialogPresenter: (any LinuxDialogPresenting)?

    var windowVisibilityProvider: ((LinuxWindowKind) -> Bool)? {
        didSet { updateWindowToggleStates() }
    }

    var setWindowVisibility: ((LinuxWindowKind, Bool) -> Void)?

    private var mainPanel: UnsafeMutableRawPointer?
    private var currentTrack: Track?
    private var videoTitle: String?
    private var currentDuration: TimeInterval = 0

    init() {
        super.init(
            title: "NullPlayer Linux: Main Player",
            width: 980,
            height: 640,
            subtitle: nil
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let panel = np_linux_ui_make_main_panel(
            userData,
            np_linux_ui_main_action_bridge,
            np_linux_ui_main_toggle_bridge,
            np_linux_ui_main_seek_bridge,
            np_linux_ui_main_volume_bridge,
            np_linux_ui_main_drop_bridge
        )
        mainPanel = panel

        if let window, let panel, let panelWidget = np_linux_ui_main_panel_widget(panel) {
            np_linux_ui_window_set_child(window, panelWidget)
        }

        syncFromCommands()
    }

    var isWindowVisible: Bool { windowIsVisible() }

    func updateTrackInfo(_ track: Track?) {
        currentTrack = track
        updateTrackLabel()
    }

    func updateVideoTrackInfo(title: String) {
        videoTitle = title
        updateTrackLabel()
    }

    func clearVideoTrackInfo() {
        videoTitle = nil
        updateTrackLabel()
    }

    func updateTime(current: TimeInterval, duration: TimeInterval) {
        guard let panel = mainPanel else { return }
        currentDuration = duration
        np_linux_ui_main_panel_set_seek_range(panel, duration)
        np_linux_ui_main_panel_set_seek_value(panel, current)
        np_linux_ui_main_panel_set_time(panel, current, duration)
    }

    func updatePlaybackState() {
        guard let panel = mainPanel else { return }
        let status = playbackStateLabel(transportCommands?.playbackState ?? .stopped)
        status.withCString { np_linux_ui_main_panel_set_status(panel, $0) }
    }

    func updateSpectrum(_ levels: [Float]) {
        guard let panel = mainPanel else { return }
        guard !levels.isEmpty else {
            "Mini visualization: no data".withCString {
                np_linux_ui_main_panel_set_spectrum_summary(panel, $0)
            }
            return
        }

        let peak = levels.max() ?? 0
        let normalized = max(0, min(1, peak))
        let summary = String(format: "Mini visualization peak: %d%%", Int(normalized * 100))
        summary.withCString {
            np_linux_ui_main_panel_set_spectrum_summary(panel, $0)
        }
    }

    func toggleShadeMode() {
        setShadeMode(!isShadeMode)
    }

    func skinDidChange() {}

    func windowVisibilityDidChange() {
        updateWindowToggleStates()
    }

    func setNeedsDisplay() {
        updatePlaybackState()
        updateTrackLabel()
    }

    func handleMainAction(_ action: Int32) {
        switch Int(action) {
        case NP_LINUX_UI_MAIN_ACTION_PREVIOUS:
            transportCommands?.previous()
        case NP_LINUX_UI_MAIN_ACTION_PLAY:
            transportCommands?.play()
        case NP_LINUX_UI_MAIN_ACTION_PAUSE:
            transportCommands?.pause()
        case NP_LINUX_UI_MAIN_ACTION_STOP:
            transportCommands?.stop()
        case NP_LINUX_UI_MAIN_ACTION_NEXT:
            transportCommands?.next()
        case NP_LINUX_UI_MAIN_ACTION_OPEN_FILES:
            openFiles()
        case NP_LINUX_UI_MAIN_ACTION_OPEN_FOLDER:
            openFolder()
        case NP_LINUX_UI_MAIN_ACTION_CYCLE_OUTPUT:
            cycleOutputDevice()
        case NP_LINUX_UI_MAIN_ACTION_TOGGLE_PLAY_PAUSE:
            togglePlayPause()
        case NP_LINUX_UI_MAIN_ACTION_SEEK_BACKWARD:
            transportCommands?.seekBy(seconds: -5)
        case NP_LINUX_UI_MAIN_ACTION_SEEK_FORWARD:
            transportCommands?.seekBy(seconds: 5)
        default:
            break
        }

        syncFromCommands()
    }

    func handleMainToggle(_ toggleID: Int32, enabled: Bool) {
        switch Int(toggleID) {
        case NP_LINUX_UI_MAIN_TOGGLE_SHUFFLE:
            transportCommands?.shuffleEnabled = enabled
        case NP_LINUX_UI_MAIN_TOGGLE_REPEAT:
            transportCommands?.repeatEnabled = enabled
        case NP_LINUX_UI_MAIN_TOGGLE_EQUALIZER:
            setWindowVisibility?(.equalizer, enabled)
        case NP_LINUX_UI_MAIN_TOGGLE_PLAYLIST:
            setWindowVisibility?(.playlist, enabled)
        case NP_LINUX_UI_MAIN_TOGGLE_LIBRARY:
            setWindowVisibility?(.libraryBrowser, enabled)
        case NP_LINUX_UI_MAIN_TOGGLE_SPECTRUM:
            setWindowVisibility?(.spectrum, enabled)
        case NP_LINUX_UI_MAIN_TOGGLE_WAVEFORM:
            setWindowVisibility?(.waveform, enabled)
        case NP_LINUX_UI_MAIN_TOGGLE_PROJECTM:
            setWindowVisibility?(.projectM, enabled)
        default:
            break
        }

        syncFromCommands()
        updateWindowToggleStates()
    }

    func handleSeekChanged(_ value: Double) {
        transportCommands?.seek(to: max(0, min(value, currentDuration > 0 ? currentDuration : value)))
    }

    func handleVolumeChanged(_ value: Double) {
        transportCommands?.volume = Float(max(0, min(1, value)))
    }

    func handleDroppedPayload(_ payload: String) {
        let urls = payload
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { line -> URL? in
                if let url = URL(string: line), url.scheme != nil {
                    return url
                }
                if line.hasPrefix("/") {
                    return URL(fileURLWithPath: line)
                }
                return nil
            }

        guard !urls.isEmpty else { return }
        transportCommands?.loadFiles(urls)
    }

    private func syncFromCommands() {
        guard let panel = mainPanel else { return }

        np_linux_ui_main_panel_set_volume_value(panel, Double(transportCommands?.volume ?? 0.2))
        np_linux_ui_main_panel_set_toggle_state(panel, Int32(NP_LINUX_UI_MAIN_TOGGLE_SHUFFLE), (transportCommands?.shuffleEnabled ?? false) ? 1 : 0)
        np_linux_ui_main_panel_set_toggle_state(panel, Int32(NP_LINUX_UI_MAIN_TOGGLE_REPEAT), (transportCommands?.repeatEnabled ?? false) ? 1 : 0)

        updateOutputLabel()
        updateWindowToggleStates()
        updatePlaybackState()
        updateTrackLabel()
    }

    private func updateTrackLabel() {
        guard let panel = mainPanel else { return }

        let text: String
        if let videoTitle, !videoTitle.isEmpty {
            text = videoTitle
        } else if let currentTrack {
            text = currentTrack.displayTitle
        } else {
            text = "No track loaded"
        }

        text.withCString {
            np_linux_ui_main_panel_set_track_title(panel, $0)
        }
    }

    private func playbackStateLabel(_ state: PlaybackState) -> String {
        switch state {
        case .stopped:
            return "Stopped"
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        }
    }

    private func updateWindowToggleStates() {
        guard let panel = mainPanel, let windowVisibilityProvider else { return }

        np_linux_ui_main_panel_set_toggle_state(panel, Int32(NP_LINUX_UI_MAIN_TOGGLE_EQUALIZER), windowVisibilityProvider(.equalizer) ? 1 : 0)
        np_linux_ui_main_panel_set_toggle_state(panel, Int32(NP_LINUX_UI_MAIN_TOGGLE_PLAYLIST), windowVisibilityProvider(.playlist) ? 1 : 0)
        np_linux_ui_main_panel_set_toggle_state(panel, Int32(NP_LINUX_UI_MAIN_TOGGLE_LIBRARY), windowVisibilityProvider(.libraryBrowser) ? 1 : 0)
        np_linux_ui_main_panel_set_toggle_state(panel, Int32(NP_LINUX_UI_MAIN_TOGGLE_SPECTRUM), windowVisibilityProvider(.spectrum) ? 1 : 0)
        np_linux_ui_main_panel_set_toggle_state(panel, Int32(NP_LINUX_UI_MAIN_TOGGLE_WAVEFORM), windowVisibilityProvider(.waveform) ? 1 : 0)
        np_linux_ui_main_panel_set_toggle_state(panel, Int32(NP_LINUX_UI_MAIN_TOGGLE_PROJECTM), windowVisibilityProvider(.projectM) ? 1 : 0)
    }

    private func openFiles() {
        let selected = dialogPresenter?.pickFiles(allowMultiple: true) ?? []
        guard !selected.isEmpty else { return }
        transportCommands?.loadFiles(selected)
    }

    private func openFolder() {
        guard let folder = dialogPresenter?.pickDirectory() else { return }
        transportCommands?.loadFolder(folder)
    }

    private func togglePlayPause() {
        guard let transportCommands else { return }
        if transportCommands.playbackState == .playing {
            transportCommands.pause()
        } else {
            transportCommands.play()
        }
    }

    private func cycleOutputDevice() {
        outputCommands?.refreshOutputDevices()
        guard let outputCommands else { return }

        let devices = outputCommands.outputDevices
        guard !devices.isEmpty else {
            updateOutputLabel()
            return
        }

        let selectedID = outputCommands.currentOutputDevice?.persistentID
        let currentIndex = devices.firstIndex(where: { $0.persistentID == selectedID }) ?? -1
        let nextIndex = (currentIndex + 1) % devices.count
        _ = outputCommands.selectOutputDevice(persistentID: devices[nextIndex].persistentID)
        updateOutputLabel()
    }

    private func updateOutputLabel() {
        guard let panel = mainPanel else { return }

        let label: String
        if let outputName = outputCommands?.currentOutputDevice?.name {
            label = "Output: \(outputName)"
        } else {
            label = "Output: Default"
        }

        label.withCString {
            np_linux_ui_main_panel_set_output_label(panel, $0)
        }
    }
}

final class LinuxPlaylistWindowController: LinuxBaseWindowController, PlaylistWindowProviding {
    weak var playlistCommands: (any LinuxPlaylistCommanding)?
    weak var transportCommands: (any LinuxTransportCommanding)?
    weak var dialogPresenter: (any LinuxDialogPresenting)?

    private var playlistPanel: UnsafeMutableRawPointer?
    private var marqueeTick: Int = 0
    private var lastMarqueeSecond: Int = -1

    init() {
        super.init(
            title: "NullPlayer Linux: Playlist",
            width: 720,
            height: 420,
            subtitle: nil
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let panel = np_linux_ui_make_playlist_panel(
            userData,
            np_linux_ui_playlist_action_bridge,
            np_linux_ui_playlist_drop_bridge
        )
        playlistPanel = panel

        if let window, let panel, let panelWidget = np_linux_ui_playlist_panel_widget(panel) {
            np_linux_ui_window_set_child(window, panelWidget)
        }
    }

    override func showWindow(_ sender: Any?) {
        reloadPlaylist()
        super.showWindow(sender)
    }

    func skinDidChange() {}

    func reloadPlaylist() {
        guard let panel = playlistPanel else { return }

        np_linux_ui_playlist_panel_begin_update(panel)

        let playlist = playlistCommands?.playlist ?? []
        let currentIndex = playlistCommands?.currentIndex ?? -1

        for (index, track) in playlist.enumerated() {
            let marker = track.mediaType == .video ? "[VID] " : ""
            let title = "\(marker)\(track.displayTitle)"
            let renderedTitle = marqueeTitle(title, isCurrent: index == currentIndex)
            let prefix = index == currentIndex ? "▶ " : ""
            let row = "\(prefix)\(renderedTitle) (\(track.formattedDuration))"
            row.withCString {
                np_linux_ui_playlist_panel_append_track(panel, $0, index == currentIndex ? 1 : 0)
            }
        }

        np_linux_ui_playlist_panel_finish_update(panel, Int32(currentIndex))
    }

    func handlePlaylistAction(_ action: Int32, index: Int32) {
        switch Int(action) {
        case NP_LINUX_UI_PLAYLIST_ACTION_ADD_FILES:
            let files = dialogPresenter?.pickFiles(allowMultiple: true) ?? []
            guard !files.isEmpty else { break }
            transportCommands?.appendFiles(files)
        case NP_LINUX_UI_PLAYLIST_ACTION_ADD_DIRECTORY:
            guard let folder = dialogPresenter?.pickDirectory() else { break }
            appendDirectory(folder)
        case NP_LINUX_UI_PLAYLIST_ACTION_ADD_URL:
            appendURLFromDialog()
        case NP_LINUX_UI_PLAYLIST_ACTION_PLAY_SELECTED:
            let selectedIndex = index >= 0 ? Int(index) : primarySelectedIndex()
            guard let selectedIndex else { break }
            playlistCommands?.playTrack(at: selectedIndex)
        case NP_LINUX_UI_PLAYLIST_ACTION_REMOVE_SELECTED:
            let indices = selectedIndices()
            if !indices.isEmpty {
                removeTracks(at: indices)
            } else if index >= 0 {
                playlistCommands?.removeTrack(at: Int(index))
            }
        case NP_LINUX_UI_PLAYLIST_ACTION_CROP_SELECTION:
            let indices = selectedIndices()
            if !indices.isEmpty {
                cropSelection(selectedIndices: indices)
            } else if index >= 0 {
                cropSelection(selectedIndices: [Int(index)])
            }
        case NP_LINUX_UI_PLAYLIST_ACTION_CLEAR:
            playlistCommands?.clearPlaylist()
        case NP_LINUX_UI_PLAYLIST_ACTION_SHUFFLE,
             NP_LINUX_UI_PLAYLIST_ACTION_RANDOMIZE:
            playlistCommands?.shufflePlaylist()
        case NP_LINUX_UI_PLAYLIST_ACTION_REVERSE:
            playlistCommands?.reversePlaylist()
        case NP_LINUX_UI_PLAYLIST_ACTION_SORT_TITLE:
            playlistCommands?.sort(by: .title, ascending: true)
        case NP_LINUX_UI_PLAYLIST_ACTION_SORT_ARTIST:
            playlistCommands?.sort(by: .artist, ascending: true)
        case NP_LINUX_UI_PLAYLIST_ACTION_SORT_ALBUM:
            playlistCommands?.sort(by: .album, ascending: true)
        case NP_LINUX_UI_PLAYLIST_ACTION_SORT_FILENAME:
            playlistCommands?.sort(by: .filename, ascending: true)
        case NP_LINUX_UI_PLAYLIST_ACTION_SORT_PATH:
            playlistCommands?.sort(by: .path, ascending: true)
        case NP_LINUX_UI_PLAYLIST_ACTION_REMOVE_DEAD_FILES:
            removeDeadFiles()
        case NP_LINUX_UI_PLAYLIST_ACTION_FILE_INFO:
            let selectedIndex = index >= 0 ? Int(index) : primarySelectedIndex()
            guard let selectedIndex else { break }
            showInfoForSelectedTrack(index: selectedIndex)
        case NP_LINUX_UI_PLAYLIST_ACTION_NEW_PLAYLIST:
            playlistCommands?.clearPlaylist()
        case NP_LINUX_UI_PLAYLIST_ACTION_SAVE_PLAYLIST:
            savePlaylist()
        case NP_LINUX_UI_PLAYLIST_ACTION_LOAD_PLAYLIST:
            loadPlaylist()
        default:
            break
        }

        reloadPlaylist()
    }

    func updateCurrentTrackMarquee(currentTime: TimeInterval) {
        let currentSecond = max(0, Int(currentTime))
        guard currentSecond != lastMarqueeSecond else { return }
        lastMarqueeSecond = currentSecond
        marqueeTick &+= 1
        reloadPlaylist()
    }

    func handlePlaylistDropPayload(_ payload: String) {
        let urls = payload
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { line -> URL? in
                if let url = URL(string: line), url.scheme != nil {
                    return url
                }
                if line.hasPrefix("/") {
                    return URL(fileURLWithPath: line)
                }
                return nil
            }

        guard !urls.isEmpty else { return }
        transportCommands?.appendFiles(urls)
        reloadPlaylist()
    }

    private func appendDirectory(_ directory: URL) {
        let discovered = LocalFileDiscovery.discoverMedia(
            from: [directory],
            recursiveDirectories: true,
            includeVideo: false
        )
        let urls = discovered.audioFiles.map(\.url)
        guard !urls.isEmpty else { return }
        transportCommands?.appendFiles(urls)
    }

    private func appendURLFromDialog() {
        guard let text = dialogPresenter?.requestURLInput(title: "Add URL", placeholder: "https://example.com/stream"),
              let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        transportCommands?.appendTracks([Track(url: url)])
    }

    private func cropSelection(selectedIndex: Int) {
        cropSelection(selectedIndices: [selectedIndex])
    }

    private func cropSelection(selectedIndices: [Int]) {
        guard let playlistCommands else { return }
        let count = playlistCommands.playlist.count
        let keep = Set(selectedIndices.filter { $0 >= 0 && $0 < count })
        guard !keep.isEmpty else { return }

        for index in stride(from: count - 1, through: 0, by: -1) where !keep.contains(index) {
            playlistCommands.removeTrack(at: index)
        }
    }

    private func removeDeadFiles() {
        guard let playlistCommands else { return }

        let playlist = playlistCommands.playlist
        for index in stride(from: playlist.count - 1, through: 0, by: -1) {
            let track = playlist[index]
            guard track.url.isFileURL else { continue }
            if !FileManager.default.fileExists(atPath: track.url.path) {
                playlistCommands.removeTrack(at: index)
            }
        }
    }

    private func showInfoForSelectedTrack(index: Int) {
        guard let dialogPresenter,
              let playlistCommands,
              index >= 0,
              index < playlistCommands.playlist.count else {
            return
        }

        let track = playlistCommands.playlist[index]
        let artist = track.artist ?? "Unknown Artist"
        let album = track.album ?? "Unknown Album"
        let message = "Title: \(track.title)\nArtist: \(artist)\nAlbum: \(album)\nPath: \(track.url.path)"
        dialogPresenter.showInfo(title: "Track Info", message: message)
    }

    private func savePlaylist() {
        guard let destination = dialogPresenter?.requestSaveURL(suggestedName: "playlist.m3u"),
              let playlistCommands else {
            return
        }

        let body = playlistCommands.playlist.map { $0.url.absoluteString }.joined(separator: "\n")
        try? body.write(to: destination, atomically: true, encoding: .utf8)
    }

    private func loadPlaylist() {
        guard let playlistURL = dialogPresenter?.pickFiles(allowMultiple: false).first,
              let contents = try? String(contentsOf: playlistURL, encoding: .utf8) else {
            return
        }

        let baseDirectory = playlistURL.deletingLastPathComponent()
        let urls: [URL] = contents
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { line in
                if let parsed = URL(string: line), parsed.scheme != nil {
                    return parsed
                }
                if line.hasPrefix("/") {
                    return URL(fileURLWithPath: line)
                }
                return URL(fileURLWithPath: line, relativeTo: baseDirectory).standardizedFileURL
            }

        guard !urls.isEmpty else { return }
        transportCommands?.loadFiles(urls)
    }

    private func removeTracks(at indices: [Int]) {
        guard let playlistCommands else { return }
        for index in Set(indices).sorted(by: >) {
            playlistCommands.removeTrack(at: index)
        }
    }

    private func primarySelectedIndex() -> Int? {
        selectedIndices().sorted().first
    }

    private func selectedIndices() -> [Int] {
        guard let panel = playlistPanel else { return [] }
        var buffer = Array(repeating: Int32(0), count: 1024)
        let count = np_linux_ui_playlist_panel_selected_indices(panel, &buffer, Int32(buffer.count))
        guard count > 0 else { return [] }
        return buffer.prefix(Int(count)).map(Int.init)
    }

    private func marqueeTitle(_ title: String, isCurrent: Bool) -> String {
        let windowSize = 42
        guard isCurrent, title.count > windowSize else { return title }

        let spacer = "   "
        let stream = title + spacer + title
        let cycleLength = title.count + spacer.count
        let safeOffset = marqueeTick % cycleLength

        let start = stream.index(stream.startIndex, offsetBy: safeOffset)
        let end = stream.index(start, offsetBy: windowSize)
        return String(stream[start..<end])
    }
}

final class LinuxLibraryBrowserWindowController: LinuxBaseWindowController, LibraryBrowserWindowProviding {
    private let dataProvider = LinuxLibraryBrowserDataProvider()
    weak var transportCommands: (any LinuxTransportCommanding)?
    private(set) var lastSnapshot = LinuxLibraryBrowserSnapshot(
        source: .local,
        browseMode: .artists,
        sort: .nameAsc,
        artists: [],
        albums: [],
        searchResults: []
    )

    init() {
        super.init(
            title: "NullPlayer Linux: Library Browser",
            width: 820,
            height: 640,
            subtitle: "Library browser placeholder window."
        )
        reloadData()
    }

    var browseModeRawValue: Int {
        get { dataProvider.snapshot.browseMode.rawValue }
        set {
            dataProvider.setBrowseMode(rawValue: newValue)
            reloadData()
        }
    }

    func skinDidChange() {}

    func reloadData() {
        dataProvider.reload()
        lastSnapshot = dataProvider.snapshot
        updateWindowTitle()
    }

    func showLinkSheet() {}

    func setSearchQuery(_ query: String) {
        dataProvider.setSearchQuery(query)
        reloadData()
    }

    func setSort(_ sort: ModernBrowserSortOption) {
        dataProvider.setSort(sort)
        reloadData()
    }

    func addWatchFolder(_ url: URL) {
        dataProvider.addWatchFolder(url)
        reloadData()
    }

    func removeWatchFolder(path: String) {
        dataProvider.removeWatchFolder(path: path)
        reloadData()
    }

    func addFiles(_ urls: [URL]) {
        dataProvider.addFiles(urls)
        reloadData()
    }

    func clearLocalLibrary() {
        dataProvider.clearLocalLibrary()
        reloadData()
    }

    func playTracks(_ tracks: [LibraryTrack]) {
        let playbackTracks = tracks.map { $0.toTrack() }
        transportCommands?.loadTracks(playbackTracks)
    }

    func enqueueTracks(_ tracks: [LibraryTrack]) {
        let playbackTracks = tracks.map { $0.toTrack() }
        transportCommands?.appendTracks(playbackTracks)
    }

    func playAlbum(albumId: String) {
        playTracks(dataProvider.tracksForAlbum(albumId))
    }

    func enqueueAlbum(albumId: String) {
        enqueueTracks(dataProvider.tracksForAlbum(albumId))
    }

    func playArtist(_ artistName: String) {
        playTracks(dataProvider.tracksForArtist(artistName))
    }

    func enqueueArtist(_ artistName: String) {
        enqueueTracks(dataProvider.tracksForArtist(artistName))
    }

    private func updateWindowTitle() {
        guard let window else { return }
        let title = "NullPlayer Linux: Library Browser (\(lastSnapshot.artists.count) artists, \(lastSnapshot.albums.count) albums)"
        title.withCString { np_linux_ui_window_set_title(window, $0) }
    }
}

final class LinuxEQWindowController: LinuxBaseWindowController, EQWindowProviding {
    init() {
        super.init(
            title: "NullPlayer Linux: Equalizer",
            width: 440,
            height: 220,
            subtitle: "Equalizer placeholder window."
        )
    }

    func skinDidChange() {}
}

final class LinuxSpectrumWindowController: LinuxBaseWindowController, SpectrumWindowProviding {
    init() {
        super.init(
            title: "NullPlayer Linux: Spectrum",
            width: 720,
            height: 360,
            subtitle: "Spectrum placeholder window."
        )
    }

    func skinDidChange() {}

    func stopRenderingForHide() {}
}

final class LinuxWaveformWindowController: LinuxBaseWindowController, WaveformWindowProviding {
    private var currentTrack: Track?

    init() {
        super.init(
            title: "NullPlayer Linux: Waveform",
            width: 720,
            height: 260,
            subtitle: "Waveform placeholder window."
        )
    }

    func skinDidChange() {}

    func updateTrack(_ track: Track?) {
        currentTrack = track
    }

    func updateTime(current: TimeInterval, duration: TimeInterval) {
        _ = (current, duration)
    }

    func reloadWaveform(force: Bool) {
        _ = force
    }

    func stopLoadingForHide() {}
}

final class LinuxProjectMWindowController: LinuxBaseWindowController, ProjectMWindowProviding {
    var isFullscreen: Bool = false
    var isPresetLocked: Bool = false
    var isProjectMAvailable: Bool = false
    var currentPresetName: String = "Unavailable"
    var currentPresetIndex: Int = 0
    var presetCount: Int = 0
    var presetsInfo: (bundledCount: Int, customCount: Int, customPath: String?) = (0, 0, nil)

    init() {
        super.init(
            title: "NullPlayer Linux: projectM",
            width: 880,
            height: 520,
            subtitle: "projectM placeholder window. Capability gate is pending Linux projectM integration."
        )
    }

    func skinDidChange() {}

    func stopRenderingForHide() {}

    func toggleFullscreen() {
        isFullscreen.toggle()
    }

    func nextPreset(hardCut: Bool) {
        _ = hardCut
    }

    func previousPreset(hardCut: Bool) {
        _ = hardCut
    }

    func selectPreset(at index: Int, hardCut: Bool) {
        _ = (index, hardCut)
    }

    func randomPreset(hardCut: Bool) {
        _ = hardCut
    }

    func reloadPresets() {}
}

@_cdecl("np_linux_ui_main_action_bridge")
private func np_linux_ui_main_action_bridge(_ action: Int32, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let controller = Unmanaged<LinuxMainWindowController>.fromOpaque(userData).takeUnretainedValue()
    controller.handleMainAction(action)
}

@_cdecl("np_linux_ui_main_toggle_bridge")
private func np_linux_ui_main_toggle_bridge(_ toggleID: Int32, _ enabled: Int32, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let controller = Unmanaged<LinuxMainWindowController>.fromOpaque(userData).takeUnretainedValue()
    controller.handleMainToggle(toggleID, enabled: enabled != 0)
}

@_cdecl("np_linux_ui_main_seek_bridge")
private func np_linux_ui_main_seek_bridge(_ value: Double, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let controller = Unmanaged<LinuxMainWindowController>.fromOpaque(userData).takeUnretainedValue()
    controller.handleSeekChanged(value)
}

@_cdecl("np_linux_ui_main_volume_bridge")
private func np_linux_ui_main_volume_bridge(_ value: Double, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let controller = Unmanaged<LinuxMainWindowController>.fromOpaque(userData).takeUnretainedValue()
    controller.handleVolumeChanged(value)
}

@_cdecl("np_linux_ui_main_drop_bridge")
private func np_linux_ui_main_drop_bridge(_ payload: UnsafePointer<CChar>?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData, let payload else { return }
    let controller = Unmanaged<LinuxMainWindowController>.fromOpaque(userData).takeUnretainedValue()
    controller.handleDroppedPayload(String(cString: payload))
}

@_cdecl("np_linux_ui_playlist_action_bridge")
private func np_linux_ui_playlist_action_bridge(_ action: Int32, _ index: Int32, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let controller = Unmanaged<LinuxPlaylistWindowController>.fromOpaque(userData).takeUnretainedValue()
    controller.handlePlaylistAction(action, index: index)
}

@_cdecl("np_linux_ui_playlist_drop_bridge")
private func np_linux_ui_playlist_drop_bridge(_ payload: UnsafePointer<CChar>?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData, let payload else { return }
    let controller = Unmanaged<LinuxPlaylistWindowController>.fromOpaque(userData).takeUnretainedValue()
    controller.handlePlaylistDropPayload(String(cString: payload))
}
#endif
