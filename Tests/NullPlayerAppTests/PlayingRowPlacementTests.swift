import XCTest
@testable import NullPlayer

/// The one placement rule every playlist follows the playing track by, in the points the Classic and
/// Original playlists scroll in (the `.wal` and `.wmz` row cases live with their surfaces' tests).
final class PlayingRowPlacementTests: XCTestCase {
    /// 18pt rows in a 90pt list (five rows) over 20 rows of content.
    private func offset(_ placement: PlayingRowPlacement, row: Int, current: CGFloat) -> CGFloat {
        placement.offset(itemTop: CGFloat(row) * 18, itemHeight: 18, viewport: 90, current: current,
                         contentHeight: 20 * 18)
    }

    func testEdgeMovesTheLeastAndLeavesAVisibleRowAlone() {
        XCTAssertEqual(offset(.edge, row: 9, current: 0), 10 * 18 - 90, "row 9 lands on the bottom edge")
        XCTAssertEqual(offset(.edge, row: 7, current: 90), 90, "already on screen")
        XCTAssertEqual(offset(.edge, row: 2, current: 90), 2 * 18, "row 2 lands on the top edge")
    }

    func testCentreCentresVisibleOrNotAndClampsAtTheEnds() {
        XCTAssertEqual(offset(.centre, row: 9, current: 0), 9 * 18 - 36)
        XCTAssertEqual(offset(.centre, row: 6, current: 90), 6 * 18 - 36, "visible, and still centred")
        XCTAssertEqual(offset(.centre, row: 1, current: 90), 0, "clamped at the top")
        XCTAssertEqual(offset(.centre, row: 19, current: 0), 20 * 18 - 90, "clamped at the bottom")
    }
}
