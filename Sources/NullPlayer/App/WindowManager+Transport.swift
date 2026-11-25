import Foundation

/// A transport button: the Classic main window's and the Winamp playlist editor's mini transport.
enum TransportAction {
    case previous, play, pause, stop, next
}

extension WindowManager {
    /// A transport press, acting on the video when one is the active playback (previous / next
    /// skip it 10 seconds), otherwise on the audio queue.
    func perform(_ action: TransportAction) {
        let video = isVideoActivePlayback
        switch action {
        case .previous: video ? skipVideoBackward(10) : audioEngine.previous()
        case .play: video ? toggleVideoPlayPause() : audioEngine.play()
        case .pause: video ? toggleVideoPlayPause() : audioEngine.pause()
        case .stop: video ? stopVideo() : audioEngine.stop()
        case .next: video ? skipVideoForward(10) : audioEngine.next()
        }
    }
}
