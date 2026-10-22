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

    /// A missing Segoe UI stands in at the em GDI would draw Segoe UI at — its 1.33 em cell against
    /// Arial's 1.117 — under its family name or its Windows filename. Anything else keeps its size.
    func testAMissingSegoeUIStandsInAtItsOwnSize() {
        for name in ["Segoe UI", "segoeui.ttf"] {
            XCTAssertEqual(WasabiTextMetrics.substituteScale(forMissing: name), 0.84, accuracy: 0.01, name)
        }
        XCTAssertEqual(WasabiTextMetrics.substituteScale(forMissing: "UNVR67X.ttf"), 1)
    }

    /// A face whose win and hhea cells agree keeps its own line — Arial's and Impact's do, and TOX
    /// Milla's timer was calibrated on Impact's. Helvetica is drawn as Arial on Windows, so it keeps
    /// its own too. (The face that does not agree, CPro Winamp for Mac's Helvetica Neue, is a skin
    /// asset and is pinned by the corpus render sweep.)
    func testAFaceWhoseCellsAgreeKeepsItsOwnLine() throws {
        for name in ["ArialMT", "Impact", "Helvetica"] {
            let font = try XCTUnwrap(NSFont(name: name, size: 35.2))
            let line = WasabiTextMetrics.gdiLine(of: font)
            XCTAssertEqual(line.cell, font.ascender - font.descender, accuracy: 0.5, name)
            XCTAssertEqual(line.baselineDrop, 0, accuracy: 0.5, name)
        }
    }
}
