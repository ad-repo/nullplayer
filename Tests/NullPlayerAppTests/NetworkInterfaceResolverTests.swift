import XCTest
@testable import NullPlayer

final class NetworkInterfaceResolverTests: XCTestCase {
    func testDiscoverLocalIPv4AddressReturnsNilOrDottedQuad() {
        guard let address = NetworkInterfaceResolver.discoverLocalIPv4Address() else {
            return
        }

        let octets = address.split(separator: ".", omittingEmptySubsequences: false)
        XCTAssertEqual(octets.count, 4)

        for octet in octets {
            guard let value = Int(octet), (0...255).contains(value) else {
                XCTFail("Expected dotted-quad IPv4 address, got \(address)")
                return
            }
        }
    }
}
