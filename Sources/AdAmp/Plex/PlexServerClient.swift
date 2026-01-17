import Foundation

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
    
    // MARK: - Request Building
    
    private func buildRequest(path: String, queryItems: [URLQueryItem]? = nil) -> URLRequest? {
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
    private func performRequest<T: Decodable>(_ request: URLRequest, retryCount: Int = 0) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PlexServerError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 {
                    throw PlexServerError.unauthorized
                }
                throw PlexServerError.httpError(statusCode: httpResponse.statusCode)
            }
            
            return try JSONDecoder().decode(T.self, from: data)
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
    
    // MARK: - Artist Operations
    
    /// Fetch all artists in a music library
    func fetchArtists(libraryID: String, offset: Int = 0, limit: Int = 100) async throws -> [PlexArtist] {
        let queryItems = [
            URLQueryItem(name: "type", value: "8"),  // type 8 = artist
            URLQueryItem(name: "X-Plex-Container-Start", value: String(offset)),
            URLQueryItem(name: "X-Plex-Container-Size", value: String(limit))
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
    
    // MARK: - Server Status
    
    /// Check if the server is reachable
    func checkConnection() async -> Bool {
        guard let request = buildRequest(path: "/") else { return false }
        
        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 200
        } catch {
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

struct PlexSearchResults {
    var artists: [PlexArtist] = []
    var albums: [PlexAlbum] = []
    var tracks: [PlexTrack] = []
    
    var isEmpty: Bool {
        artists.isEmpty && albums.isEmpty && tracks.isEmpty
    }
    
    var totalCount: Int {
        artists.count + albums.count + tracks.count
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
        }
    }
}
