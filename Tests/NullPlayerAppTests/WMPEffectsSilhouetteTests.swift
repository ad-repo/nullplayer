import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// Where a windowless `<EFFECTS>` surface may draw when the skin states no shape for it.
///
/// `livin_it_skate` hangs a 315x292 rect over a diagonal skateboard and shapes itself with
/// `transparencyColor` alone, so the corner of the rect the deck does not cover drew bars on the
/// desktop. `WMPRenderer.effectsSilhouette` cuts what the painted pixels do not *enclose*: the
/// matte connected to the canvas edge goes, a keyed hole inside the artwork stays.
final class WMPEffectsSilhouetteTests: XCTestCase {

    /// 40x40: a magenta band down the left edge (outside the skin), a magenta 8x8 hole in the
    /// middle (inside it), opaque artwork everywhere else.
    private func body(band: Bool) throws -> Data {
        var rgba: [UInt8] = []
        for y in 0..<40 {
            for x in 0..<40 {
                let outside = band && x < 8
                let hole = (16..<24).contains(x) && (16..<24).contains(y)
                rgba += outside || hole ? [255, 0, 255, 255] : [40, 180, 40, 255]
            }
        }
        return try WMPSkinTestSupport.encodedImage(width: 40, height: 40, rgba: rgba)
    }

    private func render(band: Bool) async throws -> WMPRenderResult {
        let wms = """
        <THEME><VIEW id="vis" width="40" height="40" titleBar="false" backgroundColor="none">
            <SUBVIEW id="board" zIndex="1" backgroundImage="body.png" transparencyColor="#FF00FF"/>
            <EFFECTS id="fx" zIndex="2" left="0" top="4" width="30" height="30"/>
        </VIEW></THEME>
        """
        let skin = try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8)),
            WMPTestArchiveEntry("body.png", data: try body(band: band))
        ]))
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "vis")
        XCTAssertEqual(scene.widgets.filter { $0.kind == .effects }.count, 1)
        return try await WMPRenderer(imageStore: WMPImageStore(provider: skin.archive))
            .render(scene: scene, backingScale: 2)
    }

    private func value(_ mask: CGImage, x: Int, y: Int) throws -> UInt8 {
        let data = try XCTUnwrap(mask.dataProvider?.data as Data?)
        return data[y * mask.bytesPerRow + x]
    }

    func testTheMatteOutsideTheSkinIsCutAndAnEnclosedHoleIsKept() async throws {
        let rendered = try await render(band: true)
        let mask = try XCTUnwrap(rendered.silhouetteMask)
        // Canvas resolution, whatever the backing scale.
        XCTAssertEqual(mask.width, 40)
        XCTAssertEqual(mask.height, 40)
        XCTAssertEqual(try value(mask, x: 2, y: 20), 0, "the band reaches the canvas edge")
        XCTAssertEqual(try value(mask, x: 20, y: 20), 255, "the hole is enclosed by the artwork")
        XCTAssertEqual(try value(mask, x: 12, y: 20), 255, "painted artwork")
    }

    func testARectTheSkinFullyEnclosesCarriesNoMask() async throws {
        let rendered = try await render(band: false)
        XCTAssertNil(rendered.silhouetteMask)
    }
}
