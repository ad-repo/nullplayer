import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B79 — a group whose `autowidthsource` names a **bitmap** label is as wide as that bitmap.
///
/// The renderer's `autoWidth` answered only for `<text>`, `<songticker>` and check boxes, so a source
/// that is a `<layer image=…>` answered nothing and the group resolved 0 wide. winampmodern566 and
/// The_Nokia_5220 build every titlebar menu that way — `<groupdef id="menugroup.file"
/// autowidthsource="File.txt">` over `<layer id="File.txt" image="txt.menu.file" x="0" y="0"/>` —
/// and the `<Menu w="0" relatw="1">` filling each group inherited the zero box, so no menu entry
/// could be clicked. The script's `getAutoWidth()` already answered the bitmap's width, which is how
/// `menualign.maki` spaced the labels correctly while every hit target stayed empty.
final class WinampModernB79Tests: XCTestCase {

    private static let menuBar = """
    <WasabiXML>
      <elements>
        <bitmap id="txt.menu.file" file="file.png"/>
      </elements>
      <container id="main">
        <layout id="normal" w="400" h="200" default_w="400" default_h="200">
          <group id="menugroup.file" x="1" y="18" h="16" autowidthsource="File.txt">
            <layer id="File.txt" image="txt.menu.file" x="0" y="0"/>
            <Menu id="File.menu" x="0" y="0" h="16" w="0" relatw="1" menu="WA5:File"/>
          </group>
        </layout>
      </container>
    </WasabiXML>
    """

    /// The defect: the group is its label's bitmap wide, and so is the menu entry that fills it.
    func testABitmapSourceSizesItsGroupToTheBitmap() throws {
        let (_, renderer) = try make(xml: Self.menuBar)
        XCTAssertEqual(try XCTUnwrap(frame(of: "menugroup.file", in: renderer)).width, 31, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(frame(of: "File.menu", in: renderer)).width, 31, accuracy: 0.001,
                       "the menu entry has a hit target the width of its label")
    }

    /// The drawn box and the script's `getAutoWidth()` stay one number.
    func testTheDrawnGroupAgreesWithGetAutoWidth() throws {
        let (runtime, renderer) = try make(xml: Self.menuBar)
        let group = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "menugroup.file").first)
        XCTAssertEqual(try XCTUnwrap(frame(of: "menugroup.file", in: renderer)).width,
                       CGFloat(runtime.autoWidth(of: group)), accuracy: 0.001)
    }

    /// A source with a declared width answers that width, not its bitmap's — the script's order.
    func testADeclaredWidthOutranksTheBitmap() throws {
        let xml = Self.menuBar.replacingOccurrences(of: #"image="txt.menu.file" x="0""#,
                                                    with: #"image="txt.menu.file" x="0" w="20""#)
        let (_, renderer) = try make(xml: xml)
        XCTAssertEqual(try XCTUnwrap(frame(of: "menugroup.file", in: renderer)).width, 20, accuracy: 0.001)
    }

    /// A source with no artwork at all still leaves the group collapsed.
    func testASourceWithNoArtworkLeavesTheGroupCollapsed() throws {
        let xml = Self.menuBar.replacingOccurrences(of: #"image="txt.menu.file""#,
                                                    with: #"image="never.declared""#)
        let (_, renderer) = try make(xml: xml)
        XCTAssertEqual(try XCTUnwrap(frame(of: "menugroup.file", in: renderer)).width, 0, accuracy: 0.001)
    }

    // MARK: - Fixture

    private func frame(of id: String, in renderer: WasabiSceneRenderer) -> CGRect? {
        renderer.sceneNodes().first { $0.object.xmlID == id }?.frame
    }

    private func make(xml: String) throws -> (WinampModernScriptRuntime, WasabiSceneRenderer) {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return (runtime, renderer)
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB79Tests-\(UUID().uuidString)", isDirectory: true)
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
