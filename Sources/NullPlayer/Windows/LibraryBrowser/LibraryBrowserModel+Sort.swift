import Foundation

/// The Sort menu's orders for rows sorted in memory: every source but the Local tabs the store pages.
extension LibraryBrowserModel {

    /// Rows by name, date added or year. Rows that carry no date (`created` nil) or no year
    /// (`year` nil) sort by name under those orders.
    func menuSorted<Item>(_ items: [Item], name: (Item) -> String,
                          created: ((Item) -> Date?)? = nil, year: ((Item) -> Int?)? = nil) -> [Item] {
        switch (currentSort, created, year) {
        case (.nameDesc, _, _):
            return items.sorted { compareNameStrings(name($0), name($1), ascending: false) }
        case (.dateAddedDesc, let created?, _):
            return items.sorted { (created($0) ?? .distantPast) > (created($1) ?? .distantPast) }
        case (.dateAddedAsc, let created?, _):
            return items.sorted { (created($0) ?? .distantPast) < (created($1) ?? .distantPast) }
        case (.yearDesc, _, let year?):
            return items.sorted { (year($0) ?? 0) > (year($1) ?? 0) }
        case (.yearAsc, _, let year?):
            return items.sorted { (year($0) ?? 0) < (year($1) ?? 0) }
        default:
            return items.sorted { compareNameStrings(name($0), name($1), ascending: true) }
        }
    }

    /// Subsonic, Jellyfin and Emby artists carry no dates of their own: the date and year sorts go
    /// by their albums' newest (descending) or oldest (ascending). An artist type with a
    /// `sortIndexLetter` (Subsonic's) groups the name sort by the server's index letter (e.g.
    /// "The Atlas Moth" under T, as Navidrome does).
    func sortedServerArtists<Artist: BrowsableArtist>(_ artists: [Artist], albums: [some BrowsableAlbum]) -> [Artist] {
        let indexLetter = Artist.sortIndexLetter
        var newestAdded: [String: Date] = [:]
        var oldestAdded: [String: Date] = [:]
        var newestYear: [String: Int] = [:]
        var oldestYear: [String: Int] = [:]
        for album in albums {
            guard let key = Self.serverArtistKey(id: album.artistId, name: album.artist) else { continue }
            if let created = album.created {
                newestAdded[key] = max(newestAdded[key] ?? .distantPast, created)
                oldestAdded[key] = min(oldestAdded[key] ?? .distantFuture, created)
            }
            if let year = album.year {
                newestYear[key] = max(newestYear[key] ?? Int.min, year)
                oldestYear[key] = min(oldestYear[key] ?? Int.max, year)
            }
        }

        func key(_ artist: Artist) -> String? { Self.serverArtistKey(id: artist.id, name: artist.name) }
        func byName(_ lhs: Artist, _ rhs: Artist, ascending: Bool) -> Bool {
            if let indexLetter {
                let l0 = LibraryBrowserItem.normalizedIndexLetter(indexLetter(lhs)) ?? LibraryBrowserItem.sortLetter(forTitle: lhs.name)
                let l1 = LibraryBrowserItem.normalizedIndexLetter(indexLetter(rhs)) ?? LibraryBrowserItem.sortLetter(forTitle: rhs.name)
                if l0 != l1 { return ascending ? l0 < l1 : l0 > l1 }
            }
            return compareNameStrings(lhs.name, rhs.name, ascending: ascending)
        }
        /// By the artist's value (missing = `fallback`), then by name ascending.
        func by<Value: Comparable>(_ lhs: Artist, _ rhs: Artist, _ values: [String: Value], fallback: Value, descending: Bool) -> Bool {
            let v0 = key(lhs).flatMap { values[$0] } ?? fallback
            let v1 = key(rhs).flatMap { values[$0] } ?? fallback
            if v0 != v1 { return descending ? v0 > v1 : v0 < v1 }
            return compareNameStrings(lhs.name, rhs.name, ascending: true)
        }

        switch currentSort {
        case .nameAsc: return artists.sorted { byName($0, $1, ascending: true) }
        case .nameDesc: return artists.sorted { byName($0, $1, ascending: false) }
        case .dateAddedDesc: return artists.sorted { by($0, $1, newestAdded, fallback: .distantPast, descending: true) }
        case .dateAddedAsc: return artists.sorted { by($0, $1, oldestAdded, fallback: .distantPast, descending: false) }
        case .yearDesc: return artists.sorted { by($0, $1, newestYear, fallback: 0, descending: true) }
        case .yearAsc: return artists.sorted { by($0, $1, oldestYear, fallback: 0, descending: false) }
        }
    }

    /// An artist's identity across its albums: the id, else the trimmed, lowercased name.
    private static func serverArtistKey(id: String?, name: String?) -> String? {
        if let id, !id.isEmpty { return "id:\(id)" }
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return "name:\(name.lowercased())"
    }

    /// An album's tracks by disc, then track number.
    func discOrdered<Song>(_ songs: [Song], disc: (Song) -> Int?, track: (Song) -> Int?) -> [Song] {
        songs.sorted {
            let d0 = disc($0) ?? 1; let d1 = disc($1) ?? 1
            if d0 != d1 { return d0 < d1 }
            return (track($0) ?? 0) < (track($1) ?? 0)
        }
    }
}
