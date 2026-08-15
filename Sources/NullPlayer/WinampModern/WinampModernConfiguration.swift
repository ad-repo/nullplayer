import Foundation

/// Sandboxed persistence surface shared by MAKI private values, configuration
/// objects, active color theme, and the active layout. Keys are scoped to the
/// imported skin and never expose arbitrary UserDefaults access to a script.
final class WinampModernConfiguration {
    let namespace: String
    private let defaults: UserDefaults

    init(namespace: String, defaults: UserDefaults = .standard) {
        self.namespace = Self.safeComponent(namespace)
        self.defaults = defaults
    }

    func integer(section: String, key: String, default defaultValue: Int32 = 0) -> Int32 {
        let name = storageKey(section: section, key: key)
        guard defaults.object(forKey: name) != nil else { return defaultValue }
        return Int32(clamping: Int64(defaults.integer(forKey: name)))
    }

    func setInteger(_ value: Int32, section: String, key: String) {
        defaults.set(Int(value), forKey: storageKey(section: section, key: key))
    }

    func string(section: String, key: String, default defaultValue: String = "") -> String {
        defaults.string(forKey: storageKey(section: section, key: key)) ?? defaultValue
    }

    func setString(_ value: String, section: String, key: String) {
        defaults.set(value, forKey: storageKey(section: section, key: key))
    }

    private func storageKey(section: String, key: String) -> String {
        "winampModern.config.\(namespace).\(Self.safeComponent(section)).\(Self.safeComponent(key))"
    }

    private static func safeComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_ -"))
        let result = String(value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" })
        return result.isEmpty ? "default" : result
    }
}
