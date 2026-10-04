import XCTest
@testable import NullPlayer

final class JellyfinAuthorizationHeaderTests: XCTestCase {
    func testTokenRidesInTheAuthorizationHeader() {
        XCTAssertEqual(
            JellyfinServerClient.authorization(deviceId: "dev-1", token: "abc"),
            #"MediaBrowser Client="NullPlayer", Device="Mac", DeviceId="dev-1", Version="1.0", Token="abc""#
        )
    }

    func testSignInCarriesNoToken() {
        XCTAssertEqual(
            JellyfinServerClient.authorization(deviceId: "dev-1"),
            #"MediaBrowser Client="NullPlayer", Device="Mac", DeviceId="dev-1", Version="1.0""#
        )
    }
}
