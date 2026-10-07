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

    /// Square channel avatar, shown as the channel's art, as YouTube listed it. Optional so
    /// channels saved before it existed still decode; filled in on add, or by
    /// `YouTubeManager.backfillMissingAvatars()`.
    var avatarURL: URL? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, url, dateAdded, avatarURL
    }

    /// `avatarURL` sized to `side` pixels. Google's image server sizes by an `=sNNN-` path
    /// parameter; a URL without one is returned as is.
    func avatarURL(side: Int) -> URL? {
        guard var string = avatarURL?.absoluteString else { return nil }
        if let range = string.range(of: #"=s\d+-"#, options: .regularExpression) {
            string.replaceSubrange(range, with: "=s\(side)-")
        }
        return URL(string: string)
    }
}

/// A channel found by `YouTubeManager.searchChannels`, not (necessarily) subscribed
struct YouTubeChannelSearchResult: Hashable {
    /// YouTube channel ID (`UC…`)
    let channelId: String

    /// `@handle`, nil when the channel has none
    let handle: String?

    let followerCount: Int?

    /// The channel as it would be subscribed, keyed exactly as a pasted URL of the same
    /// form would be (the URL goes through `normalizeChannelURL`).
    let channel: YouTubeChannel

    init(channelId: String, handle: String?, title: String, followerCount: Int?, avatarURL: URL?) {
        self.channelId = channelId
        self.handle = handle
        self.followerCount = followerCount
        let path = handle.map { $0.hasPrefix("@") ? $0 : "@" + $0 } ?? "channel/\(channelId)"
        let normalized = URL(string: "https://www.youtube.com/\(path)").flatMap(YouTubeManager.normalizeChannelURL)
        channel = YouTubeChannel(
            id: normalized?.key ?? channelId,
            title: title,
            url: normalized.map { YouTubeManager.channelBaseURL(fromListURL: $0.listURL) }
                ?? URL(string: "https://www.youtube.com/channel/\(channelId)")!,
            dateAdded: Date(),
            avatarURL: avatarURL)
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

    /// The small 16:9 thumbnail for a list row (`mqdefault.jpg`, 320×180, no letterbox bars)
    var rowThumbnailURL: URL {
        URL(string: "https://i.ytimg.com/vi/\(videoId)/mqdefault.jpg")!
    }

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

extension YouTubeVideo {
    /// A downloaded video, as the manifest knows it: no duration, date or thumbnail.
    init(download: YouTubeDownload) {
        self.init(videoId: download.videoId, title: download.title, channelId: download.channelId,
                  duration: nil, publishedAt: nil)
    }
}

/// Which form of a video a download is: its audio track or the MP4. A video can have both.
enum YouTubeMediaKind: String, Codable, CaseIterable {
    case audio, video

    var displayName: String {
        switch self {
        case .audio: return "Audio"
        case .video: return "Video"
        }
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

    let kind: YouTubeMediaKind

    /// A manifest entry's identity: one video can have an audio and a video download.
    struct Key: Hashable {
        let videoId: String
        let kind: YouTubeMediaKind
    }

    var key: Key { Key(videoId: videoId, kind: kind) }
}

extension YouTubeDownload {
    /// An entry written before `kind` existed infers it from the file's extension.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        videoId = try container.decode(String.self, forKey: .videoId)
        title = try container.decode(String.self, forKey: .title)
        channelId = try container.decode(String.self, forKey: .channelId)
        fileName = try container.decode(String.self, forKey: .fileName)
        kind = try container.decodeIfPresent(YouTubeMediaKind.self, forKey: .kind)
            ?? (AudioFileValidator.isVideoFile(url: URL(fileURLWithPath: fileName)) ? .video : .audio)
    }
}

/// Audio format for a video's audio download. YouTube's best audio is ~130–160 kbps Opus (or
/// 128 kbps AAC), so every format but the two originals is a re-encode of that.
enum YouTubeAudioFormat: Hashable {
    case flac, alac
    case mp3(kbps: Int)
    case aac(kbps: Int)
    case originalAAC, originalOpus

    /// The choices, as the menu groups them: lossless, MP3, AAC, originals
    static let sections: [[YouTubeAudioFormat]] = [
        [.flac, .alac],
        [320, 256, 192, 128].map { .mp3(kbps: $0) },
        [256, 192, 128].map { .aac(kbps: $0) },
        [.originalAAC, .originalOpus],
    ]

    /// The saved setting value
    var rawValue: String {
        switch self {
        case .flac: return "flac"
        case .alac: return "alac"
        case .mp3(let kbps): return "mp3-\(kbps)"
        case .aac(let kbps): return "aac-\(kbps)"
        case .originalAAC: return "originalAAC"
        case .originalOpus: return "originalOpus"
        }
    }

    /// A saved value: one of the choices, or a value of the old `YouTubeQuality` setting
    /// (`mp3High` was V0, `mp3Low` V5).
    init?(savedValue: String) {
        switch savedValue {
        case "mp3High": self = .mp3(kbps: 320)
        case "mp3Low": self = .mp3(kbps: 128)
        default:
            guard let choice = Self.sections.joined().first(where: { $0.rawValue == savedValue }) else { return nil }
            self = choice
        }
    }

    /// yt-dlp's `-f` stream selector
    var formatSelector: String {
        switch self {
        case .flac, .alac, .mp3: return "bestaudio/best"
        // An AAC source would be copied into the .m4a as is, so encode from the Opus stream.
        case .aac, .originalOpus: return "bestaudio[acodec=opus]/bestaudio"
        case .originalAAC: return "bestaudio[ext=m4a]/bestaudio"
        }
    }

    /// yt-dlp's audio-extraction arguments
    var ytdlpArgs: [String] {
        switch self {
        case .flac: return ["--audio-format", "flac"]
        // yt-dlp's `alac` mapping drops the codec and writes AAC; name it to ffmpeg directly.
        case .alac: return ["--audio-format", "alac", "--ppa", "ExtractAudio+ffmpeg_o:-c:a alac"]
        case .mp3(let kbps): return ["--audio-format", "mp3", "--audio-quality", "\(kbps)K"]
        case .aac(let kbps): return ["--audio-format", "m4a", "--audio-quality", "\(kbps)K"]
        case .originalAAC: return ["--audio-format", "m4a"]
        case .originalOpus: return ["--audio-format", "opus"]
        }
    }

    var displayName: String {
        switch self {
        case .flac: return "FLAC"
        case .alac: return "ALAC"
        case .mp3(let kbps): return "MP3 \(kbps) kbps"
        case .aac(let kbps): return "AAC \(kbps) kbps"
        case .originalAAC: return "Original AAC (no re-encode)"
        case .originalOpus: return "Original Opus (no re-encode)"
        }
    }
}

/// Height cap for a video's MP4 download
enum YouTubeVideoQuality: Hashable {
    case height(Int)
    case best

    /// The choices, as the menu groups them: the height ladder, then no cap
    static let sections: [[YouTubeVideoQuality]] = [
        [360, 480, 720, 1080, 1440, 2160].map { .height($0) },
        [.best],
    ]

    /// The saved setting value
    var rawValue: String {
        switch self {
        case .height(let height): return "p\(height)"
        case .best: return "best"
        }
    }

    /// A saved value: one of the choices, or a video value of the old `YouTubeQuality` setting.
    init?(savedValue: String) {
        switch savedValue {
        case "video720": self = .height(720)
        case "video1080": self = .height(1080)
        default:
            guard let choice = Self.sections.joined().first(where: { $0.rawValue == savedValue }) else { return nil }
            self = choice
        }
    }

    /// nil for `best`: no cap
    var maxHeight: Int? {
        switch self {
        case .height(let height): return height
        case .best: return nil
        }
    }

    var displayName: String {
        switch self {
        case .height(2160): return "2160p (4K)"
        case .height(let height): return "\(height)p"
        case .best: return "Best Available"
        }
    }
}
