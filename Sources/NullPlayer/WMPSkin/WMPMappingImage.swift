import CoreGraphics
import Foundation

/// A bounded, canonical top-left RGB mapping surface. Alpha-zero pixels and colors not registered
/// to a node are deliberately non-interactive.
struct WMPMappingImage: Hashable, Codable {
    let width: Int
    let height: Int
    private let rgb: [UInt8]
    private let alpha: [UInt8]
    let nodeByColor: [WMPColor: Int]
    let boundsByNode: [Int: WMPRect]
    var decodedBytes: Int { rgb.count + alpha.count }

    init(image: CGImage, nodeByColor: [WMPColor: Int]) throws {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              width <= WMPPhase0Limits.imageDimension,
              height <= WMPPhase0Limits.imageDimension,
              width.multipliedReportingOverflow(by: height).overflow == false,
              width * height <= WMPPhase0Limits.imagePixels else {
            throw WMPFailure(WMPDiagnostic(.oversizedImage, "Mapping image exceeds WMP image limits."))
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace, bitmapInfo: info),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            throw WMPFailure(WMPDiagnostic(.imageDecodeFailed, "Unable to allocate mapping-image pixels."))
        }
        context.setBlendMode(.copy)
        // ImageIO/CGImage decoding copied into this bitmap yields row zero in the authored top row.
        // Do not apply AppKit's view-coordinate flip to raw bitmap storage.
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        var alpha = [UInt8](repeating: 0, count: width * height)
        var extents: [Int: (minX: Int, minY: Int, maxX: Int, maxY: Int)] = [:]
        for pixel in 0..<(width * height) {
            let source = pixel * 4, destination = pixel * 3, a = bytes[source + 3]
            alpha[pixel] = a
            guard a > 0 else { continue }
            let red = Self.unpremultiply(bytes[source], alpha: a)
            let green = Self.unpremultiply(bytes[source + 1], alpha: a)
            let blue = Self.unpremultiply(bytes[source + 2], alpha: a)
            rgb[destination] = red
            rgb[destination + 1] = green
            rgb[destination + 2] = blue
            guard let node = nodeByColor[WMPColor(red: red, green: green, blue: blue)] else { continue }
            let x = pixel % width, y = pixel / width
            if let old = extents[node] {
                extents[node] = (min(old.minX, x), min(old.minY, y), max(old.maxX, x), max(old.maxY, y))
            } else {
                extents[node] = (x, y, x, y)
            }
        }
        self.width = width
        self.height = height
        self.rgb = rgb
        self.alpha = alpha
        self.nodeByColor = nodeByColor
        boundsByNode = extents.mapValues {
            WMPRect(x: CGFloat($0.minX), y: CGFloat($0.minY),
                    width: CGFloat($0.maxX - $0.minX + 1), height: CGFloat($0.maxY - $0.minY + 1))
        }
    }

    /// Test/fixture initializer with already-canonical top-left RGB bytes.
    init(width: Int, height: Int, rgb: [UInt8], alpha: [UInt8]? = nil,
         nodeByColor: [WMPColor: Int]) {
        precondition(width > 0 && height > 0 && rgb.count == width * height * 3)
        let alpha = alpha ?? [UInt8](repeating: 255, count: width * height)
        precondition(alpha.count == width * height)
        self.width = width
        self.height = height
        self.rgb = rgb
        self.alpha = alpha
        self.nodeByColor = nodeByColor
        var extents: [Int: (Int, Int, Int, Int)] = [:]
        for pixel in 0..<(width * height) where alpha[pixel] > 0 {
            let offset = pixel * 3
            let color = WMPColor(red: rgb[offset], green: rgb[offset + 1], blue: rgb[offset + 2])
            guard let node = nodeByColor[color] else { continue }
            let x = pixel % width, y = pixel / width
            if let old = extents[node] {
                extents[node] = (min(old.0, x), min(old.1, y), max(old.2, x), max(old.3, y))
            } else { extents[node] = (x, y, x, y) }
        }
        boundsByNode = extents.mapValues {
            WMPRect(x: CGFloat($0.0), y: CGFloat($0.1), width: CGFloat($0.2 - $0.0 + 1),
                    height: CGFloat($0.3 - $0.1 + 1))
        }
    }

    func node(at point: WMPPoint, in frame: WMPRect) -> Int? {
        guard frame.contains(point), frame.width > 0, frame.height > 0 else { return nil }
        let x = min(width - 1, max(0, Int((point.x - frame.x) * CGFloat(width) / frame.width)))
        let y = min(height - 1, max(0, Int((point.y - frame.y) * CGFloat(height) / frame.height)))
        let pixel = y * width + x
        guard alpha[pixel] > 0 else { return nil }
        let offset = pixel * 3
        return nodeByColor[WMPColor(red: rgb[offset], green: rgb[offset + 1], blue: rgb[offset + 2])]
    }

    func firstPixel(for node: Int) -> WMPPoint? {
        for pixel in 0..<(width * height) where alpha[pixel] > 0 {
            let offset = pixel * 3
            let color = WMPColor(red: rgb[offset], green: rgb[offset + 1], blue: rgb[offset + 2])
            if nodeByColor[color] == node {
                return WMPPoint(x: CGFloat(pixel % width), y: CGFloat(pixel / width))
            }
        }
        return nil
    }

    /// **Per pixel, this is a byte comparison against a handful of colours — never a dictionary
    /// lookup.** A mapping image registers at most a few colours (the corpus's widest group has
    /// nine), so the accepted set is resolved once and the inner loop compares three bytes against
    /// it. Hashing `WMPColor` per pixel instead put `swift_retain`/`swift_release` and
    /// `Dictionary.lookup` at the top of a live profile the moment W154 made every group's base
    /// sheet mask on every frame — six saturated cooperative threads on `New Super Mario Bros`.
    /// The caller caches the result (`WMPImageStore.mappingMask`); this only has to not be
    /// gratuitous.
    func maskImage(for nodes: Set<Int>) -> CGImage? {
        let accepted = nodeByColor.filter { nodes.contains($0.value) }.keys
            .map { ($0.red, $0.green, $0.blue) }
        var bytes = [UInt8](repeating: 0, count: width * height)
        if !accepted.isEmpty {
            for pixel in 0..<(width * height) where alpha[pixel] > 0 {
                let offset = pixel * 3
                let red = rgb[offset], green = rgb[offset + 1], blue = rgb[offset + 2]
                if accepted.contains(where: { $0 == red && $1 == green && $2 == blue }) {
                    bytes[pixel] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.linearGray) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: width, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func unpremultiply(_ component: UInt8, alpha: UInt8) -> UInt8 {
        guard alpha < 255 else { return component }
        return UInt8(min(255, (Int(component) * 255 + Int(alpha) / 2) / Int(alpha)))
    }
}
