import AppKit
import XCTest
@testable import NullPlayer

@MainActor
final class TrackVerbTests: XCTestCase {
    func testMenuListsTheFourVerbsInOrder() {
        let menu = NSMenu()
        TrackVerb.addMenuItems(to: menu) { [] }

        XCTAssertEqual(menu.items.map(\.title), ["Play", "Play and Replace Queue", "Play Next", "Add to Queue"])
    }

    /// Each item must reach its own handler. An action named `perform(_:)` once resolved to
    /// NSObject's `performSelector:`, so every click raised "unrecognized selector" and was dropped.
    func testEachMenuItemResolvesItsRowWhenChosen() async {
        _ = NSApplication.shared
        let menu = NSMenu()
        var resolved = 0
        let allResolved = expectation(description: "every item resolved its row")
        allResolved.expectedFulfillmentCount = TrackVerb.allCases.count
        TrackVerb.addMenuItems(to: menu) {
            resolved += 1
            allResolved.fulfill()
            throw CancellationError() // Stop before the verb reaches the audio engine.
        }

        for (index, item) in menu.items.enumerated() {
            let action = try! XCTUnwrap(item.action)
            XCTAssertEqual(NSStringFromSelector(action), "performVerb:")
            XCTAssertTrue((item.target as AnyObject).responds(to: action))
            menu.performActionForItem(at: index)
        }

        await fulfillment(of: [allResolved], timeout: 2)
        XCTAssertEqual(resolved, TrackVerb.allCases.count)
    }
}
