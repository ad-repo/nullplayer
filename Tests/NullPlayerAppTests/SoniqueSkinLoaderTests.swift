import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import NullPlayer

/// Builds `.sgf` bytes in-test; no Sonique or Lycos file is ever a fixture.
enum SoniqueSkinFixture {
    /// The container `reference/format.md` describes, with payloads after a full-stride table.
    static func sgf(_ entries: [(String, Data)], count: Int? = nil) -> Data {
        var table = Data(), payloads = Data()
        let first = 0x70 + entries.count * 0x64
        for (name, payload) in entries {
            var field = Data(name.utf8.prefix(0x53))
            field.append(Data(count: 0x54 - field.count))
            table.append(field)
            table.append(le32(first + payloads.count))
            table.append(le32(payload.count))
            table.append(Data(count: 8))
            payloads.append(payload)
        }
        var header = Data("DAF\0LIST".utf8)
        header.append(le32(first))
        header.append(Data(count: 0x14 - header.count))
        header.append(Data("sgf\0".utf8))
        header.append(Data(count: 0x64 - header.count))
        header.append(le32(first + payloads.count))
        header.append(le32(count ?? entries.count))
        header.append(Data(count: 4))
        return header + table + payloads
    }

    static func le32(_ value: Int) -> Data {
        withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) }
    }

    /// A real, decodable JPEG.
    static func jpeg(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// Only a SOI and a baseline frame header claiming `width` × `height`: enough for the header
    /// checks, which must fire before anything tries to decode it.
    static func jpegHeader(width: Int, height: Int) -> Data {
        Data([0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08, UInt8(height >> 8), UInt8(height & 0xFF),
              UInt8(width >> 8), UInt8(width & 0xFF), 0x03] + [UInt8](repeating: 0, count: 9))
    }

    static func region(_ rects: [(Int, Int, Int, Int)]) -> Data {
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
        let bounds = (rects.map(\.0).min() ?? 0, rects.map(\.1).min() ?? 0, rects.map(\.2).max() ?? 0, rects.map(\.3).max() ?? 0)
        var bytes = le16(rects.count) + le16(bounds.0) + le16(bounds.1) + le16(bounds.2) + le16(bounds.3)
        for r in rects { bytes += le16(r.0) + le16(r.1) + le16(r.2) + le16(r.3) }
        return Data(bytes)
    }

    /// Every mode with a picture and a frame.
    static var complete: [(String, Data)] {
        [("/skin.ini", Data("[skin]\r\ntitle=Fixture\r\n".utf8)),
         ("/jpeg/navigator", jpeg(width: 40, height: 30)), ("/rgn/nav/frame", region([(0, 0, 40, 30)])),
         ("/jpeg/midsonique", jpeg(width: 20, height: 30)), ("/rgn/mid/frame", region([(0, 0, 20, 30)])),
         ("/jpeg/smallstate", jpeg(width: 30, height: 6)), ("/rgn/small/frame", region([(0, 0, 30, 6)])),
         ("/rgn/nav/play", region([(2, 2, 8, 8), (3, 8, 7, 10)]))]
    }
}

final class SoniqueSkinLoaderTests: XCTestCase {
    private func load(_ entries: [(String, Data)]) throws -> SoniqueSkin {
        try SoniqueSkinLoader.load(data: SoniqueSkinFixture.sgf(entries))
    }

    private func assertFatal(_ code: SoniqueSkinDiagnosticCode, _ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try SoniqueSkinLoader.load(data: data), file: file, line: line) {
            XCTAssertEqual(($0 as? SoniqueSkinFinding)?.code, code, file: file, line: line)
        }
    }

    func testCompleteSkinLoadsEveryEntry() throws {
        let skin = try load(SoniqueSkinFixture.complete)
        XCTAssertEqual(skin.findings, [])
        XCTAssertEqual(skin.defaultModes, [])
        XCTAssertEqual(skin.images["/jpeg/navigator"]?.width, 40)
        XCTAssertEqual(skin.regions["/rgn/nav/play"]?.rects.count, 2)
        XCTAssertEqual(skin.ini.value("SKIN", "Title"), "Fixture")
    }

    func testEntryNamesMatchCaseInsensitivelyAndTheLastWins() throws {
        let skin = try load(SoniqueSkinFixture.complete + [
            ("/rgn/nav/logoHREF", SoniqueSkinFixture.region([(1, 1, 2, 2)])),
            ("/rgn/nav/logohref", SoniqueSkinFixture.region([(5, 5, 6, 6)]))])
        XCTAssertEqual(skin.regions["/rgn/nav/logohref"]?.bounds.left, 5)
    }

    func testTheFirstSectionOfANameIsTheOnlyOneRead() {
        let ini = SoniqueSkinINI("[skin]\nversion=105\n[Sonique Colors]\nSystemColor_1=0x1\n[SKIN]\nversion=100\nauthor=late\n")
        XCTAssertEqual(ini.value("skin", "version"), "105")
        XCTAssertNil(ini.value("skin", "author"))
        XCTAssertEqual(ini.value("sonique colors", "systemcolor_1"), "0x1")
    }

    // MARK: - Fatal codes, one each

    func testNotAnArchiveIsSQ0001() {
        assertFatal(.notAnArchive, Data("RIFF".utf8) + Data(count: 0x80))
        var truncated = SoniqueSkinFixture.sgf(SoniqueSkinFixture.complete)
        truncated.replaceSubrange(0x68..<0x6C, with: SoniqueSkinFixture.le32(200))
        assertFatal(.notAnArchive, truncated)
    }

    func testOversizedFileIsSQ0002() {
        assertFatal(.fileTooLarge, Data(count: SoniqueSkinPolicy.fileBytes + 1))
    }

    func testTooManyEntriesIsSQ0003() {
        assertFatal(.tooManyEntries, SoniqueSkinFixture.sgf([], count: SoniqueSkinPolicy.entries + 1))
    }

    /// `greenwitch.sgf`'s shape: the table is intact and a payload runs past the end of the file.
    func testTruncatedPayloadIsSQ0004() {
        let whole = SoniqueSkinFixture.sgf(SoniqueSkinFixture.complete)
        assertFatal(.entryOutOfBounds, whole.prefix(whole.count - 10))
    }

    func testOversizedImageSideIsSQ0005() {
        assertFatal(.imageTooLarge, SoniqueSkinFixture.sgf(SoniqueSkinFixture.complete + [
            ("/jpeg/shuttle", SoniqueSkinFixture.jpegHeader(width: SoniqueSkinPolicy.imageSide + 1, height: 1))]))
    }

    func testPixelBudgetIsSQ0006() {
        let strip = SoniqueSkinFixture.jpegHeader(width: 16_000, height: 1_100)
        assertFatal(.pixelBudgetExceeded, SoniqueSkinFixture.sgf((1...4).map { ("/jpeg/strip\($0)", strip) }))
    }

    func testOversizedINIIsSQ0007() {
        assertFatal(.iniTooLarge, SoniqueSkinFixture.sgf([("/skin.ini", Data(count: SoniqueSkinPolicy.iniBytes + 1))]))
    }

    // MARK: - Warnings

    func testUnreadableEntriesAreSQ0008AndAbsent() throws {
        let skin = try load(SoniqueSkinFixture.complete + [
            ("/jpeg/misc", Data("not a jpeg".utf8)),
            ("/jpeg/extra", SoniqueSkinFixture.jpegHeader(width: 10, height: 10)),
            ("/rgn/nav/next", Data([2, 0, 0, 0]))])
        XCTAssertEqual(skin.findings.map(\.code), [.entryUnreadable, .entryUnreadable, .entryUnreadable])
        XCTAssertNil(skin.images["/jpeg/misc"])
        XCTAssertNil(skin.images["/jpeg/extra"])
        XCTAssertNil(skin.regions["/rgn/nav/next"])
    }

    func testAModeWithoutPictureOrTouchedOffIsSQ0009() throws {
        var entries = SoniqueSkinFixture.complete.filter { $0.0 != "/jpeg/smallstate" }
        entries[0] = ("/skin.ini", Data("[skin]\r\nTouchMidMode = 0\r\n".utf8))
        let skin = try load(entries)
        XCTAssertEqual(skin.defaultModes, [.mid, .small])
        XCTAssertEqual(skin.findings.map(\.code), [.modeUsesDefault, .modeUsesDefault])
    }

    func testAMissingFrameAloneLeavesTheModeDrawnBySkin() throws {
        let skin = try load(SoniqueSkinFixture.complete.filter { $0.0 != "/rgn/small/frame" })
        XCTAssertEqual(skin.defaultModes, [])
        XCTAssertEqual(skin.findings, [])
    }

    func testARegionPastItsPictureIsClippedSQ0010() throws {
        let skin = try load(SoniqueSkinFixture.complete.map {
            $0.0 == "/rgn/mid/frame" ? ($0.0, SoniqueSkinFixture.region([(0, 0, 21, 30), (20, 0, 22, 4)])) : $0
        } + [("/rgn/small/extrabottom", SoniqueSkinFixture.region([(0, 6, 30, 40)]))])
        XCTAssertEqual(skin.findings.map(\.code), [.regionClipped])
        XCTAssertEqual(skin.regions["/rgn/mid/frame"]?.rects, [.init(left: 0, top: 0, right: 20, bottom: 30)])
        XCTAssertEqual(skin.regions["/rgn/small/extrabottom"]?.bounds.bottom, 40, "a drawer lies past the bar by design")
    }
}
