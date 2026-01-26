import Foundation

/// Media type for a track (audio or video)
public enum MediaType: String, Codable, Sendable {
    case audio
    case video
}

/// Represents a single audio or video track
public struct Track: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let title: String
    public let artist: String?
    public let album: String?
    public let duration: TimeInterval?
    public let bitrate: Int?
    public let sampleRate: Int?
    public let channels: Int?
    
    /// Plex rating key for play tracking (nil for local files)
    public let plexRatingKey: String?
    
    /// Subsonic song ID for scrobbling (nil for non-Subsonic tracks)
    public let subsonicId: String?
    
    /// Subsonic server ID to identify which server the track belongs to
    public let subsonicServerId: String?
    
    /// Media type (audio or video)
    public let mediaType: MediaType
    
    public init(id: UUID = UUID(),
                url: URL,
                title: String,
                artist: String? = nil,
                album: String? = nil,
                duration: TimeInterval? = nil,
                bitrate: Int? = nil,
                sampleRate: Int? = nil,
                channels: Int? = nil,
                plexRatingKey: String? = nil,
                subsonicId: String? = nil,
                subsonicServerId: String? = nil,
                mediaType: MediaType = .audio) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
        self.plexRatingKey = plexRatingKey
        self.subsonicId = subsonicId
        self.subsonicServerId = subsonicServerId
        self.mediaType = mediaType
    }
    
    /// Initialize from URL, extracting title from filename
    public init(url: URL) {
        self.id = UUID()
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        self.artist = nil
        self.album = nil
        self.duration = nil
        self.bitrate = nil
        self.sampleRate = nil
        self.channels = nil
        self.plexRatingKey = nil
        self.subsonicId = nil
        self.subsonicServerId = nil
        self.mediaType = .audio
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
        guard let duration = duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Hashable

extension Track: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
