import Foundation
import NullPlayerCore

/// A library browser row that plays as a list of tracks, from any source. `tracks()` is the one
/// place a row is resolved to what the play verbs (`TrackVerb`) queue, for both browsers' menus,
/// Enter shortcuts and double-click (a movie or episode row's double-click plays it straight in the
/// video player instead).
enum LibraryPlayable {
    /// Tracks already in hand (a local playlist's entry).
    case tracks([Track])
    case localTrack(LibraryTrack)
    case localAlbum(Album)
    case localArtist(Artist)
    case localFolder(URL)
    case localPlaylist(URL)
    case plexTrack(PlexTrack)
    case plexAlbum(PlexAlbum)
    /// The same-named Plex artists shown as one row, with their albums when already loaded
    /// (empty: fetched with `plexAlbums(ofArtistGroup:)`).
    case plexArtistGroup(members: [PlexArtist], albums: [PlexAlbum])
    case plexPlaylist(PlexPlaylist)
    case subsonicSong(SubsonicSong)
    case subsonicAlbum(SubsonicAlbum)
    case subsonicArtist(SubsonicArtist)
    case subsonicPlaylist(SubsonicPlaylist)
    case jellyfinSong(JellyfinSong)
    case jellyfinAlbum(JellyfinAlbum)
    case jellyfinArtist(JellyfinArtist)
    case jellyfinPlaylist(JellyfinPlaylist)
    case embySong(EmbySong)
    case embyAlbum(EmbyAlbum)
    case embyArtist(EmbyArtist)
    case embyPlaylist(EmbyPlaylist)
    // Video rows queue as `.video` tracks, which `loadTrack` routes to the video player.
    case localMovie(LocalVideo)
    /// A local episode, season or show: its episodes, in order.
    case localEpisodes([LocalEpisode])
    case plexMovie(PlexMovie)
    case plexEpisode(PlexEpisode)
    case plexSeason(PlexSeason)
    case plexShow(PlexShow)
    case jellyfinMovie(JellyfinMovie)
    case jellyfinEpisode(JellyfinEpisode)
    case jellyfinSeason(JellyfinSeason)
    case jellyfinShow(JellyfinShow)
    case embyMovie(EmbyMovie)
    case embyEpisode(EmbyEpisode)
    case embySeason(EmbySeason)
    case embyShow(EmbyShow)

    /// The level **Assign EQ Profile** keys this row's tracks at; nil for video, which has no local graph.
    var eqProfileLevel: EQProfileLevel? {
        switch self {
        case .localAlbum, .plexAlbum, .subsonicAlbum, .jellyfinAlbum, .embyAlbum: return .album
        case .localArtist, .plexArtistGroup, .subsonicArtist, .jellyfinArtist, .embyArtist: return .artist
        case .tracks, .localTrack, .localFolder, .localPlaylist, .plexTrack, .plexPlaylist,
             .subsonicSong, .subsonicPlaylist, .jellyfinSong, .jellyfinPlaylist, .embySong, .embyPlaylist:
            return .track
        case .localMovie, .localEpisodes, .plexMovie, .plexEpisode, .plexSeason, .plexShow,
             .jellyfinMovie, .jellyfinEpisode, .jellyfinSeason, .jellyfinShow,
             .embyMovie, .embyEpisode, .embySeason, .embyShow:
            return nil
        }
    }

    /// An artist plays album by album, oldest first; a show season by season.
    @MainActor
    func tracks() async throws -> [Track] {
        switch self {
        case .tracks(let tracks):
            return tracks
        case .localTrack(let track):
            // A .cue, or an audio file with a sibling .cue, plays as its cue tracks.
            if let cueTracks = AudioEngine.tracksForCueOrSibling(url: track.url), !cueTracks.isEmpty { return cueTracks }
            return [track.toTrack()]
        case .localAlbum(let album):
            return Self.libraryTracks(of: album).map { $0.toTrack() }
        case .localArtist(let artist):
            // A paginated artist row is a stub without albums: read them from the store.
            if artist.albums.isEmpty {
                let store = MediaLibraryStore.shared
                return try await Self.artistTracks(store.albumsForArtist(artist.name), year: \.year) {
                    store.tracksForAlbum($0.id).map { $0.toTrack() }
                }
            }
            return try await Self.artistTracks(artist.albums, year: \.year) { try await LibraryPlayable.localAlbum($0).tracks() }
        case .localFolder(let url):
            return await Task.detached { Self.tracks(inFolder: url) }.value
        case .localPlaylist(let url):
            return await Task.detached { Self.tracks(inPlaylistFile: url) }.value

        case .plexTrack(let track):
            return PlexManager.shared.convertToTrack(track).map { [$0] } ?? []
        case .plexAlbum(let album):
            return PlexManager.shared.convertToTracks(try await PlexManager.shared.fetchTracks(forAlbum: album))
        case .plexArtistGroup(let members, let albums):
            let plex = PlexManager.shared
            let albums = albums.isEmpty ? try await Self.plexAlbums(ofArtistGroup: members) : albums
            var tracks = try await Self.concatenated(Self.oldestFirst(albums, year: \.year)) { try await plex.fetchTracks(forAlbum: $0) }
            // An artist whose tracks belong to no album the server lists.
            if tracks.isEmpty {
                tracks = try await Self.concatenated(members) { try await plex.fetchTracks(forArtist: $0) }
            }
            return plex.convertToTracks(PlexIdentity.unique(tracks))
        case .plexPlaylist(let playlist):
            let tracks = try await PlexManager.shared.fetchPlaylistTracks(
                playlistID: playlist.id, smartContent: playlist.smart ? playlist.content : nil)
            return PlexManager.shared.convertToTracks(tracks)

        case .subsonicSong(let song):
            return SubsonicManager.shared.convertToTrack(song).map { [$0] } ?? []
        case .subsonicAlbum(let album):
            return SubsonicManager.shared.convertToTracks(try await SubsonicManager.shared.fetchSongs(forAlbum: album))
        case .subsonicArtist(let artist):
            return try await Self.artistTracks(try await SubsonicManager.shared.fetchAlbums(forArtist: artist), year: \.year) {
                try await LibraryPlayable.subsonicAlbum($0).tracks()
            }
        case .subsonicPlaylist(let playlist):
            let (_, songs) = try await SubsonicManager.shared.serverClient?.fetchPlaylist(id: playlist.id) ?? (playlist, [])
            return SubsonicManager.shared.convertToTracks(songs)

        case .jellyfinSong(let song):
            return JellyfinManager.shared.convertToTrack(song).map { [$0] } ?? []
        case .jellyfinAlbum(let album):
            return JellyfinManager.shared.convertToTracks(try await JellyfinManager.shared.fetchSongs(forAlbum: album))
        case .jellyfinArtist(let artist):
            return try await Self.artistTracks(try await JellyfinManager.shared.fetchAlbums(forArtist: artist), year: \.year) {
                try await LibraryPlayable.jellyfinAlbum($0).tracks()
            }
        case .jellyfinPlaylist(let playlist):
            let (_, songs) = try await JellyfinManager.shared.serverClient?.fetchPlaylist(id: playlist.id) ?? (playlist, [])
            return JellyfinManager.shared.convertToTracks(songs)

        case .embySong(let song):
            return EmbyManager.shared.convertToTrack(song).map { [$0] } ?? []
        case .embyAlbum(let album):
            return EmbyManager.shared.convertToTracks(try await EmbyManager.shared.fetchSongs(forAlbum: album))
        case .embyArtist(let artist):
            return try await Self.artistTracks(try await EmbyManager.shared.fetchAlbums(forArtist: artist), year: \.year) {
                try await LibraryPlayable.embyAlbum($0).tracks()
            }
        case .embyPlaylist(let playlist):
            let (_, songs) = try await EmbyManager.shared.serverClient?.fetchPlaylist(id: playlist.id) ?? (playlist, [])
            return EmbyManager.shared.convertToTracks(songs)

        case .localMovie(let movie):
            return [movie.toTrack()]
        case .localEpisodes(let episodes):
            return episodes.map { $0.toTrack() }

        case .plexMovie(let movie):
            return PlexManager.shared.convertToTrack(movie).map { [$0] } ?? []
        case .plexEpisode(let episode):
            return PlexManager.shared.convertToTrack(episode).map { [$0] } ?? []
        case .plexSeason(let season):
            return PlexManager.shared.convertToTracks(try await PlexManager.shared.fetchEpisodes(forSeason: season))
        case .plexShow(let show):
            return try await Self.concatenated(try await PlexManager.shared.fetchSeasons(forShow: show)) {
                try await LibraryPlayable.plexSeason($0).tracks()
            }

        case .jellyfinMovie(let movie):
            return JellyfinManager.shared.convertToTrack(movie).map { [$0] } ?? []
        case .jellyfinEpisode(let episode):
            return JellyfinManager.shared.convertToTrack(episode).map { [$0] } ?? []
        case .jellyfinSeason(let season):
            return try await JellyfinManager.shared.fetchEpisodes(forSeason: season).compactMap(JellyfinManager.shared.convertToTrack)
        case .jellyfinShow(let show):
            return try await Self.concatenated(try await JellyfinManager.shared.fetchSeasons(forShow: show)) {
                try await LibraryPlayable.jellyfinSeason($0).tracks()
            }

        case .embyMovie(let movie):
            return EmbyManager.shared.convertToTrack(movie).map { [$0] } ?? []
        case .embyEpisode(let episode):
            return EmbyManager.shared.convertToTrack(episode).map { [$0] } ?? []
        case .embySeason(let season):
            return try await EmbyManager.shared.fetchEpisodes(forSeason: season).compactMap(EmbyManager.shared.convertToTrack)
        case .embyShow(let show):
            return try await Self.concatenated(try await EmbyManager.shared.fetchSeasons(forShow: show)) {
                try await LibraryPlayable.embySeason($0).tracks()
            }
        }
    }

    /// An artist plays album by album, oldest first.
    private static func oldestFirst<A>(_ albums: [A], year: KeyPath<A, Int?>) -> [A] {
        albums.sorted { ($0[keyPath: year] ?? 0) < ($1[keyPath: year] ?? 0) }
    }

    /// An artist's tracks: each album's in turn, oldest first.
    @MainActor
    private static func artistTracks<A>(_ albums: [A], year: KeyPath<A, Int?>,
                                        tracks: (A) async throws -> [Track]) async throws -> [Track] {
        try await concatenated(oldestFirst(albums, year: year), tracks)
    }

    /// Each container's items in turn.
    @MainActor
    private static func concatenated<C, T>(_ containers: [C], _ items: (C) async throws -> [T]) async throws -> [T] {
        var result: [T] = []
        for container in containers { result.append(contentsOf: try await items(container)) }
        return result
    }

    /// Every album of a group of same-named Plex artists, once each.
    @MainActor
    static func plexAlbums(ofArtistGroup members: [PlexArtist]) async throws -> [PlexAlbum] {
        var albums: [PlexAlbum] = []
        for member in members { albums.append(contentsOf: try await PlexManager.shared.fetchAlbums(forArtist: member)) }
        return PlexIdentity.unique(albums)
    }

    /// A local album's tracks, read from the store when the album was built as a stub (no tracks).
    static func libraryTracks(of album: Album) -> [LibraryTrack] {
        album.tracks.isEmpty ? MediaLibraryStore.shared.tracksForAlbum(album.id) : album.tracks
    }

    /// Every supported audio file under a folder, subfolders first, each level by name, with
    /// library metadata where the file is in the library. Blocking: call it off the main actor.
    nonisolated static func tracks(inFolder folderURL: URL) -> [Track] {
        var audioFileURLs: [URL] = []
        var visitedPaths: Set<String> = []

        func walkDirectory(_ url: URL, depth: Int = 0) {
            guard depth < 100 else { return } // Prevent infinite recursion
            let resolvedPath = url.resolvingSymlinksInPath().path
            guard visitedPaths.insert(resolvedPath).inserted,
                  let contents = try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return }
            var subdirectories: [URL] = []
            var audioFiles: [URL] = []
            for item in contents {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    if item.resolvingSymlinksInPath().path == item.path { subdirectories.append(item) }
                } else if LocalFileDiscovery.isSupportedAudioFile(item) {
                    audioFiles.append(item)
                }
            }
            subdirectories.sort { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
            audioFiles.sort { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
            for subdirectory in subdirectories { walkDirectory(subdirectory, depth: depth + 1) }
            audioFileURLs.append(contentsOf: audioFiles)
        }

        walkDirectory(folderURL)
        let libraryTracks = MediaLibraryStore.shared.tracks(forURLs: audioFileURLs)
        // A file not in the library gets a minimal track synthesized from its URL.
        return audioFileURLs.map { (libraryTracks[$0] ?? LibraryTrack(url: $0)).toTrack() }
    }

    /// A playlist file's entries, with library metadata where the entry is in the library.
    /// Blocking: call it off the main actor.
    nonisolated static func tracks(inPlaylistFile url: URL) -> [Track] {
        guard let playlist = Playlist.load(from: url) else { return [] }

        // A relative entry is resolved against the playlist file's own directory, which is right only
        // while the playlist sits beside its music. Nothing used to check that guess, so a playlist
        // that had been moved listed a full set of entries that all looked fine and none of which
        // could play. Reported through the validator so it reaches the marquee in every skin mode.
        let missing = playlist.missingFileEntries
        if !missing.isEmpty {
            AudioFileValidator.notifyInvalidFiles(
                missing.map { (url: $0, reason: "Not found: the playlist entry '\(url.lastPathComponent)' resolves to '\(url.path)'") })
        }

        return playlist.trackURLs.map { trackURL in
            MediaLibrary.shared.findTrack(byURL: trackURL)?.toTrack() ?? Track(lightweightURL: trackURL)
        }
    }
}
