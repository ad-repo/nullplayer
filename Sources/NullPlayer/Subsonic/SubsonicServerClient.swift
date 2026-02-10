import Foundation
import CryptoKit

/// Client for communicating with a Subsonic/Navidrome server
class SubsonicServerClient {
    
    // MARK: - Properties
    
    let server: SubsonicServer
    private let password: String
    private let session: URLSession
    private let baseURL: URL
    
    /// API version to use (1.16.1 is widely supported)
    private let apiVersion = "1.16.1"
    
    /// Client identifier for API calls
    private let clientName = "NullPlayer"
    
    /// Number of retry attempts for failed requests
    private let maxRetries = 3
    
    // MARK: - Initialization
    
    init?(server: SubsonicServer, password: String) {
        self.server = server
        self.password = password
        
        guard let url = server.baseURL else {
            return nil
        }
        self.baseURL = url
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }
    
    /// Initialize from stored credentials
    convenience init?(credentials: SubsonicServerCredentials) {
        let server = SubsonicServer(
            id: credentials.id,
            name: credentials.name,
            url: credentials.url,
            username: credentials.username
        )
        self.init(server: server, password: credentials.password)
    }
    
    // MARK: - Authentication
    
    /// Generate authentication parameters for API calls
    /// Uses token-based auth: t = md5(password + salt), s = salt
    private func authParams() -> [URLQueryItem] {
        let salt = UUID().uuidString.prefix(16).lowercased()
        let token = md5Hash(password + salt)
        
        return [
            URLQueryItem(name: "u", value: server.username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: String(salt)),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "c", value: clientName),
            URLQueryItem(name: "f", value: "json")
        ]
    }
    
    /// Generate authentication parameters for streaming/binary endpoints (no f=json)
    /// The f=json parameter would cause Navidrome to return JSON instead of audio data
    /// which breaks casting to Sonos and other devices that fetch the URL directly
    private func streamAuthParams() -> [URLQueryItem] {
        let salt = UUID().uuidString.prefix(16).lowercased()
        let token = md5Hash(password + salt)
        
        return [
            URLQueryItem(name: "u", value: server.username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: String(salt)),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "c", value: clientName)
            // Note: f=json omitted - stream endpoints return binary data
        ]
    }
    
    /// Calculate MD5 hash of a string
    private func md5Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Request Building
    
    private func buildRequest(endpoint: String, params: [URLQueryItem] = []) -> URLRequest? {
        let restPath = "/rest/\(endpoint)"
        var components = URLComponents(url: baseURL.appendingPathComponent(restPath), resolvingAgainstBaseURL: false)
        
        // Combine auth params with custom params
        var allParams = authParams()
        allParams.append(contentsOf: params)
        components?.queryItems = allParams
        
        guard let url = components?.url else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        return request
    }
    
    /// Perform a request with retry logic
    private func performRequest<T: Decodable>(_ request: URLRequest, retryCount: Int = 0) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SubsonicClientError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 {
                    throw SubsonicClientError.unauthorized
                }
                throw SubsonicClientError.httpError(statusCode: httpResponse.statusCode)
            }
            
            // Debug: Print response for troubleshooting
            #if DEBUG
            if let jsonString = String(data: data, encoding: .utf8) {
                NSLog("SubsonicServerClient: Response for %@: %@", request.url?.lastPathComponent ?? "unknown", String(jsonString.prefix(500)))
            }
            #endif
            
            // Parse the response
            let decoder = JSONDecoder()
            let subsonicResponse = try decoder.decode(SubsonicResponse<T>.self, from: data)
            
            // Check for API errors
            if let error = subsonicResponse.subsonicResponse.error {
                if error.code == 40 || error.code == 41 {
                    throw SubsonicClientError.authenticationFailed
                }
                throw SubsonicClientError.apiError(error)
            }
            
            guard subsonicResponse.subsonicResponse.isOk else {
                throw SubsonicClientError.invalidResponse
            }
            
            guard let content = subsonicResponse.subsonicResponse.content else {
                throw SubsonicClientError.noContent
            }
            
            return content
            
        } catch let error as SubsonicClientError {
            throw error
        } catch {
            // Retry on network errors
            if retryCount < maxRetries && isRetryableError(error) {
                try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                return try await performRequest(request, retryCount: retryCount + 1)
            }
            throw SubsonicClientError.networkError(error)
        }
    }
    
    private func isRetryableError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        return false
    }
    
    // MARK: - Connection Test
    
    /// Test the connection to the server (ping endpoint)
    func ping() async throws -> Bool {
        guard let request = buildRequest(endpoint: "ping") else {
            throw SubsonicClientError.invalidURL
        }
        
        let _: SubsonicPingResponse = try await performRequest(request)
        return true
    }
    
    /// Check if the server is reachable (with short timeout)
    func checkConnection() async -> Bool {
        guard let request = buildRequest(endpoint: "ping") else { return false }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        let quickSession = URLSession(configuration: config)
        
        do {
            let (data, response) = try await quickSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            
            if httpResponse.statusCode != 200 {
                return false
            }
            
            // Verify the response is valid JSON with ok status
            let decoder = JSONDecoder()
            let subsonicResponse = try decoder.decode(SubsonicResponse<SubsonicPingResponse>.self, from: data)
            return subsonicResponse.subsonicResponse.isOk
            
        } catch {
            NSLog("SubsonicServerClient: Connection check failed: %@", error.localizedDescription)
            return false
        }
    }
    
    // MARK: - Artist Operations
    
    /// Fetch all artists (indexed A-Z)
    func fetchArtists() async throws -> [SubsonicIndex] {
        guard let request = buildRequest(endpoint: "getArtists") else {
            throw SubsonicClientError.invalidURL
        }
        
        let response: SubsonicArtistsResponse = try await performRequest(request)
        
        guard let indexes = response.artists?.index else {
            return []
        }
        
        return indexes.map { indexDTO in
            SubsonicIndex(
                name: indexDTO.name,
                artists: indexDTO.artist?.map { $0.toArtist() } ?? []
            )
        }
    }
    
    /// Fetch all artists as a flat list
    func fetchAllArtists() async throws -> [SubsonicArtist] {
        let indexes = try await fetchArtists()
        return indexes.flatMap { $0.artists }
    }
    
    /// Fetch artist details with their albums
    func fetchArtist(id: String) async throws -> (artist: SubsonicArtist, albums: [SubsonicAlbum]) {
        let params = [URLQueryItem(name: "id", value: id)]
        guard let request = buildRequest(endpoint: "getArtist", params: params) else {
            throw SubsonicClientError.invalidURL
        }
        
        let response: SubsonicArtistResponse = try await performRequest(request)
        
        guard let artistDTO = response.artist else {
            throw SubsonicClientError.noContent
        }
        
        let artist = SubsonicArtist(
            id: artistDTO.id,
            name: artistDTO.name,
            albumCount: artistDTO.albumCount ?? 0,
            coverArt: artistDTO.coverArt,
            artistImageUrl: artistDTO.artistImageUrl,
            starred: parseDate(artistDTO.starred)
        )
        
        let albums = artistDTO.album?.map { $0.toAlbum() } ?? []
        
        return (artist, albums)
    }
    
    // MARK: - Album Operations
    
    /// Fetch albums with various sorting options
    /// - Parameters:
    ///   - type: Sort type (alphabeticalByName, newest, frequent, recent, starred, etc.)
    ///   - size: Number of albums to return (max 500)
    ///   - offset: Offset for pagination
    func fetchAlbums(type: AlbumListType = .alphabeticalByName, size: Int = 100, offset: Int = 0) async throws -> [SubsonicAlbum] {
        let params = [
            URLQueryItem(name: "type", value: type.rawValue),
            URLQueryItem(name: "size", value: String(size)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        
        guard let request = buildRequest(endpoint: "getAlbumList2", params: params) else {
            throw SubsonicClientError.invalidURL
        }
        
        let response: SubsonicAlbumListResponse = try await performRequest(request)
        return response.albumList2?.album?.map { $0.toAlbum() } ?? []
    }
    
    /// Fetch all albums (paginated)
    func fetchAllAlbums(type: AlbumListType = .alphabeticalByName) async throws -> [SubsonicAlbum] {
        var allAlbums: [SubsonicAlbum] = []
        var offset = 0
        let pageSize = 500
        
        while true {
            let albums = try await fetchAlbums(type: type, size: pageSize, offset: offset)
            allAlbums.append(contentsOf: albums)
            
            if albums.count < pageSize {
                break
            }
            offset += pageSize
        }
        
        return allAlbums
    }
    
    /// Fetch a single song by ID
    func fetchSong(id: String) async throws -> SubsonicSong? {
        let params = [URLQueryItem(name: "id", value: id)]
        guard let request = buildRequest(endpoint: "getSong", params: params) else {
            throw SubsonicClientError.invalidURL
        }
        
        let response: SubsonicSongResponse = try await performRequest(request)
        return response.song?.toSong()
    }
    
    /// Fetch album details with tracks
    func fetchAlbum(id: String) async throws -> (album: SubsonicAlbum, songs: [SubsonicSong]) {
        let params = [URLQueryItem(name: "id", value: id)]
        guard let request = buildRequest(endpoint: "getAlbum", params: params) else {
            throw SubsonicClientError.invalidURL
        }
        
        let response: SubsonicAlbumResponse = try await performRequest(request)
        
        guard let albumDTO = response.album else {
            throw SubsonicClientError.noContent
        }
        
        let album = SubsonicAlbum(
            id: albumDTO.id,
            name: albumDTO.name,
            artist: albumDTO.artist,
            artistId: albumDTO.artistId,
            year: albumDTO.year,
            genre: albumDTO.genre,
            coverArt: albumDTO.coverArt,
            songCount: albumDTO.songCount ?? 0,
            duration: albumDTO.duration ?? 0,
            created: parseDate(albumDTO.created),
            starred: parseDate(albumDTO.starred),
            playCount: albumDTO.playCount
        )
        
        let songs = albumDTO.song?.map { $0.toSong() } ?? []
        
        return (album, songs)
    }
    
    // MARK: - Search
    
    /// Search for artists, albums, and songs
    func search(query: String, artistCount: Int = 20, albumCount: Int = 20, songCount: Int = 20) async throws -> SubsonicSearchResults {
        let params = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "artistCount", value: String(artistCount)),
            URLQueryItem(name: "albumCount", value: String(albumCount)),
            URLQueryItem(name: "songCount", value: String(songCount))
        ]
        
        guard let request = buildRequest(endpoint: "search3", params: params) else {
            throw SubsonicClientError.invalidURL
        }
        
        let response: SubsonicSearchResponse = try await performRequest(request)
        
        return SubsonicSearchResults(
            artists: response.searchResult3?.artist?.map { $0.toArtist() } ?? [],
            albums: response.searchResult3?.album?.map { $0.toAlbum() } ?? [],
            songs: response.searchResult3?.song?.map { $0.toSong() } ?? []
        )
    }
    
    // MARK: - Playlists
    
    /// Fetch all playlists
    func fetchPlaylists() async throws -> [SubsonicPlaylist] {
        guard let request = buildRequest(endpoint: "getPlaylists") else {
            throw SubsonicClientError.invalidURL
        }
        
        let response: SubsonicPlaylistsResponse = try await performRequest(request)
        return response.playlists?.playlist?.map { $0.toPlaylist() } ?? []
    }
    
    /// Fetch playlist with tracks
    func fetchPlaylist(id: String) async throws -> (playlist: SubsonicPlaylist, songs: [SubsonicSong]) {
        let params = [URLQueryItem(name: "id", value: id)]
        guard let request = buildRequest(endpoint: "getPlaylist", params: params) else {
            throw SubsonicClientError.invalidURL
        }
        
        let response: SubsonicPlaylistResponse = try await performRequest(request)
        
        guard let playlistDTO = response.playlist else {
            throw SubsonicClientError.noContent
        }
        
        let playlist = SubsonicPlaylist(
            id: playlistDTO.id,
            name: playlistDTO.name,
            comment: playlistDTO.comment,
            owner: playlistDTO.owner,
            isPublic: playlistDTO.public ?? false,
            songCount: playlistDTO.songCount ?? 0,
            duration: playlistDTO.duration ?? 0,
            created: parseDate(playlistDTO.created),
            changed: parseDate(playlistDTO.changed),
            coverArt: playlistDTO.coverArt
        )
        
        let songs = playlistDTO.entry?.map { $0.toSong() } ?? []
        
        return (playlist, songs)
    }
    
    /// Create a new playlist
    func createPlaylist(name: String, songIds: [String] = []) async throws -> String {
        var params = [URLQueryItem(name: "name", value: name)]
        for songId in songIds {
            params.append(URLQueryItem(name: "songId", value: songId))
        }
        
        guard let request = buildRequest(endpoint: "createPlaylist", params: params) else {
            throw SubsonicClientError.invalidURL
        }
        
        // Create playlist returns the playlist or just success
        let _: SubsonicPlaylistResponse = try await performRequest(request)
        
        // The API may return the playlist ID in the response, or we need to fetch playlists to find it
        // For now, return empty string - caller should refresh playlist list
        return ""
    }
    
    /// Update a playlist (add/remove songs)
    func updatePlaylist(id: String, songIdsToAdd: [String] = [], songIndexesToRemove: [Int] = []) async throws {
        var params = [URLQueryItem(name: "playlistId", value: id)]
        
        for songId in songIdsToAdd {
            params.append(URLQueryItem(name: "songIdToAdd", value: songId))
        }
        
        for index in songIndexesToRemove {
            params.append(URLQueryItem(name: "songIndexToRemove", value: String(index)))
        }
        
        guard let request = buildRequest(endpoint: "updatePlaylist", params: params) else {
            throw SubsonicClientError.invalidURL
        }
        
        let _: SubsonicPingResponse = try await performRequest(request)
    }
    
    /// Delete a playlist
    func deletePlaylist(id: String) async throws {
        let params = [URLQueryItem(name: "id", value: id)]
        guard let request = buildRequest(endpoint: "deletePlaylist", params: params) else {
            throw SubsonicClientError.invalidURL
        }
        
        let _: SubsonicPingResponse = try await performRequest(request)
    }
    
    // MARK: - Favorites (Starred)
    
    /// Fetch all starred (favorite) items
    func fetchStarred() async throws -> SubsonicStarred {
        guard let request = buildRequest(endpoint: "getStarred2") else {
            throw SubsonicClientError.invalidURL
        }
        
        let response: SubsonicStarredResponse = try await performRequest(request)
        
        return SubsonicStarred(
            artists: response.starred2?.artist?.map { $0.toArtist() } ?? [],
            albums: response.starred2?.album?.map { $0.toAlbum() } ?? [],
            songs: response.starred2?.song?.map { $0.toSong() } ?? []
        )
    }
    
    /// Star (favorite) an item
    func star(id: String? = nil, albumId: String? = nil, artistId: String? = nil) async throws {
        var params: [URLQueryItem] = []
        if let id = id { params.append(URLQueryItem(name: "id", value: id)) }
        if let albumId = albumId { params.append(URLQueryItem(name: "albumId", value: albumId)) }
        if let artistId = artistId { params.append(URLQueryItem(name: "artistId", value: artistId)) }
        
        guard !params.isEmpty else { return }
        
        guard let request = buildRequest(endpoint: "star", params: params) else {
            throw SubsonicClientError.invalidURL
        }
        
        let _: SubsonicPingResponse = try await performRequest(request)
    }
    
    /// Unstar (unfavorite) an item
    func unstar(id: String? = nil, albumId: String? = nil, artistId: String? = nil) async throws {
        var params: [URLQueryItem] = []
        if let id = id { params.append(URLQueryItem(name: "id", value: id)) }
        if let albumId = albumId { params.append(URLQueryItem(name: "albumId", value: albumId)) }
        if let artistId = artistId { params.append(URLQueryItem(name: "artistId", value: artistId)) }
        
        guard !params.isEmpty else { return }
        
        guard let request = buildRequest(endpoint: "unstar", params: params) else {
            throw SubsonicClientError.invalidURL
        }
        
        let _: SubsonicPingResponse = try await performRequest(request)
    }
    
    // MARK: - Rating
    
    /// Set the rating for a song (or album/artist)
    /// - Parameters:
    ///   - id: The ID of the song/album/artist to rate
    ///   - rating: Rating between 1 and 5 (inclusive), or 0 to remove the rating
    func setRating(id: String, rating: Int) async throws {
        let params = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "rating", value: String(rating))
        ]
        
        guard let request = buildRequest(endpoint: "setRating", params: params) else {
            throw SubsonicClientError.invalidURL
        }
        
        let _: SubsonicPingResponse = try await performRequest(request)
        NSLog("SubsonicServerClient: Set rating %d for item %@", rating, id)
    }
    
    // MARK: - Scrobbling
    
    /// Report that a song is being played (scrobble)
    /// - Parameters:
    ///   - id: Song ID
    ///   - submission: If true, marks track as "scrobbled" (played). If false, indicates "now playing".
    func scrobble(id: String, submission: Bool = true) async throws {
        let params = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "submission", value: submission ? "true" : "false")
        ]
        
        guard let request = buildRequest(endpoint: "scrobble", params: params) else {
            throw SubsonicClientError.invalidURL
        }
        
        let _: SubsonicPingResponse = try await performRequest(request)
        NSLog("SubsonicServerClient: Scrobbled song %@ (submission: %@)", id, submission ? "true" : "false")
    }
    
    // MARK: - URL Generation
    
    /// Generate a streaming URL for a song
    func streamURL(for song: SubsonicSong) -> URL? {
        streamURL(songId: song.id)
    }
    
    /// Generate a streaming URL for a song ID
    func streamURL(songId: String) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/stream"), resolvingAgainstBaseURL: false)
        
        // Use streamAuthParams (no f=json) so Navidrome returns audio data
        var params = streamAuthParams()
        params.append(URLQueryItem(name: "id", value: songId))
        components?.queryItems = params
        
        return components?.url
    }
    
    /// Generate a cover art URL
    /// - Parameters:
    ///   - coverArtId: The cover art ID from an album/artist/song
    ///   - size: Desired size in pixels (optional)
    func coverArtURL(coverArtId: String?, size: Int? = nil) -> URL? {
        guard let coverArtId = coverArtId else { return nil }
        
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/getCoverArt"), resolvingAgainstBaseURL: false)
        
        // Use streamAuthParams (no f=json) so Navidrome returns image data
        var params = streamAuthParams()
        params.append(URLQueryItem(name: "id", value: coverArtId))
        if let size = size {
            params.append(URLQueryItem(name: "size", value: String(size)))
        }
        components?.queryItems = params
        
        return components?.url
    }
}

// MARK: - Supporting Types

/// Album list sort types for getAlbumList2
enum AlbumListType: String {
    case random = "random"
    case newest = "newest"
    case frequent = "frequent"
    case recent = "recent"
    case starred = "starred"
    case alphabeticalByName = "alphabeticalByName"
    case alphabeticalByArtist = "alphabeticalByArtist"
    case byYear = "byYear"
    case byGenre = "byGenre"
}

// MARK: - Date Parsing Helper

private func parseDate(_ dateString: String?) -> Date? {
    guard let dateString = dateString else { return nil }
    
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: dateString) {
        return date
    }
    
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: dateString)
}
