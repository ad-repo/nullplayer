import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 34 — Ujola Cat: the two console buttons that did nothing, the region masks that were being
/// painted as artwork, and the `<vis>` analyzer.
///
/// The four subjects, each measured on the smallest fixture that shows it:
///
/// 1. `Container.toggle()` — the whole behaviour of the skin's Color Themes and cat buttons, refused
///    by a fail-closed dispatch, and its direction read from the **host's** window state rather than
///    from a graph attribute the host never writes.
/// 2. A layer whose `sysregion` is negative contributes to the window region and is **not painted**.
/// 3. A `<vis>`'s inline band colours take the object's `gammagroup`, so the analyzer follows the
///    skin's colour themes like everything around it.
/// 4. The analyzer draws Winamp's **bands** on a decibel scale, with `colorbandpeak` caps.
final class WinampModernPhase34Tests: XCTestCase {
    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 240
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "Synthetic Song"
        var trackInfo = "Synthetic Artist"
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

    // MARK: - 1. `Container.toggle()`

    /// The method exists at all: before this, dispatch refused it and abandoned the handler that
    /// called it — which for Ujola Cat's buttons was the handler's only statement.
    func testToggleAsksTheHostToShowAHiddenWindow() throws {
        let (runtime, program) = try makeRuntime()
        let container = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "themes").first)
        var requests: [(String, Bool)] = []
        runtime.containerVisibilityRequested = { requests.append(($0, $1)) }
        runtime.containerVisibilityQuery = { _ in false }

        _ = try runtime.invoke(method: "toggle", on: MakiObjectReference(.gui(container.stableID)),
                               arguments: [], program: program)

        XCTAssertEqual(requests.map(\.0), ["themes"])
        XCTAssertEqual(requests.map(\.1), [true], "a window that is down comes up")
        XCTAssertEqual(container.attributes["visible"], "1")
    }

    /// The direction comes from the window, not from the attribute. `setAuxiliaryWindow`, the Windows
    /// menu and a window's own close button all move a window without writing `visible`, so a toggle
    /// that trusted the attribute inverted after the first manual close: the button then closed an
    /// already-closed window, and the user had to click twice to open it.
    func testToggleFollowsTheHostWindowWhenTheAttributeHasDrifted() throws {
        let (runtime, program) = try makeRuntime()
        let container = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "themes").first)
        // The state after "the script opened it, then the user closed the window itself".
        _ = container.setAttribute("visible", value: "1")
        var requests: [(String, Bool)] = []
        runtime.containerVisibilityRequested = { requests.append(($0, $1)) }
        runtime.containerVisibilityQuery = { _ in false }

        _ = try runtime.invoke(method: "toggle", on: MakiObjectReference(.gui(container.stableID)),
                               arguments: [], program: program)

        XCTAssertEqual(requests.map(\.1), [true], "the window is down, so toggle brings it up")
    }

    /// `isVisible()` answers about the same thing `toggle()` acts on.
    func testIsVisibleAnswersFromTheHostWindow() throws {
        let (runtime, program) = try makeRuntime()
        let container = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "themes").first)
        _ = container.setAttribute("visible", value: "1")
        runtime.containerVisibilityQuery = { _ in false }

        let answer = try runtime.invoke(method: "isVisible",
                                        on: MakiObjectReference(.gui(container.stableID)),
                                        arguments: [], program: program)
        XCTAssertFalse(answer.truthy, "the window is down, whatever the graph says")
    }

    /// Nothing in the headless path changes: with no host to ask, the attribute is still the answer,
    /// and a non-container (a group a script hides) never had a window to begin with.
    func testFallsBackToTheAttributeWithoutAHost() throws {
        let (runtime, program) = try makeRuntime()
        let group = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "drawer").first)
        _ = try runtime.invoke(method: "toggle", on: MakiObjectReference(.gui(group.stableID)),
                               arguments: [], program: program)
        XCTAssertEqual(group.attributes["visible"], "0", "a visible group toggles down")
        _ = try runtime.invoke(method: "toggle", on: MakiObjectReference(.gui(group.stableID)),
                               arguments: [], program: program)
        XCTAssertEqual(group.attributes["visible"], "1", "and back up")
    }

    /// B22 (reverted): `isVisible()` returns the object's **own** `visible` attribute, not a
    /// computed walk of the ancestor chain. Walking all ancestors broke cPro-Bento's tab system.
    /// Winamp's `GuiObject.isVisible()` reads the object's own attribute.
    func testIsVisibleReturnsTheObjectsOwnAttribute() throws {
        let xml = """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="32" h="32">
              <group id="tabs" x="0" y="0" w="32" h="16">
                <group id="tab_ml" x="0" y="0" w="32" h="16" visible="0">
                  <layer id="content" x="0" y="0" w="32" h="16"/>
                </group>
              </group>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [],
                                  bindings: [], instructions: [],
                                  source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                                  ownerID: nil, parameter: nil)

        // content has no `visible` attribute → defaults to visible. Its parent is hidden, but
        // isVisible reads only the object's own attribute (Winamp behavior).
        let content = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "content").first)
        let answer = try runtime.invoke(method: "isVisible",
                                        on: MakiObjectReference(.gui(content.stableID)),
                                        arguments: [], program: program)
        XCTAssertTrue(answer.truthy,
                      "isVisible returns the object's own attribute, not the computed ancestor visibility")

        // tab_ml has visible="0" → isVisible returns false for it directly.
        let tabML = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "tab_ml").first)
        let tabAnswer = try runtime.invoke(method: "isVisible",
                                           on: MakiObjectReference(.gui(tabML.stableID)),
                                           arguments: [], program: program)
        XCTAssertFalse(tabAnswer.truthy, "tab_ml's own attribute is visible=0")
    }

    /// B22, the half the revert left open: an object inside a **closed window** is not on screen,
    /// whatever its own attribute still says.
    ///
    /// Defix's `ML` round button sends `opentab ML` to its SUI, and the handler asks the
    /// media-library tab page whether it is already showing before deciding what the click means.
    /// The page keeps `visible="1"` from the last time that tab was selected, so with the SUI window
    /// shut it answered yes and every press took the "already showing — close it" branch: the button
    /// could only ever shut a window the menu had opened. The **window** is the outer term here, and
    /// it is a different question from the hidden parent *group* the revert above is about.
    func testIsVisibleIsFalseForAnObjectInsideAClosedWindow() throws {
        let (runtime, program, page) = try makeTabPageRuntime()
        runtime.containerVisibilityQuery = { $0.caseInsensitiveCompare("sui") == .orderedSame ? false : nil }

        let answer = try runtime.invoke(method: "isVisible",
                                        on: MakiObjectReference(.gui(page.stableID)),
                                        arguments: [], program: program)
        XCTAssertFalse(answer.truthy, "the window it lives in is down, so nothing in it is visible")
    }

    /// And the revert still holds *inside* an open window: the object's own attribute is the answer,
    /// with the ancestor groups between it and the window not consulted. This is the cPro-Bento case
    /// — a script shows a tab page whose parent group is still hidden — measured with a host present,
    /// which is the arrangement the check above added.
    func testIsVisibleReadsTheAttributeWhenTheWindowIsOpen() throws {
        let (runtime, program, page) = try makeTabPageRuntime()
        runtime.containerVisibilityQuery = { _ in true }

        let answer = try runtime.invoke(method: "isVisible",
                                        on: MakiObjectReference(.gui(page.stableID)),
                                        arguments: [], program: program)
        XCTAssertTrue(answer.truthy, "the window is up, so the page's own attribute is the answer")
    }

    /// A tab page carrying `visible="1"` inside a hidden group, inside a named auxiliary window —
    /// the shape of Defix's `wdh.ml` under its `SUI`.
    private func makeTabPageRuntime() throws
        -> (WinampModernScriptRuntime, MakiProgram, WasabiObject) {
        let xml = """
        <WasabiXML>
          <container id="sui">
            <layout id="normal" w="32" h="32">
              <group id="sui.content" x="0" y="0" w="32" h="32" visible="0">
                <group id="wdh.ml" x="0" y="0" w="32" h="32" visible="1"/>
              </group>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [],
                                  bindings: [], instructions: [],
                                  source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                                  ownerID: nil, parameter: nil)
        let page = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "wdh.ml").first)
        return (runtime, program, page)
    }

    // MARK: - 2. Negative `sysregion` is a mask, not artwork

    /// `sysregion="-2"` means "contribute to the window region, do not paint". Its bitmap is a
    /// silhouette — Ujola Cat's is magenta and white — and drawn as an ordinary layer it covered the
    /// title strips of every framed window the skin owns. 11 of the 18 installed skins carry one.
    func testNegativeSysregionLayerIsNotPainted() throws {
        let pixels = try renderScene(body: """
            <layer id="mask" x="0" y="0" image="sheet" sysregion="-2"/>
            """)
        XCTAssertEqual(alpha(pixels, x: 4, y: 4), 0, "a region mask is not artwork")
    }

    /// Only the sign is read. Ujola's own console art is `sysregion="1"` on real bitmaps, and Anexa
    /// writes the non-numeric `"AND"` fifteen times; both must paint exactly as before.
    func testPositiveAndNonNumericSysregionStillPaint() throws {
        for value in ["1", "0", "AND"] {
            let pixels = try renderScene(body: """
                <layer id="art" x="0" y="0" image="sheet" sysregion="\(value)"/>
                """)
            XCTAssertEqual(alpha(pixels, x: 4, y: 4), 255, "sysregion=\(value) is still drawn")
        }
    }

    // MARK: - 3. The analyzer takes the object's `gammagroup`

    /// Ujola Cat declares all 22 of its vis colours as inline `r,g,b` triples under
    /// `gammagroup="Energy"`. Resolved through the *named-resource* path an inline triple comes back
    /// untinted, so the analyzer stayed lime green through every one of the skin's colour themes
    /// while the rest of the skin recoloured — which is the one thing the skin's author asked people
    /// to go and play with.
    func testInlineBandColoursAreTintedByTheActiveTheme() throws {
        let host = Host()
        host.spectrumLevels = Array(repeating: 1, count: 32)
        let pixels = try renderScene(body: """
            <vis id="vis" x="0" y="0" w="16" h="16" colorallbands="200,200,200" gammagroup="Energy"/>
            """, host: host, gammasets: """
            <gammaset id="Red">
              <gammagroup id="Energy" value="4096,-4096,-4096"/>
            </gammaset>
            """)
        let bar = colour(pixels, x: 0, y: 15)
        XCTAssertGreaterThan(bar[0], 200, "the red channel is boosted by the theme")
        XCTAssertLessThan(bar[1], 100, "and green and blue are pulled down")
        XCTAssertLessThan(bar[2], 100)
    }

    // MARK: - 4. Bands, on a decibel scale, with peak caps

    /// The bar is as tall as `getVisBand` says it is. Both read the same mono tap, and the tap is a
    /// linear magnitude: drawn linearly, ordinary music sits in the bottom of the box (Phase 29 found
    /// the same fault in the VU meter, Phase 30 in `getVisBand`; the drawn analyzer was the third
    /// site). −20 dBFS is two thirds of the way up a 60 dB window, not a tenth of the way.
    func testBarHeightIsTheDecibelScaleGetVisBandAnswersIn() throws {
        let host = Host()
        host.spectrumLevels = Array(repeating: 0.1, count: 19)     // −20 dBFS
        let pixels = try renderScene(body: """
            <vis id="vis" x="0" y="0" w="16" h="16" colorallbands="255,0,0"/>
            """, host: host)
        let painted = (0..<16).filter { alpha(pixels, x: 0, y: $0) > 0 }.count
        // Times the analyzer's calibration gain (B53): three engines can paint this box now, and
        // Winamp's own read hot against the other two off exactly this decibel curve. The *shape* is
        // what this test is about and is unchanged — the sweep still decides the height.
        let sweep = Double(WinampModernScriptRuntime.visByte(forMagnitude: 0.1)) / 255
        let expected = Int((sweep * Double(WasabiVisStyle.Gain.builtInAnalyzer) * 16).rounded())
        XCTAssertEqual(painted, expected, accuracy: 1, "the bar follows the dB sweep")
        XCTAssertGreaterThan(painted, 6, "and −20 dBFS is well clear of the floor")
    }

    /// Silence stays silent — the floor of the sweep is 0, not a permanent stub of a bar.
    func testSilenceDrawsNothing() throws {
        let host = Host()
        host.spectrumLevels = Array(repeating: 0, count: 19)
        let pixels = try renderScene(body: """
            <vis id="vis" x="0" y="0" w="16" h="16" colorallbands="255,0,0"/>
            """, host: host)
        XCTAssertTrue((0..<16).allSatisfy { alpha(pixels, x: 0, y: $0) == 0 })
    }

    /// `colorbandpeak` is a falling cap over the bar, and it is painted in its own colour. A skin that
    /// declares one and never sees it has lost half of what its analyzer looks like.
    func testPeakCapIsDrawnInItsOwnColourAsTheBarFalls() throws {
        let host = Host()
        host.spectrumLevels = Array(repeating: 1, count: 19)
        let (loaded, renderer) = try makeScene(body: """
            <vis id="vis" x="0" y="0" w="16" h="16" colorallbands="0,0,255" colorbandpeak="255,0,0"/>
            """, host: host)
        addTeardownBlock { loaded.teardown() }
        _ = try render(renderer: renderer, size: 16)                // full-scale frame: peaks at the top
        host.spectrumLevels = Array(repeating: 0, count: 19)
        let pixels = try render(renderer: renderer, size: 16)       // silence: the cap is still falling

        // The cap sits on a fractional row, so its edge is antialiased: the channels are compared
        // against the alpha they are premultiplied by, not against 255.
        let capRow = try XCTUnwrap((0..<16).max(by: { alpha(pixels, x: 0, y: $0) < alpha(pixels, x: 0, y: $1) }),
                                   "the cap outlives the bar under it")
        let coverage = alpha(pixels, x: 0, y: capRow)
        XCTAssertGreaterThan(coverage, 0, "something is still drawn after the bar has fallen away")
        let colour = colour(pixels, x: 0, y: capRow)
        XCTAssertEqual(colour[0], coverage, accuracy: 2, "painted in colorbandpeak…")
        XCTAssertLessThan(colour[2], 8, "…not in the band's own blue")
    }

    // MARK: - Fixtures

    private func makeRuntime() throws -> (WinampModernScriptRuntime, MakiProgram) {
        let xml = """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="32" h="32">
              <group id="drawer" x="0" y="0" w="16" h="16"/>
            </layout>
          </container>
          <container id="themes">
            <layout id="normal" w="32" h="32"/>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [],
                                  bindings: [], instructions: [],
                                  source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                                  ownerID: nil, parameter: nil)
        return (runtime, program)
    }

    private func makeScene(body: String, host: Host = Host(),
                           gammasets: String = "") throws -> (WinampModernLoadedSkin, WasabiSceneRenderer) {
        let xml = """
        <WasabiXML>
          <elements>
            <bitmap id="sheet" file="sheet.png"/>
          </elements>
          \(gammasets)
          <container id="main">
            <layout id="normal" w="16" h="16">
        \(body)
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        return (loaded, try WasabiSceneRenderer(loadedSkin: loaded, host: host))
    }

    private func renderScene(body: String, host: Host = Host(),
                             gammasets: String = "") throws -> [UInt8] {
        let (loaded, renderer) = try makeScene(body: body, host: host, gammasets: gammasets)
        addTeardownBlock { loaded.teardown() }
        return try render(renderer: renderer, size: 16)
    }

    private func render(renderer: WasabiSceneRenderer, size: Int) throws -> [UInt8] {
        addTeardownBlock { renderer.teardown() }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: size, height: size,
                                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            renderer.draw(in: context)
        }
        return pixels
    }

    private func alpha(_ pixels: [UInt8], x: Int, y: Int, width: Int = 16) -> Int {
        Int(pixels[(y * width + x) * 4 + 3])
    }

    private func colour(_ pixels: [UInt8], x: Int, y: Int, width: Int = 16) -> [Int] {
        let offset = (y * width + x) * 4
        return (0..<3).map { Int(pixels[offset + $0]) }
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase34Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase34-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in [("skin.xml", Data(xml.utf8)), ("sheet.png", try makePNG())] {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    private func makePNG() throws -> Data {
        var pixels = [UInt8](repeating: 200, count: 16 * 16 * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) { pixels[offset + 3] = 255 }
        var copy = pixels
        let image = try copy.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 16, height: 16,
                                                  bitsPerComponent: 8, bytesPerRow: 16 * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        pixels = []
        let representation = NSBitmapImageRep(cgImage: image)
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }
}
