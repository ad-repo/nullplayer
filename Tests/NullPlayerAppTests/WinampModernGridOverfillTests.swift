import XCTest
import ZIPFoundation
@testable import NullPlayer

/// CPro_iPhone3gv2 (intake #2): its `main.shadow` gives every grid slot the whole shadow, in a window
/// exactly that size, and squashing the overfull corners into halves drew four phones. Wasabi draws
/// each edge whole, anchored to its own side and clipped to its share, so the pieces add up to one.
final class WinampModernGridOverfillTests: XCTestCase {

    /// An 8px grid whose `topleft` and `topright` are both the full 8px two-tone sheet.
    func testOverfullEdgesAreClippedNotSquashed() throws {
        let xml = """
        <WasabiXML>
          <elements><bitmap id="sheet" file="sheet.png"/></elements>
          <container id="main">
            <layout id="normal" w="8" h="8">
              <grid id="g" x="0" y="0" w="8" h="8" topleft="sheet" top="sheet" topright="sheet"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let renderer = try WasabiSceneRenderer(loadedSkin: try load(xml: xml), host: TestHost(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let pixels = try render(renderer)

        // Squashed, the left corner's x=3 would be the sheet's x=6 (right half) and the right
        // corner's x=5 the sheet's x=2 (left half).
        XCTAssertEqual(blue(pixels, x: 3), 50, "the left corner shows the sheet's own left half")
        XCTAssertEqual(blue(pixels, x: 5), 200, "the right corner shows the sheet's own right half")
    }

    // MARK: -

    private func blue(_ pixels: [UInt8], x: Int) -> UInt8 { pixels[(4 * 8 + x) * 4 + 2] }

    private func render(_ renderer: WasabiSceneRenderer) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 8, height: 8,
                                                  bitsPerComponent: 8, bytesPerRow: 8 * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            renderer.draw(in: context)
        }
        return pixels
    }

    /// Left half blue 50, right half blue 200, opaque.
    private func makeTwoTonePNG() throws -> Data {
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset + 2] = (offset / 4) % 8 < 4 ? 50 : 200
            pixels[offset + 3] = 255
        }
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 8, height: 8,
                                                  bitsPerComponent: 8, bytesPerRow: 8 * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    private func load(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernGridOverfillTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("grid.wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in [("skin.xml", Data(xml.utf8)), ("sheet.png", try makeTwoTonePNG())] {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
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
