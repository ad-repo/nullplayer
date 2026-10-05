import Foundation

/// A YouTube channel saved for easy access to videos
struct YouTubeChannel: Codable, Identifiable, Hashable {
    /// Canonical channel identifier (channel ID or normalized URL key)
    let id: String

    /// Human-readable channel title
    let title: String

    /// Base channel URL (e.g., https://www.youtube.com/@handle)
    let url: URL

    /// When this channel was added to the saved list
    let dateAdded: Date

    /// Square channel avatar, shown as the channel's art. Optional so channels saved
    /// before it existed still decode; filled in on add, or on first expand.
    var avatarURL: URL? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, url, dateAdded, avatarURL
    }
}

/// A channel found by `YouTubeManager.searchChannels`, not (necessarily) subscribed
struct YouTubeChannelSearchResult: Hashable {
    /// YouTube channel ID (`UC…`)
    let channelId: String

    /// `@handle`, nil when the channel has none
    let handle: String?

    let title: String
    let followerCount: Int?
    let description: String?
    let avatarURL: URL?

    /// The channel as it would be subscribed. The URL goes through `normalizeChannelURL`
    /// so `id` is keyed exactly as a pasted URL of the same form would be.
    var asChannel: YouTubeChannel {
        let path = handle.map { $0.hasPrefix("@") ? $0 : "@" + $0 } ?? "channel/\(channelId)"
        let pasted = URL(string: "https://www.youtube.com/\(path)")
        let normalized = pasted.flatMap { YouTubeManager.normalizeChannelURL($0) }
        let key = normalized?.key ?? channelId
        let baseURL = normalized.map { YouTubeManager.channelBaseURL(fromListURL: $0.listURL) }
            ?? URL(string: "https://www.youtube.com/channel/\(channelId)")!
        return YouTubeChannel(id: key, title: title, url: baseURL, dateAdded: Date(), avatarURL: avatarURL)
    }

    /// Follower count in compact form ("15.8M", "36.5K"), nil when unknown
    var formattedFollowerCount: String? {
        guard let count = followerCount else { return nil }
        let value = Double(count)
        func compact(_ v: Double, _ suffix: String) -> String {
            let s = v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
            return (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + suffix
        }
        if value >= 1_000_000_000 { return compact(value / 1_000_000_000, "B") }
        if value >= 1_000_000 { return compact(value / 1_000_000, "M") }
        if value >= 1_000 { return compact(value / 1_000, "K") }
        return "\(count)"
    }

    /// Row info text: "@handle · 15.8M"
    var infoText: String {
        [handle, formattedFollowerCount].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A YouTube video metadata
struct YouTubeVideo: Codable, Identifiable, Hashable {
    /// YouTube video ID (unique identifier)
    let videoId: String

    /// Video title
    let title: String

    /// Channel ID that this video belongs to
    let channelId: String

    /// Video duration in seconds (nil if unknown)
    let duration: TimeInterval?

    /// Approximate upload date. yt-dlp only exposes relative dates ("3 weeks ago") on
    /// the channel grid, so this is an estimate that coarsens for older uploads. nil when
    /// unavailable (e.g. a flat fetch without the approximate-date extractor arg).
    let publishedAt: Date?

    /// 16:9 thumbnail (`hq720.jpg`, no letterbox bars), used as the video's art
    var thumbnailURL: URL? = nil

    /// Video ID is used as the Identifiable id
    var id: String { videoId }

    /// Construct a watch URL for this video
    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
    }

    /// Duration formatted as minutes and seconds without rounding the minute component.
    var formattedDuration: String? {
        duration.map {
            let totalSeconds = max(0, Int($0))
            return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
        }
    }

    /// Compact upload date for the channels list (e.g. "Jun 23, 2026"), nil if unknown.
    var formattedDate: String? {
        publishedAt.map { Self.dateFormatter.string(from: $0) }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    enum CodingKeys: String, CodingKey {
        case videoId, title, channelId, duration, publishedAt, thumbnailURL
    }
}

/// Metadata about a downloaded YouTube video
struct YouTubeDownload: Codable {
    /// YouTube video ID
    let videoId: String

    /// Video title at time of download
    let title: String

    /// Channel ID it belongs to
    let channelId: String

    /// Local filename (relative to downloadRoot)
    let fileName: String
}

/// Output quality for YouTube downloads
enum YouTubeQuality: String, Codable, CaseIterable {
    case flac = "flac"
    case mp3High = "mp3High"
    case mp3Low = "mp3Low"
    case video720 = "video720"
    case video1080 = "video1080"

    /// Whether this is a video format
    var isVideo: Bool {
        self == .video720 || self == .video1080
    }

    /// Height cap for video formats; nil for audio formats.
    var videoMaxHeight: Int? {
        switch self {
        case .video720: return 720
        case .video1080: return 1080
        default: return nil
        }
    }

    /// yt-dlp command-line arguments for this quality
    var ytdlpArgs: [String] {
        switch self {
        case .flac:
            return ["--audio-format", "flac", "--audio-quality", "0"]
        case .mp3High:
            return ["--audio-format", "mp3", "--audio-quality", "0"]
        case .mp3Low:
            return ["--audio-format", "mp3", "--audio-quality", "5"]
        case .video720, .video1080:
            return []
        }
    }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .flac: return "FLAC"
        case .mp3High: return "MP3 (High)"
        case .mp3Low: return "MP3 (Low)"
        case .video720: return "Video (720p)"
        case .video1080: return "Video (1080p)"
        }
    }

    /// File extension for this format
    var fileExtension: String {
        switch self {
        case .flac: return "flac"
        case .mp3High, .mp3Low: return "mp3"
        case .video720, .video1080: return "mp4"
        }
    }
}
