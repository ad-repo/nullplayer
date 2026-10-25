import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B261 — H2O Liquid's Configuration window showed 2½ of its CPU-usage table's five rows.
///
/// Two faults on one table. The window: a `Wasabi:StandardFrame:Static` whose content groupdef fixes
/// itself at 350x235 sat in a 400x300 layout whose frame margins leave 345x200, so the window now
/// grows to give the content its declared minimum (`frameContentFittedSize`). The rows: the table
/// aligns its columns with literal tabs, which XML turns into blanks inside an attribute value; drawn
/// as tabs at Cocoa's stops, every row overran its box and wrapped.
final class WinampModernB261Tests: XCTestCase {

    func testAFramesContentMinimumGrowsTheWindowByTheFramesMargins() throws {
        let renderer = try makeRenderer(content: #"minimum_w="450" minimum_h="335""#)
        let content = try XCTUnwrap(renderer.sceneNodes().first { $0.object.xmlID == "cfg.content" })
        let margins = CGSize(width: 400 - content.frame.width, height: 300 - content.frame.height)
        let fitted = renderer.frameContentFittedSize(CGSize(width: 400, height: 300))
        XCTAssertEqual(fitted, CGSize(width: 450 + margins.width, height: 335 + margins.height))
    }

    /// Content that already has its room leaves the window exactly where its author sized it.
    func testContentThatFitsLeavesTheWindowAlone() throws {
        let renderer = try makeRenderer(content: #"minimum_w="100" minimum_h="100""#)
        XCTAssertEqual(renderer.frameContentFittedSize(CGSize(width: 400, height: 300)),
                       CGSize(width: 400, height: 300))
    }

    func testALiteralTabOrLineBreakInAnAttributeIsABlankButAReferenceIsNot() throws {
        let parsed = try WalLenientXMLParser().parse(
            "<text a=\"x\ty\r\nz\nw\" b=\"Equalizer&#09;Alt+G\"/>", path: "/t.xml")
        let node = try XCTUnwrap(parsed.roots.first)
        XCTAssertEqual(node.attribute("a"), "x y z w")
        XCTAssertEqual(node.attribute("b"), "Equalizer\tAlt+G")
    }

    // MARK: - Fixtures

    /// A frame the skin leaves to the host, so the content group is placed at `contentInset` and
    /// stretches with the canvas, as a frame script places it.
    private func makeRenderer(content attributes: String) throws -> WasabiSceneRenderer {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <groupdef id="cfg.content" \(attributes)>
            <layer id="body" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
          </groupdef>
          <container id="main">
            <layout id="normal" default_w="400" default_h="300">
              <Wasabi:StandardFrame:Static x="0" y="0" w="0" h="0" relatw="1" relath="1"
                                           content="cfg.content"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB261Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B261-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
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
