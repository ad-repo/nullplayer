import Foundation
import NullPlayerCore

/// A Plex server's rows, as fetched for the selected library. Replacing it with a fresh value
/// drops every one of them; the expansion of their rows is collapsed alongside.
struct PlexBrowserCache {
    var artists: [PlexArtist] = []
    var albums: [PlexAlbum] = []
    /// Album count per artist id, counted from the albums' `parentKey`.
    var artistAlbumCounts: [String: Int] = [:]
    var artistGroupsByName: [String: [PlexArtist]] = [:]
    var albumsByArtistGroupKey: [String: [PlexAlbum]] = [:]
    var albumCountsByArtistGroupKey: [String: Int] = [:]
    /// Albums fetched on expand, by artist group key.
    var artistAlbums: [String: [PlexAlbum]] = [:]
    /// Albums fetched for a search result's artist, by normalized name (search ids can vary).
    var artistAlbumsByName: [String: [PlexAlbum]] = [:]
    var albumTracks: [String: [PlexTrack]] = [:]
    var movies: [PlexMovie] = []
    var shows: [PlexShow] = []
    var showSeasons: [String: [PlexSeason]] = [:]
    var seasonEpisodes: [String: [PlexEpisode]] = [:]
    /// Playlists span the server's libraries, so picking another library keeps them.
    var playlists: [PlexPlaylist] = []
    var playlistTracks: [String: [PlexTrack]] = [:]
    var searchResults: PlexSearchResults?
}

/// Each row's EQ profile marker by row id, for the store revision it was read at, so a paint reads
/// no store. A new list starts empty (`LibraryBrowserModel.displayItems`).
struct LibraryRowEQMarkers {
    private var marks: [String: Bool] = [:]
    private var revision = -1

    mutating func marked(_ id: String, revision: Int, read: () -> Bool) -> Bool {
        if revision != self.revision {
            marks.removeAll()
            self.revision = revision
        }
        if let marked = marks[id] { return marked }
        let marked = read()
        marks[id] = marked
        return marked
    }
}
