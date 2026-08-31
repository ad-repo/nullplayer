import Foundation

/// Phase-1 persistence seam for the selected Reeltone skin.
///
/// The value is an opaque installation identity rather than an archive path. Phase 2's validated
/// skin store will own the identity format and resolve it to installed resources.
enum ReeltoneSkinState {
    static let selectedSkinIdentityKey = "reeltoneSkinIdentity"

    static func selectedSkinIdentity(in defaults: UserDefaults = ReeltoneDefaults.shared) -> String? {
        defaults.string(forKey: selectedSkinIdentityKey)
    }

    static func selectSkin(identity: String?, in defaults: UserDefaults = ReeltoneDefaults.shared) {
        guard let identity, !identity.isEmpty else {
            defaults.removeObject(forKey: selectedSkinIdentityKey)
            return
        }
        defaults.set(identity, forKey: selectedSkinIdentityKey)
    }

    private static func surfaceKey(identity: String, surfaceID: ReeltoneSurfaceID, suffix: String) -> String {
        "reeltone.surface.\(identity).\(surfaceID.rawValue).\(suffix)"
    }

    static func panelVisibility(
        identity: String,
        surfaceID: ReeltoneSurfaceID,
        in defaults: UserDefaults = ReeltoneDefaults.shared
    ) -> Bool? {
        let key = surfaceKey(identity: identity, surfaceID: surfaceID, suffix: "visible")
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    static func setPanelVisibility(
        _ visible: Bool,
        identity: String,
        surfaceID: ReeltoneSurfaceID,
        in defaults: UserDefaults = ReeltoneDefaults.shared
    ) {
        defaults.set(visible, forKey: surfaceKey(identity: identity, surfaceID: surfaceID, suffix: "visible"))
    }

    static func panelFrame(
        identity: String,
        surfaceID: ReeltoneSurfaceID,
        in defaults: UserDefaults = ReeltoneDefaults.shared
    ) -> CGRect? {
        guard let value = defaults.array(forKey: surfaceKey(identity: identity, surfaceID: surfaceID, suffix: "frame")) as? [Double],
              value.count == 4 else {
            return nil
        }
        return CGRect(x: value[0], y: value[1], width: value[2], height: value[3])
    }

    static func setPanelFrame(
        _ frame: CGRect,
        identity: String,
        surfaceID: ReeltoneSurfaceID,
        in defaults: UserDefaults = ReeltoneDefaults.shared
    ) {
        defaults.set(
            [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height],
            forKey: surfaceKey(identity: identity, surfaceID: surfaceID, suffix: "frame")
        )
    }

    static func panelIsDetached(
        identity: String,
        surfaceID: ReeltoneSurfaceID,
        in defaults: UserDefaults = ReeltoneDefaults.shared
    ) -> Bool {
        defaults.bool(forKey: surfaceKey(identity: identity, surfaceID: surfaceID, suffix: "detached"))
    }

    static func setPanelDetached(
        _ detached: Bool,
        identity: String,
        surfaceID: ReeltoneSurfaceID,
        in defaults: UserDefaults = ReeltoneDefaults.shared
    ) {
        defaults.set(detached, forKey: surfaceKey(identity: identity, surfaceID: surfaceID, suffix: "detached"))
    }
}
