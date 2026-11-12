import XCTest
@testable import NullPlayerCore

/// TEXT.BMP's third row is `Å Ö Ä ? *`, so `?` and `*` are columns 3 and 4, not the `Å`/`Ö` cells (#755).
final class CoreClassicTextFontTests: XCTestCase {
    func testQuestionMarkAndAsteriskUseTheirOwnCells() {
        let font = SkinElements.TextFont.self
        XCTAssertEqual(font.character("?"), NSRect(x: 15, y: 12, width: 5, height: 6))
        XCTAssertEqual(font.character("*"), NSRect(x: 20, y: 12, width: 5, height: 6))
    }
}
