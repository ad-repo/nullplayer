#if os(Linux)
import Foundation
import NullPlayerCore
import NullPlayerPlayback

final class LinuxAppStateManager {
    private let stateURL: URL
    private let backendCapabilities: AudioBackendCapabilities

    init(backendCapabilities: AudioBackendCapabilities) {
        self.backendCapabilities = backendCapabilities
        self.stateURL = LinuxPathResolver.configDirectory().appendingPathComponent("appstate.json")
    }

    func saveState(engine: AudioEngineFacade, windows: LinuxWindowCoordinator) {
        windows.refreshVisibilityState()

        let frameHints = windows.lastKnownFrameHints

        let appState = AppState(
            isPlaylistVisible: windows.isWindowVisible(.playlist),
            isEqualizerVisible: windows.isWindowVisible(.equalizer),
            isPlexBrowserVisible: windows.isWindowVisible(.libraryBrowser),
            isProjectMVisible: windows.isWindowVisible(.projectM),
            isSpectrumVisible: windows.isWindowVisible(.spectrum),
            isWaveformVisible: windows.isWindowVisible(.waveform),
            mainWindowFrame: frameString(frameHints[.main]),
            playlistWindowFrame: frameString(frameHints[.playlist]),
            equalizerWindowFrame: frameString(frameHints[.equalizer]),
            plexBrowserWindowFrame: frameString(frameHints[.libraryBrowser]),
            projectMWindowFrame: frameString(frameHints[.projectM]),
            spectrumWindowFrame: frameString(frameHints[.spectrum]),
            waveformWindowFrame: frameString(frameHints[.waveform]),
            volume: engine.volume,
            balance: engine.balance,
            shuffleEnabled: engine.shuffleEnabled,
            repeatEnabled: engine.repeatEnabled,
            gaplessPlaybackEnabled: backendCapabilities.supportsGaplessPlayback ? engine.gaplessPlaybackEnabled : false,
            volumeNormalizationEnabled: engine.volumeNormalizationEnabled,
            sweetFadeEnabled: backendCapabilities.supportsSweetFade ? engine.sweetFadeEnabled : false,
            sweetFadeDuration: backendCapabilities.supportsSweetFade ? engine.sweetFadeDuration : 5.0,
            eqEnabled: engine.isEQEnabled(),
            eqPreamp: engine.getPreamp(),
            eqBands: (0..<engine.eqConfiguration.bandCount).map { engine.getEQBand($0) },
            playlistURLs: engine.playlist.map { $0.url.absoluteString },
            currentTrackIndex: engine.currentIndex,
            playbackPosition: engine.currentTime,
            wasPlaying: engine.state == .playing,
            timeDisplayMode: "elapsed",
            isAlwaysOnTop: false,
            customSkinPath: nil,
            baseSkinIndex: nil,
            stateVersion: 2
        )

        do {
            try FileManager.default.createDirectory(
                at: LinuxPathResolver.configDirectory(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(appState)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            fputs("LinuxAppStateManager: failed to save: \(error)\n", stderr)
        }
    }

    func restoreSettingsState(engine: AudioEngineFacade, windows: LinuxWindowCoordinator) {
        guard let state = loadState() else { return }

        engine.volume = state.volume
        engine.balance = state.balance
        engine.shuffleEnabled = state.shuffleEnabled
        engine.repeatEnabled = state.repeatEnabled
        engine.volumeNormalizationEnabled = state.volumeNormalizationEnabled
        engine.setEQEnabled(state.eqEnabled)
        engine.setPreamp(state.eqPreamp)

        if backendCapabilities.supportsGaplessPlayback {
            engine.gaplessPlaybackEnabled = state.gaplessPlaybackEnabled
        }
        if backendCapabilities.supportsSweetFade {
            engine.sweetFadeEnabled = state.sweetFadeEnabled
            engine.sweetFadeDuration = state.sweetFadeDuration
        }

        for (index, gain) in state.eqBands.enumerated() where index < engine.eqConfiguration.bandCount {
            engine.setEQBand(index, gain: gain)
        }

        windows.showMainWindow()
        windows.setWindowVisible(.libraryBrowser, visible: state.isPlexBrowserVisible)
        windows.setWindowVisible(.playlist, visible: state.isPlaylistVisible)
        windows.setWindowVisible(.equalizer, visible: state.isEqualizerVisible)
        windows.setWindowVisible(.spectrum, visible: state.isSpectrumVisible)
        windows.setWindowVisible(.waveform, visible: state.isWaveformVisible)
        windows.setWindowVisible(.projectM, visible: state.isProjectMVisible)
        windows.refreshVisibilityState()
    }

    func restorePlaylistState(engine: AudioEngineFacade) {
        guard let state = loadState() else { return }
        let tracks = state.playlistURLs.compactMap(Self.urlFromStateString).map { Track(url: $0) }
        guard !tracks.isEmpty else { return }

        engine.setPlaylistTracks(tracks)
        if state.currentTrackIndex >= 0 && state.currentTrackIndex < tracks.count {
            engine.selectTrackForDisplay(at: state.currentTrackIndex)
            if state.wasPlaying {
                engine.playTrack(at: state.currentTrackIndex)
                if state.playbackPosition > 0 {
                    engine.seek(to: state.playbackPosition)
                }
            }
        }
    }

    private func loadState() -> AppState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(AppState.self, from: data)
    }

    private static func urlFromStateString(_ raw: String) -> URL? {
        if let url = URL(string: raw), !url.absoluteString.isEmpty {
            return url
        }
        return URL(fileURLWithPath: raw)
    }

    private func frameString(_ hint: LinuxWindowFrameHint?) -> String? {
        guard let hint else { return nil }
        return "\(hint.width)x\(hint.height)"
    }
}
#endif
