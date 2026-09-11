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

    /// **`theme.openView` opens a second window and the opener is untouched.**
    ///
    /// It used to present the panel in the one window there was and remember the view it covered,
    /// which is what W90 ("closing an interior window closes the whole UI"), W96 ("the skin is empty
    /// and shows no player") and W127 (the macOS close control stranding the user) were each made
    /// of. Three things hold here and they are the whole contract: the player keeps its view, the
    /// panel gets a window of its own, and the session's persisted view is still the player's —
    /// `WoW` opens its playlist exactly this way, and quitting with it open used to restore a
    /// playlist with no player behind it.
    func testOpenViewOpensASecondWindowAndLeavesTheOpenerAlone() async throws {
        let (controller, defaults, cleanup) = try await controller(wms: """
        <THEME>
          <VIEW id="main" width="120" height="80">
            <SUBVIEW id="btn" left="0" top="0" width="120" height="80" backgroundColor="#224466"
                     onClick="JScript:theme.openView('panel');"/>
          </VIEW>
          <VIEW id="panel" width="100" height="60">
            <SUBVIEW left="0" top="0" width="100" height="60" backgroundColor="#112233"/>
          </VIEW>
        </THEME>
        """, filename: "Phase9Opened.wmz")
        defer { cleanup() }
        try await waitUntil { controller.window?.contentView is WMPMainView }
        XCTAssertEqual(defaults.string(forKey: WMPSkinImporter.selectedViewIDKey), "main")

        // Through the view's own callback, which is the path a real click takes.
        let view = try XCTUnwrap(controller.window?.contentView as? WMPMainView)
        view.onScriptEvent?("click", "btn", nil)
        try await waitUntil { controller.openViewIDs.count == 2 }

        XCTAssertEqual(controller.selectedViewID, "main",
                       "the opener keeps its view: openView is not a view switch")
        XCTAssertEqual(controller.openViewIDs, ["main", "panel"])
        XCTAssertEqual(controller.window?.frame.size, NSSize(width: 120, height: 80),
                       "the player still draws its own scene at its own size")
        XCTAssertEqual(controller.materializedAuxiliaryWindows.count, 1)
        XCTAssertEqual(controller.materializedAuxiliaryWindows.first?.frame.size,
                       NSSize(width: 100, height: 60))
        XCTAssertEqual(defaults.string(forKey: WMPSkinImporter.selectedViewIDKey), "main",
                       "a panel in its own window is not the session's view (W96)")
        controller.prepareForUITeardown()
        controller.window?.close()
    }

    /// **`theme.closeView('name')` closes that window and only that one.**
    ///
    /// 84 of the 180 archives call it and every one of them has been aborting the handler that
    /// does: the member was unrecognised, so `Halo 2`'s `checkRemoteViewStatus()` died on
    /// `theme.closeView('vidRemoteView')` and never reached the statements after it. The second
    /// assertion is that half — the statement following the call still runs.
    func testCloseViewByNameClosesThatWindowAndKeepsTheHandlerRunning() async throws {
        let (controller, defaults, cleanup) = try await controller(wms: """
        <THEME>
          <VIEW id="main" width="120" height="80">
            <SUBVIEW id="open" left="0" top="0" width="60" height="80" backgroundColor="#224466"
                     onClick="JScript:theme.openView('one');theme.openView('two');"/>
            <SUBVIEW id="shut" left="60" top="0" width="60" height="80" backgroundColor="#442266"
                     onClick="JScript:theme.closeView('one');theme.savePreference('after','yes');"/>
          </VIEW>
          <VIEW id="one" width="100" height="60">
            <SUBVIEW left="0" top="0" width="100" height="60" backgroundColor="#112233"/>
          </VIEW>
          <VIEW id="two" width="90" height="50">
            <SUBVIEW left="0" top="0" width="90" height="50" backgroundColor="#332211"/>
          </VIEW>
        </THEME>
        """, filename: "Phase9CloseByName.wmz")
        defer { cleanup() }
        try await waitUntil { controller.window?.contentView is WMPMainView }
        let view = try XCTUnwrap(controller.window?.contentView as? WMPMainView)
        view.onScriptEvent?("click", "open", nil)
        try await waitUntil { controller.openViewIDs.count == 3 }

        view.onScriptEvent?("click", "shut", nil)
        try await waitUntil { controller.openViewIDs == ["main", "two"] }
        XCTAssertEqual(controller.selectedViewID, "main")
        XCTAssertEqual(controller.window?.frame.size, NSSize(width: 120, height: 80),
                       "closing a named panel must not touch the player")
        try await waitUntil { self.preference("after", in: defaults) == "yes" }
        controller.prepareForUITeardown()
        controller.window?.close()
    }

    /// A panel's own `view.close()` closes **its** window and leaves the player up. That is the
    /// whole of what `openedViewStack` used to simulate, and the simulation is what let a close
    /// order out the only WMP window there was.
    func testAPanelClosingItselfLeavesThePlayerUp() async throws {
        let (controller, _, cleanup) = try await controller(wms: """
        <THEME>
          <VIEW id="main" width="120" height="80">
            <SUBVIEW left="0" top="0" width="120" height="80" backgroundColor="#224466"/>
          </VIEW>
          <VIEW id="playlist" width="140" height="90">
            <PLAYLIST id="rows" left="0" top="0" width="140" height="70"/>
            <BUTTON id="close" left="0" top="70" width="20" height="20"
                    onClick="JScript:view.close();"/>
          </VIEW>
        </THEME>
        """, filename: "Phase9MenuPlaylist.wmz")
        defer { cleanup() }
        try await waitUntil { controller.selectedViewID == "main" }

        // A menu-selected surface takes the same `openView` route the skin's own button takes.
        XCTAssertTrue(controller.revealSkinSurface(.playlist, switchingViews: true))
        try await waitUntil { controller.openViewIDs == ["main", "playlist"] }
        let panel = try XCTUnwrap(controller.materializedAuxiliaryWindows.first?.contentView
                                    as? WMPMainView)
        panel.onScriptEvent?("click", "close", nil)
        try await waitUntil { controller.openViewIDs == ["main"] }
        XCTAssertEqual(controller.selectedViewID, "main")
        XCTAssertTrue(controller.materializedAuxiliaryWindows.isEmpty)
        controller.prepareForUITeardown()
        controller.window?.close()
    }

    /// **Two open windows keep separate script scopes.** The runtime's overrides and its
    /// observable-property registry are per view, not per session: a registry only reports values
    /// that moved *since it last looked*, so two windows sharing one would each see half the
    /// changes. Here each panel's `onLoad` resizes only itself, and neither size may leak.
    func testTwoOpenViewsKeepSeparateOverrides() async throws {
        let (controller, _, cleanup) = try await controller(wms: """
        <THEME>
          <VIEW id="main" width="120" height="80"
                onLoad="JScript:theme.openView('one');theme.openView('two');">
            <SUBVIEW left="0" top="0" width="120" height="80" backgroundColor="#224466"/>
          </VIEW>
          <VIEW id="one" width="100" height="60" onLoad="JScript:panelOne.left = 7;">
            <SUBVIEW id="panelOne" left="0" top="0" width="40" height="40" backgroundColor="#112233"/>
          </VIEW>
          <VIEW id="two" width="90" height="50" onLoad="JScript:panelTwo.left = 21;">
            <SUBVIEW id="panelTwo" left="0" top="0" width="30" height="30" backgroundColor="#332211"/>
          </VIEW>
        </THEME>
        """, filename: "Phase9TwoViews.wmz")
        defer { cleanup() }
        try await waitUntil { controller.openViewIDs.count == 3 }
        // Each window drew its own view at its own authored canvas; a shared override table would
        // have applied one panel's geometry inside the other.
        XCTAssertEqual(controller.window?.frame.size, NSSize(width: 120, height: 80))
        let sizes = Set(controller.materializedAuxiliaryWindows.map(\.frame.size.width))
        XCTAssertEqual(sizes, [100, 90])
        XCTAssertNil(controller.lastLoadDiagnostic)
        controller.prepareForUITeardown()
        controller.window?.close()
    }

    /// **Closing the player closes the whole skin UI.** The macOS close control used to mean
    /// `closeView` whenever anything had been opened over the player, because the one window was
    /// standing in for two and letting AppKit order it out stranded the user on a playlist with no
    /// route back (Plus! Professional, W127). With the panel in its own window that compensation has
    /// no job — but the panels must not outlive the player either, which is the W96 shape.
    func testClosingThePlayerTakesItsPanelsWithIt() async throws {
        let (controller, _, cleanup) = try await controller(wms: """
        <THEME>
          <VIEW id="main" width="120" height="80">
            <SUBVIEW left="0" top="0" width="120" height="80" backgroundColor="#224466"/>
          </VIEW>
          <VIEW id="playlist" width="140" height="90">
            <PLAYLIST id="rows" left="0" top="0" width="140" height="70"/>
          </VIEW>
        </THEME>
        """, filename: "Phase9WindowClose.wmz")
        defer { cleanup() }
        try await waitUntil { controller.selectedViewID == "main" }
        XCTAssertTrue(controller.revealSkinSurface(.playlist, switchingViews: true))
        try await waitUntil { controller.openViewIDs == ["main", "playlist"] }
        let panel = try XCTUnwrap(controller.materializedAuxiliaryWindows.first)

        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(controller.windowShouldClose(window))
        XCTAssertTrue(controller.openViewIDs.isEmpty)
        XCTAssertFalse(panel.isVisible, "a panel must never outlive the player it was opened from")
        XCTAssertFalse(window.isMiniaturized, "closing the player must not minimize the app window")
        controller.prepareForUITeardown()
        window.close()
    }

    /// **A skin reload must not take the player window off screen.**
    ///
    /// Ordering the player out is what `view.close()` and the macOS close control mean, and nothing
    /// else. `WMPViewWindowMaterializer.teardown()` reuses the same `remove` a close does, and a
    /// reload tears the materializer down first — so the window went out and nothing ever put it
    /// back. The launch path is what made that visible rather than theoretical:
    /// `AppStateManager.restoreWindowFrames` calls `restoreFrame`, which reloads the skin when one
    /// is already loaded, so **every launch with a persisted `.wmz` and a saved frame** lost its
    /// main window. Reported as "main windows launch minimized".
    func testReloadingTheSkinLeavesThePlayerWindowOnScreen() async throws {
        let (controller, _, cleanup) = try await controller(wms: """
        <THEME>
          <VIEW id="main" width="120" height="80">
            <SUBVIEW left="0" top="0" width="120" height="80" backgroundColor="#224466"/>
          </VIEW>
        </THEME>
        """, filename: "Phase9Reload.wmz")
        defer { cleanup() }
        try await waitUntil { controller.selectedViewID == "main" }
        controller.showWindow(nil)
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.isVisible)

        // The launch path: a saved frame for the skin that is already loaded.
        controller.restoreFrame(NSRect(x: 120, y: 120, width: 120, height: 80),
                                skinName: "Phase9Reload", viewID: "main")
        try await waitUntil { controller.selectedViewID == "main" }
        XCTAssertTrue(window.isVisible,
                      "a reload is not a close: only view.close() orders the player out")
        XCTAssertFalse(window.isMiniaturized)
        controller.prepareForUITeardown()
        window.close()
    }

    /// NVIDIA keeps its playlist inside `mainView`; unlike an EQ panel there is no view stack for
    /// `view.close()` to pop. Its close control must therefore run the skin's authored audio-mode
    /// transition, including clearing the video latch that otherwise sends the transition back to
    /// video mode.
    func testNVIDIAEmbeddedPlaylistCloseReturnsToAudioMode() async throws {
        let (controller, _, cleanup) = try await controller(wms: """
        <THEME>
          <VIEW id="mainView" width="285" height="301" scriptFile="skin.js">
            <SUBVIEW id="audio" width="285" height="301" visible="true">
              <BUTTON id="openPlaylist" left="0" top="0" width="20" height="20"
                      onClick="JScript:plModeToggle();"/>
            </SUBVIEW>
            <SUBVIEW id="playlistMode" width="780" height="920" visible="false">
              <PLAYLIST id="playlist1" left="0" top="0" width="400" height="400"/>
              <BUTTON id="close" left="400" top="0" width="20" height="20"
                      onClick="JScript:view.close();"/>
            </SUBVIEW>
          </VIEW>
        </THEME>
        """, filename: "NVIDIA.wmz", script: """
        function plModeToggle() {
          audio.visible = false;
          playlistMode.visible = true;
          view.width = 780;
          view.height = 920;
        }
        function audioModeToggle() {
          audio.visible = true;
          playlistMode.visible = false;
          view.width = 285;
          view.height = 301;
        }
        """)
        defer { cleanup() }
        try await waitUntil { controller.selectedViewID == "mainView" }
        controller.showWindow(nil)
        let view = try XCTUnwrap(controller.window?.contentView as? WMPMainView)
        view.onScriptEvent?("click", "openPlaylist", nil)
        try await waitUntil {
            controller.window?.frame.size == NSSize(width: 780, height: 920)
                && view.subviews.contains { $0.accessibilityIdentifier() == "wmp.playlist1" }
        }

        view.onScriptEvent?("click", "close", nil)
        try await waitUntil { controller.window?.frame.size == NSSize(width: 285, height: 301) }
        XCTAssertTrue(controller.window?.isVisible == true)
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
            theme.playSound('intro.wav');
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
