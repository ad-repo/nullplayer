import AppKit
import NullPlayerCore

/// What the library browser does with its rows, and the menus that offer it, shared by the
/// classic and modern views.
///
/// Each view owns one beside its `LibraryBrowserModel`. The view maps its clicks and keys onto
/// `activate`, `run(_:on:)` and the menus built here, and pops those menus up in its own
/// coordinates; everything a menu item does is written once, here and in the
/// `LibraryBrowserActions+<Area>` files. The `host` supplies the little the actions need from the
/// view: where to present, the colours of its skin, and when to spin.
@MainActor
final class LibraryBrowserActions: NSObject {

    struct Host {
        /// The browser's view: a YouTube video's menu pops up over it.
        let view: () -> NSView
        /// Link a Plex account.
        let presentLinkSheet: () -> Void
        /// The colour of a Rate menu's filled stars.
        let ratingStarColor: () -> NSColor
        /// A YouTube download or a channel's uploads started or finished loading: `rowsAreBusy`
        /// may have changed.
        let busyChanged: () -> Void
    }

    let model: LibraryBrowserModel
    let host: Host

    /// A video row's Audio ▸ / Video ▸ menu and its downloads, which drive a per-row spinner.
    let youtubeVideos: YouTubeVideoActions

    /// A server radio station's tracks loading; a newer station replaces it.
    var radioPlayTask: Task<Void, Never>?
    /// Kept alive while their dialogs are open.
    var radioStationSheet: AddRadioStationSheet?
    var youtubeChannelSheet: AddYouTubeChannelSheet?
    /// The open tag panel of each kind; opening another of a kind closes it.
    var tagPanels: [ObjectIdentifier: NSWindow] = [:]

    init(model: LibraryBrowserModel, host: Host) {
        self.model = model
        self.host = host
        youtubeVideos = YouTubeVideoActions(search: model.youtubeSearch)
        super.init()
        youtubeVideos.onFetchesChanged = host.busyChanged
        youtubeVideos.onFilesChanged = { [weak model] in model?.rebuildCurrentModeItems() }
        NotificationCenter.default.addObserver(self, selector: #selector(channelUploadsDidChange),
                                               name: YouTubeChannelUploads.didChangeNotification, object: nil)
    }

    @objc private func channelUploadsDidChange() {
        host.busyChanged()
    }

    /// The rows show a spinner: a load, a YouTube download, or a channel's uploads loading.
    var rowsAreBusy: Bool {
        model.isLoading || youtubeVideos.hasFetchesInFlight || YouTubeChannelUploads.shared.hasFetchesInFlight
    }

    /// Drop every in-flight action before the view is torn down.
    func cancelAll() {
        radioPlayTask?.cancel(); radioPlayTask = nil
        youtubeVideos.cancel()
    }

    // MARK: - Menu items

    private struct MenuAction {
        let run: @MainActor () -> Void
    }

    /// A menu item that runs `action` when chosen.
    func menuItem(_ title: String, _ action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = MenuAction(run: action)
        return item
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        (sender.representedObject as? MenuAction)?.run()
    }

    /// A titled item that only opens `submenu`.
    func submenuItem(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    // MARK: - Playing rows

    /// Double-click and Enter: play a playable row, open a container, tune a station.
    func activate(_ item: LibraryBrowserItem) {
        switch item.type {
        case .track, .album, .plexPlaylist, .localTrack, .localAlbum, .localPlaylist, .localPlaylistTrack,
             .subsonicTrack, .subsonicAlbum, .subsonicPlaylist, .jellyfinTrack, .jellyfinAlbum, .jellyfinPlaylist,
             .embyTrack, .embyAlbum, .embyPlaylist, .movie, .episode, .localMovie, .localEpisode,
             .jellyfinMovie, .jellyfinEpisode, .embyMovie, .embyEpisode:
            run(.play, on: item)
        case .artist(let artist):
            openArtist(item, id: artist.id, name: artist.title)
        case .localArtist(let artist):
            openArtist(item, id: item.id, name: artist.name)
        case .subsonicArtist(let artist):
            openArtist(item, id: artist.id, name: artist.name)
        case .jellyfinArtist(let artist):
            openArtist(item, id: artist.id, name: artist.name)
        case .embyArtist(let artist):
            openArtist(item, id: artist.id, name: artist.name)
        case .show, .season, .localFolder, .localShow, .localSeason, .jellyfinShow, .jellyfinSeason, .embyShow, .embySeason:
            model.toggleExpand(item)
        case .radioFolder(let folder):
            if folder.hasChildren { model.toggleExpand(item) }
        case .header:
            break
        case .radioStation(let station):
            RadioManager.shared.play(station: station)
        case .youtubeChannel(let channel):
            // A search result not yet subscribed: double-click / Enter subscribes it.
            if YouTubeManager.shared.isSubscribed(channel) {
                model.toggleExpand(item)
            } else {
                model.youtubeSearch.subscribe(to: channel)
            }
        case .youtubeVideo(let video):
            youtubeVideos.activate(video, in: host.view())
        case .plexRadioStation(let radioType):
            playRadio { await radioType.tracks() }
        case .subsonicRadioStation(let radioType):
            playRadio { await radioType.tracks() }
        case .jellyfinRadioStation(let radioType):
            playRadio { await radioType.tracks(from: JellyfinManager.shared) }
        case .embyRadioStation(let radioType):
            playRadio { await radioType.tracks(from: EmbyManager.shared) }
        case .localRadioStation(let radioType):
            let tracks = radioType.tracks()
            if !tracks.isEmpty { WindowManager.shared.audioEngine.loadTracks(tracks) }
        }
    }

    /// A search result's artist opens the Artists tab on it; elsewhere it expands in place.
    private func openArtist(_ item: LibraryBrowserItem, id: String, name: String) {
        if model.browseMode == .search {
            model.navigateToArtistFromSearch(id: id, name: name)
        } else {
            model.toggleExpand(item)
        }
    }

    /// Run a play verb on the row's tracks; a row with nothing to play does nothing.
    func run(_ verb: TrackVerb, on item: LibraryBrowserItem) {
        guard let playable = playable(for: item) else { return }
        verb.run(resolver(for: playable))
    }

    /// Shift+Enter / Option+Enter: the menu's Play Next / Add to Queue on the selected row.
    func runOnSelection(_ verb: TrackVerb) {
        guard let index = model.selectedIndices.first, index < model.displayItems.count else { return }
        run(verb, on: model.displayItems[index])
    }

    /// The row's tracks for a play verb, from its menu, Enter or double-click. A server playlist is
    /// fetched behind the loading screen, which shows the error if the fetch fails.
    func resolver(for playable: LibraryPlayable) -> @MainActor () async throws -> [Track] {
        switch playable {
        case .plexPlaylist, .subsonicPlaylist, .jellyfinPlaylist, .embyPlaylist:
            return { [weak model] in
                guard let model else { throw CancellationError() }
                model.loadState = .loading
                do {
                    let tracks = try await playable.tracks()
                    model.endLoading()
                    return tracks
                } catch {
                    model.loadState = .failed("Failed to load playlist: \(error.localizedDescription.redactingSensitiveURLQueryItems)")
                    throw error
                }
            }
        default:
            return { try await playable.tracks() }
        }
    }

    /// Each of the row's items' EQ profile scopes, most specific first: a play row's own
    /// (`LibraryPlayable.eqProfileScopes`), a station's, a video's audio download. nil for none.
    func eqProfileScopes(for item: LibraryBrowserItem) -> [[EQProfileScope]]? {
        switch item.type {
        case .radioStation(let station): return [station.toTrack().eqProfileScopes]
        case .youtubeVideo: return item.audioFile.map { [[.youtubeTrack(audioFile: $0)]] }
        default: return playable(for: item)?.eqProfileScopes
        }
    }

    /// Whether the row's title draws after `∿`: read once per row per list and store revision.
    func isEQMarked(_ item: LibraryBrowserItem) -> Bool {
        let resolver = EQProfileResolver.shared
        return model.eqMarkers.marked(item.id, revision: resolver.store.revision) {
            eqProfileScopes(for: item).map(resolver.appliesProfile(toRow:)) ?? false
        }
    }

    /// The row as tracks for the play verbs; nil for a row with no basic play menu (radio,
    /// YouTube, containers that only expand).
    func playable(for item: LibraryBrowserItem) -> LibraryPlayable? {
        switch item.type {
        case .track(let t): return .plexTrack(t)
        case .album(let a): return .plexAlbum(a)
        case .artist(let a):
            return .plexArtistGroup(members: model.plexArtistGroup(for: a),
                                    albums: model.plexCountedAlbums(for: a))
        case .plexPlaylist(let p): return .plexPlaylist(p)
        case .localTrack(let t): return .localTrack(t)
        case .localAlbum(let a): return .localAlbum(a)
        case .localArtist(let a): return .localArtist(a)
        case .localFolder(let url, _): return .localFolder(url)
        case .localPlaylist(let p): return .localPlaylist(p.url)
        case .localPlaylistTrack(let t): return .tracks([t])
        case .subsonicTrack(let s): return .subsonicSong(s)
        case .subsonicAlbum(let a): return .subsonicAlbum(a)
        case .subsonicArtist(let a): return .subsonicArtist(a)
        case .subsonicPlaylist(let p): return .subsonicPlaylist(p)
        case .jellyfinTrack(let s): return .jellyfinSong(s)
        case .jellyfinAlbum(let a): return .jellyfinAlbum(a)
        case .jellyfinArtist(let a): return .jellyfinArtist(a)
        case .jellyfinPlaylist(let p): return .jellyfinPlaylist(p)
        case .embyTrack(let s): return .embySong(s)
        case .embyAlbum(let a): return .embyAlbum(a)
        case .embyArtist(let a): return .embyArtist(a)
        case .embyPlaylist(let p): return .embyPlaylist(p)
        case .movie(let m): return .plexMovie(m)
        case .episode(let e): return .plexEpisode(e)
        case .season(let s): return .plexSeason(s)
        case .show(let s): return .plexShow(s)
        case .localMovie(let m): return .localMovie(m)
        case .localEpisode(let e): return .localEpisodes([e])
        case .localSeason(let s, _): return .localEpisodes(s.episodes)
        case .localShow(let s): return .localEpisodes(s.episodes)
        case .jellyfinMovie(let m): return .jellyfinMovie(m)
        case .jellyfinEpisode(let e): return .jellyfinEpisode(e)
        case .jellyfinSeason(let s): return .jellyfinSeason(s)
        case .jellyfinShow(let s): return .jellyfinShow(s)
        case .embyMovie(let m): return .embyMovie(m)
        case .embyEpisode(let e): return .embyEpisode(e)
        case .embySeason(let s): return .embySeason(s)
        case .embyShow(let s): return .embyShow(s)
        case .header, .radioStation, .radioFolder, .youtubeChannel, .youtubeVideo, .plexRadioStation,
             .subsonicRadioStation, .jellyfinRadioStation, .embyRadioStation, .localRadioStation:
            return nil
        }
    }

    /// A server radio station: its tracks load behind the loading screen, then replace the queue.
    private func playRadio(_ tracks: @escaping @MainActor () async -> [Track]) {
        radioPlayTask?.cancel()
        model.loadState = .loading
        radioPlayTask = Task { @MainActor [weak self] in
            let tracks = await tracks()
            guard let self, !Task.isCancelled else { return }
            if !tracks.isEmpty { WindowManager.shared.audioEngine.loadTracks(tracks) }
            self.model.endLoading()
            self.radioPlayTask = nil
        }
    }

    // MARK: - Selection

    /// The selected rows of one kind when `clicked` is among them, else just `clicked`: a row's
    /// menu acts on the whole selection only when it was opened on part of it.
    func selection<T, ID: Hashable>(of clicked: T, as extract: (LibraryBrowserItem.ItemType) -> T?,
                                    id: (T) -> ID) -> [T] {
        let selected = model.selectedItems.compactMap { extract($0.type) }
        guard selected.count > 1, selected.contains(where: { id($0) == id(clicked) }) else { return [clicked] }
        var seen = Set<ID>()
        return selected.filter { seen.insert(id($0)).inserted }
    }

    // MARK: - Alerts

    /// A warning with a message and an OK button.
    static func warn(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Ask before a destructive action; true when `confirmTitle` was chosen.
    static func confirm(_ title: String, _ message: String, confirmTitle: String,
                        style: NSAlert.Style = .warning, accessory: NSView? = nil) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.accessoryView = accessory
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
