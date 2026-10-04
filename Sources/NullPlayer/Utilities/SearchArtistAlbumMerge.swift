import Foundation

/// Completes a server search's album list with the albums of the artists it matched.
///
/// Every server search caps or filters albums — Subsonic's `albumCount`, the single Jellyfin/Emby
/// `Limit` shared by every item type (whose `searchTerm` also matches album names only), Plex's
/// per-hub `limit` — so a prolific artist loses most of its albums. Each manager's
/// `searchWithArtistAlbums` merges the full album list of its first `artistLimit` matched artists
/// through here, fetched the way its Artists tab fetches them.
enum SearchArtistAlbumMerge {
    /// Bounds the fan-out, so a broad query does not fetch dozens of artists.
    static let artistLimit = 10

    /// `albums` followed by each artist's albums, in artist order, skipping any album whose `key`
    /// is already present. An artist whose fetch fails contributes nothing.
    static func merged<Artist: Sendable, Album: Sendable>(
        _ albums: [Album],
        artists: [Artist],
        key: (Album) -> String,
        fetch: @escaping @Sendable (Artist) async throws -> [Album]
    ) async -> [Album] {
        let artists = Array(artists.prefix(artistLimit))
        guard !artists.isEmpty else { return albums }
        let artistAlbums = await withTaskGroup(of: (Int, [Album]).self) { group in
            for (index, artist) in artists.enumerated() {
                group.addTask {
                    do {
                        return (index, try await fetch(artist))
                    } catch {
                        if !Task.isCancelled {
                            NSLog("SearchArtistAlbumMerge: artist album fetch failed: %@",
                                  error.localizedDescription.redactingSensitiveURLQueryItems)
                        }
                        return (index, [])
                    }
                }
            }
            var byArtist = [[Album]](repeating: [], count: artists.count)
            for await (index, fetched) in group { byArtist[index] = fetched }
            return byArtist.joined()
        }
        var seen = Set(albums.map(key))
        return albums + artistAlbums.filter { seen.insert(key($0)).inserted }
    }
}
