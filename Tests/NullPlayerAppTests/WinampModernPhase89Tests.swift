import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 89 — `resize="…"` handles (B77).
///
/// Wasabi's resize model is markup-driven. A `.wal` window is borderless, so there is no chrome the
/// window server would stretch it by; the skin nominates the handles itself by hanging `resize=` on
/// the layers that draw its border, and the shared `standardframe` include declares nine of them —
/// the whole 30-odd-pixel frame of a playlist or library window, plus two corner grips. The attribute
/// was read by nothing, so the only affordance left was AppKit's own borderless edge band, about a
/// pixel of it: reported live 2026-08-30 on Shield_Amp as a window that could barely be grabbed.
///
/// The rule is **topmost wins, with no special pleading**, because that is exactly how the skins
/// express their exceptions: `standardframe.xml` lays a bare `<layer id="window.resize.disabler">`
/// over the interior *after* the border layers ("prevents it from covering Buttons", says its own
/// comment), declares the corner grips after that again, and puts its close button on the top strip
/// above all of them. None of those names appears in the implementation.
final class WinampModernPhase89Tests: XCTestCase {

    // MARK: - The attribute

    func testEveryEdgeNameParsesToItsEdges() {
        XCTAssertEqual(WasabiResizeEdges(attribute: "left"), .left)
        XCTAssertEqual(WasabiResizeEdges(attribute: "right"), .right)
        XCTAssertEqual(WasabiResizeEdges(attribute: "top"), .top)
        XCTAssertEqual(WasabiResizeEdges(attribute: "bottom"), .bottom)
        XCTAssertEqual(WasabiResizeEdges(attribute: "topleft"), [.top, .left])
        XCTAssertEqual(WasabiResizeEdges(attribute: "topright"), [.top, .right])
        XCTAssertEqual(WasabiResizeEdges(attribute: "bottomleft"), [.bottom, .left])
        XCTAssertEqual(WasabiResizeEdges(attribute: "BottomRight"), [.bottom, .right])
    }

    /// `resize="0"` and `resize="1"` are a different attribute of the same name — `<sendparams>` uses
    /// the first 55 times in the corpus and `<groupdef>` the second 6 — and neither names an edge. A
    /// flag read as a handle would resize the window from the middle of a group.
    func testTheFlagFormIsNotAHandle() {
        XCTAssertNil(WasabiResizeEdges(attribute: "0"))
        XCTAssertNil(WasabiResizeEdges(attribute: "1"))
        XCTAssertNil(WasabiResizeEdges(attribute: ""))
        XCTAssertNil(WasabiResizeEdges(attribute: nil))
    }

    // MARK: - The hit test

    /// The base case: a border strip on a layout the skin gave a resize range answers its edge.
    func testABorderStripIsAHandle() throws {
        let renderer = try makeRenderer(resizable: true, layout: """
            <layer id="bg" image="art" x="0" y="0" w="32" h="32"/>
            <layer id="edge.left" image="art" x="0" y="0" w="6" h="32" resize="left"/>
            """)
        defer { renderer.teardown() }

        XCTAssertEqual(renderer.resizeEdges(at: CGPoint(x: 2, y: 16)), .left)
        XCTAssertNil(renderer.resizeEdges(at: CGPoint(x: 20, y: 16)), "the middle is not a handle")
    }

    /// A layout that declares no resize range at all is fixed, whatever its borders say — Winamp gives
    /// its window no affordance either, and Shield_Amp's own player is one: `player-main.xml` declares
    /// no `minimum_*`/`maximum_*` while inheriting border layers that do declare handles.
    func testAFixedLayoutHasNoHandles() throws {
        let renderer = try makeRenderer(resizable: false, layout: """
            <layer id="bg" image="art" x="0" y="0" w="32" h="32"/>
            <layer id="edge.left" image="art" x="0" y="0" w="6" h="32" resize="left"/>
            """)
        defer { renderer.teardown() }

        XCTAssertNil(renderer.resizeEdges(at: CGPoint(x: 2, y: 16)))
    }

    /// `window.resize.disabler`: a bare layer laid over the interior after the border layers, which is
    /// how every `standardframe` keeps its strips off the buttons underneath. Nothing knows its name —
    /// it wins by being declared later.
    func testAnInteriorLayerDeclaredLaterShadowsTheHandle() throws {
        let renderer = try makeRenderer(resizable: true, layout: """
            <layer id="bg" image="art" x="0" y="0" w="32" h="32"/>
            <layer id="edge.top" image="art" x="0" y="0" w="32" h="10" resize="top"/>
            <layer id="window.resize.disabler" x="4" y="4" w="24" h="24"/>
            """)
        defer { renderer.teardown() }

        XCTAssertEqual(renderer.resizeEdges(at: CGPoint(x: 16, y: 2)), .top, "the strip above it stays")
        XCTAssertNil(renderer.resizeEdges(at: CGPoint(x: 16, y: 6)),
                     "the disabler covers the rest of the strip")
    }

    /// The corner grips are declared after the disabler, so they come back out from under it. Same
    /// rule, opposite direction — and the case that stops the rule being "an interior layer always
    /// wins".
    func testAGripDeclaredAfterTheDisablerWins() throws {
        let renderer = try makeRenderer(resizable: true, layout: """
            <layer id="bg" image="art" x="0" y="0" w="32" h="32"/>
            <layer id="edge.bottom" image="art" x="0" y="22" w="32" h="10" resize="bottom"/>
            <layer id="window.resize.disabler" x="4" y="4" w="24" h="24"/>
            <layer id="gripright" image="art" x="24" y="24" w="6" h="6" resize="bottomright"/>
            """)
        defer { renderer.teardown() }

        XCTAssertEqual(renderer.resizeEdges(at: CGPoint(x: 26, y: 26)), [.bottom, .right])
    }

    /// A control on the strip is a control. Shield_Amp's close button sits on the top border at
    /// `x="-35" y="2"`, and a handle that swallowed it would leave the window unclosable.
    func testAButtonOnTheStripIsNotAHandle() throws {
        let renderer = try makeRenderer(resizable: true, layout: """
            <layer id="bg" image="art" x="0" y="0" w="32" h="32"/>
            <layer id="edge.top" image="art" x="0" y="0" w="32" h="10" resize="top"/>
            <button id="close" action="CLOSE" image="art" x="24" y="2" w="6" h="6"/>
            """)
        defer { renderer.teardown() }

        XCTAssertNil(renderer.resizeEdges(at: CGPoint(x: 26, y: 4)))
        XCTAssertEqual(renderer.resizeEdges(at: CGPoint(x: 4, y: 4)), .top, "the rest of the strip stays")
    }

    // MARK: - The geometry

    private let limits = (minimum: NSSize(width: 100, height: 80),
                          maximum: NSSize(width: 400, height: 300))

    /// The far edges: the origin never moves, because the corner they are measured from is the one
    /// AppKit already anchors to.
    func testDraggingRightAndBottomKeepsTheirOppositeCorners() {
        let start = NSRect(x: 50, y: 60, width: 200, height: 150)
        let wider = WinampModernMainView.resizedFrame(from: start, edges: .right, deltaX: 40, deltaY: 0,
                                                      minimum: limits.minimum, maximum: limits.maximum)
        XCTAssertEqual(wider, NSRect(x: 50, y: 60, width: 240, height: 150))

        // The skin's `bottom` is the frame's minY: dragging it down grows the window downward.
        let taller = WinampModernMainView.resizedFrame(from: start, edges: .bottom, deltaX: 0, deltaY: -30,
                                                       minimum: limits.minimum, maximum: limits.maximum)
        XCTAssertEqual(taller, NSRect(x: 50, y: 30, width: 200, height: 180))
    }

    /// The near edges move the origin, so the corner the user is not dragging stays put.
    func testDraggingTheTopLeftCornerAnchorsTheBottomRight() {
        let start = NSRect(x: 50, y: 60, width: 200, height: 150)
        let frame = WinampModernMainView.resizedFrame(from: start, edges: [.top, .left],
                                                      deltaX: -20, deltaY: 25,
                                                      minimum: limits.minimum, maximum: limits.maximum)
        XCTAssertEqual(frame, NSRect(x: 30, y: 60, width: 220, height: 175))
        XCTAssertEqual(frame.maxX, start.maxX)
        XCTAssertEqual(frame.origin.y, start.origin.y)
    }

    /// The clamp lands on the size *before* the origin is derived from it. Clamping the finished frame
    /// instead leaves the origin where the unclamped drag put it, and the window walks off across the
    /// desktop while the pointer keeps pushing past the layout's minimum.
    func testAWindowAtItsMinimumStopsMovingWithThePointer() {
        let start = NSRect(x: 50, y: 60, width: 200, height: 150)
        let atMinimum = WinampModernMainView.resizedFrame(from: start, edges: [.left, .bottom],
                                                          deltaX: 300, deltaY: 300,
                                                          minimum: limits.minimum, maximum: limits.maximum)
        let pastIt = WinampModernMainView.resizedFrame(from: start, edges: [.left, .bottom],
                                                       deltaX: 900, deltaY: 900,
                                                       minimum: limits.minimum, maximum: limits.maximum)
        XCTAssertEqual(atMinimum.size, limits.minimum)
        XCTAssertEqual(atMinimum, pastIt, "the frame must not keep moving once the size is pinned")
        XCTAssertEqual(atMinimum.maxX, start.maxX, "the anchored corner stays anchored")
        XCTAssertEqual(atMinimum.maxY, start.maxY)
    }

    func testTheMaximumIsClampedTheSameWay() {
        let start = NSRect(x: 50, y: 60, width: 200, height: 150)
        let frame = WinampModernMainView.resizedFrame(from: start, edges: [.right, .top],
                                                      deltaX: 900, deltaY: 900,
                                                      minimum: limits.minimum, maximum: limits.maximum)
        XCTAssertEqual(frame.size, limits.maximum)
        XCTAssertEqual(frame.origin, start.origin)
    }

    // MARK: - Harness

    /// `resizable` decides whether the layout declares a range at all — the switch
    /// `WasabiSceneRenderer.layoutIsUserResizable` reads.
    private func makeRenderer(resizable: Bool, layout: String) throws -> WasabiSceneRenderer {
        let range = resizable ? #"minimum_w="16" minimum_h="16" maximum_w="320" maximum_h="320""# : ""
        let xml = """
        <WasabiXML>
          <elements>
            <bitmap id="art" file="sheet.png" x="0" y="0" w="8" h="8"/>
          </elements>
          <container id="Main">
            <layout id="normal" w="32" h="32" \(range)>
        \(layout)
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: RenderHost())
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 32, height: 32))
        XCTAssertEqual(renderer.layoutIsUserResizable, resizable)
        return renderer
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase89Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic.wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in [("skin.xml", Data(xml.utf8)), ("sheet.png", try makeOpaquePNG())] {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    /// One 8×8 opaque tile: every layer that draws needs artwork the alpha-based hit test accepts.
    private func makeOpaquePNG() throws -> Data {
        let side = 8
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: side, height: side,
                                                  bitsPerComponent: 8, bytesPerRow: side * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private final class RenderHost: WinampModernHost {
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
