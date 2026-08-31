import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B87 — a `<text>`'s box bounds it vertically, but horizontally its **group** does.
///
/// A skin sizes its own boxes from the very measurement this renderer draws with, and then routinely
/// declares one narrower than the string it just measured. ClassicPro's SUI tab is the measured case:
/// `updateTabWidth` sets the tab to `label.getAutoWidth() + 14` around a
/// `<text x="6" w="-15" relatw="1">`, so the label's box is *always* `measurement - 1`, and its v2
/// engine is `getTextWidth() + 23` around `w="-26"`, three short. Scissored at its own rect, the last
/// glyph is cut through the middle: the five cPro skins' tab strip read `LIE PLE VII VIS BRO BPF NOV`
/// for `LIB PLE VID VIS BRO BPR NOW`.
///
/// The group is what actually bounds the string — the tab is 32 wide and hands its label only 17 of
/// them — so a non-scrolling string is clipped to the ambient clip horizontally and to its own rect
/// vertically. Two scissors had to move together: the context clip, and the rect handed to
/// `NSString.draw(in:)`, which cuts the layout at its own edge. Widening only the first changes
/// nothing at all, which is what makes this worth pinning.
final class WinampModernB87Tests: XCTestCase {

    /// The B87 shape itself: a box one pixel narrower than the string, inside a group with room.
    /// The ink has to reach past the box's right edge and stop at the group's.
    func testAStringWiderThanItsBoxIsBoundedByItsGroup() throws {
        let scene = try makeScene(markup: """
              <group id="holder" x="0" y="0" w="120" h="40">
                <text id="label" x="0" y="0" w="\(narrowBox)" h="40" fontsize="20"
                      color="255,255,255" text="\(word)"/>
              </group>
        """)
        let ink = try XCTUnwrap(scene.inkColumns())
        XCTAssertGreaterThan(ink.upperBound, CGFloat(narrowBox),
                             "the string reaches past the box the skin declared for it")
        XCTAssertLessThanOrEqual(ink.upperBound, 120, "and no further than the group that holds it")
    }

    /// The same string in the same box, with the group closed down around the box. The group is the
    /// bound, so here the cut comes back — this is what stops the fix from being "text never clips".
    func testTheGroupStillCuts() throws {
        let scene = try makeScene(markup: """
              <group id="holder" x="0" y="0" w="\(narrowBox)" h="40">
                <text id="label" x="0" y="0" w="\(narrowBox)" h="40" fontsize="20"
                      color="255,255,255" text="\(word)"/>
              </group>
        """)
        let ink = try XCTUnwrap(scene.inkColumns())
        XCTAssertLessThanOrEqual(ink.upperBound, CGFloat(narrowBox),
                                 "a group with no room to give still cuts the string at its edge")
    }

    /// A **scrolling** ticker keeps its own box on both axes: the motion is defined against that box,
    /// and a marquee let loose in its parent would smear across the whole panel. This is the case the
    /// fix must not touch.
    func testAScrollingTickerKeepsItsOwnBox() throws {
        let scene = try makeScene(markup: """
              <group id="holder" x="0" y="0" w="120" h="40">
                <text id="label" x="0" y="0" w="\(narrowBox)" h="40" fontsize="20" ticker="1"
                      color="255,255,255" text="\(word)"/>
              </group>
        """)
        let ink = try XCTUnwrap(scene.inkColumns())
        XCTAssertLessThanOrEqual(ink.upperBound, CGFloat(narrowBox),
                                 "a ticker is still scissored at the box its motion is defined by")
    }

    /// The box is only released horizontally. BB27's auto-height still decides whether a line draws
    /// at all, and a string must not bleed onto the row above or below it — a skin stacks readouts one
    /// box apart and shows them by moving their alphas.
    func testTheBoxStillBoundsTheStringVertically() throws {
        let scene = try makeScene(canvas: CGSize(width: 120, height: 60), markup: """
              <group id="holder" x="0" y="0" w="120" h="60">
                <text id="label" x="0" y="20" w="120" h="6" fontsize="30"
                      color="255,255,255" text="\(word)"/>
              </group>
        """)
        let rows = try XCTUnwrap(scene.inkRows())
        XCTAssertGreaterThanOrEqual(rows.lowerBound, 20, "nothing above the box")
        XCTAssertLessThanOrEqual(rows.upperBound, 26, "nothing below it")
    }

    /// A string that fits draws exactly where it did — the widened rect is only ever room, never a
    /// second alignment. Right- and centre-aligned text is where a rect grown the wrong way would
    /// show up, so both are measured against a box that needs no growing.
    func testAlignmentIsUnchangedForAStringThatFits() throws {
        let scene = try makeScene(canvas: CGSize(width: 300, height: 40), markup: """
              <text id="l" x="0"   y="0" w="100" h="40" fontsize="12" color="255,255,255"
                    align="left"   text="Xy"/>
              <text id="c" x="100" y="0" w="100" h="40" fontsize="12" color="255,255,255"
                    align="center" text="Xy"/>
              <text id="r" x="200" y="0" w="100" h="40" fontsize="12" color="255,255,255"
                    align="right"  text="Xy"/>
        """)
        let left = try XCTUnwrap(scene.inkColumns(in: 0..<100))
        let centre = try XCTUnwrap(scene.inkColumns(in: 100..<200))
        let right = try XCTUnwrap(scene.inkColumns(in: 200..<300))

        XCTAssertEqual(left.lowerBound, 0, accuracy: 2, "left-aligned starts at the box's left edge")
        XCTAssertEqual((centre.lowerBound + centre.upperBound) / 2, 150, accuracy: 2,
                       "centred straddles the middle of its box")
        XCTAssertEqual(right.upperBound, 300, accuracy: 2, "right-aligned ends at the box's right edge")
    }

    // MARK: - Fixture

    /// Wide enough that a 20px font cannot fit it, narrow enough to leave the group room to spare.
    private let narrowBox = 40
    private let word = "MMMMMM"

    private struct Scene {
        let renderer: WasabiSceneRenderer

        /// The horizontal extent of the lit pixels, in scene coordinates, within a column band.
        func inkColumns(in band: Range<Int>? = nil) -> ClosedRange<CGFloat>? {
            extent(band: band, horizontal: true)
        }

        /// The vertical extent of the lit pixels, in scene coordinates (a distance down from the top).
        func inkRows() -> ClosedRange<CGFloat>? {
            extent(band: nil, horizontal: false)
        }

        private func extent(band: Range<Int>?, horizontal: Bool) -> ClosedRange<CGFloat>? {
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
            // `NSString.draw(in:)` needs an AppKit context to draw into; without one the TrueType path
            // silently paints nothing and every measurement here reads empty.
            let saved = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            renderer.draw(in: context)
            NSGraphicsContext.current = saved
            var low = Int.max
            var high = Int.min
            let columns = band ?? 0..<width
            for y in 0..<height {
                for x in columns where x < width && pixels[(y * width + x) * 4 + 3] > 8 {
                    // A row index is the scene's own y: the buffer is bottom-up and the renderer draws
                    // the scene top-down, and the two cancel.
                    let value = horizontal ? x : y
                    low = min(low, value)
                    high = max(high, value + (horizontal ? 1 : 0))
                }
            }
            guard low <= high else { return nil }
            return CGFloat(low)...CGFloat(high)
        }
    }

    private func makeScene(canvas: CGSize = CGSize(width: 120, height: 40),
                           markup: String) throws -> Scene {
        let xml = """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="\(Int(canvas.width))" h="\(Int(canvas.height))">
        \(markup)
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return Scene(renderer: renderer)
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB87Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B87-\(UUID().uuidString).wal")
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
