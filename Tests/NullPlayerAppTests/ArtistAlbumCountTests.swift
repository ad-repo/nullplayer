import XCTest
@testable import NullPlayer

final class ArtistAlbumCountTests: XCTestCase {
    private struct Artist: AlbumCountedArtist {
        let id: String
        var albumCount = -1
    }

    private struct Album: AlbumArtistCredited {
        let albumArtistIds: [String]
    }

    func testCountsEveryCreditedAlbumArtistAndZeroesTheRest() {
        let artists = [Artist(id: "a"), Artist(id: "b"), Artist(id: "c")]
        let albums = [Album(albumArtistIds: ["a"]), Album(albumArtistIds: ["a", "b"]), Album(albumArtistIds: [])]

        XCTAssertEqual(artists.countingAlbums(albums).map(\.albumCount), [2, 1, 0])
    }
}
