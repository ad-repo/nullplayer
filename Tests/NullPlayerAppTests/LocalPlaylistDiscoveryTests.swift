import XCTest
import SQLite
@testable import NullPlayer

final class LocalPlaylistDiscoveryTests: XCTestCase {
    private var store: MediaLibraryStore!
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = MediaLibraryStore.makeForTesting()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalPlaylistDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        store?.close()
        store = nil

        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
            self.tempDirectoryURL = nil
        }

        try super.tearDownWithError()
    }

    // MARK: - Discovery Tests

    /// Test that when includePlaylists: true, .m3u and .pls files are discovered
    /// and placed in playlistFiles, while audio files go to audioFiles.
    func testDiscoveryIncludesPlaylistFilesWhenEnabled() throws {
        let testDirURL = tempDirectoryURL.appendingPathComponent("discovery-test", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirURL, withIntermediateDirectories: true)

        // Create a simple .m3u file
        let m3uURL = testDirURL.appendingPathComponent("playlist.m3u")
        try "#EXTM3U\n".write(to: m3uURL, atomically: true, encoding: .utf8)

        // Create a simple .pls file
        let plsURL = testDirURL.appendingPathComponent("test.pls")
        try "[playlist]\nNumberOfEntries=0\n".write(to: plsURL, atomically: true, encoding: .utf8)

        // Create an audio file to verify it goes to audioFiles, not playlistFiles
        let mp3URL = testDirURL.appendingPathComponent("song.mp3")
        try "fake mp3 data".write(to: mp3URL, atomically: true, encoding: .utf8)

        // Discover with includePlaylists: true
        let result = LocalFileDiscovery.discoverMedia(
            from: [testDirURL],
            recursiveDirectories: true,
            includeVideo: false,
            includePlaylists: true
        )

        // Assert playlists are in playlistFiles
        XCTAssertEqual(result.playlistFiles.count, 2)
        let playlistPaths = Set(result.playlistFiles.map { canonical($0.url) })
        XCTAssertTrue(playlistPaths.contains(canonical(m3uURL)))
        XCTAssertTrue(playlistPaths.contains(canonical(plsURL)))

        // Assert audio file is in audioFiles, not in playlistFiles
        XCTAssertEqual(result.audioFiles.count, 1)
        XCTAssertEqual(canonical(result.audioFiles[0].url), canonical(mp3URL))
        XCTAssertFalse(playlistPaths.contains(canonical(mp3URL)))

        // Assert playlists are NOT in allURLs (which only includes audio + video)
        XCTAssertEqual(result.allURLs.count, 1)
        XCTAssertEqual(canonical(result.allURLs[0]), canonical(mp3URL))
    }

    /// Test that when includePlaylists: false (default), playlist files are not discovered.
    func testDiscoveryExcludesPlaylistFilesWhenDisabled() throws {
        let testDirURL = tempDirectoryURL.appendingPathComponent("discovery-no-playlists", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirURL, withIntermediateDirectories: true)

        let m3uURL = testDirURL.appendingPathComponent("playlist.m3u")
        try "#EXTM3U\n".write(to: m3uURL, atomically: true, encoding: .utf8)

        let plsURL = testDirURL.appendingPathComponent("test.pls")
        try "[playlist]\nNumberOfEntries=0\n".write(to: plsURL, atomically: true, encoding: .utf8)

        let mp3URL = testDirURL.appendingPathComponent("song.mp3")
        try "fake mp3 data".write(to: mp3URL, atomically: true, encoding: .utf8)

        // Discover with includePlaylists: false (default)
        let result = LocalFileDiscovery.discoverMedia(
            from: [testDirURL],
            recursiveDirectories: true,
            includeVideo: false,
            includePlaylists: false
        )

        // Assert playlistFiles is empty
        XCTAssertEqual(result.playlistFiles.count, 0)

        // Assert audio file is still discovered
        XCTAssertEqual(result.audioFiles.count, 1)
        XCTAssertEqual(canonical(result.audioFiles[0].url), canonical(mp3URL))

        // Assert allURLs only contains audio
        XCTAssertEqual(result.allURLs.count, 1)
        XCTAssertEqual(canonical(result.allURLs[0]), canonical(mp3URL))
    }

    /// Test the streaming variant also correctly separates playlists.
    func testDiscoveryStreamingIncludesPlaylistFiles() throws {
        let testDirURL = tempDirectoryURL.appendingPathComponent("discovery-streaming", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirURL, withIntermediateDirectories: true)

        let m3uURL = testDirURL.appendingPathComponent("stream.m3u")
        try "#EXTM3U\n".write(to: m3uURL, atomically: true, encoding: .utf8)

        let mp3URL = testDirURL.appendingPathComponent("track.mp3")
        try "fake data".write(to: mp3URL, atomically: true, encoding: .utf8)

        var batchCalls = 0
        let result = LocalFileDiscovery.discoverMediaStreaming(
            from: [testDirURL],
            recursiveDirectories: true,
            includeVideo: false,
            includePlaylists: true,
            onAudioBatch: { _ in batchCalls += 1 }
        )

        XCTAssertEqual(result.playlistFiles.count, 1)
        XCTAssertEqual(canonical(result.playlistFiles[0].url), canonical(m3uURL))
        XCTAssertEqual(result.audioFiles.count, 1)
        XCTAssertEqual(canonical(result.audioFiles[0].url), canonical(mp3URL))
        XCTAssertGreaterThan(batchCalls, 0)
    }

    // MARK: - Store Round-Trip Tests

    /// Test upsertPlaylists + allPlaylists round-trip: a LocalPlaylist is stored and retrieved with all fields intact.
    func testStoreRoundTrip() throws {
        let dbURL = tempDirectoryURL.appendingPathComponent("library-roundtrip.sqlite")
        store.open(at: dbURL)

        let now = Date()
        let playlistURL = URL(fileURLWithPath: "/tmp/test.m3u")
        let playlist = LocalPlaylist(
            id: UUID(),
            url: playlistURL,
            title: "My Playlist",
            fileSize: 4096,
            dateAdded: now,
            scanFileSize: 4096,
            scanModDate: now
        )

        let sig = FileScanSignature(fileSize: 4096, contentModificationDate: now)
        store.upsertPlaylists([(playlist: playlist, sig: sig)])

        let retrieved = store.allPlaylists()
        XCTAssertEqual(retrieved.count, 1)
        XCTAssertEqual(retrieved[0].id, playlist.id)
        XCTAssertEqual(retrieved[0].url, playlist.url)
        XCTAssertEqual(retrieved[0].title, playlist.title)
        XCTAssertEqual(retrieved[0].fileSize, playlist.fileSize)
        XCTAssertEqual(retrieved[0].dateAdded.timeIntervalSince1970, playlist.dateAdded.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(retrieved[0].scanFileSize, sig.fileSize)
        XCTAssertEqual(retrieved[0].scanModDate?.timeIntervalSince1970 ?? 0, sig.contentModificationDate?.timeIntervalSince1970 ?? 0, accuracy: 0.01)
    }

    /// Test ID reuse on re-upsert: upserting a LocalPlaylist with the SAME url but different id
    /// preserves the original id (natural key stability by url).
    func testStorePreservesIdOnReUpsert() throws {
        let dbURL = tempDirectoryURL.appendingPathComponent("library-id-reuse.sqlite")
        store.open(at: dbURL)

        let playlistURL = URL(fileURLWithPath: "/tmp/playlist.m3u")
        let originalId = UUID()
        let now = Date()

        // First upsert
        let playlist1 = LocalPlaylist(
            id: originalId,
            url: playlistURL,
            title: "Original Title",
            fileSize: 1024,
            dateAdded: now,
            scanFileSize: 1024,
            scanModDate: now
        )
        let sig = FileScanSignature(fileSize: 1024, contentModificationDate: now)
        store.upsertPlaylists([(playlist: playlist1, sig: sig)])

        var retrieved = store.allPlaylists()
        XCTAssertEqual(retrieved.count, 1)
        XCTAssertEqual(retrieved[0].id, originalId)

        // Second upsert with SAME url but DIFFERENT id — should preserve original id
        let differentId = UUID()
        let playlist2 = LocalPlaylist(
            id: differentId,
            url: playlistURL,  // Same URL
            title: "Updated Title",
            fileSize: 2048,
            dateAdded: now,
            scanFileSize: 2048,
            scanModDate: now
        )
        store.upsertPlaylists([(playlist: playlist2, sig: sig)])

        retrieved = store.allPlaylists()
        XCTAssertEqual(retrieved.count, 1)
        // ID should be the original one from first upsert, not the differentId
        XCTAssertEqual(retrieved[0].id, originalId)
        XCTAssertNotEqual(retrieved[0].id, differentId)
        // But title and fileSize should be updated
        XCTAssertEqual(retrieved[0].title, "Updated Title")
        XCTAssertEqual(retrieved[0].fileSize, 2048)
    }

    /// Test deletePlaylistsByPath removes playlists by their path.
    func testStoreDeleteByPath() throws {
        let dbURL = tempDirectoryURL.appendingPathComponent("library-delete.sqlite")
        store.open(at: dbURL)

        let now = Date()
        let path1 = "/tmp/playlist1.m3u"
        let path2 = "/tmp/playlist2.m3u"

        let playlist1 = LocalPlaylist(
            id: UUID(),
            url: URL(fileURLWithPath: path1),
            title: "Playlist 1",
            fileSize: 1024,
            dateAdded: now,
            scanFileSize: 1024,
            scanModDate: now
        )
        let playlist2 = LocalPlaylist(
            id: UUID(),
            url: URL(fileURLWithPath: path2),
            title: "Playlist 2",
            fileSize: 2048,
            dateAdded: now,
            scanFileSize: 2048,
            scanModDate: now
        )

        let sig = FileScanSignature(fileSize: 1024, contentModificationDate: now)
        store.upsertPlaylists([
            (playlist: playlist1, sig: sig),
            (playlist: playlist2, sig: sig)
        ])

        var all = store.allPlaylists()
        XCTAssertEqual(all.count, 2)

        // Delete playlist1 by path
        store.deletePlaylistsByPath([path1])

        all = store.allPlaylists()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].title, "Playlist 2")
    }

    // MARK: - Migration Tests

    /// Test that a fresh database (created at v0) gets the library_playlists table and ends at v8.
    func testFreshDatabaseCreatesPlaylistsTable() throws {
        let dbURL = tempDirectoryURL.appendingPathComponent("fresh-db.sqlite")

        store.open(at: dbURL)
        let db = try XCTUnwrap(store.testDB)

        // Should be at version 8 after setupSchema
        let version = try db.scalar("PRAGMA user_version") as? Int64
        XCTAssertEqual(version, 8)

        // library_playlists table should exist
        XCTAssertTrue(try tableExists("library_playlists", in: db))

        // allPlaylists should work without error
        let playlists = store.allPlaylists()
        XCTAssertEqual(playlists.count, 0)
    }

    /// Test migration from v7 to v8: opening an old v7 DB adds the playlists table.
    func testV7ToV8MigrationCreatesPlaylistsTable() throws {
        let dbURL = tempDirectoryURL.appendingPathComponent("library-v7.sqlite")

        // Create a v7 database manually
        do {
            let seedConnection = try Connection(dbURL.path)
            try seedConnection.execute("""
                CREATE TABLE play_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    source TEXT NOT NULL,
                    content_type TEXT,
                    output_device TEXT
                );
                """)
            try seedConnection.run("PRAGMA user_version = 7")
        }

        // Open with store (should migrate from 7 -> 8)
        store.open(at: dbURL)
        let db = try XCTUnwrap(store.testDB)

        // Verify version is now 8
        let version = try db.scalar("PRAGMA user_version") as? Int64
        XCTAssertEqual(version, 8)

        // Verify library_playlists table exists
        XCTAssertTrue(try tableExists("library_playlists", in: db))

        // Verify we can query it
        let playlists = store.allPlaylists()
        XCTAssertEqual(playlists.count, 0)
    }

    /// Test that multiple playlists with different .m3u8 variant extensions are discovered.
    func testDiscoveryHandlesM3u8Extension() throws {
        let testDirURL = tempDirectoryURL.appendingPathComponent("discovery-m3u8", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirURL, withIntermediateDirectories: true)

        let m3u8URL = testDirURL.appendingPathComponent("hls.m3u8")
        try "#EXTM3U\n".write(to: m3u8URL, atomically: true, encoding: .utf8)

        let result = LocalFileDiscovery.discoverMedia(
            from: [testDirURL],
            recursiveDirectories: true,
            includeVideo: false,
            includePlaylists: true
        )

        XCTAssertEqual(result.playlistFiles.count, 1)
        XCTAssertEqual(canonical(result.playlistFiles[0].url), canonical(m3u8URL))
    }

    /// Test LocalDiscoveredMediaFile has fileSize and contentModificationDate populated.
    func testDiscoveredPlaylistFileMetadata() throws {
        let testDirURL = tempDirectoryURL.appendingPathComponent("discovery-metadata", isDirectory: true)
        try FileManager.default.createDirectory(at: testDirURL, withIntermediateDirectories: true)

        let m3uURL = testDirURL.appendingPathComponent("metadata.m3u")
        let content = "#EXTM3U\n#EXTINF:100, Track Title\n/path/to/file.mp3\n"
        try content.write(to: m3uURL, atomically: true, encoding: .utf8)

        let result = LocalFileDiscovery.discoverMedia(
            from: [testDirURL],
            recursiveDirectories: true,
            includeVideo: false,
            includePlaylists: true
        )

        XCTAssertEqual(result.playlistFiles.count, 1)
        let file = result.playlistFiles[0]
        XCTAssertGreaterThan(file.fileSize, 0)  // Should have non-zero file size
        XCTAssertNotNil(file.contentModificationDate)  // Should have modification date
        XCTAssertEqual(canonical(file.url), canonical(m3uURL))
    }

    // MARK: - Bulk upsert and batch operations

    /// Test upserting multiple playlists in a single batch.
    func testBulkPlaylistUpsert() throws {
        let dbURL = tempDirectoryURL.appendingPathComponent("library-bulk.sqlite")
        store.open(at: dbURL)

        let now = Date()
        var playlists: [(playlist: LocalPlaylist, sig: FileScanSignature?)] = []

        for i in 0..<5 {
            let playlist = LocalPlaylist(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/playlist\(i).m3u"),
                title: "Playlist \(i)",
                fileSize: Int64(1024 * (i + 1)),
                dateAdded: now,
                scanFileSize: Int64(1024 * (i + 1)),
                scanModDate: now
            )
            let sig = FileScanSignature(fileSize: Int64(1024 * (i + 1)), contentModificationDate: now)
            playlists.append((playlist: playlist, sig: sig))
        }

        store.upsertPlaylists(playlists)

        let all = store.allPlaylists()
        XCTAssertEqual(all.count, 5)

        // Verify all titles are present
        let titles = Set(all.map { $0.title })
        for i in 0..<5 {
            XCTAssertTrue(titles.contains("Playlist \(i)"))
        }
    }

    // MARK: - Helper Methods

    /// Canonical filesystem path for a URL. FileManager's enumerator returns paths under
    /// `/private/var/...` while fixture URLs built from `temporaryDirectory` are `/var/...`;
    /// resolving symlinks on both sides converges them to one canonical form.
    private func canonical(_ url: URL) -> String { url.resolvingSymlinksInPath().path }

    private func tableExists(_ tableName: String, in db: Connection) throws -> Bool {
        let result = try db.scalar("SELECT name FROM sqlite_master WHERE type='table' AND name=?", [tableName as Binding])
        return result != nil
    }
}
