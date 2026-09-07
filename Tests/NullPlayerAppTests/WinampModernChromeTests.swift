import AppKit
import XCTest
@testable import NullPlayer

final class WinampModernChromeTests: XCTestCase {
    func testSpectrumFamilyChromeRasterSnapshotPreservesFrameMetrics() throws {
        let palette = WasabiPalette(
            listText: NSColor(deviceRed: 0.90, green: 0.80, blue: 0.20, alpha: 1),
            currentText: .white,
            selectionText: .white,
            selectionBackground: NSColor(deviceRed: 0.20, green: 0.45, blue: 0.90, alpha: 1),
            contentBackground: NSColor(deviceRed: 0.08, green: 0.12, blue: 0.18, alpha: 1),
            treeText: .white,
            treeSelection: .blue
        )
        let style = WinampModernSurfaceStyle(palette: palette)
        let bitmap = try XCTUnwrap(CGContext(
            data: nil,
            width: 100,
            height: 60,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let metrics = WinampModernChrome.Metrics(
            titleHeight: 20,
            leftBorder: 12,
            rightBorder: 12,
            bottomBorder: 7
        )

        WinampModernChrome(style: style).drawSpectrumFamilyWindow(
            in: bitmap,
            bounds: CGRect(x: 0, y: 0, width: 100, height: 60),
            metrics: metrics,
            isActive: true,
            isClosePressed: false,
            controlScale: 1,
            title: "",
            fillBackground: true
        )

        // A compact sampled-pixel snapshot. E=edge, B=palette-derived bar, C=content. The sample
        // crosses both title seams, both side borders, and the bottom strip, so changing any of the
        // inherited spectrum-family metrics produces a readable failure instead of a binary fixture.
        let xs = [0, 1, 11, 12, 50, 75, 87, 88, 99]
        let ys = [0, 1, 18, 19, 20, 25, 52, 53, 58, 59]
        let snapshot = ys.map { y in
            xs.map { x in
                role(of: pixel(in: bitmap, x: x, y: y), style: style)
            }.joined()
        }.joined(separator: "\n")

        XCTAssertEqual(snapshot, """
        EEEEEEEEE
        BBBBBBBBB
        BBBBBBBBB
        EEEEEEEEE
        EBBCCCCBE
        EBBCCCCBE
        EBBCCCCBE
        BBBBBBBBB
        BBBBBBBBB
        EEEEEEEEE
        """)
    }

    func testOverlayChromeDoesNotReplaceVisualizationContent() throws {
        let style = WinampModernSurfaceStyle.fallback
        let bitmap = try XCTUnwrap(CGContext(
            data: nil,
            width: 80,
            height: 50,
            bitsPerComponent: 8,
            bytesPerRow: 320,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let sentinel = NSColor(deviceRed: 0.95, green: 0.10, blue: 0.65, alpha: 1)
        bitmap.setFillColor(sentinel.cgColor)
        bitmap.fill(CGRect(x: 0, y: 0, width: 80, height: 50))

        WinampModernChrome(style: style).drawSpectrumFamilyWindow(
            in: bitmap,
            bounds: CGRect(x: 0, y: 0, width: 80, height: 50),
            metrics: .spectrumFamily,
            isActive: false,
            isClosePressed: true,
            controlScale: 1,
            title: "",
            fillBackground: false
        )

        assert(pixel(in: bitmap, x: 40, y: 30), matches: sentinel)
        assert(pixel(in: bitmap, x: 40, y: 5), matches: style.background)
        assert(pixel(in: bitmap, x: 70, y: 5), matches: style.pressedFill)
    }

    func testPeppyMeterRetainsItsLargerRegisteredGeometry() throws {
        let peppy = try XCTUnwrap(WinampModernHostedWindowRegistry.entry(id: .peppyMeter))
        let spectrum = try XCTUnwrap(WinampModernHostedWindowRegistry.entry(id: .spectrum))

        XCTAssertEqual(peppy.defaultSize, SkinElements.PeppyMeterWindow.windowSize)
        XCTAssertEqual(peppy.minimumSize, SkinElements.PeppyMeterWindow.minSize)
        XCTAssertGreaterThan(peppy.defaultSize.height, spectrum.defaultSize.height)
        XCTAssertEqual(peppy.stackPolicy.preferredHeightMultiplier, 1.75)
    }

    private func pixel(in context: CGContext, x: Int, y: Int) -> NSColor {
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        // Bitmap memory is top-row first while CGContext coordinates are bottom-left here.
        let index = (context.height - 1 - y) * context.bytesPerRow + x * 4
        return NSColor(deviceRed: CGFloat(data[index]) / 255,
                       green: CGFloat(data[index + 1]) / 255,
                       blue: CGFloat(data[index + 2]) / 255,
                       alpha: CGFloat(data[index + 3]) / 255)
    }

    private func role(of color: NSColor, style: WinampModernSurfaceStyle) -> String {
        if matches(color, style.border) { return "E" }
        if matches(color, style.barBackground) { return "B" }
        if matches(color, style.background) { return "C" }
        return "?"
    }

    private func assert(_ actual: NSColor, matches expected: NSColor,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(matches(actual, expected), "\(actual) does not match \(expected)",
                      file: file, line: line)
    }

    private func matches(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        guard let a = lhs.usingColorSpace(.deviceRGB), let b = rhs.usingColorSpace(.deviceRGB) else {
            return false
        }
        let tolerance: CGFloat = 1.5 / 255
        return abs(a.redComponent - b.redComponent) <= tolerance
            && abs(a.greenComponent - b.greenComponent) <= tolerance
            && abs(a.blueComponent - b.blueComponent) <= tolerance
            && abs(a.alphaComponent - b.alphaComponent) <= tolerance
    }
}
