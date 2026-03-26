import XCTest
@testable import NullPlayer

final class MediaLibrarySharedUpdateTests: XCTestCase {

    func testUpdateTrackPersistsEvenWhenTrackWasNotAlreadyLoadedInMemory() {
        let url = URL(fileURLWithPath: "/tmp/nullplayer-shared-update-\(UUID().uuidString).mp3")
        let library = MediaLibrary.shared
        let store = MediaLibraryStore.shared

        addTeardownBlock { library.removeTracks(urls: [url]) }
        library.removeTracks(urls: [url])

        // Seed the track directly into the store to simulate a library entry that
        // exists on disk but has not yet been loaded into the in-memory cache.
        var seed = LibraryTrack(url: url)
        seed.title = "Seed Title"
        store.upsertTrack(seed, sig: nil)

        var track = LibraryTrack(url: url)
        track.title = "Shared Update Title"
        track.artist = "Shared Update Artist"
        track.album = "Shared Update Album"
        track.albumArtist = "Shared Update Artist"
        track.genre = "Rock"
        track.year = 2003

        library.updateTrack(track)

        let persisted = store.tracksForAlbum("Shared Update Artist|Shared Update Album")
            .first(where: { $0.url == url })

        XCTAssertNotNil(persisted)
        XCTAssertEqual(persisted?.title, "Shared Update Title")
        XCTAssertEqual(persisted?.artist, "Shared Update Artist")
        XCTAssertEqual(persisted?.albumArtist, "Shared Update Artist")
        XCTAssertEqual(persisted?.genre, "Rock")
        XCTAssertEqual(persisted?.year, 2003)

        library.removeTracks(urls: [url])
    }

    /// updateTrack must not recreate a row that was deleted from the store.
    /// Saving a stale editor snapshot after the track is removed should be a no-op.
    func testUpdateTrackIsNoOpWhenRowDoesNotExistInStore() {
        let url = URL(fileURLWithPath: "/tmp/nullplayer-shared-update-\(UUID().uuidString).mp3")
        let library = MediaLibrary.shared
        let store = MediaLibraryStore.shared

        addTeardownBlock { library.removeTracks(urls: [url]) }
        library.removeTracks(urls: [url])

        var stale = LibraryTrack(url: url)
        stale.title = "Stale Title"
        stale.album = "Stale Album"
        stale.albumArtist = "Stale Artist"

        // The track does not exist in the store — updateTrack should be a no-op.
        library.updateTrack(stale)

        let recreated = store.tracksForAlbum("Stale Artist|Stale Album")
            .first(where: { $0.url == url })
        XCTAssertNil(recreated, "updateTrack must not recreate a deleted row")
    }
}
