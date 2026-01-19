import Foundation
import AppKit

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
            UserDefaults.standard.set(currentServer?.id, forKey: "PlexCurrentServerID")
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
            UserDefaults.standard.set(currentLibrary?.id, forKey: "PlexCurrentLibraryID")
        }
    }
    
    /// Client for the current server
    private(set) var serverClient: PlexServerClient?
    
    /// All available libraries on the current server (music, movies, shows)
    private(set) var availableLibraries: [PlexLibrary] = []
    
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
            NSLog("PlexManager: No saved account found in keychain")
            return
        }
        
        NSLog("PlexManager: Found saved account: %@", savedAccount.username)
        self.account = savedAccount
        
        // Restore servers and selection in background
        Task {
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
            NSLog("PlexManager: Already refreshing servers, skipping duplicate request")
            return
        }
        
        isRefreshing = true
        defer { isRefreshing = false }
        
        connectionState = .connecting
        
        do {
            let fetchedServers = try await authClient.fetchResources(token: token)
            NSLog("PlexManager: Fetched %d servers", fetchedServers.count)
            
            await MainActor.run {
                self.servers = fetchedServers
            }
            
            // Determine which server to connect to
            var serverToConnect: PlexServer? = nil
            
            if let savedServerID = UserDefaults.standard.string(forKey: "PlexCurrentServerID"),
               let savedServer = fetchedServers.first(where: { $0.id == savedServerID }) {
                serverToConnect = savedServer
                NSLog("PlexManager: Will connect to saved server: %@", savedServer.name)
            } else if let firstServer = fetchedServers.first {
                serverToConnect = firstServer
                NSLog("PlexManager: Will connect to first server: %@", firstServer.name)
            }
            
            // Connect to the server using the full connection logic (tries all connections)
            if let server = serverToConnect {
                do {
                    try await connect(to: server)
                } catch {
                    NSLog("PlexManager: Failed to connect to server %@: %@", server.name, error.localizedDescription)
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
            NSLog("PlexManager: Background refresh of servers starting...")
            try await refreshServers()
            NSLog("PlexManager: Background refresh completed, found %d servers", servers.count)
            
            // Preload library content after successful server connection
            await preloadLibraryContent()
        } catch {
            NSLog("PlexManager: Background refresh failed: %@", error.localizedDescription)
        }
    }
    
    /// Preload library content in the background for faster Plex browser opening
    func preloadLibraryContent() async {
        // Capture the current state at the start to avoid race conditions
        guard let client = serverClient, let library = currentLibrary else {
            NSLog("PlexManager: Cannot preload - no server or library connected")
            return
        }
        
        guard !isPreloading else {
            NSLog("PlexManager: Already preloading, skipping")
            return
        }
        
        await MainActor.run {
            isPreloading = true
        }
        
        NSLog("PlexManager: Starting library content preload for library: %@", library.title)
        
        do {
            // Preload content based on the library type
            // Use the captured client and library to avoid race conditions
            if library.isMusicLibrary {
                // Preload artists and albums for music library
                NSLog("PlexManager: Fetching artists...")
                let artists = try await client.fetchAllArtists(libraryID: library.id)
                NSLog("PlexManager: Fetched %d artists, now fetching albums...", artists.count)
                let albums = try await client.fetchAlbums(libraryID: library.id, offset: 0, limit: 10000)
                NSLog("PlexManager: Fetched %d albums", albums.count)
                
                await MainActor.run {
                    // Only store if the library hasn't changed
                    if self.currentLibrary?.id == library.id {
                        self.cachedArtists = artists
                        self.cachedAlbums = albums
                        self.isContentPreloaded = true
                        NSLog("PlexManager: Stored preloaded data - %d artists, %d albums", artists.count, albums.count)
                    } else {
                        NSLog("PlexManager: Library changed during preload, discarding results")
                    }
                    self.isPreloading = false
                    NotificationCenter.default.post(name: Self.libraryContentDidPreloadNotification, object: self)
                }
                
            } else if library.isMovieLibrary {
                // Preload movies for movie library
                NSLog("PlexManager: Fetching movies...")
                let movies = try await client.fetchMovies(libraryID: library.id, offset: 0, limit: 500)
                
                await MainActor.run {
                    if self.currentLibrary?.id == library.id {
                        self.cachedMovies = movies
                        self.isContentPreloaded = true
                        NSLog("PlexManager: Stored preloaded data - %d movies", movies.count)
                    } else {
                        NSLog("PlexManager: Library changed during preload, discarding results")
                    }
                    self.isPreloading = false
                    NotificationCenter.default.post(name: Self.libraryContentDidPreloadNotification, object: self)
                }
                
            } else if library.isShowLibrary {
                // Preload shows for show library
                NSLog("PlexManager: Fetching shows...")
                let shows = try await client.fetchShows(libraryID: library.id, offset: 0, limit: 500)
                
                await MainActor.run {
                    if self.currentLibrary?.id == library.id {
                        self.cachedShows = shows
                        self.isContentPreloaded = true
                        NSLog("PlexManager: Stored preloaded data - %d shows", shows.count)
                    } else {
                        NSLog("PlexManager: Library changed during preload, discarding results")
                    }
                    self.isPreloading = false
                    NotificationCenter.default.post(name: Self.libraryContentDidPreloadNotification, object: self)
                }
            } else {
                NSLog("PlexManager: Library type not supported for preload: %@", library.type)
                await MainActor.run {
                    self.isPreloading = false
                }
            }
            
            NSLog("PlexManager: Library content preload complete")
            
        } catch {
            NSLog("PlexManager: Library content preload failed: %@", error.localizedDescription)
            await MainActor.run {
                self.isPreloading = false
            }
        }
    }
    
    /// Clear cached library content (called when library or server changes)
    private func clearCachedContent() {
        cachedArtists = []
        cachedAlbums = []
        cachedMovies = []
        cachedShows = []
        isContentPreloaded = false
    }
    
    /// Connect to a specific server
    func connect(to server: PlexServer) async throws {
        guard let token = account?.authToken else {
            throw PlexAuthError.unauthorized
        }
        
        NSLog("PlexManager: Connecting to server '%@' (id: %@)", server.name, server.id)
        NSLog("PlexManager: Server has %d connections", server.connections.count)
        for (index, conn) in server.connections.enumerated() {
            NSLog("  Connection %d: %@ (local: %d, relay: %d)", index, conn.uri, conn.local ? 1 : 0, conn.relay ? 1 : 0)
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
                NSLog("PlexManager: Skipping connection with invalid URL: %@", connection.uri)
                continue
            }
            
            let connType = connection.local ? "local" : (connection.relay ? "relay" : "remote")
            NSLog("PlexManager: Trying connection: %@ (%@)", connection.uri, connType)
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
                NSLog("PlexManager: Failed to create client for connection: %@", connection.uri)
                continue
            }
            
            // Check connection with short timeout
            let isOnline = await client.checkConnection()
            if isOnline {
                NSLog("PlexManager: Connection successful: %@", connection.uri)
                workingClient = client
                break
            } else {
                NSLog("PlexManager: Connection failed: %@", connection.uri)
                lastError = PlexServerError.serverOffline
            }
        }
        
        guard let client = workingClient else {
            NSLog("PlexManager: All connections failed for server '%@'", server.name)
            let triedList = triedConnections.joined(separator: "\n")
            connectionState = .error(lastError)
            throw PlexServerError.allConnectionsFailed(serverName: server.name, tried: triedList)
        }
        
        await MainActor.run {
            self.currentServer = server
            self.serverClient = client
        }
        
        // Fetch libraries
        NSLog("PlexManager: Fetching libraries...")
        try await refreshLibraries()
        
        connectionState = .connected
        NSLog("PlexManager: Connected to server '%@'", server.name)
    }
    
    // MARK: - Library Management
    
    /// Refresh available libraries on the current server
    func refreshLibraries() async throws {
        guard let client = serverClient else {
            throw PlexServerError.invalidURL
        }
        
        // Fetch all libraries (music, movies, shows)
        let allLibraries = try await client.fetchLibraries()
        NSLog("PlexManager: Found %d total libraries", allLibraries.count)
        for lib in allLibraries {
            NSLog("  Library: %@ (type: %@, id: %@)", lib.title, lib.type, lib.id)
        }
        
        await MainActor.run {
            self.availableLibraries = allLibraries
            
            // Restore previous library selection, or default to first music library, or first library
            if let savedLibraryID = UserDefaults.standard.string(forKey: "PlexCurrentLibraryID"),
               let savedLibrary = allLibraries.first(where: { $0.id == savedLibraryID }) {
                // Restore saved library
                self.currentLibrary = savedLibrary
                NSLog("PlexManager: Restored saved library: %@", savedLibrary.title)
            } else if let firstMusicLibrary = allLibraries.first(where: { $0.isMusicLibrary }) {
                // Default to first music library
                self.currentLibrary = firstMusicLibrary
                NSLog("PlexManager: Defaulting to music library: %@", firstMusicLibrary.title)
            } else if let firstLibrary = allLibraries.first {
                // Fall back to first available library
                self.currentLibrary = firstLibrary
                NSLog("PlexManager: Defaulting to first library: %@", firstLibrary.title)
            }
            
            NSLog("PlexManager: Current library: %@", self.currentLibrary?.title ?? "none")
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
    
    /// Fetch albums for an artist
    func fetchAlbums(forArtist artist: PlexArtist) async throws -> [PlexAlbum] {
        guard let client = serverClient else {
            return []
        }
        return try await client.fetchAlbums(forArtist: artist.id)
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
    
    /// Fetch movies from the current library (returns empty if not a movie library)
    func fetchMovies(offset: Int = 0, limit: Int = 100) async throws -> [PlexMovie] {
        guard let client = serverClient, let library = currentLibrary else {
            return []
        }
        guard library.isMovieLibrary else {
            return []  // Not a movie library, return empty
        }
        return try await client.fetchMovies(libraryID: library.id, offset: offset, limit: limit)
    }
    
    /// Fetch TV shows from the current library (returns empty if not a show library)
    func fetchShows(offset: Int = 0, limit: Int = 100) async throws -> [PlexShow] {
        guard let client = serverClient, let library = currentLibrary else {
            return []
        }
        guard library.isShowLibrary else {
            return []  // Not a show library, return empty
        }
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
    
    // MARK: - Track Conversion
    
    /// Convert a Plex track to an AudioEngine-compatible Track
    func convertToTrack(_ plexTrack: PlexTrack) -> Track? {
        guard let streamURL = streamURL(for: plexTrack) else { return nil }
        
        // Extract audio info from media
        let media = plexTrack.media.first
        let bitrate = media?.bitrate
        let channels = media?.audioChannels
        
        return Track(
            url: streamURL,
            title: plexTrack.title,
            artist: plexTrack.grandparentTitle,
            album: plexTrack.parentTitle,
            duration: plexTrack.durationInSeconds,
            bitrate: bitrate,
            sampleRate: nil,  // Plex doesn't provide sample rate in API
            channels: channels,
            plexRatingKey: plexTrack.id  // Store rating key for play tracking
        )
    }
    
    /// Convert multiple Plex tracks to AudioEngine-compatible Tracks
    func convertToTracks(_ plexTracks: [PlexTrack]) -> [Track] {
        plexTracks.compactMap { convertToTrack($0) }
    }
}
