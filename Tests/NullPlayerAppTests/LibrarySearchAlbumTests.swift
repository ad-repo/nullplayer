import XCTest
@testable import NullPlayer

/// Library search must list every album of a matched artist: each server caps or filters its
/// album hits, and Plex's /hubs/search ignores `sectionId`.
final class LibrarySearchAlbumTests: XCTestCase {

    // MARK: - Plex hub parsing

    private func hubJSON(_ hubs: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["MediaContainer": ["Hub": hubs]])
    }

    private func item(_ ratingKey: String, type: String, title: String, parent: String? = nil,
                      year: Int? = nil, section: Any? = nil) -> [String: Any] {
        var item: [String: Any] = ["ratingKey": ratingKey, "key": "/library/metadata/\(ratingKey)",
                                   "type": type, "title": title]
        if let parent { item["parentTitle"] = parent }
        if let year { item["year"] = year }
        if let section { item["librarySectionID"] = section }
        return item
    }

    func testPlexMusicHitsAreKeptToTheMusicLibrary() throws {
        let data = try hubJSON([
            ["type": "artist", "Metadata": [
                item("1", type: "artist", title: "Rush", section: 15),
                item("2", type: "artist", title: "Rush", section: 15),
                item("3", type: "artist", title: "Rush", section: 14),
            ]],
            ["type": "album", "Metadata": [
                item("10", type: "album", title: "Signals", parent: "Rush", year: 1982, section: 15),
                item("11", type: "album", title: "Presto", parent: "Rush", year: 1989, section: 14),
            ]],
            ["type": "movie", "Metadata": [item("20", type: "movie", title: "Rush", section: 1)]],
        ])

        let (results, artistIDs) = try PlexServerClient.parseHubSearch(data, musicLibraryID: "15")

        XCTAssertEqual(results.albums.map(\.title), ["Signals"])
        XCTAssertEqual(artistIDs, ["1", "2"], "every same-name record in the library is fetched")
        XCTAssertEqual(results.artists.count, 1)
        XCTAssertEqual(results.movies.map(\.title), ["Rush"], "video hits come from every section")
    }

    func testPlexKeepsEditionsThatShareATitle() throws {
        let data = try hubJSON([["type": "album", "Metadata": [
            item("10", type: "album", title: "Moving Pictures", parent: "Rush", year: 1981, section: 15),
            item("11", type: "album", title: "Moving Pictures", parent: "Rush", year: 2011, section: 15),
            item("12", type: "album", title: "moving pictures", parent: "RUSH", year: 1981, section: 15),
        ]]])

        let (results, _) = try PlexServerClient.parseHubSearch(data, musicLibraryID: "15")

        XCTAssertEqual(results.albums.map(\.id), ["10", "11"])
    }

    func testPlexWithoutMusicLibraryCollapsesCopiesAcrossSections() throws {
        let data = try hubJSON([["type": "album", "Metadata": [
            item("10", type: "album", title: "Signals", parent: "Rush", year: 1982, section: 15),
            item("30", type: "album", title: "Signals", parent: "Rush", year: 1982, section: 14),
        ]]])

        let (results, _) = try PlexServerClient.parseHubSearch(data, musicLibraryID: nil)

        XCTAssertEqual(results.albums.map(\.id), ["10"])
    }

    func testPlexAcceptsAStringSectionID() throws {
        let data = try hubJSON([["type": "album", "Metadata": [
            item("10", type: "album", title: "Signals", parent: "Rush", year: 1982, section: "15"),
            item("11", type: "album", title: "Presto", parent: "Rush", year: 1989, section: "14"),
        ]]])

        let (results, _) = try PlexServerClient.parseHubSearch(data, musicLibraryID: "15")

        XCTAssertEqual(results.albums.map(\.title), ["Signals"])
    }

    // MARK: - Artist album merge

    func testMergeAppendsArtistAlbumsInArtistOrderWithoutDuplicates() async {
        let byArtist = ["a": ["A1", "A2"], "b": ["B1", "A1"]]

        let merged = await SearchArtistAlbumMerge.merged(
            ["A2", "X"], artistIDs: ["a", "b"], key: { $0 }
        ) { byArtist[$0] ?? [] }

        XCTAssertEqual(merged, ["A2", "X", "A1", "B1"])
    }

    func testMergeSkipsAFailedArtistAndBoundsTheFanOut() async {
        struct Failure: Error {}
        let ids = (0..<(SearchArtistAlbumMerge.artistLimit + 5)).map { "artist\($0)" }

        let merged = await SearchArtistAlbumMerge.merged(
            [String](), artistIDs: ["bad"] + ids, key: { $0 }
        ) { id in
            if id == "bad" { throw Failure() }
            return [id]
        }

        XCTAssertEqual(merged, Array(ids.prefix(SearchArtistAlbumMerge.artistLimit - 1)))
    }

    // MARK: - Local album search

    func testLocalAlbumSearchMatchesTrackArtistWhenAlbumArtistIsEmpty() throws {
        let store = MediaLibraryStore.makeForTesting()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibrarySearchAlbumTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            store.close()
            try? FileManager.default.removeItem(at: dir)
        }
        store.open(at: dir.appendingPathComponent("library.sqlite"))

        let tracks = [
            LibraryTrack(url: URL(fileURLWithPath: "/tmp/signals.flac"), title: "Subdivisions",
                         artist: "Rush", album: "Signals", albumArtist: nil),
            LibraryTrack(url: URL(fileURLWithPath: "/tmp/presto.flac"), title: "Show Don't Tell",
                         artist: "Rush", album: "Presto", albumArtist: ""),
            LibraryTrack(url: URL(fileURLWithPath: "/tmp/other.flac"), title: "Other",
                         artist: "Someone", album: "Elsewhere", albumArtist: "Someone"),
        ]
        store.upsertTracks(tracks.map { (track: $0, sig: nil) })

        XCTAssertEqual(store.searchAlbumSummaries(query: "rush").map(\.name), ["Presto", "Signals"])
    }
}
