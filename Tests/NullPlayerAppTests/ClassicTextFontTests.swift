import XCTest
@testable import NullPlayer

/// TEXT.BMP's third row is `Å Ö Ä ? *`, so `?` and `*` are columns 3 and 4, not the `Å`/`Ö` cells (#755).
final class ClassicTextFontTests: XCTestCase {
    private let font = SkinElements.TextFont.self

    func testQuestionMarkAndAsteriskUseTheirOwnCells() {
        XCTAssertEqual(font.character("?"), NSRect(x: 15, y: 12, width: 5, height: 6))
        XCTAssertEqual(font.character("*"), NSRect(x: 20, y: 12, width: 5, height: 6))
    }

    func testRingAndUmlautLettersUseTheirThirdRowCells() {
        for (letters, column) in [("Åå", 0), ("Öö", 1), ("Ää", 2)] {
            for letter in letters {
                XCTAssertEqual(font.character(letter), NSRect(x: column * 5, y: 12, width: 5, height: 6),
                               "\(letter)")
            }
        }
        // The new cases sit ahead of "A"..."Z"; plain A must still be the first cell.
        XCTAssertEqual(font.character("A"), NSRect(x: 0, y: 0, width: 5, height: 6))
    }

    func testLowercaseDrawsAsItsCapitalAndAnythingElseAsASpace() {
        XCTAssertEqual(font.character("q"), font.character("Q"))
        XCTAssertEqual(font.character("ö"), font.character("Ö"))
        for unknown: Character in [",", ";", "é", "Ж", "由", "ß"] {
            XCTAssertEqual(font.character(unknown), font.character(" "), "\(unknown)")
        }
    }

    /// U+212A KELVIN SIGN is canonically `K`. The old switch matched it as "A"..."Z" but read its
    /// (missing) ASCII value, putting the cell at x = -325, off the sheet.
    func testCanonicalEquivalentsUseTheSameCell() {
        XCTAssertEqual(font.character("\u{212A}"), font.character("K"))
        XCTAssertEqual(font.character("A\u{030A}"), font.character("Å"))
    }

    func testEveryCellIsOnTheSheet() {
        let sheet = NSRect(x: 0, y: 0, width: 155, height: 18)
        for character in font.cells.keys {
            XCTAssertTrue(sheet.contains(font.character(character)), "\(character)")
        }
    }
}

/// Folding classic titles onto TEXT.BMP's glyphs so one accent no longer drops the whole title
/// to the system font (#798).
final class ClassicTextFoldingTests: XCTestCase {
    private func fold(_ text: String) -> String? { SkinElements.TextFont.bitmapText(text) }

    func testPlainTitleIsOnlyUppercased() {
        XCTAssertEqual(fold("Yuto Takei - Cubic Luster"), "YUTO TAKEI - CUBIC LUSTER")
        XCTAssertEqual(fold("(Remix) [2024] #1 100% @home!"), "(REMIX) [2024] #1 100% @HOME!")
        XCTAssertEqual(fold(""), "")
    }

    /// The two titles from the issue's screenshots.
    func testIssueTitlesStayInTheSkinFont() {
        XCTAssertEqual(fold("Padstow Farewell - Nils Brown, Seán Dagher"),
                       "PADSTOW FAREWELL - NILS BROWN, SEAN DAGHER")
        XCTAssertEqual(fold("Yuki Kajiura - the image theme of Xenosaga Ⅱ"),
                       "YUKI KAJIURA - THE IMAGE THEME OF XENOSAGA II")
    }

    func testAccentsAreStrippedButSkinGlyphsAreKept() {
        XCTAssertEqual(fold("Mötley Crüe"), "MÖTLEY CRUE")
        XCTAssertEqual(fold("Åsa Älvsjö"), "ÅSA ÄLVSJÖ")
        XCTAssertEqual(fold("Beyoncé Señor Garçon Ólafur"), "BEYONCE SENOR GARCON OLAFUR")
    }

    func testDecomposedInputFoldsLikeComposed() {
        XCTAssertEqual(fold("Se\u{0061}\u{0301}n"), "SEAN")       // a + combining acute
        XCTAssertEqual(fold("A\u{0308}ra"), "ÄRA")                // A + combining diaeresis is Ä
    }

    func testCompatibilityFormsExpand() {
        XCTAssertEqual(fold("Final Fantasy Ⅻ ⅳ"), "FINAL FANTASY XII IV")
        XCTAssertEqual(fold("Wait…"), "WAIT...")
        XCTAssertEqual(fold("ＡＢＣ１２３"), "ABC123")              // full-width
        XCTAssertEqual(fold("ﬁne"), "FINE")                       // ligature
        XCTAssertEqual(fold("a\u{00A0}b"), "A B")                 // no-break space
    }

    func testCaseFoldingCanLengthenText() {
        // The marquee measures the folded text, so a longer result must come back whole.
        XCTAssertEqual(fold("Straße"), "STRASSE")
    }

    func testTypographicPunctuationUsesPlainStandIns() {
        XCTAssertEqual(fold("Don’t Stop — “Live” ‘93 – «Edit»"), "DON'T STOP - \"LIVE\" '93 - \"EDIT\"")
    }

    func testLettersWithoutDecompositionUseStandIns() {
        XCTAssertEqual(fold("Øystein Łódź Æon Œuvre Þór Đorđe"), "OYSTEIN LODZ AEON OEUVRE THOR DORDE")
    }

    /// Anything with no stand-in keeps the whole title on the system font, never a mixed or gapped line.
    func testTextWithoutStandInsIsNotFolded() {
        XCTAssertNil(fold("梶浦由記"))
        XCTAssertNil(fold("Кино - Группа крови"))
        XCTAssertNil(fold("Ω"))
        XCTAssertNil(fold("Yuki Kajiura - 梶浦由記"))
        XCTAssertNil(fold("I ♥ NY"))
        XCTAssertNil(fold("Track 1; Part 2"))
        XCTAssertNil(fold("~intro~"))
    }

    func testFoldedTextOnlyHoldsDrawableCharacters() {
        let titles = ["Seán", "Xenosaga Ⅱ", "Straße", "Don’t", "ＡＢＣ", "Œuvre", "Mötley Crüe", "Wait…"]
        for title in titles {
            guard let folded = fold(title) else { XCTFail("\(title) did not fold"); continue }
            XCTAssertTrue(folded.allSatisfy(SkinElements.TextFont.drawableCharacters.contains),
                          "\(title) → \(folded)")
        }
    }
}

/// The three title tiers: skin glyphs, then Tiny5, then the system font (#798).
final class ClassicTitleFontTests: XCTestCase {
    private typealias Font = SkinElements.TextFont

    private func assertTier(_ title: String, _ font: Font.TitleFont, _ text: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let chosen = Font.titleFont(for: title)
        XCTAssertEqual(chosen.font, font, title, file: file, line: line)
        XCTAssertEqual(chosen.text, text, title, file: file, line: line)
    }

    func testPixelFontLoadsOnItsPixelGrid() throws {
        let font = try XCTUnwrap(Font.pixelFont, "Tiny5-Regular.ttf missing from the bundle")
        XCTAssertEqual(CTFontGetCapHeight(font), 5, accuracy: 0.01)
        XCTAssertEqual(CTFontGetAscent(font), 7, accuracy: 0.01)
        XCTAssertEqual(CTFontGetDescent(font), 2, accuracy: 0.01)
    }

    func testFoldableTitlesStayOnTheSkinFont() {
        assertTier("Padstow Farewell - Seán Dagher", .skin, "PADSTOW FAREWELL - SEAN DAGHER")
        assertTier("Xenosaga Ⅱ", .skin, "XENOSAGA II")
        assertTier("Åsa", .skin, "ÅSA")
    }

    func testUnfoldableTitlesTiny5CoversUseThePixelFontInCapitals() {
        assertTier("Кино - Группа крови", .pixel, "КИНО - ГРУППА КРОВИ")
        assertTier("Ωmega λ", .pixel, "ΩMEGA Λ")
        assertTier("I ♥ NY", .pixel, "I ♥ NY")
        assertTier("Track 1; Part 2", .pixel, "TRACK 1; PART 2")     // ASCII TEXT.BMP has no cell for
    }

    func testPixelTierExpandsCompatibilityFormsButKeepsAccents() {
        assertTier("Кино Ⅱ", .pixel, "КИНО II")                       // Tiny5 has no Roman numerals
        assertTier("Кино ＦＭ", .pixel, "КИНО FM")                    // full-width
        assertTier("Кино Seán", .pixel, "КИНО SEÁN")                  // Tiny5 draws the accent itself
        assertTier("Кино Se\u{0061}\u{0301}n", .pixel, "КИНО SEÁN")   // decomposed composes first
    }

    /// A title is never split across fonts: one glyph Tiny5 lacks sends the whole of it to the system font.
    func testScriptsTiny5LacksKeepTheWholeTitleOnTheSystemFont() {
        assertTier("梶浦由記", .system, "梶浦由記")
        assertTier("Yuki Kajiura - 梶浦由記", .system, "Yuki Kajiura - 梶浦由記")
        assertTier("Кино 梶浦", .system, "Кино 梶浦")
        assertTier("アイユー", .system, "アイユー")
        assertTier("아이유", .system, "아이유")
    }

    func testPixelFontCoverage() {
        XCTAssertTrue(Font.pixelFontCovers("ÉÑÜØŁŐ ΑΩ КЖЯ ’“”—… ♥"))
        XCTAssertFalse(Font.pixelFontCovers("Ⅱ"))
        XCTAssertFalse(Font.pixelFontCovers("由"))
        XCTAssertTrue(Font.pixelFontCovers(""))
    }

    /// The marquee loops `text + separator`; its width must be the sum of the parts and land on whole
    /// pixels, or the scroll jumps at the seam and the glyphs smear between device pixels.
    func testPixelLineWidthsAreWholePixelsAndAdditive() {
        let width = Font.pixelFontWidth
        let title = "КИНО - ГРУППА КРОВИ ♥ AVAWAY", separator = "  -  "
        XCTAssertEqual(width(title + separator + title), width(title) + width(separator) + width(title),
                       accuracy: 0.001)
        for text in [title, separator, "ΩMEGA Λ"] {
            XCTAssertEqual(width(text), width(text).rounded(), accuracy: 0.001, text)
            XCTAssertGreaterThan(width(text), 0, text)
        }
    }

    /// The pixel tier renders one font pixel per image pixel and the marquee only ever enlarges it with
    /// nearest sampling, so this image is exactly what a 1x display shows. Every pixel must be fully
    /// clear or fully the lettering colour: any in-between alpha is smoothing that would blur.
    func testPixelImageIsUnsmoothedInTheGivenColour() throws {
        let text = "КИНО - ГРУППА КРОВИ ♥ SEÁN ΩMEGA"
        let color = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.2, 0.8, 0.1, 1])!
        let image = try XCTUnwrap(Font.pixelFontImage(text, width: Font.pixelFontWidth(text), height: 13, color: color))
        XCTAssertEqual(image.height, 13)
        let rows = try opaqueRows(image, expecting: [51, 204, 26])
        XCTAssertFalse(rows.isEmpty, "drew nothing")
    }

    /// The 9 px line (7 ascent + 2 descent) sits 2 px from the bottom of the 13 pt marquee, so the
    /// 5 px capitals fill rows 4–8 from the bottom, the TEXT.BMP cell's band, and accents stay inside.
    func testPixelImageIsCentredLikeATextBMPCell() throws {
        let color = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1, 1, 1, 1])!
        func rowsFromBottom(_ text: String) throws -> Set<Int> {
            let image = try XCTUnwrap(Font.pixelFontImage(text, width: Font.pixelFontWidth(text), height: 13, color: color))
            return Set(try opaqueRows(image, expecting: [255, 255, 255]).map { 12 - $0 })
        }
        XCTAssertEqual(try rowsFromBottom("КИНО"), Set(4...8))
        let accented = try rowsFromBottom("ÁÖ")
        XCTAssertTrue(accented.isSuperset(of: 4...8))
        XCTAssertLessThan(accented.max() ?? 99, 13)
    }

    /// The rows (from the top) holding any opaque pixel; fails on any pixel that is neither clear nor
    /// exactly `rgb` at full alpha.
    private func opaqueRows(_ image: CGImage, expecting rgb: [UInt8],
                            file: StaticString = #filePath, line: UInt = #line) throws -> [Int] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var rows: Set<Int> = []
        for y in 0..<height {
            for x in 0..<width {
                let p = Array(bytes[(y * width + x) * 4..<(y * width + x) * 4 + 4])
                guard p[3] != 0 else { continue }
                XCTAssertEqual(p, rgb + [255], "smoothed or off-colour pixel at (\(x), \(y))", file: file, line: line)
                // CGContext's buffer starts at the top row
                rows.insert(y)
            }
        }
        return rows.sorted()
    }

    // MARK: - Glyph colour

    /// A TEXT.BMP-sized sheet filled with `background`, with `pixels` set inside the `A` cell.
    private func sheet(background: [UInt8], pixels: [(x: Int, y: Int, rgb: [UInt8])]) -> CGImage {
        let width = 155, height = 18
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) { bytes.replaceSubrange(i * 4..<i * 4 + 3, with: background) }
        for p in pixels { bytes.replaceSubrange((p.y * width + p.x) * 4..<(p.y * width + p.x) * 4 + 3, with: p.rgb) }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    func testGlyphColorIsTheLetterPixelLeastLikeTheBackground() throws {
        let image = sheet(background: [10, 20, 30],
                          pixels: [(1, 1, [0, 100, 0]), (2, 3, [0, 220, 0]), (3, 4, [10, 30, 30])])
        let c = try XCTUnwrap(Font.glyphColor(in: image).components)
        XCTAssertEqual(c[0], 0, accuracy: 0.01)
        XCTAssertEqual(c[1], 220.0 / 255, accuracy: 0.01)
        XCTAssertEqual(c[2], 0, accuracy: 0.01)
    }

    /// The `A` cell is the top-left one; a lit pixel outside it (here in the `B` cell) is not the
    /// lettering, so this sheet's `A` is blank and the colour is the system font fallback's green.
    func testBlankACellGivesTheSystemFallbackGreen() {
        let color = Font.glyphColor(in: sheet(background: [10, 20, 30], pixels: [(6, 2, [255, 0, 0])]))
        XCTAssertEqual(NSColor(cgColor: color), NSColor(cgColor: NSColor.green.cgColor))
    }
}
