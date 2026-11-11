import XCTest
@testable import NullPlayer

/// B409 — a stream a skin plays by bare address is titled by that address, never by its credentials.
final class WinampModernStreamTitleTests: XCTestCase {
    func testAStreamAddressTitleDropsUserInfoQueryAndFragment() throws {
        let url = try XCTUnwrap(URL(string: "http://me:pw@radio.example:8080/live?token=secret#x"))
        XCTAssertEqual(WinampModernComponentBridge.displayAddress(of: url), "http://radio.example:8080/live")
        let bare = try XCTUnwrap(URL(string: "http://83.170.113.110:8080"))
        XCTAssertEqual(WinampModernComponentBridge.displayAddress(of: bare), "http://83.170.113.110:8080")
    }
}
