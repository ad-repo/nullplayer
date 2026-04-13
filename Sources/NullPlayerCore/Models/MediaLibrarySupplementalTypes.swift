import Foundation

/// Lightweight summary of an album for paginated display.
public struct AlbumSummary: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let artist: String?
    public let year: Int?
    public let trackCount: Int

    public init(id: String, name: String, artist: String?, year: Int?, trackCount: Int) {
        self.id = id
        self.name = name
        self.artist = artist
        self.year = year
        self.trackCount = trackCount
    }
}

public struct LocalVideo: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public var title: String
    public var year: Int?
    public var duration: TimeInterval
    public var fileSize: Int64
    public var dateAdded: Date

    public init(url: URL) {
        self.id = UUID()
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        self.year = nil
        self.duration = 0
        self.fileSize = 0
        self.dateAdded = Date()
    }

    public init(id: UUID, url: URL, title: String, year: Int?, duration: TimeInterval, fileSize: Int64, dateAdded: Date) {
        self.id = id
        self.url = url
        self.title = title
        self.year = year
        self.duration = duration
        self.fileSize = fileSize
        self.dateAdded = dateAdded
    }
}

public struct LocalEpisode: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public var title: String
    public var showTitle: String
    public var seasonNumber: Int
    public var episodeNumber: Int?
    public var duration: TimeInterval
    public var fileSize: Int64
    public var dateAdded: Date

    public init(url: URL, showTitle: String, seasonNumber: Int = 1, episodeNumber: Int? = nil) {
        self.id = UUID()
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        self.showTitle = showTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.duration = 0
        self.fileSize = 0
        self.dateAdded = Date()
    }

    public init(
        id: UUID,
        url: URL,
        title: String,
        showTitle: String,
        seasonNumber: Int,
        episodeNumber: Int?,
        duration: TimeInterval,
        fileSize: Int64,
        dateAdded: Date
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.showTitle = showTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.duration = duration
        self.fileSize = fileSize
        self.dateAdded = dateAdded
    }
}

public struct FileScanSignature: Codable, Hashable, Sendable {
    public let fileSize: Int64
    public let contentModificationDate: Date?

    public init(fileSize: Int64, contentModificationDate: Date?) {
        self.fileSize = fileSize
        self.contentModificationDate = contentModificationDate
    }
}
