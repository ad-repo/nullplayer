import Foundation

/// WMP-owned per-skin/per-view sizes. A view's origin and which auxiliary views were open live in the
/// shared `SkinWindowStore`, under `SkinWindowStore.Keys.wmp`.
///
/// The size half predates second windows: the player's *position* is the main-window restore path's
/// and a view switch preserves the current safe top-left.
struct WMPViewFrameStore {
    private static let defaultsKey = "wmpViewSizes"
    let defaults: UserDefaults

    func size(skin: String, view: String) -> WMPSize? {
        guard let values = defaults.dictionary(forKey: Self.defaultsKey)?[SkinWindowStore.windowKey(skin, view)] as? [Double],
              values.count == 2, values[0].isFinite, values[1].isFinite,
              values[0] > 0, values[1] > 0 else { return nil }
        return WMPSize(width: values[0], height: values[1])
    }

    func setSize(_ size: WMPSize, skin: String, view: String) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        var values = defaults.dictionary(forKey: Self.defaultsKey) ?? [:]
        values[SkinWindowStore.windowKey(skin, view)] = [Double(size.width), Double(size.height)]
        defaults.set(values, forKey: Self.defaultsKey)
    }
}
