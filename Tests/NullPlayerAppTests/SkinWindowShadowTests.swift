import CoreGraphics
import XCTest
@testable import NullPlayer

/// The window drop shadow: the shadow image itself, and the `.wmz` signal that decides when it is
/// rebuilt. The `.wal` signal is the canvas's (`WinampModernCanvasTests`).
final class SkinWindowShadowTests: XCTestCase {

    // MARK: - Fixtures

    /// An alpha plane, top row first, from a closure answering each pixel's alpha.
    private func plane(width: Int, height: Int, alpha: (Int, Int) -> UInt8) -> AlphaPlane {
        AlphaPlane(width: width, height: height,
                   bytes: (0..<width * height).map { alpha($0 % width, $0 / width) })
    }

    /// The same plane as a premultiplied black image.
    private func maskImage(width: Int, height: Int, alpha: (Int, Int) -> UInt8) throws -> CGImage {
        try XCTUnwrap(plane(width: width, height: height, alpha: alpha).blackImage())
    }

    private func alpha(_ image: CGImage, x: Int, yFromTop: Int) -> UInt8 {
        WMPSkinTestSupport.rgba(image, x: x, yFromTop: yFromTop)[3]
    }

    // MARK: - The shadow image

    /// A 40x40 window: an opaque 20x20 body, a translucent strip above it (alpha 128) and a faint
    /// skin-drawn glow beside it (alpha 8), shadowed with a 30 px pad — so the body sits at
    /// (40...59, 40...59) in the output.
    private func shadowOfFixture() throws -> CGImage {
        let fixture = plane(width: 40, height: 40) { x, y in
            if (10..<30).contains(x), (10..<30).contains(y) { return 255 }
            if (10..<30).contains(x), (0..<10).contains(y) { return 128 }
            if (30..<40).contains(x), (10..<30).contains(y) { return 8 }
            return 0
        }
        return try XCTUnwrap(SkinWindowShadow.makeShadowImage(
            plane: fixture, blur: 12, offset: CGSize(width: 0, height: -4), opacity: 0.35, pad: 30))
    }

    func testTheShadowIsPaddedOnEverySide() throws {
        let shadow = try shadowOfFixture()
        XCTAssertEqual(shadow.width, 100)
        XCTAssertEqual(shadow.height, 100)
    }

    func testNothingIsLeftUnderSolidArt() throws {
        let shadow = try shadowOfFixture()
        for (x, y) in [(40, 40), (50, 50), (59, 59)] {
            XCTAssertEqual(alpha(shadow, x: x, yFromTop: y), 0, "under the body at (\(x),\(y))")
        }
    }

    /// Translucent art is not darkened from behind: alpha 128 clears the shadow as solid art does.
    func testTranslucentArtClearsTheShadowUnderIt() throws {
        let shadow = try shadowOfFixture()
        XCTAssertEqual(alpha(shadow, x: 50, yFromTop: 35), 0)
    }

    /// **The reported white band.** A skin's own faint glow must not cut the real shadow away from
    /// under it: Corona's alpha-1-to-60 glow did, and the desktop showed through as a white band.
    func testAFaintGlowLeavesTheShadowUnderIt() throws {
        let shadow = try shadowOfFixture()
        XCTAssertGreaterThan(alpha(shadow, x: 62, yFromTop: 50), 0)
    }

    func testTheShadowFallsOutsideTheOutlineAndFadesBeforeThePad() throws {
        let shadow = try shadowOfFixture()
        XCTAssertGreaterThan(alpha(shadow, x: 50, yFromTop: 63), 0, "just below the body")
        XCTAssertEqual(alpha(shadow, x: 0, yFromTop: 0), 0, "the far corner of the pad")
        XCTAssertEqual(alpha(shadow, x: 99, yFromTop: 99), 0, "the opposite corner")
    }

    func testTheKnockoutRampsFromFaintToSolid() {
        XCTAssertEqual(SkinWindowShadow.knockoutAlpha(0), 0)
        XCTAssertEqual(SkinWindowShadow.knockoutAlpha(16), 0, "a faint pixel clears nothing")
        XCTAssertGreaterThan(SkinWindowShadow.knockoutAlpha(17), 0)
        XCTAssertLessThan(SkinWindowShadow.knockoutAlpha(72), 255, "translucent clears in part")
        XCTAssertEqual(SkinWindowShadow.knockoutAlpha(128), 255)
        XCTAssertEqual(SkinWindowShadow.knockoutAlpha(255), 255)
    }

    /// The outline is the union of every layer handed over — a `.wmz` artwork and its overlay.
    func testTheOutlineIsEveryLayerTogether() throws {
        let left = try maskImage(width: 4, height: 1) { x, _ in x < 2 ? 255 : 0 }
        let right = try maskImage(width: 4, height: 1) { x, _ in x >= 2 ? 255 : 0 }
        let union = try XCTUnwrap(AlphaPlane(layers: [left, right], width: 4, height: 1))
        XCTAssertEqual(union.bytes, [255, 255, 255, 255])
    }

    // MARK: - `.wmz`: which repaints may have moved the outline

    private func marqueeArchive(background: String) throws -> URL {
        try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="120" height="20" \(background)>
              <TEXT id="meta" left="10" top="4" width="30" height="12" fontSize="10"
                    foregroundColor="#FFFFFF" value="MMMMMMMMMMMMMMMMMMMMMMMM"
                    scrolling="true" scrollingDelay="50" scrollingAmount="2"/>
            </VIEW></THEME>
            """.utf8))
        ])
    }

    private func marqueeRenders(background: String)
        async throws -> (whole: WMPRenderResult, repaint: WMPRenderResult) {
        let skin = try await WMPSkinLoader().load(from: try marqueeArchive(background: background))
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let renderer = WMPRenderer(imageStore: WMPImageStore(provider: skin.archive))
        let dirty = try XCTUnwrap(renderer.animationCadence(for: scene)).bounds
        let whole = try await renderer.render(scene: scene, clock: 0)
        let repaint = try await renderer.render(scene: scene, clock: 0.37, reusing: whole, dirty: dirty)
        return (whole, repaint)
    }

    /// A marquee over opaque artwork repaints 12 times a second and never moves the outline, so it
    /// must never ask for the shadow to be rebuilt.
    func testAMarqueeOverOpaqueArtLeavesTheOutlineAlone() async throws {
        let renders = try await marqueeRenders(background: ##"backgroundColor="#000000""##)
        XCTAssertTrue(renders.whole.alphaChanged, "a whole render always may have")
        XCTAssertFalse(renders.repaint.alphaChanged)
    }

    /// The same marquee over bare canvas is the outline: its glyphs are the window's only pixels.
    func testAMarqueeOverBareCanvasMovesTheOutline() async throws {
        let renders = try await marqueeRenders(background: "")
        XCTAssertTrue(renders.repaint.alphaChanged)
    }
}
