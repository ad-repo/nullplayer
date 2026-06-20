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

    /// Upload date string (format varies from API, e.g., "2024-01-15")
    let uploadDate: String?

    /// Video ID is used as the Identifiable id
    var id: String { videoId }

    /// Construct a watch URL for this video
    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
    }

    enum CodingKeys: String, CodingKey {
        case videoId, title, channelId, duration, uploadDate
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

    /// yt-dlp command-line arguments for this quality
    var ytdlpArgs: [String] {
        switch self {
        case .flac:
            return ["--audio-format", "flac", "--audio-quality", "0"]
        case .mp3High:
            return ["--audio-format", "mp3", "--audio-quality", "0"]
        case .mp3Low:
            return ["--audio-format", "mp3", "--audio-quality", "5"]
        }
    }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .flac: return "FLAC"
        case .mp3High: return "MP3 (High)"
        case .mp3Low: return "MP3 (Low)"
        }
    }

    /// File extension for this format
    var fileExtension: String {
        switch self {
        case .flac: return "flac"
        case .mp3High, .mp3Low: return "mp3"
        }
    }
}
