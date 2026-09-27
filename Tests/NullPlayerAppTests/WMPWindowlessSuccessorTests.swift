import Foundation
import XCTest
@testable import NullPlayer

/// **W175 — a windowless dispatcher's `theme.openView` calls are windows, not a redirect.**
///
/// A `.wmz` names views that are never windows: a `mediaSwitcherView` blanks itself in its own
/// `onLoad`, a `controlView` holds nothing but `<player>` and a hidden `<video>`. Each exists so an
/// `onLoad` can run with host bindings and then say what the user should be looking at — with
/// `theme.currentViewID`, which is a redirect, or with `theme.openView`, which is not one at all.
/// WMP opens a window per `openView` call and leaves the caller alone.
///
/// Collapsing both into a single `last` made the *last* panel a dispatcher opened into the player.
/// `XBOX Music Mixer`'s `onLoadSkin()` ends `theme.openView('mainView'); theme.openView('eqView');`
/// so the app opened on the equaliser, and `mainView` — the only one of its views with buttons that
/// reach the others — was never presented: reported as *"it opens to the playlist and there is no
/// route to get to the main window"*.
@MainActor
final class WMPWindowlessSuccessorTests: XCTestCase {

    private func runtime(_ name: String = #function) throws -> (WMPScriptRuntime, () -> Void) {
        let suite = "WMPWindowlessSuccessorTests.\(name).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data(name.utf8),
                                                                 defaults: defaults)),
                { defaults.removePersistentDomain(forName: suite) })
    }

    private func command(_ action: String, _ value: String) -> WMPJScriptHostCommand {
        WMPJScriptHostCommand(action: action, value: .string(value))
    }

    /// The skin's own declaration order, in the shape `XBOX Music Mixer` authors it: the switcher
    /// first, then the dispatcher, then the player, and the panels after it.
    private let xboxOrder = ["mediaSwitcherView", "controlView", "mainView", "plView",
                             "visView", "eqView", "videoView"]

    // MARK: - The report

    /// The player is the earliest of the opened views in the skin's own declaration order, and the
    /// panels opened after it are still opened — beside it, which is what `openView` means.
    func testTheEarliestDeclaredViewAPanelDispatcherOpensBecomesThePlayer() throws {
        let commands = [command("openView", "mainView"), command("openView", "eqView")]
        let result = WMPMainWindowController.windowlessSuccessors(of: commands,
                                                                  declarationOrder: xboxOrder)
        XCTAssertEqual(result.next, ["mainView", "eqView"],
                       "mainView is declared ahead of eqView, so it is the player — taking the "
                       + "last openView is what opened XBOX Music Mixer on its equaliser")
        XCTAssertEqual(result.opened.compactMap { $0.value?.string }, ["mainView", "eqView"],
                       "both are still opened; the caller drops whichever became the player")
    }

    /// The same, from the runtime rather than a hand-built command list: the dispatcher's own
    /// JScript must produce these commands in the order it authored them.
    func testADispatchersOwnScriptProducesTheOpenViewCommandsInAuthoredOrder() async throws {
        let skin = try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME>
                <VIEW id="controlView" scriptFile="s.js" onLoad="onLoadSkin()"><PLAYER/></VIEW>
                <VIEW id="mainView" width="344" height="422"/>
                <VIEW id="plView" width="343" height="365"/>
                <VIEW id="eqView" width="265" height="207"/>
            </THEME>
            """.utf8)),
            WMPTestArchiveEntry("s.js", data: Data("""
            function onLoadSkin() {
                if ("true" == theme.loadPreference("plViewer")) { theme.openView('plView'); }
                theme.openView('mainView');
                theme.openView('eqView');
            }
            """.utf8))
        ]))
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await runtime.transact(
            skin: skin, viewID: "controlView", size: WMPSize(width: 0, height: 0),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "load", targetID: "controlView",
                                   handlers: ["onLoadSkin()"]))
        XCTAssertEqual(output.hostCommands.compactMap { $0.value?.string }, ["mainView", "eqView"],
                       "an unsaved preference is WMP's `--` sentinel, so the guarded panel is not "
                       + "opened and the two unconditional calls are")
        let result = WMPMainWindowController.windowlessSuccessors(
            of: output.hostCommands, declarationOrder: skin.views.map(\.id))
        XCTAssertEqual(result.next.first, "mainView")
    }

    // MARK: - The redirect is still a redirect

    /// `theme.currentViewID` replaces the view, so the last write wins and no `openView` beside it
    /// can become the player. The panels it opened are still panels.
    func testACurrentViewIDRedirectOutranksEveryOpenViewBesideIt() throws {
        let commands = [command("openView", "eqView"),
                        command("setCurrentView", "mainView"),
                        command("openView", "plView")]
        let result = WMPMainWindowController.windowlessSuccessors(of: commands,
                                                                  declarationOrder: xboxOrder)
        XCTAssertEqual(result.next, ["mainView"])
        XCTAssertEqual(result.opened.compactMap { $0.value?.string }, ["plView", "eqView"],
                       "ranked by declaration order like any other pair, and neither is the player")
    }

    /// Two redirects in one handler is the last one winning — the pre-W175 behaviour for the one
    /// command it was ever right for.
    func testTheLastRedirectWins() throws {
        let result = WMPMainWindowController.windowlessSuccessors(
            of: [command("setCurrentView", "plView"), command("setCurrentView", "mainView")],
            declarationOrder: xboxOrder)
        XCTAssertEqual(result.next, ["mainView"])
        XCTAssertTrue(result.opened.isEmpty)
    }

    // MARK: - The ranking's own edges

    /// A view the skin does not declare cannot be ordered, and every one of them ties. `sorted(by:)`
    /// is not stable, so the tie is broken by the order the handler called them in.
    func testViewsTheSkinDoesNotDeclareKeepTheirAuthoredCallOrder() throws {
        let result = WMPMainWindowController.windowlessSuccessors(
            of: [command("openView", "ghostA"), command("openView", "ghostB"),
                 command("openView", "ghostC"), command("openView", "mainView")],
            declarationOrder: xboxOrder)
        XCTAssertEqual(result.next, ["mainView", "ghostA", "ghostB", "ghostC"],
                       "the declared view outranks all three, and the undeclared keep call order")
    }

    /// `theme.openViewRelative` carries its displacement in the action, and it is an `openView` for
    /// every purpose here — the command is replayed whole, so the offset survives the ranking.
    func testOpenViewRelativeIsRankedAndReplayedWithItsOffset() throws {
        let relative = command("openViewRelative:0,130", "eqView")
        let result = WMPMainWindowController.windowlessSuccessors(
            of: [relative, command("openView", "mainView")], declarationOrder: xboxOrder)
        XCTAssertEqual(result.next, ["mainView", "eqView"])
        XCTAssertEqual(result.opened.last, relative,
                       "the offset rides the action and must reach applyHostCommands intact")
    }

    /// Commands that are neither are the presented controller's, not this view's, and a view with
    /// no window has nothing to say about them.
    func testCommandsThatAreNotWindowCommandsAreIgnored() throws {
        let result = WMPMainWindowController.windowlessSuccessors(
            of: [command("play", ""), WMPJScriptHostCommand(action: "openView", value: nil),
                 command("openView", ""), command("toggleLibrary", "")],
            declarationOrder: xboxOrder)
        XCTAssertTrue(result.next.isEmpty)
        XCTAssertTrue(result.opened.isEmpty, "an openView with no view id names no window")
    }

    // MARK: - A ghost opened by `theme.openView` owns the window it is asking for

    /// **The other half of the same distinction, and it is where `pharaoh` trapped the user.**
    /// W175 is about a windowless view reached at *launch*; this is about one reached at *runtime*
    /// by `theme.openView`, and the rule is the same statement: `openView` opens a window beside
    /// the opener and leaves the opener alone. A view with no canvas has no window to leave
    /// anything in, so the window-scoped commands its `onLoad` posts belong to the window it was
    /// asking for — never to the one that opened it.
    ///
    /// Reported 2026-09-16 as *"you can get trapped in the mini windows with no way back to the
    /// main window"*. `pharaoh`'s transport calls
    /// `theme.openView('vGhostAutoDetect')`, that 0x0 view's `onLoad` writes
    /// `theme.currentViewID='vRos'`, and the redirect landed on the player: the 400x249 sphinx
    /// **became** the 197x194 rosetta panel, whose own close button then closed the app's only
    /// window. Driven live before the fix, two clicks left the process running with zero windows.
    func testARedirectFromAGhostOpensItsOwnWindowRatherThanReplacingTheOpeners() throws {
        let redirected = WMPMainWindowController.redirectedToOwnWindow(
            [command("setCurrentView", "vRos")])
        XCTAssertEqual(redirected, [command("openView", "vRos")],
                       "a ghost's redirect is the window it was opened to be, so it opens beside "
                       + "the player instead of replacing it")
    }

    /// The second half of `pharaoh`'s trap, and the one that made it survive a relaunch: `vGhost`
    /// is opened from `OnLoad()` on **every** launch and its `onLoad` reads a preference the skin
    /// itself saves — `if(theme.loadPreference('paneOpen')=='true')theme.currentViewID='vRos';
    /// else view.close();`. With `paneOpen` false that `view.close()` closed the player before the
    /// user ever saw it, so the skin came up with no window at all and stayed that way.
    func testAGhostCannotCloseOrMinimiseAWindowItNeverHad() throws {
        let redirected = WMPMainWindowController.redirectedToOwnWindow(
            [WMPJScriptHostCommand(action: "closeView", value: nil),
             WMPJScriptHostCommand(action: "minimizeWindow", value: nil)])
        XCTAssertTrue(redirected.isEmpty,
                      "`view.close()` and `view.minimize()` in a canvas-less view are about a "
                      + "window that was never made — they must not reach the opener's")
    }

    /// **`theme.closeView('name')` is untouched, and the distinction is the whole reason the
    /// filter reads the value rather than the action.** Naming a target is not the same as meaning
    /// your own: 84 archives call the named form, and a ghost is as entitled to close a panel by
    /// name as any other view. Host-level commands are likewise the opener's to run.
    func testANamedCloseAndEveryHostLevelCommandStillReachTheOpener() throws {
        let commands = [command("closeView", "plView"), command("play", ""),
                        command("openView", "eqView"), command("setViewTimerInterval", "50")]
        XCTAssertEqual(WMPMainWindowController.redirectedToOwnWindow(commands), commands)
    }

    // MARK: - W299: the dispatcher's `onLoad` on a launch that starts at the persisted player

    /// **The second launch onward starts at the persisted player, and the dispatcher's `onLoad`
    /// still runs.** `wmpSkinViewID` puts `mainView` first in the walk, so `controlView` — where the
    /// Skins Factory family's `onLoadSkin()` re-opens the panels the user left open — was never
    /// visited. `Alienware Invader` opened with no playlist while its `plViewer` said `"true"`, and
    /// `btnPl` took two clicks.
    func testAPersistedPlayerStillRunsTheDispatchersOnLoad() async throws {
        let root = try WMPSkinTestSupport.temporaryDirectory()
        let suite = "WMPWindowlessSuccessorTests.W299.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let importer = WMPSkinImporter(directoryURL: root, defaults: defaults)
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME>
                <VIEW id="controlView" scriptFile="s.js" onLoad="onLoadSkin()"
                      timerInterval="100" onTimer="tick()"><PLAYER/></VIEW>
                <VIEW id="mainView" width="240" height="120"/>
                <VIEW id="plView" width="200" height="100"/>
            </THEME>
            """.utf8)),
            WMPTestArchiveEntry("s.js", data: Data("""
            function onLoadSkin() { theme.openView('plView'); theme.openView('mainView'); }
            function tick() {}
            """.utf8))
        ], filename: "Dispatcher.wmz")
        _ = try await importer.importSkin(from: archive)
        defaults.set("mainView", forKey: WMPSkinImporter.selectedViewIDKey)
        let controller = WMPMainWindowController(importer: importer)
        defer { controller.prepareForUITeardown(); controller.window?.close() }
        let store = WMPViewFrameStore(defaults: defaults)
        let skin = try XCTUnwrap(importer.selectedSkinName)
        let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(3))
        while !store.openViews(skin: skin).contains("plView"), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(controller.selectedViewID, "mainView",
                       "the walk started at the persisted player, not at controlView")
        XCTAssertEqual(store.openViews(skin: skin), ["plView"],
                       "controlView's onLoad was skipped, so the panel it re-opens never opened")
    }
}
