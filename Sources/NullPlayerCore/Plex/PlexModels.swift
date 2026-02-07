import Foundation

// MARK: - Flexible Decodable Types

/// A type that can decode either a String or a numeric value into a String
/// Used for Plex fields that inconsistently return strings vs numbers
public struct FlexibleString: Decodable {
    public let value: String
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let intValue = try? container.decode(Int.self) {
            value = String(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            value = String(doubleValue)
        } else {
            throw DecodingError.typeMismatch(String.self, DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected String, Int, or Double"
            ))
        }
    }
}

/// A type that can decode either a String or a numeric value into a Double
/// Used for Plex fields that inconsistently return strings vs numbers (like frameRate)
public struct FlexibleDouble: Codable, Equatable {
    public let value: Double?
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let intValue = try? container.decode(Int.self) {
            value = Double(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            value = Double(stringValue)
        } else {
            value = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Plex Account & Authentication

/// Plex account info obtained via PIN authentication
public struct PlexAccount: Codable, Equatable {
    public let id: Int
    public let uuid: String
    public let username: String
    public let email: String?
    public let thumb: String?          // Avatar URL
    public let authToken: String
    public let title: String?          // Display name
    
    enum CodingKeys: String, CodingKey {
        case id, uuid, username, email, thumb, title
        case authToken = "authToken"
    }
}

/// PIN for device linking flow
public struct PlexPIN: Codable {
    public let id: Int
    public let code: String            // 4-character code shown to user
    public let authToken: String?      // Populated once user authorizes
    public let expiresAt: Date?
    public let trusted: Bool?
    public let clientIdentifier: String?
    
    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
}

// MARK: - Plex Server & Connections

/// A Plex server discovered from the account
public struct PlexServer: Codable, Identifiable, Equatable {
    public let id: String              // clientIdentifier
    public let name: String
    public let product: String?
    public let productVersion: String?
    public let platform: String?
    public let platformVersion: String?
    public let device: String?
    public let owned: Bool
    public let connections: [PlexConnection]
    public let accessToken: String?    // Server-specific token
    
    /// Best available connection (prefers local)
    public var preferredConnection: PlexConnection? {
        // Prefer local connections over relay
        connections.first(where: { $0.local && !$0.relay }) ??
        connections.first(where: { !$0.relay }) ??
        connections.first
    }
    
    enum CodingKeys: String, CodingKey {
        case name, product, productVersion, platform, platformVersion, device, owned, connections, accessToken
        case id = "clientIdentifier"
    }
}

/// Server connection info (local or remote)
public struct PlexConnection: Codable, Equatable {
    public let uri: String             // Full URL e.g., "http://192.168.1.100:32400"
    public let local: Bool             // true if on same network
    public let relay: Bool             // true if using Plex relay
    public let address: String?
    public let port: Int?
    public let `protocol`: String?
    
    public var url: URL? {
        URL(string: uri)
    }
}

// MARK: - Plex Library Content

/// A library on a Plex server
public struct PlexLibrary: Identifiable, Equatable {
    public let id: String              // Section key/ID
    public let uuid: String?
    public let title: String
    public let type: String            // "artist" for music, "movie" for movies, "show" for TV
    public let agent: String?
    public let scanner: String?
    public let language: String?
    public let refreshing: Bool
    public let contentCount: Int?
    
    public var isMusicLibrary: Bool {
        type == "artist"
    }
    
    public var isMovieLibrary: Bool {
        type == "movie"
    }
    
    public var isShowLibrary: Bool {
        type == "show"
    }
    
    public var isVideoLibrary: Bool {
        isMovieLibrary || isShowLibrary
    }
}

/// An artist in a Plex music library
public struct PlexArtist: Identifiable, Equatable {
    public let id: String              // ratingKey
    public let key: String             // API path for children
    public let title: String
    public let summary: String?
    public let thumb: String?          // Artwork path
    public let art: String?            // Background art path
    public let albumCount: Int
    public let genre: String?
    public let addedAt: Date?
    public let updatedAt: Date?
}

/// An album in a Plex music library
public struct PlexAlbum: Identifiable, Equatable {
    public let id: String              // ratingKey
    public let key: String             // API path for tracks
    public let title: String
    public let parentTitle: String?    // Artist name
    public let parentKey: String?      // Artist key
    public let summary: String?
    public let year: Int?
    public let thumb: String?          // Album art path
    public let trackCount: Int
    public let duration: Int?          // Total duration in milliseconds
    public let genre: String?
    public let studio: String?         // Record label
    public let addedAt: Date?
    public let originallyAvailableAt: Date?
    
    public var formattedDuration: String {
        guard let duration = duration else { return "" }
        let seconds = duration / 1000
        let minutes = seconds / 60
        let hours = minutes / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes % 60, seconds % 60)
        }
        return String(format: "%d:%02d", minutes, seconds % 60)
    }
}

/// A track in a Plex music library
public struct PlexTrack: Identifiable, Equatable {
    public let id: String              // ratingKey
    public let key: String             // API path
    public let title: String
    public let parentTitle: String?    // Album name
    public let grandparentTitle: String?  // Artist name
    public let parentKey: String?      // Album key
    public let grandparentKey: String? // Artist key
    public let summary: String?
    public let duration: Int           // Duration in milliseconds
    public let index: Int?             // Track number
    public let parentIndex: Int?       // Disc number
    public let thumb: String?          // Album art (inherited)
    public let media: [PlexMedia]      // Media files/parts
    public let addedAt: Date?
    public let updatedAt: Date?
    public let genre: String?          // Primary genre tag
    public let parentYear: Int?        // Album release year
    public let ratingCount: Int?       // Last.fm scrobble count (global popularity)
    public let userRating: Double?     // User's star rating (0-10 scale, 10 = 5 stars)
    
    /// Get the streaming part key for this track
    public var partKey: String? {
        media.first?.parts.first?.key
    }
    
    public var formattedDuration: String {
        let seconds = duration / 1000
        let minutes = seconds / 60
        return String(format: "%d:%02d", minutes, seconds % 60)
    }
    
    public var durationInSeconds: TimeInterval {
        TimeInterval(duration) / 1000.0
    }
}

// MARK: - Playlist Models

/// A playlist on a Plex server
public struct PlexPlaylist: Identifiable, Equatable {
    public let id: String              // ratingKey
    public let key: String             // API path for items
    public let title: String
    public let summary: String?
    public let playlistType: String    // "audio", "video", or "photo"
    public let smart: Bool             // Whether it's a smart playlist
    public let thumb: String?          // Playlist artwork
    public let composite: String?      // Composite image path
    public let duration: Int?          // Total duration in milliseconds
    public let leafCount: Int          // Number of items
    public let addedAt: Date?
    public let updatedAt: Date?
    
    public var isAudioPlaylist: Bool {
        playlistType == "audio"
    }
    
    public var isVideoPlaylist: Bool {
        playlistType == "video"
    }
    
    public var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let seconds = duration / 1000
        let minutes = seconds / 60
        let hours = minutes / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes % 60, seconds % 60)
        }
        return String(format: "%d:%02d", minutes, seconds % 60)
    }
}

// MARK: - Video Models

/// A movie in a Plex movie library
public struct PlexMovie: Identifiable, Equatable {
    public let id: String              // ratingKey
    public let key: String             // API path
    public let title: String
    public let year: Int?
    public let summary: String?
    public let duration: Int?          // Duration in milliseconds
    public let thumb: String?          // Poster art path
    public let art: String?            // Background art path
    public let contentRating: String?  // MPAA rating (PG, R, etc.)
    public let studio: String?
    public let media: [PlexMedia]
    public let addedAt: Date?
    public let originallyAvailableAt: Date?
    public let imdbId: String?         // IMDB ID (e.g., "tt1234567")
    public let tmdbId: String?         // TMDB ID
    
    /// Get the streaming part key for this movie (uses the longest/primary media)
    public var partKey: String? {
        primaryMedia?.parts.first?.key
    }
    
    /// Get the primary media (longest duration - the main movie, not bonus content)
    public var primaryMedia: PlexMedia? {
        media.max(by: { ($0.duration ?? 0) < ($1.duration ?? 0) })
    }
    
    public var formattedDuration: String {
        guard let duration = duration else { return "" }
        let seconds = duration / 1000
        let minutes = seconds / 60
        let hours = minutes / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes % 60, seconds % 60)
        }
        return String(format: "%d:%02d", minutes, seconds % 60)
    }
    
    public var durationInSeconds: TimeInterval {
        guard let duration = duration else { return 0 }
        return TimeInterval(duration) / 1000.0
    }
    
    /// URL to the IMDB page for this movie (direct link if ID available, otherwise search)
    public var imdbURL: URL? {
        if let imdbId = imdbId {
            return URL(string: "https://www.imdb.com/title/\(imdbId)/")
        }
        // Fall back to search
        let searchQuery = year != nil ? "\(title) (\(year!))" : title
        guard let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://www.imdb.com/find/?q=\(encoded)&s=tt&ttype=ft")
    }
    
    /// URL to the TMDB page for this movie (direct link if ID available, otherwise search)
    public var tmdbURL: URL? {
        if let tmdbId = tmdbId {
            return URL(string: "https://www.themoviedb.org/movie/\(tmdbId)")
        }
        // Fall back to search
        let searchQuery = year != nil ? "\(title) (\(year!))" : title
        guard let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://www.themoviedb.org/search?query=\(encoded)")
    }
    
    /// URL to search for this movie on Rotten Tomatoes
    public var rottenTomatoesSearchURL: URL? {
        let searchQuery = year != nil ? "\(title) (\(year!))" : title
        guard let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://www.rottentomatoes.com/search?search=\(encoded)")
    }
}

/// A TV show in a Plex show library
public struct PlexShow: Identifiable, Equatable {
    public let id: String              // ratingKey
    public let key: String             // API path for children (seasons)
    public let title: String
    public let year: Int?
    public let summary: String?
    public let thumb: String?          // Poster art path
    public let art: String?            // Background art path
    public let contentRating: String?  // TV rating (TV-MA, etc.)
    public let studio: String?
    public let childCount: Int         // Number of seasons
    public let leafCount: Int          // Total number of episodes
    public let addedAt: Date?
    public let imdbId: String?         // IMDB ID (e.g., "tt1234567")
    public let tmdbId: String?         // TMDB ID
    public let tvdbId: String?         // TVDB ID
    
    /// URL to the IMDB page for this show (direct link if ID available, otherwise search)
    public var imdbURL: URL? {
        if let imdbId = imdbId {
            return URL(string: "https://www.imdb.com/title/\(imdbId)/")
        }
        // Fall back to search
        let searchQuery = year != nil ? "\(title) (\(year!))" : title
        guard let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://www.imdb.com/find/?q=\(encoded)&s=tt&ttype=tv")
    }
    
    /// URL to the TMDB page for this show (direct link if ID available, otherwise search)
    public var tmdbURL: URL? {
        if let tmdbId = tmdbId {
            return URL(string: "https://www.themoviedb.org/tv/\(tmdbId)")
        }
        // Fall back to search
        let searchQuery = year != nil ? "\(title) (\(year!))" : title
        guard let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://www.themoviedb.org/search/tv?query=\(encoded)")
    }
    
    /// URL to search for this show on Rotten Tomatoes
    public var rottenTomatoesSearchURL: URL? {
        let searchQuery = year != nil ? "\(title) (\(year!))" : title
        guard let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://www.rottentomatoes.com/search?search=\(encoded)")
    }
}

/// A season of a TV show
public struct PlexSeason: Identifiable, Equatable {
    public let id: String              // ratingKey
    public let key: String             // API path for children (episodes)
    public let title: String           // Usually "Season X"
    public let index: Int              // Season number
    public let parentTitle: String?    // Show name
    public let parentKey: String?      // Show key
    public let thumb: String?
    public let leafCount: Int          // Number of episodes in this season
    public let addedAt: Date?
}

/// An episode of a TV show
public struct PlexEpisode: Identifiable, Equatable {
    public let id: String              // ratingKey
    public let key: String             // API path
    public let title: String
    public let index: Int              // Episode number
    public let parentIndex: Int        // Season number
    public let parentTitle: String?    // Season name
    public let grandparentTitle: String? // Show name
    public let grandparentKey: String? // Show key
    public let summary: String?
    public let duration: Int?          // Duration in milliseconds
    public let thumb: String?          // Episode thumbnail
    public let media: [PlexMedia]
    public let addedAt: Date?
    public let originallyAvailableAt: Date?
    public let imdbId: String?         // IMDB ID (e.g., "tt1234567")
    public let tmdbId: String?         // TMDB ID
    public let tvdbId: String?         // TVDB ID
    
    /// Get the streaming part key for this episode
    public var partKey: String? {
        media.first?.parts.first?.key
    }
    
    public var formattedDuration: String {
        guard let duration = duration else { return "" }
        let seconds = duration / 1000
        let minutes = seconds / 60
        let hours = minutes / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes % 60, seconds % 60)
        }
        return String(format: "%d:%02d", minutes, seconds % 60)
    }
    
    /// URL to the IMDB page for this episode (direct link if ID available, otherwise search for show)
    public var imdbURL: URL? {
        if let imdbId = imdbId {
            return URL(string: "https://www.imdb.com/title/\(imdbId)/")
        }
        // Fall back to searching for the show
        let searchQuery = grandparentTitle ?? title
        guard let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://www.imdb.com/find/?q=\(encoded)&s=tt&ttype=tv")
    }
    
    /// URL to search for this episode on TMDB
    public var tmdbSearchURL: URL? {
        // Search for the show name
        let searchQuery = grandparentTitle ?? title
        guard let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://www.themoviedb.org/search/tv?query=\(encoded)")
    }
    
    /// URL to search for this episode on Rotten Tomatoes
    public var rottenTomatoesSearchURL: URL? {
        // Search for the show name
        let searchQuery = grandparentTitle ?? title
        guard let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://www.rottentomatoes.com/search?search=\(encoded)")
    }
    
    public var durationInSeconds: TimeInterval {
        guard let duration = duration else { return 0 }
        return TimeInterval(duration) / 1000.0
    }
    
    /// Formatted episode identifier (e.g., "S01E05")
    public var episodeIdentifier: String {
        String(format: "S%02dE%02d", parentIndex, index)
    }
}

// MARK: - Hubs (Related Content)

/// A content hub containing related/similar items (for radio/mix generation)
public struct PlexHub: Identifiable {
    public let id: String
    public let type: String                // "artist", "album", "track"
    public let hubIdentifier: String       // "track.similar", "artist.similar", etc.
    public let title: String
    public let size: Int
    public let items: [PlexMetadataDTO]    // Raw metadata for flexibility
    
    /// Check if this hub contains similar/related content
    public var isSimilarContent: Bool {
        hubIdentifier.contains("similar") || hubIdentifier.contains("related")
    }
}

// MARK: - Media Info

/// Media info for a Plex item
public struct PlexMedia: Codable, Equatable {
    public let id: Int
    public let duration: Int?
    public let bitrate: Int?
    public let audioChannels: Int?
    public let audioCodec: String?
    public let videoCodec: String?
    public let videoResolution: String?
    public let width: Int?
    public let height: Int?
    public let container: String?
    public let parts: [PlexPart]
}

/// A media part (actual file) for streaming
public struct PlexPart: Codable, Equatable {
    public let id: Int
    public let key: String             // The streaming path
    public let duration: Int?
    public let file: String?           // Original file path on server
    public let size: Int64?
    public let container: String?
    public let audioProfile: String?
    public let streams: [PlexStream]   // Audio, video, and subtitle streams
}

// MARK: - Stream Info

/// Stream type enumeration for Plex media streams
public enum PlexStreamType: Int, Codable, Equatable {
    case video = 1
    case audio = 2
    case subtitle = 3
    
    public var displayName: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        case .subtitle: return "Subtitle"
        }
    }
}

/// A media stream (video, audio, or subtitle track) within a Plex media part
public struct PlexStream: Codable, Equatable, Identifiable {
    public let id: Int
    public let streamType: PlexStreamType  // 1=video, 2=audio, 3=subtitle
    public let index: Int?                  // Stream index in container
    public let codec: String?               // e.g., "aac", "ac3", "srt", "ass"
    public let language: String?            // ISO language code (e.g., "en", "es")
    public let languageTag: String?         // Full language tag (e.g., "en-US")
    public let languageCode: String?        // Three-letter code (e.g., "eng")
    public let displayTitle: String?        // Human-readable title (e.g., "English (AC3 5.1)")
    public let extendedDisplayTitle: String? // Extended title with more details
    public let title: String?               // Custom track title
    public let selected: Bool               // Whether this is the default/selected track
    public let `default`: Bool?             // Whether this is marked as default in the file
    public let forced: Bool?                // Whether this is a forced subtitle track
    public let hearingImpaired: Bool?       // Whether this is for hearing impaired (SDH)
    public let key: String?                 // URL path for external subtitles
    
    // Audio-specific properties
    public let channels: Int?               // Number of audio channels
    public let channelLayout: String?       // e.g., "5.1", "stereo"
    public let bitrate: Int?                // Audio bitrate
    public let samplingRate: Int?           // Audio sample rate
    public let bitDepth: Int?               // Audio bit depth
    
    // Video-specific properties
    public let width: Int?
    public let height: Int?
    public let frameRate: Double?
    public let profile: String?             // e.g., "main", "high"
    public let level: Int?
    public let colorSpace: String?
    
    // Subtitle-specific properties
    public let format: String?              // Subtitle format (e.g., "srt", "ass", "pgs")
    
    /// Whether this is an external subtitle (has a download URL)
    public var isExternal: Bool {
        key != nil && streamType == .subtitle
    }
    
    /// User-friendly display name for the stream
    public var localizedDisplayTitle: String {
        if let displayTitle = displayTitle, !displayTitle.isEmpty {
            return displayTitle
        }
        
        var parts: [String] = []
        
        // Add language if available
        if let lang = language ?? languageCode {
            let locale = Locale(identifier: lang)
            if let languageName = Locale.current.localizedString(forLanguageCode: lang) {
                parts.append(languageName)
            } else {
                parts.append(lang.uppercased())
            }
        } else {
            parts.append("Unknown")
        }
        
        // Add codec/format info
        if let codec = codec?.uppercased() {
            if streamType == .audio {
                if let channels = channels {
                    let channelDesc = channels == 2 ? "Stereo" : "\(channels)ch"
                    parts.append("(\(codec) \(channelDesc))")
                } else {
                    parts.append("(\(codec))")
                }
            } else {
                parts.append("(\(codec))")
            }
        }
        
        // Add SDH/Forced indicators for subtitles
        if streamType == .subtitle {
            if hearingImpaired == true {
                parts.append("[SDH]")
            }
            if forced == true {
                parts.append("[Forced]")
            }
        }
        
        return parts.joined(separator: " ")
    }
}

// MARK: - API Response Containers

/// Generic container for Plex API responses
public struct PlexMediaContainer<T: Decodable>: Decodable {
    public let size: Int?
    public let totalSize: Int?
    public let offset: Int?
    public let allowSync: Bool?
    public let identifier: String?
    public let mediaTagPrefix: String?
    public let mediaTagVersion: Int?
    public let title1: String?
    public let title2: String?
    public let items: T
    
    enum CodingKeys: String, CodingKey {
        case size, totalSize, offset, allowSync, identifier
        case mediaTagPrefix, mediaTagVersion, title1, title2
        // Items will be decoded separately based on context
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        totalSize = try container.decodeIfPresent(Int.self, forKey: .totalSize)
        offset = try container.decodeIfPresent(Int.self, forKey: .offset)
        allowSync = try container.decodeIfPresent(Bool.self, forKey: .allowSync)
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        mediaTagPrefix = try container.decodeIfPresent(String.self, forKey: .mediaTagPrefix)
        mediaTagVersion = try container.decodeIfPresent(Int.self, forKey: .mediaTagVersion)
        title1 = try container.decodeIfPresent(String.self, forKey: .title1)
        title2 = try container.decodeIfPresent(String.self, forKey: .title2)
        items = try T(from: decoder)
    }
}

/// Response wrapper for Plex API
public struct PlexResponse<T: Decodable>: Decodable {
    public let mediaContainer: T
    
    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

// MARK: - API Response Structs

public struct PlexLibrariesResponse: Decodable {
    public let size: Int?
    public let directories: [PlexLibraryDTO]?
    
    enum CodingKeys: String, CodingKey {
        case size
        case directories = "Directory"
    }
}

public struct PlexLibraryDTO: Decodable {
    public let key: String
    public let uuid: String?
    public let title: String
    public let type: String
    public let agent: String?
    public let scanner: String?
    public let language: String?
    public let refreshing: Bool?
    
    public func toLibrary() -> PlexLibrary {
        PlexLibrary(
            id: key,
            uuid: uuid,
            title: title,
            type: type,
            agent: agent,
            scanner: scanner,
            language: language,
            refreshing: refreshing ?? false,
            contentCount: nil
        )
    }
}

public struct PlexMetadataResponse: Decodable {
    public let size: Int?
    public let totalSize: Int?
    public let offset: Int?
    public let metadata: [PlexMetadataDTO]?
    
    enum CodingKeys: String, CodingKey {
        case size, totalSize, offset
        case metadata = "Metadata"
    }
}

public struct PlexMetadataDTO: Decodable {
    public let ratingKey: String
    public let key: String
    public let type: String
    public let title: String
    public let parentTitle: String?
    public let grandparentTitle: String?
    public let parentKey: String?
    public let grandparentKey: String?
    public let summary: String?
    public let index: Int?
    public let parentIndex: Int?
    public let year: Int?
    public let thumb: String?
    public let art: String?
    public let duration: Int?
    public let addedAt: Int?
    public let updatedAt: Int?
    public let originallyAvailableAt: String?
    public let leafCount: Int?         // Track count for albums/artists, episode count for shows/seasons
    public let childCount: Int?        // Album count for artists, season count for shows
    public let albumCount: Int?        // Some Plex servers return albumCount directly for artists
    public let media: [PlexMediaDTO]?
    public let genre: [PlexTagDTO]?
    public let studio: String?
    public let contentRating: String?  // MPAA/TV rating
    // Playlist-specific fields
    public let playlistType: String?   // "audio", "video", or "photo"
    public let smart: Bool?            // Whether it's a smart playlist
    public let composite: String?      // Composite image path for playlists
    // Track-specific fields for radio
    public let parentYear: Int?        // Album release year (for decade radio)
    public let ratingCount: Int?       // Last.fm scrobble count (for hits/deep cuts)
    public let userRating: Double?     // User's star rating (0-10 scale, 10 = 5 stars)
    // Extra/bonus content identification
    public let extraType: Int?         // Non-nil means this is an extra (trailer, deleted scene, etc.)
    public let subtype: String?        // Additional type info (e.g., "trailer", "clip")
    // External IDs (IMDB, TMDB, TVDB)
    public let guids: [PlexGuidDTO]?   // External ID references
    
    /// Returns true if this item is an extra/bonus content (not the main movie/episode)
    public var isExtra: Bool {
        extraType != nil || subtype != nil
    }
    
    /// Extract IMDB ID from guids array
    public var imdbId: String? {
        guids?.compactMap { $0.imdbId }.first
    }
    
    /// Extract TMDB ID from guids array
    public var tmdbId: String? {
        guids?.compactMap { $0.tmdbId }.first
    }
    
    /// Extract TVDB ID from guids array
    public var tvdbId: String? {
        guids?.compactMap { $0.tvdbId }.first
    }
    
    enum CodingKeys: String, CodingKey {
        case ratingKey, key, type, title, parentTitle, grandparentTitle
        case parentKey, grandparentKey, summary, index, parentIndex
        case year, thumb, art, duration, addedAt, updatedAt
        case originallyAvailableAt, leafCount, childCount, albumCount
        case media = "Media"
        case genre = "Genre"
        case studio, contentRating
        case playlistType, smart, composite
        case parentYear, ratingCount, userRating
        case extraType, subtype
        case guids = "Guid"
    }
    
    public func toArtist() -> PlexArtist {
        // Use childCount, albumCount, or leafCount (some servers use different fields)
        let albumCountValue = childCount ?? albumCount ?? 0
        
        return PlexArtist(
            id: ratingKey,
            key: key,
            title: title,
            summary: summary,
            thumb: thumb,
            art: art,
            albumCount: albumCountValue,
            genre: genre?.first?.tag,
            addedAt: addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            updatedAt: updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
    
    public func toAlbum() -> PlexAlbum {
        PlexAlbum(
            id: ratingKey,
            key: key,
            title: title,
            parentTitle: parentTitle,
            parentKey: parentKey,
            summary: summary,
            year: year,
            thumb: thumb,
            trackCount: leafCount ?? 0,
            duration: duration,
            genre: genre?.first?.tag,
            studio: studio,
            addedAt: addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            originallyAvailableAt: nil
        )
    }
    
    public func toTrack() -> PlexTrack {
        PlexTrack(
            id: ratingKey,
            key: key,
            title: title,
            parentTitle: parentTitle,
            grandparentTitle: grandparentTitle,
            parentKey: parentKey,
            grandparentKey: grandparentKey,
            summary: summary,
            duration: duration ?? 0,
            index: index,
            parentIndex: parentIndex,
            thumb: thumb,
            media: media?.map { $0.toMedia() } ?? [],
            addedAt: addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            updatedAt: updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            genre: genre?.first?.tag,
            parentYear: parentYear,
            ratingCount: ratingCount,
            userRating: userRating
        )
    }
    
    public func toMovie() -> PlexMovie {
        var releaseDate: Date? = nil
        if let dateStr = originallyAvailableAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            releaseDate = formatter.date(from: dateStr)
        }
        
        // Use the longest duration from all media entries (main movie, not bonus content)
        // The top-level duration field may point to a bonus/extra file
        let primaryDuration: Int?
        if let mediaList = media, !mediaList.isEmpty {
            primaryDuration = mediaList.compactMap { $0.duration }.max()
        } else {
            primaryDuration = duration
        }
        
        return PlexMovie(
            id: ratingKey,
            key: key,
            title: title,
            year: year,
            summary: summary,
            duration: primaryDuration,
            thumb: thumb,
            art: art,
            contentRating: contentRating,
            studio: studio,
            media: media?.map { $0.toMedia() } ?? [],
            addedAt: addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            originallyAvailableAt: releaseDate,
            imdbId: imdbId,
            tmdbId: tmdbId
        )
    }
    
    public func toShow() -> PlexShow {
        PlexShow(
            id: ratingKey,
            key: key,
            title: title,
            year: year,
            summary: summary,
            thumb: thumb,
            art: art,
            contentRating: contentRating,
            studio: studio,
            childCount: childCount ?? 0,
            leafCount: leafCount ?? 0,
            addedAt: addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            imdbId: imdbId,
            tmdbId: tmdbId,
            tvdbId: tvdbId
        )
    }
    
    public func toSeason() -> PlexSeason {
        PlexSeason(
            id: ratingKey,
            key: key,
            title: title,
            index: index ?? 0,
            parentTitle: parentTitle,
            parentKey: parentKey,
            thumb: thumb,
            leafCount: leafCount ?? 0,
            addedAt: addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
    
    public func toEpisode() -> PlexEpisode {
        var airDate: Date? = nil
        if let dateStr = originallyAvailableAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            airDate = formatter.date(from: dateStr)
        }
        
        return PlexEpisode(
            id: ratingKey,
            key: key,
            title: title,
            index: index ?? 0,
            parentIndex: parentIndex ?? 0,
            parentTitle: parentTitle,
            grandparentTitle: grandparentTitle,
            grandparentKey: grandparentKey,
            summary: summary,
            duration: duration,
            thumb: thumb,
            media: media?.map { $0.toMedia() } ?? [],
            addedAt: addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            originallyAvailableAt: airDate,
            imdbId: imdbId,
            tmdbId: tmdbId,
            tvdbId: tvdbId
        )
    }
    
    public func toPlaylist() -> PlexPlaylist {
        PlexPlaylist(
            id: ratingKey,
            key: key,
            title: title,
            summary: summary,
            playlistType: playlistType ?? "audio",
            smart: smart ?? false,
            thumb: thumb,
            composite: composite,
            duration: duration,
            leafCount: leafCount ?? 0,
            addedAt: addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            updatedAt: updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}

public struct PlexMediaDTO: Decodable {
    public let id: Int
    public let duration: Int?
    public let bitrate: Int?
    public let audioChannels: Int?
    public let audioCodec: String?
    public let videoCodec: String?
    public let videoResolution: String?
    public let width: Int?
    public let height: Int?
    public let container: String?
    public let parts: [PlexPartDTO]?
    
    enum CodingKeys: String, CodingKey {
        case id, duration, bitrate, audioChannels, audioCodec
        case videoCodec, videoResolution, width, height, container
        case parts = "Part"
    }
    
    public func toMedia() -> PlexMedia {
        PlexMedia(
            id: id,
            duration: duration,
            bitrate: bitrate,
            audioChannels: audioChannels,
            audioCodec: audioCodec,
            videoCodec: videoCodec,
            videoResolution: videoResolution,
            width: width,
            height: height,
            container: container,
            parts: parts?.map { $0.toPart() } ?? []
        )
    }
}

public struct PlexPartDTO: Decodable {
    public let id: Int
    public let key: String
    public let duration: Int?
    public let file: String?
    public let size: Int64?
    public let container: String?
    public let audioProfile: String?
    public let streams: [PlexStreamDTO]?
    
    enum CodingKeys: String, CodingKey {
        case id, key, duration, file, size, container, audioProfile
        case streams = "Stream"
    }
    
    public func toPart() -> PlexPart {
        PlexPart(
            id: id,
            key: key,
            duration: duration,
            file: file,
            size: size,
            container: container,
            audioProfile: audioProfile,
            streams: streams?.map { $0.toStream() } ?? []
        )
    }
}

public struct PlexStreamDTO: Decodable {
    public let id: Int
    public let streamType: Int
    public let index: Int?
    public let codec: String?
    public let language: String?
    public let languageTag: String?
    public let languageCode: String?
    public let displayTitle: String?
    public let extendedDisplayTitle: String?
    public let title: String?
    public let selected: Bool?
    public let `default`: Bool?
    public let forced: Bool?
    public let hearingImpaired: Bool?
    public let key: String?
    
    // Audio-specific
    public let channels: Int?
    public let channelLayout: String?
    public let bitrate: Int?
    public let samplingRate: Int?
    public let bitDepth: Int?
    
    // Video-specific
    public let width: Int?
    public let height: Int?
    public let frameRate: FlexibleString?  // Plex returns this as either string or number
    public let profile: String?
    public let level: Int?
    public let colorSpace: String?
    
    // Subtitle-specific
    public let format: String?
    
    public func toStream() -> PlexStream {
        PlexStream(
            id: id,
            streamType: PlexStreamType(rawValue: streamType) ?? .video,
            index: index,
            codec: codec,
            language: language,
            languageTag: languageTag,
            languageCode: languageCode,
            displayTitle: displayTitle,
            extendedDisplayTitle: extendedDisplayTitle,
            title: title,
            selected: selected ?? false,
            default: `default`,
            forced: forced,
            hearingImpaired: hearingImpaired,
            key: key,
            channels: channels,
            channelLayout: channelLayout,
            bitrate: bitrate,
            samplingRate: samplingRate,
            bitDepth: bitDepth,
            width: width,
            height: height,
            frameRate: frameRate.flatMap { Double($0.value) },
            profile: profile,
            level: level,
            colorSpace: colorSpace,
            format: format
        )
    }
}

public struct PlexTagDTO: Decodable {
    public let tag: String
}

/// External ID reference (IMDB, TMDB, TVDB, etc.)
public struct PlexGuidDTO: Decodable {
    public let id: String
    
    /// Extract the IMDB ID if this is an IMDB guid
    public var imdbId: String? {
        guard id.hasPrefix("imdb://") else { return nil }
        return String(id.dropFirst("imdb://".count))
    }
    
    /// Extract the TMDB ID if this is a TMDB guid
    public var tmdbId: String? {
        guard id.hasPrefix("tmdb://") else { return nil }
        return String(id.dropFirst("tmdb://".count))
    }
    
    /// Extract the TVDB ID if this is a TVDB guid
    public var tvdbId: String? {
        guard id.hasPrefix("tvdb://") else { return nil }
        return String(id.dropFirst("tvdb://".count))
    }
}

// MARK: - Genre Response DTOs

/// Response container for genre endpoints
public struct PlexGenreResponse: Decodable {
    public let size: Int?
    public let directory: [PlexGenreDTO]?
    
    enum CodingKeys: String, CodingKey {
        case size
        case directory = "Directory"
    }
}

/// A genre entry from the library
public struct PlexGenreDTO: Decodable {
    public let key: String
    public let title: String
}

// MARK: - Hub Response DTOs

/// Response container for hub endpoints
public struct PlexHubsResponse: Decodable {
    public let hubs: [PlexHubDTO]?
    
    enum CodingKeys: String, CodingKey {
        case hubs = "Hub"
    }
}

/// A hub containing related content
public struct PlexHubDTO: Decodable {
    public let hubKey: String?
    public let key: String?
    public let type: String
    public let hubIdentifier: String
    public let title: String
    public let size: Int?
    public let more: Bool?
    public let style: String?
    public let promoted: Bool?
    public let metadata: [PlexMetadataDTO]?
    
    enum CodingKeys: String, CodingKey {
        case hubKey, key, type, hubIdentifier, title, size, more, style, promoted
        case metadata = "Metadata"
    }
    
    public func toHub() -> PlexHub {
        PlexHub(
            id: hubKey ?? hubIdentifier,
            type: type,
            hubIdentifier: hubIdentifier,
            title: title,
            size: size ?? metadata?.count ?? 0,
            items: metadata ?? []
        )
    }
}

// MARK: - Resources/Servers Response

public struct PlexResourcesResponse: Decodable {
    public let resources: [PlexResourceDTO]
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        resources = try container.decode([PlexResourceDTO].self)
    }
}

public struct PlexResourceDTO: Decodable {
    public let name: String
    public let product: String?
    public let productVersion: String?
    public let platform: String?
    public let platformVersion: String?
    public let device: String?
    public let clientIdentifier: String
    public let createdAt: String?
    public let lastSeenAt: String?
    public let provides: String?
    public let owned: Bool?
    public let accessToken: String?
    public let publicAddress: String?
    public let httpsRequired: Bool?
    public let connections: [PlexConnectionDTO]?
    
    public func toServer() -> PlexServer? {
        // Only return servers that provide "server" capability
        guard provides?.contains("server") == true else { return nil }
        
        return PlexServer(
            id: clientIdentifier,
            name: name,
            product: product,
            productVersion: productVersion,
            platform: platform,
            platformVersion: platformVersion,
            device: device,
            owned: owned ?? false,
            connections: connections?.map { $0.toConnection() } ?? [],
            accessToken: accessToken
        )
    }
}

public struct PlexConnectionDTO: Decodable {
    public let uri: String
    public let local: Bool?
    public let relay: Bool?
    public let address: String?
    public let port: Int?
    public let `protocol`: String?
    
    public func toConnection() -> PlexConnection {
        PlexConnection(
            uri: uri,
            local: local ?? false,
            relay: relay ?? false,
            address: address,
            port: port,
            protocol: `protocol`
        )
    }
}

// MARK: - User Response

public struct PlexUserResponse: Decodable {
    public let id: Int
    public let uuid: String
    public let username: String
    public let email: String?
    public let thumb: String?
    public let authToken: String
    public let title: String?
    
    public func toAccount() -> PlexAccount {
        PlexAccount(
            id: id,
            uuid: uuid,
            username: username,
            email: email,
            thumb: thumb,
            authToken: authToken,
            title: title
        )
    }
}

// MARK: - PIN Response

public struct PlexPINResponse: Decodable {
    public let id: Int
    public let code: String
    public let authToken: String?
    public let expiresAt: String?
    public let trusted: Bool?
    public let clientIdentifier: String?
    
    public func toPIN() -> PlexPIN {
        var expiresDate: Date? = nil
        if let expiresAt = expiresAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            expiresDate = formatter.date(from: expiresAt)
            if expiresDate == nil {
                // Try without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                expiresDate = formatter.date(from: expiresAt)
            }
        }
        
        return PlexPIN(
            id: id,
            code: code,
            authToken: authToken,
            expiresAt: expiresDate,
            trusted: trusted,
            clientIdentifier: clientIdentifier
        )
    }
}
