import XCTest
@testable import NullPlayer

final class WindowManagerEdgeOcclusionTests: XCTestCase {

    func testFullSideBySideAlignmentSuppressesEntireRightEdge() {
        let frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        let other = NSRect(x: 100, y: 0, width: 80, height: 100)

        let segments = WindowManager.computeEdgeOcclusionSegments(frame: frame, otherFrames: [other], dockThreshold: 2)

        XCTAssertEqual(segments.right.count, 1)
        assertRange(segments.right[0], equals: 0...100)
        XCTAssertTrue(segments.top.isEmpty)
        XCTAssertTrue(segments.bottom.isEmpty)
        XCTAssertTrue(segments.left.isEmpty)
    }

    func testSideBySideOffsetSuppressesOnlyOverlappingVerticalSegment() {
        let frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        let other = NSRect(x: 100, y: 30, width: 80, height: 50)

        let segments = WindowManager.computeEdgeOcclusionSegments(frame: frame, otherFrames: [other], dockThreshold: 2)

        XCTAssertEqual(segments.right.count, 1)
        assertRange(segments.right[0], equals: 30...80)
    }

    func testStackedOffsetSuppressesOnlyOverlappingHorizontalSegment() {
        let frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        let other = NSRect(x: 20, y: 100, width: 50, height: 60)

        let segments = WindowManager.computeEdgeOcclusionSegments(frame: frame, otherFrames: [other], dockThreshold: 2)

        XCTAssertEqual(segments.top.count, 1)
        assertRange(segments.top[0], equals: 20...70)
    }

    func testDockThresholdBoundary() {
        let frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        let withinThreshold = NSRect(x: 102, y: 25, width: 40, height: 40)  // gap = 2
        let outsideThreshold = NSRect(x: 102.1, y: 25, width: 40, height: 40)  // gap > 2

        let within = WindowManager.computeEdgeOcclusionSegments(frame: frame, otherFrames: [withinThreshold], dockThreshold: 2)
        XCTAssertEqual(within.right.count, 1)
        assertRange(within.right[0], equals: 25...65)

        let outside = WindowManager.computeEdgeOcclusionSegments(frame: frame, otherFrames: [outsideThreshold], dockThreshold: 2)
        XCTAssertTrue(outside.right.isEmpty)
    }

    func testMultipleNeighborsMergeIntoSingleSegment() {
        let frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        let first = NSRect(x: 100, y: 0, width: 50, height: 40)
        let second = NSRect(x: 100, y: 40, width: 50, height: 40)
        let third = NSRect(x: 100, y: 79, width: 50, height: 21)

        let segments = WindowManager.computeEdgeOcclusionSegments(frame: frame, otherFrames: [first, second, third], dockThreshold: 2)

        XCTAssertEqual(segments.right.count, 1)
        assertRange(segments.right[0], equals: 0...100)
    }

    private func assertRange(_ actual: ClosedRange<CGFloat>, equals expected: ClosedRange<CGFloat>, accuracy: CGFloat = 0.001, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.lowerBound, expected.lowerBound, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.upperBound, expected.upperBound, accuracy: accuracy, file: file, line: line)
    }
}
