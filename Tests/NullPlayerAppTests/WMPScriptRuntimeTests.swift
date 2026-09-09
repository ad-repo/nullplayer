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

    /// **A geometry `_onchange` must fire in the transaction that wrote the geometry, not the next
    /// one.** Both compact-mode skins glue their transport bar to the video panel they collapse
    /// with `height_onchange="svTransports.top=svVideo.top+svVideo.height"`. Firing it a frame late
    /// left the bar trailing the panel the whole way down, and — because the last frame of an
    /// animation is followed by nothing until the skin's idle timer — the window sat visibly split
    /// into two pieces for four seconds (W87).
    func testAGeometryChangeHandlerFiresInTheSameTransactionAsTheWrite() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="panel" left="0" top="10" width="100" height="100"
                     height_onchange="bar.top = panel.top + panel.height;"/>
            <SUBVIEW id="bar" left="0" top="110" width="100" height="20"/>
            <BUTTON id="go" left="0" top="0" width="10" height="10" onClick="panel.height = 40;"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        func stableID(_ id: String) throws -> Int {
            try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == id }?.stableID)
        }
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go",
                                   handlers: ["panel.height = 40;"]))
        XCTAssertEqual(output.overrides.geometry[.init(stableID: try stableID("panel"),
                                                       property: "height")], 40)
        XCTAssertEqual(output.overrides.geometry[.init(stableID: try stableID("bar"),
                                                       property: "top")], 50,
                       "the dependent must land at panel.top + the height just written, in this "
                       + "same transaction — 50, never the 110 it was drawn at")
    }

    /// **A `moveTo` completes in the transaction that called it, and the skin chains from there**
    /// (W55). `corona`'s playlist drawer is the case that named the row: `TogglePlaylist()` only
    /// slides `svPlaylist`, and the list inside it is revealed solely by
    /// `onEndMove="ddpl.visible=ipl.visible=g_playlistIsVisible;"`. The endpoint already landed
    /// immediately (W38), so the honest completion of an instant move is now.
    func testAMoveToRaisesOnEndMoveInTheSameTransaction() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="drawer" left="200" top="0" width="100" height="100"
                     onEndMove="list.visible = true;"/>
            <SUBVIEW id="list" left="0" top="0" width="50" height="50" visible="false"/>
            <BUTTON id="go" left="0" top="0" width="10" height="10"
                    onClick="drawer.moveTo(0, 0, 400);"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        func stableID(_ id: String) throws -> Int {
            try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == id }?.stableID)
        }
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go",
                                   handlers: ["drawer.moveTo(0, 0, 400);"]))
        XCTAssertEqual(output.overrides.properties[.init(stableID: try stableID("list"),
                                                         property: "visible")], .bool(true),
                       "the drawer's onEndMove must have run, or it opens onto nothing")
    }

    /// `alphaBlendTo` is the other call with a completion, and the Alienware/ALX family chains its
    /// artwork fades from it.
    func testAnAlphaBlendToRaisesOnEndAlphaBlend() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="art" left="0" top="0" width="100" height="100" alphaBlend="0"
                     onEndAlphaBlend="next.visible = true;"/>
            <SUBVIEW id="next" left="0" top="0" width="10" height="10" visible="false"/>
            <BUTTON id="go" left="0" top="0" width="10" height="10"
                    onClick="art.alphaBlendTo(255, 200);"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let next = try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "next" }?.stableID)
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go",
                                   handlers: ["art.alphaBlendTo(255, 200);"]))
        XCTAssertEqual(output.overrides.properties[.init(stableID: next, property: "visible")],
                       .bool(true))
    }

    /// A completion handler may itself call `moveTo`, so the cascade is bounded the same way the
    /// geometry one is and a pair of panes that move each other cannot spin the transaction.
    func testCompletionHandlersCannotLoop() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="a" left="0" top="0" width="10" height="10" onEndMove="b.moveTo(1, 1, 10);"/>
            <SUBVIEW id="b" left="0" top="20" width="10" height="10" onEndMove="a.moveTo(2, 2, 10);"/>
            <BUTTON id="go" left="0" top="0" width="10" height="10" onClick="a.moveTo(3, 3, 10);"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go",
                                   handlers: ["a.moveTo(3, 3, 10);"]))
        XCTAssertFalse(output.overrides.geometry.isEmpty, "the transaction must still commit")
    }

    /// **A control's handler reads its own `value` as a bare name.** 111 of the 141 `onDragEnd`
    /// sources in the corpus are `player.controls.currentPosition = value` — the seek commit on
    /// release — and without the binding every one of them throws on its first statement.
    func testAnEventHandlerReadsItsTargetsValueAsABareName() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SLIDER id="seek" left="0" top="0" width="100" height="10" max="200"
                    onDragEnd="player.controls.currentPosition = value;"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let seek = try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "seek" }?.stableID)
        // The app's own order: the view is transacted into existence, the pointer then moves the
        // control, and the release is the transaction that reads it back. Setting the value before
        // any transaction writes only the committed override — there is no context to hold it yet.
        _ = await runtime.transact(skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
                                   snapshot: WMPHostSnapshot(), event: nil)
        await runtime.setWidgetValue(stableID: seek, value: 42)
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "onDragEnd", targetID: "seek",
                                   handlers: ["player.controls.currentPosition = value;"]))
        XCTAssertTrue(output.diagnostics.isEmpty,
                      "a bare `value` must resolve, not throw: \(output.diagnostics)")
        XCTAssertEqual(output.hostCommands.first?.action, "seekSeconds")
        XCTAssertEqual(output.hostCommands.first?.value?.number, 42)
    }

    /// The cascade is bounded and each handler fires once, so two panes that position off one
    /// another cannot spin the transaction.
    func testGeometryChangeHandlersCannotLoop() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="a" left="0" top="0" width="10" height="10" height_onchange="b.height = a.height + 1;"/>
            <SUBVIEW id="b" left="0" top="20" width="10" height="10" height_onchange="a.height = b.height + 1;"/>
            <BUTTON id="go" left="0" top="0" width="10" height="10" onClick="a.height = 5;"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go", handlers: ["a.height = 5;"]))
        XCTAssertFalse(output.overrides.geometry.isEmpty, "the transaction must still commit")
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

    /// W51/W52. The corpus writes three of this engine's events under WMP's `_onchange` spelling,
    /// and by a wide margin: `value_onchange` in 175 of 179 archives against the `onChange` form,
    /// `OpenState_onchange` in 144 and `PlayState_onchange` in 139 against 7 and 11 for
    /// `OpenStateChange`/`PlayStateChange` — on the same `<PLAYER>` element, calling the same
    /// handler. They were 2,750 uses of measured demand answering to nothing.
    ///
    /// Both spellings resolve through the **one** matcher every dispatch site already goes through,
    /// so a site cannot raise one name and miss the other. The negative half matters as much: a
    /// property whose `_onchange` this engine does not raise must still not be found, or the
    /// `UNKNOWN event` tally stops ranking it while nothing runs.
    func testTheOnchangeSpellingsResolveToTheEventsTheEngineDispatches() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
            <PLAYER PlayState_onchange="playState();" OpenState_onchange="openState();"/>
            <SLIDER id="eq1" left="0" top="0" width="10" height="40" min="-14" max="14"
                    value="wmpprop:eq.gainLevel1" value_onchange="eq.gainLevel1=value;"/>
            <SLIDER id="eq2" left="20" top="0" width="10" height="40" onChange="plain();"/>
            <TEXT id="label" left="40" top="0" width="20" height="10" textWidth_onchange="width();"/>
        </VIEW></THEME>
        """)
        func node(_ id: String) throws -> WMPNode {
            try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == id })
        }
        XCTAssertEqual(WMPMainWindowController.handlers(in: skin, event: "change", targetID: nil,
                                                        targetStableID: try node("eq1").stableID,
                                                        viewID: "main"),
                       ["eq.gainLevel1=value;"], "value_onchange is the change event's other spelling")
        XCTAssertEqual(WMPMainWindowController.handlers(in: skin, event: "change", targetID: nil,
                                                        targetStableID: try node("eq2").stableID,
                                                        viewID: "main"),
                       ["plain();"], "the onChange spelling must keep working")
        XCTAssertEqual(Set(WMPMainWindowController.handlers(in: skin, event: "openstatechange",
                                                            targetID: nil, viewID: "main")),
                       ["openState();"])
        XCTAssertEqual(Set(WMPMainWindowController.handlers(in: skin, event: "playstatechange",
                                                            targetID: nil, viewID: "main")),
                       ["playState();"])
        // Nothing raises a text element's width change, so nothing may answer for it either.
        XCTAssertTrue(WMPMainWindowController.handlers(in: skin, event: "change", targetID: nil,
                                                       targetStableID: try node("label").stableID,
                                                       viewID: "main").isEmpty,
                      "an _onchange this engine never raises must stay unmatched and keep ranking")
    }

    func testCompatibilityTableIsClosedAndChecked() {
        XCTAssertTrue(WMPJScriptCompatibility.supports(object: "controls", member: "play"))
        XCTAssertTrue(WMPJScriptCompatibility.supports(object: "theme", member: "currentViewID"))
        XCTAssertFalse(WMPJScriptCompatibility.supports(object: "player", member: "shellExecute"))
        XCTAssertFalse(WMPJScriptCompatibility.supports(object: "registry", member: "read"))
        // The static tally is measured against this table, so a member the runtime answers and the
        // table does not know reads as unimplemented demand for something that already works.
        XCTAssertTrue(WMPJScriptCompatibility.supports(object: "mediacenter", member: "videoZoom"))
        XCTAssertTrue(WMPJScriptCompatibility.supports(object: "mediacenter", member: "getnamedstring"))
        XCTAssertFalse(WMPJScriptCompatibility.supports(object: "mediacenter", member: "dvdChapter"))
        // Element *methods* count too: one the runtime answers but the table does not know is
        // measured as demand for something that already works, which is how `alphaBlendTo` was
        // ranked beside `moveTo` — implemented since Phase 3 — as outstanding work (W38).
        for method in WMPObjectModel.implementedElementMethods {
            XCTAssertTrue(WMPJScriptCompatibility.supports(object: "element", member: method),
                          "\(method) is implemented and the census still counts it as unknown")
            XCTAssertTrue(WMPObjectModel.elementMethodVocabulary.contains(method),
                          "\(method) must be in the closed method vocabulary")
        }
        XCTAssertFalse(WMPJScriptCompatibility.supports(object: "element", member: "setFocus"))
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

    /// W37: `mediacenter` was the largest single thing stopping a handler in the corpus — 159
    /// `ReferenceError: Can't find variable: mediacenter` across the 179 measured archives, killing
    /// `OnLoad` on whichever line first touched it. The object exists now and **every member of it
    /// is inert**, which is the finding and not a shortcut: there is no video surface to zoom, one
    /// effect with no type and no presets, and no high-contrast mode.
    ///
    /// The test pins the part a constant-returning stub would fail: a skin writes the effect
    /// selection and reads it back out of a second view, so the session must remember the write —
    /// while still posting no host command and still resolving `inert`, so the census keeps ranking
    /// the demand instead of losing it.
    func testMediaCenterRoundTripsSessionStateAndStaysInert() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
          <SUBVIEW id="pane" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let write = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onClick", targetID: "pane",
                         handlers: ["mediacenter.effectPreset = 4; mediacenter.videoZoom = 150;"]))
        XCTAssertTrue(write.calls.allSatisfy { $0.path.hasPrefix("mediacenter.") ? $0.resolution == .inert : true })
        XCTAssertTrue(write.hostCommands.isEmpty, "nothing is behind mediacenter to command")
        XCTAssertFalse(write.diagnostics.contains { $0.code == "handler-error" })

        // The read-back is a second transaction, the way `Plus! Professional` reads in one view
        // what its other view wrote.
        let read = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onClick", targetID: "pane",
                         handlers: ["pane.left = mediacenter.effectPreset; pane.top = mediacenter.videoZoom;"]))
        let pane = try XCTUnwrap(skin.graph.nodes(id: "pane").first)
        XCTAssertEqual(read.overrides.geometry[.init(stableID: pane.stableID, property: "left")], 4)
        XCTAssertEqual(read.overrides.geometry[.init(stableID: pane.stableID, property: "top")], 150)
        let preset = try XCTUnwrap(read.calls.first { $0.path == "mediacenter.effectpreset" })
        XCTAssertEqual(preset.resolution, .inert, "a member with no host behind it must stay counted apart")
        await session.teardown()
    }

    /// The other half of W37, and the half that keeps the tally honest. An unwritten member answers
    /// the documented default rather than `undefined`; `contrastMode` is the host's accessibility
    /// setting and is read-only in WMP too, so a *write* to it stays unrecognised; and a name the
    /// object does not carry still aborts its handler, so the tenth member ranks itself the way the
    /// first nine did.
    func testMediaCenterDefaultsAnswerAndItsSurfaceStaysClosed() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
          <SUBVIEW id="pane" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let defaults = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onClick", targetID: "pane",
                         handlers: ["pane.left = mediacenter.videoZoom;"
                                    + "pane.top = (mediacenter.contrastMode == '' && !mediacenter.showTitles"
                                    + " && mediacenter.showEffects && mediacenter.getNamedString('PLCID') == '') ? 7 : 0;"]))
        let pane = try XCTUnwrap(skin.graph.nodes(id: "pane").first)
        XCTAssertEqual(defaults.overrides.geometry[.init(stableID: pane.stableID, property: "left")], 100,
                       "an unwritten videoZoom answers WMP's 100%, not undefined")
        XCTAssertEqual(defaults.overrides.geometry[.init(stableID: pane.stableID, property: "top")], 7)

        let closed = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onClick", targetID: "pane",
                         handlers: ["mediacenter.contrastMode = 'BW'; pane.width = 33;",
                                    "mediacenter.dvdChapter; pane.height = 44;"]))
        // Element state lives for the whole session, so the properties the aborted statements would
        // have set are ones no earlier transaction touched: no override reaches the scene for them.
        XCTAssertNil(closed.overrides.geometry[.init(stableID: pane.stableID, property: "width")],
                     "a write to the read-only contrastMode must abort its handler")
        XCTAssertNil(closed.overrides.geometry[.init(stableID: pane.stableID, property: "height")],
                     "a member mediacenter does not carry must abort its handler")
        XCTAssertTrue(closed.calls.contains { $0.path == "mediacenter.contrastmode" && !$0.recognised })
        XCTAssertTrue(closed.calls.contains { $0.path == "mediacenter.dvdchapter" && !$0.recognised })
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

    /// WMP opens the named view as an *additional* window; this app has one WMP window, so the
    /// command is `openView` and the controller presents the view, remembering the one it covered
    /// so `closeView` has somewhere to go back to. It is deliberately **not** an alias for
    /// `setCurrentView`: the two mean different things to the host, and collapsing them here would
    /// erase the distinction before the controller could act on it.
    func testOpenViewPostsItsOwnHostCommandAndKeepsTheHandlerRunning() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60"/><VIEW id="panel" width="80" height="40"/></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onClick", targetID: "main",
                         handlers: ["theme.openView('panel'); theme.currentViewID = 'main';"]))
        let opened = try XCTUnwrap(output.hostCommands.first { $0.action == "openView" })
        XCTAssertEqual(opened.value?.string, "panel")
        XCTAssertFalse(output.hostCommands.contains { $0.action == "setCurrentView" && $0.value?.string == "panel" },
                       "openView must not be posted as a view replacement")
        // The statement after the call is what the whole entry was about: before this landed, the
        // unimplemented member aborted the handler and everything below it was never reached.
        XCTAssertTrue(output.hostCommands.contains { $0.action == "setCurrentView" && $0.value?.string == "main" })
        XCTAssertFalse(output.diagnostics.contains { $0.code == "handler-error" })
        let call = try XCTUnwrap(output.calls.first { $0.path == "theme.openview" && $0.kind == .invoke })
        XCTAssertEqual(call.resolution, .live, "a view is presented as a result; this is not an inert answer")
        await session.teardown()
    }

    /// A call with no view id names nothing the host could open. It stays unrecognised rather than
    /// posting a command with an empty string, which the controller would silently discard — the
    /// skin asking for something impossible must stay visible in the demand tally.
    func testOpenViewWithNoViewIDStaysUnrecognised() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60"/></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onClick", targetID: "main", handlers: ["theme.openView('');"]))
        XCTAssertFalse(output.hostCommands.contains { $0.action == "openView" })
        let call = try XCTUnwrap(output.calls.first { $0.path == "theme.openview" && $0.kind == .invoke })
        XCTAssertEqual(call.resolution, .unrecognised)
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

    @MainActor
    func testHoverRaisesExitOnTheNodeLeftBeforeEntryOnTheNodeReached() throws {
        let size = WMPSize(width: 40, height: 20)
        func hit(_ stableID: Int, _ nodeID: String, x: Double) -> WMPHitMetadata {
            WMPHitMetadata(stableID: stableID, nodeID: nodeID, kind: "button",
                frame: .init(x: x, y: 0, width: 20, height: 20), clipRect: nil,
                zIndex: 0, documentOrder: stableID, action: nil, sticky: false, enabled: true,
                mappingImage: nil, mappingTargets: [])
        }
        let hits = [hit(2, "left", x: 0), hit(3, "right", x: 20)]
        let scene = WMPScene(viewID: "main", canvasSize: size,
            resizeLimits: .init(minimum: size, maximum: size), commands: [], hits: hits,
            geometries: [:], unresolved: [], diagnostics: [], dirtyBounds: hits[0].frame,
            metrics: .init(resolvedNodeCount: 2, unresolvedNodeCount: 0, visibleBounds: hits[0].frame),
            wasBuiltOnMainThread: false)
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8,
            bytesPerRow: 160, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 20),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let view = WMPMainView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 40, height: 20))
        window.contentView = view; view.present(image, scene: scene)
        var events: [String] = []
        view.onScriptEvent = { name, target, _ in events.append("\(name):\(target ?? "-")") }
        func move(to x: CGFloat) throws {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: x, y: 10),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 0, pressure: 0))
            view.mouseMoved(with: event)
        }
        try move(to: 5)
        try move(to: 10)   // still inside the same control: no second entry
        try move(to: 30)
        // `mouseExited` reads nothing off the event, and AppKit refuses to synthesise an
        // `.mouseExited` through `NSEvent.mouseEvent`, so the pointer's last position stands in.
        view.mouseExited(with: try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved,
            location: NSPoint(x: 60, y: 10), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 0, pressure: 0)))
        XCTAssertEqual(events, ["mouseover:left", "mouseout:left", "mouseover:right", "mouseout:right"])
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

    /// W38. `alphaBlendTo` is the third of WMP's element animation methods and, measured over the
    /// 179 archives, the largest single unimplemented member on the backlog: 26 skins, 40 uses.
    /// It is also the mechanism the Alienware/ALX family is built out of — the animation artwork
    /// hangs off subviews authored `alphaBlend="0"`, which the builder lays out and then drops from
    /// the command list, so until this call commits nothing brings them back.
    ///
    /// The endpoint is applied immediately, exactly as `moveTo`/`resizeTo` are; the tween itself is
    /// rendering work and its completion callback is W55. What the test pins is the whole path, not
    /// the member: the write must reach `overrides.properties` under the name the scene builder
    /// reads, and the faded-in subtree must actually produce a paint command.
    func testAlphaBlendToFadesInASubtreeTheSceneHadDropped() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
          <SUBVIEW id="pane" left="0" top="0" width="80" height="40" alphaBlend="0">
            <TEXT id="label" left="0" top="0" width="40" height="10" value="art"/>
          </SUBVIEW>
        </VIEW></THEME>
        """)
        let pane = try XCTUnwrap(skin.graph.nodes(id: "pane").first)
        let label = try XCTUnwrap(skin.graph.nodes(id: "label").first)
        let builder = WMPSceneBuilder(loadedSkin: skin)
        let hidden = try await builder.build(viewID: "main", overrides: .empty)
        XCTAssertFalse(hidden.commands.contains { $0.stableID == label.stableID },
                       "an alphaBlend=0 subtree must not reach the command list to begin with")

        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onClick", targetID: "pane",
                         handlers: ["pane.alphaBlendTo(255, 300); pane.left = 1;"]))
        let call = try XCTUnwrap(output.calls.first {
            $0.path.hasSuffix("alphablendto") && $0.kind == .invoke
        })
        XCTAssertEqual(call.resolution, .live)
        XCTAssertEqual(output.overrides.geometry[.init(stableID: pane.stableID, property: "left")], 1,
                       "the handler must keep running past the call")
        XCTAssertEqual(output.overrides.properties[.init(stableID: pane.stableID, property: "alphablend")]?.number,
                       255)
        XCTAssertTrue(output.repaintNodeIDs.contains(pane.stableID))

        let faded = try await builder.build(viewID: "main", overrides: output.overrides)
        XCTAssertTrue(faded.commands.contains { $0.stableID == label.stableID },
                      "the subtree the skin faded in is still missing from the scene")
    }

    /// The endpoint is clamped to WMP's 0-255, and an element that never authored `alphaBlend`
    /// reads as fully opaque rather than as the 0 an unset numeric property answers — a skin that
    /// steps its own alpha (`x.alphaBlendTo(x.alphaBlend - 64, 200)`) would otherwise start from
    /// invisible and never come back.
    func testAlphaBlendReadsOpaqueByDefaultAndTheEndpointIsClamped() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
          <SUBVIEW id="pane" left="0" top="0" width="80" height="40"/>
        </VIEW></THEME>
        """)
        let pane = try XCTUnwrap(skin.graph.nodes(id: "pane").first)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onClick", targetID: "pane",
                         handlers: ["pane.top = pane.alphaBlend; pane.alphaBlendTo(400, 100);"]))
        XCTAssertEqual(output.overrides.geometry[.init(stableID: pane.stableID, property: "top")], 255,
                       "an unauthored alphaBlend must read opaque")
        XCTAssertEqual(output.overrides.properties[.init(stableID: pane.stableID, property: "alphablend")]?.number,
                       255, "the endpoint must be clamped to WMP's 0-255")
        await session.teardown()
    }

    /// The other half of W38. `setColumnWidth` is recognised on the playlist kinds so it stops
    /// aborting the handler that calls it, but nothing draws playlist columns, so it is counted
    /// **inert** — the census keeps ranking the demand instead of losing it to a member that reads,
    /// from every instrument, exactly like a working one.
    func testSetColumnWidthIsRecognisedOnPlaylistsAndCountedInert() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
          <PLAYLIST id="pl" left="0" top="0" width="80" height="40"/>
          <SUBVIEW id="pane" left="0" top="50" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let pane = try XCTUnwrap(skin.graph.nodes(id: "pane").first)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onLoad", targetID: "main",
                         handlers: ["pl.setColumnWidth(0, 120); pane.left = 3;",
                                    "pane.setColumnWidth(0, 120); pane.top = 7;"]))
        let call = try XCTUnwrap(output.calls.first {
            $0.path.hasSuffix("setcolumnwidth") && $0.kind == .invoke
        })
        XCTAssertEqual(call.resolution, .inert)
        XCTAssertTrue(call.recognised, "an inert member must not abort the handler that touched it")
        XCTAssertEqual(output.overrides.geometry[.init(stableID: pane.stableID, property: "left")], 3)
        // The method surface stays closed on the kinds WMP does not define it for.
        XCTAssertNil(output.overrides.geometry[.init(stableID: pane.stableID, property: "top")],
                     "setColumnWidth on a SUBVIEW must stay unrecognised")
        XCTAssertTrue(output.calls.contains {
            $0.path.hasSuffix("setcolumnwidth") && $0.kind == .read && !$0.recognised
        }, "the SUBVIEW's method read must stay unrecognised")
        await session.teardown()
    }

    private func fixtureScript(_ name: String) throws -> String {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/WMPSkin")
        return try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
}
