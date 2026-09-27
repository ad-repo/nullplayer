import AppKit
import XCTest
import ZIPFoundation
@testable import NullPlayer

/// **A frame painted only with tooltip art is not the skin's window chrome.**
///
/// ClassicPro engine `one` builds `wasabi.frame.layout` — the body of every `wasabi.standardframe.*`
/// it declares — from a grid of `wasabi.tooltip.*` bitmaps, and draws its `~` and `x` as text. Taken
/// as the skin's frame, it put every NullPlayer window of the 11 engine-`one` cPro skins in a cream
/// tooltip box unrelated to the player. Tooltip art is never styled, so such a frame routes to the
/// fallback (the gloss frame) instead. Engine `two` paints `cpro2.genframe.*` and keeps its frame.
final class WinampModernTooltipFrameTests: XCTestCase {

    func testAFramePaintedOnlyWithTooltipArtIsNotBorrowed() throws {
        let loaded = try makeSkin(gridPrefix: "wasabi.tooltip")
        guard case .classicFallback(let reason) = loaded.surfaceSynthesis.hostedWindows[.cava] else {
            return XCTFail("a tooltip-art frame must not be lent to NullPlayer's windows")
        }
        XCTAssertTrue(reason.contains("tooltip"), reason)
    }

    func testAFramePaintedWithItsOwnArtIsStillBorrowed() throws {
        let loaded = try makeSkin(gridPrefix: "cpro2.genframe")
        guard case .skinFrame(let frame) = loaded.surfaceSynthesis.hostedWindows[.cava] else {
            return XCTFail("a frame with its own artwork is the skin's chrome")
        }
        XCTAssertEqual(frame.groupIdentifier, "wasabi.standardframe.statusbar")
    }

    // MARK: - Fixture

    /// ClassicPro's shape: the standard frame holds a `<group id="wasabi.frame.layout"/>` naming the
    /// groupdef that carries the art, beside a script that builds the client area.
    private func makeSkin(gridPrefix: String) throws -> WinampModernLoadedSkin {
        let xml = """
        <WasabiXML>
          <groupdef id="wasabi.frame.layout">
            <grid fitparent="1" relatw="1" relath="1"
                  topleft="\(gridPrefix).top.left" top="\(gridPrefix).top"
                  topright="\(gridPrefix).top.right" left="\(gridPrefix).left"
                  middle="\(gridPrefix).center" right="\(gridPrefix).right"
                  bottomleft="\(gridPrefix).bottom.left" bottom="\(gridPrefix).bottom"
                  bottomright="\(gridPrefix).bottom.right"/>
            <text x="-20" y="2" w="18" relatx="1" default="x"/>
            <button x="-20" y="2" w="18" h="16" relatx="1" action="CLOSE"/>
          </groupdef>
          <groupdef id="wasabi.standardframe.statusbar" xuitag="Wasabi:StandardFrame:Status">
            <group id="wasabi.frame.layout" fitparent="1"/>
            <script file="scripts/standardframe.maki" param="4,19,-8,-24,0,0,1,1"/>
          </groupdef>
          <container id="main">
            <layout id="normal" default_w="300" default_h="160">
              <windowholder hold="guid:pl" x="0" y="0" w="20" h="20"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernTooltipFrameTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("TooltipFrame-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        func add(_ path: String, _ data: Data) throws {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < data.count else { return Data() }
                return data.subdata(in: start..<min(data.count, start + size))
            }
        }
        try add("skin.xml", Data(xml.utf8))
        try add("scripts/standardframe.maki", Self.frameMakiScript())
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    /// A frame script whose method table names `newGroup`, which is how synthesis tells a frame that
    /// builds its client area from one that only draws.
    private static func frameMakiScript() -> Data {
        var data = Data([0x46, 0x47])
        func u8(_ value: UInt8) { data.append(value) }
        func u16(_ value: UInt16) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func u32(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func string(_ value: String) {
            let bytes = Data(value.utf8)
            u16(UInt16(bytes.count)); data.append(bytes)
        }
        u16(0x0403); u32(23); u32(1)
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        let handlers = ["onscriptloaded", "onsetxuiparam"]
        let methods = handlers + ["newGroup"]
        u32(UInt32(methods.count))
        for method in methods { u16(0); u16(0); string(method) }
        u32(1)
        u8(0); u8(1); u16(0); u16(0); u16(0); u16(0); u16(0); u8(1); u8(1)
        u32(0)
        u32(UInt32(handlers.count))
        for method in 0..<handlers.count { u32(0); u32(UInt32(method)); u32(0) }
        u32(1); u8(33)
        return data
    }
}
