import AppKit
import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B140 — HeadAMP, reported as *"skin heapamp is creating nullplayer native windows with thick
/// borders/small interior and its also offset within the frame"*, and then, after the first fix,
/// *"the size is much better but the right shift is still there"*.
///
/// The skin follows the Wasabi contract that Itemskin does not: its standard frame builds its own
/// client area, and the rect it uses is the `param="x,y,w,h,…"` on the `<script>` in the frame's
/// groupdef — `25,28,-40,-70` for the status frame, `25,28,-40,-50` for the no-status one. Three
/// things were wrong for a window of *ours* inside a frame like that, and they are independent:
///
/// 1. **The border cost the window nothing.** `Frame.chromeInset` answered `.zero` for every frame
///    without an exemplar, so the hosted-window registry's client size was used as the *window* size
///    and the frame ate it from inside: a 343x145 meter drew in 303x75.
/// 2. **We took the richest frame flavour, not the thinnest.** A status frame reserves rows for a
///    strip whose text Winamp's own components supply and ours never do — 20 rows here, around a
///    145-row window.
/// 3. **The skin's script placed our client, off-centre.** The author's padding is asymmetric where
///    it is padding for contents we do not supply (25 left against 15 right, 28 top against 42
///    bottom), so the meter sat visibly right and low. Ours is centred instead, on the *larger* of
///    each opposing pair, which clears everything the author kept clear on either side.
///
/// The trap the third fix set is pinned here too, because it is the one that reached the reporter:
/// `WasabiSkinInitializer.instantiateHostedWindowAtRuntime` **rebuilds** the `Frame` from the
/// descriptor before it emits nodes, so a field added to `Frame` and threaded through the descriptor
/// is still dropped there. Sizing (which reads the descriptor) was right while placement (which reads
/// the rebuilt frame) was unchanged — a correctly sized window with the client still shoved right.
/// **A hosted window's geometry is decided in two places; assert both.**
final class WinampModernB140Tests: XCTestCase {

    // MARK: - The thinnest flavour wins

    func testTheFrameThatLeavesTheMostWindowIsSelected() throws {
        let loaded = try makeSkin(statusParam: "25,28,-40,-70", noStatusParam: "25,28,-40,-50")
        guard case .skinFrame(let frame) = loaded.surfaceSynthesis.hostedWindows[.cava] else {
            return XCTFail("expected a skin-frame route")
        }
        XCTAssertEqual(frame.groupIdentifier, "wasabi.standardframe.nostatusbar")
    }

    /// The old order — status bar, no status bar, static — still decides between frames that cost the
    /// window the same, which is every skin that states no rect at all.
    func testTheRichestFrameStillWinsATie() throws {
        let loaded = try makeSkin(statusParam: nil, noStatusParam: nil)
        guard case .skinFrame(let frame) = loaded.surfaceSynthesis.hostedWindows[.cava] else {
            return XCTFail("expected a skin-frame route")
        }
        XCTAssertEqual(frame.groupIdentifier, "wasabi.standardframe.statusbar")
    }

    // MARK: - The window carries the border

    func testTheWindowGrowsByTheBorderTheFrameDraws() throws {
        let loaded = try makeSkin(statusParam: "25,28,-40,-70", noStatusParam: "25,28,-40,-50")
        guard case .skinFrame(let frame) = loaded.surfaceSynthesis.hostedWindows[.cava] else {
            return XCTFail("expected a skin-frame route")
        }
        let definition = try XCTUnwrap(WinampModernHostedWindowRegistry.entry(id: .cava))
        let request = WinampModernHostedWindowInstantiation(definition: definition, frame: frame)
        // 25 left against 15 right and 28 top against 22 bottom: the symmetric border is 25 and 28,
        // so the client's own size plus 50x56.
        XCTAssertEqual(request.defaultSize,
                       CGSize(width: definition.defaultSize.width + 50,
                              height: definition.defaultSize.height + 56))
    }

    /// A frame that states no rect is left exactly where it was: the frame's own script places the
    /// client from `content=`, and the window is the registry's size. Every skin that ships an
    /// unparameterized standard frame is in this case.
    func testAFrameThatStatesNoRectIsUnchanged() throws {
        let loaded = try makeSkin(statusParam: nil, noStatusParam: nil)
        guard case .skinFrame(let frame) = loaded.surfaceSynthesis.hostedWindows[.cava] else {
            return XCTFail("expected a skin-frame route")
        }
        let definition = try XCTUnwrap(WinampModernHostedWindowRegistry.entry(id: .cava))
        let request = WinampModernHostedWindowInstantiation(definition: definition, frame: frame)
        XCTAssertEqual(request.defaultSize, definition.defaultSize)
        let nodes = WasabiSurfaceSynthesizer.frameNodes(
            frame: WasabiSurfaceSynthesizer.Frame(groupIdentifier: frame.groupIdentifier,
                                                  xuiTag: frame.xuiTag, hasArtwork: frame.hasArtwork,
                                                  exemplar: frame.exemplar,
                                                  scriptClient: frame.scriptClient),
            frameID: "f", contentGroupID: "c", componentName: "Cava",
            location: WalSourceLocation(path: "test"))
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.attribute("content"), "c")
    }

    // MARK: - The client is centred, and stays centred at runtime

    /// The rect we synthesize: our group placed at the symmetric border with the frame handed no
    /// `content=`, so the skin's script cannot put it back on one side.
    func testTheContentGroupIsCentredInTheBorder() throws {
        let loaded = try makeSkin(statusParam: "25,28,-40,-70", noStatusParam: "25,28,-40,-50")
        guard case .skinFrame(let frame) = loaded.surfaceSynthesis.hostedWindows[.cava] else {
            return XCTFail("expected a skin-frame route")
        }
        let nodes = WasabiSurfaceSynthesizer.frameNodes(
            frame: WasabiSurfaceSynthesizer.Frame(groupIdentifier: frame.groupIdentifier,
                                                  xuiTag: frame.xuiTag, hasArtwork: frame.hasArtwork,
                                                  exemplar: frame.exemplar,
                                                  scriptClient: frame.scriptClient),
            frameID: "f", contentGroupID: "c", componentName: "Cava",
            location: WalSourceLocation(path: "test"))
        XCTAssertEqual(nodes.count, 2)
        XCTAssertNil(nodes.first?.attribute("content"),
                     "a frame whose client we place ourselves is handed no content group to place")
        let group = try XCTUnwrap(nodes.last)
        XCTAssertEqual(group.attribute("id"), "c")
        XCTAssertEqual(group.attribute("x"), "25")
        XCTAssertEqual(group.attribute("y"), "28")
        XCTAssertEqual(group.attribute("w"), "-50")
        XCTAssertEqual(group.attribute("h"), "-56")
        XCTAssertEqual(group.attribute("relatw"), "1")
        XCTAssertEqual(group.attribute("relath"), "1")
    }

    /// The reporter's second screenshot, in one assertion: the runtime materializer builds its own
    /// `Frame` from the descriptor, and while that rebuild dropped the client rect the window was
    /// sized right and placed wrong.
    func testTheRuntimeMaterializerPlacesTheClientTheSameWay() throws {
        let loaded = try makeSkin(statusParam: "25,28,-40,-70", noStatusParam: "25,28,-40,-50")
        guard case .skinFrame(let frame) = loaded.surfaceSynthesis.hostedWindows[.cava] else {
            return XCTFail("expected a skin-frame route")
        }
        let definition = try XCTUnwrap(WinampModernHostedWindowRegistry.entry(id: .cava))
        let instantiate = try XCTUnwrap(loaded.runtime.instantiateHostedWindow)
        let root = try instantiate(WinampModernHostedWindowInstantiation(definition: definition,
                                                                        frame: frame))
        func find(_ object: WasabiObject, id: String) -> WasabiObject? {
            if object.xmlID == id { return object }
            for child in object.children {
                if let found = find(child, id: id) { return found }
            }
            return nil
        }
        let group = try XCTUnwrap(find(root, id: WinampModernHostedWindowID.cava.contentGroupIdentifier))
        XCTAssertEqual(group.attributes["x"], "25")
        XCTAssertEqual(group.attributes["y"], "28")
        XCTAssertEqual(group.attributes["w"], "-50")
        XCTAssertEqual(group.attributes["h"], "-56")
    }

    // MARK: - Fixture

    /// Two frame flavours, each with a script that builds a client area, differing only in what its
    /// `param` leaves of the window — HeadAMP's shape.
    private func makeSkin(statusParam: String?, noStatusParam: String?) throws
        -> WinampModernLoadedSkin {
        func script(_ param: String?) -> String {
            let attribute = param.map { #" param="\#($0)""# } ?? ""
            return #"<script file="scripts/standardframe.maki"\#(attribute)/>"#
        }
        let xml = """
        <WasabiXML>
          <groupdef id="wasabi.standardframe.statusbar" xuitag="Wasabi:StandardFrame:Status">
            <layer id="frame.art" x="0" y="0" w="0" h="8" relatw="1"/>
            \(script(statusParam))
          </groupdef>
          <groupdef id="wasabi.standardframe.nostatusbar" xuitag="Wasabi:StandardFrame:NoStatus">
            <layer id="frame.art.ns" x="0" y="0" w="0" h="8" relatw="1"/>
            \(script(noStatusParam))
          </groupdef>
          <container id="main">
            <layout id="normal" default_w="300" default_h="160">
              <windowholder hold="guid:pl" x="0" y="0" w="20" h="20"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB140Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B140-\(UUID().uuidString).wal")
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
