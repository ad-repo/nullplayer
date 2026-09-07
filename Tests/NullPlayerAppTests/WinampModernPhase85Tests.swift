import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 85 — `<Wasabi:TabSheet>` (B14).
///
/// A tab sheet **names its pages by group id** rather than nesting them, and in Winamp the standard
/// library's own object instantiates them, draws a tab per page and shows one at a time. No `.wal`
/// supplies that object, so the tag resolved to an identifier-only shell: the sheet drew nothing and
/// every page stayed out of the graph. Shield_Amp's Configuration window is one tab sheet over three
/// groups whose form widgets are all implemented, and it came up as an empty slab.
///
/// Measured: 4 skins declare 5 sheets. Two are reachable — Anexa's colour window (three pages, no
/// tab artwork) and Shield_Amp's notifier preferences (three pages, the conventional
/// `wasabi.tabsheet.button.*` bitmaps). Enkera declares two in an `xml/config.xml` its `skin.xml`
/// never `<include>`s, and mmd3's winshade sidecar names no `children` at all — it hosts a *window*
/// through `windowtype=`, which is deliberately left alone.
final class WinampModernPhase85Tests: XCTestCase {

    // MARK: - The pages enter the graph

    /// The defect itself: not one page was in the graph, so the sheet was a hole the size of the
    /// window. All three arrive, in `children=` order, as children of the sheet.
    func testASheetInstantiatesEveryPageItNames() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="350" h="440" default_w="350" default_h="440">
          <Wasabi:TabSheet id="sheet" x="20" y="25" w="310" h="370"
                           children="config.stuff;themes.stuff;changelog.stuff"/>
        </layout>
        """, groups: """
        <groupdef id="config.stuff" name="notifier preferences">
          <text id="config.label" x="0" y="0" w="100" h="12" text="Effects"/>
        </groupdef>
        <groupdef id="themes.stuff" name="Themes">
          <text id="themes.label" x="0" y="0" w="100" h="12" text="Themes"/>
        </groupdef>
        <groupdef id="changelog.stuff" name="Changelog">
          <text id="changelog.label" x="0" y="0" w="100" h="12" text="Changelog"/>
        </groupdef>
        """)
        let graph = renderer.loadedSkin.runtime.graph
        let sheet = try XCTUnwrap(graph.objects(xmlID: "sheet").first)

        let pages = WasabiTabSheet.pages(of: sheet)
        XCTAssertEqual(pages.compactMap(\.xmlID),
                       ["config.stuff", "themes.stuff", "changelog.stuff"])
        // And the pages' own bodies came with them — the widget is worth nothing if the groups
        // arrive empty.
        XCTAssertEqual(graph.objects(xmlID: "themes.label").count, 1)
    }

    /// One page at a time, and it is the first by default. Visibility is the whole mechanism: an
    /// invisible object leaves the scene with its subtree, so a hidden page neither draws nor answers
    /// the pointer and nothing else in the renderer needs to know a tab sheet exists.
    func testOnlyTheSelectedPageIsVisible() throws {
        let renderer = try makeRenderer(layout: Self.threePageLayout, groups: Self.threePageGroups)
        let graph = renderer.loadedSkin.runtime.graph
        let sheet = try XCTUnwrap(graph.objects(xmlID: "sheet").first)
        let pages = WasabiTabSheet.pages(of: sheet)

        XCTAssertEqual(pages.map { $0.attributes["visible"] }, ["1", "0", "0"])
        XCTAssertEqual(WasabiTabSheet.selectedIndex(of: sheet), 0)
        // A hidden page really is out of the drawn scene, which is what makes the swap complete.
        XCTAssertNil(renderer.frame(of: pages[1]))
        XCTAssertNotNil(renderer.frame(of: pages[0]))
    }

    /// Selecting the second page shows it and puts the first away, and the sheet remembers which.
    func testSelectingAPageSwapsWhichOneIsVisible() throws {
        let renderer = try makeRenderer(layout: Self.threePageLayout, groups: Self.threePageGroups)
        let graph = renderer.loadedSkin.runtime.graph
        let sheet = try XCTUnwrap(graph.objects(xmlID: "sheet").first)
        let pages = WasabiTabSheet.pages(of: sheet)

        XCTAssertTrue(WasabiTabSheet.select(index: 1, on: sheet))
        XCTAssertEqual(pages.map { $0.attributes["visible"] }, ["0", "1", "0"])
        XCTAssertEqual(WasabiTabSheet.selectedIndex(of: sheet), 1)
        // Selecting the page already showing changes nothing, so a caller can skip the redraw.
        XCTAssertFalse(WasabiTabSheet.select(index: 1, on: sheet))
        // And it comes back.
        XCTAssertTrue(WasabiTabSheet.select(index: 0, on: sheet))
        XCTAssertEqual(pages.map { $0.attributes["visible"] }, ["1", "0", "0"])
    }

    /// An index outside the pages is clamped rather than left to index past the end — a script or a
    /// restored value has no obligation to be in range.
    func testAnOutOfRangeSelectionIsClamped() throws {
        let renderer = try makeRenderer(layout: Self.threePageLayout, groups: Self.threePageGroups)
        let sheet = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "sheet").first)

        WasabiTabSheet.select(index: 99, on: sheet)
        XCTAssertEqual(WasabiTabSheet.selectedIndex(of: sheet), 2)
        WasabiTabSheet.select(index: -4, on: sheet)
        XCTAssertEqual(WasabiTabSheet.selectedIndex(of: sheet), 0)
    }

    /// A page fills the sheet below the strip. Both reachable skins size the sheet to the space the
    /// pages were drawn for, so a page that started at the sheet's own top would run its content
    /// under the tabs.
    func testAPageSitsBelowTheStripAndFillsWhatIsLeft() throws {
        let renderer = try makeRenderer(layout: Self.threePageLayout, groups: Self.threePageGroups)
        let graph = renderer.loadedSkin.runtime.graph
        let sheet = try XCTUnwrap(graph.objects(xmlID: "sheet").first)
        let sheetFrame = try XCTUnwrap(renderer.frame(of: sheet))
        let page = try XCTUnwrap(renderer.frame(of: WasabiTabSheet.pages(of: sheet)[0]))

        XCTAssertEqual(page.minY, sheetFrame.minY + WasabiTabSheet.stripHeight)
        XCTAssertEqual(page.height, sheetFrame.height - WasabiTabSheet.stripHeight)
        XCTAssertEqual(page.width, sheetFrame.width)
    }

    // MARK: - The strip

    /// A tab is labelled with its page groupdef's own `name`. All four declaring skins spell it that
    /// way and nothing else in the markup names a tab; the label survives into the instance because
    /// a groupdef's defaults merge onto it.
    func testATabIsLabelledWithItsPagesName() throws {
        let renderer = try makeRenderer(layout: Self.threePageLayout, groups: Self.threePageGroups)
        let sheet = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "sheet").first)

        XCTAssertEqual(WasabiTabSheet.pages(of: sheet).map(WasabiTabSheet.label),
                       ["notifier preferences", "Themes", "Changelog"])
    }

    /// A page that states no `name` still gets a tab that can be told apart and clicked — its id is
    /// the only thing left to call it.
    func testAnUnnamedPageFallsBackToItsIdentifier() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="300" h="200" default_w="300" default_h="200">
          <Wasabi:TabSheet id="sheet" x="0" y="0" w="300" h="200" children="first;second"/>
        </layout>
        """, groups: """
        <groupdef id="first" name="First"/>
        <groupdef id="second"/>
        """)
        let sheet = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "sheet").first)

        XCTAssertEqual(WasabiTabSheet.pages(of: sheet).map(WasabiTabSheet.label), ["First", "second"])
    }

    /// Winamp sizes a tab to its own label (`autowidthsource="text"` on both of Bio-Nid's
    /// replacement groupdefs), so a row that fits keeps each tab's natural width.
    func testTabsTakeTheirNaturalWidthWhenTheRowFits() {
        let frame = CGRect(x: 10, y: 20, width: 400, height: 300)
        let rects = WasabiTabSheet.tabRects(in: frame, labelWidths: [60, 30, 50])

        XCTAssertEqual(rects.count, 3)
        XCTAssertEqual(rects[0], CGRect(x: 10, y: 20, width: 60 + 13, height: WasabiTabSheet.stripHeight))
        XCTAssertEqual(rects[1].minX, rects[0].maxX)
        XCTAssertEqual(rects[1].width, 30 + 13)
        XCTAssertEqual(rects[2].minX, rects[1].maxX)
        // The strip is the top of the sheet, not the whole of it.
        XCTAssertEqual(rects[2].height, WasabiTabSheet.stripHeight)
    }

    /// A row that would overflow is shared out equally instead. Truncated labels the user can still
    /// tell apart beat tabs that run off the edge and cannot be clicked at all.
    func testTabsShareTheRowEquallyWhenTheyWouldOverflow() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 200)
        let rects = WasabiTabSheet.tabRects(in: frame, labelWidths: [80, 80, 80, 80])

        XCTAssertEqual(rects.count, 4)
        XCTAssertEqual(rects.map(\.width), [25, 25, 25, 25])
        XCTAssertEqual(rects.last?.maxX, 100)
    }

    // MARK: - The hit test

    /// A click on a tab finds that tab, and one below the strip does not — the pages are ordinary
    /// objects and their own controls have to keep answering.
    func testTheStripAnswersAPointAndThePageBelowItDoesNot() throws {
        let renderer = try makeRenderer(layout: Self.threePageLayout, groups: Self.threePageGroups)
        let sheet = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "sheet").first)
        let frame = try XCTUnwrap(renderer.frame(of: sheet))

        let first = try XCTUnwrap(renderer.tabSheetTab(at: CGPoint(x: frame.minX + 2,
                                                                  y: frame.minY + 2)))
        XCTAssertTrue(first.object === sheet)
        XCTAssertEqual(first.index, 0)
        // Below the strip is the page, not a tab.
        XCTAssertNil(renderer.tabSheetTab(at: CGPoint(x: frame.midX,
                                                      y: frame.minY + WasabiTabSheet.stripHeight + 5)))
        // And so is a point past the last tab's right edge.
        XCTAssertNil(renderer.tabSheetTab(at: CGPoint(x: frame.maxX - 1, y: frame.minY + 2)))
    }

    /// Each tab answers for itself: walking the strip left to right returns 0, 1, 2 in turn.
    func testEachTabAnswersForItsOwnPage() throws {
        let renderer = try makeRenderer(layout: Self.threePageLayout, groups: Self.threePageGroups)
        let sheet = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "sheet").first)
        let frame = try XCTUnwrap(renderer.frame(of: sheet))
        // The renderer's own measurement, not a set of invented widths — the point of one shared
        // answer is that a test cannot be right about the strip while the strip is wrong.
        let rects = renderer.tabSheetTabRects(of: sheet, frame: frame)
        XCTAssertEqual(rects.count, 3)

        for index in 0..<3 {
            let point = CGPoint(x: rects[index].midX, y: rects[index].midY)
            let hit = try XCTUnwrap(renderer.tabSheetTab(at: point),
                                    "no tab at \(point) for index \(index)")
            XCTAssertEqual(hit.index, index)
        }
    }

    // MARK: - What making the pages visible exposed (B66)

    /// A check box or radio that names **no** `cfgattrib` draws from its own `activated`.
    ///
    /// The binding provider answers `false` both for a bound attribute that is off and for an object
    /// that names none, and the old `provider?(object) ?? activated` read the second as the first.
    /// The provider is installed in the app and nil in the harness, so `activated` was only ever
    /// consulted headlessly — which is why every test passed while every radio in the corpus drew
    /// permanently empty in the app, however completely `selectRadioMember` flipped it. Found the
    /// moment B14 made Shield_Amp's and Anexa's pages visible enough to click.
    func testAnUnboundBoxDrawsFromItsOwnActivation() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="200" h="80" default_w="200" default_h="80">
          <Wasabi:CheckBox id="radio.fade" x="0" y="0" w="90" text="Fading Effect"
                           radioid="fadeorslide" activated="1"/>
        </layout>
        """, groups: "")
        let box = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "radio.fade").first)

        // The app's shape: a provider that answers for every object, `false` when it has no binding.
        XCTAssertTrue(WasabiFormWidgets.isOn(box, boundState: false))
        // The harness's shape, which is all the old expression ever exercised.
        XCTAssertTrue(WasabiFormWidgets.isOn(box, boundState: nil))
        // Off is still off.
        _ = box.setAttribute("activated", value: "0")
        XCTAssertFalse(WasabiFormWidgets.isOn(box, boundState: false))
        // And a binding still turns one on without the object tracking it — a lamp a skin draws
        // straight from the stored preference.
        XCTAssertTrue(WasabiFormWidgets.isOn(box, boundState: true))
    }

    /// The click that reaches it: a radio turns itself on and its set off, and the pages a tab sheet
    /// made visible are what the user does that on.
    func testClickingARadioTurnsItsSetOff() throws {
        let runtime = try makeRuntime(layout: """
        <layout id="normal" w="200" h="80" default_w="200" default_h="80">
          <Wasabi:CheckBox id="radio.fade" x="0" y="0" w="90" text="Fading"
                           radioid="fadeorslide" activated="1"/>
          <Wasabi:CheckBox id="radio.slide" x="100" y="0" w="90" text="Sliding"
                           radioid="fadeorslide"/>
        </layout>
        """)
        let graph = runtime.loadedSkin.runtime.graph
        let fade = try XCTUnwrap(graph.objects(xmlID: "radio.fade").first)
        let slide = try XCTUnwrap(graph.objects(xmlID: "radio.slide").first)

        XCTAssertTrue(runtime.selectRadioMember(slide))
        XCTAssertTrue(WasabiFormWidgets.isOn(slide, boundState: false))
        XCTAssertFalse(WasabiFormWidgets.isOn(fade, boundState: false))
        // And back, which is the exclusivity the set exists for.
        XCTAssertTrue(runtime.selectRadioMember(fade))
        XCTAssertTrue(WasabiFormWidgets.isOn(fade, boundState: false))
        XCTAssertFalse(WasabiFormWidgets.isOn(slide, boundState: false))
    }

    // MARK: - Containment

    /// mmd3's winshade sidecar: `<Wasabi:TabSheet id="pls.sidecar" windowtype="plsc" type="2" …/>`
    /// names no `children` at all, because it hosts a *window* rather than a set of page groups.
    /// That is a different attachment path and is deliberately not guessed at — the sheet stays as
    /// inert as it was, rather than acquiring an empty strip.
    func testASheetThatNamesNoPagesIsLeftAlone() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="300" h="200" default_w="300" default_h="200">
          <Wasabi:TabSheet id="pls.sidecar" windowtype="plsc" type="2" border="0"
                           x="0" y="0" w="122" h="143"/>
        </layout>
        """, groups: "")
        let sheet = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "pls.sidecar").first)

        XCTAssertTrue(sheet.children.isEmpty)
        XCTAssertFalse(WasabiTabSheet.isHosted(sheet))
        XCTAssertTrue(renderer.tabSheets().isEmpty)
    }

    /// A skin that ships its own body for the tag keeps it, and gets no strip drawn over it.
    ///
    /// The containment the form widgets get for free — a resolved definition means the substitution
    /// is never reached — is not available here, because a tab sheet keeps its own type name either
    /// way. Bio-Nid is the measured reason to care: it replaces the widget's two tab buttons
    /// wholesale, and a skin replacing the sheet itself is the same move.
    func testASkinsOwnDefinitionOfTheTagWins() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="300" h="200" default_w="300" default_h="200">
          <Wasabi:TabSheet id="sheet" x="0" y="0" w="300" h="200" children="first;second"/>
        </layout>
        """, groups: """
        <groupdef id="skin.tabsheet" xuitag="Wasabi:TabSheet">
          <text id="skins.own.body" x="0" y="0" w="100" h="12" text="mine"/>
        </groupdef>
        <groupdef id="first" name="First"/>
        <groupdef id="second" name="Second"/>
        """)
        let graph = renderer.loadedSkin.runtime.graph
        let sheet = try XCTUnwrap(graph.objects(xmlID: "sheet").first)

        // The skin's body is what expanded…
        XCTAssertEqual(graph.objects(xmlID: "skins.own.body").count, 1)
        // …and this engine hosts nothing: no pages, no strip, no hit test.
        XCTAssertFalse(WasabiTabSheet.isHosted(sheet))
        XCTAssertTrue(WasabiTabSheet.pages(of: sheet).isEmpty)
        XCTAssertTrue(renderer.tabSheets().isEmpty)
    }

    // MARK: - Fixtures

    private static let threePageLayout = """
    <layout id="normal" w="350" h="440" default_w="350" default_h="440">
      <Wasabi:TabSheet id="sheet" x="20" y="25" w="310" h="370"
                       children="config.stuff;themes.stuff;changelog.stuff"/>
    </layout>
    """

    private static let threePageGroups = """
    <groupdef id="config.stuff" name="notifier preferences">
      <text id="config.label" x="0" y="0" w="100" h="12" text="Effects"/>
    </groupdef>
    <groupdef id="themes.stuff" name="Themes">
      <text id="themes.label" x="0" y="0" w="100" h="12" text="Themes"/>
    </groupdef>
    <groupdef id="changelog.stuff" name="Changelog">
      <text id="changelog.label" x="0" y="0" w="100" h="12" text="Changelog"/>
    </groupdef>
    """

    private func makeRenderer(layout: String, groups: String) throws -> WasabiSceneRenderer {
        let loaded = try load(layout: layout, groups: groups)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeRuntime(layout: String) throws -> WinampModernScriptRuntime {
        let runtime = try WinampModernScriptRuntime(loadedSkin: try load(layout: layout, groups: ""),
                                                    host: TestHost())
        addTeardownBlock { runtime.teardown() }
        return runtime
    }

    private func load(layout: String, groups: String) throws -> WinampModernLoadedSkin {
        let url = try makeArchive(xml: """
        <WasabiXML>
          \(groups)
          <container id="main">
            \(layout)
          </container>
        </WasabiXML>
        """)
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase85Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic.wal")
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
        func seek(to time: TimeInterval) {}
        func setVolume(_ volume: Double) {}
        func toggleShuffle() {}
        func toggleRepeat() {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
