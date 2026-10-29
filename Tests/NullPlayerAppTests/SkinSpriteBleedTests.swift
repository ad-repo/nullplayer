import AppKit
import XCTest
@testable import NullPlayer

/// #612: at a fractional window scale a classic sprite must not pick up the neighbouring row of its sheet.
final class SkinSpriteBleedTests: XCTestCase {
    func testSpriteAtFractionalScaleDrawsNoNeighbouringRow() throws {
        // A 4×3 sheet: rows 0 and 2 are magenta dividers, row 1 is the green sprite.
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<4 {
            for y in 0..<3 {
                rep.setColor(y == 1 ? NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)
                                 : NSColor(deviceRed: 1, green: 0, blue: 1, alpha: 1), atX: x, y: y)
            }
        }
        let sheet = NSImage(size: NSSize(width: 4, height: 3))
        sheet.addRepresentation(rep)

        // A skin-coordinate (top-down) context at 3.75 device pixels per skin pixel, like 300% at 1x.
        let size = 40
        let context = try XCTUnwrap(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 3.75, y: -3.75)

        let renderer = SkinRenderer(skin: SkinLoader.shared.loadDefault())
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        renderer.drawSprite(from: sheet, sourceRect: NSRect(x: 0, y: 1, width: 4, height: 1),
                            to: NSRect(x: 1.3, y: 2.3, width: 4, height: 1), in: context)
        NSGraphicsContext.restoreGraphicsState()

        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var green = 0
        for i in 0..<(size * size) {
            let (r, g, b) = (pixels[i * 4], pixels[i * 4 + 1], pixels[i * 4 + 2])
            XCTAssertFalse(r > 40 && b > 40, "neighbouring divider row drawn at pixel \(i)")
            if g > 200 { green += 1 }
        }
        XCTAssertGreaterThan(green, 0, "the sprite itself was not drawn")
    }
}
