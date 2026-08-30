import Foundation

/// Phase-1 persistence seam for the selected Reeltone skin.
///
/// The value is an opaque installation identity rather than an archive path. Phase 2's validated
/// skin store will own the identity format and resolve it to installed resources.
enum ReeltoneSkinState {
    static let selectedSkinIdentityKey = "reeltoneSkinIdentity"

    static func selectedSkinIdentity(in defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: selectedSkinIdentityKey)
    }

    static func selectSkin(identity: String?, in defaults: UserDefaults = .standard) {
        guard let identity, !identity.isEmpty else {
            defaults.removeObject(forKey: selectedSkinIdentityKey)
            return
        }
        defaults.set(identity, forKey: selectedSkinIdentityKey)
    }
}
