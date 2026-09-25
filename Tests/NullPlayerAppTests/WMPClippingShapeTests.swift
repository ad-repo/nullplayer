import Foundation
import XCTest
@testable import NullPlayer

/// What a `clippingImage` / `clippingColor` declaration shapes, and what it must never touch.
///
/// Three defects met in one report — *"combat flight simulator and plus plasma ball have a gray box
/// background I suspect should not be showing"*, then *"you made the high res graphics low res"*,
/// then *"fix the other skins that were addressed with plus egg commit"* — and they are independent:
///
/// 1. **W167 — `auto` is a colour, not an absence.** Four declarations across three archives write
///    it, and a rejected `auto` is not the same thing as no key: `Plus! Plasma Ball`'s `mainButtons`
///    carries `clippingImage="screen_MASK.gif" clippingColor="auto"` over a mask with *zero*
///    transparent pixels, so nothing was cut and the whole 242x299 `screen_normal.jpg` — flat
///    `#9FA8AD` around the player — drew opaque over the plasma globe.
/// 2. **W168 — a clipping shape shapes the element's *contents*.** A `<SUBVIEW>`/`<VIEW>` in WMP is
///    a window region and its children are inside it. `Combat_Flight_Simulator_3` hangs its whole
///    body off `<subview id="mainBody" backgroundImage="main_bg_mask.png" clippingColor="#ffffff">`
///    and draws `main_bg.jpg` inside it as a child declaring **no key of its own**.
/// 3. **W169 — `clippingColor` keys the clipping image, never the artwork.** The two attributes were
///    read as one list, which is harmless while they name the same colour and destructive when they
///    do not. It is the largest of the three by reach: `Plus! Hard Boiled`'s `Egg_Body_Normal.jpg`
///    was losing **27%** of its pixels and `Plus! Plasma Ball`'s `eq_panel_normal.jpg` **85.7%**,
///    because a JPEG keys with `WMPColorKey.jpegComponentTolerance` and every tone within 64 of
///    white went transparent. W160 read that as a *resampling* defect and landed Lanczos on it.
///
/// W168 is the one with the trap in it, and both guards have a named archive holding them down —
/// see `testATiledSwatchIsNotAShape` and `testArtworkWithAKeyedHoleIsNotAShape`.
final class WMPClippingShapeTests: XCTestCase {

    // MARK: - Fixtures

    private static let white: [UInt8] = [255, 255, 255, 255]
    private static let black: [UInt8] = [0, 0, 0, 255]

    /// Is this pixel inside the shape? A 4x4 block inset by one, so **0,0 is the key colour** —
    /// which is where every `auto` author in the corpus put it and what `cornerColor` reads.
    private static func inShape(row: Int, column: Int) -> Bool {
        (1...4).contains(row) && (1...4).contains(column)
    }

    /// A two-toned 8x8 shape mask: white (the key) everywhere except an opaque black 4x4 block,
    /// which is the shape. This is `main_bg_mask.png`'s shape in miniature.
    private func shapeMask() throws -> Data {
        var rgba: [UInt8] = []
        for row in 0..<8 {
            for column in 0..<8 {
                rgba += Self.inShape(row: row, column: column) ? Self.black : Self.white
            }
        }
        return try WMPSkinTestSupport.encodedImage(width: 8, height: 8, rgba: rgba)
    }

    /// 8x8 of one flat colour — the tile `Gorillaz` keys, and the artwork a child covers.
    private func flat(_ colour: [UInt8], width: Int = 8, height: Int = 8) throws -> Data {
        try WMPSkinTestSupport.encodedImage(width: width, height: height,
                                            rgba: Array(repeating: colour, count: width * height).flatMap { $0 })
    }

    /// Artwork the way a `.wmz` author draws it: a near-white body over a keyed surround. The body
    /// is `#F4F4F4`, which is *within 64 components of white* — the whole of W169.
    private func nearWhiteBody() throws -> Data {
        let body: [UInt8] = [0xF4, 0xF4, 0xF4, 255]
        var rgba: [UInt8] = []
        for row in 0..<8 {
            for column in 0..<8 {
                rgba += Self.inShape(row: row, column: column) ? body : Self.white
            }
        }
        return try WMPSkinTestSupport.encodedImage(width: 8, height: 8, rgba: rgba)
    }

    private func load(wms: String, images: [String: Data]) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]
        entries += images.map { WMPTestArchiveEntry($0.key, data: $0.value) }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    private func imageCommand(_ scene: WMPScene, nodeID: String) throws -> WMPSceneImage {
        let command = try XCTUnwrap(scene.commands.first { $0.nodeID == nodeID },
                                    "\(nodeID) paints")
        guard case let .image(specification) = command.paint else {
            throw XCTSkip("\(nodeID) is not an image command")
        }
        return specification
    }

    /// Rendering has to go through the same store the scene resolved against, or every resource is
    /// missing. The builder owns one; hand it back the skin's own archive.
    private func renderer(for skin: WMPLoadedSkin) -> WMPRenderer {
        WMPRenderer(imageStore: WMPImageStore(provider: skin.archive))
    }

    // MARK: - W167: `auto`

    /// `clippingColor="auto"` takes its colour from the **clipping image**, and that is the mask's
    /// corner. `Plus! Plasma Ball` states the answer twice in the same file: its four other layers
    /// write `clippingColor="white"` by hand over masks that are white at 0,0, and the two that
    /// write `auto` are over masks that are white at 0,0 as well.
    func testAutoClippingColourComesFromTheClippingImagesCorner() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8">
            <BUTTON id="body" left="0" top="0" width="8" height="8" image="body.png"
                    clippingImage="mask.png" clippingColor="auto"/>
        </VIEW></THEME>
        """, images: ["body.png": try nearWhiteBody(), "mask.png": try shapeMask()])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        let specification = try imageCommand(scene, nodeID: "body")
        XCTAssertEqual(specification.clippingMaskKeys, [WMPColor(red: 255, green: 255, blue: 255)],
                       "auto resolved to the mask's own corner, not to nothing")
    }

    /// Every other key spelled `auto` reads the node's own artwork instead. `Compact`'s
    /// `bgSeekCtls` is the corpus's only one: `transparencyColor="auto"` over `BTNGROUP_UP.bmp`.
    func testAutoTransparencyColourComesFromTheArtworksCorner() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8">
            <BUTTON id="body" left="0" top="0" width="8" height="8" image="body.png"
                    transparencyColor="auto"/>
        </VIEW></THEME>
        """, images: ["body.png": try nearWhiteBody()])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertEqual(try imageCommand(scene, nodeID: "body").colorKeys,
                       [WMPColor(red: 255, green: 255, blue: 255)],
                       "read off the bitmap's own corner rather than guessed at")
    }

    /// A value the parser rejects for any *other* reason still resolves to nothing, and therefore
    /// still falls to the implicit magenta key (W78). `Alpine7618_v09` writes
    /// `transparencyColor="FF00FF"` with no `#`, and `backgroundColor="none"` is authored 639 times.
    func testAnUnparseableKeyIsStillNoKeyAtAll() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8">
            <BUTTON id="body" left="0" top="0" width="8" height="8" image="body.png"
                    transparencyColor="none"/>
        </VIEW></THEME>
        """, images: ["body.png": try nearWhiteBody()])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        let specification = try imageCommand(scene, nodeID: "body")
        XCTAssertTrue(specification.colorKeys.isEmpty)
        XCTAssertEqual(specification.implicitColorKey, WMPColorKey.implicitTransparency)
    }

    // MARK: - W169: the key the artwork must not receive

    /// **The largest of the three, and the one no screenshot named.** A node that declares a
    /// `clippingImage` has said what the `clippingColor` is *for*; keying it out of the artwork as
    /// well deletes the artwork. `Plus! Hard Boiled`'s `Egg_Body_Normal.jpg` lost 27% of itself
    /// this way, `TDK`'s `info_bg.jpg` 52.1%, and `elvis`'s "30 #1 HITS" became unreadable.
    func testClippingColourNeverKeysTheArtworkWhenAClippingImageIsDeclared() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8">
            <BUTTON id="body" left="0" top="0" width="8" height="8" image="body.png"
                    clippingImage="mask.png" clippingColor="white"/>
        </VIEW></THEME>
        """, images: ["body.png": try nearWhiteBody(), "mask.png": try shapeMask()])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        let specification = try imageCommand(scene, nodeID: "body")
        XCTAssertTrue(specification.colorKeys.isEmpty,
                      "the clipping colour belongs to the mask; the artwork keeps every tone")
        XCTAssertEqual(specification.clippingMaskKeys, [WMPColor(red: 255, green: 255, blue: 255)])

        let rendered = try await renderer(for: skin).render(scene: scene).image
        // Inside the shape, and within the JPEG tolerance window of the clipping colour: this is
        // the pixel that used to disappear.
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 1, yFromTop: 1),
                       [0xF4, 0xF4, 0xF4, 255], "the near-white body survives")
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 6, yFromTop: 6)[3], 0,
                       "and the mask still cuts everything outside the shape")
    }

    /// A node with **no** `clippingImage` keeps the old reading, because there `clippingColor` is
    /// the only thing shaping it — 84 `<SUBVIEW>`s and 26 `<VIEW>`s in the corpus depend on it.
    func testClippingColourStillKeysTheArtworkWithNoClippingImage() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8">
            <BUTTON id="body" left="0" top="0" width="8" height="8" image="mask.png"
                    clippingColor="white"/>
        </VIEW></THEME>
        """, images: ["mask.png": try shapeMask()])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertEqual(try imageCommand(scene, nodeID: "body").colorKeys,
                       [WMPColor(red: 255, green: 255, blue: 255)])
    }

    // MARK: - W168: a shape shapes the contents

    /// `Combat_Flight_Simulator_3` in miniature: a keyed two-toned mask on the container, and a
    /// child that draws a flat slab over the whole of it with no key of its own.
    func testAContainersShapeClipsItsChildrensPaint() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8">
            <SUBVIEW id="body" left="0" top="0" width="8" height="8"
                     backgroundImage="mask.png" clippingColor="white">
                <BUTTON id="slab" left="0" top="0" width="8" height="8" image="slab.png"/>
            </SUBVIEW>
        </VIEW></THEME>
        """, images: ["mask.png": try shapeMask(), "slab.png": try flat([10, 120, 200, 255])])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        let slab = try XCTUnwrap(scene.commands.first { $0.nodeID == "slab" })
        XCTAssertEqual(slab.inheritedClipMasks.count, 1, "the child carries its container's shape")
        XCTAssertEqual(slab.inheritedClipMasks.first?.keyedOut,
                       [WMPColor(red: 255, green: 255, blue: 255)])

        let rendered = try await renderer(for: skin).render(scene: scene).image
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 1, yFromTop: 1),
                       [10, 120, 200, 255], "the slab draws inside the shape")
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 6, yFromTop: 6)[3], 0,
                       "and not a pixel of it outside — this is the gray box")
    }

    /// The container's *own* paint is not clipped twice: it is emitted before its shape is pushed,
    /// and `WMPSceneImage.clippingMaskPath` already shapes a draw that declares one.
    func testAContainerDoesNotInheritItsOwnShape() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8">
            <SUBVIEW id="body" left="0" top="0" width="8" height="8"
                     backgroundImage="mask.png" clippingColor="white">
                <BUTTON id="slab" left="0" top="0" width="8" height="8" image="slab.png"/>
            </SUBVIEW>
        </VIEW></THEME>
        """, images: ["mask.png": try shapeMask(), "slab.png": try flat([10, 120, 200, 255])])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        let body = try XCTUnwrap(scene.commands.first { $0.nodeID == "body" })
        XCTAssertTrue(body.inheritedClipMasks.isEmpty)
    }

    /// **`transparencyColor` states the shape too, on the background-image path only (W172).** A
    /// `<SUBVIEW>` whose whole ground *is* a two-tone mask has said the same thing whichever
    /// attribute names the key — `Plus! HueShifter`'s five subviews write `transparencyColor` over
    /// `body_Mask.gif`, `playlist_tray_wholemask.gif` and three siblings, and reading only
    /// `clippingColor` left every one of them a plain rectangle: its bottom "candy" hung 22 px
    /// below the player's silhouette in a colour nothing else on screen was. 127 nodes across 17
    /// archives qualify, and the same three guards separate them from artwork.
    ///
    /// **Cerulean is not this case and never was.** Its `face.bmp` subview writes
    /// `clippingColor="#FF0000"` beside `transparencyColor="#FF00FF"`, so the shape comes from the
    /// clipping colour either way; and the bitmap is 18,601 colours, which `isShapeMask` rejects.
    /// `testArtworkWithAKeyedHoleIsNotAShape` is where that guard lives.
    func testTransparencyColourShapesTheContentsToo() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8">
            <SUBVIEW id="body" left="0" top="0" width="8" height="8"
                     backgroundImage="mask.png" transparencyColor="white">
                <BUTTON id="slab" left="0" top="0" width="8" height="8" image="slab.png"/>
            </SUBVIEW>
        </VIEW></THEME>
        """, images: ["mask.png": try shapeMask(), "slab.png": try flat([10, 120, 200, 255])])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        let slab = try XCTUnwrap(scene.commands.first { $0.nodeID == "slab" })
        XCTAssertEqual(slab.inheritedClipMasks.count, 1, "the child carries its container's shape")
        XCTAssertEqual(slab.inheritedClipMasks.first?.keyedOut,
                       [WMPColor(red: 255, green: 255, blue: 255)])

        let rendered = try await renderer(for: skin).render(scene: scene).image
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 1, yFromTop: 1),
                       [10, 120, 200, 255], "the slab draws inside the shape")
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 6, yFromTop: 6)[3], 0,
                       "and not a pixel of it outside")
    }

    /// **A node that names a `clippingImage` has one attribute for its key, and it is
    /// `clippingColor`.** The widening above is scoped to the background-image path on purpose: an
    /// authored mask file is not a container's ground, and no corpus node pairs a `clippingImage`
    /// with a `transparencyColor` meant for it.
    func testAClippingImageIsNotShapedByTransparencyColour() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8">
            <SUBVIEW id="body" left="0" top="0" width="8" height="8"
                     clippingImage="mask.png" transparencyColor="white">
                <BUTTON id="slab" left="0" top="0" width="8" height="8" image="slab.png"/>
            </SUBVIEW>
        </VIEW></THEME>
        """, images: ["mask.png": try shapeMask(), "slab.png": try flat([10, 120, 200, 255])])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertTrue(try XCTUnwrap(scene.commands.first { $0.nodeID == "slab" })
                        .inheritedClipMasks.isEmpty)
    }

    /// **A container's shape is a region, not a clipping image (W172).** The two differ only on a
    /// mask that carries transparency of its own, and there the difference is total: `Ice`'s
    /// `Clip.png` is 379x183 in exactly two values — opaque `#FF00FF` outside the player and
    /// **alpha-zero** white over it — so honouring the mask's own alpha cut the keep region and the
    /// key alike, and the two `Frost` layers it shapes disappeared. The colour is the whole
    /// statement: in the region wherever the pixel is not the key, whatever its alpha.
    func testAContainersShapeIgnoresItsMasksOwnAlpha() async throws {
        var rgba: [UInt8] = []
        for row in 0..<8 {
            for column in 0..<8 {
                // Inside the shape the mask is *fully transparent*, as `Clip.png` is; outside it is
                // the opaque key. Nothing in the file is opaque paint.
                rgba += Self.inShape(row: row, column: column)
                    ? [255, 255, 255, 0] : [255, 0, 255, 255]
            }
        }
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8">
            <SUBVIEW id="body" left="0" top="0" width="8" height="8"
                     backgroundImage="clip.png" transparencyColor="#FF00FF">
                <BUTTON id="slab" left="0" top="0" width="8" height="8" image="slab.png"/>
            </SUBVIEW>
        </VIEW></THEME>
        """, images: [
            "clip.png": try WMPSkinTestSupport.encodedImage(width: 8, height: 8, rgba: rgba),
            "slab.png": try flat([10, 120, 200, 255])])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        let rendered = try await renderer(for: skin).render(scene: scene).image
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 1, yFromTop: 1),
                       [10, 120, 200, 255], "the alpha-zero region is the shape, not a cut")
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 6, yFromTop: 6)[3], 0,
                       "and the opaque key is still outside it")
    }

    /// **A `clippingImage` with no key beside it takes the mask's own corner (W171).** 169 of the
    /// corpus's 172 declarations write a `clippingColor`; the three that do not —
    /// `Plus! HueShifter`'s `body_lower.jpg` group, `Charlies_Angels_Full_Throttle`'s `visEffects`
    /// and `gnome`'s `myeffects2` — name a **fully opaque** mask, so reading that as "no key" left
    /// the source-alpha test keeping every pixel and the node drew its whole rectangle. On
    /// HueShifter that was a 213x66 lavender plate boxed across the bottom of the player.
    func testAClippingImageWithNoKeyTakesItsOwnCorner() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8">
            <BUTTON id="body" left="0" top="0" width="8" height="8" image="body.png"
                    clippingImage="mask.png"/>
        </VIEW></THEME>
        """, images: ["mask.png": try shapeMask(), "body.png": try flat([10, 120, 200, 255])])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertEqual(try imageCommand(scene, nodeID: "body").clippingMaskKeys,
                       [WMPColor(red: 255, green: 255, blue: 255)], "the mask's 0,0")

        let rendered = try await renderer(for: skin).render(scene: scene).image
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 1, yFromTop: 1), [10, 120, 200, 255])
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 6, yFromTop: 6)[3], 0,
                       "the mask cuts, rather than passing the whole rectangle through")
    }

    /// The other half of W171: a mask that authored its own alpha has already said what it cuts,
    /// and a corner key would cut it a second time.
    func testAClippingImageWithItsOwnAlphaTakesNoCorner() async throws {
        var rgba: [UInt8] = []
        for row in 0..<8 {
            for column in 0..<8 {
                rgba += Self.inShape(row: row, column: column) ? Self.black : [0, 0, 0, 0]
            }
        }
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8">
            <BUTTON id="body" left="0" top="0" width="8" height="8" image="body.png"
                    clippingImage="mask.png"/>
        </VIEW></THEME>
        """, images: [
            "mask.png": try WMPSkinTestSupport.encodedImage(width: 8, height: 8, rgba: rgba),
            "body.png": try flat([10, 120, 200, 255])])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertTrue(try imageCommand(scene, nodeID: "body").clippingMaskKeys.isEmpty)
    }

    /// **Guard one: `Gorillaz`.** Its `noodle` view is 781x467 over a `background.gif` that is a
    /// 50x28 swatch of solid `#33CC66` with `backgroundTiled="true"`, and its
    /// `clippingColor="#33CC66"` says *my ground is invisible* — not *my window is empty*. Reading
    /// the tile as a shape erased the whole skin, all 143,248 px of it, and it was the corpus's only
    /// total loss under this rule. A bitmap standing in for a frame it does not cover is not that
    /// frame, which is the test W160 landed on for resampling too.
    func testATiledSwatchIsNotAShape() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8" backgroundImage="tile.png"
                     backgroundTiled="true" clippingColor="#33CC66">
            <BUTTON id="slab" left="0" top="0" width="8" height="8" image="slab.png"/>
        </VIEW></THEME>
        """, images: ["tile.png": try flat([0x33, 0xCC, 0x66, 255], width: 4, height: 4),
                      "slab.png": try flat([10, 120, 200, 255])])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertTrue(try XCTUnwrap(scene.commands.first { $0.nodeID == "slab" })
                        .inheritedClipMasks.isEmpty)
        let rendered = try await renderer(for: skin).render(scene: scene).image
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 6, yFromTop: 6),
                       [10, 120, 200, 255], "the skin still draws")
    }

    /// **Guard two: `YIL!OMA2K`.** Its view is 530x440 of `yMain Body.bmp` — **34,688 colours** —
    /// with a 246x179 rectangle of `#6699FF` cut out for the video and a `<subview zIndex="-2">` of
    /// solid black parked behind the body to show through that hole. Shaping children by artwork
    /// clips the backdrop away and leaves the display empty. Two tones or many is the whole
    /// question, and `WMPImageStore.isShapeMask` is where it is asked.
    func testArtworkWithAKeyedHoleIsNotAShape() async throws {
        // A picture, not a mask: a keyed hole, and enough distinct tones that no two of them
        // account for the file.
        var rgba: [UInt8] = []
        for row in 0..<8 {
            for column in 0..<8 {
                if row < 4 && column < 4 { rgba += [255, 255, 255, 255] }
                else { rgba += [UInt8(16 + row * 8), UInt8(32 + column * 8), UInt8(64 + row), 255] }
            }
        }
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8">
            <SUBVIEW id="body" left="0" top="0" width="8" height="8"
                     backgroundImage="art.png" clippingColor="white">
                <BUTTON id="slab" zIndex="-1" left="0" top="0" width="8" height="8" image="slab.png"/>
            </SUBVIEW>
        </VIEW></THEME>
        """, images: ["art.png": try WMPSkinTestSupport.encodedImage(width: 8, height: 8, rgba: rgba),
                      "slab.png": try flat([10, 120, 200, 255])])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertTrue(try XCTUnwrap(scene.commands.first { $0.nodeID == "slab" })
                        .inheritedClipMasks.isEmpty,
                      "artwork with a keyed hole means children show *through* the hole")
        let rendered = try await renderer(for: skin).render(scene: scene).image
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 1, yFromTop: 1),
                       [10, 120, 200, 255], "the backdrop shows through the keyed hole")
    }

    /// The predicate itself, stated directly, because the two populations it separates are 3 and 10
    /// colours against 2,181 and 34,688 and the threshold is a *share* rather than a count: a mask's
    /// own edges are antialiased, and `main_vismask.png` is 10 colours at 100.0% in its top two.
    func testIsShapeMaskSeparatesAMaskFromAPicture() throws {
        let mask = try shapeMask()
        var pictureRGBA: [UInt8] = []
        for row in 0..<8 {
            for column in 0..<8 {
                pictureRGBA += [UInt8(row * 8), UInt8(column * 8), UInt8(row * 4 + column), 255]
            }
        }
        let picture = try WMPSkinTestSupport.encodedImage(width: 8, height: 8, rgba: pictureRGBA)
        let store = WMPImageStore(provider: WMPMemoryResourceProvider([
            "mask.png": mask, "picture.png": picture,
        ]))

        XCTAssertTrue(try store.isShapeMask(for: "mask.png"))
        XCTAssertFalse(try store.isShapeMask(for: "picture.png"))
    }

    // MARK: - A window body's silhouette

    /// `xXx_night_vision_redx`: a view with no shape of its own takes one from its lowest subview,
    /// a whole-canvas body keyed by `transparencyColor`, and the matte round the outside is cut
    /// from every sibling too — the open button's flat green field sits over the body's magenta.
    /// A keyed hole *inside* the body is not outside the window and stays open.
    func testAWindowBodysMatteClipsItsSiblingsButNotItsInteriorHole() async throws {
        let magenta: [UInt8] = [255, 0, 255, 255]
        var rgba: [UInt8] = []
        for row in 0..<8 {
            for column in 0..<8 {
                let matte = row == 0 || row == 7 || column == 0 || column == 7
                let hole = (3...4).contains(row) && (3...4).contains(column)
                rgba += matte || hole ? magenta : [40, 40, 40, 255]
            }
        }
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8" backgroundColor="none">
            <SUBVIEW id="body" zIndex="1" left="0" top="0" backgroundImage="body.png"
                     transparencyColor="#ff00ff"/>
            <SUBVIEW id="buttons" zIndex="6" left="0" top="0" width="8" height="8"
                     transparencyColor="#ff00ff">
                <BUTTON id="open" left="0" top="0" width="8" height="8" image="slab.png"/>
            </SUBVIEW>
        </VIEW></THEME>
        """, images: ["body.png": try WMPSkinTestSupport.encodedImage(width: 8, height: 8, rgba: rgba),
                      "slab.png": try flat([173, 204, 49, 255])])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        XCTAssertEqual(try XCTUnwrap(scene.commands.first { $0.nodeID == "open" })
                        .inheritedClipMasks.map(\.exteriorOnly), [true])

        let rendered = try await renderer(for: skin).render(scene: scene).image
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 0, yFromTop: 0)[3], 0,
                       "the green field over the matte is outside the window")
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 1, yFromTop: 1),
                       [173, 204, 49, 255], "inside the silhouette the button draws")
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 3, yFromTop: 3),
                       [173, 204, 49, 255], "an interior keyed hole is not cut from the siblings")
    }

    // MARK: - Keys at 16-bit colour

    /// `YIL!OMA2K` declares `#6699FF` and its speaker bitmaps hold `#639CFF`, which is `#6699FF`
    /// through RGB555. A BMP key matches at 5 bits per channel; a PNG key stays exact.
    func testABitmapKeyMatchesAtHighColourAndAPNGKeyStaysExact() throws {
        let stored: [UInt8] = [99, 156, 255, 255]
        let neighbour: [UInt8] = [96, 160, 255, 255]
        let rgba = [stored, neighbour].flatMap { $0 }
        let store = WMPImageStore(provider: WMPMemoryResourceProvider([
            "speaker.bmp": try WMPSkinTestSupport.encodedImage(width: 2, height: 1, rgba: rgba, type: .bmp),
            "speaker.png": try WMPSkinTestSupport.encodedImage(width: 2, height: 1, rgba: rgba),
        ]))
        let key = [WMPColor(red: 0x66, green: 0x99, blue: 0xFF)]

        let bitmap = try store.image(for: "speaker.bmp", colorKeys: key).image
        XCTAssertEqual(WMPSkinTestSupport.rgba(bitmap, x: 0, yFromTop: 0)[3], 0)
        XCTAssertEqual(WMPSkinTestSupport.rgba(bitmap, x: 1, yFromTop: 0)[3], 255,
                       "one RGB555 step away is artwork, not the key")
        let png = try store.image(for: "speaker.png", colorKeys: key).image
        XCTAssertEqual(WMPSkinTestSupport.rgba(png, x: 0, yFromTop: 0)[3], 255)
    }

    /// W282: a black key clears black, not every channel 0-7. `gnome` paints its face on a flat
    /// `(4,4,4)` inside a `#000000` surround, and the 5-bit bucket W277 introduced keyed the face.
    func testABlackBitmapKeyLeavesANearBlackBacking() throws {
        let rgba: [UInt8] = [0, 0, 0, 255, 4, 4, 4, 255]
        let store = WMPImageStore(provider: WMPMemoryResourceProvider([
            "face.bmp": try WMPSkinTestSupport.encodedImage(width: 2, height: 1, rgba: rgba, type: .bmp),
        ]))

        let face = try store.image(for: "face.bmp", colorKeys: [WMPColor(red: 0, green: 0, blue: 0)]).image
        XCTAssertEqual(WMPSkinTestSupport.rgba(face, x: 0, yFromTop: 0)[3], 0)
        XCTAssertEqual(WMPSkinTestSupport.rgba(face, x: 1, yFromTop: 0), [4, 4, 4, 255],
                       "a near-black backing is artwork")
    }

    // MARK: - W281, W283: what a view and a subview draw

    /// W281: `visible` is not a `<VIEW>` attribute. `gnome` authors `<view visible="false">` and
    /// loads in WMP; honouring it emptied the window.
    func testAViewAuthoredInvisibleStillDraws() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8" visible="false">
            <SUBVIEW id="body" left="0" top="0" width="8" height="8" backgroundImage="body.png"/>
        </VIEW></THEME>
        """, images: ["body.png": try flat([10, 120, 200, 255])])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertNotNil(scene.commands.first { $0.nodeID == "body" })
    }

    /// W283: art larger than a subview's box stops at the box. `Asimov_Radio` closes its video
    /// drawer by sizing `splView` shorter than `vid_screen.bmp`, and the rest drew as a slab.
    func testASubviewTrimsBackgroundArtLargerThanItsBox() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8">
            <SUBVIEW id="drawer" left="0" top="0" width="8" height="4" backgroundImage="drawer.png"/>
        </VIEW></THEME>
        """, images: ["drawer.png": try flat([10, 120, 200, 255])])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        let rendered = try await renderer(for: skin).render(scene: scene).image
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 2, yFromTop: 2), [10, 120, 200, 255])
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered, x: 2, yFromTop: 6)[3], 0,
                       "the closed half of the drawer is not drawn")
    }

    /// `cornerColor` is nil for a bitmap whose corner is already transparent: a file that authored
    /// its own alpha has said what is see-through and there is no matte colour to infer.
    func testCornerColourIsNilForAnAlreadyTransparentCorner() throws {
        var rgba: [UInt8] = Array(repeating: 0, count: 4)
        rgba += Array(repeating: [9, 9, 9, 255], count: 63).flatMap { $0 }
        let store = WMPImageStore(provider: WMPMemoryResourceProvider([
            "clear.png": try WMPSkinTestSupport.encodedImage(width: 8, height: 8, rgba: rgba),
        ]))

        XCTAssertNil(try store.cornerColor(for: "clear.png"))
    }
}
