import Foundation

/// Edition-neutral policy for UI and session persistence.
///
/// The full edition keeps the existing preference keys and user-selectable UI mode.
/// A downstream edition can define `EDITION_CUSTOM` and supply the corresponding
/// `EditionPolicy` values without spreading edition checks through the app.
enum AppPersistence {
    /// One mandatory UI mode for a forced-mode edition; `nil` for the full edition.
    static var forcedUIMode: PlayerUIMode? {
        #if EDITION_CUSTOM
        return EditionPolicy.forcedUIMode
        #else
        return nil
        #endif
    }

    /// Namespace UI/session-geometry keys per edition. Identity for the full edition.
    static func key(_ baseKey: String) -> String {
        #if EDITION_CUSTOM
        return key(baseKey, namespace: EditionPolicy.preferenceNamespace)
        #else
        return key(baseKey, namespace: nil)
        #endif
    }

    /// Pure form used to verify scoped-edition behavior in the full-edition test target.
    static func key(_ baseKey: String, namespace: String?) -> String {
        guard let namespace else { return baseKey }
        return "\(namespace).\(baseKey)"
    }
}
