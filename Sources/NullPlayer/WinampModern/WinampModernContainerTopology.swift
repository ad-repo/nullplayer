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
    /// The surface this container *is*, from its own `component=` GUID. `nil` for a container that
    /// hosts no NullPlayer surface (colour themes, a notifier, the player itself).
    let kind: WinampModernComponentKind?
    /// True when NullPlayer synthesized this container because the skin declared no window for a
    /// surface it needs (Phase 13.2). Skin-declared containers are always false.
    let isSynthesized: Bool
}

/// How a skin lays its surfaces out. cPro-Bento embeds everything in one window; mmd3, CornerAmp,
/// and Winamp Modern each declare separate windows for the surfaces they support. Synthesis only
/// ever applies to the separate-window arrangement — an SUI skin's missing container is not missing,
/// it is embedded.
///
/// Container *count* cannot answer this (cPro also declares a notifier, a widget manager, and a
/// browser window), so the verdict comes from the declarative surface inventory: a skin whose main
/// container reaches playlist/library holders is an SUI.
enum WinampModernSurfaceArrangement: Equatable {
    case singleWindowSUI
    case separateWindows
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
                // Only a layout that *declares* a tiny box has been collapsed. A layout that declares
                // no box at all is sized by its `background` bitmap (ZDL's Reel-To-Reel declares its
                // equalizer that way), and reading its two zeroes as 0×0 hid the window the skin ships.
                let collapsed = (declared.width > 0 || declared.height > 0) &&
                    declared.width <= collapsedThreshold && declared.height <= collapsedThreshold
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
                        : nil,
                    kind: kind(of: container),
                    isSynthesized: container.attributes[Self.synthesizedAttribute] == "1"
                )
            }
    }

    /// Marks a container appended by `WasabiSurfaceSynthesizer` rather than declared by the skin.
    static let synthesizedAttribute = "nullplayer_synthesized"

    /// Whether this container belongs in the host's window menu — the list Winamp puts in its own
    /// Windows menu, and the **only** way to open a window a skin declares but binds no button to.
    ///
    /// The rule is the skin's own markup, not a heuristic: a container is listed when it carries a
    /// `name` and does not carry `nomenu="1"`. Defix says exactly this — `Config name="Skin Settings"`,
    /// `SPEAKER 1`, `SPEAKER 2` and `Playlist Editor` are named and menu-visible, while its
    /// `browserpro`, `notifier` and two `searchresults` popups all declare `nomenu="1"`, and its `SUI`
    /// and `VISCON` carry no name at all because the skin's own buttons reach them.
    ///
    /// The main player is excluded (it is never closed from a list), and so is any container the
    /// surface catalog already routes — the playlist, equalizer and library have their own menu
    /// items, and a second entry here would be a second route to one window, which the catalog exists
    /// to prevent.
    static func isListedInWindowMenu(_ info: WinampModernContainerInfo) -> Bool {
        guard !info.isMainPlayer, !info.isSynthesized, info.kind == nil else { return false }
        guard let name = info.object.attributes["name"], !name.isEmpty else { return false }
        return info.object.attributes["nomenu"] != "1"
    }

    /// The container's own display name, which is what the menu shows.
    static func displayName(of info: WinampModernContainerInfo) -> String {
        info.object.attributes["name"] ?? info.id
    }

    /// A container declares the surface it *is* with `component="guid:…"` — mmd3's
    /// `<container id="Pledit" component="guid:{45F3F7C1-…}">`. The id is not evidence: `Pledit`,
    /// `MLibrary`, and `eq` only look like their kinds by convention, and reading them as such would
    /// also make `colorthemes` a surface. The one id fallback is an exact short token (`eq`), which is
    /// how CornerAmp names the equalizer window it declares no GUID for.
    private static func kind(of container: WasabiObject) -> WinampModernComponentKind? {
        if let declared = container.attributes["component"],
           let kind = WinampModernComponentRegistry.kind(for: declared) {
            return kind
        }
        return container.xmlID.flatMap { WinampModernComponentRegistry.kind(for: $0) }
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
