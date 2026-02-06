import Foundation
import AppKit

/// Singleton managing Subsonic/Navidrome server connections and state
class SubsonicManager {
    
    // MARK: - Singleton
    
    static let shared = SubsonicManager()
    
    // MARK: - Notifications
    
    static let serversDidChangeNotification = Notification.Name("SubsonicServersDidChange")
    static let connectionStateDidChangeNotification = Notification.Name("SubsonicConnectionStateDidChange")
    static let libraryContentDidPreloadNotification = Notification.Name("SubsonicLibraryContentDidPreload")
    
    // MARK: - Server State
    
    /// All configured servers
    private(set) var servers: [SubsonicServer] = [] {
        didSet {
            NotificationCenter.default.post(name: Self.serversDidChangeNotification, object: self)
        }
    }
    
    /// Currently selected server
    private(set) var currentServer: SubsonicServer? {
        didSet {
            if oldValue?.id != currentServer?.id {
                serverClient = nil
                clearCachedContent()
                
                if let server = currentServer,
                   let credentials = KeychainHelper.shared.getSubsonicServer(id: server.id) {
                    serverClient = SubsonicServerClient(credentials: credentials)
                }
            }
            UserDefaults.standard.set(currentServer?.id, forKey: "SubsonicCurrentServerID")
        }
    }
    
    /// Client for the current server
    private(set) var serverClient: SubsonicServerClient?
    
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
    
    // MARK: - Cached Library Content
    
    /// Cached artists
    private(set) var cachedArtists: [SubsonicArtist] = []
    
    /// Cached albums
    private(set) var cachedAlbums: [SubsonicAlbum] = []
    
    /// Cached playlists
    private(set) var cachedPlaylists: [SubsonicPlaylist] = []
    
    /// Whether library content has been preloaded
    private(set) var isContentPreloaded: Bool = false
    
    /// Loading state for preload
    private(set) var isPreloading: Bool = false
    
    // MARK: - Initialization
    
    private init() {
        loadSavedServers()
    }
    
    // MARK: - Server Persistence
    
    private func loadSavedServers() {
        let credentials = KeychainHelper.shared.getSubsonicServers()
        servers = credentials.map { cred in
            SubsonicServer(
                id: cred.id,
                name: cred.name,
                url: cred.url,
                username: cred.username
            )
        }
        
        NSLog("SubsonicManager: Loaded %d saved servers", servers.count)
        
        // Restore previous server selection
        if let savedServerID = UserDefaults.standard.string(forKey: "SubsonicCurrentServerID"),
           let savedServer = servers.first(where: { $0.id == savedServerID }) {
            Task {
                await connectInBackground(to: savedServer)
            }
        }
    }
    
    // MARK: - Server Management
    
    /// Add a new server
    @discardableResult
    func addServer(name: String, url: String, username: String, password: String) async throws -> SubsonicServer {
        // Clean up URL
        var cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanURL.hasSuffix("/") {
            cleanURL = String(cleanURL.dropLast())
        }
        
        // Generate a unique ID
        let id = UUID().uuidString
        
        // Create credentials
        let credentials = SubsonicServerCredentials(
            id: id,
            name: name,
            url: cleanURL,
            username: username,
            password: password
        )
        
        // Test connection before saving
        guard let client = SubsonicServerClient(credentials: credentials) else {
            throw SubsonicClientError.invalidURL
        }
        
        connectionState = .connecting
        
        do {
            _ = try await client.ping()
        } catch {
            connectionState = .error(error)
            throw error
        }
        
        // Save to keychain
        _ = KeychainHelper.shared.addSubsonicServer(credentials)
        
        // Create server object (without password)
        let server = SubsonicServer(
            id: id,
            name: name,
            url: cleanURL,
            username: username
        )
        
        await MainActor.run {
            self.servers.append(server)
        }
        
        // Connect to the new server
        try await connect(to: server)
        
        NSLog("SubsonicManager: Added server '%@' at %@", name, cleanURL)
        
        return server
    }
    
    /// Update an existing server
    func updateServer(id: String, name: String, url: String, username: String, password: String) async throws {
        var cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanURL.hasSuffix("/") {
            cleanURL = String(cleanURL.dropLast())
        }
        
        let credentials = SubsonicServerCredentials(
            id: id,
            name: name,
            url: cleanURL,
            username: username,
            password: password
        )
        
        // Test connection
        guard let client = SubsonicServerClient(credentials: credentials) else {
            throw SubsonicClientError.invalidURL
        }
        
        _ = try await client.ping()
        
        // Update in keychain
        _ = KeychainHelper.shared.updateSubsonicServer(credentials)
        
        // Update local server list
        let server = SubsonicServer(
            id: id,
            name: name,
            url: cleanURL,
            username: username
        )
        
        await MainActor.run {
            if let index = self.servers.firstIndex(where: { $0.id == id }) {
                self.servers[index] = server
            }
            
            // If this is the current server, reconnect
            if self.currentServer?.id == id {
                self.currentServer = server
                self.serverClient = client
            }
        }
        
        NSLog("SubsonicManager: Updated server '%@'", name)
    }
    
    /// Remove a server
    func removeServer(id: String) {
        _ = KeychainHelper.shared.removeSubsonicServer(id: id)
        
        servers.removeAll { $0.id == id }
        
        // If this was the current server, disconnect
        if currentServer?.id == id {
            currentServer = nil
            serverClient = nil
            connectionState = .disconnected
            clearCachedContent()
        }
        
        NSLog("SubsonicManager: Removed server with ID %@", id)
    }
    
    /// Connect to a specific server
    func connect(to server: SubsonicServer) async throws {
        guard let credentials = KeychainHelper.shared.getSubsonicServer(id: server.id) else {
            throw SubsonicClientError.unauthorized
        }
        
        guard let client = SubsonicServerClient(credentials: credentials) else {
            throw SubsonicClientError.invalidURL
        }
        
        NSLog("SubsonicManager: Connecting to server '%@'", server.name)
        
        await MainActor.run {
            self.connectionState = .connecting
        }
        
        do {
            _ = try await client.ping()
            
            await MainActor.run {
                self.currentServer = server
                self.serverClient = client
                self.connectionState = .connected
            }
            
            NSLog("SubsonicManager: Connected to '%@'", server.name)
            
            // Preload library content in background
            await preloadLibraryContent()
            
        } catch {
            await MainActor.run {
                self.connectionState = .error(error)
            }
            throw error
        }
    }
    
    /// Connect in background (for startup)
    private func connectInBackground(to server: SubsonicServer) async {
        do {
            try await connect(to: server)
        } catch {
            NSLog("SubsonicManager: Background connection failed: %@", error.localizedDescription)
        }
    }
    
    /// Disconnect from current server
    func disconnect() {
        currentServer = nil
        serverClient = nil
        connectionState = .disconnected
        clearCachedContent()
        UserDefaults.standard.removeObject(forKey: "SubsonicCurrentServerID")
    }
    
    // MARK: - Library Preloading
    
    /// Preload library content in the background
    func preloadLibraryContent() async {
        guard let client = serverClient else {
            NSLog("SubsonicManager: Cannot preload - no server connected")
            return
        }
        
        guard !isPreloading else {
            NSLog("SubsonicManager: Already preloading, skipping")
            return
        }
        
        await MainActor.run {
            isPreloading = true
        }
        
        NSLog("SubsonicManager: Starting library content preload")
        
        do {
            // Fetch artists and albums in parallel
            async let artistsTask = client.fetchAllArtists()
            async let albumsTask = client.fetchAllAlbums()
            async let playlistsTask = client.fetchPlaylists()
            
            let (artists, albums, playlists) = try await (artistsTask, albumsTask, playlistsTask)
            
            await MainActor.run {
                self.cachedArtists = artists
                self.cachedAlbums = albums
                self.cachedPlaylists = playlists
                self.isContentPreloaded = true
                self.isPreloading = false
                
                NSLog("SubsonicManager: Preloaded %d artists, %d albums, %d playlists",
                      artists.count, albums.count, playlists.count)
                
                NotificationCenter.default.post(name: Self.libraryContentDidPreloadNotification, object: self)
            }
            
        } catch {
            NSLog("SubsonicManager: Library preload failed: %@", error.localizedDescription)
            await MainActor.run {
                self.isPreloading = false
            }
        }
    }
    
    /// Clear cached library content
    private func clearCachedContent() {
        cachedArtists = []
        cachedAlbums = []
        cachedPlaylists = []
        isContentPreloaded = false
    }
    
    // MARK: - Content Fetching
    
    /// Fetch artists (uses cache if available)
    func fetchArtists() async throws -> [SubsonicArtist] {
        if isContentPreloaded && !cachedArtists.isEmpty {
            return cachedArtists
        }
        
        guard let client = serverClient else { return [] }
        return try await client.fetchAllArtists()
    }
    
    /// Fetch albums (uses cache if available)
    func fetchAlbums() async throws -> [SubsonicAlbum] {
        if isContentPreloaded && !cachedAlbums.isEmpty {
            return cachedAlbums
        }
        
        guard let client = serverClient else { return [] }
        return try await client.fetchAllAlbums()
    }
    
    /// Fetch playlists (uses cache if available)
    func fetchPlaylists() async throws -> [SubsonicPlaylist] {
        if isContentPreloaded && !cachedPlaylists.isEmpty {
            return cachedPlaylists
        }
        
        guard let client = serverClient else { return [] }
        return try await client.fetchPlaylists()
    }
    
    /// Fetch albums for an artist
    func fetchAlbums(forArtist artist: SubsonicArtist) async throws -> [SubsonicAlbum] {
        guard let client = serverClient else { return [] }
        let (_, albums) = try await client.fetchArtist(id: artist.id)
        return albums
    }
    
    /// Fetch songs for an album
    func fetchSongs(forAlbum album: SubsonicAlbum) async throws -> [SubsonicSong] {
        guard let client = serverClient else { return [] }
        let (_, songs) = try await client.fetchAlbum(id: album.id)
        return songs
    }
    
    /// Search the library
    func search(query: String) async throws -> SubsonicSearchResults {
        guard let client = serverClient else {
            return SubsonicSearchResults()
        }
        return try await client.search(query: query)
    }
    
    /// Fetch starred (favorite) items
    func fetchStarred() async throws -> SubsonicStarred {
        guard let client = serverClient else {
            return SubsonicStarred()
        }
        return try await client.fetchStarred()
    }
    
    // MARK: - Favorites
    
    /// Star a song
    func starSong(id: String) async throws {
        guard let client = serverClient else { return }
        try await client.star(id: id)
    }
    
    /// Unstar a song
    func unstarSong(id: String) async throws {
        guard let client = serverClient else { return }
        try await client.unstar(id: id)
    }
    
    /// Star an album
    func starAlbum(id: String) async throws {
        guard let client = serverClient else { return }
        try await client.star(albumId: id)
    }
    
    /// Unstar an album
    func unstarAlbum(id: String) async throws {
        guard let client = serverClient else { return }
        try await client.unstar(albumId: id)
    }
    
    /// Star an artist
    func starArtist(id: String) async throws {
        guard let client = serverClient else { return }
        try await client.star(artistId: id)
    }
    
    /// Unstar an artist
    func unstarArtist(id: String) async throws {
        guard let client = serverClient else { return }
        try await client.unstar(artistId: id)
    }
    
    // MARK: - Playlist Management
    
    /// Create a new playlist
    func createPlaylist(name: String, songIds: [String] = []) async throws {
        guard let client = serverClient else { return }
        _ = try await client.createPlaylist(name: name, songIds: songIds)
        
        // Refresh playlists cache
        cachedPlaylists = try await client.fetchPlaylists()
    }
    
    /// Delete a playlist
    func deletePlaylist(id: String) async throws {
        guard let client = serverClient else { return }
        try await client.deletePlaylist(id: id)
        
        // Update cache
        cachedPlaylists.removeAll { $0.id == id }
    }
    
    /// Add songs to a playlist
    func addSongsToPlaylist(playlistId: String, songIds: [String]) async throws {
        guard let client = serverClient else { return }
        try await client.updatePlaylist(id: playlistId, songIdsToAdd: songIds)
    }
    
    // MARK: - URL Generation
    
    /// Get streaming URL for a song
    func streamURL(for song: SubsonicSong) -> URL? {
        serverClient?.streamURL(for: song)
    }
    
    /// Get cover art URL
    func coverArtURL(coverArtId: String?, size: Int = 300) -> URL? {
        serverClient?.coverArtURL(coverArtId: coverArtId, size: size)
    }
    
    // MARK: - Track Conversion
    
    /// Convert a Subsonic song to an AudioEngine-compatible Track
    func convertToTrack(_ song: SubsonicSong) -> Track? {
        guard let streamURL = streamURL(for: song) else { return nil }
        
        return Track(
            url: streamURL,
            title: song.title,
            artist: song.artist,
            album: song.album,
            duration: song.durationInSeconds,
            bitrate: song.bitRate,
            sampleRate: nil,
            channels: nil,
            plexRatingKey: nil,
            subsonicId: song.id,
            subsonicServerId: currentServer?.id,
            artworkThumb: song.coverArt,
            genre: song.genre
        )
    }
    
    /// Convert multiple Subsonic songs to Tracks
    func convertToTracks(_ songs: [SubsonicSong]) -> [Track] {
        songs.compactMap { convertToTrack($0) }
    }
}
