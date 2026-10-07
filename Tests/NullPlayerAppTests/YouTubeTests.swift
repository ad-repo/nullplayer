import XCTest
@testable import NullPlayer

final class YouTubeTests: XCTestCase {
    // MARK: - Channel URL Normalization Tests

    func testNormalizeChannelURLWithHandleOnly() {
        let url = URL(string: "https://www.youtube.com/@NASA")!

        let result = YouTubeManager.normalizeChannelURL(url)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.key, "NASA")
        XCTAssertEqual(result?.listURL.absoluteString, "https://www.youtube.com/@NASA/videos")
    }

    func testNormalizeChannelURLWithFullHandleURL() {
        let url = URL(string: "https://www.youtube.com/@NASA/videos")!

        let result = YouTubeManager.normalizeChannelURL(url)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.key, "NASA")
        XCTAssertEqual(result?.listURL.absoluteString, "https://www.youtube.com/@NASA/videos")
    }

    func testNormalizeChannelURLWithChannelID() {
        let url = URL(string: "https://www.youtube.com/channel/UC_x5XG1OV2P6uZZ5FSM9Ttw")!

        let result = YouTubeManager.normalizeChannelURL(url)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.key, "UC_x5XG1OV2P6uZZ5FSM9Ttw")
        XCTAssertEqual(result?.listURL.absoluteString, "https://www.youtube.com/channel/UC_x5XG1OV2P6uZZ5FSM9Ttw/videos")
    }

    func testNormalizeChannelURLWithCPath() {
        let url = URL(string: "https://www.youtube.com/c/SomeName")!

        let result = YouTubeManager.normalizeChannelURL(url)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.key, "SomeName")
        XCTAssertEqual(result?.listURL.absoluteString, "https://www.youtube.com/c/SomeName/videos")
    }

    func testNormalizeChannelURLWithUserPath() {
        let url = URL(string: "https://www.youtube.com/user/SomeName")!

        let result = YouTubeManager.normalizeChannelURL(url)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.key, "SomeName")
        XCTAssertEqual(result?.listURL.absoluteString, "https://www.youtube.com/user/SomeName/videos")
    }

    func testNormalizeChannelURLWithQueryParameters() {
        let url = URL(string: "https://www.youtube.com/@NASA/videos?sort=newest")!

        let result = YouTubeManager.normalizeChannelURL(url)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.key, "NASA")
        XCTAssertEqual(result?.listURL.absoluteString, "https://www.youtube.com/@NASA/videos")
    }

    func testNormalizeChannelURLInvalidHostReturnNil() {
        let url = URL(string: "https://www.example.com/@NASA")!

        let result = YouTubeManager.normalizeChannelURL(url)

        XCTAssertNil(result)
    }

    func testNormalizeChannelURLRejectsLookalikeYouTubeHost() {
        let url = URL(string: "https://evilyoutube.com/@NASA")!

        XCTAssertNil(YouTubeManager.normalizeChannelURL(url))
    }

    func testNormalizeChannelURLAcceptsYouTubeSubdomain() {
        let url = URL(string: "https://m.youtube.com/@NASA")!

        XCTAssertEqual(
            YouTubeManager.normalizeChannelURL(url)?.listURL.absoluteString,
            "https://www.youtube.com/@NASA/videos"
        )
    }

    func testNormalizeChannelURLInvalidPathReturnNil() {
        let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!

        let result = YouTubeManager.normalizeChannelURL(url)

        XCTAssertNil(result)
    }

    func testNormalizeChannelURLEmptyPathReturnNil() {
        let url = URL(string: "https://www.youtube.com/")!

        let result = YouTubeManager.normalizeChannelURL(url)

        XCTAssertNil(result)
    }

    func testNormalizeChannelURLWithInvalidComponents() {
        // URL with fragment that is still valid
        let url = URL(string: "https://www.youtube.com/@NASA#videos")!

        let result = YouTubeManager.normalizeChannelURL(url)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.key, "NASA")
    }

    func testNormalizeChannelURLIdempotency() {
        // Verify that normalizing the same channel via different formats returns the same key
        let handleURL = URL(string: "https://www.youtube.com/@NASA")!
        let handleWithVideosURL = URL(string: "https://www.youtube.com/@NASA/videos")!

        let result1 = YouTubeManager.normalizeChannelURL(handleURL)
        let result2 = YouTubeManager.normalizeChannelURL(handleWithVideosURL)

        XCTAssertEqual(result1?.key, result2?.key)
        XCTAssertEqual(result1?.key, "NASA")
    }

    // MARK: - Flat Playlist Parsing Tests

    func testParseFlatPlaylistWithValidJSON() throws {
        let json = """
        {
            "entries": [
                {
                    "id": "dQw4w9WgXcQ",
                    "title": "Never Gonna Give You Up",
                    "duration": 212,
                    "timestamp": 1256428800
                },
                {
                    "id": "9bZkp7q19f0",
                    "title": "Rick Astley - Together Forever",
                    "duration": 240,
                    "timestamp": 562809600
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!

        let videos = try YouTubeManager.parseFlatPlaylist(data, channelId: "test-channel")

        XCTAssertEqual(videos.count, 2)
        XCTAssertEqual(videos[0].videoId, "dQw4w9WgXcQ")
        XCTAssertEqual(videos[0].title, "Never Gonna Give You Up")
        XCTAssertEqual(videos[0].channelId, "test-channel")
        XCTAssertEqual(videos[0].duration, 212)
        XCTAssertEqual(videos[0].publishedAt, Date(timeIntervalSince1970: 1256428800))
        XCTAssertEqual(videos[0].watchURL, URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))

        XCTAssertEqual(videos[1].videoId, "9bZkp7q19f0")
        XCTAssertEqual(videos[1].title, "Rick Astley - Together Forever")
        XCTAssertEqual(videos[1].duration, 240)
    }

    func testParseFlatPlaylistWithNullDuration() throws {
        let json = """
        {
            "entries": [
                {
                    "id": "video123",
                    "title": "Test Video",
                    "duration": null,
                    "upload_date": "2024-01-01"
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!

        let videos = try YouTubeManager.parseFlatPlaylist(data, channelId: "channel-1")

        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(videos[0].videoId, "video123")
        XCTAssertNil(videos[0].duration)
    }

    func testParseFlatPlaylistWithMissingDuration() throws {
        let json = """
        {
            "entries": [
                {
                    "id": "video456",
                    "title": "Another Test",
                    "upload_date": "2024-02-15"
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!

        let videos = try YouTubeManager.parseFlatPlaylist(data, channelId: "channel-2")

        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(videos[0].videoId, "video456")
        XCTAssertNil(videos[0].duration)
    }

    func testParseFlatPlaylistWithMissingOptionalFields() throws {
        let json = """
        {
            "entries": [
                {
                    "id": "minimalvideo",
                    "title": "Minimal Entry"
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!

        let videos = try YouTubeManager.parseFlatPlaylist(data, channelId: "channel-3")

        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(videos[0].videoId, "minimalvideo")
        XCTAssertEqual(videos[0].title, "Minimal Entry")
        XCTAssertNil(videos[0].duration)
        XCTAssertNil(videos[0].publishedAt)
    }

    func testParseFlatPlaylistFiltersOutEntriesWithoutID() throws {
        let json = """
        {
            "entries": [
                {
                    "id": "validid",
                    "title": "Valid Entry"
                },
                {
                    "title": "No ID Entry",
                    "duration": 100
                },
                {
                    "id": "anotherid",
                    "title": "Another Valid"
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!

        let videos = try YouTubeManager.parseFlatPlaylist(data, channelId: "channel-4")

        XCTAssertEqual(videos.count, 2)
        XCTAssertEqual(videos[0].videoId, "validid")
        XCTAssertEqual(videos[1].videoId, "anotherid")
    }

    func testParseFlatPlaylistWithEmptyEntries() throws {
        let json = """
        {
            "entries": []
        }
        """
        let data = json.data(using: .utf8)!

        let videos = try YouTubeManager.parseFlatPlaylist(data, channelId: "empty-channel")

        XCTAssertEqual(videos.count, 0)
    }

    func testParseFlatPlaylistWithoutEntriesKey() throws {
        let json = """
        {
            "channel": "Test Channel"
        }
        """
        let data = json.data(using: .utf8)!

        let videos = try YouTubeManager.parseFlatPlaylist(data, channelId: "no-entries")

        XCTAssertEqual(videos.count, 0)
    }

    func testParseFlatPlaylistWithMalformedJSON() throws {
        let json = """
        {
            "entries": [
                "this is not valid structure"
            ]
        }
        """
        let data = json.data(using: .utf8)!

        XCTAssertThrowsError(try YouTubeManager.parseFlatPlaylist(data, channelId: "bad-json"))
    }

    func testParseFlatPlaylistWithInvalidJSON() throws {
        let data = "{ invalid json }".data(using: .utf8)!

        XCTAssertThrowsError(try YouTubeManager.parseFlatPlaylist(data, channelId: "invalid"))
    }

    // MARK: - Format Tests

    func testYouTubeAudioFormatArgs() {
        XCTAssertEqual(YouTubeAudioFormat.flac.ytdlpArgs, ["--audio-format", "flac"])
        // yt-dlp's own `alac` mapping writes AAC, so the codec is passed to ffmpeg directly.
        XCTAssertEqual(YouTubeAudioFormat.alac.ytdlpArgs,
                       ["--audio-format", "alac", "--ppa", "ExtractAudio+ffmpeg_o:-c:a alac"])
        XCTAssertEqual(YouTubeAudioFormat.mp3(kbps: 192).ytdlpArgs, ["--audio-format", "mp3", "--audio-quality", "192K"])
        XCTAssertEqual(YouTubeAudioFormat.aac(kbps: 256).ytdlpArgs, ["--audio-format", "m4a", "--audio-quality", "256K"])
        XCTAssertEqual(YouTubeAudioFormat.originalAAC.ytdlpArgs, ["--audio-format", "m4a"])
        XCTAssertEqual(YouTubeAudioFormat.originalOpus.ytdlpArgs, ["--audio-format", "opus"])
    }

    func testYouTubeAudioFormatSelectors() {
        for format in [YouTubeAudioFormat.flac, .alac, .mp3(kbps: 320)] {
            XCTAssertEqual(format.formatSelector, "bestaudio/best")
        }
        // Re-encoded AAC starts from the Opus stream; an AAC source would be copied as is.
        XCTAssertEqual(YouTubeAudioFormat.aac(kbps: 256).formatSelector, "bestaudio[acodec=opus]/bestaudio")
        XCTAssertEqual(YouTubeAudioFormat.originalAAC.formatSelector, "bestaudio[ext=m4a]/bestaudio")
        XCTAssertEqual(YouTubeAudioFormat.originalOpus.formatSelector, "bestaudio[acodec=opus]/bestaudio")
    }

    func testYouTubeAudioFormatMenuAndNames() {
        XCTAssertEqual(YouTubeAudioFormat.sections.map(\.count), [2, 4, 3, 2])
        XCTAssertEqual(YouTubeAudioFormat.mp3(kbps: 320).displayName, "MP3 320 kbps")
        XCTAssertEqual(YouTubeAudioFormat.aac(kbps: 128).displayName, "AAC 128 kbps")
        XCTAssertEqual(YouTubeAudioFormat.originalOpus.displayName, "Original Opus (no re-encode)")
    }

    func testYouTubeAudioFormatSavedValues() {
        let choices = Array(YouTubeAudioFormat.sections.joined())
        XCTAssertEqual(Set(choices.map(\.rawValue)).count, choices.count)
        for choice in choices {
            XCTAssertEqual(YouTubeAudioFormat(savedValue: choice.rawValue), choice)
        }
        // Values of the old `YouTubeQuality` setting
        XCTAssertEqual(YouTubeAudioFormat(savedValue: "flac"), .flac)
        XCTAssertEqual(YouTubeAudioFormat(savedValue: "mp3High"), .mp3(kbps: 320))
        XCTAssertEqual(YouTubeAudioFormat(savedValue: "mp3Low"), .mp3(kbps: 128))
        // A bitrate that isn't offered, and a video value, are not audio formats
        XCTAssertNil(YouTubeAudioFormat(savedValue: "mp3-999"))
        XCTAssertNil(YouTubeAudioFormat(savedValue: "video720"))
    }

    func testYouTubeVideoQuality() {
        XCTAssertEqual(YouTubeVideoQuality.sections.map(\.count), [6, 1])
        XCTAssertEqual(YouTubeVideoQuality.height(720).maxHeight, 720)
        XCTAssertNil(YouTubeVideoQuality.best.maxHeight)
        XCTAssertEqual(YouTubeVideoQuality.height(480).displayName, "480p")
        XCTAssertEqual(YouTubeVideoQuality.height(2160).displayName, "2160p (4K)")
        XCTAssertEqual(YouTubeVideoQuality.best.displayName, "Best Available")
        for choice in YouTubeVideoQuality.sections.joined() {
            XCTAssertEqual(YouTubeVideoQuality(savedValue: choice.rawValue), choice)
        }
        XCTAssertEqual(YouTubeVideoQuality(savedValue: "video720"), .height(720))
        XCTAssertEqual(YouTubeVideoQuality(savedValue: "video1080"), .height(1080))
        XCTAssertNil(YouTubeVideoQuality(savedValue: "flac"))
    }

    func testResolveFormatsMigratesTheOldQualitySetting() {
        func resolve(_ audio: String?, _ video: String?, legacy: String?) -> (YouTubeAudioFormat, YouTubeVideoQuality) {
            let formats = YouTubeManager.resolveFormats(audioFormat: audio, videoQuality: video, legacyQuality: legacy)
            return (formats.audioFormat, formats.videoQuality)
        }
        // Nothing saved: FLAC and 1080p
        XCTAssert(resolve(nil, nil, legacy: nil) == (.flac, .height(1080)))
        // An old audio value carries over; the video setting takes its default, and vice versa
        XCTAssert(resolve(nil, nil, legacy: "mp3High") == (.mp3(kbps: 320), .height(1080)))
        XCTAssert(resolve(nil, nil, legacy: "video720") == (.flac, .height(720)))
        // The new settings win over the old one
        XCTAssert(resolve("aac-192", "best", legacy: "mp3Low") == (.aac(kbps: 192), .best))
        // An unreadable value falls back to the default
        XCTAssert(resolve("bogus", "bogus", legacy: nil) == (.flac, .height(1080)))
    }

    // MARK: - YouTubeVideo Computed Properties Tests

    func testYouTubeVideoIdentifiable() {
        let video = YouTubeVideo(
            videoId: "test123",
            title: "Test Video",
            channelId: "channel123",
            duration: 180,
            publishedAt: Date(timeIntervalSince1970: 1704067200)
        )

        XCTAssertEqual(video.id, "test123")
    }

    func testYouTubeVideoWatchURL() {
        let video = YouTubeVideo(
            videoId: "dQw4w9WgXcQ",
            title: "Test",
            channelId: "channel123",
            duration: nil,
            publishedAt: nil
        )

        XCTAssertEqual(video.watchURL, URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
    }

    func testYouTubeVideoFormattedDurationDoesNotRoundMinutes() {
        let video = YouTubeVideo(
            videoId: "duration",
            title: "Duration",
            channelId: "channel",
            duration: 119,
            publishedAt: nil
        )

        XCTAssertEqual(video.formattedDuration, "1:59")
    }

    // MARK: - Edge Cases and Integration

    func testNormalizeChannelURLWithHandleContainingNumbers() {
        let url = URL(string: "https://www.youtube.com/@NASA2024")!

        let result = YouTubeManager.normalizeChannelURL(url)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.key, "NASA2024")
    }

    func testParseFlatPlaylistWithLargeDuration() throws {
        let json = """
        {
            "entries": [
                {
                    "id": "longlive",
                    "title": "Long Stream",
                    "duration": 86400,
                    "upload_date": "2024-01-01"
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!

        let videos = try YouTubeManager.parseFlatPlaylist(data, channelId: "stream-channel")

        XCTAssertEqual(videos[0].duration, 86400)
    }

    func testParseFlatPlaylistChannelIdPropagation() throws {
        let json = """
        {
            "entries": [
                {"id": "v1", "title": "V1"},
                {"id": "v2", "title": "V2"},
                {"id": "v3", "title": "V3"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let testChannelId = "specific-channel-xyz"

        let videos = try YouTubeManager.parseFlatPlaylist(data, channelId: testChannelId)

        XCTAssertTrue(videos.allSatisfy { $0.channelId == testChannelId })
    }

    // MARK: - Channel Search Tests

    /// Shape of a live `yt-dlp --flat-playlist -J` channels-only search: a handle-keyed entry,
    /// a Topic channel with a null `uploader_id`, a protocol-relative avatar, and an entry
    /// with no channel ID (dropped).
    private let channelSearchJSON = """
    {
        "entries": [
            {
                "ie_key": "YoutubeTab", "id": "UCSJ4gkVC6NrvII8umztf0Ow",
                "channel_id": "UCSJ4gkVC6NrvII8umztf0Ow", "title": "Lofi Girl",
                "uploader_id": "@LofiGirl", "channel_follower_count": 15800000,
                "url": "https://www.youtube.com/channel/UCSJ4gkVC6NrvII8umztf0Ow",
                "thumbnails": [
                    {"url": "https://yt3.ggpht.com/abc=s88-c-k-c0x00ffffff-no-rj-mo", "width": 88, "height": 88},
                    {"url": "https://yt3.ggpht.com/abc=s176-c-k-c0x00ffffff-no-rj-mo", "width": 176, "height": 176}
                ]
            },
            {
                "ie_key": "YoutubeTab", "id": "UCi5YpRRZmwegT235crEZ2YQ",
                "channel_id": "UCi5YpRRZmwegT235crEZ2YQ", "title": "Lofi Girl - Topic",
                "uploader_id": null, "channel_follower_count": 36500,
                "thumbnails": [
                    {"url": "//yt3.ggpht.com/def=s176-c-k-c0x00ffffff-no-rj-mo", "width": 176, "height": 176}
                ]
            },
            {"ie_key": "YoutubeTab", "title": "No ID"}
        ]
    }
    """

    func testParseChannelSearch() throws {
        let results = try YouTubeManager.parseChannelSearch(Data(channelSearchJSON.utf8))

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].channelId, "UCSJ4gkVC6NrvII8umztf0Ow")
        XCTAssertEqual(results[0].handle, "@LofiGirl")
        XCTAssertEqual(results[0].channel.title, "Lofi Girl")
        XCTAssertEqual(results[0].infoText, "@LofiGirl · 15.8M")
        // Largest square avatar, stored as listed and sized at use
        XCTAssertEqual(results[0].channel.avatarURL?.absoluteString, "https://yt3.ggpht.com/abc=s176-c-k-c0x00ffffff-no-rj-mo")
        XCTAssertEqual(results[0].channel.avatarURL(side: 512)?.absoluteString,
                       "https://yt3.ggpht.com/abc=s512-c-k-c0x00ffffff-no-rj-mo")

        XCTAssertNil(results[1].handle)
        XCTAssertEqual(results[1].infoText, "36.5K")
        // Protocol-relative avatar gets https:
        XCTAssertEqual(results[1].channel.avatarURL?.absoluteString, "https://yt3.ggpht.com/def=s176-c-k-c0x00ffffff-no-rj-mo")
    }

    func testChannelSearchResultChannelMatchesPastedURLKey() throws {
        let results = try YouTubeManager.parseChannelSearch(Data(channelSearchJSON.utf8))

        // With a handle: keyed and addressed exactly like a pasted @handle URL
        let pasted = YouTubeManager.normalizeChannelURL(URL(string: "https://www.youtube.com/@LofiGirl")!)
        XCTAssertEqual(results[0].channel.id, pasted?.key)
        XCTAssertEqual(results[0].channel.url.absoluteString, "https://www.youtube.com/@LofiGirl")

        // Without a handle: the /channel/UC… form
        XCTAssertEqual(results[1].channel.id, "UCi5YpRRZmwegT235crEZ2YQ")
        XCTAssertEqual(results[1].channel.url.absoluteString,
                       "https://www.youtube.com/channel/UCi5YpRRZmwegT235crEZ2YQ")
    }

    func testSubscriptionMatchingHandleKeyedSubscription() throws {
        let result = try XCTUnwrap(YouTubeManager.parseChannelSearch(Data(channelSearchJSON.utf8)).first)
        let byHandle = YouTubeChannel(id: "lofigirl", title: "Lofi Girl",
                                      url: URL(string: "https://www.youtube.com/@lofigirl")!, dateAdded: Date())

        // Handles are case-insensitive on YouTube; the subscription's own key comes back
        XCTAssertEqual(YouTubeManager.subscription(matching: result, in: [byHandle])?.id, "lofigirl")
        XCTAssertNil(YouTubeManager.subscription(matching: result, in: []))
    }

    func testSubscriptionMatchingChannelIDKeyedSubscription() throws {
        let result = try XCTUnwrap(YouTubeManager.parseChannelSearch(Data(channelSearchJSON.utf8)).first)
        // Added earlier by a /channel/UC… URL, so keyed by the UC ID, not the handle
        let byChannelID = YouTubeChannel(id: "UCSJ4gkVC6NrvII8umztf0Ow", title: "Lofi Girl",
                                         url: URL(string: "https://www.youtube.com/channel/UCSJ4gkVC6NrvII8umztf0Ow")!,
                                         dateAdded: Date())
        let other = YouTubeChannel(id: "SomeoneElse", title: "Other",
                                   url: URL(string: "https://www.youtube.com/@SomeoneElse")!, dateAdded: Date())

        XCTAssertEqual(YouTubeManager.subscription(matching: result, in: [byChannelID])?.id, "UCSJ4gkVC6NrvII8umztf0Ow")
        XCTAssertNil(YouTubeManager.subscription(matching: result, in: [other]))
    }

    func testChannelSearchURLEncodesQueryAndChannelFilter() {
        let url = YouTubeManager.channelSearchURL(query: "lofi girl & c++ #1")
        XCTAssertEqual(url?.absoluteString,
                       "https://www.youtube.com/results?search_query=lofi%20girl%20%26%20c%2B%2B%20%231&sp=EgIQAg%3D%3D")
    }

    func testChannelSavedBeforeAvatarsStillDecodes() throws {
        let saved = #"[{"id":"LofiGirl","title":"Lofi Girl","url":"https://www.youtube.com/@LofiGirl","dateAdded":0}]"#
        let channels = try JSONDecoder().decode([YouTubeChannel].self, from: Data(saved.utf8))
        XCTAssertEqual(channels.count, 1)
        XCTAssertNil(channels[0].avatarURL)
    }

    func testParseFlatPlaylistCapturesThumbnailAndChannelAvatar() throws {
        let json = """
        {
            "channel": "Lofi Girl",
            "thumbnails": [
                {"id": "0", "url": "https://yt3.googleusercontent.com/banner=w1060", "width": 1060, "height": 175},
                {"id": "7", "url": "https://yt3.googleusercontent.com/av=s900-c-k-c0x00ffffff-no-rj", "width": 900, "height": 900},
                {"id": "avatar_uncropped", "url": "https://yt3.googleusercontent.com/av=s0"}
            ],
            "entries": [
                {"id": "v1", "title": "With thumbs", "thumbnails": [
                    {"url": "https://i.ytimg.com/vi/v1/hq720.jpg?a", "width": 360, "height": 202},
                    {"url": "https://i.ytimg.com/vi/v1/hq720.jpg?b", "width": 720, "height": 404}
                ]},
                {"id": "v2", "title": "No thumbs"}
            ]
        }
        """
        let data = Data(json.utf8)

        let videos = try YouTubeManager.parseFlatPlaylist(data, channelId: "c")
        XCTAssertEqual(videos[0].thumbnailURL?.absoluteString, "https://i.ytimg.com/vi/v1/hq720.jpg?b")
        XCTAssertEqual(videos[1].thumbnailURL?.absoluteString, "https://i.ytimg.com/vi/v2/mqdefault.jpg")

        // The square 900px avatar, not the banner or the full-size original
        let info = try YouTubeManager.parseChannelInfo(data)
        XCTAssertEqual(info.title, "Lofi Girl")
        XCTAssertEqual(info.avatarURL?.absoluteString, "https://yt3.googleusercontent.com/av=s900-c-k-c0x00ffffff-no-rj")
    }

    // MARK: - Download Manifest Tests

    func testChangingDownloadRootReloadsThatFoldersManifest() throws {
        let manager = YouTubeManager.shared
        let originalRoot = manager.downloadRoot
        let rootA = FileManager.default.temporaryDirectory
            .appendingPathComponent("nullplayer-youtube-test-a-\(UUID().uuidString)", isDirectory: true)
        let rootB = FileManager.default.temporaryDirectory
            .appendingPathComponent("nullplayer-youtube-test-b-\(UUID().uuidString)", isDirectory: true)
        defer {
            manager.downloadRoot = originalRoot
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        try writeManifest(
            root: rootA,
            download: YouTubeDownload(videoId: "video-a", title: "A", channelId: "channel", fileName: "A.flac", kind: .audio)
        )
        try writeManifest(
            root: rootB,
            download: YouTubeDownload(videoId: "video-b", title: "B", channelId: "channel", fileName: "B.flac", kind: .audio)
        )

        manager.downloadRoot = rootA
        XCTAssertNotNil(manager.downloadedFiles(for: "video-a")[.audio])
        XCTAssertNil(manager.downloadedFiles(for: "video-b")[.audio])

        manager.downloadRoot = rootB
        XCTAssertNil(manager.downloadedFiles(for: "video-a")[.audio])
        XCTAssertNotNil(manager.downloadedFiles(for: "video-b")[.audio])
    }

    func testManifestEntryCannotEscapeDownloadRoot() throws {
        let manager = YouTubeManager.shared
        let originalRoot = manager.downloadRoot
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("nullplayer-youtube-test-parent-\(UUID().uuidString)", isDirectory: true)
        let root = parent.appendingPathComponent("downloads", isDirectory: true)
        let outsideFile = parent.appendingPathComponent("outside.flac")
        defer {
            manager.downloadRoot = originalRoot
            try? FileManager.default.removeItem(at: parent)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: outsideFile)
        let download = YouTubeDownload(
            videoId: "outside",
            title: "Outside",
            channelId: "channel",
            fileName: "../outside.flac",
            kind: .audio
        )
        let manifest = try JSONEncoder().encode(["outside": download])
        try manifest.write(to: root.appendingPathComponent("youtube_downloads.json"))

        manager.downloadRoot = root
        XCTAssertNil(manager.downloadedFiles(for: "outside")[.audio])
        manager.removeDownload(YouTubeDownload.Key(videoId: "outside", kind: .audio))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideFile.path))
    }

    func testAudioAndVideoDownloadsOfOneVideoCoexist() throws {
        let manager = YouTubeManager.shared
        let originalRoot = manager.downloadRoot
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nullplayer-youtube-test-kinds-\(UUID().uuidString)", isDirectory: true)
        let otherRoot = root.appendingPathComponent("other", isDirectory: true)
        defer {
            manager.downloadRoot = originalRoot
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        for name in ["V.mp3", "V.mp4"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        try writeManifestEntries(root: root, [
            "v.audio": ["videoId": "v", "title": "V", "channelId": "c", "fileName": "V.mp3", "kind": "audio"],
            "v.video": ["videoId": "v", "title": "V", "channelId": "c", "fileName": "V.mp4", "kind": "video"],
        ])

        manager.downloadRoot = root
        XCTAssertEqual(Set(manager.downloadedFiles(for: "v").keys), [.audio, .video])
        // Cover art comes from the audio file while there is one, then from the video
        XCTAssertEqual(manager.coverArtFile(for: "v")?.lastPathComponent, "V.mp3")

        manager.removeDownload(YouTubeDownload.Key(videoId: "v", kind: .audio))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("V.mp3").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("V.mp4").path))
        XCTAssertEqual(manager.coverArtFile(for: "v")?.lastPathComponent, "V.mp4")

        // The saved manifest keeps the video, keyed by video ID and kind
        manager.downloadRoot = otherRoot
        manager.downloadRoot = root
        XCTAssertEqual(Array(manager.downloadedFiles(for: "v").keys), [.video])
        let saved = try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("youtube_downloads.json"))) as? [String: Any]
        XCTAssertEqual(saved.map { Array($0.keys) }, ["v.video"])
    }

    func testManifestEntryWithoutKindInfersItFromTheFileExtension() throws {
        let manager = YouTubeManager.shared
        let originalRoot = manager.downloadRoot
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nullplayer-youtube-test-legacy-\(UUID().uuidString)", isDirectory: true)
        defer {
            manager.downloadRoot = originalRoot
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["A.flac", "B.mp4"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        // Written before `kind` existed: keyed by the bare video ID
        try writeManifestEntries(root: root, [
            "a": ["videoId": "a", "title": "A", "channelId": "c", "fileName": "A.flac"],
            "b": ["videoId": "b", "title": "B", "channelId": "c", "fileName": "B.mp4"],
        ])

        manager.downloadRoot = root
        XCTAssertEqual(Array(manager.downloadedFiles(for: "a").keys), [.audio])
        XCTAssertEqual(Array(manager.downloadedFiles(for: "b").keys), [.video])
    }

    func testLocalSearchListsDownloadsNotAlreadyListedAsTracks() throws {
        let manager = YouTubeManager.shared
        let originalRoot = manager.downloadRoot
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nullplayer-youtube-test-search-\(UUID().uuidString)", isDirectory: true)
        defer {
            manager.downloadRoot = originalRoot
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["Both.mp3", "Both.mp4", "Indexed.flac", "Partly.mp3", "Partly.opus", "Other.mp3"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        try writeManifestEntries(root: root, [
            "both.audio": ["videoId": "both", "title": "Café Session", "channelId": "c", "fileName": "Both.mp3", "kind": "audio"],
            "both.video": ["videoId": "both", "title": "Café Session (Video)", "channelId": "c", "fileName": "Both.mp4", "kind": "video"],
            "indexed.audio": ["videoId": "indexed", "title": "Indexed Session", "channelId": "c", "fileName": "Indexed.flac", "kind": "audio"],
            "partly.audio": ["videoId": "partly", "title": "A Partly Indexed Session", "channelId": "c", "fileName": "Partly.mp3", "kind": "audio"],
            "partly.video": ["videoId": "partly", "title": "A Partly Indexed Session", "channelId": "c", "fileName": "Partly.opus", "kind": "video"],
            "gone.audio": ["videoId": "gone", "title": "Gone Session", "channelId": "c", "fileName": "Gone.mp3", "kind": "audio"],
            "other.audio": ["videoId": "other", "title": "Something Else", "channelId": "c", "fileName": "Other.mp3", "kind": "audio"],
        ])
        manager.downloadRoot = root
        // The library lists these as tracks, unstandardized as a scan may report them
        let tracks: Set<URL> = [
            URL(fileURLWithPath: root.path + "/./Indexed.flac"),
            root.appendingPathComponent("Partly.mp3"),
        ]

        // Case- and accent-insensitive; one row per video, A–Z. Dropped: "indexed" (every file is
        // a track), "gone" (nothing on disk), "other" (no match)
        let result = manager.localSearch(query: " cafe session ", excluding: tracks)
        XCTAssertEqual(result.videos.map(\.videoId), ["both"])
        // Entries of one video that disagree on its title: the audio entry's wins, every time
        XCTAssertEqual(result.videos.first?.title, "Café Session")
        let all = manager.localSearch(query: "session", excluding: tracks)
        XCTAssertEqual(all.videos.map(\.videoId), ["partly", "both"])
        XCTAssertEqual(all.videos.first?.title, "A Partly Indexed Session")

        XCTAssertTrue(manager.localSearch(query: "  ", excluding: []).videos.isEmpty)
    }

    func testRowsShowUploadsOnceExpandedAndMarkEachFormOnDisk() throws {
        let manager = YouTubeManager.shared
        let originalRoot = manager.downloadRoot
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nullplayer-youtube-test-rows-\(UUID().uuidString)", isDirectory: true)
        defer {
            manager.downloadRoot = originalRoot
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["Up.mp3", "Film.mp4", "Both.mp3", "Both.mp4"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        try writeManifestEntries(root: root, [
            "up.audio": ["videoId": "up", "title": "Up", "channelId": "ch", "fileName": "Up.mp3", "kind": "audio"],
            "film.video": ["videoId": "film", "title": "Film", "channelId": "ch", "fileName": "Film.mp4", "kind": "video"],
            "both.audio": ["videoId": "both", "title": "Both", "channelId": "ch", "fileName": "Both.mp3", "kind": "audio"],
            "both.video": ["videoId": "both", "title": "Both", "channelId": "ch", "fileName": "Both.mp4", "kind": "video"],
        ])
        manager.downloadRoot = root
        let channel = YouTubeChannel(id: "ch", title: "Chan", url: URL(string: "https://www.youtube.com/@ch")!, dateAdded: Date())
        let uploads = ["ch": [
            YouTubeVideo(videoId: "up", title: "Up", channelId: "ch", duration: 75, publishedAt: nil),
            YouTubeVideo(videoId: "film", title: "Film", channelId: "ch", duration: nil, publishedAt: nil),
            YouTubeVideo(videoId: "both", title: "Both", channelId: "ch", duration: nil, publishedAt: nil),
            YouTubeVideo(videoId: "new", title: "New", channelId: "ch", duration: nil, publishedAt: nil),
        ]]

        let collapsed = YouTubeRowBuilder(expanded: [], uploads: uploads).channels([channel])
        XCTAssertEqual(collapsed.map(\.id), ["youtube-channel-ch"])

        let rows = YouTubeRowBuilder(expanded: ["ch"], uploads: uploads).channels([channel])
        XCTAssertEqual(rows.map(\.id), ["youtube-channel-ch", "youtube-video-up", "youtube-video-film",
                                         "youtube-video-both", "youtube-video-new"])
        XCTAssertEqual(rows.map(\.indentLevel), [0, 1, 1, 1, 1])
        // One marker per form on disk, audio first, kept out of the title that sorting and type-ahead read
        XCTAssertEqual(rows.map(\.title), ["Chan", "Up", "Film", "Both", "New"])
        XCTAssertEqual(rows.map(\.titlePrefix), [nil, "♫", "▶\u{FE0E}", "♫ ▶\u{FE0E}", nil])
        XCTAssertEqual(rows.map(\.info), [nil, "1:15", nil, nil, nil])
        XCTAssertEqual(rows.map(\.hasChildren), [true, false, false, false, false])

        // The Local search's download rows carry the same markers
        let found = YouTubeRowBuilder(expanded: [], uploads: [:]).localSearch(query: "film", excluding: [])
        let download = try XCTUnwrap(found.first { $0.id == "youtube-download-film" })
        XCTAssertEqual(download.title, "Film")
        XCTAssertEqual(download.titlePrefix, "▶\u{FE0E}")
    }

    @MainActor
    func testChannelUploadsAreFetchedOnceAndKeptOnDisk() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("nullplayer-youtube-uploads-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var videoLimit = 3
        let channel = YouTubeChannel(id: "ch", title: "Chan", url: URL(string: "https://www.youtube.com/@ch")!, dateAdded: Date())
        var fetchedLimits: [Int] = []
        let fetch: YouTubeChannelUploads.Fetch = { _, limit in
            fetchedLimits.append(limit)
            return (0..<limit).map { YouTubeVideo(videoId: "v\($0)", title: "V\($0)", channelId: "ch", duration: nil, publishedAt: nil) }
        }
        func settle(_ uploads: YouTubeChannelUploads) async {
            while uploads.hasFetchesInFlight { await Task.yield() }
        }

        let uploads = YouTubeChannelUploads(file: file, limit: { videoLimit }, fetch: fetch)
        var posts = 0
        let observer = NotificationCenter.default.addObserver(
            forName: YouTubeChannelUploads.didChangeNotification, object: uploads, queue: nil) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        XCTAssertTrue(uploads.uploads(of: ["ch"]).isEmpty)
        uploads.load([channel, channel])  // the second joins the first's fetch
        XCTAssertTrue(uploads.isFetching("ch"))
        XCTAssertEqual(posts, 1)  // one post per load call, so a caller rebuilds once
        await settle(uploads)
        XCTAssertEqual(posts, 2)  // and one when the fetch ends
        XCTAssertEqual(fetchedLimits, [3])
        XCTAssertEqual(uploads.uploads(of: ["ch"])["ch"]?.map(\.videoId), ["v0", "v1", "v2"])

        uploads.load([channel])  // fresh: no fetch, but still posts
        XCTAssertFalse(uploads.hasFetchesInFlight)
        XCTAssertEqual(posts, 3)
        uploads.load([channel], force: true)  // Refresh
        await settle(uploads)
        XCTAssertEqual(fetchedLimits, [3, 3])

        // A smaller limit shows the newest cached uploads; a larger one fetches again.
        videoLimit = 2
        uploads.load([channel])
        XCTAssertFalse(uploads.hasFetchesInFlight)
        XCTAssertEqual(uploads.uploads(of: ["ch"])["ch"]?.count, 2)
        videoLimit = 4
        uploads.load([channel])
        await settle(uploads)
        XCTAssertEqual(fetchedLimits, [3, 3, 4])

        // A relaunch reads the list from disk instead of fetching it.
        let relaunched = YouTubeChannelUploads(file: file, limit: { videoLimit }, fetch: fetch)
        XCTAssertEqual(relaunched.uploads(of: ["ch"])["ch"]?.count, 4)
        relaunched.load([channel])
        XCTAssertFalse(relaunched.hasFetchesInFlight)

        let entry = YouTubeChannelUploads.Entry(limit: 4, fetchedAt: Date(), videos: [])
        XCTAssertTrue(entry.isFresh(limit: 4, now: Date()))
        XCTAssertFalse(entry.isFresh(limit: 4, now: Date().addingTimeInterval(YouTubeChannelUploads.maxAge)))
    }

    func testDoubleClickPlaysTheOnlyFormOnDiskAndOtherwiseAsks() {
        let audio = URL(fileURLWithPath: "/tmp/V.mp3"), video = URL(fileURLWithPath: "/tmp/V.mp4")
        XCTAssertEqual(YouTubeVideoActions.formToPlay([.audio: audio]), .audio)
        XCTAssertEqual(YouTubeVideoActions.formToPlay([.video: video]), .video)
        // Both forms on disk: the menu chooses. Neither: the menu offers the downloads.
        XCTAssertNil(YouTubeVideoActions.formToPlay([.audio: audio, .video: video]))
        XCTAssertNil(YouTubeVideoActions.formToPlay([:]))
    }

    func testDownloadedVideoCarriesTheManifestIdentity() {
        let download = YouTubeDownload(videoId: "v", title: "Title", channelId: "c", fileName: "C/T [v].mp3", kind: .audio)
        let video = YouTubeVideo(download: download)
        XCTAssertEqual(video.videoId, "v")
        XCTAssertEqual(video.title, "Title")
        XCTAssertEqual(video.channelId, "c")
        XCTAssertNil(video.duration)
        XCTAssertNil(video.publishedAt)
    }

    private func writeManifestEntries(root: URL, _ entries: [String: [String: String]]) throws {
        let data = try JSONSerialization.data(withJSONObject: entries)
        try data.write(to: root.appendingPathComponent("youtube_downloads.json"))
    }

    private func writeManifest(root: URL, download: YouTubeDownload) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent(download.fileName))
        let data = try JSONEncoder().encode([download.videoId: download])
        try data.write(to: root.appendingPathComponent("youtube_downloads.json"))
    }
}
