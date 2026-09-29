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

    /// Tooltip art alongside the skin's own chrome is still the skin's frame: only a frame painted
    /// with nothing *but* tooltip art is refused.
    func testAFrameMixingTooltipArtWithItsOwnIsStillBorrowed() throws {
        let loaded = try makeSkin(gridPrefix: "cpro2.genframe", tooltipAccent: true)
        guard case .skinFrame = loaded.surfaceSynthesis.hostedWindows[.cava] else {
            return XCTFail("tooltip art beside the skin's own is still the skin's chrome")
        }
    }

    /// **Nothing wears tooltip art as its frame, the About page included.** With no other frame to
    /// lend, the skin's About page fills a window of NullPlayer's own glass chrome instead.
    func testAnAboutPageWearsNullPlayersChromeRatherThanATooltipFrame() throws {
        let loaded = try makeSkin(gridPrefix: "wasabi.tooltip", aboutPage: true)
        let id = WasabiSurfaceSynthesizer.aboutContainerIdentifier
        XCTAssertEqual(loaded.surfaceSynthesis.aboutContainer, id)
        let about = try XCTUnwrap(container(id, in: loaded))
        XCTAssertEqual(about.object.attributes[WinampModernContainerTopology.hostChromeAttribute], "1")

        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost(), containerID: id)
        addTeardownBlock { renderer.teardown() }
        XCTAssertFalse(renderer.sceneNodes().contains { isStandardFrame($0.object) },
                       "no tooltip frame is drawn around the page")
        XCTAssertTrue(renderer.sceneNodes().contains {
            $0.object.xmlID == WasabiSurfaceSynthesizer.aboutGroupIdentifier
        }, "the page itself is drawn")
    }

    /// A window the skin itself declares in a tooltip frame — engine `one`'s Widgets Manager — drops
    /// the frame and wears NullPlayer's chrome around the same content group.
    func testADeclaredWindowInATooltipFrameIsRehostedInNullPlayersChrome() throws {
        let loaded = try makeSkin(gridPrefix: "wasabi.tooltip", managerWindow: true)
        let manager = try XCTUnwrap(container("widgets.manager", in: loaded))
        XCTAssertEqual(manager.object.attributes[WinampModernContainerTopology.hostChromeAttribute], "1")

        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost(),
                                               containerID: "widgets.manager")
        addTeardownBlock { renderer.teardown() }
        XCTAssertFalse(renderer.sceneNodes().contains { isStandardFrame($0.object) })
        XCTAssertTrue(renderer.sceneNodes().contains { $0.object.xmlID == "manager.list" },
                      "the content group is still there, and a findObject still reaches it")
    }

    /// The same window in a frame painted with the skin's own art keeps that frame.
    func testADeclaredWindowInTheSkinsOwnFrameKeepsIt() throws {
        let loaded = try makeSkin(gridPrefix: "cpro2.genframe", managerWindow: true)
        let manager = try XCTUnwrap(container("widgets.manager", in: loaded))
        XCTAssertNil(manager.object.attributes[WinampModernContainerTopology.hostChromeAttribute])
    }

    private func container(_ id: String, in loaded: WinampModernLoadedSkin) -> WinampModernContainerInfo? {
        WinampModernContainerTopology.analyze(graph: loaded.runtime.graph).first { $0.id == id }
    }

    private func isStandardFrame(_ object: WasabiObject) -> Bool {
        object.typeName.lowercased().hasPrefix("wasabi:standardframe:")
    }

    // MARK: - Fixture

    /// ClassicPro's shape: the standard frame holds a `<group id="wasabi.frame.layout"/>` naming the
    /// groupdef that carries the art, beside a script that builds the client area.
    /// `tooltipAccent` adds one tooltip bitmap beside the grid; `aboutPage` defines the group the
    /// engine supplies as the skin's About page; `managerWindow` declares a window in the frame, the
    /// way the engine's Widgets Manager is.
    private func makeSkin(gridPrefix: String, tooltipAccent: Bool = false, aboutPage: Bool = false,
                          managerWindow: Bool = false) throws -> WinampModernLoadedSkin {
        let accent = tooltipAccent
            ? #"<layer image="wasabi.tooltip.top" x="0" y="0" w="0" h="2" relatw="1"/>"# : ""
        let about = aboutPage ? """
          <groupdef id="skin.about.group" w="0" h="0" relatw="1" relath="1">
            <layer id="about.bg" image="about.bg" x="0" y="0" w="371" h="321"/>
          </groupdef>
        """ : ""
        let manager = managerWindow ? """
          <groupdef id="widgets.manager.content">
            <group id="manager.list" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
          </groupdef>
          <container id="widgets.manager" name="Widgets Manager" default_visible="0">
            <layout id="normal" default_w="200" default_h="400">
              <Wasabi:StandardFrame:Status id="framewnd" content="widgets.manager.content" fitparent="1"/>
            </layout>
          </container>
        """ : ""
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
            \(accent)
          </groupdef>
        \(about)
        \(manager)
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

    private final class TestHost: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var spectrumLevels: [Float] = []

        func play() {}
        func pause() {}
        func stop() {}
        func previous() {}
        func next() {}
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
