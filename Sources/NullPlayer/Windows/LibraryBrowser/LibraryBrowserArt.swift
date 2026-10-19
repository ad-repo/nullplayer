import AppKit
import NullPlayerCore

/// A browser's art: each row's (for its thumbnail and Flow / Tiles), and the background art drawn
/// behind the list — the playing track's, else the selected row's, else the browsed library's.
/// Each view owns one beside its model.
@MainActor
final class LibraryBrowserArt: NSObject {
    private let model: LibraryBrowserModel
    /// Whether the view draws background art; while it does not, none is loaded or kept.
    private let isBackgroundEnabled: () -> Bool

    /// The background art to draw; nil while the view draws none.
    var background: NSImage? { isBackgroundEnabled() ? loadedBackground : nil }
    private var loadedBackground: NSImage?
    /// Called when `background` changes.
    var onBackgroundChange: (() -> Void)?
    /// The track `background` shows; nil when it shows a selected or browsed row.
    private var backgroundTrackId: UUID?
    private var backgroundTask: Task<Void, Never>?
    /// Bumped by every background request, so a load that finishes after a newer one was asked for
    /// is dropped.
    private var backgroundGeneration = 0

    init(model: LibraryBrowserModel, isBackgroundEnabled: @escaping () -> Bool) {
        self.model = model
        self.isBackgroundEnabled = isBackgroundEnabled
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(trackDidChange(_:)),
                                               name: .audioTrackDidChange, object: nil)
    }

    func cancel() {
        backgroundTask?.cancel()
        backgroundTask = nil
    }

    // MARK: - Rows

    /// A row as the Flow / Tiles views show it.
    func artItem(for item: LibraryBrowserItem) -> LibraryArtItem {
        let cacheKey = itemArtwork(for: item).cacheKey
        return LibraryArtItem(id: item.id, title: item.title, subtitle: item.info ?? "",
                              cachedArtwork: { cacheKey.flatMap { LibraryArtwork.cache.object(forKey: NSString(string: $0)) } },
                              art: rowThumbnailSource(for: item),
                              artAspect: item.type.isPoster ? LibraryArtItem.posterAspect : 1)
    }

    /// The art for a row's round thumbnail, or nil for rows that never carry art. Cover Flow items
    /// reuse `itemArtwork`'s loaders, keyed within the current server.
    func rowThumbnailSource(for item: LibraryBrowserItem) -> LibraryRowThumbnails.Source? {
        switch item.type {
        case .localFolder: return nil
        case .youtubeChannel(let channel): return .channel(channel)
        case .youtubeVideo(let video): return .video(video)
        case .radioStation(let station): return .radio(station)
        case .localPlaylistTrack(let track): return .localFile(track.url)
        default:
            guard item.type.isArtItem else { return nil }
            let (cacheKey, load) = itemArtwork(for: item)
            return .item(key: cacheKey ?? "item:\(item.id)", server: model.currentSource.serverId, owner: self, load: load)
        }
    }

    /// A row's artwork cache key and async loader.
    func itemArtwork(for item: LibraryBrowserItem) -> LibraryArtwork.ItemArtwork {
        func plex(_ id: String, _ thumb: String?) -> LibraryArtwork.ItemArtwork {
            guard let thumb else { return ("plex:\(id)", { nil }) }
            return ("plex:\(id)", { await LibraryArtwork.plex(thumb: thumb, cacheKey: "plex:\(id)") })
        }
        func subsonic(_ coverArt: String?) -> LibraryArtwork.ItemArtwork {
            guard let coverArt else { return (nil, { nil }) }
            return ("subsonic:\(coverArt)", { await LibraryArtwork.subsonic(coverArt: coverArt, cacheKey: "subsonic:\(coverArt)") })
        }
        /// Local art, kept in the browser's cache under `key` so Flow / Tiles can draw it at once.
        func local(_ key: String, _ resolve: @escaping () async -> NSImage?) -> LibraryArtwork.ItemArtwork {
            (key, { await LibraryArtwork.cached(key, resolve) })
        }
        func local(_ url: URL) -> LibraryArtwork.ItemArtwork {
            local("local:\(url.path)") { await LocalArtwork.image(for: url) }
        }

        switch item.type {
        case .album(let album): return plex(album.id, album.thumb)
        case .show(let show): return plex(show.id, show.thumb)
        case .season(let season): return plex(season.id, season.thumb)
        case .episode(let episode): return plex(episode.id, episode.thumb)
        case .artist(let artist): return plex(artist.id, artist.thumb)
        case .track(let track): return plex(track.id, track.thumb)
        case .movie(let movie):
            let key = "plex:\(movie.id)"
            return (key, {
                if let thumb = movie.thumb, let image = await LibraryArtwork.plex(thumb: thumb, cacheKey: key) {
                    return image
                }
                return await LibraryArtwork.moviePoster(title: movie.title, year: movie.year)
            })
        case .localAlbum(let album):
            return local("local-album:\(album.id)") { await LocalArtwork.image(forAlbum: album.id) }
        case .localArtist(let artist):
            return local("local-artist:\(artist.name)") { await LocalArtwork.image(forArtist: artist.name) }
        case .localTrack(let track): return local(track.url)
        case .localMovie(let movie): return local(movie.url)
        case .localEpisode(let episode): return local(episode.url)
        case .localShow(let show):
            guard let episode = show.seasons.first(where: { !$0.episodes.isEmpty })?.episodes.first else {
                return (nil, { nil })
            }
            return local(episode.url)
        case .localSeason(let season, _):
            guard let episode = season.episodes.first else { return (nil, { nil }) }
            return local(episode.url)
        case .subsonicAlbum(let album): return subsonic(album.coverArt)
        case .subsonicArtist(let artist): return subsonic(artist.coverArt)
        case .subsonicTrack(let song): return subsonic(song.coverArt)
        case .jellyfinAlbum(let album): return LibraryArtwork.jellyfinItem(album.artworkItemId)
        case .jellyfinArtist(let artist): return LibraryArtwork.jellyfinItem(artist.artworkItemId)
        case .jellyfinTrack(let song): return LibraryArtwork.jellyfinItem(song.artworkItemId)
        case .jellyfinMovie(let movie): return LibraryArtwork.jellyfinItem(movie.artworkItemId)
        case .jellyfinShow(let show): return LibraryArtwork.jellyfinItem(show.artworkItemId)
        case .jellyfinSeason(let season): return LibraryArtwork.jellyfinItem(season.artworkItemId)
        case .jellyfinEpisode(let episode): return LibraryArtwork.jellyfinItem(episode.artworkItemId)
        case .embyAlbum(let album): return LibraryArtwork.embyItem(album.artworkItemId)
        case .embyArtist(let artist): return LibraryArtwork.embyItem(artist.artworkItemId)
        case .embyTrack(let song): return LibraryArtwork.embyItem(song.artworkItemId)
        case .embyMovie(let movie): return LibraryArtwork.embyItem(movie.artworkItemId)
        case .embyShow(let show): return LibraryArtwork.embyItem(show.artworkItemId)
        case .embySeason(let season): return LibraryArtwork.embyItem(season.artworkItemId)
        case .embyEpisode(let episode): return LibraryArtwork.embyItem(episode.artworkItemId)
        default:
            return (nil, { nil })
        }
    }

    /// A local track's, album's or artist's art, else an album cover found on the web.
    private func localArtworkOrWeb(_ item: LibraryBrowserItem) async -> NSImage? {
        if let image = await itemArtwork(for: item).load() { return image }
        switch item.type {
        case .localTrack(let track):
            return await LibraryArtwork.web(artist: track.artist, album: track.album, title: track.title)
        case .localAlbum(let album):
            return await LibraryArtwork.web(artist: album.artist, album: album.name, title: nil)
        case .localArtist(let artist):
            let album = await Task.detached { MediaLibraryStore.shared.albumsForArtist(artist.name).first }.value
            return await LibraryArtwork.web(artist: artist.name, album: album?.name, title: nil)
        default:
            return nil
        }
    }

    // MARK: - Background

    @objc private func trackDidChange(_ notification: Notification) {
        showPlayingTrack(notification.userInfo?["track"] as? Track)
    }

    /// Show the playing track's art. With nothing playing, the art already shown stays.
    func showPlayingTrack(_ track: Track?) {
        guard isBackgroundEnabled() else {
            clearBackground()
            return
        }
        guard let track else {
            cancel()
            backgroundGeneration &+= 1
            backgroundTrackId = nil
            return
        }
        guard track.id != backgroundTrackId else { return }
        loadBackground(trackId: track.id, keepsNil: true) { [weak self] in
            await self?.playingTrackArtwork(track)
        }
    }

    /// Show the selected row's art, when it has any.
    func showSelection() {
        guard isBackgroundEnabled(),
              let index = model.selectedIndices.first, index < model.displayItems.count else { return }
        let item = model.displayItems[index]
        loadBackground(trackId: nil, keepsNil: false) { [weak self] in
            await self?.selectionArtwork(item)
        }
    }

    /// With nothing playing, show the first art found among the browsed local rows.
    func showBrowsedLibrary() {
        guard model.currentSource.isLocal, isBackgroundEnabled() else { return }
        if let track = WindowManager.shared.audioEngine.currentTrack {
            showPlayingTrack(track)
            return
        }
        let items = model.displayItems.filter {
            switch $0.type {
            case .localTrack, .localAlbum, .localArtist: return true
            default: return false
            }
        }
        loadBackground(trackId: nil, keepsNil: false) { [weak self] in
            for item in items {
                if let image = await self?.itemArtwork(for: item).load() { return image }
            }
            return nil
        }
    }

    /// Draw `background` faintly behind the list, fitted whole inside `rect` and centred. `flipped`
    /// is a context whose y runs top-down, as the classic view's skin coordinates do.
    func drawBackground(in context: CGContext, rect: NSRect, flipped: Bool) {
        guard let cgImage = background?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cgImage.width > 0, cgImage.height > 0 else { return }
        let scale = min(rect.width / CGFloat(cgImage.width), rect.height / CGFloat(cgImage.height))
        let size = NSSize(width: CGFloat(cgImage.width) * scale, height: CGFloat(cgImage.height) * scale)
        context.saveGState()
        context.clip(to: rect)
        context.setAlpha(0.12)
        if flipped {
            // An image draws bottom-up: flip it back upright.
            context.translateBy(x: 0, y: rect.midY * 2)
            context.scaleBy(x: 1, y: -1)
        }
        context.draw(cgImage, in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                         width: size.width, height: size.height))
        context.restoreGState()
    }

    func clearBackground() {
        cancel()
        backgroundGeneration &+= 1
        backgroundTrackId = nil
        guard loadedBackground != nil else { return }
        loadedBackground = nil
        onBackgroundChange?()
    }

    /// Load background art in place of any load in flight. A track's art replaces the background
    /// even when there is none (`keepsNil`); a row's only when it has some.
    private func loadBackground(trackId: UUID?, keepsNil: Bool, _ load: @escaping @MainActor () async -> NSImage?) {
        cancel()
        backgroundGeneration &+= 1
        let generation = backgroundGeneration
        backgroundTask = Task { [weak self] in
            let image = await load()
            guard let self, !Task.isCancelled, self.backgroundGeneration == generation else { return }
            if let trackId, WindowManager.shared.audioEngine.currentTrack?.id != trackId { return }
            guard image != nil || keepsNil else { return }
            self.loadedBackground = image
            self.backgroundTrackId = trackId
            self.onBackgroundChange?()
        }
    }

    private func playingTrackArtwork(_ track: Track) async -> NSImage? {
        if let ratingKey = track.plexRatingKey {
            if let image = await plexTrackArtwork(ratingKey: ratingKey, albumName: track.album, thumb: track.artworkThumb) {
                return image
            }
            guard track.mediaType == .video else { return nil }
            // A video's title may end in its year: "Movie Name (2023)".
            var title = track.title
            var year: Int?
            if let range = title.range(of: #"\s*\(\d{4}\)\s*$"#, options: .regularExpression) {
                year = Int(title[range].filter(\.isNumber))
                title = String(title[..<range.lowerBound])
            }
            return await LibraryArtwork.moviePoster(title: title, year: year)
        } else if let songId = track.subsonicId {
            return await subsonicTrackArtwork(songId: songId, albumName: track.album)
        } else if track.jellyfinId != nil {
            guard let itemId = track.artworkThumb else { return nil }
            return await LibraryArtwork.jellyfin(itemId: itemId)
        } else if track.embyId != nil {
            guard let itemId = track.artworkThumb else { return nil }
            return await LibraryArtwork.emby(itemId: itemId)
        } else if track.url.isFileURL {
            if let image = await LocalArtwork.image(for: track.url) { return image }
            if track.mediaType == .video { return await LibraryArtwork.moviePoster(title: track.title, year: nil) }
            return await LibraryArtwork.web(artist: track.artist, album: track.album, title: track.title)
        } else if RadioManager.shared.isActive {
            return await LibraryArtwork.radio(for: track)
        } else if let thumb = track.artworkThumb {
            return await LibraryArtwork.remote(urlString: thumb, cacheNamespace: "generic")
        }
        return nil
    }

    private func selectionArtwork(_ item: LibraryBrowserItem) async -> NSImage? {
        switch item.type {
        case .localTrack, .localAlbum, .localArtist:
            return await localArtworkOrWeb(item)
        case .subsonicPlaylist(let playlist):
            guard let coverArt = playlist.coverArt else { return nil }
            return await LibraryArtwork.subsonic(coverArt: coverArt, cacheKey: "subsonic:playlist:\(playlist.id)")
        case .plexPlaylist(let playlist):
            guard let thumb = playlist.thumb else { return nil }
            return await LibraryArtwork.plex(thumb: thumb, cacheKey: "plex:playlist:\(playlist.id)")
        case .jellyfinPlaylist(let playlist):
            return await LibraryArtwork.jellyfinItem(playlist.artworkItemId).load()
        case .embyPlaylist(let playlist):
            return await LibraryArtwork.embyItem(playlist.artworkItemId).load()
        case .radioStation(let station):
            return await LibraryArtwork.radio(for: station.toTrack(), station: station)
        case .youtubeVideo(let video):
            // A download carries its own embedded art; otherwise the 16:9 thumbnail.
            var image: NSImage?
            if let fileURL = YouTubeManager.shared.coverArtFile(for: video.videoId) {
                image = await LocalArtwork.embeddedImage(in: fileURL)
            }
            if image == nil, let thumb = video.thumbnailURL {
                image = await LibraryArtwork.remote(urlString: thumb.absoluteString, cacheNamespace: "youtube")
            }
            return image?.squareCenterCropped()
        case .youtubeChannel(let channel):
            guard let avatar = channel.avatarURL(side: 512) else { return nil }
            return await LibraryArtwork.remote(urlString: avatar.absoluteString, cacheNamespace: "youtube")?.squareCenterCropped()
        case .movie, .episode, .album, .artist, .show, .season, .track,
             .subsonicTrack, .subsonicAlbum, .subsonicArtist,
             .jellyfinTrack, .jellyfinAlbum, .jellyfinArtist, .jellyfinMovie, .jellyfinShow, .jellyfinSeason, .jellyfinEpisode,
             .embyTrack, .embyAlbum, .embyArtist, .embyMovie, .embyShow, .embySeason, .embyEpisode:
            return await itemArtwork(for: item).load()
        default:
            // Local video art is drawn during playback; folders, playlists, headers and server
            // radio stations have none.
            return nil
        }
    }

    /// A playing Plex track's art: its own thumb, else one found in the browsed albums, else the
    /// rating key's own thumb path.
    private func plexTrackArtwork(ratingKey: String, albumName: String?, thumb: String?) async -> NSImage? {
        let albums = model.plex.albums
        var thumb = thumb
        if thumb == nil, let track = model.plex.albumTracks.values.lazy.compactMap({ $0.first { $0.id == ratingKey } }).first {
            thumb = track.thumb
        }
        if thumb == nil { thumb = albums.first { $0.id == ratingKey }?.thumb }
        if thumb == nil, let albumName, !albumName.isEmpty {
            thumb = albums.first { $0.title.lowercased() == albumName.lowercased() }?.thumb
        }
        return await LibraryArtwork.plex(thumb: thumb ?? "/library/metadata/\(ratingKey)/thumb", cacheKey: "plex:\(ratingKey)")
    }

    /// A playing Subsonic song's art: its cover in the browsed albums, else its album's by name,
    /// else the song id itself (which some servers accept).
    private func subsonicTrackArtwork(songId: String, albumName: String?) async -> NSImage? {
        var coverArt: String?
        if let song = model.subsonic.albumSongs.values.lazy.compactMap({ $0.first { $0.id == songId } }).first {
            coverArt = song.coverArt
        }
        if coverArt == nil, let albumName {
            coverArt = model.subsonic.albums.first { $0.name == albumName }?.coverArt
        }
        return await LibraryArtwork.subsonic(coverArt: coverArt ?? songId, cacheKey: "subsonic:\(songId)")
    }
}
