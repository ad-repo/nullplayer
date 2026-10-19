import AppKit
import NullPlayerCore

/// The media servers' row actions: Plex radio, View Online and casting, server ratings, and a
/// server song's Play Album / Play All by Artist.
extension LibraryBrowserActions {

    // MARK: - Plex radio

    /// Start Track/Album/Artist Radio: tracks like the seed replace the queue.
    func startPlexRadio(_ tracks: @escaping @MainActor () async -> [Track]) {
        Task { @MainActor in
            let tracks = await tracks()
            if !tracks.isEmpty { WindowManager.shared.audioEngine.loadTracks(tracks) }
        }
    }

    // MARK: - View Online

    /// IMDB, TMDB and Rotten Tomatoes for a Plex movie, show or episode. A link whose id the row
    /// lacks fetches the item's details first, and falls back to a search.
    private func viewOnlineItem(imdb: @escaping @MainActor () async -> URL?,
                        tmdb: @escaping @MainActor () async -> URL?,
                        rottenTomatoes: URL?) -> NSMenuItem {
        let menu = NSMenu()
        menu.addItem(menuItem("IMDB") { Self.open(imdb) })
        menu.addItem(menuItem("TMDB") { Self.open(tmdb) })
        menu.addItem(menuItem("Rotten Tomatoes") { Self.open { rottenTomatoes } })
        return submenuItem("View Online", menu)
    }

    private static func open(_ url: @escaping @MainActor () async -> URL?) {
        Task { @MainActor in
            if let url = await url() { NSWorkspace.shared.open(url) }
        }
    }

    func viewOnlineItem(for movie: PlexMovie) -> NSMenuItem {
        let detailed = { (try? await PlexManager.shared.fetchMovieDetails(movieID: movie.id)) ?? movie }
        return viewOnlineItem(imdb: { (movie.imdbId != nil ? movie : await detailed()).imdbURL },
                              tmdb: { (movie.tmdbId != nil ? movie : await detailed()).tmdbURL },
                              rottenTomatoes: movie.rottenTomatoesSearchURL)
    }

    func viewOnlineItem(for show: PlexShow) -> NSMenuItem {
        let detailed = { (try? await PlexManager.shared.fetchShowDetails(showID: show.id)) ?? show }
        return viewOnlineItem(imdb: { (show.imdbId != nil ? show : await detailed()).imdbURL },
                              tmdb: { (show.tmdbId != nil ? show : await detailed()).tmdbURL },
                              rottenTomatoes: show.rottenTomatoesSearchURL)
    }

    func viewOnlineItem(for episode: PlexEpisode) -> NSMenuItem {
        let detailed = { (try? await PlexManager.shared.fetchEpisodeDetails(episodeID: episode.id)) ?? episode }
        // Episodes have no TMDB page of their own: search for the show.
        return viewOnlineItem(imdb: { (episode.imdbId != nil ? episode : await detailed()).imdbURL },
                              tmdb: { episode.tmdbSearchURL },
                              rottenTomatoes: episode.rottenTomatoesSearchURL)
    }

    // MARK: - Casting

    /// Cast to… with one item per video-capable device; nil when there is none.
    func castItem(_ cast: @escaping @MainActor (CastDevice) async throws -> Void) -> NSMenuItem? {
        let devices = CastManager.shared.videoCapableDevices
        guard !devices.isEmpty else { return nil }
        let menu = NSMenu()
        for device in devices {
            menu.addItem(menuItem(device.name) {
                guard !WindowManager.shared.isVideoCastingActive else {
                    Self.warn("Already Casting", "Stop the current cast before starting a new one.")
                    return
                }
                Task { @MainActor in
                    do {
                        try await cast(device)
                    } catch {
                        Self.warn("Cast Failed", error.localizedDescription.redactingSensitiveURLQueryItems)
                    }
                }
            })
        }
        return submenuItem("Cast to...", menu)
    }

    // MARK: - Rating

    /// A Rate submenu: one to five stars, then Clear Rating. `rate` gets the stars, 0 to clear.
    func rateItem(_ rate: @escaping @MainActor (Int) -> Void) -> NSMenuItem {
        let menu = NSMenu(title: "Rate")
        let gold = host.ratingStarColor()
        for stars in 1...5 {
            let label = String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
            let item = menuItem(label) { rate(stars) }
            item.attributedTitle = Self.starTitle(label, gold: gold)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Clear Rating") { rate(0) })
        return submenuItem("Rate", menu)
    }

    private static func starTitle(_ label: String, gold: NSColor) -> NSAttributedString {
        let title = NSMutableAttributedString(string: label, attributes: [.font: NSFont.menuFont(ofSize: 0),
                                                                          .foregroundColor: NSColor.secondaryLabelColor])
        for (i, ch) in label.enumerated() where ch == "★" {
            title.addAttribute(.foregroundColor, value: gold, range: NSRange(location: i, length: 1))
        }
        return title
    }

    /// Plex rates on 0–10.
    func ratePlex(_ ratingKey: String, stars: Int) {
        let rating = stars > 0 ? stars * 2 : nil
        rate("Plex", { try await PlexManager.shared.serverClient?.rateItem(ratingKey: ratingKey, rating: rating) }) { type in
            guard case .track(var track) = type, track.id == ratingKey else { return nil }
            track.userRating = rating.map(Double.init)
            return .track(track)
        }
    }

    /// Subsonic rates on 1–5.
    func rateSubsonic(_ songId: String, stars: Int) {
        rate("Subsonic", { try await SubsonicManager.shared.setRating(songId: songId, rating: stars) }) { type in
            guard case .subsonicTrack(var song) = type, song.id == songId else { return nil }
            song.userRating = stars > 0 ? stars : nil
            return .subsonicTrack(song)
        }
    }

    /// Jellyfin rates on 0–100.
    func rateJellyfin(_ itemId: String, stars: Int) {
        let rating = stars * 20
        rate("Jellyfin", { try await JellyfinManager.shared.setRating(itemId: itemId, rating: rating) }) { type in
            guard case .jellyfinTrack(var song) = type, song.id == itemId else { return nil }
            song.userRating = rating > 0 ? rating : nil
            return .jellyfinTrack(song)
        }
    }

    /// Emby rates on 0–100.
    func rateEmby(_ itemId: String, stars: Int) {
        let rating = stars * 20
        rate("Emby", { try await EmbyManager.shared.setRating(itemId: itemId, rating: rating) }) { type in
            guard case .embyTrack(var song) = type, song.id == itemId else { return nil }
            song.userRating = rating > 0 ? rating : nil
            return .embyTrack(song)
        }
    }

    /// Send a rating to the server, then show it in the row `update` rewrites.
    private func rate(_ server: String, _ send: @escaping @MainActor () async throws -> Void,
                      update: @escaping (LibraryBrowserItem.ItemType) -> LibraryBrowserItem.ItemType?) {
        Task { @MainActor [weak self] in
            do {
                try await send()
                self?.replaceRow(update)
            } catch {
                NSLog("%@ rating failed: %@", server, error.localizedDescription.redactingSensitiveURLQueryItems)
            }
        }
    }

    /// Replace the first row `update` rewrites, so its Rating column shows a new rating.
    func replaceRow(_ update: (LibraryBrowserItem.ItemType) -> LibraryBrowserItem.ItemType?) {
        for (index, item) in model.displayItems.enumerated() {
            guard let type = update(item.type) else { continue }
            model.displayItems[index] = LibraryBrowserItem(
                id: item.id, title: item.title, info: item.info, indentLevel: item.indentLevel,
                hasChildren: item.hasChildren, type: type, titlePrefix: item.titlePrefix)
            return
        }
    }

    // MARK: - A server song's album and artist

    /// Play Album and Play All by Artist for a Subsonic, Jellyfin or Emby song. Each plays the
    /// loaded album or artist when the browser has it, else fetches it.
    private func addSongContextItems(to menu: NSMenu, albumId: String?, artistId: String?,
                             album: @escaping @MainActor (String) async throws -> [Track],
                             artist: @escaping @MainActor (String) async throws -> [Track]) {
        if let albumId { menu.addItem(menuItem("Play Album") { TrackVerb.play.run { try await album(albumId) } }) }
        if let artistId { menu.addItem(menuItem("Play All by Artist") { TrackVerb.play.run { try await artist(artistId) } }) }
    }

    func addSongContextItems(to menu: NSMenu, for song: SubsonicSong) {
        addSongContextItems(to: menu, albumId: song.albumId, artistId: song.artistId, album: { [model] id in
            if let album = model.subsonic.albums.first(where: { $0.id == id }) { return try await LibraryPlayable.subsonicAlbum(album).tracks() }
            let (_, songs) = try await SubsonicManager.shared.serverClient?.fetchAlbum(id: id) ?? (nil, [])
            return SubsonicManager.shared.convertToTracks(songs)
        }, artist: { [model] id in
            if let artist = model.subsonic.artists.first(where: { $0.id == id }) { return try await LibraryPlayable.subsonicArtist(artist).tracks() }
            return SubsonicManager.shared.convertToTracks(try await SubsonicManager.shared.search(query: song.artist ?? "").songs)
        })
    }

    func addSongContextItems(to menu: NSMenu, for song: JellyfinSong) {
        addSongContextItems(to: menu, albumId: song.albumId, artistId: song.artistId, album: { [model] id in
            if let album = model.jellyfin.albums.first(where: { $0.id == id }) { return try await LibraryPlayable.jellyfinAlbum(album).tracks() }
            let (_, songs) = try await JellyfinManager.shared.serverClient?.fetchAlbum(id: id) ?? (nil, [])
            return JellyfinManager.shared.convertToTracks(songs)
        }, artist: { [model] id in
            if let artist = model.jellyfin.artists.first(where: { $0.id == id }) { return try await LibraryPlayable.jellyfinArtist(artist).tracks() }
            return JellyfinManager.shared.convertToTracks(try await JellyfinManager.shared.search(query: song.artist ?? "").songs)
        })
    }

    func addSongContextItems(to menu: NSMenu, for song: EmbySong) {
        addSongContextItems(to: menu, albumId: song.albumId, artistId: song.artistId, album: { [model] id in
            if let album = model.emby.albums.first(where: { $0.id == id }) { return try await LibraryPlayable.embyAlbum(album).tracks() }
            let (_, songs) = try await EmbyManager.shared.serverClient?.fetchAlbum(id: id) ?? (nil, [])
            return EmbyManager.shared.convertToTracks(songs)
        }, artist: { [model] id in
            if let artist = model.emby.artists.first(where: { $0.id == id }) { return try await LibraryPlayable.embyArtist(artist).tracks() }
            return EmbyManager.shared.convertToTracks(try await EmbyManager.shared.search(query: song.artist ?? "").songs)
        })
    }
}

// MARK: - What each server radio station plays

extension PlexRadioType {
    @MainActor
    func tracks() async -> [Track] {
        let plex = PlexManager.shared
        switch self {
        case .libraryRadio: return await plex.createLibraryRadio()
        case .libraryRadioSonic: return await plex.createLibraryRadioSonic()
        case .hitsRadio: return await plex.createHitsRadio()
        case .hitsRadioSonic: return await plex.createHitsRadioSonic()
        case .deepCutsRadio: return await plex.createDeepCutsRadio()
        case .deepCutsRadioSonic: return await plex.createDeepCutsRadioSonic()
        case .genreRadio(let g): return await plex.createGenreRadio(genre: g)
        case .genreRadioSonic(let g): return await plex.createGenreRadioSonic(genre: g)
        case .decadeRadio(let s, let e, _): return await plex.createDecadeRadio(startYear: s, endYear: e)
        case .decadeRadioSonic(let s, let e, _): return await plex.createDecadeRadioSonic(startYear: s, endYear: e)
        case .ratingRadio(let r, _): return await plex.createRatingRadio(minRating: r)
        case .ratingRadioSonic(let r, _): return await plex.createRatingRadioSonic(minRating: r)
        }
    }
}

extension SubsonicRadioType {
    @MainActor
    func tracks() async -> [Track] {
        let subsonic = SubsonicManager.shared
        switch self {
        case .libraryRadio: return await subsonic.createLibraryRadio()
        case .librarySimilar: return await subsonic.createLibraryRadioSimilar()
        case .genreRadio(let g): return await subsonic.createGenreRadio(genre: g)
        case .genreSimilar(let g): return await subsonic.createGenreRadioSimilar(genre: g)
        case .decadeRadio(let s, let e, _): return await subsonic.createDecadeRadio(start: s, end: e)
        case .decadeSimilar(let s, let e, _): return await subsonic.createDecadeRadioSimilar(start: s, end: e)
        case .starredRadio: return await subsonic.createRatingRadio()
        case .starredSimilar: return await subsonic.createRatingRadioSimilar()
        }
    }
}

/// The Jellyfin and Emby managers' radio, which `InstantMixRadioType` plays from.
protocol InstantMixRadioServer {
    func createLibraryRadio(limit: Int) async -> [Track]
    func createLibraryRadioInstantMix(limit: Int) async -> [Track]
    func createGenreRadio(genre: String, limit: Int) async -> [Track]
    func createGenreRadioInstantMix(genre: String, limit: Int) async -> [Track]
    func createDecadeRadio(start: Int, end: Int, limit: Int) async -> [Track]
    func createDecadeRadioInstantMix(start: Int, end: Int, limit: Int) async -> [Track]
    func createFavoritesRadio(limit: Int) async -> [Track]
    func createFavoritesRadioInstantMix(limit: Int) async -> [Track]
}

extension JellyfinManager: InstantMixRadioServer {}
extension EmbyManager: InstantMixRadioServer {}

extension InstantMixRadioType {
    @MainActor
    func tracks(from server: some InstantMixRadioServer) async -> [Track] {
        let limit = RadioPlaybackOptions.playlistLength
        switch self {
        case .libraryRadio: return await server.createLibraryRadio(limit: limit)
        case .libraryInstantMix: return await server.createLibraryRadioInstantMix(limit: limit)
        case .genreRadio(let g): return await server.createGenreRadio(genre: g, limit: limit)
        case .genreInstantMix(let g): return await server.createGenreRadioInstantMix(genre: g, limit: limit)
        case .decadeRadio(let s, let e, _): return await server.createDecadeRadio(start: s, end: e, limit: limit)
        case .decadeInstantMix(let s, let e, _): return await server.createDecadeRadioInstantMix(start: s, end: e, limit: limit)
        case .favoritesRadio: return await server.createFavoritesRadio(limit: limit)
        case .favoritesInstantMix: return await server.createFavoritesRadioInstantMix(limit: limit)
        }
    }
}

extension LocalRadioType {
    @MainActor
    func tracks() -> [Track] {
        switch self {
        case .libraryRadio: return MediaLibrary.shared.createLocalLibraryRadio()
        case .genreRadio(let g): return MediaLibrary.shared.createLocalGenreRadio(genre: g)
        case .decadeRadio(let s, let e, _): return MediaLibrary.shared.createLocalDecadeRadio(start: s, end: e)
        }
    }
}
