import CoreGraphics
import Foundation

/// A bounded, self-contained Windows BMP reader used when ImageIO refuses a file the skin author's
/// tools wrote happily. ImageIO rejects legacy WMP artwork on details Windows treats as advisory —
/// `biClrImportant` set while `biClrUsed` is zero, and some well-formed RLE8 streams — so a corpus
/// bitmap that every Windows player draws would otherwise fail with `WMP0033`.
///
/// It decodes to straight RGBA (alpha 255 everywhere except a BI_BITFIELDS alpha channel), so the
/// existing color-key pass still sees un-premultiplied source pixels.
enum WMPBitmapDecoder {
    struct Limits {
        var maximumDimension: Int
        var maximumPixels: UInt64
        var maximumDecodedBytes: UInt64
    }

    enum Failure: Error {
        /// The bytes are not a BMP this decoder understands; the caller keeps ImageIO's diagnostic.
        case unsupported(String)
        /// The bitmap is structurally fine but larger than the bounded limits allow.
        case oversized(String)
    }

    struct Decoded {
        let image: CGImage
        let width: Int
        let height: Int
        /// Straight RGBA bytes, four per pixel.
        let decodedBytes: Int
    }

    static func decode(_ data: Data, limits: Limits) throws -> Decoded {
        let bytes = [UInt8](data)
        guard bytes.count > 26, bytes[0] == 0x42, bytes[1] == 0x4D else {
            throw Failure.unsupported("not a BMP file header")
        }
        let pixelOffset = Int(u32(bytes, 10))
        let headerSize = Int(u32(bytes, 14))

        let width: Int, height: Int, bitsPerPixel: Int, compression: Int
        let paletteEntrySize: Int, declaredPaletteCount: Int
        switch headerSize {
        case 12:
            guard bytes.count >= 26 else { throw Failure.unsupported("truncated core header") }
            width = Int(i16(bytes, 18))
            height = Int(i16(bytes, 20))
            bitsPerPixel = Int(u16(bytes, 24))
            compression = 0
            paletteEntrySize = 3
            declaredPaletteCount = 0
        case 40, 52, 56, 64, 108, 124:
            guard bytes.count >= 14 + headerSize else {
                throw Failure.unsupported("truncated info header")
            }
            width = Int(i32(bytes, 18))
            height = Int(i32(bytes, 22))
            bitsPerPixel = Int(u16(bytes, 28))
            compression = Int(u32(bytes, 30))
            paletteEntrySize = 4
            declaredPaletteCount = Int(u32(bytes, 46))
        default:
            throw Failure.unsupported("unsupported DIB header size \(headerSize)")
        }

        let topDown = height < 0
        let pixelHeight = abs(height)
        guard width > 0, pixelHeight > 0 else { throw Failure.unsupported("empty bitmap") }
        guard width <= limits.maximumDimension, pixelHeight <= limits.maximumDimension else {
            throw Failure.oversized("\(width)x\(pixelHeight)")
        }
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: pixelHeight)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow, !byteOverflow, UInt64(pixelCount) <= limits.maximumPixels,
              UInt64(byteCount) <= limits.maximumDecodedBytes else {
            throw Failure.oversized("\(width)x\(pixelHeight)")
        }

        var masks: BitFields?
        if compression == 3 || compression == 6 {
            guard bitsPerPixel == 16 || bitsPerPixel == 32 else {
                throw Failure.unsupported("BI_BITFIELDS at \(bitsPerPixel)bpp")
            }
            // The masks sit at DIB offset 40 either way: inside a V4/V5 header, or straight after
            // a 40-byte one.
            let base = 14 + 40
            guard bytes.count >= base + 12 else { throw Failure.unsupported("truncated bitfields") }
            let alphaOffset = base + 12
            let alpha: UInt32 = (headerSize >= 56 && bytes.count >= alphaOffset + 4)
                ? u32(bytes, alphaOffset) : 0
            masks = BitFields(red: u32(bytes, base), green: u32(bytes, base + 4),
                              blue: u32(bytes, base + 8), alpha: alpha)
        }

        let paletteStart = 14 + headerSize + ((compression == 3 || compression == 6)
            && headerSize == 40 ? 12 : 0)
        var palette: [(UInt8, UInt8, UInt8)] = []
        if bitsPerPixel <= 8 {
            var count = declaredPaletteCount > 0 ? declaredPaletteCount : (1 << bitsPerPixel)
            let available = max(0, min(bytes.count, pixelOffset > paletteStart ? pixelOffset
                                       : bytes.count) - paletteStart) / paletteEntrySize
            count = min(count, available)
            guard count > 0 else { throw Failure.unsupported("missing palette") }
            palette.reserveCapacity(count)
            for index in 0..<count {
                let offset = paletteStart + index * paletteEntrySize
                palette.append((bytes[offset + 2], bytes[offset + 1], bytes[offset]))
            }
        }

        let dataStart = (pixelOffset > 0 && pixelOffset < bytes.count)
            ? pixelOffset : paletteStart + palette.count * paletteEntrySize
        guard dataStart < bytes.count else { throw Failure.unsupported("no pixel data") }

        var rgba = [UInt8](repeating: 0, count: byteCount)
        switch compression {
        case 0, 3, 6:
            try readPacked(bytes, from: dataStart, into: &rgba, width: width, height: pixelHeight,
                           bitsPerPixel: bitsPerPixel, topDown: topDown, palette: palette,
                           masks: masks)
        case 1 where bitsPerPixel == 8, 2 where bitsPerPixel == 4:
            readRunLength(bytes, from: dataStart, into: &rgba, width: width, height: pixelHeight,
                          fourBit: compression == 2, topDown: topDown, palette: palette)
        default:
            throw Failure.unsupported("compression \(compression) at \(bitsPerPixel)bpp")
        }

        let info = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: width, height: pixelHeight, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info,
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else {
            throw Failure.unsupported("could not build a CGImage")
        }
        return Decoded(image: image, width: width, height: pixelHeight, decodedBytes: byteCount)
    }

    // MARK: - Pixel readers

    private struct BitFields {
        let red: UInt32, green: UInt32, blue: UInt32, alpha: UInt32
    }

    private static func readPacked(_ bytes: [UInt8], from start: Int, into rgba: inout [UInt8],
                                   width: Int, height: Int, bitsPerPixel: Int, topDown: Bool,
                                   palette: [(UInt8, UInt8, UInt8)], masks: BitFields?) throws {
        let rowBytes = ((width * bitsPerPixel + 31) / 32) * 4
        for row in 0..<height {
            let sourceRow = topDown ? row : height - 1 - row
            let rowStart = start + sourceRow * rowBytes
            guard rowStart >= 0 else { continue }
            for column in 0..<width {
                var red: UInt8 = 0, green: UInt8 = 0, blue: UInt8 = 0, alpha: UInt8 = 255
                switch bitsPerPixel {
                case 1, 4, 8:
                    let bitOffset = column * bitsPerPixel
                    let index = rowStart + bitOffset / 8
                    guard index < bytes.count else { continue }
                    let byte = bytes[index]
                    let value: Int
                    switch bitsPerPixel {
                    case 1: value = Int((byte >> (7 - UInt8(bitOffset % 8))) & 1)
                    case 4: value = Int(bitOffset % 8 == 0 ? byte >> 4 : byte & 0x0F)
                    default: value = Int(byte)
                    }
                    guard value < palette.count else { continue }
                    (red, green, blue) = palette[value]
                case 16:
                    let index = rowStart + column * 2
                    guard index + 1 < bytes.count else { continue }
                    let value = UInt32(bytes[index]) | (UInt32(bytes[index + 1]) << 8)
                    if let masks {
                        red = channel(value, masks.red)
                        green = channel(value, masks.green)
                        blue = channel(value, masks.blue)
                        if masks.alpha != 0 { alpha = channel(value, masks.alpha) }
                    } else {
                        red = channel(value, 0x7C00)
                        green = channel(value, 0x03E0)
                        blue = channel(value, 0x001F)
                    }
                case 24, 32:
                    let step = bitsPerPixel / 8
                    let index = rowStart + column * step
                    guard index + step - 1 < bytes.count else { continue }
                    if bitsPerPixel == 32, let masks {
                        let value = UInt32(bytes[index]) | (UInt32(bytes[index + 1]) << 8)
                            | (UInt32(bytes[index + 2]) << 16) | (UInt32(bytes[index + 3]) << 24)
                        red = channel(value, masks.red)
                        green = channel(value, masks.green)
                        blue = channel(value, masks.blue)
                        if masks.alpha != 0 { alpha = channel(value, masks.alpha) }
                    } else {
                        blue = bytes[index]
                        green = bytes[index + 1]
                        red = bytes[index + 2]
                    }
                default:
                    throw Failure.unsupported("\(bitsPerPixel)bpp")
                }
                write(&rgba, row: row, column: column, width: width,
                      red: red, green: green, blue: blue, alpha: alpha)
            }
        }
    }

    /// BI_RLE8 / BI_RLE4. Pixels the stream never reaches stay transparent, which is what Windows
    /// leaves them as: an RLE bitmap is allowed to end early or skip forward with a delta.
    private static func readRunLength(_ bytes: [UInt8], from start: Int, into rgba: inout [UInt8],
                                      width: Int, height: Int, fourBit: Bool, topDown: Bool,
                                      palette: [(UInt8, UInt8, UInt8)]) {
        var index = start
        var x = 0, y = 0
        func put(_ paletteIndex: Int) {
            guard x < width, y < height, paletteIndex < palette.count else { return }
            let row = topDown ? y : height - 1 - y
            let (red, green, blue) = palette[paletteIndex]
            write(&rgba, row: row, column: x, width: width,
                  red: red, green: green, blue: blue, alpha: 255)
        }
        while index + 1 < bytes.count {
            let count = Int(bytes[index]), value = Int(bytes[index + 1])
            index += 2
            if count > 0 {
                for step in 0..<count {
                    put(fourBit ? (step % 2 == 0 ? value >> 4 : value & 0x0F) : value)
                    x += 1
                }
                continue
            }
            switch value {
            case 0: x = 0; y += 1
            case 1: return
            case 2:
                guard index + 1 < bytes.count else { return }
                x += Int(bytes[index]); y += Int(bytes[index + 1]); index += 2
            default:
                if fourBit {
                    for step in 0..<value {
                        let byte = index + step / 2
                        guard byte < bytes.count else { return }
                        put(step % 2 == 0 ? Int(bytes[byte]) >> 4 : Int(bytes[byte]) & 0x0F)
                        x += 1
                    }
                    let used = (value + 1) / 2
                    index += used + (used % 2)
                } else {
                    for step in 0..<value {
                        let byte = index + step
                        guard byte < bytes.count else { return }
                        put(Int(bytes[byte]))
                        x += 1
                    }
                    index += value + (value % 2)
                }
            }
            if y >= height { return }
        }
    }

    private static func write(_ rgba: inout [UInt8], row: Int, column: Int, width: Int,
                              red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let offset = (row * width + column) * 4
        guard offset + 3 < rgba.count else { return }
        rgba[offset] = red
        rgba[offset + 1] = green
        rgba[offset + 2] = blue
        rgba[offset + 3] = alpha
    }

    private static func channel(_ value: UInt32, _ mask: UInt32) -> UInt8 {
        guard mask != 0 else { return 0 }
        let shift = mask.trailingZeroBitCount
        let width = 32 - mask.leadingZeroBitCount - shift
        guard width > 0 else { return 0 }
        let raw = (value & mask) >> UInt32(shift)
        let maximum = (UInt32(1) << UInt32(width)) - 1
        return UInt8(min(255, (raw &* 255 &+ maximum / 2) / maximum))
    }

    // MARK: - Little-endian reads

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func i16(_ bytes: [UInt8], _ offset: Int) -> Int16 {
        Int16(bitPattern: u16(bytes, offset))
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func i32(_ bytes: [UInt8], _ offset: Int) -> Int32 {
        Int32(bitPattern: u32(bytes, offset))
    }
}
