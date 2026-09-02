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

    /// `static`, for the reason `WinampModernComponentRegistry.normalize` is written over bytes:
    /// this used to be rebuilt on every call, and `CharacterSet.alphanumerics.union(_:)` is not a
    /// cheap constant — it materializes Unicode bitmap planes (`CFUniCharGetBitmapForPlane`). Two
    /// calls per `storageKey`, and a `storageKey` per config read, puts it on the frame path for
    /// every `cfgattrib` in the scene: 2.5% of the main thread on cPro Bento (B105).
    private static let allowedComponentCharacters: CharacterSet =
        CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_ -"))

    private static func safeComponent(_ value: String) -> String {
        guard !value.isEmpty else { return "default" }
        // Section and key names are overwhelmingly already safe, and rebuilding an identical string
        // one `Character` at a time is the rest of the cost. Answer with the original when it is.
        if value.unicodeScalars.allSatisfy(allowedComponentCharacters.contains) { return value }
        var result = ""
        result.unicodeScalars.reserveCapacity(value.unicodeScalars.count)
        for scalar in value.unicodeScalars {
            result.unicodeScalars.append(allowedComponentCharacters.contains(scalar) ? scalar : "_")
        }
        return result
    }
}
