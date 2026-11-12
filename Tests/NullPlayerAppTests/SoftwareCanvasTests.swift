import XCTest
@testable import NullPlayer

final class SoftwareCanvasTests: XCTestCase {
    func testWideViewportIsUntouched() {
        XCTAssertTrue(SoftwareCanvas.atLeastMinimum(width: 800, height: 600) == (800, 600))
    }

    func testNarrowViewportScalesUpAtItsAspect() {
        XCTAssertTrue(SoftwareCanvas.atLeastMinimum(width: 200, height: 100) == (400, 200))
    }

    /// A 1x600 viewport asked for a 400x240,000 canvas.
    func testScaledHeightIsBounded() {
        XCTAssertTrue(SoftwareCanvas.atLeastMinimum(width: 1, height: 600) == (400, SoftwareCanvas.maxScaledHeight))
        XCTAssertTrue(SoftwareCanvas.atLeastMinimum(width: 1, height: 3000) == (400, 3000))
    }
}
