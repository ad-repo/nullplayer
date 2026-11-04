import AppKit

/// `AudioEngine` to `AIMPSkinPlayerSnapshot`, and an AIMP action or provider value back to NullPlayer.
/// Skins name AIMP's own actions (`acPlayerPlay`, `acMainExit`) and data providers (`prvVolume`);
/// each maps to the NullPlayer command that does the same thing. An action NullPlayer has no
/// equivalent for does nothing and is logged once.
///
/// `snapshot` only reads: it runs on the main thread about ten times a second, however often the
/// window asks. What changes between snapshots changes on the engine's events, as the window
/// controller passes them on:
/// - a track's start and finish are counted, and its library details looked up, when the track or
///   the play state changes (`playbackDidChange`);
/// - the playlist rows are rebuilt when the playlist changed (`playlistChanged`, `refreshPlaylist`);
/// - the skin's library window lists `librarySource`'s build of NullPlayer's library.
/// Anything that waits on the file system or the library's queue (file sizes, a track's library
/// details) is fetched on a background queue and published back through `onBackgroundUpdate`.
///
/// One per AIMP window controller, released with it: the library build, playlist rows, file sizes,
/// mute and track counts are that skin session's, not the app's.
@MainActor
final class AIMPSkinAudioEngineHost {
    private let engine: AudioEngine
    /// A background fetch finished, or the library or appearance changed: the host has more to show.
    private let onBackgroundUpdate: () -> Void
    /// The library as the skin's library window lists it.
    let librarySource: AIMPSkinLibrarySource
    private var appearanceObserver: NSKeyValueObservation?

    /// The track playing, nil while stopped, as last seen, and how many tracks have started and
    /// finished since the session began.
    private var lastTrack: URL?
    private var tracksStarted = 0
    private var tracksFinished = 0
    /// What only the library knows of the playing track, by its id.
    private var detailsTrack: Track.ID?
    private var details: (year: Int, size: Int64, rating: Int?)?

    /// The playlist's rows, and which build of them they are; `playlistDirty` until rebuilt after a change.
    private var playlistDirty = true
    private var playlistRows = AIMPSkinPlayerSnapshot.Playlist()
    private var playlistTextCache: [PlaylistKey: (title: String, seconds: Int)] = [:]
    private var fileSizes: [URL: Int64] = [:]
    /// Files whose size the background queue is reading now.
    private var sizing: Set<URL> = []

    private var mutedVolume: Float?
    /// Where the skin's effect knobs were left.
    private var otherValues: [String: Double] = [:]
    private var unmapped: Set<AIMPAction> = []

    /// The skin's library window follows NullPlayer's library (`librarySource`); its Night Mode
    /// follows the Mac's appearance as it changes.
    init(engine: AudioEngine, onBackgroundUpdate: @escaping () -> Void) {
        self.engine = engine
        self.onBackgroundUpdate = onBackgroundUpdate
        librarySource = AIMPSkinLibrarySource(onChange: onBackgroundUpdate)
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onBackgroundUpdate() } }
        }
        // The session begins with whatever is playing: a track already playing has started.
        playbackDidChange()
    }

    /// The session is over: stop following the library.
    func stop() {
        librarySource.stop()
        appearanceObserver = nil
    }

    /// The player now. Reads only what the engine and this host already hold.
    func snapshot() -> AIMPSkinPlayerSnapshot {
        var player = AIMPSkinPlayerSnapshot()
        player.nightMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch engine.state {
        case .stopped: player.playState = .stopped
        case .playing: player.playState = .playing
        case .paused: player.playState = .paused
        }
        let track = engine.currentTrack
        player.title = track?.title ?? ""
        player.artist = track?.artist ?? ""
        player.album = track?.album ?? ""
        player.bitrate = track?.bitrate ?? 0
        player.sampleRate = track?.sampleRate ?? 0
        player.channels = track?.channels ?? 0
        player.genre = track?.genre ?? ""
        player.fileType = track?.url.pathExtension.uppercased() ?? ""
        player.year = details?.year ?? 0
        player.fileSize = details?.size ?? 0
        player.rating = details?.rating
        player.volume = Double(engine.volume)
        player.balance = (Double(engine.balance) + 1) / 2
        let duration = engine.duration
        // Stopped is at the start in AIMP, whatever the engine last played to (Pioneer's tape
        // counter reads 000).
        let elapsed = engine.state == .stopped ? 0 : engine.currentTime
        player.position = duration.isFinite && duration > 0 ? min(1, max(0, elapsed / duration)) : 0
        player.elapsedSeconds = elapsed.isFinite && elapsed > 0 ? Int(elapsed) : 0
        player.durationSeconds = duration.isFinite && duration > 0 ? Int(duration) : 0
        let now = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        player.timeOfDay = (now.hour ?? 0) * 3_600 + (now.minute ?? 0) * 60 + (now.second ?? 0)
        player.shuffle = engine.shuffleEnabled
        player.repeatAll = engine.repeatEnabled
        player.stayOnTop = WindowManager.shared.isAlwaysOnTop
        player.muted = mutedVolume != nil
        player.eqEnabled = engine.isEQEnabled()
        player.playlistVisible = WindowManager.shared.isPlaylistVisible
        player.libraryVisible = WindowManager.shared.isMediaLibraryVisible
        player.equalizerVisible = WindowManager.shared.isEqualizerVisible
        player.visualizationVisible = WindowManager.shared.isSpectrumVisible
        player.otherValues = otherValues
        player.tracksStarted = tracksStarted
        player.tracksFinished = tracksFinished
        player.eqGains = (0..<engine.eqConfiguration.bandCount).map { Double(engine.getEQBand($0) + 12) / 24 }
        player.preamp = Double(engine.getPreamp() + 12) / 24
        player.speed = Double(engine.playbackSpeed) - 0.5
        player.playlist = playlistRows
        player.playlistIndex = engine.currentIndex
        player.library = librarySource.shown
        player.libraryScanning = MediaLibrary.shared.isScanning
        return player
    }

    // MARK: - The engine's events

    /// The track or the play state changed (`updateTrackInfo`, `updatePlaybackState`): a track
    /// starts when playback reaches a new one, and finishes when another replaces it or playback
    /// stops. A new track's library details are looked up.
    func playbackDidChange() {
        let track = engine.currentTrack
        let current = engine.state != .stopped ? track?.url : nil
        if current != lastTrack {
            if lastTrack != nil { tracksFinished += 1 }
            if current != nil { tracksStarted += 1 }
            lastTrack = current
        }
        guard track?.id != detailsTrack else { return }
        detailsTrack = track?.id
        details = nil
        guard let id = track?.id, let url = track?.url else { return }
        // What only the library knows (year, size, rating), looked up once per track, off main:
        // the library answers through its own queue, which a scan can hold.
        Self.background.async { [weak self] in
            let found = MediaLibrary.shared.findTrack(byURL: url)
                .map { (year: $0.year ?? 0, size: $0.fileSize, rating: $0.rating.map { ($0 + 1) / 2 }) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard self.detailsTrack == id, let found else { return }
                    self.details = found
                    self.onBackgroundUpdate()
                }
            }
        }
    }

    /// The playlist, a track's tags, or Show Artist / Show Album changed: the rows are rebuilt at
    /// the next `refreshPlaylist`, once for a burst of changes.
    func playlistChanged() { playlistDirty = true }

    /// Rebuilds the rows if the playlist changed since the last time, before a snapshot is taken.
    /// Each track's text is made once per key, so a change costs only the tracks it brings in;
    /// local files' sizes (for the totals) are read on the background queue and fill in after.
    func refreshPlaylist() {
        guard playlistDirty else { return }
        playlistDirty = false
        let fields = PlaylistRowFields.current
        var texts: [PlaylistKey: (title: String, seconds: Int)] = [:]
        var unsized: [URL] = []
        let rows = engine.playlist.map { track -> AIMPSkinPlayerSnapshot.Playlist.Row in
            let key = PlaylistKey(track, fields: fields)
            let text = texts[key] ?? playlistTextCache[key] ?? (fields.text(for: track),
                                                                track.duration.map { $0.isFinite && $0 > 0 ? Int($0) : 0 } ?? 0)
            texts[key] = text
            let bytes = fileSizes[track.url]
            if bytes == nil, track.url.isFileURL { unsized.append(track.url) }
            return .init(title: text.title, seconds: text.seconds, bytes: bytes ?? 0)
        }
        playlistTextCache = texts
        // A rebuild that changes nothing (a track change re-reads every row) is the same playlist.
        if rows != playlistRows.rows { playlistRows = .init(rows: rows, generation: playlistRows.generation + 1) }
        guard !unsized.isEmpty else { return }
        let pending = unsized.filter { sizing.insert($0).inserted }
        guard !pending.isEmpty else { return }
        Self.background.async { [weak self] in
            let sizes = pending.map { url in
                (url, ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for (url, size) in sizes {
                        self.fileSizes[url] = size
                        self.sizing.remove(url)
                    }
                    self.playlistDirty = true
                    self.onBackgroundUpdate()
                }
            }
        }
    }

    /// File-system reads and library lookups, in order, off the main thread.
    private static let background = DispatchQueue(label: "com.nullplayer.aimp-host", qos: .utility)

    /// A `PeppyMeterLevelModel` level, 0–100 (dB-linear above its `floor`), as the host's 0–1, which
    /// `pin` scales to AIMP's linear 0–145, where 100 is a meter's 0 dB mark. RMS at −8 dBFS, a loud
    /// master, reads 0 dB; the spectrum's mean, used before, held most needles in the red.
    static func meterLevel(_ volume: Double, floor: Double) -> Double {
        guard volume > 0 else { return 0 }
        let amplitude = pow(10, (floor - floor * volume / 100) / 20)
        return min(1, amplitude * 250 / 145)
    }

    private struct PlaylistKey: Hashable {
        var id: Track.ID
        var title: String
        var artist: String?
        var album: String?
        var duration: TimeInterval?
        var video: Bool
        var showArtist: Bool
        var showAlbum: Bool

        init(_ track: Track, fields: PlaylistRowFields) {
            id = track.id
            title = track.title
            artist = track.artist
            album = track.album
            duration = track.duration
            video = track.mediaType == .video
            showArtist = fields.showArtist
            showAlbum = fields.showAlbum
        }
    }

    /// Runs a command; `window` is the skin's, for the window actions. An AIMP action NullPlayer
    /// has no counterpart for is logged once.
    func perform(_ command: AIMPSkinCommand, window: NSWindow?) {
        if AIMPSkinTrace.actions { NSLog("[aimp/action] %@ at %.2f s", command.description, engine.currentTime) }
        switch command {
        case .action(let action): perform(action, window: window)
        case .seek(let seconds): seek(toSeconds: seconds)
        case .playLibraryTrack(let id):
            guard let track = librarySource.library?.tracks([id]).first?.toTrack() else { break }
            engine.appendTracks([track])
            engine.playTrack(at: engine.playlist.count - 1)
        case .removeRow(let index):
            if engine.playlist.indices.contains(index) { engine.removeTrack(at: index) }
        case .playRow(let index):
            if engine.playlist.indices.contains(index) { engine.playTrack(at: index) }
        case .volume(let volume): set(.volume, to: volume)
        // What scripts set: the EQ in dB, balance −1…1, speed as a multiplier, an effect knob 0–1.
        case .equalizerBand(let band, let dB): engine.setEQBand(band, gain: Float(dB))
        case .preamp(let dB): engine.setPreamp(Float(dB))
        case .balance(let balance): engine.balance = Float(min(1, max(-1, balance)))
        case .speed(let speed): engine.setPlaybackSpeed(Float(min(1.5, max(0.5, speed))))
        case .setValue(let provider, let value): set(provider, to: value)
        case .position(let fraction): seek(to: fraction)
        }
    }

    /// One of AIMP's named actions.
    private func perform(_ action: AIMPAction, window: NSWindow?) {
        switch action {
        // Play during playback starts the track again, as in AIMP: the decks' counter RESET keys
        // are bound to it while playing (Pioneer CT-F1000, Akai GX-77, Nakamichi BX).
        case .playerPlay: engine.state == .playing ? engine.seek(to: 0) : engine.play()
        case .playerPause: engine.state == .paused ? engine.play() : engine.pause()
        case .playerPlayPause: engine.state == .playing ? engine.pause() : engine.play()
        case .playerStop: engine.stop()
        case .playerPrevTrack: engine.previous()
        case .playerNextTrack: engine.next()
        case .playerShuffle, .playerShuffleMode: engine.shuffleEnabled.toggle()
        case .playerRepeat, .playerRepeatPlaylist, .playerRepeatTrack: engine.repeatEnabled.toggle()
        case .playerOpenFiles, .playlistAddFiles, .playerOpen: MenuActions.shared.openFile()
        case .mainExit: NSApp.terminate(nil)
        case .mainAbout: (NSApp.delegate as? AppDelegate)?.showAbout()
        // As NullPlayer's own minimize: a borderless window takes no `miniaturize` until it is
        // made miniaturizable, which this does, the skin's other windows going with it.
        case .mainMinimize: WindowManager.shared.miniaturizeAllManagedWindows()
        case .mainStayOnTop: WindowManager.shared.isAlwaysOnTop.toggle()
        case .equalizerSwitch: engine.setEQEnabled(!engine.isEQEnabled())
        case .mainOpenFiles: MenuActions.shared.openFile()
        case .mainDSPManager, .mainDSPManagerEQ: WindowManager.shared.toggleEqualizer()
        case .playerSeekForward, .playerSeekBackward:
            seek(toSeconds: engine.currentTime + (action == .playerSeekForward ? 5 : -5))
        case .playlistShow, .mainShowPlaylist: WindowManager.shared.togglePlaylist()
        case .mainShowMusicLibrary, .musicLibraryShow: WindowManager.shared.toggleMediaLibrary()
        case .equalizerShow, .mainShowEqualizer: WindowManager.shared.toggleEqualizer()
        case .visualizationShow: WindowManager.shared.toggleSpectrum()
        case .playableFileShowFileInfoAtCursor, .playlistFocusedItemShowQTE, .playableFileShowQTE:
            showTrackInfo(window: window)
        // The playing file: its tags (when the library has it), its folder, it or its tags copied.
        case .sendToTagEditor, .utilsTagEditor:
            guard let url = engine.currentTrack?.url else { break }
            Self.background.async { [weak self, weak window] in
                let track = MediaLibrary.shared.findTrack(byURL: url)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if let track { return EditTagsPanel(track: track).show() }
                        self?.showTrackInfo(window: window)
                    }
                }
            }
        case .playlistOpenFolderWithSelectedFile:
            if let url = engine.currentTrack?.url, url.isFileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .playableFileCopyInfoToClipboard:
            if let track = engine.currentTrack {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(track.displayTitle, forType: .string)
            }
        case .playableFileCopyFileToClipboard:
            if let url = engine.currentTrack?.url, url.isFileURL {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
            }
        // A twentieth of the range a press (TEAC CD-RW890's VOLUME − and +).
        case .playerVolumeUp, .playerVolumeDown:
            let step: Float = action == .playerVolumeUp ? 0.05 : -0.05
            engine.volume = min(1, max(0, engine.volume + step))
            mutedVolume = nil
        case .musicLibraryAddFiles: AIMPSkinLibrarySource.addFilesOrFolders()
        // NullPlayer has no mute: the volume goes to 0 and comes back. Not WMP's toggle
        // (`WMPAudioEngineHost`), which reads any volume of 0 as muted: AIMP's `acPlayerVolumeMute`
        // is on only while this mute holds, and moving the volume ends it (Denon Classic Style's
        // speakers script reads it before muting).
        case .playerVolumeMute:
            if let restore = mutedVolume {
                engine.volume = restore
                mutedVolume = nil
            } else {
                mutedVolume = engine.volume
                engine.volume = 0
            }
        default:
            if unmapped.insert(action).inserted { NSLog("AIMPSkin: no NullPlayer action for '%@'", action.name) }
        }
    }

    /// The playing track's tags, file and duration, as a sheet on the skin's window.
    private func showTrackInfo(window: NSWindow?) {
        guard let window, let track = engine.currentTrack else { return }
        let alert = NSAlert()
        alert.messageText = track.displayTitle
        alert.informativeText = ["Artist: \(track.artist ?? "Unknown")",
                                 "Album: \(track.album ?? "Unknown")",
                                 "Duration: \(track.formattedDuration)",
                                 track.url.isFileURL ? "Path: \(track.url.path)" : "URL: \(track.url.absoluteString)"]
            .joined(separator: "\n")
        alert.beginSheetModal(for: window)
    }

    /// A slider or knob dragged to `value` (0–1) on a provider.
    private func set(_ provider: AIMPSkinProvider?, to value: Double) {
        let value = min(1, max(0, value))
        switch provider {
        case .volume:
            engine.volume = Float(value)
            mutedVolume = nil
        case .balance: engine.balance = Float(value * 2 - 1)
        // A deck's pitch knob, and AIMP's speed and tempo, are NullPlayer's (tempo-preserving) speed,
        // held at 1× near the middle so it can be found again.
        case .speed:
            let speed = value + 0.5
            engine.setPlaybackSpeed(abs(speed - 1) < 0.03 ? 1 : Float(speed))
        case .preamp: engine.setPreamp(Float(value * 24 - 12))
        case .equalizerBand(let band): engine.setEQBand(band, gain: Float(value * 24 - 12))
        case .named(let name): otherValues[name] = value
        // A seek bar goes through `seek(to:)`; nothing else is bound to the position.
        case .position, nil: break
        }
    }

    /// A seek bar dragged to `fraction` of the track: its whole length, the end included.
    private func seek(to fraction: Double) {
        let duration = engine.duration
        guard duration.isFinite, duration > 0 else { return }
        engine.seek(to: min(1, max(0, fraction)) * duration)
    }

    /// A script's seek or a REW/FF step to `seconds`, held a second short of the end: a seek past it
    /// left the engine parked at the last frame with the REW/FF timers still winding. The track plays
    /// out from there and the next one starts.
    private func seek(toSeconds seconds: Double) {
        let duration = engine.duration
        let end = duration.isFinite && duration > 0 ? duration - 1 : .infinity
        engine.seek(to: max(0, min(end, seconds)))
    }
}
