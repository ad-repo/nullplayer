import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 20 — region clipping: a control clipped to a shape taken from a greyscale map.
///
/// `Region.loadFromMap(Map, Int threshold, Boolean reversed)` — the signature is `std.mi`'s — reads
/// the map's red channel as a 0–255 position. The reversed form keeps every pixel at or below the
/// threshold, which is how a skin fills a bar as its value rises; the plain form keeps everything at
/// or above. `Layer.setRegion` clips the control to the result, and `Layer.setRegionFromMap` is the
/// same thing with no `Region` object in between.
///
/// The fixture's map is asymmetric on both axes on purpose: its top half is a left-to-right ramp and
/// its bottom half is solid 255, so a mask built upside down selects the wrong half and the test
/// fails rather than looking plausible.
final class WinampModernPhase20Tests: XCTestCase {
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

    private static let skinXML = """
    <WasabiXML>
      <elements>
        <bitmap id="art" file="art.png"/>
        <bitmap id="player.map.volume" file="map.png"/>
      </elements>
      <container id="Main">
        <layout id="normal" w="16" h="16">
          <layer id="VolumeAnim" image="art" x="0" y="0" w="16" h="16"/>
        </layout>
      </container>
    </WasabiXML>
    """

    /// The ramp step: column `c` of the map's top half holds `c * 16`.
    private static let step = 16

    // MARK: - The mask

    func testReversedRegionKeepsEveryPixelAtOrBelowTheThreshold() throws {
        let fixture = try makeFixture()
        try fixture.setRegionFromLoadedMap(threshold: 100, reversed: true)
        let pixels = try fixture.render()

        assertPainted(pixels, x: 0, y: 0, "value 0 is under the threshold")
        assertPainted(pixels, x: 6, y: 0, "value 96 is under the threshold")
        assertClipped(pixels, x: 7, y: 0, "value 112 is over it")
        assertPainted(pixels, x: 6, y: 7, "the ramp runs the full height of the top half")
        assertClipped(pixels, x: 6, y: 8, "the bottom half is solid 255 — a mask built upside down "
                      + "would paint here and clip the row above")
    }

    func testUnreversedRegionKeepsEveryPixelAtOrAboveTheThreshold() throws {
        let fixture = try makeFixture()
        try fixture.setRegionFromLoadedMap(threshold: 100, reversed: false)
        let pixels = try fixture.render()

        assertClipped(pixels, x: 0, y: 0, "value 0 is under the threshold")
        assertPainted(pixels, x: 7, y: 0, "value 112 is over it")
        assertPainted(pixels, x: 0, y: 10, "the solid bottom half is entirely inside")
    }

    /// The whole point of the feature: as the value rises the clipped part of the bar grows.
    func testTheRegionTracksTheThreshold() throws {
        let fixture = try makeFixture()
        for column in [0, 4, 11, 15] {
            try fixture.setRegionFromLoadedMap(threshold: column * Self.step, reversed: true)
            let pixels = try fixture.render()
            assertPainted(pixels, x: column, y: 0, "column \(column) is at the threshold")
            if column < 15 {
                assertClipped(pixels, x: column + 1, y: 0, "the next column is past it")
            }
        }
    }

    func testTheShortSetRegionFromMapFormClipsTheSameWay() throws {
        let fixture = try makeFixture()
        let map = try fixture.makeMap(identifier: "player.map.volume")
        _ = try fixture.runtime.invoke(method: "setRegionFromMap",
                                       on: fixture.layerReference,
                                       arguments: [.object(map), .integer(100), .boolean(true)],
                                       program: fixture.program)
        let pixels = try fixture.render()
        assertPainted(pixels, x: 6, y: 0)
        assertClipped(pixels, x: 7, y: 0)
    }

    /// `Region.offset` moves the region in map pixels. Skins whose map covers a whole window use it
    /// to shift the shape back into the clipped layer's own space (the stock `customseek.m`).
    func testOffsetMovesTheRegion() throws {
        let fixture = try makeFixture()
        let region = try fixture.makeRegion(threshold: 100, reversed: true)
        _ = try fixture.runtime.invoke(method: "offset", on: region,
                                       arguments: [.integer(4), .integer(0)],
                                       program: fixture.program)
        _ = try fixture.runtime.invoke(method: "setRegion", on: fixture.layerReference,
                                       arguments: [.object(region)], program: fixture.program)
        let pixels = try fixture.render()
        assertPainted(pixels, x: 10, y: 0, "the ramp's column 6 now covers column 10")
        assertClipped(pixels, x: 11, y: 0)
        assertClipped(pixels, x: 3, y: 0, "and nothing is left of the region's new left edge")
    }

    // MARK: - The role, and what happens when it is not a region

    /// A `Region`, a `Map`, a `Timer` and a `List` are all born from the same bare `new`; only the
    /// first call that no other class accepts settles which one it is.
    func testLoadFromMapSettlesTheRoleWithoutDisturbingTheMapItReadsFrom() throws {
        let fixture = try makeFixture()
        let map = try fixture.makeMap(identifier: "player.map.volume")
        let region = try fixture.runtime.makeObject(classGUID: String(repeating: "0", count: 32),
                                                    program: fixture.program)
        _ = try fixture.runtime.invoke(method: "loadFromMap", on: region,
                                       arguments: [.object(map), .integer(100), .boolean(true)],
                                       program: fixture.program)

        // The map is still a map: it answers pixel queries, and the region reports the map it holds.
        XCTAssertEqual(try fixture.runtime.invoke(method: "getValue", on: map,
                                                  arguments: [.integer(6), .integer(0)],
                                                  program: fixture.program).integerValue,
                       Int32(6 * Self.step))
        XCTAssertEqual(try fixture.runtime.invoke(method: "getId", on: region, arguments: [],
                                                  program: fixture.program).stringValue,
                       "player.map.volume")
        // A timer call on the same object must not be mistaken for region state, and vice versa.
        XCTAssertFalse(try fixture.runtime.invoke(method: "isRunning", on: region, arguments: [],
                                                   program: fixture.program).truthy)
    }

    func testLoadFromMapOnSomethingThatIsNotAMapLeavesTheObjectUnclipped() throws {
        let fixture = try makeFixture()
        let notAMap = try fixture.runtime.makeObject(classGUID: String(repeating: "0", count: 32),
                                                     program: fixture.program)
        let region = try fixture.runtime.makeObject(classGUID: String(repeating: "0", count: 32),
                                                    program: fixture.program)
        _ = try fixture.runtime.invoke(method: "loadFromMap", on: region,
                                       arguments: [.object(notAMap), .integer(100), .boolean(true)],
                                       program: fixture.program)
        _ = try fixture.runtime.invoke(method: "setRegion", on: fixture.layerReference,
                                       arguments: [.object(region)], program: fixture.program)
        let pixels = try fixture.render()
        assertPainted(pixels, x: 15, y: 15, "an unloaded region must not swallow the control")
    }

    /// The degradation the handoff asked for: a map that cannot be resolved leaves the control the
    /// way it looked before regions existed, rather than clipping it away to nothing.
    func testAnUnresolvableMapDegradesToNoClipping() throws {
        let fixture = try makeFixture()
        let map = try fixture.makeMap(identifier: "no.such.map")
        let region = try fixture.runtime.makeObject(classGUID: String(repeating: "0", count: 32),
                                                    program: fixture.program)
        _ = try fixture.runtime.invoke(method: "loadFromMap", on: region,
                                       arguments: [.object(map), .integer(100), .boolean(true)],
                                       program: fixture.program)
        _ = try fixture.runtime.invoke(method: "setRegion", on: fixture.layerReference,
                                       arguments: [.object(region)], program: fixture.program)
        let pixels = try fixture.render()
        assertPainted(pixels, x: 0, y: 0)
        assertPainted(pixels, x: 15, y: 15)
    }

    // MARK: - The graph

    func testSettingARegionMarksTheGraphDirty() throws {
        let fixture = try makeFixture()
        var mutations = 0
        fixture.runtime.graphDidMutate = { mutations += 1 }
        try fixture.setRegionFromLoadedMap(threshold: 100, reversed: true)
        XCTAssertEqual(mutations, 1, "the renderer draws from the graph and nothing else")

        try fixture.setRegionFromLoadedMap(threshold: 100, reversed: true)
        XCTAssertEqual(mutations, 1, "an unchanged region is not a mutation")
    }

    func testClearingTheRegionRestoresTheFullControl() throws {
        let fixture = try makeFixture()
        try fixture.setRegionFromLoadedMap(threshold: 100, reversed: true)
        assertClipped(try fixture.render(), x: 15, y: 15)

        _ = try fixture.runtime.invoke(method: "setRegion", on: fixture.layerReference,
                                       arguments: [.null], program: fixture.program)
        let pixels = try fixture.render()
        assertPainted(pixels, x: 0, y: 0)
        assertPainted(pixels, x: 15, y: 15)
    }

    /// The engine's own no-op stand-in is gone: `setRegionFromMap` is a real capability now, so it
    /// must not be recorded as unsupported demand any more.
    func testTheRegionMethodsAreDeclaredRatherThanRefused() throws {
        let fixture = try makeFixture()
        for method in ["loadfrommap", "setregion", "setregionfrommap", "offset"] {
            XCTAssertNotNil(fixture.runtime.signature(for: method, classGUID: nil),
                            "\(method) must be in the signature table, which is the authoritative list")
        }
        try fixture.setRegionFromLoadedMap(threshold: 100, reversed: true)
        XCTAssertTrue(fixture.runtime.unsupportedMethodCalls.isEmpty)
    }

    // MARK: - Fixture

    private struct Fixture {
        let loaded: WinampModernLoadedSkin
        let renderer: WasabiSceneRenderer
        let runtime: WinampModernScriptRuntime
        let program: MakiProgram
        let layer: WasabiObject

        var layerReference: MakiObjectReference { MakiObjectReference(.gui(layer.stableID)) }

        func makeMap(identifier: String) throws -> MakiObjectReference {
            let map = try runtime.makeObject(classGUID: String(repeating: "0", count: 32), program: program)
            _ = try runtime.invoke(method: "loadMap", on: map, arguments: [.string(identifier)],
                                   program: program)
            return map
        }

        func makeRegion(threshold: Int32, reversed: Bool) throws -> MakiObjectReference {
            let map = try makeMap(identifier: "player.map.volume")
            let region = try runtime.makeObject(classGUID: String(repeating: "0", count: 32), program: program)
            _ = try runtime.invoke(method: "loadFromMap", on: region,
                                   arguments: [.object(map), .integer(threshold), .boolean(reversed)],
                                   program: program)
            return region
        }

        func setRegionFromLoadedMap(threshold: Int, reversed: Bool) throws {
            let region = try makeRegion(threshold: Int32(threshold), reversed: reversed)
            _ = try runtime.invoke(method: "setRegion", on: MakiObjectReference(.gui(layer.stableID)),
                                   arguments: [.object(region)], program: program)
        }

        func render() throws -> [UInt8] {
            let width = Int(renderer.canvasSize.width)
            let height = Int(renderer.canvasSize.height)
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
    }

    private func makeFixture() throws -> Fixture {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive())
        addTeardownBlock { loaded.teardown() }
        let host = Host()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { runtime.teardown() }
        let layer = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "VolumeAnim").first)
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                                  instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/test.maki"),
                                  ownerID: nil, parameter: nil)
        return Fixture(loaded: loaded, renderer: renderer, runtime: runtime, program: program, layer: layer)
    }

    // MARK: - Assertions

    /// `y` is measured from the top of the canvas, as the skin measures it; the backing store's
    /// first row is the top row.
    private func pixel(_ pixels: [UInt8], x: Int, y: Int) -> [UInt8] {
        let offset = (y * 16 + x) * 4
        return Array(pixels[offset..<(offset + 4)])
    }

    private func assertPainted(_ pixels: [UInt8], x: Int, y: Int, _ message: String = "",
                               file: StaticString = #filePath, line: UInt = #line) {
        let actual = pixel(pixels, x: x, y: y)
        XCTAssertEqual(actual[3], 255, "expected paint at (\(x),\(y)) — \(message); got \(actual)",
                       file: file, line: line)
    }

    private func assertClipped(_ pixels: [UInt8], x: Int, y: Int, _ message: String = "",
                               file: StaticString = #filePath, line: UInt = #line) {
        let actual = pixel(pixels, x: x, y: y)
        XCTAssertEqual(actual[3], 0, "expected the region to clip (\(x),\(y)) — \(message); got \(actual)",
                       file: file, line: line)
    }

    // MARK: - Archive

    private func makeArchive() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase20Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let entries: [(String, Data)] = [("skin.xml", Data(Self.skinXML.utf8)),
                                         ("art.png", try makeArtworkPNG()),
                                         ("map.png", try makeMapPNG())]
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

    /// 16×16 solid opaque green: every pixel of the control is paint, so anything transparent in the
    /// output was clipped by the region and nothing else.
    private func makeArtworkPNG() throws -> Data {
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset + 1] = 255
            pixels[offset + 3] = 255
        }
        return try encode(pixels)
    }

    /// 16×16. Top half: a left-to-right ramp, `red = column * 16`. Bottom half: solid 255. Both axes
    /// carry information, so a mask that is flipped or transposed cannot pass by accident.
    private func makeMapPNG() throws -> Data {
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        for row in 0..<16 {
            for column in 0..<16 {
                let value = UInt8(row < 8 ? column * Self.step : 255)
                let offset = (row * 16 + column) * 4
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
                pixels[offset + 3] = 255
            }
        }
        return try encode(pixels)
    }

    private func encode(_ pixels: [UInt8]) throws -> Data {
        var pixels = pixels
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 16, height: 16,
                                                  bitsPerComponent: 8, bytesPerRow: 16 * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }
}
