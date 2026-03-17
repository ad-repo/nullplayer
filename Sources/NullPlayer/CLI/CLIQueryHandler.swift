import Foundation

struct CLIQueryHandler {

    static func handle(_ opts: CLIOptions) async throws {
        if opts.listSources {
            try await listSources(json: opts.json)
            return
        }
        if opts.listLibraries {
            let source = opts.source ?? "local"
            try await CLISourceResolver.checkConnectivity(source: source)
            listLibraries(source: source, json: opts.json)
            return
        }
        if opts.listEQ {
            listEQ(json: opts.json)
            return
        }
        if opts.listOutputs {
            listOutputs(json: opts.json)
            return
        }
        if opts.listDevices {
            try await listDevices(castType: opts.castType, json: opts.json)
            return
        }
        if opts.listStations {
            listStations(folder: opts.folder, genre: opts.genre,
                        channel: opts.channel, region: opts.region,
                        search: opts.search, json: opts.json)
            return
        }

        // Search query (--search without playback flags → print results and exit)
        if opts.isSearchQuery {
            let source = opts.source ?? "local"
            try await CLISourceResolver.checkConnectivity(source: source)
            try await searchAndPrint(source: source, query: opts.search!, json: opts.json)
            return
        }

        // Source-dependent queries
        let source = opts.source ?? "local"
        try await CLISourceResolver.checkConnectivity(source: source)
        if let libraryName = opts.library {
            try await CLISourceResolver.applyLibrary(source: source, name: libraryName)
        }

        if opts.listArtists {
            try await listArtists(source: source, json: opts.json)
        } else if opts.listAlbums {
            try await listAlbums(source: source, artist: opts.artist, json: opts.json)
        } else if opts.listTracks {
            try await listTracks(source: source, artist: opts.artist, album: opts.album, json: opts.json)
        } else if opts.listGenres {
            listGenres(json: opts.json)
        } else if opts.listPlaylists {
            try await listPlaylists(source: source, json: opts.json)
        }
    }

    // MARK: - Source-Independent Queries

    private static func listSources(json: Bool) async throws {
        struct SourceStatus: Encodable {
            let name: String
            let connected: Bool
            let detail: String
        }

        var sources: [SourceStatus] = []

        sources.append(SourceStatus(name: "local", connected: true, detail: "Local Library"))
        sources.append(SourceStatus(name: "plex", connected: PlexManager.shared.isLinked, detail: "Plex"))
        if case .connected = SubsonicManager.shared.connectionState {
            sources.append(SourceStatus(name: "subsonic", connected: true, detail: "Subsonic/Navidrome"))
        } else {
            sources.append(SourceStatus(name: "subsonic", connected: false, detail: "Subsonic/Navidrome"))
        }
        if case .connected = JellyfinManager.shared.connectionState {
            sources.append(SourceStatus(name: "jellyfin", connected: true, detail: "Jellyfin"))
        } else {
            sources.append(SourceStatus(name: "jellyfin", connected: false, detail: "Jellyfin"))
        }
        if case .connected = EmbyManager.shared.connectionState {
            sources.append(SourceStatus(name: "emby", connected: true, detail: "Emby"))
        } else {
            sources.append(SourceStatus(name: "emby", connected: false, detail: "Emby"))
        }
        sources.append(SourceStatus(name: "radio", connected: true, detail: "Internet Radio"))

        if json {
            CLIDisplay.printJSON(sources)
        } else {
            CLIDisplay.printTable(
                headers: ["Source", "Status", "Detail"],
                rows: sources.map { [$0.name, $0.connected ? "Connected" : "Not configured", $0.detail] }
            )
        }
    }

    private static func listLibraries(source: String, json: Bool) {
        switch source {
        case "plex":
            let libs = PlexManager.shared.availableLibraries
            let current = PlexManager.shared.currentLibrary?.id
            if json {
                CLIDisplay.printJSON(libs.map { ["name": $0.title, "current": $0.id == current ? "true" : "false"] })
            } else {
                CLIDisplay.printTable(
                    headers: ["Library", "Current"],
                    rows: libs.map { [$0.title, $0.id == current ? "*" : ""] }
                )
            }
        case "subsonic":
            let folders = SubsonicManager.shared.musicFolders
            let currentId = SubsonicManager.shared.currentMusicFolder?.id
            if json {
                CLIDisplay.printJSON(folders.map { ["name": $0.name, "current": $0.id == currentId ? "true" : "false"] })
            } else {
                CLIDisplay.printTable(
                    headers: ["Folder", "Current"],
                    rows: folders.map { [$0.name, $0.id == currentId ? "*" : ""] }
                )
            }
        case "jellyfin":
            let libs = JellyfinManager.shared.musicLibraries
            let currentId = JellyfinManager.shared.currentMusicLibrary?.id
            if json {
                CLIDisplay.printJSON(libs.map { ["name": $0.name, "current": $0.id == currentId ? "true" : "false"] })
            } else {
                CLIDisplay.printTable(
                    headers: ["Library", "Current"],
                    rows: libs.map { [$0.name, $0.id == currentId ? "*" : ""] }
                )
            }
        case "emby":
            let libs = EmbyManager.shared.musicLibraries
            let currentId = EmbyManager.shared.currentMusicLibrary?.id
            if json {
                CLIDisplay.printJSON(libs.map { ["name": $0.name, "current": $0.id == currentId ? "true" : "false"] })
            } else {
                CLIDisplay.printTable(
                    headers: ["Library", "Current"],
                    rows: libs.map { [$0.name, $0.id == currentId ? "*" : ""] }
                )
            }
        default:
            fputs("Error: --list-libraries not supported for source '\(source)'\n", stderr)
        }
    }

    private static func listEQ(json: Bool) {
        let names = EQPreset.allPresets.map { $0.name }
        if json {
            CLIDisplay.printJSON(names)
        } else {
            print("Available EQ Presets:")
            for name in names {
                print("  \(name)")
            }
        }
    }

    private static func listOutputs(json: Bool) {
        let devices = AudioOutputManager.shared.outputDevices
        if json {
            CLIDisplay.printJSON(devices.map { ["name": $0.name] })
        } else {
            CLIDisplay.printTable(
                headers: ["Name"],
                rows: devices.map { [$0.name] }
            )
        }
    }

    private static func listDevices(castType: String?, json: Bool) async throws {
        CastManager.shared.startDiscovery()

        // Wait for discovery (5s)
        try await Task.sleep(nanoseconds: 5_000_000_000)

        var devices = CastManager.shared.discoveredDevices
        if let typeStr = castType {
            switch typeStr.lowercased() {
            case "sonos": devices = devices.filter { $0.type == .sonos }
            case "chromecast": devices = devices.filter { $0.type == .chromecast }
            case "dlna": devices = devices.filter { $0.type == .dlnaTV }
            default: break
            }
        }

        if json {
            CLIDisplay.printJSON(devices.map { ["name": $0.name, "type": "\($0.type)"] })
        } else {
            CLIDisplay.printTable(
                headers: ["Name", "Type"],
                rows: devices.map { [$0.name, "\($0.type)"] }
            )
        }
    }

    private static func listStations(folder: String?, genre: String?,
                                      channel: String?, region: String?,
                                      search: String?, json: Bool) {
        var stations: [RadioStation]

        if let query = search {
            stations = RadioManager.shared.searchStations(query: query)
        } else {
            let folderKind = mapFolderKind(folder: folder, genre: genre, channel: channel, region: region)
            stations = RadioManager.shared.stations(inFolder: folderKind)
        }

        if json {
            CLIDisplay.printJSON(stations.map { ["name": $0.name, "url": $0.url.absoluteString] })
        } else {
            CLIDisplay.printTable(
                headers: ["Station", "URL"],
                rows: stations.map { [$0.name, $0.url.absoluteString] }
            )
        }
    }

    private static func mapFolderKind(folder: String?, genre: String?, channel: String?, region: String?) -> RadioFolderKind {
        guard let folder else { return .allStations }
        switch folder {
        case "all": return .allStations
        case "favorites": return .favorites
        case "top-rated": return .topRated
        case "unrated": return .unrated
        case "recent": return .recentlyPlayed
        case "channels": return .byChannel
        case "genres": return .byGenre
        case "regions": return .byRegion
        case "genre":
            if let name = genre { return .genre(name) }
            return .byGenre
        case "channel":
            if let name = channel { return .channel(name) }
            return .byChannel
        case "region":
            if let name = region { return .region(name) }
            return .byRegion
        default:
            return .allStations
        }
    }

    // MARK: - Source-Dependent Queries

    private static func listArtists(source: String, json: Bool) async throws {
        switch source {
        case "local":
            let artists = MediaLibrary.shared.allArtists()
            let names = artists.map { $0.name }
            if json {
                CLIDisplay.printJSON(names)
            } else {
                for name in names { print(name) }
                print("\n\(names.count) artist(s)")
            }
        case "plex":
            let artists = try await PlexManager.shared.fetchArtists()
            let names = artists.map { $0.title }  // PlexArtist uses .title
            if json { CLIDisplay.printJSON(names) }
            else {
                for name in names { print(name) }
                print("\n\(names.count) artist(s)")
            }
        case "subsonic":
            let artists = try await SubsonicManager.shared.fetchArtists()
            let names = artists.map { $0.name }
            if json { CLIDisplay.printJSON(names) }
            else {
                for name in names { print(name) }
                print("\n\(names.count) artist(s)")
            }
        case "jellyfin":
            let artists = try await JellyfinManager.shared.fetchArtists()
            let names = artists.map { $0.name }
            if json { CLIDisplay.printJSON(names) }
            else {
                for name in names { print(name) }
                print("\n\(names.count) artist(s)")
            }
        case "emby":
            let artists = try await EmbyManager.shared.fetchArtists()
            let names = artists.map { $0.name }
            if json { CLIDisplay.printJSON(names) }
            else {
                for name in names { print(name) }
                print("\n\(names.count) artist(s)")
            }
        default:
            fputs("Error: --list-artists not supported for source '\(source)'\n", stderr)
        }
    }

    private static func listAlbums(source: String, artist: String?, json: Bool) async throws {
        switch source {
        case "local":
            var filter = LibraryFilter()
            if let artistName = artist { filter.artists = [artistName] }
            let tracks = MediaLibrary.shared.filteredTracks(filter: filter, sortBy: .album)
            let albums = Array(Set(tracks.compactMap { $0.album })).sorted()
            if json { CLIDisplay.printJSON(albums) }
            else {
                for album in albums { print(album) }
                print("\n\(albums.count) album(s)")
            }
        case "plex":
            guard let artistName = artist else {
                fputs("Error: --list-albums for plex requires --artist <name>\n", stderr)
                return
            }
            let artists = try await PlexManager.shared.fetchArtists()
            guard let plexArtist = artists.first(where: { $0.title.caseInsensitiveCompare(artistName) == .orderedSame }) else {
                fputs("Error: Artist '\(artistName)' not found on Plex\n", stderr)
                return
            }
            let albums = try await PlexManager.shared.fetchAlbums(forArtist: plexArtist)
            let names = albums.map { $0.title }  // PlexAlbum uses .title
            if json { CLIDisplay.printJSON(names) }
            else {
                for name in names { print(name) }
                print("\n\(names.count) album(s)")
            }
        case "subsonic":
            guard let artistName = artist else {
                fputs("Error: --list-albums for subsonic requires --artist <name>\n", stderr)
                return
            }
            let artists = try await SubsonicManager.shared.fetchArtists()
            guard let a = artists.first(where: { $0.name.caseInsensitiveCompare(artistName) == .orderedSame }) else {
                fputs("Error: Artist '\(artistName)' not found on Subsonic\n", stderr)
                return
            }
            let albums = try await SubsonicManager.shared.fetchAlbums(forArtist: a)
            let names = albums.map { $0.name }  // SubsonicAlbum uses .name
            if json { CLIDisplay.printJSON(names) }
            else {
                for name in names { print(name) }
                print("\n\(names.count) album(s)")
            }
        case "jellyfin":
            guard let artistName = artist else {
                fputs("Error: --list-albums for jellyfin requires --artist <name>\n", stderr)
                return
            }
            let artists = try await JellyfinManager.shared.fetchArtists()
            guard let a = artists.first(where: { $0.name.caseInsensitiveCompare(artistName) == .orderedSame }) else {
                fputs("Error: Artist '\(artistName)' not found on Jellyfin\n", stderr)
                return
            }
            let albums = try await JellyfinManager.shared.fetchAlbums(forArtist: a)
            let names = albums.map { $0.name }  // JellyfinAlbum uses .name
            if json { CLIDisplay.printJSON(names) }
            else {
                for name in names { print(name) }
                print("\n\(names.count) album(s)")
            }
        case "emby":
            guard let artistName = artist else {
                fputs("Error: --list-albums for emby requires --artist <name>\n", stderr)
                return
            }
            let artists = try await EmbyManager.shared.fetchArtists()
            guard let a = artists.first(where: { $0.name.caseInsensitiveCompare(artistName) == .orderedSame }) else {
                fputs("Error: Artist '\(artistName)' not found on Emby\n", stderr)
                return
            }
            let albums = try await EmbyManager.shared.fetchAlbums(forArtist: a)
            let names = albums.map { $0.name }  // EmbyAlbum uses .name
            if json { CLIDisplay.printJSON(names) }
            else {
                for name in names { print(name) }
                print("\n\(names.count) album(s)")
            }
        default:
            fputs("Error: --list-albums not supported for source '\(source)'\n", stderr)
        }
    }

    private static func listTracks(source: String, artist: String?, album: String?, json: Bool) async throws {
        switch source {
        case "local":
            var filter = LibraryFilter()
            if let a = artist { filter.artists = [a] }
            if let a = album { filter.albums = [a] }
            let tracks = MediaLibrary.shared.filteredTracks(filter: filter, sortBy: .title)
            let names = tracks.map { "\($0.artist ?? "Unknown") - \($0.title)" }
            if json { CLIDisplay.printJSON(names) }
            else {
                for name in names { print(name) }
                print("\n\(names.count) track(s)")
            }
        case "plex":
            guard let artistName = artist else {
                fputs("Error: --list-tracks for plex requires --artist <name>\n", stderr)
                return
            }
            let mgr = PlexManager.shared
            let artists = try await mgr.fetchArtists()
            guard let a = artists.first(where: { $0.title.caseInsensitiveCompare(artistName) == .orderedSame }) else {
                fputs("Error: Artist '\(artistName)' not found on Plex\n", stderr)
                return
            }
            let albums = try await mgr.fetchAlbums(forArtist: a)
            let targetAlbums = album.map { albName in albums.filter { $0.title.caseInsensitiveCompare(albName) == .orderedSame } } ?? albums
            var allTracks: [Track] = []
            for alb in targetAlbums {
                let plexTracks = try await mgr.fetchTracks(forAlbum: alb)
                allTracks.append(contentsOf: mgr.convertToTracks(plexTracks))
            }
            let names = allTracks.map { "\($0.artist ?? "Unknown") - \($0.title ?? "Unknown")" }
            if json { CLIDisplay.printJSON(names) }
            else {
                for name in names { print(name) }
                print("\n\(names.count) track(s)")
            }
        case "subsonic", "jellyfin", "emby":
            guard let artistName = artist else {
                fputs("Error: --list-tracks for \(source) requires --artist <name>\n", stderr)
                return
            }
            var opts = CLIOptions()
            opts.source = source
            opts.artist = artistName
            opts.album = album
            let tracks = try await CLISourceResolver.resolveContent(source: source, opts: opts)
            let names = tracks.map { "\($0.artist ?? "Unknown") - \($0.title ?? "Unknown")" }
            if json { CLIDisplay.printJSON(names) }
            else {
                for name in names { print(name) }
                print("\n\(names.count) track(s)")
            }
        default:
            fputs("Error: --list-tracks not supported for source '\(source)'\n", stderr)
        }
    }

    private static func listGenres(json: Bool) {
        let tracks = MediaLibrary.shared.filteredTracks(filter: LibraryFilter(), sortBy: .title)
        let genres = Array(Set(tracks.compactMap { $0.genre })).sorted()
        if json { CLIDisplay.printJSON(genres) }
        else {
            for genre in genres { print(genre) }
            print("\n\(genres.count) genre(s)")
        }
    }

    private static func searchAndPrint(source: String, query: String, json: Bool) async throws {
        var tracks: [Track] = []
        switch source {
        case "local":
            tracks = MediaLibrary.shared.search(query: query).map { $0.toTrack() }
        case "plex":
            let results = try await PlexManager.shared.search(query: query)
            tracks = PlexManager.shared.convertToTracks(results.tracks)
        case "subsonic":
            let results = try await SubsonicManager.shared.search(query: query)
            tracks = SubsonicManager.shared.convertToTracks(results.songs)
        case "jellyfin":
            let results = try await JellyfinManager.shared.search(query: query)
            tracks = JellyfinManager.shared.convertToTracks(results.songs)
        case "emby":
            let results = try await EmbyManager.shared.search(query: query)
            tracks = EmbyManager.shared.convertToTracks(results.songs)
        case "radio":
            let stations = RadioManager.shared.searchStations(query: query)
            if json {
                CLIDisplay.printJSON(stations.map { ["name": $0.name, "url": $0.url.absoluteString] })
            } else {
                CLIDisplay.printTable(
                    headers: ["Station", "URL"],
                    rows: stations.map { [$0.name, $0.url.absoluteString] }
                )
            }
            return
        default:
            fputs("Error: --search not supported for source '\(source)'\n", stderr)
            return
        }

        let names = tracks.map { "\($0.artist ?? "Unknown") - \($0.title ?? "Unknown")" }
        if json { CLIDisplay.printJSON(names) }
        else {
            for name in names { print(name) }
            print("\n\(names.count) result(s)")
        }
    }

    private static func listPlaylists(source: String, json: Bool) async throws {
        var names: [String] = []

        switch source {
        case "plex":
            let playlists = try await PlexManager.shared.fetchAudioPlaylists()
            names = playlists.map { $0.title }
        case "subsonic":
            let playlists = try await SubsonicManager.shared.fetchPlaylists()
            names = playlists.map { $0.name }
        case "jellyfin":
            let playlists = try await JellyfinManager.shared.fetchPlaylists()
            names = playlists.map { $0.name }
        case "emby":
            let playlists = try await EmbyManager.shared.fetchPlaylists()
            names = playlists.map { $0.name }
        default:
            fputs("Error: --list-playlists not supported for source '\(source)'\n", stderr)
            return
        }

        if json { CLIDisplay.printJSON(names) }
        else {
            for name in names { print(name) }
            print("\n\(names.count) playlist(s)")
        }
    }
}
