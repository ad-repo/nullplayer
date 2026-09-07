import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// The script runtime: one persistent `JSContext` per skin session, with a native Swift object
/// model as the security boundary. These tests are about the two things the helper-process model
/// could not do — hold state between two events, and let an expression call the skin's own code —
/// and about the bounds that had to survive the move in-process.
final class WMPScriptRuntimeTests: XCTestCase {
    private func runtime(_ name: String = #function,
                         executionSeconds: TimeInterval = 5) throws -> (WMPScriptRuntime, () -> Void) {
        let suite = "WMPScriptRuntimeTests.\(name).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data(name.utf8),
                                                                 defaults: defaults),
                                 executionSeconds: executionSeconds),
                { defaults.removePersistentDomain(forName: suite) })
    }

    private func load(wms: String, js: String? = nil) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]
        if let js { entries.append(WMPTestArchiveEntry("s.js", data: Data(js.utf8))) }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    /// A `.wmz` is free to leave a control unnamed, and Corona does: the button that switches it to
    /// its compact view is a bare `<BUTTON onClick="ToggleSuperCompact();">`. Dispatch filtered on
    /// the authored `id` and read a missing one as "no filter", so one click on that button ran
    /// **every** `onClick` in the view — the file dialog, both drawers and the view switch — leaving
    /// the skin in a compact view that renders like the player and is persisted across launches.
    /// Reported as "the playlist and eq drawers no longer open"; measured live as
    /// `event name=click target=nil handlers=16`.
    func testAnUnnamedNodeDispatchesOnlyItsOwnHandler() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
            <BUTTON id="named" left="0" top="0" width="10" height="10" onClick="named();"/>
            <BUTTON left="20" top="0" width="10" height="10" onClick="unnamed();"/>
            <BUTTON left="40" top="0" width="10" height="10" onClick="other();"/>
        </VIEW></THEME>
        """)
        func node(_ match: (WMPNode) -> Bool) throws -> WMPNode {
            try XCTUnwrap(skin.graph.allNodes.first(where: match))
        }
        let unnamed = try node { $0.xmlID == nil && $0.attributes.contains {
            $0.name.caseInsensitiveCompare("onClick") == .orderedSame } }
        let named = try node { $0.xmlID == "named" }

        XCTAssertEqual(WMPMainWindowController.handlers(in: skin, event: "click", targetID: nil,
                                                        targetStableID: unnamed.stableID, viewID: "main"),
                       ["unnamed();"], "an unnamed node must dispatch its own handler alone")
        XCTAssertEqual(WMPMainWindowController.handlers(in: skin, event: "click", targetID: "named",
                                                        targetStableID: named.stableID, viewID: "main"),
                       ["named();"])
        // View-scoped events still fan out on purpose: `load`, `timer` and the playstate events
        // depend on it, so a nil target must keep meaning "the whole view".
        XCTAssertEqual(WMPMainWindowController.handlers(in: skin, event: "click", targetID: nil,
                                                        viewID: "main").count, 3)
    }

    func testCompatibilityTableIsClosedAndChecked() {
        XCTAssertTrue(WMPJScriptCompatibility.supports(object: "controls", member: "play"))
        XCTAssertTrue(WMPJScriptCompatibility.supports(object: "theme", member: "currentViewID"))
        XCTAssertFalse(WMPJScriptCompatibility.supports(object: "player", member: "shellExecute"))
        XCTAssertFalse(WMPJScriptCompatibility.supports(object: "registry", member: "read"))
    }

    /// The defect the whole phase exists for. `g_paneCurrent` is set by one click handler and read
    /// by the next; under a fresh realm per transaction the second click found it undefined, so a
    /// pane toggle could open and never close.
    func testGlobalStateSurvivesBetweenTransactions() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60" scriptFile="s.js">
          <SUBVIEW id="pane" left="0" top="0" width="10" height="10" onClick="Toggle();"/>
        </VIEW></THEME>
        """, js: "var g_pane = 0; function Toggle() { g_pane = g_pane + 1; pane.left = g_pane; }")
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let size = WMPSize(width: 100, height: 60)
        let click = WMPJScriptEvent(name: "onClick", targetID: "pane", handlers: ["Toggle();"])
        let first = await session.transact(skin: skin, viewID: "main", size: size,
                                           snapshot: WMPHostSnapshot(), event: click)
        let second = await session.transact(skin: skin, viewID: "main", size: size,
                                            snapshot: WMPHostSnapshot(), event: click)
        let pane = try XCTUnwrap(skin.graph.nodes(id: "pane").first)
        let address = WMPScenePropertyAddress(stableID: pane.stableID, property: "left")
        XCTAssertEqual(first.overrides.geometry[address], 1)
        XCTAssertEqual(second.overrides.geometry[address], 2, "the second event started from a fresh realm")
        await session.teardown()
    }

    /// W21. The old probe pass sent no scripts at all, so an expression calling one of the skin's
    /// own functions threw `ReferenceError` — and one failure emptied the ordered list, leaving the
    /// view with no computed geometry whatsoever.
    func testExpressionsCallSkinFunctionsAndResolveInDependencyOrder() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="60" scriptFile="s.js">
          <SUBVIEW id="a" left="0" top="0" width="JScript:Half(view.width);" height="10"/>
          <SUBVIEW id="b" left="0" top="10" width="JScript:a.width + 5;" height="10"/>
        </VIEW></THEME>
        """, js: "function Half(value) { return value / 2; }")
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 200, height: 60), snapshot: WMPHostSnapshot(), event: nil)
        let a = try XCTUnwrap(skin.graph.nodes(id: "a").first)
        let b = try XCTUnwrap(skin.graph.nodes(id: "b").first)
        XCTAssertEqual(output.overrides.geometry[.init(stableID: a.stableID, property: "width")], 100)
        XCTAssertEqual(output.overrides.geometry[.init(stableID: b.stableID, property: "width")], 105)
        XCTAssertEqual(output.expressionOrder, ["a.width", "b.width"])
        await session.teardown()
    }

    /// One bad expression costs itself. The list is not emptied, and the rest of the view lays out.
    func testOneFailingExpressionCostsOnlyItself() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="60">
          <SUBVIEW id="bad" left="0" top="0" width="JScript:NoSuchFunction();" height="10"/>
          <SUBVIEW id="good" left="0" top="10" width="JScript:view.width - 20;" height="10"/>
        </VIEW></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 200, height: 60), snapshot: WMPHostSnapshot(), event: nil)
        let good = try XCTUnwrap(skin.graph.nodes(id: "good").first)
        XCTAssertEqual(output.overrides.geometry[.init(stableID: good.stableID, property: "width")], 180)
        XCTAssertTrue(output.diagnostics.contains { $0.code == "expression-error" })
        await session.teardown()
    }

    /// An unrecognised member aborts the handler that touched it, is tallied as measured demand,
    /// and leaves every other handler and every later transaction running.
    func testUnrecognisedMemberAbortsOneHandlerAndIsTallied() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
          <SUBVIEW id="pane" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onClick", targetID: "pane",
                         handlers: ["player.launchURL('http://example.com'); pane.left = 9;",
                                    "pane.top = 4;"]))
        let pane = try XCTUnwrap(skin.graph.nodes(id: "pane").first)
        XCTAssertNil(output.overrides.geometry[.init(stableID: pane.stableID, property: "left")],
                     "the aborted handler still committed a later statement")
        XCTAssertEqual(output.overrides.geometry[.init(stableID: pane.stableID, property: "top")], 4,
                       "the second handler did not run")
        XCTAssertTrue(output.calls.contains { $0.path == "player.launchurl" && !$0.recognised })
        XCTAssertTrue(output.diagnostics.contains { $0.code == "handler-error" })
        await session.teardown()
    }

    /// A member with no host behind it is counted apart from one that answers for real. Without
    /// that separation a stub reads, from every instrument, exactly like a working member.
    func testAnInertMemberIsRecognisedButCountedSeparately() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
          <SUBVIEW id="pane" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onClick", targetID: "pane",
                         handlers: ["theme.loadString('res://wmploc.dll/RT_STRING/#2099'); player.controls.play();"]))
        let inert = try XCTUnwrap(output.calls.first { $0.path == "theme.loadstring" && $0.kind == .invoke })
        XCTAssertEqual(inert.resolution, .inert)
        XCTAssertTrue(inert.recognised, "an inert member must not abort the handler that touched it")
        XCTAssertTrue(output.calls.contains { $0.path == "player.controls.play" && $0.resolution == .live })
        XCTAssertTrue(output.hostCommands.contains { $0.action == "play" })
        await session.teardown()
    }

    /// The capabilities the process sandbox used to deny are denied by the object model instead.
    func testDeniedGlobalsStayUndefinedInTheSessionContext() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
          <SUBVIEW id="probe" left="0" top="0" width="JScript:[typeof ActiveXObject, typeof WScript, typeof Enumerator, typeof fetch, typeof require, typeof XMLHttpRequest, typeof WebSocket, typeof ObjC].join(',') === 'undefined,undefined,undefined,undefined,undefined,undefined,undefined,undefined' ? 7 : 0;" height="10"/>
        </VIEW></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(), event: nil)
        XCTAssertEqual(output.expressions.first?.value, .number(7))
        await session.teardown()
    }

    /// The helper process could be killed; an in-process context cannot, so the execution-time
    /// limit is the thing standing between a hostile skin and a wedged session. If this test ever
    /// hangs, that limit is gone — which is exactly the failure it exists to catch.
    func testHostileLoopIsBoundedAndTheSessionStillAnswers() async throws {
        let context = WMPScriptContext(executionSeconds: 0.2)
        try XCTSkipUnless(context.executionLimitApplied,
                          "JavaScriptCore's execution-time limit is unavailable on this system")
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
          <SUBVIEW id="pane" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let (session, cleanup) = try runtime(executionSeconds: 0.2); defer { cleanup() }
        let size = WMPSize(width: 100, height: 60)
        let started = Date()
        let hostile = await session.transact(skin: skin, viewID: "main", size: size,
            snapshot: WMPHostSnapshot(),
            event: .init(name: "onClick", targetID: "pane", handlers: ["while (true) {}"]))
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertTrue(hostile.diagnostics.contains { $0.code == "handler-error" })
        let recovered = await session.transact(skin: skin, viewID: "main", size: size,
            snapshot: WMPHostSnapshot(),
            event: .init(name: "onClick", targetID: "pane", handlers: ["pane.left = 3;"]))
        let pane = try XCTUnwrap(skin.graph.nodes(id: "pane").first)
        XCTAssertEqual(recovered.overrides.geometry[.init(stableID: pane.stableID, property: "left")], 3)
        await session.teardown()
    }

    /// A timer callback keeps the variables it captured. Re-evaluating the function's *text*, which
    /// is all a stateless runtime could do, loses every one of them.
    func testTimerCallbackKeepsItsClosure() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60" scriptFile="s.js"/></THEME>
        """, js: "function Arm() { var step = 5; setInterval(function () { view.left = step; }, 40); }")
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let size = WMPSize(width: 100, height: 60)
        let armed = await session.transact(skin: skin, viewID: "main", size: size,
            snapshot: WMPHostSnapshot(),
            event: .init(name: "onLoad", targetID: "main", handlers: ["Arm();"]))
        let request = try XCTUnwrap(armed.timerRequests.first)
        XCTAssertTrue(request.repeats)
        XCTAssertEqual(request.periodMilliseconds, 40)
        let fired = await session.transact(skin: skin, viewID: "main", size: size,
            snapshot: WMPHostSnapshot(),
            event: .init(name: "timer", targetID: nil, handlers: [request.source]))
        let view = try XCTUnwrap(skin.views.first?.node)
        XCTAssertEqual(fired.overrides.geometry[.init(stableID: view.stableID, property: "left")], 5)
        await session.teardown()
    }

    /// Timer count and period stay inside the Phase 0 table. A skin does not get to relax them by
    /// asking harder.
    func testTimerStormStaysInsideThePhaseZeroLimits() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60"/></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let storm = "for (var i = 0; i < 4096; i++) { setTimeout(function () {}, 0); }"
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onLoad", targetID: "main", handlers: [storm]))
        XCTAssertEqual(output.timerRequests.count, WMPPhase0Limits.activeTimers)
        XCTAssertTrue(output.timerRequests.allSatisfy {
            $0.periodMilliseconds >= WMPPhase0Limits.minimumTimerPeriodMilliseconds
        })
        await session.teardown()
    }

    /// Members are spelled both ways in the same corpus file, because WMP's host objects are
    /// IDispatch. A case-sensitive bridge answers `undefined` for a call that works in WMP.
    func testMemberResolutionIsCaseInsensitive() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
          <SUBVIEW id="pane" left="0" top="0"
                   width="JScript:player.currentmedia.getiteminfo('Artist').length + player.currentMedia.getItemInfo('artist').length;"
                   height="10"/>
        </VIEW></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        var snapshot = WMPHostSnapshot()
        snapshot.metadata = WMPMediaMetadata(title: "T", artist: "Four", album: "A")
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: snapshot, event: nil)
        XCTAssertEqual(output.expressions.first?.value, .number(8))
        await session.teardown()
    }

    /// The view's own timer is a *host* timer. Corona's compact view collapses its video panel
    /// entirely through this — `RegisterTimerEvent` then `view.timerInterval = leastInterval` — and
    /// its player view declares `timerInterval="4000"` in markup to drive its transport readouts.
    /// Wiring `setTimeout` and not this left both views frozen with no diagnostic to say why.
    func testWritingViewTimerIntervalPostsAHostTimerCommand() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60" timerInterval="0" onTimer="Tick();"/></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onLoad", targetID: "main", handlers: ["view.timerInterval = 50;"]))
        XCTAssertTrue(output.hostCommands.contains {
            $0.action == "setViewTimerInterval" && $0.value == .number(50)
        })
        XCTAssertEqual(WMPMainWindowController.authoredTimerInterval(in: skin, viewID: "main"), 0)
        await session.teardown()
    }

    /// An element answers the geometry it is *drawn* at, not only what markup authored. Corona's
    /// `ResizeY` animates `svVideo` to 0 and gives up on the first tick if it reads 0 to begin
    /// with — which is what an authored-attributes-only model reports for an element sized by its
    /// background bitmap.
    func testElementGeometryAnswersTheLayoutTheSkinIsDrawnAt() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
          <SUBVIEW id="pane" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let pane = try XCTUnwrap(skin.graph.nodes(id: "pane").first)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onLoad", targetID: "main", handlers: ["pane.top = pane.height;"]),
            geometry: [pane.stableID: WMPRect(x: 0, y: 0, width: 10, height: 41)])
        XCTAssertEqual(output.overrides.geometry[.init(stableID: pane.stableID, property: "top")], 41,
                       "the element answered its authored height instead of the drawn one")
        await session.teardown()
    }

    /// `FILE_OPEN` is the only route to a track in WMP mode, because the auxiliary NullPlayer
    /// windows stay hidden until they have WMP-owned chrome. It is inert on purpose: the picker is
    /// main-actor work the script queue must not block on, so the skin's own `player.URL = newFile`
    /// line does nothing and the host plays the result.
    func testOpenDialogPostsAFileCommandAndIsCountedInert() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60"/></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onClick", targetID: "main",
                         handlers: ["var f = theme.openDialog('FILE_OPEN', 'FILES_ALLMEDIA');"]))
        XCTAssertTrue(output.hostCommands.contains { $0.action == "openFileDialog" })
        // The member *read* that resolves the function is live; the call is what has nothing behind
        // it, and that is the one the demand tally must show as inert.
        let call = try XCTUnwrap(output.calls.first { $0.path == "theme.opendialog" && $0.kind == .invoke })
        XCTAssertEqual(call.resolution, .inert)
        XCTAssertFalse(output.diagnostics.contains { $0.code == "handler-error" })
        await session.teardown()
    }

    func testSessionDetectsDependencyCycleWithoutCommittingPartialGeometry() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="50"><SUBVIEW id="a" left="0" top="0"
        width="jscript:b.width" height="10"/><SUBVIEW id="b" left="0" top="10"
        width="jscript:a.width" height="10"/></VIEW></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 50), snapshot: WMPHostSnapshot(), event: nil)
        XCTAssertTrue(output.overrides.geometry.isEmpty)
        XCTAssertTrue(output.diagnostics.contains { $0.code == "dependency-cycle" })
        await session.teardown()
    }

    func testPropertyRegistryCoalescesBindingsAndPreventsOriginFeedback() throws {
        let graph = WMPObjectGraph(document: try WMPXMLParser().parse("""
        <VIEW id="main"><TEXT id="time" value="wmpprop:player.controls.currentPositionString"/>
        <BUTTON id="play" enabled="wmpenabled:player.controls.play"/>
        <BUTTON id="pause" visible="wmpenabled:player.controls.pause"/></VIEW>
        """, path: "bindings.wms"))
        var registry = WMPObservablePropertyRegistry(graph: graph)
        var snapshot = WMPHostSnapshot(); snapshot.playlistCount = 1; snapshot.currentTime = 5
        let first = registry.changes(for: snapshot)
        XCTAssertEqual(first.count, 3)
        XCTAssertTrue(first.contains { $0.value == .string("0:05") })
        XCTAssertTrue(first.contains { $0.value == .bool(true) })
        let pause = try XCTUnwrap(graph.nodes(id: "pause").first)
        XCTAssertTrue(first.contains {
            $0.address == WMPScenePropertyAddress(stableID: pause.stableID, property: "visible")
                && $0.value == .bool(false)
        })
        XCTAssertTrue(registry.changes(for: snapshot).isEmpty)
        let origin = WMPPropertyTransactionOrigin(id: UUID())
        _ = registry.changes(for: snapshot, origin: origin)
        XCTAssertTrue(registry.changes(for: snapshot, origin: origin).isEmpty)
    }

    func testPreferencesAreHashNamespacedBoundedAndResettable() throws {
        let suite = "WMPPhase5Tests.preferences.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let first = WMPPreferenceStore(skinData: Data("one".utf8), defaults: defaults, maximumCount: 1)
        let second = WMPPreferenceStore(skinData: Data("two".utf8), defaults: defaults, maximumCount: 1)
        XCTAssertNotEqual(first.namespace, second.namespace)
        XCTAssertTrue(first.apply([.init(key: "a", value: "1")]).isEmpty)
        XCTAssertEqual(first.values(), ["a": "1"]); XCTAssertTrue(second.values().isEmpty)
        XCTAssertEqual(first.apply([.init(key: "b", value: "2")]).first?.code, "preference-count-limit")
        XCTAssertEqual(first.apply([.init(key: "a", value: String(repeating: "x", count: WMPPhase0Limits.preferenceValueBytes + 1))]).first?.code,
                       "preference-value-too-large")
        first.reset(); XCTAssertTrue(first.values().isEmpty)
    }

    func testSceneOverridesCommitResolvedGeometryAndPropertyAtomically() async throws {
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="100" height="50"><TEXT id="label" left="jscript:view.width/2"
            top="5" width="40" height="10" value="old"/></VIEW></THEME>
            """.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let label = try XCTUnwrap(skin.graph.nodes(id: "label").first)
        var overrides = WMPSceneOverrides.empty
        overrides.geometry[.init(stableID: label.stableID, property: "left")] = 50
        overrides.properties[.init(stableID: label.stableID, property: "value")] = .string("new")
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main", overrides: overrides)
        XCTAssertEqual(scene.geometries[label.stableID]?.absoluteFrame.x, 50)
        guard case let .text(text) = scene.commands.first(where: { $0.stableID == label.stableID })?.paint else {
            return XCTFail("missing text command")
        }
        XCTAssertEqual(text.value, "new")
    }

    @MainActor
    func testScriptOnlyButtonDispatchesClickWithoutTransportAction() throws {
        let size = WMPSize(width: 20, height: 20)
        let hit = WMPHitMetadata(stableID: 2, nodeID: "scriptOnly", kind: "button",
            frame: .init(x: 0, y: 0, width: 20, height: 20), clipRect: nil,
            zIndex: 0, documentOrder: 2, action: nil, sticky: false, enabled: true,
            mappingImage: nil, mappingTargets: [])
        let scene = WMPScene(viewID: "main", canvasSize: size,
            resizeLimits: .init(minimum: size, maximum: size), commands: [], hits: [hit],
            geometries: [:], unresolved: [], diagnostics: [], dirtyBounds: hit.frame,
            metrics: .init(resolvedNodeCount: 1, unresolvedNodeCount: 0, visibleBounds: hit.frame),
            wasBuiltOnMainThread: false)
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8,
            bytesPerRow: 80, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 20, height: 20),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let view = WMPMainView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 20, height: 20))
        window.contentView = view; view.present(image, scene: scene)
        var events: [String] = []
        view.onScriptEvent = { name, target, _ in events.append("\(name):\(target ?? "-")") }
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 10, y: 10),
            modifierFlags: [], timestamp: 0.01, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 0))
        view.mouseDown(with: down); view.mouseUp(with: up)
        XCTAssertTrue(events.contains("click:scriptOnly"))
    }

    func testOptInNineSeriesScriptsAndGeometryAtThreeSizes() async throws {
        guard let path = ProcessInfo.processInfo.environment["WMP_TEST_WMZ"], !path.isEmpty else {
            throw XCTSkip("Set WMP_TEST_WMZ to a user-supplied WMP skin.")
        }
        let url = URL(fileURLWithPath: path)
        let skin = try await WMPSkinLoader().load(from: url)
        let viewID = skin.views.first { $0.id.caseInsensitiveCompare("vPlayer") == .orderedSame }?.id
            ?? skin.views[0].id
        XCTAssertEqual(skin.scripts.filter { $0.status == .available }.count, skin.scriptSources.count)
        let base = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: viewID)
        let suite = "WMPPhase5Tests.corpus.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let session = WMPScriptRuntime(
            preferences: WMPPreferenceStore(skinData: try Data(contentsOf: url), defaults: defaults),
            executionSeconds: 5)
        let sizes = [base.resizeLimits.minimum, base.canvasSize,
            base.resizeLimits.clamp(.init(width: base.canvasSize.width + 160, height: base.canvasSize.height + 100))]
        var resolvedCounts: [Int] = []
        for size in sizes {
            let output = await session.transact(skin: skin, viewID: viewID, size: size,
                snapshot: WMPHostSnapshot(), event: .init(name: "load", targetID: viewID,
                    handlers: WMPMainWindowController.handlers(in: skin, event: "load", targetID: nil)))
            XCTAssertFalse(output.diagnostics.contains { $0.code == WMPPhase0DiagnosticCode.scriptTimedOut.rawValue
                || $0.code == WMPPhase0DiagnosticCode.scriptCrashed.rawValue })
            let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: viewID,
                requestedSize: size, overrides: output.overrides)
            resolvedCounts.append(scene.metrics.resolvedNodeCount)
        }
        XCTAssertEqual(resolvedCounts.count, 3)
        XCTAssertTrue(resolvedCounts.allSatisfy { $0 > 0 })
    }

    private func fixtureScript(_ name: String) throws -> String {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/WMPSkin")
        return try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
}
