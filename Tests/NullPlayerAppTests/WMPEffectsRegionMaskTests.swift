import CoreGraphics
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import NullPlayer

/// Whether a visualization surface is hosted at all, and in what shape.
///
/// Two defects met in the same rectangle, and both presented as "the spectrum is slapped on top of
/// the UI covering the controls" on `Plus! Bionic Dot`:
///
/// 1. A container the skin had **faded shut** still got an AppKit surface. `alphaBlend` inherits
///    and the scene's paint commands have honoured that since they were filtered at `emit`, but a
///    hosted `NSView` is not a paint command — so `<subview alphaBlend="0">` correctly drew no
///    artwork while the `<EFFECTS>` inside it drew a 169x160 visualizer across the face.
/// 2. The surface was clipped to its container's **rectangle** rather than its **shape**.
///
/// The second is the one with a trap in it, because a keyed container means opposite things
/// depending on whether it carries a third state — see `WMPImageStore.shapesChildrenByRegion`. The
/// two-state case here is Cerulean's shape, and it is ground truth: reading its key as "outside"
/// does not distort its visualizer, it erases it.
final class WMPEffectsRegionMaskTests: XCTestCase {

    // MARK: - Fixtures

    /// `opening` is the pixel the shape is built from: `.transparent` makes the file three-state
    /// (key = outside, transparent = the opening, paint = trim), `.keyed` makes it the ordinary
    /// two-state artwork-with-a-hole that every non-Plus! container in the corpus is.
    private enum Opening { case transparent, keyed }

    /// A 4x4 container image. The left half is the opening, the right half is the other state, and
    /// the bottom row is opaque paint standing in for the trim.
    private func containerImage(opening: Opening) throws -> Data {
        let key: [UInt8] = [255, 0, 255, 255]
        let clear: [UInt8] = [0, 0, 0, 0]
        let paint: [UInt8] = [10, 20, 30, 255]
        var rgba: [UInt8] = []
        for row in 0..<4 {
            for column in 0..<4 {
                if row == 3 { rgba += paint }
                else if column < 2 { rgba += opening == .transparent ? clear : key }
                else { rgba += opening == .transparent ? key : paint }
            }
        }
        return try WMPSkinTestSupport.encodedImage(width: 4, height: 4, rgba: rgba)
    }

    private func load(wms: String, images: [String: Data] = [:]) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]
        entries += images.map { WMPTestArchiveEntry($0.key, data: $0.value) }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    private func effectsWidget(in scene: WMPScene) throws -> WMPWidget {
        try XCTUnwrap(scene.widgets.first { $0.kind == .effects }, "the scene hosts an <EFFECTS>")
    }

    // MARK: - The inherited fade

    /// `alphaBlend` inherits down the subtree, and a widget carries the same number its container's
    /// paint commands do. `Plus! Bionic Dot` opens on a shut pane: `<subview id="visMask"
    /// alphaBlend="0">`, faded to 255 by `toggleVis()` — and its `checkPlayerState()` shuts it
    /// again whenever `player.controls.isAvailable("Stop")` is false, which is every stopped player.
    func testAFadedContainerCarriesItsFadeOntoTheWidgetAndDrawsNoArtwork() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="visMask" left="20" top="20" width="100" height="80"
                     backgroundColor="#123456" alphaBlend="0">
                <EFFECTS id="visEffects" left="0" top="0" width="100" height="80"/>
            </SUBVIEW>
        </VIEW></THEME>
        """)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertEqual(try effectsWidget(in: scene).alpha, 0,
                       "the widget inherits the container's fade, exactly as its paint does")
        XCTAssertFalse(scene.commands.contains { $0.nodeID == "visMask" },
                       "a fully faded container emits no paint — the widget must not outlive it")
    }

    /// The partial case is real: `Plus! Plasma Ball` hangs its effects off an `alphaBlend="110"`
    /// layer. Those surfaces are still hosted, carrying the fraction so the view can apply it.
    func testAPartiallyFadedContainerKeepsItsSurfaceAndItsFraction() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="glow" left="0" top="0" width="100" height="80" alphaBlend="110">
                <EFFECTS id="fx" left="0" top="0" width="100" height="80"/>
            </SUBVIEW>
        </VIEW></THEME>
        """)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        let alpha = try effectsWidget(in: scene).alpha
        XCTAssertEqual(alpha, 110.0 / 255.0, accuracy: 0.001)
        XCTAssertGreaterThan(alpha, 0, "a partial fade is hosted, not dropped")
    }

    /// No `alphaBlend` anywhere above it is the common case and the one Cerulean is in.
    func testAnUnfadedContainerLeavesTheWidgetFullyOpaque() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="plain" left="0" top="0" width="100" height="80">
                <EFFECTS id="fx" left="0" top="0" width="100" height="80"/>
            </SUBVIEW>
        </VIEW></THEME>
        """)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        XCTAssertEqual(try effectsWidget(in: scene).alpha, 1)
    }

    // MARK: - Shape versus overpaint

    private func scene(opening: Opening) async throws -> WMPScene {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="lens" left="20" top="30" width="100" height="80"
                     backgroundImage="lens.png" transparencyColor="#FF00FF">
                <EFFECTS id="visEffects" left="0" top="0" width="100" height="80"/>
            </SUBVIEW>
        </VIEW></THEME>
        """, images: ["lens.png": try containerImage(opening: opening)])
        return try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
    }

    /// A three-state container is a shape mask, and the surface is clipped to it.
    func testAThreeStateContainerShapesTheSurface() async throws {
        let widget = try effectsWidget(in: try await scene(opening: .transparent))
        let mask = try XCTUnwrap(widget.regionMask, "key + transparent + paint is a shape mask")
        XCTAssertEqual(mask.resourcePath.lowercased(), "lens.png")
        XCTAssertEqual(mask.keyedOut, [WMPColor(red: 255, green: 0, blue: 255)])
        XCTAssertEqual(mask.frame, WMPRect(x: 20, y: 30, width: 100, height: 80),
                       "the mask covers the container's frame, which is what aligns it")
    }

    /// **Cerulean's shape, and the reason this guard exists.** `face.bmp` is 56% key, 44% opaque
    /// paint and 0% transparent: the key is the *hole* the visualizer shows through, and the paint
    /// occludes the rest through `commandSplitIndex`. Masking by region here would keep the surface
    /// only where the face already covers it and cut it away inside the hole.
    func testATwoStateContainerShapesNothingAndLeavesTheOcclusionPathAlone() async throws {
        let scene = try await scene(opening: .keyed)
        XCTAssertNil(try effectsWidget(in: scene).regionMask,
                     "artwork with a keyed hole occludes by paint; it must not be read as a shape")
        XCTAssertNotNil(scene.effectsCommandSplitIndex,
                        "and the occlusion path it does use is untouched")
    }

    /// A container with no key at all cannot describe a shape either way.
    func testAContainerWithoutATransparencyColourShapesNothing() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="lens" left="0" top="0" width="100" height="80" backgroundImage="lens.png">
                <EFFECTS id="fx" left="0" top="0" width="100" height="80"/>
            </SUBVIEW>
        </VIEW></THEME>
        """, images: ["lens.png": try containerImage(opening: .transparent)])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        XCTAssertNil(try effectsWidget(in: scene).regionMask)
    }

    // MARK: - The window's own shape (W198)

    /// **Cerulean's defect, as a fixture.** A container that occludes by paint takes no
    /// `regionMask` — the test above — and until W198 that left it confining its surface with
    /// nothing at all at the edges of the skin. The `clippingColor` region is the separate
    /// statement: pixels the skin cut out of its own silhouette, where no artwork is painted and so
    /// none can occlude. Here the right half of `lens.png` is the clipping key, and the container
    /// is authored at the bitmap's own 4x4 size because a bitmap standing in for a frame it does not
    /// cover is not that frame.
    func testAContainerThatOccludesByPaintStillConfinesTheSurfaceToItsClippingRegion() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="face" left="20" top="30" width="4" height="4"
                     backgroundImage="lens.png" clippingColor="#FF00FF">
                <EFFECTS id="visEffects" left="0" top="0" width="4" height="4"/>
            </SUBVIEW>
        </VIEW></THEME>
        """, images: ["lens.png": try containerImage(opening: .keyed)])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let widget = try effectsWidget(in: scene)

        XCTAssertNil(widget.regionMask, "still not a shape mask — that path is unchanged")
        let shape = try XCTUnwrap(widget.clippingShape, "the silhouette is a separate statement")
        XCTAssertEqual(shape.resourcePath.lowercased(), "lens.png")
        XCTAssertEqual(shape.keyedOut, [WMPColor(red: 255, green: 0, blue: 255)],
                       "clippingColor only — a transparencyColor hole is where it is meant to show")
        XCTAssertEqual(shape.frame, WMPRect(x: 20, y: 30, width: 4, height: 4))
    }

    /// **`transparencyColor` alone must never become a silhouette.** A container that keys a hole
    /// *inside* itself has not said where its window ends, and reading it as one clips the surface
    /// away exactly where the skin means it to show — the W147/Cerulean inversion arriving by a
    /// third route. `groundShape` states the same rule for the `<EFFECTS>` ground.
    func testATransparencyColourAloneIsNotTheWindowShape() async throws {
        let keyed = try effectsWidget(in: try await scene(opening: .keyed))
        let threeState = try effectsWidget(in: try await scene(opening: .transparent))
        XCTAssertNil(keyed.clippingShape)
        XCTAssertNil(threeState.clippingShape)
    }

    /// The count the corpus sweep ranks on, against a fixture whose answer is arithmetic: the rect
    /// is the container's whole 4x4 frame, and the fixture's right half is the key on every row but
    /// the bottom one, which is opaque trim — so **6 of 16** pixels are cut. A container's artwork
    /// only states a shape when it is authored at the node's own size (`Gorillaz`), which is why
    /// both fixtures here are 4x4.
    func testOffShapePixelsCountsWhatTheSilhouetteRemovesFromTheRect() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <SUBVIEW id="face" left="0" top="0" width="4" height="4"
                     backgroundImage="lens.png" clippingColor="#FF00FF">
                <EFFECTS id="visEffects" left="0" top="0" width="4" height="4"/>
            </SUBVIEW>
        </VIEW></THEME>
        """, images: ["lens.png": try containerImage(opening: .keyed)])
        let store = try store(image: try containerImage(opening: .keyed))
        let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store).build(viewID: "main")
        let widget = try effectsWidget(in: scene)
        let shape = try XCTUnwrap(widget.clippingShape)

        XCTAssertEqual(WMPHarness.offShapePixels(widget: widget, shape: shape, imageStore: store), 6,
                       "the right half of the container, minus its opaque bottom row")
    }

    // MARK: - The mask's own polarity

    private func store(image: Data) throws -> WMPImageStore {
        WMPImageStore(provider: WMPMemoryResourceProvider(["lens.png": image]))
    }

    private func samples(_ mask: CGImage) -> [[UInt8]] {
        let width = mask.width, height = mask.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (0..<height).map { row in
            (0..<width).map { pixels[(row * width + $0) * 4] }
        }
    }

    /// 255 means keep. Row zero is the authored **top** — the same convention `WMPMappingImage` and
    /// the clipping mask already hold, and the reason `WMPEffectsSurfaceView` counter-flips before
    /// it clips rather than flipping the rows here.
    func testTheRegionMaskKeepsTheOpeningAndTheTrimAndCutsTheKeyedSurround() async throws {
        let store = try store(image: try containerImage(opening: .transparent))
        let mask = try store.regionMask(for: "lens.png",
                                        keyedOut: [WMPColor(red: 255, green: 0, blue: 255)])
        let rows = samples(mask)

        XCTAssertEqual(rows[0][0], 255, "a transparent pixel is the opening — inside the region")
        XCTAssertEqual(rows[0][3], 0, "a keyed pixel is the outside — cut away")
        XCTAssertEqual(rows[3][0], 255, "opaque trim is inside the region too")
    }

    /// **The shared mask builder must not have changed underneath `clippingImage`.** A clipping
    /// image reads a transparent pixel as *cut away*, which is the opposite of a region — 25 corpus
    /// skins author one, and this is the half of the function that was already shipping.
    func testAClippingMaskStillCutsTransparentPixelsWhileARegionKeepsThem() async throws {
        let store = try store(image: try containerImage(opening: .transparent))
        let keys = [WMPColor(red: 255, green: 0, blue: 255)]
        let clipping = samples(try store.clippingMask(for: "lens.png", keyedOut: keys))
        let region = samples(try store.regionMask(for: "lens.png", keyedOut: keys))

        XCTAssertEqual(clipping[0][0], 0, "a clipping image cuts a transparent pixel away")
        XCTAssertEqual(region[0][0], 255, "a region keeps it — this is the whole difference")
        XCTAssertEqual(clipping[0][3], 0, "both cut the key")
        XCTAssertEqual(region[0][3], 0)
        XCTAssertEqual(clipping[3][0], 255, "and both keep opaque paint")
        XCTAssertEqual(region[3][0], 255)
    }

    /// The predicate the whole rule turns on, stated directly against both shapes.
    func testOnlyAThreeStateImageShapesChildrenByRegion() async throws {
        let keys = [WMPColor(red: 255, green: 0, blue: 255)]
        let threeState = try store(image: try containerImage(opening: .transparent))
        let twoState = try store(image: try containerImage(opening: .keyed))

        XCTAssertTrue(try threeState.shapesChildrenByRegion(for: "lens.png", keyedOut: keys))
        XCTAssertFalse(try twoState.shapesChildrenByRegion(for: "lens.png", keyedOut: keys),
                       "artwork with a keyed hole — Cerulean's shape")
        XCTAssertFalse(try threeState.shapesChildrenByRegion(for: "lens.png", keyedOut: []),
                       "no key, nothing to read a shape out of")
    }
}
