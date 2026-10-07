import Foundation
import AppKit

/// Singleton managing YouTube channel subscriptions and downloads
final class YouTubeManager {
    // MARK: - Singleton

    static let shared = YouTubeManager()

    private init() {
        loadChannels()
        loadFormats()
        loadVideoLimit()
        setupDownloadRoot()
    }

    // MARK: - Notifications

    static let youtubeChannelsDidChangeNotification = Notification.Name("YouTubeChannelsDidChange")
    /// Posted when the per-channel video limit changes; browser views drop their cached
    /// video lists and re-fetch expanded channels so the new limit applies without a restart.
    static let youtubeVideoLimitDidChangeNotification = Notification.Name("YouTubeVideoLimitDidChange")

    // MARK: - Channels

    private(set) var channels: [YouTubeChannel] = [] {
        didSet {
            saveChannels()
            NotificationCenter.default.post(name: Self.youtubeChannelsDidChangeNotification, object: self)
        }
    }

    // MARK: - Formats

    var audioFormat: YouTubeAudioFormat = .flac {
        didSet { UserDefaults.standard.set(audioFormat.rawValue, forKey: Self.audioFormatKey) }
    }

    var videoQuality: YouTubeVideoQuality = .height(1080) {
        didSet { UserDefaults.standard.set(videoQuality.rawValue, forKey: Self.videoQualityKey) }
    }

    // MARK: - Video Limit

    /// How many recent uploads to list per channel (the `--playlist-end` value).
    /// Presets exposed in the Library → YouTube menu.
    static let videoLimitChoices = [50, 100, 200, 500]

    var videoLimit: Int = 200 {
        didSet {
            guard videoLimit != oldValue else { return }
            UserDefaults.standard.set(videoLimit, forKey: "YouTubeVideoLimit")
            NotificationCenter.default.post(name: Self.youtubeVideoLimitDidChangeNotification, object: self)
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

    /// The configured download root resolved directly from persisted settings, mirroring
    /// `setupDownloadRoot`. Reads only `UserDefaults` (which is thread-safe), so it can be
    /// called off the main thread — e.g. from `Track.playHistorySource` — without touching
    /// the manager's mutable in-memory state.
    static var resolvedDownloadRoot: URL {
        if let savedPath = UserDefaults.standard.string(forKey: downloadRootKey), !savedPath.isEmpty {
            return URL(fileURLWithPath: savedPath).standardizedFileURL
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("NullPlayer/YouTube/").standardizedFileURL
    }

    /// Whether `url` points to a file inside the YouTube download folder. Lets play-history
    /// analytics attribute downloads to the YouTube source even when the in-memory origin
    /// flag was lost — e.g. a download played from the Library Browser (where the folder is
    /// also a scanned library location) or restored from an older saved state.
    static func isWithinDownloadRoot(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let root = resolvedDownloadRoot.path
        guard !root.isEmpty else { return false }
        let candidate = url.standardizedFileURL.path
        let rootWithSlash = root.hasSuffix("/") ? root : root + "/"
        return candidate == root || candidate.hasPrefix(rootWithSlash)
    }

    // MARK: - Download Manifest

    /// In-memory cache of downloaded videos, keyed by videoId and kind
    private var downloadManifest: [YouTubeDownload.Key: YouTubeDownload] = [:]
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

    private func loadFormats() {
        let defaults = UserDefaults.standard
        let formats = Self.resolveFormats(
            audioFormat: defaults.string(forKey: Self.audioFormatKey),
            videoQuality: defaults.string(forKey: Self.videoQualityKey),
            legacyQuality: defaults.string(forKey: Self.legacyQualityKey))
        audioFormat = formats.audioFormat
        videoQuality = formats.videoQuality
    }

    /// The two format settings from their saved raw values. Before they were split, one
    /// `YouTubeQuality` setting held either an audio format or a video height; when a new
    /// key is absent its value comes from that, else the default (FLAC / 1080p).
    nonisolated static func resolveFormats(audioFormat: String?, videoQuality: String?,
                                           legacyQuality: String?) -> (audioFormat: YouTubeAudioFormat, videoQuality: YouTubeVideoQuality) {
        ((audioFormat ?? legacyQuality).flatMap(YouTubeAudioFormat.init(savedValue:)) ?? .flac,
         (videoQuality ?? legacyQuality).flatMap(YouTubeVideoQuality.init(savedValue:)) ?? .height(1080))
    }

    private func loadVideoLimit() {
        let saved = UserDefaults.standard.integer(forKey: "YouTubeVideoLimit")
        videoLimit = saved > 0 ? saved : 200
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

        // ffmpeg is required to merge video streams and transcode audio to
        // FLAC/MP3 at download time. Verify it up front (the yt-dlp check happens
        // implicitly in fetchChannelTitle below) so the user is told about a
        // missing dependency when adding a channel, rather than only when a later
        // download fails with a cryptic "Postprocessing: ffmpeg not found" error.
        try Self.requireFFmpeg()

        let info = try await Self.fetchChannelInfo(from: listURL)
        try Task.checkCancellation()

        let channel = YouTubeChannel(
            id: key,
            title: info.title,
            url: Self.channelBaseURL(fromListURL: listURL),
            dateAdded: Date(),
            avatarURL: info.avatarURL
        )
        try subscribe(to: channel)
    }

    /// Subscribe to a channel whose title is already known (e.g. a search result).
    /// Same dependency and duplicate checks as `addChannel(url:)`, without the title fetch.
    func subscribe(to channel: YouTubeChannel) throws {
        try Self.requireFFmpeg()
        if channels.contains(where: { Self.channelKeysMatch($0.id, channel.id) }) {
            throw YouTubeManagerError.channelAlreadyAdded("Channel '\(channel.title)' is already in your library")
        }
        channels.append(channel)
    }

    /// Whether `channel` is one of the subscriptions. Rows always carry a subscription's own
    /// `id`; a search result is resolved to its subscription by `subscription(matching:)`.
    func isSubscribed(_ channel: YouTubeChannel) -> Bool {
        channels.contains { $0.id == channel.id }
    }

    /// The subscription a search result is, if any: by its key (a handle-keyed
    /// subscription), or by its `UC…` channel ID (a channel added by a `/channel/UC…` URL).
    func subscription(matching result: YouTubeChannelSearchResult) -> YouTubeChannel? {
        Self.subscription(matching: result, in: channels)
    }

    nonisolated static func subscription(matching result: YouTubeChannelSearchResult,
                                         in channels: [YouTubeChannel]) -> YouTubeChannel? {
        channels.first { channelKeysMatch($0.id, result.channel.id) || $0.id == result.channelId }
    }

    /// Whether two channel keys name the same channel. Handles are case-insensitive on
    /// YouTube, so `@LofiGirl` and `@lofigirl` are one channel.
    nonisolated private static func channelKeysMatch(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }

    /// ffmpeg is required to merge video streams and transcode audio at download time.
    nonisolated private static func requireFFmpeg() throws {
        guard StreamRipper.resolveTool("ffmpeg") != nil else {
            throw YouTubeManagerError.toolNotFound("ffmpeg is not installed. Install via Homebrew: brew install ffmpeg")
        }
    }

    /// Search YouTube for channels by name (channels-only results filter, no API key).
    func searchChannels(query: String, limit: Int = 20) async throws -> [YouTubeChannelSearchResult] {
        guard let url = Self.channelSearchURL(query: query) else {
            throw YouTubeManagerError.toolFailed("Could not build search URL")
        }
        let jsonData = try await Self.fetchYtDlpJSON(from: url, playlistEnd: limit)
        return try Self.parseChannelSearch(jsonData)
    }

    /// Channels whose avatar back-fill already ran this session (success or not — not retried).
    private var avatarBackfillAttempted: Set<String> = []

    /// Fetch avatars for subscriptions saved before avatars were stored, so the Channels list
    /// shows them. One `--playlist-end 1` listing per channel, run sequentially; each avatar
    /// is stored as it lands (a listing takes seconds, so they appear one by one).
    @MainActor
    func backfillMissingAvatars() {
        let missing = channels.filter { $0.avatarURL == nil && !avatarBackfillAttempted.contains($0.id) }
        guard !missing.isEmpty else { return }
        avatarBackfillAttempted.formUnion(missing.map(\.id))
        Task { @MainActor in
            for channel in missing {
                guard let listURL = Self.channelVideosURL(channel: channel),
                      let avatar = try? await Self.fetchChannelInfo(from: listURL).avatarURL,
                      let index = self.channels.firstIndex(where: { $0.id == channel.id }) else { continue }
                self.channels[index].avatarURL = avatar
            }
        }
    }

    /// Remove a channel (does not delete downloaded videos)
    func removeChannel(_ channel: YouTubeChannel) {
        channels.removeAll { $0.id == channel.id }
    }

    // MARK: - Videos API

    /// Fetch videos from a channel (up to the specified limit)
    func videos(forChannel channel: YouTubeChannel, limit: Int? = nil) async throws -> [YouTubeVideo] {
        guard let videosURL = Self.channelVideosURL(channel: channel) else {
            throw YouTubeManagerError.invalidChannelURL("Cannot construct videos URL")
        }

        // Request approximate upload dates so the channels list can show/sort a Date column;
        // they come back as a per-entry `timestamp` in the same single flat-playlist call.
        let jsonData = try await Self.fetchYtDlpJSON(from: videosURL, playlistEnd: limit ?? videoLimit, approximateDate: true)
        return try Self.parseFlatPlaylist(jsonData, channelId: channel.id)
    }

    // MARK: - Downloads API

    /// Download audio or video from a YouTube video.
    ///
    /// Files are organized as `<downloadRoot>/<Channel Name>/<Title> [<videoId>].<ext>`
    /// so the on-disk layout mirrors the channel/video hierarchy and filenames are
    /// human-readable while staying unique (the bracketed video ID disambiguates
    /// videos that share a title). `kind` picks the audio track (in `audioFormat`) or the
    /// MP4 (capped at `videoQuality`); the two can coexist.
    /// `channelTitle` names the folder for a channel that isn't subscribed (a search
    /// result's preview), so it isn't named after a bare ID.
    func download(video: YouTubeVideo, kind: YouTubeMediaKind, channelTitle: String? = nil) async throws -> URL {
        guard isDownloadFolderReachable() else {
            throw YouTubeManagerError.downloadFolderNotReachable("Download folder is not accessible")
        }

        // Per-channel subfolder, created up front so yt-dlp can write into it.
        let channelFolder = channelFolderName(for: video.channelId, fallbackTitle: channelTitle)
        let channelDir = downloadRoot.appendingPathComponent(channelFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: channelDir, withIntermediateDirectories: true)

        // Let yt-dlp sanitize the title and pick the final extension after conversion.
        let outputTemplate = "\(channelDir.path)/%(title)s [%(id)s].%(ext)s"

        let fileURL: URL
        switch kind {
        case .video:
            fileURL = try await StreamRipper.downloadVideo(
                from: video.watchURL, maxHeight: videoQuality.maxHeight, outputTemplate: outputTemplate,
                extraArgs: Self.squareThumbnailArgs)
        case .audio:
            fileURL = try await StreamRipper.downloadAudio(
                from: video.watchURL, formatSelector: audioFormat.formatSelector,
                formatArgs: audioFormat.ytdlpArgs + Self.squareThumbnailArgs, outputTemplate: outputTemplate)
        }

        // Record in manifest as a path relative to downloadRoot (channel/file).
        let relativePath = "\(channelFolder)/\(fileURL.lastPathComponent)"
        let download = YouTubeDownload(
            videoId: video.videoId,
            title: video.title,
            channelId: video.channelId,
            fileName: relativePath,
            kind: kind
        )
        recordDownload(download)

        return fileURL
    }

    /// Embed the thumbnail as cover art, center-cropped to a square so it reads as album
    /// art. The crop runs as an ffmpeg output arg on the thumbnail converter; the `--ppa`
    /// value is one Process argument (yt-dlp shlex-splits it, hence the inner quoting,
    /// and the single quotes keep the filter's commas from splitting the filtergraph).
    static let squareThumbnailArgs = [
        "--embed-thumbnail", "--convert-thumbnails", "jpg",
        "--ppa", "ThumbnailsConvertor+FFmpeg_o:-c:v mjpeg -vf crop=\"'if(gt(ih,iw),iw,ih)':'if(gt(iw,ih),ih,iw)'\"",
    ]

    /// Folder name for a channel's downloads: the human-readable channel title when
    /// known (subscribed, else `fallbackTitle`), falling back to the channel identifier.
    /// Sanitized for use as a path component.
    private func channelFolderName(for channelId: String, fallbackTitle: String? = nil) -> String {
        let raw = channels.first(where: { $0.id == channelId })?.title ?? fallbackTitle ?? channelId
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

    /// A video's downloaded files that are on disk, by kind (empty when none are).
    func downloadedFiles(for videoId: String) -> [YouTubeMediaKind: URL] {
        loadManifestIfNeeded()
        var files: [YouTubeMediaKind: URL] = [:]
        for kind in YouTubeMediaKind.allCases {
            guard let download = downloadManifest[YouTubeDownload.Key(videoId: videoId, kind: kind)],
                  let fileURL = manifestFileURL(for: download),
                  FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            files[kind] = fileURL
        }
        return files
    }

    /// Check if any form of a video has been downloaded
    func isDownloaded(_ videoId: String) -> Bool {
        !downloadedFiles(for: videoId).isEmpty
    }

    /// The file whose embedded cover art stands for a video: the audio download, else the video.
    func coverArtFile(for videoId: String) -> URL? {
        let files = downloadedFiles(for: videoId)
        return files[.audio] ?? files[.video]
    }

    /// The Local source's search over YouTube: subscribed channels whose name matches, and
    /// downloaded videos whose title matches. `listedFiles` are already library tracks (the
    /// download folder is also a watch folder), so a video is listed only for a file on disk
    /// that is not one of them. A video's row takes its audio entry's title, as its art does
    /// (`coverArtFile`). Reads the subscriptions and the manifest only.
    func localSearch(query: String, excluding listedFiles: Set<URL>) -> (channels: [YouTubeChannel], videos: [YouTubeVideo]) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ([], []) }
        loadManifestIfNeeded()
        let listed = Set(listedFiles.map(\.standardizedFileURL))
        let videos = Dictionary(grouping: downloadManifest.values, by: \.videoId)
            .compactMap { videoId, downloads -> YouTubeVideo? in
                guard downloads.contains(where: { $0.title.localizedStandardContains(query) }),
                      !Set(downloadedFiles(for: videoId).values).isSubset(of: listed),
                      let download = downloads.first(where: { $0.kind == .audio }) ?? downloads.first else { return nil }
                return YouTubeVideo(download: download)
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return (channels.filter { $0.title.localizedStandardContains(query) }, videos)
    }

    /// Remove one form of a downloaded video (deletes file and manifest entry)
    func removeDownload(_ key: YouTubeDownload.Key) {
        loadManifestIfNeeded()
        guard let download = downloadManifest[key] else { return }
        if let fileURL = manifestFileURL(for: download) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        downloadManifest.removeValue(forKey: key)
        saveManifest()
    }

    // MARK: - Manifest Persistence

    private func recordDownload(_ download: YouTubeDownload) {
        loadManifestIfNeeded()
        downloadManifest[download.key] = download
        saveManifest()
    }

    private func loadManifestIfNeeded() {
        guard !manifestLoaded else { return }
        manifestLoaded = true

        let manifestURL = downloadRoot.appendingPathComponent("youtube_downloads.json")
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        guard let decoded = try? JSONDecoder().decode([String: YouTubeDownload].self, from: data) else { return }
        // Re-key by each entry's videoId and kind rather than trusting the dictionary key,
        // so a manifest written with any other key scheme (older ones used the bare videoId)
        // still resolves.
        var byKey: [YouTubeDownload.Key: YouTubeDownload] = [:]
        for download in decoded.values {
            byKey[download.key] = download
        }
        downloadManifest = byKey
    }

    private func saveManifest() {
        let manifestURL = downloadRoot.appendingPathComponent("youtube_downloads.json")
        let byName = Dictionary(uniqueKeysWithValues: downloadManifest.map { key, download in
            ("\(key.videoId).\(key.kind.rawValue)", download)
        })
        guard let data = try? JSONEncoder().encode(byName) else { return }
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
    nonisolated static func channelVideosURL(channel: YouTubeChannel) -> URL? {
        guard var components = URLComponents(url: channel.url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        // Strip any trailing slashes before appending so we never produce a
        // double slash like "@handle//videos". yt-dlp treats the double-slash
        // form as the channel root and returns the Videos/Live/Shorts tab list
        // instead of the uploads. This also repairs channels whose stored URL
        // already carries a trailing slash (e.g. from `addChannel`).
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/videos") {
            path += "/videos"
        }
        components.path = path
        return components.url
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

    /// Base channel URL from a listing URL: ".../@handle/videos" → ".../@handle", with no
    /// trailing slash so `channelVideosURL` doesn't build a double-slash listing URL.
    nonisolated static func channelBaseURL(fromListURL listURL: URL) -> URL {
        var baseComponents = URLComponents(url: listURL, resolvingAgainstBaseURL: false)
        var basePath = baseComponents?.path ?? ""
        if basePath.hasSuffix("/videos") { basePath.removeLast("/videos".count) }
        while basePath.hasSuffix("/") { basePath.removeLast() }
        baseComponents?.path = basePath
        return baseComponents?.url ?? listURL.deletingLastPathComponent()
    }

    /// The channels-only search results URL for a query. The query is percent-encoded
    /// down to RFC 3986 unreserved characters so `&`, `+` and `#` in it survive intact;
    /// `sp=EgIQAg==` is YouTube's "Type: Channel" filter.
    nonisolated static func channelSearchURL(query: String) -> URL? {
        let unreserved = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/results"
        components.percentEncodedQuery = "search_query=\(encoded)&sp=EgIQAg%3D%3D"
        return components.url
    }

    /// Fetch the channel title (and avatar, when present) via a one-entry listing
    nonisolated private static func fetchChannelInfo(from videosURL: URL) async throws -> (title: String, avatarURL: URL?) {
        try parseChannelInfo(await fetchYtDlpJSON(from: videosURL, playlistEnd: 1))
    }

    /// The channel title and avatar from a channel listing response.
    /// This is a pure function with no side effects, suitable for unit testing.
    nonisolated static func parseChannelInfo(_ data: Data) throws -> (title: String, avatarURL: URL?) {
        let response = try JSONDecoder().decode(YtDlpResponse.self, from: data)
        let avatar = avatarURL(from: response.thumbnails)

        // Try to get channel name from response
        if let title = response.channel ?? response.uploader {
            return (title, avatar)
        }

        // Fallback: try first entry's uploader
        if let firstEntry = response.entries?.first, let uploader = firstEntry.uploader {
            return (uploader, avatar)
        }

        throw YouTubeManagerError.couldNotFetchChannelTitle("Could not determine channel title")
    }

    /// Parse a yt-dlp channels-only search (`/results?…&sp=EgIQAg==`) into results.
    /// Entries without a `channel_id` (or with one that isn't URL-safe) are dropped.
    /// This is a pure function with no side effects, suitable for unit testing.
    nonisolated static func parseChannelSearch(_ data: Data) throws -> [YouTubeChannelSearchResult] {
        let response = try JSONDecoder().decode(YtDlpResponse.self, from: data)
        let idCharacters = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return (response.entries ?? []).compactMap { entry in
            guard let channelId = entry.channel_id ?? entry.id, !channelId.isEmpty,
                  channelId.unicodeScalars.allSatisfy({ idCharacters.contains($0) }) else { return nil }
            let handle = entry.uploader_id.flatMap { $0.hasPrefix("@") ? $0 : nil }
            return YouTubeChannelSearchResult(
                channelId: channelId,
                handle: handle,
                title: entry.title ?? entry.channel ?? handle ?? channelId,
                followerCount: entry.channel_follower_count,
                avatarURL: avatarURL(from: entry.thumbnails)
            )
        }
    }

    /// Pick a channel avatar from a `thumbnails` list: the largest square one, else
    /// `avatar_uncropped`. Callers size it with `YouTubeChannel.avatarURL(side:)`.
    nonisolated private static func avatarURL(from thumbnails: [YtDlpThumbnail]?) -> URL? {
        guard let thumbnails else { return nil }
        let square = thumbnails
            .filter { ($0.width ?? 0) > 0 && $0.width == $0.height }
            .max { ($0.width ?? 0) < ($1.width ?? 0) }
        return (square ?? thumbnails.first { $0.id == "avatar_uncropped" }).flatMap(\.absoluteURL)
    }

    /// Pick a video thumbnail: the widest `hq720` (16:9, no letterbox bars), falling back
    /// to the row's `mqdefault.jpg` (also 16:9). `hqdefault.jpg` is 4:3 letterboxed, so a
    /// square crop of it would include black bars.
    nonisolated private static func videoThumbnailURL(videoId: String, thumbnails: [YtDlpThumbnail]?) -> URL? {
        (thumbnails ?? [])
            .filter { !$0.url.contains("hqdefault") }
            .max { ($0.width ?? 0) < ($1.width ?? 0) }?
            .absoluteURL
            ?? URL(string: "https://i.ytimg.com/vi/\(videoId)/mqdefault.jpg")
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
                publishedAt: entry.timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                thumbnailURL: videoThumbnailURL(videoId: videoId, thumbnails: entry.thumbnails)
            )
        }
    }

    /// Call yt-dlp -J to get flat playlist metadata
    nonisolated private static func fetchYtDlpJSON(from url: URL, playlistEnd: Int, approximateDate: Bool = false) async throws -> Data {
        guard let ytdlp = StreamRipper.resolveTool("yt-dlp") else {
            throw YouTubeManagerError.toolNotFound("yt-dlp is not installed")
        }

        var env = ProcessInfo.processInfo.environment
        // Use SearchPaths defined locally since StreamRipper's is private
        env["PATH"] = (Self.defaultSearchPaths + [env["PATH"] ?? ""]).joined(separator: ":")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ytdlp)
        var arguments = ["--flat-playlist", "-J", "--playlist-end", "\(playlistEnd)"]
        if approximateDate {
            // Populates each entry's `timestamp` with an approximate upload date.
            arguments += ["--extractor-args", "youtubetab:approximate_date"]
        }
        arguments.append(url.absoluteString)
        task.arguments = arguments
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
    private static let audioFormatKey = "YouTubeAudioFormat"
    private static let videoQualityKey = "YouTubeVideoQuality"
    private static let legacyQualityKey = "YouTubeQuality"
    private static let downloadRootKey = "YouTubeDownloadRoot"
    private var downloadRootKey: String { Self.downloadRootKey }

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
    let thumbnails: [YtDlpThumbnail]?

    enum CodingKeys: String, CodingKey {
        case channel, uploader, entries, thumbnails
    }
}

private struct YtDlpThumbnail: Decodable {
    let url: String
    let id: String?
    let width: Int?
    let height: Int?

    /// `url` as an absolute URL: search results list some protocol-relative (`//yt3…`).
    var absoluteURL: URL? {
        URL(string: url.hasPrefix("//") ? "https:" + url : url)
    }
}

private struct YtDlpEntry: Decodable {
    let id: String?
    let title: String?
    let duration: Int?
    let upload_date: String?
    let timestamp: Int?
    let uploader: String?
    let channel: String?
    let channel_id: String?
    let uploader_id: String?
    let channel_follower_count: Int?
    let thumbnails: [YtDlpThumbnail]?
}
