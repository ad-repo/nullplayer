import CoreGraphics
import Foundation

/// What a `sysregion="1"` wrapper group puts back into the window region: one mark per thing it
/// holds. See `skills/winamp-modern-skin-guide/reference/rendering/hit-testing.md`.
extension WasabiSceneRenderer {
    /// One thing a wrapper group holds, as the region sees it: its node, filled as the artwork's
    /// shape when it is an image stretched to its box (`regionShape`), as its box otherwise.
    ///
    /// heart_'s `player.main` holds the heart as one layer, a bitmap of 310x280 whose corners above
    /// the lobes are clear. As a box it put the player back over the config drawer's whole background
    /// texture, which the drawer's own `sysregion="-1"` silhouettes had just cut away, and a teal
    /// slab showed behind the heart (B429).
    struct WasabiRegionMark: Equatable {
        let node: WasabiSceneNode
        /// The attributes `regionShape` reads, as they were when the mark was collected: a script
        /// can set `tile` or `center_image`, which changes the shape without moving the node.
        private let shapeAttributes: [String?]

        init(node: WasabiSceneNode) {
            self.node = node
            shapeAttributes = ["tile", "tilex", "tiley", "center_image"].map { node.object.attributes[$0] }
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.node.object === rhs.node.object && lhs.node.frame == rhs.node.frame
                && lhs.node.clip == rhs.node.clip && lhs.node.bitmapID == rhs.node.bitmapID
                && lhs.shapeAttributes == rhs.shapeAttributes
        }
    }

    /// Wherever the artwork has **any** alpha: a faint shadow or glow is painted, so it is window
    /// (S7Reflex's player body, RODE_3_Lite's glass), where a half-coverage cut would take it away.
    /// Nil for a tiled or centred image, which has no such shape, for an animated layer (its sprite
    /// sheet is not the frame it draws), and for a leaf with no artwork.
    /// Read when the region is built, not when the marks are collected: that runs on every frame as
    /// the cache key, and rasterises nothing the region does not use.
    private func regionShape(of node: WasabiSceneNode) -> CGImage? {
        let attributes = node.object.attributes
        guard !node.object.tag.is(.animatedLayer), let id = node.bitmapID, let bitmap = resources.bitmap(identifier: id),
              attributes["tile"] != "1", attributes["tilex"] != "1", attributes["tiley"] != "1",
              centeredImageRect(bitmap, object: node.object, in: node.frame) == nil
        else { return nil }
        return resources.alphaMask(bitmapID: id)
    }

    /// Put a wrapper's content back into the window region being built.
    func fillMarks(_ marks: [WasabiRegionMark], in context: WasabiDrawList) {
        for mark in marks {
            context.saveGState()
            context.clip(to: mark.node.clip)
            if let shape = regionShape(of: mark.node) { context.clip(to: mark.node.frame, mask: shape) }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill([mark.node.frame])
            context.restoreGState()
        }
    }
}
