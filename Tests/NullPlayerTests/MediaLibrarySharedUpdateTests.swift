import XCTest
@testable import NullPlayer

final class MediaLibrarySharedUpdateTests: XCTestCase {

    func testUpdateTrackPersistsEvenWhenTrackWasNotAlreadyLoadedInMemory() {
        let url = URL(fileURLWithPath: "/tmp/nullplayer-shared-update-\(UUID().uuidString).mp3")
        let library = MediaLibrary.shared
        let store = MediaLibraryStore.shared

        addTeardownBlock { library.removeTracks(urls: [url]) }
        library.removeTracks(urls: [url])

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
}
