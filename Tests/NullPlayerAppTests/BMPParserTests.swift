import AppKit
import NullPlayerCore
import XCTest
@testable import NullPlayer

final class BMPParserTests: XCTestCase {
    func testFourBitBMPUsesPackedAlignedRowStride() throws {
        let bmpData = makeFourBitBMP()

        let appImage = try XCTUnwrap(NullPlayer.BMPParser.parse(data: bmpData))
        assertFourBitBMPDecoded(appImage)

        let coreImage = try XCTUnwrap(NullPlayerCore.BMPParser.parse(data: bmpData))
        assertFourBitBMPDecoded(coreImage)
    }

    private func assertFourBitBMPDecoded(_ image: NSImage, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(image.size.width, 5, file: file, line: line)
        XCTAssertEqual(image.size.height, 2, file: file, line: line)
        XCTAssertEqual(pixel(atX: 0, y: 0, in: image), RGBA(255, 0, 0, 255), file: file, line: line)
        XCTAssertEqual(pixel(atX: 4, y: 0, in: image), RGBA(0, 255, 255, 255), file: file, line: line)
        XCTAssertEqual(pixel(atX: 0, y: 1, in: image), RGBA(64, 64, 64, 255), file: file, line: line)
    }

    private func makeFourBitBMP() -> Data {
        let width = 5
        let height = 2
        let bitsPerPixel: UInt16 = 4
        let paletteEntryCount = 16
        let pixelDataOffset = 14 + 40 + paletteEntryCount * 4
        let rowSize = ((width * Int(bitsPerPixel) + 31) / 32) * 4
        let fileSize = pixelDataOffset + rowSize * height

        var data = Data()
        data.append(0x42)
        data.append(0x4D)
        appendUInt32(UInt32(fileSize), to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt32(UInt32(pixelDataOffset), to: &data)

        appendUInt32(40, to: &data)
        appendInt32(Int32(width), to: &data)
        appendInt32(Int32(height), to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(bitsPerPixel, to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(UInt32(rowSize * height), to: &data)
        appendInt32(2_835, to: &data)
        appendInt32(2_835, to: &data)
        appendUInt32(UInt32(paletteEntryCount), to: &data)
        appendUInt32(0, to: &data)

        let palette: [(r: UInt8, g: UInt8, b: UInt8)] = [
            (0, 0, 0),
            (255, 0, 0),
            (0, 255, 0),
            (0, 0, 255),
            (255, 255, 0),
            (0, 255, 255),
            (255, 0, 255),
            (64, 64, 64),
            (128, 128, 128),
            (255, 128, 0),
            (128, 0, 255),
            (0, 128, 255),
            (128, 255, 0),
            (255, 0, 128),
            (0, 255, 128),
            (255, 255, 255),
        ]

        for color in palette {
            data.append(color.b)
            data.append(color.g)
            data.append(color.r)
            data.append(0)
        }

        // BMP rows are bottom-up. Five 4-bit pixels require three packed bytes
        // plus one pad byte, not five bytes rounded to an eight-byte stride.
        data.append(contentsOf: [0x78, 0x9A, 0xB0, 0x00])
        data.append(contentsOf: [0x12, 0x34, 0x50, 0x00])
        return data
    }

    private func pixel(atX x: Int, y: Int, in image: NSImage) -> RGBA? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let context = CGContext(data: &data,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let index = y * bytesPerRow + x * 4
        return RGBA(data[index], data[index + 1], data[index + 2], data[index + 3])
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private func appendInt32(_ value: Int32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private struct RGBA: Equatable {
        let r: UInt8
        let g: UInt8
        let b: UInt8
        let a: UInt8

        init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) {
            self.r = r
            self.g = g
            self.b = b
            self.a = a
        }
    }
}
