import CoreGraphics
import XCTest
@testable import NullPlayer

/// The in-house BMP reader that stands in when ImageIO refuses a legacy WMP bitmap. Nine bitmaps in
/// five skins of the 180-archive corpus are rejected by ImageIO alone; eight of them carry
/// `biClrImportant` while `biClrUsed` is zero, which Windows treats as advisory.
final class WMPBitmapDecoderTests: XCTestCase {
    private let limits = WMPBitmapDecoder.Limits(maximumDimension: 4096, maximumPixels: 1_000_000,
                                                 maximumDecodedBytes: 4_000_000)

    func testDecodesPalettedBitmapBottomUpWithAdvisoryImportantColorCount() throws {
        // The corpus shape: 8bpp, no compression, `biClrUsed` zero and `biClrImportant` 250.
        let data = paletted8(width: 2, height: 2, clrUsed: 0, clrImportant: 250,
                             palette: [(255, 0, 0), (0, 255, 0), (0, 0, 255)],
                             // Rows are stored bottom-up: the authored top row is written last.
                             rows: [[2, 2], [0, 1]])
        let decoded = try WMPBitmapDecoder.decode(data, limits: limits)
        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)
        XCTAssertEqual(rgba(decoded.image, x: 0, yFromTop: 0), [255, 0, 0, 255])
        XCTAssertEqual(rgba(decoded.image, x: 1, yFromTop: 0), [0, 255, 0, 255])
        XCTAssertEqual(rgba(decoded.image, x: 0, yFromTop: 1), [0, 0, 255, 255])
    }

    func testDecodesRunLengthEncodedBitmapIncludingAbsoluteRunsAndDeltas() throws {
        // Row order is bottom-up, so the first stream row is the authored bottom row.
        let stream: [UInt8] = [
            3, 0,                     // encoded run: three palette-0 pixels
            0, 3, 1, 2, 1, 0,         // absolute run of three, padded to an even byte count
            0, 0,                     // end of line
            0, 2, 2, 0,               // delta: skip two columns on the next row
            2, 1,                     // two palette-1 pixels, leaving column 4 untouched
            0, 1                      // end of bitmap
        ]
        let data = runLength8(width: 5, height: 2, palette: [(10, 20, 30), (40, 50, 60), (70, 80, 90)],
                              stream: stream)
        let decoded = try WMPBitmapDecoder.decode(data, limits: limits)
        XCTAssertEqual(rgba(decoded.image, x: 0, yFromTop: 1), [10, 20, 30, 255])
        XCTAssertEqual(rgba(decoded.image, x: 3, yFromTop: 1), [40, 50, 60, 255])
        XCTAssertEqual(rgba(decoded.image, x: 4, yFromTop: 1), [70, 80, 90, 255])
        XCTAssertEqual(rgba(decoded.image, x: 2, yFromTop: 0), [40, 50, 60, 255])
        XCTAssertEqual(rgba(decoded.image, x: 3, yFromTop: 0), [40, 50, 60, 255])
        // The delta skipped these, and a run the stream never reached stays transparent — which is
        // what Windows leaves, not an error.
        XCTAssertEqual(rgba(decoded.image, x: 0, yFromTop: 0)[3], 0)
        XCTAssertEqual(rgba(decoded.image, x: 4, yFromTop: 0)[3], 0)
    }

    func testDecodesTopDownTwentyFourBitBitmap() throws {
        var data = trueColor24(width: 1, height: 2, rows: [[(1, 2, 3)], [(4, 5, 6)]])
        // A negative height means the rows are stored top-down.
        data.replaceSubrange(22..<26, with: Data([0xFE, 0xFF, 0xFF, 0xFF]))
        let decoded = try WMPBitmapDecoder.decode(data, limits: limits)
        XCTAssertEqual(decoded.height, 2)
        XCTAssertEqual(rgba(decoded.image, x: 0, yFromTop: 0), [1, 2, 3, 255])
        XCTAssertEqual(rgba(decoded.image, x: 0, yFromTop: 1), [4, 5, 6, 255])
    }

    func testRejectsOversizedAndUnreadableBitmapsDistinctly() throws {
        let big = trueColor24(width: 1, height: 2, rows: [[(1, 2, 3)], [(4, 5, 6)]])
        let tight = WMPBitmapDecoder.Limits(maximumDimension: 1, maximumPixels: 1,
                                            maximumDecodedBytes: 4)
        XCTAssertThrowsError(try WMPBitmapDecoder.decode(big, limits: tight)) { error in
            guard case WMPBitmapDecoder.Failure.oversized = error else {
                return XCTFail("expected an oversized failure, got \(error)")
            }
        }
        XCTAssertThrowsError(try WMPBitmapDecoder.decode(Data(repeating: 7, count: 64),
                                                         limits: limits)) { error in
            guard case WMPBitmapDecoder.Failure.unsupported = error else {
                return XCTFail("expected an unsupported failure, got \(error)")
            }
        }
    }

    /// End to end: the store must produce the bitmap whatever route it took, so this stays true if
    /// ImageIO ever learns to read the file itself.
    func testImageStoreDecodesABitmapImageIORefuses() throws {
        let data = paletted8(width: 2, height: 1, clrUsed: 0, clrImportant: 250,
                             palette: [(255, 0, 0), (0, 255, 0)], rows: [[0, 1]])
        let store = WMPImageStore(provider: WMPMemoryResourceProvider(["strip.bmp": data]))
        let decoded = try store.image(for: "strip.bmp")
        XCTAssertEqual(decoded.size, WMPSize(width: 2, height: 1))
        XCTAssertEqual(rgba(decoded.image, x: 0, yFromTop: 0), [255, 0, 0, 255])
        XCTAssertEqual(rgba(decoded.image, x: 1, yFromTop: 0), [0, 255, 0, 255])
    }

    func testImageStoreStillReportsAnUndecodableBitmap() throws {
        let store = WMPImageStore(provider: WMPMemoryResourceProvider([
            "broken.bmp": Data(repeating: 7, count: 64)
        ]))
        XCTAssertEqual(WMPSkinTestSupport.failureCode { try store.image(for: "broken.bmp") },
                       .imageDecodeFailed)
    }

    // MARK: - Fixtures

    private func rgba(_ image: CGImage, x: Int, yFromTop: Int) -> [UInt8] {
        WMPSkinTestSupport.rgba(image, x: x, yFromTop: yFromTop)
    }

    private func header(width: Int, height: Int, bitsPerPixel: Int, compression: UInt32,
                        paletteCount: Int, clrUsed: UInt32, clrImportant: UInt32,
                        imageSize: UInt32, payload: Int) -> Data {
        let pixelOffset = 14 + 40 + paletteCount * 4
        var data = Data()
        data.append(contentsOf: [0x42, 0x4D])
        data.append(le32(UInt32(pixelOffset + payload)))
        data.append(le32(0))
        data.append(le32(UInt32(pixelOffset)))
        data.append(le32(40))
        data.append(le32(UInt32(bitPattern: Int32(width))))
        data.append(le32(UInt32(bitPattern: Int32(height))))
        data.append(contentsOf: [1, 0])
        data.append(contentsOf: [UInt8(bitsPerPixel), 0])
        data.append(le32(compression))
        data.append(le32(imageSize))
        data.append(le32(2835)); data.append(le32(2835))
        data.append(le32(clrUsed))
        data.append(le32(clrImportant))
        return data
    }

    private func paletteBytes(_ palette: [(UInt8, UInt8, UInt8)], count: Int) -> Data {
        var data = Data()
        for index in 0..<count {
            let entry = index < palette.count ? palette[index] : (UInt8(0), UInt8(0), UInt8(0))
            data.append(contentsOf: [entry.2, entry.1, entry.0, 0])
        }
        return data
    }

    /// `rows` are bottom-up, as BMP stores them: the last entry is the authored top row.
    private func paletted8(width: Int, height: Int, clrUsed: UInt32, clrImportant: UInt32,
                           palette: [(UInt8, UInt8, UInt8)], rows: [[UInt8]]) -> Data {
        let stride = ((width * 8 + 31) / 32) * 4
        var pixels = Data()
        for row in rows {
            pixels.append(contentsOf: row)
            pixels.append(Data(repeating: 0, count: stride - row.count))
        }
        var data = header(width: width, height: height, bitsPerPixel: 8, compression: 0,
                          paletteCount: 256, clrUsed: clrUsed, clrImportant: clrImportant,
                          imageSize: UInt32(pixels.count), payload: pixels.count)
        data.append(paletteBytes(palette, count: 256))
        data.append(pixels)
        return data
    }

    private func runLength8(width: Int, height: Int, palette: [(UInt8, UInt8, UInt8)],
                            stream: [UInt8]) -> Data {
        var data = header(width: width, height: height, bitsPerPixel: 8, compression: 1,
                          paletteCount: 256, clrUsed: 0, clrImportant: UInt32(palette.count),
                          imageSize: UInt32(stream.count), payload: stream.count)
        data.append(paletteBytes(palette, count: 256))
        data.append(contentsOf: stream)
        return data
    }

    /// `rows` are bottom-up unless the caller rewrites the height as negative.
    private func trueColor24(width: Int, height: Int, rows: [[(UInt8, UInt8, UInt8)]]) -> Data {
        let stride = ((width * 24 + 31) / 32) * 4
        var pixels = Data()
        for row in rows {
            for pixel in row { pixels.append(contentsOf: [pixel.2, pixel.1, pixel.0]) }
            pixels.append(Data(repeating: 0, count: stride - row.count * 3))
        }
        var data = header(width: width, height: height, bitsPerPixel: 24, compression: 0,
                          paletteCount: 0, clrUsed: 0, clrImportant: 0,
                          imageSize: UInt32(pixels.count), payload: pixels.count)
        data.append(pixels)
        return data
    }

    private func le32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
              UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)])
    }
}
