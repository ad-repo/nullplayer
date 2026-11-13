import XCTest
@testable import NullPlayer

final class DataUTF8RepairTests: XCTestCase {
    func testValidUTF8IsLeftAlone() {
        XCTAssertNil(Data(#"{"t":"Mötley Crüe"}"#.utf8).utf8Repaired)
    }

    /// A Latin-1 byte inside UTF-8 JSON: the shape a Plex search returned for "public enemy".
    func testLatin1BytesBecomeQuestionMarksAndDecode() throws {
        let data = Data(#"{"t":"M"#.utf8) + Data([0xF6]) + Data(#"tley Cr"#.utf8) + Data([0xFC]) + Data(#"e"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode([String: String].self, from: data))
        let repaired = try XCTUnwrap(data.utf8Repaired)
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: repaired), ["t": "M?tley Cr?e"])
    }
}
