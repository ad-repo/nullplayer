import Foundation
import NullPlayerCore

/// **The cast-side transport the WMP host drives while a film is on a television.**
///
/// A seam rather than direct `WindowManager` calls for one reason: the branch behind it is only
/// reachable with a real Chromecast on the network, and it has already shipped two defects that a
/// test could have caught — a seek handed seconds to a call that takes a fraction, and a volume
/// read back off the idle audio queue. `WMPWindowManagerVideoCast` is the only implementation the
/// app ever installs; a test installs its own and drives `perform` and `snapshot` directly.
@MainActor
protocol WMPVideoCastTransport {
    /// Whether a film is casting **and** WMP is the family showing it.
    var isCasting: Bool { get }
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var title: String? { get }
    func togglePlayPause()
    func stop()
    /// **A fraction of the film, not a time.** `WindowManager.seekVideoCast` multiplies by the
    /// cast's own duration itself.
    func seek(fraction: Double)
    func setVolume(_ level: Float)
}

/// The app's implementation: every call is `WindowManager`'s own cast-aware one.
@MainActor
struct WMPWindowManagerVideoCast: WMPVideoCastTransport {
    var isCasting: Bool {
        let manager = WindowManager.shared
        return manager.uiMode.controllerFamily == .wmp && manager.isVideoCastingActive
    }
    var isPlaying: Bool { WindowManager.shared.videoPlaybackState == .playing }
    var currentTime: TimeInterval { WindowManager.shared.videoCurrentTime }
    var duration: TimeInterval { WindowManager.shared.videoDuration }
    var title: String? { WindowManager.shared.videoTitle }
    func togglePlayPause() { WindowManager.shared.toggleVideoPlayPause() }
    func stop() { WindowManager.shared.stopVideo() }
    func seek(fraction: Double) { WindowManager.shared.seekVideoCast(position: fraction) }
    func setVolume(_ level: Float) { WindowManager.shared.setVideoCastVolume(level) }
}

@MainActor
final class WMPAudioEngineHost: WMPHost {
    private let engine: AudioEngine
    private var scanTimer: Timer?
    private var scanDirection: WMPScanDirection?
    private var preMuteVolume: Float = 0.2
    /// **Mute is not a volume of zero to a skin (W265).** It is implemented here by zeroing the
    /// output, but WMP keeps `settings.volume` where it was while muted, and skins rely on that:
    /// `Frostbite`'s volume knob binds `wmpprop:player.settings.volume` and its `value_onchange`
    /// ends `player.settings.mute = false`, so reporting the zero moved the knob, raised the
    /// handler, and unmuted 40 ms after every press. Set by the mute toggle only; a volume write
    /// clears it, because that write is what puts sound back.
    private var muteLatched = false
    /// **A cast device's volume is write-only from here, so the skin's slider needs a memory.**
    ///
    /// `ChromecastManager.getVolume()` is a stub returning 1.0 and nothing parses a level out of
    /// `RECEIVER_STATUS`, so while a film is on the television there is no readback to poll. The
    /// snapshot was answering `engine.volume` — the idle audio queue's — so every drag of the
    /// skin's volume slider sent its command and then snapped back to the queue's level on the
    /// next tick. Reported 2026-09-20 as "the volume wont work it raises then snaps back to
    /// quiet". Track what was last commanded instead, seeded at the 1.0 a fresh cast starts at.
    private var castVolume: Float = 1
    private var preMuteCastVolume: Float = 0.2
    private var wasCastingVideo = false
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

    /// **A film sent to a Chromecast is still the session the skin's transport belongs to.**
    ///
    /// `localVideoSessionController` answers nil the moment a cast starts — by design, because
    /// there is no local player to drive any more — and everything below it then fell through to
    /// `AudioEngine`: the skin's play button started the audio queue behind the film, its clock
    /// read the queue's, and nothing on the skin could pause the TV. Reported 2026-09-19 as "main
    /// window controls dont control it". Classic has always routed this way
    /// (`MainWindowView` → `WindowManager.isVideoActivePlayback` → `toggleVideoPlayPause`); this is
    /// the same rule on the WMP side, and the manager's own cast-aware calls do the work.
    private static var castingVideo: Bool { videoCast.isCasting }

    /// The cast transport this host drives. The app never replaces it; a test does.
    static var videoCast: any WMPVideoCastTransport = WMPWindowManagerVideoCast()

    /// The artwork WMP exposes belongs to the presentation currently visible to the user. A local
    /// video takes precedence over the audio queue for the same reason `snapshot` does below.
    var artworkTrack: Track? {
        Self.localVideoController?.currentArtworkTrack ?? engine.currentTrack
    }

    /// **What WMP would have called this media, in WMP's own spelling** (W41).
    ///
    /// Every corpus consumer of `sourceURL` classifies the string rather than opening it, and each
    /// classifier is written against Windows syntax: `cd:` for a disc, a backslash for a file,
    /// anything else for the network. A macOS `file:///Users/…` matches none of them, so nine
    /// archives lit their *network* lamp — and two put a buffering readout behind it — for every
    /// local track. So a file URL is stated as the drive-rooted path a Windows player would state,
    /// and nothing else is touched: an `http://`, `mms://` or server URL is already the string WMP
    /// would report, and `Cablemusic` (`indexOf('http')`) and `digitaldj` (`search('://')`) read it
    /// straight. Nothing in this engine reads the value back — it is a readout, never a route to
    /// the file — so the spelling is a presentation conversion in the same seam that states
    /// `crossFadeWindow` in milliseconds because WMP does.
    nonisolated static func sourceURLSpelling(_ url: URL?) -> String {
        guard let url else { return "" }
        guard url.isFileURL else { return url.absoluteString }
        return "C:" + url.path.replacingOccurrences(of: "/", with: "\\")
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
                                    duration: Self.finite($0.duration ?? 0),
                                    sourceURL: Self.sourceURLSpelling($0.url))
        }
        let sourceLayout = engine.eqConfiguration
        let sourceGains = (0..<sourceLayout.bandCount).map { engine.getEQBand($0) }
        let classicGains = EQBandRemapper.remap(gains: sourceGains, from: sourceLayout, to: .classic10)
        var result = WMPHostSnapshot(state: state, currentTime: Self.finite(engine.currentTime),
            duration: Self.finite(engine.duration), volume: reportedVolume(engine.volume, preMute: preMuteVolume),
            balance: Double(max(-1, min(1, engine.balance))), muted: engine.volume == 0,
            shuffle: engine.shuffleEnabled, repeatMode: engine.repeatEnabled,
            bitrate: Double(track?.bitrate ?? 0) * 1_000,
            metadata: WMPMediaMetadata(title: track?.title ?? "", artist: track?.artist ?? "",
                                       album: track?.album ?? "",
                                       sourceURL: Self.sourceURLSpelling(track?.url)),
            playlistIndex: engine.currentIndex, playlistCount: engine.playlist.count,
            playlistItems: playlistItems,
            equalizer: WMPEqualizerSnapshot(enabled: engine.isEQEnabled(),
                enhancedAudio: engine.wmpWOWController.active && engine.wmpWOWController.enabled,
                wowLevel: engine.wmpWOWController.level,
                truBassLevel: engine.wmpWOWController.bassLevel,
                speakerSize: engine.wmpWOWController.speakerSize,
                crossFade: engine.sweetFadeEnabled,
                crossFadeWindow: Self.finite(engine.sweetFadeDuration) * 1_000,
                normalization: engine.volumeNormalizationEnabled,
                preamp: Double(engine.getPreamp()), gains: classicGains.map(Double.init)),
            effects: WMPEffectSelection.shared.snapshot)
        if Self.castingVideo {
            // The readouts follow the cast, not the audio queue standing idle behind it. There is
            // no local picture, so `result.video` stays empty and the skin's `<VIDEO>` box is dark
            // — which is what a film playing on a television looks like from here.
            let cast = Self.videoCast
            syncCastVolumeLatch()
            result.state = cast.isPlaying ? .playing : .paused
            result.currentTime = Self.finite(cast.currentTime)
            result.duration = Self.finite(cast.duration)
            result.metadata = WMPMediaMetadata(title: cast.title ?? "")
            result.volume = reportedVolume(castVolume, preMute: preMuteCastVolume)
            result.muted = castVolume == 0
            result.playlistCount = max(1, result.playlistCount)
            videoEventLatch.reset()
            return result
        }
        syncCastVolumeLatch()
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

        // Running, but the decoder has not answered with a size yet — see `WMPHostSnapshot.State`.
        result.state = video.isPlaying
            ? (video.hasVideoOutput && video.presentationSize.width > 0 ? .playing : .transitioning)
            : .paused
        result.currentTime = Self.finite(video.currentTime)
        result.duration = Self.finite(video.duration)
        // A film is still a media with a source, and the classifiers above read it (W41). The
        // rebuild dropped it with the rest of the audio queue's metadata, so every skin reported a
        // local film as a network stream.
        result.metadata = WMPMediaMetadata(title: video.currentTitle ?? "",
                                           sourceURL: Self.sourceURLSpelling(video.currentArtworkTrack?.url))
        result.volume = reportedVolume(video.volume, preMute: preMuteVolume)
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
        if Self.castingVideo {
            let cast = Self.videoCast
            switch action {
            // `toggleVideoPlayPause` is a toggle, so a skin's *separate* play and pause buttons
            // have to ask what the cast is doing first — pressing play on a playing cast would
            // otherwise pause the television.
            case .play:
                if !cast.isPlaying { cast.togglePlayPause() }
                return
            case .pause:
                if cast.isPlaying { cast.togglePlayPause() }
                return
            case .stop: cast.stop(); return
            // `seekVideoCast` takes a *fraction*, not a time — it multiplies by the cast's own
            // duration itself. Handing it seconds squared the seek past the end of the film, and
            // the receiver answered IDLE, which reads here as "media ended" and tore the cast down.
            case .seek:
                if let fraction = value?.finiteNumber, cast.duration > 0 {
                    cast.seek(fraction: max(0, min(1, fraction)))
                }
                return
            case .volume:
                if let volume = value?.finiteNumber {
                    syncCastVolumeLatch()
                    castVolume = Float(max(0, min(1, volume))); muteLatched = false
                    cast.setVolume(castVolume)
                }
                return
            // Muting the television, not the audio queue standing idle behind it — which is what
            // the fall-through to `engine` below would have done.
            case .toggleMute:
                syncCastVolumeLatch()
                if castVolume > 0 { preMuteCastVolume = castVolume; castVolume = 0 }
                else { castVolume = max(0.01, min(1, preMuteCastVolume)) }
                muteLatched = castVolume == 0
                cast.setVolume(castVolume)
                return
            // A cast film is one item with nowhere to skip to, and `next`/`previous` must not fall
            // through to the audio queue and start a track behind it.
            case .next, .previous, .beginScan, .endScan: return
            default: break
            }
        }
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
                if let volume = value?.finiteNumber { video.volume = Float(max(0, min(1, volume))); muteLatched = false }
                return
            case .toggleMute:
                if video.volume > 0 { preMuteVolume = video.volume; video.volume = 0 }
                else { video.volume = max(0.01, min(1, preMuteVolume)) }
                muteLatched = video.volume == 0
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
            engine.volume = Float(max(0, min(1, volume))); muteLatched = false
        case .balance:
            guard let balance = value?.finiteNumber else { return }
            engine.balance = Float(max(-1, min(1, balance)))
        case .toggleMute:
            if engine.volume > 0 { preMuteVolume = engine.volume; engine.volume = 0 }
            else { engine.volume = max(0.01, min(1, preMuteVolume)) }
            muteLatched = engine.volume == 0
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
        // **Crossfade and normalization are app-wide settings, so they carry no `.wmp` gate.**
        // The WOW group above is gated because WOW *is* WMP-only DSP — retained WMP settings must
        // never activate an effect in Classic, Original or WAL. Crossfade is the opposite case:
        // it is the same Sweet Fades the other three families drive from their own menus, and a
        // `.wmz`'s crossfade button is that setting's control while WMP is the skin on screen.
        // `.setEQEnabled` below is the existing precedent for an app-wide control on this switch.
        case .setCrossFade:
            guard let enabled = value?.finiteNumber else { return }
            engine.sweetFadeEnabled = enabled != 0
        case .setCrossFadeWindow:
            // The skin states milliseconds; `sweetFadeDuration` is seconds.
            guard let milliseconds = value?.finiteNumber, milliseconds >= 0 else { return }
            engine.sweetFadeDuration = min(20, milliseconds / 1_000)
        case .setNormalization:
            guard let enabled = value?.finiteNumber else { return }
            engine.volumeNormalizationEnabled = enabled != 0
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

    /// A cast starts at the receiver's own full volume, so the remembered level is only valid
    /// for the life of one cast session.
    private func syncCastVolumeLatch() {
        let casting = Self.castingVideo
        defer { wasCastingVideo = casting }
        guard casting != wasCastingVideo else { return }
        castVolume = 1
        preMuteCastVolume = 0.2
        muteLatched = false
    }

    /// The level a skin reads: the one it was muted from while the mute toggle holds the output
    /// at zero, the output itself otherwise — so a slider dragged to zero still reads zero.
    private func reportedVolume(_ output: Float, preMute: Float) -> Double {
        Double(max(0, min(1, muteLatched && output == 0 ? preMute : output)))
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
