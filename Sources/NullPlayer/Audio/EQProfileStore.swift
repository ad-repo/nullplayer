import Foundation

extension Notification.Name {
    /// Profiles or assignments changed; the profile controller re-resolves the playing track.
    static let eqProfilesDidChange = Notification.Name("eqProfilesDidChange")
}

struct EQProfile: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var curve: EQCurve
}

enum EQProfileAssignment: Codable, Equatable {
    case profile(UUID)
    /// Explicitly no profile at this level; resolution stops here.
    case off
}

/// Track beats album beats artist.
enum EQProfileLevel: String, CaseIterable {
    case track, album, artist
}

extension Track {
    /// The source an assignment is scoped to: each media server by its id, then local, YouTube, radio.
    var eqProfileSource: String {
        switch playHistorySource {
        case .plex: return "plex:\(plexServerId ?? "")"
        case .subsonic: return "subsonic:\(subsonicServerId ?? "")"
        case .jellyfin: return "jellyfin:\(jellyfinServerId ?? "")"
        case .emby: return "emby:\(embyServerId ?? "")"
        case .local, .youtube, .radio: return playHistorySource.rawValue
        }
    }

    /// This track's assignment keys, most specific first. A level is omitted when its names are
    /// empty; radio has only a track key. `Track` has no album artist or album id, so the album key
    /// carries the artist — otherwise every "Greatest Hits" in a source would share one assignment.
    var eqProfileKeys: [(level: EQProfileLevel, key: String)] {
        func norm(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
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
        var keys: [(level: EQProfileLevel, key: String)] = [(.track, "track|\(source)|\(id)")]
        guard playHistorySource != .radio else { return keys }
        let artist = norm(artist), album = norm(album)
        if !album.isEmpty { keys.append((.album, "album|\(source)|\(artist)|\(album)")) }
        if !artist.isEmpty { keys.append((.artist, "artist|\(source)|\(artist)")) }
        return keys
    }
}

/// Profiles and their standing assignments, in `eq_profiles.json`, written on every change.
/// Main thread only.
final class EQProfileStore {
    static let shared = EQProfileStore()
    static let enabledKey = "eqProfilesEnabled"

    /// Playback Options ▸ EQ Profiles. Off: no assigned profile applies; assignments are kept.
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            didChange()
        }
    }

    /// `appliesProfile(to:)` per track id; emptied on every change. Queue views ask for every row
    /// they build, and a `.wal` playlist snapshot builds them all.
    private var appliesCache: [UUID: Bool] = [:]

    private struct File: Codable {
        var profiles: [EQProfile] = []
        var assignments: [String: EQProfileAssignment] = [:]
    }

    private var file: File
    private let url: URL?

    var profiles: [EQProfile] { file.profiles }

    init(url: URL? = EQProfileStore.defaultURL) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(File.self, from: data) {
            file = decoded
            for index in file.profiles.indices { file.profiles[index].curve = file.profiles[index].curve.clamped() }
        } else {
            file = File()
        }
    }

    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NullPlayer/eq_profiles.json")
    }

    func profile(_ id: UUID) -> EQProfile? { file.profiles.first { $0.id == id } }

    /// The first level with an assignment: its profile, or nil for an explicit `Off`.
    func resolve(_ track: Track) -> (profile: EQProfile?, level: EQProfileLevel)? {
        for (level, key) in track.eqProfileKeys {
            switch file.assignments[key] {
            case .profile(let id): if let profile = profile(id) { return (profile, level) }
            case .off: return (nil, level)
            case nil: continue
            }
        }
        return nil
    }

    /// What is set at `level` itself for `track`: nil is Inherit.
    func assignment(at level: EQProfileLevel, of track: Track) -> EQProfileAssignment? {
        track.eqProfileKeys.first { $0.level == level }.flatMap { file.assignments[$0.key] }
    }

    /// Whether a profile is running on `track` when it plays: audio (video has no local graph),
    /// profiles on, and a profile — not `Off` — resolved. The queue's row marker.
    func appliesProfile(to track: Track) -> Bool {
        if let cached = appliesCache[track.id] { return cached }
        let applies = track.mediaType == .audio && isEnabled && resolve(track)?.profile != nil
        appliesCache[track.id] = applies
        return applies
    }

    /// What resolves for `track`: "Warm (album)" or "Off (track)"; nil when nothing is assigned.
    func setting(of track: Track) -> String? {
        resolve(track).map { "\($0.profile?.name ?? "Off") (\($0.level.rawValue))" }
    }

    /// File Info's line: the setting, or "None" — and that profiles are off, when they are.
    func describe(_ track: Track) -> String {
        let setting = setting(of: track) ?? "None"
        return isEnabled ? setting : "\(setting) — EQ Profiles are turned off"
    }

    /// nil is Inherit: the keys are removed and the next level down applies. Album level keys every
    /// distinct (artist, album) pair among `tracks`, so a compilation is covered whole; artist level
    /// every distinct artist.
    func assign(_ assignment: EQProfileAssignment?, level: EQProfileLevel, tracks: [Track]) {
        let keys = Set(tracks.compactMap { track in track.eqProfileKeys.first { $0.level == level }?.key })
        guard !keys.isEmpty else { return }
        for key in keys { file.assignments[key] = assignment }
        commit()
    }

    @discardableResult
    func add(name: String, curve: EQCurve) -> EQProfile {
        let profile = EQProfile(id: UUID(), name: name, curve: curve.clamped())
        file.profiles.append(profile)
        commit()
        return profile
    }

    func update(_ id: UUID, name: String? = nil, curve: EQCurve? = nil) {
        guard let index = file.profiles.firstIndex(where: { $0.id == id }) else { return }
        if let name { file.profiles[index].name = name }
        if let curve { file.profiles[index].curve = curve.clamped() }
        commit()
    }

    /// Its assignments go with it, so what used them falls through to the next level.
    func delete(_ id: UUID) {
        file.profiles.removeAll { $0.id == id }
        file.assignments = file.assignments.filter { $0.value != .profile(id) }
        commit()
    }

    private func commit() {
        if let url {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(file).write(to: url, options: .atomic)
            } catch {
                NSLog("[eqprofile] save failed: %@", error.localizedDescription)
            }
        }
        didChange()
    }

    private func didChange() {
        appliesCache.removeAll()
        NotificationCenter.default.post(name: .eqProfilesDidChange, object: self)
    }
}
