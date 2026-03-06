import Foundation
import AppKit

/// Singleton managing Emby server connections and state
class EmbyManager {

    // MARK: - Singleton

    static let shared = EmbyManager()

    // MARK: - Notifications

    static let serversDidChangeNotification = Notification.Name("EmbyServersDidChange")
    static let connectionStateDidChangeNotification = Notification.Name("EmbyConnectionStateDidChange")
    static let libraryContentDidPreloadNotification = Notification.Name("EmbyLibraryContentDidPreload")
    static let musicLibraryDidChangeNotification = Notification.Name("EmbyMusicLibraryDidChange")
    static let videoLibraryDidChangeNotification = Notification.Name("EmbyVideoLibraryDidChange")

    // MARK: - Server State

    /// All configured servers
    private(set) var servers: [EmbyServer] = [] {
        didSet {
            NotificationCenter.default.post(name: Self.serversDidChangeNotification, object: self)
        }
    }

    /// Currently selected server
    private(set) var currentServer: EmbyServer? {
        didSet {
            if oldValue?.id != currentServer?.id {
                serverClient = nil
                clearCachedContent()

                if let server = currentServer,
                   let credentials = KeychainHelper.shared.getEmbyServer(id: server.id) {
                    serverClient = EmbyServerClient(credentials: credentials)
                }
            }
            UserDefaults.standard.set(currentServer?.id, forKey: "EmbyCurrentServerID")
        }
    }

    /// Client for the current server
    private(set) var serverClient: EmbyServerClient?

    // MARK: - Music Libraries

    /// Available music libraries on the current server
    private(set) var musicLibraries: [EmbyMusicLibrary] = []

    /// Currently selected music library
    private(set) var currentMusicLibrary: EmbyMusicLibrary? {
        didSet {
            UserDefaults.standard.set(currentMusicLibrary?.id, forKey: "EmbyCurrentMusicLibraryID")
            NotificationCenter.default.post(name: Self.musicLibraryDidChangeNotification, object: self)
        }
    }

    // MARK: - Video Libraries

    /// All video libraries (movies + tvshows) on the current server
    private(set) var videoLibraries: [EmbyMusicLibrary] = []

    /// Currently selected movie library
    private(set) var currentMovieLibrary: EmbyMusicLibrary? {
        didSet {
            UserDefaults.standard.set(currentMovieLibrary?.id, forKey: "EmbyCurrentMovieLibraryID")
            NotificationCenter.default.post(name: Self.videoLibraryDidChangeNotification, object: self)
        }
    }

    /// Currently selected TV show library
    private(set) var currentShowLibrary: EmbyMusicLibrary? {
        didSet {
            UserDefaults.standard.set(currentShowLibrary?.id, forKey: "EmbyCurrentShowLibraryID")
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

    // MARK: - Cached Library Content

    /// Cached artists
    private(set) var cachedArtists: [EmbyArtist] = []

    /// Cached albums
    private(set) var cachedAlbums: [EmbyAlbum] = []

    /// Cached playlists
    private(set) var cachedPlaylists: [EmbyPlaylist] = []

    /// Cached movies
    private(set) var cachedMovies: [EmbyMovie] = []

    /// Cached TV shows
    private(set) var cachedShows: [EmbyShow] = []

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
        let credentials = KeychainHelper.shared.getEmbyServers()
        servers = credentials.map { cred in
            EmbyServer(
                id: cred.id,
                name: cred.name,
                url: cred.url,
                username: cred.username,
                userId: cred.userId
            )
        }

        NSLog("EmbyManager: Loaded %d saved servers", servers.count)

        // Restore previous server selection
        if let savedServerID = UserDefaults.standard.string(forKey: "EmbyCurrentServerID"),
           let savedServer = servers.first(where: { $0.id == savedServerID }) {
            Task {
                await connectInBackground(to: savedServer)
            }
        }
    }

    // MARK: - Server Management

    /// Add a new server
    @discardableResult
    func addServer(name: String, url: String, username: String, password: String) async throws -> EmbyServer {
        // Clean up URL
        var cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanURL.hasSuffix("/") {
            cleanURL = String(cleanURL.dropLast())
        }

        // Generate a unique ID
        let id = UUID().uuidString
        let deviceId = KeychainHelper.shared.getOrCreateClientIdentifier()

        // Authenticate with the server first
        let authResponse: EmbyAuthResponse
        do {
            authResponse = try await EmbyServerClient.authenticate(
                url: cleanURL,
                username: username,
                password: password,
                deviceId: deviceId
            )
        } catch {
            throw error
        }

        // Create credentials with auth token
        let credentials = EmbyServerCredentials(
            id: id,
            name: name,
            url: cleanURL,
            username: username,
            password: password,
            accessToken: authResponse.AccessToken,
            userId: authResponse.User.Id
        )

        // Save to keychain
        _ = KeychainHelper.shared.addEmbyServer(credentials)

        // Create server object
        let server = EmbyServer(
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

        NSLog("EmbyManager: Added server '%@' at %@", name, cleanURL)

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
        let authResponse = try await EmbyServerClient.authenticate(
            url: cleanURL,
            username: username,
            password: password,
            deviceId: deviceId
        )

        let credentials = EmbyServerCredentials(
            id: id,
            name: name,
            url: cleanURL,
            username: username,
            password: password,
            accessToken: authResponse.AccessToken,
            userId: authResponse.User.Id
        )

        // Update in keychain
        _ = KeychainHelper.shared.updateEmbyServer(credentials)

        // Update local server list
        let server = EmbyServer(
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
                self.serverClient = EmbyServerClient(credentials: credentials)
            }
        }

        NSLog("EmbyManager: Updated server '%@'", name)
    }

    /// Remove a server
    func removeServer(id: String) {
        _ = KeychainHelper.shared.removeEmbyServer(id: id)

        servers.removeAll { $0.id == id }

        // If this was the current server, disconnect
        if currentServer?.id == id {
            currentServer = nil
            serverClient = nil
            connectionState = .disconnected
            clearCachedContent()
        }

        NSLog("EmbyManager: Removed server with ID %@", id)
    }

    /// Connect to a specific server
    func connect(to server: EmbyServer) async throws {
        guard let credentials = KeychainHelper.shared.getEmbyServer(id: server.id) else {
            throw EmbyClientError.unauthorized
        }

        guard let client = EmbyServerClient(credentials: credentials) else {
            throw EmbyClientError.invalidURL
        }

        NSLog("EmbyManager: Connecting to server '%@'", server.name)

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
                if let savedLibId = UserDefaults.standard.string(forKey: "EmbyCurrentMusicLibraryID"),
                   let savedLib = libraries.first(where: { $0.id == savedLibId }) {
                    self.currentMusicLibrary = savedLib
                } else if libraries.count == 1 {
                    self.currentMusicLibrary = libraries.first
                }

                // Auto-select movie library: prefer saved, then find first "movies" type, then single fallback
                if let savedMovieLibId = UserDefaults.standard.string(forKey: "EmbyCurrentMovieLibraryID"),
                   let savedLib = vidLibraries.first(where: { $0.id == savedMovieLibId }) {
                    self.currentMovieLibrary = savedLib
                } else if let movieLib = vidLibraries.first(where: { $0.collectionType == "movies" }) {
                    self.currentMovieLibrary = movieLib
                } else if vidLibraries.count == 1 {
                    self.currentMovieLibrary = vidLibraries.first
                }

                // Auto-select show library: prefer saved, then find first "tvshows" type, then single fallback
                if let savedShowLibId = UserDefaults.standard.string(forKey: "EmbyCurrentShowLibraryID"),
                   let savedLib = vidLibraries.first(where: { $0.id == savedShowLibId }) {
                    self.currentShowLibrary = savedLib
                } else if let showLib = vidLibraries.first(where: { $0.collectionType == "tvshows" }) {
                    self.currentShowLibrary = showLib
                } else if vidLibraries.count == 1 {
                    self.currentShowLibrary = vidLibraries.first
                }
            }

            NSLog("EmbyManager: Connected to '%@' with %d music libraries, %d video libraries", server.name, libraries.count, vidLibraries.count)

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
    private func connectInBackground(to server: EmbyServer) async {
        do {
            try await connect(to: server)
        } catch {
            NSLog("EmbyManager: Background connection failed: %@", error.localizedDescription)
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
        UserDefaults.standard.removeObject(forKey: "EmbyCurrentServerID")
        UserDefaults.standard.removeObject(forKey: "EmbyCurrentMusicLibraryID")
        UserDefaults.standard.removeObject(forKey: "EmbyCurrentMovieLibraryID")
        UserDefaults.standard.removeObject(forKey: "EmbyCurrentShowLibraryID")
    }

    /// Select a music library
    func selectMusicLibrary(_ library: EmbyMusicLibrary) {
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
    func selectMovieLibrary(_ library: EmbyMusicLibrary?) {
        currentMovieLibrary = library
        cachedMovies = []
        NSLog("EmbyManager: Selected movie library '%@'", library?.name ?? "all")
    }

    /// Select a TV show library (pass nil to show all)
    func selectShowLibrary(_ library: EmbyMusicLibrary?) {
        currentShowLibrary = library
        cachedShows = []
        NSLog("EmbyManager: Selected show library '%@'", library?.name ?? "all")
    }

    // MARK: - Library Preloading

    /// Preload library content in the background
    func preloadLibraryContent() async {
        guard let client = serverClient else {
            NSLog("EmbyManager: Cannot preload - no server connected")
            return
        }

        guard !isPreloading else {
            NSLog("EmbyManager: Already preloading, skipping")
            return
        }

        await MainActor.run {
            isPreloading = true
        }

        let libraryId = currentMusicLibrary?.id

        NSLog("EmbyManager: Starting library content preload (library: %@)", libraryId ?? "all")

        do {
            // Fetch artists, albums, and playlists in parallel
            async let artistsTask = client.fetchAllArtists(libraryId: libraryId)
            async let albumsTask = client.fetchAllAlbums(libraryId: libraryId)
            async let playlistsTask = client.fetchPlaylists()

            let (artists, albums, playlists) = try await (artistsTask, albumsTask, playlistsTask)

            // Also preload movies and shows
            var movies: [EmbyMovie] = []
            var shows: [EmbyShow] = []

            do {
                movies = try await client.fetchMovies(libraryId: currentMovieLibrary?.id)
            } catch {
                NSLog("EmbyManager: Movie preload failed: %@", error.localizedDescription)
            }

            do {
                shows = try await client.fetchShows(libraryId: currentShowLibrary?.id)
            } catch {
                NSLog("EmbyManager: Show preload failed: %@", error.localizedDescription)
            }

            await MainActor.run {
                self.cachedArtists = artists
                self.cachedAlbums = albums
                self.cachedPlaylists = playlists
                self.cachedMovies = movies
                self.cachedShows = shows
                self.isContentPreloaded = true
                self.isPreloading = false

                NSLog("EmbyManager: Preloaded %d artists, %d albums, %d playlists, %d movies, %d shows",
                      artists.count, albums.count, playlists.count, movies.count, shows.count)

                NotificationCenter.default.post(name: Self.libraryContentDidPreloadNotification, object: self)
            }

        } catch {
            NSLog("EmbyManager: Library preload failed: %@", error.localizedDescription)
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
    func fetchArtists() async throws -> [EmbyArtist] {
        if isContentPreloaded && !cachedArtists.isEmpty {
            return cachedArtists
        }

        guard let client = serverClient else { return [] }
        return try await client.fetchAllArtists(libraryId: currentMusicLibrary?.id)
    }

    /// Fetch all artists across all music libraries (no library filter, bypasses cache)
    func fetchArtistsUnfiltered() async throws -> [EmbyArtist] {
        guard let client = serverClient else { return [] }
        return try await client.fetchAllArtists(libraryId: nil)
    }

    /// Fetch albums (uses cache if available)
    func fetchAlbums() async throws -> [EmbyAlbum] {
        if isContentPreloaded && !cachedAlbums.isEmpty {
            return cachedAlbums
        }

        guard let client = serverClient else { return [] }
        return try await client.fetchAllAlbums(libraryId: currentMusicLibrary?.id)
    }

    /// Fetch playlists (uses cache if available)
    func fetchPlaylists() async throws -> [EmbyPlaylist] {
        if isContentPreloaded && !cachedPlaylists.isEmpty {
            return cachedPlaylists
        }

        guard let client = serverClient else { return [] }
        return try await client.fetchPlaylists()
    }

    /// Fetch albums for an artist
    func fetchAlbums(forArtist artist: EmbyArtist) async throws -> [EmbyAlbum] {
        guard let client = serverClient else { return [] }
        let (_, albums) = try await client.fetchArtist(id: artist.id)
        return albums
    }

    /// Fetch songs for an album
    func fetchSongs(forAlbum album: EmbyAlbum) async throws -> [EmbySong] {
        guard let client = serverClient else { return [] }
        let (_, songs) = try await client.fetchAlbum(id: album.id)
        return songs
    }

    // MARK: - Video Content Fetching

    /// Fetch movies (uses cache if available)
    func fetchMovies() async throws -> [EmbyMovie] {
        if isContentPreloaded && !cachedMovies.isEmpty {
            return cachedMovies
        }

        guard let client = serverClient else { return [] }
        let movies = try await client.fetchMovies(libraryId: currentMovieLibrary?.id)
        await MainActor.run { self.cachedMovies = movies }
        return movies
    }

    /// Fetch TV shows (uses cache if available)
    func fetchShows() async throws -> [EmbyShow] {
        if isContentPreloaded && !cachedShows.isEmpty {
            return cachedShows
        }

        guard let client = serverClient else { return [] }
        let shows = try await client.fetchShows(libraryId: currentShowLibrary?.id)
        await MainActor.run { self.cachedShows = shows }
        return shows
    }

    /// Fetch seasons for a TV show
    func fetchSeasons(forShow show: EmbyShow) async throws -> [EmbySeason] {
        guard let client = serverClient else { return [] }
        return try await client.fetchSeasons(seriesId: show.id)
    }

    /// Fetch episodes for a season
    func fetchEpisodes(forSeason season: EmbySeason) async throws -> [EmbyEpisode] {
        guard let client = serverClient else { return [] }
        return try await client.fetchEpisodes(seriesId: season.seriesId, seasonId: season.id)
    }

    // MARK: - Video URL Generation

    /// Get video streaming URL for a movie
    func videoStreamURL(for movie: EmbyMovie) -> URL? {
        serverClient?.videoStreamURL(itemId: movie.id)
    }

    /// Get video streaming URL for an episode
    func videoStreamURL(for episode: EmbyEpisode) -> URL? {
        serverClient?.videoStreamURL(itemId: episode.id)
    }

    // MARK: - Video Track Conversion

    /// Convert an Emby movie to a Track for video playback
    func convertToTrack(_ movie: EmbyMovie) -> Track? {
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
            jellyfinId: nil,
            jellyfinServerId: nil,
            embyId: movie.id,
            embyServerId: currentServer?.id,
            artworkThumb: movie.imageTag,
            mediaType: .video,
            genre: nil
        )
    }

    /// Convert an Emby episode to a Track for video playback
    func convertToTrack(_ episode: EmbyEpisode) -> Track? {
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
            jellyfinId: nil,
            jellyfinServerId: nil,
            embyId: episode.id,
            embyServerId: currentServer?.id,
            artworkThumb: episode.imageTag,
            mediaType: .video,
            genre: nil
        )
    }

    /// Search the library
    func search(query: String) async throws -> EmbySearchResults {
        guard let client = serverClient else {
            return EmbySearchResults()
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
    ///   - itemId: The Emby item ID
    ///   - rating: Rating 0-100 (percentage)
    func setRating(itemId: String, rating: Int) async throws {
        guard let client = serverClient else { return }
        try await client.setRating(itemId: itemId, rating: rating)
    }

    // MARK: - URL Generation

    /// Get streaming URL for a song
    func streamURL(for song: EmbySong) -> URL? {
        serverClient?.streamURL(for: song)
    }

    /// Get image URL for an item
    func imageURL(itemId: String, imageTag: String?, size: Int = 300) -> URL? {
        serverClient?.imageURL(itemId: itemId, imageTag: imageTag, size: size)
    }

    // MARK: - Track Conversion

    /// Convert an Emby song to an AudioEngine-compatible Track
    func convertToTrack(_ song: EmbySong) -> Track? {
        guard let streamURL = streamURL(for: song) else { return nil }

        // Derive MIME type from Emby container name (e.g. "flac" -> "audio/flac")
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
            jellyfinId: nil,
            jellyfinServerId: nil,
            embyId: song.id,
            embyServerId: currentServer?.id,
            artworkThumb: song.imageTag,
            genre: song.genre,
            contentType: mimeType
        )
    }

    /// Convert multiple Emby songs to Tracks
    func convertToTracks(_ songs: [EmbySong]) -> [Track] {
        songs.compactMap { convertToTrack($0) }
    }

    // MARK: - Radio

    func getMusicGenres() async -> [String] {
        guard let client = serverClient else { return [] }
        do {
            return try await client.fetchMusicGenres(libraryId: currentMusicLibrary?.id)
        } catch {
            NSLog("EmbyManager: Failed to fetch genres: %@", error.localizedDescription)
            return []
        }
    }

    func createLibraryRadio(limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        do {
            let songs = try await client.fetchRandomSongs(limit: limit * 3, libraryId: currentMusicLibrary?.id)
            let allTracks = songs.compactMap { convertToTrack($0) }
            let historyFiltered = EmbyRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit)
        } catch {
            NSLog("EmbyManager: Failed to create library radio: %@", error.localizedDescription)
            return []
        }
    }

    func createLibraryRadioInstantMix(limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        let seedId: String?
        if let current = WindowManager.shared.audioEngine.currentTrack,
           let id = current.embyId, current.embyServerId == currentServer?.id {
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
            let historyFiltered = EmbyRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit, maxPerArtist: 1)
        } catch {
            NSLog("EmbyManager: Failed to create library radio (instant mix): %@", error.localizedDescription)
            return []
        }
    }

    func createGenreRadio(genre: String, limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        do {
            let songs = try await client.fetchSongsByGenre(genre: genre, limit: limit * 3, libraryId: currentMusicLibrary?.id)
            let allTracks = songs.compactMap { convertToTrack($0) }.shuffled()
            let historyFiltered = EmbyRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit)
        } catch {
            NSLog("EmbyManager: Failed to create genre radio (%@): %@", genre, error.localizedDescription)
            return []
        }
    }

    func createGenreRadioInstantMix(genre: String, limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        let seedId: String?
        if let current = WindowManager.shared.audioEngine.currentTrack,
           let id = current.embyId, current.embyServerId == currentServer?.id {
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
            let historyFiltered = EmbyRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit, maxPerArtist: 1)
        } catch {
            NSLog("EmbyManager: Failed to create genre radio (instant mix): %@", error.localizedDescription)
            return []
        }
    }

    func createDecadeRadio(start: Int, end: Int, limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        do {
            let songs = try await client.fetchSongsByDecade(startYear: start, endYear: end, limit: limit * 3, libraryId: currentMusicLibrary?.id)
            let allTracks = songs.compactMap { convertToTrack($0) }
            let historyFiltered = EmbyRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit)
        } catch {
            NSLog("EmbyManager: Failed to create decade radio (%d-%d): %@", start, end, error.localizedDescription)
            return []
        }
    }

    func createDecadeRadioInstantMix(start: Int, end: Int, limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        let seedId: String?
        if let current = WindowManager.shared.audioEngine.currentTrack,
           let id = current.embyId, current.embyServerId == currentServer?.id {
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
            let historyFiltered = EmbyRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit, maxPerArtist: 1)
        } catch {
            NSLog("EmbyManager: Failed to create decade radio (instant mix): %@", error.localizedDescription)
            return []
        }
    }

    func createFavoritesRadio(limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        do {
            let songs = try await client.fetchFavoriteSongs(limit: limit * 3, libraryId: currentMusicLibrary?.id)
            let allTracks = songs.compactMap { convertToTrack($0) }.shuffled()
            let historyFiltered = EmbyRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit)
        } catch {
            NSLog("EmbyManager: Failed to create favorites radio: %@", error.localizedDescription)
            return []
        }
    }

    func createFavoritesRadioInstantMix(limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        let seedId: String?
        if let current = WindowManager.shared.audioEngine.currentTrack,
           let id = current.embyId, current.embyServerId == currentServer?.id {
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
            let historyFiltered = EmbyRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit, maxPerArtist: 1)
        } catch {
            NSLog("EmbyManager: Failed to create favorites radio (instant mix): %@", error.localizedDescription)
            return []
        }
    }

    func createTrackRadio(from track: Track, limit: Int = 100) async -> [Track] {
        guard let client = serverClient, let trackId = track.embyId else { return [] }
        do {
            let songs = try await client.fetchInstantMixForTrack(itemId: trackId, limit: limit * 3)
            let allTracks = songs.compactMap { convertToTrack($0) }
            let historyFiltered = EmbyRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit, maxPerArtist: 1)
        } catch {
            NSLog("EmbyManager: Failed to create track radio: %@", error.localizedDescription)
            return []
        }
    }

    func createArtistRadio(artistId: String, limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        do {
            let songs = try await client.fetchInstantMixForArtist(artistId: artistId, limit: limit * 3)
            let allTracks = songs.compactMap { convertToTrack($0) }
            let historyFiltered = EmbyRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit, maxPerArtist: 1)
        } catch {
            NSLog("EmbyManager: Failed to create artist radio: %@", error.localizedDescription)
            return []
        }
    }

    func createAlbumRadio(albumId: String, limit: Int = 100) async -> [Track] {
        guard let client = serverClient else { return [] }
        do {
            let songs = try await client.fetchInstantMixForAlbum(albumId: albumId, limit: limit * 3)
            let allTracks = songs.compactMap { convertToTrack($0) }
            let historyFiltered = EmbyRadioHistory.shared.filterOutHistoryTracks(allTracks)
            return filterForArtistVariety(historyFiltered, limit: limit, maxPerArtist: 1)
        } catch {
            NSLog("EmbyManager: Failed to create album radio: %@", error.localizedDescription)
            return []
        }
    }

    // MARK: - Radio Helpers

    private func filterForArtistVariety(_ tracks: [Track], limit: Int, maxPerArtist: Int = 2) -> [Track] {
        var result: [Track] = []
        var artistCounts: [String: Int] = [:]
        for track in tracks {
            let artist = track.artist ?? ""
            let count = artistCounts[artist] ?? 0
            if count < maxPerArtist {
                result.append(track)
                artistCounts[artist] = count + 1
            }
            if result.count >= limit { break }
        }
        return result
    }
}
