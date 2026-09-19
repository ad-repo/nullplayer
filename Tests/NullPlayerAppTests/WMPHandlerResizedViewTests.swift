import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// **W99: a view resolved against a size nothing is drawn at.**
///
/// Reported as a drawer's toggle button drifting out from under the pointer on `xsn_sports`, which
/// is the symptom of the milder of the two mechanisms here and named the wrong node — the button
/// never moves. What moves is everything anchored to the view's *bottom*, because a handler
/// changed the view's own size after the expressions that read it had already been resolved.
///
/// The instrument for both is `WMP_RENDER_EXPR`'s two columns: `->` is the initial resolver against
/// the canvas and `live=` is the script runtime's, and a disagreement between them where the deps
/// are only `view.width`/`view.height` is this class and nothing else. Corpus-wide it was 809 of
/// 4,679 such expressions; the evidence is `docs/wmp-skin/wmp-backlog-archive.md` § W99.
final class WMPHandlerResizedViewTests: XCTestCase {
    private func runtime(_ name: String = #function) throws -> (WMPScriptRuntime, () -> Void) {
        let suite = "WMPHandlerResizedViewTests.\(name).\(UUID().uuidString)"
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

    private func top(of id: String, in scene: WMPScene, file: StaticString = #filePath,
                     line: UInt = #line) throws -> CGFloat {
        let widget = try XCTUnwrap(scene.widgets.first { $0.nodeID == id }, file: file, line: line)
        return widget.frame.y
    }

    /// `xsn_sports`, in the smallest markup that reproduces it: the view is authored 396 tall and
    /// its `onLoad` writes 416, so the scene is built at 416 while `view.height-221` still answers
    /// against 396. The whole bottom of the skin sits 20 px high until the view's own 500 ms timer
    /// opens a second transaction — which is why the row read as a drifting button and not as a
    /// broken window, and why the 146 corpus views authoring this shape *without* a timer never
    /// correct.
    func testAnExpressionSeesTheSizeTheHandlerAssignedRatherThanTheOneItOpenedAt() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="379" height="396" resizable="true"
                     onLoad="view.height = 416;">
            <TEXT id="foot" left="0" width="40" height="10" top="jscript:view.height-221"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 379, height: 396),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "load", targetID: nil, handlers: ["view.height = 416;"]))
        XCTAssertEqual(output.viewSize, WMPSize(width: 379, height: 416),
                       "the handler resized its own window")

        let scene = try await build(skin, WMPSize(width: 379, height: 416), output.overrides)
        XCTAssertEqual(scene.canvasSize, WMPSize(width: 379, height: 416))
        XCTAssertEqual(try top(of: "foot", in: scene), 195,
                       "416-221, the canvas the view is drawn at — not 175, the size the "
                       + "expression pass opened at before the handler ran")
    }

    /// The other half, and the one with more reach: `canvas = resizeLimits.clamp(…)`, so a view
    /// declaring `minHeight` has a floor its own script cannot write through. `ALXMorph` is
    /// `<VIEW id="videoView" height="357" minHeight="357">` and `onLoadVid()` assigns 316 — the
    /// canvas stays 357 and the script went on answering 316, which drew the Alienware family's
    /// right-hand rail and close control 41 px inside the window they belong to.
    ///
    /// **Re-resolving against the raw assignment is not a smaller version of the fix**, it is this
    /// defect with the sign flipped: measured over 20 archives it walked
    /// `Back to the Future Trilogy/videoView` out to `x=-94`.
    func testAnAssignmentTheCanvasClampsIsClampedForTheExpressionsToo() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="389" height="357" minWidth="389" minHeight="357"
                     resizable="true" onLoad="view.height = 316;">
            <TEXT id="foot" left="0" width="40" height="10" top="jscript:view.height-187"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 389, height: 357),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "load", targetID: nil, handlers: ["view.height = 316;"]))
        XCTAssertEqual(output.viewSize, WMPSize(width: 389, height: 357),
                       "the size the script got, not the 316 it asked for: the window, the next "
                       + "transaction and the expressions must all carry one number")

        let scene = try await build(skin, WMPSize(width: 389, height: 357), output.overrides)
        XCTAssertEqual(scene.canvasSize, WMPSize(width: 389, height: 357),
                       "the builder's own clamp, unchanged by any of this")
        XCTAssertEqual(try top(of: "foot", in: scene), 170,
                       "357-187, against the floor the canvas is held at — not 129, which is "
                       + "357-187 against a size the window is never drawn at")
    }

    /// A handler that assigns a geometry property *and* resizes the view in one breath is doing
    /// both, and the script's number has to survive the re-resolve. This is W159's rule seen from
    /// the other side: the expression is only ever a starting value for an address the script has
    /// taken over, and the re-resolve must not hand it back.
    func testAScriptAssignedCoordinateSurvivesTheReResolve() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="379" height="396" resizable="true"
                     onLoad="foot.top = 12; view.height = 416;">
            <TEXT id="foot" left="0" width="40" height="10" top="jscript:view.height-221"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 379, height: 396),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "load", targetID: nil,
                                   handlers: ["foot.top = 12; view.height = 416;"]))
        let scene = try await build(skin, WMPSize(width: 379, height: 416), output.overrides)
        XCTAssertEqual(try top(of: "foot", in: scene), 12,
                       "the handler wrote this address, so it is the script's from then on")
    }

    /// A transaction that resized nothing must re-resolve nothing: the expression pass running
    /// before the handlers is the design, not a workaround, and paying for a second pass on every
    /// timer tick in the corpus would be a different kind of defect.
    func testATransactionThatResizesNothingIsUnchanged() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="379" height="396" resizable="true">
            <BUTTON id="go" left="0" top="0" width="10" height="10" onClick="foot.left = 3;"/>
            <TEXT id="foot" left="0" width="40" height="10" top="jscript:view.height-221"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 379, height: 396),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "go", handlers: ["foot.left = 3;"]))
        XCTAssertNil(output.viewSize, "no assignment to the view's own size")

        let scene = try await build(skin, WMPSize(width: 379, height: 396), output.overrides)
        XCTAssertEqual(try top(of: "foot", in: scene), 175, "396-221, the size it opened at")
    }
}
