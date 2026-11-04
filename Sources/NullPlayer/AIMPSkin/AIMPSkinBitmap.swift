import Foundation

/// The Windows bitmaps AIMP 3.0's `.acs3` kind 1 (`AddBtn.bmp`) and AIMP 2's `.acs` keep their
/// pictures in, decoded to the premultiplied BGRA, top row first, that `AIMPSkinImage` holds. How
/// each picture is cut into frames is in `main.ini`.
/// - Headers: `BITMAPINFOHEADER` or later, or the 12-byte `BITMAPCOREHEADER`; rows bottom-up unless
///   the height is negative. Uncompressed, or `BI_BITFIELDS` for 16 and 32 bits; RLE is not read.
/// - Depths: 1, 4 and 8 bits through the palette, 16 (5-5-5 or by masks), 24, 32.
/// - Transparency: magenta (`FF00FF`) is the key colour, clear wherever it is drawn (AIMP 2's round
///   corners and shaped keys). 32 bits carry straight alpha, unless every alpha byte is 0: Delphi
///   writes those with no alpha at all, and they are opaque.
/// - Some of AIMP 2's catalog states a pixel offset 1,024 bytes past where its pixels are (a
///   palette's room counted twice): the pixels end the file, so they are read from there.
///
/// Not Classic's `BMPParser`, on purpose: families do not share decoders (`skin-subsystem-blueprint`
/// § *Isolation*; `AudionFaceZipImport` keeps its own zip reader beside WMP's for the same reason).
/// - AIMP reads a picture's header alone as the skin loads, and decodes its pixels later, off the
///   main thread, into the raw premultiplied BGRA its frames are cut from (`AIMPSkinPixels`);
///   `BMPParser` decodes the whole file into an `NSImage`.
/// - AIMP's bitmaps need what Classic's do not: straight 32-bit alpha (and Delphi's all-zero alpha
///   read as opaque), `BI_BITFIELDS` masks, and the overstated pixel offset above.
/// - Making `BMPParser` serve both would change Classic, which AIMP work must not.
enum AIMPSkinBitmap {
    struct Header {
        let width: Int
        let height: Int
        let bitsPerPixel: Int
        let topDown: Bool
        /// Where the pixels start: the stated offset, or as far back from the file's end as they reach.
        let pixelOffset: Int
        /// 12 for a core header, 40 or more otherwise.
        let infoSize: Int
        let compression: Int
        let paletteCount: Int

        var rowBytes: Int { Self.rowBytes(width: width, bits: bitsPerPixel) }

        /// A row's bytes: rows pad to whole 32-bit words.
        static func rowBytes(width: Int, bits: Int) -> Int { (width * bits + 31) / 32 * 4 }
    }

    static func header(_ data: Data, name: String) throws -> Header {
        guard data.count >= 26, data.prefix(2) == Data("BM".utf8) else {
            throw AIMPSkinFinding(.entryUnreadable, "\(name) is not a bitmap.")
        }
        let bytes = AIMPSkinBytes(data, code: .entryUnreadable)
        let infoSize = try bytes.u32(at: 14)
        let width: Int, rawHeight: Int, bits: Int, compression: Int, colours: Int
        if infoSize == 12 {
            (width, rawHeight, bits, compression, colours) = (try bytes.u16(at: 18), try bytes.u16(at: 20), try bytes.u16(at: 24), 0, 0)
        } else {
            guard infoSize >= 40, data.count >= 54 else { throw AIMPSkinFinding(.entryUnreadable, "\(name) has a short bitmap header.") }
            width = Int(Int32(truncatingIfNeeded: try bytes.u32(at: 18)))
            rawHeight = Int(Int32(truncatingIfNeeded: try bytes.u32(at: 22)))
            bits = try bytes.u16(at: 28)
            compression = try bytes.u32(at: 30)
            colours = try bytes.u32(at: 46)
        }
        guard width > 0, rawHeight != 0, [1, 4, 8, 16, 24, 32].contains(bits),
              compression == 0 || (compression == 3 && (bits == 16 || bits == 32)) else {
            throw AIMPSkinFinding(.entryUnreadable, "\(name) is a \(bits)-bit bitmap of compression \(compression).")
        }
        let height = abs(rawHeight)
        let paletteCount = bits <= 8 ? (colours > 0 ? min(colours, 1 << bits) : 1 << bits) : 0
        let rowBytes = Header.rowBytes(width: width, bits: bits)
        let (end, overflow) = rowBytes.multipliedReportingOverflow(by: height)
        let paletteEnd = 14 + infoSize + paletteCount * (infoSize == 12 ? 3 : 4)
        let pixelOffset = overflow ? 0 : min(try bytes.u32(at: 10), data.count - end)
        guard !overflow, pixelOffset >= 14 + infoSize, paletteEnd <= data.count else {
            throw AIMPSkinFinding(.entryUnreadable, "\(name) is shorter than its \(width)×\(height) pixels.")
        }
        return Header(width: width, height: height, bitsPerPixel: bits, topDown: rawHeight < 0, pixelOffset: pixelOffset,
                      infoSize: infoSize, compression: compression, paletteCount: paletteCount)
    }

    /// Premultiplied BGRA, top row first. The loops index the bytes directly: `header` has checked
    /// that the palette and every row lie inside them.
    static func pixels(_ data: Data, name: String) throws -> Data {
        let header = try header(data, name: name)
        let width = header.width, height = header.height, bits = header.bitsPerPixel
        let source = [UInt8](data)
        let paletteStart = 14 + header.infoSize, paletteEntry = header.infoSize == 12 ? 3 : 4
        let masks = Self.masks(source, header)
        // A 32-bit bitmap with every alpha byte 0 has no alpha: Delphi writes them so.
        let opaque = bits != 32 || header.compression == 3 || !(0..<height).contains { y in
            let row = header.pixelOffset + y * header.rowBytes
            return (0..<width).contains { source[row + $0 * 4 + 3] != 0 }
        }
        var out = Data(count: width * height * 4)
        out.withUnsafeMutableBytes { raw in
            let to = raw.bindMemory(to: UInt8.self)
            for y in 0..<height {
                let row = header.pixelOffset + (header.topDown ? y : height - 1 - y) * header.rowBytes
                for x in 0..<width {
                    var b: UInt8, g: UInt8, r: UInt8, a: UInt8 = 255
                    switch bits {
                    case 32 where header.compression == 0:
                        let from = row + x * 4
                        (b, g, r) = (source[from], source[from + 1], source[from + 2])
                        if !opaque { a = source[from + 3] }
                    case 16, 32:
                        let from = row + x * bits / 8
                        let value = (0..<(bits / 8)).reduce(UInt32(0)) { $0 | UInt32(source[from + $1]) << (8 * $1) }
                        (b, g, r) = (masks[2].scale(value), masks[1].scale(value), masks[0].scale(value))
                    case 24:
                        let from = row + x * 3
                        (b, g, r) = (source[from], source[from + 1], source[from + 2])
                    default:
                        let bit = x * bits
                        let index = min(Int(source[row + bit / 8] >> (8 - bits - bit % 8)) & (1 << bits - 1), header.paletteCount - 1)
                        let at = paletteStart + index * paletteEntry
                        (b, g, r) = (source[at], source[at + 1], source[at + 2])
                    }
                    let at = (y * width + x) * 4
                    if b == 255, g == 0, r == 255 { a = 0 }
                    let alpha = Int(a)
                    to[at] = UInt8((Int(b) * alpha + 127) / 255)
                    to[at + 1] = UInt8((Int(g) * alpha + 127) / 255)
                    to[at + 2] = UInt8((Int(r) * alpha + 127) / 255)
                    to[at + 3] = a
                }
            }
        }
        return out
    }

    /// A channel of a 16- or 32-bit pixel, by its mask, widened to 8 bits.
    private struct Mask {
        let mask: UInt32

        func scale(_ value: UInt32) -> UInt8 {
            guard mask != 0 else { return 0 }
            let shift = mask.trailingZeroBitCount
            return UInt8(((value & mask) >> shift) * 255 / (mask >> shift))
        }
    }

    /// Red, green and blue masks: `BI_BITFIELDS`' (after a 40-byte header, or inside a longer one:
    /// the same offset), else 5-5-5.
    private static func masks(_ source: [UInt8], _ header: Header) -> [Mask] {
        guard header.compression == 3, source.count >= 66 else { return [Mask(mask: 0x7C00), Mask(mask: 0x03E0), Mask(mask: 0x001F)] }
        return (0..<3).map { i in Mask(mask: (0..<4).reduce(UInt32(0)) { $0 | UInt32(source[54 + i * 4 + $1]) << (8 * $1) }) }
    }
}
