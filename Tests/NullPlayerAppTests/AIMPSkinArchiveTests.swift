import Compression
import Foundation
import XCTest
@testable import NullPlayer

/// The containers, built byte by byte as `reference/format.md` § *Containers* describes them: the
/// key a scrambled `3SCA` gives away, the metadata block's length and UTF-16LE strings (names past
/// Latin-1, descriptions past 255 characters), and the body where that length says.
final class AIMPSkinArchiveTests: XCTestCase {
    private static let key: [UInt8] = [0x45, 0x24, 0x9A, 0xD9]
    /// A description longer than 255 characters: its count's high byte is not zero.
    private static let about = String(repeating: "Skin for AIMP 3. ", count: 20)
    /// A preview whose file header overstates its size, as many `.acs3` previews do.
    private static let preview: [UInt8] = Array("BM".utf8) + u32(1_078) + [UInt8](repeating: 0x5A, count: 50)

    func testACS4OpensByItsMarkerAndMetadataLength() throws {
        let body = Self.toc(["Schema.xml": Data("<schema/>".utf8)])
        var file = Array("ACS4".utf8) + [0x00] + Self.u32(450) + Self.scrambledMarker(at: 9)
        file += Self.metadata(at: file.count)
        file += Self.u32(body.count)
        file += Self.scrambled(Self.zlib(body), at: file.count)
        let archive = try AIMPSkinArchive.read(Data(file))

        XCTAssertEqual(archive.format, .acs4)
        XCTAssertEqual(archive.name, "Олимп 004 стерео")
        XCTAssertEqual(archive.author, "© ROMEO")
        XCTAssertEqual(archive.about, Self.about)
        XCTAssertEqual(archive.preview.map([UInt8].init), Self.preview, "the preview ends where the block does")
        XCTAssertEqual(try archive.entry("schema.xml").map(archive.payload), Data("<schema/>".utf8))
    }

    func testACS3HeaderKinds() throws {
        let body = Self.toc(["MainFrame.xml": Data("<item/>".utf8)])
        // Kind 6: an engine version and the marker at 9, as `.acs4`; no inflated size.
        var six = Array("ACS3".utf8) + [0x06, 0x5E, 0x01, 0x01, 0x00] + Self.scrambledMarker(at: 9)
        six += Self.metadata(at: six.count)
        six += Self.scrambled(Self.zlib(body), at: six.count)
        // Kinds 3 and 5: the marker at 5.
        var five = Array("ACS3".utf8) + [0x05] + Self.scrambledMarker(at: 5)
        five += Self.metadata(at: five.count)
        five += Self.scrambled(Self.zlib(body), at: five.count)

        for file in [six, five] {
            let archive = try AIMPSkinArchive.read(Data(file))
            XCTAssertEqual(archive.format, .acs3)
            XCTAssertEqual(archive.name, "Олимп 004 стерео")
            XCTAssertEqual(archive.about, Self.about)
            XCTAssertNotNil(archive.entry("mainframe.xml"))
        }
    }

    func testAIMP30ACS3ReadsItsNameFromMainIni() throws {
        let ini = Data("[FILE]\r\nSkinName=Vega AIO\r\nAuthor=Someone\r\n".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        let body = Self.toc(["main.ini": Data([0xFF, 0xFE]) + ini])
        // Kinds 1 and 2: the marker at 5, then the zlib body; no metadata block.
        for kind: UInt8 in [1, 2] {
            var file = Array("ACS3".utf8) + [kind] + Self.scrambledMarker(at: 5)
            file += Self.scrambled(Self.zlib(body), at: file.count)
            let archive = try AIMPSkinArchive.read(Data(file))
            XCTAssertEqual(archive.name, "Vega AIO")
            XCTAssertEqual(archive.author, "Someone")
            XCTAssertTrue(archive.isLegacy)
        }
    }

    /// What does not read is said, not swallowed: a malformed form is its parse finding, and a script
    /// that does not parse rides on the skin as one.
    func testAIMP30FormsAndScriptsReportWhatDoesNotRead() throws {
        let ini = Data([0xFF, 0xFE]) + Data("[FILE]\r\nSkinName=Vega AIO\r\n".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        func skin(_ entries: [String: Data]) throws -> AIMPSkin {
            var file = Array("ACS3".utf8) + [1] + Self.scrambledMarker(at: 5)
            file += Self.scrambled(Self.zlib(Self.toc(entries.merging(["main.ini": ini]) { a, _ in a })), at: file.count)
            return try AIMPSkinLoader.load(data: Data(file))
        }
        XCTAssertThrowsError(try skin(["MainFrame.xml": Data("<item Name=".utf8)])) {
            XCTAssertEqual(($0 as? AIMPSkinFinding)?.code, .xmlMalformed, "not AM0010: the form is there and does not read")
        }
        let loaded = try skin(["MainFrame.xml": Data("<item Name=\"Main\"/>".utf8), "Broken.fsxml": Data("FSXMLBIN".utf8)])
        XCTAssertNil(loaded.scripts.programs["broken"])
        XCTAssertEqual(loaded.findings.map(\.code), [.entryUnreadable])
        XCTAssertTrue(loaded.findings.first?.message.contains("Broken.fsxml") == true)
    }

    func testUnknownACS3KindIsUnsupported() {
        let file = Array("ACS3".utf8) + [0x04] + [UInt8](repeating: 0, count: 40)
        XCTAssertThrowsError(try AIMPSkinArchive.read(Data(file))) { error in
            XCTAssertEqual((error as? AIMPSkinFinding)?.code, .unsupportedFormat)
        }
    }

    func testACS5ReadsEntriesAfterALongDescription() throws {
        let key = (0..<16).map { UInt8(0x10 + $0 * 7) }
        var file = Array("ACS5".utf8) + [0x00] + Self.u32(500) + [0x00, UInt8(key.count)] + key
        let start = file.count
        var plain = Self.metadataBlock()
        plain += Self.u32(1)
        plain += Self.utf16LE("AIMPMainForm") + [3] + Self.u32(7) + [0] + Array("<form/>".utf8)
        for (i, byte) in plain.enumerated() { file.append(byte ^ key[(start + i) % key.count]) }
        let archive = try AIMPSkinArchive.read(Data(file))

        XCTAssertEqual(archive.about, Self.about)
        XCTAssertEqual(archive.entries.count, 1)
        XCTAssertEqual(try archive.entry("AIMPMainForm.xml").map(archive.payload), Data("<form/>".utf8))
    }

    func testProjectReadsItsCountedEntries() throws {
        var file = Array("ACSJ".utf8) + [0x04] + Self.u32(450) + [0, 0, 0, 0]
        file += Self.metadataBlock()
        file += Self.u32(2)
        file += Self.utf16LE("a.xml") + Self.u32(3) + Array("<a>".utf8)
        file += Self.utf16LE("b.xml") + Self.u32(0)
        let archive = try AIMPSkinArchive.read(Data(file))

        XCTAssertEqual(archive.format, .project)
        XCTAssertEqual(archive.name, "Олимп 004 стерео")
        XCTAssertEqual(archive.entries.count, 2)
        XCTAssertEqual(try archive.entry("a.xml").map(archive.payload), Data("<a>".utf8))
    }

    // MARK: - Building containers

    private static func u32(_ value: Int) -> [UInt8] { (0..<4).map { UInt8((value >> (8 * $0)) & 0xFF) } }

    private static func utf16LE(_ text: String) -> [UInt8] {
        let units = Array(text.utf16)
        return [UInt8(units.count & 0xFF), UInt8(units.count >> 8)] + units.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
    }

    /// `3SCA` under the key, at file offset `at`.
    private static func scrambledMarker(at: Int) -> [UInt8] { scrambled(Array("3SCA".utf8), at: at) }

    /// `bytes` XORed as if they sat at file offset `at`.
    private static func scrambled(_ bytes: [UInt8], at: Int) -> [UInt8] {
        bytes.enumerated().map { $1 ^ key[($0 + at) % 4] }
    }

    /// The metadata block, plain: u32 length, name, author, description, u8 preview flag, preview.
    private static func metadataBlock() -> [UInt8] {
        let block = utf16LE("Олимп 004 стерео") + utf16LE("© ROMEO") + utf16LE(about) + [1] + preview
        return u32(block.count) + block
    }

    /// The metadata block at file offset `at`: its length plain, the rest scrambled.
    private static func metadata(at: Int) -> [UInt8] {
        let block = metadataBlock()
        return Array(block.prefix(4)) + scrambled(Array(block.dropFirst(4)), at: at + 4)
    }

    /// An `.acs4` body: u32 count, `{ name, u32 offset, u32 size }`, then the blob.
    private static func toc(_ entries: [String: Data]) -> Data {
        var table = u32(entries.count), blob = Data()
        for (name, bytes) in entries.sorted(by: { $0.key < $1.key }) {
            table += utf16LE(name) + u32(blob.count) + u32(bytes.count)
            blob += bytes
        }
        return Data(table) + blob
    }

    /// A zlib stream: a 2-byte header and raw DEFLATE (the checksum is never read).
    private static func zlib(_ data: Data) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: data.count + 1_024)
        let count = data.withUnsafeBytes { source in
            compression_encode_buffer(&out, out.count, source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
        return [0x78, 0x9C] + out.prefix(count)
    }
}
