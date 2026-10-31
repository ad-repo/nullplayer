import CoreGraphics
import Foundation

/// A text outside every piece of a window's artwork (B334).
extension WasabiSceneRenderer {
    /// What a layout's own `background`/`alphabackground` bitmap contributes to its artwork.
    enum LayoutBitmapArt {
        /// Named, and missing from the archive: art we cannot see.
        case missing
        /// There, and with no opaque pixel.
        case transparent
        /// Its opaque box, as a fraction of the bitmap.
        case opaque(CGRect)
    }

    /// On a layout that names an `alphabackground`, a text lying wholly outside the artwork has no
    /// window to be in (B334). HALOAMP's `songArtist`/`songAlbum` sit at `y=81`, below its 80px bar on
    /// a 340x220 layout whose own backgrounds are empty: they drew over the bare desktop, on top of
    /// each other. "Artwork" is every node that is not a text, a bare group or the layout; a text that
    /// touches any of it stays, so a label on a panel, or a window with no artwork at all, is untouched.
    /// A layout naming a bitmap that is missing from the archive drops nothing (the art is unknown).
    /// ponytail: one bounding box for the whole layout; a text in the gap between two far-apart
    /// pieces of art stays. Test each piece's own frame if a skin shows one.
    func droppingStrayText(from nodes: [WasabiSceneNode]) -> [WasabiSceneNode] {
        guard layout.attributes["alphabackground"] != nil else { return nodes }
        func isArtwork(_ node: WasabiSceneNode) -> Bool {
            let object = node.object
            if object === layout || object.tag.is(anyOf: [.text, .songticker]) { return false }
            return !object.tag.is(.group) || object.attributes["background"] != nil
        }
        var art = nodes.lazy.filter(isArtwork)
            .map { $0.frame.intersection($0.clipping.rect) }.filter { !$0.isNull && !$0.isEmpty }
            .reduce(CGRect.null) { $0.union($1) }
        // The layout's own bitmaps are artwork too, where they have any (GoldenBeauty's player *is*
        // its `background`); HALOAMP's are empty, which is the case this exists for.
        let rootFrame = nodes.first?.frame ?? .zero
        for id in ["background", "alphabackground"].compactMap({ layout.attributes[$0] }) {
            switch layoutBitmapArt(id) {
            // A named bitmap the archive does not hold (Auburn's `thinger.png`): the text on it is the
            // skin's, not a stray.
            case .missing: return nodes
            case .transparent: continue
            case .opaque(let unit):
                art = art.union(CGRect(x: rootFrame.minX + unit.minX * rootFrame.width,
                                       y: rootFrame.minY + unit.minY * rootFrame.height,
                                       width: unit.width * rootFrame.width, height: unit.height * rootFrame.height))
            }
        }
        guard !art.isNull else { return nodes }
        return nodes.map { node in
            guard node.object.tag.is(anyOf: [.text, .songticker]), !node.frame.intersects(art) else { return node }
            return node.clipped(to: .zero)
        }
    }

    private func layoutBitmapArt(_ id: String) -> LayoutBitmapArt {
        let key = layout.source.path + "|" + id.lowercased()
        if let cached = layoutBitmapArtCache[key] { return cached }
        let art: LayoutBitmapArt
        if let bitmap = resources.bitmap(background: id, declaredIn: layout.source) {
            if let bounds = WasabiResourceCache.opaqueBounds(of: bitmap.image), bitmap.width > 0, bitmap.height > 0 {
                let width = CGFloat(bitmap.width), height = CGFloat(bitmap.height)
                art = .opaque(CGRect(x: bounds.minX / width, y: bounds.minY / height,
                                     width: bounds.width / width, height: bounds.height / height))
            } else {
                art = .transparent
            }
        } else {
            art = .missing
        }
        layoutBitmapArtCache[key] = art
        return art
    }
}
