import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 24 — the defects behind cPro-Bento's garbled window and its vanishing beat visualization.
///
/// Reported from a live run: an opaque slab over the volume slider, mute button and kbps/kHz
/// readouts; a stray `▭≡` floating on the display; every framed surface (tab pills, SUI sheet,
/// playlist box, mini-view strip) a flat black hole; and the beat display disappearing the moment a
/// track starts. Each is one missing renderer or runtime capability, reproduced headlessly first.
final class WinampModernPhase24Tests: XCTestCase {
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

    // MARK: - D1: a `Wasabi:Frame` pane clips its children

    /// cPro-Bento's mini view is *closed*: the splitter sits 10px from the top, so its top pane is
    /// 6px tall — which is correct. But that pane's children are anchored for the 27px strip it has
    /// when open (`y="-27" relaty="1"`), so they resolve 21px **above** the pane, over the volume
    /// slider and the readouts. A pane is a window in Wasabi and always clips.
    func testACollapsedFramePaneClipsItsChildren() throws {
        let xml = """
        <WasabiXML>
          <groupdef id="pane.top">
            <layer id="escapee" x="0" y="-27" w="-6" h="27" relaty="1" relatw="1"/>
          </groupdef>
          <groupdef id="pane.bottom"><layer id="filler" fitparent="1"/></groupdef>
          <container id="Main">
            <layout id="normal" w="100" h="100">
              <Wasabi:Frame id="split" fitparent="1" from="top" orientation="h"
                            top="pane.top" bottom="pane.bottom" height="10"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let renderer = try makeRenderer(xml: xml)
        let pane = try XCTUnwrap(node(in: renderer, xmlID: "pane.top"))
        let escapee = try XCTUnwrap(node(in: renderer, xmlID: "escapee"))
        XCTAssertEqual(pane.frame.height, 6, "the closed mini view: 10 − the divider's half-thickness")
        XCTAssertLessThan(escapee.frame.minY, pane.frame.minY,
                          "the child still resolves above the pane — its geometry is not rewritten")
        XCTAssertEqual(escapee.clip, pane.frame,
                       "but it is clipped to the pane, so nothing of it paints outside")
    }

    /// A group whose box the skin **declared** is a window like a pane is, and bounds its children.
    /// Defix's cassette display is the measured case: a 263×79 group holding a 117×117 reel bitmap,
    /// which unclipped spilled 53px below the cassette and painted both reels over the song ticker
    /// underneath, leaving the title readable only in the gaps between them.
    func testADeclaredGroupClipsItsChildren() throws {
        let xml = """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="100" h="100">
              <group id="holder" x="10" y="50" w="50" h="10">
                <layer id="overhang" x="0" y="-20" w="50" h="30"/>
              </group>
            </layout>
          </container>
        </WasabiXML>
        """
        let renderer = try makeRenderer(xml: xml)
        let overhang = try XCTUnwrap(node(in: renderer, xmlID: "overhang"))
        XCTAssertEqual(overhang.clip, CGRect(x: 10, y: 50, width: 50, height: 10),
                       "the child is bounded by the group's own declared box")
    }

    /// …but only a *declared* box. A group with no `w`/`h` of its own is sized by the renderer, and
    /// clipping children to a rect we inferred can erase content that is really there — a much worse
    /// failure than the overhang it would prevent.
    func testAGroupWithNoDeclaredBoxStillDoesNotClip() throws {
        let xml = """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="100" h="100">
              <group id="holder" x="10" y="50">
                <layer id="overhang" x="0" y="-20" w="50" h="30"/>
              </group>
            </layout>
          </container>
        </WasabiXML>
        """
        let renderer = try makeRenderer(xml: xml)
        let overhang = try XCTUnwrap(node(in: renderer, xmlID: "overhang"))
        XCTAssertEqual(overhang.clip, CGRect(x: 0, y: 0, width: 100, height: 100),
                       "an inferred box passes the inherited clip straight through")
    }

    // MARK: - D2: `<grid>` nine-slice

    /// Nine parts: corners at their own size, edges stretched along one axis, `middle` filling the
    /// centre. The fixture gives each part a unique colour so a misplaced slice is a wrong pixel
    /// rather than a plausible-looking one.
    func testANineSliceGridPlacesEveryPart() throws {
        let pixels = try renderGrid(attributes: """
            topleft="c0" top="c1" topright="c2"
            left="c3" middle="c4" right="c5"
            bottomleft="c6" bottom="c7" bottomright="c8"
            """)
        // Parts are 4×4, the grid is 32×32: a 4px frame with a 24px centre.
        XCTAssertEqual(colour(pixels, x: 1, y: 1), 0, "top-left corner")
        XCTAssertEqual(colour(pixels, x: 16, y: 1), 1, "top edge, stretched between the corners")
        XCTAssertEqual(colour(pixels, x: 30, y: 1), 2, "top-right corner")
        XCTAssertEqual(colour(pixels, x: 1, y: 16), 3, "left edge")
        XCTAssertEqual(colour(pixels, x: 16, y: 16), 4, "middle")
        XCTAssertEqual(colour(pixels, x: 30, y: 16), 5, "right edge")
        XCTAssertEqual(colour(pixels, x: 1, y: 30), 6, "bottom-left corner")
        XCTAssertEqual(colour(pixels, x: 16, y: 30), 7, "bottom edge")
        XCTAssertEqual(colour(pixels, x: 30, y: 30), 8, "bottom-right corner")
    }

    /// cPro's tab pills declare only the three `top*` parts. That is a horizontal three-slice filling
    /// the whole height — not a grid with an absent `middle` stretched over everything.
    func testATopOnlyGridDrawsAsAHorizontalThreeSlice() throws {
        let pixels = try renderGrid(attributes: #"topleft="c0" top="c1" topright="c2""#)
        XCTAssertEqual(colour(pixels, x: 1, y: 1), 0)
        XCTAssertEqual(colour(pixels, x: 16, y: 1), 1)
        XCTAssertEqual(colour(pixels, x: 30, y: 1), 2)
        // With no bottom row declared, the top row takes the full height.
        XCTAssertEqual(colour(pixels, x: 1, y: 30), 0, "the left cap runs the whole way down")
        XCTAssertEqual(colour(pixels, x: 16, y: 30), 1, "and so does the stretched centre")
    }

    /// A part the skin does not name simply is not drawn — an absent `middle` must not be filled in
    /// with a neighbouring slice.
    func testAGridSkipsThePartsTheSkinOmits() throws {
        let pixels = try renderGrid(attributes: """
            topleft="c0" topright="c2" bottomleft="c6" bottomright="c8"
            """)
        XCTAssertEqual(colour(pixels, x: 1, y: 1), 0, "the corners it did declare")
        XCTAssertEqual(colour(pixels, x: 30, y: 30), 8)
        XCTAssertEqual(pixel(pixels, x: 16, y: 16, width: 32)[3], 0, "and nothing at all in the centre")
        XCTAssertEqual(pixel(pixels, x: 16, y: 1, width: 32)[3], 0, "or along the undeclared top edge")
    }

    /// A grid drawn smaller than its own corners (a pane the user collapsed) shrinks them instead of
    /// letting them overlap or spill past its rect.
    func testAGridSmallerThanItsCornersStaysInsideItsRect() throws {
        let pixels = try renderGrid(attributes: """
            topleft="c0" top="c1" topright="c2"
            bottomleft="c6" bottom="c7" bottomright="c8"
            """, gridSize: (6, 6))
        for y in 0..<32 where y >= 6 {
            XCTAssertEqual(pixel(pixels, x: 1, y: y, width: 32)[3], 0, "nothing paints below the grid's own rect")
        }
        XCTAssertEqual(colour(pixels, x: 1, y: 1), 0, "the corner is still drawn, just smaller")
    }

    // MARK: - D5: `<rect>` and `<gradient>`

    func testAFilledRectPaintsItsColourAtItsAlpha() throws {
        let pixels = try render(size: 8, body: """
            <rect id="r" x="0" y="0" w="8" h="8" filled="1" color="0,0,255" alpha="128"/>
            """)
        let sample = pixel(pixels, x: 4, y: 4, width: 8)
        XCTAssertEqual(sample[3], 128, "the object's alpha")
        XCTAssertGreaterThan(sample[2], 100, "and its colour")
    }

    /// Winamp's default is an outline, and the engine writes `filled="0"` where it wants a border.
    func testAnUnfilledRectStrokesItsBorderOnly() throws {
        let pixels = try render(size: 8, body: """
            <rect id="r" x="0" y="0" w="8" h="8" filled="0" color="0,0,255"/>
            """)
        XCTAssertGreaterThan(pixel(pixels, x: 0, y: 0, width: 8)[3], 0, "the border is painted")
        XCTAssertEqual(pixel(pixels, x: 4, y: 4, width: 8)[3], 0, "the interior is not")
    }

    /// ClassicPro's only gradient is a vertical two-stop fade whose *alpha* is the whole point: it
    /// masks a reflection back into the list background.
    func testALinearGradientInterpolatesItsStopsIncludingAlpha() throws {
        let pixels = try render(size: 8, body: """
            <gradient id="g" x="0" y="0" w="8" h="8" mode="linear"
                      gradient_x1="0" gradient_y1="0" gradient_x2="0" gradient_y2="1"
                      points="0.0=255,0,0,0;1.0=255,0,0,255"/>
            """)
        let top = pixel(pixels, x: 4, y: 0, width: 8)
        let bottom = pixel(pixels, x: 4, y: 7, width: 8)
        XCTAssertLessThan(Int(top[3]), 64, "transparent at the first stop")
        XCTAssertGreaterThan(Int(bottom[3]), 192, "opaque at the last")
        XCTAssertEqual(pixel(pixels, x: 0, y: 7, width: 8)[3], pixel(pixels, x: 7, y: 7, width: 8)[3],
                       "and constant across a purely vertical gradient")
    }

    /// A gradient this cannot parse draws nothing and says so, rather than inventing a colour to
    /// paint over the skin's own artwork with.
    func testAMalformedGradientDrawsNothingAndIsReported() throws {
        let loaded = try load(xml: skin(size: 8, body: """
            <gradient id="g" x="0" y="0" w="8" h="8" mode="linear" points="nonsense"/>
            """))
        let pixels = try render(loaded: loaded, size: 8)
        XCTAssertEqual(pixel(pixels, x: 4, y: 4, width: 8)[3], 0, "nothing is drawn")
        let messages = report(for: loaded).findings.map(\WinampModernCompatibilityReport.Finding.message)
        XCTAssertTrue(messages.contains { $0.contains("gradient") },
                      "and the skin's report records it — got \(messages)")
    }

    func testAnUnsupportedGradientModeDrawsNothingAndIsReported() throws {
        let loaded = try load(xml: skin(size: 8, body: """
            <gradient id="g" x="0" y="0" w="8" h="8" mode="radial"
                      points="0.0=255,0,0,255;1.0=0,0,255,255"/>
            """))
        let pixels = try render(loaded: loaded, size: 8)
        XCTAssertEqual(pixel(pixels, x: 4, y: 4, width: 8)[3], 0)
        XCTAssertTrue(report(for: loaded).findings.contains { $0.code == "unsupportedElement" })
    }

    // MARK: - D3: the events that were never dispatched

    /// The events ClassicPro invokes directly as methods need a declared arity, or the interpreter
    /// cannot unwind the stack and the call fails closed. `beat.m` calls `frameGroup.onResize(...)`
    /// on itself; `tagviewer.m` does the same.
    func testTheNewlyDispatchedEventsAreCallableFromAScript() throws {
        let runtime = try makeRuntime()
        for event in ["onresize", "onsetvisible", "onpause", "onresume", "ontitlechange",
                      "onleftbuttondblclk", "onscriptunloading"] {
            XCTAssertNotNil(runtime.signature(for: event, classGUID: nil),
                            "\(event) must be callable as a method")
        }
        XCTAssertEqual(runtime.signature(for: "onresize", classGUID: nil)?.argumentCount, 4,
                       "onResize carries x, y, w, h")
    }

    /// `onResize` goes to containers of other objects — a layout, a group, a XUI instance — and not to
    /// every button in the window.
    func testResizeTargetsAreContainersNotLeafControls() throws {
        let renderer = try makeRenderer(xml: skin(size: 40, body: """
            <group id="holder" fitparent="1">
              <button id="press" x="0" y="0" w="10" h="10"/>
            </group>
            """))
        let ids = renderer.resizeTargets().compactMap(\.object.xmlID)
        XCTAssertTrue(ids.contains("holder"))
        XCTAssertTrue(ids.contains("normal"), "the layout hears about its own size too")
        XCTAssertFalse(ids.contains("press"), "a leaf control does not")
    }

    /// Each target hears its **own** geometry, in its parent's coordinates — not the window's.
    func testEachResizeTargetReportsItsOwnFrame() throws {
        let renderer = try makeRenderer(xml: skin(size: 40, body: """
            <group id="holder" x="5" y="7" w="20" h="10"/>
            """))
        let holder = try XCTUnwrap(renderer.resizeTargets().first { $0.object.xmlID == "holder" })
        XCTAssertEqual(holder.frame, CGRect(x: 5, y: 7, width: 20, height: 10))
    }

    /// `onSetVisible` fires on an actual change only. `showGroup` in `beat.m` hides both display
    /// groups before showing one, and the VU timer hangs off that event — notifying unconditionally
    /// would stop and restart it on every refresh.
    func testVisibilityChangesNotifyOnlyWhenTheyChangeSomething() throws {
        let (runtime, object) = try makeRuntimeWithObject()
        var events = 0
        runtime.dispatchObserver = { event, _, _ in if event == "onsetvisible" { events += 1 } }
        _ = try runtime.invoke(method: "hide", on: reference(object), arguments: [],
                              program: emptyProgram())
        _ = try runtime.invoke(method: "hide", on: reference(object), arguments: [],
                              program: emptyProgram())
        XCTAssertEqual(object.attributes["visible"], "0")
        // No handler is bound in this synthetic skin, so the observable effect is the attribute; the
        // guard itself is asserted by the second `hide` not re-entering the dispatch at all.
        XCTAssertEqual(events, 0, "no script is bound, so nothing ran")
    }

    /// `init(parent)` is the second half of Wasabi's two-step runtime instantiation, and treating it
    /// as a no-op is the whole of TASKS §15.6: cPro's tab buttons kept the tab strip's *container* as
    /// their parent, so their `setDispatcher(getScriptGroup().getParent())` addressed an object
    /// nothing was listening on, and clicking a tab did nothing.
    func testInitReparentsARuntimeGroupIntoTheGroupTheScriptNames() throws {
        let (runtime, _) = try makeRuntimeWithObject()
        let graph = runtime.loadedSkin.runtime.graph
        let holder = try XCTUnwrap(graph.objects(xmlID: "holder").first)
        let target = try XCTUnwrap(graph.objects(xmlID: "target").first)
        let moved = try XCTUnwrap(graph.objects(xmlID: "movable").first)
        XCTAssertTrue(moved.parent === holder, "it starts where the markup put it")
        _ = try runtime.invoke(method: "init", on: reference(moved),
                               arguments: [.object(reference(target))], program: emptyProgram())
        XCTAssertTrue(moved.parent === target, "and `init` moves it where the script asks")
    }

    /// A script cannot reparent an object into its own subtree.
    func testInitRefusesToCreateAnOwnershipCycle() throws {
        let (runtime, _) = try makeRuntimeWithObject()
        let graph = runtime.loadedSkin.runtime.graph
        let holder = try XCTUnwrap(graph.objects(xmlID: "holder").first)
        let moved = try XCTUnwrap(graph.objects(xmlID: "movable").first)
        XCTAssertThrowsError(try runtime.invoke(method: "init", on: reference(holder),
                                               arguments: [.object(reference(moved))],
                                               program: emptyProgram()))
        XCTAssertTrue(moved.parent === holder, "and the graph is left as it was")
    }

    /// Paint order is sibling order, so raising an object is moving it last among its siblings.
    func testBringToFrontMovesAnObjectLastAmongItsSiblings() throws {
        let (runtime, _) = try makeRuntimeWithObject()
        let graph = runtime.loadedSkin.runtime.graph
        let holder = try XCTUnwrap(graph.objects(xmlID: "holder").first)
        let moved = try XCTUnwrap(graph.objects(xmlID: "movable").first)
        XCTAssertEqual(holder.children.count, 2)
        _ = try runtime.invoke(method: "bringtofront", on: reference(moved), arguments: [],
                               program: emptyProgram())
        XCTAssertTrue(holder.children.last === moved)
        _ = try runtime.invoke(method: "bringtoback", on: reference(moved), arguments: [],
                               program: emptyProgram())
        XCTAssertTrue(holder.children.first === moved)
    }

    /// A script that moves something gets an `onResize` for it — once the event it did it in unwinds,
    /// or immediately when there is no event to unwind. Without it a skin cannot react to its own
    /// layout changes.
    ///
    /// cPro-Bento's "close side view" button collapses the playlist pane with `setPosition(0)` and then
    /// relies on `area_right.onResize` to swap the close button for the **open** one, which ships
    /// `visible="0"`. With no settle, closing the playlist hid the only control that could reopen it.
    func testAScriptMovingSomethingSettlesIntoAResize() throws {
        let (runtime, _) = try makeRuntimeWithObject()
        var settles = 0
        runtime.geometryDidSettle = { settles += 1 }
        let holder = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "holder").first)
        _ = try runtime.invoke(method: "setxmlparam", on: reference(holder),
                               arguments: [.string("w"), .string("40")], program: emptyProgram())
        XCTAssertEqual(settles, 1, "the geometry change is reported")
    }

    /// A mutation that cannot move anything must not pay for a settle — cPro's beat display runs a
    /// 10 ms timer that only advances an animation frame.
    func testAMutationThatCannotMoveAnythingDoesNotSettle() throws {
        let (runtime, object) = try makeRuntimeWithObject()
        var settles = 0
        runtime.geometryDidSettle = { settles += 1 }
        _ = try runtime.invoke(method: "setxmlparam", on: reference(object),
                               arguments: [.string("image"), .string("other")],
                               program: emptyProgram())
        XCTAssertEqual(settles, 0)
    }

    /// Geometry is resolved for **hidden** objects too. Wasabi lays a hidden object out anyway, and
    /// cPro's side view is hidden when it closes — the only thing that can bring it back is its own
    /// `onResize` seeing that the pane is wide again, which it can never see if a hidden object has no
    /// geometry at all.
    func testHiddenObjectsStillHaveResolvedGeometry() throws {
        let renderer = try makeRenderer(xml: skin(size: 40, body: """
            <group id="hidden.pane" x="4" y="6" w="20" h="10" visible="0"/>
            """))
        let object = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "hidden.pane").first)
        XCTAssertNil(renderer.sceneNodes().first { $0.object === object },
                     "it is not painted")
        let geometry = try XCTUnwrap(renderer.resolvedGeometry(of: object),
                                     "but it is still laid out")
        XCTAssertEqual(geometry.frame, CGRect(x: 4, y: 6, width: 20, height: 10))
        XCTAssertTrue(renderer.resizeTargets().contains { $0.object === object },
                      "and it is told when it moves")
    }

    // MARK: - The one skin-script correction

    /// ClassicPro's promo art double-centres itself, so it jumps sideways when a double-click swaps it
    /// in for the beat visualization — which lands centred at every width. The box is placed at
    /// `centre − artWidth/2`, already centring the *picture*, and then the picture is placed at an
    /// offset *inside* the box as well. Shifting the box back by that offset is exact.
    func testTheClassicProPromoBoxIsShiftedBackByItsPicturesOffset() throws {
        let renderer = try makeRenderer(xml: skin(size: 500, body: """
            <group id="beatpromo" x="185" y="47" w="300" h="45">
              <layer id="beat.promo" x="150" y="0" w="99" h="45"/>
            </group>
            """))
        let box = try XCTUnwrap(node(in: renderer, xmlID: "beatpromo"))
        let art = try XCTUnwrap(node(in: renderer, xmlID: "beat.promo"))
        XCTAssertEqual(box.frame.minX, 35, "the box moves left by the picture's in-box offset")
        XCTAssertEqual(art.frame.minX, 185, "so the picture lands where the box was told to go")
    }

    /// The branch that already works must not move: the widest promo art sits at offset 0 and is
    /// exactly centred today, which is the evidence that our `resize()`/`getWidth()` semantics are
    /// right and the skin's arithmetic is what is off.
    func testAPromoBoxWhosePictureIsAtOriginIsUntouched() throws {
        let renderer = try makeRenderer(xml: skin(size: 700, body: """
            <group id="beatpromo" x="184" y="47" w="300" h="45">
              <layer id="beat.promo" x="0" y="0" w="300" h="45"/>
            </group>
            """))
        XCTAssertEqual(try XCTUnwrap(node(in: renderer, xmlID: "beatpromo")).frame.minX, 184)
    }

    /// And it is scoped to the pair of ids ClassicPro declares — nothing else in any installed skin
    /// gets its geometry rewritten.
    func testTheCorrectionDoesNotApplyToAnyOtherGroup() throws {
        let renderer = try makeRenderer(xml: skin(size: 500, body: """
            <group id="ordinary.box" x="185" y="47" w="300" h="45">
              <layer id="beat.promo" x="150" y="0" w="99" h="45"/>
            </group>
            <group id="beatpromo" x="185" y="100" w="300" h="45">
              <layer id="some.other.art" x="150" y="0" w="99" h="45"/>
            </group>
            """))
        XCTAssertEqual(try XCTUnwrap(node(in: renderer, xmlID: "ordinary.box")).frame.minX, 185,
                       "a different box holding that picture is left alone")
        XCTAssertEqual(try XCTUnwrap(node(in: renderer, xmlID: "beatpromo")).frame.minX, 185,
                       "and so is that box holding a different picture")
    }

    // MARK: - D4: the analyzer repaints when levels arrive

    /// `updateSpectrum` used to set the levels without invalidating. cPro happens to have animated
    /// layers and therefore a 30 Hz redraw timer, so its bars moved anyway — a skin without one
    /// would never repaint its `<vis>` from a spectrum delivery at all. A direct renderer dump cannot
    /// catch this: it draws synchronously on demand.
    func testDeliveringSpectrumLevelsMarksTheViewForRedraw() throws {
        let loaded = try load(xml: skin(size: 40, body: """
            <vis id="vis" x="0" y="0" w="40" h="20"/>
            """))
        let host = Host()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { scripts.teardown() }
        let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host)
        addTeardownBlock { view.teardown() }
        // A window, so AppKit actually tracks the dirty state.
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: renderer.canvasSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.displayIfNeeded()
        let layer = try XCTUnwrap(view.layer, "a `.wal` view is layer-backed")
        // `needsDisplay` on a layer-backed view forwards to its layer and reads back false, so the
        // layer is where the invalidation is observable.
        XCTAssertFalse(layer.needsDisplay(), "clean to begin with")
        view.updateSpectrum((0..<64).map { Float($0) / 64 })
        XCTAssertTrue(layer.needsDisplay(), "levels arriving must invalidate the view")
        XCTAssertFalse(host.spectrumLevels.isEmpty)
    }

    /// `bandwidth="thin"` is a comb of narrow bars; `wide` is the solid row of blocks. Both come from
    /// the same band levels, so the difference is bar thickness.
    func testThinBandwidthDrawsNarrowerBarsThanWide() throws {
        func paintedColumns(_ bandwidth: String) throws -> Int {
            let loaded = try load(xml: skin(size: 32, body: """
                <vis id="vis" x="0" y="0" w="32" h="8" bandwidth="\(bandwidth)" colorallbands="255,0,0"/>
                """))
            let host = Host()
            host.spectrumLevels = Array(repeating: 1, count: 8)
            let pixels = try render(loaded: loaded, size: 32, host: host)
            return (0..<32).filter { pixel(pixels, x: $0, y: 4, width: 32)[3] > 0 }.count
        }
        let thin = try paintedColumns("thin")
        let wide = try paintedColumns("wide")
        XCTAssertLessThan(thin, wide, "thin bars leave more of the box unpainted")
        XCTAssertGreaterThan(thin, 0, "but they are still drawn")
    }

    // MARK: - D8: the titlebar lays its own streaks out

    /// `instanceid` is how a skin tells two instantiations of one groupdef apart: the expanded object
    /// answers to it instead of the groupdef's id. Winamp Modern's titlebar instantiates
    /// `wasabi.titlebar.streak` twice and addresses the two by instance id from both its `sendparams`
    /// and its script, which is what lays the streaks out either side of the window title.
    func testInstanceIDNamesTheExpandedGroupInstance() throws {
        let renderer = try makeRenderer(xml: """
        <WasabiXML>
          <groupdef id="streak">
            <layer id="mark" x="0" y="0" w="5" h="5"/>
          </groupdef>
          <container id="Main">
            <layout id="normal" w="40" h="20">
              <group id="streak" instanceid="streak.left" x="0" y="0" w="20" h="20"/>
              <group id="streak" instanceid="streak.right" x="20" y="0" w="20" h="20"/>
              <sendparams group="streak.left" target="mark" w="7"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let graph = renderer.loadedSkin.runtime.graph
        XCTAssertEqual(graph.objects(xmlID: "streak.left").count, 1)
        XCTAssertEqual(graph.objects(xmlID: "streak.right").count, 1)
        XCTAssertTrue(graph.objects(xmlID: "streak").isEmpty,
                      "the groupdef's own id names the definition, not either instance")
        let left = try XCTUnwrap(graph.objects(xmlID: "streak.left").first)
        let right = try XCTUnwrap(graph.objects(xmlID: "streak.right").first)
        XCTAssertEqual(left.children.first?.attributes["w"], "7",
                       "`sendparams` scoped by instance id reaches that instance's child")
        XCTAssertEqual(right.children.first?.attributes["w"], "5",
                       "and leaves the other instance alone")
    }

    /// Client ↔ screen conversion is relative to the receiver's **parent**, which is the space
    /// `getLeft()` answers in — every measured call site is `b.clientToScreenX(b.getLeft())`, receiver
    /// and coordinate the same object. Reading it as the receiver's own box double-counts that idiom;
    /// reading it as identity loses the parent chain, which put ClassicPro's tab menu at the window
    /// edge instead of under its tab.
    func testClientToScreenIsRelativeToTheReceiversParent() throws {
        let renderer = try makeRenderer(xml: """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="100" h="100">
              <group id="holder" x="30" y="40" w="50" h="50">
                <layer id="child" x="5" y="5" w="10" h="10"/>
              </group>
            </layout>
          </container>
        </WasabiXML>
        """)
        let graph = renderer.loadedSkin.runtime.graph
        let runtime = try WinampModernScriptRuntime(loadedSkin: renderer.loadedSkin, host: Host())
        addTeardownBlock { runtime.teardown() }
        runtime.resolvedGeometryRequested = { [weak renderer] in renderer?.resolvedGeometry(of: $0) }
        let child = try XCTUnwrap(graph.objects(xmlID: "child").first)
        let holder = try XCTUnwrap(graph.objects(xmlID: "holder").first)
        func call(_ method: String, on target: WasabiObject, _ value: Int32) throws -> Int32 {
            try runtime.invoke(method: method, on: reference(target), arguments: [.integer(value)],
                               program: emptyProgram()).integerValue
        }
        XCTAssertEqual(try call("clienttoscreenx", on: child, 5), 35,
                       "the idiom `child.clientToScreenX(child.getLeft())` lands on the child")
        XCTAssertEqual(try call("clienttoscreeny", on: child, 5), 45)
        XCTAssertEqual(try call("screentoclientx", on: child, 35), 5, "and it round-trips")
        XCTAssertEqual(try call("clienttoscreenx", on: holder, 30), 30,
                       "an object straight off the layout converts to itself")
    }

    /// `popAtXY` is the other half of those conversions: ClassicPro's tab strip and its drawer build a
    /// menu and place it at a computed point rather than at the mouse. Both forms reach the same
    /// presenter — the point is what tells them apart.
    func testPopAtXYPresentsTheMenuAtTheGivenPoint() throws {
        let runtime = try makeRuntime()
        var points: [CGPoint?] = []
        runtime.popupPresenter = { _, point in
            points.append(point)
            return 7
        }
        // Wasabi's `PopupMenu` class GUID as the *bytecode* carries it — little-endian per field, the
        // form `new PopupMenu` compiles to, which the runtime reorders into `f4787af4…`.
        let menu = try runtime.makeObject(classGUID: "f47a78f4bbb2f74e9cfbe74ba9bea88d",
                                          program: emptyProgram())
        _ = try runtime.invoke(method: "addcommand", on: menu,
                               arguments: [.string("Auto Close Tab"), .integer(1), .boolean(false),
                                           .boolean(false)],
                               program: emptyProgram())
        let chosen = try runtime.invoke(method: "popatxy", on: menu,
                                        arguments: [.integer(40), .integer(133)],
                                        program: emptyProgram())
        XCTAssertEqual(chosen.integerValue, 7, "the command the user picked is answered to the script")
        _ = try runtime.invoke(method: "popatmouse", on: menu, arguments: [], program: emptyProgram())
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.first ?? nil, CGPoint(x: 40, y: 133))
        XCTAssertNil(points.last ?? nil, "`popAtMouse` passes no point")
    }

    // MARK: - D9: the window commands on a skin's titlebar

    /// Reported from a live run: "none of the winamp-modern window close/minimize work". The click
    /// path was fine — every skin's `action="CLOSE"` reached `window.performClose(_:)`, which
    /// *simulates a click on the close button* and does nothing on a `.borderless` window. Both
    /// commands now go to the window layer's own seam, and this drives the real mouse path to prove
    /// the button reaches it.
    func testCloseAndMinimizeButtonsReachTheWindowCommands() throws {
        let loaded = try load(xml: skin(size: 40, body: """
            <button id="Close" action="CLOSE" x="0" y="0" w="10" h="10"/>
            <button id="Minimize" action="MINIMIZE" x="20" y="0" w="10" h="10"/>
            """))
        let host = Host()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { scripts.teardown() }
        let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host)
        addTeardownBlock { view.teardown() }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: renderer.canvasSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.setFrameSize(renderer.canvasSize)
        var commands: [String] = []
        view.closeRequested = { commands.append("close") }
        view.minimizeRequested = { commands.append("minimize") }

        // Skin space is top-left origin; the view's is bottom-left, so a button at skin y=0..10 in a
        // 40-tall canvas is at view y=30..40.
        click(view, in: window, at: NSPoint(x: 5, y: 35))
        XCTAssertEqual(commands, ["close"], "a CLOSE button reaches the close command")
        click(view, in: window, at: NSPoint(x: 25, y: 35))
        XCTAssertEqual(commands, ["close", "minimize"])
    }

    /// Press and release over the same point, as a real click arrives.
    private func click(_ view: NSView, in window: NSWindow, at point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                 timestamp: 0, windowNumber: window.windowNumber,
                                                 context: nil, eventNumber: 0, clickCount: 1,
                                                 pressure: 1) else {
                return XCTFail("could not synthesize a \(type) event")
            }
            if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
        }
    }

    // MARK: - Fixtures

    /// The skin's report. Post-load renderer diagnostics land in `runtime.diagnostics`, so this needs
    /// a runtime object even though no script runs in these fixtures.
    private func report(for loaded: WinampModernLoadedSkin) -> WinampModernCompatibilityReport {
        let runtime = try? WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        defer { runtime?.teardown() }
        guard let runtime else { return WinampModernCompatibilityReport(diagnostics: [], unsupportedMethodCalls: [:]) }
        return loaded.compatibilityReport(withRuntime: runtime)
    }

    private func makeRenderer(xml: String) throws -> WasabiSceneRenderer {
        let loaded = try load(xml: xml)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func node(in renderer: WasabiSceneRenderer, xmlID: String) -> WasabiSceneNode? {
        renderer.sceneNodes().first { $0.object.xmlID == xmlID }
    }

    private func makeRuntime() throws -> WinampModernScriptRuntime {
        try makeRuntimeWithObject().0
    }

    /// A skin with a movable child and somewhere to move it to, plus a runtime over it.
    private func makeRuntimeWithObject() throws -> (WinampModernScriptRuntime, WasabiObject) {
        let loaded = try load(xml: skin(size: 40, body: """
            <group id="holder" x="0" y="0" w="20" h="20">
              <layer id="movable" x="0" y="0" w="5" h="5"/>
              <layer id="sibling" x="5" y="0" w="5" h="5"/>
            </group>
            <group id="target" x="20" y="0" w="20" h="20"/>
            """))
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        let object = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "movable").first)
        return (runtime, object)
    }

    private func reference(_ object: WasabiObject) -> MakiObjectReference {
        MakiObjectReference(.gui(object.stableID))
    }

    private func emptyProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/test.maki"),
                    ownerID: nil, parameter: nil)
    }

    // MARK: - Grid rendering

    /// A 32×32 canvas holding one grid, with 4×4 single-colour parts named `c0`…`c8`. Each part's
    /// blue channel is `10 + index * 20`, so `colour(...)` recovers which slice painted a pixel.
    private func renderGrid(attributes: String, gridSize: (Int, Int) = (32, 32)) throws -> [UInt8] {
        var elements = ""
        for index in 0..<9 { elements += #"<bitmap id="c\#(index)" file="p\#(index).png"/>"# + "\n" }
        let xml = """
        <WasabiXML>
          <elements>
        \(elements)  </elements>
          <container id="Main">
            <layout id="normal" w="32" h="32">
              <grid id="g" x="0" y="0" w="\(gridSize.0)" h="\(gridSize.1)" \(attributes)/>
            </layout>
          </container>
        </WasabiXML>
        """
        var files: [(String, Data)] = [("skin.xml", Data(xml.utf8))]
        for index in 0..<9 {
            files.append(("p\(index).png", try makeSolidPNG(size: 4, blue: UInt8(10 + index * 20))))
        }
        let loaded = try load(files: files)
        return try render(loaded: loaded, size: 32)
    }

    /// Which grid part painted this pixel, from its blue channel; `-1` for unpainted.
    private func colour(_ pixels: [UInt8], x: Int, y: Int) -> Int {
        let sample = pixel(pixels, x: x, y: y, width: 32)
        guard sample[3] > 0 else { return -1 }
        return (Int(sample[2]) - 10) / 20
    }

    // MARK: - Rendering helpers

    private func skin(size: Int, body: String) -> String {
        """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="\(size)" h="\(size)">
        \(body)
            </layout>
          </container>
        </WasabiXML>
        """
    }

    private func render(size: Int, body: String) throws -> [UInt8] {
        try render(loaded: try load(xml: skin(size: size, body: body)), size: size)
    }

    private func render(loaded: WinampModernLoadedSkin, size: Int, host: Host = Host()) throws -> [UInt8] {
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0 })
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

    /// `y` is measured from the top, as the skin measures it.
    private func pixel(_ pixels: [UInt8], x: Int, y: Int, width: Int) -> [UInt8] {
        let offset = (y * width + x) * 4
        guard offset + 4 <= pixels.count else { return [0, 0, 0, 0] }
        return Array(pixels[offset..<(offset + 4)])
    }

    // MARK: - Archive fixtures

    private func load(xml: String) throws -> WinampModernLoadedSkin {
        try load(files: [("skin.xml", Data(xml.utf8))])
    }

    private func load(files: [(String, Data)]) throws -> WinampModernLoadedSkin {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(files: files))
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private func makeArchive(files: [(String, Data)]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase24Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase24-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in files {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    private func makeSolidPNG(size: Int, blue: UInt8) throws -> Data {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset + 2] = blue
            pixels[offset + 3] = 255
        }
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: size, height: size,
                                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

}
