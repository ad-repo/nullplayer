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

    /// A BOM-less UTF-16 file has no *failure* to fall through to: Windows-1252 accepts every byte
    /// sequence, so it decodes "successfully" into null-interleaved mojibake, and the only thing that
    /// then notices is the embedded-NUL check — which rejects the skin rather than reading it. The
    /// `.wal` engine paid for the identical trap with `isoLatin1` (B93).
    func testSniffsUTF16WithoutAByteOrderMarkInsteadOfRejectingIt() throws {
        let source = "<THEME name=\"Café\"/>"
        for littleEndian in [true, false] {
            let data = WMPSkinTestSupport.utf16(source, littleEndian: littleEndian, bom: false)
            XCTAssertEqual(try WMPTextDecoder.decode(data, path: "nobom.wms"),
                           WMPDecodedText(string: source,
                                          encoding: littleEndian ? .utf16LittleEndian : .utf16BigEndian))
        }
    }

    /// The sniff must not claim a single-byte file. It requires a `<` as the first non-whitespace
    /// unit and NULs on one side only, so ordinary text carrying a stray NUL stays a `WMP0026`
    /// rejection rather than being silently reinterpreted as the wrong encoding.
    func testSniffDoesNotClaimSingleByteTextThatMerelyContainsNULs() {
        XCTAssertEqual(code(Data([0x41, 0x00, 0x42, 0x00, 0x00, 0x43])), .embeddedNUL)
        XCTAssertEqual(code(Data("hi\u{0}there".utf8)), .embeddedNUL)
    }

    private func code(_ data: Data) -> WMPDiagnosticCode? {
        WMPSkinTestSupport.failureCode { try WMPTextDecoder.decode(data, path: "fixture.wms") }
    }
}
