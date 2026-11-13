import XCTest
@testable import NullPlayer

final class JSONDecoderUTF8RepairTests: XCTestCase {
    private func decode(_ data: Data) throws -> [String: String] {
        try JSONDecoder().decodeRepairingUTF8([String: String].self, from: data)
    }

    func testValidUTF8DecodesUnchanged() throws {
        XCTAssertEqual(try decode(Data(#"{"t":"Mötley Crüe"}"#.utf8)), ["t": "Mötley Crüe"])
    }

    /// A Latin-1 byte inside UTF-8 JSON: the shape a Plex search returned for "public enemy".
    func testLatin1BytesBecomeQuestionMarks() throws {
        let data = Data(#"{"t":"M"#.utf8) + Data([0xF6]) + Data(#"tley Cr"#.utf8) + Data([0xFC]) + Data(#"e"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode([String: String].self, from: data))
        XCTAssertEqual(try decode(data), ["t": "M?tley Cr?e"])
    }

    func testMalformedValidUTF8StillThrows() {
        XCTAssertThrowsError(try decode(Data(#"{"t":"#.utf8)))
    }
}
