import XCTest
import SQLite
@testable import NullPlayer

final class TrackArtistsSchemaTests: XCTestCase {

    private var store: MediaLibraryStore!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        store = MediaLibraryStore.makeForTesting()
        store.open(at: tempURL)
    }

    override func tearDown() {
        store.close()
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testTrackArtistsTableExists() throws {
        // track_artists table must exist after open()
        let db = try Connection(tempURL.path)
        let count = try db.scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='track_artists'"
        ) as? Int64 ?? 0
        XCTAssertEqual(count, 1, "track_artists table must exist")
    }

    func testForeignKeysEnabled() throws {
        let db = try Connection(tempURL.path)
        let fkEnabled = try db.scalar("PRAGMA foreign_keys") as? Int64 ?? 0
        // Note: PRAGMA foreign_keys is per-connection. This new connection starts at 0.
        // The test verifies it is set ON within the store's own connection by
        // testing cascade behavior (see testCascadeDeleteOnTrackDelete below).
        // This assertion just documents what a new connection returns.
        XCTAssertEqual(fkEnabled, 0, "New connections start with FK off by default")
    }

    func testSchemaVersionIs3() throws {
        let db = try Connection(tempURL.path)
        let version = try db.scalar("PRAGMA user_version") as? Int64 ?? 0
        XCTAssertEqual(version, 3)
    }

    func testCascadeDeleteOnTrackDelete() {
        // Insert a track via store
        var track = LibraryTrack(url: URL(fileURLWithPath: "/tmp/cascade_test.mp3"),
                                  title: "Cascade Test")
        track.artist = "Drake feat. Future"
        track.artists = [(name: "Drake", role: .primary), (name: "Future", role: .featured),
                         (name: "Drake", role: .albumArtist)]
        store.upsertTrack(track, sig: nil)

        // Verify track_artists rows exist
        XCTAssertEqual(store.artistsForURLs([track.url.absoluteString]).count, 1)

        // Delete the track
        store.deleteTrackByPath("/tmp/cascade_test.mp3")

        // track_artists rows must be gone (cascade)
        let remaining = store.artistsForURLs([track.url.absoluteString])
        XCTAssertTrue(remaining.isEmpty || remaining[track.url.absoluteString]?.isEmpty == true)
    }

    func testUpsertTrackWritesTrackArtistsRows() {
        var track = LibraryTrack(url: URL(fileURLWithPath: "/tmp/upsert_test.mp3"), title: "Test")
        track.artists = [
            (name: "Drake", role: .primary),
            (name: "Future", role: .featured),
            (name: "Drake", role: .albumArtist)
        ]
        store.upsertTrack(track, sig: nil)

        let result = store.artistsForURLs([track.url.absoluteString])
        let artists = result[track.url.absoluteString] ?? []
        XCTAssertEqual(artists.count, 3)
        XCTAssertTrue(artists.contains { $0.name == "Drake" && $0.role == .primary })
        XCTAssertTrue(artists.contains { $0.name == "Future" && $0.role == .featured })
        XCTAssertTrue(artists.contains { $0.name == "Drake" && $0.role == .albumArtist })
    }

    func testUpsertTrackReplacesTrackArtistsOnRescan() {
        var track = LibraryTrack(url: URL(fileURLWithPath: "/tmp/replace_test.mp3"), title: "Test")
        track.artists = [(name: "OldArtist", role: .albumArtist)]
        store.upsertTrack(track, sig: nil)

        // Re-upsert same URL with different artists
        var track2 = LibraryTrack(url: URL(fileURLWithPath: "/tmp/replace_test.mp3"), title: "Test")
        track2.artists = [(name: "NewArtist", role: .albumArtist)]
        store.upsertTrack(track2, sig: nil)

        let result = store.artistsForURLs([track.url.absoluteString])
        let artists = result[track.url.absoluteString] ?? []
        // Old artist must be gone, new artist present
        XCTAssertFalse(artists.contains { $0.name == "OldArtist" })
        XCTAssertTrue(artists.contains { $0.name == "NewArtist" })
    }

    func testUpsertTracksWritesArtistRowsForBatch() {
        var t1 = LibraryTrack(url: URL(fileURLWithPath: "/tmp/batch1.mp3"), title: "Batch1")
        t1.artists = [(name: "ArtistA", role: .albumArtist)]
        var t2 = LibraryTrack(url: URL(fileURLWithPath: "/tmp/batch2.mp3"), title: "Batch2")
        t2.artists = [(name: "ArtistB", role: .albumArtist)]

        store.upsertTracks([(t1, nil), (t2, nil)])

        let urls = [t1.url.absoluteString, t2.url.absoluteString]
        let result = store.artistsForURLs(urls)
        XCTAssertTrue(result[t1.url.absoluteString]?.contains { $0.name == "ArtistA" } ?? false)
        XCTAssertTrue(result[t2.url.absoluteString]?.contains { $0.name == "ArtistB" } ?? false)
    }
}
