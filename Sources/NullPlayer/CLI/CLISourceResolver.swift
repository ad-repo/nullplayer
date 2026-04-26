import Foundation
import NullPlayerCore

enum CLISourceError: LocalizedError {
    case noSource(String? = nil)
    case sourceNotConfigured(String)
    case noTracksFound(String)
    case invalidRadioMode(String, String, [String])
    case missingRequiredArg(String, String)

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
        }
    }
}

/// Result type to distinguish track-based playback from radio station playback
enum CLIResolveResult {
    case tracks([Track])
    case radioStation  // RadioManager handles playback directly
}

struct CLISourceResolver {

    static func resolve(_ opts: CLIOptions) async throws -> CLIResolveResult {
        let source = opts.source ?? "local"

        // Check connectivity
        try await checkConnectivity(source: source)

        // Apply library selection if specified
        if let libraryName = opts.library {
            try await applyLibrary(source: source, name: libraryName)
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

        // Standard content resolution
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
            fputs("Error: Unknown source '\(source)'. Use: local, plex, subsonic, jellyfin, emby, radio\n", stderr)
            exit(1)
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

    // MARK: - Content Resolution

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
            let results = try await mgr.search(query: query)
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
            let results = try await mgr.search(query: query)
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
            let results = try await mgr.search(query: trackName)
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
            let results = try await mgr.search(query: trackName)
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
