import AppKit
import XCTest
@testable import NullPlayer

/// B55 — a `.wal` window must repaint every cached layer after returning from occlusion or sleep.
@MainActor
final class WinampModernBackingStoreTests: XCTestCase {

    private final class InvalidationRecordingView: NSView {
        var invalidatedRects: [NSRect] = []

        override func setNeedsDisplay(_ invalidRect: NSRect) {
            invalidatedRects.append(invalidRect)
            super.setNeedsDisplay(invalidRect)
        }
    }

    func testFullBackingStoreRepaintMarksTheEntireHostedViewTree() {
        let root = InvalidationRecordingView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let hostedSurface = InvalidationRecordingView(
            frame: NSRect(x: 10, y: 10, width: 80, height: 60))
        let nestedControl = InvalidationRecordingView(
            frame: NSRect(x: 0, y: 0, width: 40, height: 20))
        root.addSubview(hostedSurface)
        hostedSurface.addSubview(nestedControl)

        WinampModernMainWindowController.markForFullBackingStoreRepaint(root)

        for view in [root, hostedSurface, nestedControl] {
            XCTAssertFalse(view.invalidatedRects.isEmpty)
            XCTAssertTrue(view.needsLayout)
        }
    }
}
