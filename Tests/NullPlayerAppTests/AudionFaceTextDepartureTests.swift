import XCTest
@testable import NullPlayer

/// The text departures from FaceKit restored from Audion's `Txtr` resources: the override table,
/// alignment, and the bitmap fonts (`skills/audion-face-guide/reference/rendering.md` § *Text*).
final class AudionFaceTextDepartureTests: XCTestCase {
    private func album(_ json: [String: Any], override: AudionFaceTextOverrides.Line? = nil) throws -> AudionFace.TextLine {
        var json = json
        json["albumDisplayRect"] = AudionFaceFixture.rect(top: 0, left: 0, bottom: 12, right: 100)
        json["albumTextMode"] = json["albumTextMode"] ?? 1
        for suffix in ["Bold", "Italic", "Underline", "Outline", "Shadow", "Condense", "Extend", "Justify"]
        where json["album\(suffix)"] == nil {
            json["album\(suffix)"] = false
        }
        let data = try JSONSerialization.data(withJSONObject: json)
        return try XCTUnwrap(AudionFaceDocument.decode(data, overrides: override.map { [.album: $0] }).album)
    }

    func testAnOverrideRestoresWhatTheConversionDropped() throws {
        let line = try album(["albumJustify": true, "albumDisplayFontName": "Geneva", "albumFontSize": 9],
                             override: .init(fontName: "Monaco", fontSize: 10,
                                             color: AudionFace.color(red: 255, green: 0, blue: 0), alignment: .right))
        XCTAssertEqual(CTFontCopyFamilyName(line.font) as String, "Monaco")
        XCTAssertEqual(CTFontGetSize(line.font), 10)
        XCTAssertEqual(line.color.components, [1, 0, 0, 1])
        XCTAssertEqual(line.alignment, .right, "the override's right wins over Justify's centre")
        XCTAssertTrue(line.style.contains(.justify), "truncation still follows Justify")
    }

    func testJustifyCentresAndItsAbsenceLeavesLeft() throws {
        XCTAssertEqual(try album(["albumJustify": true]).alignment, .center)
        XCTAssertEqual(try album([:]).alignment, .left)
    }

    func testAPinnedLineIsOffsetInWholeFacePixels() throws {
        let line = try album(["albumJustify": true])   // box 100 face px wide
        XCTAssertEqual(AudionFaceScene.alignmentOffset(line, textWidth: 2 * 41, scale: 2), 2 * 29, "(100 − 41) / 2 = 29")
        XCTAssertEqual(AudionFaceScene.alignmentOffset(line, textWidth: 2 * 140, scale: 2), 0, "wider than the box: left")
        let right = try album([:], override: .init(alignment: .right))
        XCTAssertEqual(AudionFaceScene.alignmentOffset(right, textWidth: 40, scale: 1), 60)
    }

    /// Departure: text mode 4 (QuickDraw `notSrcCopy`) is inverse video, the line colour's box with
    /// the glyphs knocked out in white (aPop, A14).
    func testTextModeFourIsInverseVideo() throws {
        XCTAssertFalse(try album([:]).inverse)
        let line = try album(["albumTextMode": 4, "albumDisplayTextFaceColorFromFace": ["red": 0, "green": 0, "blue": 255]])
        XCTAssertTrue(line.inverse)
        let image = try XCTUnwrap(AudionFaceText.image("H", line: line, justify: false, scale: 1, reduceMotion: true))
        let corner = AudionFaceSceneTests.pixel(image, 0, 0)   // blue, give or take the colour space
        XCTAssertTrue(corner[0] < 32 && corner[1] < 64 && corner[2] > 230 && corner[3] == 255, "the box: \(corner)")
        let pixels = (0..<image.width).flatMap { x in (0..<image.height).map { AudionFaceSceneTests.pixel(image, x, $0) } }
        XCTAssertTrue(pixels.contains([255, 255, 255, 255]), "white glyphs")
    }

    /// A strike sits on its own `bloc` line metrics (A15): the bottom of an H is ascent − 1 rows
    /// from the top, 10 for Geneva 9 and 9 for Monaco 9.
    func testAStrikeSitsOnItsOwnAscent() throws {
        let black = AudionFace.color(red: 0, green: 0, blue: 0)
        for (name, ascent) in [("Geneva", 10), ("Monaco", 9)] {
            let strike = try XCTUnwrap(AudionFaceBitmapFont.strike(of: NSFont(name: name, size: 9)!))
            let image = try XCTUnwrap(strike.image("H", color: black, style: [], boxWidth: 100, truncate: false, scale: 1))
            let rows = (0..<image.height).filter { y in (0..<image.width).contains { AudionFaceSceneTests.pixel(image, $0, y)[3] > 0 } }
            XCTAssertEqual(rows.last, ascent - 1, name)
        }
    }

    func testTheBitmapPathTakesOnlyAStrikeSize() throws {
        XCTAssertNotNil(AudionFaceBitmapFont.strike(of: NSFont(name: "Geneva", size: 9)!))
        XCTAssertNotNil(AudionFaceBitmapFont.strike(of: NSFont(name: "Monaco", size: 12)!))
        XCTAssertNil(AudionFaceBitmapFont.strike(of: NSFont(name: "Geneva", size: 11)!), "no strike at 11")
        XCTAssertNil(AudionFaceBitmapFont.strike(of: NSFont(name: "Helvetica", size: 9)!), "an outline-only font")
        XCTAssertNotNil(try album(["albumDisplayFontName": "Geneva", "albumFontSize": 9]).bitmap)
        XCTAssertNil(try album(["albumDisplayFontName": "Geneva", "albumFontSize": 11]).bitmap)
    }

    /// The strike follows the outline's size rules: size 0 is 12, and a size outside the policy is
    /// Helvetica 12, so no strike.
    func testTheStrikeTakesTheOutlinesSize() throws {
        let twelve = try XCTUnwrap(AudionFaceOriginalFonts.bitmap(named: "Orchis 6", size: 12))
        XCTAssertEqual(AudionFace.font(named: "Orchis 6", size: 0).bitmap, twelve)
        XCTAssertNil(AudionFace.font(named: "Mini", size: 5_000).bitmap)
    }

    /// The cut is the first one no wider than the box, an exact fit included: the bitmap path draws
    /// it, and only the outline path keeps FaceKit's strict fit.
    func testMiddleTruncationStopsAtTheFirstCutThatFits() {
        let cut = AudionFaceText.middleTruncated("abcdef", toFit: 5) { CGFloat($0.count) }
        XCTAssertEqual(cut?.text, "ab…ef")
        XCTAssertEqual(cut?.width, 5)
        XCTAssertNil(AudionFaceText.middleTruncated("abcdef", toFit: 0) { CGFloat($0.count) }, "nothing left to trim")
    }

    /// Every shipped family loads: its TrueType font resolves, every strike parses, and its
    /// licence evidence is beside it.
    func testEveryShippedOriginalFontLoads() throws {
        let root = try XCTUnwrap(BundleHelper.url(forResource: "AudionFaces", withExtension: nil, subdirectory: "Fonts"))
        let families = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertEqual(families.count, 29)
        for folder in families {
            let family = folder.lastPathComponent
            let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            XCTAssertTrue(files.contains("NOTICE.txt"), family)
            for file in files {
                if file.hasSuffix(".ttf") {
                    XCTAssertNotNil(AudionFaceOriginalFonts.font(named: family, size: 12), family)
                } else if file.hasSuffix(".nfnt"), let size = Int(file.split(separator: "-")[0]) {
                    XCTAssertNotNil(AudionFaceOriginalFonts.bitmap(named: family, size: size), "\(family) \(size)")
                }
            }
        }
    }

    func testAnOriginalStrikeDrawsWithQuickDrawsBoldAndStandIns() throws {
        let orchis = try XCTUnwrap(AudionFaceOriginalFonts.bitmap(named: "Orchis 6", size: 9))
        let black = AudionFace.color(red: 0, green: 0, blue: 0)
        func width(_ font: AudionFaceBitmapFont, _ text: String, _ style: AudionFace.TextStyle = []) throws -> Int {
            try XCTUnwrap(font.image(text, color: black, style: style, boxWidth: 1000, truncate: false, scale: 1)).width
        }
        XCTAssertEqual(try width(orchis, "AB", [.bold]), try width(orchis, "AB") + 2, "bold: a pixel onto each advance")
        XCTAssertEqual(try width(orchis, "AB", [.condense]), try width(orchis, "AB") - 2)
        // Mini Tight stops at ASCII: its em dash is the hyphen, not the missing-character box.
        let mini = try XCTUnwrap(AudionFaceOriginalFonts.bitmap(named: "Mini Tight", size: 7))
        XCTAssertEqual(try width(mini, "a—b"), try width(mini, "a-b"))
        XCTAssertNil(mini.image("a😀b", color: black, style: [], boxWidth: 1000, truncate: false, scale: 1),
                     "outside Mac Roman: the outline path draws it")
    }
}
