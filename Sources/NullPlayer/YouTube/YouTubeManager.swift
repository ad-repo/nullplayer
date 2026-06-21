import Foundation
import AppKit

/// Singleton managing YouTube channel subscriptions and downloads
final class YouTubeManager {
    // MARK: - Singleton

    static let shared = YouTubeManager()

    private init() {
        loadChannels()
        loadQuality()
        setupDownloadRoot()
    }

    // MARK: - Notifications

    static let youtubeChannelsDidChangeNotification = Notification.Name("YouTubeChannelsDidChange")

    // MARK: - Channels

    private(set) var channels: [YouTubeChannel] = [] {
        didSet {
            saveChannels()
            NotificationCenter.default.post(name: Self.youtubeChannelsDidChangeNotification, object: self)
        }
    }

    // MARK: - Quality

    var quality: YouTubeQuality = .flac {
        didSet {
            UserDefaults.standard.set(quality.rawValue, forKey: "YouTubeQuality")
        }
    }

    // MARK: - Download Root

    private var _downloadRoot: URL = URL(fileURLWithPath: "")

    var downloadRoot: URL {
        get { _downloadRoot }
        set {
            let normalizedRoot = newValue.standardizedFileURL
            guard normalizedRoot != _downloadRoot else { return }
            _downloadRoot = normalizedRoot
            downloadManifest = [:]
            manifestLoaded = false
            saveDownloadRoot()
            // Create directory if it's on a local volume
            createLocalDownloadDirectoryIfNeeded()
        }
    }

    // MARK: - Download Manifest

    /// In-memory cache of downloaded videos, keyed by videoId
    private var downloadManifest: [String: YouTubeDownload] = [:]
    private var manifestLoaded = false

    // MARK: - Initialization

    private func loadChannels() {
        guard let data = UserDefaults.standard.data(forKey: channelsKey),
              let decoded = try? JSONDecoder().decode([YouTubeChannel].self, from: data) else {
            channels = []
            return
        }
        channels = decoded
        NSLog("YouTubeManager: Loaded %d saved channels", channels.count)
    }

    private func saveChannels() {
        guard let data = try? JSONEncoder().encode(channels) else { return }
        UserDefaults.standard.set(data, forKey: channelsKey)
    }

    private func loadQuality() {
        let rawValue = UserDefaults.standard.string(forKey: "YouTubeQuality") ?? YouTubeQuality.flac.rawValue
        quality = YouTubeQuality(rawValue: rawValue) ?? .flac
    }

    private func setupDownloadRoot() {
        if let savedPath = UserDefaults.standard.string(forKey: downloadRootKey),
           !savedPath.isEmpty {
            _downloadRoot = URL(fileURLWithPath: savedPath).standardizedFileURL
        } else {
            // Default: ~/Library/Application Support/NullPlayer/YouTube/
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            _downloadRoot = appSupport.appendingPathComponent("NullPlayer/YouTube/").standardizedFileURL
            // Eagerly create the default local folder so the very first download works.
            // (User-chosen folders go through the `downloadRoot` setter instead, which
            // gates creation on reachability to avoid writing into a stale NAS mount.)
            try? FileManager.default.createDirectory(at: _downloadRoot, withIntermediateDirectories: true)
        }
    }

    private func saveDownloadRoot() {
        UserDefaults.standard.set(downloadRoot.path, forKey: downloadRootKey)
    }

    private func createLocalDownloadDirectoryIfNeeded() {
        guard isDownloadFolderReachable() else { return }
        try? FileManager.default.createDirectory(at: downloadRoot, withIntermediateDirectories: true)
    }

    // MARK: - Reachability

    /// Check if the download folder is reachable (either local or network volume)
    func isDownloadFolderReachable() -> Bool {
        FileManager.default.fileExists(atPath: downloadRoot.path) &&
            (try? downloadRoot.checkResourceIsReachable()) == true
    }

    // MARK: - Channels API

    /// Add a YouTube channel by URL. Accepts @handle, full channel URLs, etc.
    /// Fetches channel title via yt-dlp.
    func addChannel(url: URL) async throws {
        guard let (key, listURL) = Self.normalizeChannelURL(url) else {
            throw YouTubeManagerError.invalidChannelURL("Could not parse channel URL")
        }

        let title = try await Self.fetchChannelTitle(from: listURL)
        try Task.checkCancellation()

        let channel = YouTubeChannel(
            id: key,
            title: title,
            url: listURL.deletingLastPathComponent(),
            dateAdded: Date()
        )

        if channels.contains(where: { $0.id == key }) {
            throw YouTubeManagerError.channelAlreadyAdded("Channel '\(title)' is already in your library")
        }

        channels.append(channel)
    }

    /// Remove a channel (does not delete downloaded videos)
    func removeChannel(_ channel: YouTubeChannel) {
        channels.removeAll { $0.id == channel.id }
    }

    // MARK: - Videos API

    /// Fetch videos from a channel (up to the specified limit)
    func videos(forChannel channel: YouTubeChannel, limit: Int = 50) async throws -> [YouTubeVideo] {
        guard let videosURL = Self.channelVideosURL(channel: channel) else {
            throw YouTubeManagerError.invalidChannelURL("Cannot construct videos URL")
        }

        let jsonData = try await Self.fetchYtDlpJSON(from: videosURL, playlistEnd: limit)
        let videos = try Self.parseFlatPlaylist(jsonData, channelId: channel.id)
        return videos
    }

    // MARK: - Downloads API

    /// Download audio from a YouTube video.
    ///
    /// Files are organized as `<downloadRoot>/<Channel Name>/<Title> [<videoId>].<ext>`
    /// so the on-disk layout mirrors the channel/video hierarchy and filenames are
    /// human-readable while staying unique (the bracketed video ID disambiguates
    /// videos that share a title).
    func downloadAudio(video: YouTubeVideo) async throws -> URL {
        guard isDownloadFolderReachable() else {
            throw YouTubeManagerError.downloadFolderNotReachable("Download folder is not accessible")
        }

        // Per-channel subfolder, created up front so yt-dlp can write into it.
        let channelFolder = channelFolderName(for: video.channelId)
        let channelDir = downloadRoot.appendingPathComponent(channelFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: channelDir, withIntermediateDirectories: true)

        let formatArgs = quality.ytdlpArgs + ["-x", "--embed-metadata", "--embed-thumbnail", "--convert-thumbnails", "jpg", "--no-playlist"]
        // Let yt-dlp sanitize the title and pick the final extension after conversion.
        let outputTemplate = "\(channelDir.path)/%(title)s [%(id)s].%(ext)s"

        let fileURL = try await StreamRipper.downloadAudio(
            from: video.watchURL,
            formatArgs: formatArgs,
            outputTemplate: outputTemplate
        )

        // Record in manifest as a path relative to downloadRoot (channel/file).
        let relativePath = "\(channelFolder)/\(fileURL.lastPathComponent)"
        let download = YouTubeDownload(
            videoId: video.videoId,
            title: video.title,
            channelId: video.channelId,
            fileName: relativePath
        )
        recordDownload(download)

        return fileURL
    }

    /// Folder name for a channel's downloads: the human-readable channel title when
    /// known, falling back to the channel identifier. Sanitized for use as a path
    /// component.
    private func channelFolderName(for channelId: String) -> String {
        let raw = channels.first(where: { $0.id == channelId })?.title ?? channelId
        return Self.sanitizedPathComponent(raw)
    }

    /// Sanitize an arbitrary string into a safe single path component (no path
    /// separators or characters that confuse the filesystem).
    nonisolated static func sanitizedPathComponent(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:")
        let cleaned = name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Unknown Channel" : cleaned
    }

    /// Get the local URL for a downloaded video (if it exists)
    func downloadedFileURL(for videoId: String) -> URL? {
        loadManifestIfNeeded()
        guard let download = downloadManifest[videoId],
              let fileURL = manifestFileURL(for: download) else { return nil }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    /// Check if a video has been downloaded
    func isDownloaded(_ videoId: String) -> Bool {
        downloadedFileURL(for: videoId) != nil
    }

    /// Remove a downloaded video (deletes file and manifest entry)
    func removeDownload(videoId: String) {
        loadManifestIfNeeded()
        guard let download = downloadManifest[videoId] else { return }
        if let fileURL = manifestFileURL(for: download) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        downloadManifest.removeValue(forKey: videoId)
        saveManifest()
    }

    // MARK: - Manifest Persistence

    private func recordDownload(_ download: YouTubeDownload) {
        loadManifestIfNeeded()
        downloadManifest[download.videoId] = download
        saveManifest()
    }

    private func loadManifestIfNeeded() {
        guard !manifestLoaded else { return }
        manifestLoaded = true

        let manifestURL = downloadRoot.appendingPathComponent("youtube_downloads.json")
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        let decoded = try? JSONDecoder().decode([String: YouTubeDownload].self, from: data)
        downloadManifest = decoded ?? [:]
    }

    private func saveManifest() {
        let manifestURL = downloadRoot.appendingPathComponent("youtube_downloads.json")
        guard let data = try? JSONEncoder().encode(downloadManifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    /// Resolve a manifest entry without allowing a malformed or edited manifest to
    /// escape the selected download root via `..` path components.
    private func manifestFileURL(for download: YouTubeDownload) -> URL? {
        let root = downloadRoot.standardizedFileURL
        let candidate = root.appendingPathComponent(download.fileName).standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else { return nil }
        return candidate
    }

    // MARK: - Private Helpers

    /// Construct the URL to list videos from a channel
    private static func channelVideosURL(channel: YouTubeChannel) -> URL? {
        // Attempt to append /videos if not already present
        if channel.url.path.hasSuffix("/videos") {
            return channel.url
        }
        if channel.url.path == "/" || channel.url.path.isEmpty {
            return channel.url.appendingPathComponent("videos")
        }
        return URL(string: channel.url.absoluteString.appending("/videos"))
    }

    /// Single-segment YouTube paths that are not channel handles and must not be
    /// mistaken for one (e.g. `youtube.com/watch?v=...`).
    private static let reservedChannelPaths: Set<String> = [
        "watch", "results", "shorts", "playlist", "feed", "embed", "live", "hashtag",
    ]

    /// Normalize a YouTube channel URL into a canonical key and listable URL
    /// This is a pure function with no side effects, suitable for unit testing.
    nonisolated static func normalizeChannelURL(_ url: URL) -> (key: String, listURL: URL)? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        // Only accept youtube.com and its real subdomains, not lookalike hosts such
        // as evilyoutube.com.
        guard let host = components.host?.lowercased(),
              host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var pathSegments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        // Remove trailing /videos if present (we'll re-add it in listURL)
        if pathSegments.last == "videos" {
            pathSegments.removeLast()
        }

        var key: String?
        var canonicalPathSegments: [String]?
        if pathSegments.count == 1 {
            // A handle, channel ID, or legacy single-segment custom URL.
            let segment = pathSegments[0]
            if segment.hasPrefix("@") {
                key = String(segment.dropFirst()) // Remove the @ prefix
            } else if segment == "user" || segment == "c" {
                // Need more segments; won't normalize
                return nil
            } else if Self.reservedChannelPaths.contains(segment.lowercased()) {
                // Not a channel (e.g. /watch, /shorts, /playlist, /results)
                return nil
            } else {
                key = segment
            }
            canonicalPathSegments = [segment]
        } else if pathSegments.count == 2 {
            // /user/NAME or /channel/ID or /c/Name
            let prefix = pathSegments[0].lowercased()
            let identifier = pathSegments[1]
            if prefix == "user" || prefix == "channel" || prefix == "c" {
                key = identifier
                canonicalPathSegments = [prefix, identifier]
            }
        } else if pathSegments.isEmpty {
            // Just youtube.com with no path
            return nil
        }

        guard let normalizedKey = key, !normalizedKey.isEmpty,
              let canonicalPathSegments else { return nil }

        // Preserve the accepted route form. A channel ID, legacy /user URL, or /c
        // URL is not generally equivalent to an @handle with the same identifier.
        var listComponents = URLComponents()
        listComponents.scheme = "https"
        listComponents.host = "www.youtube.com"
        listComponents.path = "/" + canonicalPathSegments.joined(separator: "/") + "/videos"
        guard let listURL = listComponents.url else { return nil }
        return (key: normalizedKey, listURL: listURL)
    }

    /// Fetch the channel title by querying yt-dlp for the first video's uploader
    nonisolated private static func fetchChannelTitle(from videosURL: URL) async throws -> String {
        let jsonData = try await fetchYtDlpJSON(from: videosURL, playlistEnd: 1)
        let decoder = JSONDecoder()
        let response = try decoder.decode(YtDlpResponse.self, from: jsonData)

        // Try to get channel name from response
        if let title = response.channel ?? response.uploader {
            return title
        }

        // Fallback: try first entry's uploader
        if let firstEntry = response.entries?.first, let uploader = firstEntry.uploader {
            return uploader
        }

        throw YouTubeManagerError.couldNotFetchChannelTitle("Could not determine channel title")
    }

    /// Parse yt-dlp's flat-playlist JSON response into YouTubeVideo models
    /// This is a pure function with no side effects, suitable for unit testing.
    nonisolated static func parseFlatPlaylist(_ data: Data, channelId: String) throws -> [YouTubeVideo] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try decoder.decode(YtDlpResponse.self, from: data)
        guard let entries = response.entries else { return [] }

        return entries.compactMap { entry in
            guard let videoId = entry.id else { return nil }
            return YouTubeVideo(
                videoId: videoId,
                title: entry.title ?? "Unknown",
                channelId: channelId,
                duration: entry.duration.map(TimeInterval.init),
                uploadDate: entry.upload_date
            )
        }
    }

    /// Call yt-dlp -J to get flat playlist metadata
    nonisolated private static func fetchYtDlpJSON(from url: URL, playlistEnd: Int) async throws -> Data {
        guard let ytdlp = StreamRipper.resolveTool("yt-dlp") else {
            throw YouTubeManagerError.toolNotFound("yt-dlp is not installed")
        }

        var env = ProcessInfo.processInfo.environment
        // Use SearchPaths defined locally since StreamRipper's is private
        env["PATH"] = (Self.defaultSearchPaths + [env["PATH"] ?? ""]).joined(separator: ":")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ytdlp)
        task.arguments = ["--flat-playlist", "-J", "--playlist-end", "\(playlistEnd)", url.absoluteString]
        task.environment = env

        let tempDirectory = FileManager.default.temporaryDirectory
        let outputURL = tempDirectory.appendingPathComponent("nullplayer-ytdlp-output-\(UUID().uuidString)")
        let errorURL = tempDirectory.appendingPathComponent("nullplayer-ytdlp-error-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        guard let outputHandle = try? FileHandle(forWritingTo: outputURL),
              let errorHandle = try? FileHandle(forWritingTo: errorURL) else {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
            throw YouTubeManagerError.toolFailed("Could not create temporary yt-dlp output files")
        }
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }
        task.standardOutput = outputHandle
        task.standardError = errorHandle

        do {
            try task.run()
        } catch {
            throw YouTubeManagerError.toolFailed(error.localizedDescription)
        }

        task.waitUntilExit()
        try? outputHandle.close()
        try? errorHandle.close()

        let outputData = (try? Data(contentsOf: outputURL)) ?? Data()
        if task.terminationStatus != 0 {
            let errData = (try? Data(contentsOf: errorURL)) ?? Data()
            let errText = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw YouTubeManagerError.toolFailed("yt-dlp failed: \(errText)")
        }

        return outputData
    }

    // MARK: - Constants

    private let channelsKey = "YouTubeChannels"
    private let downloadRootKey = "YouTubeDownloadRoot"

    /// Directories searched for `yt-dlp` (same as StreamRipper's searchPaths)
    private static let defaultSearchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin"]
}

// MARK: - Error Types

enum YouTubeManagerError: LocalizedError {
    case invalidChannelURL(String)
    case channelAlreadyAdded(String)
    case downloadFolderNotReachable(String)
    case couldNotFetchChannelTitle(String)
    case toolNotFound(String)
    case toolFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidChannelURL(let msg): return msg
        case .channelAlreadyAdded(let msg): return msg
        case .downloadFolderNotReachable(let msg): return msg
        case .couldNotFetchChannelTitle(let msg): return msg
        case .toolNotFound(let msg): return msg
        case .toolFailed(let msg): return msg
        }
    }
}

// MARK: - yt-dlp JSON Decoding

private struct YtDlpResponse: Decodable {
    let channel: String?
    let uploader: String?
    let entries: [YtDlpEntry]?

    enum CodingKeys: String, CodingKey {
        case channel, uploader, entries
    }
}

private struct YtDlpEntry: Decodable {
    let id: String?
    let title: String?
    let duration: Int?
    let upload_date: String?
    let uploader: String?
}
