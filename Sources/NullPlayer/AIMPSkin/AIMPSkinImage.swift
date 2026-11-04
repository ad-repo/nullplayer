import CoreGraphics
import Foundation

/// A skin picture: premultiplied BGRA pixels, cut into state frames, with nine-slice margins. Read
/// from its header as the skin loads; the pixels decode when it is first drawn, within the skin's
/// `AIMPSkinPixelBudget`.
///
/// `ACLIMG32` (`.img` entries): chunks after a 16-byte header, each `{ tag, u32 size, data }`:
/// - `bits` u32 format (3), width, height, pixels; `bitz` (`.acs5`) the same with a u32 packed size
///   and zlib pixels;
/// - `layt` u8 orientation (1 stacked), u32 frame count, 4 × u32 nine-slice margins
///   (left, top, right, bottom), 4 × u32 content margins (where a caption goes), then as
///   `ASEIMG32`'s: u8 how it fills and the two stretched columns (`stretchColumns`);
/// - `draw` u32 (1, 3, 5), then u8 how it fills a larger rect (`fill`).
/// An image with no pixel chunk is a solid fill AIMP stores as a colour: it has no pixels.
///
/// `.acs3` skins store `ASEIMG32` instead: a 70-byte header (u32 version, u32 pixel bytes, u32 frame
/// count at 18, u8 stacked at 27, 4 × u32 nine-slice margins at 28, u32 width and height at 62),
/// the same premultiplied BGRA pixels, then a byte per frame. AIMP 3.0's BMP skins keep the same
/// layout in `main.ini` (`Layout`) and the pixels in a Windows bitmap (`AIMPSkinBitmap`), as AIMP 2's
/// `.acs` does (laid out again as its form is read: `laidOut`, `stacking`, `rows`).
struct AIMPSkinImage: Sendable {
    struct Margins: Equatable, Sendable {
        var left = 0, top = 0, right = 0, bottom = 0

        /// `rect` with these taken off its sides.
        func inset(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX + CGFloat(left), y: rect.minY + CGFloat(top),
                   width: rect.width - CGFloat(left + right), height: rect.height - CGFloat(top + bottom))
        }
    }

    /// How a frame fills a rect bigger than itself, from the `draw` chunk's last byte.
    enum Fill: UInt8, Sendable {
        /// Nine-sliced by `margins` (0).
        case stretch = 0
        /// Repeated (1: Soot's noise grain).
        case tile = 1
        /// At its own size in the middle (2: glyphs on flat keys, Soot's 50-px play icon on its
        /// 240-px key).
        case center = 2
    }

    /// Two columns that take a wider rect's extra width between them, half each, while the rest
    /// keeps its size (Vega AIO's transport panel: its round key stays round and centred as the
    /// window widens; RealPlayer 11's bottom panel keeps its play and record slots).
    struct StretchColumns: Equatable, Sendable {
        let left: Range<Int>
        let right: Range<Int>

        /// The two, in either order, when both are columns of some width and they do not overlap.
        init?(_ a: (x: Int, width: Int), _ b: (x: Int, width: Int)) {
            let (l, r) = a.x <= b.x ? (a, b) : (b, a)
            guard l.x >= 0, l.width > 0, r.width > 0, l.x + l.width <= r.x else { return nil }
            left = l.x..<(l.x + l.width)
            right = r.x..<(r.x + r.width)
        }
    }

    /// How a picture is cut into frames and stretched: what each format's header says (`ASEIMG32`'s,
    /// `ACLIMG32`'s `layt` and `draw`), or `main.ini` for a Windows bitmap (AIMP 3.0's BMPs, AIMP 2's).
    struct Layout: Equatable, Sendable {
        var frames = 1
        var stacked = false
        var margins = Margins()
        /// Where a caption starts (`ACLIMG32`).
        var contentMargins = Margins()
        var fill = Fill.stretch
        var columns: StretchColumns?
    }

    let fill: Fill
    let width: Int
    let height: Int
    let frameCount: Int
    let stacked: Bool
    let margins: Margins
    let contentMargins: Margins
    /// None when the picture has nine-slice margins, or the columns do not fit it (a bar's
    /// stretched rows are not read yet).
    let stretchColumns: StretchColumns?
    /// The pixels; nil for a solid fill or AIMP 3.0's 0×0 placeholder (it keeps one for every object).
    private let pixels: AIMPSkinPixels?

    /// Whether the picture draws anything.
    var hasPixels: Bool { pixels != nil }

    /// Nothing drawn in the first of several frames: an invisible hit area whose later frames are
    /// its mask (Technics SL-1200's `Navigator`), not states to show.
    var firstFrameBlank: Bool { frameCount > 1 && pixels?.flags()?.firstFrameBlank == true }
    /// The last of several frames is one flat colour where drawn: a hit mask, not a state (Denon
    /// DR-F8's DSP and MENU share a knob, each key's mask its half).
    var lastFrameFlat: Bool { frameCount > 1 && pixels?.flags()?.lastFrameFlat == true }

    /// Masks made from the picture's frames, by frame and size (`AIMPSkinPainter.clipToMask`): made
    /// once, not every frame for every masked key (A4 has dozens). The picture's own, not the
    /// skin's: a mask is cut from its frames, and goes with it. A window being sized makes a mask
    /// per size; the newest few are what draws.
    private let masks = AIMPSkinCache<MaskKey, CGImage?>(limit: 32)

    private struct MaskKey: Hashable, Sendable {
        let frame: Int, width: Int, height: Int
    }

    /// Frame `frame`'s mask at `width`×`height`, as `make` draws it, made once.
    func mask(frame: Int, width: Int, height: Int, making make: () -> CGImage?) -> CGImage? {
        masks.value(MaskKey(frame: frame, width: width, height: height), making: make)
    }

    var frameSize: CGSize {
        stacked ? CGSize(width: width, height: height / frameCount)
            : CGSize(width: width / frameCount, height: height)
    }

    /// One state's frame, clamped to the last.
    func frame(_ index: Int) -> CGImage? { pixels?.frame(index) }

    /// The one initializer every format ends in: the picture's size, how it is cut and stretched,
    /// and where its pixels come from (none for a solid fill or a placeholder).
    private init(width: Int, height: Int, layout: Layout, source: AIMPSkinPixels.Source?) {
        self.width = width
        self.height = height
        frameCount = max(1, layout.frames)
        stacked = layout.stacked
        margins = layout.margins
        contentMargins = layout.contentMargins
        fill = layout.fill
        stretchColumns = layout.columns.flatMap { layout.margins == Margins() && $0.right.upperBound <= width ? $0 : nil }
        pixels = source.map { AIMPSkinPixels(width: width, height: height, frameCount: max(1, layout.frames), stacked: layout.stacked, source: $0) }
    }

    /// An `ACLIMG32` or `ASEIMG32` picture from its entry's bytes, read again from `source` when it
    /// is drawn.
    init(_ data: Data, name: String, budget: AIMPSkinPixelBudget, source: @escaping () throws -> Data) throws {
        let header = Self.isASE(data) ? try Self.ase(data, name: name) : try Self.acl(data, name: name)
        let decode = header.pixels
        self.init(width: header.width, height: header.height, layout: header.layout,
                  source: decode.map { decode in AIMPSkinPixels.Source(budget: budget) { try decode(source()) } })
    }

    /// A Windows bitmap (AIMP 3.0's BMP skins, AIMP 2's), laid out as its `main.ini` says.
    init(bitmap data: Data, name: String, layout: Layout, budget: AIMPSkinPixelBudget, source: @escaping () throws -> Data) throws {
        let header = try AIMPSkinBitmap.header(data, name: name)
        self.init(width: header.width, height: header.height, layout: layout,
                  source: AIMPSkinPixels.Source(budget: budget) { try AIMPSkinBitmap.pixels(source(), name: name) })
    }

    /// The same picture cut and stretched as `layout` says (AIMP 2's, once its `main.ini` is read).
    func laidOut(_ layout: Layout) -> AIMPSkinImage {
        guard let pixels else { return self }
        return AIMPSkinImage(width: width, height: height, layout: layout, source: pixels.source)
    }

    /// Frame `index` of `frames` stacked ones, as a picture of its own.
    func stackedFrame(_ index: Int, of frames: Int) -> AIMPSkinImage? {
        guard let pixels, frames > 0, height % frames == 0 else { return nil }
        let rows = height / frames
        return AIMPSkinImage(width: width, height: rows, layout: Layout(),
                             source: pixels.source.rows((index * rows)..<((index + 1) * rows), width: width))
    }

    /// Pictures of one size, each below the last, as the frames of one; nil when the sizes differ.
    static func stacking(_ images: [AIMPSkinImage]) -> AIMPSkinImage? {
        let parts = images.compactMap(\.pixels)
        guard let first = parts.first, parts.count == images.count,
              parts.allSatisfy({ $0.width == first.width && $0.height == first.height }),
              let source = AIMPSkinPixels.Source.stacking(parts.map(\.source), length: first.width * first.height * 4) else { return nil }
        return AIMPSkinImage(width: first.width, height: first.height * parts.count,
                             layout: Layout(frames: parts.count, stacked: true), source: source)
    }

    // MARK: - Formats

    /// What a format's header gives: the size, the layout, and how the pixels are cut from the
    /// entry's bytes (nil when it has none).
    private struct Header {
        let width: Int
        let height: Int
        let layout: Layout
        let pixels: ((Data) throws -> Data)?
    }

    /// `ASEIMG32`, or AIMP 3.0's `MySknImg` (Vega AIO), the same layout.
    private static func isASE(_ data: Data) -> Bool {
        data.prefix(8) == Data("ASEIMG32".utf8) || data.prefix(8) == Data("MySknImg".utf8)
    }

    /// `ACLIMG32`: chunks after a 16-byte header.
    private static func acl(_ data: Data, name: String) throws -> Header {
        let chunks = try chunks(data, name: name)
        var width = 0, height = 0
        if let pixels = chunks["bitz"] ?? chunks["bits"], pixels.end >= 12 {
            width = try pixels.u32(at: 4)
            height = try pixels.u32(at: 8)
        }
        let bytes = try pixelBytes(width, height, name: name)
        if let raw = chunks["bits"], chunks["bitz"] == nil, raw.end < 12 + bytes {
            throw AIMPSkinFinding(.entryUnreadable, "\(name) has \(raw.end - 12) bytes for \(width)×\(height).")
        }
        var layout = Layout()
        if let draw = chunks["draw"], draw.end >= 5 { layout.fill = Fill(rawValue: try draw.u8(at: 4)) ?? .stretch }
        if let layt = chunks["layt"] {
            layout.stacked = try layt.end >= 1 && layt.u8(at: 0) == 1
            if layt.end >= 5 { layout.frames = max(1, try layt.u32(at: 1)) }
            if layt.end >= 21 { layout.margins = try margins(layt, at: 5) }
            if layt.end >= 37 { layout.contentMargins = try margins(layt, at: 21) }
            // Whatever the fill byte at 37 says, columns given are the ones that stretch (RealPlayer
            // 11's bottom panel fills "as is" and names its two).
            if layt.end >= 54 { layout.columns = try columns(layt, at: 38) }
        }
        let pixels: ((Data) throws -> Data)? = width > 0 && height > 0 ? { try aclPixels($0, name: name) } : nil
        return Header(width: width, height: height, layout: layout, pixels: pixels)
    }

    /// The pixels of an `ACLIMG32`'s `bits` chunk, or its `bitz` (a u32 packed size, then zlib).
    private static func aclPixels(_ data: Data, name: String) throws -> Data {
        let chunks = try chunks(data, name: name)
        if let packed = chunks["bitz"], packed.end >= 16 {
            let bytes = try pixelBytes(try packed.u32(at: 4), try packed.u32(at: 8), name: name)
            return try AIMPSkinZlib.inflate(packed.data.dropFirst(16), expected: bytes, name: name)
        }
        guard let raw = chunks["bits"], raw.end >= 12 else {
            throw AIMPSkinFinding(.entryUnreadable, "\(name) has no pixels.")
        }
        return raw.data.dropFirst(12)
    }

    /// `ASEIMG32`: a 70-byte header, then the pixels.
    private static func ase(_ data: Data, name: String) throws -> Header {
        let header = AIMPSkinBytes(data, code: .entryUnreadable)
        guard header.end >= 70 else { throw AIMPSkinFinding(.entryUnreadable, "\(name) has a short ASEIMG32 header.") }
        let width = try header.u32(at: 62), height = try header.u32(at: 66)
        var layout = Layout(frames: max(1, try header.u32(at: 18)), stacked: try header.u8(at: 27) == 1, margins: try margins(header, at: 28))
        // u8 at 44 is how it fills (0 as is, 1 stretched, 2 tiled); `MySknImg` keeps the two
        // columns after it, at 45.
        if try header.u8(at: 44) == 1 { layout.columns = try columns(header, at: 45) }
        // A 0×0 picture: AIMP 3.0 keeps one for every object, drawn or not.
        guard width > 0 || height > 0 else { return Header(width: 0, height: 0, layout: layout, pixels: nil) }
        guard width > 0, height > 0, data.count >= 70 + (try pixelBytes(width, height, name: name)) else {
            throw AIMPSkinFinding(.entryUnreadable, "\(name) has \(data.count - 70) bytes for \(width)×\(height).")
        }
        return Header(width: width, height: height, layout: layout, pixels: { $0.dropFirst(70) })
    }

    /// `ACLIMG32`'s chunks `{ tag, u32 size, data }` after its 16-byte header, by tag, each a
    /// cursor over its own bytes.
    private static func chunks(_ data: Data, name: String) throws -> [String: AIMPSkinBytes] {
        guard data.count >= 16, data.prefix(8) == Data("ACLIMG32".utf8) else {
            throw AIMPSkinFinding(.entryUnreadable, "\(name) is not an ACLIMG32 image.")
        }
        var reader = AIMPSkinBytes(data, code: .entryUnreadable)
        reader.offset = 16
        var chunks: [String: AIMPSkinBytes] = [:]
        while reader.remaining >= 8 {
            let tag = try reader.ascii(4)
            let size = try reader.u32()
            guard size <= reader.remaining else {
                throw AIMPSkinFinding(.entryUnreadable, "\(name): chunk \(tag) runs past the image.")
            }
            let range = try reader.skip(size)
            chunks[tag] = AIMPSkinBytes(data.subdata(in: (data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound)),
                                        code: .entryUnreadable)
        }
        return chunks
    }

    /// `width × height` BGRA pixels' bytes; a size no picture can have (the header lies) is a finding.
    private static func pixelBytes(_ width: Int, _ height: Int, name: String) throws -> Int {
        let (pixels, over) = width.multipliedReportingOverflow(by: height)
        guard !over, pixels <= Int.max / 4 else { throw AIMPSkinFinding(.entryUnreadable, "\(name) claims \(width)×\(height) pixels.") }
        return pixels * 4
    }

    private static func margins(_ bytes: AIMPSkinBytes, at: Int) throws -> Margins {
        Margins(left: try bytes.u32(at: at), top: try bytes.u32(at: at + 4), right: try bytes.u32(at: at + 8), bottom: try bytes.u32(at: at + 12))
    }

    /// Two columns as four u32s, `x, width, x, width`.
    private static func columns(_ bytes: AIMPSkinBytes, at: Int) throws -> StretchColumns? {
        StretchColumns((try bytes.u32(at: at), try bytes.u32(at: at + 4)), (try bytes.u32(at: at + 8), try bytes.u32(at: at + 12)))
    }
}
