import CoreGraphics

/// **A donor's second panel** — a side strip whose artwork carries one of its lists — and the bar
/// repair that hands it to our content (see `sideListNodeIDs`).
extension WMPHostedFrameTemplate {
    static func lists(in view: WMPNode, outside client: WMPNode) -> Set<Int> {
        var found: Set<Int> = [], inClient: Set<Int> = []
        walk(client) { inClient.insert($0.stableID) }
        walk(view) { node in
            guard [.listBox, .playlist, .dropdownPlaylist].contains(node.kind),
                  !inClient.contains(node.stableID) else { return }
            // A list resolves no frame of its own in the scene; the subview holding it does.
            let framed = node.parent.flatMap { $0.kind == .subview ? $0 : nil } ?? node
            found.insert(framed.stableID)
        }
        return found
    }

    struct PanelSides { var left = false, right = false }

    /// `image` with the columns `from..<to` (points) of the bars above and below `content`
    /// replaced by the plain column just outside that span on the client's side — the column at
    /// `to` for a left panel, at `from - 1` for a right one. Outside the span, the rows within one
    /// border of the content take the opposite corner mirrored: the panel's own corner sits higher
    /// than the client's and is outlined differently, and left alone it is a step in the edge.
    static func bridgingBars(_ image: CGImage, from: CGFloat, to: CGFloat,
                                     content: CGRect, size: CGSize) -> CGImage {
        let width = image.width, height = image.height
        let pixelsX = CGFloat(width) / size.width, pixelsY = CGFloat(height) / size.height
        let x0 = max(0, Int((from * pixelsX).rounded())), x1 = min(width - 1, Int((to * pixelsX).rounded()))
        guard x1 > x0 else { return image }
        let source = from > content.midX ? x0 - 1 : x1
        guard source >= 0, source < width else { return image }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = pixels.withUnsafeMutableBytes({ bytes -> CGContext? in
            CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Rows are top-down in the buffer, as `content` is.
        let top = Int((content.minY * pixelsY).rounded()), bottom = Int((content.maxY * pixelsY).rounded())
        let reach = Int((min(content.minX, size.width - content.maxX) * pixelsY).rounded())
        let corner = from > content.midX ? x1..<width : 0..<x0
        for y in 0..<height where y < top || y >= bottom {
            let row = y * width * 4
            func copy(_ x: Int, from source: Int) {
                for c in 0..<4 { pixels[row + x * 4 + c] = pixels[row + source * 4 + c] }
            }
            for x in x0..<x1 where x != source { copy(x, from: source) }
            if y >= top - reach, y < bottom + reach {
                for x in corner { copy(x, from: width - 1 - x) }
            }
        }
        return context.makeImage() ?? image
    }

    /// **A side strip whose own artwork carries one of the donor's lists is a second panel, not a
    /// rail.** `MCE2005_MP` bakes its whole Media Library sidebar — album-art plate, search well,
    /// list ground — into `pl_top_left.png` (272px) and `pl_left_tile.png`, the slot pieces down
    /// its left side, and lays `plListBox1` over them. Nothing can be subtracted, and the rail
    /// measure read the sidebar as 175pt of rail at the donor's floor and 63pt on a taller window
    /// (its list ground is the hole's fill), so every hosted window grew by the sidebar and then
    /// laid its content across half of it. The same template's racks (`Star Wars`, `STALKER`,
    /// `WoW`, `LostPlanet`, `Batman Begins`, `Windows Media Player Skins`) go with it: the reporter
    /// chose no sidebar on any of them (2026-11-18). **Except a list on the donor's own furniture**:
    /// `Alienware Invader` draws its album-art, search and list racks as separate subviews, which
    /// the furniture test drops, and keeps its 99pt rail (W212).
    func panelSides(in scene: WMPScene, hole: CGRect, furniture: Set<Int>) -> PanelSides {
        let slots = ringNodeIDs.subtracting(extraNodeIDs).compactMap { scene.geometries[$0]?.absoluteFrame }
        let racks = furniture.compactMap { scene.geometries[$0]?.absoluteFrame.cgRect }
        var sides = PanelSides()
        for id in sideListNodeIDs {
            guard let frame = scene.geometries[id]?.absoluteFrame, !frame.isEmpty else { continue }
            let list = frame.cgRect
            func covered(by pieces: [CGRect]) -> Bool {
                let area = pieces.reduce(CGFloat(0)) { sum, piece in
                    let overlap = piece.intersection(list)
                    return overlap.isNull ? sum : sum + overlap.width * overlap.height
                }
                return area > list.width * list.height * 0.5
            }
            // Slot tiles meet without overlapping, so their shares add up; a rack is one piece.
            guard covered(by: slots.map(\.cgRect)), !racks.contains(where: { covered(by: [$0]) })
            else { continue }
            if list.maxX <= hole.minX + 1 { sides.left = true }
            if list.minX >= hole.maxX - 1 { sides.right = true }
        }
        return sides
    }
}
