import AppKit
import XCTest
@testable import NullPlayer

/// W217 G2 and G3 — `.wmz` shared the `.wal` *placement* seams but none of its *recovery* seams.
///
/// The restore correction, the off-screen safety net and every sweep that follows a moment which
/// strands a window were gated `appliesWinampModernPlacement`, so a `.wmz` session got none of them.
/// That matters more in `.wmz` than it did in `.wal`: every one of these windows is borderless, so a
/// window pushed off the display has no title bar left to drag back by.
///
/// The gate is now `appliesPlacementRecovery` — `.winampModern` **and** `.wmp`, Classic and Original
/// still out, which is the load-bearing part (B56).
///
/// The AppKit half of the fix needs a window server and was verified live (`wmp-skin-guide/reference/windows.md`
/// § *Window placement and recovery*). What is pinned here is the gate itself, the geometry the
/// correction produces, and the one AppKit contract the sweep's new skip depends on.
final class WMPPlacementRecoveryTests: XCTestCase {

    /// The display the live measurement was taken on: 1800x1169 with a 39pt menu bar.
    private let region = NSRect(x: 0, y: 0, width: 1800, height: 1130)

    // MARK: - The gate

    /// The recovery half applies to the families whose windows are sized and placed by a skin
    /// (`.wal`, `.wmz`, Audion), and to neither of the two whose window positions people have laid their desktops out around.
    func testPlacementRecoveryAppliesToWinampModernAndWMPOnly() {
        let windowManager = WindowManager.shared
        let originalMode = windowManager.uiMode
        defer { windowManager.uiMode = originalMode }

        var checked: [PlayerUIMode] = []
        for mode in PlayerUIMode.allCases {
            windowManager.uiMode = mode
            guard windowManager.uiMode == mode else { continue }  // edition may force a mode
            checked.append(mode)
            let family = mode.controllerFamily
            XCTAssertEqual(windowManager.appliesPlacementRecovery,
                           family == .winampModern || family == .wmp || family == .audion,
                           "\(mode.displayName) must not run the placement recovery sweeps")
        }

        // Without this the test passes silently in an edition that refuses every assignment.
        XCTAssertTrue(checked.contains(.wmp), "the `.wmz` case must actually be exercised")
        XCTAssertTrue(checked.contains(.classic), "and so must at least one false case")
    }

    /// The two gates are **not** interchangeable, and that is the whole reason a second one exists:
    /// `appliesWinampModernPlacement` stays what it says — the `.wal` *arrangement* — so widening
    /// recovery to `.wmz` did not hand it anything that is about `.wal` window layout.
    func testTheArrangementGateStaysWinampModernOnly() throws {
        let windowManager = WindowManager.shared
        let originalMode = windowManager.uiMode
        defer { windowManager.uiMode = originalMode }

        windowManager.uiMode = .wmp
        try XCTSkipUnless(windowManager.uiMode == .wmp, "this edition refuses `.wmp`")
        XCTAssertTrue(windowManager.appliesPlacementRecovery)
        XCTAssertFalse(windowManager.appliesWinampModernPlacement,
                       "`.wmz` gets the recovery seams, never the `.wal` arrangement seams")
    }

    // MARK: - G2, the geometry the correction produces

    /// A docked `.wmz` cluster saved on a wide desktop and restored onto a narrower one.
    ///
    /// `Halo 2`'s player with its two skin-owned panels docked to its right edge and flush on each
    /// other, saved at x=2000 on a 2560pt-wide desktop and coming back on the 1800pt one — so the
    /// player's own top-left corner is off the display and the whole session is stranded.
    private var dockedCluster: [String: NSRect] {
        ["main":     NSRect(x: 2000, y: 700, width: 327, height: 294),
         "eqView":   NSRect(x: 2327, y: 700, width: 406, height: 209),
         "plView":   NSRect(x: 2327, y: 435, width: 406, height: 265)]
    }

    /// The defect G2 names: rescuing each window on its own is what the whole-session group offset
    /// exists to prevent. Clamped individually, every window is pushed against the same right edge
    /// by a different distance, and the docking the user built is gone.
    func testPerWindowRescueCollapsesADockedClusterOntoItself() {
        var perWindow: [String: NSRect] = [:]
        for (key, frame) in dockedCluster {
            perWindow[key] = WindowPlacement.rescued(frame, into: region)
        }

        XCTAssertEqual(perWindow["eqView"]?.minX, perWindow["plView"]?.minX,
                       "both panels are clamped to the same right edge")
        XCTAssertNotEqual(perWindow["eqView"]?.minX, perWindow["main"].map { $0.maxX },
                          "and neither is touching the player any more — the dock is broken")
        XCTAssertNotEqual(perWindow["main"]?.minX, perWindow["eqView"]?.minX,
                          "the player travelled a different distance from its own panels")
    }

    /// What `.wmz` gets now: one offset for the whole session, so the cluster arrives intact.
    func testTheSessionCorrectionMovesADockedClusterAsOneGroup() {
        let corrected = AppStateManager.correctedRestoredFrames(dockedCluster,
                                                               screens: [region],
                                                               force: false)

        XCTAssertNotEqual(corrected, dockedCluster, "the session was stranded and must be corrected")
        for (key, frame) in corrected {
            XCTAssertTrue(WindowPlacement.isReachable(frame, screens: [region]),
                          "\(key) must come back reachable")
        }

        // The dock survives: the panels still start exactly where the player ends, and still sit
        // flush on each other, because every member travelled by the same vector.
        XCTAssertEqual(corrected["eqView"]?.minX, corrected["main"]?.maxX,
                       "the panels are still docked to the player's right edge")
        XCTAssertEqual(corrected["plView"]?.minX, corrected["eqView"]?.minX)
        XCTAssertEqual(corrected["plView"]?.maxY, corrected["eqView"]?.minY,
                       "and still flush on each other")

        // One vector, not three.
        let offsets = corrected.map { key, frame in
            NSStringFromPoint(NSPoint(x: frame.minX - dockedCluster[key]!.minX,
                                      y: frame.minY - dockedCluster[key]!.minY))
        }
        XCTAssertEqual(Set(offsets).count, 1, "one group offset, applied to every member")
    }

    /// Sizes are never touched — a `.wmz` window's size is the skin's, and the correction is about
    /// where the session is, not how big it is.
    func testTheSessionCorrectionNeverResizes() {
        let corrected = AppStateManager.correctedRestoredFrames(dockedCluster,
                                                               screens: [region],
                                                               force: false)
        for (key, frame) in corrected {
            XCTAssertEqual(frame.size, dockedCluster[key]?.size, "\(key) must not be resized")
        }
    }

    /// The correction it computes has to be the one the player is actually restored to.
    ///
    /// `restoreWindowFrames` handed the WMP controller the **raw** saved rect while computing the
    /// corrected one and using it for every other window, so G2 would have been measured and then
    /// discarded for the one window a `.wmz` session always has. This pins that the two differ, so
    /// passing the wrong one is not a distinction without a difference.
    func testTheCorrectedMainFrameIsNotTheSavedOne() {
        let corrected = AppStateManager.correctedRestoredFrames(dockedCluster,
                                                               screens: [region],
                                                               force: false)
        XCTAssertNotEqual(corrected["main"], dockedCluster["main"],
                          "if these were ever equal, restoring the raw rect would look correct")
        XCTAssertFalse(WindowPlacement.isReachable(dockedCluster["main"]!, screens: [region]),
                       "the raw rect is the stranded one")
        XCTAssertTrue(WindowPlacement.isReachable(corrected["main"]!, screens: [region]))
    }

    // MARK: - G1, the second definition of "on screen" that is no longer there

    /// `restoreFrame` re-derived its own idea of on-screen, and this is the frame that proves it
    /// does not any more.
    ///
    /// `WMPWindowRestorePolicy.safeFrame` preserved an 80pt strip of the saved rect and allowed the
    /// frame to sit with 24pt above the screen bottom, picking its screen by *first* intersection.
    /// A saved rect this far to the right came back clamped to `screen.maxX - 80` — a borderless
    /// `.wmz` window showing 80pt of artwork with nothing on it to grab. The controller now keeps
    /// the frame it was handed, because the two seams either side of it own reachability:
    /// `correctedRestoredFrames` before (G2) and `ensureAllWindowsOnScreen` after the skin has
    /// sized the window (G3).
    func testTheRestoredFrameIsNotClampedByTheControllerItself() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WMPG1-\(UUID().uuidString)", isDirectory: true)
        let suite = "WMPG1.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = WMPMainWindowController(
            importer: WMPSkinImporter(directoryURL: root, defaults: defaults))
        defer {
            controller.prepareForUITeardown()
            controller.window?.close()
        }

        // Far right of any attached display, so the assertion does not depend on this machine's
        // screens: every definition of "safe" would have moved it, and none runs here now. The
        // *vertical* placement is deliberately ordinary — AppKit constrains a frame whose top is
        // above the screen itself, which would measure its rule rather than ours.
        let saved = NSRect(x: 200_000, y: 300, width: 327, height: 294)
        controller.restoreFrame(saved, skinName: nil, viewID: nil)

        let restored = try XCTUnwrap(controller.window?.frame)
        XCTAssertEqual(restored.minX, saved.minX,
                       "the saved left edge survived: no local clamp ran")
        XCTAssertEqual(restored.maxY, saved.maxY,
                       "and so did the saved top edge — the size is the player's, the top-left is the session's")
    }

    /// The responsibility moved, it did not vanish: the same frame is rescued by the seam that owns
    /// the rule. If this ever fails while the test above passes, `.wmz` restore has no on-screen
    /// rule at all.
    func testTheSeamAboveStillRescuesTheFrameTheControllerNoLongerTouches() {
        let saved = NSRect(x: 200_000, y: 300, width: 327, height: 294)
        XCTAssertFalse(WindowPlacement.isReachable(saved, screens: [region]))

        let corrected = AppStateManager.correctedRestoredFrames(["main": saved],
                                                                screens: [region],
                                                                force: false)
        let main = corrected["main"]
        XCTAssertNotNil(main)
        XCTAssertTrue(WindowPlacement.isReachable(main!, screens: [region]),
                      "the session correction is what hands `restoreFrame` its frame")
        XCTAssertEqual(main?.size, saved.size, "a rescue moves, it never resizes")
    }

    // MARK: - G3, the contract the sweep's skip rests on

    /// The safety net now skips any window with a `parent`, and this is why.
    ///
    /// The hosted video output is glued over a skin's `<VIDEO>` box with `addChildWindow` in both
    /// `.wal` and `.wmz` (`WMPVideoSurface`, `VideoPlayerWindowController.hostOutputWindow`), and it
    /// is in the managed graph, so the sweep walks it. AppKit moves a child with its parent — so
    /// rescuing the child on its own displaces it off the box, and if the parent is rescued
    /// afterwards it moves twice.
    ///
    /// This asserts AppKit's half of it deliberately: if the parent ever stops carrying its child,
    /// the skip is the wrong answer and this test is the record of why it was the right one.
    func testAChildWindowIsCarriedByItsParentAndSoMustNotBeSweptAlone() {
        let parent = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 400, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let child = NSWindow(contentRect: NSRect(x: 340, y: 340, width: 200, height: 120),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        child.isReleasedWhenClosed = false
        defer { parent.removeChildWindow(child) }
        parent.addChildWindow(child, ordered: .above)
        XCTAssertTrue(child.parent === parent, "the premise: it really is a child")

        let insetBefore = CGPoint(x: child.frame.minX - parent.frame.minX,
                                  y: child.frame.minY - parent.frame.minY)

        parent.setFrameOrigin(NSPoint(x: parent.frame.minX + 120, y: parent.frame.minY + 80))

        let insetAfter = CGPoint(x: child.frame.minX - parent.frame.minX,
                                 y: child.frame.minY - parent.frame.minY)
        XCTAssertEqual(insetAfter, insetBefore,
                       "the child rode along, so a sweep that also moved it would move it twice")
    }
}
