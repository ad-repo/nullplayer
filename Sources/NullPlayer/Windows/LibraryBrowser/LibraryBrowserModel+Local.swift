import Foundation

/// The Local source: the media library store, paged for Artists and Albums.
extension LibraryBrowserModel {

    /// The banner under the list while a local watch folder is offline, or nil.
    var offlineBannerText: String? {
        guard currentSource.isLocal, !offlineWatchFolders.isEmpty else { return nil }
        let count = offlineWatchFolders.reduce(0) { $0 + $1.totalCount }
        let names = offlineWatchFolders.map { $0.url.lastPathComponent }.joined(separator: ", ")
        return "⚠  \"\(names)\" offline — \(count) track\(count == 1 ? "" : "s") unavailable"
    }

    /// A local track or episode whose file is on an offline volume; its row is drawn dimmed.
    func isOffline(_ item: LibraryBrowserItem) -> Bool {
        let url: URL
        switch item.type {
        case .localTrack(let track): url = track.url
        case .localEpisode(let episode): url = episode.url
        default: return false
        }
        return offlineVolumePrefixes.contains { url.path.hasPrefix($0) }
    }

    func loadLocalData() {
        loadState = .idle

        // Watch folders on volumes that are not mounted
        offlineWatchFolders = MediaLibrary.shared.watchFolderSummaries().filter { !$0.isAvailable }
        offlineVolumePrefixes = Set(offlineWatchFolders.map { $0.url.path })

        let library = MediaLibrary.shared
        let store = MediaLibraryStore.shared
        switch browseMode {
        case .artists:
            if !pendingArtistLoadUnfiltered {
                localArtistPageOffset = 0
            }
            localArtistTotal = store.artistCount()
            buildLocalArtistItems()
        case .albums:
            localAlbumPageOffset = 0
            localAlbumTotal = store.albumCount()
            buildLocalAlbumItems()
        case .folders:
            buildLocalFolderItems()
        case .search:
            buildLocalSearchItems()
        case .plists:
            refreshCachedLocalPlaylists()
            buildLocalPlaylistItems()
        case .movies:
            cachedLocalMovies = library.moviesSnapshot
            buildLocalMovieItems()
        case .shows:
            cachedLocalShows = library.allShows()
            buildLocalShowItems()
        case .radio:
            loadLocalRadioStations()
        case .history:
            displayItems = []
        }
        // Apply any active column-header sort so a fresh load matches what an expand-driven
        // rebuild produces — otherwise expanding a row would re-order the list.
        if columnSortId != nil { applyColumnSort() }
        resolvePendingArtist()
        onChange?(.loaded)
    }

    func rebuildLocalItems() {
        switch browseMode {
        case .artists: buildLocalArtistItems()
        case .albums: buildLocalAlbumItems()
        case .folders: buildLocalFolderItems()
        case .search: buildLocalSearchItems()
        case .movies: buildLocalMovieItems()
        case .shows: buildLocalShowItems()
        case .plists:
            refreshCachedLocalPlaylists()
            buildLocalPlaylistItems()
        case .radio, .history: displayItems = []
        }
    }

    /// After a tag edit: reload the local rows from scratch.
    func reloadLocalBrowserAfterMetadataEdit() {
        guard currentSource.isLocal else { return }
        clearLocalCachedData()
        displayItems.removeAll()
        rowsReplaced()
        loadLocalData()
    }

    /// After adding videos: open the local Movies tab, so they are in view.
    func showLocalMovies() {
        if !currentSource.isLocal { currentSource = .local }
        browseMode = .movies
        loadDataForCurrentMode()
    }

    // MARK: - Artists and Albums (paged)

    func buildLocalArtistItems() {
        var rows: [LibraryBrowserItem] = []
        let store = MediaLibraryStore.shared
        if localArtistPageOffset == 0 {
            localArtistLetterOffsets = store.artistLetterOffsets(sort: currentSort)
        }
        let names = store.artistNames(limit: localPageSize, offset: localArtistPageOffset, sort: currentSort)
        let albumsByArtist = store.albumsForArtistsBatch(names)
        for name in names {
            let albumSummaries = albumsByArtist[name] ?? []
            rows.append(localArtistItem(name, albumCount: albumSummaries.count, indentLevel: 0))
            guard isExpanded(.localArtist, name) else { continue }
            for summary in albumSummaries {
                let albumExpanded = isExpanded(.localAlbum, summary.id)
                let tracks = albumExpanded ? store.tracksForAlbum(summary.id) : []
                let album = Album(id: summary.id, name: summary.name, artist: summary.artist, year: summary.year, tracks: tracks)
                rows.append(LibraryBrowserItem(
                    id: "local-album-\(album.id)",
                    title: album.name,
                    info: summary.year.map { String($0) },
                    indentLevel: 1,
                    hasChildren: summary.trackCount > 0,
                    type: .localAlbum(album)
                ))
                if albumExpanded {
                    rows += localTrackRows(tracks, indentLevel: 2)
                }
            }
        }
        displayItems = rows
    }

    func buildLocalAlbumItems() {
        let store = MediaLibraryStore.shared
        if localAlbumPageOffset == 0 {
            localAlbumLetterOffsets = store.albumLetterOffsets(sort: currentSort)
        }
        let summaries = store.albumSummaries(limit: localPageSize, offset: localAlbumPageOffset, sort: currentSort)
        displayItems = summaries.flatMap { localAlbumRows($0, indentLevel: 0) }
    }

    /// Scrolled near the end of a paged tab: append the next page. Returns whether it did.
    @discardableResult
    func appendNextLocalPage() -> Bool {
        let store = MediaLibraryStore.shared
        switch browseMode {
        case .artists:
            let nextOffset = localArtistPageOffset + localPageSize
            guard nextOffset < localArtistTotal else { return false }
            localArtistPageOffset = nextOffset
            let names = store.artistNames(limit: localPageSize, offset: localArtistPageOffset, sort: currentSort)
            let albumsByArtist = store.albumsForArtistsBatch(names)
            displayItems += names.map { localArtistItem($0, albumCount: albumsByArtist[$0]?.count ?? 0, indentLevel: 0) }
            return true
        case .albums:
            let nextOffset = localAlbumPageOffset + localPageSize
            guard nextOffset < localAlbumTotal else { return false }
            localAlbumPageOffset = nextOffset
            let summaries = store.albumSummaries(limit: localPageSize, offset: localAlbumPageOffset, sort: currentSort)
            displayItems += summaries.map { localAlbumItem($0, tracks: [], indentLevel: 0) }
            return true
        default:
            return false
        }
    }

    /// An artist row: a stub `Artist`, whose albums are read when it is expanded.
    private func localArtistItem(_ name: String, albumCount: Int, indentLevel: Int) -> LibraryBrowserItem {
        LibraryBrowserItem(
            id: "local-artist-\(name)",
            title: name,
            info: LibraryBrowserItem.countLabel(albumCount, "album"),
            indentLevel: indentLevel,
            hasChildren: albumCount > 0,
            type: .localArtist(Artist(id: name, name: name, albums: []))
        )
    }

    /// An album row titled "Artist - Album".
    private func localAlbumItem(_ summary: AlbumSummary, tracks: [LibraryTrack], indentLevel: Int) -> LibraryBrowserItem {
        let album = Album(id: summary.id, name: summary.name, artist: summary.artist, year: summary.year, tracks: tracks)
        let title: String
        if let artist = summary.artist, !artist.isEmpty {
            title = "\(artist) - \(summary.name)"
        } else {
            title = summary.name
        }
        return LibraryBrowserItem(id: "local-album-\(album.id)", title: title, info: "\(summary.trackCount) tracks",
                                  indentLevel: indentLevel, hasChildren: summary.trackCount > 0, type: .localAlbum(album))
    }

    /// An album row, then its tracks when expanded.
    private func localAlbumRows(_ summary: AlbumSummary, indentLevel: Int) -> [LibraryBrowserItem] {
        let expanded = isExpanded(.localAlbum, summary.id)
        let tracks = expanded ? MediaLibraryStore.shared.tracksForAlbum(summary.id) : []
        return [localAlbumItem(summary, tracks: tracks, indentLevel: indentLevel)]
            + localTrackRows(tracks, indentLevel: indentLevel + 1)
    }

    /// An album's tracks, by disc then track number.
    private func localTrackRows(_ tracks: [LibraryTrack], indentLevel: Int) -> [LibraryBrowserItem] {
        discOrdered(tracks, disc: \.discNumber, track: \.trackNumber).map { track in
            LibraryBrowserItem(id: track.id.uuidString, title: track.title, info: track.formattedDuration,
                               indentLevel: indentLevel, hasChildren: false, type: .localTrack(track))
        }
    }

    // MARK: - Folders

    /// Build the Folders view: one off-actor depth-first walk of every *expanded* directory,
    /// then a single hop back to the main actor to assign `displayItems`. The generation guard
    /// discards a walk whose result arrives after a newer rebuild (or a mode switch) started.
    func buildLocalFolderItems() {
        localFolderBuildGeneration &+= 1
        let gen = localFolderBuildGeneration

        // Snapshot main-actor state before going off-actor (value types are Sendable)
        let expandedSnapshot = Set(expanded.lazy.filter { $0.kind == .localFolder }.map(\.id))

        // Show the loading spinner (not the empty "No folders found" state) while the
        // off-actor walk runs — matters for slow network/NAS watch folders.
        displayItems.removeAll()
        loadState = .loading

        // Cancel any walk still running from a previous (faster) click
        localFolderBuildTask?.cancel()
        localFolderBuildTask = Task.detached { [weak self] in
            // Build the ordered item list entirely off the main actor (FS enumeration + DB query)
            let items = LocalFolderTree.rows(expanded: expandedSnapshot).map(LibraryBrowserItem.init)

            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self,
                      self.localFolderBuildGeneration == gen,
                      self.currentSource.isLocal,
                      self.browseMode == .folders else { return }
                self.endLoading()
                self.displayItems = items
                self.localFolderBuildTask = nil
            }
        }
    }

    func cancelLocalFolderBuild() {
        localFolderBuildGeneration &+= 1
        localFolderBuildTask?.cancel()
        localFolderBuildTask = nil
    }

    // MARK: - Search

    func buildLocalSearchItems() {
        var rows: [LibraryBrowserItem] = []
        defer { displayItems = rows }
        guard !searchedQuery.isEmpty else { return }
        let store = MediaLibraryStore.shared

        let matchingArtistNames = store.searchArtistNames(query: searchedQuery)
        if !matchingArtistNames.isEmpty {
            rows.append(LibraryBrowserItem(id: "header-local-artists", title: "Artists (\(matchingArtistNames.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            let albumsByArtist = store.albumsForArtistsBatch(matchingArtistNames)
            rows += matchingArtistNames.map { localArtistItem($0, albumCount: albumsByArtist[$0]?.count ?? 0, indentLevel: 1) }
        }

        let matchingAlbums = store.searchAlbumSummaries(query: searchedQuery)
        if !matchingAlbums.isEmpty {
            rows.append(LibraryBrowserItem(id: "header-local-albums", title: "Albums (\(matchingAlbums.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            rows += matchingAlbums.flatMap { localAlbumRows($0, indentLevel: 1) }
        }

        let matchingTracks = store.searchTracks(query: searchedQuery, limit: 200, offset: 0)
        if !matchingTracks.isEmpty {
            rows.append(LibraryBrowserItem(id: "header-local-tracks", title: "Tracks (\(matchingTracks.count))", info: nil, indentLevel: 0, hasChildren: false, type: .header))
            rows += matchingTracks.map {
                LibraryBrowserItem(id: $0.id.uuidString, title: $0.title, info: $0.formattedDuration, indentLevel: 1, hasChildren: false, type: .localTrack($0))
            }
        }

        // YouTube channels and downloads (tracks already listed above are left out)
        rows += youtubeRows.localSearch(query: searchedQuery, excluding: Set(matchingTracks.map(\.url)))
            .map { LibraryBrowserItem($0) }
    }

    // MARK: - Playlists

    func buildLocalPlaylistItems() {
        var rows: [LibraryBrowserItem] = []
        for playlist in cachedLocalPlaylists.sorted(by: { $0.title.lowercased() < $1.title.lowercased() }) {
            let key = playlist.url.path
            let info = localPlaylistTracks[key].map { "\($0.count) tracks" }
            rows.append(LibraryBrowserItem(id: key, title: playlist.title, info: info, indentLevel: 0, hasChildren: true, type: .localPlaylist(playlist)))
            guard isExpanded(.localPlaylist, key), let tracks = localPlaylistTracks[key] else { continue }
            for track in tracks {
                rows.append(LibraryBrowserItem(id: "\(key)-\(track.url.absoluteString)", title: track.title,
                                                       info: LibraryBrowserItem.formatDuration(track.duration.map { Int($0) }),
                                                       indentLevel: 1, hasChildren: false, type: .localPlaylistTrack(track)))
            }
        }
        displayItems = rows
    }

    func refreshCachedLocalPlaylists() {
        cachedLocalPlaylists = MediaLibrary.shared.playlistsSnapshot
        let validKeys = Set(cachedLocalPlaylists.map { $0.url.path })
        localPlaylistTracks = localPlaylistTracks.filter { validKeys.contains($0.key) }
        expanded = expanded.filter { $0.kind != .localPlaylist || validKeys.contains($0.id) }
    }

    // MARK: - Movies and TV

    func buildLocalMovieItems() {
        displayItems = cachedLocalMovies
            .sorted { compareNameStrings($0.title, $1.title, ascending: true) }
            .map { movie in
                let info = [movie.year.map { String($0) }, movie.formattedDuration].compactMap { $0 }.joined(separator: " • ")
                return LibraryBrowserItem(id: movie.id.uuidString, title: movie.title, info: info.isEmpty ? nil : info,
                                          indentLevel: 0, hasChildren: false, type: .localMovie(movie))
            }
    }

    func buildLocalShowItems() {
        var rows: [LibraryBrowserItem] = []
        for show in cachedLocalShows.sorted(by: { compareNameStrings($0.title, $1.title, ascending: true) }) {
            rows.append(LibraryBrowserItem(id: "local-show-\(show.id)", title: show.title, info: LibraryBrowserItem.countLabel(show.episodeCount, "episode"),
                                                   indentLevel: 0, hasChildren: true, type: .localShow(show)))
            guard isExpanded(.localShow, show.id) else { continue }
            for season in show.seasons.sorted(by: { $0.number < $1.number }) {
                let seasonKey = Self.localSeasonKey(season, showTitle: show.title)
                rows.append(LibraryBrowserItem(id: "local-season-\(seasonKey)", title: "Season \(season.number)",
                                                       info: LibraryBrowserItem.countLabel(season.episodes.count, "episode"), indentLevel: 1,
                                                       hasChildren: true, type: .localSeason(season, showTitle: show.title)))
                guard isExpanded(.localSeason, seasonKey) else { continue }
                for episode in season.episodes.sorted(by: { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }) {
                    let title = episode.episodeNumber.map { "E\($0): \(episode.title)" } ?? episode.title
                    rows.append(LibraryBrowserItem(id: episode.id.uuidString, title: title, info: episode.formattedDuration,
                                                   indentLevel: 2, hasChildren: false, type: .localEpisode(episode)))
                }
            }
        }
        displayItems = rows
    }

    /// The expansion key of a local TV season.
    static func localSeasonKey(_ season: LocalSeason, showTitle: String) -> String {
        "\(showTitle)|\(season.number)"
    }

    // MARK: - Radio

    func loadLocalRadioStations() {
        loadState = .idle
        var rows = [LibraryBrowserItem(id: "local-radio-library", title: "Library Radio", info: "Library", indentLevel: 0, hasChildren: false, type: .localRadioStation(.libraryRadio))]
        for genre in MediaLibrary.shared.allGenres() {
            rows.append(LibraryBrowserItem(id: "local-radio-genre-\(genre)", title: "\(genre) Radio", info: "Genre", indentLevel: 0, hasChildren: false, type: .localRadioStation(.genreRadio(genre))))
        }
        for decade in RadioConfig.decades {
            rows.append(LibraryBrowserItem(id: "local-radio-decade-\(decade.name)", title: "\(decade.name) Radio", info: "Decade", indentLevel: 0, hasChildren: false, type: .localRadioStation(.decadeRadio(start: decade.start, end: decade.end, name: decade.name))))
        }
        displayItems = rows
    }
}
