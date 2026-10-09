import Foundation

/// What the player is doing, as a face draws it: a pure snapshot, built from `AudioEngine` by the
/// AppKit layer and by hand in the harness. The scene reads nothing else about playback.
struct AudionFaceHostState: Equatable {
    enum PlayState: String { case stopped, playing, paused }

    /// Which of the face's three animations runs (FaceKit `AnimationType`).
    enum StreamPhase: String { case none, connecting, streaming, lag }

    var playState = PlayState.stopped
    var elapsedSeconds = 0
    /// Zero means no track: stop is disabled and the MP3, NET and pause indicators stay off.
    var durationSeconds = 0
    /// The playlist position, 1-based. Nil draws the blank track-digit frame, as FaceKit always does.
    var trackIndex: Int?
    var volume = 0.5
    var title: String?
    var artist: String?
    var album: String?
    var format: String?
    var streamPhase = StreamPhase.none
    var isWindowActive = true
    /// Pins the album marquee and truncates it instead (FaceKit reads the system setting).
    var reduceMotion = false

    var isPlaying: Bool { playState == .playing }

    /// The artist line shows the title, as Panic's player fills it.
    var artistLine: String? { title }

    /// The album line is `artist—album—format`, skipping the parts there are none of.
    var albumLine: String? {
        let parts = [artist, album, format].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "—")
    }
}
