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

    init(audioEngine: AudioEngine) { engine = audioEngine }

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
        return WMPHostSnapshot(state: state, currentTime: Self.finite(engine.currentTime),
            duration: Self.finite(engine.duration), volume: Double(max(0, min(1, engine.volume))),
            balance: Double(max(-1, min(1, engine.balance))), muted: engine.volume == 0,
            shuffle: engine.shuffleEnabled, repeatMode: engine.repeatEnabled,
            metadata: WMPMediaMetadata(title: track?.title ?? "", artist: track?.artist ?? "",
                                       album: track?.album ?? ""),
            playlistIndex: engine.currentIndex, playlistCount: engine.playlist.count,
            playlistItems: playlistItems,
            equalizer: WMPEqualizerSnapshot(enabled: engine.isEQEnabled(),
                preamp: Double(engine.getPreamp()), gains: classicGains.map(Double.init)))
    }

    func perform(_ action: WMPTransportAction, value: WMPHostValue?) {
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
        case .setPreamp:
            guard let gain = value?.finiteNumber else { return }
            engine.setPreamp(Float(max(-12, min(12, gain))))
        }
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
        engine.seekBy(seconds: scanDirection == .forward ? 5 : -5)
    }

    private static func finite(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }
}
