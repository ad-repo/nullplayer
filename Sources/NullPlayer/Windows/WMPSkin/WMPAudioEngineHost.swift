import Foundation
import NullPlayerCore

@MainActor
final class WMPAudioEngineHost: WMPHost {
    private let engine: AudioEngine
    private var scanTimer: Timer?
    private var scanDirection: WMPScanDirection?
    private var preMuteVolume: Float = 0.2
    private var spectrumConsumerActive = false
    private let spectrumConsumerID = "wmp.main.effects"
    /// VLC drops both `hasVideoOut` and `videoSize` while it rebuilds the output for a media that
    /// is still open. Keep only the event snapshot through that gap; the live video snapshot must
    /// still fall empty so the hosted child window detaches and releases mouse capture.
    private var videoEventLatch = WMPVideoEventLatch()

    init(audioEngine: AudioEngine) { engine = audioEngine }

    private static var localVideoSessionController: VideoPlayerWindowController? {
        let manager = WindowManager.shared
        guard manager.uiMode.controllerFamily == .wmp, !manager.isVideoCastingActive,
              let video = manager.currentVideoPlayerController,
              video.currentTitle != nil else { return nil }
        return video
    }

    static var localVideoController: VideoPlayerWindowController? {
        guard let video = localVideoSessionController, !video.didReachEndOfMedia else { return nil }
        return video
    }

    /// The artwork WMP exposes belongs to the presentation currently visible to the user. A local
    /// video takes precedence over the audio queue for the same reason `snapshot` does below.
    var artworkTrack: Track? {
        Self.localVideoController?.currentArtworkTrack ?? engine.currentTrack
    }

    private static func videoIdentity(_ video: VideoPlayerWindowController) -> String? {
        guard let track = video.currentArtworkTrack else {
            return video.currentTitle.map { "title:\($0)" }
        }
        if let key = track.plexRatingKey {
            return "plex:\(track.plexServerId ?? ""):\(key)"
        }
        if let key = track.jellyfinId {
            return "jellyfin:\(track.jellyfinServerId ?? ""):\(key)"
        }
        if let key = track.embyId {
            return "emby:\(track.embyServerId ?? ""):\(key)"
        }
        return "url:\(track.url.absoluteString)"
    }

    var snapshot: WMPHostSnapshot {
        let state: WMPHostSnapshot.State
        switch engine.state {
        case .stopped: state = .stopped
        case .playing: state = .playing
        case .paused: state = .paused
        }
        let track = engine.currentTrack
        let playlistItems = engine.playlist.prefix(4_096).map {
            WMPPlaylistItemSnapshot(title: $0.title, artist: $0.artist ?? "",
                                    duration: Self.finite($0.duration ?? 0))
        }
        let sourceLayout = engine.eqConfiguration
        let sourceGains = (0..<sourceLayout.bandCount).map { engine.getEQBand($0) }
        let classicGains = EQBandRemapper.remap(gains: sourceGains, from: sourceLayout, to: .classic10)
        var result = WMPHostSnapshot(state: state, currentTime: Self.finite(engine.currentTime),
            duration: Self.finite(engine.duration), volume: Double(max(0, min(1, engine.volume))),
            balance: Double(max(-1, min(1, engine.balance))), muted: engine.volume == 0,
            shuffle: engine.shuffleEnabled, repeatMode: engine.repeatEnabled,
            bitrate: Double(track?.bitrate ?? 0) * 1_000,
            metadata: WMPMediaMetadata(title: track?.title ?? "", artist: track?.artist ?? "",
                                       album: track?.album ?? "",
                                       sourceURL: track?.url.absoluteString ?? ""),
            playlistIndex: engine.currentIndex, playlistCount: engine.playlist.count,
            playlistItems: playlistItems,
            equalizer: WMPEqualizerSnapshot(enabled: engine.isEQEnabled(),
                enhancedAudio: engine.wmpWOWController.active && engine.wmpWOWController.enabled,
                wowLevel: engine.wmpWOWController.level,
                truBassLevel: engine.wmpWOWController.bassLevel,
                speakerSize: engine.wmpWOWController.speakerSize,
                preamp: Double(engine.getPreamp()), gains: classicGains.map(Double.init)),
            effects: WMPEffectSelection.shared.snapshot)
        guard let video = Self.localVideoSessionController,
              let identity = Self.videoIdentity(video) else {
            videoEventLatch.reset()
            return result
        }
        guard !video.didReachEndOfMedia else {
            // A genuine end must clear the latch so `WMPVideoPresentation` raises `videoend`.
            videoEventLatch.reset()
            return result
        }

        result.state = video.isPlaying ? .playing : .paused
        result.currentTime = Self.finite(video.currentTime)
        result.duration = Self.finite(video.duration)
        result.metadata = WMPMediaMetadata(title: video.currentTitle ?? "")
        result.volume = Double(video.volume)
        result.muted = video.volume == 0
        result.playlistCount = max(1, result.playlistCount)
        var currentVideo = WMPVideoSnapshot()
        if video.hasVideoOutput {
            currentVideo = WMPVideoSnapshot(width: Self.finite(video.presentationSize.width),
                height: Self.finite(video.presentationSize.height),
                fullScreen: video.window?.styleMask.contains(.fullScreen) == true)
            result.video = currentVideo
        }
        result.videoEvent = videoEventLatch.update(mediaIdentity: identity, current: currentVideo,
                                                   didReachEnd: false)
        return result
    }

    func perform(_ action: WMPTransportAction, value: WMPHostValue?) {
        if let video = Self.localVideoController {
            switch action {
            case .play:
                if !video.isPlaying { video.togglePlayPause() }
                return
            case .pause:
                if video.isPlaying { video.togglePlayPause() }
                return
            case .stop: video.stop(); return
            case .seek:
                if let fraction = value?.finiteNumber { video.seek(to: max(0, min(1, fraction)) * video.duration) }
                return
            case .volume:
                if let volume = value?.finiteNumber { video.volume = Float(max(0, min(1, volume))) }
                return
            case .toggleMute:
                if video.volume > 0 { preMuteVolume = video.volume; video.volume = 0 }
                else { video.volume = max(0.01, min(1, preMuteVolume)) }
                return
            default: break
            }
        }
        switch action {
        case .play: engine.play()
        case .pause: engine.pause()
        case .stop: engine.stop()
        case .previous: engine.previous()
        case .next: engine.next()
        case let .beginScan(direction): startScanning(direction)
        case .endScan: stopScanning()
        case .seek:
            guard let fraction = value?.finiteNumber else { return }
            engine.seek(to: max(0, min(1, fraction)) * engine.duration)
        case .volume:
            guard let volume = value?.finiteNumber else { return }
            engine.volume = Float(max(0, min(1, volume)))
        case .balance:
            guard let balance = value?.finiteNumber else { return }
            engine.balance = Float(max(-1, min(1, balance)))
        case .toggleMute:
            if engine.volume > 0 { preMuteVolume = engine.volume; engine.volume = 0 }
            else { engine.volume = max(0.01, min(1, preMuteVolume)) }
        case .toggleShuffle: engine.shuffleEnabled.toggle()
        case .toggleRepeat: engine.repeatEnabled.toggle()
        case let .playPlaylistItem(index): engine.playTrack(at: index)
        case let .removePlaylistItem(index): engine.removeTrack(at: index)
        case let .movePlaylistItem(source, destination): engine.moveTrack(from: source, to: destination)
        case .setWOWEnabled:
            guard WindowManager.shared.uiMode.controllerFamily == .wmp,
                  let enabled = value?.finiteNumber else { return }
            engine.wmpWOWController.setEnabled(enabled != 0)
        case .setWOWLevel:
            guard WindowManager.shared.uiMode.controllerFamily == .wmp,
                  let level = value?.finiteNumber else { return }
            engine.wmpWOWController.setLevel(level)
        case .setTruBassLevel:
            guard WindowManager.shared.uiMode.controllerFamily == .wmp,
                  let level = value?.finiteNumber else { return }
            engine.wmpWOWController.setBassLevel(level)
        case .setSpeakerSize:
            guard WindowManager.shared.uiMode.controllerFamily == .wmp,
                  let speaker = value?.finiteNumber, (0...2).contains(speaker) else { return }
            engine.wmpWOWController.setSpeakerSize(Int(speaker))
        case .setEQEnabled:
            guard let enabled = value?.finiteNumber else { return }
            engine.setEQEnabled(enabled != 0)
        case let .setEQBand(index):
            guard (0..<10).contains(index), let gain = value?.finiteNumber else { return }
            var classic = snapshot.equalizer.gains.map(Float.init)
            classic[index] = Float(max(-12, min(12, gain)))
            let target = engine.eqConfiguration
            let remapped = EQBandRemapper.remap(gains: classic, from: .classic10, to: target)
            for (band, remappedGain) in remapped.enumerated() { engine.setEQBand(band, gain: remappedGain) }
            engageEqualizer()
        case .setPreamp:
            guard let gain = value?.finiteNumber else { return }
            engine.setPreamp(Float(max(-12, min(12, gain))))
            engageEqualizer()
        case let .setEQPreset(index):
            // WMP tracks a "current preset" and the engine does not, so a selection is applied as
            // the ten band gains and the preamp it stands for — the same thing the object model
            // already does for a script writing `eq.currentPreset`.
            guard EQPreset.allPresets.indices.contains(index) else { return }
            let preset = EQPreset.allPresets[index]
            engine.setPreamp(Float(max(-12, min(12, preset.preamp))))
            let clamped = preset.bands.map { Float(max(-12, min(12, $0))) }
            let remapped = EQBandRemapper.remap(gains: clamped, from: .classic10,
                                                to: engine.eqConfiguration)
            for (band, gain) in remapped.enumerated() { engine.setEQBand(band, gain: gain) }
            engageEqualizer()
        // What the skin's `<EFFECTS>` rect draws. The selection is the WMP session's own — see
        // `WMPEffectSelection` for why cycling it does not write the app's visualization
        // preference back.
        case let .setEffectType(name): WMPEffectSelection.shared.select(name)
        case .nextEffect: WMPEffectSelection.shared.step(by: 1)
        case .previousEffect: WMPEffectSelection.shared.step(by: -1)
        case let .setEffectPreset(index): WMPEffectSelection.shared.setPreset(index)
        case .nextEffectPreset: WMPEffectSelection.shared.stepPreset(by: 1)
        }
    }

    /// Moving a band, the preamp or a preset turns the equaliser on if it was off.
    ///
    /// Every other skin engine in this app already does it where it can — `EQView`, `ModernEQView`
    /// and `WinampModernComponentBridge` all enable the equaliser when they apply a preset — and a
    /// `.wmz` needs it more, because it has nowhere to say so: only `gnome` writes `eq.enabled`
    /// from script anywhere in the corpus, and the 19 skins with band sliders that author no
    /// `<EQUALIZERSETTINGS enable="true">` (`Cablemusic`, `Windows XP`, the five `Plus!` skins,
    /// both `Revert` releases…) would otherwise drag a slider into a bypassed equaliser forever.
    /// A skin that authored `enable="false"` would be overridden here — none does, corpus-wide.
    private func engageEqualizer() {
        guard !engine.isEQEnabled() else { return }
        engine.setEQEnabled(true)
    }

    func setSpectrumConsumerActive(_ active: Bool) {
        guard active != spectrumConsumerActive else { return }
        spectrumConsumerActive = active
        if active { engine.addSpectrumConsumer(spectrumConsumerID) }
        else { engine.removeSpectrumConsumer(spectrumConsumerID) }
    }

    func stopContinuousCommands() {
        stopScanning()
        setSpectrumConsumerActive(false)
    }

    private func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
        scanDirection = nil
    }

    private func startScanning(_ direction: WMPScanDirection) {
        stopScanning()
        scanDirection = direction
        scanStep()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scanStep() }
        }
    }

    private func scanStep() {
        guard let scanDirection else { return }
        if let video = Self.localVideoController {
            video.seek(to: max(0, min(video.duration,
                                     video.currentTime + (scanDirection == .forward ? 5 : -5))))
            return
        }
        engine.seekBy(seconds: scanDirection == .forward ? 5 : -5)
    }

    private static func finite(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }
}
