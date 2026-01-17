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
        serverClient = nil
        availableLibraries = []
        connectionState = .disconnected
        
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
        
        connectionState = .connecting
        
        do {
            let fetchedServers = try await authClient.fetchResources(token: token)
            
            await MainActor.run {
                self.servers = fetchedServers
                
                // Restore previous selection or select first server
                if let savedServerID = UserDefaults.standard.string(forKey: "PlexCurrentServerID"),
                   let savedServer = fetchedServers.first(where: { $0.id == savedServerID }) {
                    self.currentServer = savedServer
                } else if let firstServer = fetchedServers.first {
                    self.currentServer = firstServer
                }
            }
            
            // If we have a server selected, fetch its libraries
            if currentServer != nil {
                try await refreshLibraries()
            }
            
            connectionState = .connected
        } catch {
            connectionState = .error(error)
            throw error
        }
    }
    
    /// Refresh servers without throwing (for background refresh)
    private func refreshServersInBackground() async {
        do {
            try await refreshServers()
        } catch {
            print("Failed to refresh Plex servers: \(error)")
        }
    }
    
    /// Connect to a specific server
    func connect(to server: PlexServer) async throws {
        guard let token = account?.authToken else {
            throw PlexAuthError.unauthorized
        }
        
        connectionState = .connecting
        
        // Create client for the server
        guard let client = PlexServerClient(server: server, authToken: token) else {
            connectionState = .error(PlexServerError.invalidURL)
            throw PlexServerError.invalidURL
        }
        
        // Check connection
        let isOnline = await client.checkConnection()
        guard isOnline else {
            connectionState = .error(PlexServerError.serverOffline)
            throw PlexServerError.serverOffline
        }
        
        await MainActor.run {
            self.currentServer = server
            self.serverClient = client
        }
        
        // Fetch libraries
        try await refreshLibraries()
        
        connectionState = .connected
    }
    
    // MARK: - Library Management
    
    /// Refresh available libraries on the current server
    func refreshLibraries() async throws {
        guard let client = serverClient else {
            throw PlexServerError.invalidURL
        }
        
        let libraries = try await client.fetchMusicLibraries()
        
        await MainActor.run {
            self.availableLibraries = libraries
            
            // Restore previous selection or select first library
            if let savedLibraryID = UserDefaults.standard.string(forKey: "PlexCurrentLibraryID"),
               let savedLibrary = libraries.first(where: { $0.id == savedLibraryID }) {
                self.currentLibrary = savedLibrary
            } else if let firstLibrary = libraries.first {
                self.currentLibrary = firstLibrary
            }
        }
    }
    
    /// Select a library
    func selectLibrary(_ library: PlexLibrary) {
        currentLibrary = library
    }
    
    // MARK: - Content Fetching (Convenience)
    
    /// Fetch artists from the current library
    func fetchArtists() async throws -> [PlexArtist] {
        guard let client = serverClient, let library = currentLibrary else {
            throw PlexServerError.invalidURL
        }
        return try await client.fetchAllArtists(libraryID: library.id)
    }
    
    /// Fetch albums from the current library
    func fetchAlbums(offset: Int = 0, limit: Int = 100) async throws -> [PlexAlbum] {
        guard let client = serverClient, let library = currentLibrary else {
            throw PlexServerError.invalidURL
        }
        return try await client.fetchAlbums(libraryID: library.id, offset: offset, limit: limit)
    }
    
    /// Fetch tracks from the current library
    func fetchTracks(offset: Int = 0, limit: Int = 100) async throws -> [PlexTrack] {
        guard let client = serverClient, let library = currentLibrary else {
            throw PlexServerError.invalidURL
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
    
    // MARK: - URL Generation
    
    /// Get streaming URL for a track
    func streamURL(for track: PlexTrack) -> URL? {
        serverClient?.streamURL(for: track)
    }
    
    /// Get artwork URL
    func artworkURL(thumb: String?, size: Int = 300) -> URL? {
        serverClient?.artworkURL(thumb: thumb, width: size, height: size)
    }
    
    // MARK: - Track Conversion
    
    /// Convert a Plex track to an AudioEngine-compatible Track
    func convertToTrack(_ plexTrack: PlexTrack) -> Track? {
        guard let streamURL = streamURL(for: plexTrack) else { return nil }
        
        return Track(
            url: streamURL,
            title: plexTrack.title,
            artist: plexTrack.grandparentTitle,
            album: plexTrack.parentTitle,
            duration: plexTrack.durationInSeconds
        )
    }
    
    /// Convert multiple Plex tracks to AudioEngine-compatible Tracks
    func convertToTracks(_ plexTracks: [PlexTrack]) -> [Track] {
        plexTracks.compactMap { convertToTrack($0) }
    }
}
