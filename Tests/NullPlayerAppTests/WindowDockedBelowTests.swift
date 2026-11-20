import AppKit
import XCTest
@testable import NullPlayer

/// `WindowManager.windowsDocked(below:among:threshold:)`, the walk the centre stack's slide-up and its
/// bounds share: which windows hang under a frame, directly or through one another.
@MainActor
final class WindowDockedBelowTests: XCTestCase {

    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        super.tearDown()
    }

    private func window(_ frame: NSRect, visible: Bool = true) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.setFrame(frame, display: false)
        if visible { window.orderFront(nil) }
        windows.append(window)
        return window
    }

    func testTheWalkFollowsDockedEdgesNearestFirst() {
        let top = NSRect(x: 100, y: 500, width: 275, height: 116)
        let deep = window(NSRect(x: 100, y: 268, width: 275, height: 116))      // under `direct`
        let direct = window(NSRect(x: 100, y: 384, width: 275, height: 116))    // under `top`
        let nearMiss = window(NSRect(x: 150, y: 382, width: 100, height: 116))  // 2pt gap, in threshold
        let besideIt = window(NSRect(x: 400, y: 384, width: 275, height: 116))  // no horizontal overlap
        let tooFar = window(NSRect(x: 100, y: 120, width: 275, height: 140))    // 8pt below `deep`
        let hidden = window(NSRect(x: 100, y: 152, width: 275, height: 116), visible: false)

        let docked = WindowManager.windowsDocked(below: top, among: [deep, direct, nearMiss, besideIt, tooFar, hidden],
                                                 threshold: 3)
        XCTAssertEqual(docked, [direct, nearMiss, deep],
                       "both windows under the frame first, then the one under them; never the hidden one")
    }

    func testNothingDockedIsEmpty() {
        let away = window(NSRect(x: 0, y: 0, width: 50, height: 50))
        XCTAssertTrue(WindowManager.windowsDocked(below: NSRect(x: 0, y: 400, width: 50, height: 50),
                                                  among: [away], threshold: 3).isEmpty)
    }
}
