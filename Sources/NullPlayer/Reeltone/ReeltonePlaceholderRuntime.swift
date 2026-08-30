import Foundation

/// Prepares the Original presentation used by the Phase-1 Reeltone shell.
/// Dynamic Reeltone themes replace this adapter in later phases.
enum ReeltonePlaceholderRuntime {
    static func prepare() {
        ModernSkinEngine.shared.loadPreferredSkin(for: .modern, preservePersistedProfiles: false)
    }
}
