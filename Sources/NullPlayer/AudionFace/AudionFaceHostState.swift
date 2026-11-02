import Foundation

/// What the player is doing, as a face draws it: a pure snapshot, built from `AudioEngine` by the
/// AppKit layer and by hand in the harness. The scene reads nothing else about playback.
struct AudionFaceHostState: Equatable {
    enum PlayState: String { case stopped, playing, paused }

    /// Which of the face's three animations runs (FaceKit `AnimationType`).
    enum StreamPhase: String { case none, connecting, streaming, lag }

    var playState = PlayState.stopped
    var elapsedSeconds = 0
    var durationSeconds = 0
    /// The playlist position, 1-based. Nil draws the blank track-digit frame, as FaceKit always does.
    var trackIndex: Int?
    var title: String?
    var artist: String?
    var streamPhase = StreamPhase.none
    var isWindowActive = true
    /// Pins the album marquee and truncates it instead (FaceKit reads the system setting).
    var reduceMotion = false

    var isPlaying: Bool { playState == .playing }

    /// A track is loaded: one with a duration (FaceKit's whole rule), or a live stream, which has
    /// none. Without one, stop is disabled and the MP3, NET and pause indicators stay off.
    var hasTrack: Bool { durationSeconds != 0 || streamPhase != .none }

    /// The track has a position to move to, which a live stream does not: the time digits open the
    /// position slider only then.
    var isSeekable: Bool { durationSeconds > 0 }

    /// The artist line shows the artist and the album line the title, as Panic's face previews and
    /// Rackview's ARTIST/TRACK labels show (#662); an empty one shows nothing.
    var artistLine: String? { artist.flatMap { $0.isEmpty ? nil : $0 } }
    var albumLine: String? { title.flatMap { $0.isEmpty ? nil : $0 } }
}
