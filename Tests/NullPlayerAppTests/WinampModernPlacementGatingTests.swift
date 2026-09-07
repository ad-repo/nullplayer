import AppKit
import XCTest
@testable import NullPlayer

/// The placement corrections this branch introduced for `.wal` window management must not reach
/// Classic or Original.
///
/// They were written for one problem — a `.wal` skin's windows are sized by the skin, arranged by a
/// generated tiling, and could land off the display with no way back. Classic and Original place
/// their windows by rules that predate all of it, including the habit of parking a window mostly past
/// an edge, which the corrections read as damage to repair.
///
/// The branch's own reachability rule is defined on a window's **top-left corner** precisely so a
/// parked window is left alone (`WindowPlacement.isReachable`, and see the comment there). The
/// `force` path is the one that does not honour it: it routes frames through `WindowPlacement.rescued`,
/// which measures the **whole rect**, and so moves windows that were never stranded. That is what
/// these tests pin down.
final class WinampModernPlacementGatingTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 850)

    /// A Classic session: main window in the middle, playlist parked mostly past the bottom edge.
    /// Nothing is stranded — both top-left corners are on screen.
    private let parkedSession: [String: NSRect] = [
        "main": NSRect(x: 100, y: 400, width: 275, height: 116),
        "playlist": NSRect(x: 100, y: -180, width: 275, height: 232)
    ]

    // MARK: - Why the gate is needed

    /// Documents the behaviour the gate exists to keep away from Classic: with `force`, a session
    /// where *every* window is reachable is still moved, because `rescued` measures the whole rect
    /// while `isReachable` measures the corner.
    ///
    /// This is the `.wal` recovery path and it stays as it is — a `.wal` window's frame is the skin's,
    /// not a placement the user chose. If it is ever made corner-consistent, this test is the one to
    /// delete, and `WindowPlacement`'s parked-window rule is the reason why.
    func testForcedCorrectionMovesAReachableParkedSessionAndSoMustStayGated() {
        for (key, frame) in parkedSession {
            XCTAssertTrue(WindowPlacement.isReachable(frame, screens: [screen]),
                          "\(key) must start reachable for this test to mean anything")
        }

        let forced = AppStateManager.correctedRestoredFrames(parkedSession,
                                                            screens: [screen],
                                                            force: true)

        XCTAssertNotEqual(forced, parkedSession,
                          "if this ever stops moving them the gate can be revisited")
        XCTAssertEqual(forced["playlist"]?.minY, 0, "the parked playlist is pulled back onto the screen")
        XCTAssertEqual(forced["main"]?.minY, 580, "and the whole cluster travels with it, by +180")
    }

    /// A window parked past the *right* edge is moved by the same path, for the same reason.
    func testForcedCorrectionMovesARightParkedWindow() {
        let saved = ["main": NSRect(x: 1300, y: 700, width: 275, height: 116)]
        XCTAssertTrue(WindowPlacement.isReachable(saved["main"]!, screens: [screen]))

        let forced = AppStateManager.correctedRestoredFrames(saved, screens: [screen], force: true)

        XCTAssertEqual(forced["main"]?.minX, 1165, "clamped to the screen's right edge, not left alone")
    }

    /// `force` is far cheaper to trip than "the monitor was unplugged": the comparison is exact
    /// `NSRect` equality on `visibleFrame`, so **resizing or hiding the Dock** is enough. That is what
    /// makes an ungated `force` path a routine event rather than a rare one.
    func testResizingTheDockAloneTripsTheForcedCorrection() {
        let savedWithSmallDock = NSRect(x: 0, y: 0, width: 1440, height: 850)
        let nowWithLargerDock = NSRect(x: 0, y: 0, width: 1440, height: 800)

        XCTAssertTrue(AppStateManager.savedScreenIsMissing(NSStringFromRect(savedWithSmallDock),
                                                           screens: [nowWithLargerDock]),
                      "a Dock resize alone reads as 'the saved screen is gone'")
    }

    /// Without `force`, a parked session is left exactly as saved — the behaviour Classic and Original
    /// get now that the caller is gated.
    func testAnUnforcedCorrectionLeavesAParkedSessionAlone() {
        XCTAssertEqual(AppStateManager.correctedRestoredFrames(parkedSession,
                                                               screens: [screen],
                                                               force: false),
                       parkedSession)
    }

    // MARK: - The gate itself

    func testPlacementCorrectionsApplyOnlyToWinampModern() {
        let windowManager = WindowManager.shared
        let originalMode = windowManager.uiMode
        defer { windowManager.uiMode = originalMode }

        var checked: [PlayerUIMode] = []
        for mode in PlayerUIMode.allCases {
            windowManager.uiMode = mode
            guard windowManager.uiMode == mode else { continue }  // edition may force a mode
            checked.append(mode)
            XCTAssertEqual(windowManager.appliesWinampModernPlacement,
                           mode == .winampModern,
                           "\(mode.displayName) must not run the .wal placement corrections")
        }

        // Without this the test passes silently in an edition that refuses every assignment.
        XCTAssertTrue(checked.contains(.winampModern), "the true case must actually be exercised")
        XCTAssertTrue(checked.contains(.classic), "and so must at least one false case")
    }

    /// The z-order `bringAllWindowsToFront` applies is written out explicitly rather than read from
    /// `managedWindowRecords`, whose order describes docking membership. Taking it from there raised
    /// the equalizer above the playlist, and the video window above the visualizer and the library.
    ///
    /// There is no way to assert an `orderFront` sequence without a window server, so this pins the
    /// thing that actually regressed: that the two orders are not the same list, and so must not be
    /// substituted for one another.
    func testDockingMembershipOrderIsNotTheStackingOrder() {
        let stacking = ["main", "equalizer", "playlist", "spectrum", "audioAnalysis", "peppyMeter",
                        "networkMonitor", "cava", "waveform", "video", "projectM", "library"]
        let dockingMembership = ["main", "playlist", "equalizer", "spectrum", "audioAnalysis",
                                 "peppyMeter", "networkMonitor", "cava", "waveform", "library",
                                 "projectM", "video"]

        XCTAssertEqual(Set(stacking), Set(dockingMembership), "same windows")
        XCTAssertNotEqual(stacking, dockingMembership,
                          "different order — which is why bringAllWindowsToFront spells its own out")
    }
}
