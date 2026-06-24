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

    enum CodingKeys: String, CodingKey {
        case id, title, url, dateAdded
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
        case videoId, title, channelId, duration, publishedAt
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

    /// Format this file was downloaded in. A video can be downloaded in more than
    /// one format, so identity in the manifest is (videoId, quality), not videoId.
    let quality: YouTubeQuality

    init(videoId: String, title: String, channelId: String, fileName: String, quality: YouTubeQuality) {
        self.videoId = videoId
        self.title = title
        self.channelId = channelId
        self.fileName = fileName
        self.quality = quality
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        videoId = try c.decode(String.self, forKey: .videoId)
        title = try c.decode(String.self, forKey: .title)
        channelId = try c.decode(String.self, forKey: .channelId)
        fileName = try c.decode(String.self, forKey: .fileName)
        // Manifests written before per-format downloads have no `quality`; infer it
        // from the file extension so existing downloads stay addressable.
        quality = try c.decodeIfPresent(YouTubeQuality.self, forKey: .quality)
            ?? YouTubeQuality.inferred(fromFileName: fileName)
    }

    private enum CodingKeys: String, CodingKey {
        case videoId, title, channelId, fileName, quality
    }
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

    /// Best-effort quality for a download whose manifest entry predates the
    /// `quality` field, inferred from its file extension. Resolution-only
    /// distinctions (720 vs 1080, mp3 high vs low) can't be recovered, so we
    /// pick a representative value; the file still plays either way.
    static func inferred(fromFileName name: String) -> YouTubeQuality {
        switch (name as NSString).pathExtension.lowercased() {
        case "flac": return .flac
        case "mp3": return .mp3High
        case "mp4", "mkv", "webm", "mov", "m4v": return .video720
        default: return .flac
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
