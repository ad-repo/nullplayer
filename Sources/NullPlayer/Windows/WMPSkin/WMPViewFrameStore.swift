import Foundation

/// WMP-owned per-skin/per-view geometry persistence, plus which auxiliary views the skin had open.
///
/// The size half predates second windows: the player's *position* is the main-window restore path's
/// and a view switch preserves the current safe top-left. An auxiliary window has neither — nothing
/// else in the app knows it exists — so its origin is kept here too, and restored on the rule `.wal`
/// already follows: **what the user last decided wins over what the skin declares**.
struct WMPViewFrameStore {
    private static let defaultsKey = "wmpViewSizes"
    private static let originsKey = "wmpViewOrigins"
    private static let openViewsKey = "wmpOpenViews"
    let defaults: UserDefaults

    func size(skin: String, view: String) -> WMPSize? {
        guard let values = defaults.dictionary(forKey: Self.defaultsKey)?[key(skin, view)] as? [Double],
              values.count == 2, values[0].isFinite, values[1].isFinite,
              values[0] > 0, values[1] > 0 else { return nil }
        return WMPSize(width: values[0], height: values[1])
    }

    func setSize(_ size: WMPSize, skin: String, view: String) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        var values = defaults.dictionary(forKey: Self.defaultsKey) ?? [:]
        values[key(skin, view)] = [Double(size.width), Double(size.height)]
        defaults.set(values, forKey: Self.defaultsKey)
    }

    /// The window's top-left in screen coordinates, which is the anchor `.wmz` geometry is expressed
    /// from everywhere else in this engine.
    func origin(skin: String, view: String) -> CGPoint? {
        guard let values = defaults.dictionary(forKey: Self.originsKey)?[key(skin, view)] as? [Double],
              values.count == 2, values[0].isFinite, values[1].isFinite else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }

    func setOrigin(_ origin: CGPoint, skin: String, view: String) {
        guard origin.x.isFinite, origin.y.isFinite else { return }
        var values = defaults.dictionary(forKey: Self.originsKey) ?? [:]
        values[key(skin, view)] = [Double(origin.x), Double(origin.y)]
        defaults.set(values, forKey: Self.originsKey)
    }

    /// The auxiliary views this skin had open when the session ended, in the order they were opened.
    /// The player's own view is not one of them — that is `WMPSkinImporter.selectedViewIDKey`.
    func openViews(skin: String) -> [String] {
        defaults.dictionary(forKey: Self.openViewsKey)?[skinKey(skin)] as? [String] ?? []
    }

    func setOpenViews(_ views: [String], skin: String) {
        var values = defaults.dictionary(forKey: Self.openViewsKey) ?? [:]
        if views.isEmpty { values.removeValue(forKey: skinKey(skin)) }
        else { values[skinKey(skin)] = views }
        defaults.set(values, forKey: Self.openViewsKey)
    }

    private func key(_ skin: String, _ view: String) -> String {
        "\(skin.utf8.count):\(skin.lowercased())|\(view.lowercased())"
    }

    private func skinKey(_ skin: String) -> String {
        "\(skin.utf8.count):\(skin.lowercased())"
    }
}
