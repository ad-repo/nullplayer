import XCTest
@testable import NullPlayer

/// W193 — `view.size(corner)`, the only resize a borderless `.wmz` window has.
///
/// The gesture itself is a window drag and cannot be measured without one; what is pinned here is
/// the mapping every one of the corpus's 235 calls goes through, and the axis convention it has to
/// agree with. `WMPMainView.edges(at:)` reads the view's *flipped* y — a point at the visual bottom
/// inserts `.bottom` — and `dragWindowResize` moves the window origin for `.left` and `.bottom`, so
/// a skin's `bottomright` has to mean the visually-bottom-right corner and not the screen's.
final class WMPScriptResizeTests: XCTestCase {

    /// Every spelling the 88 archives author, with its count in the installed corpus.
    func testEveryAuthoredCornerResolvesToItsOwnEdges() {
        let cases: [(String, WMPWindowEdges)] = [
            ("bottomright", [.bottom, .right]),   // 86 archives
            ("topright", [.top, .right]),         // 4
            ("right", [.right]),                  // 3
            ("bottom", [.bottom]),                // 2
            ("bottomleft", [.bottom, .left]),     // 2
            ("left", [.left]),                    // 2
            ("topleft", [.top, .left]),           // 2
        ]
        for (corner, expected) in cases {
            XCTAssertEqual(WMPMainView.edges(forCorner: corner), expected, "corner \(corner)")
        }
    }

    /// `Compact` writes `view.size( 'bottomright' )` and `Revert` `view.size("TopLeft")`: the
    /// argument is a string literal a skin author typed, so case and stray space are not signals.
    func testCornerMatchingIgnoresCaseAndSurroundingSpace() {
        XCTAssertEqual(WMPMainView.edges(forCorner: "BottomRight"), [.bottom, .right])
        XCTAssertEqual(WMPMainView.edges(forCorner: " TopLeft "), [.top, .left])
    }

    /// An empty or unrecognised corner arms nothing. `beginScriptResize` refuses on an empty set
    /// rather than falling back to a default edge: a drag the skin did not ask for is worse than
    /// the dead call this row replaced.
    func testAnUnknownCornerArmsNoEdge() {
        for corner in ["", "middle", "centre", "sizenwse"] {
            XCTAssertTrue(WMPMainView.edges(forCorner: corner).isEmpty, "corner \(corner)")
        }
    }
}
