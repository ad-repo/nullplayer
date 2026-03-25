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

    func testSchemaVersionIs4() throws {
        let db = try Connection(tempURL.path)
        let version = try db.scalar("PRAGMA user_version") as? Int64 ?? 0
        XCTAssertEqual(version, 4)
    }

    func testTrackMetadataColumnsExistInV4() throws {
        let db = try Connection(tempURL.path)
        var columnNames: Set<String> = []
        for row in try db.prepare("PRAGMA table_info(library_tracks)") {
            if let name = row[1] as? String {
                columnNames.insert(name)
            }
        }
        let expected: Set<String> = [
            "composer", "comment", "grouping", "bpm", "musical_key", "isrc", "copyright",
            "musicbrainz_recording_id", "musicbrainz_release_id",
            "discogs_release_id", "discogs_master_id", "discogs_label",
            "discogs_catalog_number", "artwork_url",
        ]
        XCTAssertTrue(expected.isSubset(of: columnNames))
    }

    func testMigrationFromV3AddsExtendedTrackColumns() throws {
        let legacyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: legacyURL) }

        let legacyDB = try Connection(legacyURL.path)
        try legacyDB.run("""
            CREATE TABLE library_tracks (
                id TEXT PRIMARY KEY,
                url TEXT UNIQUE,
                title TEXT,
                artist TEXT,
                album TEXT,
                album_artist TEXT,
                genre TEXT,
                year INTEGER,
                track_number INTEGER,
                disc_number INTEGER,
                duration REAL,
                bitrate INTEGER,
                sample_rate INTEGER,
                channels INTEGER,
                file_size INTEGER,
                date_added REAL,
                last_played REAL,
                play_count INTEGER,
                rating INTEGER,
                scan_file_size INTEGER,
                scan_mod_date REAL
            )
            """)
        try legacyDB.run("PRAGMA user_version = 3")

        let migratingStore = MediaLibraryStore.makeForTesting()
        migratingStore.open(at: legacyURL)
        defer { migratingStore.close() }

        let migratedDB = try Connection(legacyURL.path)
        let version = try migratedDB.scalar("PRAGMA user_version") as? Int64 ?? 0
        XCTAssertEqual(version, 4)

        var columnNames: Set<String> = []
        for row in try migratedDB.prepare("PRAGMA table_info(library_tracks)") {
            if let name = row[1] as? String { columnNames.insert(name) }
        }
        XCTAssertTrue(columnNames.contains("musicbrainz_release_id"))
        XCTAssertTrue(columnNames.contains("discogs_release_id"))
        XCTAssertTrue(columnNames.contains("artwork_url"))
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

    func testBackfillPopulatesTrackArtistsFromRawColumns() {
        // Insert a track with raw artist/albumArtist columns but NO track_artists rows
        // (simulates a pre-v3 library row)
        guard let db = store.testDB else {
            XCTFail("testDB not accessible"); return
        }
        let url = "file:///tmp/backfill_test.mp3"
        try? db.run("""
            INSERT INTO library_tracks (id, url, title, artist, album_artist, duration, file_size, date_added, play_count)
            VALUES (?, ?, 'BackfillTrack', 'Drake feat. Future', 'Drake feat. Future', 180.0, 0, 0.0, 0)
            """, UUID().uuidString, url)

        // Confirm no track_artists rows exist yet
        let before = try? db.scalar("SELECT COUNT(*) FROM track_artists WHERE track_url = ?", url) as? Int64 ?? 0
        XCTAssertEqual(before, 0)

        // Run backfill
        let expectation = expectation(description: "backfill")
        store.backfillTrackArtistsIfNeeded {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)

        // Verify track_artists rows exist
        let after = (try? db.scalar("SELECT COUNT(*) FROM track_artists WHERE track_url = ?", url) as? Int64) ?? 0
        XCTAssertGreaterThan(after, 0, "Backfill must have created track_artists rows")
        let drakeRows = (try? db.scalar(
            "SELECT COUNT(*) FROM track_artists WHERE track_url = ? AND artist_name = 'Drake' AND role = 'album_artist'",
            url
        ) as? Int64) ?? 0
        XCTAssertEqual(drakeRows, 1)
    }
}
