import Foundation

/// One top-level `container` in a loaded skin, classified for native-window mapping.
struct WinampModernContainerInfo {
    let object: WasabiObject
    let id: String
    /// The Winamp "main" player window (`container id="main"`), which always maps to a window.
    let isMainPlayer: Bool
    /// True when the container declares a real visible window; false when it is an SUI-collapsed
    /// stub (e.g. neutralized by `window-overrides.xml` to a 1×1 invisible window because its
    /// surface is embedded in the main SUI via a `windowholder`).
    let isVisibleWindow: Bool
    /// The default canvas size of the container's normal layout.
    let defaultSize: CGSize
    /// The normal layout's `minimum_w`/`minimum_h`, in skin pixels. A layout that declares none is
    /// still bounded at 1×1 — `WasabiSceneRenderer.resize` uses the same floor.
    let minimumSize: CGSize
    /// The normal layout's `maximum_w`/`maximum_h`, in skin pixels, or `nil` per axis when the
    /// layout declares none (freely resizable up to the renderer's own 16384 ceiling).
    let maximumSize: CGSize?
}

/// Classifies a loaded skin's containers so the controller can decide, per P0B §3, between the
/// component-hosting SUI model (cPro-Bento: one visible window, everything else embedded) and the
/// separate-windows model (skins that declare multiple visible containers).
enum WinampModernContainerTopology {
    /// A container collapsed by window-overrides is at most this many pixels on a side.
    private static let collapsedThreshold: CGFloat = 2

    static func analyze(graph: WasabiObjectGraph) -> [WinampModernContainerInfo] {
        graph.roots
            .filter { $0.typeName.caseInsensitiveCompare("container") == .orderedSame }
            .map { container in
                let id = container.xmlID ?? ""
                let isMain = id.caseInsensitiveCompare("main") == .orderedSame
                let layout = normalLayout(of: container)
                let declared = size(of: layout, keys: [["default_w", "w", "minimum_w"],
                                                       ["default_h", "h", "minimum_h"]])
                let hidden = isHidden(container)
                let collapsed = declared.width <= collapsedThreshold && declared.height <= collapsedThreshold
                let minimum = size(of: layout, keys: [["minimum_w"], ["minimum_h"]])
                let maximum = size(of: layout, keys: [["maximum_w"], ["maximum_h"]])
                return WinampModernContainerInfo(
                    object: container,
                    id: id,
                    isMainPlayer: isMain,
                    isVisibleWindow: isMain || (!hidden && !collapsed),
                    defaultSize: declared,
                    minimumSize: CGSize(width: max(1, minimum.width), height: max(1, minimum.height)),
                    maximumSize: (maximum.width > 0 || maximum.height > 0)
                        ? CGSize(width: maximum.width > 0 ? maximum.width : .greatestFiniteMagnitude,
                                 height: maximum.height > 0 ? maximum.height : .greatestFiniteMagnitude)
                        : nil
                )
            }
    }

    /// The containers that should each become a native window. The main player is always included;
    /// additional visible containers are included only when the skin actually declares them (the
    /// separate-windows arrangement). An all-collapsed skin yields just the main window.
    static func windowContainers(graph: WasabiObjectGraph) -> [WinampModernContainerInfo] {
        analyze(graph: graph).filter(\.isVisibleWindow)
    }

    private static func normalLayout(of container: WasabiObject) -> WasabiObject? {
        let layouts = container.children.filter { $0.typeName.caseInsensitiveCompare("layout") == .orderedSame }
        return layouts.first { $0.xmlID?.caseInsensitiveCompare("normal") == .orderedSame } ?? layouts.first
    }

    /// `keys` is `[widthKeysInPreferenceOrder, heightKeysInPreferenceOrder]`; an axis nothing answers
    /// for is 0, which callers read as "not declared".
    private static func size(of layout: WasabiObject?, keys: [[String]]) -> CGSize {
        guard let layout else { return .zero }
        func dimension(_ candidates: [String]) -> CGFloat {
            for key in candidates {
                if let raw = layout.attributes[key], let value = Double(raw) { return CGFloat(value) }
            }
            return 0
        }
        return CGSize(width: dimension(keys[0]), height: dimension(keys[1]))
    }

    private static func isHidden(_ container: WasabiObject) -> Bool {
        let value = container.attributes["visible"]?.lowercased()
        return value == "0" || value == "false" || value == "no"
    }
}
