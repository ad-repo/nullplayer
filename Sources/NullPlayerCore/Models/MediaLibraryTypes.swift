import Foundation

/// Represents an entry in the media library with full metadata
public struct LibraryTrack: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public var title: String
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var genre: String?
    public var year: Int?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var duration: TimeInterval
    public var bitrate: Int?
    public var sampleRate: Int?
    public var channels: Int?
    public var fileSize: Int64
    public var dateAdded: Date
    public var lastPlayed: Date?
    public var playCount: Int
    
    public init(url: URL) {
        self.id = UUID()
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        self.duration = 0
        self.fileSize = 0
        self.dateAdded = Date()
        self.playCount = 0
    }
    
    public init(id: UUID = UUID(),
                url: URL,
                title: String,
                artist: String? = nil,
                album: String? = nil,
                albumArtist: String? = nil,
                genre: String? = nil,
                year: Int? = nil,
                trackNumber: Int? = nil,
                discNumber: Int? = nil,
                duration: TimeInterval = 0,
                bitrate: Int? = nil,
                sampleRate: Int? = nil,
                channels: Int? = nil,
                fileSize: Int64 = 0,
                dateAdded: Date = Date(),
                lastPlayed: Date? = nil,
                playCount: Int = 0) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.genre = genre
        self.year = year
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.duration = duration
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
        self.fileSize = fileSize
        self.dateAdded = dateAdded
        self.lastPlayed = lastPlayed
        self.playCount = playCount
    }
    
    /// Display title (artist - title or just title)
    public var displayTitle: String {
        if let artist = artist, !artist.isEmpty {
            return "\(artist) - \(title)"
        }
        return title
    }
    
    /// Formatted duration string (MM:SS)
    public var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Convert to Track for playback
    public func toTrack() -> Track {
        return Track(
            id: id,
            url: url,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            bitrate: bitrate,
            sampleRate: sampleRate,
            channels: channels
        )
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Represents an album in the library
public struct Album: Identifiable, Hashable, Sendable {
    public let id: String  // "artist|album" key
    public let name: String
    public let artist: String?
    public let year: Int?
    public var tracks: [LibraryTrack]
    
    public init(id: String, name: String, artist: String?, year: Int?, tracks: [LibraryTrack]) {
        self.id = id
        self.name = name
        self.artist = artist
        self.year = year
        self.tracks = tracks
    }
    
    public var displayName: String {
        if let artist = artist, !artist.isEmpty {
            return "\(artist) - \(name)"
        }
        return name
    }
    
    public var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }
    
    public var formattedDuration: String {
        let totalSeconds = Int(totalDuration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, totalSeconds % 60)
        }
        return String(format: "%d:%02d", minutes, totalSeconds % 60)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Represents an artist in the library
public struct Artist: Identifiable, Hashable, Sendable {
    public let id: String  // Artist name as key
    public let name: String
    public var albums: [Album]
    
    public init(id: String, name: String, albums: [Album]) {
        self.id = id
        self.name = name
        self.albums = albums
    }
    
    public var trackCount: Int {
        albums.reduce(0) { $0 + $1.tracks.count }
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Sort options for library browsing
public enum LibrarySortOption: String, CaseIterable, Codable, Sendable {
    case title = "Title"
    case artist = "Artist"
    case album = "Album"
    case dateAdded = "Date Added"
    case duration = "Duration"
    case playCount = "Play Count"
}

/// Filter options for library browsing
public struct LibraryFilter: Codable, Sendable {
    public var searchText: String = ""
    public var artists: Set<String> = []
    public var albums: Set<String> = []
    public var genres: Set<String> = []
    public var yearRange: ClosedRange<Int>?
    
    public init() {}
    
    public var isEmpty: Bool {
        searchText.isEmpty && artists.isEmpty && albums.isEmpty && genres.isEmpty && yearRange == nil
    }
}

/// Library-related errors
public enum LibraryError: LocalizedError, Sendable {
    case noLibraryFile
    case backupNotFound
    case invalidBackupFile
    
    public var errorDescription: String? {
        switch self {
        case .noLibraryFile:
            return "No library file exists to backup."
        case .backupNotFound:
            return "The backup file was not found."
        case .invalidBackupFile:
            return "The backup file is invalid or corrupted."
        }
    }
}
