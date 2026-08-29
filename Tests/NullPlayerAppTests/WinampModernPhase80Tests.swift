import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 80 — `<Wasabi:TitleBox>`, and the window menu a skin can leave ambiguous.
///
/// Reported live against Bio-Nid: "the important window is empty and the eq's are little spiders
/// that dont seem to do anything". Two separate findings behind one report.
///
/// **The title box.** Bio-Nid's `IMPORTANT` container is one `<Wasabi:TitleBox>` wrapping the
/// desktop-alpha toggle the window exists to show. A title box names its body by group id the way a
/// standard frame does, and in Winamp the standard library supplies the object that instantiates it.
/// We had neither half, so the tag drew nothing *and* its content group never entered the graph —
/// the window measured as 19 nodes of frame with a hole in the middle. Measured reach across the 35
/// installed skins: 9 skins, 33 declarations, and **no** skin ships a `wasabi.titlebox.*` bitmap
/// because the artwork is Winamp's.
///
/// **The spiders.** Not a defect in them: they are decorative desktop spiders, and Bio-Nid declares
/// eight of them by copying its equalizer container and leaving `name="Equalizer"` on every copy. The
/// menu showed eight identical items, none of which was the equalizer — that one is routed to its own
/// surface and is never in this list at all.
final class WinampModernPhase80Tests: XCTestCase {

    // MARK: - The body a title box names

    /// The whole defect in one assertion: the content group has to be *in the graph*, beneath the
    /// box. Before this it was absent, so nothing downstream — layout, hit testing, scripts — had
    /// anything to work with.
    func testATitleBoxInstantiatesTheGroupItNames() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="200" h="120" default_w="200" default_h="120">
          <Wasabi:TitleBox id="box" x="0" y="0" w="180" h="100"
                           title="Smooth Skin" content="dtabox.content"/>
        </layout>
        """, groups: """
        <groupdef id="dtabox.content">
          <layer id="knob" x="0" y="0" w="20" h="20"/>
        </groupdef>
        """)
        let graph = renderer.loadedSkin.runtime.graph
        let box = try XCTUnwrap(graph.objects(xmlID: "box").first)
        let body = try XCTUnwrap(box.children.first)

        XCTAssertEqual(body.xmlID, "dtabox.content", "the box's body is the group it names")
        XCTAssertEqual(body.children.count, 1, "and the body's own objects come with it")
        XCTAssertEqual(body.children.first?.xmlID, "knob")
    }

    /// The body sits clear of the border and below the title. The inset is calibrated, not invented:
    /// Shield_Amp and Itemskin both wrap one 20px row in `h="40"` with the row at `y="0"`.
    func testTheBodyIsInsetClearOfTheBorderAndTheTitle() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="200" h="120" default_w="200" default_h="120">
          <Wasabi:TitleBox id="box" x="10" y="5" w="180" h="100" content="dtabox.content"/>
        </layout>
        """, groups: """
        <groupdef id="dtabox.content">
          <layer id="knob" x="0" y="0" w="20" h="20"/>
        </groupdef>
        """)

        let box = try XCTUnwrap(frame(of: "box", in: renderer))
        let body = try XCTUnwrap(frame(of: "dtabox.content", in: renderer))
        XCTAssertEqual(body.minX, box.minX + WasabiTitleBox.contentInset.x)
        XCTAssertEqual(body.minY, box.minY + WasabiTitleBox.contentInset.y)
        XCTAssertEqual(body.width, box.width + WasabiTitleBox.contentInset.width)
        XCTAssertEqual(body.height, box.height + WasabiTitleBox.contentInset.height)
        XCTAssertGreaterThan(body.minY, box.minY + WasabiTitleBox.titleHeight,
                             "the body must start below the label, not under it")
    }

    /// Enkera declares two title boxes as bare labelled frames around objects placed beside them.
    /// A box with nothing to instantiate must still be a box, not a load failure.
    func testATitleBoxWithNoContentIsStillABox() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="200" h="120" default_w="200" default_h="120">
          <Wasabi:TitleBox id="box" x="0" y="0" w="180" h="100" title="Button Selection"/>
        </layout>
        """, groups: "")
        let box = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "box").first)

        XCTAssertTrue(box.children.isEmpty)
        XCTAssertEqual(WasabiTitleBox.title(of: box), "Button Selection")
    }

    /// Skins pad the title for artwork we do not have — Bio-Nid's begins with a space, which would
    /// otherwise indent the label past its own border.
    func testTheTitleIsTrimmedOfTheSkinsPadding() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="200" h="120" default_w="200" default_h="120">
          <Wasabi:TitleBox id="box" x="0" y="0" w="180" h="100"
                           title=" THIS BUTTON MUST BE TURNED ON FOR GRAPHICS SMOOTHING "/>
        </layout>
        """, groups: "")
        let box = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "box").first)

        XCTAssertEqual(WasabiTitleBox.title(of: box),
                       "THIS BUTTON MUST BE TURNED ON FOR GRAPHICS SMOOTHING")
    }

    /// The tag has to *resolve*. An unclaimed XUI tag warns and drops, and a skin that inherits from
    /// `wasabi.titlebox` would then lose whatever it derived.
    func testTheStandardLibrarySuppliesTheTagAndTheBase() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="200" h="120" default_w="200" default_h="120">
          <Wasabi:TitleBox id="box" x="0" y="0" w="180" h="100" title="Effects"/>
        </layout>
        """, groups: "")

        let unresolved: [String] = renderer.loadedSkin.runtime.diagnostics
            .map(\WalDiagnostic.message)
            .filter { $0.lowercased().contains("titlebox") }
        XCTAssertTrue(unresolved.isEmpty,
                      "the standard library supplies wasabi.titlebox: \(unresolved)")
    }

    // MARK: - What the box draws

    /// No `.wal` ships title-box artwork, so the renderer draws the border and the label — the same
    /// deliberate exception as `<Wasabi:Button text="…">`. The box's own `color=` is what it uses;
    /// Bio-Nid and Core-X5 both state one.
    func testTheBoxDrawsItsBorderInItsDeclaredColour() throws {
        let pixels = try render(xml: """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="16" h="16">
              <Wasabi:TitleBox id="box" x="0" y="0" w="16" h="16" color="0,255,0"/>
            </layout>
          </container>
        </WasabiXML>
        """, size: CGSize(width: 16, height: 16))

        // The border's top edge sits one row below the label band; its left edge is column 0.
        let border = colour(pixels, x: 0, y: Int(WasabiTitleBox.titleHeight) + 2)
        XCTAssertGreaterThan(border[1], border[0], "the border takes the declared green")
        XCTAssertGreaterThan(border[1], border[2])
        XCTAssertEqual(colour(pixels, x: 8, y: 4), [0, 0, 0],
                       "nothing is painted over the label band when there is no title")
        XCTAssertEqual(colour(pixels, x: 8, y: 14), [0, 0, 0],
                       "the box is an outline, not a fill — the body draws inside it")
    }

    // MARK: - The window menu

    /// Bio-Nid's eight spiders. The container id is the only thing that tells them apart.
    func testDuplicateWindowNamesAreQualifiedByContainerID() {
        let labels = WinampModernContainerTopology.menuLabels(forWindowNames: [
            (id: "spider1", name: "Equalizer"),
            (id: "spider2", name: "Equalizer"),
            (id: "Message", name: "IMPORTANT"),
        ])

        XCTAssertEqual(labels, ["Equalizer (spider1)", "Equalizer (spider2)", "IMPORTANT"])
    }

    /// The skin's own wording is the label wherever it says something unambiguous. Qualifying every
    /// window would make every other skin's menu worse to fix one skin's.
    func testUniqueWindowNamesAreLeftExactlyAsTheSkinWroteThem() {
        let labels = WinampModernContainerTopology.menuLabels(forWindowNames: [
            (id: "Config", name: "Skin Settings"),
            (id: "SPEAKER1", name: "SPEAKER 1"),
        ])

        XCTAssertEqual(labels, ["Skin Settings", "SPEAKER 1"])
    }

    // MARK: - Helpers

    private func frame(of id: String, in renderer: WasabiSceneRenderer) -> CGRect? {
        renderer.sceneNodes().first { $0.object.xmlID == id }?.frame
    }

    private func colour(_ pixels: [UInt8], x: Int, y: Int) -> [UInt8] {
        let offset = (y * 16 + x) * 4
        return Array(pixels[offset..<(offset + 3)])
    }

    private func render(xml: String, size: CGSize) throws -> [UInt8] {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }

        let width = Int(size.width)
        let height = Int(size.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            renderer.draw(in: context)
        }
        return pixels
    }

    private func makeRenderer(layout: String, groups: String) throws -> WasabiSceneRenderer {
        let url = try makeArchive(xml: """
        <WasabiXML>
          \(groups)
          <container id="main">
            \(layout)
          </container>
        </WasabiXML>
        """)
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase80Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic.wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        return url
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
        func seek(to time: TimeInterval) {}
        func setVolume(_ volume: Double) {}
        func toggleShuffle() {}
        func toggleRepeat() {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
