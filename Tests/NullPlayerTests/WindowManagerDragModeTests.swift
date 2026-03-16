import XCTest
@testable import NullPlayer

final class WindowManagerDragModeTests: XCTestCase {

    func testShortHoldReturnsSeparate() {
        // Elapsed 0.1s < 0.4s threshold → separate
        let mode = WindowManager.determineDragMode(
            holdStart: 1000.0,
            currentTime: 1000.1,
            threshold: 0.4
        )
        XCTAssertEqual(mode, .separate)
    }

    func testLongHoldReturnsGroup() {
        // Elapsed 0.5s >= 0.4s threshold → group
        let mode = WindowManager.determineDragMode(
            holdStart: 1000.0,
            currentTime: 1000.5,
            threshold: 0.4
        )
        XCTAssertEqual(mode, .group)
    }

    func testExactThresholdReturnsGroup() {
        // Elapsed == threshold → group (use small base to avoid floating-point precision loss)
        let mode = WindowManager.determineDragMode(
            holdStart: 0.0,
            currentTime: 0.4,
            threshold: 0.4
        )
        XCTAssertEqual(mode, .group)
    }

    func testNilHoldStartReturnsGroup() {
        // nil holdStart → group (defensive guard inside determineDragMode; the actual mid-flight
        // path in windowWillMove calls windowWillStartDragging first which sets holdStartTime,
        // so nil is never passed there — this tests the function's own defensive fallback)
        let mode = WindowManager.determineDragMode(
            holdStart: nil,
            currentTime: 1000.0,
            threshold: 0.4
        )
        XCTAssertEqual(mode, .group)
    }

    func testZeroElapsedReturnsSeparate() {
        // Elapsed 0s → separate
        let mode = WindowManager.determineDragMode(
            holdStart: 1000.0,
            currentTime: 1000.0,
            threshold: 0.4
        )
        XCTAssertEqual(mode, .separate)
    }
}
