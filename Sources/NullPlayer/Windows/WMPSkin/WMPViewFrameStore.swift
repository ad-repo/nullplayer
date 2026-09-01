import Foundation

/// WMP-owned per-skin/per-view size persistence. Position remains controlled by the main-window
/// restore path; view switches preserve the current safe top-left anchor.
struct WMPViewFrameStore {
    private static let defaultsKey = "wmpViewSizes"
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

    private func key(_ skin: String, _ view: String) -> String {
        "\(skin.utf8.count):\(skin.lowercased())|\(view.lowercased())"
    }
}
