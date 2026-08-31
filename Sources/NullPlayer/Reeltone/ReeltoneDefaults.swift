import Foundation

/// Dedicated preferences domain for the Reeltone skin system.
///
/// Application-wide playback state and the selected UI mode remain app preferences. Everything
/// owned by Reeltone itself—skin selection, per-skin surfaces, and embedded-host presentation
/// defaults—lives in this suite and cannot collide with Classic, Original, Metal, or `.wal` keys.
enum ReeltoneDefaults {
    static let suiteName = "com.nullplayer.app.reeltone"
    static let migrationMarkerKey = "reeltone.defaults.migratedFromStandard.v1"

    static let shared: UserDefaults = {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create the Reeltone preferences domain")
        }
        migrateLegacy(from: .standard, to: defaults)
        return defaults
    }()

    static func migrateLegacy(from source: UserDefaults, to destination: UserDefaults) {
        guard !destination.bool(forKey: migrationMarkerKey) else { return }
        let keys = source.dictionaryRepresentation().keys.filter {
            $0 == ReeltoneSkinState.selectedSkinIdentityKey || $0.hasPrefix("reeltone.surface.")
        }
        for key in keys {
            if destination.object(forKey: key) == nil, let value = source.object(forKey: key) {
                destination.set(value, forKey: key)
            }
            source.removeObject(forKey: key)
        }
        destination.set(true, forKey: migrationMarkerKey)
    }
}
