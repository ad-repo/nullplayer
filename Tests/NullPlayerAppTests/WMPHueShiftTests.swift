import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// **W173 — `hueShift`, the property a skin is named after.**
///
/// `Plus! HueShifter` is one archive in the corpus of 180 and the only one that uses this: 10
/// writes, all of them from script. Its paintbrush button is `changeHue()`, which steps a JS global
/// by `360.0 / 11` and assigns it to the five "candy" pieces ringing the player — `topCandy`,
/// `botCandy`, `leftCandy`, `rightCandy`, `botCandyFacade` — so the ring cycles through the
/// spectrum. The property was unimplemented, so every write was inert and the candies were frozen
/// at their native green. Reported as *"is it supposed to be green or not because it still is"*;
/// the green **is** the artwork — the skin's own `hueshifter_final.jpg` shows it — and the defect
/// was that it could never be anything else.
///
/// **The unit is degrees and the skin is the authority.** `changeHue()` offers ten stops at 33°,
/// 65°, 98° … 327° and `savePrefs` clamps to `0…360`. Read as -1…1 every one of those would clamp
/// to the same value and the button would do nothing visible, which is not what Microsoft shipped.
final class WMPHueShiftTests: XCTestCase {

    // MARK: - Fixtures

    private func flat(_ colour: [UInt8], size: Int = 4) throws -> Data {
        try WMPSkinTestSupport.encodedImage(width: size, height: size,
            rgba: Array(repeating: colour, count: size * size).flatMap { $0 })
    }

    private func load(wms: String, images: [String: Data]) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]
        entries += images.map { WMPTestArchiveEntry($0.key, data: $0.value) }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    private func image(_ rgba: [UInt8], width: Int, height: Int) throws -> CGImage {
        let data = try WMPSkinTestSupport.encodedImage(width: width, height: height, rgba: rgba)
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCreateImageAtIndex(source, 0, nil)!
    }

    private func pixel(_ image: CGImage, x: Int = 0, y: Int = 0) -> [UInt8] {
        WMPSkinTestSupport.rgba(image, x: x, yFromTop: y)
    }

    /// The luma the rotation is defined to preserve — the SVG/CSS `hue-rotate` weights, which are
    /// the axis the chroma turns about.
    private func luma(_ rgba: [UInt8]) -> Double {
        0.213 * Double(rgba[0]) + 0.715 * Double(rgba[1]) + 0.072 * Double(rgba[2])
    }

    // MARK: - The angle

    /// 0 and 360 are both "no shift", a negative angle wraps forward, and past a full turn it wraps
    /// back — which is what makes the skin's own `currHue` bookkeeping harmless whatever it saves.
    func testTheAngleWraps() {
        XCTAssertEqual(WMPImageStore.canonicalHueShift(0), 0)
        XCTAssertEqual(WMPImageStore.canonicalHueShift(360), 0)
        XCTAssertEqual(WMPImageStore.canonicalHueShift(33), 33)
        XCTAssertEqual(WMPImageStore.canonicalHueShift(-30), 330)
        XCTAssertEqual(WMPImageStore.canonicalHueShift(393), 33)
        XCTAssertEqual(WMPImageStore.canonicalHueShift(.nan), 0, "a bad write is no shift, not a crash")
        XCTAssertEqual(WMPImageStore.canonicalHueShift(.infinity), 0)
    }

    // MARK: - The rotation

    /// 120° around the wheel takes red to green and green to blue — the defining property of a hue
    /// rotation, and the one a wrong matrix fails outright. The first version of this used the NTSC
    /// YIQ constants and rotated the other way: red to *blue*, (24, 42, 255) where every other
    /// implementation of `hue-rotate` gives (0, 113, 0).
    func testAThirdOfATurnWalksThePrimaries() throws {
        let red = try image([255, 0, 0, 255], width: 1, height: 1)
        let rotated = try XCTUnwrap(WMPImageStore.hueRotated(red, degrees: 120))
        let result = pixel(rotated)
        XCTAssertGreaterThan(result[1], result[0], "green now dominates")
        XCTAssertGreaterThan(result[1], result[2])

        let green = try image([0, 255, 0, 255], width: 1, height: 1)
        let twice = try XCTUnwrap(WMPImageStore.hueRotated(green, degrees: 120))
        let blued = pixel(twice)
        XCTAssertGreaterThan(blued[2], blued[0], "blue now dominates")
        XCTAssertGreaterThan(blued[2], blued[1])
    }

    /// **Luminance survives, which is why the artwork's shading does.** The matrix turns the chroma
    /// about the luma axis and leaves the axis itself alone; going via HSB instead would quantise
    /// twice and drift the greys, and on artwork as soft as these candies that reads as banding.
    ///
    /// Measured at all ten stops `changeHue()` offers, on in-gamut colours: the worst drift is 0.45
    /// of 255, which is rounding. **A fully saturated pixel is the exception and always will be** —
    /// no hue rotation can keep one in gamut, so it clips and loses luma (flat `#C8283C` drifts 10,
    /// the candies' brightest green 29). That is inherent to the operation, not to this matrix.
    func testLuminanceIsPreserved() throws {
        for colour in [[180, 120, 140, 255], [120, 180, 140, 255], [140, 120, 180, 255]] as [[UInt8]] {
            let source = try image(colour, width: 1, height: 1)
            for degrees in [33, 65, 98, 131, 164, 196, 229, 262, 295, 327] {
                let rotated = try XCTUnwrap(WMPImageStore.hueRotated(source, degrees: degrees))
                XCTAssertEqual(luma(pixel(rotated)), luma(colour), accuracy: 1,
                               "\(colour) at \(degrees)deg")
            }
        }
    }

    /// A grey has no hue to rotate, so every angle must leave it exactly where it was. This is the
    /// guard that a rotation is not quietly a saturation or gamma change: the candies' black wedges
    /// and white specular highlight are greys and must not move.
    func testGreysDoNotMove() throws {
        for value: UInt8 in [0, 64, 128, 200, 255] {
            let source = try image([value, value, value, 255], width: 1, height: 1)
            let rotated = try XCTUnwrap(WMPImageStore.hueRotated(source, degrees: 164))
            let result = pixel(rotated)
            XCTAssertEqual(Int(result[0]), Int(value), accuracy: 2, "grey \(value)")
            XCTAssertEqual(Int(result[1]), Int(value), accuracy: 2)
            XCTAssertEqual(Int(result[2]), Int(value), accuracy: 2)
        }
    }

    /// **Alpha is untouched, and the colour is un-premultiplied across the matrix.** Rotating
    /// premultiplied colour scales the result by its own alpha and fringes every keyed silhouette —
    /// these candies are cut out by a mask on all four sides.
    func testAlphaSurvivesAndDoesNotTintTheResult() throws {
        let opaque = try image([220, 30, 30, 255], width: 1, height: 1)
        let faded = try image([220, 30, 30, 128], width: 1, height: 1)
        let rotatedOpaque = pixel(try XCTUnwrap(WMPImageStore.hueRotated(opaque, degrees: 98)))
        let rotatedFaded = pixel(try XCTUnwrap(WMPImageStore.hueRotated(faded, degrees: 98)))

        XCTAssertEqual(Int(rotatedFaded[3]), 128, "the alpha channel is carried through untouched")
        for channel in 0..<3 {
            XCTAssertEqual(Int(rotatedFaded[channel]), Int(rotatedOpaque[channel]), accuracy: 3,
                           "the same colour resolves the same way at any alpha")
        }

        let clear = try image([220, 30, 30, 0], width: 1, height: 1)
        XCTAssertEqual(pixel(try XCTUnwrap(WMPImageStore.hueRotated(clear, degrees: 98)))[3], 0)
    }

    // MARK: - Reaching the draw

    /// The authored attribute reaches `WMPSceneImage`, and a node that declares none is 0 — which
    /// is every other draw in the corpus and the reason a sweep over it is byte-identical.
    func testTheAuthoredAttributeReachesTheSceneAndDefaultsToZero() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="4" height="8">
            <BUTTON id="shifted" left="0" top="0" width="4" height="4" image="art.png" hueShift="120"/>
            <BUTTON id="plain" left="0" top="4" width="4" height="4" image="art.png"/>
        </VIEW></THEME>
        """, images: ["art.png": try flat([255, 0, 0, 255])])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        func hue(_ nodeID: String) throws -> Double {
            let command = try XCTUnwrap(scene.commands.first { $0.nodeID == nodeID })
            guard case let .image(specification) = command.paint else {
                throw XCTSkip("\(nodeID) is not an image command")
            }
            return specification.hueShift
        }
        XCTAssertEqual(try hue("shifted"), 120)
        XCTAssertEqual(try hue("plain"), 0)
    }

    /// End to end: the rotation lands in the rendered pixels, not merely in the scene.
    func testTheRotationReachesTheRenderedPixels() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="4" height="4">
            <BUTTON id="art" left="0" top="0" width="4" height="4" image="art.png" hueShift="120"/>
        </VIEW></THEME>
        """, images: ["art.png": try flat([255, 0, 0, 255])])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let rendered = try await WMPRenderer(imageStore: WMPImageStore(provider: skin.archive))
            .render(scene: scene).image

        let drawn = WMPSkinTestSupport.rgba(rendered, x: 1, yFromTop: 1)
        XCTAssertGreaterThan(drawn[1], drawn[0], "the red sprite draws green")
        XCTAssertGreaterThan(drawn[1], drawn[2])
    }

    /// **`hueShift` is a script property first, and a write to it has to commit as a mutation.**
    /// No corpus node authors it; all ten uses are assignments from a handler. Stored inert it
    /// would never reach the scene, which is exactly what the defect was.
    func testAScriptWriteCommitsAsAMutation() {
        XCTAssertTrue(WMPObjectModel.standardNumericProperties.contains("hueshift"))
        XCTAssertTrue(WMPObjectModel.standardElementProperties.contains("hueshift"))
    }

    /// Two elements at different angles must not share one cached bitmap — the store keys the
    /// decode on the angle, and `HueShifter` drives five elements from one image.
    func testTwoAnglesOfOneBitmapAreSeparateCacheEntries() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="4" height="4"/></THEME>
        """, images: ["art.png": try flat([255, 0, 0, 255])])
        let store = WMPImageStore(provider: skin.archive)

        let plain = try store.image(for: "art.png").image
        let shifted = try store.image(for: "art.png", hueShift: 120).image
        let again = try store.image(for: "art.png", hueShift: 120).image

        XCTAssertNotEqual(pixel(plain), pixel(shifted), "the angle is part of the key")
        XCTAssertEqual(pixel(shifted), pixel(again), "and the second read is the cached one")
        XCTAssertEqual(pixel(try store.image(for: "art.png").image), pixel(plain),
                       "the unshifted entry is still its own")
    }
}
