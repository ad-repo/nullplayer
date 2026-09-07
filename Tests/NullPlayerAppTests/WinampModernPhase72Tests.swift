import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 72 — BB32: the enlarged playlist's album art opened at half height.
///
/// Two independent faults, both in the machinery around `<Wasabi:Frame>`:
///
/// 1. **`attribute.onDataChanged()` was inert.** It is how a skin applies its *stored* settings at
///    load — a `cfgattrib` handler otherwise only ever fires on a change, so an option nobody touched
///    this launch never reaches the layout. Big Bento Modern's `pledit` ends `onScriptLoaded` with it
///    and drives the enlarged playlist, its album-art splitter and its search box from there. The
///    method had an arity but was missing from `dispatchableEventArity`, so the call fell through to
///    a `return .null`.
///
///    What made that expensive rather than cosmetic: the splitter therefore kept its `height="120"`
///    markup seed, and the same script's `onScriptUnloading` persists `getPosition()` into the skin's
///    own config. One quit wrote the seed over the skin's own 335px default, permanently. **A call we
///    answer with nothing becomes a value we invented, as soon as the skin saves what it read back.**
///
/// 2. **A horizontal splitter was bounded by `minwidth`.** `playlist.dualwnd` carries `minheight="100"`
///    beside a leftover `minwidth="313"`, and the limit lookup read the width names first whatever the
///    axis — so one drag snapped the cover pane to a 313px floor for a *height*, with no way back.
final class WinampModernPhase72Tests: XCTestCase {

    // MARK: - `onDataChanged` as a method

    /// The arity contract, which is what the dispatch below rides on: zero arguments, no result. This
    /// one passed before the fix as well — `onDataChanged` was already in the *method* table, which is
    /// exactly why the defect was invisible from here and had to be caught by the dispatch test.
    func testOnDataChangedIsDispatchableWithNoArguments() throws {
        let (runtime, _) = try makeRuntime()
        let signature = try XCTUnwrap(runtime.signature(for: "onDataChanged", classGUID: nil),
                                      "a skin applies its stored settings by calling this")
        XCTAssertEqual(signature.argumentCount, 0)
        XCTAssertEqual(signature.returnKind, .null)
    }

    /// Calling the handler runs it, rather than being swallowed. Before the fix this reached
    /// `case "callme", "ondatachanged": return .null` and dispatched nothing — the shape of the whole
    /// defect, on the one receiver whose dispatch a test can observe directly.
    func testCallingOnDataChangedDispatchesTheHandler() throws {
        let (runtime, _) = try makeRuntime()
        runtime.recordsDispatchedEventsForTesting = true
        let button = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "enlarge").first)

        _ = try runtime.invoke(method: "ondatachanged",
                               on: MakiObjectReference(.gui(button.stableID)),
                               arguments: [], program: makeProgram())

        XCTAssertTrue(runtime.dispatchedEventsForTesting
            .contains { $0.object == "enlarge" && $0.event == "ondatachanged" })
    }

    /// And it stays a *dispatch*, not a config write: running the handler must not change the value
    /// the handler is about, or a skin re-asserting its own state at load would rewrite the user's
    /// settings on every launch.
    func testCallingOnDataChangedDoesNotWriteTheAttribute() throws {
        let (runtime, loaded) = try makeRuntime()
        loaded.configuration.setString("1", section: "{0167CFD9}", key: "Enlarge Playlist")
        let button = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "enlarge").first)

        _ = try runtime.invoke(method: "ondatachanged",
                               on: MakiObjectReference(.gui(button.stableID)),
                               arguments: [], program: makeProgram())

        XCTAssertEqual(loaded.configuration.string(section: "{0167CFD9}", key: "Enlarge Playlist"), "1")
    }

    // MARK: - The splitter's own axis

    /// Big Bento's `playlist.dualwnd`, to the attribute: the side playlist over its album art, with
    /// both spellings of the minimum present and only one of them meant for this axis.
    private static let coverSplitter = """
    <groupdef id="pane.playlist"><text id="pl" text="P" x="0" y="0" w="10" h="10"/></groupdef>
    <groupdef id="pane.cover"><text id="cv" text="C" x="0" y="0" w="10" h="10"/></groupdef>
    <layout id="normal" w="340" h="820" default_w="340" default_h="820">
      <Wasabi:Frame id="playlist.dualwnd" x="0" y="0" w="0" h="0" relatw="1" relath="1"
                    top="pane.playlist" bottom="pane.cover" orientation="h"
                    from="bottom" height="120" minheight="100" minwidth="313"/>
    </layout>
    """

    /// The drag that could not be undone. `minheight="100"` is this frame's own floor; the leftover
    /// `minwidth="313"` belongs to the axis it does not split.
    func testAHorizontalDividerIsBoundedByItsHeightLimits() throws {
        let renderer = try makeRenderer(layout: Self.coverSplitter)
        let divider = try XCTUnwrap(renderer.frameDividers().first)
        renderer.dragFrameDivider(divider.object, to: CGPoint(x: 170, y: 700))
        XCTAssertEqual(WasabiFrame.position(of: divider.object), 120,
                       "820 − 700, comfortably above the 100 floor and nowhere near 313")

        renderer.dragFrameDivider(divider.object, to: CGPoint(x: 170, y: 800))
        XCTAssertEqual(WasabiFrame.position(of: divider.object), 100, "`minheight`, not `minwidth`")
    }

    /// The fallback the change must not break: ClassicPro's `centro.plframe` is horizontal and spells
    /// its bounds `minwidth`/`maxwidth` with no height names at all.
    func testAHorizontalDividerStillFallsBackToTheWidthNames() throws {
        let renderer = try makeRenderer(layout: """
        <groupdef id="pane.top"><text id="t" text="T" x="0" y="0" w="10" h="10"/></groupdef>
        <groupdef id="pane.bottom"><text id="b" text="B" x="0" y="0" w="10" h="10"/></groupdef>
        <layout id="normal" w="400" h="400" default_w="400" default_h="400">
          <Wasabi:Frame id="plframe" x="0" y="0" w="0" h="0" relatw="1" relath="1"
                        top="pane.top" bottom="pane.bottom" orientation="h"
                        from="top" height="200" minwidth="150" maxwidth="-120"/>
        </layout>
        """)
        let divider = try XCTUnwrap(renderer.frameDividers().first)
        renderer.dragFrameDivider(divider.object, to: CGPoint(x: 200, y: 10))
        XCTAssertEqual(WasabiFrame.position(of: divider.object), 150, "`minwidth` on a horizontal frame")
        renderer.dragFrameDivider(divider.object, to: CGPoint(x: 200, y: 390))
        XCTAssertEqual(WasabiFrame.position(of: divider.object), 280, "`maxwidth=-120` from the far edge")
    }

    /// A vertical frame is unchanged — the width names are its own, and a stray `minheight` must not
    /// start bounding it.
    func testAVerticalDividerIgnoresAStrayHeightLimit() throws {
        let renderer = try makeRenderer(layout: """
        <groupdef id="pane.left"><text id="l" text="L" x="0" y="0" w="10" h="10"/></groupdef>
        <groupdef id="pane.right"><text id="r" text="R" x="0" y="0" w="10" h="10"/></groupdef>
        <layout id="normal" w="500" h="300" default_w="500" default_h="300">
          <Wasabi:Frame id="split" x="0" y="0" w="0" h="0" relatw="1" relath="1"
                        left="pane.left" right="pane.right" orientation="vertical"
                        from="left" width="200" minwidth="158" minheight="400"/>
        </layout>
        """)
        let divider = try XCTUnwrap(renderer.frameDividers().first)
        renderer.dragFrameDivider(divider.object, to: CGPoint(x: 10, y: 150))
        XCTAssertEqual(WasabiFrame.position(of: divider.object), 158)
    }

    /// What the skin's settings pass is *for*: the position it writes is the height the cover pane
    /// gets, measured from the bottom. 335 is Big Bento's own default and 120 the markup seed the
    /// dead call left it on — the visible difference between a square cover and a squashed strip.
    func testThePositionAScriptWritesIsTheBottomPanesHeight() throws {
        let renderer = try makeRenderer(layout: Self.coverSplitter)
        let divider = try XCTUnwrap(renderer.frameDividers().first)
        XCTAssertEqual(WasabiFrame.position(of: divider.object), 120, "the markup seed")

        WasabiFrame.setPosition(335, on: divider.object)
        let cover = try XCTUnwrap(divider.object.children
            .first { $0.xmlID?.caseInsensitiveCompare("pane.cover") == .orderedSame })
        XCTAssertEqual(cover.attributes["h"], "331", "335 less the divider's own half-thickness")
        XCTAssertEqual(cover.attributes["y"], "-331")
        XCTAssertEqual(cover.attributes["relaty"], "1", "measured from the bottom edge")
    }

    // MARK: - Fixtures

    private func makeProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                    ownerID: nil, parameter: nil)
    }

    private func makeRuntime() throws -> (WinampModernScriptRuntime, WinampModernLoadedSkin) {
        let loaded = try makeSkin(layout: """
        <layout id="normal" w="200" h="200" default_w="200" default_h="200">
          <togglebutton id="enlarge" x="0" y="0" w="20" h="20"
                        cfgattrib="{0167CFD9};Enlarge Playlist"/>
        </layout>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        return (runtime, loaded)
    }

    private func makeRenderer(layout: String) throws -> WasabiSceneRenderer {
        let renderer = try WasabiSceneRenderer(loadedSkin: makeSkin(layout: layout), host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeSkin(layout: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase72Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase72-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data("""
        <WasabiXML>
          <container id="main">
            \(layout)
          </container>
        </WasabiXML>
        """.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
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
