import Foundation
import XCTest
@testable import NullPlayer

final class WMPTextDecoderTests: XCTestCase {
    func testDecodesUTF8BothUTF16ByteOrdersAndLegacyWindows1252() throws {
        let source = "<THEME name=\"Café 😀\"/>"
        let utf8 = try WMPTextDecoder.decode(Data([0xEF, 0xBB, 0xBF]) + Data(source.utf8), path: "a.wms")
        XCTAssertEqual(utf8, WMPDecodedText(string: source, encoding: .utf8))
        XCTAssertEqual(try WMPTextDecoder.decode(WMPSkinTestSupport.utf16(source, littleEndian: true), path: "le.wms"),
                       WMPDecodedText(string: source, encoding: .utf16LittleEndian))
        XCTAssertEqual(try WMPTextDecoder.decode(WMPSkinTestSupport.utf16(source, littleEndian: false), path: "be.wms"),
                       WMPDecodedText(string: source, encoding: .utf16BigEndian))
        XCTAssertEqual(try WMPTextDecoder.decode(Data([0x43, 0x61, 0x66, 0xE9]), path: "ansi.js"),
                       WMPDecodedText(string: "Café", encoding: .windows1252))
    }

    func testRejectsOddLengthUnpairedSurrogatesAndNUL() {
        XCTAssertEqual(code(Data([0xFF, 0xFE, 0x41])), .invalidTextEncoding)
        XCTAssertEqual(code(Data([0xFF, 0xFE, 0x00, 0xD8, 0x41, 0x00])), .invalidTextEncoding)
        XCTAssertEqual(code(Data([0xFE, 0xFF, 0xDC, 0x00])), .invalidTextEncoding)
        XCTAssertEqual(code(Data([0xEF, 0xBB, 0xBF, 0x41, 0, 0x42])), .embeddedNUL)
        XCTAssertEqual(code(Data([0x41, 0, 0x42])), .embeddedNUL)
    }

    private func code(_ data: Data) -> WMPDiagnosticCode? {
        WMPSkinTestSupport.failureCode { try WMPTextDecoder.decode(data, path: "fixture.wms") }
    }
}
