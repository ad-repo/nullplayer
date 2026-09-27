import AppKit
import XCTest
@testable import NullPlayer

/// W237 — the side-docked library must not follow the centre stack's height in a `.wmz` session.
///
/// Two seams carry that rule and only one of them is pure arithmetic. The live one is
/// `WindowManager.refitDockedPlexBrowserToVerticalStack`, reached from every
/// `updateDockedChildWindows` caller — including `handleCenterStackWindowWillClose`, whose guard
/// reads `!isRunningModernUI` and is therefore *true* in WMP; it needs a real controller stack and
/// was verified by driving the app (library 547x890 across a Cava open and close in `.wmz`, against
/// 580 → 290 in Classic and 580 → 290 → 580 in Original on the same binary).
///
/// The reopen seam is testable, and it is what these tests pin: a remembered, right-docked library
/// reopens on the re-derived dock edge, and in `.wmz` keeps the height the user left it at.
/// The `.wal` half of the defect is B147 and is deliberately not answered here.
final class WMPLibraryStackSizingTests: XCTestCase {

    /// The re-derived docked frame: right of the cluster, spanning a two-window centre stack.
    private let reDerived = NSRect(x: 1276, y: 613, width: 547, height: 613)
    /// What the user left the library at: same width, taller than the stack.
    private let remembered = NSRect(x: 1276, y: 336, width: 547, height: 890)

    func testWMPReopenKeepsTheRememberedHeightOnTheReDerivedDockEdge() {
        let frame = WindowManager.dockedLibraryReopenFrame(
            reDerived: reDerived,
            remembered: remembered,
            preservingRememberedHeight: true
        )

        XCTAssertEqual(frame.height, remembered.height, accuracy: 0.001,
                       "the centre stack must not resize the library in .wmz")
        XCTAssertEqual(frame.minX, reDerived.minX, accuracy: 0.001, "the dock edge is still re-derived")
        XCTAssertEqual(frame.width, reDerived.width, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, reDerived.maxY, accuracy: 0.001,
                       "and it grows downward: the top is anchored to the stack's top")
    }

    /// Classic and Original are unchanged — they take the re-derived frame whole, height included.
    func testClassicAndOriginalReopenTakeTheReDerivedFrameWhole() {
        let frame = WindowManager.dockedLibraryReopenFrame(
            reDerived: reDerived,
            remembered: remembered,
            preservingRememberedHeight: false
        )

        XCTAssertEqual(frame, reDerived)
    }

    /// A remembered height *shorter* than the stack is kept too: the rule is "not the stack's
    /// height", not "never shrink".
    func testWMPReopenKeepsAShorterRememberedHeight() {
        let short = NSRect(x: 1276, y: 800, width: 547, height: 300)

        let frame = WindowManager.dockedLibraryReopenFrame(
            reDerived: reDerived,
            remembered: short,
            preservingRememberedHeight: true
        )

        XCTAssertEqual(frame.height, 300, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, reDerived.maxY, accuracy: 0.001)
    }
}
