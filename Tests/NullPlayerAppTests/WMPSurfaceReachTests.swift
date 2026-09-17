import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// W213 — the three rules a `.wmz` visualizer needs before the player around it can be used, all
/// reported together on 2026-09-17 against `circle`:
///
/// > *"the circle skin has multiple issues, it cannt be dragged and looks to be missing parts of
/// > the UI. also the vizulization opens below it"*
///
/// Neither is a drawing defect and no render dump shows either, which is why they stood: the scene
/// `circle` builds is correct in every capture. What was wrong was *where the hosted surface may be
/// clicked* and *what size the window was laid out at*.
///
/// 1. **A hosted surface owns its rectangle for input.** `circle`'s `<EFFECTS>` is
///    `jscript:vMain.width` by `jscript:vMain.height` — the entire player — and it wires
///    `onClick="previous();"`. `WMPHitTester` already ranks a surface behind every real control
///    (`Alienware Invader`, `Radio`, `XBOX`), and that is enough while the surface is a small lens;
///    it is not enough when the surface *is* the window, because the pixels in between are not
///    controls at all, they are the skin's body. Every press on it answered "visualization" and
///    never reached `beginWindowDrag`, so the window could not be moved anywhere on screen.
/// 2. **A `.wmz` window's size is the skin's.** `WindowManager.tightenClassicCenterStackIfNeeded`
///    is Classic's stack repair and `isRunningModernUI` answers false for the WMP controller, so it
///    ran over a borderless skin window and grew it to `Skin.mainWindowSize.height`. On the mouse-up
///    of the very first click — because a press on bare artwork is a window drag — `circle`'s 192x82
///    player became **192x145**, and the 63 px that were never the skin's filled with its own
///    `<EFFECTS height="jscript:vMain.height">`: the "visualization opens below it" of the report.
///
/// **And one rule that was built and is not here**, kept as the third section below because the
/// corpus agreed with it and the screen did not: confining the surface to a *sibling's*
/// `clippingColor`. See `testASiblingsClippingColourIsNotTheWindowsOutline`.
final class WMPSurfaceReachTests: XCTestCase {

    // MARK: - Fixtures

    private static let black: [UInt8] = [0, 0, 0, 255]
    private static let red: [UInt8] = [255, 0, 0, 255]
    private static let magenta: [UInt8] = [255, 0, 255, 255]

    private func load(wms: String, images: [String: Data] = [:]) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]
        entries += images.map { WMPTestArchiveEntry($0.key, data: $0.value) }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    /// `visfield.bmp` in miniature: a field with both of the keys a `.wmz` container declares over
    /// its own artwork, and an opaque body.
    ///
    /// - column 0 is `clippingColor` — the field's matte, which on `circle` is where its **track
    ///   number** is cut out of the visualizer and is emphatically not the edge of the window;
    /// - column 1 is `transparencyColor` — the hole the visualizer shows through;
    /// - columns 2-7 are opaque body.
    private func visField() throws -> Data {
        var rgba: [UInt8] = []
        for _ in 0..<8 {
            for column in 0..<8 {
                switch column {
                case 0: rgba += Self.red
                case 1: rgba += Self.magenta
                default: rgba += Self.black
                }
            }
        }
        return try WMPSkinTestSupport.encodedImage(width: 8, height: 8, rgba: rgba)
    }

    /// The `circle` shape: a view with no artwork of its own, a full-view `<EFFECTS zIndex="-1">`,
    /// and the keyed field that covers it, declared after it.
    private func circleShaped(viewAttributes: String = "") async throws -> (WMPLoadedSkin, WMPScene) {
        let skin = try await load(wms: """
        <THEME><VIEW id="vMain" width="8" height="8" backgroundColor="none" \(viewAttributes)>
            <EFFECTS id="visEffects" zIndex="-1" left="0" top="0" width="8" height="8"
                     onClick="previous();"/>
            <SUBVIEW id="field" backgroundImage="visfield.bmp"
                     backgroundColor="none" transparencyColor="#FF00FF" clippingColor="#FF0000"/>
        </VIEW></THEME>
        """, images: ["visfield.bmp": try visField()])
        return (skin, try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "vMain"))
    }

    private func effectsHit(_ scene: WMPScene) throws -> WMPHitMetadata {
        try XCTUnwrap(scene.hits.first { $0.kind.caseInsensitiveCompare("effects") == .orderedSame },
                      "the surface has a hit entry at all")
    }

    /// What the app asks on `mouseDown`: nil is "no control here", which is the window drag.
    private func target(_ scene: WMPScene, x: CGFloat, y: CGFloat) -> WMPHitTarget? {
        WMPHitTester(hits: scene.hits).hitTest(WMPPoint(x: x, y: y))
    }

    // MARK: - 1: where a hosted surface may be clicked

    /// The reported defect, and the reason a press on the body must fall through: the skin painted
    /// over the surface there, so there is no visualizer under the pointer to click.
    func testAPressOnArtworkOverTheSurfaceIsNotTheSurface() async throws {
        let (_, scene) = try await circleShaped()

        XCTAssertNil(target(scene, x: 5.5, y: 4.5),
                     "the body is the skin's artwork, and a press on it drags the window")
        XCTAssertEqual(target(scene, x: 1.5, y: 4.5)?.kind, "effects",
                       "the keyed hole is the visualizer, and a press there is still its onClick")
    }

    /// The guard that keeps every surface the corpus does reach: coverage only ever subtracts where
    /// something is actually painted. A surface with nothing declared over it keeps its whole rect,
    /// which is what it had before this rule existed.
    func testASurfaceWithNothingOverItKeepsItsWholeRect() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="vis" width="8" height="8" backgroundColor="none">
            <EFFECTS id="visEffects" left="0" top="0" width="8" height="8" onClick="next();"/>
        </VIEW></THEME>
        """)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "vis")

        XCTAssertNil(try effectsHit(scene).coverage, "no occluder, no mask")
        XCTAssertEqual(target(scene, x: 4.5, y: 4.5)?.kind, "effects")
    }

    /// **`clippingColor` keys a container's shape, never its artwork (W169) — so the artwork over a
    /// visualizer is opaque where the shape cuts it away, and only the shape says otherwise.**
    ///
    /// This is the half that decides the corpus rather than the reported skin. `cerulean`'s
    /// `face.bmp` is fully opaque `#FF0000` across its own lens and the container's region mask is
    /// what opens the hole; read without the mask, the artwork buries the visualizer. Measured with
    /// `WMP_RENDER_OCCLUDED=1` over the 184 installed archives before this guard was added:
    /// `cerulean`, `aoe`, `claw`, `gadget` and `pharaoh` each lost their surface outright — five
    /// visualizers that are plainly on screen. With it, the corpus's `rect-only` set is identical to
    /// the baseline and 20 surfaces gain a mask.
    func testAMaskedCommandOccludesOnlyWhereItsShapeKeepsIt() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="vis" width="8" height="8" backgroundColor="none">
            <SUBVIEW id="body" backgroundImage="visfield.bmp" clippingColor="#FF0000">
                <EFFECTS id="visEffects" zIndex="-1" left="0" top="0" width="8" height="8"
                         onClick="next();"/>
            </SUBVIEW>
        </VIEW></THEME>
        """, images: ["visfield.bmp": try visField()])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "vis")

        XCTAssertNil(target(scene, x: 5.5, y: 4.5), "opaque body, and the shape keeps it")
        XCTAssertEqual(target(scene, x: 0.5, y: 4.5)?.kind, "effects",
                       "the container's own shape cuts its artwork away here, so the surface shows")
    }

    /// **A windowed surface is a real child window and nothing the skin paints is drawn over it**
    /// (W144), so its rect stays live whatever the markup declares afterwards. 17 corpus skins say
    /// `windowed="true"`; `xsn_sports` is the worked case.
    func testAWindowedSurfaceKeepsItsWholeRectUnderArtwork() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="vis" width="8" height="8" backgroundColor="none">
            <EFFECTS id="visEffects" zIndex="-1" left="0" top="0" width="8" height="8"
                     windowed="true" onClick="next();"/>
            <SUBVIEW id="field" backgroundImage="visfield.bmp" transparencyColor="#FF00FF"/>
        </VIEW></THEME>
        """, images: ["visfield.bmp": try visField()])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "vis")

        XCTAssertNil(try effectsHit(scene).coverage)
        XCTAssertEqual(target(scene, x: 5.5, y: 4.5)?.kind, "effects")
    }

    // MARK: - 2: what the silhouette rule must not be

    /// **A sibling's `clippingColor` is not the window's outline, and `circle` is the case that
    /// says so.** Confining the surface to `visfield.bmp`'s keep region was built, measured clean
    /// across the corpus, and reported wrong on screen: the 4,022 px it keys away are the
    /// visualizer's own field, and the skin's track-number readout lives in them. `sHundreds`,
    /// `sTens` and `sOnes` cycle ten `num*.bmp` that are made **entirely** of the two key colours —
    /// a magenta glyph cut out of a red matte — so the digit is whatever shows through, and what
    /// shows through is the surface. Clip it there and the readout goes dark.
    ///
    /// The guard is simply that a container shaping a surface has to be one the surface is inside:
    /// `groundShapeStack` is ancestors, and W205's is the sibling *behind*. A sibling declared after
    /// it contributes nothing.
    func testASiblingsClippingColourIsNotTheWindowsOutline() async throws {
        let (_, scene) = try await circleShaped()
        let widget = try XCTUnwrap(scene.widgets.first { $0.kind == .effects })

        XCTAssertNil(widget.clippingShape,
                     "the field's matte is the visualizer's field, not the edge of the window")
        XCTAssertNotNil(target(scene, x: 0.5, y: 4.5),
                        "and the surface is still reachable in it, which is what the readout needs")
    }

    // MARK: - 3: what the visualizer stands on

    /// **A visualizer with no backdrop is a window with holes in it (W213).** `circle` is the case:
    /// no ancestor states a shape, so the rect took no ground, and everything its artwork keys away
    /// showed the desktop — the fringe round the dial, the three track-number panels, the whole
    /// right-hand field. WMP paints black behind a visualization; so do we now.
    func testASurfaceWithNoShapeInScopeStillGetsItsBackdrop() async throws {
        let (_, scene) = try await circleShaped()

        let ground = try XCTUnwrap(scene.effectsGrounds.first, "the visualizer stands on something")
        XCTAssertNil(ground.shape, "the rect itself — no container stated a window shape")
        XCTAssertEqual(ground.frame, WMPRect(x: 0, y: 0, width: 8, height: 8))
        XCTAssertEqual(ground.color, WMPColor(red: 0, green: 0, blue: 0), "WMP's own backdrop")
    }

    /// **The permission is a `clippingColor` on a full-canvas child, and `Plus! Plasma Ball` is why.**
    /// It shapes itself with `transparencyColor` alone and never names a matte; grounding its rect
    /// turns 40,334 px black outside its silhouette. A skin that names both keys over a canvas-sized
    /// field has said which is the hole and which is the matte, and both are the visualizer's.
    func testAFieldThatNamesNoMatteGrantsNoBackdrop() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="vMain" width="8" height="8" backgroundColor="none">
            <EFFECTS id="visEffects" zIndex="-1" left="0" top="0" width="8" height="8"/>
            <SUBVIEW id="field" backgroundImage="visfield.bmp"
                     backgroundColor="none" transparencyColor="#FF00FF"/>
        </VIEW></THEME>
        """, images: ["visfield.bmp": try visField()])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "vMain")

        XCTAssertTrue(scene.effectsGrounds.isEmpty,
                      "transparencyColor alone is a silhouette, and a fill would spill outside it")
    }

    // MARK: - 3: the size a view is laid out at

    /// `resizAble` is the corpus's dominant spelling and `resizable` the other; absent is false, and
    /// a false answer is what stops the frame store's record reaching a fixed player.
    func testAuthoredResizableReadsBothSpellingsAndDefaultsToFalse() async throws {
        let skin = try await load(wms: """
        <THEME>
            <VIEW id="fixed" width="8" height="8"/>
            <VIEW id="spelledOne" width="8" height="8" resizAble="true"/>
            <VIEW id="spelledTwo" width="8" height="8" resizable="TRUE"/>
            <VIEW id="saysNo" width="8" height="8" resizAble="false"/>
        </THEME>
        """)

        XCTAssertFalse(WMPMainWindowController.authoredResizable(in: skin, viewID: "fixed"))
        XCTAssertTrue(WMPMainWindowController.authoredResizable(in: skin, viewID: "spelledOne"))
        XCTAssertTrue(WMPMainWindowController.authoredResizable(in: skin, viewID: "spelledTwo"))
        XCTAssertFalse(WMPMainWindowController.authoredResizable(in: skin, viewID: "saysNo"))
    }

    /// **The window's floor is the scene's, and a scene smaller than the app's no-skin player is
    /// not forced up to it (W213).** `configureWindow` set `minSize` to `unskinnedSize` — 440x170 —
    /// and never moved it, so `circle`'s 192x82 player was one edge drag from being snapped to a
    /// window four times its size with the scene left behind at 192x82. AppKit enforces `minSize`
    /// *after* every delegate answers, so refusing the resize is not enough on its own.
    ///
    /// The detector this pins is `WMPWindowSizeLimits`, shared with `WMP_RENDER_LIMITS` so the probe
    /// and the app cannot answer differently. **483 of the corpus's 630 views are below the
    /// unskinned floor in at least one axis**, which is the size of the exposure.
    func testASmallFixedViewGetsItsOwnFloorAndNotTheUnskinnedPlayers() async throws {
        let (_, scene) = try await circleShaped()
        let limits = WMPWindowSizeLimits.forScene(scene)

        XCTAssertEqual(limits.minimum, scene.canvasSize, "a fixed view is pinned to its canvas")
        XCTAssertEqual(limits.maximum, scene.canvasSize, "at both ends")
        XCTAssertNil(limits.breakage(for: scene.canvasSize), "so nothing forces the window")

        // And the detector bites: the floor the app used to carry would force this window.
        let unskinned = WMPWindowSizeLimits(
            minimum: WMPSize(width: WMPMainWindowController.unskinnedSize.width,
                             height: WMPMainWindowController.unskinnedSize.height),
            maximum: nil)
        XCTAssertEqual(unskinned.breakage(for: scene.canvasSize), .belowFloor,
                       "a check that cannot fail is not a check")
    }

    /// A resizable view keeps the range it authored — the pin is only for a view that declares none.
    func testAResizableViewKeepsItsAuthoredRange() async throws {
        let (_, scene) = try await circleShaped(viewAttributes: #"resizAble="true" maxWidth="40""#)
        let limits = WMPWindowSizeLimits.forScene(scene)

        XCTAssertEqual(limits.minimum, WMPSize(width: 8, height: 8))
        XCTAssertEqual(limits.maximum?.width, 40)
        XCTAssertNil(limits.breakage(for: scene.canvasSize))
    }

    /// **The builder still honours any size it is handed, and must.** The gate is the controller's,
    /// because the same parameter carries two different questions: *the window is this size*, and
    /// *render this donor view at our window's size* for a hosted frame (W209). Pinning it in the
    /// builder broke every fixed donor in the corpus, which is what this test records.
    func testTheBuilderStillLaysAFixedViewOutAtAnyRequestedSize() async throws {
        let (skin, _) = try await circleShaped()
        let grown = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "vMain", requestedSize: WMPSize(width: 8, height: 14))

        XCTAssertEqual(grown.canvasSize, WMPSize(width: 8, height: 14))
        XCTAssertFalse(grown.isResizable, "and it still reports that the user may not do this")
    }
}
