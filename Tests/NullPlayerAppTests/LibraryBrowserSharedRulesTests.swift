import XCTest
@testable import NullPlayer

/// Rules both library browser views share: tab widths, the letters a row files under, and the
/// radio stations a server lists.
final class LibraryBrowserSharedRulesTests: XCTestCase {

    func testTabWidthsShareTheLeftoverEqually() {
        XCTAssertEqual(LibraryBrowseMode.fitTabWidths([10, 20, 30], into: 90), [20, 30, 40])
    }

    func testTabWidthsShrinkInProportionWhenTheLabelsOverflow() {
        XCTAssertEqual(LibraryBrowseMode.fitTabWidths([20, 60], into: 40), [10, 30])
    }

    func testSlotLabelsIncludeWhatATwoWaySlotSwitchesTo() {
        XCTAssertTrue(LibraryBrowseMode.slotLabels.contains("Folders"))
        XCTAssertTrue(LibraryBrowseMode.slotLabels.contains("Channels"))
        XCTAssertEqual(LibraryBrowseMode.slotLabels.count, LibraryBrowseMode.tabs.count + 2)
    }

    func testSortLetterIgnoresALeadingArticleAndFilesDigitsUnderHash() {
        XCTAssertEqual(LibraryBrowserItem.sortLetter(forTitle: "The Beatles"), "B")
        XCTAssertEqual(LibraryBrowserItem.sortLetter(forTitle: "808 State"), "#")
        XCTAssertEqual(LibraryBrowserItem.sortLetter(forTitle: ""), "#")
    }

    func testTypeAheadMatchesTheStartTheArticlelessStartAndTheCanonicalForm() {
        func item(_ title: String) -> LibraryBrowserItem {
            LibraryBrowserItem(id: title, title: title, info: nil, indentLevel: 0, hasChildren: false, type: .header)
        }
        XCTAssertTrue(item("The Beatles").matchesTypeAhead("the b"))
        XCTAssertTrue(item("The Beatles").matchesTypeAhead("beat"))
        XCTAssertTrue(item("Atlas Moth, The").matchesTypeAhead("the at"))
        XCTAssertFalse(item("Beatles").matchesTypeAhead("x"))
    }

    /// Library and favourites first, then each genre and each decade, plain before Instant Mix.
    func testInstantMixStationsComeInMenuOrder() {
        let stations = InstantMixRadioType.stations(genres: ["Rock"])
        XCTAssertEqual(Array(stations.prefix(6)), [.libraryRadio, .libraryInstantMix, .favoritesRadio,
                                                  .favoritesInstantMix, .genreRadio("Rock"), .genreInstantMix("Rock")])
        XCTAssertEqual(stations.count, 6 + 2 * RadioConfig.decades.count)
        XCTAssertEqual(stations[1].displayName, "Library Radio (Instant Mix)")
        XCTAssertEqual(stations[2].category, "Favorites")
    }

    func testSubsonicStationsComeInMenuOrder() {
        let stations = SubsonicRadioType.stations(genres: ["Jazz"])
        XCTAssertEqual(Array(stations.prefix(6)), [.libraryRadio, .librarySimilar, .starredRadio, .starredSimilar,
                                                  .genreRadio("Jazz"), .genreSimilar("Jazz")])
        XCTAssertEqual(stations.count, 6 + 2 * RadioConfig.decades.count)
    }

    /// Station rows are keyed by category and name, so every row of a list has its own id.
    func testStationIdsAreUnique() {
        let stations = InstantMixRadioType.stations(genres: ["Library", "Rock"])
        let ids = stations.map { "radio-\($0.category)-\($0.displayName)" }
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
