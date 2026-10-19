import Foundation
import NullPlayerCore

/// Expanding and collapsing rows. A row whose children come from a server fetches them on its
/// first expand and rebuilds once they arrive.
extension LibraryBrowserModel {

    /// An expanded row: what kind of row it is, and the id its children are cached under.
    struct ExpansionKey: Hashable {
        enum Kind: Hashable {
            case plexArtist, plexSearchArtist, plexAlbum, plexShow, plexSeason, plexPlaylist
            case localArtist, localAlbum, localFolder, localShow, localSeason, localPlaylist
            case subsonicArtist, subsonicAlbum, subsonicPlaylist
            case jellyfinArtist, jellyfinAlbum, jellyfinPlaylist, jellyfinShow, jellyfinSeason
            case embyArtist, embyAlbum, embyPlaylist, embyShow, embySeason
            case radioFolder

            /// Where the row's children come from: dropping that cache collapses the row.
            var scope: ExpansionScope {
                switch self {
                case .plexArtist, .plexSearchArtist, .plexAlbum, .plexShow, .plexSeason: return .plexLibrary
                case .plexPlaylist: return .plexPlaylists
                case .localArtist, .localAlbum, .localFolder, .localShow, .localSeason: return .local
                case .localPlaylist: return .localPlaylists
                case .subsonicArtist, .subsonicAlbum, .subsonicPlaylist: return .subsonic
                case .jellyfinArtist, .jellyfinAlbum, .jellyfinPlaylist: return .jellyfinMusic
                case .jellyfinShow, .jellyfinSeason: return .jellyfinVideo
                case .embyArtist, .embyAlbum, .embyPlaylist: return .embyMusic
                case .embyShow, .embySeason: return .embyVideo
                case .radioFolder: return .radio
                }
            }
        }

        let kind: Kind
        let id: String
    }

    enum ExpansionScope {
        case plexLibrary, plexPlaylists, local, localPlaylists, subsonic
        case jellyfinMusic, jellyfinVideo, embyMusic, embyVideo, radio
    }

    func isExpanded(_ kind: ExpansionKey.Kind, _ id: String) -> Bool {
        expanded.contains(ExpansionKey(kind: kind, id: id))
    }

    func isExpanded(_ item: LibraryBrowserItem) -> Bool {
        if case .youtubeChannel(let channel) = item.type { return expandedYouTubeChannels[channel.id] != nil }
        return expansionKey(for: item).map { expanded.contains($0) } ?? false
    }

    /// Collapse every row whose children come from one of `scopes`.
    func collapse(_ scopes: ExpansionScope...) {
        expanded = expanded.filter { !scopes.contains($0.kind.scope) }
    }

    /// Collapse every library row. Radio folders and local playlists stay open: their children
    /// are read locally rather than from a cache a reload drops, and a column sort leaves them in place.
    func collapseLibraryRows() {
        expanded = expanded.filter { $0.kind.scope == .radio || $0.kind.scope == .localPlaylists }
    }

    private func expansionKey(for item: LibraryBrowserItem) -> ExpansionKey? {
        let kind: ExpansionKey.Kind
        let id: String
        switch item.type {
        // Search results expand by name: their ids vary after de-duplication. Elsewhere the
        // row is the grouped artist, so same-name Plex artists expand together.
        case .artist(let artist) where browseMode == .search: (kind, id) = (.plexSearchArtist, Self.plexSearchArtistKey(artist))
        case .artist: (kind, id) = (.plexArtist, item.id)
        case .album(let album): (kind, id) = (.plexAlbum, album.id)
        case .show(let show): (kind, id) = (.plexShow, show.id)
        case .season(let season): (kind, id) = (.plexSeason, season.id)
        case .plexPlaylist(let playlist): (kind, id) = (.plexPlaylist, playlist.id)
        case .localArtist(let artist): (kind, id) = (.localArtist, artist.id)
        case .localAlbum(let album): (kind, id) = (.localAlbum, album.id)
        case .localFolder(let url, _): (kind, id) = (.localFolder, url.path)
        case .localShow(let show): (kind, id) = (.localShow, show.id)
        case .localSeason(let season, let showTitle): (kind, id) = (.localSeason, Self.localSeasonKey(season, showTitle: showTitle))
        case .localPlaylist(let playlist): (kind, id) = (.localPlaylist, playlist.url.path)
        case .subsonicArtist(let artist): (kind, id) = (.subsonicArtist, artist.id)
        case .subsonicAlbum(let album): (kind, id) = (.subsonicAlbum, album.id)
        case .subsonicPlaylist(let playlist): (kind, id) = (.subsonicPlaylist, playlist.id)
        case .jellyfinArtist(let artist): (kind, id) = (.jellyfinArtist, artist.id)
        case .jellyfinAlbum(let album): (kind, id) = (.jellyfinAlbum, album.id)
        case .jellyfinPlaylist(let playlist): (kind, id) = (.jellyfinPlaylist, playlist.id)
        case .jellyfinShow(let show): (kind, id) = (.jellyfinShow, show.id)
        case .jellyfinSeason(let season): (kind, id) = (.jellyfinSeason, season.id)
        case .embyArtist(let artist): (kind, id) = (.embyArtist, artist.id)
        case .embyAlbum(let album): (kind, id) = (.embyAlbum, album.id)
        case .embyPlaylist(let playlist): (kind, id) = (.embyPlaylist, playlist.id)
        case .embyShow(let show): (kind, id) = (.embyShow, show.id)
        case .embySeason(let season): (kind, id) = (.embySeason, season.id)
        case .radioFolder(let folder) where folder.hasChildren: (kind, id) = (.radioFolder, folder.id)
        default: return nil
        }
        return ExpansionKey(kind: kind, id: id)
    }

    func toggleExpand(_ item: LibraryBrowserItem) {
        if case .youtubeChannel(let channel) = item.type {
            if expandedYouTubeChannels.removeValue(forKey: channel.id) == nil {
                expandedYouTubeChannels[channel.id] = channel
                YouTubeChannelUploads.shared.load([channel])  // rebuilds through youtubeUploadsDidChange
                return
            }
        } else if let key = expansionKey(for: item), expanded.remove(key) == nil {
            expanded.insert(key)
            if fetchChildrenIfNeeded(of: item, key: key) { return }
        }
        rebuildCurrentModeItems()
    }

    /// A row was just expanded: start fetching its children when they are not cached yet.
    /// Returns whether a fetch started (it rebuilds once they arrive).
    private func fetchChildrenIfNeeded(of item: LibraryBrowserItem, key: ExpansionKey) -> Bool {
        switch item.type {
        case .artist(let artist) where key.kind == .plexSearchArtist:
            guard plex.artistAlbumsByName[key.id] == nil else { return false }
            fetchChildren(of: artist.title, key: key) { model in
                let albums = try await PlexManager.shared.fetchAlbums(forArtist: artist)
                // An empty answer for an artist with albums is not cached, so expanding retries
                if albums.isEmpty && artist.albumCount > 0 {
                    model.expanded.remove(key)
                } else {
                    model.plex.artistAlbumsByName[key.id] = albums
                }
            }
        case .artist(let artist):
            guard plex.artistAlbums[key.id] == nil else { return false }
            fetchChildren(of: artist.title, key: key) { model in
                let albums = try await model.fetchAlbumsForPlexArtistGroup(artist)
                // An empty answer for an artist with albums is not cached, so expanding retries
                if albums.isEmpty && (model.plexArtistAlbumCount(for: artist) ?? 0) > 0 {
                    model.expanded.remove(key)
                } else {
                    model.plex.artistAlbums[key.id] = albums
                }
            }
        case .album(let album):
            guard plex.albumTracks[album.id] == nil else { return false }
            fetchChildren(of: album.title, key: key) { model in
                model.plex.albumTracks[album.id] = try await PlexManager.shared.fetchTracks(forAlbum: album)
            }
        case .show(let show):
            guard plex.showSeasons[show.id] == nil else { return false }
            fetchChildren(of: show.title, key: key) { model in
                model.plex.showSeasons[show.id] = try await PlexManager.shared.fetchSeasons(forShow: show)
            }
        case .season(let season):
            guard plex.seasonEpisodes[season.id] == nil else { return false }
            fetchChildren(of: season.title, key: key) { model in
                model.plex.seasonEpisodes[season.id] = try await PlexManager.shared.fetchEpisodes(forSeason: season)
            }
        case .plexPlaylist(let playlist):
            guard plex.playlistTracks[playlist.id] == nil else { return false }
            let smartContent = playlist.smart ? playlist.content : nil
            fetchChildren(of: playlist.title, key: key) { model in
                model.plex.playlistTracks[playlist.id] = try await PlexManager.shared.fetchPlaylistTracks(
                    playlistID: playlist.id, smartContent: smartContent)
            }

        case .localPlaylist(let playlist):
            guard localPlaylistTracks[key.id] == nil else { return false }
            let url = playlist.url
            Task.detached { [weak self] in
                let tracks = LibraryPlayable.tracks(inPlaylistFile: url)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.localPlaylistTracks[key.id] = tracks
                    self.rebuildCurrentModeItems()
                }
            }

        case .subsonicArtist(let artist): return fetchServerAlbums(of: artist, SubsonicManager.shared, key: key)
        case .subsonicAlbum(let album): return fetchServerSongs(of: album, SubsonicManager.shared, key: key)
        case .subsonicPlaylist(let playlist): return fetchServerSongs(of: playlist, SubsonicManager.shared, key: key)
        case .jellyfinArtist(let artist): return fetchServerAlbums(of: artist, JellyfinManager.shared, key: key)
        case .jellyfinAlbum(let album): return fetchServerSongs(of: album, JellyfinManager.shared, key: key)
        case .jellyfinPlaylist(let playlist): return fetchServerSongs(of: playlist, JellyfinManager.shared, key: key)
        case .jellyfinShow(let show): return fetchServerSeasons(of: show, JellyfinManager.shared, key: key)
        case .jellyfinSeason(let season): return fetchServerEpisodes(of: season, JellyfinManager.shared, key: key)
        case .embyArtist(let artist): return fetchServerAlbums(of: artist, EmbyManager.shared, key: key)
        case .embyAlbum(let album): return fetchServerSongs(of: album, EmbyManager.shared, key: key)
        case .embyPlaylist(let playlist): return fetchServerSongs(of: playlist, EmbyManager.shared, key: key)
        case .embyShow(let show): return fetchServerSeasons(of: show, EmbyManager.shared, key: key)
        case .embySeason(let season): return fetchServerEpisodes(of: season, EmbyManager.shared, key: key)

        default:
            return false
        }
        return true
    }

    // MARK: - Subsonic, Jellyfin and Emby

    /// An artist's albums: those already cached at once, else from the server.
    private func fetchServerAlbums<M: MusicServerBrowsing>(of artist: M.Artist, _ manager: M, key: ExpansionKey) -> Bool {
        let cache = M.musicCache
        guard self[keyPath: cache].artistAlbums[artist.id] == nil else { return false }
        let cached = self[keyPath: cache].albums.filter { $0.artistId == artist.id }
        guard cached.isEmpty else { self[keyPath: cache].artistAlbums[artist.id] = cached; return false }
        fetchChildren(of: artist.name, key: key, replacingServerExpand: true) { model in
            model[keyPath: cache].artistAlbums[artist.id] = try await manager.fetchAlbums(forArtist: artist)
        }
        return true
    }

    private func fetchServerSongs<M: MusicServerBrowsing>(of album: M.Album, _ manager: M, key: ExpansionKey) -> Bool {
        let cache = M.musicCache
        guard self[keyPath: cache].albumSongs[album.id] == nil else { return false }
        fetchChildren(of: album.name, key: key, replacingServerExpand: true) { model in
            model[keyPath: cache].albumSongs[album.id] = try await manager.fetchSongs(forAlbum: album)
        }
        return true
    }

    private func fetchServerSongs<M: MusicServerBrowsing>(of playlist: M.Playlist, _ manager: M, key: ExpansionKey) -> Bool {
        let cache = M.musicCache
        guard self[keyPath: cache].playlistTracks[playlist.id] == nil else { return false }
        fetchChildren(of: playlist.name, key: key, replacingServerExpand: true) { model in
            model[keyPath: cache].playlistTracks[playlist.id] = try await manager.playlistSongs(playlist)
        }
        return true
    }

    private func fetchServerSeasons<V: VideoServerBrowsing>(of show: V.Show, _ manager: V, key: ExpansionKey) -> Bool {
        let cache = V.videoCache
        guard self[keyPath: cache].showSeasons[show.id] == nil else { return false }
        fetchChildren(of: show.title, key: key, replacingServerExpand: true) { model in
            model[keyPath: cache].showSeasons[show.id] = try await manager.fetchSeasons(forShow: show)
        }
        return true
    }

    private func fetchServerEpisodes<V: VideoServerBrowsing>(of season: V.Season, _ manager: V, key: ExpansionKey) -> Bool {
        let cache = V.videoCache
        guard self[keyPath: cache].seasonEpisodes[season.id] == nil else { return false }
        fetchChildren(of: season.title, key: key, replacingServerExpand: true) { model in
            model[keyPath: cache].seasonEpisodes[season.id] = try await manager.fetchEpisodes(forSeason: season)
        }
        return true
    }

    /// Fetch an expanded row's children, then rebuild. `fetch` stores them in the cache. A failed
    /// fetch collapses the row, so expanding it again retries. A Subsonic, Jellyfin or Emby fetch
    /// (`replacingServerExpand`) replaces the one still running.
    private func fetchChildren(of title: String, key: ExpansionKey, replacingServerExpand: Bool = false,
                               _ fetch: @escaping @MainActor (LibraryBrowserModel) async throws -> Void) {
        // Detached: a plain Task {} inherits main-actor cancellation, so a main-actor
        // teardown (e.g. reloadUI) could cancel the expand before it runs.
        let fetchTask = Task.detached { @MainActor [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                try await fetch(self)
                try Task.checkCancellation()
                self.rebuildCurrentModeItems()
            } catch is CancellationError {
            } catch where Task.isCancelled {
            } catch {
                NSLog("LibraryBrowserModel: Failed to load the contents of '%@': %@", title,
                      String(describing: error).redactingSensitiveURLQueryItems)
                self.expanded.remove(key)
                self.rebuildCurrentModeItems()
            }
        }
        if replacingServerExpand {
            expandTask?.cancel()
            expandTask = fetchTask
        }
    }
}
