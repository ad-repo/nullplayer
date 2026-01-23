import Foundation

// MARK: - Plex Account & Authentication

/// Plex account info obtained via PIN authentication
struct PlexAccount: Codable, Equatable {
    let id: Int
    let uuid: String
    let username: String
    let email: String?
    let thumb: String?          // Avatar URL
    let authToken: String
    let title: String?          // Display name
    
    enum CodingKeys: String, CodingKey {
        case id, uuid, username, email, thumb, title
        case authToken = "authToken"
    }
}

/// PIN for device linking flow
struct PlexPIN: Codable {
    let id: Int
    let code: String            // 4-character code shown to user
    let authToken: String?      // Populated once user authorizes
    let expiresAt: Date?
    let trusted: Bool?
    let clientIdentifier: String?
    
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
}

// MARK: - Plex Server & Connections

/// A Plex server discovered from the account
struct PlexServer: Codable, Identifiable, Equatable {
    let id: String              // clientIdentifier
    let name: String
    let product: String?
    let productVersion: String?
    let platform: String?
    let platformVersion: String?
    let device: String?
    let owned: Bool
    let connections: [PlexConnection]
    let accessToken: String?    // Server-specific token
    
    /// Best available connection (prefers local)
    var preferredConnection: PlexConnection? {
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
struct PlexConnection: Codable, Equatable {
    let uri: String             // Full URL e.g., "http://192.168.1.100:32400"
    let local: Bool             // true if on same network
    let relay: Bool             // true if using Plex relay
    let address: String?
    let port: Int?
    let `protocol`: String?
    
    var url: URL? {
        URL(string: uri)
    }
}

// MARK: - Plex Library Content

/// A library on a Plex server
struct PlexLibrary: Identifiable, Equatable {
    let id: String              // Section key/ID
    let uuid: String?
    let title: String
    let type: String            // "artist" for music, "movie" for movies, "show" for TV
    let agent: String?
    let scanner: String?
    let language: String?
    let refreshing: Bool
    let contentCount: Int?
    
    var isMusicLibrary: Bool {
        type == "artist"
    }
    
    var isMovieLibrary: Bool {
        type == "movie"
    }
    
    var isShowLibrary: Bool {
        type == "show"
    }
    
    var isVideoLibrary: Bool {
        isMovieLibrary || isShowLibrary
    }
}

/// An artist in a Plex music library
struct PlexArtist: Identifiable, Equatable {
    let id: String              // ratingKey
    let key: String             // API path for children
    let title: String
    let summary: String?
    let thumb: String?          // Artwork path
    let art: String?            // Background art path
    let albumCount: Int
    let genre: String?
    let addedAt: Date?
    let updatedAt: Date?
}

/// An album in a Plex music library
struct PlexAlbum: Identifiable, Equatable {
    let id: String              // ratingKey
    let key: String             // API path for tracks
    let title: String
    let parentTitle: String?    // Artist name
    let parentKey: String?      // Artist key
    let summary: String?
    let year: Int?
    let thumb: String?          // Album art path
    let trackCount: Int
    let duration: Int?          // Total duration in milliseconds
    let genre: String?
    let studio: String?         // Record label
    let addedAt: Date?
    let originallyAvailableAt: Date?
    
    var formattedDuration: String {
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
struct PlexTrack: Identifiable, Equatable {
    let id: String              // ratingKey
    let key: String             // API path
    let title: String
    let parentTitle: String?    // Album name
    let grandparentTitle: String?  // Artist name
    let parentKey: String?      // Album key
    let grandparentKey: String? // Artist key
    let summary: String?
    let duration: Int           // Duration in milliseconds
    let index: Int?             // Track number
    let parentIndex: Int?       // Disc number
    let thumb: String?          // Album art (inherited)
    let media: [PlexMedia]      // Media files/parts
    let addedAt: Date?
    let updatedAt: Date?
    
    /// Get the streaming part key for this track
    var partKey: String? {
        media.first?.parts.first?.key
    }
    
    var formattedDuration: String {
        let seconds = duration / 1000
        let minutes = seconds / 60
        return String(format: "%d:%02d", minutes, seconds % 60)
    }
    
    var durationInSeconds: TimeInterval {
        TimeInterval(duration) / 1000.0
    }
}

// MARK: - Playlist Models

/// A playlist on a Plex server
struct PlexPlaylist: Identifiable, Equatable {
    let id: String              // ratingKey
    let key: String             // API path for items
    let title: String
    let summary: String?
    let playlistType: String    // "audio", "video", or "photo"
    let smart: Bool             // Whether it's a smart playlist
    let thumb: String?          // Playlist artwork
    let composite: String?      // Composite image path
    let duration: Int?          // Total duration in milliseconds
    let leafCount: Int          // Number of items
    let addedAt: Date?
    let updatedAt: Date?
    
    var isAudioPlaylist: Bool {
        playlistType == "audio"
    }
    
    var isVideoPlaylist: Bool {
        playlistType == "video"
    }
    
    var formattedDuration: String? {
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
struct PlexMovie: Identifiable, Equatable {
    let id: String              // ratingKey
    let key: String             // API path
    let title: String
    let year: Int?
    let summary: String?
    let duration: Int?          // Duration in milliseconds
    let thumb: String?          // Poster art path
    let art: String?            // Background art path
    let contentRating: String?  // MPAA rating (PG, R, etc.)
    let studio: String?
    let media: [PlexMedia]
    let addedAt: Date?
    let originallyAvailableAt: Date?
    
    /// Get the streaming part key for this movie
    var partKey: String? {
        media.first?.parts.first?.key
    }
    
    var formattedDuration: String {
        guard let duration = duration else { return "" }
        let seconds = duration / 1000
        let minutes = seconds / 60
        let hours = minutes / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes % 60, seconds % 60)
        }
        return String(format: "%d:%02d", minutes, seconds % 60)
    }
    
    var durationInSeconds: TimeInterval {
        guard let duration = duration else { return 0 }
        return TimeInterval(duration) / 1000.0
    }
}

/// A TV show in a Plex show library
struct PlexShow: Identifiable, Equatable {
    let id: String              // ratingKey
    let key: String             // API path for children (seasons)
    let title: String
    let year: Int?
    let summary: String?
    let thumb: String?          // Poster art path
    let art: String?            // Background art path
    let contentRating: String?  // TV rating (TV-MA, etc.)
    let studio: String?
    let childCount: Int         // Number of seasons
    let leafCount: Int          // Total number of episodes
    let addedAt: Date?
}

/// A season of a TV show
struct PlexSeason: Identifiable, Equatable {
    let id: String              // ratingKey
    let key: String             // API path for children (episodes)
    let title: String           // Usually "Season X"
    let index: Int              // Season number
    let parentTitle: String?    // Show name
    let parentKey: String?      // Show key
    let thumb: String?
    let leafCount: Int          // Number of episodes in this season
    let addedAt: Date?
}

/// An episode of a TV show
struct PlexEpisode: Identifiable, Equatable {
    let id: String              // ratingKey
    let key: String             // API path
    let title: String
    let index: Int              // Episode number
    let parentIndex: Int        // Season number
    let parentTitle: String?    // Season name
    let grandparentTitle: String? // Show name
    let grandparentKey: String? // Show key
    let summary: String?
    let duration: Int?          // Duration in milliseconds
    let thumb: String?          // Episode thumbnail
    let media: [PlexMedia]
    let addedAt: Date?
    let originallyAvailableAt: Date?
    
    /// Get the streaming part key for this episode
    var partKey: String? {
        media.first?.parts.first?.key
    }
    
    var formattedDuration: String {
        guard let duration = duration else { return "" }
        let seconds = duration / 1000
        let minutes = seconds / 60
        let hours = minutes / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes % 60, seconds % 60)
        }
        return String(format: "%d:%02d", minutes, seconds % 60)
    }
    
    var durationInSeconds: TimeInterval {
        guard let duration = duration else { return 0 }
        return TimeInterval(duration) / 1000.0
    }
    
    /// Formatted episode identifier (e.g., "S01E05")
    var episodeIdentifier: String {
        String(format: "S%02dE%02d", parentIndex, index)
    }
}

// MARK: - Media Info

/// Media info for a Plex item
struct PlexMedia: Codable, Equatable {
    let id: Int
    let duration: Int?
    let bitrate: Int?
    let audioChannels: Int?
    let audioCodec: String?
    let videoCodec: String?
    let videoResolution: String?
    let width: Int?
    let height: Int?
    let container: String?
    let parts: [PlexPart]
}

/// A media part (actual file) for streaming
struct PlexPart: Codable, Equatable {
    let id: Int
    let key: String             // The streaming path
    let duration: Int?
    let file: String?           // Original file path on server
    let size: Int64?
    let container: String?
    let audioProfile: String?
}

// MARK: - API Response Containers

/// Generic container for Plex API responses
struct PlexMediaContainer<T: Decodable>: Decodable {
    let size: Int?
    let totalSize: Int?
    let offset: Int?
    let allowSync: Bool?
    let identifier: String?
    let mediaTagPrefix: String?
    let mediaTagVersion: Int?
    let title1: String?
    let title2: String?
    let items: T
    
    enum CodingKeys: String, CodingKey {
        case size, totalSize, offset, allowSync, identifier
        case mediaTagPrefix, mediaTagVersion, title1, title2
        // Items will be decoded separately based on context
    }
    
    init(from decoder: Decoder) throws {
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
struct PlexResponse<T: Decodable>: Decodable {
    let mediaContainer: T
    
    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

// MARK: - API Response Structs

struct PlexLibrariesResponse: Decodable {
    let size: Int?
    let directories: [PlexLibraryDTO]?
    
    enum CodingKeys: String, CodingKey {
        case size
        case directories = "Directory"
    }
}

struct PlexLibraryDTO: Decodable {
    let key: String
    let uuid: String?
    let title: String
    let type: String
    let agent: String?
    let scanner: String?
    let language: String?
    let refreshing: Bool?
    
    func toLibrary() -> PlexLibrary {
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

struct PlexMetadataResponse: Decodable {
    let size: Int?
    let totalSize: Int?
    let offset: Int?
    let metadata: [PlexMetadataDTO]?
    
    enum CodingKeys: String, CodingKey {
        case size, totalSize, offset
        case metadata = "Metadata"
    }
}

struct PlexMetadataDTO: Decodable {
    let ratingKey: String
    let key: String
    let type: String
    let title: String
    let parentTitle: String?
    let grandparentTitle: String?
    let parentKey: String?
    let grandparentKey: String?
    let summary: String?
    let index: Int?
    let parentIndex: Int?
    let year: Int?
    let thumb: String?
    let art: String?
    let duration: Int?
    let addedAt: Int?
    let updatedAt: Int?
    let originallyAvailableAt: String?
    let leafCount: Int?         // Track count for albums/artists, episode count for shows/seasons
    let childCount: Int?        // Album count for artists, season count for shows
    let albumCount: Int?        // Some Plex servers return albumCount directly for artists
    let media: [PlexMediaDTO]?
    let genre: [PlexTagDTO]?
    let studio: String?
    let contentRating: String?  // MPAA/TV rating
    // Playlist-specific fields
    let playlistType: String?   // "audio", "video", or "photo"
    let smart: Bool?            // Whether it's a smart playlist
    let composite: String?      // Composite image path for playlists
    
    enum CodingKeys: String, CodingKey {
        case ratingKey, key, type, title, parentTitle, grandparentTitle
        case parentKey, grandparentKey, summary, index, parentIndex
        case year, thumb, art, duration, addedAt, updatedAt
        case originallyAvailableAt, leafCount, childCount, albumCount
        case media = "Media"
        case genre = "Genre"
        case studio, contentRating
        case playlistType, smart, composite
    }
    
    func toArtist() -> PlexArtist {
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
    
    func toAlbum() -> PlexAlbum {
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
    
    func toTrack() -> PlexTrack {
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
            updatedAt: updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
    
    func toMovie() -> PlexMovie {
        var releaseDate: Date? = nil
        if let dateStr = originallyAvailableAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            releaseDate = formatter.date(from: dateStr)
        }
        
        return PlexMovie(
            id: ratingKey,
            key: key,
            title: title,
            year: year,
            summary: summary,
            duration: duration,
            thumb: thumb,
            art: art,
            contentRating: contentRating,
            studio: studio,
            media: media?.map { $0.toMedia() } ?? [],
            addedAt: addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            originallyAvailableAt: releaseDate
        )
    }
    
    func toShow() -> PlexShow {
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
            addedAt: addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
    
    func toSeason() -> PlexSeason {
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
    
    func toEpisode() -> PlexEpisode {
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
            originallyAvailableAt: airDate
        )
    }
    
    func toPlaylist() -> PlexPlaylist {
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

struct PlexMediaDTO: Decodable {
    let id: Int
    let duration: Int?
    let bitrate: Int?
    let audioChannels: Int?
    let audioCodec: String?
    let videoCodec: String?
    let videoResolution: String?
    let width: Int?
    let height: Int?
    let container: String?
    let parts: [PlexPartDTO]?
    
    enum CodingKeys: String, CodingKey {
        case id, duration, bitrate, audioChannels, audioCodec
        case videoCodec, videoResolution, width, height, container
        case parts = "Part"
    }
    
    func toMedia() -> PlexMedia {
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

struct PlexPartDTO: Decodable {
    let id: Int
    let key: String
    let duration: Int?
    let file: String?
    let size: Int64?
    let container: String?
    let audioProfile: String?
    
    func toPart() -> PlexPart {
        PlexPart(
            id: id,
            key: key,
            duration: duration,
            file: file,
            size: size,
            container: container,
            audioProfile: audioProfile
        )
    }
}

struct PlexTagDTO: Decodable {
    let tag: String
}

// MARK: - Resources/Servers Response

struct PlexResourcesResponse: Decodable {
    let resources: [PlexResourceDTO]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        resources = try container.decode([PlexResourceDTO].self)
    }
}

struct PlexResourceDTO: Decodable {
    let name: String
    let product: String?
    let productVersion: String?
    let platform: String?
    let platformVersion: String?
    let device: String?
    let clientIdentifier: String
    let createdAt: String?
    let lastSeenAt: String?
    let provides: String?
    let owned: Bool?
    let accessToken: String?
    let publicAddress: String?
    let httpsRequired: Bool?
    let connections: [PlexConnectionDTO]?
    
    func toServer() -> PlexServer? {
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

struct PlexConnectionDTO: Decodable {
    let uri: String
    let local: Bool?
    let relay: Bool?
    let address: String?
    let port: Int?
    let `protocol`: String?
    
    func toConnection() -> PlexConnection {
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

struct PlexUserResponse: Decodable {
    let id: Int
    let uuid: String
    let username: String
    let email: String?
    let thumb: String?
    let authToken: String
    let title: String?
    
    func toAccount() -> PlexAccount {
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

struct PlexPINResponse: Decodable {
    let id: Int
    let code: String
    let authToken: String?
    let expiresAt: String?
    let trusted: Bool?
    let clientIdentifier: String?
    
    func toPIN() -> PlexPIN {
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
