import AppKit
import Foundation
import XCTest
@testable import NullPlayer

/// Compact mode: the three defects that between them made every `.wmz` alternate view unreachable,
/// indistinguishable, or a trap — reported live as "there are major issues with any skin that has
/// compact mode… pressing the compact mode button has no visual difference on any skin… there is no
/// way to leave compact mode while in the skin."
///
/// The controller half is here because none of it is visible to the headless render sweep: a view
/// switch is an app path, and the sweep renders each view independently and never performs one.
@MainActor
final class WMPPhase9Tests: XCTestCase {

    private func waitUntil(timeout: Duration = .seconds(5),
                           _ condition: @MainActor @escaping () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { XCTFail("Timed out waiting for WMP controller state"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func controller(wms: String, filename: String = "Phase9.wmz",
                            script: String? = nil) async throws
        -> (WMPMainWindowController, UserDefaults, () -> Void) {
        let root = try WMPSkinTestSupport.temporaryDirectory()
        let suite = "WMPPhase9Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let importer = WMPSkinImporter(directoryURL: root, defaults: defaults)
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]
        if let script { entries.append(WMPTestArchiveEntry("skin.js", data: Data(script.utf8))) }
        let source = try WMPSkinTestSupport.makeArchive(entries, filename: filename)
        _ = try await importer.importSkin(from: source)
        let controller = WMPMainWindowController(importer: importer)
        return (controller, defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    /// What the skin wrote with `theme.savePreference`, whatever this fixture's namespace is.
    private func preference(_ key: String, in defaults: UserDefaults) -> String? {
        for (name, value) in defaults.dictionaryRepresentation()
        where name.hasPrefix("wmp.preferences.") {
            if let values = value as? [String: String], let stored = values[key] { return stored }
        }
        return nil
    }

    /// **W46 — a view arrived at by a switch must load exactly like one arrived at by launch.**
    ///
    /// `switchView(to:)` used to call `transact(event: nil)` — so the new view's `onLoad` never ran —
    /// and to drop the transaction's host commands on the presented path. A `.wmz` compact mode is
    /// built out of both: Corona's `viewTiny` is authored `timerInterval="0"` and animates itself
    /// into the mini player entirely from `OnTinyLoad`, which posts `setViewTimerInterval`. With the
    /// load event dropped the handler never ran and with the commands dropped the interval never
    /// arrived, so the view sat at frame zero — the same artwork at the same size as the player.
    ///
    /// One assertion covers both halves. `second`'s `onLoad` redirects to `third`: the redirect can
    /// only happen if the load event was raised *and* the host command it posted was honoured.
    func testASwitchedViewRunsItsOnLoadAndHonoursTheHostCommandsItPosts() async throws {
        let (controller, _, cleanup) = try await controller(wms: """
        <THEME>
          <VIEW id="main" width="120" height="80">
            <SUBVIEW left="0" top="0" width="120" height="80" backgroundColor="#224466"/>
          </VIEW>
          <VIEW id="second" width="100" height="60" onLoad="JScript:theme.currentViewID='third';">
            <SUBVIEW left="0" top="0" width="100" height="60" backgroundColor="#112233"/>
          </VIEW>
          <VIEW id="third" width="90" height="50">
            <SUBVIEW left="0" top="0" width="90" height="50" backgroundColor="#445566"/>
          </VIEW>
        </THEME>
        """)
        defer { cleanup() }
        try await waitUntil { controller.window?.contentView is WMPMainView }
        XCTAssertEqual(controller.selectedViewID, "main")

        controller.switchView(to: "second")
        try await waitUntil { controller.selectedViewID == "third" }
        XCTAssertEqual(controller.window?.frame.size, NSSize(width: 90, height: 50),
                       "the redirect the switched-to view asked for in its own onLoad must be "
                       + "followed, which it can only be if the load event ran and its host "
                       + "commands were applied")
        XCTAssertNil(controller.lastLoadDiagnostic)
        controller.prepareForUITeardown()
        controller.window?.close()
    }

    /// A view that blanks itself in the `onLoad` this path now runs must not become the window.
    /// `Halo 2` opens on a store-thumbnail `previewView` whose handler sets `view.width = 0` and
    /// redirects; presenting it leaves an empty window the size of a thumbnail. Initial load already
    /// guarded this, and the guard had to come with the load event when the switch path gained one.
    func testASwitchedToViewThatCollapsesItselfIsNotPresented() async throws {
        let (controller, _, cleanup) = try await controller(wms: """
        <THEME>
          <VIEW id="main" width="120" height="80">
            <SUBVIEW left="0" top="0" width="120" height="80" backgroundColor="#224466"/>
          </VIEW>
          <VIEW id="ghost" width="200" height="150"
                onLoad="JScript:view.width=0;view.height=0;theme.currentViewID='third';">
            <SUBVIEW left="0" top="0" width="200" height="150" backgroundColor="#112233"/>
          </VIEW>
          <VIEW id="third" width="90" height="50">
            <SUBVIEW left="0" top="0" width="90" height="50" backgroundColor="#445566"/>
          </VIEW>
        </THEME>
        """, filename: "Phase9Ghost.wmz")
        defer { cleanup() }
        try await waitUntil { controller.window?.contentView is WMPMainView }

        controller.switchView(to: "ghost")
        try await waitUntil { controller.selectedViewID == "third" }
        XCTAssertEqual(controller.window?.frame.size, NSSize(width: 90, height: 50),
                       "a view that collapses itself in its own onLoad must hand off, never present")
        controller.prepareForUITeardown()
        controller.window?.close()
    }

    /// **W88 — a host command is the script's output, not the drawing's.**
    ///
    /// `applyHostCommands` used to run *after* the scene was built and presented, inside the same
    /// cancellable block. The build and the render are the slow half of a transaction, so a view
    /// timer that fires during them cancels the task at `guard !Task.isCancelled` — right for the
    /// drawing, because a newer transaction is already building a newer scene, and it discarded the
    /// commands along with it.
    ///
    /// `Alienware Invader` is what that cost, reported live as "it opens to reveal the controls and
    /// then closes". Its 568-frame intro ends on the heaviest tick in the skin — `toggleShutter()`
    /// swaps `mainBack` to `main_back.png`, turns `mainBackGroup1` on, and posts
    /// `view.timerInterval = 0` to stop its own animation — and building that frame decodes the
    /// whole player's artwork, overrunning the 50 ms period. The reveal was never presented and the
    /// `0` never applied, so the timer kept firing with the skin's own `introStatus` now true and
    /// the next tick took the *other* branch of `toggleShutter()`, closing the shutter it had just
    /// opened. The trace is `txn 207 ran … hostCommands=["setViewTimerInterval=0"]` with no
    /// `command` line after it, and `txn 208 begin timer` immediately below.
    ///
    /// **This test pins the contract, not the overrun.** Nothing here can make a 120x80 scene take
    /// longer than a timer period, so it does not fail against the old code; the race itself was
    /// reproduced and the fix confirmed in the running app, per
    /// `skills/wmp-skin-guide/reference/harness.md` § *Driving the app*. What it does hold is that a
    /// handler which stops its own timer is obeyed and stays obeyed — the ticks stop at one.
    func testATimerHandlerThatStopsItsOwnTimerIsObeyed() async throws {
        let (controller, defaults, cleanup) = try await controller(wms: """
        <THEME>
          <VIEW id="main" width="120" height="80" scriptFile="skin.js"
                timerInterval="20" onTimer="tick()">
            <SUBVIEW left="0" top="0" width="120" height="80" backgroundColor="#224466"/>
          </VIEW>
        </THEME>
        """, filename: "Phase9Timer.wmz", script: """
        var ticks = 0;
        function tick() {
            ticks = ticks + 1;
            theme.savePreference('ticks', '' + ticks);
            view.timerInterval = 0;
        }
        """)
        defer { cleanup() }
        try await waitUntil { controller.window?.contentView is WMPMainView }
        try await waitUntil { self.preference("ticks", in: defaults) != nil }
        XCTAssertEqual(preference("ticks", in: defaults), "1")

        // Long enough for a dozen more periods, so a dropped `setViewTimerInterval` shows up as a
        // count that kept climbing rather than as a timing coincidence.
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(preference("ticks", in: defaults), "1",
                       "a view timer the skin stopped from its own onTimer must stay stopped")
        XCTAssertNil(controller.lastLoadDiagnostic)
        controller.prepareForUITeardown()
        controller.window?.close()
    }
}
