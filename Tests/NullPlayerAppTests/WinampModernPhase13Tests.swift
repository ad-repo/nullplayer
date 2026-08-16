import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 13 — playlist, EQ, and library surfaces for `.wal` skins.
///
/// Step 13.0 first: a window dragged below its layout minimum used to *scramble* rather than cramp,
/// because a child whose parent is shorter than the child's own margins resolves to a negative box
/// and `WasabiRect.standardized` painted it flipped across its origin, on top of its siblings.
final class WinampModernPhase13Tests: XCTestCase {

    // MARK: - 13.0 Negative-size culling

    /// A negative box is dropped instead of being flipped over its siblings.
    func testNegativelySizedObjectIsCulledRatherThanFlipped() throws {
        let renderer = try makeRenderer(layout: """
        <layer id="short" x="0" y="100" w="0" h="6" relatw="1"/>
        <group id="host" x="0" y="100" w="0" h="6" relatw="1">
          <layer id="taller.than.parent" x="2" y="2" w="-4" h="-15" relatw="1" relath="1"/>
        </group>
        """)
        let ids = renderer.sceneNodes().compactMap(\.object.xmlID)
        XCTAssertTrue(ids.contains("host"), "the parent itself is a real 6px-tall box")
        XCTAssertFalse(ids.contains("taller.than.parent"),
                       "a child needing 15px more than its parent has must draw nothing")
        for node in renderer.sceneNodes() {
            XCTAssertGreaterThanOrEqual(node.frame.width, 0)
            XCTAssertGreaterThanOrEqual(node.frame.height, 0)
        }
    }

    /// Culling takes the subtree with it: descendants resolve against a box that does not exist.
    func testCullingANegativeBoxAlsoDropsItsChildren() throws {
        let renderer = try makeRenderer(layout: """
        <group id="collapsed" x="0" y="0" w="-10" h="20">
          <layer id="child.of.collapsed" x="0" y="0" w="8" h="8"/>
          <group id="deep">
            <layer id="grandchild" x="0" y="0" w="8" h="8"/>
          </group>
        </group>
        """)
        let ids = Set(renderer.sceneNodes().compactMap(\.object.xmlID))
        XCTAssertFalse(ids.contains("collapsed"))
        XCTAssertFalse(ids.contains("child.of.collapsed"))
        XCTAssertFalse(ids.contains("grandchild"))
    }

    /// Zero-sized objects keep their existing pass-through behaviour — only *negative* boxes are
    /// bogus. Skins park real content in 0×0 groups that size themselves from their children.
    func testZeroSizedObjectsAreStillWalked() throws {
        let renderer = try makeRenderer(layout: """
        <group id="zero" x="0" y="0" w="0" h="0">
          <layer id="child.of.zero" x="0" y="0" w="10" h="10"/>
        </group>
        """)
        let ids = Set(renderer.sceneNodes().compactMap(\.object.xmlID))
        XCTAssertTrue(ids.contains("zero"))
        XCTAssertTrue(ids.contains("child.of.zero"))
    }

    /// The R1 case end to end. cPro-Bento's declared minimum is *itself* degenerate: at 168px the
    /// SUI area (`h="-168" relath="1"`) is zero-tall, so its contents go negative. A shrunk window
    /// must cramp — every remaining node inside the canvas — never stack flipped boxes over the
    /// chrome. `resize` already clamps to the layout minimum, so this is the smallest real size.
    func testShrinkingToTheLayoutMinimumNeverPaintsOutsideTheCanvas() throws {
        let renderer = try makeRenderer(layout: """
        <layer id="header" x="0" y="0" w="0" h="80" relatw="1"/>
        <group id="body" x="0" y="80" w="0" h="-80" relatw="1" relath="1">
          <layer id="body.fill" x="2" y="2" w="-4" h="-4" relatw="1" relath="1"/>
        </group>
        """)
        XCTAssertTrue(Set(renderer.sceneNodes().compactMap(\.object.xmlID))
            .isSuperset(of: ["header", "body", "body.fill"]))

        let clamped = renderer.resize(to: CGSize(width: 10, height: 10))
        XCTAssertEqual(clamped, CGSize(width: 120, height: 80), "resize clamps to the layout minimum")
        let nodes = renderer.sceneNodes()
        let ids = Set(nodes.compactMap(\.object.xmlID))
        XCTAssertTrue(ids.contains("header"), "the header is still a valid 80px box")
        XCTAssertFalse(ids.contains("body.fill"), "4px of margin inside a zero-tall body is negative")
        let canvas = CGRect(origin: .zero, size: clamped)
        for node in nodes where !node.frame.isEmpty {
            XCTAssertTrue(canvas.intersects(node.frame),
                          "\(node.object.xmlID ?? node.object.typeName) escaped the canvas at \(node.frame)")
            XCTAssertGreaterThanOrEqual(node.frame.minY, 0, "a flipped box paints above the canvas")
        }
    }

    // MARK: - 13.0 Layout limits and restored-frame clamping

    /// The limits come from the layout the renderer is *showing*, not from a fixed constant.
    func testRendererExposesTheActiveLayoutLimits() throws {
        let renderer = try makeRenderer(layout: "<layer id=\"x\" x=\"0\" y=\"0\" w=\"4\" h=\"4\"/>")
        XCTAssertEqual(renderer.layoutMinimumSize, CGSize(width: 120, height: 80))
        XCTAssertEqual(renderer.layoutMaximumSize, CGSize(width: 16_384, height: 16_384),
                       "a layout with no maximum is bounded only by the renderer's own ceiling")
    }

    /// Each container carries its own minimum — an auxiliary playlist window is not bounded by the
    /// player's floor.
    func testContainersCarryTheirOwnMinimaAndMaxima() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" default_w="500" default_h="500" minimum_w="317" minimum_h="168"/>
          </container>
          <container id="Pledit" component="guid:{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D}">
            <layout id="normal" default_w="381" default_h="260" minimum_w="240" minimum_h="60"
                    maximum_w="900"/>
          </container>
        </WasabiXML>
        """)
        let containers = WinampModernContainerTopology.analyze(graph: loaded.runtime.graph)
        let main = try XCTUnwrap(containers.first { $0.id == "main" })
        let playlist = try XCTUnwrap(containers.first { $0.id == "Pledit" })
        XCTAssertEqual(main.defaultSize, CGSize(width: 500, height: 500))
        XCTAssertEqual(main.minimumSize, CGSize(width: 317, height: 168))
        XCTAssertNil(main.maximumSize, "no maximum_* means freely resizable")
        XCTAssertEqual(playlist.minimumSize, CGSize(width: 240, height: 60))
        XCTAssertEqual(playlist.maximumSize?.width, 900)
        XCTAssertEqual(playlist.maximumSize?.height, .greatestFiniteMagnitude,
                       "a maximum on one axis only leaves the other unbounded")
    }

    /// R1: a saved frame is honoured for position, never for a size the layout rejects. The saved
    /// top-left stays put, so a clamped window grows downward rather than jumping.
    func testRestoredFrameIsClampedToTheLayoutWhilePreservingTopLeft() {
        let minimum = NSSize(width: 317, height: 168)
        let maximum = NSSize(width: 16_384, height: 16_384)
        let saved = NSRect(x: 700, y: 400, width: 376, height: 100)
        let clamped = WinampModernMainWindowController.clamp(frame: saved, minimum: minimum, maximum: maximum)
        XCTAssertEqual(clamped.width, 376, "a width already above the minimum is left alone")
        XCTAssertEqual(clamped.height, 168)
        XCTAssertEqual(clamped.minX, saved.minX)
        XCTAssertEqual(clamped.maxY, saved.maxY, "the saved top edge is the anchor")

        let valid = NSRect(x: 10, y: 10, width: 500, height: 500)
        XCTAssertEqual(WinampModernMainWindowController.clamp(frame: valid, minimum: minimum, maximum: maximum),
                       valid, "a frame inside the limits is untouched")

        let huge = NSRect(x: 10, y: 10, width: 40_000, height: 40_000)
        let capped = WinampModernMainWindowController.clamp(frame: huge, minimum: minimum, maximum: maximum)
        XCTAssertEqual(capped.size, maximum)
    }

    /// UI Size multiplies the skin's pixel grid, so the limits scale with it at every level.
    func testLayoutLimitsScaleWithEveryUISizeLevel() throws {
        let renderer = try makeRenderer(layout: "<layer id=\"x\" x=\"0\" y=\"0\" w=\"4\" h=\"4\"/>")
        let minimum = renderer.layoutMinimumSize
        for level in UIScaleLevel.allCases {
            let scale = level.scaleFactor
            let scaled = NSSize(width: (minimum.width * scale).rounded(),
                                height: (minimum.height * scale).rounded())
            let saved = NSRect(x: 0, y: 1_000, width: 10, height: 10)
            let clamped = WinampModernMainWindowController.clamp(
                frame: saved, minimum: scaled,
                maximum: NSSize(width: 16_384 * scale, height: 16_384 * scale))
            XCTAssertEqual(clamped.size, scaled, "UI Size \(level) must clamp to its own scaled minimum")
            XCTAssertEqual(clamped.maxY, saved.maxY)
        }
    }

    // MARK: - Helpers

    private func makeRenderer(layout: String) throws -> WasabiSceneRenderer {
        let xml = """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="200" h="200" minimum_w="120" minimum_h="80">
        \(layout)
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try makeSkin(xml: xml)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase13Tests-\(UUID().uuidString)", isDirectory: true)
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
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
