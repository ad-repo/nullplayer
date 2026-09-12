import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// What may be drawn **over** a visualization, which `<EFFECTS>` answers in two opposite ways.
///
/// A windowless surface is composited into the artwork at its own place in the paint order, and the
/// skin draws over it on purpose: Cerulean puts `<effects zIndex="-1">` behind a colour-keyed hole
/// in `face.bmp`, which is what `WMPWidget.commandSplitIndex` exists for. A **windowed** one is a
/// real child window in WMP and nothing the skin paints can be layered on it at all — which is why
/// 106 corpus skins say `windowed="false"` and only 17 say `true`.
///
/// Treating every surface as windowless is W144 in `docs/wmp-skin/wmp-backlog-archive.md`
/// § *Phase 15*. **Note which instrument settles this:** a render dump is deliberately flat
/// (`WMPRenderer.dump` passes `splitAtEffects: false`, so the PNG is the whole artwork in one pass)
/// and can never show the occlusion. `WMP_RENDER_APPKIT` hosts the real view stack and can.
final class WMPEffectsOcclusionTests: XCTestCase {

    private func load(wms: String) async throws -> WMPLoadedSkin {
        try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(
            [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]))
    }

    /// The xsn_sports shape, reduced: a black pane with the visualization in it, and a piece of
    /// skin artwork declared *after* it that overlaps the pane. The `zIndex` values are the skin's
    /// own — the drawer at 17 is walked after the mask at 15, so the drawer lands in the overlay.
    private func scene(windowed: String) async throws -> (WMPLoadedSkin, WMPScene) {
        let skin = try await load(wms: """
        <THEME><VIEW id="vis" width="200" height="200" backgroundColor="#202020">
            <SUBVIEW id="mask" zIndex="15" left="20" top="20" width="160" height="100"
                     backgroundColor="#000000">
                <EFFECTS id="visEffects" zIndex="25" left="0" top="0" width="160" height="100"
                         \(windowed)/>
            </SUBVIEW>
            <SUBVIEW id="drawer" zIndex="17" left="20" top="80" width="160" height="100"
                     backgroundColor="#FF0000"/>
        </VIEW></THEME>
        """)
        return (skin, try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "vis"))
    }

    /// Both halves of the split are still there for a windowed surface — it is hosted between two
    /// rasters exactly as a windowless one is. Only what the upper raster is allowed to cover
    /// changes.
    func testAWindowedEffectsDeclaresAnOcclusionRectAndAWindowlessOneDoesNot() async throws {
        let (_, windowed) = try await scene(windowed: #"windowed="true""#)
        XCTAssertEqual(windowed.windowedEffectsRects.count, 1,
                       "a windowed surface occludes the artwork in its own rect")
        XCTAssertEqual(windowed.windowedEffectsRects.first?.width, 160)
        XCTAssertEqual(windowed.windowedEffectsRects.first?.height, 100)
        XCTAssertNotNil(windowed.effectsCommandSplitIndex,
                        "the surface is still hosted between two rasters")

        for spelling in [#"windowed="false""#, ""] {
            let (_, windowless) = try await scene(windowed: spelling)
            XCTAssertTrue(windowless.windowedEffectsRects.isEmpty,
                          "windowless is the default and the common case (\(spelling.isEmpty ? "absent" : spelling))")
            XCTAssertNotNil(windowless.effectsCommandSplitIndex)
        }
    }

    /// The pixel the report was about. `xsn_sports` retracts its settings drawer to a resting
    /// position 26px inside the bottom of the effects rect, and the drawer's own background
    /// (`vis_drawer_1.png` pictures a button and a slider row) was drawn across the bottom of the
    /// visualization while the drawer was shut.
    ///
    /// The assertion is on the **overlay**, because that is the raster hosted above the surface.
    /// Clearing rather than dropping it is what keeps the rest of the artwork right: the drawer
    /// continues below the effects rect, and that part must still draw.
    func testWindowedOcclusionClearsTheOverlayInsideTheRectAndKeepsItOutside() async throws {
        func overlaySamples(windowed: String) async throws -> (inside: UInt8, outside: UInt8) {
            let (skin, scene) = try await scene(windowed: windowed)
            let store = WMPImageStore(provider: skin.archive)
            let rendered = try await WMPRenderer(imageStore: store).render(scene: scene)
            let overlay = try XCTUnwrap(rendered.overlayImage,
                                        "a scene hosting an <EFFECTS> renders two layers")
            // (100, 100) is inside the effects rect and inside the drawer; (100, 160) is inside the
            // drawer and below the rect. Alpha is what the punch-out removes.
            return (try alpha(of: overlay, x: 100, y: 100), try alpha(of: overlay, x: 100, y: 160))
        }

        let windowed = try await overlaySamples(windowed: #"windowed="true""#)
        XCTAssertEqual(windowed.inside, 0,
                       "skin artwork is not drawn over a windowed visualization")
        XCTAssertEqual(windowed.outside, 255,
                       "and the same piece still draws everywhere the surface is not")

        let windowless = try await overlaySamples(windowed: #"windowed="false""#)
        XCTAssertEqual(windowless.inside, 255,
                       "a windowless surface is one the skin is meant to draw over — Cerulean's hole")
        XCTAssertEqual(windowless.outside, 255)
    }

    private func alpha(of image: CGImage, x: Int, y: Int) throws -> UInt8 {
        var pixel: [UInt8] = [0, 0, 0, 0]
        let context = try XCTUnwrap(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y),
                                       width: image.width, height: image.height))
        return pixel[3]
    }
}
