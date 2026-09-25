import CoreText
import XCTest
@testable import NullPlayer

/// **A `<TEXT>`'s `fontSize` is in points at WMP's 96 dpi, not in skin pixels.**
///
/// GDI draws 7 pt as 9.33 px, and a skin is laid out in pixels, so a size used as a pixel count drew
/// every readout in the corpus at three quarters of its authored size. Measured 2026-09-25 against the
/// Internet Archive's WMP reference captures: `xXx_night_vision_redx`'s Tahoma 7 metadata has 7 px
/// caps there and 5.5 px here before the fix (7.5 after); `WoW`'s Arial 11 `00:00` has 11 px digits
/// there and ~8 here before.
final class WMPTextPointSizeTests: XCTestCase {
    func testAFontSizeIsPointsAtNinetySixDpi() {
        XCTAssertEqual(WMPTextMetrics.pixelSize(7), 28.0 / 3, accuracy: 0.001)
        XCTAssertEqual(CTFontGetSize(WMPTextMetrics.font("Tahoma", size: 7, bold: false,
                                                         italic: false)),
                       28.0 / 3, accuracy: 0.001,
                       "the drawn face is the converted size, not the authored number")
    }

    /// The width a skin compares against its box (`metadata.textWidth > metadata.width`) is measured
    /// in the same face that is drawn, so it grows with it.
    func testMeasuredWidthScalesWithTheConversion() {
        let seven = WMPTextMetrics.width(of: "PLAYING", fontName: "Arial", fontSize: 7,
                                         bold: false, italic: false)
        let font = CTFontCreateWithName("Arial" as CFString, 7, nil)
        let line = WMPTextMetrics.line("PLAYING", font: font, color: CGColor(gray: 0, alpha: 1),
                                       underline: false)
        let atSevenPixels = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        XCTAssertEqual(seven, atSevenPixels * 96 / 72, accuracy: 0.01)
    }

    /// A glyph-sized box is never shorter than the converted size.
    func testLineHeightFloorIsTheConvertedSize() {
        XCTAssertGreaterThanOrEqual(
            WMPTextMetrics.lineHeight(fontName: "Arial", fontSize: 7, bold: false, italic: false),
            28.0 / 3)
    }
}
