import Foundation

class CLIPlayer: AudioEngineDelegate {
    let audioEngine: AudioEngine
    private var options: CLIOptions
    let display = CLIDisplay()
    private var previousVolume: Float = 0.5
    private var lastArtworkKey: String?

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
                fputs("Error: Unknown EQ preset '\(eqName)'. Available: \(names)\n", stderr)
                exit(1)
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
                fputs("Error: Unknown output device '\(outputName)'. Available: \(names)\n", stderr)
                exit(1)
            }
        }
    }

    private var currentPlaylist: [Track] = []

    func play(tracks: [Track]) {
        currentPlaylist = tracks
        audioEngine.loadTracks(tracks)
        audioEngine.play()
        display.printTrackInfo(tracks.first)
        if options.art, let first = tracks.first {
            showArtworkIfChanged(for: first)
        }

        // Casting
        if let castName = options.cast {
            Task { @MainActor in
                await setupCasting(deviceName: castName)
            }
        }
    }

    private func setupCasting(deviceName: String) async {
        // Wait for AudioEngine to have a current track loaded before casting
        let trackDeadline = Date().addingTimeInterval(5)
        while audioEngine.currentTrack == nil && Date() < trackDeadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard audioEngine.currentTrack != nil else {
            fputs("Error: No track loaded for casting\n", stderr)
            return
        }

        CastManager.shared.startDiscovery()

        // Poll for devices with 10s timeout
        let deadline = Date().addingTimeInterval(10)
        while CastManager.shared.discoveredDevices.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // Filter by cast type if specified
        var devices = CastManager.shared.discoveredDevices
        if let castType = options.castType {
            switch castType.lowercased() {
            case "sonos": devices = devices.filter { $0.type == .sonos }
            case "chromecast": devices = devices.filter { $0.type == .chromecast }
            case "dlna": devices = devices.filter { $0.type == .dlnaTV }
            default:
                fputs("Error: Unknown cast type '\(castType)'. Use: sonos, chromecast, dlna\n", stderr)
                return
            }
        }

        guard let device = devices.first(where: {
            $0.name.caseInsensitiveCompare(deviceName) == .orderedSame
        }) else {
            let available = devices.map { "\($0.name) (\($0.type))" }.joined(separator: ", ")
            fputs("Error: Cast device '\(deviceName)' not found. Available: \(available)\n", stderr)
            return
        }

        do {
            try await CastManager.shared.castCurrentTrack(to: device)

            // Sonos multi-room
            if let roomsStr = options.sonosRooms {
                let roomNames = roomsStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let sonosDevices = CastManager.shared.discoveredDevices.filter { $0.type == .sonos }
                let coordinatorUDN = device.id

                for roomName in roomNames {
                    if let room = sonosDevices.first(where: {
                        $0.name.caseInsensitiveCompare(roomName) == .orderedSame
                    }) {
                        try await CastManager.shared.joinSonosToGroup(
                            zoneUDN: room.id,
                            coordinatorUDN: coordinatorUDN
                        )
                    } else {
                        fputs("Warning: Sonos room '\(roomName)' not found\n", stderr)
                    }
                }
            }
        } catch {
            fputs("Error: Cast failed: \(error.localizedDescription)\n", stderr)
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

    func togglePlayPause() {
        if audioEngine.state == .playing {
            audioEngine.pause()
        } else {
            audioEngine.play()
        }
    }

    func nextTrack() { audioEngine.next() }
    func previousTrack() { audioEngine.previous() }

    func seekForward(_ seconds: TimeInterval = 10) {
        let newTime = audioEngine.currentTime + seconds
        audioEngine.seek(to: min(newTime, audioEngine.duration))
    }

    func seekBackward(_ seconds: TimeInterval = 10) {
        let newTime = audioEngine.currentTime - seconds
        audioEngine.seek(to: max(newTime, 0))
    }

    func volumeUp() {
        audioEngine.volume = min(audioEngine.volume + 0.05, 1.0)
        display.printVolume(audioEngine.volume)
    }

    func volumeDown() {
        audioEngine.volume = max(audioEngine.volume - 0.05, 0.0)
        display.printVolume(audioEngine.volume)
    }

    func toggleShuffle() {
        audioEngine.shuffleEnabled.toggle()
        display.printStatus(shuffle: audioEngine.shuffleEnabled,
                           repeat: audioEngine.repeatEnabled)
    }

    func cycleRepeat() {
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
        audioEngine.stop()
        CLIKeyboard.restoreTerminal()
        exit(0)
    }

    // MARK: - AudioEngineDelegate

    func audioEngineDidChangeState(_ state: PlaybackState) {
        // Implement repeat-all: when playlist ends (state == .stopped),
        // reload and restart from the beginning
        if state == .stopped && options.repeatAll && !currentPlaylist.isEmpty {
            audioEngine.loadTracks(currentPlaylist)
            audioEngine.play()
            return
        }
        display.printState(state)
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
        display.printTrackInfo(track)
        if options.art, let track {
            showArtworkIfChanged(for: track)
        }
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
                self.display.printAsciiArt(image)
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
        fputs("Error loading '\(track.title ?? "Unknown")': \(error.localizedDescription)\n", stderr)
    }
}
