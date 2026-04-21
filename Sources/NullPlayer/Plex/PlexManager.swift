import Foundation
import AppKit
import NullPlayerCore

/// Singleton managing Plex account linking, server discovery, and state
class PlexManager {
    
    // MARK: - Singleton
    
    static let shared = PlexManager()
    
    // MARK: - Notifications
    
    static let accountDidChangeNotification = Notification.Name("PlexAccountDidChange")
    static let serversDidChangeNotification = Notification.Name("PlexServersDidChange")
    static let libraryDidChangeNotification = Notification.Name("PlexLibraryDidChange")
    static let connectionStateDidChangeNotification = Notification.Name("PlexConnectionStateDidChange")
    
    // MARK: - Account State
    
    /// The linked Plex account (nil if not linked)
    private(set) var account: PlexAccount? {
        didSet {
            NotificationCenter.default.post(name: Self.accountDidChangeNotification, object: self)
        }
    }
    
    /// Whether a Plex account is linked
    var isLinked: Bool {
        account != nil
    }
    
    // MARK: - Server State
    
    /// All discovered servers for the account
    private(set) var servers: [PlexServer] = [] {
        didSet {
            NotificationCenter.default.post(name: Self.serversDidChangeNotification, object: self)
        }
    }
    
    /// Currently selected server
    private(set) var currentServer: PlexServer? {
        didSet {
            // Reset client and library when server changes
            if oldValue?.id != currentServer?.id {
                serverClient = nil
                currentLibrary = nil
                if let server = currentServer, let token = account?.authToken {
                    serverClient = PlexServerClient(server: server, authToken: token)
                }
            }
            // Only save to UserDefaults if we have a valid server (don't overwrite with nil)
            if let serverId = currentServer?.id {
                UserDefaults.standard.set(serverId, forKey: "PlexCurrentServerID")
            }
        }
    }
    
    /// Currently selected library (can be any type - music, movies, or shows)
    private(set) var currentLibrary: PlexLibrary? {
        didSet {
            // Clear cached content when library changes
            if oldValue?.id != currentLibrary?.id {
                clearCachedContent()
            }
            NotificationCenter.default.post(name: Self.libraryDidChangeNotification, object: self)
            // Only save to UserDefaults if we have a valid library (don't overwrite with nil)
            if let libraryId = currentLibrary?.id {
                UserDefaults.standard.set(libraryId, forKey: "PlexCurrentLibraryID")
            }
        }
    }
    
    /// Client for the current server
    private(set) var serverClient: PlexServerClient?
    
    /// All available libraries on the current server (music, movies, shows)
    private(set) var availableLibraries: [PlexLibrary] = []

    /// Task for the initial background server refresh — awaitable by CLI mode
    private(set) var serverRefreshTask: Task<Void, Never>?
    
    // MARK: - Cached Library Content
    
    /// Notification posted when library content is preloaded
    static let libraryContentDidPreloadNotification = Notification.Name("PlexLibraryContentDidPreload")
    
    /// Cached artists for music library
    private(set) var cachedArtists: [PlexArtist] = []
    
    /// Cached albums for music library
    private(set) var cachedAlbums: [PlexAlbum] = []
    
    /// Cached movies for movie library
    private(set) var cachedMovies: [PlexMovie] = []
    
    /// Cached TV shows for show library
    private(set) var cachedShows: [PlexShow] = []
    
    /// Cached playlists (not library-specific)
    private(set) var cachedPlaylists: [PlexPlaylist] = []
    
    /// Whether library content has been preloaded
    private(set) var isContentPreloaded: Bool = false
    
    /// Loading state for preload
    private(set) var isPreloading: Bool = false
    
    // MARK: - Connection State
    
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case error(Error)
    }
    
    private(set) var connectionState: ConnectionState = .disconnected {
        didSet {
            NotificationCenter.default.post(name: Self.connectionStateDidChangeNotification, object: self)
        }
    }
    
    // MARK: - Private Properties
    
    private let authClient: PlexAuthClient
    private var linkingTask: Task<Bool, Error>?
    
    /// Flag to prevent concurrent server refreshes
    private var isRefreshing: Bool = false
    
    // MARK: - Initialization
    
    private init() {
        authClient = PlexAuthClient()
        loadSavedAccount()
    }
    
    // MARK: - Account Persistence
    
    private func loadSavedAccount() {
        guard let savedAccount = KeychainHelper.shared.getPlexAccount() else {
            Log.server.infoPublic("PlexManager: No saved account found in keychain")
            return
        }
        
        Log.server.infoPublic("PlexManager: Found saved account: \(savedAccount.username)")
        self.account = savedAccount
        
        // Restore servers and selection in background
        serverRefreshTask = Task {
            await refreshServersInBackground()
        }
    }
    
    private func saveAccount() {
        guard let account = account else {
            KeychainHelper.shared.clearPlexCredentials()
            return
        }
        _ = KeychainHelper.shared.setPlexAccount(account)
    }
    
    // MARK: - Account Linking (PIN Flow)
    
    /// Start the PIN-based account linking process
    /// - Returns: The PIN to display to the user
    func startLinking() async throws -> PlexPIN {
        // Create a new PIN
        let pin = try await authClient.createPIN()
        return pin
    }
    
    /// Open the plex.tv/link page in the browser
    func openLinkPage() {
        authClient.openLinkPage()
    }
    
    /// Poll for PIN authorization
    /// - Parameters:
    ///   - pin: The PIN from startLinking()
    ///   - onUpdate: Optional callback for progress updates
    /// - Returns: true if authorization succeeded
    @discardableResult
    func pollForAuthorization(pin: PlexPIN, onUpdate: ((PlexPIN) -> Void)? = nil) async throws -> Bool {
        // Cancel any existing linking task
        linkingTask?.cancel()
        
        let task = Task {
            let authorizedPIN = try await authClient.pollForAuthorization(pin: pin, onUpdate: onUpdate)
            
            guard let token = authorizedPIN.authToken else {
                throw PlexAuthError.unauthorized
            }
            
            // Fetch user info
            let userAccount = try await authClient.fetchUser(token: token)
            
            // Update state on main thread
            await MainActor.run {
                self.account = userAccount
                self.saveAccount()
            }
            
            // Fetch servers
            try await refreshServers()
            
            return true
        }
        
        linkingTask = task
        return try await task.value
    }
    
    /// Cancel any in-progress linking
    func cancelLinking() {
        linkingTask?.cancel()
        linkingTask = nil
    }
    
    /// Unlink the Plex account and clear all credentials
    func unlinkAccount() {
        // Cancel any operations
        linkingTask?.cancel()
        linkingTask = nil
        
        // Clear state
        account = nil
        servers = []
        currentServer = nil
        currentLibrary = nil
        serverClient = nil
        availableLibraries = []
        connectionState = .disconnected
        
        // Clear cached content
        clearCachedContent()
        
        // Clear saved data
        KeychainHelper.shared.clearPlexCredentials()
        UserDefaults.standard.removeObject(forKey: "PlexCurrentServerID")
        UserDefaults.standard.removeObject(forKey: "PlexCurrentLibraryID")
    }
    
    // MARK: - Server Management
    
    /// Refresh the list of available servers
    func refreshServers() async throws {
        guard let token = account?.authToken else {
            throw PlexAuthError.unauthorized
        }
        
        // Skip if already refreshing to prevent race conditions
        guard !isRefreshing else {
            Log.server.infoPublic("PlexManager: Already refreshing servers, skipping duplicate request")
            return
        }
        
        isRefreshing = true
        defer { isRefreshing = false }
        
        connectionState = .connecting
        
        do {
            let fetchedServers = try await authClient.fetchResources(token: token)
            Log.server.infoPublic("PlexManager: Fetched \(fetchedServers.count) servers")
            
            await MainActor.run {
                self.servers = fetchedServers
            }
            
            // Determine which server to connect to
            var serverToConnect: PlexServer? = nil
            
            if let savedServerID = UserDefaults.standard.string(forKey: "PlexCurrentServerID"),
               let savedServer = fetchedServers.first(where: { $0.id == savedServerID }) {
                serverToConnect = savedServer
                Log.server.infoPublic("PlexManager: Will connect to saved server: \(savedServer.name)")
            } else if let firstServer = fetchedServers.first {
                serverToConnect = firstServer
                Log.server.infoPublic("PlexManager: Will connect to first server: \(firstServer.name)")
            }
            
            // Connect to the server using the full connection logic (tries all connections)
            if let server = serverToConnect {
                do {
                    try await connect(to: server)
                } catch {
                    Log.server.errorPublic("PlexManager: Failed to connect to server \(server.name): \(error.localizedDescription)")
                    // Don't throw - we still have the server list, just no active connection
                    connectionState = .disconnected
                }
            } else {
                connectionState = .disconnected
            }
        } catch {
            connectionState = .error(error)
            throw error
        }
    }
    
    /// Refresh servers without throwing (for background refresh)
    private func refreshServersInBackground() async {
        do {
            Log.server.infoPublic("PlexManager: Background refresh of servers starting...")
            try await refreshServers()
            Log.server.infoPublic("PlexManager: Background refresh completed, found \(servers.count) servers")
            
            // Preload library content after successful server connection
            await preloadLibraryContent()
        } catch {
            Log.server.errorPublic("PlexManager: Background refresh failed: \(error.localizedDescription)")
        }
    }
    
    /// Preload library content in the background for faster Plex browser opening
    func preloadLibraryContent() async {
        guard let client = serverClient else {
            Log.server.errorPublic("PlexManager: Cannot preload - no server connected")
            return
        }

        guard !isPreloading else {
            Log.server.infoPublic("PlexManager: Already preloading, skipping")
            return
        }

        await MainActor.run {
            isPreloading = true
        }

        Log.server.infoPublic("PlexManager: Starting library content preload")

        // Preload music from the current library if it's a music library
        if let musicLib = currentLibrary, musicLib.isMusicLibrary {
            do {
                Log.server.infoPublic("PlexManager: Fetching artists...")
                let artists = try await client.fetchAllArtists(libraryID: musicLib.id)
                Log.server.infoPublic("PlexManager: Fetched \(artists.count) artists, now fetching albums...")
                let albums = try await client.fetchAlbums(libraryID: musicLib.id, offset: 0, limit: 10000)
                Log.server.infoPublic("PlexManager: Fetched \(albums.count) albums")

                await MainActor.run {
                    if self.currentLibrary?.id == musicLib.id {
                        self.cachedArtists = artists
                        self.cachedAlbums = albums
                        Log.server.infoPublic("PlexManager: Stored preloaded music - \(artists.count) artists, \(albums.count) albums")
                    }
                }
            } catch {
                Log.server.errorPublic("PlexManager: Music preload failed: \(error.localizedDescription)")
            }
        }

        // Preload movies from selected movie library, falling back to first movie library
        let movieLib = (currentLibrary?.isMovieLibrary == true ? currentLibrary : nil)
            ?? availableLibraries.first(where: { $0.isMovieLibrary })
        if let movieLib = movieLib {
            do {
                Log.server.infoPublic("PlexManager: Fetching movies from '\(movieLib.title)'...")
                let movies = try await client.fetchMovies(libraryID: movieLib.id, offset: 0, limit: 500)
                await MainActor.run {
                    let activeMovieLib = (self.currentLibrary?.isMovieLibrary == true ? self.currentLibrary : nil)
                        ?? self.availableLibraries.first(where: { $0.isMovieLibrary })
                    if activeMovieLib?.id == movieLib.id {
                        self.cachedMovies = movies
                        Log.server.infoPublic("PlexManager: Stored preloaded movies - \(movies.count)")
                    }
                }
            } catch {
                Log.server.errorPublic("PlexManager: Movie preload failed: \(error.localizedDescription)")
            }
        }

        // Preload shows from selected show library, falling back to first show library
        let showLib = (currentLibrary?.isShowLibrary == true ? currentLibrary : nil)
            ?? availableLibraries.first(where: { $0.isShowLibrary })
        if let showLib = showLib {
            do {
                Log.server.infoPublic("PlexManager: Fetching shows from '\(showLib.title)'...")
                let shows = try await client.fetchShows(libraryID: showLib.id, offset: 0, limit: 500)
                await MainActor.run {
                    let activeShowLib = (self.currentLibrary?.isShowLibrary == true ? self.currentLibrary : nil)
                        ?? self.availableLibraries.first(where: { $0.isShowLibrary })
                    if activeShowLib?.id == showLib.id {
                        self.cachedShows = shows
                        Log.server.infoPublic("PlexManager: Stored preloaded shows - \(shows.count)")
                    }
                }
            } catch {
                Log.server.errorPublic("PlexManager: Show preload failed: \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            self.isContentPreloaded = true
            self.isPreloading = false
            NotificationCenter.default.post(name: Self.libraryContentDidPreloadNotification, object: self)
        }

        Log.server.infoPublic("PlexManager: Library content preload complete")
    }
    
    /// Clear cached library content (called when library or server changes, or on refresh)
    func clearCachedContent() {
        cachedArtists = []
        cachedAlbums = []
        cachedMovies = []
        cachedShows = []
        cachedPlaylists = []
        isContentPreloaded = false
    }
    
    /// Connect to a specific server
    func connect(to server: PlexServer) async throws {
        guard let token = account?.authToken else {
            throw PlexAuthError.unauthorized
        }
        
        Log.server.infoPublic("PlexManager: Connecting to server '\(server.name)' (id: \(server.id))")
        Log.server.infoPublic("PlexManager: Server has \(server.connections.count) connections")
        for (index, conn) in server.connections.enumerated() {
            Log.server.infoPublic("  Connection \(index): \(conn.uri) (local: \(conn.local ? 1 : 0), relay: \(conn.relay ? 1 : 0))")
        }
        
        connectionState = .connecting
        
        // Try each connection in order until one works
        // Order: local non-relay, remote non-relay, relay
        let sortedConnections = server.connections.sorted { c1, c2 in
            // Prefer local, then non-relay
            if c1.local != c2.local { return c1.local }
            if c1.relay != c2.relay { return !c1.relay }
            return false
        }
        
        var lastError: Error = PlexServerError.serverOffline
        var workingClient: PlexServerClient? = nil
        var triedConnections: [String] = []
        
        for connection in sortedConnections {
            guard connection.url != nil else {
                Log.server.infoPublic("PlexManager: Skipping connection with invalid URL: \(connection.uri)")
                continue
            }
            
            let connType = connection.local ? "local" : (connection.relay ? "relay" : "remote")
            Log.server.infoPublic("PlexManager: Trying connection: \(connection.uri) (\(connType))")
            triedConnections.append("\(connType): \(connection.uri)")
            
            // Create a temporary server with just this connection to test it
            let testServer = PlexServer(
                id: server.id,
                name: server.name,
                product: server.product,
                productVersion: server.productVersion,
                platform: server.platform,
                platformVersion: server.platformVersion,
                device: server.device,
                owned: server.owned,
                connections: [connection],
                accessToken: server.accessToken
            )
            
            guard let client = PlexServerClient(server: testServer, authToken: token) else {
                Log.server.errorPublic("PlexManager: Failed to create client for connection: \(connection.uri)")
                continue
            }
            
            // Check connection with short timeout
            let isOnline = await client.checkConnection()
            if isOnline {
                Log.server.infoPublic("PlexManager: Connection successful: \(connection.uri)")
                workingClient = client
                break
            } else {
                Log.server.errorPublic("PlexManager: Connection failed: \(connection.uri)")
                lastError = PlexServerError.serverOffline
            }
        }
        
        guard let client = workingClient else {
            Log.server.errorPublic("PlexManager: All connections failed for server '\(server.name)'")
            let triedList = triedConnections.joined(separator: "\n")
            connectionState = .error(lastError)
            throw PlexServerError.allConnectionsFailed(serverName: server.name, tried: triedList)
        }
        
        await MainActor.run {
            self.currentServer = server
            self.serverClient = client
        }
        
        // Fetch libraries
        Log.server.infoPublic("PlexManager: Fetching libraries...")
        try await refreshLibraries()
        
        connectionState = .connected
        Log.server.infoPublic("PlexManager: Connected to server '\(server.name)'")
    }
    
    // MARK: - Library Management
    
    /// Refresh available libraries on the current server
    func refreshLibraries() async throws {
        guard let client = serverClient else {
            throw PlexServerError.invalidURL
        }
        
        // Fetch all libraries (music, movies, shows)
        let allLibraries = try await client.fetchLibraries()
        Log.server.infoPublic("PlexManager: Found \(allLibraries.count) total libraries")
        for lib in allLibraries {
            Log.server.infoPublic("  Library: \(lib.title) (type: \(lib.type), id: \(lib.id))")
        }
        
        await MainActor.run {
            self.availableLibraries = allLibraries
            
            // Restore previous library selection, or default to first music library, or first library
            if let savedLibraryID = UserDefaults.standard.string(forKey: "PlexCurrentLibraryID"),
               let savedLibrary = allLibraries.first(where: { $0.id == savedLibraryID }) {
                // Restore saved library
                self.currentLibrary = savedLibrary
                Log.server.infoPublic("PlexManager: Restored saved library: \(savedLibrary.title)")
            } else if let firstMusicLibrary = allLibraries.first(where: { $0.isMusicLibrary }) {
                // Default to first music library
                self.currentLibrary = firstMusicLibrary
                Log.server.infoPublic("PlexManager: Defaulting to music library: \(firstMusicLibrary.title)")
            } else if let firstLibrary = allLibraries.first {
                // Fall back to first available library
                self.currentLibrary = firstLibrary
                Log.server.infoPublic("PlexManager: Defaulting to first library: \(firstLibrary.title)")
            }
            
            Log.server.infoPublic("PlexManager: Current library: \(self.currentLibrary?.title ?? "none")")
        }
    }
    
    /// Select a library (any type)
    func selectLibrary(_ library: PlexLibrary) {
        let libraryChanged = currentLibrary?.id != library.id
        currentLibrary = library
        
        // Preload content for the new library in the background
        if libraryChanged {
            Task {
                await preloadLibraryContent()
            }
        }
    }
    
    // MARK: - Content Fetching (Convenience)
    
    /// Fetch artists from the current library (returns empty if not a music library)
    func fetchArtists() async throws -> [PlexArtist] {
        guard let client = serverClient, let library = currentLibrary else {
            return []
        }
        guard library.isMusicLibrary else {
            return []  // Not a music library, return empty
        }
        return try await client.fetchAllArtists(libraryID: library.id)
    }
    
    /// Fetch albums from the current library (returns empty if not a music library)
    func fetchAlbums(offset: Int = 0, limit: Int = 100) async throws -> [PlexAlbum] {
        guard let client = serverClient, let library = currentLibrary else {
            return []
        }
        guard library.isMusicLibrary else {
            return []  // Not a music library, return empty
        }
        return try await client.fetchAlbums(libraryID: library.id, offset: offset, limit: limit)
    }
    
    /// Fetch tracks from the current library (returns empty if not a music library)
    func fetchTracks(offset: Int = 0, limit: Int = 100) async throws -> [PlexTrack] {
        guard let client = serverClient, let library = currentLibrary else {
            return []
        }
        guard library.isMusicLibrary else {
            return []  // Not a music library, return empty
        }
        return try await client.fetchTracks(libraryID: library.id, offset: offset, limit: limit)
    }
    
    /// Fetch albums for an artist (with fallback to library section filter)
    func fetchAlbums(forArtist artist: PlexArtist) async throws -> [PlexAlbum] {
        guard let client = serverClient else {
            return []
        }
        
        // Primary: fetch via /library/metadata/{id}/children
        let albums = try await client.fetchAlbums(forArtist: artist.id)
        if !albums.isEmpty {
            return albums
        }
        
        // Fallback: query library section with artist.id filter
        // This handles cases where the /children endpoint returns empty
        // (compilation artists, metadata agent quirks, etc.)
        guard let library = currentLibrary, library.isMusicLibrary else {
            return []
        }
        Log.server.infoPublic("PlexManager: fetchAlbums /children returned empty for '\(artist.title)' (id=\(artist.id)), trying library section filter fallback")
        return try await client.fetchAlbumsByArtistFilter(artistID: artist.id, libraryID: library.id)
    }
    
    /// Fetch tracks for an artist directly (bypasses album hierarchy)
    /// Used as a last-resort fallback when album fetch returns empty
    func fetchTracks(forArtist artist: PlexArtist) async throws -> [PlexTrack] {
        guard let client = serverClient, let library = currentLibrary, library.isMusicLibrary else {
            return []
        }
        return try await client.fetchTracksByArtistFilter(artistID: artist.id, libraryID: library.id)
    }
    
    /// Fetch tracks for an album
    func fetchTracks(forAlbum album: PlexAlbum) async throws -> [PlexTrack] {
        guard let client = serverClient else {
            return []
        }
        return try await client.fetchTracks(forAlbum: album.id)
    }
    
    /// Search the current library
    func search(query: String, type: SearchType = .all) async throws -> PlexSearchResults {
        guard let client = serverClient, let library = currentLibrary else {
            return PlexSearchResults()
        }
        return try await client.search(query: query, libraryID: library.id, type: type)
    }
    
    // MARK: - Video Content Fetching
    
    /// Fetch movies from the current library if it's a movie library, otherwise from the first available movie library
    func fetchMovies(offset: Int = 0, limit: Int = 100) async throws -> [PlexMovie] {
        guard let client = serverClient else { return [] }
        let library = currentLibrary?.isMovieLibrary == true ? currentLibrary! : availableLibraries.first(where: { $0.isMovieLibrary })
        guard let library else { return [] }
        return try await client.fetchMovies(libraryID: library.id, offset: offset, limit: limit)
    }
    
    /// Fetch TV shows from the current library if it's a show library, otherwise from the first available show library
    func fetchShows(offset: Int = 0, limit: Int = 100) async throws -> [PlexShow] {
        guard let client = serverClient else { return [] }
        let library = currentLibrary?.isShowLibrary == true ? currentLibrary! : availableLibraries.first(where: { $0.isShowLibrary })
        guard let library else { return [] }
        return try await client.fetchShows(libraryID: library.id, offset: offset, limit: limit)
    }
    
    /// Fetch seasons for a TV show
    func fetchSeasons(forShow show: PlexShow) async throws -> [PlexSeason] {
        guard let client = serverClient else {
            throw PlexServerError.invalidURL
        }
        return try await client.fetchSeasons(forShow: show.id)
    }
    
    /// Fetch episodes for a season
    func fetchEpisodes(forSeason season: PlexSeason) async throws -> [PlexEpisode] {
        guard let client = serverClient else {
            throw PlexServerError.invalidURL
        }
        return try await client.fetchEpisodes(forSeason: season.id)
    }
    
    // MARK: - Detailed Metadata (includes external IDs)
    
    /// Fetch detailed movie metadata including IMDB/TMDB IDs
    func fetchMovieDetails(movieID: String) async throws -> PlexMovie? {
        guard let client = serverClient else {
            return nil
        }
        return try await client.fetchMovieDetails(movieID: movieID)
    }
    
    /// Fetch detailed show metadata including IMDB/TMDB/TVDB IDs
    func fetchShowDetails(showID: String) async throws -> PlexShow? {
        guard let client = serverClient else {
            return nil
        }
        return try await client.fetchShowDetails(showID: showID)
    }
    
    /// Fetch detailed episode metadata including IMDB ID
    func fetchEpisodeDetails(episodeID: String) async throws -> PlexEpisode? {
        guard let client = serverClient else {
            return nil
        }
        return try await client.fetchEpisodeDetails(episodeID: episodeID)
    }
    
    // MARK: - Playlist Operations
    
    /// Fetch all playlists (not library-specific)
    func fetchPlaylists() async throws -> [PlexPlaylist] {
        guard let client = serverClient else {
            return []
        }
        let playlists = try await client.fetchPlaylists()
        cachedPlaylists = playlists
        return playlists
    }
    
    /// Fetch audio playlists only
    func fetchAudioPlaylists() async throws -> [PlexPlaylist] {
        guard let client = serverClient else {
            return []
        }
        return try await client.fetchAudioPlaylists()
    }
    
    /// Fetch tracks in a playlist
    /// For smart playlists, pass the content URI as fallback
    func fetchPlaylistTracks(playlistID: String, smartContent: String? = nil) async throws -> [PlexTrack] {
        guard let client = serverClient else {
            return []
        }
        return try await client.fetchPlaylistTracks(playlistID: playlistID, smartContent: smartContent)
    }
    
    // MARK: - URL Generation
    
    /// Get streaming URL for a track
    func streamURL(for track: PlexTrack) -> URL? {
        serverClient?.streamURL(for: track)
    }
    
    /// Get artwork URL
    func artworkURL(thumb: String?, size: Int = 300) -> URL? {
        serverClient?.artworkURL(thumb: thumb, width: size, height: size)
    }
    
    /// Get streaming URL for a movie
    func streamURL(for movie: PlexMovie) -> URL? {
        serverClient?.streamURL(for: movie)
    }
    
    /// Get streaming URL for an episode
    func streamURL(for episode: PlexEpisode) -> URL? {
        serverClient?.streamURL(for: episode)
    }
    
    /// Get headers required for streaming (needed for remote/relay connections)
    var streamingHeaders: [String: String]? {
        serverClient?.streamingHeaders
    }

    /// Fetch the audio sample rate for a track via its rating key.
    /// Returns nil if unavailable (network error, server not connected, etc.)
    func fetchSampleRate(for ratingKey: String) async -> Int? {
        guard let client = serverClient,
              let track = try? await client.fetchTrackDetails(trackID: ratingKey) else {
            return nil
        }
        return track.media.first?.audioSampleRate
    }
    
    // MARK: - Track Conversion
    
    /// Convert a Plex track to an AudioEngine-compatible Track
    func convertToTrack(_ plexTrack: PlexTrack) -> Track? {
        guard let streamURL = streamURL(for: plexTrack) else {
            Log.server.errorPublic("PlexManager: Cannot convert track '\(plexTrack.title)' - no stream URL (missing partKey)")
            return nil
        }
        
        // Extract audio info from media
        let media = plexTrack.media.first
        let bitrate = media?.bitrate
        let channels = media?.audioChannels
        let sampleRate = media?.audioSampleRate
        
        // Use grandparentTitle as artist, but avoid duplication if title already contains artist
        var artist = plexTrack.grandparentTitle
        let title = plexTrack.title
        
        // Check if title already starts with artist name (avoid "Artist - Artist - Song")
        if let artistName = artist, title.lowercased().hasPrefix(artistName.lowercased() + " - ") {
            artist = nil  // Don't set artist if title already includes it
        }
        
        return Track(
            url: streamURL,
            title: title,
            artist: artist,
            album: plexTrack.parentTitle,
            duration: plexTrack.durationInSeconds,
            bitrate: bitrate,
            sampleRate: sampleRate,
            channels: channels,
            plexRatingKey: plexTrack.id,  // Store rating key for play tracking
            plexServerId: currentServer?.id,
            artworkThumb: plexTrack.thumb,
            genre: plexTrack.genre
        )
    }

    /// Convert multiple Plex tracks to AudioEngine-compatible Tracks
    func convertToTracks(_ plexTracks: [PlexTrack]) -> [Track] {
        plexTracks.compactMap { convertToTrack($0) }
    }
    
    /// Convert a Plex movie to an AudioEngine-compatible Track (video type)
    func convertToTrack(_ movie: PlexMovie) -> Track? {
        guard let streamURL = streamURL(for: movie) else {
            Log.server.errorPublic("PlexManager: Cannot convert movie '\(movie.title)' - no stream URL")
            return nil
        }
        
        return Track(
            url: streamURL,
            title: movie.title,
            artist: movie.studio,  // Use studio as "artist" for movies
            album: nil,
            duration: movie.durationInSeconds,
            bitrate: movie.media.first?.bitrate,
            sampleRate: movie.media.first?.audioSampleRate,
            channels: movie.media.first?.audioChannels,
            plexRatingKey: movie.id,
            plexServerId: currentServer?.id,
            artworkThumb: movie.thumb,
            mediaType: .video,
            playHistoryContentTypeOverride: "movie"
        )
    }

    /// Convert a Plex episode to an AudioEngine-compatible Track (video type)
    func convertToTrack(_ episode: PlexEpisode) -> Track? {
        guard let streamURL = streamURL(for: episode) else {
            Log.server.errorPublic("PlexManager: Cannot convert episode '\(episode.title)' - no stream URL")
            return nil
        }
        
        // Build a descriptive title: "Show - S01E02 - Episode Title"
        let showTitle = episode.grandparentTitle ?? "Unknown Show"
        let episodeTitle = "\(showTitle) - \(episode.episodeIdentifier) - \(episode.title)"
        
        return Track(
            url: streamURL,
            title: episodeTitle,
            artist: showTitle,  // Use show name as "artist"
            album: episode.parentTitle,  // Use season name as "album"
            duration: episode.durationInSeconds,
            bitrate: episode.media.first?.bitrate,
            sampleRate: episode.media.first?.audioSampleRate,
            channels: episode.media.first?.audioChannels,
            plexRatingKey: episode.id,
            plexServerId: currentServer?.id,
            artworkThumb: episode.thumb,
            mediaType: .video,
            playHistoryContentTypeOverride: "tv"
        )
    }

    /// Convert multiple Plex movies to AudioEngine-compatible Tracks
    func convertToTracks(_ movies: [PlexMovie]) -> [Track] {
        movies.compactMap { convertToTrack($0) }
    }
    
    /// Convert multiple Plex episodes to AudioEngine-compatible Tracks
    func convertToTracks(_ episodes: [PlexEpisode]) -> [Track] {
        episodes.compactMap { convertToTrack($0) }
    }
    
    // MARK: - Radio/Mix Generation
    
    /// Create a track radio based on a seed track
    /// - Parameters:
    ///   - track: The seed track
    ///   - limit: Maximum number of tracks to include
    /// - Returns: Array of tracks for the radio playlist, or empty if unavailable
    func createTrackRadio(from track: PlexTrack, limit: Int = RadioConfig.defaultLimit) async -> [Track] {
        guard let (client, library) = radioLibraryContext(logPrefix: "create track radio") else {
            return []
        }
        
        do {
            let plexTracks = try await client.createTrackRadio(
                trackID: track.id,
                libraryID: library.id,
                limit: limit
            )
            
            let tracks = convertToTracks(plexTracks)
            Log.server.infoPublic("PlexManager: Track radio created with \(tracks.count) tracks")
            return PlexRadioHistory.shared.filterOutHistoryTracks(tracks)
        } catch {
            Log.server.errorPublic("PlexManager: Failed to create track radio: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Create an artist radio based on a seed artist
    /// - Parameters:
    ///   - artist: The seed artist
    ///   - limit: Maximum number of tracks to include
    /// - Returns: Array of tracks for the radio playlist, or empty if unavailable
    func createArtistRadio(from artist: PlexArtist, limit: Int = RadioConfig.defaultLimit) async -> [Track] {
        guard let (client, library) = radioLibraryContext(logPrefix: "create artist radio") else {
            return []
        }
        
        do {
            let plexTracks = try await client.createArtistRadio(
                artistID: artist.id,
                libraryID: library.id,
                limit: limit
            )
            
            let tracks = convertToTracks(plexTracks)
            Log.server.infoPublic("PlexManager: Artist radio created with \(tracks.count) tracks")
            return PlexRadioHistory.shared.filterOutHistoryTracks(tracks)
        } catch {
            Log.server.errorPublic("PlexManager: Failed to create artist radio: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Create an album radio based on a seed album
    /// - Parameters:
    ///   - album: The seed album
    ///   - limit: Maximum number of tracks to include
    /// - Returns: Array of tracks for the radio playlist, or empty if unavailable
    func createAlbumRadio(from album: PlexAlbum, limit: Int = RadioConfig.defaultLimit) async -> [Track] {
        guard let (client, library) = radioLibraryContext(logPrefix: "create album radio") else {
            return []
        }
        
        do {
            let plexTracks = try await client.createAlbumRadio(
                albumID: album.id,
                libraryID: library.id,
                limit: limit
            )
            
            let tracks = convertToTracks(plexTracks)
            Log.server.infoPublic("PlexManager: Album radio created with \(tracks.count) tracks")
            return PlexRadioHistory.shared.filterOutHistoryTracks(tracks)
        } catch {
            Log.server.errorPublic("PlexManager: Failed to create album radio: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Check if radio features are likely available (requires Plex Pass + sonic analysis)
    /// This is a best-effort check; actual availability depends on server configuration
    var isRadioLikelyAvailable: Bool {
        // Radio features require a connected music library
        guard serverClient != nil, currentLibrary?.isMusicLibrary == true else {
            return false
        }
        return true
    }
    
    // MARK: - Genre Fetching
    
    /// Cached genres for the current library
    private var cachedGenres: [String] = []
    
    /// Fetch available genres from the current library
    func fetchGenres() async -> [String] {
        guard let client = serverClient, let library = currentLibrary else {
            Log.server.errorPublic("PlexManager: Cannot fetch genres - no server or library connected")
            return RadioConfig.fallbackGenres
        }
        
        do {
            let genres = try await client.fetchGenres(libraryID: library.id)
            cachedGenres = genres
            return genres
        } catch {
            Log.server.errorPublic("PlexManager: Failed to fetch genres: \(error.localizedDescription), using fallback")
            return RadioConfig.fallbackGenres
        }
    }
    
    /// Get cached genres or fetch if empty
    func getGenres() async -> [String] {
        if !cachedGenres.isEmpty {
            return cachedGenres
        }
        return await fetchGenres()
    }

    private func radioLibraryContext(logPrefix: String) -> (PlexServerClient, PlexLibrary)? {
        guard let client = serverClient else {
            Log.server.errorPublic("PlexManager: Cannot \(logPrefix) - no server connected")
            return nil
        }
        if let library = currentLibrary, library.isMusicLibrary {
            return (client, library)
        }
        if let currentLibrary {
            Log.server.infoPublic("PlexManager: \(logPrefix) requested with non-music library '\(currentLibrary.title)' (type: \(currentLibrary.type))")
        }
        if let musicLibrary = availableLibraries.first(where: { $0.isMusicLibrary }) {
            Log.server.infoPublic("PlexManager: Falling back to music library '\(musicLibrary.title)' for \(logPrefix)")
            return (client, musicLibrary)
        }
        Log.server.errorPublic("PlexManager: Cannot \(logPrefix) - no music library available")
        return nil
    }
    
    // MARK: - Extended Radio Methods (Non-Sonic and Sonic Versions)
    
    /// Filter tracks to limit duplicates per artist for better radio variety
    /// - Parameters:
    ///   - tracks: The tracks to filter
    ///   - limit: The desired number of tracks
    ///   - maxPerArtist: Maximum tracks allowed per artist (default from RadioConfig)
    /// - Returns: Filtered tracks with artist variety
    private func filterForArtistVariety(_ tracks: [Track], limit: Int, maxPerArtist: Int = RadioConfig.maxTracksPerArtist) -> [Track] {
        if maxPerArtist <= RadioPlaybackOptions.unlimitedMaxTracksPerArtist {
            let unfiltered = Array(tracks.prefix(limit))
            NSLog("PlexManager: Artist variety filter disabled (unlimited) - input: %d, output: %d",
                  tracks.count, unfiltered.count)
            return unfiltered
        }
        var result: [Track] = []
        var artistCounts: [String: Int] = [:]
        
        for track in tracks {
            // Normalize artist name: trim whitespace and lowercase for comparison
            let artist = track.artist?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "unknown"
            let currentCount = artistCounts[artist, default: 0]
            
            if currentCount < maxPerArtist {
                result.append(track)
                artistCounts[artist] = currentCount + 1
                
                if result.count >= limit {
                    break
                }
            }
        }
        
        // Spread out tracks so same artist isn't back-to-back
        let spreadResult = spreadArtistTracks(result)
        
        NSLog("PlexManager: Artist variety filter - input: %d, output: %d, unique artists: %d", 
              tracks.count, spreadResult.count, artistCounts.count)
        return spreadResult
    }
    
    /// Reorder tracks to avoid same artist playing back-to-back
    private func spreadArtistTracks(_ tracks: [Track]) -> [Track] {
        guard tracks.count > 2 else { return tracks }
        
        var result: [Track] = []
        var remaining = tracks
        var lastArtist: String? = nil
        
        while !remaining.isEmpty {
            // Find a track that's not by the last artist
            let nextIndex = remaining.firstIndex { track in
                let artist = track.artist?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "unknown"
                return artist != lastArtist
            }
            
            if let index = nextIndex {
                let track = remaining.remove(at: index)
                lastArtist = track.artist?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "unknown"
                result.append(track)
            } else {
                // No choice but to add a back-to-back track (all remaining are same artist)
                let track = remaining.removeFirst()
                lastArtist = track.artist?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "unknown"
                result.append(track)
            }
        }
        
        return result
    }

    /// Apply history filtering + artist variety filtering to radio tracks
    private func applyRadioFilters(_ tracks: [Track], limit: Int, maxPerArtist: Int = RadioConfig.maxTracksPerArtist) -> [Track] {
        let historyFiltered = PlexRadioHistory.shared.filterOutHistoryTracks(tracks)
        return filterForArtistVariety(historyFiltered, limit: limit, maxPerArtist: maxPerArtist)
    }

    /// Get a seed track for sonic radio: currently playing Plex track, or random from library
    private func getSonicSeedTrackID() async -> String? {
        // Check if currently playing track is a Plex track
        if let currentTrack = WindowManager.shared.audioEngine.currentTrack,
           let ratingKey = currentTrack.plexRatingKey {
            Log.server.infoPublic("PlexManager: Using current playing track as sonic seed: \(ratingKey)")
            return ratingKey
        }
        
        // Otherwise, pick a truly random track from the library
        guard let (client, library) = radioLibraryContext(logPrefix: "resolve sonic seed") else {
            return nil
        }
        
        do {
            // Use random sort to get a different seed each time
            let queryItems = [
                URLQueryItem(name: "type", value: "10"),
                URLQueryItem(name: "sort", value: "random"),
                URLQueryItem(name: "limit", value: "1")
            ]
            
            guard let request = client.buildRequest(path: "/library/sections/\(library.id)/all", queryItems: queryItems) else {
                return nil
            }
            
            let response: PlexResponse<PlexMetadataResponse> = try await client.performRequest(request)
            if let randomTrack = response.mediaContainer.metadata?.first {
                Log.server.infoPublic("PlexManager: Using random track as sonic seed: \(randomTrack.ratingKey)")
                return randomTrack.ratingKey
            }
        } catch {
            Log.server.errorPublic("PlexManager: Failed to get random seed track: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    // MARK: Library Radio
    
    /// Library Radio - Non-Sonic (random tracks from library)
    func createLibraryRadio(limit: Int = RadioConfig.defaultLimit) async -> [Track] {
        guard let (client, library) = radioLibraryContext(logPrefix: "create library radio") else {
            return []
        }
        
        do {
            let fetchLimit = RadioPlaybackOptions.candidateFetchLimit(
                for: limit,
                maxPerArtist: RadioConfig.maxTracksPerArtist
            )
            var plexTracks = try await client.createLibraryRadio(libraryID: library.id, limit: fetchLimit)
            if plexTracks.isEmpty && fetchLimit > 0 {
                Log.server.infoPublic("PlexManager: Library radio random query returned 0 tracks, falling back to library track fetch")
                plexTracks = try await client.fetchTracks(libraryID: library.id, offset: 0, limit: fetchLimit).shuffled()
            }
            let allTracks = convertToTracks(plexTracks)
            let tracks = applyRadioFilters(allTracks, limit: limit)
            Log.server.infoPublic("PlexManager: Library radio created with \(tracks.count) tracks")
            return tracks
        } catch {
            Log.server.errorPublic("PlexManager: Failed to create library radio: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Library Radio - Sonic (sonically similar to seed track)
    func createLibraryRadioSonic(limit: Int = RadioConfig.defaultLimit) async -> [Track] {
        guard let (client, library) = radioLibraryContext(logPrefix: "create library radio (sonic)") else {
            return []
        }
        
        guard let seedTrackID = await getSonicSeedTrackID() else {
            Log.server.errorPublic("PlexManager: Cannot create library radio (sonic) - no seed track available")
            return []
        }
        
        do {
            let fetchLimit = limit * RadioConfig.overFetchMultiplier
            let plexTracks = try await client.createLibraryRadioSonic(trackID: seedTrackID, libraryID: library.id, limit: fetchLimit)
            let allTracks = convertToTracks(plexTracks)
            // Sonic: limit to 1 track per artist for maximum variety
            let tracks = applyRadioFilters(allTracks, limit: limit, maxPerArtist: 1)
            Log.server.infoPublic("PlexManager: Library radio (sonic) created with \(tracks.count) tracks")
            return tracks
        } catch {
            Log.server.errorPublic("PlexManager: Failed to create library radio (sonic): \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: Genre Radio
    
    /// Genre Radio - Non-Sonic
    func createGenreRadio(genre: String, limit: Int = RadioConfig.defaultLimit) async -> [Track] {
        guard let (client, library) = radioLibraryContext(logPrefix: "create genre radio") else {
            return []
        }
        
        do {
            let fetchLimit = RadioPlaybackOptions.candidateFetchLimit(
                for: limit,
                maxPerArtist: RadioConfig.maxTracksPerArtist
            )
            let plexTracks = try await client.createGenreRadio(genre: genre, libraryID: library.id, limit: fetchLimit)
            let allTracks = convertToTracks(plexTracks)
            let tracks = applyRadioFilters(allTracks, limit: limit)
            Log.server.infoPublic("PlexManager: Genre radio (\(genre)) created with \(tracks.count) tracks")
            return tracks
        } catch {
            Log.server.errorPublic("PlexManager: Failed to create genre radio: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Genre Radio - Sonic
    func createGenreRadioSonic(genre: String, limit: Int = RadioConfig.defaultLimit) async -> [Track] {
        guard let (client, library) = radioLibraryContext(logPrefix: "create genre radio (sonic)") else {
            return []
        }
        
        guard let seedTrackID = await getSonicSeedTrackID() else {
            Log.server.errorPublic("PlexManager: Cannot create genre radio (sonic) - no seed track available")
            return []
        }
        
        do {
            let fetchLimit = limit * RadioConfig.overFetchMultiplier
            let plexTracks = try await client.createGenreRadioSonic(genre: genre, trackID: seedTrackID, libraryID: library.id, limit: fetchLimit)
            let allTracks = convertToTracks(plexTracks)
            // Sonic: limit to 1 track per artist for maximum variety
            let tracks = applyRadioFilters(allTracks, limit: limit, maxPerArtist: 1)
            Log.server.infoPublic("PlexManager: Genre radio (sonic) (\(genre)) created with \(tracks.count) tracks")
            return tracks
        } catch {
            Log.server.errorPublic("PlexManager: Failed to create genre radio (sonic): \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: Decade Radio
    
    /// Decade Radio - Non-Sonic
    func createDecadeRadio(startYear: Int, endYear: Int, limit: Int = RadioConfig.defaultLimit) async -> [Track] {
        guard let (client, library) = radioLibraryContext(logPrefix: "create decade radio") else {
            return []
        }
        
        do {
            let fetchLimit = RadioPlaybackOptions.candidateFetchLimit(
                for: limit,
                maxPerArtist: RadioConfig.maxTracksPerArtist
            )
            let plexTracks = try await client.createDecadeRadio(startYear: startYear, endYear: endYear, libraryID: library.id, limit: fetchLimit)
            let allTracks = convertToTracks(plexTracks)
            let tracks = applyRadioFilters(allTracks, limit: limit)
            Log.server.infoPublic("PlexManager: Decade radio (\(startYear)-\(endYear)) created with \(tracks.count) tracks")
            return tracks
        } catch {
            Log.server.errorPublic("PlexManager: Failed to create decade radio: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Decade Radio - Sonic
    func createDecadeRadioSonic(startYear: Int, endYear: Int, limit: Int = RadioConfig.defaultLimit) async -> [Track] {
        guard let (client, library) = radioLibraryContext(logPrefix: "create decade radio (sonic)") else {
            return []
        }
        
        guard let seedTrackID = await getSonicSeedTrackID() else {
            Log.server.errorPublic("PlexManager: Cannot create decade radio (sonic) - no seed track available")
            return []
        }
        
        do {
            let fetchLimit = limit * RadioConfig.overFetchMultiplier
            let plexTracks = try await client.createDecadeRadioSonic(startYear: startYear, endYear: endYear, trackID: seedTrackID, libraryID: library.id, limit: fetchLimit)
            let allTracks = convertToTracks(plexTracks)
            // Sonic: limit to 1 track per artist for maximum variety
            let tracks = applyRadioFilters(allTracks, limit: limit, maxPerArtist: 1)
            Log.server.infoPublic("PlexManager: Decade radio (sonic) (\(startYear)-\(endYear)) created with \(tracks.count) tracks")
            return tracks
        } catch {
            Log.server.errorPublic("PlexManager: Failed to create decade radio (sonic): \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: Hits Radio
    
    /// Only the Hits Radio - Non-Sonic
    func createHitsRadio(limit: Int = RadioConfig.defaultLimit) async -> [Track] {
        guard let (client, library) = radioLibraryContext(logPrefix: "create hits radio") else {
            return []
        }
        
        do {
            let fetchLimit = RadioPlaybackOptions.candidateFetchLimit(
                for: limit,
                maxPerArtist: RadioConfig.maxTracksPerArtist
            )
            let plexTracks = try await client.createHitsRadio(libraryID: library.id, limit: fetchLimit)
            let allTracks = convertToTracks(plexTracks)
            let tracks = applyRadioFilters(allTracks, limit: limit)
            Log.server.infoPublic("PlexManager: Hits radio created with \(tracks.count) tracks")
            return tracks
        } catch {
            Log.server.errorPublic("PlexManager: Failed to create hits radio: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Only the Hits Radio - Sonic
    func createHitsRadioSonic(limit: Int = RadioConfig.defaultLimit) async -> [Track] {
        guard let (client, library) = radioLibraryContext(logPrefix: "create hits radio (sonic)") else {
            return []
        }
        
        guard let seedTrackID = await getSonicSeedTrackID() else {
            Log.server.errorPublic("PlexManager: Cannot create hits radio (sonic) - no seed track available")
            return []
        }
        
        do {
            let fetchLimit = limit * RadioConfig.overFetchMultiplier
            let plexTracks = try await client.createHitsRadioSonic(trackID: seedTrackID, libraryID: library.id, limit: fetchLimit)
            let allTracks = convertToTracks(plexTracks)
            // Sonic: limit to 1 track per artist for maximum variety
            let tracks = applyRadioFilters(allTracks, limit: limit, maxPerArtist: 1)
            Log.server.infoPublic("PlexManager: Hits radio (sonic) created with \(tracks.count) tracks")
            return tracks
        } catch {
            Log.server.errorPublic("PlexManager: Failed to create hits radio (sonic): \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: Deep Cuts Radio
    
    /// Deep Cuts Radio - Non-Sonic
    func createDeepCutsRadio(limit: Int = RadioConfig.defaultLimit) async -> [Track] {
        guard let (client, library) = radioLibraryContext(logPrefix: "create deep cuts radio") else {
            return []
        }
        
        do {
            let fetchLimit = RadioPlaybackOptions.candidateFetchLimit(
                for: limit,
                maxPerArtist: RadioConfig.maxTracksPerArtist
            )
            let plexTracks = try await client.createDeepCutsRadio(libraryID: library.id, limit: fetchLimit)
            let allTracks = convertToTracks(plexTracks)
            let tracks = applyRadioFilters(allTracks, limit: limit)
            Log.server.infoPublic("PlexManager: Deep cuts radio created with \(tracks.count) tracks")
            return tracks
        } catch {
            Log.server.errorPublic("PlexManager: Failed to create deep cuts radio: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Deep Cuts Radio - Sonic
    func createDeepCutsRadioSonic(limit: Int = RadioConfig.defaultLimit) async -> [Track] {
        guard let (client, library) = radioLibraryContext(logPrefix: "create deep cuts radio (sonic)") else {
            return []
        }
        
        guard let seedTrackID = await getSonicSeedTrackID() else {
            Log.server.errorPublic("PlexManager: Cannot create deep cuts radio (sonic) - no seed track available")
            return []
        }
        
        do {
            let fetchLimit = limit * RadioConfig.overFetchMultiplier
            let plexTracks = try await client.createDeepCutsRadioSonic(trackID: seedTrackID, libraryID: library.id, limit: fetchLimit)
            let allTracks = convertToTracks(plexTracks)
            // Sonic: limit to 1 track per artist for maximum variety
            let tracks = applyRadioFilters(allTracks, limit: limit, maxPerArtist: 1)
            Log.server.infoPublic("PlexManager: Deep cuts radio (sonic) created with \(tracks.count) tracks")
            return tracks
        } catch {
            Log.server.errorPublic("PlexManager: Failed to create deep cuts radio (sonic): \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Rating Radio
    
    /// Rating Radio - Non-Sonic
    /// Plays tracks the user has rated at or above the minimum rating threshold
    /// - Parameters:
    ///   - minRating: Minimum user rating (0-10 scale, where 10 = 5 stars)
    ///   - limit: Maximum number of tracks to return
    func createRatingRadio(minRating: Double, limit: Int = RadioConfig.defaultLimit) async -> [Track] {
        guard let (client, library) = radioLibraryContext(logPrefix: "create rating radio") else {
            return []
        }
        
        do {
            let fetchLimit = RadioPlaybackOptions.candidateFetchLimit(
                for: limit,
                maxPerArtist: RadioConfig.maxTracksPerArtist
            )
            let plexTracks = try await client.createRatingRadio(minRating: minRating, libraryID: library.id, limit: fetchLimit)
            let allTracks = convertToTracks(plexTracks)
            let tracks = applyRadioFilters(allTracks, limit: limit)
            Log.server.infoPublic("PlexManager: Rating radio (\(String(format: "%.1f", minRating / 2))+ stars) created with \(tracks.count) tracks")
            return tracks
        } catch {
            Log.server.errorPublic("PlexManager: Failed to create rating radio: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Rating Radio - Sonic
    /// Plays tracks sonically similar to the seed that are rated at or above the minimum rating
    /// - Parameters:
    ///   - minRating: Minimum user rating (0-10 scale, where 10 = 5 stars)
    ///   - limit: Maximum number of tracks to return
    func createRatingRadioSonic(minRating: Double, limit: Int = RadioConfig.defaultLimit) async -> [Track] {
        guard let (client, library) = radioLibraryContext(logPrefix: "create rating radio (sonic)") else {
            return []
        }
        
        guard let seedTrackID = await getSonicSeedTrackID() else {
            Log.server.errorPublic("PlexManager: Cannot create rating radio (sonic) - no seed track available")
            return []
        }
        
        do {
            let fetchLimit = limit * RadioConfig.overFetchMultiplier
            let plexTracks = try await client.createRatingRadioSonic(minRating: minRating, trackID: seedTrackID, libraryID: library.id, limit: fetchLimit)
            let allTracks = convertToTracks(plexTracks)
            // Sonic: limit to 1 track per artist for maximum variety
            let tracks = applyRadioFilters(allTracks, limit: limit, maxPerArtist: 1)
            Log.server.infoPublic("PlexManager: Rating radio (sonic, \(String(format: "%.1f", minRating / 2))+ stars) created with \(tracks.count) tracks")
            return tracks
        } catch {
            Log.server.errorPublic("PlexManager: Failed to create rating radio (sonic): \(error.localizedDescription)")
            return []
        }
    }
}
