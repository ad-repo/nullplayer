import CoreGraphics
import XCTest
@testable import NullPlayer

/// **W254 — the hosted picture burst out of a fixed view's video box.**
///
/// Reported live 2026-09-22 as a black slab three hundred points wide hanging out through the right
/// edge of `Revert`'s player, at exactly the height of the video band. It could not exist before
/// W252 closed: the `<VIDEO>` had never been shown, so nothing had ever parked a window over it.
///
/// `WMPVideoSurface` sets `showsVideoControlBar` on the window it parks over the skin's box. That
/// bar does not compress — its controls are one required Auto Layout chain — so the window has a
/// minimum width derived from it and `setFrame` to anything narrower is *silently refused*.
/// `WMPSceneBuilder` compensates by widening the **view** until the box reaches
/// `videoControlBarWidth`, and that is gated on `scene.isResizable`, correctly: forcing a fixed view
/// to a size its scene is not is how a window comes apart (W213).
///
/// So a view that is both **fixed and narrow** falls between the two — it can never be widened, and
/// the window it hosts can never be narrowed. `Revert`'s `vwPlayer` is `resizable="false"` with a
/// 92pt box, and the engine's own hosted-frame diagnostic had been printing the whole defect ten
/// times a second for as long as the path had existed:
///
/// ```
/// WinampModern video: box {92, 67} refused, window took {395, 67}
/// ```
///
/// Verified live after the fix: the window went from `395x67` to `92x67` at the authored rect, and
/// the refusal count went to **zero**.
@MainActor
final class WMPVideoControlBarFitTests: XCTestCase {

    private let bar = WMPSceneBuilder.videoControlBarWidth

    /// The rule itself. A box at or above the bar's own fitting width keeps the overlay; one below
    /// it shows the picture instead, because in a box the skin authored the picture is what the
    /// skin asked for — and real WMP draws no overlay inside a skin's video rect at all.
    func testTheBarIsShownOnlyInABoxThatCanActuallyCarryIt() {
        XCTAssertFalse(WMPVideoSurface.barFits(box: 92, minimumWidth: bar),
                       "Revert's authored box, and the 395pt slab that came out of it")
        XCTAssertFalse(WMPVideoSurface.barFits(box: bar - 1, minimumWidth: bar),
                       "one point short is still short — the window would be refused")
        XCTAssertTrue(WMPVideoSurface.barFits(box: bar, minimumWidth: bar),
                      "exactly wide enough is wide enough")
        XCTAssertTrue(WMPVideoSurface.barFits(box: 640, minimumWidth: bar))
    }

    /// **The surface and the builder must agree about which boxes are wide enough**, or a view the
    /// builder widened *to* the bar's width would have the bar switched off again by the surface and
    /// the widening would be for nothing. Both compare with the same half-point tolerance; this is
    /// the assertion that keeps them one rule rather than two.
    func testEveryBoxTheBuilderWidensForIsOneTheSurfaceThenAcceptsTheBarIn() {
        for authored in stride(from: 40.0, through: 600.0, by: 13.0) {
            let shortfall = authored + 0.5 < bar
            XCTAssertEqual(shortfall, !WMPVideoSurface.barFits(box: authored, minimumWidth: bar),
                           "builder and surface disagree about a \(authored)pt box")
        }
    }

    /// And the widening the surface depends on is refused for exactly the views that produce this
    /// defect: a fixed one is pinned to its canvas at both ends, so it can never grow to fit the
    /// bar and the surface is the only thing standing between it and a burst window.
    func testAFixedViewIsNeverWidenedForTheBarSoTheSurfaceIsTheOnlyGuard() {
        func scene(resizable: Bool, box: CGFloat) -> WMPScene {
            let canvas = WMPSize(width: 256, height: 130)
            let video = WMPWidget(stableID: 1, nodeID: "ctrlVideo", kind: .video,
                                  frame: WMPRect(x: 161, y: 17, width: box, height: 67),
                                  clipRect: nil, label: "Video", toolTip: nil,
                                  minimumValue: nil, maximumValue: nil)
            return WMPScene(viewID: "vwPlayer", canvasSize: canvas,
                            resizeLimits: .init(minimum: canvas,
                                                maximum: resizable
                                                    ? WMPSize(width: 4000, height: 4000) : canvas),
                            isResizable: resizable,
                            commands: [], hits: [], widgets: [video], geometries: [:],
                            unresolved: [], diagnostics: [], dirtyBounds: nil,
                            metrics: .init(resolvedNodeCount: 1, unresolvedNodeCount: 0,
                                           visibleBounds: nil),
                            wasBuiltOnMainThread: false)
        }
        XCTAssertNil(WMPSceneBuilder.videoBarShortfall(in: scene(resizable: false, box: 92)),
                     "Revert's vwPlayer — resizable=false, and the whole of W254")
        XCTAssertNotNil(WMPSceneBuilder.videoBarShortfall(in: scene(resizable: true, box: 92)),
                        "a resizable view still grows, so it keeps the overlay")
    }
}
