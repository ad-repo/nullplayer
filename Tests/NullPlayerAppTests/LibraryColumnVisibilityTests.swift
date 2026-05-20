import XCTest
@testable import NullPlayer

final class LibraryColumnVisibilityTests: XCTestCase {
    private struct TestColumn {
        let id: String
    }

    func testNormalizedIdsFiltersUnknownIdsDeduplicatesAndRestoresTitle() {
        let ids = LibraryColumnVisibility.normalizedIds(
            ["genre", "unknown", "genre", "rating"],
            allIds: ["title", "artist", "genre", "rating"]
        )

        XCTAssertEqual(ids, ["title", "genre", "rating"])
    }

    func testNormalizedIdsPreservesExistingTitlePosition() {
        let ids = LibraryColumnVisibility.normalizedIds(
            ["genre", "title", "artist"],
            allIds: ["title", "artist", "genre"]
        )

        XCTAssertEqual(ids, ["genre", "title", "artist"])
    }

    func testVisibleColumnsReturnsNormalizedColumnsInVisibleOrder() {
        let columns = [
            TestColumn(id: "title"),
            TestColumn(id: "artist"),
            TestColumn(id: "album"),
            TestColumn(id: "rating")
        ]

        let visible = LibraryColumnVisibility.visibleColumns(
            allColumns: columns,
            visibleIds: ["rating", "missing", "artist", "rating"],
            id: { $0.id }
        )

        XCTAssertEqual(visible.map(\.id), ["title", "rating", "artist"])
    }

    func testArtistsModeMenuIncludesArtistAlbumAndTrackSections() {
        let groups = LibraryColumnVisibility.menuGroups(
            isArtistsMode: true,
            isAlbumsMode: false,
            hasTrackRows: false,
            hasAlbumRows: false,
            hasArtistRows: true
        )

        XCTAssertEqual(groups, [.artist, .album, .track])
    }

    func testAlbumsModeMenuIncludesAlbumAndTrackSections() {
        let groups = LibraryColumnVisibility.menuGroups(
            isArtistsMode: false,
            isAlbumsMode: true,
            hasTrackRows: false,
            hasAlbumRows: true,
            hasArtistRows: false
        )

        XCTAssertEqual(groups, [.album, .track])
    }

    func testFallbackMenuGroupUsesCurrentRowTypePrecedence() {
        XCTAssertEqual(
            LibraryColumnVisibility.menuGroups(
                isArtistsMode: false,
                isAlbumsMode: false,
                hasTrackRows: true,
                hasAlbumRows: true,
                hasArtistRows: true
            ),
            [.track]
        )

        XCTAssertEqual(
            LibraryColumnVisibility.menuGroups(
                isArtistsMode: false,
                isAlbumsMode: false,
                hasTrackRows: false,
                hasAlbumRows: true,
                hasArtistRows: true
            ),
            [.album]
        )

        XCTAssertEqual(
            LibraryColumnVisibility.menuGroups(
                isArtistsMode: false,
                isAlbumsMode: false,
                hasTrackRows: false,
                hasAlbumRows: false,
                hasArtistRows: true
            ),
            [.artist]
        )
    }

    func testColumnVisibilityGroupMenuLabelsMatchUserFacingSections() {
        XCTAssertEqual(LibraryColumnVisibilityGroup.artist.headerTitle, "Artist columns")
        XCTAssertEqual(LibraryColumnVisibilityGroup.album.headerTitle, "Album columns")
        XCTAssertEqual(LibraryColumnVisibilityGroup.track.headerTitle, "Track columns")
        XCTAssertEqual(LibraryColumnVisibilityGroup.artist.resetTitle, "Reset Artist Columns")
        XCTAssertEqual(LibraryColumnVisibilityGroup.album.resetTitle, "Reset Album Columns")
        XCTAssertEqual(LibraryColumnVisibilityGroup.track.resetTitle, "Reset Track Columns")
    }
}
