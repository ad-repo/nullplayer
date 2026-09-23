import AppKit
import CoreGraphics
import XCTest
@testable import NullPlayer

/// **A side rail is frame even where most of its bitmap lies inside the hole.**
///
/// The whole-view frame drops a piece as the donor's furniture when it touches no edge of the view
/// and lies more than half inside the client hole. `Back to the Future Trilogy` bakes its list's
/// black into side tiles far wider than the rail they carry (`f_right_s.png` is 154px with the rail
/// in its outer 15), so both its right rails met that test and the library's right edge came out
/// bare. A piece authored as a rail — stretched along a side — that runs out past the side of the
/// hole it borders is kept.
final class WMPHostedFrameRailTests: XCTestCase {

    private static func sheet(_ width: Int, _ height: Int,
                              _ pixel: (Int) -> [UInt8]) throws -> Data {
        try WMPSkinTestSupport.encodedImage(width: width, height: height,
            rgba: (0..<(width * height)).flatMap { pixel($0 % width) })
    }

    private func artwork(_ markup: String) async throws -> SkinnedSurfaceFrameArtwork {
        let white = try Self.sheet(24, 24) { _ in [255, 255, 255, 255] }
        // 60 wide, opaque red only in its outer 20 columns: the rest is transparent, standing in
        // for the list's own interior colour that the skin's content covers.
        let rail = try Self.sheet(60, 8) { x in x >= 40 ? [255, 0, 0, 255] : [0, 0, 0, 0] }
        let entries = [WMPTestArchiveEntry("skin.wms", data: Data(markup.utf8)),
                       WMPTestArchiveEntry("corner.png", data: white),
                       WMPTestArchiveEntry("rail.png", data: rail)]
        let loaded = try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
        let template = try XCTUnwrap(WMPHostedFrameTemplate.derive(from: loaded, playerViewID: nil))
        let store = WMPImageStore(provider: loaded.archive)
        let drawn = try await template.artwork(
            builder: WMPSceneBuilder(loadedSkin: loaded, imageStore: store),
            renderer: WMPRenderer(imageStore: store),
            size: CGSize(width: 200, height: 200), backingScale: 1)
        return try XCTUnwrap(drawn)
    }

    private func isRed(_ image: CGImage, _ x: Int, _ y: Int) throws -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        let colour = try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        return colour.alphaComponent > 0.8 && colour.redComponent > 0.8 && colour.greenComponent < 0.2
    }

    private static func ring(rail: String) -> String {
        """
        <THEME><VIEW id="pl" width="200" height="200">
            <SUBVIEW left="10" top="10" width="jscript:view.width-40" height="jscript:view.height-20"
                     horizontalAlignment="stretch" verticalAlignment="stretch"
                     backgroundColor="#000000">
              <PLAYLIST id="list" left="0" top="0" width="160" height="180"/>
            </SUBVIEW>
            <SUBVIEW horizontalAlignment="left"  verticalAlignment="top"    backgroundImage="corner.png"/>
            <SUBVIEW left="176" horizontalAlignment="right" verticalAlignment="top"
                     backgroundImage="corner.png"/>
            <SUBVIEW top="176" horizontalAlignment="left" verticalAlignment="bottom"
                     backgroundImage="corner.png"/>
            <SUBVIEW left="176" top="176" horizontalAlignment="right" verticalAlignment="bottom"
                     backgroundImage="corner.png"/>
            \(rail)
        </VIEW></THEME>
        """
    }

    /// The rail's opaque column is at 170...189, outside the hole's right edge at 170, while two
    /// thirds of its frame lie inside it.
    func testAStretchedRailMostlyInsideTheHoleIsStillDrawn() async throws {
        let frame = try await artwork(Self.ring(rail: """
            <SUBVIEW left="130" top="24" width="60" height="152" horizontalAlignment="right"
                     verticalAlignment="stretch" backgroundImage="rail.png" backgroundTiled="true"/>
            """))
        XCTAssertTrue(try isRed(frame.image, 180, 100), "the rail was dropped as furniture")
    }

    /// The same bitmap, not authored to stretch, is a panel the donor put over its content — the
    /// `Alienware Invader` shape the furniture test exists for — and is still dropped.
    func testAnUnstretchedPieceInTheHoleIsStillFurniture() async throws {
        let frame = try await artwork(Self.ring(rail: """
            <SUBVIEW left="130" top="24" width="60" height="152" backgroundImage="rail.png"
                     backgroundTiled="true"/>
            """))
        XCTAssertFalse(try isRed(frame.image, 180, 100))
    }
}
