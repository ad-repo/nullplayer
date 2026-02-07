import Foundation

// MARK: - Subsonic Server

/// A Subsonic/Navidrome server connection
public struct SubsonicServer: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let url: String              // Base URL (e.g., "http://localhost:4533")
    public let username: String
    
    /// Display URL without credentials
    public var displayURL: String {
        url
    }
    
    /// Get the base URL for API calls
    public var baseURL: URL? {
        URL(string: url)
    }
}

/// Credentials for a Subsonic server (stored in keychain)
public struct SubsonicServerCredentials: Codable {
    public let id: String
    public let name: String
    public let url: String
    public let username: String
    public let password: String         // Stored encrypted in keychain
}

// MARK: - Library Content

/// An artist in a Subsonic music library
public struct SubsonicArtist: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let albumCount: Int
    public let coverArt: String?        // Cover art ID for artwork URL
    public let artistImageUrl: String?  // Direct URL to artist image (Navidrome)
    public let starred: Date?           // Date when starred (favorited)
    
    public init(id: String, name: String, albumCount: Int, coverArt: String?, artistImageUrl: String?, starred: Date?) {
        self.id = id
        self.name = name
        self.albumCount = albumCount
        self.coverArt = coverArt
        self.artistImageUrl = artistImageUrl
        self.starred = starred
    }
}

/// An album in a Subsonic music library
public struct SubsonicAlbum: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let artist: String?
    public let artistId: String?
    public let year: Int?
    public let genre: String?
    public let coverArt: String?        // Cover art ID for artwork URL
    public let songCount: Int
    public let duration: Int            // Total duration in seconds
    public let created: Date?           // When added to library
    public let starred: Date?           // Date when starred (favorited)
    public let playCount: Int?          // Number of plays
    
    public init(id: String, name: String, artist: String?, artistId: String?, year: Int?, genre: String?, coverArt: String?, songCount: Int, duration: Int, created: Date?, starred: Date?, playCount: Int?) {
        self.id = id
        self.name = name
        self.artist = artist
        self.artistId = artistId
        self.year = year
        self.genre = genre
        self.coverArt = coverArt
        self.songCount = songCount
        self.duration = duration
        self.created = created
        self.starred = starred
        self.playCount = playCount
    }
    
    public var formattedDuration: String {
        let minutes = duration / 60
        let hours = minutes / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes % 60, duration % 60)
        }
        return String(format: "%d:%02d", minutes, duration % 60)
    }
}

/// A song (track) in a Subsonic music library
public struct SubsonicSong: Identifiable, Equatable {
    public let id: String
    public let parent: String?          // Parent album ID
    public let title: String
    public let album: String?
    public let artist: String?
    public let albumId: String?
    public let artistId: String?
    public let track: Int?              // Track number
    public let year: Int?
    public let genre: String?
    public let coverArt: String?        // Cover art ID
    public let size: Int64?             // File size in bytes
    public let contentType: String?     // MIME type
    public let suffix: String?          // File extension
    public let duration: Int            // Duration in seconds
    public let bitRate: Int?            // Bitrate in kbps
    public let samplingRate: Int?       // Sample rate in Hz (e.g., 44100, 96000)
    public let path: String?            // Server-side file path
    public let discNumber: Int?
    public let created: Date?
    public let starred: Date?           // Date when starred
    public let playCount: Int?
    
    public var formattedDuration: String {
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    public var durationInSeconds: TimeInterval {
        TimeInterval(duration)
    }
}

/// A playlist in Subsonic
public struct SubsonicPlaylist: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let comment: String?
    public let owner: String?
    public let isPublic: Bool
    public let songCount: Int
    public let duration: Int            // Total duration in seconds
    public let created: Date?
    public let changed: Date?           // Last modified
    public let coverArt: String?
    
    public var formattedDuration: String {
        let minutes = duration / 60
        let hours = minutes / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes % 60, duration % 60)
        }
        return String(format: "%d:%02d", minutes, duration % 60)
    }
}

/// Index entry for artist browsing (A-Z grouping)
public struct SubsonicIndex: Equatable {
    public let name: String             // Letter or "#" for non-alpha
    public let artists: [SubsonicArtist]
}

// MARK: - Search Results

/// Results from a Subsonic search3 query
public struct SubsonicSearchResults {
    public var artists: [SubsonicArtist] = []
    public var albums: [SubsonicAlbum] = []
    public var songs: [SubsonicSong] = []
    
    public init(artists: [SubsonicArtist] = [], albums: [SubsonicAlbum] = [], songs: [SubsonicSong] = []) {
        self.artists = artists
        self.albums = albums
        self.songs = songs
    }
    
    public var isEmpty: Bool {
        artists.isEmpty && albums.isEmpty && songs.isEmpty
    }
    
    public var totalCount: Int {
        artists.count + albums.count + songs.count
    }
}

/// Starred (favorite) items
public struct SubsonicStarred {
    public var artists: [SubsonicArtist] = []
    public var albums: [SubsonicAlbum] = []
    public var songs: [SubsonicSong] = []
    
    public init(artists: [SubsonicArtist] = [], albums: [SubsonicAlbum] = [], songs: [SubsonicSong] = []) {
        self.artists = artists
        self.albums = albums
        self.songs = songs
    }
    
    public var isEmpty: Bool {
        artists.isEmpty && albums.isEmpty && songs.isEmpty
    }
}

// MARK: - API Response Containers

/// Standard Subsonic API response wrapper
struct SubsonicResponse<T: Decodable>: Decodable {
    public let subsonicResponse: SubsonicResponseBody<T>
    
    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

/// Body of a Subsonic response
struct SubsonicResponseBody<T: Decodable>: Decodable {
    public let status: String
    public let version: String
    public let type: String?            // Server type (e.g., "navidrome")
    public let serverVersion: String?
    public let openSubsonic: Bool?      // Whether server supports OpenSubsonic extensions
    public let content: T?
    public let error: SubsonicError?
    
    public var isOk: Bool {
        status == "ok"
    }
    
    enum CodingKeys: String, CodingKey {
        case status, version, type, serverVersion, openSubsonic, error
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        version = try container.decode(String.self, forKey: .version)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        serverVersion = try container.decodeIfPresent(String.self, forKey: .serverVersion)
        openSubsonic = try container.decodeIfPresent(Bool.self, forKey: .openSubsonic)
        error = try container.decodeIfPresent(SubsonicError.self, forKey: .error)
        
        // Decode the content using the generic type
        content = try? T(from: decoder)
    }
}

/// Subsonic API error
public struct SubsonicError: Decodable, Error {
    public let code: Int
    public let message: String
    
    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
    
    public var localizedDescription: String {
        "Subsonic error \(code): \(message)"
    }
}

// MARK: - API Response DTOs

/// Response for ping endpoint
struct SubsonicPingResponse: Decodable {
    // Ping just returns the status, no additional data
}

/// Response for getArtists endpoint
struct SubsonicArtistsResponse: Decodable {
    let artists: ArtistsContainer?
    
    struct ArtistsContainer: Decodable {
        let index: [IndexDTO]?
        let ignoredArticles: String?
    }
    
    struct IndexDTO: Decodable {
        let name: String
        let artist: [ArtistDTO]?
    }
}

/// Response for getArtist endpoint (artist details + albums)
struct SubsonicArtistResponse: Decodable {
    let artist: ArtistDetailDTO?
    
    struct ArtistDetailDTO: Decodable {
        let id: String
        let name: String
        let coverArt: String?
        let artistImageUrl: String?
        let albumCount: Int?
        let starred: String?
        let album: [AlbumDTO]?
    }
}

/// Response for getAlbum endpoint (album details + tracks)
struct SubsonicAlbumResponse: Decodable {
    let album: AlbumDetailDTO?
    
    struct AlbumDetailDTO: Decodable {
        let id: String
        let name: String
        let artist: String?
        let artistId: String?
        let coverArt: String?
        let songCount: Int?
        let duration: Int?
        let created: String?
        let year: Int?
        let genre: String?
        let starred: String?
        let playCount: Int?
        let song: [SongDTO]?
    }
}

/// Response for getAlbumList2 endpoint
struct SubsonicAlbumListResponse: Decodable {
    let albumList2: AlbumListContainer?
    
    struct AlbumListContainer: Decodable {
        let album: [AlbumDTO]?
    }
}

/// Response for search3 endpoint
struct SubsonicSearchResponse: Decodable {
    let searchResult3: SearchResultContainer?
    
    struct SearchResultContainer: Decodable {
        let artist: [ArtistDTO]?
        let album: [AlbumDTO]?
        let song: [SongDTO]?
    }
}

/// Response for getPlaylists endpoint
struct SubsonicPlaylistsResponse: Decodable {
    let playlists: PlaylistsContainer?
    
    struct PlaylistsContainer: Decodable {
        let playlist: [PlaylistDTO]?
    }
}

/// Response for getPlaylist endpoint (playlist + tracks)
struct SubsonicPlaylistResponse: Decodable {
    let playlist: PlaylistDetailDTO?
    
    struct PlaylistDetailDTO: Decodable {
        let id: String
        let name: String
        let comment: String?
        let owner: String?
        let `public`: Bool?
        let songCount: Int?
        let duration: Int?
        let created: String?
        let changed: String?
        let coverArt: String?
        let entry: [SongDTO]?
    }
}

/// Response for getStarred2 endpoint
struct SubsonicStarredResponse: Decodable {
    let starred2: StarredContainer?
    
    struct StarredContainer: Decodable {
        let artist: [ArtistDTO]?
        let album: [AlbumDTO]?
        let song: [SongDTO]?
    }
}

// MARK: - Shared DTOs

/// Artist DTO for parsing API responses
public struct ArtistDTO: Decodable {
    public let id: String
    public let name: String
    public let coverArt: String?
    public let artistImageUrl: String?
    public let albumCount: Int?
    public let starred: String?
    
    public func toArtist() -> SubsonicArtist {
        SubsonicArtist(
            id: id,
            name: name,
            albumCount: albumCount ?? 0,
            coverArt: coverArt,
            artistImageUrl: artistImageUrl,
            starred: parseDate(starred)
        )
    }
}

/// Album DTO for parsing API responses
public struct AlbumDTO: Decodable {
    public let id: String
    public let name: String
    public let artist: String?
    public let artistId: String?
    public let coverArt: String?
    public let songCount: Int?
    public let duration: Int?
    public let created: String?
    public let year: Int?
    public let genre: String?
    public let starred: String?
    public let playCount: Int?
    
    public func toAlbum() -> SubsonicAlbum {
        SubsonicAlbum(
            id: id,
            name: name,
            artist: artist,
            artistId: artistId,
            year: year,
            genre: genre,
            coverArt: coverArt,
            songCount: songCount ?? 0,
            duration: duration ?? 0,
            created: parseDate(created),
            starred: parseDate(starred),
            playCount: playCount
        )
    }
}

/// Song DTO for parsing API responses
public struct SongDTO: Decodable {
    public let id: String
    public let parent: String?
    public let title: String
    public let album: String?
    public let artist: String?
    public let albumId: String?
    public let artistId: String?
    public let track: Int?
    public let year: Int?
    public let genre: String?
    public let coverArt: String?
    public let size: Int64?
    public let contentType: String?
    public let suffix: String?
    public let duration: Int?
    public let bitRate: Int?
    public let samplingRate: Int?
    public let path: String?
    public let discNumber: Int?
    public let created: String?
    public let starred: String?
    public let playCount: Int?
    
    public func toSong() -> SubsonicSong {
        SubsonicSong(
            id: id,
            parent: parent,
            title: title,
            album: album,
            artist: artist,
            albumId: albumId,
            artistId: artistId,
            track: track,
            year: year,
            genre: genre,
            coverArt: coverArt,
            size: size,
            contentType: contentType,
            suffix: suffix,
            duration: duration ?? 0,
            bitRate: bitRate,
            samplingRate: samplingRate,
            path: path,
            discNumber: discNumber,
            created: parseDate(created),
            starred: parseDate(starred),
            playCount: playCount
        )
    }
}

/// Playlist DTO for parsing API responses
public struct PlaylistDTO: Decodable {
    public let id: String
    public let name: String
    public let comment: String?
    public let owner: String?
    public let `public`: Bool?
    public let songCount: Int?
    public let duration: Int?
    public let created: String?
    public let changed: String?
    public let coverArt: String?
    
    public func toPlaylist() -> SubsonicPlaylist {
        SubsonicPlaylist(
            id: id,
            name: name,
            comment: comment,
            owner: owner,
            isPublic: `public` ?? false,
            songCount: songCount ?? 0,
            duration: duration ?? 0,
            created: parseDate(created),
            changed: parseDate(changed),
            coverArt: coverArt
        )
    }
}

// MARK: - Date Parsing Helper

/// Parse ISO 8601 date strings from Subsonic API
private func parseDate(_ dateString: String?) -> Date? {
    guard let dateString = dateString else { return nil }
    
    // Try ISO 8601 with fractional seconds first
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: dateString) {
        return date
    }
    
    // Try without fractional seconds
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: dateString) {
        return date
    }
    
    // Try simple date format (yyyy-MM-dd)
    let simpleFormatter = DateFormatter()
    simpleFormatter.dateFormat = "yyyy-MM-dd"
    return simpleFormatter.date(from: dateString)
}

// MARK: - Errors

public enum SubsonicClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case apiError(SubsonicError)
    case unauthorized
    case serverOffline
    case networkError(Error)
    case authenticationFailed
    case noContent
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "Server error: \(code)"
        case .apiError(let error):
            return error.message
        case .unauthorized:
            return "Authentication failed - check username and password"
        case .serverOffline:
            return "Server is offline or unreachable"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .authenticationFailed:
            return "Invalid username or password"
        case .noContent:
            return "No content returned from server"
        }
    }
}
