import XCTest
@testable import NullPlayer

/// The format a lightweight import leaves out, read back from the file and filled into the row.
final class TrackFormatTests: XCTestCase {
    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Audio/\(name)")
    }

    /// `AVAudioFile` opens MPEG-4 Opus with zero frames (macOS 27; older systems refuse it outright,
    /// the branch that reads the asset's own track format), so the duration comes from the asset.
    func testAnOpusFileReadsInFull() async throws {
        let url = fixture("opus-in-m4a.m4a")
        let format = await Track.Format.read(from: url)

        XCTAssertGreaterThan(try XCTUnwrap(format.duration), 0)
        XCTAssertNotNil(format.bitrate)
        XCTAssertEqual(format.sampleRate, 48_000)
        XCTAssertNotNil(format.channels)
        XCTAssertFalse(Track(lightweightURL: url).filling(format).lacksFormat)
    }

    func testAFileTheNativeReaderOpensReadsInFull() async {
        let url = fixture("aac-in-m4a.m4a")
        let format = await Track.Format.read(from: url)
        XCTAssertFalse(Track(lightweightURL: url).filling(format).lacksFormat)
    }

    /// Only the unknown fields fill, and nothing else about the track is lost on the way — the
    /// stream's detected format used to drop the cue range and the origin flags.
    func testFillingKeepsKnownFieldsAndEverythingElse() {
        let source = URL(fileURLWithPath: "/tmp/album.flac")
        let track = Track(url: source, title: "Side A", bitrate: 900,
                          playHistoryContentTypeOverride: "audiobook",
                          cueStartOffset: 12, cueEndOffset: 34, cueSourceURL: source,
                          isRadioOrigin: true, isYouTubeOrigin: true)

        let filled = track.filling(Track.Format(duration: 300, bitrate: 128, sampleRate: 44_100, channels: 2))

        XCTAssertEqual(filled.id, track.id)
        XCTAssertEqual(filled.bitrate, 900)
        XCTAssertEqual(filled.duration, 300)
        XCTAssertEqual(filled.sampleRate, 44_100)
        XCTAssertEqual(filled.channels, 2)
        XCTAssertEqual(filled.playHistoryContentTypeOverride, "audiobook")
        XCTAssertEqual(filled.cueStartOffset, 12)
        XCTAssertEqual(filled.cueEndOffset, 34)
        XCTAssertEqual(filled.cueSourceURL, source)
        XCTAssertTrue(filled.isRadioOrigin)
        XCTAssertTrue(filled.isYouTubeOrigin)
    }

    /// A saved local row keeps its format, so a restored playlist is not read from disk again to
    /// fill it in; a state saved before the format was kept still decodes, with the format unknown.
    func testASavedLocalTrackKeepsItsFormat() throws {
        let track = Track(url: URL(fileURLWithPath: "/tmp/song.flac"), title: "Song", duration: 200,
                          bitrate: 900, sampleRate: 96_000, channels: 2)
        let data = try JSONEncoder().encode(AppStateManager.SavedTrack.from(track, radioStations: []))
        let saved = try JSONDecoder().decode(AppStateManager.SavedTrack.self, from: data)

        XCTAssertEqual(saved.bitrate, 900)
        XCTAssertEqual(saved.sampleRate, 96_000)
        XCTAssertEqual(saved.channels, 2)

        let old = try JSONDecoder().decode(AppStateManager.SavedTrack.self,
                                           from: Data(#"{"localURL":"file:///tmp/song.flac","title":"Song","duration":200}"#.utf8))
        XCTAssertNil(old.bitrate)
        XCTAssertNil(old.sampleRate)
        XCTAssertNil(old.channels)
    }

    /// Every family's playlist row: `Artist - Title` by default, as `displayTitle` was, with the
    /// artist and album following Show Artist / Show Album and the title always kept.
    func testPlaylistTitleFollowsTheRowFieldToggles() {
        var fields = PlaylistRowFields()
        func row(_ artist: String?, _ title: String, _ album: String?, video: Bool = false) -> String {
            fields.text(title: title, artist: artist, album: album, isVideo: video)
        }
        let track = Track(url: URL(fileURLWithPath: "/tmp/a.flac"), title: "T\tune", artist: "A", album: "B")
        XCTAssertEqual(track.displayTitle, "A - T une")
        XCTAssertEqual(row("A", "T", "B"), "A - T")
        XCTAssertEqual(row(nil, "T", "B"), "T")
        XCTAssertEqual(row("A", "", nil), "A - ")
        XCTAssertEqual(row("A", "T", nil, video: true), "\(MediaType.video.rowMarker) A - T")

        fields.showAlbum = true
        XCTAssertEqual(row("A", "T", "B"), "A - T - B")
        XCTAssertEqual(row("A", "T", ""), "A - T")

        fields.showArtist = false
        XCTAssertEqual(row("A", "T", "B"), "T - B")

        fields.showAlbum = false
        XCTAssertEqual(row("A", "T", "B"), "T")
    }

    /// Unset keys read as the default row; the hide-artist key is stored inverted.
    func testRowFieldsReadTheirKeys() {
        let defaults = UserDefaults.standard
        defer {
            defaults.removeObject(forKey: PlaylistRowFields.hideArtistKey)
            defaults.removeObject(forKey: PlaylistRowFields.showAlbumKey)
        }
        defaults.removeObject(forKey: PlaylistRowFields.hideArtistKey)
        defaults.removeObject(forKey: PlaylistRowFields.showAlbumKey)
        XCTAssertTrue(PlaylistRowFields.current.showArtist)
        XCTAssertFalse(PlaylistRowFields.current.showAlbum)
        defaults.set(true, forKey: PlaylistRowFields.hideArtistKey)
        defaults.set(true, forKey: PlaylistRowFields.showAlbumKey)
        XCTAssertFalse(PlaylistRowFields.current.showArtist)
        XCTAssertTrue(PlaylistRowFields.current.showAlbum)
    }

    /// A filled-in format is the same queue, so the playlists repaint rather than reload. A reload
    /// snapped every playlist back to the playing row each time a server stream reported its sample
    /// rate, undoing shuffle's centring and the user's own scroll position.
    func testAFilledInFormatRepaintsThePlaylistsRatherThanReloadingThem() throws {
        let engine = AudioEngine()
        let oldHeadless = AudioEngine.isHeadless
        AudioEngine.isHeadless = true
        defer { engine.clearPlaylist(); AudioEngine.isHeadless = oldHeadless }
        let wav = try TestAudioFile.temporaryWAV()
        defer { try? FileManager.default.removeItem(at: wav) }
        engine.setPlaylistTracks([Track(lightweightURL: wav)])
        engine.playTrack(at: 0)
        let recorder = PlaylistRecorder()
        engine.delegate = recorder
        var trackChanges = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .audioTrackDidChange, object: engine, queue: nil) { _ in trackChanges += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        engine.streamingPlayerDidDetectFormat(sampleRate: 12_345, channels: 1)

        XCTAssertEqual(engine.playlist.first?.sampleRate, 12_345)
        XCTAssertEqual(recorder.reloads, 0)
        XCTAssertEqual(recorder.repaints, 1)
        // A `.wal` playlist follows the playing track from this notification: posting it here would
        // reset that playlist's selection and scroll on every stream's format.
        XCTAssertEqual(trackChanges, 0)
    }

    private final class PlaylistRecorder: AudioEngineDelegate {
        var reloads = 0
        var repaints = 0
        func audioEngineDidChangeState(_ state: PlaybackState) {}
        func audioEngineDidUpdateTime(current: TimeInterval, duration: TimeInterval) {}
        func audioEngineDidChangeTrack(_ track: Track?) {}
        func audioEngineDidUpdateSpectrum(_ levels: [Float]) {}
        func audioEngineDidChangePlaylist() { reloads += 1 }
        func audioEngineDidUpdatePlaylistRows() { repaints += 1 }
        func audioEngineDidFailToLoadTrack(_ track: Track, error: Error) {}
    }
}
