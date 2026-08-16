import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Pixel-level regression coverage for `WasabiSceneRenderer`.
///
/// Every previous phase asserted structure (graph built, scripts ran, node counts) and never looked
/// at a rendered pixel, which is how three compounding defects survived a green suite: sprites were
/// cropped from a bottom-left origin (`CGImage.cropping(to:)` is top-left), every bitmap was drawn
/// vertically mirrored under the flipped skin CTM, and `tile`/`fitparent` were unimplemented.
final class WinampModernRenderPixelTests: XCTestCase {

    /// Atlas is 16×16, banded by row so a wrong crop origin or a vertical flip changes the answer:
    ///   rows 0–3 red, rows 4–7 green, rows 8–11 blue, rows 12–15 white.
    private enum Band {
        static let red: [UInt8] = [255, 0, 0]
        static let green: [UInt8] = [0, 255, 0]
        static let blue: [UInt8] = [0, 0, 255]
    }

    /// `<bitmap y="4" h="4">` must cut the *green* band — the fifth pixel row of the file — and paint
    /// it upright at the layer's position. Before the fix it cut the blue band and drew it mirrored.
    func testSpriteCropUsesTopLeftOriginAndDrawsUpright() throws {
        let xml = """
        <WasabiXML>
          <elements>
            <bitmap id="band.green" file="sheet.png" x="0" y="4" w="16" h="4"/>
            <bitmap id="band.split" file="sheet.png" x="0" y="0" w="16" h="8"/>
          </elements>
          <container id="Main">
            <layout id="normal" w="16" h="16">
              <layer id="green" image="band.green" x="0" y="0" w="16" h="4"/>
              <layer id="split" image="band.split" x="0" y="8" w="16" h="8"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let pixels = try render(xml: xml, size: CGSize(width: 16, height: 16))

        // The `band.green` layer: the green band, not the blue one four rows lower in the file.
        assertColor(pixels, x: 8, y: 1, equals: Band.green, "y=4 must crop the green band")

        // `band.split` spans red (rows 0–3) then green (rows 4–7), drawn at y=8. Upright means red
        // lands on top (canvas rows 8–11) and green below (rows 12–15); mirrored swaps them.
        assertColor(pixels, x: 8, y: 9, equals: Band.red, "sprite must not be vertically mirrored")
        assertColor(pixels, x: 8, y: 14, equals: Band.green, "sprite must not be vertically mirrored")
    }

    /// `tile="1"` repeats the bitmap across the layer. Without it the frame painted one tile and left
    /// the rest of the window bare — the empty middle in the first live run.
    func testTiledLayerFillsItsFrame() throws {
        let xml = """
        <WasabiXML>
          <elements>
            <bitmap id="tile.blue" file="sheet.png" x="0" y="8" w="4" h="4"/>
          </elements>
          <container id="Main">
            <layout id="normal" w="16" h="16">
              <layer id="fill" image="tile.blue" x="0" y="0" w="16" h="16" tile="1"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let pixels = try render(xml: xml, size: CGSize(width: 16, height: 16))
        assertColor(pixels, x: 2, y: 2, equals: Band.blue, "first tile")
        assertColor(pixels, x: 14, y: 14, equals: Band.blue, "far corner must be covered by tiling")
    }

    /// `fitparent="1"` fills the parent regardless of x/y/w/h. Without it these groups resolve to a
    /// 0×0 rect and every descendant collapses into the top-left corner.
    func testFitParentGroupTakesTheParentFrame() throws {
        let xml = """
        <WasabiXML>
          <elements>
            <bitmap id="band.green" file="sheet.png" x="0" y="4" w="16" h="4"/>
          </elements>
          <groupdef id="probe.group">
            <layer id="inner" image="band.green" x="0" y="0" w="16" h="4"/>
          </groupdef>
          <container id="Main">
            <layout id="normal" w="16" h="16">
              <group id="probe.group" fitparent="1"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: xml))
        defer { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: RenderHost())
        defer { renderer.teardown() }

        let group = try XCTUnwrap(renderer.sceneNodes().first {
            $0.object.typeName.caseInsensitiveCompare("group") == .orderedSame
        })
        XCTAssertEqual(group.frame, CGRect(x: 0, y: 0, width: 16, height: 16))
    }

    // MARK: - Helpers

    private func render(xml: String, size: CGSize) throws -> [UInt8] {
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: xml))
        defer { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: RenderHost())
        defer { renderer.teardown() }
        XCTAssertEqual(renderer.canvasSize, size)

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

    /// `y` is measured from the top of the canvas, matching the skin's own coordinate system. The
    /// backing store's first row is the top row, so no conversion is needed.
    private func assertColor(_ pixels: [UInt8], x: Int, y: Int, equals expected: [UInt8],
                             _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let offset = (y * 16 + x) * 4
        let actual = Array(pixels[offset..<(offset + 3)])
        XCTAssertEqual(actual, expected, "\(message) — at (\(x),\(y)) got \(actual)",
                       file: file, line: line)
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernRenderPixelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic.wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in [("skin.xml", Data(xml.utf8)), ("sheet.png", try makeBandedPNG())] {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    /// 16×16, four solid four-row bands top-to-bottom: red, green, blue, white.
    private func makeBandedPNG() throws -> Data {
        let side = 16
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        let bands: [[UInt8]] = [Band.red, Band.green, Band.blue, [255, 255, 255]]
        for row in 0..<side {
            let band = bands[row / 4]
            for column in 0..<side {
                let offset = (row * side + column) * 4
                pixels[offset] = band[0]
                pixels[offset + 1] = band[1]
                pixels[offset + 2] = band[2]
                pixels[offset + 3] = 255
            }
        }
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
