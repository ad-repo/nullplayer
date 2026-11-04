import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// Pictures without a corpus: frames cut from side-by-side and stacked strips, pixels decoded on
/// first draw within the skin's budget and let go least recently drawn first, and AIMP 3.0's BMPs.
final class AIMPSkinImageTests: XCTestCase {
    func testFramesOfASideBySideStripAreItsColumns() throws {
        // Three 2×1 frames side by side: each pixel's blue byte is its x.
        let image = Self.ase(width: 6, height: 1, frames: 3, stacked: false, budget: AIMPSkinPixelBudget()) { x, _ in UInt8(x) }
        XCTAssertEqual(image.frameSize, CGSize(width: 2, height: 1))
        XCTAssertEqual(Self.blue(image.frame(1)), [2, 3])
        XCTAssertEqual(Self.blue(image.frame(9)), [4, 5], "clamped to the last")
    }

    func testFramesOfAStackedStripAreItsRows() throws {
        let image = Self.ase(width: 1, height: 4, frames: 2, stacked: true, budget: AIMPSkinPixelBudget()) { _, y in UInt8(y) }
        XCTAssertEqual(Self.blue(image.frame(0)), [0, 1])
        XCTAssertEqual(Self.blue(image.frame(1)), [2, 3])
    }

    func testPicturesDecodeWhenDrawnAndTheLeastRecentlyDrawnGo() throws {
        let budget = AIMPSkinPixelBudget(limit: 20)
        var decodes = 0
        let pictures = (0..<3).map { _ in
            Self.ase(width: 10, height: 1, frames: 1, stacked: false, budget: budget) { _, _ in 1 } onDecode: { decodes += 1 }
        }
        XCTAssertEqual(budget.residentPixels, 0, "nothing decodes as the skin loads")
        XCTAssertNotNil(pictures[0].frame(0))
        XCTAssertNotNil(pictures[1].frame(0))
        XCTAssertEqual(budget.residentPixels, 20)
        XCTAssertNotNil(pictures[0].frame(0), "drawn again: resident, no decode")
        XCTAssertEqual(decodes, 2)
        XCTAssertNotNil(pictures[2].frame(0))
        XCTAssertEqual(budget.residentPixels, 20, "the third pushed out the least recently drawn")
        XCTAssertNotNil(pictures[0].frame(0))
        XCTAssertEqual(decodes, 3, "the first stayed")
        XCTAssertNotNil(pictures[1].frame(0))
        XCTAssertEqual(decodes, 4, "the second decodes again")
    }

    func testCoversBlurOncePerCoverAndLevel() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let cover = try XCTUnwrap(context.makeImage()), other = try XCTUnwrap(context.makeImage())
        let covers = AIMPSkinBlurredCovers()
        var made = 0
        func blur() -> CGImage? { made += 1; return cover }
        _ = covers.image(cover, level: 40, blur: blur)
        _ = covers.image(cover, level: 40, blur: blur)
        XCTAssertEqual(made, 1, "the same cover at the same level is made once")
        _ = covers.image(cover, level: 60, blur: blur)
        _ = covers.image(other, level: 40, blur: blur)
        XCTAssertEqual(made, 3, "another level or another cover is made anew")
    }

    func testFirstFrameBlankAndLastFrameFlatAreReadOnceWhenFirstAsked() {
        // Frame 0 transparent, frame 1 one opaque colour over 18 pixels.
        let budget = AIMPSkinPixelBudget()
        var decodes = 0
        let image = Self.ase(width: 3, height: 12, frames: 2, stacked: true, budget: budget) { _, y in y < 6 ? 0 : 200 } onDecode: { decodes += 1 }
        XCTAssertEqual(decodes, 0, "nothing decodes until the flags are first asked")
        XCTAssertTrue(image.firstFrameBlank)
        XCTAssertTrue(image.lastFrameFlat)
        XCTAssertNotNil(image.frame(1))
        XCTAssertEqual(decodes, 1, "the first ask decodes the picture into its budget; asking or drawing after does not again")
    }

    func testBitmapsDecodeToPremultipliedTopDown() throws {
        // 2×2, 32 bits bottom-up: bottom row straight-alpha half-white, top row opaque red.
        let rows: [[UInt8]] = [[255, 255, 255, 128, 255, 255, 255, 128], [0, 0, 255, 255, 0, 0, 255, 255]]
        let pixels = try AIMPSkinBitmap.pixels(Data(Self.bitmap(width: 2, height: 2, bits: 32, rows: rows)), name: "a.bmp")
        XCTAssertEqual(Array(pixels.prefix(4)), [0, 0, 255, 255], "the top row first")
        XCTAssertEqual(Array(pixels.suffix(4)), [128, 128, 128, 128], "premultiplied")

        // All alpha bytes 0: no alpha, opaque.
        let flat = try AIMPSkinBitmap.pixels(Data(Self.bitmap(width: 1, height: 1, bits: 32, rows: [[10, 20, 30, 0]])), name: "b.bmp")
        XCTAssertEqual(Array(flat), [10, 20, 30, 255])

        // 24 bits, rows padded to four bytes.
        let rgb = try AIMPSkinBitmap.pixels(Data(Self.bitmap(width: 1, height: 1, bits: 24, rows: [[1, 2, 3, 0]])), name: "c.bmp")
        XCTAssertEqual(Array(rgb), [1, 2, 3, 255])
    }

    func testBitmapPictureTakesItsLayoutFromMainIni() throws {
        let rows = (0..<2).map { _ in [UInt8](repeating: 9, count: 8 * 4) }
        let data = Data(Self.bitmap(width: 8, height: 2, bits: 32, rows: rows))
        let layout = AIMPSkinImage.Layout(frames: 4)
        let image = try AIMPSkinImage(bitmap: data, name: "AddBtn.bmp", layout: layout, budget: AIMPSkinPixelBudget()) { data }
        XCTAssertEqual(image.frameSize, CGSize(width: 2, height: 2))
        XCTAssertEqual(image.frame(3)?.width, 2)
    }

    // MARK: - Building pictures

    /// An `ASEIMG32` whose blue byte at (x, y) is `blue(x, y)`, opaque where it is not 0.
    private static func ase(width: Int, height: Int, frames: Int, stacked: Bool, budget: AIMPSkinPixelBudget,
                            blue: (Int, Int) -> UInt8, onDecode: @escaping () -> Void = {}) -> AIMPSkinImage {
        var header = [UInt8](repeating: 0, count: 70)
        header.replaceSubrange(0..<8, with: Array("ASEIMG32".utf8))
        func put(_ value: Int, at: Int) { for i in 0..<4 { header[at + i] = UInt8((value >> (8 * i)) & 0xFF) } }
        put(frames, at: 18)
        header[27] = stacked ? 1 : 0
        put(width, at: 62)
        put(height, at: 66)
        var pixels: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let b = blue(x, y)
                pixels += [b, 0, 0, b == 0 ? 0 : 255]
            }
        }
        let data = Data(header + pixels)
        return try! AIMPSkinImage(data, name: "test.myimg", budget: budget) {
            onDecode()
            return data
        }
    }

    private static func blue(_ image: CGImage?) -> [UInt8] {
        guard let image, let data = image.dataProvider?.data as Data? else { return [] }
        return stride(from: 0, to: image.width * image.height * 4, by: 4).map { data[$0] }
    }

    /// A Windows bitmap, rows bottom-up as given (each already padded).
    private static func bitmap(width: Int, height: Int, bits: Int, rows: [[UInt8]]) -> [UInt8] {
        func u32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        let pixels = rows.flatMap { $0 }
        return Array("BM".utf8) + u32(54 + pixels.count) + u32(0) + u32(54)
            + u32(40) + u32(width) + u32(height) + [1, 0, UInt8(bits), 0] + u32(0) + u32(pixels.count)
            + u32(0) + u32(0) + u32(0) + u32(0) + pixels
    }
}
