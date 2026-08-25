import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 67 (backlog BB2a) — a colour the skin spelled out arrives as the colour it spelled out.
///
/// Reported as *"the embedded library panel is black, where the skin names a colour"*. The palette
/// wiring was never the problem: `reconcileHostedSurfaces` applies it on mount and on every theme
/// change, and `WinampModernSurfaceStyle.background` is `palette.contentBackground`. The colour was
/// being lost one layer lower, in resolution, and three separate faults did it — each one alone
/// enough to turn a declared colour into a fallback, and each one reaching skins well beyond the
/// library panel:
///
/// 1. **A colour resource may name another colour resource.** Big Bento Modern writes nearly its
///    whole palette that way (`wasabi.list.text` = `color.display`, `wasabi.list.background` =
///    `color.window.bg`). `resolvedColor` split the value on commas, found one token instead of
///    three, and returned `unparseableColor` — **white** — so a dark blue-grey skin drew white list
///    text on a white list.
/// 2. **Wasabi keeps bitmaps and colours in different tables.** One id may legitimately be both, and
///    Big Bento declares `wasabi.list.background` as a `<color>` in `system-colors.xml` *and* as a
///    tiled `<bitmap>` in `system-elements.xml`. With one flat registry the bitmap won, a colour
///    lookup found an image with no `color=` attribute, and the whole chain fell through to the
///    black literal — the black rectangle in the report.
/// 3. **`#rrggbb` is a literal too.** Enkera declares its entire palette in hex and Sony_Walkman its
///    analyzer (`colorband1="#808589"`); both resolved to `unparseableColor`, which drew opaque white
///    bars across Sony_Walkman's own wordmark. The parse existed but was gated off behind `if false`
///    in `8c7e0567` — whose message says it *"lands the inline #rrggbb colour parse"* and reports a
///    corpus sweep only reachable with it enabled, so the shipped build contradicted its own
///    verification.
///
/// The measured end state for Big Bento Modern is `contentBackground = rgb(55,57,64)` —
/// `color.window.bg` at `xml/system-colors.xml:30`, the same dark blue-grey as its chrome.
final class WinampModernPhase67Tests: XCTestCase {

    // MARK: - A colour resource that names another colour resource

    func testAColourValueMayNameAnotherColourResource() throws {
        let renderer = try renderer(resources: """
        <color id="color.window.bg" value="55,57,64"/>
        <color id="wasabi.list.background" value="color.window.bg"/>
        """)
        XCTAssertEqual(channels(renderer.resolvedColor("wasabi.list.background")), [55, 57, 64],
                       "the reference is followed to the literal behind it")
    }

    /// Bento's real shape: the referring declaration carries the gammagroup, the target carries the
    /// numbers. Tinting must happen once, by the group the id that was *asked for* names.
    func testAFollowedReferenceIsTintedOnceByTheReferringGammagroup() throws {
        let renderer = try renderer(resources: """
        <color id="color.display" value="147,175,185" gammagroup="DisplayText"/>
        <color id="wasabi.list.text" value="color.display" gammagroup="DisplayText"/>
        """)
        XCTAssertEqual(channels(renderer.resolvedColor("wasabi.list.text")), [147, 175, 185])
    }

    /// A skin can write `value="<its own id>"`, or a ring of them. The walk is bounded, so the worst
    /// case is a fallback colour rather than a hang.
    func testACircularReferenceTerminates() throws {
        let renderer = try renderer(resources: """
        <color id="a.loop" value="b.loop"/>
        <color id="b.loop" value="a.loop"/>
        """)
        _ = renderer.resolvedColor("a.loop")
    }

    // MARK: - Bitmaps and colours are different tables

    func testAColourLookupPrefersTheColourDeclarationOverASameNamedBitmap() throws {
        // Declaration order matters: the bitmap is registered *after* the colour, exactly as Big
        // Bento's `system-elements.xml` is included after `system-colors.xml`.
        let renderer = try renderer(resources: """
        <color id="wasabi.list.background" value="55,57,64"/>
        <bitmap id="wasabi.list.background" h="10" w="10" file="window/lists_bg.png"/>
        """)
        XCTAssertEqual(channels(renderer.palette.contentBackground), [55, 57, 64],
                       "the panel takes the skin's colour, not the black fallback")
    }

    /// The bitmap table is untouched by this: a `<bitmap>` lookup must still answer the bitmap, or a
    /// skin that tiles that image loses its artwork.
    func testTheBitmapTableStillAnswersTheBitmap() throws {
        let renderer = try renderer(resources: """
        <color id="wasabi.list.background" value="55,57,64"/>
        <bitmap id="wasabi.list.background" h="10" w="10" file="window/lists_bg.png"/>
        """)
        let definition = renderer.loadedSkin.runtime.resources
            .resolvedDefinition(identifier: "wasabi.list.background")
        XCTAssertEqual(definition?.kind, "bitmap")
        XCTAssertEqual(definition?.attributes["file"], "window/lists_bg.png")
    }

    /// A `$solid` bitmap *is* its `color=` attribute, and cPro-Bento relies on that reaching the
    /// palette — the case the kind-aware lookup must not regress.
    func testAGeneratedSolidBitmapStillAnswersAsAColour() throws {
        let renderer = try renderer(resources: """
        <bitmap id="wasabi.list.background" file="$solid" h="1" w="1" color="8,9,10"/>
        """)
        XCTAssertEqual(channels(renderer.palette.contentBackground), [8, 9, 10])
    }

    /// Ebonite_2_1's shape, and the reason a `$solid` cannot simply be "another colour declaration":
    /// it declares `wasabi.list.background` as a `<color>` at 70,70,70 ("lists/trees item
    /// background") **and** as a `$solid` at 237,237,237 ("Tree background bitmap (tile)"), the tile
    /// last. Its list text is white, so taking the tile painted white on near-white. A real `<color>`
    /// outranks a generated bitmap however late the bitmap is registered.
    func testARealColourOutranksAGeneratedBitmapWhicheverIsDeclaredLast() throws {
        let tileLast = try renderer(resources: """
        <color id="wasabi.list.background" value="70,70,70"/>
        <bitmap id="wasabi.list.background" file="$solid" h="10" w="10" color="237,237,237"/>
        """)
        XCTAssertEqual(channels(tileLast.palette.contentBackground), [70, 70, 70])

        let colorLast = try renderer(resources: """
        <bitmap id="wasabi.list.background" file="$solid" h="10" w="10" color="237,237,237"/>
        <color id="wasabi.list.background" value="70,70,70"/>
        """)
        XCTAssertEqual(channels(colorLast.palette.contentBackground), [70, 70, 70])
    }

    /// Two `<color>`s of the same id keep the ordinary last-wins rule — the ranking is only about
    /// *kind*, and a skin that genuinely redefines a colour later still means the later one.
    func testTwoColoursOfTheSameIdKeepLastWins() throws {
        let renderer = try renderer(resources: """
        <color id="wasabi.list.background" value="70,70,70"/>
        <color id="wasabi.list.background" value="12,34,56"/>
        """)
        XCTAssertEqual(channels(renderer.palette.contentBackground), [12, 34, 56])
    }

    // MARK: - `#rrggbb`

    func testAHexColourResourceResolves() throws {
        let renderer = try renderer(resources: ##"<color id="wasabi.list.background" value="#800000"/>"##)
        XCTAssertEqual(channels(renderer.palette.contentBackground), [128, 0, 0],
                       "Enkera declares its whole palette this way")
    }

    /// Sony_Walkman's analyzer, which drew opaque white over its own logo while the parse was gated
    /// off. This is the inline-attribute path, not the resource path.
    func testAHexColourInlineOnAnObjectResolves() throws {
        let pixels = try renderVis(attributes: ##"colorallbands="#808589""##)
        XCTAssertEqual(pixel(pixels, x: 2, y: 10), [0x80, 0x85, 0x89, 255],
                       "the grey the skin asked for, not unparseableColor's white")
    }

    /// The strictness that keeps the parse from swallowing identifiers: only a `#`-prefixed token is
    /// a hex literal, so a bare word stays a resource id.
    func testABareTokenIsStillTreatedAsAResourceIdentifier() throws {
        let renderer = try renderer(resources: #"<color id="abcdef" value="1,2,3"/>"#)
        XCTAssertEqual(channels(renderer.resolvedColor("abcdef")), [1, 2, 3])
    }

    // MARK: - The palette as a whole

    /// Every role names the chain it tries, so the `RENDER_PALETTE` probe reports the same chains the
    /// resolver walks rather than a second copy that can drift from them.
    func testEveryRoleDeclaresANonEmptyChain() {
        for role in WasabiPalette.Role.allCases {
            XCTAssertFalse(role.identifiers.isEmpty, "\(role.rawValue) has no identifiers")
        }
        XCTAssertEqual(WasabiPalette.Role.contentBackground.identifiers,
                       ["wasabi.edit.background", "studio.list.column.background",
                        "wasabi.list.background", "common.labelwnd.background"])
    }

    func testASkinThatDeclaresNothingStillLandsOnTheDocumentedFallbacks() throws {
        let renderer = try renderer(resources: "")
        XCTAssertEqual(channels(renderer.palette.contentBackground), [0, 0, 0])
        XCTAssertEqual(channels(renderer.palette.listText), [0, 255, 0])
    }

    // MARK: - Fixture

    private func channels(_ color: NSColor) -> [Int] {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return [] }
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
            .map { Int(($0 * 255).rounded()) }
    }

    private func pixel(_ pixels: [UInt8], x: Int, y: Int) -> [UInt8] {
        let offset = (y * 64 + x) * 4
        return Array(pixels[offset..<(offset + 4)])
    }

    private func renderer(resources: String) throws -> WasabiSceneRenderer {
        let xml = """
        <WasabiXML>
          <elements>
        \(resources)
          </elements>
          <container id="main">
            <layout id="normal" w="64" h="20"/>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func renderVis(attributes: String) throws -> [UInt8] {
        let xml = """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="64" h="20">
              <vis id="vis" x="0" y="0" w="64" h="20" \(attributes)/>
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
            .appendingPathComponent("WinampModernPhase67Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase67-\(UUID().uuidString).wal")
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
        var spectrumLevels: [Float] = Array(repeating: 1, count: 16)

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
