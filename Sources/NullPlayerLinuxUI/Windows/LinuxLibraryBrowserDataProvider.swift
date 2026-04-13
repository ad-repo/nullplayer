#if os(Linux)
import Foundation
import NullPlayerCore

struct LinuxLibraryBrowserSnapshot {
    let source: ModernBrowserSource
    let browseMode: ModernBrowseMode
    let sort: ModernBrowserSortOption
    let artists: [String]
    let albums: [AlbumSummary]
    let searchResults: [LibraryTrack]
}

final class LinuxLibraryBrowserDataProvider {
    private let store: MediaLibraryStore

    private(set) var source: ModernBrowserSource = .local
    private(set) var browseMode: ModernBrowseMode = .artists
    private(set) var sort: ModernBrowserSortOption = .nameAsc
    private(set) var searchQuery: String = ""
    private(set) var snapshot = LinuxLibraryBrowserSnapshot(
        source: .local,
        browseMode: .artists,
        sort: .nameAsc,
        artists: [],
        albums: [],
        searchResults: []
    )

    init(store: MediaLibraryStore = .shared) {
        self.store = store
        self.store.open()
        reload()
    }

    func setSource(_ source: ModernBrowserSource) {
        self.source = source
        reload()
    }

    func setBrowseMode(rawValue: Int) {
        guard let mode = ModernBrowseMode(rawValue: rawValue) else { return }
        browseMode = mode
        reload()
    }

    func setSort(_ sort: ModernBrowserSortOption) {
        self.sort = sort
        sort.save()
        reload()
    }

    func setSearchQuery(_ query: String) {
        searchQuery = query
        reload()
    }

    func addWatchFolder(_ url: URL) {
        store.insertWatchFolder(url)
        store.refreshTracksFromWatchFolders()
        reload()
    }

    func removeWatchFolder(path: String) {
        store.deleteWatchFolder(path)
        store.refreshTracksFromWatchFolders()
        reload()
    }

    func addFiles(_ urls: [URL]) {
        let discovered = LocalFileDiscovery.discoverMedia(
            from: urls,
            recursiveDirectories: true,
            includeVideo: false
        )
        let entries = discovered.audioFiles.map { file in
            let track = LibraryTrack(
                url: file.url,
                title: file.url.deletingPathExtension().lastPathComponent,
                duration: 0,
                fileSize: file.fileSize,
                dateAdded: Date()
            )
            return (track: track, sig: FileScanSignature(fileSize: file.fileSize, contentModificationDate: file.contentModificationDate))
        }
        store.upsertTracks(entries)
        store.checkpoint()
        reload()
    }

    func clearLocalLibrary() {
        store.deleteAllTracks()
        store.checkpoint()
        reload()
    }

    func tracksForAlbum(_ albumId: String) -> [LibraryTrack] {
        store.tracksForAlbum(albumId)
    }

    func tracksForArtist(_ artistName: String) -> [LibraryTrack] {
        store.albumsForArtist(artistName).flatMap { store.tracksForAlbum($0.id) }
    }

    func reload() {
        if source != .local {
            snapshot = LinuxLibraryBrowserSnapshot(
                source: source,
                browseMode: browseMode,
                sort: sort,
                artists: [],
                albums: [],
                searchResults: []
            )
            return
        }

        let artists = store.artistNames(limit: 5000, offset: 0, sort: sort)
        let albums = store.albumSummaries(limit: 5000, offset: 0, sort: sort)
        let searchResults: [LibraryTrack]
        if searchQuery.isEmpty {
            searchResults = []
        } else {
            searchResults = store.searchTracks(query: searchQuery, limit: 5000, offset: 0)
        }

        snapshot = LinuxLibraryBrowserSnapshot(
            source: source,
            browseMode: browseMode,
            sort: sort,
            artists: artists,
            albums: albums,
            searchResults: searchResults
        )
    }
}
#endif
