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
}
