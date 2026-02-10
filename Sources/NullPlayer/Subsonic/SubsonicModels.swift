import Foundation

// MARK: - Subsonic Server

/// A Subsonic/Navidrome server connection
struct SubsonicServer: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let url: String              // Base URL (e.g., "http://localhost:4533")
    let username: String
    
    /// Display URL without credentials
    var displayURL: String {
        url
    }
    
    /// Get the base URL for API calls
    var baseURL: URL? {
        URL(string: url)
    }
}

/// Credentials for a Subsonic server (stored in keychain)
struct SubsonicServerCredentials: Codable {
    let id: String
    let name: String
    let url: String
    let username: String
    let password: String         // Stored encrypted in keychain
}

// MARK: - Library Content

/// An artist in a Subsonic music library
struct SubsonicArtist: Identifiable, Equatable {
    let id: String
    let name: String
    let albumCount: Int
    let coverArt: String?        // Cover art ID for artwork URL
    let artistImageUrl: String?  // Direct URL to artist image (Navidrome)
    let starred: Date?           // Date when starred (favorited)
}

/// An album in a Subsonic music library
struct SubsonicAlbum: Identifiable, Equatable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let year: Int?
    let genre: String?
    let coverArt: String?        // Cover art ID for artwork URL
    let songCount: Int
    let duration: Int            // Total duration in seconds
    let created: Date?           // When added to library
    let starred: Date?           // Date when starred (favorited)
    let playCount: Int?          // Number of plays
    
    var formattedDuration: String {
        let minutes = duration / 60
        let hours = minutes / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes % 60, duration % 60)
        }
        return String(format: "%d:%02d", minutes, duration % 60)
    }
}

/// A song (track) in a Subsonic music library
struct SubsonicSong: Identifiable, Equatable {
    let id: String
    let parent: String?          // Parent album ID
    let title: String
    let album: String?
    let artist: String?
    let albumId: String?
    let artistId: String?
    let track: Int?              // Track number
    let year: Int?
    let genre: String?
    let coverArt: String?        // Cover art ID
    let size: Int64?             // File size in bytes
    let contentType: String?     // MIME type
    let suffix: String?          // File extension
    let duration: Int            // Duration in seconds
    let bitRate: Int?            // Bitrate in kbps
    let samplingRate: Int?       // Sample rate in Hz (e.g., 44100, 96000)
    let path: String?            // Server-side file path
    let discNumber: Int?
    let created: Date?
    let starred: Date?           // Date when starred
    let playCount: Int?
    let userRating: Int?         // User rating [1-5], nil if unrated
    
    var formattedDuration: String {
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var durationInSeconds: TimeInterval {
        TimeInterval(duration)
    }
}

/// A playlist in Subsonic
struct SubsonicPlaylist: Identifiable, Equatable {
    let id: String
    let name: String
    let comment: String?
    let owner: String?
    let isPublic: Bool
    let songCount: Int
    let duration: Int            // Total duration in seconds
    let created: Date?
    let changed: Date?           // Last modified
    let coverArt: String?
    
    var formattedDuration: String {
        let minutes = duration / 60
        let hours = minutes / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes % 60, duration % 60)
        }
        return String(format: "%d:%02d", minutes, duration % 60)
    }
}

/// Index entry for artist browsing (A-Z grouping)
struct SubsonicIndex: Equatable {
    let name: String             // Letter or "#" for non-alpha
    let artists: [SubsonicArtist]
}

// MARK: - Search Results

/// Results from a Subsonic search3 query
struct SubsonicSearchResults {
    var artists: [SubsonicArtist] = []
    var albums: [SubsonicAlbum] = []
    var songs: [SubsonicSong] = []
    
    var isEmpty: Bool {
        artists.isEmpty && albums.isEmpty && songs.isEmpty
    }
    
    var totalCount: Int {
        artists.count + albums.count + songs.count
    }
}

/// Starred (favorite) items
struct SubsonicStarred {
    var artists: [SubsonicArtist] = []
    var albums: [SubsonicAlbum] = []
    var songs: [SubsonicSong] = []
    
    var isEmpty: Bool {
        artists.isEmpty && albums.isEmpty && songs.isEmpty
    }
}

// MARK: - API Response Containers

/// Standard Subsonic API response wrapper
struct SubsonicResponse<T: Decodable>: Decodable {
    let subsonicResponse: SubsonicResponseBody<T>
    
    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

/// Body of a Subsonic response
struct SubsonicResponseBody<T: Decodable>: Decodable {
    let status: String
    let version: String
    let type: String?            // Server type (e.g., "navidrome")
    let serverVersion: String?
    let openSubsonic: Bool?      // Whether server supports OpenSubsonic extensions
    let content: T?
    let error: SubsonicError?
    
    var isOk: Bool {
        status == "ok"
    }
    
    enum CodingKeys: String, CodingKey {
        case status, version, type, serverVersion, openSubsonic, error
    }
    
    init(from decoder: Decoder) throws {
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
struct SubsonicError: Decodable, Error {
    let code: Int
    let message: String
    
    var localizedDescription: String {
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

/// Response for getSong endpoint
struct SubsonicSongResponse: Decodable {
    let song: SongDTO?
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
struct ArtistDTO: Decodable {
    let id: String
    let name: String
    let coverArt: String?
    let artistImageUrl: String?
    let albumCount: Int?
    let starred: String?
    
    func toArtist() -> SubsonicArtist {
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
struct AlbumDTO: Decodable {
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
    
    func toAlbum() -> SubsonicAlbum {
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
struct SongDTO: Decodable {
    let id: String
    let parent: String?
    let title: String
    let album: String?
    let artist: String?
    let albumId: String?
    let artistId: String?
    let track: Int?
    let year: Int?
    let genre: String?
    let coverArt: String?
    let size: Int64?
    let contentType: String?
    let suffix: String?
    let duration: Int?
    let bitRate: Int?
    let samplingRate: Int?
    let path: String?
    let discNumber: Int?
    let created: String?
    let starred: String?
    let playCount: Int?
    let userRating: Int?
    
    func toSong() -> SubsonicSong {
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
            playCount: playCount,
            userRating: userRating
        )
    }
}

/// Playlist DTO for parsing API responses
struct PlaylistDTO: Decodable {
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
    
    func toPlaylist() -> SubsonicPlaylist {
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

enum SubsonicClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case apiError(SubsonicError)
    case unauthorized
    case serverOffline
    case networkError(Error)
    case authenticationFailed
    case noContent
    
    var errorDescription: String? {
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
