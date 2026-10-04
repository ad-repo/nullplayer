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
        let sort = LibraryBrowserTabSort(menuSort: .dateAddedDesc, columnSortId: "year", columnSortAscending: false)
        LibraryBrowserTabSortStore.save(sort, modeRawValue: 1, defaults: defaults)

        XCTAssertEqual(LibraryBrowserTabSortStore.load(modeRawValue: 1, defaults: defaults), sort)
    }

    func testTabsAreIndependent() {
        let albums = LibraryBrowserTabSort(menuSort: .dateAddedDesc)
        let plists = LibraryBrowserTabSort(menuSort: .nameAsc, columnSortId: "title", columnSortAscending: false)
        LibraryBrowserTabSortStore.save(albums, modeRawValue: 1, defaults: defaults)
        LibraryBrowserTabSortStore.save(plists, modeRawValue: 3, defaults: defaults)

        XCTAssertEqual(LibraryBrowserTabSortStore.load(modeRawValue: 1, defaults: defaults), albums)
        XCTAssertEqual(LibraryBrowserTabSortStore.load(modeRawValue: 3, defaults: defaults), plists)
        XCTAssertEqual(LibraryBrowserTabSortStore.load(modeRawValue: 0, defaults: defaults), LibraryBrowserTabSort())
    }

    func testClearingColumnSortPersistsNil() {
        LibraryBrowserTabSortStore.save(LibraryBrowserTabSort(columnSortId: "title"), modeRawValue: 0, defaults: defaults)
        LibraryBrowserTabSortStore.save(LibraryBrowserTabSort(menuSort: .nameDesc), modeRawValue: 0, defaults: defaults)

        XCTAssertNil(LibraryBrowserTabSortStore.load(modeRawValue: 0, defaults: defaults).columnSortId)
    }

    func testTabWithoutEntryStartsFromLegacyGlobalSort() {
        defaults.set("Year (Newest)", forKey: "BrowserSortOption")
        defaults.set("title", forKey: "BrowserColumnSortId")
        defaults.set(false, forKey: "BrowserColumnSortAscending")
        let legacy = LibraryBrowserTabSort(menuSort: .yearDesc, columnSortId: "title", columnSortAscending: false)

        XCTAssertEqual(LibraryBrowserTabSortStore.load(modeRawValue: 0, defaults: defaults), legacy)

        LibraryBrowserTabSortStore.save(LibraryBrowserTabSort(), modeRawValue: 1, defaults: defaults)
        // The first save carries the legacy sort over; the old keys are not read again.
        defaults.set("Name Z-A", forKey: "BrowserSortOption")

        XCTAssertEqual(LibraryBrowserTabSortStore.load(modeRawValue: 0, defaults: defaults), legacy)
        XCTAssertNil(LibraryBrowserTabSortStore.load(modeRawValue: 1, defaults: defaults).columnSortId)
    }

    func testClearColumnSortDropsHiddenColumnFromEveryTabAndLegacySort() {
        defaults.set("rating", forKey: "BrowserColumnSortId")
        LibraryBrowserTabSortStore.save(
            LibraryBrowserTabSort(columnSortId: "rating", columnSortAscending: false), modeRawValue: 0, defaults: defaults
        )
        LibraryBrowserTabSortStore.save(
            LibraryBrowserTabSort(menuSort: .dateAddedDesc, columnSortId: "year"), modeRawValue: 1, defaults: defaults
        )

        LibraryBrowserTabSortStore.clearColumnSort(id: "rating", defaults: defaults)

        XCTAssertEqual(
            LibraryBrowserTabSortStore.load(modeRawValue: 0, defaults: defaults),
            LibraryBrowserTabSort(columnSortAscending: false)
        )
        XCTAssertEqual(LibraryBrowserTabSortStore.load(modeRawValue: 1, defaults: defaults).columnSortId, "year")
        XCTAssertNil(LibraryBrowserTabSortStore.load(modeRawValue: 3, defaults: defaults).columnSortId)
    }

    /// The store is keyed by browse-mode raw value and shared by both browsers, so the two
    /// browse-mode enums must agree, as must the two sort-option enums the store converts between.
    func testClassicAndModernEnumsShareRawValues() {
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: PlexBrowseMode.allCases.map { ($0.rawValue, $0.title) }),
            Dictionary(uniqueKeysWithValues: ModernBrowseMode.allCases.map { ($0.rawValue, $0.title) })
        )
        for option in BrowserSortOption.allCases {
            XCTAssertEqual(option.asModernSort.rawValue, option.rawValue)
            XCTAssertEqual(BrowserSortOption(option.asModernSort), option)
        }
        XCTAssertEqual(BrowserSortOption.allCases.count, ModernBrowserSortOption.allCases.count)
    }
}
