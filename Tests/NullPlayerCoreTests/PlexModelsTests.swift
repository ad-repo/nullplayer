import XCTest
@testable import NullPlayerCore

final class PlexModelsTests: XCTestCase {
    func testSmartPlaylistDecodingPreservesContentAndLibrarySectionID() throws {
        let json = """
        {
          "MediaContainer": {
            "size": 1,
            "Metadata": [
              {
                "ratingKey": "42",
                "key": "/playlists/42/items",
                "type": "playlist",
                "title": "Smart Mix",
                "playlistType": "audio",
                "smart": true,
                "content": "/library/sections/15/all?type=10&sort=random",
                "leafCount": 12
              }
            ]
          }
        }
        """

        let response = try JSONDecoder().decode(PlexResponse<PlexMetadataResponse>.self, from: Data(json.utf8))
        let playlist = try XCTUnwrap(response.mediaContainer.metadata?.first?.toPlaylist())

        XCTAssertTrue(playlist.smart)
        XCTAssertEqual(playlist.content, "/library/sections/15/all?type=10&sort=random")
        XCTAssertEqual(playlist.librarySectionID, "15")
    }

    func testLibrarySectionIDReturnsNilWhenContentHasNoSectionPath() {
        let playlist = PlexPlaylist(
            id: "42",
            key: "/playlists/42/items",
            title: "Manual Mix",
            summary: nil,
            playlistType: "audio",
            smart: false,
            content: nil,
            thumb: nil,
            composite: nil,
            duration: nil,
            leafCount: 0,
            addedAt: nil,
            updatedAt: nil
        )

        XCTAssertNil(playlist.librarySectionID)
    }
}
