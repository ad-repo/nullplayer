import Foundation

@MainActor
final class WMPAudioEngineHost: WMPHost {
    private let engine: AudioEngine
    private var scanTimer: Timer?
    private var scanDirection: WMPScanDirection?
    private var preMuteVolume: Float = 0.2

    init(audioEngine: AudioEngine) { engine = audioEngine }

    var snapshot: WMPHostSnapshot {
        let state: WMPHostSnapshot.State
        switch engine.state {
        case .stopped: state = .stopped
        case .playing: state = .playing
        case .paused: state = .paused
        }
        let track = engine.currentTrack
        return WMPHostSnapshot(state: state, currentTime: Self.finite(engine.currentTime),
            duration: Self.finite(engine.duration), volume: Double(max(0, min(1, engine.volume))),
            balance: Double(max(-1, min(1, engine.balance))), muted: engine.volume == 0,
            shuffle: engine.shuffleEnabled, repeatMode: engine.repeatEnabled,
            metadata: WMPMediaMetadata(title: track?.title ?? "", artist: track?.artist ?? "",
                                       album: track?.album ?? ""),
            playlistIndex: engine.currentIndex, playlistCount: engine.playlist.count)
    }

    func perform(_ action: WMPTransportAction, value: WMPHostValue?) {
        switch action {
        case .play: engine.play()
        case .pause: engine.pause()
        case .stop: engine.stop()
        case .previous: engine.previous()
        case .next: engine.next()
        case let .beginScan(direction): startScanning(direction)
        case .endScan: stopContinuousCommands()
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
        }
    }

    func stopContinuousCommands() {
        scanTimer?.invalidate()
        scanTimer = nil
        scanDirection = nil
    }

    private func startScanning(_ direction: WMPScanDirection) {
        stopContinuousCommands()
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
