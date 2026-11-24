import XCTest
@testable import NullPlayerCore

/// TEXT.BMP's third row is `Å Ö Ä ? *`, so `?` and `*` are columns 3 and 4, not the `Å`/`Ö` cells (#755).
final class CoreClassicTextFontTests: XCTestCase {
    func testQuestionMarkAndAsteriskUseTheirOwnCells() {
        let font = SkinElements.TextFont.self
        XCTAssertEqual(font.character("?"), NSRect(x: 15, y: 12, width: 5, height: 6))
        XCTAssertEqual(font.character("*"), NSRect(x: 20, y: 12, width: 5, height: 6))
    }

    func testRingAndUmlautLettersUseTheirThirdRowCells() {
        let font = SkinElements.TextFont.self
        for (letters, column) in [("Åå", 0), ("Öö", 1), ("Ää", 2)] {
            for letter in letters {
                XCTAssertEqual(font.character(letter), NSRect(x: column * 5, y: 12, width: 5, height: 6),
                               "\(letter)")
            }
        }
        XCTAssertEqual(font.character("A"), NSRect(x: 0, y: 0, width: 5, height: 6))
    }
}
