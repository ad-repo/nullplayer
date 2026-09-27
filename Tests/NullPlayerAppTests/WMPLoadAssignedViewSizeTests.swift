import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// **W244: a view that resizes itself in its own `onLoad` was rendered at the size it asked for
/// and shown in a window that was still the authored one.**
///
/// Reported live 2026-09-20 on `Xbox Live Skin`'s `eqView`, which is
/// `width="423" height="343" minWidth="429" minHeight="197"` with `onLoad="loadEQPrefs()"`, and
/// `loadEQPrefs()` is three lines — `view.width = view.minWidth; view.height = view.minHeight`,
/// the compact equaliser its artwork is drawn for. The scene was right and the window was not:
/// `RENDER-DUMP eqView: 429x197` against a measured window of `429x343`, so everything pinned
/// `top="jscript:view.height-181"` travelled to a bottom nobody was looking at and left a black
/// band with two white seams.
///
/// The cause is one line of builder contract: `canvas = resizeLimits.clamp(requestedSize ??
/// defaultSize)`, and the script's assignment lives in `defaultSize`. Both load paths handed the
/// builder the *pre*-`onLoad` canvas as `requestedSize`, which therefore won.
///
/// Measured A/B in a debug build, `winhelper windows`, on the real archive: `429x343` with the
/// change backed out and `429x197` with it, on both the player path (`eqView` as the startup view)
/// and the `theme.openView` path (`mainStartUp` opens it from `mainView`).
final class WMPLoadAssignedViewSizeTests: XCTestCase {
    private func runtime(_ name: String = #function) throws -> (WMPScriptRuntime, () -> Void) {
        let suite = "WMPLoadAssignedViewSizeTests.\(name).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data(name.utf8),
                                                                 defaults: defaults)),
                { defaults.removePersistentDomain(forName: suite) })
    }

    private func load(_ wms: String) async throws -> WMPLoadedSkin {
        try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(
            [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]))
    }

    private func build(_ skin: WMPLoadedSkin, _ size: WMPSize?,
                       _ overrides: WMPSceneOverrides = .empty) async throws -> WMPScene {
        try await WMPSceneBuilder(loadedSkin: skin, imageStore: WMPImageStore(provider: skin.archive))
            .build(viewID: "eqView", requestedSize: size, overrides: overrides)
    }

    /// `eqView` in the smallest markup that reproduces it, including the rail the defect is visible
    /// on: a piece pinned to `view.height-181`, which is 162 in the compact layout the skin asked
    /// for and 324 in the one it was drawn at.
    private static let markup = """
    <THEME><VIEW id="eqView" width="423" height="343" minWidth="429" minHeight="197"
                 resizAble="true" onLoad="view.width = view.minWidth; view.height = view.minHeight;">
        <TEXT id="rail" left="0" width="10" height="10" top="jscript:view.height-181"/>
    </VIEW></THEME>
    """

    private func loadTransaction(_ skin: WMPLoadedSkin, _ runtime: WMPScriptRuntime,
                                 opening opened: WMPSize) async -> WMPScriptOutput {
        await runtime.transact(
            skin: skin, viewID: "eqView", size: opened, snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "load", targetID: nil,
                                   handlers: ["view.width = view.minWidth; view.height = view.minHeight;"]))
    }

    /// The canvas the view opens with, before any script runs: the authored 423x343 lifted to the
    /// `minWidth` floor. This is the number both load paths used to hand the builder.
    func testTheViewOpensAtItsAuthoredCanvasLiftedToItsFloor() async throws {
        let scene = try await build(try await load(Self.markup), nil)
        XCTAssertEqual(scene.canvasSize, WMPSize(width: 429, height: 343))
    }

    /// The load transaction reports the assignment, already clamped to the view's own limits — so
    /// the answer the load path needs was available all along and simply was not read.
    func testTheLoadTransactionReportsTheSizeTheHandlerAssigned() async throws {
        let skin = try await load(Self.markup)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        let output = await loadTransaction(skin, runtime, opening: WMPSize(width: 429, height: 343))
        XCTAssertEqual(output.viewSize, WMPSize(width: 429, height: 197),
                       "minWidth x minHeight, which is what the handler assigned")
    }

    /// **The defect, held in place.** The builder takes `requestedSize` over the script override,
    /// so passing the pre-`onLoad` canvas rebuilds the canvas at 343 while every
    /// `jscript:view.height` in it still answers 197 — the scene/window disagreement the row names,
    /// and the shape of the reported picture: a rail pinned to the bottom edge is drawn 16 from the
    /// *top* of a canvas 146 px taller than the one it was measured against, leaving the band below
    /// it empty.
    func testThePreLoadCanvasAsRequestedSizeDiscardsTheAssignment() async throws {
        let skin = try await load(Self.markup)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        let opened = WMPSize(width: 429, height: 343)
        let output = await loadTransaction(skin, runtime, opening: opened)
        let scene = try await build(skin, opened, output.overrides)

        XCTAssertEqual(scene.canvasSize, opened, "requestedSize wins over the script's assignment")
        XCTAssertEqual(try XCTUnwrap(scene.widgets.first { $0.nodeID == "rail" }).frame.y, 16,
                       "197-181: the expression answers the size the script asked for while the "
                       + "canvas around it is 343, so the rail is 146 px short of the bottom it "
                       + "is pinned to")
    }

    /// **The fix.** `loadedCanvas` is what both load paths now hand the builder, and at it the
    /// canvas, the window and the expression all carry one number.
    func testTheAssignedSizeIsTheCanvasTheFirstSceneIsBuiltAt() async throws {
        let skin = try await load(Self.markup)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        let opened = WMPSize(width: 429, height: 343)
        let output = await loadTransaction(skin, runtime, opening: opened)
        let requested = WMPMainWindowController.loadedCanvas(assigned: output.viewSize,
                                                             opened: opened)
        XCTAssertEqual(requested, WMPSize(width: 429, height: 197))

        let scene = try await build(skin, requested, output.overrides)
        XCTAssertEqual(scene.canvasSize, WMPSize(width: 429, height: 197))
        XCTAssertEqual(try XCTUnwrap(scene.widgets.first { $0.nodeID == "rail" }).frame.y, 16,
                       "the same 197-181 — but now against a 197 canvas, so the rail is on the "
                       + "bottom edge it was pinned to rather than 146 px above it")
    }

    /// **A view whose `onLoad` sizes nothing is built exactly as before.** `viewSize` is nil unless
    /// the transaction assigned the root's own width or height, which is what keeps this change off
    /// the rest of the corpus.
    func testAViewThatAssignsNoSizeKeepsTheCanvasItOpenedWith() async throws {
        let skin = try await load("""
        <THEME><VIEW id="eqView" width="423" height="343" minWidth="429" minHeight="197"
                     resizAble="true" onLoad="view.backgroundColor = '#000000';">
            <TEXT id="rail" left="0" width="10" height="10" top="jscript:view.height-181"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        let opened = WMPSize(width: 429, height: 343)
        let output = await runtime.transact(
            skin: skin, viewID: "eqView", size: opened, snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "load", targetID: nil,
                                   handlers: ["view.backgroundColor = '#000000';"]))
        XCTAssertNil(output.viewSize)
        XCTAssertEqual(WMPMainWindowController.loadedCanvas(assigned: output.viewSize,
                                                            opened: opened), opened)
    }
}
