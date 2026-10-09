import AppKit

/// The main window's keyboard shortcuts, shared by the Modern main window and an Audion face: space
/// toggles play, Return stops, the arrows seek 5 s and step the volume, z x c v b are the transport,
/// s and r toggle shuffle and repeat, and l, e and p toggle the library, equalizer and playlist.
/// While a video plays, its own player takes play, stop and seek.
@MainActor
enum MainWindowKeys {
    /// Performs the key's action, or answers false for a key that has none.
    static func perform(_ event: NSEvent) -> Bool {
        let audioEngine = WindowManager.shared.audioEngine

        switch event.keyCode {
        case 49: // Space - play/pause
            if WindowManager.shared.isVideoActivePlayback {
                WindowManager.shared.toggleVideoPlayPause()
            } else if audioEngine.state == .playing {
                audioEngine.pause()
            } else {
                audioEngine.play()
            }

        case 123: // Left arrow - seek backward 5s
            if WindowManager.shared.isVideoActivePlayback {
                WindowManager.shared.skipVideoBackward(5)
            } else {
                audioEngine.seek(to: max(0, audioEngine.currentTime - 5))
            }

        case 124: // Right arrow - seek forward 5s
            if WindowManager.shared.isVideoActivePlayback {
                WindowManager.shared.skipVideoForward(5)
            } else {
                audioEngine.seek(to: min(audioEngine.duration, audioEngine.currentTime + 5))
            }

        case 125: // Down arrow - volume down
            audioEngine.volume = max(0, audioEngine.volume - 0.05)

        case 126: // Up arrow - volume up
            audioEngine.volume = min(1, audioEngine.volume + 0.05)

        case 36: // Return - stop
            if WindowManager.shared.isVideoActivePlayback {
                WindowManager.shared.stopVideo()
            } else {
                audioEngine.stop()
            }

        default:
            switch event.characters {
            case "z": audioEngine.previous()
            case "x": audioEngine.play()
            case "c": audioEngine.pause()
            case "v": audioEngine.stop()
            case "b": audioEngine.next()
            case "s": audioEngine.shuffleEnabled.toggle()
            case "r": audioEngine.repeatEnabled.toggle()
            case "l": WindowManager.shared.togglePlexBrowser()
            case "e": WindowManager.shared.toggleEqualizer()
            case "p": WindowManager.shared.togglePlaylist()
            default: return false
            }
        }
        return true
    }
}
