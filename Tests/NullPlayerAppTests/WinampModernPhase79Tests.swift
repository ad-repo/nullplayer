import XCTest
@testable import NullPlayer

/// Phase 79 — B63: a `.wal` skin's readouts follow the **video** session while a film plays.
///
/// `AudioEngine` is deliberately paused for the whole of a video session, so a host that answers
/// only from it reports a skin's transport as paused and its clock as 0:00 while the picture plays
/// in cPro-Bento's own Video tab. The substitution is made once, at the host — the seam every `.wal`
/// readout, script binding and `getPlayItemMetaDataString` key already goes through.
final class WinampModernPhase79Tests: XCTestCase {

    private func makeHost(engine: AudioEngine = AudioEngine(),
                          session: WinampModernVideoSession?) -> WinampModernAudioEngineHost {
        let host = WinampModernAudioEngineHost(engine: engine, artworkLoading: { false }) { (nil, nil) }
        host.videoSession = { session }
        return host
    }

    private var playingFilm: WinampModernVideoSession {
        WinampModernVideoSession(state: .playing, currentTime: 95, duration: 380, title: "Rear Window")
    }

    func testAPlayingFilmDrivesTheTransportClockAndTitle() {
        let host = makeHost(session: playingFilm)

        XCTAssertEqual(host.playbackState, .playing,
                       "the audio engine is paused for the film; the skin must not read that as a pause")
        XCTAssertEqual(host.currentTime, 95)
        XCTAssertEqual(host.duration, 380)
        XCTAssertEqual(host.trackTitle, "Rear Window")
    }

    func testAPausedFilmIsReportedPausedRatherThanAsTheAudioEnginesState() {
        let host = makeHost(session: WinampModernVideoSession(state: .paused, currentTime: 12,
                                                              duration: 380, title: "Rear Window"))

        XCTAssertEqual(host.playbackState, .paused)
        XCTAssertEqual(host.currentTime, 12)
    }

    /// The fallback is the whole of the previous behaviour, and every skin without a film is on it.
    func testWithNoVideoSessionTheHostIsTheAudioEnginesAgain() {
        let engine = AudioEngine()
        let host = makeHost(engine: engine, session: nil)

        XCTAssertEqual(host.playbackState, engine.state)
        XCTAssertEqual(host.currentTime, engine.currentTime)
        XCTAssertEqual(host.duration, engine.duration)
        XCTAssertEqual(host.trackTitle, engine.currentTrack?.title ?? "")
    }

    /// A skin's clock is as often a `<text display="timeelapsed">` filled by a script as a rect the
    /// renderer draws, so the metadata table has to answer from the same clock — otherwise the two
    /// halves of one skin disagree about how far into the film it is.
    func testTheMetadataTableAnswersFromTheFilmsClockAndTitle() {
        let host = makeHost(session: playingFilm)

        XCTAssertEqual(host.playItemMetadata(forKey: "title"), "Rear Window")
        XCTAssertEqual(host.playItemMetadata(forKey: "timeelapsed"), "1:35")
        XCTAssertEqual(host.playItemMetadata(forKey: "timeremaining"), "4:45")
        XCTAssertEqual(host.playItemMetadata(forKey: "length"), "380000")
    }

    /// The session is read through a closure rather than captured, because it is polled from the
    /// clock ten times a second: a value snapshotted at load would freeze the film's readout at
    /// whatever it said when the skin was loaded.
    func testTheSessionIsReReadRatherThanSnapshotted() {
        var session = playingFilm
        let host = makeHost(session: nil)
        host.videoSession = { session }

        XCTAssertEqual(host.currentTime, 95)
        session.currentTime = 96
        XCTAssertEqual(host.currentTime, 96)
    }
}
