import XCTest
@testable import NullPlayer

/// `LibraryBrowserListLayout(content:…)` splits the list area for both browser views: the classic
/// view in flipped skin coordinates, the modern view in bottom-left view coordinates.
final class LibraryBrowserListLayoutTests: XCTestCase {
    private let columns = [LibraryBrowserColumn.title, .artist]

    func testClassicFlippedLayoutPutsBannerAtBottomAndAlphabetBesideHeader() {
        let layout = LibraryBrowserListLayout(
            content: NSRect(x: 10, y: 50, width: 300, height: 200), bannerHeight: 18,
            columns: columns, group: nil, headerHeight: 20,
            scrollbarWidth: 8, alphabetWidth: 12, alphabetBesideHeader: true,
            rowHeight: 18, scale: 1, isFlipped: true)

        XCTAssertEqual(layout.area, NSRect(x: 10, y: 50, width: 300, height: 182))
        XCTAssertEqual(layout.banner, NSRect(x: 10, y: 232, width: 300, height: 18))
        XCTAssertEqual(layout.header?.rect, NSRect(x: 10, y: 50, width: 280, height: 20))
        XCTAssertEqual(layout.rows, NSRect(x: 10, y: 70, width: 280, height: 162))
        XCTAssertEqual(layout.alphabet, NSRect(x: 290, y: 50, width: 12, height: 182))
        XCTAssertNil(layout.headerGap, "the classic alphabet index runs beside the header")
        // Row 0 starts at the top of the rows, counted downward in skin coordinates.
        XCTAssertEqual(layout.rowRect(0, scrollOffset: 0), NSRect(x: 10, y: 70, width: 280, height: 18))
        XCTAssertEqual(layout.rowRect(2, scrollOffset: 9), NSRect(x: 10, y: 97, width: 280, height: 18))
    }

    func testModernLayoutPutsBannerAtBottomAndAlphabetUnderHeader() {
        let layout = LibraryBrowserListLayout(
            content: NSRect(x: 0, y: 10, width: 300, height: 200), bannerHeight: 18,
            columns: columns, group: nil, headerHeight: 20,
            scrollbarWidth: 0, alphabetWidth: 16, alphabetBesideHeader: false,
            rowHeight: 18, scale: 1, isFlipped: false)

        XCTAssertEqual(layout.area, NSRect(x: 0, y: 28, width: 300, height: 182))
        XCTAssertEqual(layout.banner, NSRect(x: 0, y: 10, width: 300, height: 18))
        XCTAssertEqual(layout.header?.rect, NSRect(x: 0, y: 190, width: 284, height: 20))
        XCTAssertEqual(layout.rows, NSRect(x: 0, y: 28, width: 284, height: 162))
        XCTAssertEqual(layout.alphabet, NSRect(x: 284, y: 28, width: 16, height: 162))
        XCTAssertEqual(layout.headerGap, NSRect(x: 284, y: 190, width: 16, height: 20),
                       "above the alphabet index, which starts under the header")
        // Row 0 hangs from the top of the rows in bottom-up coordinates.
        XCTAssertEqual(layout.rowRect(0, scrollOffset: 0), NSRect(x: 0, y: 172, width: 284, height: 18))
        XCTAssertEqual(layout.band(1, height: 10, in: layout.alphabet), NSRect(x: 284, y: 170, width: 16, height: 10))
    }

    /// Flow / Tiles draw no header, so the rows and the alphabet index take the full height.
    func testNoColumnsAndNoBannerGiveRowsTheWholeArea() {
        let layout = LibraryBrowserListLayout(
            content: NSRect(x: 0, y: 10, width: 300, height: 200), bannerHeight: 0,
            columns: [], group: nil, headerHeight: 20,
            scrollbarWidth: 0, alphabetWidth: 16, alphabetBesideHeader: false,
            rowHeight: 18, scale: 1, isFlipped: false)

        XCTAssertNil(layout.header)
        XCTAssertNil(layout.banner)
        XCTAssertEqual(layout.area, NSRect(x: 0, y: 10, width: 300, height: 200))
        XCTAssertEqual(layout.rows, NSRect(x: 0, y: 10, width: 284, height: 200))
        XCTAssertEqual(layout.alphabet, NSRect(x: 284, y: 10, width: 16, height: 200))
    }
}
