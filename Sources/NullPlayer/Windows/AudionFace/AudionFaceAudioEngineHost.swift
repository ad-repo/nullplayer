import AppKit

/// What the face window asks NullPlayer to do: a pressed button, or a slider's value.
enum AudionFaceCommand: Equatable {
    case button(AudionFace.ButtonRole)
    /// 0–1.
    case volume(Double)
    /// Seconds into the track.
    case seek(Double)
}

/// `AudioEngine` to `AudionFaceHostState`, and an `AudionFaceCommand` back to a NullPlayer action
/// (decision record § *Button mapping*). The scene reads only the snapshot. The volume and info
/// buttons open `AudionFaceMainView`'s own popups and never arrive here.
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
        state.streamPhase = streamPhase(of: track)
        state.isWindowActive = isWindowActive
        state.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        return state
    }

    /// Radio reports its connection; any other non-file track reads as streaming.
    // ponytail: a server stream's own buffering is private to `AudioEngine`; expose it if a face's
    // connecting or lag animation is wanted outside radio.
    private static func streamPhase(of track: Track?) -> AudionFaceHostState.StreamPhase {
        guard let track, !track.url.isFileURL else { return .none }
        guard RadioManager.shared.isActive else { return .streaming }
        switch RadioManager.shared.connectionState {
        case .connecting: return .connecting
        case .reconnecting: return .lag
        default: return .streaming
        }
    }

    static func perform(_ command: AudionFaceCommand, engine: AudioEngine) {
        switch command {
        case .volume(let value): engine.volume = Float(value)
        case .seek(let seconds): engine.seek(to: seconds)
        case .button(let role): perform(role, engine: engine)
        }
    }

    private static func perform(_ role: AudionFace.ButtonRole, engine: AudioEngine) {
        switch role {
        case .play: engine.play()
        case .pause: engine.pause()
        case .stop: engine.stop()
        case .rewind: engine.previous()
        case .fastForward: engine.next()
        case .eject: MenuActions.shared.openFile()
        case .playlist: WindowManager.shared.togglePlaylist()
        case .close: NSApp.terminate(nil)
        case .mode: WindowManager.shared.toggleMediaLibrary()
        case .info, .volume: break
        }
    }

    private static func seconds(_ time: TimeInterval) -> Int {
        time.isFinite && time > 0 ? Int(time) : 0
    }
}
