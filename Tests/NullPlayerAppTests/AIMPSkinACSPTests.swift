import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// AIMP 2's `.acs` (`ACSP`) from synthetic packages: the container in both versions, its Windows
/// bitmaps, and `main.ini` read into the form (`reference/format.md` § *AIMP 2*).
final class AIMPSkinACSPTests: XCTestCase {
    // MARK: - The container

    func testVersion3NamesItselfInMainINI() throws {
        let ini = Self.ini("[FILE]\nSkinName=Red Lights\nAuthor=Tarik\n")
        let archive = try AIMPSkinArchive.read(Self.package(version: 3, entries: [("main.ini", ini), ("PlayBtn.bmp", Data([1, 2]))]))

        XCTAssertEqual(archive.format, .acsp)
        XCTAssertEqual(archive.name, "Red Lights")
        XCTAssertEqual(archive.author, "Tarik")
        XCTAssertEqual(try archive.entry("playbtn.bmp").map { try archive.payload($0) }, Data([1, 2]))
        XCTAssertTrue(archive.isLegacy, "main.ini and no AIMPMainForm.xml")
    }

    func testVersion2HasFixedNamesAndItsHeaderCredits() throws {
        let archive = try AIMPSkinArchive.read(Self.package(version: 2, name: "Big Bento", author: "Pro.Grammer",
                                                            entries: [("PLAYBTN_skin.bmp", Data([7])), ("main.ini", Self.ini(""))]))

        XCTAssertEqual(archive.name, "Big Bento")
        XCTAssertEqual(archive.author, "Pro.Grammer")
        XCTAssertEqual(try archive.entry("PLAYBTN_skin.bmp").map { try archive.payload($0) }, Data([7]))
    }

    func testOtherVersionsAndShortBodiesAreRefused() throws {
        var unknown = Self.package(version: 3, entries: [])
        unknown[4] = 0x20
        XCTAssertThrowsError(try AIMPSkinArchive.read(unknown)) { XCTAssertEqual(($0 as? AIMPSkinFinding)?.code, .unsupportedFormat) }

        // An entry declaring more bytes than the body holds.
        let truncated = Self.package(version: 3, entries: [("a.bmp", Data([1]))], declaredSizes: ["a.bmp": 50])
        XCTAssertThrowsError(try AIMPSkinArchive.read(truncated)) { XCTAssertEqual(($0 as? AIMPSkinFinding)?.code, .entryOutOfBounds) }
    }

    // MARK: - Bitmaps

    func testMagentaIsClearAndRowsRunBottomUp() throws {
        // Two rows of 24-bit pixels, bottom row first: red, magenta / blue, green.
        let image = try Self.picture(Self.bitmap(width: 2, height: 2, depth: 24,
                                                  rows: [[0, 0, 255, 255, 0, 255, 0, 0], [255, 0, 0, 0, 255, 0, 0, 0]]))
        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.frameCount, 1)
        let pixels = try XCTUnwrap(Self.bgra(image))
        XCTAssertEqual(Array(pixels[0..<8]), [255, 0, 0, 255, 0, 255, 0, 255], "top row: blue, green")
        XCTAssertEqual(Array(pixels[8..<16]), [0, 0, 255, 255, 0, 0, 0, 0], "bottom row: red, then the key colour clear")
    }

    func testThirtyTwoBitAlphaIsKeptOnlyWhereItVaries() throws {
        let varying = try Self.picture(Self.bitmap(width: 2, height: 1, depth: 32, rows: [[200, 100, 50, 128, 10, 20, 30, 255]]))
        XCTAssertEqual(try XCTUnwrap(Self.bgra(varying)), [100, 50, 25, 128, 10, 20, 30, 255], "straight alpha, premultiplied")

        let unused = try Self.picture(Self.bitmap(width: 2, height: 1, depth: 32, rows: [[200, 100, 50, 0, 10, 20, 30, 0]]))
        XCTAssertEqual(try XCTUnwrap(Self.bgra(unused)), [200, 100, 50, 255, 10, 20, 30, 255], "all-zero alpha: opaque")
    }

    func testPalettesAndAnOverstatedPixelOffset() throws {
        // 8-bit: index 1 of a two-colour palette.
        var paletted = Self.bitmap(width: 1, height: 1, depth: 8, rows: [[1, 0, 0, 0]], palette: [[0, 0, 0], [10, 20, 30]])
        XCTAssertEqual(try XCTUnwrap(Self.bgra(try Self.picture(paletted))), [10, 20, 30, 255])

        // A pixel offset 1,024 bytes past the pixels, which end the file.
        paletted = Self.bitmap(width: 1, height: 1, depth: 24, rows: [[1, 2, 3, 0]])
        let offset = UInt32(paletted.count - 4 + 1_024)
        paletted.replaceSubrange(10..<14, with: withUnsafeBytes(of: offset.littleEndian) { Data($0) })
        XCTAssertEqual(try XCTUnwrap(Self.bgra(try Self.picture(paletted))), [1, 2, 3, 255])
    }

    // MARK: - The form

    func testVersion3ObjectsPlaceAndActAsAIMP3Reads() throws {
        let ini = Self.ini("""
        [FILE]
        SkinName=Test
        [Parents]
        PlayBtn=MAIN
        CloseBtn=MAIN
        EQBtn=MAIN
        time=MAIN
        Gone=TCCTRL
        [PlayBtn]
        Align=0
        Bounds=2,3,12,13
        ParentBounds=0,0,40,24
        SkinFrames=4
        [CloseBtn]
        Align=1
        Bounds=28,0,38,10
        ParentBounds=0,0,40,24
        [EQBtn]
        Align=0
        Bounds=14,3,24,13
        ParentBounds=0,0,40,24
        [time]
        Align=0
        Bounds=0,14,26,24
        ParentBounds=0,0,40,24
        Digits=2
        """)
        let layout = Data("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<item Align=\"top\" Level=\"0\" Control=\"MainFrame\"/>\n".utf8)
        let skin = try AIMPSkinLoader.load(data: Self.package(version: 3, entries: [
            ("main.ini", ini), ("MainLayout.xml", layout),
            ("MainClient.bmp", Self.solid(width: 40, height: 20)), ("BottomDock.bmp", Self.solid(width: 40, height: 8)),
            ("PlayBtn.bmp", Self.solid(width: 40, height: 10)), ("CloseBtn.bmp", Self.solid(width: 20, height: 10)),
            ("EQBtn.bmp", Self.solid(width: 10, height: 10)), ("time.bmp", Self.solid(width: 169, height: 10)),
            ("MainEquaFrame.bmp", Self.solid(width: 30, height: 30)),
        ]))

        let controls = Dictionary(skin.mainForm.descendants().filter { $0.tag == "control" }.map { ($0["name"] ?? "", $0) },
                                  uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(Set(controls.keys), ["PlayBtn", "CloseBtn", "EQBtn", "time"], "the tray's objects are AIMP's window")
        let play = try XCTUnwrap(controls["PlayBtn"]?.properties["PlaceInfo"])
        XCTAssertEqual(play["anchors"], "1,1,0,0")
        XCTAssertEqual(play["margins"], "2,3,0,0")
        XCTAssertEqual(play["Size"], "10,10")
        XCTAssertEqual(controls["CloseBtn"]?.properties["PlaceInfo"]?["anchors"], "0,1,1,0", "Align 1 keeps the right edge")
        XCTAssertEqual(controls["CloseBtn"]?.properties["PlaceInfo"]?["margins"], "0,0,2,0")
        XCTAssertEqual(controls["time"]?["class"], "TimeDisplay")
        XCTAssertEqual(controls["EQBtn"]?.properties["Bindings"]?.link("Action")?["Source"], "EquaForm",
                       "the equalizer is a window of its own")

        XCTAssertEqual(skin.images["playbtn.img"]?.frameCount, 4)
        XCTAssertEqual(skin.images["closebtn.img"]?.frameCount, 2, "as many states as fit its width")
        XCTAssertEqual(skin.images["time.img"]?.frameCount, 13, "a digit strip")
        XCTAssertEqual(skin.images["bottomdock.img"]?.height, 4, "the docked state of two")
        XCTAssertEqual(skin.naturalSize(form: nil), CGSize(width: 40, height: 24), "MainClient over BottomDock's state")
        let equalizer = try XCTUnwrap(skin.companions.first)
        XCTAssertEqual(equalizer.name, "EquaForm")
        XCTAssertEqual(equalizer.placement, .right)
        XCTAssertFalse(equalizer.initiallyVisible)
    }

    func testVersion2ReadsItsOwnSectionsAndSpelling() throws {
        let ini = Self.ini("""
        [SKIN_OBJS]
        PLAYBTN=0,0,10,10
        Volumebar=10,0,30,5
        AIMPSlider1=0,0,4,20
        TrayPlay=0,0,5,5
        [PARENTS]
        PLAYBTN=Main
        Volumebar=Main
        [TC_PARENTS]
        TrayPlay=TCCTRL
        [SKIN_WIDTHS]
        PLAYBTN_align=0
        Volumebar_align=2
        Volumebar_HORIZONTAL=1
        """)
        let skin = try AIMPSkinLoader.load(data: Self.package(version: 2, name: "V2", author: "", entries: [
            ("main.ini", ini), ("MainClient_skin.bmp", Self.solid(width: 40, height: 20)),
            ("PLAYBTN_skin.bmp", Self.solid(width: 30, height: 10)), ("Volumebar_skin.bmp", Self.solid(width: 20, height: 5)),
            ("Volumebar_sel.bmp", Self.solid(width: 20, height: 5)), ("Volumebar_thumb.bmp", Self.solid(width: 4, height: 5)),
            ("Client_skin.bmp", Self.solid(width: 30, height: 30)), ("AIMPSlider9_skin.bmp", Self.solid(width: 4, height: 20)),
        ]))

        let controls = Dictionary(skin.allForms.flatMap { $0.descendants() }.filter { $0.tag == "control" }.map { ($0["name"] ?? "", $0) },
                                  uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(controls["PLAYBTN"]?.properties["Bindings"]?.link("Action")?["Source"], "acPlayerPlay", "names match in any case")
        XCTAssertEqual(controls["Volumebar"]?["class"], "Slider")
        XCTAssertEqual(controls["Volumebar"]?.properties["PlaceInfo"]?["anchors"], "1,1,1,0", "Align 2 stretches")
        XCTAssertEqual(skin.images["volumebar.img"]?.frameCount, 2, "the lit track is its second frame")
        XCTAssertNil(controls["TrayPlay"])
        XCTAssertEqual(controls["AIMPSlider1"]?.properties["Bindings"]?.link("Action")?["SourcePin"], "Band1",
                       "an equalizer band with no parent")
        XCTAssertNotNil(skin.images["aimpslider1.img"], "the bands share the ninth's picture")
        XCTAssertEqual(skin.companions.map(\.name), ["EquaForm"], "version 2's equalizer is `Client`")
        XCTAssertNotNil(skin.mainForm.descendants().first { $0["link"] == "Playlist" }, "the playlist docks under the player")
    }

    func testVersion3TakesItsLayoutFromItsFilesAndSaysWhyNot() throws {
        let ini = Self.ini("[Parents]\nPlayBtn=MAIN\n[PlayBtn]\nBounds=0,0,10,10\n")
        let entries = [("main.ini", ini), ("MainClient.bmp", Self.solid(width: 40, height: 20))]
        XCTAssertThrowsError(try AIMPSkinLoader.load(data: Self.package(version: 3, entries: entries)),
                             "a version 3 skin is never given version 2's fixed layout") {
            XCTAssertEqual(($0 as? AIMPSkinFinding)?.code, .noMainForm)
        }
        let malformed = entries + [("MainLayout.xml", Data("<item Align=\"top\"".utf8))]
        XCTAssertThrowsError(try AIMPSkinLoader.load(data: Self.package(version: 3, entries: malformed))) {
            XCTAssertEqual(($0 as? AIMPSkinFinding)?.code, .xmlMalformed, "the parse failure, not a missing form")
        }
    }

    func testMainINIReadsAsDelphiDoes() {
        let ini = AIMPSkinINI("key=before\n[FILE]\n SkinName =Micro Aimp \n[TextLabel2]\nTemplate= / %S\n[file]\nAuthor=Me\n")
        XCTAssertEqual(ini["file", "skinname"], "Micro Aimp", "sections and keys in any case; the value's end trimmed")
        XCTAssertEqual(ini["TextLabel2", "Template"], " / %S", "the spaces a value starts with are kept")
        XCTAssertEqual(ini["FILE", "Author"], "Me", "a repeated header carries on its section")
        XCTAssertEqual(ini["", "key"], "before")
        XCTAssertEqual(ini.sections.map(\.name), ["", "FILE", "TextLabel2"])
    }

    // MARK: - Fixtures

    /// An `ACSP` package: the header, then the zlib body of inline entries.
    private static func package(version: UInt8, name: String = "", author: String = "", entries: [(String, Data)],
                                declaredSizes: [String: Int] = [:]) -> Data {
        var header = Data("ACSP".utf8) + [version]
        header += padded(name, to: 32) + padded(author, to: 35)
        header += le32(entries.count)
        var body = Data()
        for (entryName, data) in entries {
            body += version == 2 ? padded(entryName, to: 32) : Data([UInt8(entryName.utf8.count)]) + Data(entryName.utf8)
            body += le32(declaredSizes[entryName] ?? data.count) + data
        }
        // `NSData`'s zlib is raw DEFLATE: the package's 2-byte zlib header goes before it.
        let deflated = (try? (body as NSData).compressed(using: .zlib)) as Data? ?? Data()
        return header + [0x78, 0x9C] + deflated
    }

    private static func padded(_ text: String, to length: Int) -> Data {
        Data(text.utf8.prefix(length)) + Data(repeating: 0, count: max(0, length - text.utf8.count))
    }

    private static func le32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }

    /// `main.ini` as AIMP 2 writes it: UTF-16 with a byte-order mark.
    private static func ini(_ text: String) -> Data { text.data(using: .utf16)! }

    /// A `BITMAPINFOHEADER` bitmap; `rows` bottom row first, each padded to 4 bytes by the caller.
    private static func bitmap(width: Int, height: Int, depth: Int, rows: [[UInt8]], palette: [[UInt8]] = []) -> Data {
        let colours: [UInt8] = palette.flatMap { $0 + [0] }
        let pixels: [UInt8] = rows.flatMap { $0 }
        let offset = 54 + colours.count
        var data = Data("BM".utf8) + le32(offset + pixels.count) + le32(0) + le32(offset)
        data += le32(40) + le32(width) + le32(height)
        data += Data([1, 0, UInt8(depth), 0]) + le32(0) + le32(pixels.count) + le32(0) + le32(0) + le32(palette.count) + le32(0)
        return data + colours + pixels
    }

    /// A grey 24-bit bitmap.
    private static func solid(width: Int, height: Int) -> Data {
        let row = [UInt8](repeating: 0x80, count: (width * 3 + 3) / 4 * 4)
        return bitmap(width: width, height: height, depth: 24, rows: Array(repeating: row, count: height))
    }

    /// A bitmap as the loader reads one, its pixels decoded when asked for.
    private static func picture(_ data: Data) throws -> AIMPSkinImage {
        try AIMPSkinImage(bitmap: data, name: "test.bmp", layout: .init(), budget: AIMPSkinPixelBudget(), source: { data })
    }

    private static func bgra(_ image: AIMPSkinImage) -> [UInt8]? {
        guard let data = image.frame(0)?.dataProvider?.data else { return nil }
        return [UInt8](data as Data)
    }
}

private extension AIMPNode {
    /// A `Bindings` property's first link to `pin`.
    func link(_ pin: String) -> AIMPNode? { children("link").first { $0["TargetPin"] == pin } }
}
