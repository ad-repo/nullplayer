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

    func testAllServiceCredentialsAndDuplicateQueryItems() throws {
        let keys = ["X-Plex-Token", "api_key", "ApiKey", "X-Emby-Token",
                    "u", "t", "s", "p", "password", "token", "access_token",
                    "auth_token", "auth", "signature", "sig"]
        for key in keys {
            let url = try XCTUnwrap(URL(string: "https://music.example/stream?\(key)=secret-one&\(key)=secret-two&id=42"))
            for value in [url.redacted, url.absoluteString.redactingSensitiveURLQueryItems] {
                XCTAssertFalse(value.contains("secret-one"), key)
                XCTAssertFalse(value.contains("secret-two"), key)
                XCTAssertTrue(value.contains("id=42"), key)
            }
            XCTAssertTrue(url.absoluteString.contains("secret-one"))
        }
    }

    func testRadioBasicAuthentication() throws {
        let url = try XCTUnwrap(URL(string: "https://alice:secret-password@radio.example/live?token=secret-token"))
        for value in [url.redacted, url.absoluteString.redactingSensitiveURLQueryItems] {
            XCTAssertFalse(value.contains("alice"))
            XCTAssertFalse(value.contains("secret-password"))
            XCTAssertFalse(value.contains("secret-token"))
            XCTAssertTrue(value.contains("@radio.example/live"))
        }
    }

    func testEscapedAndNestedURLs() throws {
        let messages = [
            "<res>https://music.example/stream?id=42&amp;api_key=secret-token</res>",
            #"{"url":"https:\/\/music.example\/stream?api_key=secret-token&id=42"}"#,
            "https://plex.example/photo?url=https%3A%2F%2Fmusic.example%2Fstream%3Fapi_key%3Dsecret-token",
            "https://music.example/stream?api_key=first%26secret-token&id=42"
        ]
        for message in messages {
            XCTAssertFalse(message.redactingSensitiveURLQueryItems.contains("secret-token"))
        }
        let encodedName = try XCTUnwrap(URL(string: "https://music.example/stream?%61pi_key=secret-token"))
        XCTAssertFalse(encodedName.redacted.contains("secret-token"))
        XCTAssertFalse("https://music.example/stream?%61pi_key=secret-token".redactingSensitiveURLQueryItems.contains("secret-token"))
        let nested = try XCTUnwrap(URL(string: messages[2]))
        XCTAssertFalse(nested.redacted.contains("secret-token"))
    }

    func testLocalCastingCapabilities() throws {
        for path in ["stream/0123456789ABCDEF", "media/0123456789ABCDEF.mp3", "artwork/0123456789ABCDEF"] {
            let url = try XCTUnwrap(URL(string: "http://192.0.2.1:8765/\(path)"))
            XCTAssertFalse(url.redacted.contains("0123456789ABCDEF"))
            XCTAssertFalse(url.absoluteString.redactingSensitiveURLQueryItems.contains("0123456789ABCDEF"))
            let escaped = url.absoluteString.replacingOccurrences(of: "/", with: #"\/"#)
            XCTAssertFalse(escaped.redactingSensitiveURLQueryItems.contains("0123456789ABCDEF"))
            XCTAssertTrue(url.redacted.contains("192.0.2.1:8765"))
        }
    }

    func testErrorCredentialFieldsAndHeaders() {
        let messages = [
            #"{"AccessToken":"secret-token","Name":"Music"}"#,
            #"{"password":"secret-token","id":42}"#,
            "Authorization: Emby Token=secret-token",
            "X-Emby-Token: secret-token",
            "X-Plex-Token: secret-token"
        ]
        for message in messages {
            XCTAssertFalse(message.redactingSensitiveURLQueryItems.contains("secret-token"))
        }
    }

    func testXMLAttributeCredentialsAndRetainedFaultDetail() {
        let leaking = [
            #"<Response code="1001" status="Invalid token" token="secret-token"/>"#,
            #"<user authToken="secret-token" email="user@example.test"/>"#,
            #"<Server accessToken="secret-token" name="Music"/>"#
        ]
        for message in leaking {
            XCTAssertFalse(message.redactingSensitiveURLQueryItems.contains("secret-token"), message)
        }

        // SOAP faults and benign attributes are the diagnostics we log for; keep them.
        let fault = "<UPnPError><errorCode>701</errorCode><errorDescription>Transition not available</errorDescription></UPnPError>"
        XCTAssertEqual(fault.redactingSensitiveURLQueryItems, fault)
        let track = #"<Track title="Song" id="42" duration="180000"/>"#
        XCTAssertEqual(track.redactingSensitiveURLQueryItems, track)
    }

    func testNonSensitiveDiagnosticsRemainReadable() throws {
        let url = try XCTUnwrap(URL(string: "https://music.example/Audio/42/stream?static=true&id=42"))
        XCTAssertEqual(url.redacted, url.absoluteString)
        let message = "HTTP 503 for https://music.example/Audio/42/stream?id=42"
        XCTAssertEqual(message.redactingSensitiveURLQueryItems, message)
        let emailQuery = "https://host.example?email=user@example.test"
        XCTAssertEqual(emailQuery.redactingSensitiveURLQueryItems, emailQuery)
        let file = URL(fileURLWithPath: "/tmp/My Music/song.flac")
        XCTAssertEqual(file.redacted, file.absoluteString)
    }
}
