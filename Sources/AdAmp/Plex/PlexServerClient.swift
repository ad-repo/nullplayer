import Foundation

/// Radio station configuration - easy to modify thresholds
enum RadioConfig {
    /// Minimum Last.fm scrobbles to qualify as a "hit"
    static let hitsThreshold = 1_000_000
    
    /// Maximum Last.fm scrobbles to qualify as a "deep cut"
    static let deepCutsThreshold = 1_000
    
    /// Default number of tracks to fetch for radio
    static let defaultLimit = 100
    
    /// Maximum tracks per artist in a radio playlist (for variety)
    static let maxTracksPerArtist = 2
    
    /// Multiplier for over-fetching to allow for artist deduplication
    static let overFetchMultiplier = 3
    
    /// Fallback genres if library fetch fails (most libraries have these)
    static let fallbackGenres = ["Pop/Rock", "Jazz", "Classical", "Electronic", "R&B", "Rap", "Country", "Blues"]
    
    /// Decade ranges for Decade Radio (start year, end year, display name)
    static let decades: [(start: Int, end: Int, name: String)] = [
        (1920, 1929, "1920s"), (1930, 1939, "1930s"), (1940, 1949, "1940s"),
        (1950, 1959, "1950s"), (1960, 1969, "1960s"), (1970, 1979, "1970s"),
        (1980, 1989, "1980s"), (1990, 1999, "1990s"), (2000, 2009, "2000s"),
        (2010, 2019, "2010s"), (2020, 2029, "2020s")
    ]
    
    // MARK: - User Rating Thresholds (0-10 scale, 10 = 5 stars)
    
    /// Rating options for user rating-based radio stations
    /// Each tuple: (minRating: Double, name: String, description: String)
    static let ratingStations: [(minRating: Double, name: String, description: String)] = [
        (10.0, "5 Stars", "Only your 5-star rated tracks"),
        (8.0, "4+ Stars", "Your highly rated tracks (4+ stars)"),
        (6.0, "3+ Stars", "Tracks you've rated 3 stars or higher"),
        (4.0, "2+ Stars", "Any track you've rated 2 stars or higher"),
        (0.1, "All Rated", "Any track you've rated")
    ]
}

/// Client for communicating with a Plex Media Server
class PlexServerClient {
    
    // MARK: - Properties
    
    let server: PlexServer
    let authToken: String
    private let clientIdentifier: String
    private let session: URLSession
    private let baseURL: URL
    
    /// Number of retry attempts for failed requests
    private let maxRetries = 3
    
    // MARK: - Initialization
    
    init?(server: PlexServer, authToken: String, clientIdentifier: String? = nil) {
        self.server = server
        self.authToken = server.accessToken ?? authToken
        self.clientIdentifier = clientIdentifier ?? KeychainHelper.shared.getOrCreateClientIdentifier()
        
        // Get the preferred connection URL
        guard let connection = server.preferredConnection,
              let url = connection.url else {
            return nil
        }
        self.baseURL = url
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Standard Headers
    
    private var standardHeaders: [String: String] {
        [
            "X-Plex-Client-Identifier": clientIdentifier,
            "X-Plex-Product": "AdAmp",
            "X-Plex-Version": "1.0",
            "X-Plex-Platform": "macOS",
            "X-Plex-Platform-Version": ProcessInfo.processInfo.operatingSystemVersionString,
            "X-Plex-Device": "Mac",
            "X-Plex-Device-Name": Host.current().localizedName ?? "Mac",
            "X-Plex-Token": authToken,
            "Accept": "application/json"
        ]
    }
    
    /// Headers required for streaming (used by video player)
    /// Remote/relay connections require full client identification
    var streamingHeaders: [String: String] {
        [
            "X-Plex-Client-Identifier": clientIdentifier,
            "X-Plex-Product": "AdAmp",
            "X-Plex-Version": "1.0",
            "X-Plex-Platform": "macOS",
            "X-Plex-Platform-Version": ProcessInfo.processInfo.operatingSystemVersionString,
            "X-Plex-Device": "Mac",
            "X-Plex-Device-Name": Host.current().localizedName ?? "Mac",
            "X-Plex-Token": authToken
        ]
    }
    
    // MARK: - Request Building
    
    func buildRequest(path: String, queryItems: [URLQueryItem]? = nil) -> URLRequest? {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        
        guard let url = components?.url else { return nil }
        
        var request = URLRequest(url: url)
        for (key, value) in standardHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
    
    /// Perform a request with retry logic
    func performRequest<T: Decodable>(_ request: URLRequest, retryCount: Int = 0) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PlexServerError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                // Log the error response body for debugging
                let errorBody = String(data: data, encoding: .utf8) ?? "(non-UTF8 data)"
                NSLog("PlexServerClient: HTTP %d error for %@: %@", 
                      httpResponse.statusCode, 
                      request.url?.path ?? "unknown",
                      String(errorBody.prefix(500)))
                
                if httpResponse.statusCode == 401 {
                    throw PlexServerError.unauthorized
                }
                throw PlexServerError.httpError(statusCode: httpResponse.statusCode)
            }
            
            // Debug: Log response for troubleshooting
            #if DEBUG
            let endpoint = request.url?.path ?? "unknown"
            if let jsonString = String(data: data, encoding: .utf8) {
                NSLog("PlexServerClient: Response for %@: %@", endpoint, String(jsonString.prefix(1000)))
            }
            #endif
            
            // First try direct decoding
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch let initialError {
                // If direct decoding fails, the data might contain invalid UTF-8 bytes
                // (e.g., single bytes from Latin-1/Windows-1252 encoded artist names)
                if String(data: data, encoding: .utf8) == nil {
                    // Use lossy UTF-8 decoding, then replace the replacement character with "?"
                    // so it displays properly in bitmap fonts that don't support U+FFFD
                    let lossyString = String(decoding: data, as: UTF8.self)
                        .replacingOccurrences(of: "\u{FFFD}", with: "?")
                    if let sanitizedData = lossyString.data(using: .utf8) {
                        do {
                            NSLog("PlexServerClient: Retrying decode after UTF-8 sanitization (replaced invalid chars with ?)")
                            return try JSONDecoder().decode(T.self, from: sanitizedData)
                        } catch {
                            NSLog("PlexServerClient: UTF-8 sanitization didn't help: %@", error.localizedDescription)
                        }
                    }
                }
                
                // Log detailed decoding error for debugging
                NSLog("PlexServerClient: JSON decoding failed for %@ (data size: %d bytes)", request.url?.path ?? "unknown", data.count)
                if let decodingError = initialError as? DecodingError {
                    switch decodingError {
                    case .typeMismatch(let type, let context):
                        NSLog("PlexServerClient: Type mismatch: expected %@, path: %@", String(describing: type), context.codingPath.map { $0.stringValue }.joined(separator: "."))
                    case .valueNotFound(let type, let context):
                        NSLog("PlexServerClient: Value not found: %@, path: %@", String(describing: type), context.codingPath.map { $0.stringValue }.joined(separator: "."))
                    case .keyNotFound(let key, let context):
                        NSLog("PlexServerClient: Key not found: %@, path: %@", key.stringValue, context.codingPath.map { $0.stringValue }.joined(separator: "."))
                    case .dataCorrupted(let context):
                        NSLog("PlexServerClient: Data corrupted: %@, path: %@", context.debugDescription, context.codingPath.map { $0.stringValue }.joined(separator: "."))
                    @unknown default:
                        NSLog("PlexServerClient: Unknown decoding error: %@", initialError.localizedDescription)
                    }
                }
                
                throw initialError
            }
        } catch {
            // Retry on network errors
            if retryCount < maxRetries && isRetryableError(error) {
                try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                return try await performRequest(request, retryCount: retryCount + 1)
            }
            throw error
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
    
    // MARK: - Library Operations
    
    /// Fetch all libraries on the server
    func fetchLibraries() async throws -> [PlexLibrary] {
        guard let request = buildRequest(path: "/library/sections") else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexLibrariesResponse> = try await performRequest(request)
        return response.mediaContainer.directories?.map { $0.toLibrary() } ?? []
    }
    
    /// Fetch music libraries only
    func fetchMusicLibraries() async throws -> [PlexLibrary] {
        let libraries = try await fetchLibraries()
        return libraries.filter { $0.isMusicLibrary }
    }
    
    /// Fetch movie libraries only
    func fetchMovieLibraries() async throws -> [PlexLibrary] {
        let libraries = try await fetchLibraries()
        return libraries.filter { $0.isMovieLibrary }
    }
    
    /// Fetch TV show libraries only
    func fetchShowLibraries() async throws -> [PlexLibrary] {
        let libraries = try await fetchLibraries()
        return libraries.filter { $0.isShowLibrary }
    }
    
    /// Fetch all video libraries (movies and shows)
    func fetchVideoLibraries() async throws -> [PlexLibrary] {
        let libraries = try await fetchLibraries()
        return libraries.filter { $0.isVideoLibrary }
    }
    
    // MARK: - Artist Operations
    
    /// Fetch all artists in a music library
    func fetchArtists(libraryID: String, offset: Int = 0, limit: Int = 100) async throws -> [PlexArtist] {
        let queryItems = [
            URLQueryItem(name: "type", value: "8"),  // type 8 = artist
            URLQueryItem(name: "X-Plex-Container-Start", value: String(offset)),
            URLQueryItem(name: "X-Plex-Container-Size", value: String(limit)),
            // Include additional metadata to get album counts
            URLQueryItem(name: "includeCollections", value: "1"),
            URLQueryItem(name: "includeAdvanced", value: "1"),
            URLQueryItem(name: "includeMeta", value: "1")
        ]
        
        guard let request = buildRequest(path: "/library/sections/\(libraryID)/all", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        return response.mediaContainer.metadata?.map { $0.toArtist() } ?? []
    }
    
    /// Fetch all artists in a library (paginated, fetches all)
    func fetchAllArtists(libraryID: String) async throws -> [PlexArtist] {
        var allArtists: [PlexArtist] = []
        var offset = 0
        let pageSize = 100
        
        while true {
            let artists = try await fetchArtists(libraryID: libraryID, offset: offset, limit: pageSize)
            allArtists.append(contentsOf: artists)
            
            if artists.count < pageSize {
                break
            }
            offset += pageSize
        }
        
        return allArtists
    }
    
    // MARK: - Album Operations
    
    /// Fetch all albums in a music library
    func fetchAlbums(libraryID: String, offset: Int = 0, limit: Int = 100) async throws -> [PlexAlbum] {
        let queryItems = [
            URLQueryItem(name: "type", value: "9"),  // type 9 = album
            URLQueryItem(name: "X-Plex-Container-Start", value: String(offset)),
            URLQueryItem(name: "X-Plex-Container-Size", value: String(limit))
        ]
        
        guard let request = buildRequest(path: "/library/sections/\(libraryID)/all", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        return response.mediaContainer.metadata?.map { $0.toAlbum() } ?? []
    }
    
    /// Fetch albums for a specific artist
    func fetchAlbums(forArtist artistID: String) async throws -> [PlexAlbum] {
        guard let request = buildRequest(path: "/library/metadata/\(artistID)/children") else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        return response.mediaContainer.metadata?.map { $0.toAlbum() } ?? []
    }
    
    // MARK: - Track Operations
    
    /// Fetch all tracks in a music library
    func fetchTracks(libraryID: String, offset: Int = 0, limit: Int = 100) async throws -> [PlexTrack] {
        let queryItems = [
            URLQueryItem(name: "type", value: "10"),  // type 10 = track
            URLQueryItem(name: "X-Plex-Container-Start", value: String(offset)),
            URLQueryItem(name: "X-Plex-Container-Size", value: String(limit))
        ]
        
        guard let request = buildRequest(path: "/library/sections/\(libraryID)/all", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        return response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
    }
    
    /// Fetch tracks for a specific album
    func fetchTracks(forAlbum albumID: String) async throws -> [PlexTrack] {
        guard let request = buildRequest(path: "/library/metadata/\(albumID)/children") else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        return response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
    }
    
    // MARK: - Movie Operations
    
    /// Fetch all movies in a movie library
    func fetchMovies(libraryID: String, offset: Int = 0, limit: Int = 100) async throws -> [PlexMovie] {
        let queryItems = [
            URLQueryItem(name: "type", value: "1"),  // type 1 = movie
            URLQueryItem(name: "X-Plex-Container-Start", value: String(offset)),
            URLQueryItem(name: "X-Plex-Container-Size", value: String(limit))
        ]
        
        guard let request = buildRequest(path: "/library/sections/\(libraryID)/all", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        return response.mediaContainer.metadata?.map { $0.toMovie() } ?? []
    }
    
    // MARK: - TV Show Operations
    
    /// Fetch all shows in a TV show library
    /// Filters out bonus content that Plex misclassifies as TV shows
    func fetchShows(libraryID: String, offset: Int = 0, limit: Int = 100) async throws -> [PlexShow] {
        let queryItems = [
            URLQueryItem(name: "type", value: "2"),  // type 2 = show
            URLQueryItem(name: "X-Plex-Container-Start", value: String(offset)),
            URLQueryItem(name: "X-Plex-Container-Size", value: String(limit))
        ]
        
        guard let request = buildRequest(path: "/library/sections/\(libraryID)/all", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        
        // Filter out shows that are likely misclassified bonus content:
        // - Shows with very few episodes (2 or less) AND only 1 season
        // - Shows marked as extras
        return response.mediaContainer.metadata?
            .filter { item in
                // Skip items marked as extras
                if item.isExtra { return false }
                
                // Skip shows with 1 season and 2 or fewer episodes (likely bonus content)
                let seasonCount = item.childCount ?? 0
                let episodeCount = item.leafCount ?? 0
                if seasonCount <= 1 && episodeCount <= 2 {
                    NSLog("PlexServerClient: Filtering out likely bonus content show: '%@' (%d seasons, %d episodes)", 
                          item.title, seasonCount, episodeCount)
                    return false
                }
                
                return true
            }
            .map { $0.toShow() } ?? []
    }
    
    /// Fetch seasons for a specific TV show
    func fetchSeasons(forShow showID: String) async throws -> [PlexSeason] {
        guard let request = buildRequest(path: "/library/metadata/\(showID)/children") else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        return response.mediaContainer.metadata?.map { $0.toSeason() } ?? []
    }
    
    /// Fetch episodes for a specific season
    func fetchEpisodes(forSeason seasonID: String) async throws -> [PlexEpisode] {
        guard let request = buildRequest(path: "/library/metadata/\(seasonID)/children") else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        return response.mediaContainer.metadata?.map { $0.toEpisode() } ?? []
    }
    
    // MARK: - Detailed Item Metadata
    
    /// Fetch detailed metadata for a movie (includes external IDs like IMDB, TMDB)
    func fetchMovieDetails(movieID: String) async throws -> PlexMovie? {
        let queryItems = [
            URLQueryItem(name: "includeGuids", value: "1")
        ]
        guard let request = buildRequest(path: "/library/metadata/\(movieID)", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        return response.mediaContainer.metadata?.first?.toMovie()
    }
    
    /// Fetch detailed metadata for a TV show (includes external IDs like IMDB, TMDB, TVDB)
    func fetchShowDetails(showID: String) async throws -> PlexShow? {
        let queryItems = [
            URLQueryItem(name: "includeGuids", value: "1")
        ]
        guard let request = buildRequest(path: "/library/metadata/\(showID)", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        return response.mediaContainer.metadata?.first?.toShow()
    }
    
    /// Fetch detailed metadata for an episode (includes external IDs like IMDB)
    func fetchEpisodeDetails(episodeID: String) async throws -> PlexEpisode? {
        let queryItems = [
            URLQueryItem(name: "includeGuids", value: "1")
        ]
        guard let request = buildRequest(path: "/library/metadata/\(episodeID)", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        return response.mediaContainer.metadata?.first?.toEpisode()
    }
    
    /// Fetch detailed metadata for a track (includes media info, genre, year, ratings)
    func fetchTrackDetails(trackID: String) async throws -> PlexTrack? {
        guard let request = buildRequest(path: "/library/metadata/\(trackID)") else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        return response.mediaContainer.metadata?.first?.toTrack()
    }
    
    // MARK: - Search
    
    /// Search for content in a library
    func search(query: String, libraryID: String, type: SearchType = .all) async throws -> PlexSearchResults {
        // Use the hubs/search endpoint which is more reliable
        let queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "sectionId", value: libraryID),
            URLQueryItem(name: "limit", value: "50")
        ]
        
        guard let request = buildRequest(path: "/hubs/search", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        // Hub search returns a different structure with multiple hubs
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexServerError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            NSLog("Search failed with status %d", httpResponse.statusCode)
            throw PlexServerError.httpError(statusCode: httpResponse.statusCode)
        }
        
        // Parse hub search response
        struct HubSearchResponse: Decodable {
            let MediaContainer: HubContainer
        }
        struct HubContainer: Decodable {
            let Hub: [Hub]?
        }
        struct Hub: Decodable {
            let type: String
            let Metadata: [PlexMetadataDTO]?
        }
        
        let decoder = JSONDecoder()
        let hubResponse = try decoder.decode(HubSearchResponse.self, from: data)
        
        var results = PlexSearchResults()
        for hub in hubResponse.MediaContainer.Hub ?? [] {
            guard let metadata = hub.Metadata else { continue }
            
            switch hub.type {
            case "artist":
                results.artists.append(contentsOf: metadata.map { $0.toArtist() })
            case "album":
                results.albums.append(contentsOf: metadata.map { $0.toAlbum() })
            case "track":
                results.tracks.append(contentsOf: metadata.map { $0.toTrack() })
            case "movie":
                results.movies.append(contentsOf: metadata.map { $0.toMovie() })
            case "show":
                results.shows.append(contentsOf: metadata.map { $0.toShow() })
            case "episode":
                results.episodes.append(contentsOf: metadata.map { $0.toEpisode() })
            default:
                break
            }
        }
        return results
    }
    
    // MARK: - URL Generation
    
    /// Generate a streaming URL for a track
    func streamURL(for track: PlexTrack) -> URL? {
        guard let partKey = track.partKey else { return nil }
        
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = partKey
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: authToken)
        ]
        
        return components?.url
    }
    
    /// Generate a streaming URL for a movie
    func streamURL(for movie: PlexMovie) -> URL? {
        guard let partKey = movie.partKey else { return nil }
        
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = partKey
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: authToken)
        ]
        
        return components?.url
    }
    
    /// Generate a streaming URL for an episode
    func streamURL(for episode: PlexEpisode) -> URL? {
        guard let partKey = episode.partKey else { return nil }
        
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = partKey
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: authToken)
        ]
        
        return components?.url
    }
    
    // MARK: - Playlist Operations
    
    /// Fetch all playlists on the server
    func fetchPlaylists() async throws -> [PlexPlaylist] {
        guard let request = buildRequest(path: "/playlists") else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        return response.mediaContainer.metadata?.map { $0.toPlaylist() } ?? []
    }
    
    /// Fetch audio (music) playlists only
    func fetchAudioPlaylists() async throws -> [PlexPlaylist] {
        let queryItems = [
            URLQueryItem(name: "playlistType", value: "audio")
        ]
        
        guard let request = buildRequest(path: "/playlists", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        return response.mediaContainer.metadata?.map { $0.toPlaylist() } ?? []
    }
    
    /// Fetch tracks in a playlist
    /// For smart playlists, falls back to executing the filter query directly if the items endpoint fails
    /// - Parameters:
    ///   - playlistID: The playlist ratingKey
    ///   - smartContent: Optional filter URI for smart playlists (e.g., "/library/sections/15/all?type=10&...")
    func fetchPlaylistTracks(playlistID: String, smartContent: String? = nil) async throws -> [PlexTrack] {
        // Try the standard playlist items endpoint first
        guard let request = buildRequest(path: "/playlists/\(playlistID)/items") else {
            throw PlexServerError.invalidURL
        }
        
        do {
            let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
            return response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
        } catch PlexServerError.httpError(let statusCode) where statusCode == 500 {
            // Server returned 500 - try fallback for smart playlists
            NSLog("PlexServerClient: Playlist items endpoint returned 500, trying smart playlist fallback")
            
            // If we don't have the content URI, try to fetch it from the playlist details
            var contentURI = smartContent
            if contentURI == nil || contentURI!.isEmpty {
                NSLog("PlexServerClient: Fetching playlist details to get content URI")
                if let details = try? await fetchPlaylistDetails(playlistID: playlistID) {
                    contentURI = details.content
                    NSLog("PlexServerClient: Got content URI from playlist details: %@", contentURI ?? "nil")
                }
            }
            
            guard let content = contentURI, !content.isEmpty else {
                NSLog("PlexServerClient: No smart content URI available for fallback")
                throw PlexServerError.httpError(statusCode: statusCode)
            }
            
            return try await fetchSmartPlaylistContent(contentURI: content)
        }
    }
    
    /// Fetch full details for a single playlist (includes content URI for smart playlists)
    func fetchPlaylistDetails(playlistID: String) async throws -> PlexPlaylist {
        guard let request = buildRequest(path: "/playlists/\(playlistID)") else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        guard let metadata = response.mediaContainer.metadata?.first else {
            throw PlexServerError.invalidResponse
        }
        return metadata.toPlaylist()
    }
    
    /// Fetch tracks by executing a smart playlist's filter query directly
    /// - Parameter contentURI: The filter URI from the smart playlist's content field
    private func fetchSmartPlaylistContent(contentURI: String) async throws -> [PlexTrack] {
        NSLog("PlexServerClient: Fetching smart playlist via content URI: %@", contentURI)
        
        // The content URI can be in different formats:
        // 1. Direct path: "/library/sections/15/all?type=10&..."
        // 2. Plex library URI: "library://x/directory/%2Flibrary%2Fsections%2F3%2Fall%3Ftype%3D10..."
        //    This needs to be decoded - the actual path is URL-encoded after "library://x/directory/"
        
        var apiPath = contentURI
        
        if contentURI.hasPrefix("library://") {
            // Parse the library:// URI scheme
            // Format: library://x/directory/{url-encoded-path}
            if let directoryRange = contentURI.range(of: "/directory/") {
                let encodedPath = String(contentURI[directoryRange.upperBound...])
                // URL decode the path (may be double-encoded)
                var decoded = encodedPath.removingPercentEncoding ?? encodedPath
                // Handle double-encoding (e.g., %253E becomes %3E then >)
                while decoded.contains("%") && decoded != decoded.removingPercentEncoding {
                    decoded = decoded.removingPercentEncoding ?? decoded
                }
                apiPath = decoded
                NSLog("PlexServerClient: Decoded library URI to path: %@", apiPath)
            }
        }
        
        // Build the URL manually since the path may contain query parameters
        // that we don't want to double-encode
        let fullURL: URL
        if apiPath.contains("?") {
            // Path includes query string - build URL directly
            guard let url = URL(string: baseURL.absoluteString + apiPath) else {
                throw PlexServerError.invalidURL
            }
            fullURL = url
        } else {
            fullURL = baseURL.appendingPathComponent(apiPath)
        }
        
        // Add auth token to URL
        var components = URLComponents(url: fullURL, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "X-Plex-Token", value: authToken))
        components?.queryItems = queryItems
        
        guard let finalURL = components?.url else {
            throw PlexServerError.invalidURL
        }
        
        NSLog("PlexServerClient: Final smart playlist URL: %@", finalURL.absoluteString)
        
        var request = URLRequest(url: finalURL)
        for (key, value) in standardHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        let tracks = response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
        
        NSLog("PlexServerClient: Smart playlist content returned %d tracks", tracks.count)
        return tracks
    }
    
    /// Generate an artwork/thumbnail URL
    /// - Parameters:
    ///   - thumb: The thumb path from a Plex item
    ///   - width: Desired width (default 300)
    ///   - height: Desired height (default 300)
    func artworkURL(thumb: String?, width: Int = 300, height: Int = 300) -> URL? {
        guard let thumb = thumb else { return nil }
        
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/photo/:/transcode"
        components?.queryItems = [
            URLQueryItem(name: "url", value: thumb),
            URLQueryItem(name: "width", value: String(width)),
            URLQueryItem(name: "height", value: String(height)),
            URLQueryItem(name: "minSize", value: "1"),
            URLQueryItem(name: "X-Plex-Token", value: authToken)
        ]
        
        return components?.url
    }
    
    // MARK: - Playback Reporting
    
    /// Report playback state to Plex (for "Now Playing" and progress tracking)
    /// - Parameters:
    ///   - ratingKey: The item's rating key
    ///   - state: Playback state ("playing", "paused", "stopped")
    ///   - time: Current playback position in milliseconds
    ///   - duration: Total duration in milliseconds
    ///   - type: Media type ("music", "movie", "episode")
    func reportPlaybackState(
        ratingKey: String,
        state: PlaybackReportState,
        time: Int,
        duration: Int,
        type: String = "music"
    ) async throws {
        var queryItems = [
            URLQueryItem(name: "ratingKey", value: ratingKey),
            URLQueryItem(name: "key", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "state", value: state.rawValue),
            URLQueryItem(name: "time", value: String(time)),
            URLQueryItem(name: "duration", value: String(duration)),
            URLQueryItem(name: "playbackTime", value: String(time)),
            URLQueryItem(name: "type", value: type)
        ]
        
        // Add context for Now Playing display
        queryItems.append(URLQueryItem(name: "context", value: "streaming"))
        
        guard var request = buildRequest(path: "/:/timeline", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        // Timeline uses POST or GET depending on server version, but GET is most compatible
        request.httpMethod = "GET"
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexServerError.invalidResponse
        }
        
        // Timeline endpoint returns 200 on success
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw PlexServerError.unauthorized
            }
            throw PlexServerError.httpError(statusCode: httpResponse.statusCode)
        }
    }
    
    /// Mark an item as played (scrobble) - increments play count and sets last played date
    /// - Parameter ratingKey: The item's rating key
    func scrobble(ratingKey: String) async throws {
        let queryItems = [
            URLQueryItem(name: "key", value: ratingKey),
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library")
        ]
        
        guard var request = buildRequest(path: "/:/scrobble", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        request.httpMethod = "GET"
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexServerError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw PlexServerError.unauthorized
            }
            throw PlexServerError.httpError(statusCode: httpResponse.statusCode)
        }
        
        NSLog("PlexServerClient: Scrobbled item %@", ratingKey)
    }
    
    /// Mark an item as unplayed
    /// - Parameter ratingKey: The item's rating key
    func unscrobble(ratingKey: String) async throws {
        let queryItems = [
            URLQueryItem(name: "key", value: ratingKey),
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library")
        ]
        
        guard var request = buildRequest(path: "/:/unscrobble", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        request.httpMethod = "GET"
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexServerError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw PlexServerError.unauthorized
            }
            throw PlexServerError.httpError(statusCode: httpResponse.statusCode)
        }
    }
    
    /// Rate a Plex item (track, album, artist, movie, etc.)
    /// - Parameters:
    ///   - ratingKey: The Plex item's ratingKey
    ///   - rating: Rating value 0-10 (nil or -1 to clear rating)
    func rateItem(ratingKey: String, rating: Int?) async throws {
        let ratingValue = rating ?? -1
        
        // Build URL manually - query params don't need encoding for this endpoint
        let urlString = "\(baseURL.absoluteString)/:/rate?key=\(ratingKey)&identifier=com.plexapp.plugins.library&rating=\(ratingValue)&X-Plex-Token=\(authToken)"
        
        guard let url = URL(string: urlString) else {
            throw PlexServerError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        for (key, value) in standardHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexServerError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw PlexServerError.unauthorized
            }
            throw PlexServerError.httpError(statusCode: httpResponse.statusCode)
        }
        
        NSLog("PlexServerClient: Rated item %@ with rating %d", ratingKey, ratingValue)
    }
    
    /// Update playback progress (for resume functionality)
    /// - Parameters:
    ///   - ratingKey: The item's rating key
    ///   - time: Current playback position in milliseconds
    func updateProgress(ratingKey: String, time: Int) async throws {
        let queryItems = [
            URLQueryItem(name: "key", value: ratingKey),
            URLQueryItem(name: "time", value: String(time)),
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library")
        ]
        
        guard var request = buildRequest(path: "/:/progress", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        request.httpMethod = "GET"
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexServerError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw PlexServerError.unauthorized
            }
            throw PlexServerError.httpError(statusCode: httpResponse.statusCode)
        }
    }
    
    // MARK: - Radio API (Sonic Analysis)
    
    /// Create a track radio using Plex's sonic analysis
    /// - Parameters:
    ///   - trackID: The seed track's rating key
    ///   - libraryID: The library section ID
    ///   - limit: Maximum number of tracks to return
    /// - Returns: Array of sonically similar tracks
    func createTrackRadio(trackID: String, libraryID: String, limit: Int = 100) async throws -> [PlexTrack] {
        NSLog("PlexServerClient: Creating track radio for track %@ in library %@", trackID, libraryID)
        
        // Use the sonicallySimilar filter with random sort for diverse results
        let queryItems = [
            URLQueryItem(name: "type", value: "10"),  // type 10 = tracks
            URLQueryItem(name: "track.sonicallySimilar", value: trackID),
            URLQueryItem(name: "sort", value: "random"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        
        guard let request = buildRequest(path: "/library/sections/\(libraryID)/all", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        let tracks = response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
        
        NSLog("PlexServerClient: Track radio returned %d sonically similar tracks", tracks.count)
        return tracks
    }
    
    /// Create an artist radio using Plex's sonic analysis
    /// Fetches tracks from sonically similar artists
    /// - Parameters:
    ///   - artistID: The seed artist's rating key
    ///   - libraryID: The library section ID
    ///   - limit: Maximum number of tracks to return
    /// - Returns: Array of tracks from similar artists
    func createArtistRadio(artistID: String, libraryID: String, limit: Int = 100) async throws -> [PlexTrack] {
        NSLog("PlexServerClient: Creating artist radio for artist %@ in library %@", artistID, libraryID)
        
        // First get sonically similar artists
        let artistQueryItems = [
            URLQueryItem(name: "type", value: "8"),  // type 8 = artists
            URLQueryItem(name: "artist.sonicallySimilar", value: artistID),
            URLQueryItem(name: "limit", value: "15")
        ]
        
        guard let artistRequest = buildRequest(path: "/library/sections/\(libraryID)/all", queryItems: artistQueryItems) else {
            throw PlexServerError.invalidURL
        }
        
        let artistResponse: PlexResponse<PlexMetadataResponse> = try await performRequest(artistRequest)
        let similarArtists = artistResponse.mediaContainer.metadata ?? []
        
        NSLog("PlexServerClient: Found %d similar artists", similarArtists.count)
        
        if similarArtists.isEmpty {
            return []
        }
        
        // Get tracks from each similar artist
        var allTracks: [PlexTrack] = []
        let tracksPerArtist = max(5, limit / similarArtists.count)
        
        for artist in similarArtists {
            let trackQueryItems = [
                URLQueryItem(name: "type", value: "10"),
                URLQueryItem(name: "artist.id", value: artist.ratingKey),
                URLQueryItem(name: "sort", value: "random"),
                URLQueryItem(name: "limit", value: String(tracksPerArtist))
            ]
            
            guard let trackRequest = buildRequest(path: "/library/sections/\(libraryID)/all", queryItems: trackQueryItems) else {
                continue
            }
            
            do {
                let trackResponse: PlexResponse<PlexMetadataResponse> = try await performRequest(trackRequest)
                let tracks = trackResponse.mediaContainer.metadata?.map { $0.toTrack() } ?? []
                allTracks.append(contentsOf: tracks)
            } catch {
                NSLog("PlexServerClient: Failed to get tracks for artist %@: %@", artist.ratingKey, error.localizedDescription)
            }
            
            if allTracks.count >= limit {
                break
            }
        }
        
        // Shuffle and limit the final result
        let result = Array(allTracks.shuffled().prefix(limit))
        NSLog("PlexServerClient: Artist radio created with %d tracks", result.count)
        return result
    }
    
    /// Create an album radio using Plex's sonic analysis
    /// - Parameters:
    ///   - albumID: The seed album's rating key
    ///   - libraryID: The library section ID
    ///   - limit: Maximum number of tracks to return
    /// - Returns: Array of tracks from sonically similar albums
    func createAlbumRadio(albumID: String, libraryID: String, limit: Int = 100) async throws -> [PlexTrack] {
        NSLog("PlexServerClient: Creating album radio for album %@ in library %@", albumID, libraryID)
        
        // Get sonically similar albums
        let albumQueryItems = [
            URLQueryItem(name: "type", value: "9"),  // type 9 = albums
            URLQueryItem(name: "album.sonicallySimilar", value: albumID),
            URLQueryItem(name: "limit", value: "10")
        ]
        
        guard let albumRequest = buildRequest(path: "/library/sections/\(libraryID)/all", queryItems: albumQueryItems) else {
            throw PlexServerError.invalidURL
        }
        
        let albumResponse: PlexResponse<PlexMetadataResponse> = try await performRequest(albumRequest)
        let similarAlbums = albumResponse.mediaContainer.metadata ?? []
        
        NSLog("PlexServerClient: Found %d similar albums", similarAlbums.count)
        
        if similarAlbums.isEmpty {
            return []
        }
        
        // Get tracks from each similar album
        var allTracks: [PlexTrack] = []
        let tracksPerAlbum = max(5, limit / similarAlbums.count)
        
        for album in similarAlbums {
            let tracks = try await fetchTracks(forAlbum: album.ratingKey)
            let shuffledTracks = tracks.shuffled().prefix(tracksPerAlbum)
            allTracks.append(contentsOf: shuffledTracks)
            
            if allTracks.count >= limit {
                break
            }
        }
        
        // Shuffle and limit the final result
        let result = Array(allTracks.shuffled().prefix(limit))
        NSLog("PlexServerClient: Album radio created with %d tracks", result.count)
        return result
    }
    
    // MARK: - Genre Fetching
    
    /// Fetch available genres from a music library
    func fetchGenres(libraryID: String) async throws -> [String] {
        NSLog("PlexServerClient: Fetching genres for library %@", libraryID)
        
        guard let request = buildRequest(path: "/library/sections/\(libraryID)/genre") else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexGenreResponse> = try await performRequest(request)
        let genres = response.mediaContainer.directory?.compactMap { $0.title } ?? []
        NSLog("PlexServerClient: Found %d genres", genres.count)
        return genres
    }
    
    // MARK: - Extended Radio API (Non-Sonic and Sonic Versions)
    
    /// Library Radio - Non-Sonic (random tracks from library)
    func createLibraryRadio(libraryID: String, limit: Int = RadioConfig.defaultLimit) async throws -> [PlexTrack] {
        NSLog("PlexServerClient: Creating library radio (non-sonic) for library %@", libraryID)
        
        let queryItems = [
            URLQueryItem(name: "type", value: "10"),
            URLQueryItem(name: "sort", value: "random"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        
        guard let request = buildRequest(path: "/library/sections/\(libraryID)/all", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        let tracks = response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
        NSLog("PlexServerClient: Library radio returned %d tracks", tracks.count)
        return tracks
    }
    
    /// Library Radio - Sonic (sonically similar to seed track)
    /// Uses sort=random to get varied results from the sonically similar pool
    func createLibraryRadioSonic(trackID: String, libraryID: String, limit: Int = RadioConfig.defaultLimit) async throws -> [PlexTrack] {
        NSLog("PlexServerClient: Creating library radio (sonic) for track %@ in library %@", trackID, libraryID)
        
        let queryItems = [
            URLQueryItem(name: "type", value: "10"),
            URLQueryItem(name: "track.sonicallySimilar", value: trackID),
            URLQueryItem(name: "sort", value: "random"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        
        guard let request = buildRequest(path: "/library/sections/\(libraryID)/all", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        let tracks = response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
        NSLog("PlexServerClient: Library radio (sonic) returned %d tracks", tracks.count)
        return tracks
    }
    
    /// Genre Radio - Non-Sonic
    func createGenreRadio(genre: String, libraryID: String, limit: Int = RadioConfig.defaultLimit) async throws -> [PlexTrack] {
        NSLog("PlexServerClient: Creating genre radio (non-sonic) for %@ in library %@", genre, libraryID)
        
        let queryItems = [
            URLQueryItem(name: "type", value: "10"),
            URLQueryItem(name: "genre", value: genre),
            URLQueryItem(name: "sort", value: "random"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        
        guard let request = buildRequest(path: "/library/sections/\(libraryID)/all", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        let tracks = response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
        NSLog("PlexServerClient: Genre radio returned %d tracks", tracks.count)
        return tracks
    }
    
    /// Genre Radio - Sonic (requires seed track)
    /// Uses sort=random to get varied results from the sonically similar pool
    func createGenreRadioSonic(genre: String, trackID: String, libraryID: String, limit: Int = RadioConfig.defaultLimit) async throws -> [PlexTrack] {
        NSLog("PlexServerClient: Creating genre radio (sonic) for %@ with seed %@ in library %@", genre, trackID, libraryID)
        
        let queryItems = [
            URLQueryItem(name: "type", value: "10"),
            URLQueryItem(name: "genre", value: genre),
            URLQueryItem(name: "track.sonicallySimilar", value: trackID),
            URLQueryItem(name: "sort", value: "random"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        
        guard let request = buildRequest(path: "/library/sections/\(libraryID)/all", queryItems: queryItems) else {
            throw PlexServerError.invalidURL
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        let tracks = response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
        NSLog("PlexServerClient: Genre radio (sonic) returned %d tracks", tracks.count)
        return tracks
    }
    
    /// Decade Radio - Non-Sonic
    /// - Note: Uses raw query string because Plex requires literal >= and <= operators
    func createDecadeRadio(startYear: Int, endYear: Int, libraryID: String, limit: Int = RadioConfig.defaultLimit) async throws -> [PlexTrack] {
        NSLog("PlexServerClient: Creating decade radio (non-sonic) for %d-%d in library %@", startYear, endYear, libraryID)
        
        // Build URL manually - Plex filter syntax requires unencoded >= and <= operators
        let urlString = "\(baseURL.absoluteString)/library/sections/\(libraryID)/all?type=10&year>=\(startYear)&year<=\(endYear)&sort=random&limit=\(limit)&X-Plex-Token=\(authToken)"
        
        guard let url = URL(string: urlString) else {
            throw PlexServerError.invalidURL
        }
        
        var request = URLRequest(url: url)
        for (key, value) in standardHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        let tracks = response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
        NSLog("PlexServerClient: Decade radio returned %d tracks", tracks.count)
        return tracks
    }
    
    /// Decade Radio - Sonic
    /// Uses sort=random to get varied results from the sonically similar pool
    /// - Note: Uses raw query string because Plex requires literal >= and <= operators
    func createDecadeRadioSonic(startYear: Int, endYear: Int, trackID: String, libraryID: String, limit: Int = RadioConfig.defaultLimit) async throws -> [PlexTrack] {
        NSLog("PlexServerClient: Creating decade radio (sonic) for %d-%d with seed %@ in library %@", startYear, endYear, trackID, libraryID)
        
        // Build URL manually - Plex filter syntax requires unencoded >= and <= operators
        let urlString = "\(baseURL.absoluteString)/library/sections/\(libraryID)/all?type=10&year>=\(startYear)&year<=\(endYear)&track.sonicallySimilar=\(trackID)&sort=random&limit=\(limit)&X-Plex-Token=\(authToken)"
        
        guard let url = URL(string: urlString) else {
            throw PlexServerError.invalidURL
        }
        
        var request = URLRequest(url: url)
        for (key, value) in standardHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        let tracks = response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
        NSLog("PlexServerClient: Decade radio (sonic) returned %d tracks", tracks.count)
        return tracks
    }
    
    /// Only the Hits Radio - Non-Sonic
    /// - Note: Uses raw query string because Plex requires literal >= operator
    func createHitsRadio(libraryID: String, limit: Int = RadioConfig.defaultLimit) async throws -> [PlexTrack] {
        NSLog("PlexServerClient: Creating hits radio (non-sonic) in library %@", libraryID)
        
        // Build URL manually - Plex filter syntax requires unencoded >= operator
        let urlString = "\(baseURL.absoluteString)/library/sections/\(libraryID)/all?type=10&ratingCount>=\(RadioConfig.hitsThreshold)&sort=random&limit=\(limit)&X-Plex-Token=\(authToken)"
        
        guard let url = URL(string: urlString) else {
            throw PlexServerError.invalidURL
        }
        
        var request = URLRequest(url: url)
        for (key, value) in standardHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        let tracks = response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
        NSLog("PlexServerClient: Hits radio returned %d tracks", tracks.count)
        return tracks
    }
    
    /// Only the Hits Radio - Sonic
    /// Uses sort=random to get varied results from the sonically similar pool
    /// - Note: Uses raw query string because Plex requires literal >= operator
    func createHitsRadioSonic(trackID: String, libraryID: String, limit: Int = RadioConfig.defaultLimit) async throws -> [PlexTrack] {
        NSLog("PlexServerClient: Creating hits radio (sonic) with seed %@ in library %@", trackID, libraryID)
        
        // Build URL manually - Plex filter syntax requires unencoded >= operator
        let urlString = "\(baseURL.absoluteString)/library/sections/\(libraryID)/all?type=10&ratingCount>=\(RadioConfig.hitsThreshold)&track.sonicallySimilar=\(trackID)&sort=random&limit=\(limit)&X-Plex-Token=\(authToken)"
        
        guard let url = URL(string: urlString) else {
            throw PlexServerError.invalidURL
        }
        
        var request = URLRequest(url: url)
        for (key, value) in standardHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        let tracks = response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
        NSLog("PlexServerClient: Hits radio (sonic) returned %d tracks", tracks.count)
        return tracks
    }
    
    /// Deep Cuts Radio - Non-Sonic
    /// - Note: Uses raw query string because Plex requires literal <= operator (not URL-encoded)
    func createDeepCutsRadio(libraryID: String, limit: Int = RadioConfig.defaultLimit) async throws -> [PlexTrack] {
        NSLog("PlexServerClient: Creating deep cuts radio (non-sonic) in library %@", libraryID)
        
        // Build URL manually - Plex filter syntax requires unencoded <= operator
        // Using <= with threshold-1 because Plex doesn't support < operator (only >=, <=, =, !=)
        let urlString = "\(baseURL.absoluteString)/library/sections/\(libraryID)/all?type=10&ratingCount<=\(RadioConfig.deepCutsThreshold - 1)&sort=random&limit=\(limit)&X-Plex-Token=\(authToken)"
        
        guard let url = URL(string: urlString) else {
            throw PlexServerError.invalidURL
        }
        
        var request = URLRequest(url: url)
        for (key, value) in standardHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        let tracks = response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
        NSLog("PlexServerClient: Deep cuts radio returned %d tracks", tracks.count)
        return tracks
    }
    
    /// Deep Cuts Radio - Sonic
    /// Uses sort=random to get varied results from the sonically similar pool
    /// - Note: Uses raw query string because Plex requires literal <= operator (not URL-encoded)
    func createDeepCutsRadioSonic(trackID: String, libraryID: String, limit: Int = RadioConfig.defaultLimit) async throws -> [PlexTrack] {
        NSLog("PlexServerClient: Creating deep cuts radio (sonic) with seed %@ in library %@", trackID, libraryID)
        
        // Build URL manually - Plex filter syntax requires unencoded <= operator
        // Using <= with threshold-1 because Plex doesn't support < operator (only >=, <=, =, !=)
        let urlString = "\(baseURL.absoluteString)/library/sections/\(libraryID)/all?type=10&ratingCount<=\(RadioConfig.deepCutsThreshold - 1)&track.sonicallySimilar=\(trackID)&sort=random&limit=\(limit)&X-Plex-Token=\(authToken)"
        
        guard let url = URL(string: urlString) else {
            throw PlexServerError.invalidURL
        }
        
        var request = URLRequest(url: url)
        for (key, value) in standardHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        let tracks = response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
        NSLog("PlexServerClient: Deep cuts radio (sonic) returned %d tracks", tracks.count)
        return tracks
    }
    
    // MARK: - Rating Radio
    
    /// Rating Radio - Non-Sonic
    /// Plays tracks the user has rated at or above the minimum rating threshold
    /// - Parameters:
    ///   - minRating: Minimum user rating (0-10 scale, where 10 = 5 stars)
    ///   - libraryID: The library section ID
    ///   - limit: Maximum number of tracks to return
    /// - Note: Uses raw query string for userRating filter because Plex requires
    ///   literal `>=` in the URL (URLQueryItem would encode it as %3E%3D which breaks filtering)
    func createRatingRadio(minRating: Double, libraryID: String, limit: Int = RadioConfig.defaultLimit) async throws -> [PlexTrack] {
        NSLog("PlexServerClient: Creating rating radio (non-sonic) with minRating %.1f in library %@", minRating, libraryID)
        
        // Build URL manually - Plex filter syntax requires unencoded >= in parameter name
        // URLQueryItem would encode "userRating>=" as "userRating%3E%3D" which Plex ignores
        // Use max(1, ...) to ensure "All Rated" (minRating=0.1) filters to userRating>=1, not >=0
        let ratingFilter = max(1, Int(minRating))
        let urlString = "\(baseURL.absoluteString)/library/sections/\(libraryID)/all?type=10&userRating>=\(ratingFilter)&sort=random&limit=\(limit)&X-Plex-Token=\(authToken)"
        
        guard let url = URL(string: urlString) else {
            throw PlexServerError.invalidURL
        }
        
        var request = URLRequest(url: url)
        for (key, value) in standardHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        let tracks = response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
        NSLog("PlexServerClient: Rating radio returned %d tracks", tracks.count)
        return tracks
    }
    
    /// Rating Radio - Sonic
    /// Plays tracks sonically similar to the seed that are rated at or above the minimum rating
    /// - Parameters:
    ///   - minRating: Minimum user rating (0-10 scale, where 10 = 5 stars)
    ///   - trackID: The seed track ID for sonic similarity
    ///   - libraryID: The library section ID
    ///   - limit: Maximum number of tracks to return
    /// - Note: Uses raw query string for userRating filter because Plex requires
    ///   literal `>=` in the URL (URLQueryItem would encode it as %3E%3D which breaks filtering)
    func createRatingRadioSonic(minRating: Double, trackID: String, libraryID: String, limit: Int = RadioConfig.defaultLimit) async throws -> [PlexTrack] {
        NSLog("PlexServerClient: Creating rating radio (sonic) with minRating %.1f, seed %@ in library %@", minRating, trackID, libraryID)
        
        // Build URL manually - Plex filter syntax requires unencoded >= in parameter name
        // URLQueryItem would encode "userRating>=" as "userRating%3E%3D" which Plex ignores
        // Use max(1, ...) to ensure "All Rated" (minRating=0.1) filters to userRating>=1, not >=0
        let ratingFilter = max(1, Int(minRating))
        let urlString = "\(baseURL.absoluteString)/library/sections/\(libraryID)/all?type=10&userRating>=\(ratingFilter)&track.sonicallySimilar=\(trackID)&sort=random&limit=\(limit)&X-Plex-Token=\(authToken)"
        
        guard let url = URL(string: urlString) else {
            throw PlexServerError.invalidURL
        }
        
        var request = URLRequest(url: url)
        for (key, value) in standardHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let response: PlexResponse<PlexMetadataResponse> = try await performRequest(request)
        let tracks = response.mediaContainer.metadata?.map { $0.toTrack() } ?? []
        NSLog("PlexServerClient: Rating radio (sonic) returned %d tracks", tracks.count)
        return tracks
    }
    
    // MARK: - Server Status
    
    /// Check if the server is reachable (with short timeout)
    func checkConnection() async -> Bool {
        guard let request = buildRequest(path: "/") else { return false }
        
        // Use a shorter timeout for connection checks
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5  // 5 seconds
        config.timeoutIntervalForResource = 10
        let quickSession = URLSession(configuration: config)
        
        do {
            let (_, response) = try await quickSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 200
        } catch {
            NSLog("PlexServerClient: Connection check failed: %@", error.localizedDescription)
            return false
        }
    }
}

// MARK: - Supporting Types

enum SearchType: Int {
    case all = 0
    case artist = 8
    case album = 9
    case track = 10
}

/// Playback state for timeline reporting
enum PlaybackReportState: String {
    case playing = "playing"
    case paused = "paused"
    case stopped = "stopped"
}

struct PlexSearchResults {
    var artists: [PlexArtist] = []
    var albums: [PlexAlbum] = []
    var tracks: [PlexTrack] = []
    var movies: [PlexMovie] = []
    var shows: [PlexShow] = []
    var episodes: [PlexEpisode] = []
    
    var isEmpty: Bool {
        artists.isEmpty && albums.isEmpty && tracks.isEmpty &&
        movies.isEmpty && shows.isEmpty && episodes.isEmpty
    }
    
    var totalCount: Int {
        artists.count + albums.count + tracks.count +
        movies.count + shows.count + episodes.count
    }
    
    var hasMusicResults: Bool {
        !artists.isEmpty || !albums.isEmpty || !tracks.isEmpty
    }
    
    var hasVideoResults: Bool {
        !movies.isEmpty || !shows.isEmpty || !episodes.isEmpty
    }
}

// MARK: - Errors

enum PlexServerError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case unauthorized
    case serverOffline
    case networkError(Error)
    case allConnectionsFailed(serverName: String, tried: String)
    case noMusicLibrary
    case noVideoLibrary
    case noMovieLibrary
    case noShowLibrary
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "Server error: \(code)"
        case .unauthorized:
            return "Not authorized to access this server"
        case .serverOffline:
            return "Server is offline or unreachable"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .allConnectionsFailed(let serverName, let tried):
            return "Could not connect to '\(serverName)'. Tried:\n\(tried)"
        case .noMusicLibrary:
            return "No music library on this server"
        case .noVideoLibrary:
            return "No video library on this server"
        case .noMovieLibrary:
            return "No movie library on this server"
        case .noShowLibrary:
            return "No TV show library on this server"
        }
    }
}
