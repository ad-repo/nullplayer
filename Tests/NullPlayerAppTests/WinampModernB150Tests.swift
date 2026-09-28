import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B150 — a `<Menu>` entry's hover and pressed art is the entry's size when it states none.
///
/// winampmodern566 and The_Nokia_5220 write `<menu:button_hover id="File.hover.btn" x="0" y="0"/>`
/// into a groupdef that states only `h="16"`, and the art inside it is a three-slice cut to stretch
/// (`w="-7" relatw="1"`). Nothing sized the state object, so it resolved 0 wide and hovering or
/// pressing an entry drew nothing — `WasabiMenuBar.apply` swapped the visibility of an empty box.
final class WinampModernB150Tests: XCTestCase {

    private static let menuBar = """
    <WasabiXML>
      <elements>
        <bitmap id="txt.menu.file" file="file.png"/>
        <bitmap id="button.menu.hover.middle" file="file.png" x="0" y="0" w="4" h="16"/>
      </elements>
      <groupdef id="menu.button.hover" xuitag="menu:button_hover" h="16">
        <layer id="button.middle" image="button.menu.hover.middle" x="4" y="0" w="-7" relatw="1"/>
      </groupdef>
      <container id="main">
        <layout id="normal" w="400" h="200" default_w="400" default_h="200">
          <group id="menugroup.file" x="1" y="18" h="16" autowidthsource="File.txt">
            <menu:button_hover id="File.hover.btn" x="0" y="0" visible="0"/>
            <layer id="File.txt" image="txt.menu.file" x="0" y="0"/>
            <Menu id="File.menu" x="0" y="0" h="16" w="0" relatw="1" menu="WA5:File"
                  hover="File.hover.btn"/>
          </group>
        </layout>
      </container>
    </WasabiXML>
    """

    /// The defect: hovering shows the state object at the entry's size, and its stretched art with it.
    func testHoverArtFillsTheEntry() throws {
        let (graph, renderer) = try make(xml: Self.menuBar)
        let menu = try XCTUnwrap(graph.objects(xmlID: "File.menu").first)
        // Resolved once at rest first, as the window does, so the swap has to get past the memo.
        XCTAssertNil(frame(of: "File.hover.btn", in: renderer), "hidden at rest")
        XCTAssertTrue(WasabiMenuBar.apply(.hover, to: menu))
        let state = try XCTUnwrap(frame(of: "File.hover.btn", in: renderer))
        XCTAssertEqual(state.width, 31, accuracy: 0.001, "the entry is its 31px label wide")
        XCTAssertEqual(state.height, 16, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(frame(of: "button.middle", in: renderer)).width, 24, accuracy: 0.001,
                       "the three-slice middle stretches across the entry")
    }

    /// A state object that states its own width keeps it — Big Bento's are deliberately inset.
    func testADeclaredWidthIsKept() throws {
        let xml = Self.menuBar.replacingOccurrences(of: #"id="File.hover.btn" x="0""#,
                                                    with: #"id="File.hover.btn" x="0" w="20""#)
        let (graph, renderer) = try make(xml: xml)
        WasabiMenuBar.apply(.hover, to: try XCTUnwrap(graph.objects(xmlID: "File.menu").first))
        XCTAssertEqual(try XCTUnwrap(frame(of: "File.hover.btn", in: renderer)).width, 20, accuracy: 0.001)
    }

    /// The same group with no `<Menu>` naming it is not sized — the rule belongs to the entry.
    func testAnUnownedGroupIsNotSized() throws {
        let xml = Self.menuBar.replacingOccurrences(of: #"hover="File.hover.btn""#, with: "")
            .replacingOccurrences(of: #"id="File.hover.btn" x="0" y="0" visible="0""#,
                                  with: #"id="File.hover.btn" x="0" y="0""#)
        let (_, renderer) = try make(xml: xml)
        XCTAssertEqual(frame(of: "File.hover.btn", in: renderer)?.width ?? 0, 0, accuracy: 0.001)
    }

    // MARK: - Fixture

    private func frame(of id: String, in renderer: WasabiSceneRenderer) -> CGRect? {
        renderer.sceneNodes().first { $0.object.xmlID == id }?.frame
    }

    private func make(xml: String) throws -> (WasabiObjectGraph, WasabiSceneRenderer) {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return (loaded.runtime.graph, renderer)
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB150Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic.wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (name, payload) in [("skin.xml", Data(xml.utf8)), ("file.png", Self.labelPNG)] {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    /// A 31x16 opaque label, the size of winampmodern566's `txt.menu.file`.
    private static let labelPNG: Data = {
        let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 31, pixelsHigh: 16,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                              isPlanar: false, colorSpaceName: .deviceRGB,
                                              bytesPerRow: 31 * 4, bitsPerPixel: 32)!
        var components = [255, 255, 255, 255]
        for y in 0..<16 {
            for x in 0..<31 {
                representation.setPixel(&components, atX: x, y: y)
            }
        }
        return representation.representation(using: .png, properties: [:])!
    }()

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
