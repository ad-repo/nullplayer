import Accelerate
import CoreGraphics

/// One byte of alpha per pixel, top row first, `width` bytes a row — a window's or a sprite's
/// outline with the colour thrown away.
///
/// Shared by the skin-window drop shadow (`SkinWindowShadow`) and the `.wal` renderer's animation
/// core (`WasabiSceneRenderer.animationCore`). `WMPAlphaPlane` is the `.wmz` engine's own, with
/// that engine's size limit and keep-mask reading, and answers hit tests rather than building
/// images.
struct AlphaPlane: Equatable {
    let width: Int
    let height: Int
    private(set) var bytes: [UInt8]

    init(width: Int, height: Int, bytes: [UInt8]) {
        precondition(bytes.count == width * height, "an alpha plane is width x height bytes")
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    /// The combined alpha of `layers`, each drawn over the last to fill `width` x `height`.
    init?(layers: [CGImage], width: Int, height: Int) {
        guard width > 0, height > 0, !layers.isEmpty else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            for layer in layers { context.draw(layer, in: bounds) }
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, bytes: bytes)
    }

    /// Keep each pixel's lower alpha of this plane and `other`, which is the same size.
    mutating func formMinimum(_ other: AlphaPlane) {
        precondition(other.width == width && other.height == height, "planes differ in size")
        for index in bytes.indices where other.bytes[index] < bytes[index] {
            bytes[index] = other.bytes[index]
        }
    }

    /// Premultiplied black at this alpha — or at `table[alpha]` when a 256-entry lookup is given.
    /// vImage rather than a loop: a debug build spent ~20 ms interleaving a 596x468 plane by hand.
    func blackImage(mappedThrough table: [UInt8]? = nil) -> CGImage? {
        precondition(table == nil || table?.count == 256, "a lookup maps every alpha value")
        var alpha = bytes
        var zero = [UInt8](repeating: 0, count: bytes.count)
        var pixels = [UInt8](repeating: 0, count: bytes.count * 4)
        let rows = vImagePixelCount(height), columns = vImagePixelCount(width)
        let error: vImage_Error = alpha.withUnsafeMutableBytes { alphaBytes in
            zero.withUnsafeMutableBytes { zeroBytes in
                pixels.withUnsafeMutableBytes { pixelBytes in
                    var alphaBuffer = vImage_Buffer(data: alphaBytes.baseAddress, height: rows,
                                                    width: columns, rowBytes: width)
                    var zeroBuffer = vImage_Buffer(data: zeroBytes.baseAddress, height: rows,
                                                   width: columns, rowBytes: width)
                    var destination = vImage_Buffer(data: pixelBytes.baseAddress, height: rows,
                                                    width: columns, rowBytes: width * 4)
                    if let table {
                        let result = vImageTableLookUp_Planar8(&alphaBuffer, &alphaBuffer, table,
                                                               vImage_Flags(kvImageNoFlags))
                        guard result == kvImageNoError else { return result }
                    }
                    // The four planes go in in memory order, so this is R, G, B, A: premultiplied
                    // black is (0, 0, 0, a).
                    return vImageConvert_Planar8toARGB8888(&zeroBuffer, &zeroBuffer, &zeroBuffer,
                                                           &alphaBuffer, &destination,
                                                           vImage_Flags(kvImageNoFlags))
                }
            }
        }
        guard error == kvImageNoError,
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8,
                       bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
