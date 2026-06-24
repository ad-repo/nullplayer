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

    // MARK: - YouTubeQuality Tests

    func testYouTubeQualityFLACArgs() {
        let quality = YouTubeQuality.flac

        XCTAssertEqual(quality.ytdlpArgs, ["--audio-format", "flac", "--audio-quality", "0"])
        XCTAssertEqual(quality.displayName, "FLAC")
        XCTAssertEqual(quality.fileExtension, "flac")
    }

    func testYouTubeQualityMP3HighArgs() {
        let quality = YouTubeQuality.mp3High

        XCTAssertEqual(quality.ytdlpArgs, ["--audio-format", "mp3", "--audio-quality", "0"])
        XCTAssertEqual(quality.displayName, "MP3 (High)")
        XCTAssertEqual(quality.fileExtension, "mp3")
    }

    func testYouTubeQualityMP3LowArgs() {
        let quality = YouTubeQuality.mp3Low

        XCTAssertEqual(quality.ytdlpArgs, ["--audio-format", "mp3", "--audio-quality", "5"])
        XCTAssertEqual(quality.displayName, "MP3 (Low)")
        XCTAssertEqual(quality.fileExtension, "mp3")
    }

    func testYouTubeQualityAllCases() {
        let allCases = YouTubeQuality.allCases

        XCTAssertEqual(allCases.count, 5)
        XCTAssertTrue(allCases.contains(.flac))
        XCTAssertTrue(allCases.contains(.mp3High))
        XCTAssertTrue(allCases.contains(.mp3Low))
        XCTAssertTrue(allCases.contains(.video720))
        XCTAssertTrue(allCases.contains(.video1080))
    }

    func testYouTubeQualityVideo720() {
        let quality = YouTubeQuality.video720

        XCTAssertEqual(quality.displayName, "Video (720p)")
        XCTAssertEqual(quality.fileExtension, "mp4")
        XCTAssertTrue(quality.isVideo)
        XCTAssertEqual(quality.videoMaxHeight, 720)
    }

    func testYouTubeQualityVideo1080() {
        let quality = YouTubeQuality.video1080

        XCTAssertEqual(quality.displayName, "Video (1080p)")
        XCTAssertEqual(quality.fileExtension, "mp4")
        XCTAssertTrue(quality.isVideo)
        XCTAssertEqual(quality.videoMaxHeight, 1080)
    }

    func testYouTubeQualityAudioFormats() {
        for quality in [YouTubeQuality.flac, .mp3High, .mp3Low] {
            XCTAssertFalse(quality.isVideo)
            XCTAssertNil(quality.videoMaxHeight)
        }
    }

    func testYouTubeQualityRawValues() {
        XCTAssertEqual(YouTubeQuality.flac.rawValue, "flac")
        XCTAssertEqual(YouTubeQuality.mp3High.rawValue, "mp3High")
        XCTAssertEqual(YouTubeQuality.mp3Low.rawValue, "mp3Low")
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
            download: YouTubeDownload(videoId: "video-a", title: "A", channelId: "channel", fileName: "A.flac", quality: .flac)
        )
        try writeManifest(
            root: rootB,
            download: YouTubeDownload(videoId: "video-b", title: "B", channelId: "channel", fileName: "B.flac", quality: .flac)
        )

        manager.downloadRoot = rootA
        XCTAssertNotNil(manager.downloadedFileURL(for: "video-a", quality: .flac))
        XCTAssertNil(manager.downloadedFileURL(for: "video-b", quality: .flac))

        manager.downloadRoot = rootB
        XCTAssertNil(manager.downloadedFileURL(for: "video-a", quality: .flac))
        XCTAssertNotNil(manager.downloadedFileURL(for: "video-b", quality: .flac))
    }

    func testSameVideoCanBeDownloadedInMultipleFormats() throws {
        let manager = YouTubeManager.shared
        let originalRoot = manager.downloadRoot
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nullplayer-youtube-test-multi-\(UUID().uuidString)", isDirectory: true)
        defer {
            manager.downloadRoot = originalRoot
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("vid.flac"))
        try Data().write(to: root.appendingPathComponent("vid.mp4"))
        let manifest: [String: YouTubeDownload] = [
            "vid#flac": YouTubeDownload(videoId: "vid", title: "V", channelId: "c", fileName: "vid.flac", quality: .flac),
            "vid#video1080": YouTubeDownload(videoId: "vid", title: "V", channelId: "c", fileName: "vid.mp4", quality: .video1080),
        ]
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: root.appendingPathComponent("youtube_downloads.json"))

        manager.downloadRoot = root
        // Both formats resolve independently; one does not mask the other.
        XCTAssertNotNil(manager.downloadedFileURL(for: "vid", quality: .flac))
        XCTAssertNotNil(manager.downloadedFileURL(for: "vid", quality: .video1080))
        // A format that wasn't downloaded is reported as missing, so the UI offers a download.
        XCTAssertNil(manager.downloadedFileURL(for: "vid", quality: .video720))

        // Removing one format leaves the other intact.
        manager.removeDownload(videoId: "vid", quality: .flac)
        XCTAssertNil(manager.downloadedFileURL(for: "vid", quality: .flac))
        XCTAssertNotNil(manager.downloadedFileURL(for: "vid", quality: .video1080))
    }

    func testLegacyManifestWithoutQualityMigratesByExtension() throws {
        let manager = YouTubeManager.shared
        let originalRoot = manager.downloadRoot
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nullplayer-youtube-test-legacy-\(UUID().uuidString)", isDirectory: true)
        defer {
            manager.downloadRoot = originalRoot
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("legacy.flac"))
        // Old manifest shape: keyed by bare videoId, entry has no `quality` field.
        let legacyJSON = """
        {"legacy":{"videoId":"legacy","title":"L","channelId":"c","fileName":"legacy.flac"}}
        """
        try legacyJSON.data(using: .utf8)!.write(to: root.appendingPathComponent("youtube_downloads.json"))

        manager.downloadRoot = root
        XCTAssertNotNil(manager.downloadedFileURL(for: "legacy", quality: .flac))
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
            quality: .flac
        )
        let manifest = try JSONEncoder().encode(["outside#flac": download])
        try manifest.write(to: root.appendingPathComponent("youtube_downloads.json"))

        manager.downloadRoot = root
        XCTAssertNil(manager.downloadedFileURL(for: "outside", quality: .flac))
        manager.removeDownload(videoId: "outside", quality: .flac)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideFile.path))
    }

    private func writeManifest(root: URL, download: YouTubeDownload) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent(download.fileName))
        let data = try JSONEncoder().encode([download.videoId: download])
        try data.write(to: root.appendingPathComponent("youtube_downloads.json"))
    }
}
