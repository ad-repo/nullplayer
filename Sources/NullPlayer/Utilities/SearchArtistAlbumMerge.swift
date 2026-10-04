import Foundation

/// Completes a server search's album list with the albums of the artists it matched.
///
/// Every server search caps or filters albums — Subsonic's `albumCount`, the single Jellyfin/Emby
/// `Limit` shared by every item type (whose `searchTerm` also matches album names only), Plex's
/// per-hub `limit` — so a prolific artist loses most of its albums. Each source merges the full
/// album list of its first `artistLimit` matched artists through here.
enum SearchArtistAlbumMerge {
    /// Bounds the fan-out, so a broad query does not fetch dozens of artists.
    static let artistLimit = 10

    /// `albums` followed by each artist's albums, in artist order, skipping any album whose `key`
    /// is already present. An artist whose fetch fails contributes nothing.
    static func merged<Album: Sendable>(
        _ albums: [Album],
        artistIDs: [String],
        key: (Album) -> String,
        fetch: @escaping @Sendable (String) async throws -> [Album]
    ) async -> [Album] {
        let ids = Array(artistIDs.prefix(artistLimit))
        guard !ids.isEmpty else { return albums }
        let artistAlbums = await withTaskGroup(of: (Int, [Album]).self) { group in
            for (index, artistID) in ids.enumerated() {
                group.addTask { (index, (try? await fetch(artistID)) ?? []) }
            }
            var byIndex: [Int: [Album]] = [:]
            for await (index, fetched) in group { byIndex[index] = fetched }
            return byIndex.sorted { $0.key < $1.key }.flatMap(\.value)
        }
        var seen = Set(albums.map(key))
        return albums + artistAlbums.filter { seen.insert(key($0)).inserted }
    }
}
