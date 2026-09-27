import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// **W201 — `pharaoh`'s scarab-mode back button drew as a black box, reported 2026-09-16.**
///
/// `pyrevolver.gif` declares a 140x128 logical screen, and all 16 of its frames are 21x16 blocks at
/// 0,0 with a local colour table and no transparent index. With no global colour table the rest of
/// the screen has no defined colour, and ImageIO decodes it as opaque black. The skin's `<BUTTON>` is
/// 21x16, so the whole canvas was stretched into it: a black box with the artwork squeezed into one
/// corner.
///
/// The discrimination is what these tests are for. 27 corpus GIFs have frames smaller than their
/// canvas, and 26 of them mean it: `Official_Xbox_MP71` places a 16x10 frame at 4,4 inside a 23x18
/// button, and `Age_of_Mythology`'s `open_shutter.gif` is a 193x172 frame on a 198x173 canvas. All 26
/// carry a global colour table, and ImageIO decodes their uncovered area as transparent. Only the
/// GIF with **no global colour table** is trimmed. The corpus numbers are a scan of the installed
/// archives on 2026-09-24, not a committed script; the on-screen half was verified by driving the
/// app (`reference/skins/pharaoh.md`).
final class WMPGIFCanvasTests: XCTestCase {

    /// A GIF stream assembled block by block, with each frame's origin and size stated directly.
    /// Every frame is one hand-written LZW literal for a single pixel of index 0, so a frame that
    /// ImageIO has to decode must be 1x1; `WMPGIFCanvas` never reads the payload.
    private struct GIFBuilder {
        var canvas: (width: Int, height: Int) = (140, 128)
        var globalColorTable = false
        private var frames: [(x: Int, y: Int, width: Int, height: Int)] = []

        mutating func frame(x: Int = 0, y: Int = 0, _ width: Int, _ height: Int) {
            frames.append((x, y, width, height))
        }

        func build() -> Data {
            func le16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)] }
            // Index 0 is red and index 1 blue, in whichever table the frame reads.
            let table: [UInt8] = [255, 0, 0, 0, 0, 255]
            var bytes: [UInt8] = Array("GIF89a".utf8)
            bytes += le16(canvas.width)
            bytes += le16(canvas.height)
            bytes += [globalColorTable ? 0x80 : 0x00, 0x00, 0x00]
            if globalColorTable { bytes += table }
            for frame in frames {
                bytes += [0x21, 0xF9, 0x04, 0x04, 0x0A, 0x00, 0x00, 0x00]
                bytes += [0x2C]
                bytes += le16(frame.x)
                bytes += le16(frame.y)
                bytes += le16(frame.width)
                bytes += le16(frame.height)
                if globalColorTable {
                    bytes += [0x00]
                } else {
                    bytes += [0x80]
                    bytes += table
                }
                bytes += [0x02, 0x02, 0x44, 0x01, 0x00]
            }
            bytes += [0x3B]
            return Data(bytes)
        }
    }

    // MARK: - The block walker

    /// The `pyrevolver.gif` shape: every frame a small block at the origin of a large canvas, and no
    /// global colour table.
    func testFramesInsideASmallerRectangleAtTheOriginAreThatRectangle() throws {
        var gif = GIFBuilder()
        for _ in 0..<16 { gif.frame(21, 16) }
        let extent = try XCTUnwrap(WMPGIFCanvas.paintedExtent(gif.build()))
        XCTAssertEqual(extent.width, 21)
        XCTAssertEqual(extent.height, 16)
    }

    /// **The 26-file guard.** With a global colour table the canvas is defined, and a frame placed
    /// inside a larger canvas is layout the skin depends on: `Official_Xbox_MP71`'s 16x10 frame at
    /// 4,4 of 23x18, and `Age_of_Mythology`'s `open_shutter.gif`.
    func testAGlobalColourTableKeepsTheCanvas() {
        var gif = GIFBuilder()
        gif.globalColorTable = true
        gif.canvas = (23, 18)
        gif.frame(x: 4, y: 4, 16, 10)
        XCTAssertNil(WMPGIFCanvas.paintedExtent(gif.build()))
    }

    /// The rectangle covers every frame, not just the first, and runs from the origin to the far
    /// edge of whichever frame reaches furthest.
    func testTheRectangleCoversEveryFrame() throws {
        var gif = GIFBuilder()
        gif.canvas = (40, 40)
        gif.frame(10, 5)
        gif.frame(x: 2, y: 3, 5, 10)
        let extent = try XCTUnwrap(WMPGIFCanvas.paintedExtent(gif.build()))
        XCTAssertEqual(extent.width, 10)
        XCTAssertEqual(extent.height, 13)
    }

    /// A frame that reaches the canvas edge leaves nothing to trim, which is almost every GIF in the
    /// corpus with or without a global colour table.
    func testFramesThatFillTheCanvasKeepIt() {
        var gif = GIFBuilder()
        gif.canvas = (32, 32)
        gif.frame(32, 32)
        XCTAssertNil(WMPGIFCanvas.paintedExtent(gif.build()))
    }

    /// **A stream this cannot read keeps its canvas**, which is the engine's behaviour before this
    /// rule existed. A frame declaring itself past the canvas edge is malformed too.
    func testAnythingUnreadableKeepsTheCanvas() {
        var gif = GIFBuilder()
        gif.frame(21, 16)
        let complete = gif.build()
        XCTAssertNil(WMPGIFCanvas.paintedExtent(Data()))
        XCTAssertNil(WMPGIFCanvas.paintedExtent(Data("not a gif at all".utf8)))
        XCTAssertNil(WMPGIFCanvas.paintedExtent(complete.prefix(13)))
        XCTAssertNil(WMPGIFCanvas.paintedExtent(complete.prefix(25)), "cut inside the image descriptor")

        var oversized = GIFBuilder()
        oversized.canvas = (10, 10)
        oversized.frame(x: 5, y: 0, 8, 4)
        XCTAssertNil(WMPGIFCanvas.paintedExtent(oversized.build()))
    }

    /// **A sliced `Data` keeps the original buffer's indices.** The same stream must answer the same
    /// way however it was carved.
    func testASlicedStreamReadsTheSameAsAStandaloneOne() throws {
        var gif = GIFBuilder()
        gif.frame(21, 16)
        var padded = Data(repeating: 0xAB, count: 37)
        padded.append(gif.build())
        let slice = padded[padded.startIndex.advanced(by: 37)...]
        XCTAssertNotEqual(slice.startIndex, 0, "the fixture has to be a genuine offset slice")
        let extent = try XCTUnwrap(WMPGIFCanvas.paintedExtent(slice))
        XCTAssertEqual(extent.width, 21)
        XCTAssertEqual(extent.height, 16)
    }

    // MARK: - What the image store does with it

    /// The top-left pixel, straight RGBA.
    private func pixel(_ image: CGImage) -> (red: UInt8, alpha: UInt8)? {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (bytes[0], bytes[3])
    }

    private func store(_ gif: Data) -> WMPImageStore {
        WMPImageStore(provider: WMPMemoryResourceProvider(["a.gif": gif]))
    }

    /// The reported defect: the decoded image is the frame, so drawing it into the skin's declared
    /// frame draws the artwork and no black. Every frame is trimmed, not only the first.
    func testTheStoreDecodesOnlyThePaintedRectangle() throws {
        var gif = GIFBuilder()
        gif.canvas = (3, 2)
        gif.frame(1, 1)
        gif.frame(1, 1)
        let images = store(gif.build())
        for frame in 0..<2 {
            let decoded = try images.image(for: "a.gif", frame: frame)
            XCTAssertEqual(decoded.image.width, 1, "frame \(frame)")
            XCTAssertEqual(decoded.image.height, 1, "frame \(frame)")
            XCTAssertEqual(decoded.size, WMPSize(width: 1, height: 1), "frame \(frame)")
            XCTAssertEqual(decoded.decodedBytes, 4, "frame \(frame)")
            let pixel = try XCTUnwrap(pixel(decoded.image))
            XCTAssertEqual(pixel.red, 255, "frame \(frame) is the frame's own red")
            XCTAssertEqual(pixel.alpha, 255, "frame \(frame)")
        }
    }

    /// The same shape with a global colour table keeps its canvas size, so a GIF whose offset
    /// placement is the skin's layout does not move.
    func testTheStoreKeepsTheCanvasWhenTheGIFHasAGlobalColourTable() throws {
        var gif = GIFBuilder()
        gif.globalColorTable = true
        gif.canvas = (3, 2)
        gif.frame(1, 1)
        gif.frame(1, 1)
        let decoded = try store(gif.build()).image(for: "a.gif")
        XCTAssertEqual(decoded.image.width, 3)
        XCTAssertEqual(decoded.image.height, 2)
        XCTAssertEqual(decoded.size, WMPSize(width: 3, height: 2))
    }
}
