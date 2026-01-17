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
    
    /// Currently selected music library
    private(set) var currentLibrary: PlexLibrary? {
        didSet {
            NotificationCenter.default.post(name: Self.libraryDidChangeNotification, object: self)
            UserDefaults.standard.set(currentLibrary?.id, forKey: "PlexCurrentLibraryID")
        }
    }
    
    /// Client for the current server
    private(set) var serverClient: PlexServerClient?
    
    /// Available music libraries on the current server
    private(set) var availableLibraries: [PlexLibrary] = []
    
    /// Available video libraries (movies + shows) on the current server
    private(set) var availableVideoLibraries: [PlexLibrary] = []
    
    /// Currently selected video library (for movies/shows browsing)
    private(set) var currentVideoLibrary: PlexLibrary? {
        didSet {
            NotificationCenter.default.post(name: Self.libraryDidChangeNotification, object: self)
            UserDefaults.standard.set(currentVideoLibrary?.id, forKey: "PlexCurrentVideoLibraryID")
        }
    }
    
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
    
    // MARK: - Initialization
    
    private init() {
        authClient = PlexAuthClient()
        loadSavedAccount()
    }
    
    // MARK: - Account Persistence
    
    private func loadSavedAccount() {
        guard let savedAccount = KeychainHelper.shared.getPlexAccount() else {
            return
        }
        
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
        currentVideoLibrary = nil
        serverClient = nil
        availableLibraries = []
        availableVideoLibraries = []
        connectionState = .disconnected
        
        // Clear saved data
        KeychainHelper.shared.clearPlexCredentials()
        UserDefaults.standard.removeObject(forKey: "PlexCurrentServerID")
        UserDefaults.standard.removeObject(forKey: "PlexCurrentLibraryID")
        UserDefaults.standard.removeObject(forKey: "PlexCurrentVideoLibraryID")
    }
    
    // MARK: - Server Management
    
    /// Refresh the list of available servers
    func refreshServers() async throws {
        guard let token = account?.authToken else {
            throw PlexAuthError.unauthorized
        }
        
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
        } catch {
            NSLog("PlexManager: Background refresh failed: %@", error.localizedDescription)
        }
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
        
        // Fetch all libraries at once
        let allLibraries = try await client.fetchLibraries()
        NSLog("PlexManager: Found %d total libraries", allLibraries.count)
        for lib in allLibraries {
            NSLog("  Library: %@ (type: %@, id: %@)", lib.title, lib.type, lib.id)
        }
        
        let musicLibraries = allLibraries.filter { $0.isMusicLibrary }
        let videoLibraries = allLibraries.filter { $0.isVideoLibrary }
        
        NSLog("PlexManager: %d music libraries, %d video libraries", musicLibraries.count, videoLibraries.count)
        
        await MainActor.run {
            self.availableLibraries = musicLibraries
            self.availableVideoLibraries = videoLibraries
            
            // Restore previous music library selection or select first library
            if let savedLibraryID = UserDefaults.standard.string(forKey: "PlexCurrentLibraryID"),
               let savedLibrary = musicLibraries.first(where: { $0.id == savedLibraryID }) {
                self.currentLibrary = savedLibrary
            } else if let firstLibrary = musicLibraries.first {
                self.currentLibrary = firstLibrary
            }
            
            // Restore previous video library selection or select first video library
            if let savedVideoLibraryID = UserDefaults.standard.string(forKey: "PlexCurrentVideoLibraryID"),
               let savedVideoLibrary = videoLibraries.first(where: { $0.id == savedVideoLibraryID }) {
                self.currentVideoLibrary = savedVideoLibrary
            } else if let firstVideoLibrary = videoLibraries.first {
                self.currentVideoLibrary = firstVideoLibrary
            }
            
            NSLog("PlexManager: Current music library: %@", self.currentLibrary?.title ?? "none")
            NSLog("PlexManager: Current video library: %@", self.currentVideoLibrary?.title ?? "none")
        }
    }
    
    /// Select a music library
    func selectLibrary(_ library: PlexLibrary) {
        currentLibrary = library
    }
    
    /// Select a video library
    func selectVideoLibrary(_ library: PlexLibrary) {
        currentVideoLibrary = library
    }
    
    // MARK: - Content Fetching (Convenience)
    
    /// Fetch artists from the current library
    func fetchArtists() async throws -> [PlexArtist] {
        guard let client = serverClient else {
            throw PlexServerError.invalidURL
        }
        guard let library = currentLibrary else {
            throw PlexServerError.noMusicLibrary
        }
        return try await client.fetchAllArtists(libraryID: library.id)
    }
    
    /// Fetch albums from the current library
    func fetchAlbums(offset: Int = 0, limit: Int = 100) async throws -> [PlexAlbum] {
        guard let client = serverClient else {
            throw PlexServerError.invalidURL
        }
        guard let library = currentLibrary else {
            throw PlexServerError.noMusicLibrary
        }
        return try await client.fetchAlbums(libraryID: library.id, offset: offset, limit: limit)
    }
    
    /// Fetch tracks from the current library
    func fetchTracks(offset: Int = 0, limit: Int = 100) async throws -> [PlexTrack] {
        guard let client = serverClient else {
            throw PlexServerError.invalidURL
        }
        guard let library = currentLibrary else {
            throw PlexServerError.noMusicLibrary
        }
        return try await client.fetchTracks(libraryID: library.id, offset: offset, limit: limit)
    }
    
    /// Fetch albums for an artist
    func fetchAlbums(forArtist artist: PlexArtist) async throws -> [PlexAlbum] {
        guard let client = serverClient else {
            throw PlexServerError.invalidURL
        }
        return try await client.fetchAlbums(forArtist: artist.id)
    }
    
    /// Fetch tracks for an album
    func fetchTracks(forAlbum album: PlexAlbum) async throws -> [PlexTrack] {
        guard let client = serverClient else {
            throw PlexServerError.invalidURL
        }
        return try await client.fetchTracks(forAlbum: album.id)
    }
    
    /// Search the current library
    func search(query: String, type: SearchType = .all) async throws -> PlexSearchResults {
        guard let client = serverClient, let library = currentLibrary else {
            throw PlexServerError.invalidURL
        }
        return try await client.search(query: query, libraryID: library.id, type: type)
    }
    
    // MARK: - Video Content Fetching
    
    /// Fetch movies from the current video library
    func fetchMovies(offset: Int = 0, limit: Int = 100) async throws -> [PlexMovie] {
        guard let client = serverClient else {
            NSLog("PlexManager.fetchMovies: No server client")
            throw PlexServerError.invalidURL
        }
        
        // Use current video library if it's a movie library, otherwise find first movie library
        let movieLibrary = currentVideoLibrary?.isMovieLibrary == true 
            ? currentVideoLibrary 
            : availableVideoLibraries.first(where: { $0.isMovieLibrary })
        guard let library = movieLibrary else {
            NSLog("PlexManager.fetchMovies: No movie library found")
            throw PlexServerError.noMovieLibrary
        }
        NSLog("PlexManager.fetchMovies: Using library %@ (id: %@)", library.title, library.id)
        return try await client.fetchMovies(libraryID: library.id, offset: offset, limit: limit)
    }
    
    /// Fetch TV shows from the current video library
    func fetchShows(offset: Int = 0, limit: Int = 100) async throws -> [PlexShow] {
        guard let client = serverClient else {
            NSLog("PlexManager.fetchShows: No server client")
            throw PlexServerError.invalidURL
        }
        
        // Use current video library if it's a show library, otherwise find first show library
        let showLibrary = currentVideoLibrary?.isShowLibrary == true 
            ? currentVideoLibrary 
            : availableVideoLibraries.first(where: { $0.isShowLibrary })
        guard let library = showLibrary else {
            NSLog("PlexManager.fetchShows: No show library found")
            throw PlexServerError.noShowLibrary
        }
        NSLog("PlexManager.fetchShows: Using library %@ (id: %@)", library.title, library.id)
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
            channels: channels
        )
    }
    
    /// Convert multiple Plex tracks to AudioEngine-compatible Tracks
    func convertToTracks(_ plexTracks: [PlexTrack]) -> [Track] {
        plexTracks.compactMap { convertToTrack($0) }
    }
}
