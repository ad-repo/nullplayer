import Foundation

/// A surface a `.wmz` skin may provide itself, and that NullPlayer also has a window for.
///
/// **Only these two, and that is a gap rather than the whole list.** This comment used to say every
/// other window NullPlayer opens has no counterpart in the WMP skin format at all; measured over the
/// 179-archive corpus on 2026-09-09, four do. `<EFFECTS>` reaches **171 skins** and `<VIDEO>` 170 —
/// more than the playlist's 170 and the equaliser's 163 — plus `<VIDEOSETTINGS>` (94) and
/// `<NETWORK>` (4). So the visualizer and video toggles still open our window over a skin that
/// declares its own, which is the defect this type exists to prevent.
///
/// A case is not the fix on its own: routing stands NullPlayer's window aside on the strength of an
/// authored tag, so **adding one before `WMPMainView` hosts that surface trades a duplicate window
/// for an empty drawer.** W101-W105 in `WMP_TASKS.md` § *Tier 1e* rank the hosting ahead of the
/// routing for that reason. The library, Cava, PeppyMeter, the waveform and the analysis panes do
/// genuinely have no counterpart.
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
    /// `ITEMSPLAYLIST` resolved to `.unknown` when this was written — Corona's drawer is one — so a
    /// kind-only test reported that skin as owning no playlist and opened ours on top of it. It is
    /// `.playlist` since W97 and the first case now catches it, but the tag rule is deliberately
    /// kept: what decides this routing is what the skin *declares*, not how much of it this engine
    /// hosts today, so any tag ending in `PLAYLIST` is a playlist here even before it is one there.
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
