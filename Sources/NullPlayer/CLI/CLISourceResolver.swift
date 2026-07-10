import Foundation
import NullPlayerCore

enum CLISourceError: LocalizedError {
    case noSource(String? = nil)
    case sourceNotConfigured(String)
    case noTracksFound(String)
    case invalidRadioMode(String, String, [String])
    case missingRequiredArg(String, String)
    case unsupportedVideoSource(String)

    var errorDescription: String? {
        switch self {
        case .noSource(let detail):
            if let detail { return detail }
            return "No source specified. Use --source (local, plex, subsonic, jellyfin, emby, radio)"
        case .sourceNotConfigured(let source):
            return "\(source) is not configured. Set up in NullPlayer GUI first."
        case .noTracksFound(let detail):
            return "No tracks found \(detail)"
        case .invalidRadioMode(let mode, let source, let available):
            return "Radio mode '\(mode)' not available for \(source). Available: \(available.joined(separator: ", "))"
        case .missingRequiredArg(let flag, let requires):
            return "\(flag) requires \(requires)"
        case .unsupportedVideoSource(let source):
            return "Video casting is supported for local files, Plex, Jellyfin, and Emby, not \(source)."
        }
    }
}

/// Result type to distinguish audio playback, radio station playback, and video casting.
enum CLIResolveResult {
    case tracks([Track])
    case radioStation  // RadioManager handles playback directly
    case video(CLIVideoItem)
}

enum CLIVideoItem {
    case localFile(URL, title: String)
    case plexMovie(PlexMovie)
    case plexEpisode(PlexEpisode)
    case jellyfinMovie(JellyfinMovie)
    case jellyfinEpisode(JellyfinEpisode)
    case embyMovie(EmbyMovie)
    case embyEpisode(EmbyEpisode)

    var displayTitle: String {
        switch self {
        case .localFile(_, let title):
            return title
        case .plexMovie(let movie):
            return movie.title
        case .plexEpisode(let episode):
            return [episode.grandparentTitle, episode.episodeIdentifier, episode.title]
                .compactMap { $0 }
                .joined(separator: " - ")
        case .jellyfinMovie(let movie):
            return movie.title
        case .jellyfinEpisode(let episode):
            return [episode.seriesName, episode.episodeIdentifier, episode.title]
                .compactMap { $0 }
                .joined(separator: " - ")
        case .embyMovie(let movie):
            return movie.title
        case .embyEpisode(let episode):
            return [episode.seriesName, episode.episodeIdentifier, episode.title]
                .compactMap { $0 }
                .joined(separator: " - ")
        }
    }
}

struct CLISourceResolver {

    static func resolve(_ opts: CLIOptions) async throws -> CLIResolveResult {
        let source = opts.source ?? "local"

        if let filePath = opts.file {
            return try resolveFile(filePath)
        }

        if opts.movie != nil || opts.episode != nil {
            try await checkConnectivity(source: source)
            if source == "local" {
                return try await resolveVideo(source: source, opts: opts)
            }
            if let libraryName = opts.library {
                try await applyVideoLibrary(source: source, name: libraryName, wantsShows: opts.episode != nil)
            } else {
                try ensureVideoLibrarySelected(source: source, wantsShows: opts.episode != nil)
            }
            return try await resolveVideo(source: source, opts: opts)
        }

        // Check connectivity
        try await checkConnectivity(source: source)

        // Apply the explicit library, or ensure a music library is selected for the
        // music-only operations that follow (artist/album/search AND server radio).
        // Playlists are server-level, so they skip selection. No-op for local/subsonic/radio.
        if let libraryName = opts.library {
            try await applyLibrary(source: source, name: libraryName)
        } else if opts.playlist == nil {
            try ensureMusicLibrarySelected(source: source)
        }

        // Radio mode
        if let radioMode = opts.radio {
            let tracks = try await resolveRadio(source: source, mode: radioMode, opts: opts)
            return .tracks(tracks)
        }

        // Internet radio station — RadioManager handles playback directly
        if let stationName = opts.station, source == "radio" {
            let stations = RadioManager.shared.searchStations(query: stationName)
            guard let station = stations.first else {
                throw CLISourceError.noTracksFound("for station '\(stationName)'")
            }
            RadioManager.shared.play(station: station)
            return .radioStation
        }

        // Standard content resolution (music library already ensured above).
        var tracks = try await resolveContent(source: source, opts: opts)

        // Post-filter by --track
        if let trackName = opts.track {
            tracks = tracks.filter { ($0.title ?? "").localizedCaseInsensitiveContains(trackName) }
        }

        return .tracks(tracks)
    }

    // MARK: - Connectivity
    // internal (not private) so CLIQueryHandler can also call it
    static func checkConnectivity(source: String) async throws {
        switch source {
        case "local":
            break // Will fail at query time if empty
        case "plex":
            guard PlexManager.shared.isLinked else {
                throw CLISourceError.sourceNotConfigured("Plex")
            }
            // Wait for the background server refresh so serverClient / currentLibrary
            // are populated before we query. Without this, queries race the refresh
            // and silently return empty results ("artist not found").
            await PlexManager.shared.serverRefreshTask?.value
        case "subsonic":
            await SubsonicManager.shared.serverConnectTask?.value
            if case .connected = SubsonicManager.shared.connectionState { } else {
                throw CLISourceError.sourceNotConfigured("Subsonic")
            }
        case "jellyfin":
            await JellyfinManager.shared.serverConnectTask?.value
            if case .connected = JellyfinManager.shared.connectionState { } else {
                throw CLISourceError.sourceNotConfigured("Jellyfin")
            }
        case "emby":
            await EmbyManager.shared.serverConnectTask?.value
            if case .connected = EmbyManager.shared.connectionState { } else {
                throw CLISourceError.sourceNotConfigured("Emby")
            }
        case "radio":
            break // Always available
        default:
            fputs("Error: Unknown source '\(source)'. Use: local, plex, subsonic, jellyfin, emby, radio\n", cliStderr)
            CLIPlayer.exitAndRestoreTerminal(code: 1)
        }
    }

    // MARK: - Library Selection

    // internal so CLIQueryHandler can also call it
    static func applyLibrary(source: String, name: String) async throws {
        switch source {
        case "plex":
            // Wait for background server refresh to populate availableLibraries
            await PlexManager.shared.serverRefreshTask?.value
            let libs = PlexManager.shared.availableLibraries
            guard let lib = libs.first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("— library '\(name)' not found on Plex. Available: \(libs.map { $0.title }.joined(separator: ", "))")
            }
            PlexManager.shared.selectLibrary(lib)
        case "subsonic":
            let folders = SubsonicManager.shared.musicFolders
            guard let folder = folders.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("— music folder '\(name)' not found on Subsonic. Available: \(folders.map { $0.name }.joined(separator: ", "))")
            }
            SubsonicManager.shared.selectMusicFolder(folder)
        case "jellyfin":
            let libs = JellyfinManager.shared.musicLibraries
            guard let lib = libs.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("— library '\(name)' not found on Jellyfin. Available: \(libs.map { $0.name }.joined(separator: ", "))")
            }
            JellyfinManager.shared.selectMusicLibrary(lib)
        case "emby":
            let libs = EmbyManager.shared.musicLibraries
            guard let lib = libs.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("— library '\(name)' not found on Emby. Available: \(libs.map { $0.name }.joined(separator: ", "))")
            }
            EmbyManager.shared.selectMusicLibrary(lib)
        default:
            break // local and radio don't have sub-libraries
        }
    }

    /// Ensure a *music* library is selected for music-only queries/playback when the
    /// user did not pass an explicit `--library`. Plex, Jellyfin, and Emby all expose
    /// non-music sections (Movies/TV, and on Jellyfin/Emby also Playlists), and the
    /// restored "current library" — carried over from the GUI's last selection — may be
    /// one of those. Music queries against a non-music library silently return nothing.
    /// Call only after `checkConnectivity`.
    ///
    /// - If the current library is already a music library, it is kept.
    /// - If there is exactly one music library, it is auto-selected.
    /// - If there are several, throws a clear "specify --library" error listing them.
    ///
    /// Subsonic/Navidrome is a music-only server (a nil music-folder selection means
    /// "all folders"), so it needs no adjustment.
    static func ensureMusicLibrarySelected(source: String) throws {
        switch source {
        case "plex":
            if PlexManager.shared.currentLibrary?.isMusicLibrary == true { return }
            let musicLibs = PlexManager.shared.availableLibraries.filter { $0.isMusicLibrary }
            guard let first = musicLibs.first else {
                throw CLISourceError.noTracksFound("— no music library found on Plex")
            }
            if musicLibs.count > 1 {
                throw CLISourceError.noTracksFound(
                    "— Plex has multiple music libraries; specify one with --library <name>. "
                    + "Available: \(musicLibs.map { $0.title }.joined(separator: ", "))")
            }
            PlexManager.shared.selectLibrary(first)

        case "jellyfin":
            // JellyfinManager.musicLibraries actually holds every view (Music, Playlists,
            // Video), so filter by collectionType to find the real music libraries.
            if JellyfinManager.shared.currentMusicLibrary?.collectionType?.lowercased() == "music" { return }
            let musicLibs = JellyfinManager.shared.musicLibraries.filter { $0.collectionType?.lowercased() == "music" }
            guard let first = musicLibs.first else {
                throw CLISourceError.noTracksFound("— no music library found on Jellyfin")
            }
            if musicLibs.count > 1 {
                throw CLISourceError.noTracksFound(
                    "— Jellyfin has multiple music libraries; specify one with --library <name>. "
                    + "Available: \(musicLibs.map { $0.name }.joined(separator: ", "))")
            }
            JellyfinManager.shared.selectMusicLibrary(first)

        case "emby":
            if EmbyManager.shared.currentMusicLibrary?.collectionType?.lowercased() == "music" { return }
            let musicLibs = EmbyManager.shared.musicLibraries.filter { $0.collectionType?.lowercased() == "music" }
            guard let first = musicLibs.first else {
                throw CLISourceError.noTracksFound("— no music library found on Emby")
            }
            if musicLibs.count > 1 {
                throw CLISourceError.noTracksFound(
                    "— Emby has multiple music libraries; specify one with --library <name>. "
                    + "Available: \(musicLibs.map { $0.name }.joined(separator: ", "))")
            }
            EmbyManager.shared.selectMusicLibrary(first)

        default:
            break // subsonic (music-only), local, radio: nothing to adjust
        }
    }

    // MARK: - Content Resolution

    private static func resolveFile(_ path: String) throws -> CLIResolveResult {
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLISourceError.noTracksFound("— file '\(path)' not found")
        }

        let detected = detectContentType(for: url)
        let title = url.deletingPathExtension().lastPathComponent
        if detected.mediaType == .video {
            return .video(.localFile(url, title: title))
        }

        return .tracks([Track(url: url, title: title, contentType: detected.contentType)])
    }

    // internal (not private) so CLIQueryHandler.listTracks can reuse it
    static func resolveContent(source: String, opts: CLIOptions) async throws -> [Track] {
        switch source {
        case "local":
            return try await resolveLocal(opts)
        case "plex":
            return try await resolvePlex(opts)
        case "subsonic":
            return try await resolveSubsonic(opts)
        case "jellyfin":
            return try await resolveJellyfin(opts)
        case "emby":
            return try await resolveEmby(opts)
        default:
            throw CLISourceError.noSource()
        }
    }

    private static func resolveLocal(_ opts: CLIOptions) async throws -> [Track] {
        let library = MediaLibrary.shared

        if let query = opts.search {
            return library.search(query: query).map { $0.toTrack() }
        }

        if let genre = opts.genre {
            var filter = LibraryFilter()
            filter.genres = [genre]
            return library.filteredTracks(filter: filter, sortBy: .title).map { $0.toTrack() }
        }

        if let artistName = opts.artist {
            if let albumName = opts.album {
                var filter = LibraryFilter()
                filter.artists = [artistName]
                filter.albums = [albumName]
                return library.filteredTracks(filter: filter, sortBy: .title).map { $0.toTrack() }
            }
            var filter = LibraryFilter()
            filter.artists = [artistName]
            return library.filteredTracks(filter: filter, sortBy: .title).map { $0.toTrack() }
        }

        if let albumName = opts.album {
            var filter = LibraryFilter()
            filter.albums = [albumName]
            return library.filteredTracks(filter: filter, sortBy: .title).map { $0.toTrack() }
        }

        throw CLISourceError.noTracksFound("— specify --artist, --album, --genre, --search, or --track")
    }

    private static func resolvePlex(_ opts: CLIOptions) async throws -> [Track] {
        let mgr = PlexManager.shared

        if let query = opts.search {
            let results = try await mgr.search(query: query)
            return mgr.convertToTracks(results.tracks)
        }

        if let playlistName = opts.playlist {
            let playlists = try await mgr.fetchAudioPlaylists()
            guard let playlist = playlists.first(where: {
                $0.title.caseInsensitiveCompare(playlistName) == .orderedSame
            }) else {
                throw CLISourceError.noTracksFound("for playlist '\(playlistName)' on Plex")
            }
            let plexTracks = try await mgr.fetchPlaylistTracks(playlistID: playlist.id)
            return mgr.convertToTracks(plexTracks)
        }

        if let artistName = opts.artist {
            let artists = try await mgr.fetchArtists()
            guard let artist = artists.first(where: {
                $0.title.caseInsensitiveCompare(artistName) == .orderedSame  // PlexArtist uses .title
            }) else {
                throw CLISourceError.noTracksFound("for artist '\(artistName)' on Plex")
            }

            if let albumName = opts.album {
                let albums = try await mgr.fetchAlbums(forArtist: artist)
                guard let album = albums.first(where: {
                    $0.title.caseInsensitiveCompare(albumName) == .orderedSame
                }) else {
                    throw CLISourceError.noTracksFound("for album '\(albumName)' by '\(artistName)' on Plex")
                }
                let plexTracks = try await mgr.fetchTracks(forAlbum: album)
                return mgr.convertToTracks(plexTracks)
            }

            // All tracks by artist
            let albums = try await mgr.fetchAlbums(forArtist: artist)
            var allTracks: [Track] = []
            for album in albums {
                let plexTracks = try await mgr.fetchTracks(forAlbum: album)
                allTracks.append(contentsOf: mgr.convertToTracks(plexTracks))
            }
            return allTracks
        }

        throw CLISourceError.noTracksFound("— specify --artist, --search, or --playlist for Plex")
    }

    private static func resolveSubsonic(_ opts: CLIOptions) async throws -> [Track] {
        let mgr = SubsonicManager.shared

        if let query = opts.search {
            let results = try await mgr.search(query: query)
            return mgr.convertToTracks(results.songs)
        }

        if let playlistName = opts.playlist {
            let playlists = try await mgr.fetchPlaylists()
            guard let playlist = playlists.first(where: {
                $0.name.caseInsensitiveCompare(playlistName) == .orderedSame
            }) else {
                throw CLISourceError.noTracksFound("for playlist '\(playlistName)' on Subsonic")
            }
            let songs = try await mgr.fetchPlaylistSongs(id: playlist.id)
            return mgr.convertToTracks(songs)
        }

        if let artistName = opts.artist {
            let artists = try await mgr.fetchArtists()
            guard let artist = artists.first(where: {
                $0.name.caseInsensitiveCompare(artistName) == .orderedSame
            }) else {
                throw CLISourceError.noTracksFound("for artist '\(artistName)' on Subsonic")
            }

            if let albumName = opts.album {
                let albums = try await mgr.fetchAlbums(forArtist: artist)
                guard let album = albums.first(where: {
                    $0.name.caseInsensitiveCompare(albumName) == .orderedSame
                }) else {
                    throw CLISourceError.noTracksFound("for album '\(albumName)' by '\(artistName)' on Subsonic")
                }
                let songs = try await mgr.fetchSongs(forAlbum: album)
                return mgr.convertToTracks(songs)
            }

            let albums = try await mgr.fetchAlbums(forArtist: artist)
            var allTracks: [Track] = []
            for album in albums {
                let songs = try await mgr.fetchSongs(forAlbum: album)
                allTracks.append(contentsOf: mgr.convertToTracks(songs))
            }
            return allTracks
        }

        throw CLISourceError.noTracksFound("— specify --artist, --playlist, or --search for Subsonic")
    }

    private static func resolveJellyfin(_ opts: CLIOptions) async throws -> [Track] {
        let mgr = JellyfinManager.shared

        if let query = opts.search {
            let results = try await mgr.search(query: query, parentId: mgr.currentMusicLibrary?.id)
            return mgr.convertToTracks(results.songs)
        }

        if let playlistName = opts.playlist {
            let playlists = try await mgr.fetchPlaylists()
            guard let playlist = playlists.first(where: {
                $0.name.caseInsensitiveCompare(playlistName) == .orderedSame
            }) else {
                throw CLISourceError.noTracksFound("for playlist '\(playlistName)' on Jellyfin")
            }
            let songs = try await mgr.fetchPlaylistSongs(id: playlist.id)
            return mgr.convertToTracks(songs)
        }

        if let artistName = opts.artist {
            let artists = try await mgr.fetchArtists()
            guard let artist = artists.first(where: {
                $0.name.caseInsensitiveCompare(artistName) == .orderedSame
            }) else {
                throw CLISourceError.noTracksFound("for artist '\(artistName)' on Jellyfin")
            }

            if let albumName = opts.album {
                let albums = try await mgr.fetchAlbums(forArtist: artist)
                guard let album = albums.first(where: {
                    $0.name.caseInsensitiveCompare(albumName) == .orderedSame
                }) else {
                    throw CLISourceError.noTracksFound("for album '\(albumName)' by '\(artistName)' on Jellyfin")
                }
                let songs = try await mgr.fetchSongs(forAlbum: album)
                return mgr.convertToTracks(songs)
            }

            let albums = try await mgr.fetchAlbums(forArtist: artist)
            var allTracks: [Track] = []
            for album in albums {
                let songs = try await mgr.fetchSongs(forAlbum: album)
                allTracks.append(contentsOf: mgr.convertToTracks(songs))
            }
            return allTracks
        }

        throw CLISourceError.noTracksFound("— specify --artist, --playlist, or --search for Jellyfin")
    }

    private static func resolveEmby(_ opts: CLIOptions) async throws -> [Track] {
        let mgr = EmbyManager.shared

        if let query = opts.search {
            let results = try await mgr.search(query: query, parentId: mgr.currentMusicLibrary?.id)
            return mgr.convertToTracks(results.songs)
        }

        if let playlistName = opts.playlist {
            let playlists = try await mgr.fetchPlaylists()
            guard let playlist = playlists.first(where: {
                $0.name.caseInsensitiveCompare(playlistName) == .orderedSame
            }) else {
                throw CLISourceError.noTracksFound("for playlist '\(playlistName)' on Emby")
            }
            let songs = try await mgr.fetchPlaylistSongs(id: playlist.id)
            return mgr.convertToTracks(songs)
        }

        if let artistName = opts.artist {
            let artists = try await mgr.fetchArtists()
            guard let artist = artists.first(where: {
                $0.name.caseInsensitiveCompare(artistName) == .orderedSame
            }) else {
                throw CLISourceError.noTracksFound("for artist '\(artistName)' on Emby")
            }

            if let albumName = opts.album {
                let albums = try await mgr.fetchAlbums(forArtist: artist)
                guard let album = albums.first(where: {
                    $0.name.caseInsensitiveCompare(albumName) == .orderedSame
                }) else {
                    throw CLISourceError.noTracksFound("for album '\(albumName)' by '\(artistName)' on Emby")
                }
                let songs = try await mgr.fetchSongs(forAlbum: album)
                return mgr.convertToTracks(songs)
            }

            let albums = try await mgr.fetchAlbums(forArtist: artist)
            var allTracks: [Track] = []
            for album in albums {
                let songs = try await mgr.fetchSongs(forAlbum: album)
                allTracks.append(contentsOf: mgr.convertToTracks(songs))
            }
            return allTracks
        }

        throw CLISourceError.noTracksFound("— specify --artist, --playlist, or --search for Emby")
    }

    // MARK: - Video Resolution

    private enum VideoMatch {
        static func exactOrContains<T>(
            _ items: [T],
            query: String,
            title: (T) -> String,
            candidateDescription: (T) -> String
        ) throws -> T {
            let exact = items.filter { title($0).caseInsensitiveCompare(query) == .orderedSame }
            if exact.count == 1 { return exact[0] }

            let matches = exact.isEmpty
                ? items.filter { title($0).localizedCaseInsensitiveContains(query) }
                : exact
            guard let first = matches.first else {
                throw CLISourceError.noTracksFound("for '\(query)'")
            }
            guard matches.count == 1 else {
                let candidates = matches.prefix(10).map(candidateDescription).joined(separator: ", ")
                throw CLISourceError.noTracksFound("— ambiguous match for '\(query)'. Candidates: \(candidates)")
            }
            return first
        }
    }

    private static func resolveVideo(source: String, opts: CLIOptions) async throws -> CLIResolveResult {
        switch source {
        case "plex":
            return try await resolvePlexVideo(opts)
        case "jellyfin":
            return try await resolveJellyfinVideo(opts)
        case "emby":
            return try await resolveEmbyVideo(opts)
        case "local":
            throw CLISourceError.missingRequiredArg("--movie/--episode", "--source plex|jellyfin|emby")
        default:
            throw CLISourceError.unsupportedVideoSource(source)
        }
    }

    private static func resolvePlexVideo(_ opts: CLIOptions) async throws -> CLIResolveResult {
        let mgr = PlexManager.shared
        if let title = opts.movie {
            let movies = try await fetchAllPlexMovies()
            let movie = try VideoMatch.exactOrContains(
                movies,
                query: title,
                title: { $0.title },
                candidateDescription: { movie in
                    movie.year.map { "\(movie.title) (\($0))" } ?? movie.title
                }
            )
            return .video(.plexMovie(movie))
        }

        guard let episodeTitle = opts.episode else {
            throw CLISourceError.missingRequiredArg("--movie/--episode", "--movie <title> or --episode <title>")
        }
        guard let showName = opts.show else {
            throw CLISourceError.missingRequiredArg("--episode", "--show <name>")
        }
        let shows = try await fetchAllPlexShows()
        let show = try VideoMatch.exactOrContains(
            shows,
            query: showName,
            title: { $0.title },
            candidateDescription: { $0.title }
        )
        var seasons = try await mgr.fetchSeasons(forShow: show)
        if let seasonNumber = opts.season {
            seasons = seasons.filter { $0.index == seasonNumber }
        }
        var episodes: [PlexEpisode] = []
        for season in seasons {
            episodes.append(contentsOf: try await mgr.fetchEpisodes(forSeason: season))
        }
        if let episodeNumber = opts.number {
            episodes = episodes.filter { $0.index == episodeNumber }
        }
        let episode = try VideoMatch.exactOrContains(
            episodes,
            query: episodeTitle,
            title: { $0.title },
            candidateDescription: { "\($0.episodeIdentifier) \($0.title)" }
        )
        return .video(.plexEpisode(episode))
    }

    private static func resolveJellyfinVideo(_ opts: CLIOptions) async throws -> CLIResolveResult {
        let mgr = JellyfinManager.shared
        if let title = opts.movie {
            let movies = try await mgr.fetchMovies()
            let movie = try VideoMatch.exactOrContains(
                movies,
                query: title,
                title: { $0.title },
                candidateDescription: { movie in
                    movie.year.map { "\(movie.title) (\($0))" } ?? movie.title
                }
            )
            return .video(.jellyfinMovie(movie))
        }

        guard let episodeTitle = opts.episode else {
            throw CLISourceError.missingRequiredArg("--movie/--episode", "--movie <title> or --episode <title>")
        }
        guard let showName = opts.show else {
            throw CLISourceError.missingRequiredArg("--episode", "--show <name>")
        }
        let shows = try await mgr.fetchShows()
        let show = try VideoMatch.exactOrContains(
            shows,
            query: showName,
            title: { $0.title },
            candidateDescription: { $0.title }
        )
        var seasons = try await mgr.fetchSeasons(forShow: show)
        if let seasonNumber = opts.season {
            seasons = seasons.filter { $0.index == seasonNumber }
        }
        var episodes: [JellyfinEpisode] = []
        for season in seasons {
            episodes.append(contentsOf: try await mgr.fetchEpisodes(forSeason: season))
        }
        if let episodeNumber = opts.number {
            episodes = episodes.filter { $0.index == episodeNumber }
        }
        let episode = try VideoMatch.exactOrContains(
            episodes,
            query: episodeTitle,
            title: { $0.title },
            candidateDescription: { "\($0.episodeIdentifier) \($0.title)" }
        )
        return .video(.jellyfinEpisode(episode))
    }

    private static func resolveEmbyVideo(_ opts: CLIOptions) async throws -> CLIResolveResult {
        let mgr = EmbyManager.shared
        if let title = opts.movie {
            let movies = try await mgr.fetchMovies()
            let movie = try VideoMatch.exactOrContains(
                movies,
                query: title,
                title: { $0.title },
                candidateDescription: { movie in
                    movie.year.map { "\(movie.title) (\($0))" } ?? movie.title
                }
            )
            return .video(.embyMovie(movie))
        }

        guard let episodeTitle = opts.episode else {
            throw CLISourceError.missingRequiredArg("--movie/--episode", "--movie <title> or --episode <title>")
        }
        guard let showName = opts.show else {
            throw CLISourceError.missingRequiredArg("--episode", "--show <name>")
        }
        let shows = try await mgr.fetchShows()
        let show = try VideoMatch.exactOrContains(
            shows,
            query: showName,
            title: { $0.title },
            candidateDescription: { $0.title }
        )
        var seasons = try await mgr.fetchSeasons(forShow: show)
        if let seasonNumber = opts.season {
            seasons = seasons.filter { $0.index == seasonNumber }
        }
        var episodes: [EmbyEpisode] = []
        for season in seasons {
            episodes.append(contentsOf: try await mgr.fetchEpisodes(forSeason: season))
        }
        if let episodeNumber = opts.number {
            episodes = episodes.filter { $0.index == episodeNumber }
        }
        let episode = try VideoMatch.exactOrContains(
            episodes,
            query: episodeTitle,
            title: { $0.title },
            candidateDescription: { "\($0.episodeIdentifier) \($0.title)" }
        )
        return .video(.embyEpisode(episode))
    }

    private static func fetchAllPlexMovies() async throws -> [PlexMovie] {
        var offset = 0
        let limit = 500
        var all: [PlexMovie] = []
        while true {
            let page = try await PlexManager.shared.fetchMovies(offset: offset, limit: limit)
            all.append(contentsOf: page)
            if page.count < limit { break }
            offset += limit
        }
        return all
    }

    private static func fetchAllPlexShows() async throws -> [PlexShow] {
        var offset = 0
        let limit = 500
        var all: [PlexShow] = []
        while true {
            let page = try await PlexManager.shared.fetchShowsPage(offset: offset, limit: limit)
            all.append(contentsOf: page.shows)
            offset += page.rawCount
            if page.rawCount == 0 { break }
            if let totalSize = page.totalSize, offset >= totalSize { break }
            if page.rawCount < limit { break }
        }
        return all
    }

    private static func applyVideoLibrary(source: String, name: String, wantsShows: Bool) async throws {
        switch source {
        case "plex":
            await PlexManager.shared.serverRefreshTask?.value
            let libs = PlexManager.shared.availableLibraries.filter { wantsShows ? $0.isShowLibrary : $0.isMovieLibrary }
            guard let lib = libs.first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("— video library '\(name)' not found on Plex. Available: \(libs.map { $0.title }.joined(separator: ", "))")
            }
            PlexManager.shared.selectLibrary(lib)
        case "jellyfin":
            let expectedType = wantsShows ? "tvshows" : "movies"
            let libs = JellyfinManager.shared.musicLibraries.filter { $0.collectionType?.lowercased() == expectedType }
            guard let lib = libs.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("— video library '\(name)' not found on Jellyfin. Available: \(libs.map { $0.name }.joined(separator: ", "))")
            }
            wantsShows ? JellyfinManager.shared.selectShowLibrary(lib) : JellyfinManager.shared.selectMovieLibrary(lib)
        case "emby":
            let expectedType = wantsShows ? "tvshows" : "movies"
            let libs = EmbyManager.shared.musicLibraries.filter { $0.collectionType?.lowercased() == expectedType }
            guard let lib = libs.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("— video library '\(name)' not found on Emby. Available: \(libs.map { $0.name }.joined(separator: ", "))")
            }
            wantsShows ? EmbyManager.shared.selectShowLibrary(lib) : EmbyManager.shared.selectMovieLibrary(lib)
        default:
            throw CLISourceError.unsupportedVideoSource(source)
        }
    }

    private static func ensureVideoLibrarySelected(source: String, wantsShows: Bool) throws {
        switch source {
        case "plex":
            if wantsShows, PlexManager.shared.currentLibrary?.isShowLibrary == true { return }
            if !wantsShows, PlexManager.shared.currentLibrary?.isMovieLibrary == true { return }
            let libs = PlexManager.shared.availableLibraries.filter { wantsShows ? $0.isShowLibrary : $0.isMovieLibrary }
            guard let first = libs.first else {
                throw CLISourceError.noTracksFound("— no \(wantsShows ? "TV" : "movie") library found on Plex")
            }
            if libs.count > 1 {
                throw CLISourceError.noTracksFound(
                    "— Plex has multiple \(wantsShows ? "TV" : "movie") libraries; specify one with --library <name>. "
                    + "Available: \(libs.map { $0.title }.joined(separator: ", "))")
            }
            PlexManager.shared.selectLibrary(first)
        case "jellyfin":
            let expectedType = wantsShows ? "tvshows" : "movies"
            let currentType = wantsShows
                ? JellyfinManager.shared.currentShowLibrary?.collectionType?.lowercased()
                : JellyfinManager.shared.currentMovieLibrary?.collectionType?.lowercased()
            if currentType == expectedType { return }
            let libs = JellyfinManager.shared.musicLibraries.filter { $0.collectionType?.lowercased() == expectedType }
            guard let first = libs.first else {
                throw CLISourceError.noTracksFound("— no \(wantsShows ? "TV" : "movie") library found on Jellyfin")
            }
            if libs.count > 1 {
                throw CLISourceError.noTracksFound(
                    "— Jellyfin has multiple \(wantsShows ? "TV" : "movie") libraries; specify one with --library <name>. "
                    + "Available: \(libs.map { $0.name }.joined(separator: ", "))")
            }
            wantsShows ? JellyfinManager.shared.selectShowLibrary(first) : JellyfinManager.shared.selectMovieLibrary(first)
        case "emby":
            let expectedType = wantsShows ? "tvshows" : "movies"
            let currentType = wantsShows
                ? EmbyManager.shared.currentShowLibrary?.collectionType?.lowercased()
                : EmbyManager.shared.currentMovieLibrary?.collectionType?.lowercased()
            if currentType == expectedType { return }
            let libs = EmbyManager.shared.musicLibraries.filter { $0.collectionType?.lowercased() == expectedType }
            guard let first = libs.first else {
                throw CLISourceError.noTracksFound("— no \(wantsShows ? "TV" : "movie") library found on Emby")
            }
            if libs.count > 1 {
                throw CLISourceError.noTracksFound(
                    "— Emby has multiple \(wantsShows ? "TV" : "movie") libraries; specify one with --library <name>. "
                    + "Available: \(libs.map { $0.name }.joined(separator: ", "))")
            }
            wantsShows ? EmbyManager.shared.selectShowLibrary(first) : EmbyManager.shared.selectMovieLibrary(first)
        default:
            throw CLISourceError.unsupportedVideoSource(source)
        }
    }

    // MARK: - Radio Resolution

    private static func resolveRadio(source: String, mode: String, opts: CLIOptions) async throws -> [Track] {
        switch source {
        case "plex":
            return try await resolvePlexRadio(mode: mode, opts: opts)
        case "subsonic":
            return try await resolveSubsonicRadio(mode: mode, opts: opts)
        case "jellyfin":
            return try await resolveJellyfinRadio(mode: mode, opts: opts)
        case "emby":
            return try await resolveEmbyRadio(mode: mode, opts: opts)
        default:
            throw CLISourceError.invalidRadioMode(mode, source, [])
        }
    }

    private static func resolvePlexRadio(mode: String, opts: CLIOptions) async throws -> [Track] {
        let mgr = PlexManager.shared
        switch mode {
        case "library":
            return await mgr.createLibraryRadio()
        case "genre":
            guard let genre = opts.genre else {
                throw CLISourceError.missingRequiredArg("--radio genre", "--genre <name>")
            }
            return await mgr.createGenreRadio(genre: genre)
        case "decade":
            guard let decade = opts.decade else {
                throw CLISourceError.missingRequiredArg("--radio decade", "--decade <year>")
            }
            return await mgr.createDecadeRadio(startYear: decade, endYear: decade + 9)
        case "hits":
            return await mgr.createHitsRadio()
        case "deep-cuts":
            return await mgr.createDeepCutsRadio()
        case "rating":
            return await mgr.createRatingRadio(minRating: 4.0)
        case "artist":
            guard let artistName = opts.artist else {
                throw CLISourceError.missingRequiredArg("--radio artist", "--artist <name>")
            }
            let artists = try await mgr.fetchArtists()
            guard let artist = artists.first(where: { $0.title.caseInsensitiveCompare(artistName) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("for artist '\(artistName)' on Plex")
            }
            return await mgr.createArtistRadio(from: artist)
        case "album":
            guard let artistName = opts.artist, let albumName = opts.album else {
                throw CLISourceError.missingRequiredArg("--radio album", "--artist <name> --album <name>")
            }
            let artists = try await mgr.fetchArtists()
            guard let artist = artists.first(where: { $0.title.caseInsensitiveCompare(artistName) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("for artist '\(artistName)' on Plex")
            }
            let albums = try await mgr.fetchAlbums(forArtist: artist)
            guard let album = albums.first(where: { $0.title.caseInsensitiveCompare(albumName) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("for album '\(albumName)' on Plex")
            }
            return await mgr.createAlbumRadio(from: album)
        case "track":
            guard let trackName = opts.track ?? opts.search else {
                throw CLISourceError.missingRequiredArg("--radio track", "--track <name>")
            }
            let results = try await mgr.search(query: trackName)
            guard let plexTrack = results.tracks.first else {
                throw CLISourceError.noTracksFound("for track '\(trackName)' on Plex")
            }
            return await mgr.createTrackRadio(from: plexTrack)
        default:
            throw CLISourceError.invalidRadioMode(mode, "plex",
                ["library", "genre", "decade", "hits", "deep-cuts", "rating", "artist", "album", "track"])
        }
    }

    private static func resolveSubsonicRadio(mode: String, opts: CLIOptions) async throws -> [Track] {
        let mgr = SubsonicManager.shared
        switch mode {
        case "library":
            return await mgr.createLibraryRadio()
        case "genre":
            guard let genre = opts.genre else {
                throw CLISourceError.missingRequiredArg("--radio genre", "--genre <name>")
            }
            return await mgr.createGenreRadio(genre: genre)
        case "decade":
            guard let decade = opts.decade else {
                throw CLISourceError.missingRequiredArg("--radio decade", "--decade <year>")
            }
            return await mgr.createDecadeRadio(start: decade, end: decade + 9)
        case "rating":
            return await mgr.createRatingRadio()
        case "artist":
            guard let artistName = opts.artist else {
                throw CLISourceError.missingRequiredArg("--radio artist", "--artist <name>")
            }
            let artists = try await mgr.fetchArtists()
            guard let artist = artists.first(where: { $0.name.caseInsensitiveCompare(artistName) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("for artist '\(artistName)' on Subsonic")
            }
            return await mgr.createArtistRadio(artistId: artist.id)
        case "album":
            guard let artistName = opts.artist, let albumName = opts.album else {
                throw CLISourceError.missingRequiredArg("--radio album", "--artist <name> --album <name>")
            }
            let artists = try await mgr.fetchArtists()
            guard let artist = artists.first(where: { $0.name.caseInsensitiveCompare(artistName) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("for artist '\(artistName)' on Subsonic")
            }
            let albums = try await mgr.fetchAlbums(forArtist: artist)
            guard let album = albums.first(where: { $0.name.caseInsensitiveCompare(albumName) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("for album '\(albumName)' on Subsonic")
            }
            return await mgr.createAlbumRadio(albumId: album.id)
        case "track":
            guard let trackName = opts.track ?? opts.search else {
                throw CLISourceError.missingRequiredArg("--radio track", "--track <name>")
            }
            let results = try await mgr.search(query: trackName)
            guard let song = results.songs.first else {
                throw CLISourceError.noTracksFound("for track '\(trackName)' on Subsonic")
            }
            guard let track = mgr.convertToTrack(song) else {
                throw CLISourceError.noTracksFound("for track '\(trackName)' on Subsonic")
            }
            return await mgr.createTrackRadio(from: track)
        default:
            throw CLISourceError.invalidRadioMode(mode, "subsonic",
                ["library", "genre", "decade", "rating", "artist", "album", "track"])
        }
    }

    private static func resolveJellyfinRadio(mode: String, opts: CLIOptions) async throws -> [Track] {
        let mgr = JellyfinManager.shared
        switch mode {
        case "library":
            return await mgr.createLibraryRadio()
        case "genre":
            guard let genre = opts.genre else {
                throw CLISourceError.missingRequiredArg("--radio genre", "--genre <name>")
            }
            return await mgr.createGenreRadio(genre: genre)
        case "decade":
            guard let decade = opts.decade else {
                throw CLISourceError.missingRequiredArg("--radio decade", "--decade <year>")
            }
            return await mgr.createDecadeRadio(start: decade, end: decade + 9)
        case "favorites":
            return await mgr.createFavoritesRadio()
        case "artist":
            guard let artistName = opts.artist else {
                throw CLISourceError.missingRequiredArg("--radio artist", "--artist <name>")
            }
            let artists = try await mgr.fetchArtists()
            guard let artist = artists.first(where: { $0.name.caseInsensitiveCompare(artistName) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("for artist '\(artistName)' on Jellyfin")
            }
            return await mgr.createArtistRadio(artistId: artist.id)
        case "album":
            guard let artistName = opts.artist, let albumName = opts.album else {
                throw CLISourceError.missingRequiredArg("--radio album", "--artist <name> --album <name>")
            }
            let artists = try await mgr.fetchArtists()
            guard let artist = artists.first(where: { $0.name.caseInsensitiveCompare(artistName) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("for artist '\(artistName)' on Jellyfin")
            }
            let albums = try await mgr.fetchAlbums(forArtist: artist)
            guard let album = albums.first(where: { $0.name.caseInsensitiveCompare(albumName) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("for album '\(albumName)' on Jellyfin")
            }
            return await mgr.createAlbumRadio(albumId: album.id)
        case "track":
            guard let trackName = opts.track ?? opts.search else {
                throw CLISourceError.missingRequiredArg("--radio track", "--track <name>")
            }
            let results = try await mgr.search(query: trackName, parentId: mgr.currentMusicLibrary?.id)
            guard let song = results.songs.first else {
                throw CLISourceError.noTracksFound("for track '\(trackName)' on Jellyfin")
            }
            guard let track = mgr.convertToTrack(song) else {
                throw CLISourceError.noTracksFound("for track '\(trackName)' on Jellyfin")
            }
            return await mgr.createTrackRadio(from: track)
        default:
            throw CLISourceError.invalidRadioMode(mode, "jellyfin",
                ["library", "genre", "decade", "favorites", "artist", "album", "track"])
        }
    }

    private static func resolveEmbyRadio(mode: String, opts: CLIOptions) async throws -> [Track] {
        let mgr = EmbyManager.shared
        switch mode {
        case "library":
            return await mgr.createLibraryRadio()
        case "genre":
            guard let genre = opts.genre else {
                throw CLISourceError.missingRequiredArg("--radio genre", "--genre <name>")
            }
            return await mgr.createGenreRadio(genre: genre)
        case "decade":
            guard let decade = opts.decade else {
                throw CLISourceError.missingRequiredArg("--radio decade", "--decade <year>")
            }
            return await mgr.createDecadeRadio(start: decade, end: decade + 9)
        case "favorites":
            return await mgr.createFavoritesRadio()
        case "artist":
            guard let artistName = opts.artist else {
                throw CLISourceError.missingRequiredArg("--radio artist", "--artist <name>")
            }
            let artists = try await mgr.fetchArtists()
            guard let artist = artists.first(where: { $0.name.caseInsensitiveCompare(artistName) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("for artist '\(artistName)' on Emby")
            }
            return await mgr.createArtistRadio(artistId: artist.id)
        case "album":
            guard let artistName = opts.artist, let albumName = opts.album else {
                throw CLISourceError.missingRequiredArg("--radio album", "--artist <name> --album <name>")
            }
            let artists = try await mgr.fetchArtists()
            guard let artist = artists.first(where: { $0.name.caseInsensitiveCompare(artistName) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("for artist '\(artistName)' on Emby")
            }
            let albums = try await mgr.fetchAlbums(forArtist: artist)
            guard let album = albums.first(where: { $0.name.caseInsensitiveCompare(albumName) == .orderedSame }) else {
                throw CLISourceError.noTracksFound("for album '\(albumName)' on Emby")
            }
            return await mgr.createAlbumRadio(albumId: album.id)
        case "track":
            guard let trackName = opts.track ?? opts.search else {
                throw CLISourceError.missingRequiredArg("--radio track", "--track <name>")
            }
            let results = try await mgr.search(query: trackName, parentId: mgr.currentMusicLibrary?.id)
            guard let song = results.songs.first else {
                throw CLISourceError.noTracksFound("for track '\(trackName)' on Emby")
            }
            guard let track = mgr.convertToTrack(song) else {
                throw CLISourceError.noTracksFound("for track '\(trackName)' on Emby")
            }
            return await mgr.createTrackRadio(from: track)
        default:
            throw CLISourceError.invalidRadioMode(mode, "emby",
                ["library", "genre", "decade", "favorites", "artist", "album", "track"])
        }
    }
}
