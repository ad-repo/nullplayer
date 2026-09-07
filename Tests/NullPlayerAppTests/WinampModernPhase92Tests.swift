import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 92 — the built-in spectrum analyzer, on the ClassicPro family.
///
/// Two independent defects, reported together as "the analyzer is striped, and on some colour themes
/// it is missing":
///
/// 1. **A `Map` sampled the composited pixel, not the stored one.** `WasabiBitmap.pixel(at:)` drew
///    into a `premultipliedLast` context, so a pixel with `alpha = 0` read back as pure black however
///    much colour it carried. ClassicPro's engine-two ramp bitmap keeps eight of its sixteen band
///    colours in rows whose alpha is 0, so `getARGBValue` answered `0,0,0` for every other band.
/// 2. **The sixteen `colorband` colours were mapped across the row instead of up the box.** They are
///    classic `viscolor.txt` entries 2–17: a bottom-to-top gradient over the analyzer, shared by every
///    bar. Read as one colour per bar, ClassicPro's deliberately alternating bright/dim ramp dimmed
///    every other *bar* — which is the striping — and on a theme whose dim value sat near the
///    background those bars disappeared.
final class WinampModernPhase92Tests: XCTestCase {

    // MARK: - A map keeps the colour stored under a transparent pixel

    /// The pixel a skin wrote, not the one you would see composited.
    func testColourUnderAFullyTransparentPixelSurvivesSampling() throws {
        let bitmap = try makeBitmap(pixels: [[(156, 215, 238, 0), (184, 197, 227, 255)]])
        let clear = try XCTUnwrap(bitmap.pixel(at: CGPoint(x: 0, y: 0)))
        XCTAssertEqual([clear.red, clear.green, clear.blue], [156, 215, 238],
                       "alpha 0 must not zero the colour channels")
        XCTAssertEqual(clear.alpha, 0, "and the alpha is still reported honestly")
    }

    /// The opaque case is unchanged — this is the half that always worked, and the half that made the
    /// defect read as stripes rather than as a blank analyzer.
    func testAnOpaquePixelIsUnchanged() throws {
        let bitmap = try makeBitmap(pixels: [[(156, 215, 238, 0), (184, 197, 227, 255)]])
        let opaque = try XCTUnwrap(bitmap.pixel(at: CGPoint(x: 1, y: 0)))
        XCTAssertEqual([opaque.red, opaque.green, opaque.blue, opaque.alpha], [184, 197, 227, 255])
    }

    /// Out of bounds still answers `nil` rather than a stray neighbouring pixel — the direct sampler
    /// indexes raw bytes, so its bounds check is load-bearing in a way the drawing one's was not.
    func testSamplingOutsideTheBitmapAnswersNil() throws {
        let bitmap = try makeBitmap(pixels: [[(1, 2, 3, 255), (4, 5, 6, 255)]])
        XCTAssertNil(bitmap.pixel(at: CGPoint(x: 2, y: 0)))
        XCTAssertNil(bitmap.pixel(at: CGPoint(x: 0, y: 1)))
        XCTAssertNil(bitmap.pixel(at: CGPoint(x: -1, y: 0)))
    }

    // MARK: - The analyzer ramp is vertical

    /// Every bar shares one bottom-to-top gradient, so two bars of the same height are the same
    /// colour wherever they sit in the row. This is the assertion that fails under the old reading.
    func testTheRampRunsUpTheBoxAndNotAcrossTheRow() {
        let style = rampStyle()
        XCTAssertEqual(red(style.rampColor(atHeightFraction: 0)), 1)
        XCTAssertEqual(red(style.rampColor(atHeightFraction: 0.99)), 16)
        for fraction in [0.0, 0.25, 0.5, 0.99] {
            XCTAssertEqual(red(style.barColor(index: 0, count: 75, level: CGFloat(fraction))),
                           red(style.barColor(index: 74, count: 75, level: CGFloat(fraction))),
                           "the bar's position in the row does not colour it")
        }
    }

    /// **Why sixteen colours cannot be per-bar.** `bandwidth="thin"` draws far more than sixteen bars,
    /// so the old mapping painted sixteen wide blocks across the row rather than a gradient.
    func testTheRampIsIndependentOfHowManyBarsTheSkinAsksFor() {
        let style = rampStyle()
        for count in [16, 20, 75] {
            XCTAssertEqual(red(style.barColor(index: 0, count: count, level: 0.99)), 16,
                           "a full-height bar tops the ramp whatever the band count")
        }
    }

    /// ClassicPro's own ramp shape: alternating bright and dim rows. Up the box that is the LED
    /// scanline inside each bar; across the row it dimmed every other bar, which is the report.
    func testAnAlternatingRampStaysWithinOneBar() {
        var attributes: [String: String] = [:]
        for band in 1...16 { attributes["colorband\(band)"] = band.isMultiple(of: 2) ? "20,20,20" : "240,240,240" }
        let style = self.style(attributes)
        // Adjacent *heights* alternate…
        XCTAssertNotEqual(red(style.rampColor(atHeightFraction: 0.03)),
                          red(style.rampColor(atHeightFraction: 0.10)))
        // …while adjacent *bars* at one height do not.
        XCTAssertEqual(red(style.barColor(index: 3, count: 16, level: 0.5)),
                       red(style.barColor(index: 4, count: 16, level: 0.5)))
    }

    // MARK: - Helpers

    private func rampStyle() -> WasabiVisStyle {
        var attributes: [String: String] = [:]
        for band in 1...16 { attributes["colorband\(band)"] = "\(band),0,0" }
        return style(attributes)
    }

    private func style(_ attributes: [String: String]) -> WasabiVisStyle {
        WasabiVisStyle.decode(attributes: attributes) { raw in
            let parts = raw.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 3 else { return WasabiVisStyle.white }
            return CGColor(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: 1)
        }
    }

    private func red(_ color: CGColor) -> Int {
        Int(((color.components?.first ?? 0) * 255).rounded())
    }

    /// A real decoded PNG, so the sampler is exercised through the same ImageIO path a skin takes
    /// rather than through a hand-built buffer that could not reproduce the format question.
    private func makeBitmap(pixels: [[(UInt8, UInt8, UInt8, UInt8)]]) throws -> WasabiBitmap {
        let height = pixels.count
        let width = pixels[0].count
        var raw = [UInt8]()
        for row in pixels { for pixel in row { raw += [pixel.0, pixel.1, pixel.2, pixel.3] } }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(raw) as CFData))
        let source = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
                                           bitsPerPixel: 32, bytesPerRow: width * 4,
                                           space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                           provider: provider, decode: nil, shouldInterpolate: false,
                                           intent: .defaultIntent))
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, source, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let decodeSource = try XCTUnwrap(CGImageSourceCreateWithData(encoded as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decodeSource, 0, nil))
        return WasabiBitmap(image: decoded, width: decoded.width, height: decoded.height, cost: 0)
    }
}
