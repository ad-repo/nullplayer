import AppKit
import XCTest
import ZIPFoundation
@testable import NullPlayer

/// A bitmap-font clock's colon has a cell of its own.
///
/// Reported live 2026-09-03 against the cPro skins: *"there is a space between the : and the seconds
/// in elapsed time"* — the readout drew `1:03: 16`. The ClassicPro engine draws its time with a
/// fixed-pitch atlas (`numfont.png`, `charwidth="15"`) whose colon is inked into only the leftmost
/// **6** columns of its 15px cell, and compensates on the object: `timecolonwidth="6"`. The Core Text
/// path had honoured that attribute since BB29 (`WasabiTextMetrics.clockRun`); the bitmap path
/// advanced every glyph by the full atlas cell and never read it, so the colon's nine unused columns
/// became a gap before the seconds.
///
/// The atlas here is the engine's own geometry — a 16×3 sheet of 15×31 cells, colon at row 1 column
/// 12 — with each glyph inked into a known sub-rectangle so the drawn run can be read back column by
/// column rather than eyeballed.
final class WinampModernBitmapClockTests: XCTestCase {

    /// The reported defect, in the geometry that produced it. `63:16` on a 15px atlas with a 6px
    /// colon puts the seconds at column 36; the full-cell advance put them at 45.
    func testTheColonAdvancesByItsOwnCellNotTheAtlasCell() throws {
        let scene = try makeScene(colon: #"timecolonwidth="6""#, seconds: 63 * 60 + 16)

        XCTAssertEqual(scene.inkColumns(), expectedColumns(for: "63:16", colon: 6),
                       "the colon takes its declared 6px and the seconds follow it directly")
    }

    /// Both colons of an `h:mm:ss` value, because the gap the report describes is *per colon* — a
    /// full-cell advance displaced the minutes as well as the seconds, and by twice as much.
    func testEveryColonInAnHoursValueTakesItsCell() throws {
        let scene = try makeScene(colon: #"timecolonwidth="6" timerhours="1""#,
                                  seconds: 3600 + 3 * 60 + 16)

        XCTAssertEqual(scene.inkColumns(), expectedColumns(for: "1:03:16", colon: 6),
                       "1:03:16, not 1:03: 16")
    }

    /// What a script laying out the total time beside the readout measures. A skin sizes its own
    /// boxes from `getTextWidth()`, so a measurement that kept the full-cell advance would put the
    /// separator nine pixels off whatever the readout now draws.
    func testTheMeasurementAgreesWithWhatIsDrawn() throws {
        let scene = try makeScene(colon: #"timecolonwidth="6""#, seconds: 63 * 60 + 16)

        XCTAssertEqual(scene.metrics.width(of: scene.clock, text: "63:16"), 15 + 15 + 6 + 15 + 15)
    }

    // MARK: - What must not change

    /// An atlas clock with no `timecolonwidth` keeps the fixed pitch it always had. The attribute is
    /// the skin's own statement about its sheet; absent, there is nothing to infer from.
    func testAnUndeclaredColonKeepsTheAtlasCell() throws {
        let scene = try makeScene(colon: "", seconds: 63 * 60 + 16)

        XCTAssertEqual(scene.inkColumns(), expectedColumns(for: "63:16", colon: 15))
        XCTAssertEqual(scene.metrics.width(of: scene.clock, text: "63:16"), 5 * 15)
    }

    /// Only a clock has fields, so only a clock reads the attribute — the same restriction
    /// `clockRun` puts on the Core Text path. A label that happens to carry both a colon and a stray
    /// `timecolonwidth` is still one fixed-pitch run.
    func testANonClockTextIgnoresTheAttribute() throws {
        let scene = try makeScene(colon: #"timecolonwidth="6""#, seconds: 0,
                                  display: #"text="63:16""#)

        XCTAssertEqual(scene.inkColumns(), expectedColumns(for: "63:16", colon: 15))
        XCTAssertNil(WasabiTextMetrics.bitmapColonWidth(of: scene.clock))
    }

    // MARK: - Fixture

    /// Where each glyph's ink lands when `text` is drawn from column 0 with a 15px atlas cell and a
    /// `colon`-wide colon cell. Every glyph is inked into columns 1…13 of its own cell and the colon
    /// into columns 1…4 of its (narrower) one, so the drawn run reads back as an exact column set.
    private func expectedColumns(for text: String, colon: Int) -> [Int] {
        var columns: Set<Int> = []
        var x = 0
        for character in text {
            let cell = character == ":" ? colon : 15
            let ink = character == ":" ? 1...4 : 1...13
            columns.formUnion(ink.map { x + $0 })
            x += cell
        }
        return columns.sorted()
    }

    private struct Scene {
        let renderer: WasabiSceneRenderer
        let metrics: WasabiTextMetrics
        let clock: WasabiObject

        /// The scene's lit columns. A column set rather than an extent: the defect is a *gap inside*
        /// the run, which an extent cannot see.
        func inkColumns() -> [Int] {
            let width = Int(renderer.canvasSize.width)
            let height = Int(renderer.canvasSize.height)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = pixels.withUnsafeMutableBytes { bytes in
                CGContext(data: bytes.baseAddress, width: width, height: height,
                          bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            }
            guard let context else { return [] }
            renderer.invalidateSceneCache()
            renderer.draw(in: context)
            var columns: Set<Int> = []
            for y in 0..<height {
                for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 { columns.insert(x) }
            }
            return columns.sorted()
        }
    }

    private func makeScene(colon: String, seconds: TimeInterval,
                           display: String = #"display="time""#) throws -> Scene {
        let xml = """
        <WasabiXML>
          <bitmap id="nums.source" file="numfont.png" x="0" y="0" w="240" h="93"/>
          <bitmapfont id="nums" file="nums.source" charwidth="15" charheight="31" hspacing="0"/>
          <container id="Main">
            <layout id="normal" w="200" h="40">
              <text id="clock" x="0" y="0" w="200" h="31" font="nums" valign="top" align="left" \(display) \(colon)/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let host = Host()
        host.currentTime = seconds
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let metrics = WasabiTextMetrics(loadedSkin: loaded)
        addTeardownBlock { metrics.teardown() }
        let object = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "clock").first)
        return Scene(renderer: renderer, metrics: metrics, clock: object)
    }

    /// The engine's sheet geometry, drawn as blocks: 16 columns of 15px by 3 rows of 31px, digits on
    /// row 1 columns 0…9 and the colon on row 1 column 12 — Winamp's fixed three-row glyph map, which
    /// is what `WasabiSceneRenderer` indexes the atlas by.
    private func makeAtlas() throws -> Data {
        let (width, height) = (240, 93)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        func fill(column: Int, ink: ClosedRange<Int>) {
            for y in 31..<62 {
                for x in ink {
                    let offset = (y * width + column * 15 + x) * 4
                    pixels.replaceSubrange(offset..<(offset + 4), with: [255, 255, 255, 255])
                }
            }
        }
        for digit in 0...9 { fill(column: digit, ink: 1...13) }
        fill(column: 12, ink: 1...4)
        let context = pixels.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        let image = try XCTUnwrap(context?.makeImage())
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png,
                                                                            properties: [:]))
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernBitmapClockTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("clock-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (name, payload) in [("skin.xml", Data(xml.utf8)), ("numfont.png", try makeAtlas())] {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
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
