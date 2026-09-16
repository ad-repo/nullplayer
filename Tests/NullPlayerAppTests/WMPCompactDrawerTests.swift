import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// **The drawer report (W184–W190): everything `Compact.wmz` needed to open a drawer.**
///
/// Reported as *"drawer controls don't work in compact wmp skin"* and it was seven unrelated
/// engine defects, of which **three were invisible to every headless probe** — the render dump
/// rebuilds a scene straight from the script's overrides, so a canvas that only the *window* gets
/// wrong looks perfect in a capture. Each test below is one of them, written against the smallest
/// markup that reproduces it rather than against the archive; the archive is what found them and
/// `skills/wmp-skin-guide/reference/skins/compact.md` is where it is written down.
final class WMPCompactDrawerTests: XCTestCase {
    private func runtime(_ name: String = #function) throws -> (WMPScriptRuntime, () -> Void) {
        let suite = "WMPCompactDrawerTests.\(name).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data(name.utf8),
                                                                 defaults: defaults)),
                { defaults.removePersistentDomain(forName: suite) })
    }

    private func load(_ wms: String) async throws -> WMPLoadedSkin {
        try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(
            [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]))
    }

    private func stableID(_ skin: WMPLoadedSkin, _ id: String) throws -> Int {
        try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == id }?.stableID)
    }

    // MARK: W184 — the `event` object

    /// **`event` is a global object, and a skin reads it from a plain function call.** Both of
    /// `Compact`'s drawer handlers open with `view.maxWidth = event.screenWidth` *before* they grow
    /// the view, so with the global undefined the `ReferenceError` took the growth and the slide
    /// with it and the click read as inert.
    func testScreenSizeAnswersTheEventObject() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="200" height="100">
            <BUTTON id="go" left="0" top="0" width="10" height="10"
                    onClick="view.width = event.screenWidth - 20;"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        await runtime.setScreen(WMPSize(width: 1280, height: 800))
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 100),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go",
                                   handlers: ["view.width = event.screenWidth - 20;"]))
        XCTAssertEqual(output.diagnostics.filter { $0.code == "handler-error" }.count, 0,
                       "an undefined `event` aborts the handler at its first statement")
        XCTAssertEqual(output.viewSize?.width, 1260)
    }

    /// A modifier flag is the live half of `event` this engine can answer honestly: `Compact`'s ten
    /// equaliser sliders are each `value_onchange="if (!event.shiftKey) eq.gainLevel<n> = value;"`,
    /// so every one of them aborted and the sliders inside its settings drawer moved and did
    /// nothing. `keyCode` stays unrecognised on purpose — see `WMPObjectModel.readEvent`.
    func testModifierFlagsComeFromTheDispatchingEvent() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="200" height="100">
            <BUTTON id="go" left="0" top="0" width="10" height="10"
                    onClick="view.width = event.shiftKey ? 150 : 180;"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let source = "view.width = event.shiftKey ? 150 : 180;"
        let plain = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 100),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go", handlers: [source]))
        XCTAssertEqual(plain.viewSize?.width, 180)
        let shifted = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 100),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go", handlers: [source],
                                   modifiers: .shift))
        XCTAssertEqual(shifted.viewSize?.width, 150)
    }

    // MARK: W186, W188 — the size a script assigns the window

    /// **One axis is a resize.** `Compact` grows only the width for its playlist drawer and only
    /// the height for its settings drawer; demanding both left `viewSize` nil, so the app never
    /// moved the window and the drawer opened inside the old frame. No capture could see it: the
    /// scene builder takes the canvas from the overrides either way.
    func testAWidthOnlyAssignmentIsAResize() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="200" height="100">
            <BUTTON id="go" left="0" top="0" width="10" height="10" onClick="view.width += 50;"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 100),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go", handlers: ["view.width += 50;"]))
        XCTAssertEqual(output.viewSize, WMPSize(width: 250, height: 100),
                       "the height the script never touched is the window's own, not nil")
    }

    /// **The axis a transaction did not assign is the window's current one, never the one left in
    /// the overrides.** Those are cumulative: the first handler's 250 stays in `overrides.geometry`
    /// for the session, so a later handler that touches only the *height* used to re-assert it and
    /// yank a window the user had since stretched. Reported as "the right side drawer keeps
    /// stretching the window and releasing the stretch" (W188).
    func testAStaleWidthOverrideDoesNotComeBackOnAHeightOnlyAssignment() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="200" height="100">
            <BUTTON id="wide" left="0" top="0" width="10" height="10" onClick="view.width += 50;"/>
            <BUTTON id="tall" left="0" top="20" width="10" height="10" onClick="view.height += 40;"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        _ = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 100),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "wide", handlers: ["view.width += 50;"]))
        // The user then drags the window wider than the script ever asked for.
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 400, height: 100),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "tall", handlers: ["view.height += 40;"]))
        XCTAssertEqual(output.viewSize, WMPSize(width: 400, height: 140),
                       "the height moves; the width stays where the user left it")
    }

    // MARK: W185 — a script-assigned alignment re-anchors

    /// **WMP re-measures an element's margins the moment its alignment is written**, which is what
    /// the `SetAlignment(false)` → grow → `SetAlignment(true)` dance in `Compact`'s drawer handlers
    /// is for: the player body keeps its 422 and the width the view gained is the drawer. Anchored
    /// at the markup instead, the body stretched over the whole new window and the drawer opened
    /// underneath it — "the drawers do not slide out, they change the size/shape of the player".
    func testAScriptAssignedAlignmentAnchorsAtTheCanvasItWasAssignedAt() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="200" height="100">
            <SUBVIEW id="body" left="0" top="0" width="200" height="100" horizontalAlignment="stretch"/>
            <BUTTON id="go" left="0" top="0" width="10" height="10"
                    onClick="body.horizontalAlignment='left'; view.width += 50;
                             body.horizontalAlignment='stretch';"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let source = """
        body.horizontalAlignment='left'; view.width += 50; body.horizontalAlignment='stretch';
        """
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 200, height: 100),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go", handlers: [source]))
        let anchor = output.overrides.scriptAssignedAlignment[
            .init(stableID: try stableID(skin, "body"), property: "horizontalalignment")]
        XCTAssertEqual(anchor, WMPSize(width: 250, height: 100),
                       "the second write happened after the view grew, so 250 is its baseline — "
                       + "the canvas moves *within* the transaction and the anchor follows it")

        let scene = try await WMPSceneBuilder(loadedSkin: skin,
                                              imageStore: WMPImageStore(provider: skin.archive))
            .build(viewID: "main", requestedSize: WMPSize(width: 250, height: 100),
                   overrides: output.overrides)
        let body = try XCTUnwrap(scene.geometries[try stableID(skin, "body")])
        XCTAssertEqual(body.localFrame.width, 200,
                       "stretch from a 250 baseline in a 250 window adds nothing: the body keeps "
                       + "its own 200 and the 50 the view gained is the drawer's")
    }

    // MARK: W189 — WMP's own resource strings

    func testResourceStringsResolveOrBlankButNeverDrawTheURL() {
        XCTAssertEqual(WMPResourceStrings.resolved("res://wmploc.dll/RT_STRING/#1846"), "On")
        XCTAssertEqual(WMPResourceStrings.resolved("res://wmploc.dll/RT_STRING/#1827"),
                       "SRS WOW Effects")
        // `transport.js` spells the library both ways within ten lines.
        XCTAssertEqual(WMPResourceStrings.resolved("res://wmploc/RT_STRING/#1800"), "Play")
        XCTAssertEqual(WMPResourceStrings.resolved("res://wmploc.dll/RT_STRING/#2099"), "",
                       "an id nothing in the corpus names is blank, never the URL")
        XCTAssertEqual(WMPResourceStrings.resolved("Ready"), "Ready",
                       "anything that is not a resource URL passes through untouched")
        XCTAssertNil(WMPResourceStrings.resolved(nil))
    }
}
