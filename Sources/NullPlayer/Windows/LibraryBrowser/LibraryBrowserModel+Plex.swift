import Foundation
import NullPlayerCore

/// The Plex source.
extension LibraryBrowserModel {

    func loadPlexData(serverId: String, generation: Int) {
        let expectedSource = LibraryBrowserSource.plex(serverId: serverId)
        guard isLoadContextActive(generation, source: expectedSource) else { return }
        let manager = PlexManager.shared
        guard manager.isLinked else {
            displayItems = []
            endLoading()
            return
        }
        loadState = .loading
        let load: @MainActor () -> Void = { [weak self] in
            self?.loadPlexDataForCurrentMode(serverId: serverId, generation: generation, expectedSource: expectedSource)
        }
        guard manager.currentServer?.id != serverId || manager.serverClient == nil else { load(); return }
        let server = manager.servers.first { $0.id == serverId }
        connectThenLoad(generation: generation, source: expectedSource,
                        connect: server.map { server in { try await manager.connect(to: server) } },
                        isConnected: { manager.currentServer?.id == serverId }, load: load)
    }

    private func loadPlexDataForCurrentMode(serverId: String, generation: Int, expectedSource: LibraryBrowserSource) {
        let pm = PlexManager.shared
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard self.isLoadContextActive(generation, source: expectedSource),
                      pm.currentServer?.id == serverId else { return }

                func preloadedOr<Item>(_ preloaded: [Item], fetch: @MainActor () async throws -> [Item]) async throws -> [Item] {
                    try await self.preloadedOrFetched(preloaded, isPreloaded: pm.isContentPreloaded,
                                                      generation: generation, source: expectedSource, fetch: fetch)
                }

                switch self.browseMode {
                case .artists:
                    if self.plex.artists.isEmpty {
                        // Keep the coupled caches atomic so a superseded load cannot expose
                        // artists without albums and permanently skip the index rebuild.
                        let artists: [PlexArtist]
                        let albums: [PlexAlbum]
                        if !self.pendingArtistLoadUnfiltered && pm.isContentPreloaded && !pm.cachedArtists.isEmpty {
                            artists = pm.cachedArtists
                            albums = pm.cachedAlbums
                        } else {
                            artists = try await pm.fetchArtists()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                            albums = try await pm.fetchAllAlbums()
                            guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        }
                        self.plex.artists = artists
                        self.plex.albums = albums
                    }
                    self.buildArtistAlbumCounts()
                    self.pendingArtistLoadUnfiltered = false
                    self.buildArtistItems()
                case .albums:
                    if self.plex.albums.isEmpty {
                        // Every album, as the Artists tab and the preload fetch: the tab sorts
                        // client-side, so a partial fetch would sort only a subset.
                        self.plex.albums = try await preloadedOr(pm.cachedAlbums) { try await pm.fetchAllAlbums() }
                    }
                    self.buildAlbumItems()
                case .movies:
                    if self.plex.movies.isEmpty {
                        self.plex.movies = try await preloadedOr(pm.cachedMovies) { try await pm.fetchAllMovies() }
                    }
                    self.buildMovieItems()
                case .shows:
                    if self.plex.shows.isEmpty {
                        self.plex.shows = try await preloadedOr(pm.cachedShows) { try await pm.fetchAllShows() }
                    }
                    self.buildShowItems()
                case .plists, .folders:
                    if self.plex.playlists.isEmpty {
                        // The manager keeps playlists whether or not the library preloaded
                        self.plex.playlists = try await self.preloadedOrFetched(pm.cachedPlaylists, isPreloaded: true,
                                                                                generation: generation, source: expectedSource) {
                            try await pm.fetchPlaylists()
                        }
                    }
                    self.buildPlexPlaylistItems()
                case .search:
                    if self.searchedQuery.isEmpty {
                        self.displayItems = []
                    } else {
                        self.plex.searchResults = try await pm.searchWithArtistAlbums(query: self.searchedQuery)
                        guard self.isLoadContextActive(generation, source: expectedSource) else { return }
                        self.buildSearchItems()
                    }
                case .radio:
                    self.loadPlexRadioStations(generation: generation)
                    return
                case .history:
                    self.displayItems = []
                }
                self.finishLoadIfActive(generation: generation, source: expectedSource)
            } catch is CancellationError {
            } catch where Task.isCancelled {
            } catch {
                self.setLoadErrorIfActive(error.localizedDescription, generation: generation, source: expectedSource)
            }
        }
    }

    func rebuildPlexItems() {
        switch browseMode {
        case .artists: buildArtistItems()
        case .albums: buildAlbumItems()
        case .movies: buildMovieItems()
        case .shows: buildShowItems()
        case .plists: buildPlexPlaylistItems()
        case .search: buildSearchItems()
        case .folders: displayItems = []
        case .radio, .history: break
        }
    }

    /// A Plex library was picked from the server bar. The tab is kept when it fits the library.
    func selectPlexLibrary(_ library: PlexLibrary) {
        PlexManager.shared.selectLibrary(library)
        let keepsTab = (library.isMusicLibrary && !browseMode.isVideoMode) ||
            [.plists, .radio, .search, .history].contains(browseMode)
        if !keepsTab {
            if library.isMusicLibrary {
                browseMode = .artists
            } else if library.isMovieLibrary {
                browseMode = .movies
            } else if library.isShowLibrary {
                browseMode = .shows
            }
        }
        // Playlists span the server's libraries
        plex = PlexBrowserCache(playlists: plex.playlists, playlistTracks: plex.playlistTracks)
        collapse(.plexLibrary)
        rowsReplaced()
        reloadData()
    }

    // MARK: - Artists and Albums

    /// Extract an artist ID from a parentKey path, handling various Plex server formats:
    /// - "/library/metadata/12345" → "12345"
    /// - "/library/metadata/12345/children" → "12345"
    /// - "12345" (bare ID) → "12345"
    private func extractArtistId(from parentKey: String) -> String? {
        if parentKey.contains("/library/metadata/") {
            let stripped = parentKey.replacingOccurrences(of: "/library/metadata/", with: "")
            return stripped.split(separator: "/").first.map(String.init)
        }
        let trimmed = parentKey.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed.allSatisfy({ $0.isNumber }) { return trimmed }
        NSLog("LibraryBrowserModel: Warning - unrecognized parentKey format: %@", parentKey)
        return nil
    }

    /// Album counts per artist, and albums per same-name artist group, from the cached albums.
    private func buildArtistAlbumCounts() {
        plex.artistAlbumCounts.removeAll()
        plex.artistGroupsByName = Dictionary(grouping: plex.artists, by: { PlexIdentity.normalizedName($0.title) })
        plex.albumsByArtistGroupKey.removeAll()
        plex.albumCountsByArtistGroupKey.removeAll()

        var artistsById: [String: PlexArtist] = [:]
        for artist in plex.artists {
            artistsById[artist.id] = artist
        }
        for album in plex.albums {
            if let parentKey = album.parentKey, let artistId = extractArtistId(from: parentKey) {
                plex.artistAlbumCounts[artistId, default: 0] += 1
                if let artist = artistsById[artistId] {
                    plex.albumsByArtistGroupKey[plexArtistGroupKey(for: artist), default: []].append(album)
                }
            }
        }

        for (groupKey, albums) in plex.albumsByArtistGroupKey {
            let deduplicated = PlexIdentity.unique(albums)
            plex.albumsByArtistGroupKey[groupKey] = deduplicated
            plex.albumCountsByArtistGroupKey[groupKey] = deduplicated.count
        }
    }

    private func buildArtistItems() {
        if plex.artistGroupsByName.isEmpty && !plex.artists.isEmpty {
            buildArtistAlbumCounts()
        }
        var rows: [LibraryBrowserItem] = []
        for artist in sortPlexArtists(uniquePlexArtistsByName(plex.artists)) {
            let groupKey = plexArtistGroupKey(for: artist)
            // Prefer the albums fetched on expand, then the counted albums
            let info: String?
            if let albums = plex.artistAlbums[groupKey] {
                info = LibraryBrowserItem.countLabel(albums.count, "album")
            } else if let count = plexArtistAlbumCount(for: artist), count > 0 {
                info = LibraryBrowserItem.countLabel(count, "album")
            } else {
                info = nil
            }
            rows.append(LibraryBrowserItem(id: groupKey, title: artist.title, info: info, indentLevel: 0, hasChildren: true, type: .artist(artist)))
            guard isExpanded(.plexArtist, groupKey), let albums = plex.artistAlbums[groupKey] else { continue }
            rows += plexAlbumRows(albums, indentLevel: 1)
        }
        displayItems = rows
    }

    /// Albums under an artist, each with its tracks when expanded.
    private func plexAlbumRows(_ albums: [PlexAlbum], indentLevel: Int) -> [LibraryBrowserItem] {
        sortPlexAlbums(albums).flatMap { album in
            [LibraryBrowserItem(id: album.id, title: album.title, info: album.year.map { String($0) }, indentLevel: indentLevel, hasChildren: true, type: .album(album))]
                + plexTrackRows(ofAlbum: album, indentLevel: indentLevel + 1)
        }
    }

    /// An expanded album's tracks by disc ('parentIndex') then track number ('index').
    private func plexTrackRows(ofAlbum album: PlexAlbum, indentLevel: Int) -> [LibraryBrowserItem] {
        guard isExpanded(.plexAlbum, album.id), let tracks = plex.albumTracks[album.id] else { return [] }
        return discOrdered(tracks, disc: \.parentIndex, track: \.index).map { track in
            LibraryBrowserItem(id: track.id, title: track.title, info: track.formattedDuration, indentLevel: indentLevel, hasChildren: false, type: .track(track))
        }
    }

    private func buildAlbumItems() {
        displayItems = sortPlexAlbums(plex.albums).flatMap { album in
            [LibraryBrowserItem(id: album.id, title: "\(album.parentTitle ?? "Unknown") - \(album.title)", info: album.year.map { String($0) }, indentLevel: 0, hasChildren: true, type: .album(album))]
                + plexTrackRows(ofAlbum: album, indentLevel: 1)
        }
    }

    // MARK: - Movies and TV

    private func buildMovieItems() {
        displayItems = plex.movies.map { plexMovieItem($0, indentLevel: 0) }
    }

    private func plexMovieItem(_ movie: PlexMovie, indentLevel: Int) -> LibraryBrowserItem {
        let info = [movie.year.map { String($0) }, movie.formattedDuration].compactMap { $0 }.joined(separator: " • ")
        return LibraryBrowserItem(id: movie.id, title: movie.title, info: info.isEmpty ? nil : info, indentLevel: indentLevel, hasChildren: false, type: .movie(movie))
    }

    private func buildShowItems() {
        displayItems = plex.shows.flatMap { show in
            let info = [show.year.map { String($0) }, "\(show.childCount) seasons"].compactMap { $0 }.joined(separator: " • ")
            return [LibraryBrowserItem(id: show.id, title: show.title, info: info, indentLevel: 0, hasChildren: true, type: .show(show))]
                + plexSeasonRows(of: show, indentLevel: 1)
        }
    }

    /// An expanded show's seasons, each with its episodes when expanded.
    private func plexSeasonRows(of show: PlexShow, indentLevel: Int) -> [LibraryBrowserItem] {
        guard isExpanded(.plexShow, show.id), let seasons = plex.showSeasons[show.id] else { return [] }
        var rows: [LibraryBrowserItem] = []
        for season in seasons {
            rows.append(LibraryBrowserItem(id: season.id, title: season.title, info: "\(season.leafCount) episodes", indentLevel: indentLevel, hasChildren: true, type: .season(season)))
            guard isExpanded(.plexSeason, season.id), let episodes = plex.seasonEpisodes[season.id] else { continue }
            for episode in episodes {
                rows.append(LibraryBrowserItem(id: episode.id, title: "\(episode.episodeIdentifier) - \(episode.title)", info: episode.formattedDuration, indentLevel: indentLevel + 1, hasChildren: false, type: .episode(episode)))
            }
        }
        return rows
    }

    // MARK: - Playlists

    private func buildPlexPlaylistItems() {
        var rows: [LibraryBrowserItem] = []
        // Audio playlists only, de-duplicated by title (Plex sometimes returns duplicates with different IDs)
        var seenTitles = Set<String>()
        let playlists = plex.playlists.filter { $0.isAudioPlaylist && seenTitles.insert($0.title.lowercased()).inserted }
        for playlist in menuSorted(playlists, name: \.title, created: { $0.addedAt }) {
            rows.append(LibraryBrowserItem(id: playlist.id, title: playlist.title, info: LibraryBrowserItem.countLabel(playlist.leafCount, "track"), indentLevel: 0, hasChildren: playlist.leafCount > 0, type: .plexPlaylist(playlist)))
            guard isExpanded(.plexPlaylist, playlist.id), let tracks = plex.playlistTracks[playlist.id] else { continue }
            for track in tracks {
                rows.append(LibraryBrowserItem(id: "\(playlist.id)-\(track.id)", title: track.title, info: track.formattedDuration, indentLevel: 1, hasChildren: false, type: .track(track)))
            }
        }
        displayItems = rows
    }

    // MARK: - Search

    /// The normalized name a search result's artist is de-duplicated and expanded by.
    static func plexSearchArtistKey(_ artist: PlexArtist) -> String {
        artist.title.lowercased().trimmingCharacters(in: .whitespaces)
    }

    private func buildSearchItems() {
        guard let results = plex.searchResults else { displayItems = []; return }

        // One row per name, keeping the artist with the most albums
        var artistsByName: [String: PlexArtist] = [:]
        for artist in results.artists {
            let key = Self.plexSearchArtistKey(artist)
            if let existing = artistsByName[key], existing.albumCount >= artist.albumCount { continue }
            artistsByName[key] = artist
        }
        var rows = searchSection("artists", "Artists", sortPlexArtists(Array(artistsByName.values))) { artist in
            let key = Self.plexSearchArtistKey(artist)
            let info = artist.albumCount > 0 ? LibraryBrowserItem.countLabel(artist.albumCount, "album") : nil
            let row = LibraryBrowserItem(id: artist.id, title: artist.title, info: info, indentLevel: 1, hasChildren: true, type: .artist(artist))
            guard isExpanded(.plexSearchArtist, key), let albums = plex.artistAlbumsByName[key] else { return [row] }
            return [row] + plexAlbumRows(albums, indentLevel: 2)
        }
        rows += searchSection("albums", "Albums", sortPlexAlbums(uniqueById(results.albums))) { album in
            [LibraryBrowserItem(id: album.id, title: "\(album.parentTitle ?? "") - \(album.title)", info: album.year.map { String($0) }, indentLevel: 1, hasChildren: true, type: .album(album))]
                + plexTrackRows(ofAlbum: album, indentLevel: 2)
        }
        rows += searchSection("tracks", "Tracks", menuSorted(uniqueById(results.tracks), name: \.title, created: { $0.addedAt })) { track in
            [LibraryBrowserItem(id: track.id, title: "\(track.grandparentTitle ?? "") - \(track.title)", info: track.formattedDuration, indentLevel: 1, hasChildren: false, type: .track(track))]
        }
        rows += searchSection("movies", "Movies", uniqueById(results.movies)) { [plexMovieItem($0, indentLevel: 1)] }
        rows += searchSection("shows", "TV Shows", uniqueById(results.shows)) { show in
            [LibraryBrowserItem(id: show.id, title: show.title, info: "\(show.childCount) seasons", indentLevel: 1, hasChildren: true, type: .show(show))]
                + plexSeasonRows(of: show, indentLevel: 2)
        }
        rows += searchSection("episodes", "Episodes", uniqueById(results.episodes)) { episode in
            [LibraryBrowserItem(id: episode.id, title: "\(episode.grandparentTitle ?? "") - \(episode.episodeIdentifier) - \(episode.title)", info: episode.formattedDuration, indentLevel: 1, hasChildren: false, type: .episode(episode))]
        }
        displayItems = rows
    }

    /// The first of each id, in order: search returns some items more than once.
    private func uniqueById<Item: Identifiable>(_ items: [Item]) -> [Item] where Item.ID == String {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Same-name artist groups

    func plexArtistGroupKey(for artist: PlexArtist) -> String {
        "plex-artist-\(PlexIdentity.normalizedName(artist.title))"
    }

    private func uniquePlexArtistsByName(_ artists: [PlexArtist]) -> [PlexArtist] {
        var groups = Dictionary(grouping: artists, by: { PlexIdentity.normalizedName($0.title) })
        if artists.count == plex.artists.count && !plex.artistGroupsByName.isEmpty {
            groups = plex.artistGroupsByName
        }
        return groups.values.compactMap { group in
            // Highest albumCount wins; ties broken by smallest id for a deterministic representative.
            group.max { lhs, rhs in
                lhs.albumCount != rhs.albumCount ? lhs.albumCount < rhs.albumCount : lhs.id > rhs.id
            }
        }
    }

    /// The same-name Plex artists a grouped artist row stands for.
    func plexArtistGroup(for artist: PlexArtist) -> [PlexArtist] {
        guard browseMode != .search else { return [artist] }
        let key = PlexIdentity.normalizedName(artist.title)
        let matches = plex.artistGroupsByName[key] ?? plex.artists.filter { PlexIdentity.normalizedName($0.title) == key }
        return matches.isEmpty ? [artist] : matches
    }

    /// The albums counted for a grouped artist row from the loaded albums; empty before they load.
    func plexCountedAlbums(for artist: PlexArtist) -> [PlexAlbum] {
        plex.albumsByArtistGroupKey[plexArtistGroupKey(for: artist)] ?? []
    }

    func plexArtistAlbumCount(for artist: PlexArtist) -> Int? {
        if let count = plex.albumCountsByArtistGroupKey[plexArtistGroupKey(for: artist)], count > 0 {
            return count
        }
        var count = 0
        var foundCount = false
        for member in plexArtistGroup(for: artist) {
            if let cached = plex.artistAlbumCounts[member.id], cached > 0 {
                count += cached
                foundCount = true
            } else if member.albumCount > 0 {
                count += member.albumCount
                foundCount = true
            }
        }
        return foundCount ? count : nil
    }

    func fetchAlbumsForPlexArtistGroup(_ artist: PlexArtist) async throws -> [PlexAlbum] {
        let cached = plexCountedAlbums(for: artist)
        if !cached.isEmpty { return cached }
        return try await LibraryPlayable.plexAlbums(ofArtistGroup: plexArtistGroup(for: artist))
    }

    // MARK: - Sorting

    /// Artists have no year, so the year sorts order them by name.
    private func sortPlexArtists(_ artists: [PlexArtist]) -> [PlexArtist] {
        menuSorted(artists, name: \.title, created: { $0.addedAt })
    }

    private func sortPlexAlbums(_ albums: [PlexAlbum]) -> [PlexAlbum] {
        menuSorted(albums, name: \.title, created: { $0.addedAt }, year: { $0.year })
    }

    // MARK: - Radio

    func loadPlexRadioStations(generation: Int) {
        guard case .plex = currentSource else { return }
        let expectedSource = currentSource
        loadState = .loading
        radioLoadTask?.cancel()
        radioLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let genres = await PlexManager.shared.getGenres()
            guard !Task.isCancelled,
                  self.isLoadContextActive(generation, source: expectedSource),
                  self.browseMode == .radio else { return }
            self.buildPlexRadioStationItems(genres: genres)
            self.endLoading()
            self.radioLoadTask = nil
        }
    }

    private func buildPlexRadioStationItems(genres: [String]) {
        NSLog("LibraryBrowserModel: Building Plex radio station list with %d genres", genres.count)
#if DEBUG
        let hasJazz = genres.contains { $0.localizedCaseInsensitiveCompare("Jazz") == .orderedSame }
        NSLog("LibraryBrowserModel: Plex radio station genres contain Jazz=%@; genres=%@",
              hasJazz ? "yes" : "no", genres.joined(separator: ", "))
#endif
        var stations: [(id: String, title: String, info: String, type: PlexRadioType)] = [
            ("plex-radio-library", "Library Radio", "Library", .libraryRadio),
            ("plex-radio-library-sonic", "Library Radio (Sonic)", "Library", .libraryRadioSonic),
            ("plex-radio-hits", "Only the Hits", "Popularity", .hitsRadio),
            ("plex-radio-hits-sonic", "Only the Hits (Sonic)", "Popularity", .hitsRadioSonic),
            ("plex-radio-deepcuts", "Deep Cuts", "Popularity", .deepCutsRadio),
            ("plex-radio-deepcuts-sonic", "Deep Cuts (Sonic)", "Popularity", .deepCutsRadioSonic),
        ]
        for station in RadioConfig.ratingStations {
            stations.append(("plex-radio-rating-\(station.minRating)", "\(station.name) Radio", "My Ratings",
                             .ratingRadio(minRating: station.minRating, name: station.name)))
            stations.append(("plex-radio-rating-\(station.minRating)-sonic", "\(station.name) Radio (Sonic)", "My Ratings",
                             .ratingRadioSonic(minRating: station.minRating, name: station.name)))
        }
        for genre in genres {
            stations.append(("plex-radio-genre-\(genre)", "\(genre) Radio", "Genre", .genreRadio(genre)))
            stations.append(("plex-radio-genre-\(genre)-sonic", "\(genre) Radio (Sonic)", "Genre", .genreRadioSonic(genre)))
        }
        for decade in RadioConfig.decades {
            stations.append(("plex-radio-decade-\(decade.name)", "\(decade.name) Radio", "Decade",
                             .decadeRadio(start: decade.start, end: decade.end, name: decade.name)))
            stations.append(("plex-radio-decade-\(decade.name)-sonic", "\(decade.name) Radio (Sonic)", "Decade",
                             .decadeRadioSonic(start: decade.start, end: decade.end, name: decade.name)))
        }
        displayItems = stations.map {
            LibraryBrowserItem(id: $0.id, title: $0.title, info: $0.info, indentLevel: 0, hasChildren: false, type: .plexRadioStation($0.type))
        }
    }
}
