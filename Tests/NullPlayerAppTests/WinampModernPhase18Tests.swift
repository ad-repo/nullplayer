import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 18 — a layout sized by its `background` bitmap.
///
/// `w`/`h` are optional on a `<layout>`: Wasabi sizes one that declares neither to its background
/// artwork. Measured against ZDL's Reel-To-Reel, every one of whose layouts is written that way, then
/// reduced to this self-authored fixture.
final class WinampModernPhase18Tests: XCTestCase {
    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
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

    /// `main` is background-sized (120×200) with a control below the 116px classic default; `compact`
    /// is background-sized differently (120×40); `boxed` declares its own box over a larger
    /// background. `eq` is a second background-sized window, `ghostwindow` an explicitly collapsed one.
    private static let skinXML = """
    <WasabiXML>
      <elements>
        <bitmap id="base" file="base.png"/>
        <bitmap id="strip" file="base.png" x="0" y="0" w="120" h="40"/>
        <bitmap id="knob" file="base.png" x="0" y="0" w="10" h="10"/>
      </elements>
      <container id="main">
        <layout id="normal" background="base">
          <button id="deep" action="Play" x="20" y="170" image="knob"/>
        </layout>
        <layout id="compact" background="strip"/>
        <layout id="boxed" background="base" w="64" h="48"/>
      </container>
      <container id="eq">
        <layout id="normal" background="base">
          <slider id="band1" action="EQ_BAND" param="0" x="10" y="10" w="10" h="20" thumb="knob"/>
        </layout>
      </container>
      <container id="ghostwindow">
        <layout id="normal" w="1" h="1"/>
      </container>
    </WasabiXML>
    """

    // MARK: - Canvas size

    func testLayoutWithNoBoxTakesItsBackgroundBitmapSize() throws {
        let (_, renderer) = try makeSkin()
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 120, height: 200))
    }

    func testObjectBelowTheClassicDefaultHeightStaysInTheScene() throws {
        let (_, renderer) = try makeSkin()
        // At the old 275×116 fallback this button landed outside the canvas, where `append` drops
        // it — which is what left ZDL's controls missing and the rest stacked on the reels.
        XCTAssertTrue(renderer.sceneNodes().contains { $0.object.xmlID == "deep" })
        XCTAssertNotNil(renderer.object(at: CGPoint(x: 25, y: 175)))
    }

    func testSwitchingToAnotherBackgroundSizedLayoutResizesTheCanvas() throws {
        let (_, renderer) = try makeSkin()
        XCTAssertEqual(try renderer.activateLayout(id: "compact"), CGSize(width: 120, height: 40))
    }

    func testDeclaredBoxStillWinsOverTheBackgroundBitmap() throws {
        let (_, renderer) = try makeSkin()
        XCTAssertEqual(try renderer.activateLayout(id: "boxed"), CGSize(width: 64, height: 48))
    }

    // MARK: - Window visibility

    func testBackgroundSizedContainerIsAVisibleWindow() throws {
        let (loaded, _) = try makeSkin()
        let ids = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph).map(\.id)
        XCTAssertTrue(ids.contains("eq"), "a layout with no box is sized by its art, not collapsed")
        // …and the inventory has to agree, or a plain window gets synthesized over the skin's own.
        XCTAssertEqual(loaded.surfaceInventory.declaredContainers[.equalizer], "eq")
        XCTAssertNil(loaded.surfaceSynthesis.synthesizedContainers[.equalizer])
    }

    func testExplicitlyCollapsedContainerIsStillHidden() throws {
        let (loaded, _) = try makeSkin()
        let ids = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph).map(\.id)
        XCTAssertFalse(ids.contains("ghostwindow"))
    }

    // MARK: - Fixture

    private func makeSkin() throws -> (WinampModernLoadedSkin, WasabiSceneRenderer) {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive())
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return (loaded, renderer)
    }

    private func makeArchive() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase18Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let entries: [(String, Data)] = [("skin.xml", Data(Self.skinXML.utf8)),
                                         ("base.png", try makePNG(width: 120, height: 200))]
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

    private func makePNG(width: Int, height: Int) throws -> Data {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = UInt8((offset / 4) % 256)
            pixels[offset + 1] = 90
            pixels[offset + 2] = 30
        }
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }
}
