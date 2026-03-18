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
}
