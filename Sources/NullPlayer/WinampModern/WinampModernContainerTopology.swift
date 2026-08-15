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
                let size = normalLayoutSize(of: container)
                let hidden = isHidden(container)
                let collapsed = size.width <= collapsedThreshold && size.height <= collapsedThreshold
                return WinampModernContainerInfo(
                    object: container,
                    id: id,
                    isMainPlayer: isMain,
                    isVisibleWindow: isMain || (!hidden && !collapsed),
                    defaultSize: size
                )
            }
    }

    /// The containers that should each become a native window. The main player is always included;
    /// additional visible containers are included only when the skin actually declares them (the
    /// separate-windows arrangement). An all-collapsed skin yields just the main window.
    static func windowContainers(graph: WasabiObjectGraph) -> [WinampModernContainerInfo] {
        analyze(graph: graph).filter(\.isVisibleWindow)
    }

    private static func normalLayoutSize(of container: WasabiObject) -> CGSize {
        let layouts = container.children.filter { $0.typeName.caseInsensitiveCompare("layout") == .orderedSame }
        let layout = layouts.first {
            $0.xmlID?.caseInsensitiveCompare("normal") == .orderedSame
        } ?? layouts.first
        guard let layout else { return .zero }
        func dimension(_ keys: [String]) -> CGFloat {
            for key in keys {
                if let raw = layout.attributes[key], let value = Double(raw) { return CGFloat(value) }
            }
            return 0
        }
        return CGSize(width: dimension(["default_w", "w", "minimum_w"]),
                      height: dimension(["default_h", "h", "minimum_h"]))
    }

    private static func isHidden(_ container: WasabiObject) -> Bool {
        let value = container.attributes["visible"]?.lowercased()
        return value == "0" || value == "false" || value == "no"
    }
}
