import Foundation
import AppKit

/// Singleton managing Jellyfin server connections and state
class JellyfinManager {
    
    // MARK: - Singleton
    
    static let shared = JellyfinManager()
    
    // MARK: - Notifications
    
    static let serversDidChangeNotification = Notification.Name("JellyfinServersDidChange")
    static let connectionStateDidChangeNotification = Notification.Name("JellyfinConnectionStateDidChange")
    static let libraryContentDidPreloadNotification = Notification.Name("JellyfinLibraryContentDidPreload")
    static let musicLibraryDidChangeNotification = Notification.Name("JellyfinMusicLibraryDidChange")
    static let videoLibraryDidChangeNotification = Notification.Name("JellyfinVideoLibraryDidChange")
    
    // MARK: - Server State
    
    /// All configured servers
    private(set) var servers: [JellyfinServer] = [] {
        didSet {
            NotificationCenter.default.post(name: Self.serversDidChangeNotification, object: self)
        }
    }
    
    /// Currently selected server
    private(set) var currentServer: JellyfinServer? {
        didSet {
            if oldValue?.id != currentServer?.id {
                serverClient = nil
                clearCachedContent()
                
                if let server = currentServer,
                   let credentials = KeychainHelper.shared.getJellyfinServer(id: server.id) {
                    serverClient = JellyfinServerClient(credentials: credentials)
                }
            }
            UserDefaults.standard.set(currentServer?.id, forKey: "JellyfinCurrentServerID")
        }
    }
    
    /// Client for the current server
    private(set) var serverClient: JellyfinServerClient?
    
    // MARK: - Music Libraries
    
    /// Available music libraries on the current server
    private(set) var musicLibraries: [JellyfinMusicLibrary] = []
    
    /// Currently selected music library
    private(set) var currentMusicLibrary: JellyfinMusicLibrary? {
        didSet {
            UserDefaults.standard.set(currentMusicLibrary?.id, forKey: "JellyfinCurrentMusicLibraryID")
            NotificationCenter.default.post(name: Self.musicLibraryDidChangeNotification, object: self)
        }
    }
    
    // MARK: - Video Libraries
    
    /// All video libraries (movies + tvshows) on the current server
    private(set) var videoLibraries: [JellyfinMusicLibrary] = []
    
    /// Currently selected movie library
    private(set) var currentMovieLibrary: JellyfinMusicLibrary? {
        didSet {
            UserDefaults.standard.set(currentMovieLibrary?.id, forKey: "JellyfinCurrentMovieLibraryID")
            NotificationCenter.default.post(name: Self.videoLibraryDidChangeNotification, object: self)
        }
    }
    
    /// Currently selected TV show library
    private(set) var currentShowLibrary: JellyfinMusicLibrary? {
        didSet {
            UserDefaults.standard.set(currentShowLibrary?.id, forKey: "JellyfinCurrentShowLibraryID")
            NotificationCenter.default.post(name: Self.videoLibraryDidChangeNotification, object: self)
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

    /// Task for the initial background server connect — awaitable by CLI mode
    private(set) var serverConnectTask: Task<Void, Never>?

    // MARK: - Cached Library Content
    
    /// Cached artists
    private(set) var cachedArtists: [JellyfinArtist] = []
    
    /// Cached albums
    private(set) var cachedAlbums: [JellyfinAlbum] = []
    
    /// Cached playlists
    private(set) var cachedPlaylists: [JellyfinPlaylist] = []
    
    /// Cached movies
    private(set) var cachedMovies: [JellyfinMovie] = []
    
    /// Cached TV shows
    private(set) var cachedShows: [JellyfinShow] = []
    
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
        let credentials = KeychainHelper.shared.getJellyfinServers()
        servers = credentials.map { cred in
            JellyfinServer(
                id: cred.id,
                name: cred.name,
                url: cred.url,
                username: cred.username,
                userId: cred.userId
            )
        }
        
        NSLog("JellyfinManager: Loaded %d saved servers", servers.count)
        
        // Restore previous server selection
        if let savedServerID = UserDefaults.standard.string(forKey: "JellyfinCurrentServerID"),
           let savedServer = servers.first(where: { $0.id == savedServerID }) {
            serverConnectTask = Task {
                await connectInBackground(to: savedServer)
            }
        }
    }
    
    // MARK: - Server Management
    
    /// Add a new server
    @discardableResult
    func addServer(name: String, url: String, username: String, password: String) async throws -> JellyfinServer {
        // Clean up URL
        var cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanURL.hasSuffix("/") {
            cleanURL = String(cleanURL.dropLast())
        }
        
        // Generate a unique ID
        let id = UUID().uuidString
        let deviceId = KeychainHelper.shared.getOrCreateClientIdentifier()
        
        // Authenticate with the server first
        let authResponse: JellyfinAuthResponse
        do {
            authResponse = try await JellyfinServerClient.authenticate(
                url: cleanURL,
                username: username,
                password: password,
                deviceId: deviceId
            )
        } catch {
            throw error
        }
        
        // Create credentials with auth token
        let credentials = JellyfinServerCredentials(
            id: id,
            name: name,
            url: cleanURL,
            username: username,
            password: password,
            accessToken: authResponse.AccessToken,
            userId: authResponse.User.Id
        )
        
        // Save to keychain
        _ = KeychainHelper.shared.addJellyfinServer(credentials)
        
        // Create server object
        let server = JellyfinServer(
            id: id,
            name: name,
            url: cleanURL,
            username: username,
            userId: authResponse.User.Id
        )
        
        await MainActor.run {
            self.servers.append(server)
        }
        
        // Connect to the new server
        try await connect(to: server)
        
        NSLog("JellyfinManager: Added server '%@' at %@", name, cleanURL)
        
        return server
    }
    
    /// Update an existing server
    func updateServer(id: String, name: String, url: String, username: String, password: String) async throws {
        var cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanURL.hasSuffix("/") {
            cleanURL = String(cleanURL.dropLast())
        }
        
        let deviceId = KeychainHelper.shared.getOrCreateClientIdentifier()
        
        // Re-authenticate to get fresh token
        let authResponse = try await JellyfinServerClient.authenticate(
            url: cleanURL,
            username: username,
            password: password,
            deviceId: deviceId
        )
        
        let credentials = JellyfinServerCredentials(
            id: id,
            name: name,
            url: cleanURL,
            username: username,
            password: password,
            accessToken: authResponse.AccessToken,
            userId: authResponse.User.Id
        )
        
        // Update in keychain
        _ = KeychainHelper.shared.updateJellyfinServer(credentials)
        
        // Update local server list
        let server = JellyfinServer(
            id: id,
            name: name,
            url: cleanURL,
            username: username,
            userId: authResponse.User.Id
        )
        
        await MainActor.run {
            if let index = self.servers.firstIndex(where: { $0.id == id }) {
                self.servers[index] = server
            }
            
            // If this is the current server, reconnect
            if self.currentServer?.id == id {
                self.currentServer = server
                self.serverClient = JellyfinServerClient(credentials: credentials)
            }
        }
        
        NSLog("JellyfinManager: Updated server '%@'", name)
    }
    
    /// Remove a server
    func removeServer(id: String) {
        _ = KeychainHelper.shared.removeJellyfinServer(id: id)
        
        servers.removeAll { $0.id == id }
        
        // If this was the current server, disconnect
        if currentServer?.id == id {
            currentServer = nil
            serverClient = nil
            connectionState = .disconnected
            clearCachedContent()
        }
        
        NSLog("JellyfinManager: Removed server with ID %@", id)
    }
    
    /// Connect to a specific server
    func connect(to server: JellyfinServer) async throws {
        guard let credentials = KeychainHelper.shared.getJellyfinServer(id: server.id) else {
            throw JellyfinClientError.unauthorized
        }
        
        guard let client = JellyfinServerClient(credentials: credentials) else {
            throw JellyfinClientError.invalidURL
        }
        
        NSLog("JellyfinManager: Connecting to server '%@'", server.name)
        
        await MainActor.run {
            self.connectionState = .connecting
        }
        
        do {
            _ = try await client.ping()
            
            // Fetch music and video libraries in parallel
            async let musicLibTask = client.fetchMusicLibraries()
            async let videoLibTask = client.fetchVideoLibraries()
            
            let (libraries, vidLibraries) = try await (musicLibTask, videoLibTask)
            
            await MainActor.run {
                self.currentServer = server
                self.serverClient = client
                self.musicLibraries = libraries
                self.videoLibraries = vidLibraries
                self.connectionState = .connected
                
                // Auto-select music library
                if let savedLibId = UserDefaults.standard.string(forKey: "JellyfinCurrentMusicLibraryID"),
                   let savedLib = libraries.first(where: { $0.id == savedLibId }) {
                    self.currentMusicLibrary = savedLib
                } else if libraries.count == 1 {
                    self.currentMusicLibrary = libraries.first
                }
                
                // Auto-select movie library: prefer saved, then find first "movies" type, then single fallback
                if let savedMovieLibId = UserDefaults.standard.string(forKey: "JellyfinCurrentMovieLibraryID"),
                   let savedLib = vidLibraries.first(where: { $0.id == savedMovieLibId }) {
                    self.currentMovieLibrary = savedLib
                } else if let movieLib = vidLibraries.first(where: { $0.collectionType == "movies" }) {
                    self.currentMovieLibrary = movieLib
                } else if vidLibraries.count == 1 {
                    self.currentMovieLibrary = vidLibraries.first
                }
                
                // Auto-select show library: prefer saved, then find first "tvshows" type, then single fallback
                if let savedShowLibId = UserDefaults.standard.string(forKey: "JellyfinCurrentShowLibraryID"),
                   let savedLib = vidLibraries.first(where: { $0.id == savedShowLibId }) {
                    self.currentShowLibrary = savedLib
                } else if let showLib = vidLibraries.first(where: { $0.collectionType == "tvshows" }) {
                    self.currentShowLibrary = showLib
                } else if vidLibraries.count == 1 {
                    self.currentShowLibrary = vidLibraries.first
                }
            }
            
            NSLog("JellyfinManager: Connected to '%@' with %d music libraries, %d video libraries", server.name, libraries.count, vidLibraries.count)
            
            // Start preload in background without blocking browser connection flow.
            Task.detached(priority: .utility) { [weak self] in
                await self?.preloadLibraryContent()
            }
            
        } catch {
            await MainActor.run {
                self.connectionState = .error(error)
            }
            throw error
        }
    }
    
    /// Connect in background (for startup)
    private func connectInBackground(to server: JellyfinServer) async {
        do {
            try await connect(to: server)
        } catch {
            NSLog("JellyfinManager: Background connection failed: %@", error.localizedDescription)
        }
    }
    
    /// Disconnect from current server
    func disconnect() {
        currentServer = nil
        serverClient = nil
        connectionState = .disconnected
        musicLibraries = []
        currentMusicLibrary = nil
        videoLibraries = []
        currentMovieLibrary = nil
        currentShowLibrary = nil
        clearCachedContent()
        UserDefaults.standard.removeObject(forKey: "JellyfinCurrentServerID")
        UserDefaults.standard.removeObject(forKey: "JellyfinCurrentMusicLibraryID")
        UserDefaults.standard.removeObject(forKey: "JellyfinCurrentMovieLibraryID")
        UserDefaults.standard.removeObject(forKey: "JellyfinCurrentShowLibraryID")
    }
    
    /// Select a music library
    func selectMusicLibrary(_ library: JellyfinMusicLibrary) {
        currentMusicLibrary = library
        clearCachedContent()
        Task {
            await preloadLibraryContent()
        }
    }
    
    /// Clear music library selection (show all libraries)
    func clearMusicLibrarySelection() {
        currentMusicLibrary = nil
        clearCachedContent()
        Task {
            await preloadLibraryContent()
        }
    }
    
    /// Select a movie library (pass nil to show all)
    func selectMovieLibrary(_ library: JellyfinMusicLibrary?) {
        currentMovieLibrary = library
        cachedMovies = []
        NSLog("JellyfinManager: Selected movie library '%@'", library?.name ?? "all")
    }
    
    /// Select a TV show library (pass nil to show all)
    func selectShowLibrary(_ library: JellyfinMusicLibrary?) {
        currentShowLibrary = library
        cachedShows = []
        NSLog("JellyfinManager: Selected show library '%@'", library?.name ?? "all")
    }
    
    // MARK: - Library Preloading
    
    /// Preload library content in the background
    func preloadLibraryContent() async {
        guard let client = serverClient else {
            NSLog("JellyfinManager: Cannot preload - no server connected")
            return
        }
        
        guard !isPreloading else {
            NSLog("JellyfinManager: Already preloading, skipping")
            return
        }
        
        await MainActor.run {
            isPreloading = true
        }
        
        let libraryId = currentMusicLibrary?.id
        
        NSLog("JellyfinManager: Starting library content preload (library: %@)", libraryId ?? "all")
        
        do {
            // Keep startup preload music-focused for faster browser readiness.
            async let artistsTask = client.fetchAllArtists(libraryId: libraryId)
            async let albumsTask = client.fetchAllAlbums(libraryId: libraryId)
            async let playlistsTask = client.fetchPlaylists()

            let (artists, albums, playlists) = try await (artistsTask, albumsTask, playlistsTask)

            await MainActor.run {
                self.cachedArtists = artists
                self.cachedAlbums = albums
                self.cachedPlaylists = playlists
                self.isContentPreloaded = true
                self.isPreloading = false

                NSLog("JellyfinManager: Preloaded music content - %d artists, %d albums, %d playlists",
                      artists.count, albums.count, playlists.count)

                NotificationCenter.default.post(name: Self.libraryContentDidPreloadNotification, object: self)
            }

        } catch {
            NSLog("JellyfinManager: Library preload failed: %@", error.localizedDescription)
            await MainActor.run {
                self.isPreloading = false
            }
        }
    }
    
    /// Clear cached library content
    func clearCachedContent() {
        cachedArtists = []
        cachedAlbums = []
        cachedPlaylists = []
        cachedMovies = []
        cachedShows = []
        isContentPreloaded = false
    }
    
    // MARK: - Content Fetching
    
    /// Fetch artists (uses cache if available)
    func fetchArtists() async throws -> [JellyfinArtist] {
        if isContentPreloaded && !cachedArtists.isEmpty {
            return cachedArtists
        }

        guard let client = serverClient else { return [] }
        return try await client.fetchAllArtists(libraryId: currentMusicLibrary?.id)
    }

    /// Fetch all artists across all music libraries (no library filter, bypasses cache)
    func fetchArtistsUnfiltered() async throws -> [JellyfinArtist] {
        guard let client = serverClient else { return [] }
        return try await client.fetchAllArtists(libraryId: nil)
    }
    
    /// Fetch albums (uses cache if available)
    func fetchAlbums() async throws -> [JellyfinAlbum] {
        if isContentPreloaded && !cachedAlbums.isEmpty {
            return cachedAlbums
        }
        
        guard let client = serverClient else { return [] }
        return try await client.fetchAllAlbums(libraryId: currentMusicLibrary?.id)
    }
    
    /// Fetch playlists (uses cache if available)
    func fetchPlaylists() async throws -> [JellyfinPlaylist] {
        if isContentPreloaded && !cachedPlaylists.isEmpty {
            return cachedPlaylists
        }

        guard let client = serverClient else { return [] }
        return try await client.fetchPlaylists()
    }

    func fetchPlaylistSongs(id: String) async throws -> [JellyfinSong] {
        guard let client = serverClient else { throw JellyfinClientError.unauthorized }
        let result = try await client.fetchPlaylist(id: id)
        return result.songs
    }

    /// Fetch albums for an artist
    func fetchAlbums(forArtist artist: JellyfinArtist) async throws -> [JellyfinAlbum] {
        guard let client = serverClient else { return [] }
        let (_, albums) = try await client.fetchArtist(id: artist.id)
        return albums
    }
    
    /// Fetch songs for an album
    func fetchSongs(forAlbum album: JellyfinAlbum) async throws -> [JellyfinSong] {
        guard let client = serverClient else { return [] }
        let (_, songs) = try await client.fetchAlbum(id: album.id)
        return songs
    }
    
    // MARK: - Video Content Fetching
    
    /// Fetch movies (uses cache if available)
    func fetchMovies() async throws -> [JellyfinMovie] {
        if isContentPreloaded && !cachedMovies.isEmpty {
            return cachedMovies
        }
        
        guard let client = serverClient else { return [] }
        let movies = try await client.fetchMovies(libraryId: currentMovieLibrary?.id)
        await MainActor.run { self.cachedMovies = movies }
        return movies
    }

    /// Fetch TV shows (uses cache if available)
    func fetchShows() async throws -> [JellyfinShow] {
        if isContentPreloaded && !cachedShows.isEmpty {
            return cachedShows
        }

        guard let client = serverClient else { return [] }
        let shows = try await client.fetchShows(libraryId: currentShowLibrary?.id)
        await MainActor.run { self.cachedShows = shows }
        return shows
    }
    
    /// Fetch seasons for a TV show
    func fetchSeasons(forShow show: JellyfinShow) async throws -> [JellyfinSeason] {
        guard let client = serverClient else { return [] }
        return try await client.fetchSeasons(seriesId: show.id)
    }
    
    /// Fetch episodes for a season
    func fetchEpisodes(forSeason season: JellyfinSeason) async throws -> [JellyfinEpisode] {
        guard let client = serverClient else { return [] }
        return try await client.fetchEpisodes(seriesId: season.seriesId, seasonId: season.id)
    }
    
    // MARK: - Video URL Generation
    
    /// Get video streaming URL for a movie
    func videoStreamURL(for movie: JellyfinMovie) -> URL? {
        serverClient?.videoStreamURL(itemId: movie.id)
    }
    
    /// Get video streaming URL for an episode
    func videoStreamURL(for episode: JellyfinEpisode) -> URL? {
        serverClient?.videoStreamURL(itemId: episode.id)
    }
    
    // MARK: - Video Track Conversion
    
    /// Convert a Jellyfin movie to a Track for video playback
    func convertToTrack(_ movie: JellyfinMovie) -> Track? {
        guard let streamURL = videoStreamURL(for: movie) else { return nil }
        
        return Track(
            url: streamURL,
            title: movie.title,
            artist: nil,
            album: nil,
            duration: movie.duration.map { TimeInterval($0) } ?? 0,
            bitrate: nil,
            sampleRate: nil,
            channels: nil,
            plexRatingKey: nil,
            subsonicId: nil,
            subsonicServerId: nil,
            jellyfinId: movie.id,
            jellyfinServerId: currentServer?.id,
            artworkThumb: movie.imageTag,
            mediaType: .video,
            genre: nil
        )
    }
    
    /// Convert a Jellyfin episode to a Track for video playback
    func convertToTrack(_ episode: JellyfinEpisode) -> Track? {
        guard let streamURL = videoStreamURL(for: episode) else { return nil }
        
        let title: String
        if let showName = episode.seriesName {
            title = "\(showName) - \(episode.episodeIdentifier) - \(episode.title)"
        } else {
            title = episode.title
        }
        
        return Track(
            url: streamURL,
            title: title,
            artist: episode.seriesName,
            album: episode.seasonName,
            duration: episode.duration.map { TimeInterval($0) } ?? 0,
            bitrate: nil,
            sampleRate: nil,
            channels: nil,
            plexRatingKey: nil,
            subsonicId: nil,
            subsonicServerId: nil,
            jellyfinId: episode.id,
            jellyfinServerId: currentServer?.id,
            artworkThumb: episode.imageTag,
            mediaType: .video,
            genre: nil
        )
    }
    
    /// Search the library
    func search(query: String) async throws -> JellyfinSearchResults {
        guard let client = serverClient else {
            return JellyfinSearchResults()
        }
        return try await client.search(query: query)
    }
    
    // MARK: - Favorites
    
    /// Favorite an item
    func favorite(itemId: String) async throws {
        guard let client = serverClient else { return }
        try await client.favorite(itemId: itemId)
    }
    
    /// Unfavorite an item
    func unfavorite(itemId: String) async throws {
        guard let client = serverClient else { return }
        try await client.unfavorite(itemId: itemId)
    }
    
    // MARK: - Rating
    
    /// Set the rating for an item
    /// - Parameters:
    ///   - itemId: The Jellyfin item ID
    ///   - rating: Rating 0-100 (percentage)
    func setRating(itemId: String, rating: Int) async throws {
        guard let client = serverClient else { return }
        try await client.setRating(itemId: itemId, rating: rating)
    }
    
    // MARK: - URL Generation
    
    /// Get streaming URL for a song
    func streamURL(for song: JellyfinSong) -> URL? {
        serverClient?.streamURL(for: song)
    }
    
    /// Get image URL for an item
    func imageURL(itemId: String, imageTag: String?, size: Int = 300) -> URL? {
        serverClient?.imageURL(itemId: itemId, imageTag: imageTag, size: size)
    }
    
    // MARK: - Track Conversion
    
    /// Convert a Jellyfin song to an AudioEngine-compatible Track
    func convertToTrack(_ song: JellyfinSong) -> Track? {
        guard let streamURL = streamURL(for: song) else { return nil }
        
        // Derive MIME type from Jellyfin container name (e.g. "flac" -> "audio/flac")
        let mimeType = song.contentType.map { CastManager.detectAudioContentType(forExtension: $0) }
        
        return Track(
            url: streamURL,
            title: song.title,
            artist: song.artist,
            album: song.album,
            duration: song.durationInSeconds,
            bitrate: song.bitRate,
            sampleRate: song.sampleRate,
            channels: song.channels,
            plexRatingKey: nil,
            subsonicId: nil,
            subsonicServerId: nil,
            jellyfinId: song.id,
            jellyfinServerId: currentServer?.id,
            artworkThumb: song.imageTag,
            genre: song.genre,
            contentType: mimeType
        )
    }
    
    /// Convert multiple Jellyfin songs to Tracks
    func convertToTracks(_ songs: [JellyfinSong]) -> [Track] {
        songs.compactMap { convertToTrack($0) }
    }

    // MARK: - Radio

    func getMusicGenres() async -> [String] {
        guard let client = serverClient else { return [] }
        do {
            return try await client.fetchMusicGenres(libraryId: currentMusicLibrary?.id)
        } catch {
            NSLog("JellyfinManager: Failed to fetch genres: %@", error.localizedDescription)
            return []
        }
    }

    func createLibraryRadio(limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        do {
            let songs = try await client.fetchRandomSongs(limit: limit * 3, libraryId: currentMusicLibrary?.id)
            let allTracks = songs.compactMap { convertToTrack($0) }
            let historyFiltered = JellyfinRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit)
        } catch {
            NSLog("JellyfinManager: Failed to create library radio: %@", error.localizedDescription)
            return []
        }
    }

    func createLibraryRadioInstantMix(limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        let seedId: String?
        if let current = WindowManager.shared.audioEngine.currentTrack, let id = current.jellyfinId {
            seedId = id
        } else {
            do {
                let seeds = try await client.fetchRandomSongs(limit: 1, libraryId: currentMusicLibrary?.id)
                seedId = seeds.first?.id
            } catch { seedId = nil }
        }
        guard let id = seedId else { return await createLibraryRadio(limit: limit) }
        do {
            let songs = try await client.fetchInstantMixForTrack(itemId: id, limit: limit * 3)
            let allTracks = songs.compactMap { convertToTrack($0) }
            let historyFiltered = JellyfinRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit, maxPerArtist: 1)
        } catch {
            NSLog("JellyfinManager: Failed to create library radio (instant mix): %@", error.localizedDescription)
            return []
        }
    }

    func createGenreRadio(genre: String, limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        do {
            let songs = try await client.fetchSongsByGenre(genre: genre, limit: limit * 3, libraryId: currentMusicLibrary?.id)
            let allTracks = songs.compactMap { convertToTrack($0) }.shuffled()
            let historyFiltered = JellyfinRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit)
        } catch {
            NSLog("JellyfinManager: Failed to create genre radio (%@): %@", genre, error.localizedDescription)
            return []
        }
    }

    func createGenreRadioInstantMix(genre: String, limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        let seedId: String?
        if let current = WindowManager.shared.audioEngine.currentTrack, let id = current.jellyfinId {
            seedId = id
        } else {
            do {
                let seeds = try await client.fetchSongsByGenre(genre: genre, limit: 1, libraryId: currentMusicLibrary?.id)
                seedId = seeds.first?.id
            } catch { seedId = nil }
        }
        guard let id = seedId else { return await createGenreRadio(genre: genre, limit: limit) }
        do {
            let songs = try await client.fetchInstantMixForTrack(itemId: id, limit: limit * 3)
            let allTracks = songs.compactMap { convertToTrack($0) }
            let historyFiltered = JellyfinRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit, maxPerArtist: 1)
        } catch {
            NSLog("JellyfinManager: Failed to create genre radio (instant mix): %@", error.localizedDescription)
            return []
        }
    }

    func createDecadeRadio(start: Int, end: Int, limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        do {
            let songs = try await client.fetchSongsByDecade(startYear: start, endYear: end, limit: limit * 3, libraryId: currentMusicLibrary?.id)
            let allTracks = songs.compactMap { convertToTrack($0) }
            let historyFiltered = JellyfinRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit)
        } catch {
            NSLog("JellyfinManager: Failed to create decade radio (%d-%d): %@", start, end, error.localizedDescription)
            return []
        }
    }

    func createDecadeRadioInstantMix(start: Int, end: Int, limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        let seedId: String?
        if let current = WindowManager.shared.audioEngine.currentTrack, let id = current.jellyfinId {
            seedId = id
        } else {
            do {
                let seeds = try await client.fetchSongsByDecade(startYear: start, endYear: end, limit: 1, libraryId: currentMusicLibrary?.id)
                seedId = seeds.first?.id
            } catch { seedId = nil }
        }
        guard let id = seedId else { return await createDecadeRadio(start: start, end: end, limit: limit) }
        do {
            let songs = try await client.fetchInstantMixForTrack(itemId: id, limit: limit * 3)
            let allTracks = songs.compactMap { convertToTrack($0) }
            let historyFiltered = JellyfinRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit, maxPerArtist: 1)
        } catch {
            NSLog("JellyfinManager: Failed to create decade radio (instant mix): %@", error.localizedDescription)
            return []
        }
    }

    func createFavoritesRadio(limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        do {
            let songs = try await client.fetchFavoriteSongs(limit: limit * 3, libraryId: currentMusicLibrary?.id)
            let allTracks = songs.compactMap { convertToTrack($0) }.shuffled()
            let historyFiltered = JellyfinRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit)
        } catch {
            NSLog("JellyfinManager: Failed to create favorites radio: %@", error.localizedDescription)
            return []
        }
    }

    func createFavoritesRadioInstantMix(limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        let seedId: String?
        if let current = WindowManager.shared.audioEngine.currentTrack, let id = current.jellyfinId {
            seedId = id
        } else {
            do {
                let seeds = try await client.fetchFavoriteSongs(limit: 1, libraryId: currentMusicLibrary?.id)
                seedId = seeds.first?.id
            } catch { seedId = nil }
        }
        guard let id = seedId else { return await createFavoritesRadio(limit: limit) }
        do {
            let songs = try await client.fetchInstantMixForTrack(itemId: id, limit: limit * 3)
            let allTracks = songs.compactMap { convertToTrack($0) }
            let historyFiltered = JellyfinRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit, maxPerArtist: 1)
        } catch {
            NSLog("JellyfinManager: Failed to create favorites radio (instant mix): %@", error.localizedDescription)
            return []
        }
    }

    func createTrackRadio(from track: Track, limit: Int = 100) async -> [Track] {
        guard let client = serverClient, let trackId = track.jellyfinId else { return [] }
        do {
            let songs = try await client.fetchInstantMixForTrack(itemId: trackId, limit: limit * 3)
            let allTracks = songs.compactMap { convertToTrack($0) }
            let historyFiltered = JellyfinRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit, maxPerArtist: 1)
        } catch {
            NSLog("JellyfinManager: Failed to create track radio: %@", error.localizedDescription)
            return []
        }
    }

    func createArtistRadio(artistId: String, limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        do {
            let songs = try await client.fetchInstantMixForArtist(artistId: artistId, limit: limit * 3)
            let allTracks = songs.compactMap { convertToTrack($0) }
            let historyFiltered = JellyfinRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit, maxPerArtist: 1)
        } catch {
            NSLog("JellyfinManager: Failed to create artist radio: %@", error.localizedDescription)
            return []
        }
    }

    func createAlbumRadio(albumId: String, limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        do {
            let songs = try await client.fetchInstantMixForAlbum(albumId: albumId, limit: limit * 3)
            let allTracks = songs.compactMap { convertToTrack($0) }
            let historyFiltered = JellyfinRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit, maxPerArtist: 1)
        } catch {
            NSLog("JellyfinManager: Failed to create album radio: %@", error.localizedDescription)
            return []
        }
    }

    // MARK: - Radio Helpers

    private func filterForArtistVariety(_ tracks: [Track], limit: Int, maxPerArtist: Int = RadioPlaybackOptions.maxTracksPerArtist) -> [Track] {
        if maxPerArtist <= RadioPlaybackOptions.unlimitedMaxTracksPerArtist {
            return Array(tracks.prefix(limit))
        }
        var result: [Track] = []
        var artistCounts: [String: Int] = [:]
        for track in tracks {
            let artist = track.artist?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "unknown"
            let currentCount = artistCounts[artist, default: 0]
            if currentCount < maxPerArtist {
                result.append(track)
                artistCounts[artist] = currentCount + 1
                if result.count >= limit { break }
            }
        }
        return spreadArtistTracks(result)
    }

    private func spreadArtistTracks(_ tracks: [Track]) -> [Track] {
        guard tracks.count > 2 else { return tracks }
        var result: [Track] = []
        var remaining = tracks
        var lastArtist: String? = nil
        while !remaining.isEmpty {
            let nextIndex = remaining.firstIndex { track in
                let artist = track.artist?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "unknown"
                return artist != lastArtist
            }
            if let index = nextIndex {
                let track = remaining.remove(at: index)
                lastArtist = track.artist?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "unknown"
                result.append(track)
            } else {
                let track = remaining.removeFirst()
                lastArtist = track.artist?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "unknown"
                result.append(track)
            }
        }
        return result
    }
}
