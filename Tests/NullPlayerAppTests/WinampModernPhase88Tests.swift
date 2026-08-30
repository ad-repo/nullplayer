import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 88 — `sysregion` shapes the window (B76).
///
/// Half of the attribute was already implemented: `WasabiSceneRenderer.isRegionOnly` reads a negative
/// value and skips *painting* the layer, which is what stopped Ujola Cat's magenta mask drawing as
/// artwork. Nothing then consumed the silhouette, so it was discarded rather than subtracted and
/// every `Wasabi:StandardFrame:*` window kept the square corners `component.bg` paints — measured on
/// Shield_Amp as corner alpha **255** on `Pledit`, `MLibrary`, `AVS` and `Video` against **0** on the
/// hand-drawn `main` and `equalizer`, whose own artwork carries the rounded alpha.
///
/// Three properties of the composition are load-bearing, and each was found by a skin rather than
/// reasoned out:
///
/// 1. **It composites once, over the finished scene.** As a `CGContext` clip mask it is consulted by
///    every drawing operation instead, and fractional coverage then accumulates across overlapping
///    draws — 8451 pixels of winampmodern566's stacked player artwork moved that the region never
///    meant to touch.
/// 2. **Order decides the shape.** A positive `sysregion` adds back what a negative one took.
///    S7Reflex lays its config drawer *behind* the player in `main/normal`, and the drawer's two
///    350 and 251 px silhouettes are followed by the `player.main` group's `sysregion="1"` — so
///    subtracting every negative layer cut away the left third of the window (31,289 px, 16.6%).
/// 3. **The cut is binary.** Ebonite's frame strips are cut from the window's own *background
///    texture* at alpha 179; as coverage that left the border of every framed window at 30% opacity,
///    which reads as a rendering fault rather than as a shape.
final class WinampModernPhase88Tests: XCTestCase {

    /// The colour of the always-opaque background art, so a kept pixel is identifiable.
    private let background: [UInt8] = [255, 0, 0]

    // MARK: - The shape

    /// The base case, and Shield_Amp's in miniature: a full-bleed background with a silhouette over
    /// its corner. The corner goes, the rest stays, and the silhouette still paints nothing.
    func testNegativeSysregionCutsItsSilhouetteOutOfTheWindow() throws {
        let pixels = try render(layout: """
            <layer id="bg" image="art.opaque" x="0" y="0" w="16" h="16"/>
            <layer id="trim" image="art.opaque" x="0" y="0" w="4" h="4" sysregion="-2"/>
            """)

        XCTAssertEqual(alpha(pixels, x: 1, y: 1), 0, "the silhouette's own box must be cut away")
        XCTAssertEqual(alpha(pixels, x: 8, y: 8), 255, "the rest of the window must be untouched")
        assertColor(pixels, x: 8, y: 8, equals: background, "the background must still paint")
    }

    /// A skin that declares no negative `sysregion` keeps the rectangle it has always had. 672 of the
    /// corpus's 926 declarations are positive and most are ordinary painted artwork; composing a
    /// region from those alone would decide the shape of every skin that uses the attribute at all.
    func testPositiveSysregionAloneLeavesTheWindowRectangular() throws {
        let pixels = try render(layout: """
            <layer id="bg" image="art.opaque" x="0" y="0" w="16" h="16" sysregion="1"/>
            """)

        XCTAssertEqual(alpha(pixels, x: 0, y: 0), 255)
        XCTAssertEqual(alpha(pixels, x: 15, y: 15), 255)
    }

    /// S7Reflex's case: the object declared *after* the cut adds its box back. A model that merely
    /// subtracted every negative layer answers 0 here.
    func testALaterPositiveSysregionRestoresWhatANegativeOneCut() throws {
        let pixels = try render(layout: """
            <layer id="bg" image="art.opaque" x="0" y="0" w="16" h="16"/>
            <layer id="trim" image="art.opaque" x="0" y="0" w="8" h="8" sysregion="-2"/>
            <group id="restore" x="0" y="0" w="4" h="4" sysregion="1"/>
            """)

        XCTAssertEqual(alpha(pixels, x: 1, y: 1), 255, "the group must add its own box back")
        XCTAssertEqual(alpha(pixels, x: 6, y: 6), 0, "the rest of the cut must survive it")
    }

    /// Ebonite's case. `art.soft` is alpha 179 — as coverage it would leave 76 here.
    func testAPartiallyTransparentSilhouetteCutsCompletely() throws {
        let pixels = try render(layout: """
            <layer id="bg" image="art.opaque" x="0" y="0" w="16" h="16"/>
            <layer id="trim" image="art.soft" x="0" y="0" w="4" h="4" sysregion="-2"/>
            """)

        XCTAssertEqual(alpha(pixels, x: 1, y: 1), 0, "a region is a shape, not a translucency")
    }

    /// A silhouette below the threshold is not a shape either, so the window keeps its rect: the
    /// direction that cannot lose a window a skin meant to draw.
    func testASilhouetteBelowTheCoverageFloorCutsNothing() throws {
        let pixels = try render(layout: """
            <layer id="bg" image="art.opaque" x="0" y="0" w="16" h="16"/>
            <layer id="trim" image="art.faint" x="0" y="0" w="4" h="4" sysregion="-2"/>
            """)

        XCTAssertEqual(alpha(pixels, x: 1, y: 1), 255)
    }

    /// Anexa writes `sysregion="AND"` fifteen times. It has never painted and it must not shape
    /// anything either — the corpus's non-numeric forms are not a combining mode we can read.
    func testANonNumericSysregionShapesNothing() throws {
        let pixels = try render(layout: """
            <layer id="bg" image="art.opaque" x="0" y="0" w="16" h="16"/>
            <layer id="trim" image="art.opaque" x="0" y="0" w="4" h="4" sysregion="AND"/>
            """)

        XCTAssertEqual(alpha(pixels, x: 1, y: 1), 255)
    }

    // MARK: - The pointer

    /// An opaque window corner is still opaque to the pointer however carefully the renderer erased
    /// it, so the hit test has to answer from the same shape: a click on a trimmed corner falls
    /// through to whatever is behind the window.
    func testACutCornerTakesNoClick() throws {
        let renderer = try makeRenderer(layout: """
            <layer id="bg" image="art.opaque" x="0" y="0" w="16" h="16"/>
            <layer id="trim" image="art.opaque" x="0" y="0" w="4" h="4" sysregion="-2"/>
            """)
        defer { renderer.teardown() }

        XCTAssertFalse(renderer.containsRegionPixel(at: CGPoint(x: 1, y: 1)))
        XCTAssertNil(renderer.object(at: CGPoint(x: 1, y: 1), interactiveOnly: false))
        XCTAssertTrue(renderer.containsRegionPixel(at: CGPoint(x: 8, y: 8)))
        XCTAssertNotNil(renderer.object(at: CGPoint(x: 8, y: 8), interactiveOnly: false))
    }

    // MARK: - Harness

    /// 16×16, four 8×8 quadrants: opaque red (the artwork), opaque black, black at alpha 179
    /// (Ebonite's texture), black at alpha 32 (below the floor).
    private enum Quadrant {
        static let opaque = "0 0"
        static let soft = "8 0"
        static let faint = "0 8"
    }

    private func makeRenderer(layout: String) throws -> WasabiSceneRenderer {
        let xml = """
        <WasabiXML>
          <elements>
            <bitmap id="art.opaque" file="sheet.png" x="0" y="0" w="8" h="8"/>
            <bitmap id="art.soft" file="sheet.png" x="8" y="0" w="8" h="8"/>
            <bitmap id="art.faint" file="sheet.png" x="0" y="8" w="8" h="8"/>
          </elements>
          <container id="Main">
            <layout id="normal" w="16" h="16">
        \(layout)
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: RenderHost())
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 16, height: 16))
        return renderer
    }

    private func render(layout: String) throws -> [UInt8] {
        let renderer = try makeRenderer(layout: layout)
        defer { renderer.teardown() }
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 16, height: 16,
                                                  bitsPerComponent: 8, bytesPerRow: 16 * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            renderer.draw(in: context)
        }
        return pixels
    }

    /// `y` is measured from the top of the canvas, as the skin measures it; the backing store's first
    /// row is the top row, so no conversion is needed.
    private func alpha(_ pixels: [UInt8], x: Int, y: Int) -> UInt8 { pixels[(y * 16 + x) * 4 + 3] }

    private func assertColor(_ pixels: [UInt8], x: Int, y: Int, equals expected: [UInt8],
                             _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let offset = (y * 16 + x) * 4
        let actual = Array(pixels[offset..<(offset + 3)])
        XCTAssertEqual(actual, expected, "\(message) — at (\(x),\(y)) got \(actual)",
                       file: file, line: line)
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase88Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic.wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in [("skin.xml", Data(xml.utf8)), ("sheet.png", try makeQuadrantPNG())] {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    private func makeQuadrantPNG() throws -> Data {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        // Premultiplied: the colour components are scaled by the alpha they carry.
        func fill(originX: Int, originY: Int, red: UInt8, alpha: UInt8) {
            for row in originY..<(originY + 8) {
                for column in originX..<(originX + 8) {
                    let offset = (row * side + column) * 4
                    pixels[offset] = UInt8(Int(red) * Int(alpha) / 255)
                    pixels[offset + 3] = alpha
                }
            }
        }
        fill(originX: 0, originY: 0, red: 255, alpha: 255)   // art.opaque
        fill(originX: 8, originY: 0, red: 0, alpha: 179)     // art.soft — Ebonite's texture
        fill(originX: 0, originY: 8, red: 0, alpha: 32)      // art.faint — below the floor
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: side, height: side,
                                                  bitsPerComponent: 8, bytesPerRow: side * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
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
