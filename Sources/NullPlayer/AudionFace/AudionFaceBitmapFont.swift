import CoreText
import Foundation

/// A 1-bit bitmap font at one size, drawn pixel for pixel as Audion drew it: at 1× and scaled up
/// nearest-neighbour like the face's artwork. A departure from FaceKit, which draws smoothed outlines.
///
/// Two sources. The strikes a system font carries (`bloc`/`bdat`): Geneva at 9, 10, 12, 14, 18, 20
/// and 24 and Monaco at 9, 10, 12 and 14, the classic Mac screen fonts most faces name. CoreText
/// ignores them (with antialiasing off it rasterizes unhinted outlines, and 1 px stems drop out), so
/// they are read here. And QuickDraw `NFNT` strikes, the bitmap fonts face authors shipped with
/// their faces (`AudionFaceOriginalFonts`).
struct AudionFaceBitmapFont: Hashable {
    private struct Glyph {
        let width, height, bearingX, bearingY, advance: Int
        /// Rows top to bottom, each `(width + 7) / 8` bytes, most significant bit leftmost.
        let rows: [UInt8]
    }

    private enum Glyphs {
        /// By glyph ID, through the font's own character map.
        case sfnt(CTFont, [CGGlyph: Glyph])
        /// By Mac Roman code; `missing` is the strike's missing-character glyph.
        case nfnt([UInt8: Glyph], missing: Glyph?)
    }

    /// Identifies the font and size, for `Hashable`: a `TextLine` carries this.
    private let key: String
    private let glyphTable: Glyphs
    /// Image height, and the baseline's height above the image's bottom edge.
    private let height, baseline: Int

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }

    /// The 1-bit strike `font` carries at its own size, or nil.
    static func strike(of font: CTFont) -> AudionFaceBitmapFont? {
        guard let ppem = Int(exactly: CTFontGetSize(font)) else { return nil }
        return cached("\(CTFontCopyPostScriptName(font))/\(ppem)") { key in
            strike(font, ppem: ppem).map {
                AudionFaceBitmapFont(key: key, font: font, glyphs: $0.glyphs, ascent: $0.ascent, descent: $0.descent)
            }
        }
    }

    /// The QuickDraw strike in the file at `url`, or nil.
    static func nfnt(at url: URL) -> AudionFaceBitmapFont? {
        cached(url.path) { key in
            (try? Data(contentsOf: url)).flatMap { AudionFaceBitmapFont(nfnt: [UInt8]($0), key: key) }
        }
    }

    /// Each font parsed once, a miss included: every face load asks again for each of its lines.
    private static func cached(_ key: String, _ make: (String) -> AudionFaceBitmapFont?) -> AudionFaceBitmapFont? {
        lock.lock()
        defer { lock.unlock() }
        if let font = cache[key] { return font }
        let font = make(key)
        cache[key] = font
        return font
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: AudionFaceBitmapFont?] = [:]

    private init(key: String, font: CTFont, glyphs: [CGGlyph: Glyph], ascent: Int, descent: Int) {
        self.key = key
        glyphTable = .sfnt(font, glyphs)
        // QuickDraw's line, as for an `NFNT`: the strike's ascent from the top. Panic's screenshots
        // put Geneva 9 two pixels and Monaco 9 one pixel below FaceKit's outline baseline (A15).
        // The image keeps at least the outline line's height, so an inverse box keeps its size.
        height = max(Int(NSAttributedString(string: " ", attributes: [.font: font]).size().height), ascent + descent)
        baseline = height - ascent
    }

    /// A QuickDraw `NFNT`/`FONT` resource: a `FontRec` header, one bit image holding every glyph
    /// side by side, a location table (each glyph's first column) and an offset/width table.
    private init?(nfnt data: [UInt8], key: String) {
        func i16(_ at: Int) -> Int { Int(Int16(bitPattern: UInt16(data[at]) << 8 | UInt16(data[at + 1]))) }
        func u16(_ at: Int) -> Int { Int(UInt16(data[at]) << 8 | UInt16(data[at + 1])) }
        guard data.count >= 26 else { return nil }
        let first = i16(2), last = i16(4), kernMax = i16(8), rectHeight = i16(14)
        let ascent = i16(18), descent = i16(20), leading = i16(22), rowBytes = i16(24) * 2
        // `owTLoc` is a word offset from its own field; large fonts carry its high word in `nDescent`.
        let tableWords = (i16(10) > 0 ? i16(10) << 16 : 0) | u16(16)
        let image = 26, locations = image + rowBytes * rectHeight, widths = 16 + tableWords * 2
        let count = last - first + 2   // every character, then the missing-character glyph
        guard first >= 0, last >= first, last <= 255, rectHeight > 0, rowBytes > 0,
              locations + 2 * (count + 1) <= data.count, widths + 2 * count <= data.count else { return nil }

        var glyphs: [UInt8: Glyph] = [:], missing: Glyph?
        for index in 0..<count {
            let entry = u16(widths + 2 * index)
            guard entry != 0xFFFF else { continue }
            let left = u16(locations + 2 * index), right = u16(locations + 2 * index + 2)
            let width = max(0, right - left), stride = (width + 7) / 8
            guard (left + width + 7) / 8 <= rowBytes else { return nil }
            var rows = [UInt8](repeating: 0, count: stride * rectHeight)
            for row in 0..<rectHeight {
                for column in 0..<width {
                    let bit = left + column
                    guard data[image + row * rowBytes + bit / 8] & (0x80 >> (bit % 8)) != 0 else { continue }
                    rows[row * stride + column / 8] |= 0x80 >> (column % 8)
                }
            }
            let glyph = Glyph(width: width, height: rectHeight, bearingX: kernMax + entry >> 8, bearingY: ascent,
                              advance: entry & 0xFF, rows: rows)
            if index == count - 1 { missing = glyph } else { glyphs[UInt8(first + index)] = glyph }
        }
        self.key = key
        glyphTable = .nfnt(glyphs, missing: missing)
        // QuickDraw's line: the ascent from the top, then descent and leading. FaceKit's outline
        // baseline, (ascent − descent) / 2, would push a strike's tight ascent out of the image.
        height = ascent + descent + leading
        baseline = descent + leading
    }

    /// The line as `AudionFaceText` lays out an outline line, at 1× then scaled by `scale`: as wide
    /// as the string, middle-truncated to `boxWidth` face pixels when `truncate`. QuickDraw's style
    /// on a bitmap: `bold` smears each glyph a pixel right and widens its advance by one; condense
    /// and extend take a pixel off or put one onto every advance. Nil for any other style, or when a
    /// character has no bitmap, so the caller draws the outline path instead.
    func image(_ text: String, color: CGColor, style: AudionFace.TextStyle, boxWidth: Int, truncate: Bool,
               scale: Int) -> CGImage? {
        guard style.subtracting([.justify, .bold, .condense, .extend]).isEmpty, let full = glyphs(text) else { return nil }
        let bold = style.contains(.bold) ? 1 : 0
        let spacing = bold + (style.contains(.condense) ? -1 : style.contains(.extend) ? 1 : 0)
        var drawn = full
        if truncate, width(full, spacing) > boxWidth {
            guard glyphs("…") != nil else { return nil }
            // Widths here are whole pixels, so an exact fit is common, and it draws: FaceKit's strict
            // fit would leave those lines blank. Nothing left to trim draws nothing.
            drawn = AudionFaceText.middleTruncated(text, toFit: CGFloat(boxWidth)) {
                glyphs($0).map { CGFloat(width($0, spacing)) } ?? .infinity
            }.flatMap { glyphs($0.text) } ?? []
        }
        guard let context = CGContext.audionFaceBitmap(width: width(full, spacing) * scale, height: height * scale)
        else { return nil }
        var pixels: [CGRect] = []
        var pen = 0
        for glyph in drawn {
            let stride = (glyph.width + 7) / 8
            for row in 0..<glyph.height {
                let y = baseline + glyph.bearingY - 1 - row
                for column in 0..<glyph.width where glyph.rows[row * stride + column / 8] & (0x80 >> (column % 8)) != 0 {
                    pixels.append(CGRect(x: (pen + glyph.bearingX + column) * scale, y: y * scale,
                                         width: (1 + bold) * scale, height: scale))
                }
            }
            pen += glyph.advance + spacing
        }
        context.setFillColor(color)
        context.fill(pixels)
        return context.makeImage()
    }

    private func glyphs(_ text: String) -> [Glyph]? {
        switch glyphTable {
        case let .sfnt(font, table):
            let characters = Array(text.utf16)
            var ids = [CGGlyph](repeating: 0, count: characters.count)
            guard CTFontGetGlyphsForCharacters(font, characters, &ids, characters.count) else { return nil }
            // A surrogate pair maps to its glyph then 0; drop the filler.
            let mapped = zip(characters, ids).filter { !UTF16.isTrailSurrogate($0.0) }.map { table[$0.1] }
            return mapped.contains { $0 == nil } ? nil : mapped.compactMap { $0 }
        case let .nfnt(table, missing):
            var out: [Glyph] = []
            for character in text {
                guard let code = String(character).data(using: .macOSRoman), code.count == 1 else { return nil }
                if let glyph = table[code[code.startIndex]] {
                    out.append(glyph)
                } else if let ascii = Self.asciiStandIns[character], let glyphs = glyphs(ascii) {
                    // Many strikes stop at ASCII; the host's dashes and the truncation ellipsis
                    // would otherwise draw as the missing-character box.
                    out += glyphs
                } else if let missing {
                    out.append(missing)
                } else {
                    return nil
                }
            }
            return out
        }
    }

    private static let asciiStandIns: [Character: String] = ["—": "-", "–": "-", "…": "..."]

    private func width(_ glyphs: [Glyph], _ spacing: Int) -> Int { glyphs.reduce(0) { $0 + $1.advance + spacing } }

    /// The 1-bit strike at `ppem`, from `bloc` (EBLC's layout) and `bdat` (EBDT's). Geneva and
    /// Monaco use index formats 1 and 3 (4- and 2-byte offsets) and the byte-aligned image formats
    /// 1 (small metrics) and 6 (big metrics); a strike in any other format is not read.
    private static func strike(_ font: CTFont, ppem: Int) -> (glyphs: [CGGlyph: Glyph], ascent: Int, descent: Int)? {
        guard let bloc = CTFontCopyTable(font, CTFontTableTag(kCTFontTableBloc), []).map({ [UInt8]($0 as Data) }),
              let bdat = CTFontCopyTable(font, CTFontTableTag(kCTFontTableBdat), []).map({ [UInt8]($0 as Data) }),
              bloc.count >= 8 else { return nil }
        func u16(_ b: [UInt8], _ at: Int) -> Int { Int(b[at]) << 8 | Int(b[at + 1]) }
        func u32(_ b: [UInt8], _ at: Int) -> Int { u16(b, at) << 16 | u16(b, at + 2) }
        func i8(_ value: UInt8) -> Int { Int(Int8(bitPattern: value)) }

        for size in 0..<u32(bloc, 4) {
            let entry = 8 + 48 * size
            guard entry + 48 <= bloc.count else { return nil }
            guard Int(bloc[entry + 45]) == ppem, bloc[entry + 46] == 1 else { continue }
            let array = u32(bloc, entry)
            var glyphs: [CGGlyph: Glyph] = [:]
            for subtable in 0..<u32(bloc, entry + 8) {
                let at = array + 8 * subtable
                guard at + 8 <= bloc.count else { return nil }
                let first = u16(bloc, at), last = u16(bloc, at + 2), header = array + u32(bloc, at + 4)
                guard first <= last, header + 8 <= bloc.count else { return nil }
                let indexFormat = u16(bloc, header), imageFormat = u16(bloc, header + 2)
                let imageData = u32(bloc, header + 4)
                guard [1, 3].contains(indexFormat), [1, 6].contains(imageFormat) else { return nil }
                let offsetSize = indexFormat == 1 ? 4 : 2
                func offset(_ index: Int) -> Int? {
                    let at = header + 8 + offsetSize * index
                    guard at + offsetSize <= bloc.count else { return nil }
                    return offsetSize == 4 ? u32(bloc, at) : u16(bloc, at)
                }
                for id in first...last {
                    guard let start = offset(id - first).map({ imageData + $0 }),
                          let end = offset(id - first + 1).map({ imageData + $0 }) else { return nil }
                    let metrics = imageFormat == 1 ? 5 : 8
                    guard end - start >= metrics, end <= bdat.count else { continue }
                    let height = Int(bdat[start]), width = Int(bdat[start + 1])
                    guard start + metrics + (width + 7) / 8 * height <= end else { continue }
                    glyphs[CGGlyph(id)] = Glyph(width: width, height: height, bearingX: i8(bdat[start + 2]),
                                                bearingY: i8(bdat[start + 3]), advance: Int(bdat[start + 4]),
                                                rows: Array(bdat[(start + metrics)..<end]))
                }
            }
            // The strike's horizontal line metrics: ascender, then descender (negative).
            return (glyphs, i8(bloc[entry + 16]), -i8(bloc[entry + 17]))
        }
        return nil
    }
}
