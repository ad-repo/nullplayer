import XCTest
@testable import NullPlayer

final class UpdateCheckerTests: XCTestCase {
    private func release(_ tag: String, assets: String = #"[{"name":"NullPlayer.dmg","browser_download_url":"https://example.com/NullPlayer.dmg"}]"#) -> Data {
        Data(#"{"tag_name":"\#(tag)","assets":\#(assets)}"#.utf8)
    }

    func testIsNewerComparesVersionComponentsNumerically() {
        XCTAssertTrue(UpdateChecker.isNewer("0.34.10", than: "0.34.9"))
        XCTAssertTrue(UpdateChecker.isNewer("0.35.0", than: "0.34.2"))
        XCTAssertTrue(UpdateChecker.isNewer("v1.0", than: "0.34.2"))
        XCTAssertFalse(UpdateChecker.isNewer("0.34.2", than: "0.34.2"))
        XCTAssertFalse(UpdateChecker.isNewer("0.34.1", than: "0.34.2"))
    }

    func testNewerReleaseOffersItsStableDMG() {
        XCTAssertEqual(UpdateChecker.outcome(data: release("0.35.0"), statusCode: 200, current: "0.34.2"),
                       .available(tag: "0.35.0", dmg: URL(string: "https://example.com/NullPlayer.dmg")!))
    }

    func testSameReleaseIsUpToDateEvenWithoutAssets() {
        XCTAssertEqual(UpdateChecker.outcome(data: release("0.34.2", assets: "[]"), statusCode: 200, current: "0.34.2"),
                       .upToDate)
    }

    func testFailures() {
        XCTAssertEqual(UpdateChecker.outcome(data: Data(#"{"message":"API rate limit exceeded"}"#.utf8),
                                             statusCode: 403, current: "0.34.2"),
                       .failed("GitHub answered with HTTP 403."))
        XCTAssertEqual(UpdateChecker.outcome(data: Data("nope".utf8), statusCode: 200, current: "0.34.2"),
                       .failed("GitHub's reply could not be read."))
        XCTAssertEqual(UpdateChecker.outcome(data: release("0.35.0", assets: "[]"), statusCode: 200, current: "0.34.2"),
                       .failed("Release 0.35.0 has no NullPlayer.dmg."))
    }
}
