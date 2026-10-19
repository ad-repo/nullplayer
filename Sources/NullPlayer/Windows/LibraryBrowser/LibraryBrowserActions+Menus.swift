import AppKit
import NullPlayerCore

/// The library browser's menus: a row's context menu, and the server bar's source, library, add
/// and sort menus. Each view pops them up in its own coordinates.
extension LibraryBrowserActions {

    // MARK: - Row context menu

    /// The menu a right-click on `item` opens; nil for a row with nothing to offer.
    func contextMenu(for item: LibraryBrowserItem) -> NSMenu? {
        let menu = NSMenu()
        if let playable = playable(for: item) {
            TrackVerb.addMenuItems(to: menu, resolve: resolver(for: playable))
            if let level = playable.eqProfileLevel {
                EQProfileMenu.addAssignItem(to: menu, level: level, scopes: playable.eqProfileScopes,
                                            resolve: resolver(for: playable))
            }
        }

        switch item.type {
        case .track(let track):
            menu.addItem(.separator())
            menu.addItem(menuItem("Start Track Radio") { [unowned self] in
                startPlexRadio { await PlexManager.shared.createTrackRadio(from: track, limit: RadioPlaybackOptions.playlistLength) }
            })
            menu.addItem(rateItem { [unowned self] in ratePlex(track.id, stars: $0) })

        case .album(let album):
            menu.addItem(.separator())
            menu.addItem(menuItem("Start Album Radio") { [unowned self] in
                startPlexRadio { await PlexManager.shared.createAlbumRadio(from: album, limit: RadioPlaybackOptions.playlistLength) }
            })
            menu.addItem(rateItem { [unowned self] in ratePlex(album.id, stars: $0) })

        case .artist(let artist):
            addExpandItem(for: item, to: menu)
            menu.addItem(.separator())
            menu.addItem(menuItem("Start Artist Radio") { [unowned self] in
                startPlexRadio { await PlexManager.shared.createArtistRadio(from: artist, limit: RadioPlaybackOptions.playlistLength) }
            })

        case .movie(let movie):
            addCastItem(to: menu) { try await CastManager.shared.castPlexMovie(movie, to: $0) }
            menu.addItem(.separator())
            menu.addItem(viewOnlineItem(for: movie))

        case .show(let show):
            addExpandItem(for: item, to: menu)
            menu.addItem(.separator())
            menu.addItem(viewOnlineItem(for: show))

        case .episode(let episode):
            addCastItem(to: menu) { try await CastManager.shared.castPlexEpisode(episode, to: $0) }
            menu.addItem(.separator())
            menu.addItem(viewOnlineItem(for: episode))

        case .season, .plexPlaylist, .subsonicArtist, .subsonicPlaylist, .jellyfinArtist, .jellyfinPlaylist,
             .jellyfinShow, .jellyfinSeason, .embyArtist, .embyPlaylist, .embyShow, .embySeason:
            addExpandItem(for: item, to: menu)

        case .localTrack(let track):
            menu.addItem(.separator())
            menu.addItem(rateItem { [unowned self] in rateLocalTrack(track.id, stars: $0) })
            menu.addItem(.separator())
            menu.addItem(menuItem("Edit Tags") { [unowned self] in editTags(track) })
            menu.addItem(menuItem("See Tags") { [unowned self] in showTags(track) })
            menu.addItem(menuItem("Show in Finder") { [unowned self] in showInFinder(track.url) })
            menu.addItem(.separator())
            menu.addItem(menuItem("Remove from Library") { [unowned self] in removeLocalTracks(clicked: track) })
            menu.addItem(menuItem("Delete File from Disk...") { [unowned self] in deleteLocalTracks(clicked: track) })

        case .localFolder(let url, _):
            menu.addItem(.separator())
            menu.addItem(menuItem("Show in Finder") { [unowned self] in showInFinder(url) })

        case .localAlbum(let album):
            menu.addItem(.separator())
            menu.addItem(rateItem { [unowned self] in rateLocalAlbum(album.id, stars: $0) })
            menu.addItem(menuItem("Edit Album Tags") { [unowned self] in editAlbumTags(album) })
            menu.addItem(.separator())
            menu.addItem(menuItem("Remove Album from Library") { [unowned self] in removeLocalAlbum(album) })
            menu.addItem(menuItem("Delete Album from Disk...") { [unowned self] in deleteLocalAlbum(album) })

        case .localArtist(let artist):
            addExpandItem(for: item, to: menu)
            menu.addItem(.separator())
            menu.addItem(rateItem { [unowned self] in rateLocalArtist(artist.id, stars: $0) })
            menu.addItem(.separator())
            menu.addItem(menuItem("Remove Artist from Library") { [unowned self] in removeLocalArtists(clicked: artist) })
            menu.addItem(menuItem("Delete Artist from Disk...") { [unowned self] in deleteLocalArtists(clicked: artist) })

        case .localMovie(let movie):
            addCastItem(to: menu) { try await CastManager.shared.castLocalVideo(movie.url, title: movie.title, to: $0) }
            menu.addItem(.separator())
            menu.addItem(menuItem("Show in Finder") { [unowned self] in showInFinder(movie.url) })
            menu.addItem(.separator())
            menu.addItem(menuItem("Edit Tags") { [unowned self] in editVideoTags(.movie(movie)) })
            menu.addItem(menuItem("Remove from Library") { [unowned self] in removeLocalMovies(clicked: movie) })

        case .localShow(let show):
            addExpandItem(for: item, to: menu)
            menu.addItem(.separator())
            menu.addItem(menuItem("Remove Show from Library") { [unowned self] in removeLocalShow(show) })

        case .localSeason(let season, let showTitle):
            addExpandItem(for: item, to: menu)
            menu.addItem(.separator())
            menu.addItem(menuItem("Remove Season from Library") { [unowned self] in removeLocalSeason(season, showTitle: showTitle) })

        case .localEpisode(let episode):
            addCastItem(to: menu) { try await CastManager.shared.castLocalVideo(episode.url, title: episode.title, to: $0) }
            menu.addItem(.separator())
            menu.addItem(menuItem("Show in Finder") { [unowned self] in showInFinder(episode.url) })
            menu.addItem(.separator())
            menu.addItem(menuItem("Edit Tags") { [unowned self] in editVideoTags(.episode(episode)) })
            menu.addItem(menuItem("Remove from Library") { [unowned self] in removeLocalEpisode(episode) })

        case .subsonicTrack(let song):
            menu.addItem(.separator())
            addSongContextItems(to: menu, for: song)
            menu.addItem(.separator())
            menu.addItem(rateItem { [unowned self] in rateSubsonic(song.id, stars: $0) })

        case .subsonicAlbum(let album):
            menu.addItem(.separator())
            menu.addItem(rateItem { [unowned self] in rateSubsonic(album.id, stars: $0) })

        case .jellyfinTrack(let song):
            menu.addItem(.separator())
            addSongContextItems(to: menu, for: song)
            menu.addItem(.separator())
            menu.addItem(rateItem { [unowned self] in rateJellyfin(song.id, stars: $0) })

        case .embyTrack(let song):
            menu.addItem(.separator())
            addSongContextItems(to: menu, for: song)
            menu.addItem(.separator())
            menu.addItem(rateItem { [unowned self] in rateEmby(song.id, stars: $0) })

        case .radioStation(let station):
            menu.addItem(menuItem("Play Station") { RadioManager.shared.play(station: station) })
            EQProfileMenu.addAssignItem(to: menu, level: .track, tracks: [station.toTrack()])
            menu.addItem(.separator())
            menu.addItem(submenuItem("Folders", stationFoldersMenu(for: station)))
            menu.addItem(submenuItem("Smart Folders", stationSmartFoldersMenu(for: station)))
            menu.addItem(.separator())
            menu.addItem(menuItem("Edit Station...") { [unowned self] in editStation(station) })
            menu.addItem(menuItem("Delete Station") { [unowned self] in deleteStation(station) })

        case .radioFolder(let folder):
            if folder.hasChildren { addExpandItem(for: item, to: menu) }
            switch folder.kind {
            case .manual(let folderID):
                if !menu.items.isEmpty { menu.addItem(.separator()) }
                menu.addItem(menuItem("Rename Folder...") { [unowned self] in renameFolder(folderID) })
                menu.addItem(menuItem("Delete Folder") { [unowned self] in deleteFolder(folderID) })
            case .userFoldersRoot:
                if !menu.items.isEmpty { menu.addItem(.separator()) }
                menu.addItem(menuItem("New Folder...") { [unowned self] in createFolder() })
            default:
                break
            }

        case .youtubeChannel(let channel):
            addExpandItem(for: item, to: menu)
            menu.addItem(.separator())
            if !YouTubeManager.shared.isSubscribed(channel) {
                menu.addItem(menuItem("Subscribe") { [unowned self] in model.youtubeSearch.subscribe(to: channel) })
            } else if model.isYouTubeChannelSearch {
                // Refresh/Remove belong to the Channels tab.
                let subscribed = NSMenuItem(title: "Already Subscribed", action: nil, keyEquivalent: "")
                subscribed.isEnabled = false
                menu.addItem(subscribed)
            } else {
                menu.addItem(menuItem("Refresh") { [unowned self] in model.refreshYouTubeChannel(channel) })
                menu.addItem(menuItem("Remove Channel") { [unowned self] in model.removeYouTubeChannel(channel) })
            }

        case .youtubeVideo(let video):
            youtubeVideos.addMenuItems(for: video, to: menu)

        case .plexRadioStation(let radioType):
            menu.addItem(menuItem("Play \(radioType.displayName)") { [unowned self] in activate(item) })

        case .subsonicRadioStation, .jellyfinRadioStation, .embyRadioStation, .localRadioStation:
            menu.addItem(menuItem("Play") { [unowned self] in activate(item) })

        case .jellyfinAlbum, .embyAlbum, .localPlaylist, .localPlaylistTrack,
             .jellyfinMovie, .jellyfinEpisode, .embyMovie, .embyEpisode, .header:
            break
        }
        return menu.items.isEmpty ? nil : menu
    }

    private func addExpandItem(for item: LibraryBrowserItem, to menu: NSMenu) {
        menu.addItem(menuItem(model.isExpanded(item) ? "Collapse" : "Expand") { [unowned self] in model.toggleExpand(item) })
    }

    private func addCastItem(to menu: NSMenu, _ cast: @escaping @MainActor (CastDevice) async throws -> Void) {
        guard let item = castItem(cast) else { return }
        menu.addItem(.separator())
        menu.addItem(item)
    }

    // MARK: - A station's folders

    private func stationFoldersMenu(for station: RadioStation) -> NSMenu {
        let menu = NSMenu()
        let folders = RadioManager.shared.userRadioFolders()
        if folders.isEmpty {
            let empty = NSMenuItem(title: "No Folders", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for folder in folders {
            let item = menuItem(folder.name) { [unowned self] in toggleMembership(of: station, inFolder: folder.id) }
            item.state = RadioManager.shared.isStation(station, inUserFolderID: folder.id) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("New Folder...") { [unowned self] in createFolder(adding: station) })
        return menu
    }

    private func stationSmartFoldersMenu(for station: RadioStation) -> NSMenu {
        let manager = RadioManager.shared
        let stationGenre = (station.genre ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let genreMenu = smartFolderMenu(
            auto: "Use Station Genre (\(stationGenre.isEmpty ? "Unknown" : stationGenre))",
            isOverridden: manager.smartGenreOverride(for: station) != nil,
            options: manager.smartGenreOptions(including: station),
            current: manager.normalizedGenre(for: station)
        ) { [unowned self] in setSmartGenre($0, for: station) }
        let regionMenu = smartFolderMenu(
            auto: "Use Auto Region (\(manager.autoRegion(for: station)))",
            isOverridden: manager.smartRegionOverride(for: station) != nil,
            options: manager.smartRegionOptions(including: station),
            current: manager.effectiveRegion(for: station)
        ) { [unowned self] in setSmartRegion($0, for: station) }

        let menu = NSMenu()
        menu.addItem(submenuItem("By Genre", genreMenu))
        menu.addItem(submenuItem("By Region", regionMenu))
        return menu
    }

    /// The automatic choice, then each option; `assign` gets nil for the automatic one.
    private func smartFolderMenu(auto: String, isOverridden: Bool, options: [String], current: String,
                                 assign: @escaping @MainActor (String?) -> Void) -> NSMenu {
        let menu = NSMenu()
        let autoItem = menuItem(auto) { assign(nil) }
        autoItem.state = isOverridden ? .off : .on
        menu.addItem(autoItem)
        menu.addItem(.separator())
        for option in options {
            let item = menuItem(option) { assign(option) }
            item.state = current.localizedCaseInsensitiveCompare(option) == .orderedSame ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Server bar

    /// The sort indicator's menu: the current tab's sort.
    func sortMenu() -> NSMenu {
        let menu = NSMenu()
        for option in LibraryBrowserSortOption.allCases {
            let item = menuItem(option.rawValue) { [unowned self] in model.selectMenuSort(option) }
            item.state = option == model.currentSort ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    /// The source button's menu: Local, Internet Radio, YouTube, then each server, offering to
    /// link or add one of a kind there is none of.
    func sourceMenu() -> NSMenu {
        let menu = NSMenu()
        let current = model.currentSource
        func addSource(_ title: String, _ source: LibraryBrowserSource) {
            let item = menuItem(title) { [unowned self] in model.currentSource = source }
            item.state = source == current ? .on : .off
            menu.addItem(item)
        }

        addSource("Local Files", .local)
        menu.addItem(.separator())
        addSource("Internet Radio", .radio)
        menu.addItem(.separator())
        addSource("YouTube", .youtube)
        menu.addItem(.separator())

        let plexServers = PlexManager.shared.servers
        if plexServers.isEmpty && !PlexManager.shared.isLinked {
            menu.addItem(menuItem("Link Plex Account...") { [unowned self] in host.presentLinkSheet() })
        }
        for server in plexServers { addSource(server.name, .plex(serverId: server.id)) }

        menu.addItem(.separator())
        let subsonicServers = SubsonicManager.shared.servers
        if subsonicServers.isEmpty {
            menu.addItem(menuItem("Add Navidrome/Subsonic...") { WindowManager.shared.showSubsonicLinkSheet() })
        }
        for server in subsonicServers { addSource("🎵 \(server.name)", .subsonic(serverId: server.id)) }

        menu.addItem(.separator())
        let jellyfinServers = JellyfinManager.shared.servers
        if jellyfinServers.isEmpty {
            menu.addItem(menuItem("Add Jellyfin Server...") { WindowManager.shared.showJellyfinLinkSheet() })
        }
        for server in jellyfinServers { addSource("🟣 \(server.name)", .jellyfin(serverId: server.id)) }

        menu.addItem(.separator())
        let embyServers = EmbyManager.shared.servers
        if embyServers.isEmpty {
            menu.addItem(menuItem("Add Emby Server...") { WindowManager.shared.showEmbyLinkSheet() })
        }
        for server in embyServers { addSource("🔵 \(server.name)", .emby(serverId: server.id)) }
        return menu
    }

    /// The add button's menu, on the sources that have one: Local, Internet Radio and YouTube.
    func addMenu() -> NSMenu? {
        let menu = NSMenu()
        switch model.currentSource {
        case .local:
            menu.addItem(menuItem("Add Files...") { [unowned self] in addFiles() })
            menu.addItem(menuItem("Add Video Files...") { [unowned self] in addVideoFiles() })
            menu.addItem(menuItem("Add Folder...") { [unowned self] in addWatchFolder() })
        case .radio:
            menu.addItem(menuItem("Add Station...") { [unowned self] in addStation() })
            menu.addItem(menuItem("New Folder...") { [unowned self] in createFolder() })
            menu.addItem(.separator())
            menu.addItem(menuItem("Import Playlist URL...") { [unowned self] in importRadioPlaylistURL() })
            menu.addItem(menuItem("Import Playlist File...") { [unowned self] in importRadioPlaylistFile() })
            menu.addItem(.separator())
            menu.addItem(menuItem("Add Missing Defaults") { [unowned self] in addMissingDefaultStations() })
            menu.addItem(menuItem("Reset to Defaults") { [unowned self] in resetStationsToDefaults() })
        case .youtube:
            menu.addItem(menuItem("Add Channel...") { [unowned self] in addYouTubeChannel() })
        case .plex, .subsonic, .jellyfin, .emby:
            return nil
        }
        return menu
    }

    /// The library button's menu, on a server source: the Plex library, the Subsonic music
    /// folder, or the Jellyfin or Emby library of the current tab's kind. A pick only tells the
    /// manager; the model reloads on the manager's notification.
    func libraryMenu() -> NSMenu? {
        switch model.currentSource {
        case .plex:
            return plexLibraryMenu()
        case .subsonic:
            let manager = SubsonicManager.shared
            return libraryMenu(all: "All Folders", libraries: manager.musicFolders.map { ($0, $0.id, $0.name) },
                               current: manager.currentMusicFolder?.id) { folder in
                if let folder { manager.selectMusicFolder(folder) } else { manager.clearMusicFolderSelection() }
            }
        case .jellyfin:
            let manager = JellyfinManager.shared
            if model.browseMode.isVideoMode {
                return libraryMenu(all: "All Libraries", libraries: manager.videoLibraries.map { ($0, $0.id, Self.videoLibraryTitle($0.name, $0.collectionType)) },
                                   current: model.browseMode == .shows ? manager.currentShowLibrary?.id : manager.currentMovieLibrary?.id) { library in
                    manager.selectMovieLibrary(library)
                    manager.selectShowLibrary(library)
                }
            }
            return libraryMenu(all: "All Libraries", libraries: manager.musicLibraries.map { ($0, $0.id, "\($0.name) (Music)") },
                               current: manager.currentMusicLibrary?.id) { library in
                if let library { manager.selectMusicLibrary(library) } else { manager.clearMusicLibrarySelection() }
            }
        case .emby:
            let manager = EmbyManager.shared
            if model.browseMode.isVideoMode {
                return libraryMenu(all: "All Libraries", libraries: manager.videoLibraries.map { ($0, $0.id, Self.videoLibraryTitle($0.name, $0.collectionType)) },
                                   current: model.browseMode == .shows ? manager.currentShowLibrary?.id : manager.currentMovieLibrary?.id) { library in
                    manager.selectMovieLibrary(library)
                    manager.selectShowLibrary(library)
                }
            }
            return libraryMenu(all: "All Libraries", libraries: manager.musicLibraries.map { ($0, $0.id, "\($0.name) (Music)") },
                               current: manager.currentMusicLibrary?.id) { library in
                if let library { manager.selectMusicLibrary(library) } else { manager.clearMusicLibrarySelection() }
            }
        case .local, .radio, .youtube:
            return nil
        }
    }

    private static func videoLibraryTitle(_ name: String, _ collectionType: String?) -> String {
        "\(name) (\(collectionType == "tvshows" ? "TV Shows" : "Movies"))"
    }

    /// "All", then each library; `select` gets nil for All.
    private func libraryMenu<Library>(all: String, libraries: [(Library, id: String, title: String)], current: String?,
                                      select: @escaping @MainActor (Library?) -> Void) -> NSMenu {
        let menu = NSMenu()
        let allItem = menuItem(all) { select(nil) }
        allItem.state = current == nil ? .on : .off
        menu.addItem(allItem)
        if !libraries.isEmpty { menu.addItem(.separator()) }
        for (library, id, title) in libraries {
            let item = menuItem(title) { select(library) }
            item.state = id == current ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func plexLibraryMenu() -> NSMenu {
        let menu = NSMenu()
        let libraries = PlexManager.shared.availableLibraries
        if libraries.isEmpty {
            let none = NSMenuItem(title: "No libraries available", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        let currentId = PlexManager.shared.currentLibrary?.id
        for library in libraries {
            let kind = library.isMusicLibrary ? "Music"
                : library.isMovieLibrary ? "Movies"
                : library.isShowLibrary ? "TV Shows"
                : library.type
            let item = menuItem("\(library.title) (\(kind))") { [unowned self] in model.selectPlexLibrary(library) }
            item.state = library.id == currentId ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    /// A right-click on the column header: tick the current group's columns, or reset them; nil
    /// when the list's columns are fixed.
    func columnMenu() -> NSMenu? {
        guard let group = model.configurableColumnGroup else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: group.headerTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let visibleIds = Set(model.visibleColumnIds(for: group))
        for column in LibraryBrowserColumn.all(for: group) {
            let item = NSMenuItem()
            item.view = ColumnVisibilityCheckboxView(
                title: column.title,
                isChecked: column.id == .title || visibleIds.contains(column.id.rawValue),
                isEnabled: column.id != .title
            ) { [weak model] isVisible in
                model?.setColumn(column.id, visible: isVisible, in: group)
            }
            menu.addItem(item)
        }
        menu.addItem(menuItem(group.resetTitle) { [unowned self] in model.resetColumns(group) })
        return menu
    }

    /// A right-click below the rows: Manage Folders on the Local source.
    func emptySpaceMenu() -> NSMenu? {
        guard model.currentSource.isLocal else { return nil }
        let menu = NSMenu()
        menu.addItem(menuItem("Manage Folders...") { [unowned self] in manageWatchFolders() })
        return menu
    }
}
