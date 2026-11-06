import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B378: a slider's drawn thumb is part of the slider. Enya_Winamp_3_Skin's EQ bands are 3-px
/// `<slider>`s under a 5-px thumb, over a bar layer; a press on the knob's outer columns hit the bar.
final class WinampModernB378Tests: XCTestCase {
    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 1
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var trackDisplayTitle = ""
        var bitrateKbps = 0
        var sampleRateHz = 0
        var channelCount = 2
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

    /// Enya's band in miniature: a 5x39 bar, a 3x30 vertical slider centred on it, a 5x5 thumb.
    private static let skinXML = """
    <WasabiXML>
      <elements>
        <bitmap id="bar" file="bar.png"/>
        <bitmap id="knob" file="knob.png"/>
      </elements>
      <container id="Main">
        <layout id="normal" w="16" h="40">
          <layer id="eqbar" image="bar" x="5" y="0"/>
          <slider id="band" action="EQ_BAND" param="1" x="6" y="0" w="3" h="30" thumb="knob" orientation="v"/>
        </layout>
      </container>
    </WasabiXML>
    """

    func testThePressOnTheThumbsOuterColumnsIsTheSlidersNotTheBars() throws {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive())
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let band = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "band").first)
        let thumb = try XCTUnwrap(renderer.resources.bitmap(identifier: "knob"))
        let knob = renderer.sliderThumbFrame(band, thumb: thumb, in: try XCTUnwrap(renderer.frame(of: band)))
        let row = knob.midY
        XCTAssertEqual(renderer.object(at: CGPoint(x: 5.5, y: row))?.xmlID, "band", "the knob's left column")
        XCTAssertEqual(renderer.object(at: CGPoint(x: 9.5, y: row))?.xmlID, "band", "the knob's right column")
        XCTAssertEqual(renderer.object(at: CGPoint(x: 7.5, y: row))?.xmlID, "band")
        XCTAssertEqual(renderer.object(at: CGPoint(x: 5.5, y: 35))?.xmlID, "eqbar",
                       "the bar below the slider's travel is still the bar's")
    }

    private func makeArchive() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB378Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let entries: [(String, Data)] = [
            ("skin.xml", Data(Self.skinXML.utf8)),
            ("bar.png", try png(width: 5, height: 39)),
            ("knob.png", try png(width: 5, height: 5))
        ]
        for (path, payload) in entries {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    private func png(width: Int, height: Int) throws -> Data {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        let rep = NSBitmapImageRep(cgImage: image)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
