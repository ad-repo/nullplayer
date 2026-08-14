import Foundation

struct PodcastFeed: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let indexId: Int64?
    let title: String
    let author: String?
    let summary: String?
    let feedURL: URL
    let websiteURL: URL?
    let imageURL: URL?
    let categories: [String]
    let language: String?
    let episodeCount: Int?
    let explicit: Bool

    init(
        indexId: Int64? = nil,
        title: String,
        author: String? = nil,
        summary: String? = nil,
        feedURL: URL,
        websiteURL: URL? = nil,
        imageURL: URL? = nil,
        categories: [String] = [],
        language: String? = nil,
        episodeCount: Int? = nil,
        explicit: Bool = false
    ) {
        self.id = Self.stableID(for: feedURL)
        self.indexId = indexId
        self.title = title.nilIfBlank ?? "Untitled Podcast"
        self.author = author?.nilIfBlank
        self.summary = summary?.podcastPlainText.nilIfBlank
        self.feedURL = feedURL
        self.websiteURL = websiteURL
        self.imageURL = imageURL
        self.categories = categories.filter { !$0.isEmpty }
        self.language = language?.nilIfBlank
        self.episodeCount = episodeCount
        self.explicit = explicit
    }

    static func stableID(for url: URL) -> String {
        Data(url.absoluteString.lowercased().utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct PodcastEpisode: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let indexId: Int64?
    let feedID: String
    let feedIndexId: Int64?
    let feedTitle: String
    let feedAuthor: String?
    let title: String
    let summary: String?
    let publishedAt: Date?
    let duration: TimeInterval?
    let enclosureURL: URL
    let enclosureType: String?
    let enclosureLength: Int64?
    let imageURL: URL?
    let websiteURL: URL?
    let explicit: Bool

    init(
        persistedID: String? = nil,
        persistedFeedID: String? = nil,
        indexId: Int64? = nil,
        guid: String? = nil,
        feed: PodcastFeed,
        title: String,
        summary: String? = nil,
        publishedAt: Date? = nil,
        duration: TimeInterval? = nil,
        enclosureURL: URL,
        enclosureType: String? = nil,
        enclosureLength: Int64? = nil,
        imageURL: URL? = nil,
        websiteURL: URL? = nil,
        explicit: Bool = false
    ) {
        let stableValue = indexId.map(String.init) ?? guid?.nilIfBlank ?? enclosureURL.absoluteString
        self.id = persistedID ?? "\(feed.id):\(stableValue)"
        self.indexId = indexId
        self.feedID = persistedFeedID ?? feed.id
        self.feedIndexId = feed.indexId
        self.feedTitle = feed.title
        self.feedAuthor = feed.author
        self.title = title.nilIfBlank ?? "Untitled Episode"
        self.summary = summary?.podcastPlainText.nilIfBlank
        self.publishedAt = publishedAt
        self.duration = duration.flatMap { $0 > 0 ? $0 : nil }
        self.enclosureURL = enclosureURL
        self.enclosureType = enclosureType?.nilIfBlank
        self.enclosureLength = enclosureLength
        self.imageURL = imageURL ?? feed.imageURL
        self.websiteURL = websiteURL
        self.explicit = explicit
    }

    var isVideo: Bool {
        if enclosureType?.lowercased().hasPrefix("video/") == true { return true }
        return AudioFileValidator.isVideoFile(url: enclosureURL)
    }

    var formattedDuration: String {
        guard let duration else { return "--:--" }
        let total = max(0, Int(duration))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

struct PodcastSubscription: Codable, Identifiable, Hashable, Sendable {
    var id: String { feed.id }
    var feed: PodcastFeed
    var subscribedAt: Date
    var autoDownloadNewest: Bool
}

struct PodcastEpisodeState: Codable, Hashable, Sendable {
    var position: TimeInterval = 0
    var duration: TimeInterval?
    var isPlayed = false
    var isFavorite = false
    var downloadedPath: String?
    var lastPlayedAt: Date?
}

struct PodcastLibrarySnapshot: Codable, Sendable {
    var subscriptions: [PodcastSubscription]
    var episodeStates: [String: PodcastEpisodeState]
    var knownEpisodes: [String: PodcastEpisode]
}

extension URL {
    /// True only for remote `http`/`https` resources. Podcast feed, enclosure, and image URLs
    /// originate from untrusted RSS/Atom/OPML and directory JSON, so every URL that becomes a
    /// `URLSession` fetch/download or a file destination must pass through here first — otherwise a
    /// crafted `file://` (or other scheme) enclosure could read local files or reach unintended sinks.
    var isPodcastRemoteURL: Bool {
        switch scheme?.lowercased() {
        case "http", "https": return true
        default: return false
        }
    }
}

extension String {
    fileprivate var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var podcastPlainText: String {
        var result = replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</p>", with: "\n", options: [.caseInsensitive])
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&nbsp;": " "
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement,
                                                  options: [.caseInsensitive])
        }
        return result
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
