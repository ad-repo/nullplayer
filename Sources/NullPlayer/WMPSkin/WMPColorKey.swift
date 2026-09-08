import CoreGraphics
import Foundation

enum WMPColorKey {
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
