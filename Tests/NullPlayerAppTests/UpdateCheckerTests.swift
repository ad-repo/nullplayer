import XCTest
@testable import NullPlayer

final class UpdateCheckerTests: XCTestCase {
    func testIsNewerComparesVersionComponentsNumerically() {
        XCTAssertTrue(UpdateChecker.isNewer("0.34.10", than: "0.34.9"))
        XCTAssertTrue(UpdateChecker.isNewer("0.35.0", than: "0.34.2"))
        XCTAssertTrue(UpdateChecker.isNewer("v1.0", than: "0.34.2"))
        XCTAssertFalse(UpdateChecker.isNewer("0.34.2", than: "0.34.2"))
        XCTAssertFalse(UpdateChecker.isNewer("0.34.1", than: "0.34.2"))
    }
}
