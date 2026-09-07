import XCTest
@testable import NullPlayer

/// Off-screen window recovery — the rule, in isolation.
///
/// Windows launched off screen and stayed there, and with a large `.wal` skin the only escape was a
/// menu command most users do not know exists. The cause was that every placement path carried its
/// own idea of where a window may sit and they disagreed; the fix is that they all defer to these
/// four functions, and to the reversal they encode: **overlapping windows are preferable to hidden
/// ones.**
final class WindowPlacementTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 1600, height: 1000)

    // MARK: - Reachability

    /// Reachability is defined on the top-left corner alone, because that corner carries the title
    /// bar and the drag area: if it is visible, the window can always be pulled back by hand.
    func testAWindowFullyOnScreenIsReachable() {
        let frame = NSRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertTrue(WindowPlacement.isReachable(frame, screens: [screen]))
    }

    /// The classic habit of parking a window mostly past the bottom or right edge is a *placement*,
    /// not a strand — a sweep that yanked it back would be the bug.
    func testAWindowParkedPastTheBottomEdgeIsStillReachable() {
        let frame = NSRect(x: 100, y: -280, width: 400, height: 300)
        XCTAssertTrue(WindowPlacement.isReachable(frame, screens: [screen]),
                      "its top-left corner is still on screen")
    }

    func testAWindowPastTheRightEdgeIsNotReachable() {
        let frame = NSRect(x: 1700, y: 500, width: 400, height: 300)
        XCTAssertFalse(WindowPlacement.isReachable(frame, screens: [screen]))
    }

    /// The case a wide `.wal` skin produced: column 2 starts past `maxX`, so the window's whole body
    /// including its title bar is off the display.
    func testAWindowAboveTheTopEdgeIsNotReachable() {
        let frame = NSRect(x: 100, y: 900, width: 400, height: 300)
        XCTAssertFalse(WindowPlacement.isReachable(frame, screens: [screen]),
                      "maxY 1200 is above the visible top")
    }

    func testReachabilityIsSatisfiedByAnySingleScreen() {
        let second = NSRect(x: 1600, y: 0, width: 1200, height: 800)
        let frame = NSRect(x: 1700, y: 400, width: 400, height: 300)
        XCTAssertFalse(WindowPlacement.isReachable(frame, screens: [screen]))
        XCTAssertTrue(WindowPlacement.isReachable(frame, screens: [screen, second]))
    }

    // MARK: - Host screen

    func testTheHostIsTheScreenTheWindowMostlyOverlaps() {
        let second = NSRect(x: 1600, y: 0, width: 1200, height: 800)
        let frame = NSRect(x: 1500, y: 400, width: 400, height: 300)  // 100pt on the left, 300 right
        XCTAssertEqual(WindowPlacement.hostScreen(for: frame, screens: [screen, second]), second)
    }

    /// The unplugged-monitor case: the frame overlaps nothing, so the nearest screen takes it.
    func testAFrameOverlappingNothingGoesToTheNearestScreen() {
        let second = NSRect(x: 1600, y: 0, width: 1200, height: 800)
        let frame = NSRect(x: 3200, y: 400, width: 400, height: 300)
        XCTAssertEqual(WindowPlacement.hostScreen(for: frame, screens: [screen, second]), second)
    }

    func testNoScreensMeansNoHost() {
        XCTAssertNil(WindowPlacement.hostScreen(for: .zero, screens: []))
    }

    // MARK: - Rescue

    func testRescuingMovesAWindowOnlyAsFarAsItMustGo() {
        let frame = NSRect(x: 1700, y: 500, width: 400, height: 300)
        let rescued = WindowPlacement.rescued(frame, into: screen)
        XCTAssertEqual(rescued.maxX, screen.maxX, "flush to the edge it overshot")
        XCTAssertEqual(rescued.minY, 500, "the axis that was already fine is untouched")
    }

    func testRescuingNeverResizes() {
        let frame = NSRect(x: -900, y: 1800, width: 400, height: 300)
        XCTAssertEqual(WindowPlacement.rescued(frame, into: screen).size, frame.size)
    }

    /// A window larger than the display must keep its title bar, not its bottom: a `.wal` window's
    /// size is the skin and a classic sub-window's size is pinned, so shrinking is not an option.
    func testAWindowLargerThanTheScreenAlignsTopLeft() {
        let frame = NSRect(x: 400, y: -200, width: 2000, height: 1400)
        let rescued = WindowPlacement.rescued(frame, into: screen)
        XCTAssertEqual(rescued.minX, screen.minX)
        XCTAssertEqual(rescued.maxY, screen.maxY, "the top edge, where the controls are")
    }

    func testAnAlreadyOnScreenFrameIsUnchanged() {
        let frame = NSRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertEqual(WindowPlacement.rescued(frame, into: screen), frame)
    }

    /// The whole reason `rescued` accepts a frame it will overlap something: hidden is worse.
    func testRescuingIntoAnOffsetScreenUsesThatScreensOrigin() {
        let second = NSRect(x: 1600, y: 200, width: 1200, height: 800)
        let rescued = WindowPlacement.rescued(NSRect(x: 0, y: 0, width: 400, height: 300),
                                              into: second)
        XCTAssertEqual(rescued.origin, NSPoint(x: 1600, y: 200))
    }

    // MARK: - Group offset

    /// Per-window clamping is what would break docking: two windows flush against the same edge,
    /// clamped independently, come back overlapping instead of touching. One offset cannot.
    func testTheGroupOffsetPreservesEveryRelativePosition() {
        let main = NSRect(x: 2000, y: 400, width: 275, height: 116)
        let playlist = NSRect(x: 2000, y: 168, width: 275, height: 232)
        let union = main.union(playlist)

        let offset = WindowPlacement.groupOffset(union: union, into: screen)
        let movedMain = main.offsetBy(dx: offset.x, dy: offset.y)
        let movedPlaylist = playlist.offsetBy(dx: offset.x, dy: offset.y)

        XCTAssertEqual(movedMain.minY, movedPlaylist.maxY, "still docked edge to edge")
        XCTAssertEqual(movedMain.minX, movedPlaylist.minX, "still left-aligned")
        XCTAssertTrue(WindowPlacement.isReachable(movedMain, screens: [screen]))
        XCTAssertTrue(WindowPlacement.isReachable(movedPlaylist, screens: [screen]))
    }

    func testAGroupAlreadyOnScreenIsNotMoved() {
        let union = NSRect(x: 100, y: 100, width: 400, height: 400)
        XCTAssertEqual(WindowPlacement.groupOffset(union: union, into: screen), .zero)
    }

    /// A cluster taller than the display cannot be saved by one offset — it anchors top-left and the
    /// callers rescue whatever is still outside individually.
    func testAGroupTallerThanTheScreenAnchorsToTheTop() {
        let union = NSRect(x: 100, y: -600, width: 400, height: 1400)
        let offset = WindowPlacement.groupOffset(union: union, into: screen)
        XCTAssertEqual(union.offsetBy(dx: offset.x, dy: offset.y).maxY, screen.maxY)
    }
}
