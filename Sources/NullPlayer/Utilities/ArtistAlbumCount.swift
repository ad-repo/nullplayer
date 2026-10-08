import Foundation

/// An artist whose album count is taken from the album list rather than the server: Emby and
/// Jellyfin send none (an artist's `ChildCount` is its song count).
protocol AlbumCountedArtist: Identifiable where ID == String {
    var albumCount: Int { get set }
}

/// An album crediting one or more album artists by id.
protocol AlbumArtistCredited {
    var albumArtistIds: [String] { get }
}

extension Array where Element: AlbumCountedArtist {
    /// Each artist with its album count from `albums`, crediting every album artist of an album,
    /// as expanding the artist lists it.
    func countingAlbums(_ albums: [some AlbumArtistCredited]) -> [Element] {
        let counts = Dictionary(grouping: albums.flatMap(\.albumArtistIds), by: { $0 }).mapValues(\.count)
        return map { var artist = $0; artist.albumCount = counts[artist.id] ?? 0; return artist }
    }
}
