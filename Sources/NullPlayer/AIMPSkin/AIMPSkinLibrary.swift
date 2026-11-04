import Foundation
import os

/// The music library a skin's own library window shows (`MusicLibraryFrame`: its `MLGroupingTree`
/// and `MLTable`), over one build of NullPlayer's library (`AIMPSkinLibrarySource`): the window
/// draws at 30 frames a second and a library runs to thousands of tracks, so groups and filtered
/// lists are worked out here and kept until asked for differently.
///
/// The tree groups two levels deep by a grouping preset (artist then album by default), under an
/// "All Tracks" row; the table lists the selected group's tracks in album order, narrowed by the
/// quick search. Names sort as the library browser sorts them (`LibraryTextSorter`).
final class AIMPSkinLibrary: Sendable {
    /// AIMP's grouping presets, as far as NullPlayer's tags reach.
    enum Grouping: Int, CaseIterable, Sendable {
        case artistAlbum, albumArtistAlbum, genreArtist, yearAlbum, folder

        var title: String {
            switch self {
            case .artistAlbum: return "Artist / Album"
            case .albumArtistAlbum: return "Album Artist / Album"
            case .genreArtist: return "Genre / Artist"
            case .yearAlbum: return "Year / Album"
            case .folder: return "Folder"
            }
        }

        /// A track's group and subgroup; an empty subgroup is none.
        func keys(_ track: LibraryTrack) -> (String, String) {
            func named(_ text: String?, _ unknown: String) -> String { text.flatMap { $0.isEmpty ? nil : $0 } ?? unknown }
            switch self {
            case .artistAlbum: return (named(track.artist, "Unknown Artist"), named(track.album, "Unknown Album"))
            case .albumArtistAlbum:
                return (named(track.albumArtist.flatMap { $0.isEmpty ? nil : $0 } ?? track.artist, "Unknown Artist"),
                        named(track.album, "Unknown Album"))
            case .genreArtist: return (named(track.genre, "Unknown Genre"), named(track.artist, "Unknown Artist"))
            case .yearAlbum: return ((track.year ?? 0) > 0 ? String(track.year ?? 0) : "Unknown Year", named(track.album, "Unknown Album"))
            case .folder: return (named(track.url.deletingLastPathComponent().lastPathComponent, "Unknown Folder"), "")
            }
        }
    }

    /// A row of the tree: "All Tracks" (`path` empty), a group, or a group's subgroup (`path` the
    /// two joined by `separator`).
    struct Row: Equatable, Sendable {
        var path: String
        var name: String
        var level: Int
        var count: Int
        var expandable: Bool
    }

    static let separator = "\u{1F}"

    let tracks: [LibraryTrack]
    /// Each track's index in `tracks`, by id.
    private let indexByID: [UUID: Int]

    init(tracks: [LibraryTrack]) {
        self.tracks = tracks
        indexByID = Dictionary(tracks.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The tracks with `ids`, in their order; an id this build does not have is left out.
    func tracks(_ ids: [UUID]) -> [LibraryTrack] { ids.compactMap { indexByID[$0].map { tracks[$0] } } }

    /// A track's length in whole seconds, 0 when unknown.
    static func seconds(_ track: LibraryTrack) -> Int { track.duration.isFinite && track.duration > 0 ? Int(track.duration) : 0 }

    private static func ascending(_ a: String, _ b: String) -> Bool { LibraryTextSorter.compare(a, b) == .orderedAscending }

    private struct Group: Sendable {
        var name: String
        var count: Int
        var children: [(name: String, count: Int)]
    }

    /// What the lists were last worked out as: a window asks every frame, from whichever thread
    /// draws it, so the caches are behind a lock (held only to read or store, never while working).
    /// The library build's own, not a skin's: the host hands the same build to every skin it runs.
    private struct Caches: Sendable {
        var groups: [Grouping: [Group]] = [:]
        var orders: [Grouping: [Int]] = [:]
        var rows: (key: String, rows: [Row])?
        var tables: [String: [Int]] = [:]
    }
    private let caches = OSAllocatedUnfairLock(initialState: Caches())

    private func cached<T>(_ read: (Caches) -> T) -> T { caches.withLockUnchecked { read($0) } }
    private func store(_ write: (inout Caches) -> Void) { caches.withLockUnchecked { write(&$0) } }

    private func groups(_ grouping: Grouping) -> [Group] {
        if let cached = cached({ $0.groups[grouping] }) { return cached }
        var counts: [String: (count: Int, children: [String: Int])] = [:]
        for track in tracks {
            let (top, sub) = grouping.keys(track)
            var entry = counts[top] ?? (0, [:])
            entry.count += 1
            if !sub.isEmpty { entry.children[sub, default: 0] += 1 }
            counts[top] = entry
        }
        let groups = counts.keys.sorted(by: grouping == .yearAlbum ? { $0 > $1 } : Self.ascending).map { name in
            Group(name: name, count: counts[name]!.count,
                  children: counts[name]!.children.keys.sorted(by: Self.ascending).map { ($0, counts[name]!.children[$0]!) })
        }
        store { $0.groups[grouping] = groups }
        return groups
    }

    /// The tree's rows: "All Tracks", then each group, with its subgroups under it while
    /// expanded. A search keeps the groups whose name, or a subgroup's, holds every word of it.
    func rows(_ grouping: Grouping, expanded: Set<String>, search: String) -> [Row] {
        let key = "\(grouping.rawValue)|\(expanded.sorted().joined(separator: Self.separator))|\(search)"
        if let cached = cached({ $0.rows }), cached.key == key { return cached.rows }
        let words = search.lowercased().split(separator: " ")
        func matches(_ text: String) -> Bool { words.allSatisfy { text.lowercased().contains($0) } }
        var rows = [Row(path: "", name: "All Tracks", level: 0, count: tracks.count, expandable: false)]
        for group in groups(grouping) {
            let children = words.isEmpty || matches(group.name) ? group.children : group.children.filter { matches($0.name) }
            guard words.isEmpty || matches(group.name) || !children.isEmpty else { continue }
            rows.append(Row(path: group.name, name: group.name, level: 0, count: group.count, expandable: !group.children.isEmpty))
            guard expanded.contains(group.name) || !words.isEmpty else { continue }
            for child in children {
                rows.append(Row(path: group.name + Self.separator + child.name, name: child.name, level: 1, count: child.count,
                                expandable: false))
            }
        }
        store { $0.rows = (key, rows) }
        return rows
    }

    /// The table: the tracks under the tree's `path` (all of them for "All Tracks"), by group, year,
    /// album, disc and number, narrowed to those whose title, artist or album hold every word of
    /// `search`. Indices into `tracks`.
    func table(_ grouping: Grouping, path: String, search: String) -> [Int] {
        let key = "\(grouping.rawValue)|\(path)|\(search)"
        if let cached = cached({ $0.tables[key] }) { return cached }
        let parts = path.components(separatedBy: Self.separator)
        let words = search.lowercased().split(separator: " ")
        let indices = order(grouping).filter { index in
            let track = tracks[index]
            if !path.isEmpty {
                let (top, sub) = grouping.keys(track)
                guard top == parts[0], parts.count < 2 || sub == parts[1] else { return false }
            }
            guard !words.isEmpty else { return true }
            let text = "\(track.title) \(track.artist ?? "") \(track.album ?? "")".lowercased()
            return words.allSatisfy { text.contains($0) }
        }
        // A handful of recent lists (a menu asks for the group's whole list beside the shown one).
        store { caches in
            if caches.tables.count > 8 { caches.tables.removeAll() }
            caches.tables[key] = indices
        }
        return indices
    }

    /// Every track by group, album, disc, number and title, sorted once per grouping.
    private func order(_ grouping: Grouping) -> [Int] {
        if let cached = cached({ $0.orders[grouping] }) { return cached }
        let keys = tracks.map { (group: grouping.keys($0).0, album: $0.album ?? "", disc: $0.discNumber ?? 0, number: $0.trackNumber ?? 0,
                                 title: $0.title) }
        let order = tracks.indices.sorted { a, b in
            let x = keys[a], y = keys[b]
            if x.group != y.group { return Self.ascending(x.group, y.group) }
            if x.album != y.album { return Self.ascending(x.album, y.album) }
            if x.disc != y.disc { return x.disc < y.disc }
            if x.number != y.number { return x.number < y.number }
            return Self.ascending(x.title, y.title)
        }
        store { $0.orders[grouping] = order }
        return order
    }
}

extension AIMPSkinLibrary: Equatable {
    /// One library is one build of it: a rebuild is a change.
    static func == (lhs: AIMPSkinLibrary, rhs: AIMPSkinLibrary) -> Bool { lhs === rhs }
}
