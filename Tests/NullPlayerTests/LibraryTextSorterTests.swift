import XCTest
@testable import NullPlayer

final class LibraryTextSorterTests: XCTestCase {

    func testNaturalNumericOrderingAscending() {
        let values = ["Track 10", "Track 2", "Track 1"]
        let sorted = values.sorted {
            LibraryTextSorter.areInOrder(
                $0,
                $1,
                ascending: true,
                ignoreLeadingArticles: false
            )
        }

        XCTAssertEqual(sorted, ["Track 1", "Track 2", "Track 10"])
    }

    func testCaseInsensitiveCompareTreatsEqualStringsAsSame() {
        let result = LibraryTextSorter.compare(
            "alpha",
            "ALPHA",
            ignoreLeadingArticles: false
        )

        XCTAssertEqual(result, .orderedSame)
    }

    func testLeadingArticleNormalizationCanBeToggled() {
        let normalized = LibraryTextSorter.normalized("The Beatles", ignoreLeadingArticles: true)
        let unchanged = LibraryTextSorter.normalized("The Beatles", ignoreLeadingArticles: false)

        XCTAssertEqual(normalized, "Beatles")
        XCTAssertEqual(unchanged, "The Beatles")
    }

    func testNaturalNumericOrderingDescending() {
        let values = ["Track 1", "Track 2", "Track 10"]
        let sorted = values.sorted {
            LibraryTextSorter.areInOrder(
                $0,
                $1,
                ascending: false,
                ignoreLeadingArticles: false
            )
        }

        XCTAssertEqual(sorted, ["Track 10", "Track 2", "Track 1"])
    }
}
