import AppKit

/// `AudioEngine` to `AudionFaceHostState`, and a pressed face button back to a NullPlayer action
/// (decision record § *Button mapping*). The scene reads only the snapshot.
@MainActor
enum AudionFaceAudioEngineHost {
    static func snapshot(_ engine: AudioEngine, isWindowActive: Bool) -> AudionFaceHostState {
        var state = AudionFaceHostState()
        switch engine.state {
        case .stopped: state.playState = .stopped
        case .playing: state.playState = .playing
        case .paused: state.playState = .paused
        }
        let track = engine.currentTrack
        state.elapsedSeconds = seconds(engine.currentTime)
        state.durationSeconds = seconds(engine.duration)
        state.trackIndex = engine.currentIndex >= 0 ? engine.currentIndex + 1 : nil
        state.title = track?.title
        state.artist = track?.artist
        state.album = track?.album
        state.format = track.map { $0.url.pathExtension.uppercased() }.flatMap { $0.isEmpty ? nil : $0 }
        // ponytail: any non-file track reads as streaming; connecting and lag need the stream
        // player's buffering state (Phase 4).
        state.streamPhase = track.map { $0.url.isFileURL ? .none : .streaming } ?? .none
        state.isWindowActive = isWindowActive
        state.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        return state
    }

    static func perform(_ role: AudionFace.ButtonRole, engine: AudioEngine) {
        switch role {
        case .play: engine.play()
        case .pause: engine.pause()
        case .stop: engine.stop()
        case .rewind: engine.previous()
        case .fastForward: engine.next()
        case .eject: MenuActions.shared.openFile()
        case .playlist: WindowManager.shared.togglePlaylist()
        // Phase 4: volume slider, info, mode, close.
        case .close, .info, .volume, .mode: break
        }
    }

    private static func seconds(_ time: TimeInterval) -> Int {
        time.isFinite && time > 0 ? Int(time) : 0
    }
}
