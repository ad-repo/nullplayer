import Foundation

private enum CLIPlayerError: LocalizedError {
    case videoRequiresCast
    case unknownCastType(String)
    case castDeviceNotFound(String, [String])
    case sonosVideoUnsupported

    var errorDescription: String? {
        switch self {
        case .videoRequiresCast:
            return "Video casting in CLI mode requires --cast <Chromecast or DLNA TV>."
        case .unknownCastType(let type):
            return "Unknown cast type '\(type)'. Use: sonos, chromecast, dlna"
        case .castDeviceNotFound(let name, let available):
            let list = available.isEmpty ? "none discovered" : available.joined(separator: ", ")
            return "Cast device '\(name)' not found. Available: \(list)"
        case .sonosVideoUnsupported:
            return "Sonos does not support video; use a Chromecast or DLNA TV."
        }
    }
}

class CLIPlayer: AudioEngineDelegate {
    let audioEngine: AudioEngine
    private var options: CLIOptions
    let display = CLIDisplay()
    private var previousVolume: Float = 0.5
    private var lastArtworkKey: String?
    private var lastTrackInfoKey: String?

    static func exitAndRestoreTerminal(code: Int32) -> Never {
        CLIKeyboard.restoreTerminal()
        exit(code)
    }

    init(options: CLIOptions) {
        self.options = options
        self.audioEngine = AudioEngine()

        // Wire CLI engine to managers that need it
        RadioManager.cliAudioEngine = audioEngine
        CastManager.cliAudioEngine = audioEngine

        audioEngine.delegate = self

        // Shuffle / Repeat
        // AudioEngine repeat semantics:
        //   repeatEnabled=true, shuffleEnabled=false → loop single track
        //   repeatEnabled=true, shuffleEnabled=true  → random track on playlist end
        //   Neither supports sequential "repeat all in order", so CLIPlayer
        //   implements it via audioEngineDidChangeState (.stopped → restart).
        if options.shuffle {
            audioEngine.shuffleEnabled = true
        }
        if options.repeatOne {
            audioEngine.repeatEnabled = true
            // shuffleEnabled stays false = repeat-one (loops single track)
        }
        // --repeat-all is handled in audioEngineDidChangeState below

        // Volume
        if let vol = options.volume {
            audioEngine.volume = Float(max(0, min(100, vol))) / 100.0
        }

        // Reference Tuning (session-only — does not write back to UserDefaults).
        // Precedence: --tuning-offset-cents → --tuning off → --tuning <Hz> → persisted state.
        if let cents = options.tuningOffsetCents {
            guard cents.isFinite else {
                fputs("Error: --tuning-offset-cents must be a finite number\n", cliStderr)
                Self.exitAndRestoreTerminal(code: 1)
            }
            audioEngine.setTuningOffsetCents(cents, persist: false)
        } else if let tuning = options.tuning {
            if tuning.caseInsensitiveCompare("off") == .orderedSame {
                audioEngine.setTuningEnabled(false, persist: false)
            } else if let targetHz = Double(tuning), targetHz.isFinite, targetHz > 0 {
                let sourceHz: Double
                if let src = options.tuningSource {
                    guard let parsed = Double(src), parsed.isFinite, parsed > 0 else {
                        fputs("Error: --tuning-source requires a positive number (Hz)\n", cliStderr)
                        Self.exitAndRestoreTerminal(code: 1)
                    }
                    sourceHz = parsed
                } else {
                    sourceHz = 440
                }
                audioEngine.setTuningPreset(.custom(source: sourceHz, target: targetHz), persist: false)
            } else {
                fputs("Error: --tuning requires 'off' or a positive number in Hz (e.g. 432)\n", cliStderr)
                Self.exitAndRestoreTerminal(code: 1)
            }
        }

        // EQ
        if let eqName = options.eq {
            if let preset = EQPreset.allPresets.first(where: {
                $0.name.caseInsensitiveCompare(eqName) == .orderedSame
            }) {
                audioEngine.setPreamp(preset.preamp)
                for (i, gain) in preset.bands.enumerated() {
                    audioEngine.setEQBand(i, gain: gain)
                }
                audioEngine.setEQEnabled(true)
            } else {
                let names = EQPreset.allPresets.map { $0.name }.joined(separator: ", ")
                fputs("Error: Unknown EQ preset '\(eqName)'. Available: \(names)\n", cliStderr)
                Self.exitAndRestoreTerminal(code: 1)
            }
        }

        // Output device
        if let outputName = options.output {
            if let device = AudioOutputManager.shared.outputDevices.first(where: {
                $0.name.caseInsensitiveCompare(outputName) == .orderedSame
            }) {
                audioEngine.setOutputDevice(device.id)
            } else {
                let names = AudioOutputManager.shared.outputDevices.map { $0.name }.joined(separator: ", ")
                fputs("Error: Unknown output device '\(outputName)'. Available: \(names)\n", cliStderr)
                Self.exitAndRestoreTerminal(code: 1)
            }
        }
    }

    private var currentPlaylist: [Track] = []
    private var hasStartedPlaying = false

    /// Set once we commit to casting. During the cast handoff the local engine is
    /// deliberately stopped (`stopLocalForCasting`) and emits `.stopped` even though
    /// audio is now playing on the cast device (the engine re-enters `.playing` once
    /// the device reports status). Without this flag the CLI would mistake that
    /// handoff `.stopped` for end-of-playlist and quit exactly when casting begins.
    /// It stays set for the life of a successful cast (auto-advance between cast
    /// tracks can emit `.stopped`, so a one-shot would exit mid-playlist), and is
    /// cleared if cast setup throws — otherwise a failed cast would swallow every
    /// future `.stopped` and hang the CLI at natural end (see the catch in setupCasting).
    private var castSessionActive = false

    /// Set when the streaming player enters an error state. The engine surfaces
    /// both error-induced and natural end-of-playlist stops as `.stopped`, so this
    /// flag lets us tell them apart and avoid quitting (or restart-looping) on an
    /// error such as a mid-stream network drop.
    private var lastStopWasError = false

    func play(tracks: [Track]) {
        currentPlaylist = tracks
        audioEngine.loadTracks(tracks)
        audioEngine.play()
        printTrackInfoIfChanged(tracks.first)
        if options.art, let first = tracks.first {
            showArtworkIfChanged(for: first)
        }

        // Casting
        if let castName = options.cast {
            Task { @MainActor in
                await setupCasting(castValue: castName)
            }
        }
    }

    private func parseCastRequest(_ castValue: String) -> (deviceName: String, inlineRooms: [String]) {
        let castComponents = castValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let deviceName = castComponents.first ?? castValue.trimmingCharacters(in: .whitespaces)
        return (deviceName, Array(castComponents.dropFirst()))
    }

    private func castTypeFilter(videoOnly: Bool) throws -> CastDeviceType? {
        guard let castType = options.castType else {
            return nil
        }
        switch castType.lowercased() {
        case "sonos":
            if videoOnly { throw CLIPlayerError.sonosVideoUnsupported }
            return .sonos
        case "chromecast":
            return .chromecast
        case "dlna":
            return .dlnaTV
        default:
            throw CLIPlayerError.unknownCastType(castType)
        }
    }

    private func resolveCastDevice(castValue: String, videoOnly: Bool) async throws -> CastDevice {
        let request = parseCastRequest(castValue)
        let typeFilter = try castTypeFilter(videoOnly: videoOnly)

        CastManager.shared.startDiscovery()
        fputs("Discovering cast devices...\n", cliStderr)

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let allDevices = CastManager.shared.discoveredDevices
            let filteredDevices = allDevices.filter { device in
                if videoOnly && !device.supportsVideo { return false }
                if let typeFilter, device.type != typeFilter { return false }
                return true
            }

            if let match = filteredDevices.first(where: {
                $0.name.caseInsensitiveCompare(request.deviceName) == .orderedSame
            }) {
                return match
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        let available = CastManager.shared.discoveredDevices
            .filter { device in
                if videoOnly && !device.supportsVideo { return false }
                if let typeFilter, device.type != typeFilter { return false }
                return true
            }
            .map { "\($0.name) (\($0.type))" }
        throw CLIPlayerError.castDeviceNotFound(request.deviceName, available)
    }

    private func setupCasting(castValue: String) async {
        // Wait for AudioEngine to have a current track loaded before casting
        let trackDeadline = Date().addingTimeInterval(5)
        while audioEngine.currentTrack == nil && Date() < trackDeadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard audioEngine.currentTrack != nil else {
            fputs("Error: No track loaded for casting\n", cliStderr)
            return
        }

        let request = parseCastRequest(castValue)
        let device: CastDevice
        do {
            device = try await resolveCastDevice(castValue: castValue, videoOnly: false)
        } catch {
            fputs("Error: \(error.localizedDescription.redactingSensitiveURLQueryItems)\n", cliStderr)
            return
        }

        // Commit to casting before the handoff. castCurrentTrack triggers
        // stopLocalForCasting, whose `.stopped` must not exit the CLI (see flag docs).
        castSessionActive = true
        do {
            try await CastManager.shared.castCurrentTrack(to: device)
        } catch {
            // Cast setup failed — undo the handoff guard so normal stop handling
            // resumes. Left set, the guard would swallow every future .stopped and the
            // CLI would hang at natural end instead of exiting/repeating. If local
            // playback was already stopped for the (failed) handoff there is nothing
            // left to play, so exit with an error; otherwise (e.g. an all-Sonos-
            // incompatible playlist that threw before local playback was touched) let
            // local playback continue and exit naturally at its end.
            castSessionActive = false
            fputs("Error: Cast failed: \(error.localizedDescription.redactingSensitiveURLQueryItems)\n", cliStderr)
            if audioEngine.state != .playing {
                metadataTimer?.invalidate()
                Self.exitAndRestoreTerminal(code: 1)
            }
            return
        }

        // Cast is now active. Grouping is best-effort: a room that fails to join must
        // not tear down the working cast, so failures here are per-room warnings only
        // (they do NOT clear castSessionActive).
        let explicitRooms = options.sonosRooms?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        // Dedupe case-insensitively and drop the coordinator itself.
        var seen = Set([request.deviceName.lowercased()])
        var roomNames: [String] = []
        for room in request.inlineRooms + explicitRooms where !room.isEmpty {
            if seen.insert(room.lowercased()).inserted {
                roomNames.append(room)
            }
        }

        guard !roomNames.isEmpty else { return }
        guard device.type == .sonos else {
            fputs("Warning: multi-room grouping is only supported for Sonos; ignoring \(roomNames.joined(separator: ", "))\n", cliStderr)
            return
        }
        let sonosDevices = CastManager.shared.discoveredDevices.filter { $0.type == .sonos }
        let coordinatorUDN = device.id
        for roomName in roomNames {
            guard let room = sonosDevices.first(where: {
                $0.name.caseInsensitiveCompare(roomName) == .orderedSame
            }) else {
                fputs("Warning: Sonos room '\(roomName)' not found\n", cliStderr)
                continue
            }
            do {
                try await CastManager.shared.joinSonosToGroup(
                    zoneUDN: room.id,
                    coordinatorUDN: coordinatorUDN
                )
            } catch {
                fputs("Warning: failed to group '\(roomName)': \(error.localizedDescription.redactingSensitiveURLQueryItems)\n", cliStderr)
            }
        }
    }

    // MARK: - Playback Controls

    /// Called when --source radio --station plays via RadioManager directly.
    /// RadioManager plays through `resolvedAudioEngine` which is `self.audioEngine`
    /// (wired via `RadioManager.cliAudioEngine`), so delegate callbacks
    /// (state changes, time updates) fire on this CLIPlayer automatically.
    /// We also start a metadata poller since streaming radio metadata updates
    /// come through RadioManager, not the AudioEngine delegate.
    func monitorRadio() {
        display.printState(.playing)
        startRadioMetadataPoller()
    }

    private var metadataTimer: Timer?
    private var videoProgressTimer: Timer?
    private var videoCastActive = false
    private var videoCastHasStartedPlaying = false
    private var videoSessionObserver: NSObjectProtocol?
    private var videoMediaStatusObserver: NSObjectProtocol?
    private var videoCastIsPaused = false

    private func startRadioMetadataPoller() {
        // Poll RadioManager for metadata changes every 5 seconds
        var lastTitle: String?
        metadataTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let currentTitle = RadioManager.shared.currentMetadataTitle,
               currentTitle != lastTitle {
                lastTitle = currentTitle
                self.display.printAboveProgress("Radio: \(currentTitle)")
            }
        }
    }

    // MARK: - Video Casting

    @MainActor
    func castVideo(_ item: CLIVideoItem, castValue: String?) async throws {
        guard let castValue, !castValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIPlayerError.videoRequiresCast
        }

        if options.castType?.caseInsensitiveCompare("sonos") == .orderedSame {
            throw CLIPlayerError.sonosVideoUnsupported
        }

        videoCastActive = true
        videoCastHasStartedPlaying = false
        videoCastIsPaused = false
        installVideoCastObservers()

        do {
            let device = try await resolveCastDevice(castValue: castValue, videoOnly: true)
            guard device.supportsVideo, device.type != .sonos else {
                throw CLIPlayerError.sonosVideoUnsupported
            }

            display.printVideoInfo(title: item.displayTitle, device: device.name, manualQuitOnly: device.type == .dlnaTV)

            switch item {
            case .localFile(let url, let title):
                try await CastManager.shared.castLocalVideo(url, title: title, to: device)
            case .plexMovie(let movie):
                try await CastManager.shared.castPlexMovie(movie, to: device)
            case .plexEpisode(let episode):
                try await CastManager.shared.castPlexEpisode(episode, to: device)
            case .jellyfinMovie(let movie):
                try await CastManager.shared.castJellyfinMovie(movie, to: device)
            case .jellyfinEpisode(let episode):
                try await CastManager.shared.castJellyfinEpisode(episode, to: device)
            case .embyMovie(let movie):
                try await CastManager.shared.castEmbyMovie(movie, to: device)
            case .embyEpisode(let episode):
                try await CastManager.shared.castEmbyEpisode(episode, to: device)
            }
        } catch {
            videoCastActive = false
            removeVideoCastObservers()
            throw error
        }

        startVideoProgressTimer()
    }

    private func installVideoCastObservers() {
        removeVideoCastObservers()
        videoSessionObserver = NotificationCenter.default.addObserver(
            forName: CastManager.sessionDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.videoCastActive,
               self.videoCastHasStartedPlaying,
               CastManager.shared.currentCast == .none {
                self.exitAndRestoreTerminalAfterVideo(code: 0)
            }
        }

        videoMediaStatusObserver = NotificationCenter.default.addObserver(
            forName: ChromecastManager.mediaStatusDidUpdateNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  self.videoCastActive,
                  let status = notification.userInfo?["status"] as? CastMediaStatus
            else { return }
            if status.playerState == .playing || status.playerState == .buffering {
                self.videoCastHasStartedPlaying = true
                self.videoCastIsPaused = false
            } else if status.playerState == .paused {
                self.videoCastIsPaused = true
            }
        }
    }

    private func removeVideoCastObservers() {
        if let videoSessionObserver {
            NotificationCenter.default.removeObserver(videoSessionObserver)
            self.videoSessionObserver = nil
        }
        if let videoMediaStatusObserver {
            NotificationCenter.default.removeObserver(videoMediaStatusObserver)
            self.videoMediaStatusObserver = nil
        }
    }

    private func startVideoProgressTimer() {
        videoProgressTimer?.invalidate()
        videoProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.videoCastActive else { return }
            self.display.updateVideoProgress(
                current: CastManager.shared.videoCastCurrentTime,
                duration: CastManager.shared.videoCastDuration,
                paused: self.videoCastIsPaused
            )
        }
    }

    private func stopVideoProgressTimer() {
        videoProgressTimer?.invalidate()
        videoProgressTimer = nil
    }

    private func exitAndRestoreTerminalAfterVideo(code: Int32) -> Never {
        stopVideoProgressTimer()
        removeVideoCastObservers()
        videoCastActive = false
        Self.exitAndRestoreTerminal(code: code)
    }

    func togglePlayPause() {
        if videoCastActive {
            Task { @MainActor in
                do {
                    if CastManager.shared.isVideoCastPlaying {
                        try await CastManager.shared.pause()
                        videoCastIsPaused = true
                        display.printAboveProgress("[Paused]")
                    } else {
                        try await CastManager.shared.resume()
                        videoCastIsPaused = false
                    }
                } catch {
                    display.printAboveProgress("Cast control failed: \(error.localizedDescription.redactingSensitiveURLQueryItems)")
                }
            }
            return
        }
        if audioEngine.state == .playing {
            audioEngine.pause()
        } else {
            audioEngine.play()
        }
    }

    func nextTrack() {
        guard !videoCastActive else { return }
        audioEngine.next()
    }

    func previousTrack() {
        guard !videoCastActive else { return }
        audioEngine.previous()
    }

    func seekForward(_ seconds: TimeInterval = 10) {
        if videoCastActive {
            Task { @MainActor in
                let duration = CastManager.shared.videoCastDuration
                let target = CastManager.shared.videoCastCurrentTime + seconds
                do {
                    try await CastManager.shared.seek(to: duration > 0 ? min(target, duration) : target)
                } catch {
                    display.printAboveProgress("Cast seek failed: \(error.localizedDescription.redactingSensitiveURLQueryItems)")
                }
            }
            return
        }
        let newTime = audioEngine.currentTime + seconds
        audioEngine.seek(to: min(newTime, audioEngine.duration))
    }

    func seekBackward(_ seconds: TimeInterval = 10) {
        if videoCastActive {
            Task { @MainActor in
                let target = max(CastManager.shared.videoCastCurrentTime - seconds, 0)
                do {
                    try await CastManager.shared.seek(to: target)
                } catch {
                    display.printAboveProgress("Cast seek failed: \(error.localizedDescription.redactingSensitiveURLQueryItems)")
                }
            }
            return
        }
        let newTime = audioEngine.currentTime - seconds
        audioEngine.seek(to: max(newTime, 0))
    }

    func volumeUp() {
        guard !videoCastActive else { return }
        audioEngine.volume = min(audioEngine.volume + 0.05, 1.0)
        display.printVolume(audioEngine.volume)
    }

    func volumeDown() {
        guard !videoCastActive else { return }
        audioEngine.volume = max(audioEngine.volume - 0.05, 0.0)
        display.printVolume(audioEngine.volume)
    }

    func toggleShuffle() {
        guard !videoCastActive else { return }
        audioEngine.shuffleEnabled.toggle()
        display.printStatus(shuffle: audioEngine.shuffleEnabled,
                           repeat: audioEngine.repeatEnabled)
    }

    func cycleRepeat() {
        guard !videoCastActive else { return }
        if !options.repeatAll && !audioEngine.repeatEnabled {
            // Off -> Repeat All (managed by CLIPlayer)
            options.repeatAll = true
            audioEngine.repeatEnabled = false
        } else if options.repeatAll {
            // Repeat All -> Repeat One (AudioEngine native)
            options.repeatAll = false
            audioEngine.repeatEnabled = true
        } else {
            // Repeat One -> Off
            audioEngine.repeatEnabled = false
        }
        let repeatMode: CLIDisplay.RepeatMode = options.repeatAll ? .all
            : audioEngine.repeatEnabled ? .one : .off
        display.printRepeatStatus(shuffle: audioEngine.shuffleEnabled, repeat: repeatMode)
    }

    func toggleMute() {
        guard !videoCastActive else { return }
        if audioEngine.volume > 0 {
            previousVolume = audioEngine.volume
            audioEngine.volume = 0
        } else {
            audioEngine.volume = previousVolume
        }
        display.printVolume(audioEngine.volume)
    }

    func quit() {
        metadataTimer?.invalidate()
        stopVideoProgressTimer()
        removeVideoCastObservers()
        if videoCastActive {
            Task { @MainActor in
                await CastManager.shared.stopCasting()
                Self.exitAndRestoreTerminal(code: 0)
            }
            return
        }
        audioEngine.stop()
        Self.exitAndRestoreTerminal(code: 0)
    }

    // MARK: - AudioEngineDelegate

    func audioEngineDidEncounterPlaybackError() {
        lastStopWasError = true
    }

    func audioEngineDidChangeState(_ state: PlaybackState) {
        // While a cast session owns playback, the local engine is intentionally
        // stopped for the handoff and re-enters .playing once the device reports
        // status. Never treat a local .stopped as end-of-playlist here — audio is
        // playing on the cast device, and exiting/restarting would kill or fight it.
        if state == .stopped && castSessionActive {
            return
        }

        // An error-induced stop (e.g. seek into EOF, network drop, dead server)
        // surfaces as .stopped just like a natural end-of-playlist. Don't treat it
        // as completion: skip both the repeat-all restart (which would hammer a
        // failing stream in a tight loop) and the exit. Stay alive so the user can
        // press > to skip or q to quit.
        if state == .stopped && lastStopWasError {
            lastStopWasError = false
            display.printState(state)
            display.printAboveProgress("Playback error — press > to skip or q to quit")
            return
        }

        // Implement repeat-all: when playlist ends (state == .stopped),
        // reload and restart from the beginning
        if state == .stopped && options.repeatAll && !currentPlaylist.isEmpty {
            audioEngine.loadTracks(currentPlaylist)
            audioEngine.play()
            return
        }
        if state == .playing {
            hasStartedPlaying = true
            lastStopWasError = false  // Recovered — a later stop is a real one
        }
        display.printState(state)
        // Exit when playback finishes naturally and there is nothing left to play
        if state == .stopped && hasStartedPlaying && !options.repeatAll {
            metadataTimer?.invalidate()
            Self.exitAndRestoreTerminal(code: 0)
        }
    }

    func audioEngineDidUpdateTime(current: TimeInterval, duration: TimeInterval) {
        let repeatMode: CLIDisplay.RepeatMode = options.repeatOne ? .one
            : options.repeatAll ? .all
            : .off
        display.updateProgress(current: current, duration: duration,
                              volume: audioEngine.volume,
                              shuffle: audioEngine.shuffleEnabled,
                              repeat: repeatMode)
    }

    func audioEngineDidChangeTrack(_ track: Track?) {
        printTrackInfoIfChanged(track)
        if options.art, let track {
            showArtworkIfChanged(for: track)
        }
    }

    /// Print the "Now Playing" block only when the track actually changes. The
    /// track-change delegate fires several times for the same track during load and
    /// stream-format detection (and `play()` prints once up front), so a plain print
    /// would repeat the same block 4–5×. The `i` key calls `display.printTrackInfo`
    /// directly and is intentionally not deduped — it's an explicit on-demand reprint.
    private func printTrackInfoIfChanged(_ track: Track?) {
        guard let track else { return }
        let key = "\(track.artist ?? "")|\(track.title ?? "")|\(track.album ?? "")"
        guard key != lastTrackInfoKey else { return }
        lastTrackInfoKey = key
        display.printTrackInfo(track)
    }

    private func showArtworkIfChanged(for track: Track) {
        // Build a key that identifies this track's artwork.
        // For remote sources, artworkThumb is the identifier.
        // For local files, use the file URL (each file has its own embedded art).
        let key: String
        if let thumb = track.artworkThumb {
            key = thumb
        } else if track.url.isFileURL {
            // Use directory path as key — tracks in the same folder likely share album art
            key = track.url.deletingLastPathComponent().path
        } else {
            return // no artwork available
        }

        guard key != lastArtworkKey else {
            NSLog("[CLIArt] skipping — same key as last artwork: %@", key)
            return
        }
        lastArtworkKey = key
        NSLog("[CLIArt] loading artwork for key: %@", key)

        Task {
            let image = await CLIArtwork.loadArtwork(for: track)
            guard let image else {
                NSLog("[CLIArt] loadArtwork returned nil for: %@", track.url.lastPathComponent)
                // No art found — clear the key so the next track can retry
                await MainActor.run { self.lastArtworkKey = nil }
                return
            }
            NSLog("[CLIArt] got image %@ x %@, rendering ASCII art", "\(image.size.width)", "\(image.size.height)")
            await MainActor.run {
                self.display.printAsciiArt(image,
                                           forceColor: self.options.artColor,
                                           forceAscii: self.options.artAscii)
            }
        }
    }

    func audioEngineDidUpdateSpectrum(_ levels: [Float]) {
        // No-op in CLI mode — no visualization
    }

    func audioEngineDidChangePlaylist() {
        // Optional: could print updated playlist info
    }

    func audioEngineDidFailToLoadTrack(_ track: Track, error: Error) {
        fputs("Error loading '\(track.title)': \(error.localizedDescription.redactingSensitiveURLQueryItems)\n", cliStderr)
    }
}
