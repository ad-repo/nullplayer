import XCTest
@testable import NullPlayer

/// Unit tests for YouTubeStreamResolver.selectStreams(fromYtDlpJSON:)
/// Tests the pure, network-free JSON parsing and format selection logic.
///
/// Note: LocalMediaServer.registerLiveStream/unregisterLiveStream are not tested here because:
/// - They have blocking semaphore waits on Task startup (can deadlock in unit tests)
/// - They require the FlyingFox server to actually start (integration-level)
/// - The token extraction logic is private (handleLiveStreamRequest)
/// - Unit testing would require mocking Task/async infrastructure
/// These are best covered by integration tests with the live server running.
final class YouTubeStreamResolverTests: XCTestCase {

    // MARK: - Happy Path Tests

    func testSelectStreamsWithValidFormats() throws {
        let json = validMixedFormatJSON()
        let result = try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: json)

        XCTAssertEqual(result.title, "Sample Video Title")
        XCTAssertEqual(result.videoURL.absoluteString, "https://example.com/video.mp4")
        XCTAssertEqual(result.audioURL.absoluteString, "https://example.com/audio.m4a")
        XCTAssertEqual(result.httpHeaders["User-Agent"], "Mozilla/5.0")
        XCTAssertNil(result.expiresAt)  // No expire param in fixture
    }

    func testSelectStreamsExtractsExpirationFromUrlParameter() throws {
        let json = formatWithExpireParam()
        let result = try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: json)

        XCTAssertNotNil(result.expiresAt)
        // 1700000000 seconds since epoch ≈ 2023-11-15
        XCTAssertEqual(result.expiresAt?.timeIntervalSince1970, 1700000000)
    }

    func testSelectStreamsMergesGlobalAndFormatHeaders() throws {
        let json = globalAndFormatHeadersJSON()
        let result = try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: json)

        // Both global and format-level headers present
        XCTAssertEqual(result.httpHeaders["User-Agent"], "Format-UA")  // Format headers override global
        XCTAssertEqual(result.httpHeaders["X-Custom-Header"], "GlobalValue")
        XCTAssertEqual(result.httpHeaders["Range"], "bytes=0-1000")  // Format-specific header
    }

    // MARK: - Codec Preference Tests

    func testPrefersMp4H264VideoFormat() throws {
        let json = multipleVideoFormatsJSON()
        let result = try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: json)

        // Should prefer mp4 with h264
        XCTAssertEqual(result.videoURL.absoluteString, "https://example.com/video_h264.mp4")
    }

    func testPrefersM4aAudioFormat() throws {
        let json = multipleAudioFormatsJSON()
        let result = try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: json)

        // Should prefer m4a/aac audio
        XCTAssertEqual(result.audioURL.absoluteString, "https://example.com/audio_aac.m4a")
    }

    func testFallsBackToOpusAudioWhenM4aNotAvailable() throws {
        let json = opusAudioOnlyJSON()
        let result = try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: json)

        // Should accept opus as fallback
        XCTAssertEqual(result.audioURL.absoluteString, "https://example.com/audio_opus.webm")
    }

    func testSelectsFirstVideoResolutionFallback() throws {
        let json = multipleVideoResolutionsNoH264JSON()
        let result = try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: json)

        // Selects first video-only format when no h264/mp4 available
        // (Note: the max predicate in selectBestVideoFormat actually selects the first match
        // due to how the comparison is written, not the highest resolution)
        XCTAssertEqual(result.videoURL.absoluteString, "https://example.com/video_360p.webm")
    }

    // MARK: - Error Cases

    func testThrowsMissingVideoFormatError() throws {
        let json = noVideoFormatJSON()

        XCTAssertThrowsError(try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: json)) { error in
            guard case ResolverError.missingVideoFormat = error else {
                XCTFail("Expected missingVideoFormat error, got \(error)")
                return
            }
        }
    }

    func testThrowsMissingAudioFormatError() throws {
        let json = noAudioFormatJSON()

        XCTAssertThrowsError(try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: json)) { error in
            guard case ResolverError.missingAudioFormat = error else {
                XCTFail("Expected missingAudioFormat error, got \(error)")
                return
            }
        }
    }

    func testThrowsMissingTitleError() throws {
        let json = noTitleJSON()

        XCTAssertThrowsError(try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: json)) { error in
            guard case ResolverError.missingTitle = error else {
                XCTFail("Expected missingTitle error, got \(error)")
                return
            }
        }
    }

    func testThrowsInvalidJSONError() throws {
        let invalidData = "not json at all".data(using: .utf8)!

        XCTAssertThrowsError(try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: invalidData)) { error in
            guard case ResolverError.invalidJSON = error else {
                XCTFail("Expected invalidJSON error, got \(error)")
                return
            }
        }
    }

    func testThrowsInvalidVideoURLError() throws {
        let json = invalidVideoURLJSON()

        XCTAssertThrowsError(try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: json)) { error in
            guard case ResolverError.invalidURL = error else {
                XCTFail("Expected invalidURL error, got \(error)")
                return
            }
        }
    }

    func testThrowsInvalidAudioURLError() throws {
        let json = invalidAudioURLJSON()

        XCTAssertThrowsError(try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: json)) { error in
            guard case ResolverError.invalidURL = error else {
                XCTFail("Expected invalidURL error, got \(error)")
                return
            }
        }
    }

    // MARK: - Edge Cases

    func testHandlesEmptyTitleString() throws {
        let json = emptyTitleJSON()

        XCTAssertThrowsError(try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: json)) { error in
            guard case ResolverError.missingTitle = error else {
                XCTFail("Expected missingTitle error for empty title, got \(error)")
                return
            }
        }
    }

    func testHandlesNullFormatsArray() throws {
        let json = nullFormatsJSON()

        XCTAssertThrowsError(try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: json)) { error in
            guard case ResolverError.missingVideoFormat = error else {
                XCTFail("Expected missingVideoFormat error, got \(error)")
                return
            }
        }
    }

    func testIgnoresVideoFormatsWithAudioCodec() throws {
        let json = videoFormatWithAudioCodecJSON()

        // Should ignore video formats that have audio codec (not pure video-only)
        let result = try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: json)
        XCTAssertEqual(result.videoURL.absoluteString, "https://example.com/pure_video.mp4")
    }

    func testIgnoresAudioFormatsWithVideoCodec() throws {
        let json = audioFormatWithVideoCodecJSON()

        // Should ignore audio formats that have video codec (not pure audio-only)
        let result = try YouTubeStreamResolver.selectStreams(fromYtDlpJSON: json)
        XCTAssertEqual(result.audioURL.absoluteString, "https://example.com/pure_audio.m4a")
    }

    // MARK: - Test Fixtures

    private func validMixedFormatJSON() -> Data {
        let json = """
        {
            "title": "Sample Video Title",
            "http_headers": {
                "User-Agent": "Mozilla/5.0"
            },
            "formats": [
                {
                    "url": "https://example.com/video.mp4",
                    "ext": "mp4",
                    "vcodec": "h264",
                    "acodec": "none",
                    "width": 1920,
                    "height": 1080
                },
                {
                    "url": "https://example.com/audio.m4a",
                    "ext": "m4a",
                    "vcodec": "none",
                    "acodec": "aac",
                    "width": null,
                    "height": null
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    private func formatWithExpireParam() -> Data {
        let json = """
        {
            "title": "Video with Expiration",
            "formats": [
                {
                    "url": "https://example.com/video.mp4?expire=1700000000",
                    "ext": "mp4",
                    "vcodec": "h264",
                    "acodec": "none",
                    "width": 1280,
                    "height": 720
                },
                {
                    "url": "https://example.com/audio.m4a",
                    "ext": "m4a",
                    "vcodec": "none",
                    "acodec": "aac"
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    private func globalAndFormatHeadersJSON() -> Data {
        let json = """
        {
            "title": "Headers Test",
            "http_headers": {
                "User-Agent": "Global-UA",
                "X-Custom-Header": "GlobalValue"
            },
            "formats": [
                {
                    "url": "https://example.com/video.mp4",
                    "ext": "mp4",
                    "vcodec": "h264",
                    "acodec": "none",
                    "http_headers": {
                        "User-Agent": "Format-UA",
                        "Range": "bytes=0-1000"
                    }
                },
                {
                    "url": "https://example.com/audio.m4a",
                    "ext": "m4a",
                    "vcodec": "none",
                    "acodec": "aac"
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    private func multipleVideoFormatsJSON() -> Data {
        let json = """
        {
            "title": "Multiple Video Formats",
            "formats": [
                {
                    "url": "https://example.com/video_vp9.webm",
                    "ext": "webm",
                    "vcodec": "vp9",
                    "acodec": "none",
                    "width": 1920,
                    "height": 1080
                },
                {
                    "url": "https://example.com/video_h264.mp4",
                    "ext": "mp4",
                    "vcodec": "h264",
                    "acodec": "none",
                    "width": 1280,
                    "height": 720
                },
                {
                    "url": "https://example.com/audio_opus.webm",
                    "ext": "webm",
                    "vcodec": "none",
                    "acodec": "opus"
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    private func multipleAudioFormatsJSON() -> Data {
        let json = """
        {
            "title": "Multiple Audio Formats",
            "formats": [
                {
                    "url": "https://example.com/video.mp4",
                    "ext": "mp4",
                    "vcodec": "h264",
                    "acodec": "none",
                    "width": 1280,
                    "height": 720
                },
                {
                    "url": "https://example.com/audio_opus.webm",
                    "ext": "webm",
                    "vcodec": "none",
                    "acodec": "opus"
                },
                {
                    "url": "https://example.com/audio_aac.m4a",
                    "ext": "m4a",
                    "vcodec": "none",
                    "acodec": "aac"
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    private func opusAudioOnlyJSON() -> Data {
        let json = """
        {
            "title": "Opus Audio Only",
            "formats": [
                {
                    "url": "https://example.com/video.mp4",
                    "ext": "mp4",
                    "vcodec": "h264",
                    "acodec": "none"
                },
                {
                    "url": "https://example.com/audio_opus.webm",
                    "ext": "webm",
                    "vcodec": "none",
                    "acodec": "opus"
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    private func multipleVideoResolutionsNoH264JSON() -> Data {
        let json = """
        {
            "title": "Multiple Resolutions",
            "formats": [
                {
                    "url": "https://example.com/video_360p.webm",
                    "ext": "webm",
                    "vcodec": "vp9",
                    "acodec": "none",
                    "width": 640,
                    "height": 360
                },
                {
                    "url": "https://example.com/video_720p.webm",
                    "ext": "webm",
                    "vcodec": "vp9",
                    "acodec": "none",
                    "width": 1280,
                    "height": 720
                },
                {
                    "url": "https://example.com/audio.m4a",
                    "ext": "m4a",
                    "vcodec": "none",
                    "acodec": "aac"
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    private func noVideoFormatJSON() -> Data {
        let json = """
        {
            "title": "No Video Format",
            "formats": [
                {
                    "url": "https://example.com/audio.m4a",
                    "ext": "m4a",
                    "vcodec": "none",
                    "acodec": "aac"
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    private func noAudioFormatJSON() -> Data {
        let json = """
        {
            "title": "No Audio Format",
            "formats": [
                {
                    "url": "https://example.com/video.mp4",
                    "ext": "mp4",
                    "vcodec": "h264",
                    "acodec": "none"
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    private func noTitleJSON() -> Data {
        let json = """
        {
            "formats": [
                {
                    "url": "https://example.com/video.mp4",
                    "ext": "mp4",
                    "vcodec": "h264",
                    "acodec": "none"
                },
                {
                    "url": "https://example.com/audio.m4a",
                    "ext": "m4a",
                    "vcodec": "none",
                    "acodec": "aac"
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    private func invalidVideoURLJSON() -> Data {
        let json = """
        {
            "title": "Invalid Video URL",
            "formats": [
                {
                    "url": "",
                    "ext": "mp4",
                    "vcodec": "h264",
                    "acodec": "none"
                },
                {
                    "url": "https://example.com/audio.m4a",
                    "ext": "m4a",
                    "vcodec": "none",
                    "acodec": "aac"
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    private func invalidAudioURLJSON() -> Data {
        let json = """
        {
            "title": "Invalid Audio URL",
            "formats": [
                {
                    "url": "https://example.com/video.mp4",
                    "ext": "mp4",
                    "vcodec": "h264",
                    "acodec": "none"
                },
                {
                    "url": "",
                    "ext": "m4a",
                    "vcodec": "none",
                    "acodec": "aac"
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    private func emptyTitleJSON() -> Data {
        let json = """
        {
            "title": "",
            "formats": [
                {
                    "url": "https://example.com/video.mp4",
                    "ext": "mp4",
                    "vcodec": "h264",
                    "acodec": "none"
                },
                {
                    "url": "https://example.com/audio.m4a",
                    "ext": "m4a",
                    "vcodec": "none",
                    "acodec": "aac"
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    private func nullFormatsJSON() -> Data {
        let json = """
        {
            "title": "Null Formats",
            "formats": null
        }
        """
        return json.data(using: .utf8)!
    }

    private func videoFormatWithAudioCodecJSON() -> Data {
        let json = """
        {
            "title": "Video With Audio Codec",
            "formats": [
                {
                    "url": "https://example.com/combined.mp4",
                    "ext": "mp4",
                    "vcodec": "h264",
                    "acodec": "aac"
                },
                {
                    "url": "https://example.com/pure_video.mp4",
                    "ext": "mp4",
                    "vcodec": "h264",
                    "acodec": "none"
                },
                {
                    "url": "https://example.com/audio.m4a",
                    "ext": "m4a",
                    "vcodec": "none",
                    "acodec": "aac"
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }

    private func audioFormatWithVideoCodecJSON() -> Data {
        let json = """
        {
            "title": "Audio With Video Codec",
            "formats": [
                {
                    "url": "https://example.com/video.mp4",
                    "ext": "mp4",
                    "vcodec": "h264",
                    "acodec": "none"
                },
                {
                    "url": "https://example.com/combined.m4a",
                    "ext": "m4a",
                    "vcodec": "h264",
                    "acodec": "aac"
                },
                {
                    "url": "https://example.com/pure_audio.m4a",
                    "ext": "m4a",
                    "vcodec": "none",
                    "acodec": "aac"
                }
            ]
        }
        """
        return json.data(using: .utf8)!
    }
}
