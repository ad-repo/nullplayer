import Foundation

/// A surface a `.wmz` skin may provide itself, and that NullPlayer also has a window for.
///
/// Only these two. Every other window NullPlayer opens — the library, the spectrum analyser, Cava,
/// Flow, PeppyMeter, the waveform, the analysis panes, the visualizer — has no counterpart in the
/// WMP skin format at all, so nothing there can be redundant.
enum WMPSkinSurface: String, CaseIterable {
    case playlist
    case equalizer
}

/// Which of its own surfaces the loaded skin declares, and in which views.
///
/// **This is the whole reason NullPlayer's playlist and equalizer are a *fallback* in WMP mode
/// rather than the default.** Measured over the 180-archive corpus on 2026-09-09: **171 skins
/// declare a playlist and 164 an equaliser** (164 declare both). Opening our own window beside one
/// of those is two playlists on screen, one of them ignoring the skin the user chose — which is
/// exactly what `.wal` avoids by routing a component toggle to the skin's own container first
/// (`WindowManager.routeWinampModernSurface`).
///
/// Reproduce the counts by scanning the corpus for `<PLAYLIST`, `<ITEMSPLAYLIST`,
/// `<DROPDOWNPLAYLIST` and `<EQUALIZERSETTINGS`; the split between skins that keep the playlist in
/// their first view and skins that give it a view of its own is close to even (87 / 84), which is
/// why routing has to answer *both* shapes.
struct WMPSkinSurfaces: Equatable, Sendable {
    /// View ids that declare each surface, in document order.
    private var views: [WMPSkinSurface: [String]] = [:]

    static let empty = WMPSkinSurfaces()

    init() {}

    init(skin: WMPLoadedSkin) {
        for registration in skin.views {
            for surface in WMPSkinSurface.allCases where Self.declares(surface, in: registration.node) {
                views[surface, default: []].append(registration.id)
            }
        }
    }

    func viewIDs(for surface: WMPSkinSurface) -> [String] { views[surface] ?? [] }

    func provides(_ surface: WMPSkinSurface) -> Bool { !viewIDs(for: surface).isEmpty }

    /// Whether `viewID` is one of the views that declares this surface — i.e. the skin is already
    /// showing it and a NullPlayer window would be the second copy.
    func view(_ viewID: String?, provides surface: WMPSkinSurface) -> Bool {
        guard let viewID else { return false }
        return viewIDs(for: surface).contains { $0.caseInsensitiveCompare(viewID) == .orderedSame }
    }

    // MARK: - Recognition

    private static func declares(_ surface: WMPSkinSurface, in node: WMPNode) -> Bool {
        if matches(surface, node) { return true }
        return node.children.contains { declares(surface, in: $0) }
    }

    /// Matched on the **authored tag name**, not only on `WMPElementKind`.
    ///
    /// `ITEMSPLAYLIST` is a playlist the object model does not model yet — Corona's drawer is one —
    /// so it resolves to `.unknown` and a kind-only test would report that skin as owning no
    /// playlist and open ours on top of it. What decides this routing is what the skin *declares*,
    /// not how much of it this engine hosts today; any tag ending in `PLAYLIST` is a playlist.
    private static func matches(_ surface: WMPSkinSurface, _ node: WMPNode) -> Bool {
        let tag = node.authoredTagName.uppercased()
        switch surface {
        case .playlist:
            if node.kind == .playlist || node.kind == .dropdownPlaylist { return true }
            return tag.hasSuffix("PLAYLIST")
        case .equalizer:
            return node.kind == .equalizerSettings || tag == "EQUALIZERSETTINGS"
        }
    }
}
