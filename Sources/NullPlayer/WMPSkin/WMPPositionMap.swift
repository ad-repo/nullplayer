import CoreGraphics
import Foundation

/// A `CUSTOMSLIDER`'s `positionImage`: the bitmap that says what fraction of the range each pixel
/// of the control represents, so a slider can run around an arbitrary path instead of along a
/// straight track. 93 of the 177 measurable corpus skins author one, and every `CUSTOMSLIDER` in
/// the corpus has one.
///
/// **What the bitmap encodes was read out of the art, not assumed.** `ALXMorph/seek_map.png` is
/// 86x10 and every column is a single grey, stepping 0, 2, 5, 8 … 252 from left to right: a
/// **greyscale ramp whose luminance is the fraction**. Its `volume_map.png` is a 72x38 arc — mostly
/// one flat colour with a ramp through the knob's travel — which is the same encoding on a path
/// that is not a line, and the reason this cannot be replaced by "interpolate across the width".
///
/// **The control is the size of the map, and `image` is a filmstrip.** `ALXMorph/seek.png` is
/// 86x600 against an 86x10 map — 60 frames stacked vertically — and its `volume.png` is 2232x38
/// against a 72x38 map, 31 frames laid out horizontally. So the strip's axis is whichever one is a
/// whole multiple of the map, and the value picks the frame. Sizing such a control from `image`
/// instead of the map makes it 2,232 pixels wide.
struct WMPPositionMap: Hashable, Codable {
    let width: Int
    let height: Int
    /// Row-major luminance in authored top-left order, one byte per pixel. Alpha-zero pixels are
    /// not part of the control and are stored as `nil` through `isMapped`.
    private let luminance: [UInt8]
    private let mapped: [Bool]

    var decodedBytes: Int { luminance.count + mapped.count }
    var size: WMPSize { WMPSize(width: CGFloat(width), height: CGFloat(height)) }

    init(image: CGImage) throws {
        width = image.width
        height = image.height
        guard width > 0, height > 0 else {
            throw WMPFailure(WMPDiagnostic(.renderFailed, "Position image has no pixels."))
        }
        let pixelWidth = width, pixelHeight = height
        var bytes = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: pixelWidth, height: pixelHeight,
                bitsPerComponent: 8, bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }
        var luminance = [UInt8](repeating: 0, count: pixelWidth * pixelHeight)
        var mapped = [Bool](repeating: false, count: pixelWidth * pixelHeight)
        // Row zero is the authored top row — a CGImage drawn into a bitmap context arrives that way
        // round; see `WMPMappingImage`. A vertical ramp is the only fixture that can see this being
        // wrong, because a horizontal one is identical under a vertical flip.
        for y in 0..<pixelHeight {
            let source = y * pixelWidth * 4
            for x in 0..<pixelWidth {
                let offset = source + x * 4
                let alpha = bytes[offset + 3]
                guard alpha > 0 else { continue }
                // Un-premultiply before averaging, or a half-transparent ramp reads as a darker
                // one — a different fraction, silently.
                let scale = Double(alpha) / 255
                let red = Double(bytes[offset]) / scale
                let green = Double(bytes[offset + 1]) / scale
                let blue = Double(bytes[offset + 2]) / scale
                let index = y * pixelWidth + x
                luminance[index] = UInt8(max(0, min(255, (red + green + blue) / 3)))
                mapped[index] = true
            }
        }
        self.luminance = luminance
        self.mapped = mapped
    }

    /// The fraction the map assigns to a point inside `frame`, or nil where the map says the point
    /// is not part of the control. Sampling is nearest-pixel against the unscaled map, the same
    /// rule `WMPMappingImage` uses, because an irregular region's value must come from an exact
    /// pixel rather than an interpolation across its boundary.
    func fraction(at point: WMPPoint, in frame: WMPRect) -> Double? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        let x = Int(((point.x - frame.x) / frame.width) * CGFloat(width))
        let y = Int(((point.y - frame.y) / frame.height) * CGFloat(height))
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let index = y * width + x
        guard mapped[index] else { return nil }
        return Double(luminance[index]) / 255
    }

    /// How `image` is laid out against this map, and which frame a fraction selects.
    ///
    /// Returns nil when the artwork is not a whole multiple of the map on either axis — a single
    /// frame the same size as the map, or art that simply does not match. The caller then draws it
    /// as an ordinary image rather than cropping a frame out of something that is not a strip.
    func frame(for fraction: Double, in artwork: WMPSize) -> WMPRect? {
        guard width > 0, height > 0, artwork.width > 0, artwork.height > 0 else { return nil }
        let horizontal = Int(artwork.width) / width
        let vertical = Int(artwork.height) / height
        let clamped = max(0, min(1, fraction))
        if horizontal > 1, Int(artwork.width) % width == 0, Int(artwork.height) == height {
            let index = min(horizontal - 1, Int((Double(horizontal - 1) * clamped).rounded()))
            return WMPRect(x: CGFloat(index * width), y: 0,
                           width: CGFloat(width), height: CGFloat(height))
        }
        if vertical > 1, Int(artwork.height) % height == 0, Int(artwork.width) == width {
            let index = min(vertical - 1, Int((Double(vertical - 1) * clamped).rounded()))
            return WMPRect(x: 0, y: CGFloat(index * height),
                           width: CGFloat(width), height: CGFloat(height))
        }
        return nil
    }
}
