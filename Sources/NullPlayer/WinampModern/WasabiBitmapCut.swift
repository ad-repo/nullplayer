import CoreGraphics
import Foundation

/// A `<bitmap>`'s sprite cut — its `x`/`y`/`w`/`h` applied to the decoded file — and the pixel
/// questions asked of one. The renderer draws the cut; the initializer measures a frame's strips
/// from it, so both read the same rectangle out of the atlas.
extension WasabiResourceCache {
    /// The part of `image` a `<bitmap>` with these attributes names. `w`/`h` default to the rest of
    /// the image and are clamped to it; nil when the cut falls outside the image.
    static func cut(_ image: CGImage, attributes: [String: String]) -> CGImage? {
        var fullImage = image
        // A negative offset reaches **before** the image: the rect starts in transparent space.
        // hm_Touch ships its timer digits as a one-row sheet and declares it `y="-30" h="60"`, so
        // the digits land on row 1 — where a bitmap font keeps them. Clamped to 0, the sheet was
        // one row tall and every digit fell off it: the player's big timer drew nothing.
        // `relatx`/`relaty` offsets count from the far edge and are not padding.
        if let padded = padForNegativeOffset(fullImage, attributes: attributes) {
            fullImage = padded
        }
        let x = max(0, Int(Double(attributes["x"] ?? "0") ?? 0))
        let topY = max(0, Int(Double(attributes["y"] ?? "0") ?? 0))
        let width = max(1, min(fullImage.width - x,
                               Int(Double(attributes["w"] ?? "") ?? Double(fullImage.width - x))))
        let height = max(1, min(fullImage.height - topY,
                                Int(Double(attributes["h"] ?? "") ?? Double(fullImage.height - topY))))
        // `CGImage.cropping(to:)` addresses raw pixel data, whose origin is the image's TOP-left —
        // the same convention Wasabi's `y=` uses. Converting to a bottom-left origin here mirrored
        // every sprite's source rect about the sheet's centreline, so each element was cut from the
        // wrong row of the atlas.
        guard topY + height <= fullImage.height else { return nil }
        return fullImage.cropping(to: CGRect(x: x, y: topY, width: width, height: height))
    }

    private static let clampsNegativeOffsets =
        ProcessInfo.processInfo.environment["WINAMP_MODERN_BITMAP_NEGATIVE_CLAMP"] != nil

    /// `image` moved down/right by a declared negative `y`/`x`, on a transparent canvas, so the
    /// crop that follows can start at 0. Nil when there is nothing to pad.
    static func padForNegativeOffset(_ image: CGImage, attributes: [String: String]) -> CGImage? {
        func padding(_ axis: String, _ relat: String) -> Int {
            guard attributes[relat] != "1", let value = Double(attributes[axis] ?? "") else { return 0 }
            return max(0, -Int(value))
        }
        let left = padding("x", "relatx"), top = padding("y", "relaty")
        guard left > 0 || top > 0, !clampsNegativeOffsets,
              let context = CGContext(data: nil, width: image.width + left, height: image.height + top,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // CGContext is bottom-left origin: the image's top edge sits `top` rows below the canvas top.
        context.draw(image, in: CGRect(x: left, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// The box around `image`'s non-transparent pixels, top-left origin; nil when nothing in it is
    /// opaque.
    static func opaqueBounds(of image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        // The buffer's first row is the image's top row: a bitmap context's memory is top-down.
        for y in 0..<height {
            for x in 0..<width where alpha[y * width + x] > 0 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
