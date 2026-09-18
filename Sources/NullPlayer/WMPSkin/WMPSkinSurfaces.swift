import CoreGraphics
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
    case video
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
        for registration in skin.views where Self.canBecomeAWindow(registration.node) {
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

    // MARK: - Presentability

    /// Whether this view can become a window at all — because a surface declared in one that cannot
    /// is a surface the skin never shows, and standing NullPlayer's own window aside for it leaves
    /// the user with neither.
    ///
    /// `WMPMainWindowController.loadView` already treats a view whose canvas resolves to 0x0 as
    /// **windowless**: it runs the script and hands off without ever materialising a window. That is
    /// deliberate and correct — 25 corpus skins author a `controlView` holding only `<player>` and a
    /// hidden `<video>` so a script can run with host bindings and no window. But routing asks a
    /// different question of the same markup and was not asking it, so a surface parked in such a
    /// view counted as provided.
    ///
    /// **`cyberchannel` is the one archive where the two disagree, and it has no playlist at all as
    /// a result.** Its whole second view is `<VIEW id="playview"><PLAYLIST/></VIEW>`: a bare list
    /// stating no box, in a view stating no size and carrying no background artwork. Nothing can
    /// size either — WMP's ambient `width`/`height` default is "zero or the size of the image
    /// specified in the control's **image** attribute" and there is no image, so the view is 0x0 in
    /// WMP's own arithmetic too. The skin's `#00d106` button calls `theme.openView('playview')`, the
    /// load path classifies it windowless and opens nothing, and because `WMPSkinSurfaces` reported
    /// a playlist, `dismissWMPFallbackSurfacesTheSkinProvides` had already put ours away.
    ///
    /// Measured over the 185-archive corpus: **27 views state no size, no background and hold
    /// nothing that could size them**, and 26 of those are the Skins Factory `controlView` — whose
    /// only surface is an unsized `<VIDEO>` that `matches` already refuses. So this rule changes
    /// exactly one skin's routing, which is the one it was written for.
    ///
    /// Markup alone decides it, so a view that could size *itself* at load is left alone: a
    /// `scriptFile` or an `onLoad` can write `view.width`, which no static reading can see, and the
    /// safe answer when the size is unknowable is that the skin still owns the surface.
    private static func canBecomeAWindow(_ view: WMPNode) -> Bool {
        if literal(view, "width") != nil, literal(view, "height") != nil { return true }
        if resource(view) != nil { return true }
        if view.attribute(named: "scriptFile") != nil || view.attribute(named: "onLoad") != nil {
            return true
        }
        return contributesGeometry(view.children)
    }

    /// Whether anything in this subtree states a box or carries artwork a box could be read from —
    /// the markup half of `WMPSceneBuilder.contentUnionSize`, which is what sizes a view that
    /// authored no size of its own.
    private static func contributesGeometry(_ nodes: [WMPNode]) -> Bool {
        nodes.contains { node in
            if literal(node, "width") != nil, literal(node, "height") != nil { return true }
            if resource(node) != nil { return true }
            return contributesGeometry(node.children)
        }
    }

    /// Any attribute a node's natural size can come from. Deliberately the union of every kind's
    /// list rather than `intrinsicSizeResourceNames`'s per-kind one: this only has to answer
    /// *whether* a size exists, never which bitmap states it.
    private static func resource(_ node: WMPNode) -> WMPAttribute? {
        ["image", "backgroundImage", "background", "mappingImage", "positionImage",
         "foregroundImage", "thumbImage", "hoverImage", "downImage", "disabledImage"]
            .lazy.compactMap { node.attribute(named: $0) }
            .first { !($0.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    }

    private static func literal(_ node: WMPNode, _ name: String) -> CGFloat? {
        WMPNumber.literal(node.attribute(named: name))
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
        case .video:
            guard tag == "VIDEO" || tag == "WMPVIDEO" else { return false }
            // The corpus's windowless dispatchers carry an anonymous, unsized VIDEO solely for
            // onVideoStart. A zero-width compact-view listener is likewise not a video window.
            if WMPNumber.literal(node.attribute(named: "width")) == 0
                || WMPNumber.literal(node.attribute(named: "height")) == 0 { return false }
            return node.xmlID != nil || (node.attribute(named: "width") != nil
                                          && node.attribute(named: "height") != nil)
        }
    }
}
