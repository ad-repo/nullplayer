import AppKit
import Foundation
import XCTest
@testable import NullPlayer

/// W216. **An event handler resolves an unqualified name against the element it is authored on.**
/// WMP puts that element at the front of the handler's scope chain; this engine bound one global,
/// `value`, and let everything else fall through to the skin's globals and throw.
///
/// **Measured 2026-09-21 over the 184-archive corpus**, scanning the decoded script text (the
/// census drives `onLoad` and this demand is in `onClick`, so it cannot see it — the W100 blind
/// spot) and repairing the `01 00 01 00` local headers the way `WMPArchiveHeaderRepair` does, or
/// `Need_for_Speed_Underground` and `SplinterCellWMPSkin` drop out silently. Encoding breakdown of
/// the scan: 158 UTF-16-BOM / 146 cp1252 / 89 UTF-8 / 9 UTF-8-BOM.
///
/// | half of the class | measured |
/// |---|---|
/// | unqualified **call** | 31 uses / 20 archives — `previous()` 10, `next()` 8, `alphaBlendTo` 4, `nextEffect` 1 |
/// | unqualified **property**, net of the `value` and `<attr>_onchange` globals already bound | 255 unresolved reads + 249 silent writes / 100 archives — `down` 196/89, `toolTip=` 114/40, `left`/`top` 108/9, `width` 34/25, `scrolling` 20/17 |
///
/// The call half is the recorded row and is not what carries it: `player.settings.mute = down` on a
/// sticky mute button is 89 archives on its own, and before this a read threw
/// `ReferenceError: Can't find variable: down` while a write silently made a global and never
/// reached the element.
///
/// **The two guards below are the ones the corpus sweep found, not ones reasoned out.** A `with`
/// scope over the element is only safe while `WMPObjectModel.recognises` — not the open property
/// surface the read path answers with — decides what the element owns, and it was wrong at both
/// edges: it claimed the element's own handler attributes (`corona`'s entire `OnLoad` died on
/// `OnLoad is not a function`) and it did not claim the computed properties `readElement` answers
/// from the host (`Asia`'s marquee died on a bare `textWidth` while `metadata.textWidth` beside it
/// answered).
@MainActor
final class WMPHandlerElementScopeTests: XCTestCase {

    private func waitUntil(timeout: Duration = .seconds(5),
                           _ condition: @MainActor @escaping () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { XCTFail("Timed out waiting for WMP controller state"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func controller(_ entries: [WMPTestArchiveEntry], filename: String) async throws
        -> (WMPMainWindowController, UserDefaults, () -> Void) {
        let root = try WMPSkinTestSupport.temporaryDirectory()
        let suite = "WMPHandlerElementScopeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let importer = WMPSkinImporter(directoryURL: root, defaults: defaults)
        let source = try WMPSkinTestSupport.makeArchive(entries, filename: filename)
        _ = try await importer.importSkin(from: source)
        let controller = WMPMainWindowController(importer: importer)
        return (controller, defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    private func controller(wms: String, filename: String) async throws
        -> (WMPMainWindowController, UserDefaults, () -> Void) {
        try await controller([WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))],
                             filename: filename)
    }

    private func preference(_ key: String, in defaults: UserDefaults) -> String? {
        for (name, value) in defaults.dictionaryRepresentation()
        where name.hasPrefix("wmp.preferences.") {
            if let values = value as? [String: String], let stored = values[key] { return stored }
        }
        return nil
    }

    /// The read half, on the element's own authored attribute. `down` is the corpus's case — 196
    /// uses across 89 archives, every one of them a sticky transport button telling the player what
    /// it was just toggled to — and the assertion is that the handler reaches its *second*
    /// statement at all, which it could not while the first threw.
    func testHandlerReadsItsOwnAuthoredAttributeUnqualified() async throws {
        let (controller, defaults, cleanup) = try await controller(wms: """
        <THEME>
          <VIEW id="main" width="120" height="80">
            <SUBVIEW id="probe" left="0" top="0" width="120" height="80" backgroundColor="#224466"
                     alphaBlend="128"
                     onClick="JScript:theme.savePreference('alpha',String(alphaBlend));\
        theme.savePreference('after','yes');"/>
          </VIEW>
        </THEME>
        """, filename: "ScopeRead.wmz")
        defer { cleanup() }
        try await waitUntil { controller.window?.contentView is WMPMainView }
        let view = try XCTUnwrap(controller.window?.contentView as? WMPMainView)

        view.onScriptEvent?("click", "probe", nil)
        try await waitUntil { self.preference("after", in: defaults) == "yes" }
        XCTAssertEqual(preference("alpha", in: defaults), "128",
                       "a bare name in a handler is the handler's own element's property")
        controller.prepareForUITeardown()
        controller.window?.close()
    }

    /// The write half, and it is the half with no error to read: an unqualified assignment used to
    /// create a global and leave the element untouched, so `toolTip='Seek'` (114 uses across 40
    /// archives) and `scrolling=false` reported success and changed nothing. Read back through the
    /// qualified path, which is the one that was always right.
    func testHandlerWritesItsOwnAttributeUnqualified() async throws {
        let (controller, defaults, cleanup) = try await controller(wms: """
        <THEME>
          <VIEW id="main" width="120" height="80">
            <SUBVIEW id="probe" left="0" top="0" width="120" height="80" backgroundColor="#224466"
                     toolTip="before"
                     onClick="JScript:toolTip='after';\
        theme.savePreference('tip',String(probe.toolTip));"/>
          </VIEW>
        </THEME>
        """, filename: "ScopeWrite.wmz")
        defer { cleanup() }
        try await waitUntil { controller.window?.contentView is WMPMainView }
        let view = try XCTUnwrap(controller.window?.contentView as? WMPMainView)

        view.onScriptEvent?("click", "probe", nil)
        try await waitUntil { self.preference("tip", in: defaults) != nil }
        XCTAssertEqual(preference("tip", in: defaults), "after",
                       "an unqualified assignment reaches the element, not a new global")
        controller.prepareForUITeardown()
        controller.window?.close()
    }

    /// The call half — the recorded row. `moveTo` is ambient, so it is the one element method every
    /// kind answers and the one this can assert without a hosted surface; the corpus's own spelling
    /// of this class is `<EFFECTS onClick="previous();">` in 20 archives.
    func testHandlerCallsItsOwnElementMethodUnqualified() async throws {
        let (controller, defaults, cleanup) = try await controller(wms: """
        <THEME>
          <VIEW id="main" width="120" height="80">
            <SUBVIEW id="probe" left="0" top="0" width="120" height="80" backgroundColor="#224466"
                     onClick="JScript:moveTo(40,8);\
        theme.savePreference('left',String(probe.left));"/>
          </VIEW>
        </THEME>
        """, filename: "ScopeCall.wmz")
        defer { cleanup() }
        try await waitUntil { controller.window?.contentView is WMPMainView }
        let view = try XCTUnwrap(controller.window?.contentView as? WMPMainView)

        view.onScriptEvent?("click", "probe", nil)
        try await waitUntil { self.preference("left", in: defaults) != nil }
        XCTAssertEqual(preference("left", in: defaults), "40",
                       "a bare call resolves against the element the handler is on")
        controller.prepareForUITeardown()
        controller.window?.close()
    }

    /// **The first guard, and the whole reason the scope is arbitrated rather than open.** A view
    /// authors `onLoad`, so an element that claims every attribute it declares answers the bare
    /// `OnLoad` in its own handler with the attribute's *text* and the skin's function of that name
    /// never resolves — `corona`'s startup died on `OnLoad is not a function` and its whole player
    /// came up unpainted. Caught by the corpus sweep, not by reading the code.
    func testAnElementDoesNotClaimItsOwnHandlerAttributeNames() async throws {
        let script = """
        function OnLoad()
        {
            theme.savePreference('ran', 'yes');
        }
        """
        let wms = """
        <THEME scriptFile="main.js">
          <VIEW id="main" width="120" height="80" onLoad="JScript:OnLoad();">
            <SUBVIEW id="probe" left="0" top="0" width="120" height="80" backgroundColor="#224466"/>
          </VIEW>
        </THEME>
        """
        let (controller, defaults, cleanup) = try await controller([
            WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8)),
            WMPTestArchiveEntry("main.js", data: Data(script.utf8))
        ], filename: "ScopeShadow.wmz")
        defer { cleanup() }
        try await waitUntil { controller.window?.contentView is WMPMainView }
        try await waitUntil { self.preference("ran", in: defaults) == "yes" }
        XCTAssertEqual(preference("ran", in: defaults), "yes",
                       "a handler attribute is raised, never resolved as the element's property")
        controller.prepareForUITeardown()
        controller.window?.close()
    }

    /// **The second guard, the mirror of the first.** `textWidth` is computed by `readElement` from
    /// `WMPTextMetrics` rather than held on the element, so a scope that claims only authored and
    /// standard properties answered the qualified `metadata.textWidth` and threw on the bare one in
    /// the same skin — `Asia`'s `onEndMove="scrolling = textWidth > width"`, which is how a marquee
    /// decides to scroll at all (92 archives read it).
    func testHandlerReadsAComputedPropertyUnqualified() async throws {
        let (controller, defaults, cleanup) = try await controller(wms: """
        <THEME>
          <VIEW id="main" width="200" height="80">
            <TEXT id="label" left="0" top="0" width="40" height="14" fontSize="10"
                  value="a title far wider than forty points"
                  onClick="JScript:theme.savePreference('wide',(textWidth>width)?'yes':'no');\
        theme.savePreference('after','yes');"/>
          </VIEW>
        </THEME>
        """, filename: "ScopeComputed.wmz")
        defer { cleanup() }
        try await waitUntil { controller.window?.contentView is WMPMainView }
        let view = try XCTUnwrap(controller.window?.contentView as? WMPMainView)

        view.onScriptEvent?("click", "label", nil)
        try await waitUntil { self.preference("after", in: defaults) == "yes" }
        XCTAssertEqual(preference("wide", in: defaults), "yes",
                       "textWidth is measured, so the bare name must answer what the qualified one does")
        controller.prepareForUITeardown()
        controller.window?.close()
    }

    /// The scope must not swallow the skin's own globals, which is the trap the expression path
    /// already paid for (`Corona`'s `GetEqSliderLeft(1)` resolving to an empty string and losing
    /// all ten equaliser sliders). A name the element does not own reaches the global of that name
    /// even when the element is in scope.
    func testAGlobalFunctionStillResolvesInsideTheElementScope() async throws {
        let script = """
        function Widen(base)
        {
            return base + 10;
        }
        """
        let wms = """
        <THEME scriptFile="main.js">
          <VIEW id="main" width="120" height="80">
            <SUBVIEW id="probe" left="5" top="0" width="120" height="80" backgroundColor="#224466"
                     onClick="JScript:theme.savePreference('widened',String(Widen(left)));"/>
          </VIEW>
        </THEME>
        """
        let (controller, defaults, cleanup) = try await controller([
            WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8)),
            WMPTestArchiveEntry("main.js", data: Data(script.utf8))
        ], filename: "ScopeGlobals.wmz")
        defer { cleanup() }
        try await waitUntil { controller.window?.contentView is WMPMainView }
        let view = try XCTUnwrap(controller.window?.contentView as? WMPMainView)

        view.onScriptEvent?("click", "probe", nil)
        try await waitUntil { self.preference("widened", in: defaults) != nil }
        XCTAssertEqual(preference("widened", in: defaults), "15",
                       "the element is at the front of the scope chain, not the whole of it")
        controller.prepareForUITeardown()
        controller.window?.close()
    }
}
