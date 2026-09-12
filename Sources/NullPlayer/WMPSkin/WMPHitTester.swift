import Foundation

struct WMPHitTarget: Hashable, Codable {
    let stableID: Int
    let nodeID: String?
    let kind: String
    let frame: WMPRect
    let action: WMPTransportAction?
    let sticky: Bool
    let enabled: Bool
    /// What the pointer resting here should say. A mapping child carries its own, which is why this
    /// is on the target and not only on `WMPHitMetadata`: `alx_dl.wms` gives one of four
    /// `<BUTTONELEMENT>`s inside a single mapping image the tip "Open Media File".
    var toolTip: String?
}

struct WMPHitTester {
    let hits: [WMPHitMetadata]

    func hitTest(_ point: WMPPoint) -> WMPHitTarget? {
        for hit in hits.sorted(by: Self.frontToBack) {
            guard hit.enabled, hit.frame.contains(point),
                  hit.clipRect.map({ $0.contains(point) }) ?? true else { continue }
            // **A control is its artwork, not its rectangle.** A pixel the skin keyed out of this
            // node's own sprite belongs to whatever is drawn under it, exactly as `mappingImage`
            // already decides for a `<BUTTONGROUP>`'s children. See `WMPHitCoverage`.
            guard hit.coverage?.covers(point, in: hit.frame) ?? true else { continue }
            if let mapping = hit.mappingImage {
                guard let stableID = mapping.node(at: point, in: hit.frame),
                      let target = hit.mappingTargets.first(where: { $0.stableID == stableID }),
                      target.enabled else { continue }
                return target
            }
            return WMPHitTarget(stableID: hit.stableID, nodeID: hit.nodeID, kind: hit.kind,
                                frame: hit.frame, action: hit.action, sticky: hit.sticky,
                                enabled: hit.enabled)
        }
        return nil
    }

    /// Front-most first, in the reverse of the order the scene painted them.
    ///
    /// **Not by `zIndex`.** That attribute orders a node among its *siblings*, and comparing it
    /// across a flat array asks two unrelated branches of the tree to be ranked by whichever
    /// authored the larger literal. `paintOrder` is the traversal `WMPSceneBuilder` already uses to
    /// build `commands`, so what the pointer finds is what the user can see.
    ///
    /// **A hosted surface is always last.** `<EFFECTS>` and `<VIDEO>` are click-through by design —
    /// `WMPEffectsSurfaceView` returns `nil` from `hitTest`, and `WMPMainView.menu(for:)` says the
    /// same of both — but 51 corpus skins wire an `onClick` on the effects node itself, so it is a
    /// *fallback* target rather than a blocker. Both are also routinely the largest node in their
    /// view and declared late, so ranking them by paint order alone swallows whatever the skin
    /// draws over them: the rating stars in `Alienware Invader`'s `visView`, the equalizer sliders
    /// in `Radio`'s, and `XBOX`'s `xDown` over its video window — 58 controls across 12 archives,
    /// measured with `WMP_RENDER_OCCLUDED=1`.
    private static func frontToBack(_ lhs: WMPHitMetadata, _ rhs: WMPHitMetadata) -> Bool {
        let left = isHostedSurface(lhs), right = isHostedSurface(rhs)
        return left == right ? lhs.paintOrder > rhs.paintOrder : right
    }

    private static func isHostedSurface(_ hit: WMPHitMetadata) -> Bool {
        hit.kind.caseInsensitiveCompare("effects") == .orderedSame
            || hit.kind.caseInsensitiveCompare("video") == .orderedSame
    }
}
