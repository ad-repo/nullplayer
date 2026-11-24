import AppKit

/// Which font a Classic title draws in (#798), best first:
///
/// 1. The skin's TEXT.BMP. It draws A–Z, 0–9, `Å Ö Ä` and a few symbols, so the title is folded onto
///    that set first: `é`→`E`, `Ⅱ`→`II`, curly quotes→straight. Every Latin-script title lands here.
/// 2. Tiny5, a 5 px pixel font, in capitals and the skin's glyph colour, for what does not fold:
///    Greek, Cyrillic, `♥`, ASCII TEXT.BMP has no cell for (`;`, `~`).
/// 3. The system font, for scripts Tiny5 has no glyphs for (CJK, kana, Hangul).
///
/// Before this, one character outside TEXT.BMP dropped the whole title to the system font.
extension SkinElements.TextFont {
    enum TitleFont: Equatable { case skin, pixel, system }

    /// The tier `text` draws in, and the text spelled for that tier.
    static func titleFont(for text: String) -> (font: TitleFont, text: String) {
        if let folded = bitmapText(text) { return (.skin, folded) }
        // NFKC turns `Ⅱ` into `II` and full-width letters into ASCII but keeps accents, which Tiny5 has.
        let capitals = text.precomposedStringWithCompatibilityMapping.uppercased()
        if pixelFontCovers(capitals) { return (.pixel, capitals) }
        return (.system, text)
    }

    // MARK: - Skin font (TEXT.BMP)

    /// Characters the bitmap path draws. `,` has no cell and draws as a space, as it always has.
    static let drawableCharacters = Set<Character>(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ÅÖÄ \"@:()-'!_+\\/[]^&%.=$#?*,"
    )

    /// Uppercase characters with no compatibility decomposition onto the glyph set.
    private static let standIns: [Character: String] = [
        "‘": "'", "’": "'", "‚": "'", "‛": "'", "′": "'", "`": "'", "´": "'",
        "“": "\"", "”": "\"", "„": "\"", "‟": "\"", "″": "\"", "«": "\"", "»": "\"",
        "‐": "-", "‑": "-", "‒": "-", "–": "-", "—": "-", "―": "-", "−": "-",
        "Ø": "O", "Æ": "AE", "Œ": "OE", "Ł": "L", "Đ": "D", "Ð": "D", "Þ": "TH",
    ]

    /// `text` spelled in `drawableCharacters`, or nil when some character has no stand-in.
    static func bitmapText(_ text: String) -> String? {
        var folded = ""
        for character in text.uppercased() {
            guard let drawable = drawable(character) else { return nil }
            folded += drawable
        }
        return folded
    }

    private static func drawable(_ character: Character) -> String? {
        if drawableCharacters.contains(character) { return String(character) }
        if let standIn = standIns[character] { return standIn }
        // NFKD splits `É` into `E` + accent and `Ⅱ` into `II`; drop the accents, keep the letters.
        let scalars = String(character).decomposedStringWithCompatibilityMapping.unicodeScalars
            .filter { $0.properties.generalCategory != .nonspacingMark }
        let base = String(String.UnicodeScalarView(scalars)).uppercased()
        return !base.isEmpty && base.allSatisfy(drawableCharacters.contains) ? base : nil
    }

    /// The colour of the skin's lettering: the pixel of the `A` cell least like the space cell.
    /// Nil when the `A` cell is blank.
    static func glyphColor(in sheet: CGImage) -> CGColor? {
        let space = character(" "), letter = character("A")
        guard let context = CGContext(data: nil, width: 2 * Int(charWidth), height: Int(charHeight),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let spaceCell = sheet.cropping(to: space), let letterCell = sheet.cropping(to: letter),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(spaceCell, in: CGRect(x: 0, y: 0, width: charWidth, height: charHeight))
        context.draw(letterCell, in: CGRect(x: charWidth, y: 0, width: charWidth, height: charHeight))
        let bytesPerRow = context.bytesPerRow
        func rgb(_ x: Int, _ y: Int) -> [Int] { (0..<3).map { Int(pixels[y * bytesPerRow + x * 4 + $0]) } }
        let background = rgb(0, 0)
        var best: (distance: Int, rgb: [Int]) = (0, background)
        for y in 0..<Int(charHeight) {
            for x in Int(charWidth)..<2 * Int(charWidth) {
                let pixel = rgb(x, y)
                let distance = zip(pixel, background).reduce(0) { $0 + abs($1.0 - $1.1) }
                if distance > best.distance { best = (distance, pixel) }
            }
        }
        guard best.distance > 0 else { return nil }
        let c = best.rgb.map { CGFloat($0) / 255 }
        return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [c[0], c[1], c[2], 1])
    }

    // MARK: - Pixel font (Tiny5)

    /// Tiny5 at 8 pt: 5 px capitals, 7 px ascent, 2 px descent, one font pixel per point. Read from
    /// the bundle, never registered, as `AudionFaceFontSubstitutes` does.
    static let pixelFont: CTFont? = {
        guard let url = BundleHelper.url(forResource: "Tiny5-Regular", withExtension: "ttf", subdirectory: "Fonts"),
              let found = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              // Tiny5 is a variable font; take the default instance.
              let descriptor = found.first(where: {
                  CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == "Tiny5-Regular"
              }) ?? found.first else { return nil }
        return CTFontCreateWithFontDescriptor(descriptor, 8, nil)
    }()

    static func pixelFontCovers(_ text: String) -> Bool {
        guard let pixelFont else { return false }
        let units = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        return CTFontGetGlyphsForCharacters(pixelFont, units, &glyphs, units.count)
    }

    /// A line of `text` in the pixel font, drawn in the context's fill colour. Tiny5 has whole-pixel
    /// advances and no kerning, so a marquee's `text + separator` is exactly as wide as its parts.
    static func pixelFontLine(_ text: String) -> CTLine? {
        guard let pixelFont else { return nil }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: pixelFont,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}
