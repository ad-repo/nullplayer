import Foundation
import SQLite

extension Notification.Name {
    /// Profiles or assignments changed; the profile controller re-resolves the playing track.
    static let eqProfilesDidChange = Notification.Name("eqProfilesDidChange")
}

/// A profile's curve in dB, per channel: 31 band gains and a preamp. The DSP's input.
struct EQCurve: Codable, Equatable {
    struct Channel: Codable, Equatable {
        static let flat = Channel(bands: Array(repeating: 0, count: EQProfileDesign.bandCount), preamp: 0)

        var bands: [Float]
        var preamp: Float

        /// Every value inside ±12 dB and 31 bands long, whatever a file held.
        func clamped() -> Channel {
            Channel(bands: (0..<EQProfileDesign.bandCount).map { bands.indices.contains($0) ? EQCurve.clamp(bands[$0]) : 0 },
                    preamp: EQCurve.clamp(preamp))
        }
    }

    static let range: ClosedRange<Float> = -12...12
    static let flat = EQCurve(left: .flat, right: .flat)

    var left: Channel
    var right: Channel

    var isFlat: Bool { self == .flat }

    /// Channel 0 is left, 1 right.
    subscript(channel: Int) -> Channel {
        get { channel == 0 ? left : right }
        set { if channel == 0 { left = newValue } else { right = newValue } }
    }

    func clamped() -> EQCurve { EQCurve(left: left.clamped(), right: right.clamped()) }

    static func clamp(_ value: Float) -> Float {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : 0
    }
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

    var profileID: UUID? {
        if case .profile(let id) = self { return id }
        return nil
    }
}

/// Track beats album beats artist.
enum EQProfileLevel: String, CaseIterable {
    case track, album, artist
}

/// What one assignment row is keyed on.
struct EQProfileScope: Hashable {
    let level: EQProfileLevel
    /// `plex:<serverId>` etc., `local`, `youtube` or `radio`.
    let source: String
    /// The track's id, `<artist>|<album>`, or the artist; names lower-cased and trimmed.
    let key: String
}

/// Profiles and their standing assignments, in `eq_profiles.db`, and the global toggle: storage
/// only — `EQProfileResolver` keys tracks, resolves them and words the result. A database that
/// cannot be opened leaves the store empty and writes nothing, so it never replaces what is on disk.
/// Main thread only.
final class EQProfileStore {
    static let shared = EQProfileStore()
    static let enabledKey = "eqProfilesEnabled"

    /// Playback Options ▸ EQ Profiles. Off: no assigned profile applies; assignments are kept.
    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            guard newValue != isEnabled else { return }
            defaults.set(newValue, forKey: Self.enabledKey)
            didChange()
        }
    }

    /// Bumped by every change, so a cache of what resolves can tell it is stale.
    private(set) var revision = 0

    private let db: Connection?
    private let defaults: UserDefaults

    private let profilesTable = Table("eq_profiles")
    private let colID = SQLite.Expression<String>("id")
    private let colName = SQLite.Expression<String>("name")
    private let colCurve = SQLite.Expression<String>("curve")

    /// A NULL `profile_id` is an explicit `Off`; deleting a profile cascades to its rows.
    private let assignmentsTable = Table("eq_profile_assignments")
    private let colLevel = SQLite.Expression<String>("level")
    private let colSource = SQLite.Expression<String>("source")
    private let colScopeKey = SQLite.Expression<String>("scope_key")
    private let colProfileID = SQLite.Expression<String?>("profile_id")

    /// `path` nil is an in-memory database.
    init(path: String? = EQProfileStore.defaultPath, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        db = Self.open(path)
    }

    static var defaultPath: String? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NullPlayer/eq_profiles.db").path
    }

    private static func open(_ path: String?) -> Connection? {
        do {
            let db: Connection
            if let path {
                try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                                                        withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                db = try Connection(path)
            } else {
                db = try Connection(.inMemory)
            }
            try db.execute("""
                PRAGMA foreign_keys = ON;
                CREATE TABLE IF NOT EXISTS eq_profiles (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    curve TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS eq_profile_assignments (
                    level TEXT NOT NULL,
                    source TEXT NOT NULL,
                    scope_key TEXT NOT NULL,
                    profile_id TEXT REFERENCES eq_profiles(id) ON DELETE CASCADE,
                    PRIMARY KEY (level, source, scope_key)
                );
                """)
            return db
        } catch {
            NSLog("[eqprofile] database unavailable: %@", String(describing: error))
            return nil
        }
    }

    var profiles: [EQProfile] { fetchProfiles(profilesTable) }

    /// By name, as every profile list shows them.
    var sortedProfiles: [EQProfile] {
        profiles.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func profile(_ id: UUID) -> EQProfile? { fetchProfiles(profilesTable.filter(colID == id.uuidString)).first }

    /// nil is Inherit: the rows are removed and the next level down applies.
    func assign(_ assignment: EQProfileAssignment?, scopes: Set<EQProfileScope>) {
        guard !scopes.isEmpty else { return }
        write { db in
            try db.transaction {
                for scope in scopes {
                    if let assignment {
                        try db.run(assignmentsTable.insert(or: .replace,
                                                           colLevel <- scope.level.rawValue,
                                                           colSource <- scope.source,
                                                           colScopeKey <- scope.key,
                                                           colProfileID <- assignment.profileID?.uuidString))
                    } else {
                        try db.run(rows(scope).delete())
                    }
                }
            }
        }
    }

    /// What is set at `scope`: nil is Inherit.
    func assignment(_ scope: EQProfileScope) -> EQProfileAssignment? {
        guard let db else { return nil }
        do {
            guard let row = try db.pluck(rows(scope).select(colProfileID)) else { return nil }
            guard let id = row[colProfileID] else { return .off }
            return UUID(uuidString: id).map { .profile($0) }
        } catch {
            NSLog("[eqprofile] read failed: %@", String(describing: error))
            return nil
        }
    }

    /// Every scope with an assignment at `level` in `source`.
    func assignedScopes(level: EQProfileLevel, source: String) -> [EQProfileScope] {
        guard let db else { return [] }
        do {
            return try db.prepare(assignmentsTable.select(colScopeKey)
                .filter(colLevel == level.rawValue && colSource == source))
                .map { EQProfileScope(level: level, source: source, key: $0[colScopeKey]) }
        } catch {
            NSLog("[eqprofile] read failed: %@", String(describing: error))
            return []
        }
    }

    /// nil when it could not be saved.
    func add(name: String, curve: EQCurve) -> EQProfile? {
        let profile = EQProfile(id: UUID(), name: name, curve: curve.clamped())
        let saved = write { db in
            try db.run(profilesTable.insert(colID <- profile.id.uuidString, colName <- profile.name,
                                            colCurve <- Self.encode(profile.curve)))
        }
        return saved ? profile : nil
    }

    func update(_ id: UUID, name: String? = nil, curve: EQCurve? = nil) {
        guard name != nil || curve != nil else { return }
        write { db in
            var setters: [Setter] = []
            if let name { setters.append(colName <- name) }
            if let curve { setters.append(try colCurve <- Self.encode(curve.clamped())) }
            try db.run(profilesTable.filter(colID == id.uuidString).update(setters))
        }
    }

    /// Its assignments go with it (the foreign key), so what used them falls through to the next level.
    func delete(_ id: UUID) {
        write { db in try db.run(profilesTable.filter(colID == id.uuidString).delete()) }
    }

    private func rows(_ scope: EQProfileScope) -> Table {
        assignmentsTable.filter(colLevel == scope.level.rawValue && colSource == scope.source && colScopeKey == scope.key)
    }

    private func fetchProfiles(_ query: Table) -> [EQProfile] {
        guard let db else { return [] }
        do {
            return try db.prepare(query).compactMap { row in
                guard let id = UUID(uuidString: row[colID]) else { return nil }
                guard let curve = try? JSONDecoder().decode(EQCurve.self, from: Data(row[colCurve].utf8)) else {
                    NSLog("[eqprofile] unreadable curve for %@; showing it flat", row[colName])
                    return EQProfile(id: id, name: row[colName], curve: .flat)
                }
                return EQProfile(id: id, name: row[colName], curve: curve.clamped())
            }
        } catch {
            NSLog("[eqprofile] read failed: %@", String(describing: error))
            return []
        }
    }

    private static func encode(_ curve: EQCurve) throws -> String {
        String(decoding: try JSONEncoder().encode(curve), as: UTF8.self)
    }

    /// Runs a change and announces it; false, and nothing announced, when it could not be written.
    @discardableResult
    private func write(_ change: (Connection) throws -> Void) -> Bool {
        guard let db else { return false }
        do {
            try change(db)
        } catch {
            NSLog("[eqprofile] save failed: %@", String(describing: error))
            return false
        }
        didChange()
        return true
    }

    private func didChange() {
        revision += 1
        NotificationCenter.default.post(name: .eqProfilesDidChange, object: self)
    }
}
