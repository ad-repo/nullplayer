import Foundation
import NullPlayerCore
import NullPlayerPlayback

final class LinuxCLIPlayer: AudioEngineDelegate {
    private let engine: AudioEngineFacade
    private let outputRouting: any AudioOutputRouting
    private let display: LinuxCLIDisplay
    private let options: LinuxCLIOptions
    private let quitHandler: (Int32) -> Void

    private var isQuitting = false

    init(
        engine: AudioEngineFacade,
        outputRouting: any AudioOutputRouting,
        display: LinuxCLIDisplay,
        options: LinuxCLIOptions,
        quitHandler: @escaping (Int32) -> Void
    ) {
        self.engine = engine
        self.outputRouting = outputRouting
        self.display = display
        self.options = options
        self.quitHandler = quitHandler
        self.engine.delegate = self
    }

    func listOutputs() {
        outputRouting.refreshOutputs()
        display.printOutputs(outputRouting.outputDevices, current: outputRouting.currentOutputDevice)
    }

    func startPlayback(with tracks: [Track]) {
        configurePlaybackOptions()

        if let output = options.output {
            applyOutputSelection(output)
        }

        display.printBanner()
        display.startKeyboardCapture { [weak self] action in
            self?.handleKeyboard(action)
        }

        engine.loadTracks(tracks)
        engine.play()
        renderStatus()
    }

    func requestQuit(exitCode: Int32 = 0) {
        guard !isQuitting else { return }
        isQuitting = true

        engine.stop()
        display.stopKeyboardCapture()
        display.restoreTerminal()
        quitHandler(exitCode)
    }

    private func configurePlaybackOptions() {
        engine.shuffleEnabled = options.shuffle
        engine.repeatEnabled = options.repeatOne

        if let volume = options.volume {
            engine.volume = Float(volume) / 100
        }

        if let eq = options.eq {
            applyEQ(eq)
        }
    }

    private func applyOutputSelection(_ output: String) {
        outputRouting.refreshOutputs()
        let devices = outputRouting.outputDevices
        if let exact = devices.first(where: { $0.persistentID == output }) {
            _ = outputRouting.selectOutputDevice(persistentID: exact.persistentID)
            return
        }

        if let byName = devices.first(where: { $0.name.caseInsensitiveCompare(output) == .orderedSame }) {
            _ = outputRouting.selectOutputDevice(persistentID: byName.persistentID)
            return
        }

        display.printMessage("Output '\(output)' not found. Use --list-outputs to inspect available devices.")
    }

    private func applyEQ(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized == "off" {
            engine.setEQEnabled(false)
            return
        }

        if normalized == "flat" {
            engine.setEQEnabled(true)
            for band in 0..<engine.eqConfiguration.bandCount {
                engine.setEQBand(band, gain: 0)
            }
            engine.setPreamp(0)
            return
        }

        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == engine.eqConfiguration.bandCount else {
            display.printMessage("Invalid --eq value. Provide 'off', 'flat', or \(engine.eqConfiguration.bandCount) comma-separated gains.")
            return
        }

        let gains = parts.compactMap(Float.init)
        guard gains.count == engine.eqConfiguration.bandCount else {
            display.printMessage("Invalid --eq gains. Values must be numeric.")
            return
        }

        engine.setEQEnabled(true)
        engine.setPreamp(0)
        for (index, gain) in gains.enumerated() {
            engine.setEQBand(index, gain: gain)
        }
    }

    private func handleKeyboard(_ action: LinuxCLIInputAction) {
        switch action {
        case .togglePlayPause:
            if engine.state == .playing {
                engine.pause()
            } else {
                engine.play()
            }

        case .next:
            engine.next()

        case .previous:
            engine.previous()

        case .seekForward:
            engine.seekBy(seconds: 10)

        case .seekBackward:
            engine.seekBy(seconds: -10)

        case .volumeUp:
            engine.volume = min(1.0, engine.volume + 0.05)
            renderStatus()

        case .volumeDown:
            engine.volume = max(0.0, engine.volume - 0.05)
            renderStatus()

        case .quit:
            requestQuit()
        }
    }

    private func renderStatus() {
        display.printNowPlaying(
            track: engine.currentTrack,
            state: engine.state,
            current: engine.currentTime,
            duration: engine.duration,
            volume: engine.volume,
            eqEnabled: engine.isEQEnabled()
        )
    }

    // MARK: - AudioEngineDelegate

    func audioEngineDidChangeState(_ state: PlaybackState) {
        renderStatus()

        if state == .stopped,
           options.repeatAll,
           !engine.playlist.isEmpty,
           !isQuitting {
            engine.playTrack(at: 0)
        }
    }

    func audioEngineDidUpdateTime(current: TimeInterval, duration: TimeInterval) {
        _ = current
        _ = duration
        renderStatus()
    }

    func audioEngineDidChangeTrack(_ track: Track?) {
        _ = track
        renderStatus()
    }

    func audioEngineDidUpdateSpectrum(_ levels: [Float]) {
        _ = levels
    }

    func audioEngineDidChangePlaylist() {}

    func audioEngineDidFailToLoadTrack(_ track: Track, error: Error) {
        display.printMessage("\nFailed to load '\(track.title)': \(error.localizedDescription)")
        if !isQuitting {
            engine.next()
        }
    }
}
