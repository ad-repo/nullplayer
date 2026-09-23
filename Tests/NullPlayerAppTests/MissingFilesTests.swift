import XCTest
import SQLite
@testable import NullPlayer

/// The missing-file paths of the local library: relocating a moved watch root, telling a deleted
/// file from an unavailable volume, resolving playlist entries, and not starting some other track
/// when the one asked for is on a disconnected drive.
final class MissingFilesTests: XCTestCase {
    private var store: MediaLibraryStore!
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = MediaLibraryStore.makeForTesting()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingFilesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        store.open(at: tempDirectoryURL.appendingPathComponent("library.sqlite"))
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

    // MARK: - relocatePathPrefix

    func testRelocationRewritesTracksAndTheWatchFolderButNotASiblingPrefix() {
        store.insertWatchFolder(URL(fileURLWithPath: "/Old/music", isDirectory: true))
        store.upsertTracks([
            "/Old/music/a b.flac", "/Old/music/sub/c.flac", "/Old/music2/d.flac"
        ].map { (track: LibraryTrack(url: URL(fileURLWithPath: $0)), sig: nil) })

        let counts = store.relocatePathPrefix(from: "/Old/music", to: "/New/Archive (Old)/music")

        XCTAssertEqual(counts["library_tracks"], 2)
        XCTAssertEqual(counts["library_watch_folders"], 1)
        XCTAssertEqual(Set(store.allTracks().map(\.url.path)), [
            "/New/Archive (Old)/music/a b.flac",
            "/New/Archive (Old)/music/sub/c.flac",
            "/Old/music2/d.flac"
        ])
        XCTAssertEqual(store.allWatchFolders().map { $0.standardizedFileURL.path }, ["/New/Archive (Old)/music"])
    }

    func testRelocationRewritesALegacyPlainPathRow() throws {
        store.upsertTracks([(track: LibraryTrack(url: URL(fileURLWithPath: "/Old/music/legacy.flac")), sig: nil)])
        try rewriteStoredTrackURLs(to: "/Old/music/legacy.flac")

        store.relocatePathPrefix(from: "/Old/music", to: "/New/music")

        XCTAssertEqual(store.allTracks().map(\.url), [URL(fileURLWithPath: "/New/music/legacy.flac")])
    }

    /// `substr` counts characters and macOS hands back NFD paths, so a byte length — or Swift's
    /// grapheme count — over this prefix would match nothing and relocation would silently no-op.
    func testRelocationMatchesANonASCIIDecomposedPrefix() throws {
        let oldRoot = "/Old/Mu\u{0308}sik"
        store.upsertTracks([(track: LibraryTrack(url: URL(fileURLWithPath: oldRoot + "/a.flac")), sig: nil)])
        try rewriteStoredTrackURLs(to: oldRoot + "/a.flac")

        let counts = store.relocatePathPrefix(from: oldRoot, to: "/New/Musik")

        XCTAssertEqual(counts["library_tracks"], 1)
        XCTAssertEqual(store.allTracks().map(\.url.path), ["/New/Musik/a.flac"])
    }

    /// The obvious user recovery — add the new location as a watch folder and let it scan — puts a
    /// row at the destination already. The stale row wins: it carries the play history.
    func testRelocationKeepsTheStaleRowWhenTheDestinationAlreadyHasOne() {
        let stale = LibraryTrack(url: URL(fileURLWithPath: "/Old/music/a.flac"))
        let fresh = LibraryTrack(url: URL(fileURLWithPath: "/New/music/a.flac"))
        store.upsertTracks([(track: stale, sig: nil), (track: fresh, sig: nil)])

        store.relocatePathPrefix(from: "/Old/music", to: "/New/music")

        let tracks = store.allTracks()
        XCTAssertEqual(tracks.map(\.url.path), ["/New/music/a.flac"])
        XCTAssertEqual(tracks.first?.id, stale.id)
    }

    /// Every scanned track has `track_artists` rows referencing its url, and a relocation that did
    /// not carry them along failed the foreign key and rolled back — silently, on every real library.
    func testRelocationCarriesArtistRowsAlong() throws {
        var track = LibraryTrack(url: URL(fileURLWithPath: "/Old/music/a.flac"))
        track.artist = "Anika Nilles"
        store.upsertTracks([(track: track, sig: nil)])
        let db = try XCTUnwrap(store.testDB)
        XCTAssertGreaterThan(try db.scalar("SELECT count(*) FROM track_artists") as! Int64, 0)

        let counts = store.relocatePathPrefix(from: "/Old/music", to: "/New/music")

        XCTAssertEqual(counts["library_tracks"], 1)
        XCTAssertEqual(store.allTracks().map(\.url.path), ["/New/music/a.flac"])
        let artistURLs = try db.prepare("SELECT DISTINCT track_url FROM track_artists").map { $0[0] as? String }
        XCTAssertEqual(artistURLs, [URL(fileURLWithPath: "/New/music/a.flac").absoluteString])
    }

    func testNestedRelocationIsRefused() {
        store.upsertTracks([(track: LibraryTrack(url: URL(fileURLWithPath: "/Old/music/a.flac")), sig: nil)])

        XCTAssertTrue(store.relocatePathPrefix(from: "/Old/music", to: "/Old/music/sub").isEmpty)
        XCTAssertEqual(store.allTracks().map(\.url.path), ["/Old/music/a.flac"])
    }

    /// Store a track row the way an older library did, as a plain path — in both the track row and
    /// the artist rows that reference it, so the foreign key holds.
    private func rewriteStoredTrackURLs(to plainPath: String) throws {
        let db = try XCTUnwrap(store.testDB)
        try db.transaction {
            try db.run("PRAGMA defer_foreign_keys = ON")
            try db.run("UPDATE library_tracks SET url = ?", plainPath)
            try db.run("UPDATE track_artists SET track_url = ?", plainPath)
        }
    }

    // MARK: - Deleted vs unavailable

    func testAFileUnderADeletedFolderOnAPresentDiskCountsAsDeleted() {
        let url = tempDirectoryURL.appendingPathComponent("deleted-folder/a.mp3")
        XCTAssertTrue(MediaLibrary.firstSurvivingAncestorIsMounted(url))
    }

    func testAFileOnAnUnmountedVolumeDoesNotCountAsDeleted() {
        let volume = "/Volumes/NoSuchDrive-\(UUID().uuidString)"
        XCTAssertFalse(MediaLibrary.firstSurvivingAncestorIsMounted(URL(fileURLWithPath: volume + "/Music/a.mp3")))
        XCTAssertFalse(MediaLibrary.firstSurvivingAncestorIsMounted(
            URL(fileURLWithPath: "/NoSuchRoot-\(UUID().uuidString)/a.mp3")))
    }

    func testAFolderThatIsGoneOrEmptyIsNotPresent() throws {
        let full = tempDirectoryURL.appendingPathComponent("full", isDirectory: true)
        let empty = tempDirectoryURL.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: full, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: full.appendingPathComponent("other.mp3"))

        XCTAssertTrue(AudioEngine.containingFolderIsPresent(full.appendingPathComponent("bad.mp3")))
        XCTAssertFalse(AudioEngine.containingFolderIsPresent(empty.appendingPathComponent("bad.mp3")))
        XCTAssertFalse(AudioEngine.containingFolderIsPresent(
            tempDirectoryURL.appendingPathComponent("gone/bad.mp3")))
    }

    // MARK: - Disconnected drive playback

    /// Playing a track on a disconnected drive used to skip silently to the next entry — the
    /// track that was already playing — and start it under the error message.
    func testPlayingATrackOnAMissingVolumeDoesNotStartAnotherTrack() {
        let engine = AudioEngine()
        let other = Track(url: tempDirectoryURL.appendingPathComponent("other.mp3"))
        let missing = Track(url: URL(fileURLWithPath: "/Volumes/NoSuchDrive-\(UUID().uuidString)/Music/a.mp3"))
        engine.setPlaylistTracks([other])

        engine.playNow([missing])

        XCTAssertEqual(engine.playlist.map(\.url), [missing.url, other.url])
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertNil(engine.currentTrack)
        XCTAssertNotEqual(engine.state, .playing)
    }

    /// Control for the test below: left alone, a track that will not open is skipped after the
    /// half-second the error needs to be readable — so the harness can see an advance happen.
    func testAFailedTrackAdvancesToTheNextEntry() throws {
        let folder = try albumFolderWithAnUnreadableFile()
        let next = folder.appendingPathComponent("next.mp3")
        let engine = AudioEngine()
        engine.setPlaylistTracks([Track(url: folder.appendingPathComponent("bad.mp3")), Track(url: next)])
        let nextFailed = expectation(forNotification: .audioTrackDidFailToLoad, object: engine) { note in
            (note.userInfo?["track"] as? Track)?.url == next
        }

        engine.playTrack(at: 0)

        wait(for: [nextFailed], timeout: 5)
    }

    /// Replacing the playlist inside that half-second left the pending advance armed. It read the
    /// cleared `currentIndex` of -1 as the failed position and started the new playlist's first
    /// entry — from `setPlaylistTracks`, which promises not to play anything.
    func testReplacingThePlaylistCancelsAPendingSkipPastAFailedTrack() throws {
        let folder = try albumFolderWithAnUnreadableFile()
        let engine = AudioEngine()
        engine.setPlaylistTracks([Track(url: folder.appendingPathComponent("bad.mp3")),
                                  Track(url: folder.appendingPathComponent("next.mp3"))])
        let failed = expectation(forNotification: .audioTrackDidFailToLoad, object: engine)
        engine.playTrack(at: 0)
        wait(for: [failed], timeout: 5)

        // Two entries: with one, the failure limit (`< playlist.count`) ends the queue before the
        // stray advance can start anything, and the test passes without the fix.
        engine.setPlaylistTracks([Track(url: folder.appendingPathComponent("replacement-1.mp3")),
                                  Track(url: folder.appendingPathComponent("replacement-2.mp3"))])
        RunLoop.main.run(until: Date().addingTimeInterval(1))

        XCTAssertEqual(engine.currentIndex, -1)
        XCTAssertNil(engine.currentTrack)
    }

    /// A present, non-empty folder holding `bad.mp3`, which is not audio — one bad file, not a
    /// missing volume, so the failure path skips rather than stops.
    private func albumFolderWithAnUnreadableFile() throws -> URL {
        let folder = tempDirectoryURL.appendingPathComponent("album", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not audio".utf8).write(to: folder.appendingPathComponent("bad.mp3"))
        return folder
    }

    // MARK: - Playlist.resolveEntry

    func testPlaylistEntriesResolveAsPaths() {
        let directory = URL(fileURLWithPath: "/Music/Album", isDirectory: true)

        XCTAssertEqual(Playlist.resolveEntry("01 - Those Hills.flac", relativeTo: directory),
                       URL(fileURLWithPath: "/Music/Album/01 - Those Hills.flac"))
        XCTAssertEqual(Playlist.resolveEntry("../Other/b.mp3", relativeTo: directory),
                       URL(fileURLWithPath: "/Music/Other/b.mp3"))
        XCTAssertEqual(Playlist.resolveEntry("/Users/me/a b.flac", relativeTo: directory),
                       URL(fileURLWithPath: "/Users/me/a b.flac"))
        XCTAssertEqual(Playlist.resolveEntry("file:///Users/me/a%20b.flac", relativeTo: directory),
                       URL(fileURLWithPath: "/Users/me/a b.flac"))
        XCTAssertEqual(Playlist.resolveEntry("http://radio.example/stream", relativeTo: directory)?.scheme, "http")
        XCTAssertTrue(Playlist.resolveEntry("C:\\Music\\a.mp3", relativeTo: directory)?.isFileURL ?? false)
        XCTAssertNil(Playlist.resolveEntry("#EXTINF:123,Title", relativeTo: directory))
        XCTAssertNil(Playlist.resolveEntry("   ", relativeTo: directory))
    }

    func testM3UEntriesAreAllPlayableFileURLs() throws {
        let m3u = tempDirectoryURL.appendingPathComponent("list.m3u")
        try "#EXTM3U\n01 - a.flac\n/abs/b c.flac\n".write(to: m3u, atomically: true, encoding: .utf8)

        let urls = try Playlist.fromM3U(url: m3u).trackURLs

        XCTAssertEqual(urls.map(\.path), [
            tempDirectoryURL.appendingPathComponent("01 - a.flac").standardizedFileURL.path,
            "/abs/b c.flac"
        ])
        XCTAssertTrue(urls.allSatisfy(\.isFileURL))
    }
}
