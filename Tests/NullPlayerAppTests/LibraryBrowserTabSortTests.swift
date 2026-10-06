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

    /// A fresh store over the same defaults, as on the next launch.
    private func relaunched() -> LibraryBrowserTabSortStore {
        LibraryBrowserTabSortStore(defaults: defaults)
    }

    func testRoundTripsSortForOneTab() {
        let store = relaunched()
        store.setMenuSort(.dateAddedDesc, for: 1)
        store.clickColumn("year", for: 1)
        store.clickColumn("year", for: 1)

        let expected = LibraryBrowserTabSort(menuSort: .dateAddedDesc, columnSortId: "year", columnSortAscending: false)
        XCTAssertEqual(store.sort(for: 1), expected)
        XCTAssertEqual(relaunched().sort(for: 1), expected)
    }

    func testTabsAreIndependent() {
        let store = relaunched()
        store.setMenuSort(.dateAddedDesc, for: 1)
        store.clickColumn("title", for: 3)

        let reloaded = relaunched()
        XCTAssertEqual(reloaded.sort(for: 1), LibraryBrowserTabSort(menuSort: .dateAddedDesc))
        XCTAssertEqual(reloaded.sort(for: 3), LibraryBrowserTabSort(columnSortId: "title"))
        XCTAssertEqual(reloaded.sort(for: 0), LibraryBrowserTabSort())
    }

    func testClickingANewColumnSortsAscending() {
        let store = relaunched()
        store.clickColumn("title", for: 0)
        store.clickColumn("title", for: 0)
        store.clickColumn("year", for: 0)

        XCTAssertEqual(store.sort(for: 0), LibraryBrowserTabSort(columnSortId: "year", columnSortAscending: true))
    }

    func testMenuSortReplacesColumnSort() {
        let store = relaunched()
        store.clickColumn("title", for: 0)
        store.setMenuSort(.nameDesc, for: 0)

        XCTAssertNil(relaunched().sort(for: 0).columnSortId)
    }

    func testTabWithoutEntryStartsFromLegacyGlobalSort() {
        defaults.set("Year (Newest)", forKey: "BrowserSortOption")
        defaults.set("title", forKey: "BrowserColumnSortId")
        defaults.set(false, forKey: "BrowserColumnSortAscending")
        let legacy = LibraryBrowserTabSort(menuSort: .yearDesc, columnSortId: "title", columnSortAscending: false)

        let store = relaunched()
        XCTAssertEqual(store.sort(for: 0), legacy)

        store.setMenuSort(.nameAsc, for: 1)
        // The first save carries the legacy sort over; the old keys are not read again.
        defaults.set("Name Z-A", forKey: "BrowserSortOption")

        let reloaded = relaunched()
        XCTAssertEqual(reloaded.sort(for: 0), legacy)
        XCTAssertNil(reloaded.sort(for: 1).columnSortId)
    }

    func testDropColumnClearsItFromEveryTabAndLegacySort() {
        defaults.set("rating", forKey: "BrowserColumnSortId")
        let store = relaunched()
        // Tab 0 starts from the legacy "rating" sort, so this click flips it to descending.
        store.clickColumn("rating", for: 0)
        store.setMenuSort(.dateAddedDesc, for: 1)
        store.clickColumn("year", for: 1)

        store.dropColumn("rating")

        let reloaded = relaunched()
        XCTAssertEqual(reloaded.sort(for: 0), LibraryBrowserTabSort(columnSortAscending: false))
        XCTAssertEqual(reloaded.sort(for: 1).columnSortId, "year")
        XCTAssertNil(reloaded.sort(for: 3).columnSortId)
    }

    /// The store is keyed by browse-mode raw value and shared by both browsers, so the two
    /// browse-mode enums must agree.
    func testClassicAndModernBrowseModesShareRawValues() {
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: PlexBrowseMode.allCases.map { ($0.rawValue, $0.title) }),
            Dictionary(uniqueKeysWithValues: ModernBrowseMode.allCases.map { ($0.rawValue, $0.title) })
        )
    }
}
