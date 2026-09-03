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
        // No `WindowManager` in the suite: with no session the transport must not consult one either.
        host.videoTransport = { nil }
        return host
    }

    /// Records what the skin's transport sent to the film, so the fall-through can be proved without
    /// a live `VideoPlayerWindowController`.
    private final class TransportRecorder {
        var toggles = 0
        var stops = 0
        var skips: [TimeInterval] = []
        var seeks: [TimeInterval] = []

        var transport: WinampModernVideoTransport {
            WinampModernVideoTransport(togglePlayPause: { self.toggles += 1 },
                                       stop: { self.stops += 1 },
                                       skip: { self.skips.append($0) },
                                       seek: { self.seeks.append($0) })
        }
    }

    private func makeHostWithFilm(engine: AudioEngine = AudioEngine())
        -> (WinampModernAudioEngineHost, TransportRecorder) {
        let host = makeHost(engine: engine, session: playingFilm)
        let recorder = TransportRecorder()
        host.videoTransport = { recorder.transport }
        return (host, recorder)
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

    // MARK: - The transport drives the film (step 1)

    /// PLAY and PAUSE **both** toggle, which is what Classic does: a skin's single play/pause button
    /// sends whichever of the two its artwork currently shows, and either must flip the film.
    func testPlayAndPauseBothToggleTheFilmRatherThanReachingTheEngine() {
        let engine = AudioEngine()
        let (host, recorder) = makeHostWithFilm(engine: engine)

        host.play()
        host.pause()

        XCTAssertEqual(recorder.toggles, 2)
        XCTAssertEqual(engine.state, .stopped, "the audio engine must be left alone during a film")
    }

    func testStopStopsTheFilm() {
        let (host, recorder) = makeHostWithFilm()

        host.stop()

        XCTAssertEqual(recorder.stops, 1)
        XCTAssertEqual(recorder.toggles, 0)
    }

    /// PREV/NEXT skip ∓10s, mirroring Classic. A queued film advances only on its own end — the
    /// accepted parity limit, not an oversight.
    func testPreviousAndNextSkipTenSecondsWithinTheFilm() {
        let (host, recorder) = makeHostWithFilm()

        host.previous()
        host.next()

        XCTAssertEqual(recorder.skips, [-10, 10])
    }

    func testSeekReachesTheFilmRatherThanTheEngine() {
        let engine = AudioEngine()
        let (host, recorder) = makeHostWithFilm(engine: engine)

        host.seek(to: 123)

        XCTAssertEqual(recorder.seeks, [123])
        XCTAssertEqual(engine.currentTime, 0)
    }

    /// The regression that would break ordinary audio: with no film, all six still reach the engine.
    func testWithNoFilmEveryTransportCommandStillReachesTheEngine() {
        let engine = AudioEngine()
        let host = makeHost(engine: engine, session: nil)
        var reached = 0
        host.videoTransport = { reached += 1; return nil }

        host.play()
        host.pause()
        host.stop()
        host.previous()
        host.next()
        host.seek(to: 5)

        XCTAssertEqual(reached, 6, "each command must consult the seam and then fall through")
        XCTAssertEqual(engine.state, .stopped)
        XCTAssertEqual(engine.currentTime, 0)
    }

    // MARK: - The rest of the readouts (step 2)

    /// `songname` is the readout most skins print, and it is the one that showed the *previous audio
    /// track* through the whole of a film.
    func testTheDisplayTitleIsTheFilmsTitle() {
        let host = makeHost(session: playingFilm)

        XCTAssertEqual(host.trackDisplayTitle, "Rear Window")
    }

    /// Everything but the title and the clock answers empty, so a skin **hides** those lines rather
    /// than printing the stale audio track's bitrate, path and artist against the film's title.
    func testEveryOtherReadoutIsEmptyDuringAFilmRatherThanTheStaleAudioTracks() throws {
        let host = makeHost(engine: try loadedEngine(), session: playingFilm)

        XCTAssertEqual(host.trackInfo, "")
        XCTAssertEqual(host.trackPath, "")
        XCTAssertEqual(host.decoderName, "")
        XCTAssertEqual(host.trackArtist, "")
        XCTAssertEqual(host.trackAlbum, "")
        XCTAssertEqual(host.bitrateKbps, 0)
        XCTAssertEqual(host.sampleRateHz, 0)
        XCTAssertEqual(host.channelCount, 0)
        XCTAssertEqual(host.playItemMetadata(forKey: "genre"), "")
    }

    /// …and a stopped session hands every one of them straight back. Same host, same engine, the
    /// session closure the only thing that moves — so this is the fall-through and nothing else.
    func testAStoppedSessionRestoresEveryReadoutToTheEnginesTrack() throws {
        let engine = try loadedEngine()
        let host = makeHost(engine: engine, session: playingFilm)
        XCTAssertEqual(host.trackArtist, "", "precondition: the film is hiding the audio track")

        host.videoSession = { nil }

        XCTAssertEqual(host.trackDisplayTitle, "Miles Davis - So What")
        XCTAssertEqual(host.trackArtist, "Miles Davis")
        XCTAssertEqual(host.trackAlbum, "Kind of Blue")
        XCTAssertEqual(host.trackInfo, "Miles Davis - Kind of Blue")
        XCTAssertEqual(host.decoderName, "PCM Wave")
        XCTAssertEqual(host.bitrateKbps, 320)
        XCTAssertEqual(host.sampleRateHz, 44_100)
        XCTAssertEqual(host.channelCount, 2)
        XCTAssertFalse(host.trackPath.isEmpty)
    }

    /// An engine with a real `currentTrack`. `loadTracks` filters out a file that does not exist (and
    /// puts up an alert for it), so the stale audio track has to be backed by one — a fraction of a
    /// second of silence, stopped again immediately; only its metadata is under test.
    private func loadedEngine() throws -> AudioEngine {
        let engine = AudioEngine()
        engine.volume = 0
        engine.loadTracks([Track(url: try Self.silentWAV(), title: "So What", artist: "Miles Davis",
                                 album: "Kind of Blue", bitrate: 320, sampleRate: 44_100, channels: 2)])
        engine.stop()
        return engine
    }

    /// 0.05 s of 44.1 kHz stereo silence, written once per run.
    private static func silentWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("np-phase79-silence.wav")
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        let frames = 2_205, channels = 2, rate = 44_100
        let dataBytes = frames * channels * 2
        var wav = Data()
        func append(_ string: String) { wav.append(contentsOf: Array(string.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        append("RIFF"); append32(UInt32(36 + dataBytes)); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(UInt16(channels))
        append32(UInt32(rate)); append32(UInt32(rate * channels * 2))
        append16(UInt16(channels * 2)); append16(16)
        append("data"); append32(UInt32(dataBytes))
        wav.append(Data(count: dataBytes))
        try wav.write(to: url)
        return url
    }
}
