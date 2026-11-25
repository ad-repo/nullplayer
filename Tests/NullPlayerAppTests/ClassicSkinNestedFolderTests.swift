import AppKit
import XCTest
import ZIPFoundation
@testable import NullPlayer

/// MERYXMS1.wsz keeps its bitmaps two folders deep (`meryxmas/Merry Christmas Amp/main.bmp`).
/// The loader only looked one level down, so the skin fell back to the unskinned look.
final class ClassicSkinNestedFolderTests: XCTestCase {
    func testBitmapsTwoFoldersDeepAreFound() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("nested-wsz-\(UUID().uuidString)")
        let deep = root.appendingPathComponent("src/meryxmas/Merry Christmas Amp")
        try fm.createDirectory(at: deep, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 275, pixelsHigh: 116, bitsPerSample: 8,
                                   samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try rep.representation(using: .bmp, properties: [:])!.write(to: deep.appendingPathComponent("main.bmp"))
        try "readme".write(to: root.appendingPathComponent("src/meryxmas/readme.txt"), atomically: true, encoding: .utf8)

        let wsz = root.appendingPathComponent("nested.wsz")
        try fm.zipItem(at: root.appendingPathComponent("src/meryxmas"), to: wsz)

        XCTAssertNotNil(try SkinLoader.shared.load(from: wsz).main)
    }

    /// A stray BMP at the root does not hide the skin folder beneath it.
    func testMainBitmapBeatsAShallowerStrayBitmap() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("stray-wsz-\(UUID().uuidString)")
        let src = root.appendingPathComponent("src")
        try fm.createDirectory(at: src.appendingPathComponent("theme"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let main = try bitmap(width: 275, height: 116)
        try main.write(to: src.appendingPathComponent("theme/main.bmp"))
        try bitmap(width: 10, height: 10).write(to: src.appendingPathComponent("preview.bmp"))

        let wsz = root.appendingPathComponent("stray.wsz")
        try fm.zipItem(at: src, to: wsz, shouldKeepParent: false)

        XCTAssertEqual(try SkinLoader.shared.load(from: wsz).main?.size.width, 275)
    }

    private func bitmap(width: Int, height: Int) throws -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return try XCTUnwrap(rep.representation(using: .bmp, properties: [:]))
    }
}
