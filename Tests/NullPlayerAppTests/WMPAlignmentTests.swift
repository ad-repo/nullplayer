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

    /// **An expression that already reads `view.width` is not centred on top of its own answer.**
    /// WoW authors `left="JScript:view.width-202"` beside an alignment on the same node, and
    /// counting the resize twice threw its right-hand chrome off the canvas. The `isComputed` guard
    /// covers the centred axis for the same reason it covers the other three — including a
    /// coordinate a script wrote, which is an explicit answer and not a layout hint.
    func testAComputedCoordinateOutranksCentring() async throws {
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
        XCTAssertEqual(try frame(skin, scene, "expressed").y, 147,
                       "the expression's own answer stands; centring would have said 77")
        XCTAssertEqual(try frame(skin, scene, "scripted").y, 12,
                       "so does a coordinate the skin's script assigned")
    }
}
