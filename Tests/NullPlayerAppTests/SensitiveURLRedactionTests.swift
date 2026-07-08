import XCTest
@testable import NullPlayer

final class SensitiveURLRedactionTests: XCTestCase {
    func testURLRedactedHidesPlexTokenCaseInsensitively() throws {
        let url = try XCTUnwrap(URL(string: "https://plex.example/library/parts/1?x-plex-token=secret-token&download=1"))

        XCTAssertEqual(
            url.redacted,
            "https://plex.example/library/parts/1?x-plex-token=%3Credacted%3E&download=1"
        )
        XCTAssertFalse(url.redacted.contains("secret-token"))
    }

    func testURLRedactedHidesKnownTokenParameters() throws {
        let url = try XCTUnwrap(URL(string: "https://music.example/rest/stream.view?u=alice&t=token&s=salt&id=1"))

        let redacted = url.redacted
        XCTAssertFalse(redacted.contains("alice"))
        XCTAssertFalse(redacted.contains("token"))
        XCTAssertFalse(redacted.contains("salt"))
        XCTAssertTrue(redacted.contains("id=1"))
    }

    func testStringRedactionHidesEmbeddedPlexToken() {
        let message = "AudioPlayerError.network(https://plex.example/library/parts/1?X-Plex-Token=secret-token&download=1)"

        let redacted = message.redactingSensitiveURLQueryItems
        XCTAssertFalse(redacted.contains("secret-token"))
        XCTAssertTrue(redacted.contains("X-Plex-Token=<redacted>"))
        XCTAssertTrue(redacted.contains("download=1"))
    }
}
