import XCTest
@testable import NullPlayer

final class TrackArtistsQueriesTests: XCTestCase {

    private var store: MediaLibraryStore!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        store = MediaLibraryStore.makeForTesting()
        store.open(at: tempURL)
        insertTestTracks()
    }

    override func tearDown() {
        store.close()
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    /// Insert test tracks:
    /// - Track 1: albumArtist = "Drake feat. Future" → Drake (albumArtist), Future (albumArtist)
    /// - Track 2: albumArtist = "Adele" → Adele (albumArtist)
    /// - Track 3: no albumArtist, artist = "Simon & Garfunkel" → Simon & Garfunkel (albumArtist via fallback)
    private func insertTestTracks() {
        var t1 = LibraryTrack(url: URL(fileURLWithPath: "/tmp/t1.mp3"), title: "T1")
        t1.albumArtist = "Drake feat. Future"
        t1.artist = "Drake"
        t1.album = "Take Care"
        t1.artists = ArtistSplitter.split("Drake", isAlbumArtist: false)
        let aa1 = ArtistSplitter.split("Drake feat. Future", isAlbumArtist: true)
        t1.artists.append(contentsOf: aa1)
        store.upsertTrack(t1, sig: nil)

        var t2 = LibraryTrack(url: URL(fileURLWithPath: "/tmp/t2.mp3"), title: "T2")
        t2.albumArtist = "Adele"
        t2.artist = "Adele"
        t2.album = "21"
        t2.artists = ArtistSplitter.split("Adele", isAlbumArtist: false)
        t2.artists.append(contentsOf: ArtistSplitter.split("Adele", isAlbumArtist: true))
        store.upsertTrack(t2, sig: nil)

        var t3 = LibraryTrack(url: URL(fileURLWithPath: "/tmp/t3.mp3"), title: "T3")
        t3.artist = "Simon & Garfunkel"
        t3.album = "Sounds of Silence"
        // No albumArtist → fallback: artist split with isAlbumArtist: true
        t3.artists = ArtistSplitter.split("Simon & Garfunkel", isAlbumArtist: false)
        t3.artists.append(contentsOf: ArtistSplitter.split("Simon & Garfunkel", isAlbumArtist: true))
        store.upsertTrack(t3, sig: nil)
    }

    func testArtistCount() {
        // Drake, Future, Adele, Simon & Garfunkel = 4
        XCTAssertEqual(store.artistCount(), 4)
    }

    func testArtistNamesContainsSplitArtists() {
        let names = store.artistNames(limit: 100, offset: 0, sort: .nameAsc)
        XCTAssertTrue(names.contains("Drake"))
        XCTAssertTrue(names.contains("Future"))
        XCTAssertTrue(names.contains("Adele"))
        XCTAssertTrue(names.contains("Simon & Garfunkel"))
        XCTAssertFalse(names.contains("Drake feat. Future"), "Raw unsplit string must not appear")
    }

    func testArtistNamesPageCountMatchesArtistCount() {
        let count = store.artistCount()
        let names = store.artistNames(limit: 100, offset: 0, sort: .nameAsc)
        XCTAssertEqual(names.count, count)
    }

    func testArtistLetterOffsetsAlignWithArtistNames() {
        let names = store.artistNames(limit: 100, offset: 0, sort: .nameAsc)
        let offsets = store.artistLetterOffsets(sort: .nameAsc)
        for (letter, offset) in offsets {
            let firstMatch = names.firstIndex { n in
                let firstChar = n.prefix(1).uppercased()
                return firstChar == letter || (letter == "#" && !firstChar.first!.isLetter)
            }
            XCTAssertEqual(firstMatch, offset, "Letter '\(letter)' offset \(offset) must match artistNames index")
        }
    }

    func testSearchArtistNamesReturnsSplitNames() {
        let results = store.searchArtistNames(query: "Drake")
        XCTAssertTrue(results.contains("Drake"))
        XCTAssertFalse(results.contains("Drake feat. Future"))
    }

    func testAlbumsForArtistDrake() {
        let albums = store.albumsForArtist("Drake")
        XCTAssertFalse(albums.isEmpty, "Drake must have albums")
        XCTAssertTrue(albums.contains { $0.name == "Take Care" })
    }

    func testAlbumsForArtistFuture() {
        let albums = store.albumsForArtist("Future")
        XCTAssertFalse(albums.isEmpty, "Future must have albums via albumArtist split")
        XCTAssertTrue(albums.contains { $0.name == "Take Care" })
    }

    func testAlbumsForArtistsBatch() {
        let batch = store.albumsForArtistsBatch(["Drake", "Future", "Adele"])
        XCTAssertTrue(batch["Drake"]?.contains { $0.name == "Take Care" } ?? false)
        XCTAssertTrue(batch["Future"]?.contains { $0.name == "Take Care" } ?? false)
        XCTAssertTrue(batch["Adele"]?.contains { $0.name == "21" } ?? false)
        XCTAssertNil(batch["Drake feat. Future"], "Unsplit key must not be in result")
    }
}
