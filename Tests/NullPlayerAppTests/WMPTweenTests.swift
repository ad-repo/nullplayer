import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// **W194: `moveTo`/`resizeTo`/`alphaBlendTo` animate over the duration they were given.**
///
/// Reported against `Compact`'s drawers as *"its not a smooth opening"*. The endpoint landed at the
/// handler boundary and `onEndMove` was raised in the same transaction, so a 1,000 ms slide took
/// one frame and nothing in the corpus ever moved over its duration.
///
/// **The whole shape of the fix is the split these tests are written around**: a tween animates
/// only where something is driving frames. A caller with no clock — a render dump, the corpus
/// census, the windowless dispatcher (W89) — gets exactly the behaviour it had before this row, so
/// every measurement taken on this subsystem still holds and the settled state is identical either
/// way. The first two tests are that invariant; the rest are the motion.
///
/// The frame-level tests use a 10 s duration when they need a tween still running and a 1 ms one
/// when they need it finished, because a frame's progress comes from the wall clock — the harness
/// pins frames for GIFs (`WMP_RENDER_CLOCK`) and there is no such pin here.
final class WMPTweenTests: XCTestCase {

    private func load(wms: String, js: String? = nil) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]
        if let js { entries.append(WMPTestArchiveEntry("s.js", data: Data(js.utf8))) }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    private func runtime(_ name: String = #function) throws -> (WMPScriptRuntime, () -> Void) {
        let suite = "WMPTweenTests.\(name).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data(name.utf8),
                                                                 defaults: defaults)),
                { defaults.removePersistentDomain(forName: suite) })
    }

    private func stableID(_ skin: WMPLoadedSkin, _ id: String) throws -> Int {
        try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == id }?.stableID)
    }

    private let canvas = WMPSize(width: 400, height: 200)

    /// The drawer template Microsoft shipped, reduced to the three nodes that matter: a tab that
    /// slides the drawer, and a list inside it that only `onEndMove` ever reveals.
    private func drawerSkin(onEndMove: String = "list.visible = true;") -> String {
        """
        <THEME><VIEW id="main" width="400" height="200" scriptFile="s.js">
            <SUBVIEW id="drawer" left="100" top="0" width="100" height="100"
                     onEndMove="\(onEndMove)"/>
            <SUBVIEW id="list" left="0" top="0" width="10" height="10" visible="false"/>
            <BUTTON id="tab" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """
    }

    private func click(_ runtime: WMPScriptRuntime, _ skin: WMPLoadedSkin, _ source: String,
                       animates: Bool) async -> WMPScriptOutput {
        await runtime.transact(
            skin: skin, viewID: "main", size: canvas, snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "tab", handlers: [source]),
            animatesTweens: animates)
    }

    private func left(_ output: WMPScriptOutput, _ skin: WMPLoadedSkin) throws -> CGFloat? {
        output.overrides.geometry[.init(stableID: try stableID(skin, "drawer"), property: "left")]
    }

    private func listIsVisible(_ output: WMPScriptOutput, _ skin: WMPLoadedSkin) throws -> Bool {
        output.overrides.properties[.init(stableID: try stableID(skin, "list"),
                                          property: "visible")] == .bool(true)
    }

    // MARK: - The caller with no clock is unchanged

    /// **The invariant the corpus sweep rests on.** Every headless probe in this subsystem runs
    /// without `animatesTweens`, and for them a duration is still a statement about where the
    /// element ends up rather than about how it gets there: the endpoint lands in this transaction
    /// (W38) and the completion is raised from it (W55).
    func testWithoutAClockTheEndpointAndItsCompletionStillLandAtOnce() async throws {
        let skin = try await load(wms: drawerSkin(),
                                  js: "function Move() { drawer.moveTo(300, drawer.top, 400); }")
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await click(runtime, skin, "Move();", animates: false)
        XCTAssertEqual(try left(output, skin), 300, "the endpoint still lands in this transaction")
        XCTAssertTrue(try listIsVisible(output, skin), "and `onEndMove` is still raised from it")
        XCTAssertFalse(output.hasActiveTweens, "a caller with no clock is never owed a frame")
    }

    /// The same skin, the same call, with a clock: the endpoint is **held back entirely** and the
    /// completion with it. This is the half of the change that carries the risk — 36 corpus views
    /// chain their next step off `onEndMove` — so it is pinned explicitly rather than inferred from
    /// the frame tests below.
    func testWithAClockNeitherTheEndpointNorItsCompletionLandsInTheClick() async throws {
        let skin = try await load(wms: drawerSkin(),
                                  js: "function Move() { drawer.moveTo(300, drawer.top, 10000); }")
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await click(runtime, skin, "Move();", animates: true)
        XCTAssertNotEqual(try left(output, skin), 300, "the drawer has not arrived yet")
        XCTAssertFalse(try listIsVisible(output, skin),
                       "`onEndMove` belongs to the end of the tween, not the end of the handler")
        XCTAssertTrue(output.hasActiveTweens, "and the window is owed frames")
    }

    // MARK: - The motion

    /// A frame drawn while the tween is still running lands **between** the two endpoints and
    /// leaves the view still owing frames. The value is not asserted exactly — it comes from the
    /// wall clock — only that it is somewhere along the way, which is the whole difference between
    /// a slide and a jump.
    func testAFrameInFlightLandsBetweenTheEndpointsAndOwesAnother() async throws {
        let skin = try await load(wms: drawerSkin(),
                                  js: "function Move() { drawer.moveTo(300, drawer.top, 10000); }")
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        _ = await click(runtime, skin, "Move();", animates: true)
        let stepped = await runtime.tweenFrame(skin: skin, viewID: "main", size: canvas,
                                               snapshot: WMPHostSnapshot())
        let frame = try XCTUnwrap(stepped)
        let position = try XCTUnwrap(try left(frame, skin))
        XCTAssertGreaterThanOrEqual(position, 100)
        XCTAssertLessThan(position, 300, "a frame 10 s into a 10 s slide would be the jump again")
        XCTAssertFalse(try listIsVisible(frame, skin), "still moving, so still no completion")
        XCTAssertTrue(frame.hasActiveTweens)
    }

    /// The last frame is the endpoint **itself** rather than an interpolation that happens to land
    /// near it — a drawer comes to rest on the pixel the skin named — and it carries `onEndMove`
    /// into the same transaction, so the handler that reveals the drawer's contents runs with the
    /// drawer already there.
    func testTheFinalFrameIsTheEndpointAndRaisesTheCompletion() async throws {
        let skin = try await load(wms: drawerSkin(),
                                  js: "function Move() { drawer.moveTo(300, drawer.top, 1); }")
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        _ = await click(runtime, skin, "Move();", animates: true)
        try await Task.sleep(nanoseconds: 20_000_000)
        let stepped = await runtime.tweenFrame(skin: skin, viewID: "main", size: canvas,
                                               snapshot: WMPHostSnapshot())
        let frame = try XCTUnwrap(stepped)
        XCTAssertEqual(try left(frame, skin), 300, "it must come to rest on the authored endpoint")
        XCTAssertTrue(try listIsVisible(frame, skin), "and `onEndMove` is raised from that frame")
        XCTAssertFalse(frame.hasActiveTweens, "nothing left to animate")
        let after = await runtime.tweenFrame(skin: skin, viewID: "main", size: canvas,
                                             snapshot: WMPHostSnapshot())
        XCTAssertNil(after, "a view with no motion in it answers no frame, which stops the loop")
    }

    /// **A duration of zero is not a tween**, clock or no clock: it is an instant move and a later
    /// read in the same handler must see it, which is what `movePlayButton()`'s
    /// `moveTo(x, 116, 0)` toggle depends on.
    func testAZeroDurationIsNeverAnimatedEvenWithAClock() async throws {
        let skin = try await load(wms: drawerSkin(), js: """
        function Move() { drawer.moveTo(300, drawer.top, 0); }
        function Read() { if (drawer.left == 300) { tab.visible = false; } }
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await click(runtime, skin, "Move();Read();", animates: true)
        XCTAssertEqual(try left(output, skin), 300)
        XCTAssertEqual(output.overrides.properties[.init(stableID: try stableID(skin, "tab"),
                                                         property: "visible")], .bool(false),
                       "an instant move is readable immediately")
        XCTAssertFalse(output.hasActiveTweens)
    }

    /// **A tween with nowhere to travel is over the moment it starts**, so its completion is raised
    /// at once. Without this a sequence chained off a no-op move — a drawer told to slide to where
    /// it already is — would stall forever waiting for a frame that has nothing to draw.
    func testAMoveToWhereTheElementAlreadyIsCompletesImmediately() async throws {
        let skin = try await load(wms: drawerSkin(),
                                  js: "function Move() { drawer.moveTo(100, 0, 400); }")
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await click(runtime, skin, "Move();", animates: true)
        XCTAssertTrue(try listIsVisible(output, skin))
        XCTAssertFalse(output.hasActiveTweens)
    }

    /// **A tween's endpoint is still not readable by the rest of the handler that started it**
    /// (W112), and under a clock it is doubly true: the element answers where it *is*.
    /// `Cablemusic`'s playlist tab is `onClick="PlayListMove();HidePlist();"` — the first slides
    /// the drawer and the second reads `subPlayList.left` to decide whether it is now open or shut.
    func testTheDestinationIsNotReadableInsideTheHandlerThatStartedTheSlide() async throws {
        let skin = try await load(wms: drawerSkin(), js: """
        function Move() { drawer.moveTo(300, drawer.top, 10000); }
        function Hide() { if (drawer.left == 300) { tab.visible = false; } }
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await click(runtime, skin, "Move();Hide();", animates: true)
        XCTAssertNil(output.overrides.properties[.init(stableID: try stableID(skin, "tab"),
                                                       property: "visible")],
                     "`drawer.left` still read 100, so the guard did not fire")
    }

    /// A second call on the same element and property **replaces** the one running rather than
    /// queueing behind it: a drawer re-toggled mid-slide reverses from wherever it currently is,
    /// which is what the one handler every drawer tab in the corpus carries actually means.
    func testASecondCallReplacesTheTweenAlreadyRunning() async throws {
        let skin = try await load(wms: drawerSkin(), js: """
        function Out() { drawer.moveTo(300, drawer.top, 10000); }
        function Back() { drawer.moveTo(0, drawer.top, 1); }
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        _ = await click(runtime, skin, "Out();", animates: true)
        _ = await click(runtime, skin, "Back();", animates: true)
        try await Task.sleep(nanoseconds: 20_000_000)
        let stepped = await runtime.tweenFrame(skin: skin, viewID: "main", size: canvas,
                                               snapshot: WMPHostSnapshot())
        let frame = try XCTUnwrap(stepped)
        XCTAssertEqual(try left(frame, skin), 0, "the reversal owns the element, not the first slide")
        XCTAssertFalse(frame.hasActiveTweens, "and the slide it replaced is not still running")
    }

    /// `resizeTo` animates like the other two and raises **nothing** at the end of it:
    /// `onEndResize` is zero uses corpus-wide and deliberately not implemented.
    func testResizeToAnimatesAndHasNoCompletion() async throws {
        let skin = try await load(wms: drawerSkin(),
                                  js: "function Grow() { drawer.resizeTo(300, 100, 1); }")
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let opened = await click(runtime, skin, "Grow();", animates: true)
        XCTAssertTrue(opened.hasActiveTweens)
        try await Task.sleep(nanoseconds: 20_000_000)
        let stepped = await runtime.tweenFrame(skin: skin, viewID: "main", size: canvas,
                                               snapshot: WMPHostSnapshot())
        let frame = try XCTUnwrap(stepped)
        XCTAssertEqual(frame.overrides.geometry[.init(stableID: try stableID(skin, "drawer"),
                                                      property: "width")], 300)
        XCTAssertFalse(try listIsVisible(frame, skin), "`onEndMove` is not a resize's completion")
    }

    /// A completion handler that starts the next step keeps the loop it was raised from: the tween
    /// it registers is picked up by the frame that raised it, so the sequence runs on without the
    /// caller starting a second clock. This is the shape `Compact` closes its drawer with.
    func testASequenceChainedFromACompletionKeepsTheLoopRunning() async throws {
        let skin = try await load(wms: drawerSkin(onEndMove: "Next();"), js: """
        function Move() { drawer.moveTo(300, drawer.top, 1); }
        function Next() { list.moveTo(50, 0, 10000); }
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        _ = await click(runtime, skin, "Move();", animates: true)
        try await Task.sleep(nanoseconds: 20_000_000)
        let stepped = await runtime.tweenFrame(skin: skin, viewID: "main", size: canvas,
                                               snapshot: WMPHostSnapshot())
        let frame = try XCTUnwrap(stepped)
        XCTAssertEqual(try left(frame, skin), 300, "the first slide finished")
        XCTAssertTrue(frame.hasActiveTweens,
                      "and the step its completion started is owed frames from the same loop")
    }

    /// A view that stops existing has no motion to finish. Nothing puts the endpoint back — this is
    /// the same rule `discardView` applies to the view's overrides and its elements (W90).
    func testDiscardingAViewDropsWhateverItWasAnimating() async throws {
        let skin = try await load(wms: drawerSkin(),
                                  js: "function Move() { drawer.moveTo(300, drawer.top, 10000); }")
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let opened = await click(runtime, skin, "Move();", animates: true)
        XCTAssertTrue(opened.hasActiveTweens)
        await runtime.discardView("main")
        let frame = await runtime.tweenFrame(skin: skin, viewID: "main", size: canvas,
                                             snapshot: WMPHostSnapshot())
        XCTAssertNil(frame)
    }

    // MARK: - The load transaction (W253)

    /// **A tween authored in `onLoad` animates, because the load transaction carries a clock too.**
    ///
    /// W194 promised `animatesTweens:` from the click and view-timer paths and left `load` out, so
    /// a skin that opens with a fade or a slide landed its endpoint in one frame. `Revert (1)`'s
    /// `onLoad="vwPlayer_OnLoad();alphaBlendTo(40,9000);"` is the clean case — a nine-second fade
    /// to translucent that arrived fully faded before the window was ever shown.
    ///
    /// **The `load` event is the whole point of these two.** Every test above drives a `click`, and
    /// it was the event rather than anything about the call that decided the outcome — which is
    /// also why the first attempt at this row was wired to the wrong transaction and still
    /// compiled, passed, and changed nothing on screen.
    private func fadingSkin() -> String {
        "<THEME><VIEW id=\"main\" width=\"400\" height=\"200\" alphaBlend=\"255\""
            + " onLoad=\"alphaBlendTo(40, 9000);\"/></THEME>"
    }

    private func dispatchLoad(_ runtime: WMPScriptRuntime, _ skin: WMPLoadedSkin,
                              animates: Bool) async -> WMPScriptOutput {
        await runtime.transact(
            skin: skin, viewID: "main", size: canvas, snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(
                name: "load", targetID: "main",
                handlers: WMPMainWindowController.handlers(in: skin, event: "load",
                                                           targetID: nil, viewID: "main")),
            animatesTweens: animates)
    }

    private func alpha(_ output: WMPScriptOutput, _ skin: WMPLoadedSkin) throws -> WMPJSONValue? {
        output.overrides.properties[.init(stableID: try stableID(skin, "main"),
                                          property: "alphablend")]
    }

    func testATweenAuthoredInOnLoadIsHeldBackAndAnimated() async throws {
        let skin = try await load(wms: fadingSkin())
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await dispatchLoad(runtime, skin, animates: true)
        XCTAssertNotEqual(try alpha(output, skin), .number(40),
                          "the fade has not arrived in the transaction that started it")
        XCTAssertTrue(output.hasActiveTweens, "and the window that opened it is owed frames")
    }

    /// The invariant half, and the reason no sweep or render dump moved when this row landed: a
    /// caller with no clock still gets the endpoint at the handler boundary, so the settled state
    /// every headless probe measures is what it always was.
    func testWithoutAClockAnOnLoadTweenStillArrivesAtOnce() async throws {
        let skin = try await load(wms: fadingSkin())
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await dispatchLoad(runtime, skin, animates: false)
        XCTAssertEqual(try alpha(output, skin), .number(40),
                       "a render dump and the census still see the settled state")
        XCTAssertFalse(output.hasActiveTweens)
    }
}
