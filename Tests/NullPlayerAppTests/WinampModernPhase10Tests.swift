import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 10 — fidelity fixes driven by running MMD3 (`mmd3.wal`), a colour-themed skin whose whole UI
/// is script-built: sliding drawers, rotary knobs, and 83 colour themes. Each test here corresponds to
/// a defect that was visible on screen or fatal at run time.
final class WinampModernPhase10Tests: XCTestCase {

    // MARK: - Colour themes

    /// `<gammagroup value="r,g,b">` is a per-channel **additive offset** normalized to ±1: 0 leaves a
    /// channel alone, +4096 adds 1.0, −4096 subtracts 1.0. Skins like Anaheim Player 01 use black pixel
    /// templates recolored entirely by gamma; a multiplicative model left them black.
    func testGammaGroupValueIsAnAdditiveOffset() {
        let neutral = WasabiGammaTransform(value: "0,0,0", gray: nil, boost: nil)
        XCTAssertTrue(neutral.isIdentity, "0,0,0 must change nothing at all.")

        let tinted = WasabiGammaTransform(value: "4096,-4096,2048", gray: nil, boost: nil)
        XCTAssertEqual(tinted.red, 1.0, accuracy: 0.001)
        XCTAssertEqual(tinted.green, -1.0, accuracy: 0.001)
        XCTAssertEqual(tinted.blue, 0.5, accuracy: 0.001)

        // `gray` is a mode, not a flag — MMD3 ships both gray="1" and gray="2".
        XCTAssertTrue(WasabiGammaTransform(value: "0,0,0", gray: "2", boost: nil).grayscale)
        XCTAssertFalse(WasabiGammaTransform(value: "0,0,0", gray: "0", boost: nil).grayscale)
    }

    /// The default colour theme is the **first gammaset in the document**, which skins name freely
    /// ("clean | orange (default)"). Choosing the alphabetically first name handed MMD3 a green theme
    /// on every launch.
    func testDefaultColorThemeIsTheFirstGammasetInDocumentOrder() throws {
        let xml = """
        <WasabiXML>
          <elements>
            <gammaset id="zulu (default)"><gammagroup id="Display" value="0,0,0"/></gammaset>
            <gammaset id="alpha"><gammagroup id="Display" value="4096,0,0"/></gammaset>
          </elements>
          <container id="Main">
            <layout id="normal" w="16" h="16"/>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: xml))
        defer { loaded.teardown() }
        let catalog = WasabiColorThemeCatalog(loadedSkin: loaded)
        XCTAssertEqual(catalog.activeTheme, "zulu (default)")
        XCTAssertEqual(catalog.themeNames, ["zulu (default)", "alpha"],
                       "The theme list keeps document order, as Winamp's ColorThemes list does.")
    }

    /// Gamma is additive: a red-only offset on a pure-green sprite adds red to it, producing yellow.
    func testColorThemeAddsOffsetsToPixels() throws {
        let xml = """
        <WasabiXML>
          <elements>
            <gammaset id="only"><gammagroup id="Test" value="2048,0,0"/></gammaset>
            <bitmap id="band.green" file="sheet.png" x="0" y="4" w="16" h="4" gammagroup="Test"/>
          </elements>
          <container id="Main">
            <layout id="normal" w="16" h="16">
              <layer id="green" image="band.green" x="0" y="0" w="16" h="16"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let pixels = try render(xml: xml, size: CGSize(width: 16, height: 16))
        // CIColorMatrix works in linear space; the 0.5 bias maps to ~188 after sRGB encoding.
        assertColor(pixels, x: 8, y: 8, equals: [188, 255, 0],
                    "a red-channel gamma adds red to a green sprite, producing yellow")
    }

    /// Black pixels (0,0,0) become visible under a positive gamma offset — the core Anaheim scenario.
    func testBlackPixelsBecomeVisibleUnderPositiveGamma() throws {
        let xml = """
        <WasabiXML>
          <elements>
            <gammaset id="only"><gammagroup id="Test" value="2048,1024,3072"/></gammaset>
            <bitmap id="band.red" file="sheet.png" x="0" y="0" w="16" h="4" gammagroup="Test"/>
          </elements>
          <container id="Main">
            <layout id="normal" w="16" h="16">
              <layer id="dark" image="band.red" x="0" y="0" w="16" h="16"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let pixels = try render(xml: xml, size: CGSize(width: 16, height: 16))
        // Red band (255,0,0) + offset (0.5, 0.25, 0.75) in linear space, then sRGB-encoded.
        assertColor(pixels, x: 8, y: 8, equals: [255, 137, 225],
                    "gamma adds offsets to each channel, making dark channels visible")
    }

    // MARK: - Animated layers

    /// Scripts drive a knob as a frame *range*: `setStartFrame` / `setEndFrame` / `setSpeed` / `play`,
    /// then poll `isPlaying()`. The play head must walk from start to end at the set speed and stop
    /// there — a looping modulo (the previous model) never finishes and spins the knob forever.
    func testAnimatedLayerPlaysAFrameRangeAndStops() throws {
        let object = try makeAnimatedLayer(attributes: [
            "startframe": "0", "endframe": "10", "speed": "100", "playing": "1", "animstart": "1000"
        ])
        let mid = WasabiAnimation.state(of: object, frameCount: 23, clock: 1000.35)
        XCTAssertEqual(mid.frame, 3)
        XCTAssertTrue(mid.isPlaying)

        let done = WasabiAnimation.state(of: object, frameCount: 23, clock: 1002)
        XCTAssertEqual(done.frame, 10, "the play head stops on the end frame")
        XCTAssertFalse(done.isPlaying, "isPlaying() must go false so the driving timer can finish")
    }

    /// A knob turned down runs the range backwards.
    func testAnimatedLayerPlaysAFrameRangeBackwards() throws {
        let object = try makeAnimatedLayer(attributes: [
            "startframe": "20", "endframe": "5", "speed": "100", "playing": "1", "animstart": "1000"
        ])
        XCTAssertEqual(WasabiAnimation.state(of: object, frameCount: 23, clock: 1000.55).frame, 15)
        XCTAssertEqual(WasabiAnimation.state(of: object, frameCount: 23, clock: 1009).frame, 5)
    }

    /// `stop()` (an explicit `playing="0"`) wins over the XML's `autoplay`, so a script can freeze a
    /// layer the skin declared as self-playing.
    func testExplicitPlayingStateOverridesAutoplay() throws {
        let object = try makeAnimatedLayer(attributes: ["autoplay": "1", "playing": "0", "frame": "4"])
        let state = WasabiAnimation.state(of: object, frameCount: 23, clock: 5000)
        XCTAssertEqual(state.frame, 4)
        XCTAssertFalse(state.isPlaying)
    }

    // MARK: - Scene culling

    /// Skins park objects outside the layout to hide them. MMD3 keeps a dummy volume slider at
    /// (400,400) whose `thumb` is the 44×1012 knob *sheet*, and a slider centres its thumb on its
    /// track — so an unculled object painted a column of knobs down the window.
    func testObjectOutsideItsParentIsCulledWithItsSubtree() throws {
        let xml = """
        <WasabiXML>
          <elements>
            <bitmap id="band.green" file="sheet.png" x="0" y="4" w="16" h="4"/>
          </elements>
          <groupdef id="probe.group">
            <layer id="child" image="band.green" x="0" y="0" w="4" h="4"/>
          </groupdef>
          <container id="Main">
            <layout id="normal" w="16" h="16">
              <layer id="onscreen" image="band.green" x="0" y="0" w="4" h="4"/>
              <group id="probe.group" x="400" y="400" w="8" h="8"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: xml))
        defer { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: RenderHost())
        defer { renderer.teardown() }

        let ids = renderer.sceneNodes().compactMap { $0.object.xmlID }
        XCTAssertTrue(ids.contains("onscreen"))
        XCTAssertFalse(ids.contains("probe.group"), "an off-layout object draws nothing")
        XCTAssertFalse(ids.contains("child"), "and neither do its children")
    }

    // MARK: - Script robustness

    /// Winamp ignores a call on a null object; skins ship with them. MMD3 checks menu commands from a
    /// function that also runs before the menu is built, and throwing there aborted the rest of
    /// `onScriptLoaded` — every drawer, knob, and LED it had yet to wire up.
    func testMethodCallOnANullObjectIsANoOp() throws {
        var code = Data()
        code.append(pushVariable(2))            // an integer variable, not an object
        code.append(callMethod(0))              // v2.getId()
        code.append(assignToVariable(1))        // stash the (null) result
        let program = try MakiBytecodeParser().parse(makeScript(code: code, methodName: "getid"),
                                                     source: WalSourceLocation(path: "/null.maki"))
        let dispatcher = NoOpDispatcher()
        let interpreter = MakiInterpreter(dispatcher: dispatcher)
        XCTAssertNoThrow(try interpreter.execute(program: program, at: 0),
                         "a null receiver must not abort the event")
        XCTAssertEqual(program.variables[1].value.stringValue, "")
    }

    // MARK: - Helpers

    private func makeAnimatedLayer(attributes: [String: String]) throws -> WasabiObject {
        let attributePairs = attributes.map { "\($0.key)=\"\($0.value)\"" }.joined(separator: " ")
        let xml = """
        <WasabiXML>
          <elements>
            <bitmap id="band.green" file="sheet.png" x="0" y="0" w="16" h="16"/>
          </elements>
          <container id="Main">
            <layout id="normal" w="16" h="16">
              <animatedlayer id="knob" image="band.green" x="0" y="0" w="4" h="4" \(attributePairs)/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        return try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "knob").first)
    }

    private func render(xml: String, size: CGSize) throws -> [UInt8] {
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: xml))
        defer { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: RenderHost())
        defer { renderer.teardown() }
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

    /// `y` is measured from the top of the 16-wide canvas, matching the skin's coordinate system.
    private func assertColor(_ pixels: [UInt8], x: Int, y: Int, equals expected: [UInt8],
                             _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let offset = (y * 16 + x) * 4
        let actual = Array(pixels[offset..<(offset + 3)])
        for (channel, pair) in zip(actual, expected).enumerated() {
            XCTAssertEqual(Int(pair.0), Int(pair.1), accuracy: 2,
                           "\(message) — at (\(x),\(y)) channel \(channel), got \(actual)",
                           file: file, line: line)
        }
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase10Tests-\(UUID().uuidString)", isDirectory: true)
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
        let bands: [[UInt8]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255]]
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

    // MARK: - Minimal MAKI assembler (mirrors the Phase 8 helpers)

    private final class NoOpDispatcher: MakiMethodDispatching {
        func signature(for method: String, classGUID: String?) -> MakiMethodSignature? {
            .init(argumentCount: 0, returnKind: .string)
        }
        func invoke(method: String, on object: MakiObjectReference, arguments: [MakiValue],
                    program: MakiProgram) throws -> MakiValue { .string("called") }
        func makeObject(classGUID: String, program: MakiProgram) throws -> MakiObjectReference {
            MakiObjectReference(.system)
        }
    }

    private func pushVariable(_ index: UInt32) -> Data {
        var data = Data([1])
        appendUInt32(index, to: &data)
        return data
    }

    private func assignToVariable(_ index: UInt32) -> Data {
        var data = Data([3])
        appendUInt32(index, to: &data)
        return data
    }

    private func callMethod(_ index: UInt32) -> Data {
        var data = Data([24])
        appendUInt32(index, to: &data)
        return data
    }

    /// One class, one method (named by the caller), three variables: v0 system object, v1 string
    /// result slot, v2 a plain integer — the stand-in for an unassigned object variable.
    private func makeScript(code: Data, methodName: String) -> Data {
        var data = Data([0x46, 0x47])
        appendUInt16(0x0403, to: &data)
        appendUInt32(23, to: &data)

        appendUInt32(1, to: &data)                                  // classes
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))

        appendUInt32(1, to: &data)                                  // methods
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendString(methodName, to: &data)

        appendUInt32(3, to: &data)                                  // variables
        appendVariable(typeOffset: 0, object: true, system: true, to: &data)
        appendVariable(typeOffset: MakiValueKind.string.rawValue, to: &data)
        appendVariable(typeOffset: MakiValueKind.integer.rawValue, initial: 5, to: &data)

        appendUInt32(0, to: &data)                                  // constants
        appendUInt32(0, to: &data)                                  // bindings
        appendUInt32(UInt32(code.count), to: &data)
        data.append(code)
        return data
    }

    private func appendVariable(typeOffset: UInt8, object: Bool = false, system: Bool = false,
                                initial: UInt16 = 0, to data: inout Data) {
        data.append(typeOffset)
        data.append(object ? 1 : 0)
        appendUInt16(0, to: &data)
        appendUInt16(initial, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        data.append(0)
        data.append(system ? 1 : 0)
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 0, through: 24, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    private func appendString(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        appendUInt16(UInt16(bytes.count), to: &data)
        data.append(bytes)
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
