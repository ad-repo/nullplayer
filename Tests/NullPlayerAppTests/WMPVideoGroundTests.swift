import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// A `<VIDEO>`'s `backgroundColor` paints only over artwork already drawn beneath it (W312).
///
/// The fill is a surface inside the window, never part of its shape. This engine takes a window's
/// shape from what is painted, so a fill over bare canvas became `Navigator`'s grey box under its
/// wing. Over artwork it is the skin's authored well — `The Unit`'s black screen — and paints as
/// before.
final class WMPVideoGroundTests: XCTestCase {

    func testAVideoFillPaintsOverArtworkAndNotOverBareCanvas() async throws {
        let rgba = Array([[UInt8]](repeating: [40, 180, 40, 255], count: 30 * 40).joined())
        let wms = """
        <THEME><VIEW id="main" width="60" height="40" titleBar="false">
            <SUBVIEW id="art" left="0" top="0" width="30" height="40" backgroundImage="art.png"/>
            <VIDEO id="vid" zIndex="1" left="20" top="10" width="30" height="20"
                   backgroundColor="#404040"/>
        </VIEW></THEME>
        """
        let skin = try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8)),
            WMPTestArchiveEntry("art.png",
                                data: try WMPSkinTestSupport.encodedImage(width: 30, height: 40, rgba: rgba))
        ]))
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let rendered = try await WMPRenderer(imageStore: WMPImageStore(provider: skin.archive))
            .render(scene: scene)

        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered.image, x: 25, yFromTop: 20), [64, 64, 64, 255],
                       "over the skin's artwork the video ground paints as authored")
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered.image, x: 40, yFromTop: 20)[3], 0,
                       "over bare canvas it paints nothing, so it adds nothing to the window's shape")
        XCTAssertEqual(WMPSkinTestSupport.rgba(rendered.image, x: 10, yFromTop: 20), [40, 180, 40, 255],
                       "the artwork outside the video rect is untouched")
    }
}
