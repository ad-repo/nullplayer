import XCTest
@testable import NullPlayer

final class LibraryBrowserTabSortTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LibraryBrowserTabSortTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testRoundTripsSortForOneTab() {
        let sort = LibraryBrowserTabSort(menuSortRawValue: "Recently Added", columnSortId: "year", columnSortAscending: false)
        LibraryBrowserTabSortStore.save(sort, modeRawValue: 1, defaults: defaults)

        XCTAssertEqual(LibraryBrowserTabSortStore.load(modeRawValue: 1, defaults: defaults), sort)
    }

    func testTabsAreIndependent() {
        let albums = LibraryBrowserTabSort(menuSortRawValue: "Recently Added", columnSortId: nil, columnSortAscending: true)
        let plists = LibraryBrowserTabSort(menuSortRawValue: "Name A-Z", columnSortId: "title", columnSortAscending: false)
        LibraryBrowserTabSortStore.save(albums, modeRawValue: 1, defaults: defaults)
        LibraryBrowserTabSortStore.save(plists, modeRawValue: 3, defaults: defaults)

        XCTAssertEqual(LibraryBrowserTabSortStore.load(modeRawValue: 1, defaults: defaults), albums)
        XCTAssertEqual(LibraryBrowserTabSortStore.load(modeRawValue: 3, defaults: defaults), plists)
        XCTAssertEqual(
            LibraryBrowserTabSortStore.load(modeRawValue: 0, defaults: defaults),
            LibraryBrowserTabSort(menuSortRawValue: "Name A-Z", columnSortId: nil, columnSortAscending: true)
        )
    }

    func testClearingColumnSortPersistsNil() {
        LibraryBrowserTabSortStore.save(
            LibraryBrowserTabSort(menuSortRawValue: "Name A-Z", columnSortId: "title", columnSortAscending: true),
            modeRawValue: 0, defaults: defaults
        )
        LibraryBrowserTabSortStore.save(
            LibraryBrowserTabSort(menuSortRawValue: "Name Z-A", columnSortId: nil, columnSortAscending: true),
            modeRawValue: 0, defaults: defaults
        )

        XCTAssertNil(LibraryBrowserTabSortStore.load(modeRawValue: 0, defaults: defaults).columnSortId)
    }

    func testTabWithoutEntryFallsBackToLegacyGlobalSort() {
        defaults.set("Year (Newest)", forKey: "BrowserSortOption")
        defaults.set("title", forKey: "BrowserColumnSortId")
        defaults.set(false, forKey: "BrowserColumnSortAscending")
        LibraryBrowserTabSortStore.save(
            LibraryBrowserTabSort(menuSortRawValue: "Name A-Z", columnSortId: nil, columnSortAscending: true),
            modeRawValue: 1, defaults: defaults
        )

        XCTAssertEqual(
            LibraryBrowserTabSortStore.load(modeRawValue: 0, defaults: defaults),
            LibraryBrowserTabSort(menuSortRawValue: "Year (Newest)", columnSortId: "title", columnSortAscending: false)
        )
        XCTAssertNil(LibraryBrowserTabSortStore.load(modeRawValue: 1, defaults: defaults).columnSortId)
        XCTAssertEqual(defaults.string(forKey: "BrowserSortOption"), "Year (Newest)")
    }

    func testClearColumnSortDropsHiddenColumnFromEveryTabAndLegacyKey() {
        defaults.set("rating", forKey: "BrowserColumnSortId")
        LibraryBrowserTabSortStore.save(
            LibraryBrowserTabSort(menuSortRawValue: "Name A-Z", columnSortId: "rating", columnSortAscending: false),
            modeRawValue: 0, defaults: defaults
        )
        LibraryBrowserTabSortStore.save(
            LibraryBrowserTabSort(menuSortRawValue: "Recently Added", columnSortId: "year", columnSortAscending: true),
            modeRawValue: 1, defaults: defaults
        )

        LibraryBrowserTabSortStore.clearColumnSort(id: "rating", defaults: defaults)

        XCTAssertEqual(
            LibraryBrowserTabSortStore.load(modeRawValue: 0, defaults: defaults),
            LibraryBrowserTabSort(menuSortRawValue: "Name A-Z", columnSortId: nil, columnSortAscending: false)
        )
        XCTAssertEqual(LibraryBrowserTabSortStore.load(modeRawValue: 1, defaults: defaults).columnSortId, "year")
        XCTAssertNil(defaults.string(forKey: "BrowserColumnSortId"))
        XCTAssertNil(LibraryBrowserTabSortStore.load(modeRawValue: 3, defaults: defaults).columnSortId)
    }
}
