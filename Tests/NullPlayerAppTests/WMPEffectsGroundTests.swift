import CoreGraphics
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import NullPlayer

/// What is behind an `<EFFECTS>` rect when the skin painted nothing there (W174).
///
/// A `<VIEW>` that declares both `clippingColor` and `transparencyColor` has said two different
/// things: the clipping colour is the matte outside the window's silhouette, and the transparency
/// colour is a hole *inside* it. Keying both straight out of the artwork makes the second one a
/// hole through a borderless `isOpaque = false` window — `Ovoid`'s reported screen, *"missing its
/// backing in the center, it click through to the desktop"*. What belongs in a hole inside the
/// window is the control behind it, and WMP's visualization control has a black ground.
///
/// **The shape is what keeps the ground from becoming a slab, and only an ancestor's
/// `clippingColor` states it.** A container that shapes itself with `transparencyColor` alone has
/// not distinguished the outside from a hole, and a ground keyed off that would paint black
/// outside the skin — `Plus! BubbleSkin` by 44% of its rect. That is the second test here. The
/// ancestor half has its own corpus reason: `circle` declares its rect and the vis field keying a
/// hole in it as siblings, and that field's magenta is a one-pixel antialias fringe between the
/// field and the red matte rather than a screen.
final class WMPEffectsGroundTests: XCTestCase {

    /// A 40x40 ground bitmap in three colours, which is the corpus idiom: `#FF0000` outside the
    /// silhouette (the left column band), `#FF00FF` for the screen (the 20x20 centre), and opaque
    /// artwork everywhere else.
    private func background(clipped: Bool) throws -> Data {
        var rgba: [UInt8] = []
        for y in 0..<40 {
            for x in 0..<40 {
                let outside = clipped && x < 6
                let screen = (10..<30).contains(x) && (10..<30).contains(y)
                switch (outside, screen) {
                case (true, _): rgba += [255, 0, 0, 255]
                case (_, true): rgba += [255, 0, 255, 255]
                default: rgba += [40, 180, 40, 255]
                }
            }
        }
        return try WMPSkinTestSupport.encodedImage(width: 40, height: 40, rgba: rgba)
    }

    private func scene(clippingColor: String?) async throws -> (WMPLoadedSkin, WMPScene) {
        let keys = clippingColor.map { #"clippingColor="\#($0)" "# } ?? ""
        let wms = """
        <THEME><VIEW id="vis" width="40" height="40" titleBar="false"
                     backgroundImage="body.png" \(keys)transparencyColor="#FF00FF">
            <EFFECTS id="myeffects" zIndex="-1" left="10" top="10" width="20" height="20"/>
        </VIEW></THEME>
        """
        let skin = try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8)),
            WMPTestArchiveEntry("body.png", data: try background(clipped: clippingColor != nil))
        ]))
        return (skin, try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "vis"))
    }

    /// The reported pixel. The screen is opaque black afterwards, which is both halves of the
    /// report at once: there is something to see, and the window server has a pixel to hit-test.
    /// The matte outside the silhouette stays a hole — that is where the window genuinely is not.
    func testAnEffectsRectOverAKeyedHoleIsBackedByItsOwnGroundAndTheMatteIsNot() async throws {
        let (skin, scene) = try await scene(clippingColor: "#FF0000")
        XCTAssertEqual(scene.effectsGrounds.count, 1,
                       "the view states a shape, so the rect has a ground")
        XCTAssertEqual(scene.effectsGrounds.first?.color, WMPColor(red: 0, green: 0, blue: 0),
                       "black is WMP's own, and the two corpus rects that restate it write #000000")

        let store = WMPImageStore(provider: skin.archive)
        let rendered = try await WMPRenderer(imageStore: store).render(scene: scene)
        let flat = try flatten(rendered, size: 40)

        XCTAssertEqual(WMPSkinTestSupport.rgba(flat, x: 20, yFromTop: 20), [0, 0, 0, 255],
                       "the screen is the visualizer's ground, not a hole to the desktop")
        XCTAssertEqual(WMPSkinTestSupport.rgba(flat, x: 2, yFromTop: 20)[3], 0,
                       "and the clipping matte is still where the window is not")
        XCTAssertEqual(WMPSkinTestSupport.rgba(flat, x: 35, yFromTop: 20), [40, 180, 40, 255],
                       "the skin's own artwork is untouched")
    }

    /// The guard. The same markup with no `clippingColor` shapes itself by the transparency key
    /// alone, so nothing separates the screen from the outside and no ground may be laid at all.
    func testAContainerThatStatesNoClippingColourGroundsNothing() async throws {
        let (skin, scene) = try await scene(clippingColor: nil)
        XCTAssertTrue(scene.effectsGrounds.isEmpty,
                      "transparencyColor alone has not said which hole is the outside")

        let store = WMPImageStore(provider: skin.archive)
        let rendered = try await WMPRenderer(imageStore: store).render(scene: scene)
        let flat = try flatten(rendered, size: 40)
        XCTAssertEqual(WMPSkinTestSupport.rgba(flat, x: 20, yFromTop: 20)[3], 0,
                       "so the rect renders exactly as it always has")
    }

    /// A rect the skin backs itself takes no ground of ours — which is the whole of W9's rule, and
    /// why 78 of the corpus's 95 effects rects render byte-identically.
    func testARectWithArtworkBehindItKeepsTheArtwork() async throws {
        let wms = """
        <THEME><VIEW id="vis" width="40" height="40" titleBar="false"
                     backgroundImage="body.png" clippingColor="#FF0000" transparencyColor="#FF00FF">
            <SUBVIEW id="screen" left="10" top="10" width="20" height="20"
                     backgroundColor="#0000FF"/>
            <EFFECTS id="myeffects" left="10" top="10" width="20" height="20"/>
        </VIEW></THEME>
        """
        let skin = try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8)),
            WMPTestArchiveEntry("body.png", data: try background(clipped: true))
        ]))
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "vis")
        let store = WMPImageStore(provider: skin.archive)
        let flat = try flatten(try await WMPRenderer(imageStore: store).render(scene: scene), size: 40)
        XCTAssertEqual(WMPSkinTestSupport.rgba(flat, x: 20, yFromTop: 20), [0, 0, 255, 255],
                       "the ground is laid under the below layer, never over it")
    }

    /// The renderer's two layers composited back into one, which is what a viewer sees.
    private func flatten(_ result: WMPRenderResult, size: Int) throws -> CGImage {
        guard let overlay = result.overlayImage else { return result.image }
        let context = try XCTUnwrap(CGContext(data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue))
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        context.draw(result.image, in: rect)
        context.draw(overlay, in: rect)
        return try XCTUnwrap(context.makeImage())
    }
}
