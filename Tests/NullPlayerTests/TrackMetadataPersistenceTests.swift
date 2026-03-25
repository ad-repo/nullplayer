import XCTest
@testable import NullPlayer

final class TrackMetadataPersistenceTests: XCTestCase {

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

    func testUpsertAndReadPersistsExtendedMetadataFields() {
        var track = LibraryTrack(url: URL(fileURLWithPath: "/tmp/persist_ext.mp3"), title: "Persist")
        track.artist = "Artist"
        track.album = "Album"
        track.albumArtist = "Artist"
        track.composer = "Composer"
        track.comment = "Comment"
        track.grouping = "Group"
        track.bpm = 128
        track.musicalKey = "8A"
        track.isrc = "US-R1L-99-12345"
        track.copyright = "2026 Test"
        track.musicBrainzRecordingID = "mb-recording-id"
        track.musicBrainzReleaseID = "mb-release-id"
        track.discogsReleaseID = 123
        track.discogsMasterID = 456
        track.discogsLabel = "Label"
        track.discogsCatalogNumber = "CAT-001"
        track.artworkURL = "https://example.com/art.jpg"
        store.upsertTrack(track, sig: nil)

        let readBack = store.allTracks().first { $0.url == track.url }
        XCTAssertNotNil(readBack)
        XCTAssertEqual(readBack?.composer, "Composer")
        XCTAssertEqual(readBack?.comment, "Comment")
        XCTAssertEqual(readBack?.grouping, "Group")
        XCTAssertEqual(readBack?.bpm, 128)
        XCTAssertEqual(readBack?.musicalKey, "8A")
        XCTAssertEqual(readBack?.isrc, "US-R1L-99-12345")
        XCTAssertEqual(readBack?.copyright, "2026 Test")
        XCTAssertEqual(readBack?.musicBrainzRecordingID, "mb-recording-id")
        XCTAssertEqual(readBack?.musicBrainzReleaseID, "mb-release-id")
        XCTAssertEqual(readBack?.discogsReleaseID, 123)
        XCTAssertEqual(readBack?.discogsMasterID, 456)
        XCTAssertEqual(readBack?.discogsLabel, "Label")
        XCTAssertEqual(readBack?.discogsCatalogNumber, "CAT-001")
        XCTAssertEqual(readBack?.artworkURL, "https://example.com/art.jpg")
    }

    func testExtendedMetadataAvailableInSearchAndAlbumQueries() {
        var track = LibraryTrack(url: URL(fileURLWithPath: "/tmp/persist_query.mp3"), title: "Searchable")
        track.artist = "Search Artist"
        track.album = "Search Album"
        track.albumArtist = "Search Artist"
        track.discogsCatalogNumber = "CAT-SEARCH-01"
        track.musicBrainzReleaseID = "mb-search-release"
        store.upsertTrack(track, sig: nil)

        let bySearch = store.searchTracks(query: "Searchable", limit: 10, offset: 0).first
        XCTAssertEqual(bySearch?.discogsCatalogNumber, "CAT-SEARCH-01")
        XCTAssertEqual(bySearch?.musicBrainzReleaseID, "mb-search-release")

        let albumTracks = store.tracksForAlbum("Search Artist|Search Album")
        XCTAssertEqual(albumTracks.first?.discogsCatalogNumber, "CAT-SEARCH-01")
        XCTAssertEqual(albumTracks.first?.musicBrainzReleaseID, "mb-search-release")
    }

    func testUpsertTrackRefreshesTrackArtistsFromEditedMetadata() {
        var track = LibraryTrack(url: URL(fileURLWithPath: "/tmp/persist_artist_edit.mp3"), title: "Editable")
        track.artist = "Old Artist"
        track.album = "Edited Album"
        track.albumArtist = "Old Artist"
        store.upsertTrack(track, sig: nil)

        track.artist = "New Artist"
        track.albumArtist = "New Artist"
        store.upsertTrack(track, sig: nil)

        let artistNames = store.artistNames(limit: 20, offset: 0, sort: .nameAsc)
        XCTAssertTrue(artistNames.contains("New Artist"))
        XCTAssertFalse(artistNames.contains("Old Artist"))

        let albumTracks = store.tracksForAlbum("New Artist|Edited Album")
        XCTAssertEqual(albumTracks.count, 1)
        XCTAssertEqual(albumTracks.first?.artist, "New Artist")
        XCTAssertEqual(albumTracks.first?.albumArtist, "New Artist")
    }
}
