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

    /// **`transparencyColor` never shapes the contents, and Cerulean is why.** `face.bmp` keys
    /// `#FF0000` as the window matte *and* `#FF00FF` as a hole its `zIndex="-1"` visualizer and
    /// `zIndex="-2"` eye show through. Reading both into the shape clips those two away, which is
    /// the W147 inversion arriving by a second route.
    func testTransparencyColourAloneShapesNothing() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="8" height="8">
            <SUBVIEW id="body" left="0" top="0" width="8" height="8"
                     backgroundImage="mask.png" transparencyColor="white">
                <BUTTON id="slab" left="0" top="0" width="8" height="8" image="slab.png"/>
            </SUBVIEW>
        </VIEW></THEME>
        """, images: ["mask.png": try shapeMask(), "slab.png": try flat([10, 120, 200, 255])])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertTrue(try XCTUnwrap(scene.commands.first { $0.nodeID == "slab" })
                        .inheritedClipMasks.isEmpty)
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
