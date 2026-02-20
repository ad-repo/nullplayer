import Foundation

/// Client for communicating with a Jellyfin media server
class JellyfinServerClient {
    
    // MARK: - Properties
    
    let server: JellyfinServer
    private let accessToken: String
    private let session: URLSession
    private let baseURL: URL
    
    /// Client identifier for API calls
    private let clientName = "NullPlayer"
    
    /// Device ID for Jellyfin session tracking
    private let deviceId: String
    
    /// Number of retry attempts for failed requests
    private let maxRetries = 3
    
    /// File extensions that are not video — used as a safety net to filter out
    /// image files, metadata files, and subtitle files that Jellyfin may return
    private static let nonVideoExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "tiff", "tif", "ico", "svg",
        "nfo", "srt", "sub", "ssa", "ass", "vtt", "txt", "xml", "json", "log",
        "lrc", "idx", "sup"
    ]
    
    /// Check if a Jellyfin item is actual video content (not an image, subtitle, firmware, or metadata file)
    private static func isVideoItem(_ item: JellyfinItemDTO) -> Bool {
        // Items with no container likely aren't real video (e.g. firmware .bin files)
        // Jellyfin sets Container for any file it can identify as media
        guard let container = item.Container, !container.isEmpty else {
            return false
        }
        
        // Container can be a comma-separated list (e.g. "mov,mp4,m4a,3gp,3g2,mj2")
        // Check if any part is a non-video extension
        let containerParts = container.lowercased().split(separator: ",").map { String($0) }
        if containerParts.allSatisfy({ nonVideoExtensions.contains($0) }) {
            return false
        }
        
        // Check file path extension for known non-video types
        if let path = item.Path {
            let ext = (path as NSString).pathExtension.lowercased()
            if !ext.isEmpty && nonVideoExtensions.contains(ext) {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Initialization
    
    init?(server: JellyfinServer, accessToken: String) {
        self.server = server
        self.accessToken = accessToken
        self.deviceId = KeychainHelper.shared.getOrCreateClientIdentifier()
        
        guard let url = server.baseURL else {
            return nil
        }
        self.baseURL = url
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600  // 10 minutes for large library fetches
        self.session = URLSession(configuration: config)
    }
    
    /// Initialize from stored credentials
    convenience init?(credentials: JellyfinServerCredentials) {
        let server = JellyfinServer(
            id: credentials.id,
            name: credentials.name,
            url: credentials.url,
            username: credentials.username,
            userId: credentials.userId
        )
        self.init(server: server, accessToken: credentials.accessToken)
    }
    
    // MARK: - Authentication
    
    /// Generate authentication headers for API calls
    private func authHeaders() -> [String: String] {
        var headers = [
            "Authorization": "MediaBrowser Client=\"\(clientName)\", Device=\"Mac\", DeviceId=\"\(deviceId)\", Version=\"1.0\"",
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
        if !accessToken.isEmpty {
            headers["X-Emby-Token"] = accessToken
        }
        return headers
    }
    
    /// Authenticate with a Jellyfin server (called before client is created)
    static func authenticate(url: String, username: String, password: String, deviceId: String) async throws -> JellyfinAuthResponse {
        var cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanURL.hasSuffix("/") {
            cleanURL = String(cleanURL.dropLast())
        }
        
        guard let baseURL = URL(string: cleanURL) else {
            throw JellyfinClientError.invalidURL
        }
        
        let authURL = baseURL.appendingPathComponent("/Users/AuthenticateByName")
        
        var request = URLRequest(url: authURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "MediaBrowser Client=\"NullPlayer\", Device=\"Mac\", DeviceId=\"\(deviceId)\", Version=\"1.0\"",
            forHTTPHeaderField: "Authorization"
        )
        
        let body: [String: String] = ["Username": username, "Pw": password]
        request.httpBody = try JSONEncoder().encode(body)
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JellyfinClientError.invalidResponse
            }
            
            if httpResponse.statusCode == 401 {
                throw JellyfinClientError.authenticationFailed
            }
            
            guard httpResponse.statusCode == 200 else {
                throw JellyfinClientError.httpError(statusCode: httpResponse.statusCode)
            }
            
            let authResponse = try JSONDecoder().decode(JellyfinAuthResponse.self, from: data)
            return authResponse
            
        } catch let error as JellyfinClientError {
            throw error
        } catch {
            throw JellyfinClientError.networkError(error)
        }
    }
    
    // MARK: - Request Building
    
    private func buildRequest(path: String, params: [URLQueryItem] = [], method: String = "GET") -> URLRequest? {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !params.isEmpty {
            components?.queryItems = params
        }
        guard let url = components?.url else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (key, value) in authHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
    
    /// Perform a request with retry logic
    private func performRequest<T: Decodable>(_ request: URLRequest, retryCount: Int = 0) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JellyfinClientError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 {
                    throw JellyfinClientError.unauthorized
                }
                throw JellyfinClientError.httpError(statusCode: httpResponse.statusCode)
            }
            
            #if DEBUG
            if let jsonString = String(data: data, encoding: .utf8) {
                NSLog("JellyfinServerClient: Response for %@: %@", request.url?.lastPathComponent ?? "unknown", String(jsonString.prefix(500)))
            }
            #endif
            
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
            
        } catch let error as JellyfinClientError {
            throw error
        } catch {
            // Retry on network errors
            if retryCount < maxRetries && isRetryableError(error) {
                try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                return try await performRequest(request, retryCount: retryCount + 1)
            }
            throw JellyfinClientError.networkError(error)
        }
    }
    
    /// Perform a request that returns no meaningful body (e.g. POST actions)
    private func performVoidRequest(_ request: URLRequest) async throws {
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JellyfinClientError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw JellyfinClientError.unauthorized
            }
            throw JellyfinClientError.httpError(statusCode: httpResponse.statusCode)
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
        guard let request = buildRequest(path: "/System/Ping") else {
            throw JellyfinClientError.invalidURL
        }
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JellyfinClientError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw JellyfinClientError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return true
    }
    
    /// Check if the server is reachable (with short timeout)
    func checkConnection() async -> Bool {
        guard let request = buildRequest(path: "/System/Ping") else { return false }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        let quickSession = URLSession(configuration: config)
        
        do {
            let (_, response) = try await quickSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 200
        } catch {
            NSLog("JellyfinServerClient: Connection check failed: %@", error.localizedDescription)
            return false
        }
    }
    
    // MARK: - Music Libraries
    
    /// Fetch all libraries/views on the server (no collection type filtering)
    func fetchMusicLibraries() async throws -> [JellyfinMusicLibrary] {
        guard let request = buildRequest(path: "/Users/\(server.userId)/Views") else {
            throw JellyfinClientError.invalidURL
        }
        
        let response: JellyfinViewsResponse = try await performRequest(request)
        return response.Items.map { $0.toMusicLibrary() }
    }
    
    // MARK: - Video Libraries
    
    /// Fetch all libraries/views on the server (no collection type filtering)
    func fetchVideoLibraries() async throws -> [JellyfinMusicLibrary] {
        guard let request = buildRequest(path: "/Users/\(server.userId)/Views") else {
            throw JellyfinClientError.invalidURL
        }
        
        let response: JellyfinViewsResponse = try await performRequest(request)
        return response.Items.map { $0.toMusicLibrary() }
    }
    
    // MARK: - Movie Operations
    
    /// Fetch all movies from a library (paginated)
    func fetchMovies(libraryId: String) async throws -> [JellyfinMovie] {
        var allMovies: [JellyfinMovie] = []
        var offset = 0
        let pageSize = 10000
        
        while true {
            let params = [
                URLQueryItem(name: "parentId", value: libraryId),
                URLQueryItem(name: "IncludeItemTypes", value: "Movie"),
                URLQueryItem(name: "MediaTypes", value: "Video"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
                URLQueryItem(name: "Fields", value: "Overview,MediaSources,Path"),
                URLQueryItem(name: "Limit", value: String(pageSize)),
                URLQueryItem(name: "StartIndex", value: String(offset))
            ]
            
            guard let request = buildRequest(path: "/Users/\(server.userId)/Items", params: params) else {
                throw JellyfinClientError.invalidURL
            }
            
            let response: JellyfinQueryResult = try await performRequest(request)
            let movies = response.Items
                .filter { Self.isVideoItem($0) }
                .map { $0.toMovie() }
            allMovies.append(contentsOf: movies)
            
            if response.Items.count < pageSize {
                break
            }
            offset += pageSize
        }
        
        return allMovies
    }
    
    /// Fetch a single movie by ID
    func fetchMovie(id: String) async throws -> JellyfinMovie {
        guard let request = buildRequest(path: "/Users/\(server.userId)/Items/\(id)") else {
            throw JellyfinClientError.invalidURL
        }
        
        let dto: JellyfinItemDTO = try await performRequest(request)
        return dto.toMovie()
    }
    
    // MARK: - Show Operations
    
    /// Fetch all TV shows from a library (paginated)
    func fetchShows(libraryId: String) async throws -> [JellyfinShow] {
        var allShows: [JellyfinShow] = []
        var offset = 0
        let pageSize = 10000
        
        while true {
            let params = [
                URLQueryItem(name: "parentId", value: libraryId),
                URLQueryItem(name: "IncludeItemTypes", value: "Series"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
                URLQueryItem(name: "Fields", value: "Overview"),
                URLQueryItem(name: "Limit", value: String(pageSize)),
                URLQueryItem(name: "StartIndex", value: String(offset))
            ]
            
            guard let request = buildRequest(path: "/Users/\(server.userId)/Items", params: params) else {
                throw JellyfinClientError.invalidURL
            }
            
            let response: JellyfinQueryResult = try await performRequest(request)
            let shows = response.Items.map { $0.toShow() }
            allShows.append(contentsOf: shows)
            
            if shows.count < pageSize {
                break
            }
            offset += pageSize
        }
        
        return allShows
    }
    
    /// Fetch seasons for a TV show
    func fetchSeasons(seriesId: String) async throws -> [JellyfinSeason] {
        let params = [
            URLQueryItem(name: "userId", value: server.userId)
        ]
        
        guard let request = buildRequest(path: "/Shows/\(seriesId)/Seasons", params: params) else {
            throw JellyfinClientError.invalidURL
        }
        
        let response: JellyfinQueryResult = try await performRequest(request)
        return response.Items.map { $0.toSeason() }
    }
    
    /// Fetch episodes for a season of a TV show
    func fetchEpisodes(seriesId: String, seasonId: String) async throws -> [JellyfinEpisode] {
        let params = [
            URLQueryItem(name: "userId", value: server.userId),
            URLQueryItem(name: "seasonId", value: seasonId),
            URLQueryItem(name: "MediaTypes", value: "Video"),
            URLQueryItem(name: "Fields", value: "Overview,MediaSources")
        ]
        
        guard let request = buildRequest(path: "/Shows/\(seriesId)/Episodes", params: params) else {
            throw JellyfinClientError.invalidURL
        }
        
        let response: JellyfinQueryResult = try await performRequest(request)
        return response.Items.map { $0.toEpisode() }
    }
    
    /// Fetch a single episode by ID
    func fetchEpisode(id: String) async throws -> JellyfinEpisode {
        guard let request = buildRequest(path: "/Users/\(server.userId)/Items/\(id)") else {
            throw JellyfinClientError.invalidURL
        }
        
        let dto: JellyfinItemDTO = try await performRequest(request)
        return dto.toEpisode()
    }
    
    // MARK: - Artist Operations
    
    /// Fetch all artists (paginated)
    func fetchAllArtists(libraryId: String? = nil) async throws -> [JellyfinArtist] {
        var allArtists: [JellyfinArtist] = []
        var offset = 0
        let pageSize = 10000
        
        while true {
            var params = [
                URLQueryItem(name: "userId", value: server.userId),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
                URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio"),
                URLQueryItem(name: "Limit", value: String(pageSize)),
                URLQueryItem(name: "StartIndex", value: String(offset))
            ]
            if let libId = libraryId {
                params.append(URLQueryItem(name: "parentId", value: libId))
            }
            
            guard let request = buildRequest(path: "/Artists/AlbumArtists", params: params) else {
                throw JellyfinClientError.invalidURL
            }
            
            let response: JellyfinQueryResult = try await performRequest(request)
            let artists = response.Items.map { $0.toArtist() }
            allArtists.append(contentsOf: artists)
            
            if artists.count < pageSize {
                break
            }
            offset += pageSize
        }
        
        return allArtists
    }
    
    /// Fetch artist details with their albums
    func fetchArtist(id: String) async throws -> (artist: JellyfinArtist, albums: [JellyfinAlbum]) {
        // Fetch artist details
        guard let artistRequest = buildRequest(path: "/Users/\(server.userId)/Items/\(id)") else {
            throw JellyfinClientError.invalidURL
        }
        
        let artistDTO: JellyfinItemDTO = try await performRequest(artistRequest)
        let artist = artistDTO.toArtist()
        
        // Fetch artist's albums
        let albumParams = [
            URLQueryItem(name: "AlbumArtistIds", value: id),
            URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "SortBy", value: "ProductionYear,SortName")
        ]
        
        guard let albumRequest = buildRequest(path: "/Users/\(server.userId)/Items", params: albumParams) else {
            throw JellyfinClientError.invalidURL
        }
        
        let albumResponse: JellyfinQueryResult = try await performRequest(albumRequest)
        let albums = albumResponse.Items.map { $0.toAlbum() }
        
        return (artist, albums)
    }
    
    // MARK: - Album Operations
    
    /// Fetch all albums (paginated)
    func fetchAllAlbums(libraryId: String? = nil) async throws -> [JellyfinAlbum] {
        var allAlbums: [JellyfinAlbum] = []
        var offset = 0
        let pageSize = 10000
        
        while true {
            var params = [
                URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
                URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio"),
                URLQueryItem(name: "Limit", value: String(pageSize)),
                URLQueryItem(name: "StartIndex", value: String(offset))
            ]
            if let libId = libraryId {
                params.append(URLQueryItem(name: "parentId", value: libId))
            }
            
            guard let request = buildRequest(path: "/Users/\(server.userId)/Items", params: params) else {
                throw JellyfinClientError.invalidURL
            }
            
            let response: JellyfinQueryResult = try await performRequest(request)
            let albums = response.Items.map { $0.toAlbum() }
            allAlbums.append(contentsOf: albums)
            
            if albums.count < pageSize {
                break
            }
            offset += pageSize
        }
        
        return allAlbums
    }
    
    /// Fetch album details with tracks
    func fetchAlbum(id: String) async throws -> (album: JellyfinAlbum, songs: [JellyfinSong]) {
        // Fetch album details
        guard let albumRequest = buildRequest(path: "/Users/\(server.userId)/Items/\(id)") else {
            throw JellyfinClientError.invalidURL
        }
        
        let albumDTO: JellyfinItemDTO = try await performRequest(albumRequest)
        let album = albumDTO.toAlbum()
        
        // Fetch album tracks
        let trackParams = [
            URLQueryItem(name: "parentId", value: id),
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "SortBy", value: "ParentIndexNumber,IndexNumber")
        ]
        
        guard let trackRequest = buildRequest(path: "/Users/\(server.userId)/Items", params: trackParams) else {
            throw JellyfinClientError.invalidURL
        }
        
        let trackResponse: JellyfinQueryResult = try await performRequest(trackRequest)
        let songs = trackResponse.Items.map { $0.toSong() }
        
        return (album, songs)
    }
    
    /// Fetch a single song by ID
    func fetchSong(id: String) async throws -> JellyfinSong? {
        guard let request = buildRequest(path: "/Users/\(server.userId)/Items/\(id)") else {
            throw JellyfinClientError.invalidURL
        }
        
        let dto: JellyfinItemDTO = try await performRequest(request)
        return dto.toSong()
    }
    
    // MARK: - Search
    
    /// Search for artists, albums, songs, movies, shows, and episodes
    func search(query: String) async throws -> JellyfinSearchResults {
        let params = [
            URLQueryItem(name: "searchTerm", value: query),
            URLQueryItem(name: "IncludeItemTypes", value: "Audio,MusicAlbum,MusicArtist,Movie,Series,Episode"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "userId", value: server.userId),
            URLQueryItem(name: "Fields", value: "Overview,MediaSources"),
            URLQueryItem(name: "Limit", value: "50")
        ]
        
        guard let request = buildRequest(path: "/Items", params: params) else {
            throw JellyfinClientError.invalidURL
        }
        
        let response: JellyfinQueryResult = try await performRequest(request)
        
        var results = JellyfinSearchResults()
        for item in response.Items {
            switch item.ItemType {
            case "MusicArtist":
                results.artists.append(item.toArtist())
            case "MusicAlbum":
                results.albums.append(item.toAlbum())
            case "Audio":
                results.songs.append(item.toSong())
            case "Movie":
                results.movies.append(item.toMovie())
            case "Series":
                results.shows.append(item.toShow())
            case "Episode":
                results.episodes.append(item.toEpisode())
            default:
                break
            }
        }
        
        return results
    }
    
    // MARK: - Playlists
    
    /// Fetch all playlists
    func fetchPlaylists() async throws -> [JellyfinPlaylist] {
        let params = [
            URLQueryItem(name: "IncludeItemTypes", value: "Playlist"),
            URLQueryItem(name: "Recursive", value: "true")
        ]
        
        guard let request = buildRequest(path: "/Users/\(server.userId)/Items", params: params) else {
            throw JellyfinClientError.invalidURL
        }
        
        let response: JellyfinQueryResult = try await performRequest(request)
        return response.Items.map { $0.toPlaylist() }
    }
    
    /// Fetch playlist with tracks
    func fetchPlaylist(id: String) async throws -> (playlist: JellyfinPlaylist, songs: [JellyfinSong]) {
        // Fetch playlist details
        guard let playlistRequest = buildRequest(path: "/Users/\(server.userId)/Items/\(id)") else {
            throw JellyfinClientError.invalidURL
        }
        
        let playlistDTO: JellyfinItemDTO = try await performRequest(playlistRequest)
        let playlist = playlistDTO.toPlaylist()
        
        // Fetch playlist items
        let itemParams = [
            URLQueryItem(name: "userId", value: server.userId)
        ]
        
        guard let itemRequest = buildRequest(path: "/Playlists/\(id)/Items", params: itemParams) else {
            throw JellyfinClientError.invalidURL
        }
        
        let itemResponse: JellyfinQueryResult = try await performRequest(itemRequest)
        let songs = itemResponse.Items.map { $0.toSong() }
        
        return (playlist, songs)
    }
    
    // MARK: - Favorites
    
    /// Add item to favorites
    func favorite(itemId: String) async throws {
        guard let request = buildRequest(path: "/Users/\(server.userId)/FavoriteItems/\(itemId)", method: "POST") else {
            throw JellyfinClientError.invalidURL
        }
        try await performVoidRequest(request)
        NSLog("JellyfinServerClient: Added favorite for item %@", itemId)
    }
    
    /// Remove item from favorites
    func unfavorite(itemId: String) async throws {
        guard let request = buildRequest(path: "/Users/\(server.userId)/FavoriteItems/\(itemId)", method: "DELETE") else {
            throw JellyfinClientError.invalidURL
        }
        try await performVoidRequest(request)
        NSLog("JellyfinServerClient: Removed favorite for item %@", itemId)
    }
    
    // MARK: - Rating
    
    /// Set the rating for an item
    /// - Parameters:
    ///   - itemId: The Jellyfin item ID
    ///   - rating: Rating 0-100 (percentage). Each star = 20%.
    func setRating(itemId: String, rating: Int) async throws {
        let params = [
            URLQueryItem(name: "likes", value: rating > 0 ? "true" : "false")
        ]
        guard let request = buildRequest(path: "/Users/\(server.userId)/Items/\(itemId)/Rating", params: params, method: "POST") else {
            throw JellyfinClientError.invalidURL
        }
        try await performVoidRequest(request)
        NSLog("JellyfinServerClient: Set rating %d for item %@", rating, itemId)
    }
    
    // MARK: - Scrobbling / Playback Reporting
    
    /// Mark an item as played
    func scrobble(itemId: String) async throws {
        guard let request = buildRequest(path: "/Users/\(server.userId)/PlayedItems/\(itemId)", method: "POST") else {
            throw JellyfinClientError.invalidURL
        }
        try await performVoidRequest(request)
        NSLog("JellyfinServerClient: Scrobbled item %@", itemId)
    }
    
    /// Report playback start
    func reportPlaybackStart(itemId: String) async throws {
        guard var request = buildRequest(path: "/Sessions/Playing", method: "POST") else {
            throw JellyfinClientError.invalidURL
        }
        
        let body: [String: Any] = [
            "ItemId": itemId,
            "CanSeek": true,
            "PlayMethod": "DirectStream"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        try await performVoidRequest(request)
        NSLog("JellyfinServerClient: Reported playback start for %@", itemId)
    }
    
    /// Report playback progress
    func reportPlaybackProgress(itemId: String, positionTicks: Int64, isPaused: Bool = false) async throws {
        guard var request = buildRequest(path: "/Sessions/Playing/Progress", method: "POST") else {
            throw JellyfinClientError.invalidURL
        }
        
        let body: [String: Any] = [
            "ItemId": itemId,
            "PositionTicks": positionTicks,
            "IsPaused": isPaused
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        try await performVoidRequest(request)
    }
    
    /// Report playback stopped
    func reportPlaybackStopped(itemId: String, positionTicks: Int64) async throws {
        guard var request = buildRequest(path: "/Sessions/Playing/Stopped", method: "POST") else {
            throw JellyfinClientError.invalidURL
        }
        
        let body: [String: Any] = [
            "ItemId": itemId,
            "PositionTicks": positionTicks
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        try await performVoidRequest(request)
        NSLog("JellyfinServerClient: Reported playback stopped for %@", itemId)
    }
    
    // MARK: - URL Generation
    
    /// Generate a streaming URL for a song
    func streamURL(for song: JellyfinSong) -> URL? {
        streamURL(itemId: song.id)
    }
    
    /// Generate a streaming URL for an item ID (audio)
    func streamURL(itemId: String) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("/Audio/\(itemId)/stream"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "api_key", value: accessToken)
        ]
        return components?.url
    }
    
    /// Generate a video streaming URL for an item ID
    func videoStreamURL(itemId: String) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("/Videos/\(itemId)/stream"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "api_key", value: accessToken)
        ]
        return components?.url
    }
    
    /// Generate an image URL for an item
    /// Note: imageTag is optional — Jellyfin serves images without it, the tag is just for caching/ETag
    func imageURL(itemId: String, imageTag: String?, size: Int = 300) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("/Items/\(itemId)/Images/Primary"), resolvingAgainstBaseURL: false)
        var params = [
            URLQueryItem(name: "maxHeight", value: String(size)),
            URLQueryItem(name: "maxWidth", value: String(size))
        ]
        if let tag = imageTag {
            params.append(URLQueryItem(name: "tag", value: tag))
        }
        components?.queryItems = params
        return components?.url
    }
}
