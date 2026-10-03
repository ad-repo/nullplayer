import XCTest
@testable import NullPlayer

/// The Classic main window's layer redraws only on `setNeedsDisplay`. An edge resize that did not
/// ask for one kept the old bitmap, and the time, spectrum and position bar repainted at the new
/// scale over it — the window smeared into trailing copies of itself.
final class ClassicMainWindowResizeTests: XCTestCase {
    /// Records the area each `draw` repainted.
    private final class RecordingMainWindowView: MainWindowView {
        var drawnRects: [NSRect] = []
        override func draw(_ dirtyRect: NSRect) {
            drawnRects.append(dirtyRect)
            super.draw(dirtyRect)
        }
    }

    private func makeShownWindow() -> (NSWindow, RecordingMainWindowView) {
        let size = Skin.mainWindowSize
        let view = RecordingMainWindowView(frame: NSRect(origin: .zero, size: size))
        // `ResizableWindow` is what the main window is, and what resizes it by hand.
        let window = ResizableWindow(contentRect: NSRect(origin: NSPoint(x: 200, y: 200), size: size))
        window.contentView = view
        window.orderFront(nil)
        addTeardownBlock { window.orderOut(nil) }
        view.displayIfNeeded()
        view.drawnRects.removeAll()
        return (window, view)
    }

    /// The resize as `ResizableWindow.performResize` applies it: the whole new bounds is repainted.
    func testEdgeResizeRepaintsTheWholeView() {
        let (window, view) = makeShownWindow()
        var frame = window.frame
        frame.origin.x -= 86
        frame.size.width += 86
        window.setFrame(frame, display: true)
        view.displayIfNeeded()
        let repainted = view.drawnRects.reduce(NSRect.null) { $0.union($1) }
        XCTAssertEqual(view.bounds.size, frame.size)
        XCTAssertTrue(repainted.contains(view.bounds),
                      "repainted \(repainted) of \(view.bounds): the rest keeps the old bitmap")
    }

    /// A move is not a resize, and leaves the cached bitmap alone.
    func testMoveDoesNotRepaint() {
        let (window, view) = makeShownWindow()
        window.setFrameOrigin(NSPoint(x: window.frame.minX + 40, y: window.frame.minY))
        view.displayIfNeeded()
        XCTAssertEqual(view.drawnRects, [])
    }
}
