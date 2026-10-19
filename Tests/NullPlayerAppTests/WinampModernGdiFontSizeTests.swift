import AppKit
import XCTest
@testable import NullPlayer

/// GDI fits a face's whole cell into `fontsize`, so a face with a taller cell than Arial's draws a
/// smaller em. TOX Milla's `fontsize="24"` Impact timer draws 14px digits in its own screenshot.
final class WinampModernGdiFontSizeTests: XCTestCase {
    func testATallCellFaceDrawsASmallerEm() throws {
        let impact = try XCTUnwrap(NSFont(name: "Impact", size: 19.2))
        XCTAssertEqual(WasabiTextMetrics.gdiSized(impact).pointSize, 17.6, accuracy: 0.1)
    }

    func testArialAndHelveticaKeepTheirSize() throws {
        for name in ["ArialMT", "Helvetica"] {
            let font = try XCTUnwrap(NSFont(name: name, size: 19.2))
            XCTAssertEqual(WasabiTextMetrics.gdiSized(font).pointSize, 19.2, accuracy: 0.01, name)
        }
    }
}
