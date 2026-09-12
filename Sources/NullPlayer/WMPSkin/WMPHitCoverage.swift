import CoreGraphics
import Foundation

/// Where a control's own artwork actually *is*, so a click on a pixel the skin keyed away falls
/// through to whatever the author put underneath.
///
/// **A `.wmz` control is its artwork, not its rectangle.** Every skin in the corpus is built out of
/// `transparencyColor`, and authors rely on it for input as much as for paint: `Plus! Pulsar` lays
/// two 79x136 `<CUSTOMSLIDER>` rects straight across the `<BUTTONGROUP>` carrying its equalizer,
/// playlist and visualization buttons, and every contested pixel of `vol.png`/`seek.png` there is
/// `#ff00ff`. `Navigator` states the same intent a second way — its `progress` slider spans the
/// whole player and `progress_map.bmp` has holes cut in it exactly where the close, full-mode and
/// visualization buttons sit. Hit testing the rect hands those clicks to a slider that is not drawn
/// there, and the user sees a control that hovers, highlights and does nothing.
///
/// This is deliberately **not** a z-order rule. `zIndex` was measured against this same corpus and
/// no ordering explains it: ordering `Pulsar`'s buttons in front costs `Navigator`'s close button,
/// `Alienware Invader`'s rating stars and 73 other controls, because those skins *do* rely on a flat
/// `zIndex` reaching across subviews. Coverage is orthogonal to ordering and leaves it alone — see
/// `skills/wmp-skin-guide/reference/skins/plus-family.md`.
///
/// Conservative by construction: a node with **no artwork of its own** — a bare `<BUTTON>` that
/// exists to catch `onMouseMove`, a handler on a `<SUBVIEW>` — has no coverage and stays hittable
/// across its whole rect, which is what it was before this type existed. Only a node that draws
/// something can have a hole in it.
struct WMPHitCoverage: Hashable, Codable {
    /// The mask's own resolution, in frame space. Capped so a full-window background cannot turn
    /// one hit target into a multi-megabyte scene field.
    static let resolutionCap = 512

    let width: Int
    let height: Int
    private let opaque: [UInt8]

    init?(width: Int, height: Int, opaque: [UInt8]) {
        guard width > 0, height > 0, opaque.count == width * height else { return nil }
        // A mask with no hole in it is the same answer as no mask, and cheaper to carry.
        guard opaque.contains(0) else { return nil }
        self.width = width
        self.height = height
        self.opaque = opaque
    }

    /// Is the control drawn at this point? `frame` is the target's rect in scene coordinates.
    func covers(_ point: WMPPoint, in frame: WMPRect) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return true }
        let x = min(width - 1, max(0, Int((point.x - frame.x) * CGFloat(width) / frame.width)))
        let y = min(height - 1, max(0, Int((point.y - frame.y) * CGFloat(height) / frame.height)))
        return opaque[y * width + x] != 0
    }
}

/// Builds a coverage mask from the paint commands a single node emitted for itself.
enum WMPHitCoverageBuilder {
    /// `nil` means "no hole was found" — every caller treats that as fully covered.
    ///
    /// The commands arrive in paint order, so a later one filling a pixel the earlier one keyed out
    /// puts the artwork back: a `<BUTTONGROUP>` draws its `backgroundImage` and then its `image`
    /// over it, and only a pixel neither of them paints is a hole.
    static func coverage(for commands: [WMPPaintCommand], frame: WMPRect,
                         pixels: (WMPSceneImage) -> WMPAlphaPlane?) -> WMPHitCoverage? {
        guard frame.width >= 1, frame.height >= 1, !commands.isEmpty else { return nil }
        let width = min(WMPHitCoverage.resolutionCap, Int(frame.width.rounded()))
        let height = min(WMPHitCoverage.resolutionCap, Int(frame.height.rounded()))
        guard width > 0, height > 0 else { return nil }
        var opaque = [UInt8](repeating: 0, count: width * height)
        var sawArtwork = false
        for command in commands {
            switch command.paint {
            case .fill:
                // An authored `backgroundColor` is opaque across the whole frame, so the node has
                // no hole in it whatever its sprites do.
                return nil
            case .text:
                // Glyphs are not a shape a click is tested against; a TEXT hit keeps its box.
                return nil
            case .image(let image):
                // Tiling and stretching both resample, and a stretched sprite's holes stay holes —
                // sampling in frame space handles both. What is not modelled is a mapping mask,
                // which `WMPHitTester` already consults separately and more precisely.
                guard image.mappingMask == nil, let decoded = pixels(image) else { return nil }
                sawArtwork = true
                let source = image.sourceRect
                    ?? WMPRect(x: 0, y: 0, width: CGFloat(decoded.width), height: CGFloat(decoded.height))
                guard source.width > 0, source.height > 0 else { return nil }
                for row in 0..<height {
                    let v = (CGFloat(row) + 0.5) / CGFloat(height)
                    for column in 0..<width {
                        let u = (CGFloat(column) + 0.5) / CGFloat(width)
                        let sx = Int((source.x + u * source.width).rounded(.down))
                        let sy = Int((source.y + v * source.height).rounded(.down))
                        guard sx >= 0, sy >= 0, sx < decoded.width, sy < decoded.height else { continue }
                        if decoded.alpha(atX: sx, y: sy) > 0 { opaque[row * width + column] = 1 }
                    }
                }
            }
        }
        guard sawArtwork else { return nil }
        // **A sprite with nothing opaque in it is a hit catcher, not a shape.** Skins draw a
        // control into the parent's background art and lay a fully transparent `<BUTTON>` over it
        // to collect the clicks — `holiday_skin` builds both its views that way, `Grinch` and
        // `Josie_and_the_Pussycats` their whole transports. Reading those as "drawn nowhere" takes
        // the control away instead of giving it back: 104 of them across 21 archives, measured with
        // `WMP_RENDER_OCCLUDED=1` over the installed corpus. Coverage only ever *subtracts* from a
        // node that has visible artwork somewhere.
        guard opaque.contains(where: { $0 != 0 }) else { return nil }
        return WMPHitCoverage(width: width, height: height, opaque: opaque)
    }
}

/// An 8-bit alpha plane lifted out of an already colour-keyed sprite.
///
/// The store hands back a `CGImage` whose keyed colours are alpha zero, so "is the skin drawn
/// here" is one byte per pixel and nothing else needs to be re-derived.
struct WMPAlphaPlane: Hashable {
    let width: Int
    let height: Int
    private let alpha: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              width * height <= WMPPhase0Limits.imagePixels else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height)
        let ok: Bool = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            context.setBlendMode(.copy)
            // Row zero is the authored top row, matching `WMPMappingImage`: raw bitmap storage
            // never takes AppKit's view-coordinate flip.
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        self.width = width
        self.height = height
        self.alpha = bytes
    }

    func alpha(atX x: Int, y: Int) -> UInt8 {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return alpha[y * width + x]
    }
}
