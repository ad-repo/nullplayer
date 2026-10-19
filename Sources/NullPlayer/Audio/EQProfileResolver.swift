import Foundation

extension Track {
    /// The source an assignment is scoped to: each media server by its id, then local, YouTube, radio.
    var eqProfileSource: String {
        switch playHistorySource {
        case .plex: return EQProfileScope.source(.plex, serverId: plexServerId)
        case .subsonic: return EQProfileScope.source(.subsonic, serverId: subsonicServerId)
        case .jellyfin: return EQProfileScope.source(.jellyfin, serverId: jellyfinServerId)
        case .emby: return EQProfileScope.source(.emby, serverId: embyServerId)
        case .local, .youtube, .radio: return playHistorySource.rawValue
        }
    }

    /// Where this track's assignments apply, most specific first. A level is omitted when its names
    /// are empty; radio has only a track scope. `Track` has no album artist or album id, so the album
    /// key carries the artist — otherwise every "Greatest Hits" in a source would share one assignment.
    var eqProfileScopes: [EQProfileScope] {
        let source = eqProfileSource
        let id: String
        switch playHistorySource {
        case .plex: id = plexRatingKey ?? ""
        case .subsonic: id = subsonicId ?? ""
        case .jellyfin: id = jellyfinId ?? ""
        case .emby: id = embyId ?? ""
        case .radio: id = url.absoluteString
        case .local, .youtube:
            id = (cueSourceURL ?? url).path + (cueStartOffset.map { "@\($0)" } ?? "")
        }
        let scope = EQProfileScope(level: .track, source: source, key: id)
        guard playHistorySource != .radio else { return [scope] }
        return [scope] + EQProfileScope.containers(source: source, artist: artist, album: album)
    }

    func eqProfileScope(at level: EQProfileLevel) -> EQProfileScope? {
        eqProfileScopes.first { $0.level == level }
    }
}

extension EQProfileScope {
    /// A server source carries its server's id.
    static func source(_ source: PlayHistorySource, serverId: String?) -> String {
        "\(source.rawValue):\(serverId ?? "")"
    }

    /// The album then artist scope for these names; a level is omitted when its names are empty.
    /// A library album or artist row keys itself with this, without fetching its tracks.
    static func containers(source: String, artist: String?, album: String?) -> [EQProfileScope] {
        func norm(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let artist = norm(artist), album = norm(album)
        var scopes: [EQProfileScope] = []
        if !album.isEmpty { scopes.append(EQProfileScope(level: .album, source: source, key: "\(artist)|\(album)")) }
        if !artist.isEmpty { scopes.append(EQProfileScope(level: .artist, source: source, key: artist)) }
        return scopes
    }

    /// A YouTube download's track scope, keyed as `Track.eqProfileScopes` keys its audio file but
    /// without reading the file's tags. A video row's marker reads only this level.
    // ponytail: every YouTube assign is track level (a video's menu, the queue's), so this is exact
    // unless a library album or artist holds the download folder's files; read their tags if it does.
    static func youtubeTrack(audioFile: URL) -> EQProfileScope {
        EQProfileScope(level: .track, source: PlayHistorySource.youtube.rawValue, key: audioFile.path)
    }
}

extension Array where Element == EQProfileScope {
    /// The scopes from `level` down; empty when there is none at `level`. Every scope list is
    /// ordered track, album, artist (`Track.eqProfileScopes`, `containers`), a missing level omitted.
    func from(_ level: EQProfileLevel) -> [EQProfileScope] {
        Array(drop { $0.level != level })
    }
}

/// What the store's assignments mean for a track — which profile resolves, whether a queue row is
/// marked — and how that is worded. Runs on its store's thread: `shared` is the main thread's.
final class EQProfileResolver {
    static let shared = EQProfileResolver(store: .shared)

    let store: EQProfileStore

    /// `appliesProfile(to:)` per track id, for the store revision it was built at. Queue views ask
    /// for every row they build, and a `.wal` playlist snapshot builds them all.
    private var appliesCache: [UUID: Bool] = [:]
    private var cacheRevision = -1

    init(store: EQProfileStore) {
        self.store = store
    }

    /// The first level with an assignment: its profile, or nil for an explicit `Off`.
    func resolve(_ track: Track) -> (profile: EQProfile?, level: EQProfileLevel)? {
        resolve(track.eqProfileScopes)
    }

    /// The first of `scopes`, most specific first, with an assignment.
    func resolve(_ scopes: [EQProfileScope]) -> (profile: EQProfile?, level: EQProfileLevel)? {
        for scope in scopes {
            switch store.assignment(scope) {
            case .profile(let id): if let profile = store.profile(id) { return (profile, scope.level) }
            case .off: return (nil, scope.level)
            case nil: continue
            }
        }
        return nil
    }

    /// What runs on `track`: nil when profiles are off, nothing is assigned, or `Off` resolved.
    func activeProfile(for track: Track) -> (profile: EQProfile, level: EQProfileLevel)? {
        activeProfile(for: track.eqProfileScopes)
    }

    func activeProfile(for scopes: [EQProfileScope]) -> (profile: EQProfile, level: EQProfileLevel)? {
        guard store.isEnabled, let match = resolve(scopes), let profile = match.profile else { return nil }
        return (profile, match.level)
    }

    /// nil is Inherit. Album level keys every distinct (artist, album) pair among `tracks`, so a
    /// compilation is covered whole; artist level every distinct artist. Returns the scopes written.
    @discardableResult
    func assign(_ assignment: EQProfileAssignment?, level: EQProfileLevel, tracks: [Track]) -> Set<EQProfileScope> {
        let scopes = Set(tracks.compactMap { $0.eqProfileScope(at: level) })
        store.assign(assignment, scopes: scopes)
        return scopes
    }

    /// Whether a profile is running on `track` when it plays: audio (video has no local graph) and
    /// an active profile. The queue's row marker.
    func appliesProfile(to track: Track) -> Bool {
        if cacheRevision != store.revision {
            appliesCache.removeAll()
            cacheRevision = store.revision
        }
        if let cached = appliesCache[track.id] { return cached }
        let applies = track.mediaType == .audio && activeProfile(for: track) != nil
        appliesCache[track.id] = applies
        return applies
    }

    /// A library row's marker: a profile is active on every one of its items' scopes, most specific
    /// first (`LibraryBrowserActions.eqProfileScopes(for:)`). The list caches it per row.
    func appliesProfile(toRow items: [[EQProfileScope]]) -> Bool {
        !items.isEmpty && items.allSatisfy { activeProfile(for: $0) != nil }
    }

    /// A queue row's title as every playlist surface draws it: `∿` before it when `marked`.
    static func queueTitle(_ title: String, marked: Bool) -> String {
        marked ? "∿ \(title)" : title
    }

    func queueTitle(for track: Track) -> String {
        Self.queueTitle(track.playlistTitle, marked: appliesProfile(to: track))
    }

    /// What resolves for `track`: "Warm (album)" or "Off (track)"; nil when nothing is assigned.
    func setting(of track: Track) -> String? {
        setting(of: track.eqProfileScopes)
    }

    func setting(of scopes: [EQProfileScope]) -> String? {
        resolve(scopes).map { "\($0.profile?.name ?? "Off") (\($0.level.rawValue))" }
    }

    /// File Info's line: the setting, or "None" — and that profiles are off, when they are. nil for
    /// video, which has no local graph to run a profile in.
    func fileInfoLine(for track: Track) -> String? {
        guard track.mediaType == .audio else { return nil }
        let setting = setting(of: track) ?? "None"
        return "EQ Profile: " + (store.isEnabled ? setting : "\(setting) — EQ Profiles are turned off")
    }

    /// Drops local track assignments whose file is gone, so a new file at a moved one's old path
    /// does not inherit its profile. The file checks run off the main thread: a sleeping network
    /// share can take seconds to answer. Server, radio and YouTube rows are never touched.
    func pruneMissingLocalTracks(completion: (() -> Void)? = nil) {
        let scopes = store.assignedScopes(level: .track, source: PlayHistorySource.local.rawValue)
        DispatchQueue.global(qos: .utility).async {
            let gone = scopes.filter { Self.isMissingLocalFile($0.key) }
            DispatchQueue.main.async {
                if !gone.isEmpty { NSLog("[eqprofile] pruned %d assignment(s) for missing files", gone.count) }
                self.store.assign(nil, scopes: Set(gone))
                completion?()
            }
        }
    }

    /// A local track key is the file path, plus `@<offset>` for a cue track. A file on a volume that
    /// is not mounted is not missing: unplugging a drive must not drop its assignments.
    static func isMissingLocalFile(_ key: String) -> Bool {
        let files = FileManager.default
        if files.fileExists(atPath: key) { return false }
        let path = key.lastIndex(of: "@").map { String(key[..<$0]) } ?? key
        let components = URL(fileURLWithPath: path).pathComponents
        if components.count > 2, components[1] == "Volumes", !files.fileExists(atPath: "/Volumes/\(components[2])") {
            return false
        }
        return !files.fileExists(atPath: path)
    }
}
