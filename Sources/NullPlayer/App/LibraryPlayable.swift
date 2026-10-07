import Foundation
import NullPlayerCore

/// A library browser row that plays as a list of tracks, from any source. `tracks()` is the one
/// place a row is resolved to what the play verbs (`TrackVerb`) queue, for both browsers' menus,
/// Enter shortcuts and double-click.
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
    /// The same-named Plex artists the browser shows as one row, and the albums it has cached for
    /// them (empty when it hasn't fetched them yet).
    case plexArtistGroup(members: [PlexArtist], cachedAlbums: [PlexAlbum])
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

    /// An artist plays album by album, oldest first.
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
                return store.albumsForArtist(artist.name).sorted { ($0.year ?? 0) < ($1.year ?? 0) }
                    .flatMap { store.tracksForAlbum($0.id) }.map { $0.toTrack() }
            }
            return artist.albums.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
                .flatMap { Self.libraryTracks(of: $0) }.map { $0.toTrack() }
        case .localFolder(let url):
            return await Task.detached { Self.tracks(inFolder: url) }.value
        case .localPlaylist(let url):
            return await Task.detached { Self.tracks(inPlaylistFile: url) }.value

        case .plexTrack(let track):
            return PlexManager.shared.convertToTrack(track).map { [$0] } ?? []
        case .plexAlbum(let album):
            return PlexManager.shared.convertToTracks(try await PlexManager.shared.fetchTracks(forAlbum: album))
        case .plexArtistGroup(let members, let cachedAlbums):
            let plex = PlexManager.shared
            var albums = cachedAlbums
            if albums.isEmpty {
                for member in members { albums.append(contentsOf: try await plex.fetchAlbums(forArtist: member)) }
                albums = PlexIdentity.unique(albums)
            }
            var tracks: [PlexTrack] = []
            for album in albums { tracks.append(contentsOf: try await plex.fetchTracks(forAlbum: album)) }
            // An artist whose tracks belong to no album the server lists.
            if tracks.isEmpty {
                for member in members { tracks.append(contentsOf: try await plex.fetchTracks(forArtist: member)) }
            }
            return plex.convertToTracks(PlexIdentity.unique(tracks))
        case .plexPlaylist(let playlist):
            let tracks = try await PlexManager.shared.fetchPlaylistTracks(
                playlistID: playlist.id, smartContent: playlist.smart ? playlist.content : nil)
            return PlexManager.shared.convertToTracks(tracks)

        case .subsonicSong(let song):
            return SubsonicManager.shared.convertToTrack(song).map { [$0] } ?? []
        case .subsonicAlbum(let album):
            return try await SubsonicManager.shared.fetchSongs(forAlbum: album).compactMap { SubsonicManager.shared.convertToTrack($0) }
        case .subsonicArtist(let artist):
            var tracks: [Track] = []
            for album in try await SubsonicManager.shared.fetchAlbums(forArtist: artist).sorted(by: { ($0.year ?? 0) < ($1.year ?? 0) }) {
                tracks.append(contentsOf: try await LibraryPlayable.subsonicAlbum(album).tracks())
            }
            return tracks
        case .subsonicPlaylist(let playlist):
            let (_, songs) = try await SubsonicManager.shared.serverClient?.fetchPlaylist(id: playlist.id) ?? (playlist, [])
            return songs.compactMap { SubsonicManager.shared.convertToTrack($0) }

        case .jellyfinSong(let song):
            return JellyfinManager.shared.convertToTrack(song).map { [$0] } ?? []
        case .jellyfinAlbum(let album):
            return JellyfinManager.shared.convertToTracks(try await JellyfinManager.shared.fetchSongs(forAlbum: album))
        case .jellyfinArtist(let artist):
            var tracks: [Track] = []
            for album in try await JellyfinManager.shared.fetchAlbums(forArtist: artist).sorted(by: { ($0.year ?? 0) < ($1.year ?? 0) }) {
                tracks.append(contentsOf: try await LibraryPlayable.jellyfinAlbum(album).tracks())
            }
            return tracks
        case .jellyfinPlaylist(let playlist):
            let (_, songs) = try await JellyfinManager.shared.serverClient?.fetchPlaylist(id: playlist.id) ?? (playlist, [])
            return JellyfinManager.shared.convertToTracks(songs)

        case .embySong(let song):
            return EmbyManager.shared.convertToTrack(song).map { [$0] } ?? []
        case .embyAlbum(let album):
            return EmbyManager.shared.convertToTracks(try await EmbyManager.shared.fetchSongs(forAlbum: album))
        case .embyArtist(let artist):
            var tracks: [Track] = []
            for album in try await EmbyManager.shared.fetchAlbums(forArtist: artist).sorted(by: { ($0.year ?? 0) < ($1.year ?? 0) }) {
                tracks.append(contentsOf: try await LibraryPlayable.embyAlbum(album).tracks())
            }
            return tracks
        case .embyPlaylist(let playlist):
            let (_, songs) = try await EmbyManager.shared.serverClient?.fetchPlaylist(id: playlist.id) ?? (playlist, [])
            return EmbyManager.shared.convertToTracks(songs)
        }
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
