import Foundation

/// The library, server and radio notifications that change what the browser lists.
extension LibraryBrowserModel {

    func observeNotifications() {
        let center = NotificationCenter.default
        for name in [PlexManager.accountDidChangeNotification,
                     PlexManager.libraryDidChangeNotification,
                     PlexManager.connectionStateDidChangeNotification] {
            center.addObserver(self, selector: #selector(plexStateDidChange), name: name, object: nil)
        }
        let observers: [(Selector, Notification.Name)] = [
            (#selector(plexServerDidChange), PlexManager.serversDidChangeNotification),
            (#selector(plexContentDidPreload), PlexManager.libraryContentDidPreloadNotification),
            (#selector(mediaLibraryDidChange), MediaLibrary.libraryDidChangeNotification),
            (#selector(radioStationsDidChange), RadioManager.stationsDidChangeNotification),
            (#selector(youtubeChannelsDidChange), YouTubeManager.youtubeChannelsDidChangeNotification),
            (#selector(youtubeVideoLimitDidChange), YouTubeManager.youtubeVideoLimitDidChangeNotification),
            (#selector(youtubeUploadsDidChange), YouTubeChannelUploads.didChangeNotification),
            (#selector(jellyfinMusicLibraryDidChange), JellyfinManager.musicLibraryDidChangeNotification),
            (#selector(jellyfinVideoLibraryDidChange), JellyfinManager.videoLibraryDidChangeNotification),
            (#selector(embyMusicLibraryDidChange), EmbyManager.musicLibraryDidChangeNotification),
            (#selector(embyVideoLibraryDidChange), EmbyManager.videoLibraryDidChangeNotification),
            (#selector(embyLibraryContentDidPreload), EmbyManager.libraryContentDidPreloadNotification),
            (#selector(embyConnectionStateDidChange), EmbyManager.connectionStateDidChangeNotification),
            (#selector(subsonicMusicFolderDidChange), SubsonicManager.musicFolderDidChangeNotification),
            (#selector(playHistoryDidChange), MediaLibraryStore.playHistoryDidChangeNotification),
            // External source selection (e.g. Subsonic/Jellyfin menu > Show in Library Browser)
            (#selector(handleSetBrowserSource(_:)), NSNotification.Name("SetBrowserSource")),
        ]
        for (selector, name) in observers {
            center.addObserver(self, selector: selector, name: name, object: nil)
        }
    }

    @objc private func playHistoryDidChange() {
        Task { @MainActor [weak self] in
            guard let self, self.browseMode.isHistoryMode else { return }
            self.history.scheduleRefresh()
        }
    }

    // MARK: - Plex

    @objc private func plexStateDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self, case .plex = self.currentSource else { return }
            if case .connecting = PlexManager.shared.connectionState {
                self.loadState = .loading
                return
            }
            self.reloadData()
        }
    }

    @objc private func plexServerDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if case .connecting = PlexManager.shared.connectionState {
                // The server list changed mid-connect; the link state may have, too.
                self.onChange?(.listState)
                return
            }
            guard self.currentSource.isPlex || self.pendingSourceRestore != nil else { return }
            // A server source saved before its server list loaded: the saved server, else the
            // first of its kind.
            if let pending = self.pendingSourceRestore {
                self.pendingSourceRestore = nil
                if pending != .local, let restored = Self.configuredSource(for: pending) {
                    NSLog("LibraryBrowserModel: Restoring pending source")
                    self.currentSource = restored
                    return
                }
            }
            NSLog("LibraryBrowserModel: Server changed, clearing cache and reloading")
            self.clearAllCachedData()
            self.reloadData()
        }
    }

    @objc private func plexContentDidPreload() {
        guard case .plex = currentSource else { return }
        reloadData()
    }

    // MARK: - Local library

    /// Debounced: a scan posts this for every batch it imports.
    @objc private func mediaLibraryDidChange() {
        guard currentSource.isLocal, !browseMode.isRadioMode, !browseMode.isHistoryMode else { return }
        localLibraryReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.currentSource.isLocal, !self.browseMode.isRadioMode, !self.browseMode.isHistoryMode else { return }
            self.loadLocalData()
        }
        localLibraryReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30, execute: workItem)
    }

    // MARK: - Internet Radio and YouTube

    var isShowingInternetRadioContent: Bool {
        currentSource.isRadio ||
            (currentSource.isYouTube && browseMode == .radio && !radioSlotShowsChannels)
    }

    @objc private func radioStationsDidChange() {
        guard isShowingInternetRadioContent else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch self.browseMode {
            case .radio: self.loadRadioStations()
            case .search: self.loadRadioSearchResults()
            default: break
            }
        }
    }

    @objc private func youtubeChannelsDidChange() {
        // Posted off the main thread by `addChannel(url:)`.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentSource.isYouTube else { return }
            self.rebuildCurrentModeItems()
        }
    }

    /// A larger limit fetches the expanded channels again; a smaller one shows fewer of the cached uploads.
    @objc private func youtubeVideoLimitDidChange() {
        YouTubeChannelUploads.shared.load(expandedYouTubeChannels.values)
    }

    @objc private func youtubeUploadsDidChange() {
        if showsYouTubeRows { rebuildCurrentModeItems() }
    }

    /// The list shows YouTube rows: the YouTube source, or the Local search's channel and video rows.
    var showsYouTubeRows: Bool {
        if currentSource.isLocal { return browseMode == .search }
        return currentSource.isYouTube
    }

    // MARK: - Jellyfin, Emby and Subsonic

    @objc private func jellyfinMusicLibraryDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self, case .jellyfin = self.currentSource else { return }
            self.clearAllCachedData(); self.reloadData()
        }
    }

    @objc private func jellyfinVideoLibraryDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self, case .jellyfin = self.currentSource, self.browseMode.isVideoMode else { return }
            self.resetJellyfinVideo()
            self.reloadData()
        }
    }

    @objc private func embyMusicLibraryDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self, case .emby = self.currentSource else { return }
            self.clearAllCachedData(); self.reloadData()
        }
    }

    @objc private func embyVideoLibraryDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self, case .emby = self.currentSource, self.browseMode.isVideoMode else { return }
            self.resetEmbyVideo()
            self.reloadData()
        }
    }

    @objc private func embyLibraryContentDidPreload() {
        DispatchQueue.main.async { [weak self] in
            guard let self, case .emby = self.currentSource else { return }
            self.reloadData()
        }
    }

    @objc private func embyConnectionStateDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self, case .emby = self.currentSource else { return }
            self.reloadData()
        }
    }

    @objc private func subsonicMusicFolderDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self, case .subsonic = self.currentSource else { return }
            self.clearAllCachedData(); self.reloadData()
        }
    }

    @objc private func handleSetBrowserSource(_ notification: Notification) {
        guard let source = notification.object as? LibraryBrowserSource else { return }
        currentSource = source
    }
}
