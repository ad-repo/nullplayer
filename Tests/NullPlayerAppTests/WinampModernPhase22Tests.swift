import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 22 — a `<vis>` box is painted in the colours and opacity the skin asks for.
///
/// Reported from a live Rika run: "spectrum visualization plays over the display". Rika sits its
/// `<vis>` on top of its own artwork and asks for `colorallbands="0,0,0"` at `alpha="50"` — a dark
/// shading. We read only the per-band `colorband1`…`colorband16` form, defaulted to **white**, and
/// ignored the object's `alpha` (only bitmap drawing honoured it), so the skin got bright white bars
/// straight across its song title and time. T800 (`colorallbands="145,17,54"`), micro and Anexa
/// declare their analyzers the same way.
final class WinampModernPhase22Tests: XCTestCase {
    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .playing
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var trackDisplayTitle = ""
        var bitrateKbps = 0
        var sampleRateHz = 0
        var channelCount = 2
        /// Every band at full scale, so a bar covers its whole column and a sampled pixel is the
        /// band's colour and nothing else.
        var spectrumLevels: [Float] = Array(repeating: 1, count: 16)
        /// B73 — the analyzer's input is the host's own FFT now, not `spectrumLevels`. A stub host
        /// has no tap, so it answers from the levels this test sets. See `analyzerTestBands`.
        func analyzerBands(count: Int) -> [CGFloat] {
            analyzerTestBands(from: spectrumLevels, count: count)
        }

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

    func testColorAllBandsColoursTheAnalyzer() throws {
        let pixels = try render(visAttributes: #"colorallbands="0,0,255""#)
        XCTAssertEqual(pixel(pixels, x: 1, y: 10), [0, 0, 255, 255],
                       "the skin's one-stroke band colour, not the white default")
    }

    func testAPerBandColourStillWinsOverColorAllBands() throws {
        let pixels = try render(visAttributes: #"colorallbands="0,0,255" colorband1="255,0,0""#)
        XCTAssertEqual(pixel(pixels, x: 1, y: 10), [255, 0, 0, 255], "band 1 keeps its own colour")
        XCTAssertEqual(pixel(pixels, x: 34, y: 10), [0, 0, 255, 255], "the rest fall back")
    }

    /// Rika's actual declaration: black at 50/255, which is a shading over its art rather than a
    /// bar chart drawn on top of it.
    func testTheVisualizationHonoursItsOwnAlpha() throws {
        let pixels = try render(visAttributes: #"colorallbands="0,0,0" alpha="50""#)
        let sample = pixel(pixels, x: 1, y: 10)
        XCTAssertEqual(sample[3], 50, "the object's alpha reaches the analyzer")
        XCTAssertNotEqual(sample[3], 255, "which is the whole difference from painting over the skin")
    }

    /// `mode="2"` is the oscilloscope and `mode="1"` the analyzer — the pairing Love is War Miku's own
    /// menu script writes (`oscstyle` then `setMode(2)`; `bandwidth` then `setMode(1)`).
    func testTheOscilloscopeUsesTheOscilloscopeColours() throws {
        let pixels = try render(visAttributes: #"mode="2" colorosc1="0,255,0" colorband1="255,0,0""#)
        let painted = (0..<64).flatMap { x in (0..<20).map { y in pixel(pixels, x: x, y: y) } }
            .filter { $0[3] > 0 }
        XCTAssertFalse(painted.isEmpty, "the scope draws something")
        XCTAssertTrue(painted.allSatisfy { $0[0] == 0 },
                      "and never in the analyzer's band colour — got \(Set(painted.map { "\($0)" }).prefix(3))")
    }

    /// The Phase 17 rule this sits beside, kept honest: `mode="3"` is "I draw my own here".
    func testAVisualizationTheSkinTurnedOffStaysOff() throws {
        let pixels = try render(visAttributes: #"mode="3" colorallbands="0,0,255""#)
        XCTAssertEqual(pixel(pixels, x: 2, y: 10)[3], 0)
    }

    // MARK: - Fixture

    private func pixel(_ pixels: [UInt8], x: Int, y: Int) -> [UInt8] {
        let offset = (y * 64 + x) * 4
        return Array(pixels[offset..<(offset + 4)])
    }

    private func render(visAttributes: String) throws -> [UInt8] {
        let xml = """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="64" h="20">
              <vis id="vis" x="0" y="0" w="64" h="20" \(visAttributes)/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        var pixels = [UInt8](repeating: 0, count: 64 * 20 * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 64, height: 20,
                                                  bitsPerComponent: 8, bytesPerRow: 64 * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            renderer.draw(in: context)
        }
        return pixels
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase22Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase22-\(UUID().uuidString).wal")
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
}
