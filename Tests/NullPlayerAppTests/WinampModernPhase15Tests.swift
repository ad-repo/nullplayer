import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 15 — the protective window minimum (R1's remaining half) and splitter dragging (12.5).
///
/// A skin's declared `minimum_w`/`minimum_h` is written for Winamp, where a group clips its children.
/// We clip a group only when it says `clipchildren="1"` or declares its own box, so below a certain
/// size a child that no longer fits can paint *over* its siblings rather than being cut off. Rather
/// than change clipping globally (which would change what every skin draws), the window simply
/// refuses to go that small.
///
/// The probe calibrates against the skin's *own* default size: at the size its author chose the scene
/// is by definition correct, so overhang that exists there is deliberate and only overflow that
/// appears after shrinking raises the floor.
///
/// **Painting over something is the whole of it (B89).** An object a parent clips, one that has left
/// the window, and one that has left the scene are all cut off rather than painting over anything, so
/// none of them raises the floor. Counting them made the floor cPro's own default size — "not
/// resizable at all" — for a skin declaring `minimum_w="317"` and shipping promo sheets of that
/// compact player.
final class WinampModernPhase15Tests: XCTestCase {

    // MARK: - The floor is raised only when shrinking actually breaks the layout

    func testMinimumRisesToWhereTheLayoutStillFits() throws {
        let renderer = try makeRenderer(layout: Self.overflowsOntoItsSiblings)
        XCTAssertEqual(renderer.layoutMinimumSize.width, 300,
                       "below 300 `inner` hangs out of the panel, onto the window beside it")
        XCTAssertLessThanOrEqual(renderer.layoutMinimumSize.height, 120)
    }

    /// The one shape that raises the floor: a child escaping a parent that does **not** clip it, with
    /// the escaping part still inside the window — which is to say, painting over something.
    ///
    /// `panel` is a `<layer>`, so it clips nothing, and it is 100px narrower than the canvas, so what
    /// leaves it lands on the window rather than off the edge of it. `inner` reaches x=200 at every
    /// size; the panel is 200 wide at the skin's own 300 and narrower at anything less.
    private static let overflowsOntoItsSiblings = """
    <layout id="normal" w="300" h="120" default_w="300" default_h="120" minimum_w="50" minimum_h="20">
      <layer id="panel" x="0" y="0" w="-100" h="100" relatw="1">
        <text id="inner" text="x" x="100" y="0" w="100" h="40"/>
      </layer>
    </layout>
    """

    func testDeclaredMinimumIsKeptWhenTheLayoutGenuinelyFits() throws {
        // Everything is relative, so the scene fits at every size: the skin's own number stands and
        // the window stays as resizable as its author made it.
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="300" h="120" default_w="300" default_h="120" minimum_w="80" minimum_h="40">
          <text id="inner" text="x" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
        </layout>
        """)
        XCTAssertEqual(renderer.layoutMinimumSize, CGSize(width: 80, height: 40))
    }

    func testOverhangPresentAtTheSkinsOwnSizeDoesNotRaiseTheFloor() throws {
        // A slider centres its thumb on its track and thumb sheets routinely overhang, so overflow
        // that is already there at the default size is the author's intent, not a fit failure. This
        // one is anchored to the right edge, so it overhangs by 50px at every size.
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="300" h="120" default_w="300" default_h="120" minimum_w="60" minimum_h="30">
          <text id="overhang" text="x" x="-10" relatx="1" y="0" w="60" h="60"/>
        </layout>
        """)
        XCTAssertEqual(renderer.layoutMinimumSize, CGSize(width: 60, height: 30))
    }

    func testAnObjectLeavingTheWindowDoesNotRaiseTheFloor() throws {
        // B89's second half. This one sits at a fixed x=290 and is culled entirely below 291 — but a
        // culled object paints over nothing, and Winamp culls it too, so it is not evidence that the
        // window has become too small. Counting it is what set cPro's floor: every size below
        // 317×296 was rejected by objects going missing, with zero overflow, at sizes that render
        // correctly.
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="300" h="120" default_w="300" default_h="120" minimum_w="60" minimum_h="30">
          <text id="overhang" text="x" x="290" y="0" w="60" h="60"/>
        </layout>
        """)
        XCTAssertEqual(renderer.layoutMinimumSize, CGSize(width: 60, height: 30))
    }

    func testAChildItsParentClipsDoesNotRaiseTheFloor() throws {
        // B89's first half, in the shape the ClassicPro engine ships it: `<group id="beatvis" x="200"
        // w="300"/>` flush against the right edge of a 500-wide sized group. The group clips, exactly
        // as Winamp does, so the overflow is a crop and not a collision.
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="500" h="120" default_w="500" default_h="120" minimum_w="100" minimum_h="40">
          <group id="screen" x="0" y="0" w="0" h="100" relatw="1">
            <group id="beatvis" x="200" y="0" w="300" h="45"/>
          </group>
        </layout>
        """)
        XCTAssertEqual(renderer.layoutMinimumSize, CGSize(width: 100, height: 40))
    }

    func testMinimumNeverExceedsTheSkinsOwnDefaultSize() throws {
        // The probe searches within `declared…default`. Even a layout that overflows at every size
        // is left resizable down to the size its author ships it at — the floor is protection, not a
        // way to make a window bigger than the skin describes.
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="200" h="100" default_w="200" default_h="100" minimum_w="50" minimum_h="25">
          <text id="always.out" text="x" x="400" y="400" w="500" h="500"/>
        </layout>
        """)
        XCTAssertLessThanOrEqual(renderer.layoutMinimumSize.width, 200)
        XCTAssertLessThanOrEqual(renderer.layoutMinimumSize.height, 100)
    }

    // MARK: - What the window does with it

    func testEachLayoutCarriesItsOwnFloor() throws {
        // A shade layout is a different scene: switching to it must re-derive the minimum, or the
        // player's floor would pin a 23px-tall shade window open at full height.
        let renderer = try makeRenderer(layout: Self.overflowsOntoItsSiblings + """
        <layout id="shade" w="300" h="24" default_w="300" default_h="24" minimum_w="100" minimum_h="24">
          <text id="shade.inner" text="x" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>
        </layout>
        """)
        XCTAssertEqual(renderer.layoutMinimumSize.width, 300)
        _ = try renderer.activateLayout(id: "shade")
        XCTAssertEqual(renderer.layoutMinimumSize, CGSize(width: 100, height: 24))
    }

    func testResizeIsClampedToTheProtectiveFloor() throws {
        // A script resizing below the floor (cPro's `gotoGlobal` restores a saved width verbatim)
        // is clamped up, exactly as one resizing below the declared minimum always was.
        let renderer = try makeRenderer(layout: Self.overflowsOntoItsSiblings)
        XCTAssertEqual(renderer.resize(to: CGSize(width: 120, height: 120)).width, 300)
    }

    func testRestoredFrameIsClampedUpKeepingItsTopLeft() throws {
        // The R1 restore path, in pure form: a saved 376×182 frame comes back at the floor without
        // the window jumping away from where the user left it.
        let clamped = WinampModernMainWindowController.clamp(
            frame: NSRect(x: 40, y: 300, width: 376, height: 182),
            minimum: NSSize(width: 477, height: 201),
            maximum: NSSize(width: 16_384, height: 16_384))
        XCTAssertEqual(clamped.size, NSSize(width: 477, height: 201))
        XCTAssertEqual(clamped.minX, 40)
        XCTAssertEqual(clamped.maxY, 482, "the saved top edge is preserved")
    }

    // MARK: - Splitter dragging (12.5)

    /// cPro-Bento's own splitter, to the attribute: a vertical divider measured from the right edge,
    /// 200px in, bounded at 158 and at "always leave 224px for the other pane".
    private static let classicProSplitter = """
    <groupdef id="pane.left"><text id="left.label" text="L" x="0" y="0" w="10" h="10"/></groupdef>
    <groupdef id="pane.right"><text id="right.label" text="R" x="0" y="0" w="10" h="10"/></groupdef>
    <layout id="normal" w="500" h="300" default_w="500" default_h="300" minimum_w="200" minimum_h="100">
      <Wasabi:Frame id="split" x="0" y="0" w="0" h="0" relatw="1" relath="1"
                    left="pane.left" right="pane.right" orientation="vertical"
                    from="right" width="200" minwidth="158" maxwidth="-224"/>
    </layout>
    """

    func testDividerStripSitsBetweenThePanes() throws {
        let renderer = try makeRenderer(layout: Self.classicProSplitter)
        let dividers = renderer.frameDividers()
        XCTAssertEqual(dividers.count, 1)
        // Measured from the right edge: 500 − 200 = 300, with the 8px strip centred on it.
        XCTAssertEqual(dividers.first?.rect, CGRect(x: 296, y: 0, width: 8, height: 300))
        XCTAssertEqual(dividers.first?.isVertical, true)
        XCTAssertNotNil(renderer.frameDivider(at: CGPoint(x: 300, y: 150)))
        XCTAssertNil(renderer.frameDivider(at: CGPoint(x: 200, y: 150)))
    }

    func testDraggingTheDividerMovesBothPanes() throws {
        let renderer = try makeRenderer(layout: Self.classicProSplitter)
        let divider = try XCTUnwrap(renderer.frameDivider(at: CGPoint(x: 300, y: 150)))
        XCTAssertTrue(renderer.dragFrameDivider(divider, to: CGPoint(x: 260, y: 150)))

        let left = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "pane.left").first)
        let right = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "pane.right").first)
        XCTAssertEqual(renderer.frame(of: left)?.maxX, 256, "the near pane stops short of the strip")
        XCTAssertEqual(renderer.frame(of: right)?.minX, 264, "the far pane starts past it")
        XCTAssertEqual(renderer.frameDividers().first?.rect.minX, 256)
    }

    func testDragIsBoundedByTheFramesOwnLimits() throws {
        let renderer = try makeRenderer(layout: Self.classicProSplitter)
        let divider = try XCTUnwrap(renderer.frameDivider(at: CGPoint(x: 300, y: 150)))

        // Dragging past the far end asks for an offset of 500: `maxwidth="-224"` caps it at 276.
        renderer.dragFrameDivider(divider, to: CGPoint(x: 0, y: 150))
        XCTAssertEqual(WasabiFrame.position(of: divider), 276)
        // And past the near end asks for 0, which `minwidth="158"` lifts.
        renderer.dragFrameDivider(divider, to: CGPoint(x: 500, y: 150))
        XCTAssertEqual(WasabiFrame.position(of: divider), 158)
    }

    func testHorizontalSplitterDragsOnItsOwnAxis() throws {
        // ClassicPro's `centro.plframe` is horizontal and still spells its bounds `minwidth`/
        // `maxwidth`, so the limits are read by name in either orientation.
        let renderer = try makeRenderer(layout: """
        <groupdef id="pane.top"><text id="top.label" text="T" x="0" y="0" w="10" h="10"/></groupdef>
        <groupdef id="pane.bottom"><text id="bottom.label" text="B" x="0" y="0" w="10" h="10"/></groupdef>
        <layout id="normal" w="400" h="200" default_w="400" default_h="200">
          <Wasabi:Frame id="split" x="0" y="0" w="0" h="0" relatw="1" relath="1"
                        top="pane.top" bottom="pane.bottom" orientation="h"
                        from="top" height="60" minwidth="20" maxwidth="-50"/>
        </layout>
        """)
        let divider = try XCTUnwrap(renderer.frameDividers().first)
        XCTAssertEqual(divider.rect, CGRect(x: 0, y: 56, width: 400, height: 8))
        XCTAssertEqual(divider.isVertical, false)
        renderer.dragFrameDivider(divider.object, to: CGPoint(x: 200, y: 190))
        XCTAssertEqual(WasabiFrame.position(of: divider.object), 150, "`maxwidth=-50` on a 200px axis")
    }

    func testAClosedSplitOffersNothingToGrab() throws {
        // ClassicPro closes its side view with `setPosition(0)`; a divider flush with the edge must
        // not sit there as an invisible grab strip over the pane that replaced it.
        let renderer = try makeRenderer(layout: Self.classicProSplitter)
        let divider = try XCTUnwrap(renderer.frameDivider(at: CGPoint(x: 300, y: 150)))
        WasabiFrame.setPosition(0, on: divider)
        XCTAssertTrue(renderer.frameDividers().isEmpty)
        XCTAssertNil(renderer.frameDivider(at: CGPoint(x: 498, y: 150)))
    }

    // MARK: - Fixtures

    private func makeRenderer(layout: String) throws -> WasabiSceneRenderer {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            \(layout)
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase15Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        // A unique archive name gives each fixture its own configuration namespace.
        let url = directory.appendingPathComponent("Phase15-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
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
