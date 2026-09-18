import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// `horizontalAlignment` / `verticalAlignment`, and the one distinction between their four values
/// that a whole window frame rests on: **`center` is not a margin.**
///
/// `right`, `bottom` and `stretch` say "hold this edge's authored distance to the parent's edge",
/// which is the delta form — a no-op at the view's own authored size, and the thing W113's
/// counter-evidence protects. `center` says the element *stays centred*, so its coordinate is
/// computed from the parent and the element's own size, and the authored coordinate on that axis is
/// not an offset into it. Reading `center` as a margin too collapsed every centred piece to the
/// parent's origin, which is W143 in `docs/wmp-skin/wmp-backlog-archive.md` § *Phase 15*.
final class WMPAlignmentTests: XCTestCase {

    private func load(wms: String, resources: [String: Data] = [:]) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]
        for (name, data) in resources.sorted(by: { $0.key < $1.key }) {
            entries.append(WMPTestArchiveEntry(name, data: data))
        }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    private func stableID(_ skin: WMPLoadedSkin, _ id: String) throws -> Int {
        try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == id }?.stableID)
    }

    private func sheet(_ width: Int, _ height: Int,
                       _ colour: (UInt8, UInt8, UInt8) = (0, 0, 0)) throws -> Data {
        try WMPSkinTestSupport.encodedImage(width: width, height: height,
            rgba: (0..<(width * height)).flatMap { _ in [colour.0, colour.1, colour.2, 255] })
    }

    private func frame(_ skin: WMPLoadedSkin, _ scene: WMPScene, _ id: String) throws -> WMPRect {
        try XCTUnwrap(scene.geometries[try stableID(skin, id)]?.absoluteFrame,
                      "\(id) resolved no geometry")
    }

    // MARK: - W143: a centred piece is centred, at every size

    /// The AlienMorph/ALX frame, reduced: a corner piece at the origin and a side-column piece that
    /// declares `verticalAlignment="center"`, **no `top`**, and nothing but its own artwork to be
    /// sized by. Every playlist, equaliser, visualisation and video window in that family is built
    /// this way, and read as a margin the column landed at `top=0` — on top of the corner, taking
    /// the window's whole title bar with it. Reported as "the playlist and eq windows are not
    /// properly constructed … there are large gaps".
    func testACentredChildIsCentredInItsParentAtTheAuthoredSize() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="389" height="247">
            <SUBVIEW id="corner" zIndex="5" backgroundImage="corner.png"/>
            <SUBVIEW id="column" zIndex="5" verticalAlignment="center" backgroundImage="column.png"/>
        </VIEW></THEME>
        """, resources: ["corner.png": try sheet(175, 76), "column.png": try sheet(175, 92)])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertEqual(try frame(skin, scene, "column").y, (247 - 92) / 2,
                       "the centred column sits at (parent − own) / 2, not at the parent's origin")
        XCTAssertNil(try frame(skin, scene, "column").intersection(try frame(skin, scene, "corner")),
                     "which is what keeps it off the title bar the corner piece draws")
    }

    /// The horizontal half, and the `.wmz` shape it comes from: `Project Gotham Racing 2` centres
    /// `f_top_stripe.png` on its title bar with `horizontalAlignment="center"` and no `left`.
    func testACentredChildIsCentredHorizontallyToo() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="301" height="328">
            <SUBVIEW id="stripe" zIndex="20" horizontalAlignment="center" backgroundImage="s.png"/>
        </VIEW></THEME>
        """, resources: ["s.png": try sheet(61, 12)])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        XCTAssertEqual(try frame(skin, scene, "stripe").x, (301 - 61) / 2)
    }

    /// Centring is a rule about the *parent*, so it holds after a resize without the authored size
    /// entering into it — `plView` is `389x247` authored and dragged to anything above its
    /// `minWidth`/`minHeight`.
    func testCentringFollowsTheParentThroughAResize() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="389" height="247">
            <SUBVIEW id="column" verticalAlignment="center" backgroundImage="column.png"/>
        </VIEW></THEME>
        """, resources: ["column.png": try sheet(175, 92)])
        let view = try XCTUnwrap(skin.views.first { $0.id == "main" }?.node.stableID)
        var overrides = WMPSceneOverrides.empty
        overrides.geometry[.init(stableID: view, property: "width")] = 700
        overrides.geometry[.init(stableID: view, property: "height")] = 450
        let scene = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "main", overrides: overrides)
        XCTAssertEqual(try frame(skin, scene, "column").y, (450 - 92) / 2)
    }

    /// Both axes are independent: a piece centred vertically and pinned right keeps the authored
    /// `left` margin on the axis it did not centre. AlienMorph's `plRightCenter` is exactly this.
    func testTheCentredAxisDoesNotDisturbTheOther() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="389" height="247">
            <SUBVIEW id="right" left="214" verticalAlignment="center"
                     horizontalAlignment="right" backgroundImage="column.png"/>
        </VIEW></THEME>
        """, resources: ["column.png": try sheet(175, 92)])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let resolved = try frame(skin, scene, "right")
        XCTAssertEqual(resolved.x, 214, "the right margin is authored and the delta is zero here")
        XCTAssertEqual(resolved.y, (247 - 92) / 2)
    }

    // MARK: - The counter-evidence: the other three values are still margins

    /// W113's rule, re-pinned beside the new one because this is the pair that can drift: a
    /// `right`-aligned child moves by the canvas minus the **authored** width, so it holds its own
    /// margin instead of being repositioned from the parent. `LostPlanet` is the case.
    func testAMarginAlignmentIsStillMeasuredFromTheAuthoredSize() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="100">
            <SUBVIEW id="edge" left="90" top="0" width="10" height="10"
                     horizontalAlignment="right" backgroundColor="#FF0000"/>
            <SUBVIEW id="tile" left="10" top="0" width="80" height="10"
                     horizontalAlignment="stretch" backgroundColor="#00FF00"/>
        </VIEW></THEME>
        """)
        let view = try XCTUnwrap(skin.views.first { $0.id == "main" }?.node.stableID)
        var overrides = WMPSceneOverrides.empty
        overrides.geometry[.init(stableID: view, property: "width")] = 160
        overrides.geometry[.init(stableID: view, property: "height")] = 100
        let scene = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "main", overrides: overrides)
        XCTAssertEqual(try frame(skin, scene, "edge").x, 150)
        XCTAssertEqual(try frame(skin, scene, "tile").width, 140,
                       "a stretch tile covers the growth; centring must not have changed this")
    }

    // MARK: - W159: a script's coordinate is anchored at the canvas it was written at

    /// **A script assignment is a plain number, and alignment carries it forward from the canvas it
    /// was written at — not from the authored one.**
    ///
    /// This is the half `WMPScriptRuntime`'s retirement rule hands off to. The runtime stops an
    /// authored `jscript:` expression taking back an address the script wrote; without a way to
    /// re-anchor, a drawer a skin slid by script would then freeze in absolute terms whenever the
    /// window resized. `xsn_sports` is the case — `visDrawer.moveTo(0, view.height-73, 400)` on a
    /// node authoring `verticalAlignment="bottom"` means "73 up from the bottom", and the corpus
    /// A/B drew that panel floating in the middle of `visView` until this landed.
    ///
    /// **Measured from the assignment, not from the markup.** Taking the delta from the authored
    /// size instead moved 15 default-state views that had no business moving — `Catwoman`'s video
    /// settings drawer, the Alienware/ALX `videoView` family, `Scooby-Doo_2`'s info panel — because
    /// those skins size their own view by script at load, so the authored-size delta is not zero
    /// there and their panels slid open on sight.
    func testAScriptedCoordinateReanchorsFromTheCanvasItWasAssignedAt() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="drawer" left="0" top="127" width="140" height="130"
                     verticalAlignment="bottom" backgroundColor="#FF0000"/>
            <SUBVIEW id="pinned" left="0" top="127" width="140" height="10"
                     backgroundColor="#00FF00"/>
        </VIEW></THEME>
        """)
        let view = try XCTUnwrap(skin.views.first { $0.id == "main" }?.node.stableID)
        let drawer = try stableID(skin, "drawer")
        let pinned = try stableID(skin, "pinned")
        var overrides = WMPSceneOverrides.empty
        // The view is 300 tall now; both coordinates were written by script while it was 200.
        overrides.geometry[.init(stableID: view, property: "height")] = 300
        for id in [drawer, pinned] {
            overrides.geometry[.init(stableID: id, property: "top")] = 127
            overrides.scriptAssignedGeometry[.init(stableID: id, property: "top")] =
                WMPSize(width: 200, height: 200)
        }
        let scene = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "main", overrides: overrides)
        XCTAssertEqual(try frame(skin, scene, "drawer").y, 227,
                       "127 + the 100 the view grew by since the assignment: still 73 up from the "
                       + "bottom, which is what the handler asked for")
        XCTAssertEqual(try frame(skin, scene, "pinned").y, 127,
                       "no alignment, so nothing re-anchors it — a script number behaves as a "
                       + "markup literal would")
    }

    /// **Nothing outranks centring on the centred axis — not an expression, and not a coordinate
    /// a script assigned.** The `isComputed` guard was carried onto `center` alongside the other
    /// three values when W143 landed, justified by WoW's `left="JScript:view.width-202"` beside an
    /// alignment; WoW's alignment on that node is `right`, and a decoded scan of the 180-archive
    /// corpus puts **3** centred nodes with an authored expression on the centred axis, all three
    /// in `Ice`, against 285 + 91 that author no coordinate at all. So the guard protected nothing
    /// it was written for and cost every drawer a skin slides by script: `xsn_sports` opens its
    /// video and visualisation drawers with `visDrawer.moveTo(0, view.height-73, 400)`, and the
    /// `0` is not a position — `moveTo` takes both axes and the horizontal one is the author's way
    /// of saying "unchanged", because the drawer is centred. Honouring it pinned a 141-wide drawer
    /// to the window's left edge while its own cover artwork stayed centred: reported as two
    /// drawers, one growing "to double size on the border", with the settings panel inside the
    /// misplaced one showing through the video window and no reachable tab to shut it. W144.
    ///
    /// Ice is the counter-evidence that turned out to agree: it authors
    /// `left="jscript:view.width-180"` on the 313-wide `Pl-xp.bmp` bar its playlist and
    /// visualisation windows hang along the bottom, which ran the bar off the right edge and left
    /// the bottom-left corner empty. Centred, it sits under the window.
    func testCentringOutranksBothAnExpressionAndAScriptedCoordinate() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="389" height="247">
            <SUBVIEW id="expressed" top="jscript:view.height-100" verticalAlignment="center"
                     backgroundImage="column.png"/>
            <SUBVIEW id="scripted" verticalAlignment="center" backgroundImage="column.png"/>
        </VIEW></THEME>
        """, resources: ["column.png": try sheet(175, 92)])
        var overrides = WMPSceneOverrides.empty
        overrides.geometry[.init(stableID: try stableID(skin, "scripted"), property: "top")] = 12
        let scene = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "main", overrides: overrides)
        XCTAssertEqual(try frame(skin, scene, "expressed").y, (247 - 92) / 2,
                       "the expression's 147 does not survive a centred axis")
        XCTAssertEqual(try frame(skin, scene, "scripted").y, (247 - 92) / 2,
                       "and neither does a coordinate the skin's script assigned")
    }

    /// The other axis, and the shape the report came in as: a centred drawer, the cover artwork it
    /// has to line up with, and a `moveTo` that slides it vertically while passing `0` for `left`.
    /// Both pieces must land on the same x or the skin draws two drawers.
    func testAScriptedSlideKeepsACentredDrawerUnderItsCover() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="vis" width="379" height="338">
            <SUBVIEW id="cover" top="241" width="141" height="24"
                     horizontalAlignment="center" backgroundColor="#00FF00"/>
            <SUBVIEW id="drawer" top="jscript:view.height-123" width="141" height="131"
                     verticalAlignment="bottom" horizontalAlignment="center"
                     backgroundColor="#0000FF"/>
        </VIEW></THEME>
        """)
        var overrides = WMPSceneOverrides.empty
        let drawer = try stableID(skin, "drawer")
        overrides.geometry[.init(stableID: drawer, property: "left")] = 0
        overrides.geometry[.init(stableID: drawer, property: "top")] = 265
        let scene = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "vis", overrides: overrides)
        XCTAssertEqual(try frame(skin, scene, "drawer").x, (379 - 141) / 2,
                       "moveTo's 0 does not un-centre the drawer")
        XCTAssertEqual(try frame(skin, scene, "drawer").x, try frame(skin, scene, "cover").x,
                       "which is the only way it stays under its own cover")
        XCTAssertEqual(try frame(skin, scene, "drawer").y, 265,
                       "while the axis the skin actually slid still takes the scripted value")
    }

    // MARK: - W212: reading a centred piece's coordinate back out

    /// **A `wmpprop:` read of another element's geometry answers where that element *is*.**
    ///
    /// One hop on from the rule above, and the half of it that had no answer. The same
    /// Alienware/ALX frame that hangs its side columns off a centred piece states the tiles above
    /// and below them as `top="wmpprop:plLeftCenter.top"` — and centring computes a coordinate the
    /// markup does not carry, so a resolver reading the target's *authored* attribute answered
    /// **0** and both tiles painted at the top of the window, over the corner pieces. The white
    /// filler those bitmaps carry for the skin's own list to cover then landed in the caption
    /// band's right end, on every NullPlayer window wearing the borrowed frame.
    ///
    /// It only ever showed there. WMP answers the read from the live object model and the skin's
    /// own window does the same through the script runtime, so the one surface built without a
    /// runtime — `WMPHostedFrameTemplate`'s private builder — was the one that had no source for
    /// it, which is why three rounds of artwork fixes changed nothing the reporter could see.
    func testAWmppropGeometryReadAnswersWhereTheTargetIsDrawn() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="pl" width="531" height="291">
            <SUBVIEW id="corner" zIndex="5" backgroundImage="corner.png"/>
            <SUBVIEW id="centre" zIndex="10" verticalAlignment="center" backgroundImage="mid.png"/>
            <SUBVIEW id="tile" zIndex="6" top="wmpprop:centre.top" backgroundImage="tile.png"/>
        </VIEW></THEME>
        """, resources: ["corner.png": try sheet(99, 60), "mid.png": try sheet(99, 56),
                         "tile.png": try sheet(99, 51)])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "pl")

        XCTAssertEqual(try frame(skin, scene, "tile").y, (291 - 56) / 2,
                       "the tile meets the centre piece it names, wherever centring put it")
        XCTAssertNil(try frame(skin, scene, "tile").intersection(try frame(skin, scene, "corner")),
                     "which is what keeps its baked-in white filler off the caption band")
    }

    /// The target is walked **after** the node that reads it — the layout walk is in paint order,
    /// and this family states the tile at `zIndex=6` against a centre piece at `zIndex=10`. So the
    /// answer cannot come from a resolved frame and is computed from the centring instead, which is
    /// the only coordinate the static resolver reads wrong. Pinned separately because the two
    /// sources are different code paths and only this one has an ordering to get wrong.
    func testTheReadIsAnsweredEvenWhenTheTargetIsPaintedLater() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="pl" width="531" height="291">
            <SUBVIEW id="early" zIndex="1" top="wmpprop:late.top" backgroundImage="tile.png"/>
            <SUBVIEW id="late" zIndex="50" verticalAlignment="center" backgroundImage="mid.png"/>
        </VIEW></THEME>
        """, resources: ["mid.png": try sheet(99, 56), "tile.png": try sheet(99, 51)])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "pl")
        XCTAssertEqual(try frame(skin, scene, "early").y, (291 - 56) / 2)
    }

    /// And the case that must keep its authored answer: a target that states its own coordinate is
    /// read at that coordinate, centring or not. Nothing here is entitled to move a piece whose
    /// author placed it.
    func testAWmppropReadOfAnAuthoredCoordinateIsUnchanged() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="pl" width="531" height="291">
            <SUBVIEW id="anchor" zIndex="10" top="118" backgroundImage="mid.png"/>
            <SUBVIEW id="tile" zIndex="6" top="wmpprop:anchor.top" backgroundImage="tile.png"/>
        </VIEW></THEME>
        """, resources: ["mid.png": try sheet(99, 56), "tile.png": try sheet(99, 51)])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "pl")
        XCTAssertEqual(try frame(skin, scene, "tile").y, 118)
    }

    // MARK: - W226: a hidden element still has a place, and a bound extent is not a baseline

    /// **A geometry binding reads where the target *is*, and a hidden target is somewhere.**
    ///
    /// `Compact` sizes its visualisation pane with `<subview id="svVisual"
    /// height="wmpprop:video1.height">`, and `video1` is `visible="false"` for the whole of audio
    /// playback. A hidden node was never walked, so it had no resolved frame and the read fell back
    /// to the markup — 240, the height the window was *born* at. Stretching the window grew the
    /// pane's width and left its height where it started, so the visualizer hosted inside it never
    /// followed the drag. Reported as "when you stretch the window the visualization does not
    /// follow the stretch".
    ///
    /// The second half is in the same picture: the pane's own extent now follows the window, and
    /// its children measure their alignment from `ownAuthoredSize`. Reading the grown extent back
    /// as the baseline makes that delta zero, so the strip under the visualizer stays where it was
    /// authored — which is how the surface can grow while everything inside it does not.
    func testAPaneBoundToAHiddenSiblingFollowsTheResizeAndCarriesItsChildren() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="320" height="240">
            <SUBVIEW id="pane" width="320" height="240"
                     horizontalAlignment="stretch" verticalAlignment="stretch">
                <SUBVIEW id="film" visible="false" width="320" height="240"
                         horizontalAlignment="stretch" verticalAlignment="stretch"
                         backgroundColor="#FF00FF"/>
                <SUBVIEW id="vis" zIndex="2" width="320" height="wmpprop:film.height"
                         horizontalAlignment="stretch" backgroundColor="#000000">
                    <SUBVIEW id="strip" top="220" width="320" height="20"
                             verticalAlignment="bottom" backgroundColor="#00FF00"/>
                </SUBVIEW>
            </SUBVIEW>
        </VIEW></THEME>
        """)
        let view = try XCTUnwrap(skin.views.first { $0.id == "main" }?.node.stableID)
        var overrides = WMPSceneOverrides.empty
        overrides.geometry[.init(stableID: view, property: "height")] = 462
        let scene = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "main", overrides: overrides)

        XCTAssertEqual(try frame(skin, scene, "vis").height, 462,
                       "the pane follows the hidden element it is bound to, which stretched")
        XCTAssertEqual(try frame(skin, scene, "strip").y, 442,
                       "220 + the 222 the pane grew by: the strip rides the pane's bottom edge "
                       + "instead of freezing at the authored margin")
    }

    /// And the hidden element is **measured, not drawn**. It answers where it is and contributes
    /// nothing else: no paint, no hit target, no widget, no children.
    func testAMeasuredHiddenElementPaintsNothing() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="320" height="240">
            <SUBVIEW id="film" visible="false" width="320" height="240" backgroundColor="#FF00FF">
                <SUBVIEW id="inner" width="10" height="10" backgroundColor="#FF00FF"/>
            </SUBVIEW>
            <SUBVIEW id="vis" width="320" height="wmpprop:film.height" backgroundColor="#000000"/>
        </VIEW></THEME>
        """)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let magenta = WMPColor(red: 255, green: 0, blue: 255)
        XCTAssertNotNil(scene.geometries[try stableID(skin, "film")],
                        "it was measured, or the binding below could not have been answered")
        XCTAssertNil(scene.geometries[try stableID(skin, "inner")],
                     "a hidden element's children are not walked")
        XCTAssertFalse(scene.commands.contains { $0.paint == .fill(magenta) },
                       "and nothing it declares reaches the picture")
        XCTAssertEqual(try frame(skin, scene, "vis").height, 240)
    }

    /// The other side of the same rule: a hidden element **nothing reads a coordinate off** is not
    /// measured at all. Only the graph asking where it is buys it a frame — every other hidden node
    /// in the corpus leaves the walk exactly where it did before.
    func testAHiddenElementNobodyBindsToIsNotMeasured() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="320" height="240">
            <SUBVIEW id="film" visible="false" width="320" height="240" backgroundColor="#FF00FF"/>
        </VIEW></THEME>
        """)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        XCTAssertNil(scene.geometries[try stableID(skin, "film")])
    }

    /// **A script-assigned extent is still the baseline, and that is W225's rule.** The runtime
    /// writes a geometry override for both a handler's assignment and its own re-evaluation of an
    /// authored expression; only the first is the author stating a size deliberately, and only the
    /// first may be measured from. `scriptAssignedGeometry` is what separates them.
    func testAScriptAssignedExtentIsStillTheBaselineForItsChildren() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="320" height="240">
            <SUBVIEW id="pane" width="320" height="240" backgroundColor="#000000">
                <SUBVIEW id="strip" top="220" width="320" height="20"
                         verticalAlignment="bottom" backgroundColor="#00FF00"/>
            </SUBVIEW>
        </VIEW></THEME>
        """)
        let pane = try stableID(skin, "pane")
        var overrides = WMPSceneOverrides.empty
        overrides.geometry[.init(stableID: pane, property: "height")] = 300
        overrides.scriptAssignedGeometry[.init(stableID: pane, property: "height")] =
            WMPSize(width: 320, height: 240)
        let scene = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "main", overrides: overrides)
        XCTAssertEqual(try frame(skin, scene, "strip").y, 220,
                       "the handler sized the pane to 300 and its children measure from that, so "
                       + "the strip keeps the margin the script left it at")
    }

    /// **A script-assigned extent on a *nested* node must not have the resize added to it (W227).**
    ///
    /// The re-anchoring the test above exercises is the growth of the element's **parent** since the
    /// assignment, and only a child of the view root has a parent whose extent the canvas is. Deeper
    /// than that the fallback was the growth since the *markup*, added on top of a number the
    /// handler measured at the size the window is already at — so the resize was counted twice.
    ///
    /// `Compact` is the case it was reported on. `svBanner`'s `visible_onchange` writes
    /// `svScreen.height = svScreenOuter.height - svScreen.top` the first time a track plays, and its
    /// `<EFFECTS>` is `height="jscript:svScreen.height - top"` under that. Stretch the player to
    /// 620x573 and *then* start playing: both wrote the right number for that canvas, 435 and 410,
    /// and both were drawn 195 taller — 195 being 573 − 378, the growth since the authored size. The
    /// visualizer spilled out of the window over the transport strip.
    func testANestedScriptAssignedExtentIsNotRegrownByTheResize() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="320" height="240">
            <SUBVIEW id="outer" width="320" height="240" verticalAlignment="stretch"
                     horizontalAlignment="stretch" backgroundColor="#000000">
                <SUBVIEW id="pane" width="320" height="200" verticalAlignment="stretch"
                         horizontalAlignment="stretch" backgroundColor="#00FF00"/>
            </SUBVIEW>
        </VIEW></THEME>
        """)
        let pane = try stableID(skin, "pane")
        var overrides = WMPSceneOverrides.empty
        // The window is already at 320x300 and the handler measured 260 against it.
        overrides.geometry[.init(stableID: pane, property: "height")] = 260
        overrides.scriptAssignedGeometry[.init(stableID: pane, property: "height")] =
            WMPSize(width: 320, height: 300)
        let scene = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "main", requestedSize: WMPSize(width: 320, height: 300),
                   overrides: overrides)
        XCTAssertEqual(try frame(skin, scene, "pane").height, 260,
                       "the handler's own answer for this canvas, not that plus the 60 the view "
                       + "grew since its markup")
    }

}
