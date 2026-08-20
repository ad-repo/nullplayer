import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 38 (backlog B4) — `valign=` on a text object.
///
/// Every string was drawn centred in its own box whatever the skin asked for. The corpus asks for
/// something else 63 times across 9 of the 17 measured skins — 54 of them `top` — and it is the
/// difference between Defix's songticker sitting on the top line of its display and floating in the
/// middle of it, and between multipass's bitmap-font readouts inside their LED windows and riding
/// the upper edge.
///
/// Two draw paths carry text and both had to move: the TrueType path (which centred) and the
/// bitmap-font sheet path (which was pinned to the box's top edge, i.e. `valign="top"` and nothing
/// else, including for the rows NullPlayer draws into a skin's own playlist).
final class WinampModernPhase38Tests: XCTestCase {
    // MARK: - The unit

    func testTheAttributeDecodes() {
        XCTAssertEqual(alignment(of: ["valign": "top"]), .top)
        XCTAssertEqual(alignment(of: ["valign": "TOP"]), .top)
        XCTAssertEqual(alignment(of: ["valign": "bottom"]), .bottom)
        XCTAssertEqual(alignment(of: ["valign": "center"]), .center)
    }

    /// Wasabi centres a string unless told otherwise, so anything unrecognised — and the far more
    /// common case of no attribute at all — has to land on `center`, not on the first case.
    func testAnythingElseCentres() {
        XCTAssertEqual(alignment(of: [:]), .center)
        XCTAssertEqual(alignment(of: ["valign": ""]), .center)
        XCTAssertEqual(alignment(of: ["valign": "middle"]), .center)
    }

    func testTheOffsetIsTheDistanceDownFromTheBoxTop() {
        XCTAssertEqual(WasabiTextMetrics.VerticalAlignment.top.offset(cell: 10, in: 30), 0)
        XCTAssertEqual(WasabiTextMetrics.VerticalAlignment.center.offset(cell: 10, in: 30), 10)
        XCTAssertEqual(WasabiTextMetrics.VerticalAlignment.bottom.offset(cell: 10, in: 30), 20)
    }

    /// A box exactly as tall as its own text places identically whatever it asks for — which is why
    /// this attribute is invisible in most skins and obvious in the few with tall displays.
    func testATightBoxPlacesTheSameThreeWays() {
        for alignment in [WasabiTextMetrics.VerticalAlignment.top, .center, .bottom] {
            XCTAssertEqual(alignment.offset(cell: 12, in: 12), 0)
        }
    }

    // MARK: - The TrueType path

    func testThreeAlignmentsDrawAtThreeHeights() throws {
        let scene = try makeScene(markup: """
              <text id="a" x="0" y="0" w="100" h="60" fontsize="12" color="255,255,255"
                    align="center" valign="top" text="Xy"/>
              <text id="b" x="100" y="0" w="100" h="60" fontsize="12" color="255,255,255"
                    align="center" valign="center" text="Xy"/>
              <text id="c" x="200" y="0" w="100" h="60" fontsize="12" color="255,255,255"
                    align="center" valign="bottom" text="Xy"/>
        """)
        let top = try XCTUnwrap(scene.textCentreY(inColumns: 0..<100))
        let centre = try XCTUnwrap(scene.textCentreY(inColumns: 100..<200))
        let bottom = try XCTUnwrap(scene.textCentreY(inColumns: 200..<300))

        XCTAssertLessThan(top, centre, "`top` sits above `center` in the box")
        XCTAssertLessThan(centre, bottom, "`bottom` sits below `center` in the box")
        XCTAssertEqual(centre, 30, accuracy: 4, "a centred string straddles the middle of its box")
    }

    func testTextWithNoValignDrawsWhereCenterDoes() throws {
        let scene = try makeScene(markup: """
              <text id="a" x="0" y="0" w="100" h="60" fontsize="12" color="255,255,255"
                    align="center" text="Xy"/>
              <text id="b" x="100" y="0" w="100" h="60" fontsize="12" color="255,255,255"
                    align="center" valign="center" text="Xy"/>
        """)
        let implied = try XCTUnwrap(scene.textCentreY(inColumns: 0..<100))
        let explicit = try XCTUnwrap(scene.textCentreY(inColumns: 100..<200))
        XCTAssertEqual(implied, explicit, accuracy: 0.001)
    }

    /// A string taller than its own box starts at the top rather than above it, whatever it asked
    /// for: the clamp that keeps an oversized readout's ascenders inside the window.
    func testAStringTallerThanItsBoxIsNotLiftedOutOfIt() throws {
        let scene = try makeScene(canvas: CGSize(width: 200, height: 40), markup: """
              <text id="a" x="0" y="0" w="100" h="20" fontsize="40" color="255,255,255"
                    align="center" valign="bottom" text="Xy"/>
              <text id="b" x="100" y="0" w="100" h="20" fontsize="40" color="255,255,255"
                    align="center" valign="top" text="Xy"/>
        """)
        let bottom = try XCTUnwrap(scene.textCentreY(inColumns: 0..<100))
        let top = try XCTUnwrap(scene.textCentreY(inColumns: 100..<200))
        XCTAssertEqual(bottom, top, accuracy: 0.001)
    }

    // MARK: - The bitmap-font path

    /// The sheet path drew every run at `frame.minY`. That is `valign="top"`, so the 54 declarations
    /// that ask for it were already right and every other bitmap-font readout in the corpus was one
    /// half-box too high.
    func testABitmapFontRunFollowsValignToo() throws {
        let scene = try makeScene(markup: """
              <text id="a" x="0" y="0" w="100" h="60" font="sheet" valign="top" text="a"/>
              <text id="b" x="100" y="0" w="100" h="60" font="sheet" text="a"/>
              <text id="c" x="200" y="0" w="100" h="60" font="sheet" valign="bottom" text="a"/>
        """, bitmapFont: true)
        let top = try XCTUnwrap(scene.textCentreY(inColumns: 0..<100))
        let implied = try XCTUnwrap(scene.textCentreY(inColumns: 100..<200))
        let bottom = try XCTUnwrap(scene.textCentreY(inColumns: 200..<300))

        XCTAssertEqual(top, 3, accuracy: 1, "a `top` run still sits on the box's top edge")
        XCTAssertEqual(implied, 30, accuracy: 2, "no attribute centres the run, as Wasabi does")
        XCTAssertEqual(bottom, 57, accuracy: 1, "a `bottom` run sits on the box's bottom edge")
    }

    // MARK: - Fixture

    private func alignment(of attributes: [String: String]) -> WasabiTextMetrics.VerticalAlignment {
        let graph = WasabiObjectGraph()
        let object = graph.makeObject(typeName: "text", attributes: attributes,
                                      source: WalSourceLocation(path: "test.xml", line: 1))
        return WasabiTextMetrics.verticalAlignment(of: object)
    }

    private struct Scene {
        let renderer: WasabiSceneRenderer

        /// The vertical centroid of the lit pixels in a column band, **in scene coordinates** — a
        /// distance down from the top of the layout, the same axis `valign` is measured on.
        func textCentreY(inColumns columns: Range<Int>) -> CGFloat? {
            let width = Int(renderer.canvasSize.width)
            let height = Int(renderer.canvasSize.height)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = pixels.withUnsafeMutableBytes { bytes in
                CGContext(data: bytes.baseAddress, width: width, height: height,
                          bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            }
            guard let context else { return nil }
            renderer.invalidateSceneCache()
            // `NSString.draw(in:)` needs an AppKit context to draw into; without one the TrueType
            // path silently paints nothing and every text measurement here reads empty.
            let saved = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            renderer.draw(in: context)
            NSGraphicsContext.current = saved
            var weighted: CGFloat = 0
            var count: CGFloat = 0
            for y in 0..<height {
                for x in columns where x < width && pixels[(y * width + x) * 4 + 3] > 8 {
                    // A row index is the scene's own y: the buffer is bottom-up and the renderer
                    // draws the scene top-down, and the two cancel.
                    weighted += CGFloat(y)
                    count += 1
                }
            }
            return count == 0 ? nil : weighted / count
        }
    }

    private func makeScene(canvas: CGSize = CGSize(width: 300, height: 60),
                           markup: String, bitmapFont: Bool = false) throws -> Scene {
        let font = bitmapFont
            ? #"<bitmapfont id="sheet" file="sheet.png" charwidth="6" charheight="6" hspacing="0"/>"#
            : ""
        let xml = """
        <WasabiXML>
          \(font)
          <container id="Main">
            <layout id="normal" w="\(Int(canvas.width))" h="\(Int(canvas.height))">
        \(markup)
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml,
                                                                                             sheet: bitmapFont))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return Scene(renderer: renderer)
    }

    private func makeArchive(xml: String, sheet: Bool) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase38Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase38-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        var files: [(String, Data)] = [("skin.xml", Data(xml.utf8))]
        // Three rows of 6×6 cells, all opaque: any glyph the run picks is a solid block, so the
        // centroid measures where the *run* was placed rather than which letter it drew.
        if sheet { files.append(("sheet.png", try makeWhitePNG(width: 6 * 30, height: 6 * 3))) }
        for (path, payload) in files {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    private func makeWhitePNG(width: Int, height: Int) throws -> Data {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 200
        var volume: Double = 0.5
        var balance: Double = 0
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
