import Foundation
import XCTest
@testable import NullPlayer

/// **W199 — a container's `backgroundColor` fill and its `backgroundImage` are one layer, and the
/// container's keys apply to the composite.**
///
/// Reported against `pharaoh` on 2026-09-16 as three defects, two of which are this one:
/// *"first is w199 … also no visualisation displays"*. The fill was painted as a bare rectangle
/// under the keyed artwork, so it filled in every hole that artwork cuts, and the two holes mean
/// opposite things:
///
/// - the `clippingColor` matte is **outside the window**, so the player drew as an opaque slab
///   where WMP draws a silhouette — `sphinx.bmp` carries 53,252 px of `#FF0000` and all of them
///   came back black;
/// - the `transparencyColor` hole is **where something behind shows through**, and on this idiom
///   that something is always the visualizer: five of the population's nine archives hang an
///   `<EFFECTS zIndex="-1">` under the hole, within 2 px of its bounds. `pharaoh`'s surface was
///   live and hosted the whole time (`ProjectM … viewport 174x148`, which is its 87x74 rect at 2x)
///   and 1,608 px of black fill sat on top of it.
///
/// **The population is 10 nodes in 9 archives** — a container declaring a `backgroundColor` other
/// than `none`, at least one key, and a background image — measured over the 185 installed
/// archives with a `WMPTextDecoder`-shaped decode (158 UTF-16, 146 cp1252, 89 UTF-8, 9 UTF-8-BOM):
/// `Asimov_Radio`, `Nautical`, `anime`, `aoe`, `bluegrid`, `cerulean`, `claw`, `gadget` and
/// `pharaoh` twice. `aoe`, `bluegrid`, `claw`, `gadget` and `pharaoh` are the five with a
/// visualizer under the hole, and each rendered a fully opaque rectangle before this.
///
/// **`pharaoh` states the control inside its own archive**: `vRos` is the same markup with
/// `backgroundColor="none"`, and it clipped correctly throughout — 1,462 transparent px, exactly
/// `rosetta.bmp`'s `#FF0000` count. The fill was the only difference.
///
/// `cerulean` used to be a named exemption in `WMPSceneBuilder` — a one-skin `isCeruleanFace`
/// predicate whose comment asserted the same pattern was *intentional* in `claw`, `gadget` and
/// `pharaoh`. It is not; the general rule subsumes the exemption, and cerulean's rendered PNG is
/// byte-identical across the change while its command count goes 12 → 13.
///
/// The two guards carry named counter-evidence and each has a test below: `Gorillaz` for the tiled
/// swatch, and any container whose artwork does not cover its frame.
final class WMPContainerFillClipTests: XCTestCase {

    // MARK: - Fixtures

    private static let matte: [UInt8] = [255, 0, 0, 255]        // clippingColor  — outside the window
    private static let hole: [UInt8] = [255, 0, 255, 255]       // transparencyColor — the vis shows here
    private static let body: [UInt8] = [0x40, 0x80, 0xC0, 255]  // the artwork itself

    /// `sphinx.bmp` in miniature: an 8x8 picture whose left column is the window matte, whose 2x2
    /// block at (3,3) is a keyed hole, and whose remaining pixels are opaque artwork.
    private static func region(row: Int, column: Int) -> [UInt8] {
        if column == 0 { return matte }
        if (3...4).contains(row) && (3...4).contains(column) { return hole }
        return body
    }

    private func artwork(width: Int = 8, height: Int = 8) throws -> Data {
        var rgba: [UInt8] = []
        for row in 0..<height {
            for column in 0..<width { rgba += Self.region(row: row, column: column) }
        }
        return try WMPSkinTestSupport.encodedImage(width: width, height: height, rgba: rgba)
    }

    /// The `Gorillaz` tile: one flat colour, small, and keyed by the colour it is made of.
    private func swatch() throws -> Data {
        try WMPSkinTestSupport.encodedImage(
            width: 2, height: 2, rgba: Array(repeating: Self.matte, count: 4).flatMap { $0 })
    }

    private func load(wms: String, images: [String: Data]) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]
        entries += images.map { WMPTestArchiveEntry($0.key, data: $0.value) }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    private func renderer(for skin: WMPLoadedSkin) -> WMPRenderer {
        WMPRenderer(imageStore: WMPImageStore(provider: skin.archive))
    }

    /// The container's own `.fill` command, which is the only thing any of these tests is about.
    private func fillCommand(_ scene: WMPScene, nodeID: String) throws -> WMPPaintCommand {
        try XCTUnwrap(scene.commands.first {
            $0.nodeID == nodeID && { if case .fill = $0.paint { return true } else { return false } }($0)
        }, "\(nodeID) emits a background fill")
    }

    /// `pharaoh`'s `sSphinx`, to scale: a filled, keyed container with its visualizer behind the
    /// hole and `zIndex="-1"` putting it there.
    private let pharaohIdiom = """
    <THEME><VIEW id="main" width="8" height="8" backgroundColor="none">
        <SUBVIEW id="sSphinx" backgroundImage="sphinx.png" backgroundColor="black"
                 clippingColor="#FF0000" transparencyColor="#FF00FF">
            <EFFECTS id="visSphinx" zIndex="-1" left="3" top="3" width="2" height="2"/>
        </SUBVIEW>
    </VIEW></THEME>
    """

    /// The same container with no `<EFFECTS>` in it, for the pixel assertions. A scene that hosts
    /// one is **two rasters** either side of `WMPScene.effectsCommandSplitIndex` (W139) and
    /// `render(scene:).image` is only the layer below the surface — the container's keyed artwork
    /// is authored above it and lands in `overlayImage`. Reading one raster of a split scene as if
    /// it were the window is how a correct render reads as a missing one.
    private let pharaohIdiomWithoutTheSurface = """
    <THEME><VIEW id="main" width="8" height="8" backgroundColor="none">
        <SUBVIEW id="sSphinx" backgroundImage="sphinx.png" backgroundColor="black"
                 clippingColor="#FF0000" transparencyColor="#FF00FF"/>
    </VIEW></THEME>
    """

    // MARK: - The rule

    /// Both keys, and the *node's own* artwork: the fill may paint only where the composite is
    /// opaque. Unlike `groundShape`, which answers *where the window is* and must never read a hole
    /// as a matte, this answers *where the composite is opaque* — and there a hole is as
    /// transparent as the matte around it.
    func testTheFillIsMaskedByBothOfTheContainersOwnKeys() async throws {
        let skin = try await load(wms: pharaohIdiom, images: ["sphinx.png": try artwork()])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        let mask = try XCTUnwrap(fillCommand(scene, nodeID: "sSphinx").inheritedClipMasks.first,
                                 "the fill is inside a mask of its own artwork")
        XCTAssertEqual(WMPPath.fold(mask.resourcePath), WMPPath.fold("sphinx.png"))
        XCTAssertEqual(Set(mask.keyedOut), [WMPColor(red: 255, green: 0, blue: 0),
                                            WMPColor(red: 255, green: 0, blue: 255)],
                       "the matte and the hole alike — a fill that keys only the matte still "
                       + "buries the visualizer, which is half of what pharaoh reported")
    }

    /// The pixels, which is where the report was: the window becomes a silhouette and the hole
    /// opens. Before this, all three of these were opaque black.
    func testTheMatteAndTheHoleAreBothTransparentInTheRenderedScene() async throws {
        let skin = try await load(wms: pharaohIdiomWithoutTheSurface,
                                  images: ["sphinx.png": try artwork()])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let image = try await renderer(for: skin).render(scene: scene).image

        XCTAssertEqual(WMPSkinTestSupport.rgba(image, x: 0, yFromTop: 0)[3], 0,
                       "the clippingColor matte is outside the window — pharaoh's 53,252 px")
        XCTAssertEqual(WMPSkinTestSupport.rgba(image, x: 3, yFromTop: 3)[3], 0,
                       "and the transparencyColor hole is what the visualizer shows through — "
                       + "pharaoh's 1,608 px, over a surface that was hosted and running")
        XCTAssertEqual(WMPSkinTestSupport.rgba(image, x: 6, yFromTop: 0), Self.body,
                       "while the artwork itself is untouched")
    }

    /// The fill is not *removed*, only confined: a container whose artwork has an alpha hole rather
    /// than a keyed one still shows the colour the author asked for behind it. This is the half a
    /// blanket suppression — which is what `cerulean` had — gets wrong.
    func testTheFillStillPaintsWhereTheCompositeIsOpaque() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8" backgroundColor="none">
            <SUBVIEW id="panel" backgroundImage="art.png" backgroundColor="#FF0000"
                     transparencyColor="#FF00FF"/>
        </VIEW></THEME>
        """, images: ["art.png": try WMPSkinTestSupport.encodedImage(
            width: 8, height: 8,
            rgba: Array(repeating: [UInt8](arrayLiteral: 0, 0, 0, 0), count: 64).flatMap { $0 })])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let image = try await renderer(for: skin).render(scene: scene).image

        XCTAssertEqual(WMPSkinTestSupport.rgba(image, x: 4, yFromTop: 4), Self.matte,
                       "fully transparent artwork keys nothing, so the whole fill survives")
    }

    /// A container that declares no key at all is not in the population and its fill is a plain
    /// rectangle, exactly as before. 639 corpus containers write `backgroundColor="none"` and the
    /// rest of the corpus writes no key beside a colour at all.
    func testAContainerWithNoKeyIsUntouched() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8" backgroundColor="none">
            <SUBVIEW id="panel" backgroundImage="art.png" backgroundColor="black"/>
        </VIEW></THEME>
        """, images: ["art.png": try artwork()])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertTrue(try fillCommand(scene, nodeID: "panel").inheritedClipMasks.isEmpty)
    }

    // MARK: - Counter-evidence

    /// **`Gorillaz` holds this one down and it is the corpus's only total loss under a careless
    /// widening.** Its `noodle` view is 781x467 over a `background.gif` that is a 50x28 square of
    /// solid `#33CC66` with `backgroundTiled="true"`, keyed by `clippingColor="#33CC66"` — the
    /// author saying *my ground is invisible*, not *my window is empty*. Reading the tile as a mask
    /// takes all 143,248 px of the skin. Same guard, same reason, as `clipMask` and `groundShape`.
    func testATiledSwatchDoesNotMaskTheFill() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8" backgroundColor="none">
            <SUBVIEW id="noodle" left="0" top="0" width="8" height="8" backgroundImage="tile.png"
                     backgroundTiled="true" backgroundColor="black" clippingColor="#FF0000"/>
        </VIEW></THEME>
        """, images: ["tile.png": try swatch()])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertTrue(try fillCommand(scene, nodeID: "noodle").inheritedClipMasks.isEmpty,
                      "a tiled swatch is a ground, not a shape — reading it as one erases Gorillaz")
        let image = try await renderer(for: skin).render(scene: scene).image
        XCTAssertEqual(WMPSkinTestSupport.rgba(image, x: 4, yFromTop: 4)[3], 255,
                       "and the skin still has a window")
    }

    /// The other half of the same guard: a bitmap standing in for a frame it does not cover is not
    /// that frame (W160). Only artwork authored at the node's own size may say where the composite
    /// is opaque.
    func testArtworkSmallerThanTheFrameDoesNotMaskTheFill() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8" backgroundColor="none">
            <SUBVIEW id="panel" left="0" top="0" width="8" height="8" backgroundImage="art.png"
                     backgroundColor="black" clippingColor="#FF0000"/>
        </VIEW></THEME>
        """, images: ["art.png": try artwork(width: 4, height: 4)])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertTrue(try fillCommand(scene, nodeID: "panel").inheritedClipMasks.isEmpty)
    }
}
