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

    /// B335: the OS/2 win fields are unsigned, and Xenon's `square.TTF` stored -136 in `usWinDescent`,
    /// a 64 em cell that pushed its clock 376px out of its box. A face like that has no usable win
    /// cell and falls back to its own line. The fixture is Arial's bytes with that one field patched.
    func testANegativeWinDescentIsNotACell() throws {
        let url = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Arial.ttf")
        var data = try XCTUnwrap(try? Data(contentsOf: url))
        let tables = Int(data[4]) << 8 | Int(data[5])
        var patched = false
        for index in 0..<tables {
            let entry = 12 + index * 16
            guard String(decoding: data[entry..<entry + 4], as: UTF8.self) == "OS/2" else { continue }
            let offset = data[entry + 8..<entry + 12].reduce(0) { $0 << 8 | Int($1) }
            data[offset + 76] = 0xFF
            data[offset + 77] = 0x78
            patched = true
        }
        XCTAssertTrue(patched)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let cgFont = try XCTUnwrap(CGFont(provider))
        let font = try XCTUnwrap(CTFontCreateWithGraphicsFont(cgFont, 16, nil, nil) as NSFont?)
        XCTAssertNil(WasabiTextMetrics.winMetricsPerEm(of: font))
        XCTAssertEqual(WasabiTextMetrics.gdiLine(of: font).cell, font.ascender - font.descender, accuracy: 0.01)
    }
}
