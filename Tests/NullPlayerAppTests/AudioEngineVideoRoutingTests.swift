import XCTest
@testable import NullPlayer

final class AudioEngineVideoRoutingTests: XCTestCase {
    /// A playlist film replaces the playing song: the engine hands it over stopped at 0:00. Left
    /// `.playing` with the song's start date until the video window paused it, `currentTime`
    /// read the song's elapsed time for the film (M26).
    func testPlayingAFilmRowStopsTheOutgoingSongAtZero() throws {
        let song = try TestAudioFile.temporaryWAV(seconds: 10, tone: true)
        defer { try? FileManager.default.removeItem(at: song) }
        let film = Track(url: URL(fileURLWithPath: "/tmp/film.mp4"), title: "Film", mediaType: .video)

        let engine = AudioEngine()
        defer { engine.stop() }
        // No video window: the hand-over stops at the engine.
        AudioEngine.isHeadless = true
        defer { AudioEngine.isHeadless = false }
        engine.playNow([Track(url: song, title: "Song"), film])
        XCTAssertEqual(engine.state, .playing)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        engine.playTrack(at: 1)

        XCTAssertEqual(engine.currentTrack?.id, film.id)
        XCTAssertEqual(engine.state, .stopped)
        XCTAssertEqual(engine.currentTime, 0)
    }

    /// The playlist's Add Files, Add Directory and Load Playlist all go through `loadFiles`, which
    /// rejected a film as "Unsupported format" (M27). The library's validation still refuses one:
    /// video is imported by its own path.
    func testLoadFilesKeepsAFilmRowAndTheLibraryStillRefusesIt() throws {
        let film = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mp4")
        try Data().write(to: film)
        defer { try? FileManager.default.removeItem(at: film) }

        let engine = AudioEngine()
        defer { engine.stop() }
        AudioEngine.isHeadless = true
        defer { AudioEngine.isHeadless = false }
        engine.loadFiles([film])

        XCTAssertEqual(engine.playlist.map(\.url), [film])
        XCTAssertEqual(engine.playlist.first?.mediaType, .video)
        XCTAssertNotNil(AudioFileValidator.quickValidate(url: film, includeVideo: false))
    }
}
