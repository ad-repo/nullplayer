import Foundation

/// The Subsonic, Jellyfin and Emby sources: loading, rows, search and radio, written once over
/// `MusicServerBrowsing`. Jellyfin and Emby add the Movies and TV tabs (`VideoServerBrowsing`).
extension LibraryBrowserModel {

    /// The manager behind the current source, when it is a Subsonic, Jellyfin or Emby server.
    var currentServerManager: (any MusicServerBrowsing)? {
        switch currentSource {
        case .subsonic: return SubsonicManager.shared
        case .jellyfin: return JellyfinManager.shared
        case .emby: return EmbyManager.shared
        case .local, .plex, .radio, .youtube: return nil
        }
    }

    // MARK: - Loading

    /// Connect to the current source's server when another is connected, then load the current tab.
    func loadServerData<M: MusicServerBrowsing>(_ manager: M, generation: Int) {
        let expectedSource = currentSource
        guard let serverId = expectedSource.serverId, isLoadContextActive(generation, source: expectedSource) else { return }
        loadState = .loading
        let load: @MainActor () -> Void = { [weak self] in
            self?.loadServerTab(manager, generation: generation, expectedSource: expectedSource)
        }
        guard manager.currentServer?.id != serverId else { load(); return }
        let server = manager.servers.first { $0.id == serverId }
        connectThenLoad(generation: generation, source: expectedSource,
                        connect: server.map { server in { try await manager.connect(to: server) } },
                        isConnected: { manager.currentServer?.id == serverId }, load: load)
    }

    private func loadServerTab<M: MusicServerBrowsing>(_ manager: M, generation: Int, expectedSource: LibraryBrowserSource) {
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard self.isLoadContextActive(generation, source: expectedSource),
                      try await self.waitForPreload({ manager.isPreloading }, generation: generation, source: expectedSource)
                else { return }
                if self.browseMode == .radio {
                    self.loadServerRadioStations(manager, generation: generation)
                    return
                }
                guard try await self.fetchServerTab(manager, generation: generation, source: expectedSource) else { return }
                self.rebuildServerRows(manager)
                self.finishLoadIfActive(generation: generation, source: expectedSource)
            } catch is CancellationError {
            } catch where Task.isCancelled {
            } catch {
                self.setLoadErrorIfActive(error.localizedDescription, generation: generation, source: expectedSource)
            }
        }
    }

    /// Fill the current tab's cache from the server's preload, or a fetch when it has none. Returns
    /// false once the load is superseded.
    private func fetchServerTab<M: MusicServerBrowsing>(_ manager: M, generation: Int,
                                                        source: LibraryBrowserSource) async throws -> Bool {
        let cache = M.musicCache
        func preloadedOr<Item>(_ preloaded: [Item], fetch: @MainActor () async throws -> [Item]) async throws -> [Item] {
            try await preloadedOrFetched(preloaded, isPreloaded: manager.isContentPreloaded,
                                         generation: generation, source: source, fetch: fetch)
        }

        switch browseMode {
        case .artists:
            if self[keyPath: cache].artists.isEmpty {
                if pendingArtistLoadUnfiltered {
                    // After a search jump: every artist, so the one found outside the library is listed.
                    try Task.checkCancellation()
                    self[keyPath: cache].artists = try await manager.fetchArtistsUnfiltered()
                    guard isLoadContextActive(generation, source: source) else { return false }
                } else {
                    self[keyPath: cache].artists = try await preloadedOr(manager.cachedArtists) { try await manager.fetchArtists() }
                    if !M.warmsAlbumsAfterArtists {
                        self[keyPath: cache].albums = try await preloadedOr(manager.cachedAlbums) { try await manager.fetchAlbums() }
                    } else if manager.isContentPreloaded && !manager.cachedAlbums.isEmpty {
                        self[keyPath: cache].albums = manager.cachedAlbums
                    } else if let serverId = manager.currentServer?.id {
                        warmServerAlbums(manager, serverId: serverId)
                    }
                }
            }
            pendingArtistLoadUnfiltered = false
        case .albums:
            if self[keyPath: cache].albums.isEmpty {
                self[keyPath: cache].albums = try await preloadedOr(manager.cachedAlbums) { try await manager.fetchAlbums() }
            }
        case .plists, .folders:
            if self[keyPath: cache].playlists.isEmpty {
                self[keyPath: cache].playlists = try await preloadedOr(manager.cachedPlaylists) { try await manager.fetchPlaylists() }
            }
        case .search:
            if searchedQuery.isEmpty {
                self[keyPath: cache].searchResults = nil
            } else {
                let results = try await manager.librarySearch(searchedQuery)
                guard isLoadContextActive(generation, source: source) else { return false }
                self[keyPath: cache].searchResults = results
            }
        case .movies, .shows:
            if let video = manager as? any VideoServerBrowsing {
                try await fetchVideoTab(video, generation: generation, source: source)
            }
        case .radio, .history:
            break
        }
        return true
    }

    private func fetchVideoTab<V: VideoServerBrowsing>(_ manager: V, generation: Int, source: LibraryBrowserSource) async throws {
        let cache = V.videoCache
        func preloadedOr<Item>(_ preloaded: [Item], fetch: @MainActor () async throws -> [Item]) async throws -> [Item] {
            try await preloadedOrFetched(preloaded, isPreloaded: manager.isContentPreloaded,
                                         generation: generation, source: source, fetch: fetch)
        }
        if browseMode == .movies, self[keyPath: cache].movies.isEmpty {
            self[keyPath: cache].movies = try await preloadedOr(manager.cachedMovies) { try await manager.fetchMovies() }
        } else if browseMode == .shows, self[keyPath: cache].shows.isEmpty {
            self[keyPath: cache].shows = try await preloadedOr(manager.cachedShows) { try await manager.fetchShows() }
        }
    }

    /// The Artists tab loaded without albums: fetch them in the background, for the date and year
    /// sorts and for instant expansion.
    private func warmServerAlbums<M: MusicServerBrowsing>(_ manager: M, serverId: String) {
        guard albumWarmTask == nil else { return }
        albumWarmTask = Task.detached { @MainActor [weak self] in
            do {
                let albums = try await manager.fetchAlbums()
                guard let self else { return }
                defer { self.albumWarmTask = nil }
                guard self.currentSource == M.source(serverId: serverId), self[keyPath: M.musicCache].albums.isEmpty else { return }
                self[keyPath: M.musicCache].albums = albums
                if self.browseMode == .artists { self.displayItems = self.serverArtistRows(M.self) }
            } catch {
                self?.albumWarmTask = nil
                if !(error is CancellationError) {
                    NSLog("LibraryBrowserModel: album cache warm failed: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
                }
            }
        }
    }

    /// The Refresh button: drop the server's own cache and wait for its library to preload again.
    func refreshServer(_ manager: some MusicServerBrowsing) {
        albumWarmTask?.cancel(); albumWarmTask = nil
        manager.clearCachedContent()
        refreshAfterPreload { await manager.preloadLibraryContent() }
    }

    // MARK: - Rows

    /// The current tab's rows from the cache.
    func rebuildServerRows<M: MusicServerBrowsing>(_ manager: M) {
        switch browseMode {
        case .artists: displayItems = serverArtistRows(M.self)
        case .albums: displayItems = serverAlbumRows(M.self)
        case .plists, .folders: displayItems = serverPlaylistRows(M.self)
        case .search: displayItems = serverSearchRows(manager)
        case .movies, .shows: displayItems = (manager as? any VideoServerBrowsing).map { videoRows($0) } ?? []
        case .radio, .history: displayItems = []
        }
    }

    /// Each artist, then its albums when expanded, each with its songs when expanded.
    private func serverArtistRows<M: MusicServerBrowsing>(_: M.Type) -> [LibraryBrowserItem] {
        let cache = self[keyPath: M.musicCache]
        var rows: [LibraryBrowserItem] = []
        for artist in sortedServerArtists(cache.artists, albums: cache.albums) {
            rows.append(artistRow(artist, indentLevel: 0))
            guard isExpanded(M.Artist.expansionKind, artist.id), let albums = cache.artistAlbums[artist.id] else { continue }
            for album in sortedServerAlbums(albums) {
                rows.append(albumRow(album, title: album.name, indentLevel: 1))
                rows += songRows(ofAlbum: album, M.self, indentLevel: 2)
            }
        }
        return rows
    }

    private func serverAlbumRows<M: MusicServerBrowsing>(_: M.Type) -> [LibraryBrowserItem] {
        sortedServerAlbums(self[keyPath: M.musicCache].albums).flatMap { album in
            [albumRow(album, title: "\(album.artist ?? "Unknown") - \(album.name)", indentLevel: 0)]
                + songRows(ofAlbum: album, M.self, indentLevel: 1)
        }
    }

    private func serverPlaylistRows<M: MusicServerBrowsing>(_: M.Type) -> [LibraryBrowserItem] {
        let cache = self[keyPath: M.musicCache]
        var rows: [LibraryBrowserItem] = []
        for playlist in menuSorted(cache.playlists, name: \.name, created: M.Playlist.addedDate) {
            rows.append(LibraryBrowserItem(id: playlist.id, title: playlist.name, info: LibraryBrowserItem.countLabel(playlist.songCount, "track"),
                                           indentLevel: 0, hasChildren: playlist.songCount > 0, type: playlist.itemType))
            guard isExpanded(M.Playlist.expansionKind, playlist.id), let songs = cache.playlistTracks[playlist.id] else { continue }
            rows += songs.map { song in
                LibraryBrowserItem(id: "\(playlist.id)-\(song.id)", title: song.title, info: LibraryBrowserItem.formatDuration(song.duration),
                                   indentLevel: 1, hasChildren: false, type: song.itemType)
            }
        }
        return rows
    }

    /// Artists, albums and tracks found, each under a header; a video server's movies and shows too.
    private func serverSearchRows<M: MusicServerBrowsing>(_ manager: M) -> [LibraryBrowserItem] {
        guard let results = self[keyPath: M.musicCache].searchResults else { return [] }
        var rows: [LibraryBrowserItem] = []
        let artists = sortedServerArtists(results.artists, albums: self[keyPath: M.musicCache].albums)
        rows += searchSection("artists", "Artists", artists) { [artistRow($0, indentLevel: 1)] }
        rows += searchSection("albums", "Albums", sortedServerAlbums(results.albums)) { [albumRow($0, title: $0.name, indentLevel: 1)] }
        let songs = menuSorted(results.songs, name: \.title, created: { $0.created }, year: { $0.year })
        rows += searchSection("tracks", "Tracks", songs) { songRows([$0], indentLevel: 1) }
        if let video = manager as? any VideoServerBrowsing {
            rows += videoSearchRows(video)
        }
        return rows
    }

    private func videoSearchRows<V: VideoServerBrowsing>(_: V) -> [LibraryBrowserItem] {
        guard let results = self[keyPath: V.musicCache].searchResults else { return [] }
        return searchSection("movies", "Movies", results.movies) { [movieRow($0, indentLevel: 1)] }
            + searchSection("shows", "TV Shows", results.shows) { showRows($0, V.self, indentLevel: 1) }
    }

    /// A header with the count, then each item's rows; nothing when there are none.
    func searchSection<Item>(_ id: String, _ title: String, _ items: [Item],
                                     rows: (Item) -> [LibraryBrowserItem]) -> [LibraryBrowserItem] {
        guard !items.isEmpty else { return [] }
        return [LibraryBrowserItem(id: "header-\(id)", title: "\(title) (\(items.count))", info: nil,
                                   indentLevel: 0, hasChildren: false, type: .header)] + items.flatMap(rows)
    }

    private func artistRow(_ artist: some BrowsableArtist, indentLevel: Int) -> LibraryBrowserItem {
        LibraryBrowserItem(id: artist.id, title: artist.name, info: artist.albumCount > 0 ? LibraryBrowserItem.countLabel(artist.albumCount, "album") : nil,
                           indentLevel: indentLevel, hasChildren: true, type: artist.itemType)
    }

    private func albumRow(_ album: some BrowsableAlbum, title: String, indentLevel: Int) -> LibraryBrowserItem {
        LibraryBrowserItem(id: album.id, title: title, info: album.year.map { String($0) },
                           indentLevel: indentLevel, hasChildren: true, type: album.itemType)
    }

    /// An expanded album's songs, by disc then track number.
    private func songRows<M: MusicServerBrowsing>(ofAlbum album: M.Album, _: M.Type, indentLevel: Int) -> [LibraryBrowserItem] {
        guard isExpanded(M.Album.expansionKind, album.id), let songs = self[keyPath: M.musicCache].albumSongs[album.id] else { return [] }
        return songRows(discOrdered(songs, disc: \.discNumber, track: \.track), indentLevel: indentLevel)
    }

    private func songRows(_ songs: [some BrowsableSong], indentLevel: Int) -> [LibraryBrowserItem] {
        songs.map { LibraryBrowserItem(id: $0.id, title: $0.title, info: LibraryBrowserItem.formatDuration($0.duration),
                                       indentLevel: indentLevel, hasChildren: false, type: $0.itemType) }
    }

    // MARK: - Video rows

    private func videoRows<V: VideoServerBrowsing>(_: V) -> [LibraryBrowserItem] {
        let cache = self[keyPath: V.videoCache]
        return browseMode == .movies
            ? cache.movies.map { movieRow($0, indentLevel: 0) }
            : cache.shows.flatMap { showRows($0, V.self, indentLevel: 0) }
    }

    private func movieRow(_ movie: some BrowsableMovie, indentLevel: Int) -> LibraryBrowserItem {
        let info = [movie.year.map { String($0) }, movie.formattedDuration].compactMap { $0 }.joined(separator: " • ")
        return LibraryBrowserItem(id: movie.id, title: movie.title, info: info.isEmpty ? nil : info,
                                  indentLevel: indentLevel, hasChildren: false, type: movie.itemType)
    }

    /// A show, then its seasons when expanded, each with its episodes when expanded. A count the
    /// server does not report is left out.
    private func showRows<V: VideoServerBrowsing>(_ show: V.Show, _: V.Type, indentLevel: Int) -> [LibraryBrowserItem] {
        let cache = self[keyPath: V.videoCache]
        let seasonCount = show.childCount > 0 ? "\(show.childCount) seasons" : nil
        let info = [show.year.map { String($0) }, seasonCount].compactMap { $0 }.joined(separator: " • ")
        var rows = [LibraryBrowserItem(id: show.id, title: show.title, info: info.isEmpty ? nil : info,
                                       indentLevel: indentLevel, hasChildren: true, type: show.itemType)]
        guard isExpanded(V.Show.expansionKind, show.id), let seasons = cache.showSeasons[show.id] else { return rows }
        for season in seasons {
            rows.append(LibraryBrowserItem(id: season.id, title: season.title,
                                           info: season.childCount > 0 ? "\(season.childCount) episodes" : nil,
                                           indentLevel: indentLevel + 1, hasChildren: true, type: season.itemType))
            guard isExpanded(V.Season.expansionKind, season.id), let episodes = cache.seasonEpisodes[season.id] else { continue }
            rows += episodes.map { episode in
                LibraryBrowserItem(id: episode.id, title: "\(episode.episodeIdentifier) - \(episode.title)",
                                   info: episode.formattedDuration, indentLevel: indentLevel + 2, hasChildren: false,
                                   type: episode.itemType)
            }
        }
        return rows
    }

    // MARK: - Sorting

    private func sortedServerAlbums<Album: BrowsableAlbum>(_ albums: [Album]) -> [Album] {
        menuSorted(albums, name: \.name, created: { $0.created }, year: { $0.year })
    }

    // MARK: - Radio

    func loadServerRadioStations<M: MusicServerBrowsing>(_ manager: M, generation: Int) {
        let expectedSource = currentSource
        loadState = .loading
        radioLoadTask?.cancel()
        radioLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let genres = await manager.radioGenres()
            guard !Task.isCancelled, self.isLoadContextActive(generation, source: expectedSource),
                  self.browseMode == .radio else { return }
            self.displayItems = M.RadioStation.stations(genres: genres).map { station in
                LibraryBrowserItem(id: "radio-\(station.category)-\(station.displayName)", title: station.displayName,
                                   info: station.category, indentLevel: 0, hasChildren: false, type: M.radioItem(station))
            }
            self.endLoading()
            self.radioLoadTask = nil
        }
    }
}
