import Foundation

/// **The library a `.wmz` script reads: whatever source the library browser has selected**
/// (W136). A skin's library is contextual the same way the browser's is.
///
/// Local Files is small enough to hold whole, so it is built once and every query is a filter. A
/// server is not: its catalog starts as what the server's manager already has cached — playlist
/// names, artist, album and genre lists — and the tracks behind a playlist or an album/artist/genre
/// query are fetched the first time a skin asks for them (`fetch(_:)`), the "answer from what is
/// loaded, then refresh" rule. Every fetched track is appended, so a catalog index stays valid for
/// the life of the source.
@MainActor
final class WMPLibrarySource {
    private(set) var catalog = WMPLibraryCatalog.empty
    /// What playback opens, by catalog index. The catalog carries WMP's spelling of each file for
    /// the skin to read; this is the track the rest of the player knows.
    private(set) var playables: [Track] = []
    /// `playables` by location. A server playlist can be the whole library — Plex's "All Music"
    /// — and finding each fetched track by scanning `playables` was quadratic, on the main actor:
    /// it beachballed the app.
    private var indexByURL: [URL: Int] = [:]
    private var source: ModernBrowserSource = .local
    private var provider: WMPLibraryProvider?
    /// Fetches under way, by demand. A second request for the same playlist — a fast second
    /// click — waits for the first fetch rather than being turned away as a duplicate, which lost
    /// the play that was waiting on it.
    private var inFlight: [String: Task<Bool, Never>] = [:]

    /// Rebuild for the browser's current source. Returns true when the playlist list the skin
    /// fills its chooser from changed — the caller loads those views again.
    func rebuild() async -> Bool {
        let selected = ModernBrowserSource.load() ?? .local
        let previousNames = catalog.playlists.map(\.name)
        let previousSource = catalog.sourceID
        source = selected
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        switch selected {
        case .local:
            provider = nil
            let built = await Task.detached { Self.buildLocal() }.value
            catalog = built.catalog
            catalog.indexPlaylists()
            playables = built.playables
            indexByURL = [:]
        default:
            provider = WMPLibraryProvider.make(for: selected)
            var fresh = WMPLibraryCatalog()
            fresh.sourceID = Self.sourceID(selected)
            fresh.isComplete = false
            let keptPlayables = playables
            playables = []
            if let provider {
                let lists = await provider.playlists()
                fresh.playlists = lists.map { .init(id: $0.id, name: $0.name, tracks: [], loaded: false) }
                fresh.strings = await provider.strings()
            }
            // Keep what this same server already fetched: a manager refresh re-lists the names,
            // it does not unload the tracks a skin is showing.
            if fresh.sourceID == previousSource {
                playables = keptPlayables
                fresh.tracks = catalog.tracks
                fresh.libraryTracks = catalog.libraryTracks
                // An empty answer may be a fetch that failed before the server was up, so only a
                // non-empty one is kept; the rest are asked again.
                fresh.queryResults = catalog.queryResults.filter { !$0.value.isEmpty }
                for (index, playlist) in fresh.playlists.enumerated() {
                    if let old = catalog.playlistIndex(id: playlist.id),
                       catalog.playlists[old].loaded, !catalog.playlists[old].tracks.isEmpty {
                        fresh.playlists[index].tracks = catalog.playlists[old].tracks
                        fresh.playlists[index].loaded = true
                    }
                }
            } else {
                playables = []
                indexByURL = [:]
            }
            catalog = fresh
            catalog.indexPlaylists()
        }
        return catalog.playlists.map(\.name) != previousNames || catalog.sourceID != previousSource
    }

    /// Fetch what a skin asked for and the catalog does not hold. Returns false when there was
    /// nothing new to fetch — already loaded, already in flight, or a different source by now.
    func fetch(_ demand: String) async -> Bool {
        if let running = inFlight[demand] { return await running.value }
        let task = Task { await perform(demand) }
        inFlight[demand] = task
        let fetched = await task.value
        inFlight[demand] = nil
        return fetched
    }

    private func perform(_ demand: String) async -> Bool {
        guard let provider else { return false }
        let sourceID = catalog.sourceID
        if demand.hasPrefix("playlist:") {
            let id = String(demand.dropFirst("playlist:".count))
            guard let index = catalog.playlistIndex(id: id), !catalog.playlists[index].loaded
            else { return false }
            let tracks = await provider.loadPlaylist(id)
            guard catalog.sourceID == sourceID, let index = catalog.playlistIndex(id: id)
            else { return false }
            catalog.playlists[index].tracks = append(tracks)
            catalog.playlists[index].loaded = true
            return true
        }
        if demand.hasPrefix("query:") {
            let key = String(demand.dropFirst("query:".count))
            guard catalog.queryResults[key] == nil,
                  let colon = key.firstIndex(of: ":") else { return false }
            let attribute = String(key[..<colon]), value = String(key[key.index(after: colon)...])
            let tracks = await provider.loadQuery(attribute, value)
            guard catalog.sourceID == sourceID else { return false }
            catalog.queryResults[key] = append(tracks)
            return true
        }
        return false
    }

    /// Add fetched tracks to the catalog, once each by location, and return their indices.
    private func append(_ tracks: [Track]) -> [Int] {
        if indexByURL.count != playables.count {
            indexByURL = Dictionary(playables.enumerated().map { ($1.url, $0) },
                                    uniquingKeysWith: { first, _ in first })
        }
        return tracks.map { track in
            if let existing = indexByURL[track.url] { return existing }
            playables.append(track)
            indexByURL[track.url] = playables.count - 1
            // **Not added to `libraryTracks`.** A fetched track is addressable — a playlist or a
            // query can name it — but it is not "the library": a server's library cannot be
            // listed, and counting every fetched track as part of it made `getAll()` and "All
            // Music" answer with whatever had been searched for or opened before, which is how a
            // `WoW` search came back in `NVIDIA` after a skin and a source switch.
            catalog.tracks.append(Self.entry(track))
            return catalog.tracks.count - 1
        }
    }

    private static func entry(_ track: Track) -> WMPLibraryCatalog.Track {
        .init(title: track.title, artist: track.artist ?? "", album: track.album ?? "",
              genre: track.genre ?? "", sourceURL: WMPAudioEngineHost.sourceURLSpelling(track.url),
              duration: track.duration ?? 0, isVideo: track.mediaType == .video)
    }

    private static func sourceID(_ source: ModernBrowserSource) -> String {
        switch source {
        case .local: return "local"
        case .plex(let id): return "plex:\(id)"
        case .subsonic(let id): return "subsonic:\(id)"
        case .jellyfin(let id): return "jellyfin:\(id)"
        case .emby(let id): return "emby:\(id)"
        case .radio: return "radio"
        case .youtube: return "youtube"
        }
    }

    // MARK: Local Files

    private nonisolated static func buildLocal() -> (catalog: WMPLibraryCatalog, playables: [Track]) {
        var catalog = WMPLibraryCatalog()
        var playables: [Track] = []
        var indexByPath: [String: Int] = [:]

        func append(_ entry: WMPLibraryCatalog.Track, _ track: Track) -> Int {
            if let existing = indexByPath[track.url.path] { return existing }
            catalog.tracks.append(entry)
            playables.append(track)
            indexByPath[track.url.path] = catalog.tracks.count - 1
            return catalog.tracks.count - 1
        }

        let library = MediaLibrary.shared
        for track in library.tracksSnapshot {
            let index = append(.init(title: track.title, artist: track.artist ?? "",
                                     album: track.album ?? "", genre: track.genre ?? "",
                                     sourceURL: WMPAudioEngineHost.sourceURLSpelling(track.url),
                                     duration: track.duration, isVideo: false), track.toTrack())
            catalog.libraryTracks.append(index)
        }
        for video in library.moviesSnapshot {
            let index = append(.init(title: video.title, artist: "", album: "", genre: "",
                                     sourceURL: WMPAudioEngineHost.sourceURLSpelling(video.url),
                                     duration: video.duration, isVideo: true),
                               Track(lightweightURL: video.url))
            catalog.libraryTracks.append(index)
        }
        for playlist in library.playlistsSnapshot {
            let entries = Playlist.load(from: playlist.url)?.trackURLs ?? []
            let tracks = entries.map { url -> Int in
                let known = library.findTrack(byURL: url)
                return append(.init(title: known?.title ?? url.deletingPathExtension().lastPathComponent,
                                    artist: known?.artist ?? "", album: known?.album ?? "",
                                    genre: known?.genre ?? "",
                                    sourceURL: WMPAudioEngineHost.sourceURLSpelling(url),
                                    duration: known?.duration ?? 0, isVideo: false),
                              known?.toTrack() ?? Track(lightweightURL: url))
            }
            catalog.playlists.append(.init(id: playlist.url.absoluteString, name: playlist.title,
                                           tracks: tracks))
        }
        return (catalog, playables)
    }
}

/// One media server's answers to the questions a skin asks, from its manager's caches and fetches.
/// The same five questions for every server; only the manager calls differ.
@MainActor
struct WMPLibraryProvider {
    /// The server's playlists — its manager's cache, or a fetch when nothing has cached them yet:
    /// Plex fills its cache only when the browser's Playlists tab is opened.
    let playlists: () async -> [(id: String, name: String)]
    let strings: () async -> [String: [String]]
    let loadPlaylist: (_ playlistID: String) async -> [Track]
    let loadQuery: (_ attribute: String, _ value: String) async -> [Track]

    /// A genre or an artist can span hundreds of albums; a skin asking for one gets the first
    /// this many rather than a request per album of the whole library.
    private static let maximumAlbumsPerQuery = 25

    /// The library section a Plex smart playlist queries: its content URI is
    /// `library://…/directory/%2Flibrary%2Fsections%2F<id>%2Fall…`.
    private static func smartPlaylistSection(_ content: String?) -> String? {
        guard let decoded = content?.removingPercentEncoding,
              let range = decoded.range(of: "/library/sections/") else { return nil }
        let id = decoded[range.upperBound...].prefix { $0 != "/" && $0 != "?" }
        return id.isEmpty ? nil : String(id)
    }

    private static func matches(_ name: String?, _ value: String) -> Bool {
        name?.caseInsensitiveCompare(value) == .orderedSame
    }

    private static func sortedUnique(_ values: [String?]) -> [String] {
        var seen = Set<String>(), result: [String] = []
        for case let value? in values where !value.isEmpty && seen.insert(value.lowercased()).inserted {
            result.append(value)
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func make(for source: ModernBrowserSource) -> WMPLibraryProvider? {
        switch source {
        case .plex:
            let manager = PlexManager.shared
            return .init(
                playlists: {
                    var cached = manager.cachedPlaylists
                    if cached.isEmpty { cached = (try? await manager.fetchPlaylists()) ?? [] }
                    // A smart playlist is a query over one Plex library section, and one over a
                    // section other than the current library cannot be opened: Plex answers 500
                    // for its items and 404 for its query (measured 2026-09-24). Listing it gave
                    // the skin a playlist that could never play.
                    let section = manager.currentLibrary?.id
                    return cached.filter { playlist in
                        guard playlist.playlistType == "audio" else { return false }
                        guard playlist.smart, let section,
                              let owner = smartPlaylistSection(playlist.content) else { return true }
                        return owner == section
                    }.map { ($0.id, $0.title) }
                },
                strings: {
                    ["artist": sortedUnique(manager.cachedArtists.map(\.title)),
                     "album": sortedUnique(manager.cachedAlbums.map(\.title)),
                     "genre": sortedUnique(await manager.getGenres())]
                },
                loadPlaylist: { id in
                    guard let playlist = manager.cachedPlaylists.first(where: { $0.id == id }),
                          let fetched = try? await manager.fetchPlaylistTracks(
                            playlistID: id, smartContent: playlist.smart ? playlist.content : nil)
                    else { return [] }
                    return manager.convertToTracks(fetched)
                },
                loadQuery: { attribute, value in
                    switch attribute {
                    case "search":
                        guard let found = try? await manager.search(query: value, type: .track) else { return [] }
                        return manager.convertToTracks(found.tracks)
                    case "artist":
                        guard let artist = manager.cachedArtists.first(where: { matches($0.title, value) }),
                              let fetched = try? await manager.fetchTracks(forArtist: artist) else { return [] }
                        return manager.convertToTracks(fetched)
                    case "album", "genre":
                        var result: [Track] = []
                        let albums = manager.cachedAlbums.filter {
                            attribute == "album" ? matches($0.title, value) : matches($0.genre, value)
                        }.prefix(maximumAlbumsPerQuery)
                        for album in albums {
                            if let fetched = try? await manager.fetchTracks(forAlbum: album) {
                                result += manager.convertToTracks(fetched)
                            }
                        }
                        return result
                    default: return []
                    }
                })
        case .subsonic:
            let manager = SubsonicManager.shared
            return .init(
                playlists: {
                    var cached = manager.cachedPlaylists
                    if cached.isEmpty { cached = (try? await manager.fetchPlaylists()) ?? [] }
                    return cached.map { ($0.id, $0.name) }
                },
                strings: {
                    ["artist": sortedUnique(manager.cachedArtists.map(\.name)),
                     "album": sortedUnique(manager.cachedAlbums.map(\.name)),
                     "genre": sortedUnique(await manager.getGenres())]
                },
                loadPlaylist: { id in
                    manager.convertToTracks((try? await manager.fetchPlaylistSongs(id: id)) ?? [])
                },
                loadQuery: { attribute, value in
                    if attribute == "search" {
                        guard let found = try? await manager.search(query: value) else { return [] }
                        return manager.convertToTracks(found.songs)
                    }
                    var albums: [SubsonicAlbum]
                    switch attribute {
                    case "artist":
                        guard let artist = manager.cachedArtists.first(where: { matches($0.name, value) })
                        else { return [] }
                        albums = (try? await manager.fetchAlbums(forArtist: artist)) ?? []
                    case "album": albums = manager.cachedAlbums.filter { matches($0.name, value) }
                    case "genre": albums = manager.cachedAlbums.filter { matches($0.genre, value) }
                    default: return []
                    }
                    var result: [Track] = []
                    for album in albums.prefix(maximumAlbumsPerQuery) {
                        result += manager.convertToTracks((try? await manager.fetchSongs(forAlbum: album)) ?? [])
                    }
                    return result
                })
        case .jellyfin:
            let manager = JellyfinManager.shared
            return .init(
                playlists: {
                    var cached = manager.cachedPlaylists
                    if cached.isEmpty { cached = (try? await manager.fetchPlaylists()) ?? [] }
                    return cached.map { ($0.id, $0.name) }
                },
                strings: {
                    ["artist": sortedUnique(manager.cachedArtists.map(\.name)),
                     "album": sortedUnique(manager.cachedAlbums.map(\.name)),
                     "genre": sortedUnique(await manager.getMusicGenres())]
                },
                loadPlaylist: { id in
                    manager.convertToTracks((try? await manager.fetchPlaylistSongs(id: id)) ?? [])
                },
                loadQuery: { attribute, value in
                    if attribute == "search" {
                        guard let found = try? await manager.search(query: value) else { return [] }
                        return manager.convertToTracks(found.songs)
                    }
                    var albums: [JellyfinAlbum]
                    switch attribute {
                    case "artist":
                        guard let artist = manager.cachedArtists.first(where: { matches($0.name, value) })
                        else { return [] }
                        albums = (try? await manager.fetchAlbums(forArtist: artist)) ?? []
                    case "album": albums = manager.cachedAlbums.filter { matches($0.name, value) }
                    case "genre": albums = manager.cachedAlbums.filter { matches($0.genre, value) }
                    default: return []
                    }
                    var result: [Track] = []
                    for album in albums.prefix(maximumAlbumsPerQuery) {
                        result += manager.convertToTracks((try? await manager.fetchSongs(forAlbum: album)) ?? [])
                    }
                    return result
                })
        case .emby:
            let manager = EmbyManager.shared
            return .init(
                playlists: {
                    var cached = manager.cachedPlaylists
                    if cached.isEmpty { cached = (try? await manager.fetchPlaylists()) ?? [] }
                    return cached.map { ($0.id, $0.name) }
                },
                strings: {
                    ["artist": sortedUnique(manager.cachedArtists.map(\.name)),
                     "album": sortedUnique(manager.cachedAlbums.map(\.name)),
                     "genre": sortedUnique(await manager.getMusicGenres())]
                },
                loadPlaylist: { id in
                    manager.convertToTracks((try? await manager.fetchPlaylistSongs(id: id)) ?? [])
                },
                loadQuery: { attribute, value in
                    if attribute == "search" {
                        guard let found = try? await manager.search(query: value) else { return [] }
                        return manager.convertToTracks(found.songs)
                    }
                    var albums: [EmbyAlbum]
                    switch attribute {
                    case "artist":
                        guard let artist = manager.cachedArtists.first(where: { matches($0.name, value) })
                        else { return [] }
                        albums = (try? await manager.fetchAlbums(forArtist: artist)) ?? []
                    case "album": albums = manager.cachedAlbums.filter { matches($0.name, value) }
                    case "genre": albums = manager.cachedAlbums.filter { matches($0.genre, value) }
                    default: return []
                    }
                    var result: [Track] = []
                    for album in albums.prefix(maximumAlbumsPerQuery) {
                        result += manager.convertToTracks((try? await manager.fetchSongs(forAlbum: album)) ?? [])
                    }
                    return result
                })
        case .local, .radio, .youtube:
            return nil
        }
    }
}
