import Foundation

/// **What a `.wmz` may see of this player's library: the source the library browser has selected,
/// read-only** (W66/W136, decided 2026-09-24).
///
/// WMP's `player.mediaCollection` and `player.playlistCollection` are how a skin fills its own
/// playlist chooser and library pickers — `WoW`'s `plListBox1` is `playlistCollection.getAll()`,
/// `digitaldj`'s genre/artist/album boxes are `mediaCollection.getAttributeStringCollection`. In
/// NullPlayer "the library" is whatever the browser's source picker is on, so that is what a skin
/// is answered from. Writes (`newPlaylist`, `add`, `remove`, `importPlaylist`) stay refused.
///
/// An immutable value the host builds off the main actor and hands the script runtime whole; the
/// object model reads it and never touches the store, the file system or the network.
struct WMPLibraryCatalog: Sendable, Equatable {
    struct Track: Sendable, Equatable {
        var title: String
        var artist: String
        var album: String
        var genre: String
        var sourceURL: String
        var duration: TimeInterval
        var isVideo: Bool
    }

    struct Playlist: Sendable, Equatable {
        /// The source's own id for it — a server playlist id, a local playlist's file URL. **A
        /// skin's reference is by id, not by position**: a server re-lists its playlists whenever
        /// it reloads, and a reference by position then named whichever playlist moved into it.
        var id: String
        var name: String
        /// Indices into `tracks`. Meaningful only once `loaded`: a server playlist is listed by
        /// name first and its tracks fetched the first time a skin asks for them.
        var tracks: [Int]
        var loaded = true
    }

    /// Which source this is — `local`, `plex:<server>` … — so a switch can be told from a refresh.
    var sourceID = "local"
    /// **Whether every track of the source is in `tracks`.** True for Local Files, whose queries
    /// are answered by filtering. A server's library is far too large to hold, so its queries are
    /// fetched on demand into `queryResults`, and `strings` comes from its own cached lists.
    var isComplete = true
    /// Fetched `getByAttribute` answers, keyed by `queryKey(_:_:)`.
    var queryResults: [String: [Int]] = [:]
    /// `getAttributeStringCollection` answers for an incomplete source, keyed by attribute name
    /// (`artist`, `album`, `genre`).
    var strings: [String: [String]] = [:]

    var tracks: [Track] = []
    /// Indices into `tracks` of the library proper — every scanned track for Local Files, and
    /// **empty for a server**, whose library cannot be listed. A saved playlist, a fetched server
    /// playlist and a search result can all name tracks outside it; those rows exist only so the
    /// list naming them can hold them.
    var libraryTracks: [Int] = []
    var playlists: [Playlist] = []

    static let empty = WMPLibraryCatalog()

    // MARK: Queries

    /// WMP's attribute names as the corpus spells them, folded onto the four this catalog carries.
    enum Attribute { case title, artist, album, genre, mediaType, sourceURL }

    static func attribute(_ name: String) -> Attribute? {
        switch name.lowercased() {
        case "title", "name": return .title
        case "artist", "author", "wm/albumartist", "displayartist": return .artist
        case "album", "wm/albumtitle": return .album
        case "genre", "wm/genre": return .genre
        case "mediatype": return .mediaType
        case "sourceurl": return .sourceURL
        default: return nil
        }
    }

    func value(of attribute: Attribute, track index: Int) -> String {
        guard tracks.indices.contains(index) else { return "" }
        let track = tracks[index]
        switch attribute {
        case .title: return track.title
        case .artist: return track.artist
        case .album: return track.album
        case .genre: return track.genre
        case .mediaType: return track.isVideo ? "video" : "audio"
        case .sourceURL: return track.sourceURL
        }
    }

    /// `getByAttribute(name, value)` and its `getByAlbum`/`getByGenre`/`getByAuthor` spellings:
    /// library tracks whose attribute equals the value, ignoring case the way WMP's library does.
    static func queryKey(_ attribute: Attribute, _ value: String) -> String {
        "\(attribute):\(value.lowercased())"
    }

    func tracks(where attribute: Attribute, equals wanted: String) -> [Int] {
        libraryTracks.filter {
            value(of: attribute, track: $0).caseInsensitiveCompare(wanted) == .orderedSame
        }
    }

    /// `getAttributeStringCollection(attribute, mediaType)`: the distinct non-empty values, sorted.
    func strings(of attribute: Attribute, mediaType: String) -> [String] {
        if !isComplete {
            let key: String
            switch attribute {
            case .artist: key = "artist"
            case .album: key = "album"
            case .genre: key = "genre"
            default: return []
            }
            return strings[key] ?? []
        }
        let type = mediaType.lowercased()
        var seen = Set<String>(), result: [String] = []
        for index in libraryTracks {
            if !type.isEmpty, value(of: .mediaType, track: index) != type { continue }
            let item = value(of: attribute, track: index)
            guard !item.isEmpty, seen.insert(item.lowercased()).inserted else { continue }
            result.append(item)
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// `playlists` by id. **Every per-playlist call a skin makes goes through here**, and `WoW`'s
    /// `fillListBox()` makes several for each of a server's playlists inside one `onLoad` — 1,850
    /// on the Jellyfin server this was measured against. A scan per call made that quadratic and
    /// ran the handler past the 0.25 s script limit, which killed it after `deleteAll()` and left
    /// the chooser empty. Rebuilt by `indexPlaylists()` whenever `playlists` is replaced.
    private(set) var playlistIndexByID: [String: Int] = [:]

    mutating func indexPlaylists() {
        playlistIndexByID = Dictionary(playlists.enumerated().map { ($1.id, $0) },
                                       uniquingKeysWith: { first, _ in first })
    }

    func playlistIndex(id: String) -> Int? {
        playlistIndexByID[id]
    }

    func playlists(named name: String) -> [Int] {
        playlists.indices.filter { playlists[$0].name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

/// What a skin's script has put into its own list-like controls beyond their rows (W136): the
/// playlist a `<PLAYLIST>` was pointed at with `playlist1.playlist = …`, and the row a `<LISTBOX>`
/// script selected. Transaction output, read on the script queue with the rows themselves.
struct WMPWidgetScriptState: Sendable, Equatable {
    struct PlaylistRows: Sendable, Equatable {
        /// The object path of the playlist shown, so playing it can make it the current one.
        var reference: String
        var items: [WMPPlaylistItemSnapshot]
        /// Catalog indices, by row — what a double-click hands back to be played.
        var tracks: [Int]
    }

    /// `<PLAYLIST>` stable id to the library playlist it shows. Absent means the current playlist.
    var playlists: [Int: PlaylistRows] = [:]
    /// `<LISTBOX>` stable id to the `selectedItem` its script wrote in this transaction.
    var listSelections: [Int: Int] = [:]
    /// `<EDITBOX>` stable id to its `value` — `WoW`'s "Search..." placeholder, which its own
    /// `onFocus`/`onBlur` clear and restore.
    var editValues: [Int: String] = [:]

    static let empty = WMPWidgetScriptState()
}
