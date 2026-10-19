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

    func testHeaderGroupFollowsTheMostDetailedExpandedRows() {
        // Artists tab: collapsed, an artist expanded, then one of its albums expanded.
        XCTAssertEqual(LibraryColumnVisibility.headerGroup([.artist, .artist]), .artist)
        XCTAssertEqual(LibraryColumnVisibility.headerGroup([.artist, .album, .artist]), .album)
        XCTAssertEqual(LibraryColumnVisibility.headerGroup([.artist, .album, .track, .album]), .track)
    }

    func testHeaderGroupIgnoresRowsWithoutSharedColumns() {
        // Plists tab: playlist rows carry no columns, their tracks do. YouTube rows keep their own.
        XCTAssertEqual(LibraryColumnVisibility.headerGroup([nil, .track, nil]), .track)
        XCTAssertEqual(LibraryColumnVisibility.headerGroup([.youtube, nil]), nil)
    }

    func testColumnVisibilityGroupMenuLabelsMatchUserFacingSections() {
        XCTAssertEqual(LibraryColumnVisibilityGroup.artist.headerTitle, "Artist columns")
        XCTAssertEqual(LibraryColumnVisibilityGroup.album.headerTitle, "Album columns")
        XCTAssertEqual(LibraryColumnVisibilityGroup.track.headerTitle, "Track columns")
        XCTAssertEqual(LibraryColumnVisibilityGroup.artist.resetTitle, "Reset Artist Columns")
        XCTAssertEqual(LibraryColumnVisibilityGroup.album.resetTitle, "Reset Album Columns")
        XCTAssertEqual(LibraryColumnVisibilityGroup.track.resetTitle, "Reset Track Columns")
    }

    func testChannelSortValueMapsFormattedLabelsToComparableChannelCounts() {
        XCTAssertEqual(LibraryColumnVisibility.channelSortValue("Mono"), 1)
        XCTAssertEqual(LibraryColumnVisibility.channelSortValue("Stereo"), 2)
        XCTAssertEqual(LibraryColumnVisibility.channelSortValue("5.1"), 6)
        XCTAssertEqual(LibraryColumnVisibility.channelSortValue("7.1"), 8)
        XCTAssertEqual(LibraryColumnVisibility.channelSortValue("10ch"), 10)
    }

    /// #542: under track columns the `#` cell (30 pt after the 4 pt pad) already puts a track right
    /// of its album, while an artist or album row, which has nothing for `#`, spans it from the pad.
    /// Every other cell stays under its heading.
    func testCellFramesIndentTheTitleOnlyByWhatTheLeadingCellsLeaveShort() {
        func titleStart(_ indent: CGFloat, spans: Bool, widths: [CGFloat] = [30, 120, 50], title: Int = 1) -> CGFloat {
            LibraryColumnVisibility.cellFrames(widths: widths, titleIndex: title, indent: indent, spansLeadingCells: spans)[title].start
        }
        XCTAssertEqual(titleStart(32, spans: false), 36, "a two-deep track indents just past the # cell")
        XCTAssertEqual(titleStart(0, spans: false), 34, "a top-level track sits after the # cell")
        XCTAssertEqual(titleStart(0, spans: true), 4, "an artist row under track columns stays at the pad")
        XCTAssertEqual(titleStart(16, spans: true), 20, "an album row indents from the pad, as a plain row does")
        XCTAssertEqual(titleStart(16, spans: false, widths: [120, 50], title: 0), 20, "the same album under album columns")

        let cells = LibraryColumnVisibility.cellFrames(widths: [30, 120, 50], titleIndex: 1, indent: 16, spansLeadingCells: true)
        XCTAssertEqual(cells.map(\.start), [4, 20, 154])
        XCTAssertEqual(cells.map(\.width), [30, 134, 50], "the title cell still ends where its heading does")
    }
}
