import CoreGraphics
import Foundation

enum WMPColorKey {
    /// The colour WMP keys out of a bitmap that carries no alpha channel and whose node declares no
    /// key of its own. It is not written in any markup — it is the default the corpus is authored
    /// against, and the authors say so by hand: **4,979 of the 6,076 `transparencyColor`
    /// declarations in the 179-archive corpus (82%, 142 skins) are exactly this colour**, and the
    /// skins in the W78 class key some siblings and leave the rest to it (`Halo 2` keys `mainBack`,
    /// `shutterSub` and `shutterStatic` `#ff00ff` and leaves `m_trans_no.png` bare; `Main_Street`
    /// authors one `transparencyColor` in the whole file). Measure the class with
    /// `scripts/wmp_implicit_key.py` before widening this rule: **527 references across 66 skins
    /// and 437 sprites** is what it covers today.
    ///
    /// **The sprite's own alpha channel does not veto it (W78a).** W78 shipped with that veto, on
    /// the reasoning that a PNG or GIF which authored transparency has already said what is
    /// see-through. The corpus says otherwise: `scripts/wmp_implicit_key.py --alpha` measures the
    /// complement W78 left behind — 76 references across 21 skins and 62 sprites — and **11 of
    /// those nodes carry two states of the same button, one exported without an alpha channel and
    /// one with, holding pixel-for-pixel identical magenta** (`Half-Life_2`'s `m_pause_no.png` /
    /// `m_pause_hov.gif`, both 1,394; `Harry_Potter…`'s `bottomgroup_no.png` / `bottomgroup_hover.gif`,
    /// both 5,866). Under the veto the normal state keyed and the hover state did not, so the button
    /// turned magenta under the pointer — which no author wrote. The alpha channel is an export
    /// format, not a statement about the key.
    static let implicitTransparency = WMPColor(red: 255, green: 0, blue: 255)

    /// Replaces only pixels whose un-premultiplied RGB exactly matches the key. Non-matching pixels
    /// keep their original alpha, including partial alpha from PNG/GIF sources.
    static func applying(_ key: WMPColor, to image: CGImage) throws -> CGImage {
        try applying([key], to: image)
    }

    /// A node may declare more than one key — `clippingColor` cuts the shape of a subview out of its
    /// own artwork while `transparencyColor` keys the drawing inside it, and the two are different
    /// colours in most of the corpus. Every declared key clears in one pass.
    static func applying(_ keys: [WMPColor], to image: CGImage) throws -> CGImage {
        guard !keys.isEmpty else { return image }
        let width = image.width, height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace, bitmapInfo: bitmapInfo) else {
            throw WMPFailure(WMPDiagnostic(.imageDecodeFailed,
                "Unable to allocate a bounded color-key surface."))
        }
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            throw WMPFailure(WMPDiagnostic(.imageDecodeFailed,
                "Unable to access color-key pixels."))
        }
        for index in 0..<(width * height) {
            let offset = index * 4
            let alpha = bytes[offset + 3]
            guard alpha > 0 else { continue }
            let red = unpremultiply(bytes[offset], alpha: alpha)
            let green = unpremultiply(bytes[offset + 1], alpha: alpha)
            let blue = unpremultiply(bytes[offset + 2], alpha: alpha)
            if keys.contains(where: { $0.red == red && $0.green == green && $0.blue == blue }) {
                bytes[offset] = 0
                bytes[offset + 1] = 0
                bytes[offset + 2] = 0
                bytes[offset + 3] = 0
            }
        }
        guard let result = context.makeImage() else {
            throw WMPFailure(WMPDiagnostic(.imageDecodeFailed,
                "Unable to create a color-keyed image."))
        }
        return result
    }

    private static func unpremultiply(_ component: UInt8, alpha: UInt8) -> UInt8 {
        guard alpha < 255 else { return component }
        return UInt8(min(255, (Int(component) * 255 + Int(alpha) / 2) / Int(alpha)))
    }
}
