import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// **No `.wmz` window may be sized past the display it is on.**
///
/// Reported 2026-09-19: a 2560x1440 `.mp4` played under `Combat_Flight_Simulator_3` opened a
/// window "massive, with no right click context controls". The skin's `SnapToVideo()` is
/// `view.width = player.currentMedia.imageSourceWidth * (zoom/100) + 20`, and the corpus is full of
/// that shape: seeded with a 2560x1440 source, **83 views across 80 archives** ask for a window
/// around 2600x1600 and `Plus! SlimLine/perfectVSkin` for 5720x3480, against **zero** views over
/// 1440x810 with no video. The window is borderless, so past the screen edge go the skin's own
/// close, zoom and resize controls and there is nothing left to recover it with.
///
/// **Three rules answer it, and it took all three to fix it on screen:** the decoder-driven
/// assignment is refused outright so the view keeps its own canvas
/// (`WMPVideoPresentation.isMediaDrivenViewSize`), any remaining view size is fitted to the
/// display's usable area (`WMPSize.fitted(within:)`), and a size an earlier session already filed
/// away is not restored if it fills or exceeds that area
/// (`WMPMainWindowController.restorableViewSize`). The first fix shipped with only the second of
/// those and the reporter's answer was "the window is still too large … it should not open full
/// screen" — half of that was the ceiling being the whole desktop, and half was the stored size.
///
/// The corpus instrument is `WMP_RENDER_LIMITS=1 WMP_RENDER_HOST='playing,video=2560x1440'`, with
/// the same run minus `video=` as the control. Verified on screen against the reporter's own
/// 2560x1440 film: `videoView` 1800x1130 before, 380x351 after.
final class WMPDisplayCeilingTests: XCTestCase {
    private func runtime(_ name: String = #function) throws -> (WMPScriptRuntime, () -> Void) {
        let suite = "WMPDisplayCeilingTests.\(name).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data(name.utf8),
                                                                 defaults: defaults)),
                { defaults.removePersistentDomain(forName: suite) })
    }

    private func load(_ wms: String) async throws -> WMPLoadedSkin {
        try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(
            [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]))
    }

    private func build(_ skin: WMPLoadedSkin, _ size: WMPSize,
                       _ overrides: WMPSceneOverrides) async throws -> WMPScene {
        try await WMPSceneBuilder(loadedSkin: skin, imageStore: WMPImageStore(provider: skin.archive))
            .build(viewID: "main", requestedSize: size, overrides: overrides)
    }

    /// `Combat_Flight_Simulator_3`'s `SnapToVideo()`, in the smallest markup that reproduces it.
    ///
    /// The three numbers that have to agree are the transaction's `viewSize` (what the window is
    /// set to), the scene's canvas (what the artwork is rasterized at, and what every click is
    /// resolved against — W213) and the expression reading `view.width`. All three are the ceiling.
    func testAViewSizedFromTheDecoderIsFittedToTheDisplay() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="380" height="351" minWidth="380" minHeight="351"
                     resizable="true"
                     onLoad="view.width = 2580; view.height = 1532;">
            <TEXT id="body" left="10" top="37" height="10" width="jscript:view.width-20"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        await runtime.setScreen(WMPSize(width: 1920, height: 1080),
                                usable: WMPSize(width: 1920, height: 1055))

        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 380, height: 351),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "load", targetID: nil,
                                   handlers: ["view.width = 2580; view.height = 1532;"]))
        XCTAssertEqual(output.viewSize, WMPSize(width: 1920, height: 1055),
                       "the window is the display's usable area, not the decoder's 2580x1532")

        let scene = try await build(skin, try XCTUnwrap(output.viewSize), output.overrides)
        XCTAssertEqual(scene.canvasSize, WMPSize(width: 1920, height: 1055),
                       "the scene the overrides build must be the size the window was given")
        let body = try XCTUnwrap(scene.widgets.first { $0.nodeID == "body" })
        XCTAssertEqual(body.frame.width, 1900, "view.width-20 against the clamped canvas")
    }

    /// The ceiling is the machine's, so a bigger display keeps a bigger window. Nothing here is a
    /// constant: `WMPMainWindowController.usableScreenSize(for:)` reads the window's own screen and
    /// `windowDidMove` re-sends it when the window is dragged to another one.
    func testTheCeilingFollowsTheDisplayItWasGiven() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="380" height="351" resizable="true"
                     onLoad="view.width = 2580; view.height = 1532;"/></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        await runtime.setScreen(WMPSize(width: 3456, height: 2234),
                                usable: WMPSize(width: 3456, height: 2145))

        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 380, height: 351),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "load", targetID: nil,
                                   handlers: ["view.width = 2580; view.height = 1532;"]))
        XCTAssertEqual(output.viewSize, WMPSize(width: 2580, height: 1532),
                       "it fits this display, so nothing is clamped")
    }

    /// The ceiling is a ceiling and not a size: a view that fits is left exactly where it is.
    /// Measured corpus-wide as the control — with no video seeded, not one of the 630 views moves.
    func testAViewThatFitsIsUntouched() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="380" height="351" resizable="true"
                     onLoad="view.width = 475; view.height = 373;"/></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        await runtime.setScreen(WMPSize(width: 1920, height: 1080),
                                usable: WMPSize(width: 1920, height: 1055))

        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 380, height: 351),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "load", targetID: nil,
                                   handlers: ["view.width = 475; view.height = 373;"]))
        XCTAssertEqual(output.viewSize, WMPSize(width: 475, height: 373))
    }

    /// **The decoder-driven refusal is recognised on the raw assignment, and the clamp runs after
    /// it.** `WMPVideoPresentation.isMediaDrivenViewSize` matches a *formula* — authored shell plus
    /// the decoder minus the authored video box — which a clamped number no longer is. Testing the
    /// clamped size instead silently stopped `corona`, `Classic`, `9SeriesDefault` and `Compact`
    /// being recognised at all, and the engine then kept an assignment it exists to discard: all
    /// four grew from their authored canvas to the whole screen. Caught only by the corpus sweep.
    func testTheDecoderFormulaIsStillRefusedWhenTheClampWouldAlsoApply() async throws {
        // 596 + 2560 - 300 = 2856, 468 + 1440 - 200 = 1708: `corona`'s shape, over the ceiling.
        let skin = try await load("""
        <THEME><VIEW id="main" width="596" height="468" resizable="true"
                     onLoad="view.width = 2856; view.height = 1708;">
            <VIDEO id="pic" left="0" top="0" width="300" height="200"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        await runtime.setScreen(WMPSize(width: 1920, height: 1080),
                                usable: WMPSize(width: 1920, height: 1055))

        var snapshot = WMPHostSnapshot()
        snapshot.video = WMPVideoSnapshot(width: 2560, height: 1440)
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 596, height: 468),
            snapshot: snapshot,
            event: WMPJScriptEvent(name: "load", targetID: nil,
                                   handlers: ["view.width = 2856; view.height = 1708;"]))
        XCTAssertNil(output.viewSize,
                     "a decoder-sized assignment is refused outright; the picture is fitted into "
                     + "the authored box instead of growing the window")

        let scene = try await build(skin, WMPSize(width: 596, height: 468), output.overrides)
        XCTAssertEqual(scene.canvasSize, WMPSize(width: 691, height: 468),
                       "the refusal must not leave the clamped size in the overrides — 596 is the "
                       + "authored width, plus the 95 this 300pt video box is short of the command "
                       + "bar's 395 (WMPSceneBuilder.videoControlBarWidth)")
    }

    /// The ceiling wins over a floor the view declares for itself. A `minWidth` larger than the
    /// screen is a window whose edges the user cannot reach, which is the whole defect.
    func testTheDisplayWinsOverAViewsOwnFloor() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="380" height="351" minWidth="4000" minHeight="3000"
                     resizable="true" onLoad="view.width = 4000; view.height = 3000;"/></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        await runtime.setScreen(WMPSize(width: 1920, height: 1080),
                                usable: WMPSize(width: 1920, height: 1055))

        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 380, height: 351),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "load", targetID: nil,
                                   handlers: ["view.width = 4000; view.height = 3000;"]))
        XCTAssertEqual(output.viewSize, WMPSize(width: 1920, height: 1055))
    }

    /// **A size already on disk from before the fix.** The store files whatever the window came to
    /// rest at, so the decoder-driven size outlived the growth that made it: the video view stopped
    /// growing and went on *opening* at 1800x1130 every launch, which is what "the window is still
    /// too large" was after the first fix. Measured live on `Combat_Flight_Simulator_3` with the
    /// reporter's own 2560x1440 film — 1800x1130 before, the authored 380x351 after.
    func testAStoredSizeThatFillsOrExceedsTheDisplayIsNotRestored() {
        let screen = NSScreen.main
        let ceiling = WMPMainWindowController.usableScreenSize(for: nil)
        XCTAssertNotNil(screen, "this assertion set is about the real display")
        XCTAssertNil(WMPMainWindowController.restorableViewSize(
            WMPSize(width: ceiling.width + 780, height: ceiling.height + 400), for: nil),
            "the raw decoder size")
        XCTAssertNil(WMPMainWindowController.restorableViewSize(ceiling, for: nil),
            "and the same size once it has been fitted to the display and filed away")
        XCTAssertEqual(WMPMainWindowController.restorableViewSize(
            WMPSize(width: 600, height: ceiling.height), for: nil),
            WMPSize(width: 600, height: ceiling.height),
            "a window dragged to the full height of the screen is still the user's own")
        XCTAssertEqual(WMPMainWindowController.restorableViewSize(
            WMPSize(width: 380, height: 351), for: nil), WMPSize(width: 380, height: 351))
        XCTAssertNil(WMPMainWindowController.restorableViewSize(.zero, for: nil))
    }

    /// `WMPSize.fitted(within:)` itself, including the two degenerate ceilings a headless caller
    /// can hand it — a missing display and a zero one — which must leave the size alone rather
    /// than collapse the window to nothing.
    func testFittedLeavesASizeAloneWhenThereIsNoUsableCeiling() {
        let size = WMPSize(width: 2580, height: 1532)
        XCTAssertEqual(size.fitted(within: nil), size)
        XCTAssertEqual(size.fitted(within: WMPSize(width: 0, height: 0)), size)
        XCTAssertEqual(size.fitted(within: WMPSize(width: 1920, height: 2000)),
                       WMPSize(width: 1920, height: 1532), "each axis on its own")
    }
}
