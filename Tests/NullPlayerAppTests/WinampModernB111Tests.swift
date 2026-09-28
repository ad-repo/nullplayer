import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B111's live check — Itemskin's volume, dragged up from a persisted zero — found two more defects
/// between the user and the fix.
///
/// **A script region adds to what a click can reach.** Itemskin's volume display `vol` is a hollow
/// outline, and `volume2.maki` gives it a solid region with `loadFromBitmap` + `setRegion`. The hit
/// test sampled the outline alone, so every click inside it fell through and the volume could not be
/// raised at all. A region never takes pixels away, because T800 drags a strip its region clips.
///
/// **A `<ProgressGrid>` shows the slider it sits under.** Itemskin declares a hidden VOLUME slider
/// before the SEEK slider under its seek grid, and the first slider with an action won, so the seek
/// bar showed the volume.
final class WinampModernB111Tests: XCTestCase {
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

    /// Itemskin's shape in 16x16: a backdrop, a hollow 16x8 volume outline over it, and below them a
    /// hidden VOLUME slider declared ahead of the seek grid and the SEEK slider it sits under.
    private static let skinXML = """
    <WasabiXML>
      <elements>
        <bitmap id="solid" file="solid.png"/>
        <bitmap id="outline" file="outline.png"/>
        <bitmap id="volumeregion" file="region.png"/>
      </elements>
      <container id="Main">
        <layout id="normal" w="16" h="16">
          <layer id="back" image="solid" x="0" y="0" w="16" h="8"/>
          <layer id="vol" image="outline" x="0" y="0"/>
          <slider id="hidvol" action="VOLUME" x="900" y="300" w="16" h="4"/>
          <ProgressGrid id="grid" x="0" y="10" w="16" h="4" middle="solid" orientation="right"/>
          <slider id="Seeker" action="SEEK" x="0" y="10" w="16" h="4"/>
        </layout>
      </container>
    </WasabiXML>
    """

    // MARK: - Hit testing

    func testAClickInsideAHollowLayerFallsThroughWithoutARegion() throws {
        let fixture = try makeFixture()
        XCTAssertEqual(fixture.renderer.object(at: CGPoint(x: 8, y: 4))?.xmlID, "back")
        XCTAssertEqual(fixture.renderer.object(at: CGPoint(x: 0, y: 0))?.xmlID, "vol",
                       "the outline itself is still the layer's own")
    }

    func testABitmapRegionMakesTheWholeStripClickable() throws {
        let fixture = try makeFixture()
        let region = try fixture.makeObject()
        _ = try fixture.runtime.invoke(method: "loadFromBitmap", on: region,
                                       arguments: [.string("volumeregion")], program: fixture.program)
        _ = try fixture.runtime.invoke(method: "setRegion", on: fixture.volReference,
                                       arguments: [.object(region)], program: fixture.program)

        XCTAssertEqual(fixture.renderer.object(at: CGPoint(x: 8, y: 4))?.xmlID, "vol",
                       "Itemskin's volume: the region is solid, so the hollow middle is the control")
    }

    func testARegionNeverTakesAwayWhatTheArtworkClaims() throws {
        let fixture = try makeFixture()
        // Every map value is 0, so an unreversed threshold of 1 selects no pixel at all.
        let map = try fixture.makeObject()
        _ = try fixture.runtime.invoke(method: "loadMap", on: map, arguments: [.string("volumeregion")],
                                       program: fixture.program)
        let region = try fixture.makeObject()
        _ = try fixture.runtime.invoke(method: "loadFromMap", on: region,
                                       arguments: [.object(map), .integer(1), .boolean(false)],
                                       program: fixture.program)
        _ = try fixture.runtime.invoke(method: "setRegion", on: fixture.volReference,
                                       arguments: [.object(region)], program: fixture.program)

        XCTAssertEqual(fixture.renderer.object(at: CGPoint(x: 0, y: 0))?.xmlID, "vol",
                       "T800 drags a strip its region clips; the artwork keeps its claim")
        XCTAssertEqual(fixture.renderer.object(at: CGPoint(x: 8, y: 4))?.xmlID, "back")
    }

    // MARK: - ProgressGrid

    func testAProgressGridShowsTheSliderItSitsUnderNotTheFirstSlider() throws {
        let fixture = try makeFixture()
        let grid = try XCTUnwrap(fixture.loaded.runtime.graph.objects(xmlID: "grid").first)
        let frame = try XCTUnwrap(fixture.renderer.frame(of: grid))
        XCTAssertEqual(fixture.renderer.valueSibling(of: grid, frame: frame)?.xmlID, "Seeker")

        // Volume full, nothing playing: a grid reading the volume fills the whole bar.
        let pixels = try fixture.render()
        XCTAssertEqual(pixels[(11 * 16 + 8) * 4 + 3], 0, "the seek grid is empty with nothing playing")
    }

    // MARK: - Fixture

    private struct Fixture {
        let loaded: WinampModernLoadedSkin
        let renderer: WasabiSceneRenderer
        let runtime: WinampModernScriptRuntime
        let program: MakiProgram
        let vol: WasabiObject

        var volReference: MakiObjectReference { MakiObjectReference(.gui(vol.stableID)) }

        func makeObject() throws -> MakiObjectReference {
            try runtime.makeObject(classGUID: String(repeating: "0", count: 32), program: program)
        }

        func render() throws -> [UInt8] {
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
    }

    private func makeFixture() throws -> Fixture {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive())
        addTeardownBlock { loaded.teardown() }
        let host = Host()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { runtime.teardown() }
        let vol = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "vol").first)
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                                  instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/test.maki"),
                                  ownerID: nil, parameter: nil)
        return Fixture(loaded: loaded, renderer: renderer, runtime: runtime, program: program, vol: vol)
    }

    // MARK: - Archive

    private func makeArchive() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB111Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let entries: [(String, Data)] = [
            ("skin.xml", Data(Self.skinXML.utf8)),
            ("solid.png", try png(width: 16, height: 16) { _, _ in true }),
            // Itemskin's `pl-volume.png`: a one-pixel frame with a transparent middle.
            ("outline.png", try png(width: 16, height: 8) { x, y in x == 0 || x == 15 || y == 0 || y == 7 }),
            // Itemskin's `pl-volume-region.png`: opaque black everywhere.
            ("region.png", try png(width: 16, height: 8, gray: 0) { _, _ in true })
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

    private func png(width: Int, height: Int, gray: UInt8 = 255,
                     opaque: (Int, Int) -> Bool) throws -> Data {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width where opaque(x, y) {
                let offset = (y * width + x) * 4
                pixels[offset] = gray
                pixels[offset + 1] = gray
                pixels[offset + 2] = gray
                pixels[offset + 3] = 255
            }
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
