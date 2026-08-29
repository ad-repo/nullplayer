import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 17 — the MMD3 defect sweep. Every case here was measured against `mmd3.wal` first and then
/// reduced to a synthetic skin, so the fixture is self-authored and the test runs everywhere.
final class WinampModernPhase17Tests: XCTestCase {
    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .playing
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 240
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "Title"
        var trackInfo = "Artist - Album"
        var trackDisplayTitle = "Artist - Title"
        var bitrateKbps = 320
        var sampleRateHz = 44_100
        var channelCount = 2
        var spectrumLevels: [Float] = [0.2, 0.9, 0.5, 1]
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

    /// A skin whose bitmap font names a **path** (MMD3's form) alongside one that names a declared
    /// bitmap (the stock Winamp Modern form), plus the text bindings, the overlapping groups the hit
    /// test has to see through, and a `<vis>` whose mode is switched.
    private static let skinXML = """
    <WasabiXML>
      <elements>
        <bitmap id="sheet" file="sheet.png"/>
        <bitmap id="panel" file="sheet.png" x="0" y="0" w="8" h="8"/>
        <bitmapfont id="path.font" file="font/glyphs.png" charwidth="8" charheight="8"/>
        <bitmapfont id="id.font" file="sheet" charwidth="8" charheight="8"/>
      </elements>
      <container id="main">
        <layout id="normal" w="120" h="64">
          <group id="under" x="0" y="0" w="40" h="20" background="panel">
            <button id="tab" x="0" y="0" w="10" h="10" image="panel"/>
          </group>
          <AnimatedLayer id="knob" image="panel" x="60" y="30" w="8" h="8"/>
          <text id="system.font" text="AAAA" font="Helvetica" fontsize="20" bold="1"
                x="0" y="20" w="56" h="40"/>
          <text id="title" display="songname" font="path.font" x="0" y="40" w="112" h="8"/>
          <text id="info" display="songinfo" x="0" y="48" w="112" h="8"/>
          <text id="ticker" display="songname" alternatetext="placeholder" x="0" y="56" w="112" h="8"/>
          <vis id="scope" mode="3" x="60" y="0" w="40" h="20" colorband1="255,0,0"/>
          <group id="over" x="0" y="0" w="120" h="64" move="1" sysregion="1"/>
        </layout>
      </container>
    </WasabiXML>
    """

    // MARK: - 17.1  Text

    func testBitmapFontSheetResolvesByPathAsWellAsByIdentifier() throws {
        let (loaded, renderer, _) = try makeSkin()
        let byPath = try XCTUnwrap(loaded.runtime.resources.resolvedDefinition(identifier: "path.font"))
        let byIdentifier = try XCTUnwrap(loaded.runtime.resources.resolvedDefinition(identifier: "id.font"))
        // The path form is the one that used to return nil, taking every string drawn with it out of
        // the scene without a diagnostic.
        XCTAssertNotNil(byPath.logicalFile)
        XCTAssertNotNil(renderer.resources.fontSheet(for: byPath))
        XCTAssertNil(byIdentifier.logicalFile)
        XCTAssertNotNil(renderer.resources.fontSheet(for: byIdentifier))
    }

    func testTextDrawnWithAPathBackedBitmapFontReachesTheCanvas() throws {
        let (_, renderer, _) = try makeSkin()
        let pixels = try render(renderer)
        // The title's row is the only thing in this band, so any opaque pixel there is its glyphs.
        XCTAssertTrue(hasOpaquePixel(pixels, canvas: renderer.canvasSize,
                                     in: CGRect(x: 0, y: 40, width: 112, height: 8)),
                      "A path-backed bitmap font must draw glyphs")
    }

    func testSystemFontFamilyAndBoldAreResolvedAtAPixelHeight() throws {
        let (loaded, renderer, _) = try makeSkin()
        let object = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "system.font").first)
        // `fontsize` is a pixel height, not a point size (Love is War Miku's 30px time readout draws
        // at a 24pt em); taken at face value every string is a quarter too big for its box.
        let size = WasabiTextMetrics.pointSize(of: object)
        XCTAssertEqual(size, 16, accuracy: 0.001)
        // A skin that declares no font resource names one it expects the system to have. Resolving
        // only declared resources drew all of those in the monospaced fallback.
        let font = try XCTUnwrap(renderer.resources.font(identifier: object.attributes["font"],
                                                        size: size,
                                                        traits: WasabiTextMetrics.traits(of: object)))
        XCTAssertEqual(font.familyName, "Helvetica")
        XCTAssertEqual(font.pointSize, 16, accuracy: 0.001)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    func testTextIsCentredInItsBoxRatherThanDrawnFromTheTop() throws {
        let (_, renderer, _) = try makeSkin()
        let pixels = try render(renderer)
        // The box is 40px tall around a ~18px line, so the two conventions are ~11px apart. Top of
        // the box stays clear; the glyphs sit in the middle band. (`x < 56` keeps the knob out.)
        XCTAssertFalse(hasOpaquePixel(pixels, canvas: renderer.canvasSize,
                                      in: CGRect(x: 0, y: 21, width: 56, height: 9)),
                       "Text must not be drawn from the top edge of its box")
        XCTAssertTrue(hasOpaquePixel(pixels, canvas: renderer.canvasSize,
                                     in: CGRect(x: 0, y: 34, width: 56, height: 12)),
                      "Text must be drawn centred in its box")
    }

    func testDisplayBindingsCarryTheValuesTheSkinsScriptsRead() throws {
        let (loaded, _, _) = try makeSkin()
        let host = Host()
        let title = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "title").first)
        let info = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "info").first)
        // `songname` is the playlist display title — dropping the artist is what report #1 was.
        XCTAssertEqual(WasabiTextMetrics.content(of: title, host: host), "Artist - Title")
        // `songinfo` is the stream-info line a `songinfo.maki` tokenises for kbps/khz, not the
        // artist/album. The units must stay attached to their numbers.
        XCTAssertEqual(WasabiTextMetrics.content(of: info, host: host), "320kbps stereo 44khz")
    }

    func testAlternateTextIsAPlaceholderInXMLAndAnOverrideFromAScript() throws {
        let (loaded, _, runtime) = try makeSkin()
        let host = Host()
        let ticker = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "ticker").first)
        let reference = MakiObjectReference(.gui(ticker.stableID))
        let program = Self.makeProgram()

        // Declared in XML: a placeholder, shown only when the binding has nothing to say.
        XCTAssertEqual(WasabiTextMetrics.content(of: ticker, host: host), "Artist - Title")
        host.trackDisplayTitle = ""
        XCTAssertEqual(WasabiTextMetrics.content(of: ticker, host: host), "placeholder")
        host.trackDisplayTitle = "Artist - Title"

        // Set by a script: an override, for as long as it is set.
        _ = try runtime.invoke(method: "setalternatetext", on: reference,
                               arguments: [.string("VOLUME: 40%")], program: program)
        XCTAssertEqual(WasabiTextMetrics.content(of: ticker, host: host), "VOLUME: 40%")
        // `setText` is how a skin takes it back down (MMD3's ticker timer fires exactly this).
        _ = try runtime.invoke(method: "settext", on: reference, arguments: [.string("")],
                               program: program)
        XCTAssertEqual(WasabiTextMetrics.content(of: ticker, host: host), "Artist - Title")
    }

    func testGetTextAnswersWithWhatTheObjectShows() throws {
        let (loaded, _, runtime) = try makeSkin()
        let info = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "info").first)
        let value = try runtime.invoke(method: "gettext", on: MakiObjectReference(.gui(info.stableID)),
                                       arguments: [], program: Self.makeProgram())
        XCTAssertEqual(value.stringValue, "320kbps stereo 44khz")
    }

    // MARK: - 17.2  Hit testing

    func testABareGroupDoesNotSwallowClicksMeantForWhatIsUnderIt() throws {
        let (_, renderer, _) = try makeSkin()
        // `over` is declared last, covers the whole layout and carries `move="1"`. It has no artwork,
        // so in Wasabi it has no region of its own — the button beneath it must still take the click.
        XCTAssertEqual(renderer.object(at: CGPoint(x: 5, y: 5))?.xmlID, "tab")
        // A group that paints a background *does* have a region and still claims its own area.
        XCTAssertEqual(renderer.object(at: CGPoint(x: 30, y: 15))?.xmlID, "under")
        // And nothing else is under this point, so the bare group claims nothing at all.
        XCTAssertNil(renderer.object(at: CGPoint(x: 110, y: 60)))
    }

    func testAnimatedLayersTakeClicks() throws {
        let (_, renderer, _) = try makeSkin()
        // MMD3's rotary volume/bass/treble knobs are animated layers with `onLeftButtonDown` handlers.
        XCTAssertEqual(renderer.object(at: CGPoint(x: 64, y: 34))?.xmlID, "knob")
    }

    // MARK: - 17.3  Visualization mode

    func testVisualizationIsDrawnOnlyInTheModesThatAskForIt() throws {
        let (loaded, renderer, _) = try makeSkin()
        let box = CGRect(x: 60, y: 0, width: 40, height: 20)
        let scope = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "scope").first)

        // Mode 3 is what MMD3 ships and what its script sets whenever its own animated display is
        // showing — our bars over the top of it was report #3.
        XCTAssertFalse(hasOpaquePixel(try render(renderer), canvas: renderer.canvasSize, in: box))
        _ = scope.setAttribute("mode", value: "0")
        XCTAssertFalse(hasOpaquePixel(try render(renderer), canvas: renderer.canvasSize, in: box))
        _ = scope.setAttribute("mode", value: "2")
        XCTAssertTrue(hasOpaquePixel(try render(renderer), canvas: renderer.canvasSize, in: box))
        _ = scope.setAttribute("mode", value: "1")
        XCTAssertTrue(hasOpaquePixel(try render(renderer), canvas: renderer.canvasSize, in: box))
    }

    // MARK: - Fixture

    private func makeSkin() throws -> (WinampModernLoadedSkin, WasabiSceneRenderer, WinampModernScriptRuntime) {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive())
        addTeardownBlock { loaded.teardown() }
        let host = Host()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { runtime.teardown() }
        return (loaded, renderer, runtime)
    }

    private static func makeProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/test.maki"),
                    ownerID: nil, parameter: nil)
    }

    /// Render the current scene and hand back straight RGBA bytes, top-left origin.
    private func render(_ renderer: WasabiSceneRenderer) throws -> [UInt8] {
        let size = renderer.canvasSize
        let width = Int(size.width)
        let height = Int(size.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            // `drawText` ends in `NSString.draw`, which paints into the *current* NSGraphicsContext.
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            renderer.draw(in: context)
            NSGraphicsContext.current = previous
        }
        return pixels
    }

    /// Whether anything opaque landed inside a rect given in Wasabi (top-left) coordinates.
    private func hasOpaquePixel(_ pixels: [UInt8], canvas: CGSize, in rect: CGRect) -> Bool {
        let width = Int(canvas.width)
        let height = Int(canvas.height)
        // A bitmap context stores its rows top-down, and the renderer has already applied its own
        // flip, so a memory row index *is* a Wasabi y.
        for y in Int(rect.minY)..<min(height, Int(rect.maxY)) {
            for x in Int(rect.minX)..<min(width, Int(rect.maxX)) where pixels[(y * width + x) * 4 + 3] > 8 {
                return true
            }
        }
        return false
    }

    private func makeArchive() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase17Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let sheet = try makePNG(width: 256, height: 32)
        let entries: [(String, Data)] = [("skin.xml", Data(Self.skinXML.utf8)),
                                         ("sheet.png", sheet),
                                         ("font/glyphs.png", sheet)]
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
            pixels[offset + 1] = 80
            pixels[offset + 2] = 160
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
