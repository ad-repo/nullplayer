import AppKit
import CoreGraphics
import XCTest
@testable import NullPlayer

/// The gate on the ring's **span repair**: which bare edge is a piece the frame build drew short,
/// and which is a keyed notch to be left alone (W212, W228).
///
/// `Alienware Invader` is the archive behind both rows. It sizes each rail in `onPlResize()`, which
/// the frame build never runs — the builder is outside the script runtime — so the borrowed ring
/// comes out with the **same 107pt** bare run down each side at every window size. Every number
/// below is measured: `WMP_HOSTED_FRAME=<size>` over the installed corpus, scale 2.
final class WMPHostedRingSpanTests: XCTestCase {

    /// **The regression, stated as the two windows that disagreed.** 107pt is 0.231 of a 464pt-tall
    /// window and 0.132 of the library browser's 810 — so the fraction alone repaired the identical
    /// hole on nine hosted windows and left it open on the tenth, which is the *"alien invader
    /// media library window draws broken"* report of 2026-09-18.
    func testTheSameBareRunIsAMissingPieceAtEveryWindowHeight() {
        for height in [CGFloat(291), 464, 640, 760, 810, 931, 1200] {
            let gap = 107 / height
            XCTAssertTrue(WMPHostedFrameTemplate.edgeCameOutBare(gap, along: height),
                          "a 107pt bare rail was read as a notch on a \(height)pt window")
        }
    }

    /// The fraction still answers on its own where the run is a large share of a short edge: a
    /// 30pt hole in a 150pt-tall analyser edge is a fifth of it and no keyed notch.
    func testALargeShareOfAShortEdgeIsStillAMissingPiece() {
        XCTAssertTrue(WMPHostedFrameTemplate.edgeCameOutBare(30 / 150, along: 150))
    }

    /// **And the point limit does not swallow the notches.** Over the 185 installed archives at
    /// 710x810 the rings that close run 0 to 24.3pt — rounded corners and keyed cut-outs — and the
    /// ones with a piece missing measure 49.7 (`Half-Life_2`), 85.2 (`Combat_Flight_Simulator_3`)
    /// and 106.9 (`Alienware Invader`). Nothing lies between, which is what 40 is picked out of.
    func testAKeyedNotchIsNotAMissingPiece() {
        for points in [CGFloat(1.6), 10.7, 17.8, 24.3] {
            for edge in [CGFloat(464), 810, 931] {
                XCTAssertFalse(WMPHostedFrameTemplate.edgeCameOutBare(points / edge, along: edge),
                               "a \(points)pt notch was read as a missing piece on a \(edge)pt edge")
            }
        }
    }

    /// A closed edge is closed.
    func testAClosedEdgeIsNeverRepaired() {
        XCTAssertFalse(WMPHostedFrameTemplate.edgeCameOutBare(0, along: 810))
    }

    /// **A strip its script sizes reaches the corner in its row (`Crimson_Skies`).** `plTopStretch`
    /// is tiled, declares no width and no alignment, so it lands in the top-left slot as an extra,
    /// and only `checkPlViewSize()` ever widens it. The frame build runs no script, so the strip kept
    /// its 4px bitmap width and the top edge opened between it and the right corner.
    func testAScriptSizedStripReachesTheCornerInItsRow() async throws {
        func sheet(_ width: Int, _ height: Int) throws -> Data {
            try WMPSkinTestSupport.encodedImage(width: width, height: height, rgba: [UInt8](
                (0..<(width * height)).flatMap { _ in [UInt8(255), 0, 0, 255] }))
        }
        let markup = """
            <THEME><VIEW id="plView" width="200" height="200" minWidth="200" minHeight="200">
              <SUBVIEW id="client" left="10" top="30" width="180" height="140"
                       horizontalAlignment="stretch" verticalAlignment="stretch">
                <PLAYLIST id="list" left="0" top="0" width="180" height="140"/>
              </SUBVIEW>
              <SUBVIEW backgroundImage="corner.png"/>
              <SUBVIEW left="176" horizontalAlignment="right" backgroundImage="corner.png"/>
              <SUBVIEW top="176" verticalAlignment="bottom" backgroundImage="corner.png"/>
              <SUBVIEW left="176" top="176" horizontalAlignment="right" verticalAlignment="bottom"
                       backgroundImage="corner.png"/>
              <SUBVIEW top="24" verticalAlignment="stretch" backgroundImage="rail.png"
                       backgroundTiled="true"/>
              <SUBVIEW left="176" top="24" horizontalAlignment="right" verticalAlignment="stretch"
                       backgroundImage="rail.png" backgroundTiled="true"/>
              <SUBVIEW left="24" top="176" verticalAlignment="bottom" horizontalAlignment="stretch"
                       backgroundImage="bar.png" backgroundTiled="true"/>
              <SUBVIEW id="strip" left="24" backgroundImage="bar.png" backgroundTiled="true"/>
            </VIEW></THEME>
            """
        let entries = [WMPTestArchiveEntry("skin.wms", data: Data(markup.utf8)),
                       WMPTestArchiveEntry("corner.png", data: try sheet(24, 24)),
                       WMPTestArchiveEntry("rail.png", data: try sheet(24, 4)),
                       WMPTestArchiveEntry("bar.png", data: try sheet(4, 24))]
        let loaded = try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
        let template = try XCTUnwrap(WMPHostedFrameTemplate.derive(from: loaded, playerViewID: nil))
        XCTAssertEqual(template.spannedAcrossNodeIDs.count, 1)
        let store = WMPImageStore(provider: loaded.archive)
        let drawn = try await template.artwork(
            builder: WMPSceneBuilder(loadedSkin: loaded, imageStore: store),
            renderer: WMPRenderer(imageStore: store),
            size: CGSize(width: 320, height: 200), backingScale: 1)
        let image = try XCTUnwrap(drawn).image
        let alpha = NSBitmapImageRep(cgImage: image).colorAt(x: 200, y: 4)?.alphaComponent ?? 0
        XCTAssertGreaterThan(alpha, 0.9, "the top edge is bare between the strip and the corner")
    }
}
