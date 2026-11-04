import Foundation
import XCTest
@testable import NullPlayer

/// The skin's library window over one build of NullPlayer's library (`AIMPSkinLibrary`).
final class AIMPSkinLibraryTests: XCTestCase {
    private func track(_ title: String, artist: String?, album: String? = nil, number: Int? = nil) -> LibraryTrack {
        LibraryTrack(url: URL(fileURLWithPath: "/Music/\(artist ?? "x")/\(title).mp3"), title: title, artist: artist, album: album,
                     trackNumber: number)
    }

    func testTracksAreLookedUpInTheBuildByID() {
        let tracks = [track("One", artist: "A"), track("Two", artist: "B"), track("Three", artist: "C")]
        let library = AIMPSkinLibrary(tracks: tracks)
        XCTAssertEqual(library.tracks([tracks[2].id, UUID(), tracks[0].id]).map(\.title), ["Three", "One"],
                       "in the order asked, an id the build lacks left out")
    }

    func testGroupsSortAsTheLibraryBrowserSortsThem() {
        let library = AIMPSkinLibrary(tracks: [track("1", artist: "Zappa"), track("2", artist: "The Beatles"),
                                               track("3", artist: nil), track("4", artist: "abba")])
        let rows = library.rows(.artistAlbum, expanded: [], search: "").map(\.name)
        XCTAssertEqual(rows, ["All Tracks", "abba", "The Beatles", "Unknown Artist", "Zappa"], "a leading article is not sorted on")
    }

    func testTheTableRunsByAlbumThenNumber() {
        let library = AIMPSkinLibrary(tracks: [track("b", artist: "A", album: "Y", number: 2), track("a", artist: "A", album: "Y", number: 1),
                                               track("c", artist: "A", album: "X", number: 9)])
        XCTAssertEqual(library.table(.artistAlbum, path: "A", search: "").map { library.tracks[$0].title }, ["c", "a", "b"])
        XCTAssertEqual(AIMPSkinLibrary.seconds(track("d", artist: nil)), 0)
    }
}
