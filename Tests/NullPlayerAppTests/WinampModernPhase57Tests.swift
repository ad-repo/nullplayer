import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 57 — BB12, the seek bar drawn as a solid black bar.
///
/// Measured, not reasoned about: `WINAMP_MODERN_RENDER_PROBE=main/normal` on Big Bento Modern put a
/// `windowholder` at exactly the rect the black slab covered —
/// `HOLDERS main/normal: other@wdh.waveseeker(16, 123, 414, 34)` — sitting directly over the seek
/// bar's grid and progress fill. The holder declares `hold="none"`.
///
/// `none` is not an unknown component: it is Wasabi for *this holder holds nothing*. Reading it as a
/// GUID we do not recognize sent it down the `.other` branch, which fills the holder's rect with the
/// palette's content colour — an opaque slab over whatever the skin drew underneath. The skin ships
/// this holder for WACUP's integrated Waveform Seeker, a plugin we do not have, so the correct
/// outcome is that it draws nothing at all and the seek bar underneath shows.
///
/// The fix is deliberately narrow. `autoopen="0"` is on the same element and would also have
/// explained it, but that attribute is on real, wanted holders elsewhere in the corpus (micro's
/// playlist, Defix's SUI), so honouring *it* would have blanked surfaces that work today. `none` is
/// the unambiguous half, and across the installed corpus it appears on this element alone.
final class WinampModernPhase57Tests: XCTestCase {

    // MARK: - `none` holds nothing

    /// The holder is not a surface, so nothing draws it, nothing hit-tests it, and no host view is
    /// ever mounted into it.
    func testHoldNoneIsNotAComponentHolder() throws {
        let renderer = try makeRenderer(layout: """
        <windowholder id="wdh.waveseeker" hold="none" x="0" y="0" w="200" h="200"/>
        """)
        XCTAssertTrue(renderer.componentHolders().isEmpty)
        XCTAssertNil(renderer.componentHolder(at: CGPoint(x: 100, y: 100)))
    }

    /// The defect itself: the artwork beneath the holder must survive. A `.other` holder filled this
    /// whole rect with one flat colour, which is what turned Big Bento's seek bar into a black bar.
    func testHoldNoneDrawsNothingOverTheArtworkBeneathIt() throws {
        let covered = try renderPixel(at: CGPoint(x: 100, y: 100), layout: """
        <rect id="seek.bg" x="0" y="0" w="200" h="200" filled="1" color="0,200,0"/>
        <windowholder id="wdh.waveseeker" hold="none" x="0" y="0" w="200" h="200"/>
        """)
        XCTAssertEqual(covered.green, 200, "a holder that holds nothing must not paint")
        XCTAssertEqual(covered.red, 0)
        XCTAssertEqual(covered.blue, 0)
    }

    /// And the counter-measurement that makes the one above mean something: an *unknown* component
    /// still paints its inert surface, so the assertion is reading a real difference rather than a
    /// renderer that never fills a holder.
    func testAnUnrecognizedComponentStillPaintsOverTheSameArtwork() throws {
        let covered = try renderPixel(at: CGPoint(x: 100, y: 100), layout: """
        <rect id="seek.bg" x="0" y="0" w="200" h="200" filled="1" color="0,200,0"/>
        <windowholder id="mystery" hold="guid:{DEADBEEF-0000-0000-0000-000000000000}"
                      x="0" y="0" w="200" h="200"/>
        """)
        XCTAssertNotEqual(covered.green, 200, "an unknown component is still an inert filled surface")
    }

    /// `none` is a deliberate declaration, not a gap, so it must not be reported as a compatibility
    /// finding — otherwise every Bento variant carries a permanent warning about a plugin holder
    /// that is behaving exactly as intended.
    func testHoldNoneIsNotReportedAsAnUnknownComponent() throws {
        let loaded = try makeSkin(xml: Self.document(layout: """
        <windowholder id="wdh.waveseeker" hold="none" x="0" y="0" w="200" h="200"/>
        """))
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        _ = renderer.componentHolders()
        XCTAssertFalse(loaded.compatibilityReport.findings.contains {
            $0.code == WalDiagnosticCode.unknownComponent.rawValue
        })
    }

    /// An explicit `none` must also stop the *id* heuristic. That fallback exists for a holder that
    /// names no component at all (`centro.windowholder.library`); a holder that explicitly names
    /// nothing has answered the question already, and letting its id speak instead would hand it a
    /// library surface it never asked for.
    func testExplicitNoneBeatsTheHolderIdHeuristic() throws {
        XCTAssertEqual(WinampModernComponentRegistry.kindFromHolderIdentifier("centro.windowholder.library"),
                       .library, "the fallback this test is about must really be live")
        let renderer = try makeRenderer(layout: """
        <windowholder id="centro.windowholder.library" hold="none" x="0" y="0" w="200" h="200"/>
        """)
        XCTAssertTrue(renderer.componentHolders().isEmpty)
    }

    /// The third holder form reads its reference from `param`, and means the same thing by `none`.
    func testComponentParamNoneAlsoHoldsNothing() throws {
        let renderer = try makeRenderer(layout: """
        <component id="nothing" param="none" x="0" y="0" w="200" h="200"/>
        <componentbucket id="nothing.bucket" hold="NONE" x="0" y="0" w="200" h="200"/>
        """)
        XCTAssertTrue(renderer.componentHolders().isEmpty, "the match is case-insensitive")
    }

    /// A holder naming a component we *do* have is untouched by any of this.
    func testAKnownComponentIsStillAHolder() throws {
        let renderer = try makeRenderer(layout: """
        <component id="pl.content" param="guid:{45F3F7C1-A6F3-4ee6-A15E-125E92FC3F8D}"
                   x="0" y="0" w="200" h="200"/>
        """)
        XCTAssertEqual(renderer.componentHolders().map(\.kind), [.playlist])
    }

    // MARK: - Fixture

    private struct Pixel {
        let red: Int, green: Int, blue: Int
    }

    /// Render the scene and read one pixel back. Premultiplied-last RGBA, and every fixture here is
    /// fully opaque, so the channels are read directly.
    private func renderPixel(at point: CGPoint, layout: String) throws -> Pixel {
        let loaded = try makeSkin(xml: Self.document(layout: layout))
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost(),
                                               containerID: "Main", clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let width = 200, height = 200
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            // `drawText` ends in AppKit, which paints into the *current* NSGraphicsContext rather
            // than the CGContext it was handed (see the harness reference).
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            renderer.draw(in: context)
            NSGraphicsContext.current = previous
        }
        let index = (Int(point.y) * width + Int(point.x)) * 4
        return Pixel(red: Int(pixels[index]), green: Int(pixels[index + 1]), blue: Int(pixels[index + 2]))
    }

    private static func document(layout: String) -> String {
        """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="200" h="200">
        \(layout)
            </layout>
          </container>
        </WasabiXML>
        """
    }

    private func makeRenderer(layout: String) throws -> WasabiSceneRenderer {
        let loaded = try makeSkin(xml: Self.document(layout: layout))
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
            .appendingPathComponent("WinampModernPhase57Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        // A unique archive name gives each fixture its own `WinampModernConfiguration` namespace.
        let url = directory.appendingPathComponent("Phase57-\(UUID().uuidString).wal")
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
