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
        await runtime.setWidgetValue(stableID: seek, value: 42, viewID: "main")
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

    /// W136's half of the list above: the `<LISTBOX>` fill methods a playlist chooser is built
    /// out of are answered, so the census must stop ranking them as demand.
    func testTheListBoxFillMethodsAreImplemented() {
        for method in ["deleteall", "insertitem", "deleteitem", "appenditem", "getitem"] {
            XCTAssertTrue(WMPObjectModel.implementedElementMethods.contains(method), method)
            XCTAssertTrue(WMPJScriptCompatibility.supports(object: "element", member: method), method)
        }
    }

    /// W128. The vocabulary is the SDK's element-method list, and an SDK method this engine does
    /// **not** implement has to resolve unrecognised so the census can rank it. A name missing from
    /// the set falls into the open property surface instead, answers `""`, and dies as a bare
    /// `TypeError` — the same abort, but invisible to the instrument the backlog is ranked from,
    /// which is how `view.returnToMediaCenter` had to be found by a live reporter (W100).
    func testSDKElementMethodsAreCountedWhenUnimplemented() {
        // `returntomediacenter` was this list's `<VIEW>` example until W100 implemented it;
        // `restore` replaces it because the point is the *kind*, not the name — a VIEW method the
        // SDK defines and this engine does not answer still has to be counted rather than swallowed.
        // `deleteAll` and `insertItem` were this list's `<LISTBOX>` examples until W136 filled a
        // skin's playlist chooser; `findItem` and `replaceItem` are the list-box methods still
        // unanswered, and the ones W136 implemented are pinned the other way round below.
        for method in ["finditem", "replaceitem", "copy", "abortcopy", "deleteselected",
                       "restore", "sortcolumn", "getline", "getbutton"] {
            XCTAssertTrue(WMPObjectModel.elementMethodVocabulary.contains(method),
                          "\(method) is an SDK element method and must be counted, not swallowed")
            XCTAssertFalse(WMPObjectModel.implementedElementMethods.contains(method),
                           "\(method) gained an implementation — move this name to the other list")
            XCTAssertFalse(WMPJScriptCompatibility.supports(object: "element", member: method),
                           "\(method) is unimplemented, so the census must keep counting it")
        }
        // The surface stays closed: a name the SDK does not define is not a method here either,
        // because every name in this set also gates an *unauthored property read* of the same
        // spelling and would newly abort the handler that made it.
        for absent in ["settext", "refresh", "scrollintoview", "setvalue"] {
            XCTAssertFalse(WMPObjectModel.elementMethodVocabulary.contains(absent),
                           "\(absent) is not in the SDK's element-method list")
        }
    }

    /// W100. *Return to full mode* is the most widely authored control in the corpus — **162 of 180
    /// archives, 196 controls** — and it died on its own first statement until this. WMP leaves skin
    /// mode for the player's own shell; NullPlayer toggles the Library Browser, which is the closest
    /// surface it has to what that shell is for. Two things are pinned here and the second is the
    /// one to keep: it must post `toggleLibrary`, and it must **not** be `closeView` — taking the
    /// user's skin away on a button labelled "Return to full mode" is the outcome the backlog row
    /// forbade by name.
    ///
    /// Dispatched on the `<VIEW>` kind and never on the receiver's spelling: 13 of the 196 call it
    /// on a named view element (`vFull`, `ballview`, `KidsView`, `digitaldj`…) rather than on
    /// `view`, so `vFull.returnToMediaCenter()` has to reach the same command.
    func testReturnToMediaCenterTogglesTheLibrary() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="vFull" width="100" height="60">
          <SUBVIEW id="pane" left="0" top="45" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let pane = try XCTUnwrap(skin.graph.nodes(id: "pane").first)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "vFull",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onLoad", targetID: "vFull",
                         handlers: ["view.returnToMediaCenter(); pane.width = 3;",
                                    "vFull.returnToMediaCenter();"]))
        XCTAssertEqual(output.hostCommands.filter { $0.action == "toggleLibrary" }.count, 2,
                       "both the `view` receiver and the skin's own named one must reach the command")
        XCTAssertFalse(output.hostCommands.contains { $0.action == "closeView" },
                       "returning to full mode must never take the skin away")
        XCTAssertFalse(output.calls.contains { $0.path.hasSuffix("returntomediacenter") && !$0.recognised },
                       "the method is implemented and must no longer be counted as unmet demand")
        XCTAssertTrue(output.diagnostics.isEmpty, "the handler must not raise: \(output.diagnostics)")
        // 0 of the 196 corpus uses have a statement after the call, but the handler surviving it is
        // what separates an implementation from an `inert()` that merely stops the diagnostic.
        XCTAssertEqual(output.overrides.geometry[.init(stableID: pane.stableID, property: "width")], 3,
                       "the handler must continue past the call")
        await session.teardown()
    }

    /// W193. `view.size(corner)` is the corpus's resize grip — 235 calls in 88 of the 185 installed
    /// archives — and on a borderless `.wmz` window it is the only resize there is. It posted
    /// nothing until this, so the user reached for the macOS window edge and skipped whatever the
    /// skin wraps around its own resize (`Compact`'s `DoSize()` pins both drawers for the drag).
    ///
    /// Three claims, and the last is the one the corpus depends on: the corner reaches the host
    /// verbatim, the method is no longer counted as unmet demand, and **the handler continues past
    /// the call** — `DoSize()` has four statements after it and every one of them is the drawer
    /// bookkeeping the resize is for.
    ///
    /// Dispatched on the `<VIEW>` kind rather than the receiver's spelling, for the reason
    /// `returnToMediaCenter` is: a skin names its own view as often as it says `view`.
    func testViewSizePostsItsCornerToTheHost() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
          <SUBVIEW id="pane" left="0" top="45" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let pane = try XCTUnwrap(skin.graph.nodes(id: "pane").first)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onMouseDown", targetID: "main",
                         handlers: ["view.size('bottomright'); pane.width = 3;",
                                    "main.size( 'topleft' );"]))
        let sizes = output.hostCommands.filter { $0.action == "sizeWindow" }
        XCTAssertEqual(sizes.map { $0.value?.string }, ["bottomright", "topleft"],
                       "the corner rides the command's value, and a named view receiver reaches it too")
        XCTAssertFalse(output.calls.contains { $0.path.hasSuffix("size") && !$0.recognised },
                       "the method is implemented and must no longer be counted as unmet demand")
        XCTAssertTrue(output.diagnostics.isEmpty, "the handler must not raise: \(output.diagnostics)")
        XCTAssertEqual(output.overrides.geometry[.init(stableID: pane.stableID, property: "width")], 3,
                       "the handler must continue past the call — `DoSize()` unpins after it")
        await session.teardown()
    }

    /// The behavioural half of W128, on a still-unanswered `<LISTBOX>` method and the second
    /// highest-reach name in the corpus scan, `playlist2.copy()` (8), plus `view.restore()` for
    /// the `<VIEW>` kind. Each aborts its own handler exactly as before — the screen does not
    /// change — and each now appears in `output.calls` as unrecognised demand instead of nowhere.
    /// `view.returnToMediaCenter()` was the third until W100; it is pinned the other way round in
    /// `testReturnToMediaCenterTogglesTheLibrary`.
    func testUnimplementedSDKMethodsAreTalliedRatherThanSilent() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
          <LISTBOX id="box" left="0" top="0" width="40" height="20"/>
          <PLAYLIST id="pl" left="0" top="20" width="40" height="20"/>
          <SUBVIEW id="pane" left="0" top="45" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let pane = try XCTUnwrap(skin.graph.nodes(id: "pane").first)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let output = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onLoad", targetID: "main",
                         handlers: ["box.replaceItem(0, 'x'); pane.left = 1;",
                                    "pl.copy(); pane.top = 2;",
                                    "view.restore(); pane.width = 3;",
                                    "pane.height = 4;"]))
        for method in ["replaceitem", "copy", "restore"] {
            XCTAssertTrue(output.calls.contains {
                $0.path.hasSuffix(method) && $0.kind == .read && !$0.recognised
            }, "\(method) must be tallied as unrecognised demand, not answer as an empty string")
        }
        // Each call aborts its own handler at the statement that made it, and only that one.
        for property in ["left", "top", "width"] {
            XCTAssertNil(output.overrides.geometry[.init(stableID: pane.stableID,
                                                         property: property)],
                         "the handler must abort at the unrecognised method, as it did before")
        }
        XCTAssertEqual(output.overrides.geometry[.init(stableID: pane.stableID,
                                                       property: "height")], 4,
                       "an unrelated handler must still run")
        await session.teardown()
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
    /// `OnLoad` on whichever line first touched it. The object exists now, and **seven of its nine
    /// members are inert**: there is no video surface to zoom and no high-contrast mode.
    ///
    /// The test pins the part a constant-returning stub would fail: a skin writes one of the seven
    /// and reads it back out of a second view, so the session must remember the write — while still
    /// posting no host command and still resolving `inert`, so the census keeps ranking the demand
    /// instead of losing it.
    ///
    /// `effectType` and `effectPreset` are the two that left this class in W101: the `<EFFECTS>`
    /// rect they select for is hosted, so they reach a host and are pinned by
    /// `testMediaCenterEffectSelectionIsLiveAndCommandsTheHost`.
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
                         handlers: ["mediacenter.videoZoom = 150; mediacenter.showTitles = true;"]))
        XCTAssertTrue(write.calls.allSatisfy { $0.path.hasPrefix("mediacenter.") ? $0.resolution == .inert : true })
        XCTAssertTrue(write.hostCommands.isEmpty, "nothing is behind these members to command")
        XCTAssertFalse(write.diagnostics.contains { $0.code == "handler-error" })

        // The read-back is a second transaction, the way `Plus! Professional` reads in one view
        // what its other view wrote.
        let read = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onClick", targetID: "pane",
                         handlers: ["pane.top = mediacenter.videoZoom;"]))
        let pane = try XCTUnwrap(skin.graph.nodes(id: "pane").first)
        XCTAssertEqual(read.overrides.geometry[.init(stableID: pane.stableID, property: "top")], 150)
        let zoom = try XCTUnwrap(read.calls.first { $0.path == "mediacenter.videozoom" })
        XCTAssertEqual(zoom.resolution, .inert, "a member with no host behind it must stay counted apart")
        await session.teardown()
    }

    /// W101: the two `mediacenter` members 162 corpus archives keep their visualization selection
    /// in. The `<EFFECTS>` rect is hosted now, so a write commands the host rather than storing
    /// session state, and a read answers what the host says is being drawn — a skin that wrote
    /// `spikes`, which is a WMP visualizer this player does not have, must read back the effect
    /// that is really on screen and not its own string.
    func testMediaCenterEffectSelectionIsLiveAndCommandsTheHost() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
          <EFFECTS id="visEffects" left="0" top="0" width="80" height="40"/>
          <SUBVIEW id="pane" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        var snapshot = WMPHostSnapshot()
        snapshot.effects = WMPEffectsSnapshot(type: "geiss", title: "Geiss",
                                              preset: 3, presetTitle: "Rings")
        let write = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: snapshot,
            event: .init(name: "onClick", targetID: "pane",
                         handlers: ["mediacenter.effectType = 'spikes'; visEffects.next();"]))
        XCTAssertTrue(write.hostCommands.contains { $0.action == "setEffectType" })
        XCTAssertTrue(write.hostCommands.contains { $0.action == "stepEffect" })
        XCTAssertTrue(write.calls.contains { $0.path == "mediacenter.effecttype" && $0.resolution == .live })

        let read = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: snapshot,
            event: .init(name: "onClick", targetID: "pane",
                         handlers: ["pane.left = mediacenter.effectPreset;"
                                    + "pane.width = visEffects.currentPreset;"
                                    + "pane.value = visEffects.currentEffectTitle;"]))
        let pane = try XCTUnwrap(skin.graph.nodes(id: "pane").first)
        XCTAssertEqual(read.overrides.geometry[.init(stableID: pane.stableID, property: "left")], 3)
        XCTAssertEqual(read.overrides.geometry[.init(stableID: pane.stableID, property: "width")], 3)
        XCTAssertTrue(read.calls.contains {
            $0.path == "viseffects.currenteffecttitle" && $0.resolution == .live
        })
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

    /// **W260 — an `onTimer` with no `timerInterval` beside it ticks at WMP's default second.**
    ///
    /// `authoredTimerInterval` answered 0 for an absent attribute and every caller reads 0 as "this
    /// view has no timer", so the handler was registered and never once raised. `Stealth` writes its
    /// elapsed readout from `OnTimerTick()` and nothing else, so the skin sat at the authored
    /// `00:00` through a whole track while the visualizer ran beside it — reported as the skin not
    /// playing at all. **7 views in 7 archives** author the shape, measured over 184.
    func testAnOnTimerWithNoIntervalTakesWMPsDefaultSecond() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60" onTimer="OnTimerTick();"/></THEME>
        """)
        XCTAssertEqual(WMPMainWindowController.authoredTimerInterval(in: skin, viewID: "main"),
                       WMPMainWindowController.defaultTimerIntervalMilliseconds,
                       "the view asks for the event and leaves the period unstated")
        XCTAssertEqual(WMPMainWindowController.defaultTimerIntervalMilliseconds, 1_000)
    }

    /// The default is taken only where the view authors the handler: a view with no `onTimer` must
    /// keep costing nothing, which is 100+ archives' worth of transactions.
    func testAViewWithNoTimerHandlerStartsNoTimer() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60"/></THEME>
        """)
        XCTAssertEqual(WMPMainWindowController.authoredTimerInterval(in: skin, viewID: "main"), 0)
    }

    /// **An authored `0` still means off.** That is WMP's meaning for it and the corpus writes it
    /// deliberately — `corona`'s `viewTiny` opens stopped and starts its own clock from a script —
    /// so the default must not reach past an attribute the skin actually stated. Its companion is
    /// `testWritingViewTimerIntervalPostsAHostTimerCommand` above, which pins the same `0` against
    /// a view that does author `onTimer`.
    func testAnAuthoredZeroIntervalStaysOffAndAnAuthoredPeriodIsKept() async throws {
        let off = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60" timerInterval="0" onTimer="Tick();"/></THEME>
        """)
        XCTAssertEqual(WMPMainWindowController.authoredTimerInterval(in: off, viewID: "main"), 0)
        let stated = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60" timerInterval="4000" onTimer="Tick();"/></THEME>
        """)
        XCTAssertEqual(WMPMainWindowController.authoredTimerInterval(in: stated, viewID: "main"), 4_000)
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

    /// WMP skins distinguish an absent preference from one deliberately saved as an empty string.
    /// `Plus! Professional` tests `loadPreference("vidRightDrawer") != "--"`; answering `""`
    /// for an absent key therefore took its closed-drawer branch on a fresh skin session (W76).
    func testThemeLoadPreferenceUsesWMPAbsentSentinelAndPreservesSavedValues() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
            <TEXT id="answer" left="0" top="0" width="100" height="12"/>
        </VIEW></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let answer = try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "answer" }?.stableID)
        let missing = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onClick", targetID: "answer",
                         handlers: ["answer.value = theme.loadPreference('unset');"]))
        XCTAssertEqual(missing.overrides.properties[.init(stableID: answer, property: "value")], .string("--"))

        let saved = await session.transact(skin: skin, viewID: "main",
            size: .init(width: 100, height: 60), snapshot: WMPHostSnapshot(),
            event: .init(name: "onClick", targetID: "answer",
                         handlers: ["theme.savePreference('unset', 'open'); answer.value = theme.loadPreference('unset');"]))
        XCTAssertEqual(saved.overrides.properties[.init(stableID: answer, property: "value")], .string("open"))
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

    /// **`<attribute>_onchange` is a general SDK mechanism, and the attribute is readable by its
    /// own name inside its own handler (W129).** *Ambient Event Handlers*: "when a skin attribute
    /// changes value, an event occurs… the name of the event handler is the name of the attribute
    /// followed by `_onchange`". This engine collected four geometry properties and `value`;
    /// everything else the corpus writes in that form — 387 handlers across 104 of the 177
    /// measured archives — was classified `.literal` and was not a handler at all.
    ///
    /// The bare-name binding is the half that decides whether any of it runs: **68 of the corpus's
    /// 77 `currentEffectType_onchange` uses are `mediacenter.effectType=currentEffectType`**, and
    /// without the attribute bound that is a `ReferenceError` on the handler's first statement — a
    /// handler that dies silently, which is this row's whole failure mode.
    func testAnAmbientAttributeChangeHandlerFiresWithTheAttributeBoundByItsName() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="panel" left="0" top="0" width="100" height="100" alphaBlend="255"
                     alphaBlend_onchange="bar.top = alphaBlend;"/>
            <SUBVIEW id="bar" left="0" top="180" width="100" height="10"/>
            <BUTTON id="go" left="0" top="0" width="10" height="10"
                    onClick="panel.alphaBlend = 42;"/>
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
                                   handlers: ["panel.alphaBlend = 42;"]))
        XCTAssertEqual(output.overrides.geometry[.init(stableID: try stableID("bar"),
                                                       property: "top")], 42,
                       "a non-geometry attribute must raise its declared handler, and the handler "
                       + "must read the new value under the attribute's own authored name")
        XCTAssertTrue(output.diagnostics.filter { $0.code == "handler-error" }.isEmpty,
                      "the bare name must resolve, not throw: \(output.diagnostics)")
    }

    /// The bound is unchanged by generalising the property: only what the markup declared, and each
    /// `(element, attribute)` at most once per transaction, so two attributes that write each other
    /// cannot loop (W87's rule, now over every attribute rather than the four geometry ones).
    func testAmbientChangeHandlersThatWriteEachOtherCannotLoop() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="a" left="0" top="0" width="10" height="10" alphaBlend="255"
                     alphaBlend_onchange="b.alphaBlend = a.alphaBlend;"/>
            <SUBVIEW id="b" left="0" top="20" width="10" height="10" alphaBlend="255"
                     alphaBlend_onchange="a.alphaBlend = b.alphaBlend;"/>
            <BUTTON id="go" left="0" top="0" width="10" height="10" onClick="a.alphaBlend = 10;"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go",
                                   handlers: ["a.alphaBlend = 10;"]))
        XCTAssertTrue(output.diagnostics.filter { $0.code == "handler-error" }.isEmpty,
                      "a mutual pair must settle, not abort: \(output.diagnostics)")
    }

    /// **`value_onchange` must not be collected twice.** It has its own map and its own two
    /// directions (W51/W52); claiming it as an ambient attribute handler as well would raise it a
    /// second time in the same transaction, and 2,170 uses across 175 archives is the wrong place
    /// to discover that. The general rule is deliberately matched *after* it.
    func testValueOnchangeStaysOnItsOwnPathAndTheGeneralRuleTakesTheRest() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SLIDER id="s" left="0" top="0" width="10" height="40" min="0" max="10"
                    value_onchange="readout.left = value;"/>
            <TEXT id="label" left="0" top="50" width="40" height="10"
                  textWidth_onchange="readout.top = textWidth;"/>
            <SUBVIEW id="readout" left="0" top="60" width="10" height="10"/>
        </VIEW></THEME>
        """)
        func stableID(_ id: String) throws -> Int {
            try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == id }?.stableID)
        }
        let plan = WMPScriptViewPlan(skin: skin, viewID: "main")
        XCTAssertEqual(plan.valueChangeHandlers[try stableID("s")], "readout.left = value;")
        XCTAssertNil(plan.attributeChangeHandlers[try stableID("s")]?["value"],
                     "value belongs to the value path alone, or it fires twice per transaction")
        XCTAssertEqual(plan.attributeChangeHandlers[try stableID("label")]?["textwidth"]?.attribute,
                       "textWidth", "the authored spelling is what the handler reads it by")
    }

    /// The four host-driven ambient handlers (W129). They are attributes of the *player*, which no
    /// script writes and which move underneath the skin, and they carry the measured reach:
    /// `currentPosition_onchange` 105 uses / 81 skins, `currentEffectType_onchange` 77 / 65,
    /// `currentPlaylist_onchange` 65 / 48, `currentMedia_onchange` 12 / 9. They resolve through the
    /// same one matcher every other dispatch site goes through, and the negative half matters as
    /// much: a sibling spelling this engine does not raise must stay unmatched and keep ranking.
    func testTheHostAmbientChangeEventsResolveToTheirAuthoredHandlers() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
            <PLAYER currentPlaylist_onChange="updateMetadata('playlist');"
                    currentMedia_onChange="updateAlbumArt();">
                <controls currentPosition_onchange="seek.value=player.controls.currentPosition;"/>
            </PLAYER>
            <EFFECTS id="vis" left="0" top="0" width="50" height="50"
                     currentEffectType_onchange="mediacenter.effectType=currentEffectType;"
                     currentPreset_onchange="mediacenter.effectPreset=currentPreset;"/>
        </VIEW></THEME>
        """)
        for (event, source) in [("currenteffecttype_onchange", "mediacenter.effectType=currentEffectType;"),
                                ("currentposition_onchange", "seek.value=player.controls.currentPosition;"),
                                ("currentplaylist_onchange", "updateMetadata('playlist');"),
                                ("currentmedia_onchange", "updateAlbumArt();")] {
            XCTAssertEqual(WMPMainWindowController.handlers(in: skin, event: event, targetID: nil,
                                                            viewID: "main"),
                           [source], "\(event) must reach its authored handler")
        }
        // `currentPreset_onchange` is the fifth: the same element, the same write-back idiom, and
        // safe because `WMPEffectSelection.setPreset` early-returns on an unchanged value.
        XCTAssertEqual(WMPMainWindowController.handlers(in: skin, event: "currentpreset_onchange",
                                                        targetID: nil, viewID: "main"),
                       ["mediacenter.effectPreset=currentPreset;"])
        for event in ["currentposition_onchange", "currentmedia_onchange", "currentplaylist_onchange",
                      "currenteffecttype_onchange", "currentpreset_onchange"] {
            XCTAssertTrue(WMPCorpusReportHarness.supportedEvents.contains(event),
                          "\(event) has a dispatch site and must not rank as demand")
        }
        // The negative half still binds: an ambient name with no dispatch site must stay off the
        // list, or it drops out of the tally while still doing nothing.
        XCTAssertFalse(WMPCorpusReportHarness.supportedEvents.contains("textwidth_onchange"))
        XCTAssertFalse(WMPCorpusReportHarness.supportedEvents.contains("selecteditem_onchange"))
    }

    // MARK: - The slider's own position change (W56)

    /// **A dispatch site with no classification is as silent as a classification with no dispatch
    /// site.** `handlers(in:event:)` has accepted `positionchange` wherever it raises `change`
    /// since W119, but `onpositionchange` was never in `WMPAttributeValue.handlerNames`, so no
    /// attribute ever became a `.handler` under that name and the alias could never match: the
    /// running app raised `change targetID=<slider> handlers=0` while the markup sat in the graph
    /// as `.jScript` text. 151 uses across 42 of the 182 readable archives, every one on a
    /// `SLIDER` (91) or a `CUSTOMSLIDER` (60).
    func testASliderPositionChangeReachesItsAuthoredHandler() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
            <CUSTOMSLIDER id="volume" left="0" top="0" width="50" height="10"
                          onPositionChange="jscript: player.settings.volume = value;"/>
            <SLIDER id="seek" left="0" top="20" width="50" height="10"
                    onPositionChange="updateSeekToolTip();"/>
        </VIEW></THEME>
        """)
        // `change` is the raise, and it carries the element, so the bare `value` these handlers
        // read is bound. Both spellings reach it through the one alias set.
        XCTAssertEqual(WMPMainWindowController.handlers(in: skin, event: "change", targetID: "volume",
                                                        viewID: "main")
                           .map { $0.trimmingCharacters(in: .whitespaces) },
                       ["player.settings.volume = value;"])
        XCTAssertEqual(WMPMainWindowController.handlers(in: skin, event: "change", targetID: "seek",
                                                        viewID: "main"),
                       ["updateSeekToolTip();"])
        XCTAssertTrue(WMPCorpusReportHarness.supportedEvents.contains("onpositionchange"),
                      "onPositionChange has a dispatch site and must not rank as demand")
    }

    /// **It is a user gesture and not the clock, which is W119 staying shut.** The position tick
    /// raises `hostsettle` and `currentposition_onchange`; neither accepts this spelling, so the
    /// 151 handlers cannot be run ten times a second with `value` unbound. The guard is worth a
    /// test because the tick was spelled `positionchange` once, and classifying the name is
    /// exactly the change that would have made that spelling live.
    func testAClockTickDoesNotRaiseASlidersPositionChange() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
            <SLIDER id="seek" left="0" top="0" width="50" height="10"
                    onPositionChange="updateSeekToolTip();"/>
        </VIEW></THEME>
        """)
        for tick in ["hostsettle", "currentposition_onchange"] {
            XCTAssertTrue(WMPMainWindowController.handlers(in: skin, event: tick, targetID: nil,
                                                           viewID: "main").isEmpty,
                          "\(tick) is the clock and must not reach an authored onPositionChange")
        }
    }

    // MARK: - The keyboard (W53)

    /// **WMP hands a key handler a Windows virtual key code, and that is the whole contract.** It is
    /// the opposite shape to the `.wal` one: `WinampModernKeyAccelerator` produces the string
    /// `"alt+g"` because every Wasabi handler compares a string, and every WMP handler compares an
    /// integer. Measured over 184 archives, `event.keyCode` is 405 of the 409 `event.` reads in a
    /// key handler or a function one calls, and the literals are VK values.
    func testAKeystrokeIsAnsweredWithItsWindowsVirtualKeyCode() {
        // The arrows, which 796 of the corpus's `onkeydown` comparisons are.
        XCTAssertEqual(WMPVirtualKeyCode.keyDown(keyCode: 123, charactersIgnoringModifiers: nil), 37)
        XCTAssertEqual(WMPVirtualKeyCode.keyDown(keyCode: 126, charactersIgnoringModifiers: nil), 38)
        XCTAssertEqual(WMPVirtualKeyCode.keyDown(keyCode: 124, charactersIgnoringModifiers: nil), 39)
        XCTAssertEqual(WMPVirtualKeyCode.keyDown(keyCode: 125, charactersIgnoringModifiers: nil), 40)
        // Return, which is every one of `onkeyup`'s 100 comparisons.
        XCTAssertEqual(WMPVirtualKeyCode.keyDown(keyCode: 36, charactersIgnoringModifiers: "\r"), 13)
        XCTAssertEqual(WMPVirtualKeyCode.keyDown(keyCode: 49, charactersIgnoringModifiers: " "), 32)
        // A letter: VK_A…VK_Z are the ASCII values of the *uppercase* forms, so `ALXMorph`'s
        // `case 86: player.controls.stop()` is reached by pressing the unshifted `v`. Verified end
        // to end in the running app on `Age_of_Mythology_MP7`.
        XCTAssertEqual(WMPVirtualKeyCode.keyDown(keyCode: 9, charactersIgnoringModifiers: "v"), 86)
        XCTAssertEqual(WMPVirtualKeyCode.keyDown(keyCode: 9, charactersIgnoringModifiers: "V"), 86)
    }

    /// **`event.keyCode` is writable, for the one dispatch** (W266). The Xbox skins' `resetCode()`
    /// runs `event.keycode = 65` every timer tick and threw on every tick while the member was
    /// read-only. The write is read back within the transaction and never reaches the next one.
    func testEventKeyCodeWriteLastsForItsOwnTransactionOnly() {
        let model = WMPObjectModel()
        model.beginTransaction(snapshot: WMPHostSnapshot(), preferences: [:], viewID: "mainBox")
        guard case .value = model.set("event", "keycode", .number(65)) else {
            return XCTFail("the write is accepted")
        }
        guard case .value(let written) = model.get("event", "keyCode") else { return XCTFail() }
        XCTAssertEqual(written, .number(65))
        model.beginTransaction(snapshot: WMPHostSnapshot(), preferences: [:], viewID: "mainBox")
        guard case .value(let next) = model.get("event", "keyCode") else { return XCTFail() }
        XCTAssertEqual(next, .null, "a written key does not leak into the next event")
    }

    /// **An authored key handler owns an arrow only where it compares that arrow.** `Halloween`'s
    /// player view is `onKeyPress="viewHotKeys();"`, which switches over letters; its resize button
    /// is `onkeydown="viewResizer(event);"`, which switches over `37`…`40`. Before the scan the
    /// first claimed every arrow and the `<EFFECTS>` surface never saw one — and the scan's own
    /// first revision shipped an unbalanced pattern whose fallback answered "yes" for every skin,
    /// so the Halloween pair is the case that has to keep both answers.
    func testAKeyHandlerOwnsAnArrowOnlyWhereItComparesIt() {
        let script = """
        function viewHotKeys()
        {
            switch(event.keycode)
            {
                case 122:
                case 90:
                    player.controls.previous();
                    break;
                case 108:
                case 76:
                    openFile();
                    break;
            }
        }
        function openFile()
        {
            var media = theme.openDialog('FILE_OPEN','FILES_ALLMEDIA');
            if(media) { player.URL = media; player.controls.play(); }
        }
        function viewResizer(event)
        {
            switch(event.keycode)
            {
                case 37: view.width-=20; break;
                case 38: view.height-=20; break;
                case 39: view.width+=20; break;
                case 40: view.height+=20; break;
            }
        }
        """
        for arrow in 37...40 {
            XCTAssertFalse(WMPKeyHandlerScan.handlers(["viewHotKeys();"], compare: arrow, in: [script]),
                           "a letter hotkey handler must not claim VK \(arrow)")
            XCTAssertTrue(WMPKeyHandlerScan.handlers(["viewResizer(event);"], compare: arrow, in: [script]),
                          "a resize handler keeps VK \(arrow)")
        }
        // Inline comparisons, either way round; a longer number is not the key.
        XCTAssertTrue(WMPKeyHandlerScan.handlers(["if (event.keyCode == 38) vol.value += 5;"],
                                                 compare: 38, in: []))
        XCTAssertTrue(WMPKeyHandlerScan.handlers(["if (40 == event.keyCode) vol.value -= 5;"],
                                                 compare: 40, in: []))
        XCTAssertFalse(WMPKeyHandlerScan.handlers(["if (event.keyCode == 380) vol.value = 0;"],
                                                  compare: 38, in: []))
        // A function the scan cannot find keeps the key rather than losing it.
        XCTAssertTrue(WMPKeyHandlerScan.handlers(["notDefinedAnywhere();"], compare: 39, in: [script]))
        // A call in a comment is not a call (`Age_of_Mythology_MPXP`'s `//\tvideoZoom();`), and a
        // comparison in one is not a comparison; a `//` inside a string is not a comment.
        let commented = """
        function hotKeys() { switch(event.keycode) { case 90: break; case 70: //\tvideoZoom();
        /* case 38: */ break; } }
        function urlKeys() { var u = "http://x"; if (event.keyCode == 38) u = ''; }
        """
        XCTAssertFalse(WMPKeyHandlerScan.handlers(["hotKeys();"], compare: 38, in: [commented]))
        XCTAssertTrue(WMPKeyHandlerScan.handlers(["urlKeys();"], compare: 38, in: [commented]))
    }

    /// **`charactersIgnoringModifiers` is the key as engraved**, which is what a VK names: Option-G
    /// is `g` there rather than the `©` that `characters` reports. And a key with no honest VK
    /// answers nil rather than `0` — `0` is VK_NULL, a number `switch(event.keyCode)` can match,
    /// which is W260's absent-is-not-a-zero trap in a second place. Punctuation is the OEM range,
    /// whose meaning depended on the Windows keyboard layout, and no corpus handler compares one.
    func testAKeyWithNoHonestVirtualCodeIsAbsentRatherThanZero() {
        XCTAssertEqual(WMPVirtualKeyCode.keyDown(keyCode: 5, charactersIgnoringModifiers: "g"), 71,
                       "Option-G is the letter G, not the character it composes")
        XCTAssertNil(WMPVirtualKeyCode.keyDown(keyCode: 41, charactersIgnoringModifiers: ";"))
        XCTAssertNil(WMPVirtualKeyCode.keyDown(keyCode: 200, charactersIgnoringModifiers: nil))
    }

    /// **Recognising an event is not dispatching it, and the inverse is just as silent.** `onkeyup`
    /// had a dispatch site before it had a name — `WMPMainView` already raised it for an
    /// `<EDITBOX>`'s text — and with the name missing from `handlerNames` every one of those
    /// handlers was classified `.literal`, invisible to the dispatcher and to the tally alike.
    func testTheThreeKeyEventsAreClassifiedAndCountedAsImplemented() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60" onKeyPress="viewHotKeys();">
            <SLIDER id="vol" left="0" top="0" width="50" height="10" onKeyDown="volUpDown(event);"/>
            <EDITBOX id="find" left="0" top="20" width="50" height="10" onKeyUp="search();"/>
        </VIEW></THEME>
        """)
        for (event, target) in [("keypress", "view"), ("keydown", "vol"), ("keyup", "find")] {
            XCTAssertFalse(WMPMainWindowController.handlers(in: skin, event: event,
                                                            targetID: target, viewID: "main").isEmpty,
                           "\(event) must reach the element that authored it")
        }
        for event in ["onkeydown", "onkeypress", "onkeyup"] {
            XCTAssertTrue(WMPCorpusReportHarness.supportedEvents.contains(event),
                          "\(event) has a dispatch site and must not rank as demand")
        }
    }

    /// **The key the handler reads is the key that was pressed**, bound the way the bare `value` and
    /// the named `<PLAYER>` arguments are: for the duration of the transaction, then cleared.
    /// `Age_of_Mythology_MP7`'s `viewHotKeys` switches over it and calls no argument of its own —
    /// `event` is a global in WMP, not a handler parameter.
    func testAKeyHandlerReadsTheKeyCodeOffTheEventObject() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60"
                     onKeyPress="if (event.keyCode == 86) player.controls.stop();"/></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        func stopped(_ keyCode: Int?) async -> Bool {
            let output = await runtime.transact(
                skin: skin, viewID: "main", size: WMPSize(width: 100, height: 60),
                snapshot: WMPHostSnapshot(),
                event: WMPJScriptEvent(name: "keypress", targetID: "view",
                                       handlers: ["if (event.keyCode == 86) player.controls.stop();"],
                                       keyCode: keyCode))
            return output.hostCommands.contains { $0.action == "stop" }
        }
        let onItsKey = await stopped(86), onAnother = await stopped(88), withNoKey = await stopped(nil)
        XCTAssertTrue(onItsKey, "VK_V is the key this skin stops on")
        XCTAssertFalse(onAnother, "a different key must not reach the same case")
        // **Outside a keystroke there is no key.** `null` matches no numeric case and compares false
        // against every literal in the corpus, and the member still *resolves*, so a handler reading
        // it from a timer or a host event runs on rather than dying with a `ReferenceError`.
        XCTAssertFalse(withNoKey)
    }

    /// **The element that raised the event, and the reason a whole skin depends on it (W121).**
    ///
    /// `Cablemusic` gives all eighteen of its station buttons the same
    /// `onMouseDown="StartProgram();"` and the function asks which one it was —
    /// `var i = Number(String(event.srcElement.id).substring(2));`. Eighteen presets share
    /// `AssignPreset()` the same way, so an unrecognised member here took both surfaces with it:
    /// the handler dies on its first statement and nothing on the skin's face does anything.
    /// It answers the element *object*, which is what WMP hands back; `.id` is only the member
    /// the corpus happens to read first.
    ///
    /// **The assertion is which button, not whether one.** Both buttons author the same source,
    /// exactly as the skin does, so a `srcElement` answering any element at all — or the first in
    /// the view — would still pass a whether-it-fired check and fail this one.
    ///
    /// **A fresh runtime per case, and that is not incidental.** Two transactions raised against
    /// one runtime do not re-run the handler for a second target, so a reused runtime answers the
    /// *first* target's result to both and every negative case passes for the wrong reason. This
    /// was a live false pass while the implementation was correct.
    func testAHandlerReadsTheElementThatRaisedItOffTheEventObject() async throws {
        let source = "if (String(event.srcElement.id) == 'b7') player.controls.play();"
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
            <BUTTON id="b7" left="0" top="0" width="10" height="10" onMouseDown="\(source)"/>
            <BUTTON id="b8" left="20" top="0" width="10" height="10" onMouseDown="\(source)"/>
        </VIEW></THEME>
        """)
        func played(targetID: String) async throws -> Bool {
            let (runtime, cleanup) = try runtime()
            defer { cleanup() }
            let output = await runtime.transact(
                skin: skin, viewID: "main", size: WMPSize(width: 100, height: 60),
                snapshot: WMPHostSnapshot(),
                event: WMPJScriptEvent(name: "mousedown", targetID: targetID, handlers: [source]))
            return output.hostCommands.contains { $0.action == "play" }
        }
        let fromB7 = try await played(targetID: "b7")
        let fromB8 = try await played(targetID: "b8")
        XCTAssertTrue(fromB7, "the handler must see the button that raised it")
        XCTAssertFalse(fromB8, "a different button sharing the same source must not match b7")
    }

    /// **`event.button` is IE's numbering, which WMP inherits: 1 left, 2 right, 4 middle (W121).**
    ///
    /// `digitaldj`'s list boxes, spinners and comparison toggles are built out of
    /// `if (event.button == 1)` and `if (event.button != 1) return;` — 15 uses in its markup alone.
    /// Only the left button reaches a script event at all, because `WMPMainView` overrides
    /// `mouseDown` and not `rightMouseDown`, so the answer is a measurement rather than a guess.
    func testAMouseHandlerReadsTheButtonAndATransactionWithNoMouseReadsNone() async throws {
        let source = "if (event.button == 1) player.controls.next();"
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="60">
            <TEXT id="spin" left="0" top="0" width="40" height="10" onMouseDown="\(source)"/>
        </VIEW></THEME>
        """)
        func advanced(button: Int?) async throws -> Bool {
            let (runtime, cleanup) = try runtime()
            defer { cleanup() }
            let output = await runtime.transact(
                skin: skin, viewID: "main", size: WMPSize(width: 100, height: 60),
                snapshot: WMPHostSnapshot(),
                event: WMPJScriptEvent(name: "mousedown", targetID: "spin",
                                       handlers: [source], button: button))
            return output.hostCommands.contains { $0.action == "next" }
        }
        let onTheLeftButton = try await advanced(button: 1)
        let withNoMouse = try await advanced(button: nil)
        XCTAssertTrue(onTheLeftButton)
        // A view timer and a host state change carry no button at all. `null` fails `== 1` and
        // passes `!= 1`, which is what the corpus's early-return idiom wants: a transaction with
        // no mouse behind it is not a click of the wrong button.
        XCTAssertFalse(withNoMouse)
    }

    /// **WMP's `event` object is ambient rather than per-dispatch, and `clientX`/`clientY` is where
    /// that matters (W121).** `LostPlanet`'s `menuTicker()` is an `onTimer` that opens and closes
    /// its own drop-down by testing the pointer against the menu's rectangle on every tick, so
    /// confining the pointer to mouse transactions leaves that handler dead in a different way.
    /// The coordinates are the view's own top-left client space, the space the scene is built in —
    /// `WMPMainView.skinPoint(fromWindowPoint:sceneSize:)` is where a live one comes from.
    func testATimerHandlerReadsThePointerOffTheEventObject() async throws {
        let source = "if (event.clientX > 10 && event.clientY < 75) player.controls.play();"
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="120" onTimer="\(source)"
                     timerInterval="500"/></THEME>
        """)
        func opened(pointer: WMPPoint?) async throws -> Bool {
            let (runtime, cleanup) = try runtime()
            defer { cleanup() }
            let output = await runtime.transact(
                skin: skin, viewID: "main", size: WMPSize(width: 200, height: 120),
                snapshot: WMPHostSnapshot(),
                event: WMPJScriptEvent(name: "timer", targetID: nil,
                                       handlers: [source], pointer: pointer))
            return output.hostCommands.contains { $0.action == "play" }
        }
        let insideTheHotspot = try await opened(pointer: WMPPoint(x: 40, y: 20))
        let belowIt = try await opened(pointer: WMPPoint(x: 40, y: 90))
        let withNoPointer = try await opened(pointer: nil)
        XCTAssertTrue(insideTheHotspot, "a timer handler must see where the pointer is")
        XCTAssertFalse(belowIt, "outside the rectangle the handler must not fire")
        XCTAssertFalse(withNoPointer, "no window to ask means no pointer, not the origin")
    }

    private func fixtureScript(_ name: String) throws -> String {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/WMPSkin")
        return try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
    // MARK: - W144: what an authored expression may overwrite, and when a view saves

    /// **An authored `JScript:` geometry expression re-applies only when its own value changes.**
    ///
    /// It is re-evaluated every transaction — that is what makes `top="jscript:view.height-123"`
    /// follow a resize — and committing it unconditionally put it *ahead of the mutations*, so any
    /// transaction whose handlers did not touch the node snapped the node back to its authored
    /// place. A view with an `onTimer` therefore undid its own script within one tick.
    /// `xsn_sports` slides its drawers with `visDrawer.moveTo(0, view.height-73, 400)` against
    /// `timerInterval="500"`, and half a second after every click the drawer was back at
    /// `view.height-123` — reported as "it still does not open".
    func testATimerTickDoesNotUndoAScriptedMoveWithTheAuthoredExpression() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200" scriptFile="s.js"
                   onTimer="tick();" timerInterval="500">
            <SUBVIEW id="drawer" left="0" top="jscript:view.height-123" width="140" height="130"/>
            <BUTTON id="go" left="0" top="0" width="10" height="10"
                    onClick="drawer.moveTo(0, view.height-73, 400);"/>
        </VIEW></THEME>
        """, js: "function tick(){}")
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let drawer = try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "drawer" }?.stableID)
        let top = WMPScenePropertyAddress(stableID: drawer, property: "top")
        let size = WMPSize(width: 200, height: 200)

        let opened = await runtime.transact(
            skin: skin, viewID: "main", size: size, snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go",
                                   handlers: ["drawer.moveTo(0, view.height-73, 400);"]))
        XCTAssertEqual(opened.overrides.geometry[top], 127, "200 - 73")

        let ticked = await runtime.transact(
            skin: skin, viewID: "main", size: size, snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "timer", targetID: nil, handlers: ["tick();"]))
        XCTAssertEqual(ticked.overrides.geometry[top], 127,
                       "the timer touched nothing, so `view.height-123` must not put it back to 77")
    }

    /// **A resize does not hand the axis back either — the script owns it from the assignment on
    /// (W159).**
    ///
    /// This case used to assert the opposite, on the reading that "when its value changes" had to
    /// mean a resize wins, because otherwise nothing would carry a script-placed element to the new
    /// size. What carries it is **alignment**, which is the half this rule hands off to and is
    /// covered in `WMPAlignmentTests`: a script assignment is a plain number written against the
    /// canvas of the moment, so a `bottom`/`right`/`stretch` node re-anchors by the growth since
    /// then and a node with no alignment stays put — exactly as an authored literal behaves.
    ///
    /// The old reading cost `NVIDIA` its playlist layout. `setModesMinWidth('playlist')` assigns
    /// `mainModeMetadata.width = view.width-266` and then resizes the view in the same handler, so
    /// `width="jscript:view.width-101"` answered something new on the very next transaction and
    /// took the property back: the bar resolved 119 px past the window's right edge and the time
    /// readout hanging off `jscript:mainModeMetadata.width-80` drew off-window. Reported as "the
    /// timer in the playlist draws at the wrong location".
    func testAResizeDoesNotHandTheAxisBackToTheExpression() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="drawer" left="0" top="jscript:view.height-123" width="140" height="130"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let drawer = try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "drawer" }?.stableID)
        let top = WMPScenePropertyAddress(stableID: drawer, property: "top")

        _ = await runtime.transact(skin: skin, viewID: "main",
                                   size: WMPSize(width: 200, height: 200),
                                   snapshot: WMPHostSnapshot(), event: nil)
        let moved = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: nil, handlers: ["drawer.top = 5;"]))
        XCTAssertEqual(moved.overrides.geometry[top], 5)

        let resized = await runtime.transact(skin: skin, viewID: "main",
                                             size: WMPSize(width: 200, height: 300),
                                             snapshot: WMPHostSnapshot(), event: nil)
        XCTAssertEqual(resized.overrides.geometry[top], 5,
                       "the script wrote this axis, so `view.height-123` never gets it back; this "
                       + "node authors no alignment, so it stays where a literal 5 would stay")
        XCTAssertEqual(resized.overrides.scriptAssignedGeometry[top], WMPSize(width: 200, height: 200),
                       "and it is anchored at the canvas it was assigned against, which is what "
                       + "lets an aligned node re-anchor by the growth since then")
    }

    /// A nested node's script-assigned size is anchored at its **parent's** extent at the write —
    /// the nearest ancestor with a resolved frame — and not anchored at all once the view has
    /// resized earlier in the same transaction, because the parent's frame is then stale.
    func testANestedAssignmentRecordsItsParentsExtent() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="outer" width="200" height="180">
                <SUBVIEW id="pane" width="200" height="100"/>
            </SUBVIEW>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let id = { (xmlID: String) in
            try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == xmlID }?.stableID)
        }
        let view = try XCTUnwrap(skin.views.first { $0.id == "main" }?.node.stableID)
        let outer = try id("outer"), pane = try id("pane")
        let height = WMPScenePropertyAddress(stableID: pane, property: "height")
        let geometry = [view: WMPRect(x: 0, y: 0, width: 200, height: 200),
                        outer: WMPRect(x: 0, y: 0, width: 200, height: 180),
                        pane: WMPRect(x: 0, y: 0, width: 200, height: 100)]

        _ = await runtime.transact(skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
                                   snapshot: WMPHostSnapshot(), event: nil, geometry: geometry)
        let written = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: nil, handlers: ["pane.height = 150;"]),
            geometry: geometry)
        XCTAssertEqual(written.overrides.scriptAssignedParentExtent[height], 180)

        let afterResize = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: nil,
                                   handlers: ["view.height = 300; pane.height = 120;"]),
            geometry: geometry)
        XCTAssertNil(afterResize.overrides.scriptAssignedParentExtent[height],
                     "`outer`'s 180 was measured before the view grew, so it anchors nothing")
    }

    /// **`onClose` is where a `.wmz` saves its state, and it had no dispatch site at all.**
    ///
    /// 373 handlers across 133 of the 180 archives were dead. `xsn_sports` closes with
    /// `saveVisPrefs()`, which writes `visDrawerStatus` through `theme.savePreference`; with
    /// nothing ever saved, `theme.loadPreference` answered the `--` absent sentinel on every launch
    /// and the settings drawer opened itself every time. This is the transaction shape the two
    /// controller sites and `flushCloseHandlersOnTermination` post: the handlers run, and the
    /// preference writes they post are committed before the view's scope is discarded.
    func testACloseTransactionCommitsThePreferencesItsHandlerWrites() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200" scriptFile="s.js" onClose="saveState();">
            <SUBVIEW id="drawer" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """, js: "var open=false; function saveState(){ theme.savePreference('drawer', open); }")
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        XCTAssertEqual(WMPMainWindowController.handlers(in: skin, event: "close", targetID: nil,
                                                        viewID: "main"),
                       ["saveState();"],
                       "the dispatch site looks up `close`, and the markup spells it `onClose`")

        let closed = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "close", targetID: nil, handlers: ["saveState();"]))
        XCTAssertTrue(closed.diagnostics.isEmpty,
                      "\(closed.diagnostics.map(\.message))")

        // Read it back the way the next launch does. A boolean round-trips as "true"/"false", which
        // is what `loadVisPrefs` compares against — and never as the `--` absent sentinel again.
        let reopened = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "load", targetID: nil,
                                   handlers: ["drawer.width = (theme.loadPreference('drawer') == '--') ? 1 : 2;"]))
        let width = WMPScenePropertyAddress(
            stableID: try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "drawer" }?.stableID),
            property: "width")
        XCTAssertEqual(reopened.overrides.geometry[width], 2,
                       "the saved value is there, so the skin takes its restore branch")
    }

    // MARK: A colour written as an expression

    /// `Asimov_Radio`'s texts author `foregroundColor="jscript:NormalTextColor"` against a global in
    /// `MBay.js`. Only geometry expressions were evaluated, so the colour was never read and every
    /// readout drew in the default instead of the skin's green.
    func testAJScriptColourIsAssignedOnLoad() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200" scriptFile="s.js" onLoad="Init();">
            <TEXT id="status" left="0" top="0" value="Ready" foregroundColor="jscript:NormalTextColor"/>
        </VIEW></THEME>
        """, js: """
        var NormalTextColor = "#00FF00";
        function Init() {}
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await runtime.transact(skin: skin, viewID: "main",
                                            size: WMPSize(width: 200, height: 200),
                                            snapshot: WMPHostSnapshot(),
                                            event: WMPJScriptEvent(name: "load", targetID: "main",
                                                                   handlers: ["Init();"]))
        XCTAssertFalse(output.diagnostics.contains { $0.code == "handler-error" },
                       "\(output.diagnostics)")
        let status = try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "status" }?.stableID)
        XCTAssertEqual(output.overrides.properties[.init(stableID: status,
                                                         property: "foregroundcolor")]?.string,
                       "#00FF00")
    }

    // MARK: A skin's own function, called in the wrong case (W42)

    /// **The call site is in the program, and the declaration is further down the same file.**
    /// `elvis.js`'s `Init()` calls `UpdateMetaData()` against `function UpdateMetadata`, so the
    /// `onLoad` threw `ReferenceError` on line 17 and lost the whole of `Init` below it — the
    /// column modes, the volume slider's position and the video/visualization pane. The alias pass
    /// therefore runs *after* the whole program set has evaluated, never before: the name a call
    /// needs is usually declared below the call.
    func testAProgramCallingItsOwnFunctionInTheWrongCaseStillResolves() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200" scriptFile="s.js" onLoad="Init();">
            <SUBVIEW id="panel" left="0" top="0" width="100" height="100"/>
        </VIEW></THEME>
        """, js: """
        function Init() { UpdateMetaData(); panel.width = 42; }
        function UpdateMetadata() { panel.height = 40; }
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        func stableID(_ id: String) throws -> Int {
            try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == id }?.stableID)
        }
        let output = await runtime.transact(skin: skin, viewID: "main",
                                            size: WMPSize(width: 200, height: 200),
                                            snapshot: WMPHostSnapshot(),
                                            event: WMPJScriptEvent(name: "load", targetID: "main",
                                                                   handlers: ["Init();"]))
        XCTAssertFalse(output.diagnostics.contains { $0.code == "handler-error" },
                       "the misspelled call must resolve, not throw: \(output.diagnostics)")
        XCTAssertEqual(output.overrides.geometry[.init(stableID: try stableID("panel"),
                                                       property: "height")], 40)
        XCTAssertEqual(output.overrides.geometry[.init(stableID: try stableID("panel"),
                                                       property: "width")], 42,
                       "the statement *after* the misspelled call is the whole cost of the defect")
    }

    /// The other half of the corpus's shape: the call site is in the markup rather than the
    /// program. `TDK.wms` binds `onLoad="onLoadVideo();"` against `function OnLoadVideo`, and six
    /// archives bind `onClose="onCloseVideo();"` against `function OnCloseVideo`.
    func testAMarkupHandlerCallingAFunctionInTheWrongCaseStillResolves() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200" scriptFile="s.js">
            <SUBVIEW id="panel" left="0" top="0" width="100" height="100"/>
            <BUTTON id="go" left="0" top="0" width="10" height="10" onClick="onCloseVideo();"/>
        </VIEW></THEME>
        """, js: "function OnCloseVideo() { panel.height = 40; }")
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await runtime.transact(skin: skin, viewID: "main",
                                            size: WMPSize(width: 200, height: 200),
                                            snapshot: WMPHostSnapshot(),
                                            event: WMPJScriptEvent(name: "click", targetID: "go",
                                                                   handlers: ["onCloseVideo();"]))
        XCTAssertFalse(output.diagnostics.contains { $0.code == "handler-error" },
                       "the misspelled call must resolve, not throw: \(output.diagnostics)")
        let panel = try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "panel" }?.stableID)
        XCTAssertEqual(output.overrides.geometry[.init(stableID: panel, property: "height")], 40)
    }

    /// **The alias is last resort and never a fold.** `Kids` declares both `StartVideo` and
    /// `startVideo` with different bodies, and `Cablemusic` and `HOB` do the same with their own
    /// pairs. A spelling that resolves exactly must keep resolving to itself; an ambiguous fold
    /// must be declined even when the wanted spelling resolves to nothing.
    func testTwoGlobalsDifferingOnlyByCaseAreNeverFoldedIntoEachOther() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200" scriptFile="s.js">
            <SUBVIEW id="panel" left="0" top="0" width="100" height="100"/>
            <BUTTON id="lower" left="0" top="0" width="10" height="10" onClick="startVideo();"/>
            <BUTTON id="upper" left="0" top="20" width="10" height="10" onClick="StartVideo();"/>
            <BUTTON id="third" left="0" top="40" width="10" height="10" onClick="STARTVIDEO();"/>
        </VIEW></THEME>
        """, js: """
        function StartVideo() { panel.height = 11; }
        function startVideo() { panel.height = 22; }
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let panel = try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "panel" }?.stableID)
        let address = WMPScenePropertyAddress(stableID: panel, property: "height")
        for (target, source, expected) in [("lower", "startVideo();", 22.0),
                                           ("upper", "StartVideo();", 11.0)] {
            let output = await runtime.transact(
                skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
                snapshot: WMPHostSnapshot(),
                event: WMPJScriptEvent(name: "click", targetID: target, handlers: [source]))
            XCTAssertEqual(output.overrides.geometry[address], expected,
                           "\(source) must reach its own declaration, not the other spelling")
        }
        let ambiguous = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "third", handlers: ["STARTVIDEO();"]))
        XCTAssertTrue(ambiguous.diagnostics.contains { $0.code == "handler-error" },
                      "a third spelling case-folds to two declarations and must be declined")
    }

    /// A name the archive does not contain in any spelling must keep throwing. `Plus! Plasma Ball`
    /// calls `UpdateMetaData()` and declares nothing like it, and inventing a no-op for that is the
    /// `inert()` phantom this subsystem exists to avoid.
    func testAFunctionDeclaredInNoSpellingStillThrows() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200" scriptFile="s.js">
            <BUTTON id="go" left="0" top="0" width="10" height="10" onClick="UpdateMetaData();"/>
        </VIEW></THEME>
        """, js: "function somethingElse() { return 1; }")
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go", handlers: ["UpdateMetaData();"]))
        XCTAssertTrue(output.diagnostics.contains { $0.code == "handler-error" },
                      "nothing case-folds to it, so it must still throw")
    }

    /// **The fold only ever reaches a function.** A global that is not one — the skin's own state,
    /// or an element, which is an object — must be left exactly where it was even when a call site
    /// folds onto its name. The assertion is on the *second* handler: the first throws either way,
    /// so the only way to see the guard is to ask afterwards whether the name was invented.
    func testACallSiteNeverAliasesOntoAGlobalThatIsNotAFunction() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200" scriptFile="s.js">
            <SUBVIEW id="panel" left="0" top="0" width="100" height="100"/>
            <BUTTON id="call" left="0" top="0" width="10" height="10" onClick="Flag();"/>
            <BUTTON id="ask" left="0" top="20" width="10" height="10"
                    onClick="panel.height = (typeof Flag == 'undefined') ? 40 : 11;"/>
        </VIEW></THEME>
        """, js: "var flag = 7;")
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let called = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "call", handlers: ["Flag();"]))
        XCTAssertTrue(called.diagnostics.contains { $0.code == "handler-error" },
                      "`flag` is a number, so `Flag()` must still throw")
        let source = "panel.height = (typeof Flag == 'undefined') ? 40 : 11;"
        let asked = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "ask", handlers: [source]))
        let panel = try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "panel" }?.stableID)
        XCTAssertEqual(asked.overrides.geometry[.init(stableID: panel, property: "height")], 40,
                       "the failed call must not have left `Flag` behind as a global")
    }

    /// **Two views that each name their own `scriptFile` do not share the functions in them
    /// (W204/W257).**
    ///
    /// `Plus! SlimLine` is the reported case: `perfect.js` and `perfectV.js` both define `Init`,
    /// `savePrefs`, `switchSkin` and `EndVideo`, the program evaluated last won every call in both
    /// views, and so the horizontal view ran the *vertical* view's `Init()` — whose `EndVideo()`
    /// calls `switchSkin('perfectVSkin')` and put the skin straight back. Reported live 2026-09-22
    /// as "when I click the recycle it switches and instantly switches back".
    func testAViewRunsTheFunctionsItsOwnScriptFileDefines() async throws {
        let wms = """
        <THEME>
            <VIEW id="a" width="200" height="200" scriptFile="a.js">
                <SUBVIEW id="panelA" left="0" top="0" width="100" height="100"/>
                <BUTTON id="goA" left="0" top="0" width="10" height="10" onClick="panelA.height = mark();"/>
            </VIEW>
            <VIEW id="b" width="200" height="200" scriptFile="b.js">
                <SUBVIEW id="panelB" left="0" top="0" width="100" height="100"/>
                <BUTTON id="goB" left="0" top="0" width="10" height="10" onClick="panelB.height = mark();"/>
                <BUTTON id="sharedB" left="0" top="20" width="10" height="10"
                        onClick="panelB.height = onlyInA();"/>
            </VIEW>
        </THEME>
        """
        let skin = try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8)),
            WMPTestArchiveEntry("a.js", data: Data("""
            function mark() { return 41; }
            function onlyInA() { return 77; }
            """.utf8)),
            WMPTestArchiveEntry("b.js", data: Data("function mark() { return 42; }".utf8)),
        ]))
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        func stableID(_ id: String) throws -> Int {
            try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == id }?.stableID)
        }
        func height(_ viewID: String, _ targetID: String, _ source: String) async -> CGFloat? {
            let output = await runtime.transact(
                skin: skin, viewID: viewID, size: WMPSize(width: 200, height: 200),
                snapshot: WMPHostSnapshot(),
                event: WMPJScriptEvent(name: "click", targetID: targetID, handlers: [source]))
            let panel = try? stableID(viewID == "a" ? "panelA" : "panelB")
            return panel.flatMap { output.overrides.geometry[.init(stableID: $0, property: "height")] }
        }
        // `b.js` is evaluated last, so before the view scope existed both of these answered 42.
        let inB = await height("b", "goB", "panelB.height = mark();")
        XCTAssertEqual(inB, 42)
        let inA = await height("a", "goA", "panelA.height = mark();")
        XCTAssertEqual(inA, 41, "view `a` must run `a.js`'s `mark`, not the last program's")
        let backInB = await height("b", "goB", "panelB.height = mark();")
        XCTAssertEqual(backInB, 42, "and switching back must put `b.js`'s own function back")
        // A name only one program defines is not contested, so it stays shared — which is what a
        // skin whose views deliberately share a helper is relying on.
        let shared = await height("b", "sharedB", "panelB.height = onlyInA();")
        XCTAssertEqual(shared, 77, "a helper exactly one program defines must reach every view")
    }

}
