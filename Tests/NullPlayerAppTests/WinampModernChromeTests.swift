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

    /// W177: a borrowed `.wmz` ring is the frame *around* a hosted surface, never wallpaper behind
    /// it. The seven spectrum-family windows draw their content first and this chrome over it, and
    /// several rings in the corpus are solid rather than keyed — `Half-Life_2` builds its panels out
    /// of opaque `f_*.png` strips — so an uncut ring painted a still picture over a running Cava.
    func testABorrowedRingIsNotPaintedOverTheSurfaceItFrames() throws {
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

        // An opaque ring: the worst case, and the one the corpus actually ships.
        let ringColor = NSColor(deviceRed: 1.0, green: 0.45, blue: 0.0, alpha: 1)
        let ring = try XCTUnwrap(CGContext(
            data: nil,
            width: 80,
            height: 50,
            bitsPerComponent: 8,
            bytesPerRow: 320,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ring.setFillColor(ringColor.cgColor)
        ring.fill(CGRect(x: 0, y: 0, width: 80, height: 50))
        let artwork = SkinnedSurfaceFrameArtwork(
            image: try XCTUnwrap(ring.makeImage()),
            size: CGSize(width: 80, height: 50),
            contentRect: CGRect(x: 12, y: 20, width: 56, height: 23),
            wasScaledToFit: false
        )

        WinampModernChrome(style: style, artwork: artwork).drawSpectrumFamilyWindow(
            in: bitmap,
            bounds: CGRect(x: 0, y: 0, width: 80, height: 50),
            metrics: .spectrumFamily,
            isActive: false,
            isClosePressed: false,
            controlScale: 1,
            title: "",
            fillBackground: false
        )

        // Inside the client hole the surface's own content survives untouched...
        assert(pixel(in: bitmap, x: 40, y: 31), matches: sentinel)
        assert(pixel(in: bitmap, x: 13, y: 21), matches: sentinel)
        assert(pixel(in: bitmap, x: 67, y: 42), matches: sentinel)
        // ...and everywhere else the ring is drawn exactly as before: sides, caption band, bottom.
        assert(pixel(in: bitmap, x: 2, y: 31), matches: ringColor)
        assert(pixel(in: bitmap, x: 78, y: 31), matches: ringColor)
        assert(pixel(in: bitmap, x: 40, y: 3), matches: ringColor)
        assert(pixel(in: bitmap, x: 40, y: 47), matches: ringColor)
    }

    /// W178: the caption's lettering is guarded against the ring it lands on, not against the
    /// palette's own ground. `Half-Life_2`'s caption is a bright orange strip; a label checked for
    /// contrast against a dark palette and then drawn over that strip clears the threshold on paper
    /// and is unreadable on screen.
    func testBorrowedCaptionLetteringFollowsTheRingUnderIt() throws {
        func title(overCaption caption: NSColor) throws -> NSColor {
            let bitmap = try XCTUnwrap(CGContext(
                data: nil, width: 80, height: 50, bitsPerComponent: 8, bytesPerRow: 320,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let ring = try XCTUnwrap(CGContext(
                data: nil, width: 80, height: 50, bitsPerComponent: 8, bytesPerRow: 320,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            ring.setFillColor(NSColor.gray.cgColor)
            ring.fill(CGRect(x: 0, y: 0, width: 80, height: 50))
            // The caption band is the image's *top* 20 rows, which is the bitmap's last 20 rows.
            ring.setFillColor(caption.cgColor)
            ring.fill(CGRect(x: 0, y: 30, width: 80, height: 20))
            let artwork = SkinnedSurfaceFrameArtwork(
                image: try XCTUnwrap(ring.makeImage()),
                size: CGSize(width: 80, height: 50),
                contentRect: CGRect(x: 12, y: 20, width: 56, height: 23),
                wasScaledToFit: false
            )

            // `SkinnedSurfaceStyle.drawText` lays its glyphs through `NSString.draw`, which paints
            // into the *current* `NSGraphicsContext` and not into the `CGContext` it is handed — so
            // without this the chrome draws and the lettering silently does not.
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
            defer { NSGraphicsContext.current = previous }

            SkinnedSurfaceChrome(style: .fallback, artwork: artwork).drawSpectrumFamilyWindow(
                in: bitmap, bounds: CGRect(x: 0, y: 0, width: 80, height: 50),
                metrics: .spectrumFamily, isActive: true, isClosePressed: false,
                controlScale: 1, title: "III", fillBackground: false
            )
            // The glyph colour is whatever in the label band is furthest from the ring behind it.
            var found = caption
            var distance: CGFloat = 0
            for y in 4..<16 {
                for x in 20..<60 {
                    let sample = pixel(in: bitmap, x: x, y: y)
                    let delta = abs(SkinnedSurfaceStyle.relativeLuminance(sample)
                                    - SkinnedSurfaceStyle.relativeLuminance(caption))
                    if delta > distance { distance = delta; found = sample }
                }
            }
            return found
        }

        let overWhite = try title(overCaption: .white)
        let overBlack = try title(overCaption: .black)
        XCTAssertLessThan(SkinnedSurfaceStyle.relativeLuminance(overWhite), 0.4,
                          "a title over a bright ring must be drawn dark")
        XCTAssertGreaterThan(SkinnedSurfaceStyle.relativeLuminance(overBlack), 0.2,
                             "a title over a dark ring must be drawn light")
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
