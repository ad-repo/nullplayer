import AppKit
import NullPlayerCore
import UniformTypeIdentifiers

/// The local library's row actions: tags, ratings, Show in Finder, Remove from Library and
/// delete from disk, and adding files, folders and dropped items.
///
/// Every library change posts `MediaLibrary`'s change notification, and the model's debounced
/// reload picks it up, so nothing here reloads the rows itself.
extension LibraryBrowserActions {

    // MARK: - Tags

    func showTags(_ track: LibraryTrack) {
        let panel = TagsPanel(track: track)
        present(panel) { panel.show() }
    }

    func editTags(_ track: LibraryTrack) {
        let panel = EditTagsPanel(track: track)
        panel.onSave = { [weak model] in model?.reloadLocalBrowserAfterMetadataEdit() }
        present(panel) { panel.show() }
    }

    func editAlbumTags(_ album: Album) {
        let panel = EditAlbumTagsPanel(album: album)
        panel.onSave = { [weak model] in model?.reloadLocalBrowserAfterMetadataEdit() }
        present(panel) { panel.show() }
    }

    func editVideoTags(_ video: EditVideoTagsPanel.VideoItem) {
        let panel = EditVideoTagsPanel(item: video)
        panel.onSave = { [weak model] in model?.reloadLocalBrowserAfterMetadataEdit() }
        present(panel) { panel.show() }
    }

    /// Show `panel`, closing the last one of its kind.
    private func present(_ panel: NSWindow, show: () -> Void) {
        let kind = ObjectIdentifier(type(of: panel))
        tagPanels[kind]?.close()
        tagPanels[kind] = panel
        show()
    }

    // MARK: - Ratings

    /// The library rates on 0–10; nil clears.
    private static func libraryRating(_ stars: Int) -> Int? { stars > 0 ? stars * 2 : nil }

    func rateLocalTrack(_ trackId: UUID, stars: Int) {
        let rating = Self.libraryRating(stars)
        MediaLibrary.shared.setRating(for: trackId, rating: rating)
        replaceRow { type in
            guard case .localTrack(var track) = type, track.id == trackId else { return nil }
            track.rating = rating
            return .localTrack(track)
        }
    }

    func rateLocalAlbum(_ albumId: String, stars: Int) {
        MediaLibrary.shared.setAlbumRating(albumId: albumId, rating: Self.libraryRating(stars))
    }

    func rateLocalArtist(_ artistId: String, stars: Int) {
        MediaLibrary.shared.setArtistRating(artistId: artistId, rating: Self.libraryRating(stars))
    }

    // MARK: - Finder

    func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Remove from Library

    func removeLocalTracks(clicked track: LibraryTrack) {
        let tracks = selectedLocalTracks(clicked: track)
        if tracks.count == 1 {
            MediaLibrary.shared.removeTrack(track)
        } else {
            MediaLibrary.shared.removeTracks(urls: tracks.map(\.url))
        }
    }

    func removeLocalAlbum(_ album: Album) {
        let tracks = LibraryPlayable.libraryTracks(of: album)
        guard Self.confirmRemove("\"\(album.name)\"", count: tracks.count, noun: "track") else { return }
        MediaLibrary.shared.removeTracks(urls: tracks.map(\.url))
    }

    func removeLocalArtists(clicked artist: Artist) {
        let artists = selectedLocalArtists(clicked: artist)
        let tracks = Self.libraryTracks(of: artists)
        let name = artists.count == 1 ? "\"\(artist.name)\"" : "\(artists.count) Artists"
        guard Self.confirmRemove(name, count: tracks.count, noun: "track") else { return }
        MediaLibrary.shared.removeTracks(urls: tracks.map(\.url))
    }

    func removeLocalMovies(clicked movie: LocalVideo) {
        let movies = selection(of: movie, as: { if case .localMovie(let m) = $0 { return m }; return nil }, id: \.id)
        if movies.count == 1 {
            MediaLibrary.shared.removeMovie(movie)
        } else {
            MediaLibrary.shared.removeMovies(urls: movies.map(\.url))
        }
    }

    func removeLocalEpisode(_ episode: LocalEpisode) {
        MediaLibrary.shared.removeEpisode(episode)
    }

    func removeLocalShow(_ show: LocalShow) {
        guard Self.confirmRemove("\"\(show.title)\"", count: show.episodeCount, noun: "episode") else { return }
        MediaLibrary.shared.removeShow(title: show.title)
    }

    func removeLocalSeason(_ season: LocalSeason, showTitle: String) {
        guard Self.confirmRemove("Season \(season.number) of \"\(showTitle)\"", count: season.episodes.count,
                                 noun: "episode") else { return }
        MediaLibrary.shared.removeSeason(showTitle: showTitle, seasonNumber: season.number)
    }

    private static func confirmRemove(_ name: String, count: Int, noun: String) -> Bool {
        confirm("Remove \(name) from Library?",
                "This will remove \(count) \(noun)\(count == 1 ? "" : "s"). Files will not be deleted.",
                confirmTitle: "Remove")
    }

    // MARK: - Delete from disk

    func deleteLocalTracks(clicked track: LibraryTrack) {
        deleteFromDisk(selectedLocalTracks(clicked: track))
    }

    func deleteLocalAlbum(_ album: Album) {
        deleteFromDisk(LibraryPlayable.libraryTracks(of: album))
    }

    func deleteLocalArtists(clicked artist: Artist) {
        deleteFromDisk(Self.libraryTracks(of: selectedLocalArtists(clicked: artist)))
    }

    /// Move the files to the Trash, or delete them outright, then drop them from the library.
    private func deleteFromDisk(_ tracks: [LibraryTrack]) {
        guard !tracks.isEmpty else { return }
        let moveToTrash = NSButton(checkboxWithTitle: "Move to Trash instead of deleting permanently", target: nil, action: nil)
        moveToTrash.state = .on
        guard Self.confirm(tracks.count == 1 ? "Delete file from disk?" : "Delete \(tracks.count) files from disk?",
                           "This will permanently delete the file(s) from your computer. This action cannot be undone.",
                           confirmTitle: "Delete", style: .critical, accessory: moveToTrash) else { return }

        var failedFiles: [String] = []
        var removed: [LibraryTrack] = []
        for track in tracks {
            do {
                if moveToTrash.state == .on {
                    try FileManager.default.trashItem(at: track.url, resultingItemURL: nil)
                } else {
                    try FileManager.default.removeItem(at: track.url)
                }
                removed.append(track)
            } catch {
                failedFiles.append(track.url.lastPathComponent)
            }
        }

        if removed.count == 1 {
            MediaLibrary.shared.removeTrack(removed[0])
        } else if !removed.isEmpty {
            MediaLibrary.shared.removeTracks(urls: removed.map(\.url))
        }

        if !failedFiles.isEmpty {
            var message = "Failed to delete:\n" + failedFiles.prefix(5).joined(separator: "\n")
            if failedFiles.count > 5 { message += "\n...and \(failedFiles.count - 5) more" }
            Self.warn("Some files could not be deleted", message)
        }
    }

    // MARK: - Selection

    private func selectedLocalTracks(clicked track: LibraryTrack) -> [LibraryTrack] {
        selection(of: track, as: { if case .localTrack(let t) = $0 { return t }; return nil }, id: \.url)
    }

    private func selectedLocalArtists(clicked artist: Artist) -> [Artist] {
        selection(of: artist, as: { if case .localArtist(let a) = $0 { return a }; return nil }, id: \.id)
    }

    /// Every track of `artists`, once each. A paged artist row is a stub with no albums: its
    /// albums are read from the store.
    private static func libraryTracks(of artists: [Artist]) -> [LibraryTrack] {
        let store = MediaLibraryStore.shared
        let tracks = artists.flatMap { artist in
            artist.albums.isEmpty
                ? store.albumsForArtist(artist.name).flatMap { store.tracksForAlbum($0.id) }
                : artist.albums.flatMap(LibraryPlayable.libraryTracks(of:))
        }
        var seen = Set<URL>()
        return tracks.filter { seen.insert($0.url).inserted }
    }

    // MARK: - Adding to the library

    func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff]
        panel.message = "Select audio files to add to your library"
        guard panel.runModal() == .OK else { return }
        MediaLibrary.shared.addTracks(urls: panel.urls)
        showLocalSource()
    }

    func addVideoFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        // Every container we play, so formats like .mkv, .avi and .webm aren't greyed out.
        var videoTypes: [UTType] = [.movie, .video]
        for ext in AudioFileValidator.supportedVideoExtensions {
            if let type = UTType(filenameExtension: ext) { videoTypes.append(type) }
        }
        panel.allowedContentTypes = videoTypes
        panel.message = "Select video files to add to your library"
        guard panel.runModal() == .OK else { return }
        MediaLibrary.shared.addVideoFiles(urls: panel.urls)
        model.showLocalMovies()
    }

    func addWatchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to add to your library"
        let folderDelegate = TopLevelFolderPickerDelegate()
        panel.delegate = folderDelegate
        withExtendedLifetime(folderDelegate) {
            guard panel.runModal() == .OK, let url = panel.url else { return }
            MediaLibrary.shared.addWatchFolder(url)
            MediaLibrary.shared.scanFolder(url)
            showLocalSource()
        }
    }

    func manageWatchFolders() {
        WatchFolderManagerDialog.present { [weak model] in
            guard let model, model.currentSource.isLocal else { return }
            model.loadLocalData()
        }
    }

    /// After adding files, show them: switch to the Local source from any other.
    private func showLocalSource() {
        if !model.currentSource.isLocal { model.currentSource = .local }
    }

    /// Files and folders dropped on the browser: folders become watch folders, audio and video
    /// files join the library, and `.m3u` / `.pls` playlists import as radio stations.
    func addDroppedItems(_ urls: [URL]) -> Bool {
        var audioURLs: [URL] = []
        var videoURLs: [URL] = []
        var playlistURLs: [URL] = []
        var addedFolder = false
        for url in urls {
            if LocalFileDiscovery.isDirectory(url) {
                MediaLibrary.shared.addWatchFolder(url)
                MediaLibrary.shared.scanFolder(url)
                addedFolder = true
            } else if LocalFileDiscovery.isSupportedPlaylistFile(url) {
                playlistURLs.append(url)
            } else if LocalFileDiscovery.isSupportedAudioFile(url) {
                audioURLs.append(url)
            } else if LocalFileDiscovery.isSupportedVideoFile(url) {
                videoURLs.append(url)
            }
        }
        if !playlistURLs.isEmpty {
            importRadioPlaylistFiles(playlistURLs, reportEmpty: false)
        }
        if !audioURLs.isEmpty {
            MediaLibrary.shared.addTracks(urls: audioURLs)
            showLocalSource()
        }
        if !videoURLs.isEmpty {
            MediaLibrary.shared.addVideoFiles(urls: videoURLs)
            model.showLocalMovies()
        }
        return !audioURLs.isEmpty || !videoURLs.isEmpty || !playlistURLs.isEmpty || addedFolder
    }
}
