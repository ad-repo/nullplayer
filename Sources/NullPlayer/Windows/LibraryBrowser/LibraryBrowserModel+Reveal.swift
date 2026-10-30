import Foundation
import NullPlayerCore

/// Opening the Artists tab on one artist: from a search result, or from a track's Go to Artist and
/// Go to Album, which also expands the artist and selects the album under it.
extension LibraryBrowserModel {

    /// The rows a reveal selects.
    struct RevealTarget {
        /// A row, matched by title first, then id: a server's search-result ids can differ from its
        /// Artists-tab rows.
        struct Row {
            /// Nil matches by title alone.
            var id: String?
            var name: String
        }

        var artist: Row
        var album: Row? = nil
    }

    /// A reveal waiting for the Artists tab's rows.
    enum PendingReveal {
        /// Waiting for the Artists load `reveal` started; `unfiltered` when it fetched every artist.
        case artist(RevealTarget, unfiltered: Bool)
        /// The artist was expanded to show the album: waiting for the rebuild that expand makes,
        /// now or once its albums arrive (or it collapses, when they fail to).
        case album(RevealTarget)
    }

    /// A search result's artist row was activated: open the Artists tab on that artist.
    func navigateToArtistFromSearch(id: String, name: String = "") {
        reveal(RevealTarget(artist: .init(id: id, name: name.isEmpty ? id.replacingOccurrences(of: "local-artist-", with: "") : name)),
               unfiltered: true)
    }

    /// Open the Artists tab, and select the target's artist, or its album under the expanded artist.
    /// A row's own artist is in the tab's cached rows; `unfiltered` refetches every artist, for one
    /// found outside the selected folder or library (a search result, or a playlist entry's).
    func reveal(_ target: RevealTarget, unfiltered: Bool = false) {
        if unfiltered {
            plex.artists.removeAll()
            subsonic.artists.removeAll()
            jellyfin.artists.removeAll()
            emby.artists.removeAll()
        }
        // Switch first so the page offset is computed under the Artists tab's own sort, and since
        // a tab change drops any pending reveal.
        browseMode = .artists
        pendingReveal = .artist(target, unfiltered: unfiltered)
        if currentSource.isLocal,
           let artistOffset = MediaLibraryStore.shared.artistOffset(named: target.artist.name, sort: currentSort) {
            localArtistPageOffset = (artistOffset / localPageSize) * localPageSize
        }
        loadDataForCurrentMode()
    }

    /// After a load or rebuild: select the row a reveal is looking for. An album expands its
    /// artist first, and the rebuild that makes comes back here.
    func resolvePendingReveal() {
        guard let pending = pendingReveal else { return }
        switch pending {
        case .artist(let target, let unfiltered):
            guard let artistIndex = index(of: target.artist, in: displayItems.indices, where: \.isArtist) else {
                // A rebuild while the reveal's own load still runs: wait for that load.
                guard loadState != .loading else { return }
                // The library's Artists tab is never filtered, so only a server retries unfiltered.
                if unfiltered || currentSource.isLocal { finishReveal(at: nil) } else { reveal(target, unfiltered: true) }
                return
            }
            guard target.album != nil else { return finishReveal(at: artistIndex) }
            let artistRow = displayItems[artistIndex]
            pendingReveal = .album(target)
            if isExpanded(artistRow) { resolvePendingReveal() } else { toggleExpand(artistRow) }

        case .album(let target):
            guard let artistIndex = index(of: target.artist, in: displayItems.indices, where: \.isArtist) else {
                return finishReveal(at: nil)
            }
            let indent = displayItems[artistIndex].indentLevel
            let children = displayItems.indices.dropFirst(artistIndex + 1).prefix { displayItems[$0].indentLevel > indent }
            let albumIndex = target.album.flatMap { index(of: $0, in: children, where: \.isAlbumItem) }
            finishReveal(at: albumIndex ?? artistIndex)
        }
    }

    private func finishReveal(at index: Int?) {
        pendingReveal = nil
        guard let index else { return }
        selectedIndices = [index]
        onChange?(.reveal(index))
    }

    private func index(of row: RevealTarget.Row, in indices: some Collection<Int>,
                       where isKind: (LibraryBrowserItem.ItemType) -> Bool) -> Int? {
        let candidates = indices.filter { isKind(displayItems[$0].type) }
        return candidates.first { !row.name.isEmpty && displayItems[$0].title.caseInsensitiveCompare(row.name) == .orderedSame }
            ?? row.id.flatMap { id in candidates.first { displayItems[$0].id == id } }
    }

    // MARK: - A row's artist and album

    /// Where a track row's artist and album, or an album row's artist, sit in the Artists tab; nil
    /// for any other row, or one that names no artist. A track's album is left out when it names none.
    func revealTarget(of item: LibraryBrowserItem) -> RevealTarget? {
        switch item.type {
        case .localAlbum(let album): return localRevealTarget(album)
        case .album(let album): return nonEmpty(album.parentTitle).map { RevealTarget(artist: .init(id: nil, name: $0)) }
        case .subsonicAlbum(let album): return serverRevealTarget(album)
        case .jellyfinAlbum(let album): return serverRevealTarget(album)
        case .embyAlbum(let album): return serverRevealTarget(album)
        case .localTrack(let track): return localRevealTarget(track)
        // A playlist entry the library has not scanned has no Artists-tab row.
        case .localPlaylistTrack(let track): return MediaLibraryStore.shared.track(forURL: track.url).flatMap(localRevealTarget)
        case .track(let track): return plexRevealTarget(track)
        case .subsonicTrack(let song): return serverRevealTarget(song)
        case .jellyfinTrack(let song): return serverRevealTarget(song)
        case .embyTrack(let song): return serverRevealTarget(song)
        default: return nil
        }
    }

    /// The library files a track under its first album artist.
    private func localRevealTarget(_ track: LibraryTrack) -> RevealTarget? {
        guard let artist = MediaLibraryStore.albumArtistNames(of: track)?.first else { return nil }
        return RevealTarget(artist: .init(id: "local-artist-\(artist)", name: artist),
                            album: nonEmpty(track.album).map { .init(id: "local-album-\(MediaLibraryStore.albumId(of: track))", name: $0) })
    }

    /// A search album's artist is its album artist or artist; elsewhere only its album artist,
    /// so an album without one asks its first track.
    private func localRevealTarget(_ album: Album) -> RevealTarget? {
        let artist = album.artist.flatMap { ArtistSplitter.split($0, isAlbumArtist: true).first?.name }
            ?? MediaLibraryStore.shared.tracksForAlbum(album.id).first.flatMap { MediaLibraryStore.albumArtistNames(of: $0)?.first }
        return artist.map { RevealTarget(artist: .init(id: "local-artist-\($0)", name: $0)) }
    }

    /// Plex keys a track's album by path ("/library/metadata/<ratingKey>"); its artist matches by
    /// title, as Plex groups same-name artists under one row.
    private func plexRevealTarget(_ track: PlexTrack) -> RevealTarget? {
        guard let artist = nonEmpty(track.grandparentTitle) else { return nil }
        return RevealTarget(artist: .init(id: nil, name: artist),
                            album: nonEmpty(track.parentTitle).map { .init(id: track.parentKey.map { ($0 as NSString).lastPathComponent }, name: $0) })
    }

    private func serverRevealTarget(_ song: some BrowsableSong) -> RevealTarget? {
        guard let artist = nonEmpty(song.artist) else { return nil }
        return RevealTarget(artist: .init(id: song.artistId, name: artist),
                            album: nonEmpty(song.album).map { .init(id: song.albumId, name: $0) })
    }

    private func serverRevealTarget(_ album: some BrowsableAlbum) -> RevealTarget? {
        nonEmpty(album.artist).map { RevealTarget(artist: .init(id: album.artistId, name: $0)) }
    }

    private func nonEmpty(_ text: String?) -> String? {
        text.flatMap { $0.isEmpty ? nil : $0 }
    }
}
