import XCTest
@testable import NullPlayer

/// The song title marquee is placed at base skin size and scaled up by the window scale with a
/// transform. Rendered at the backing scale alone it was stretched with linear filtering and its
/// bitmap-font glyphs blurred into halos — worst on 1x displays (#611).
final class ClassicMarqueeScaleTests: XCTestCase {
    private func makeShownWindow() -> (NSWindow, MainWindowView) {
        let size = Skin.mainWindowSize
        let view = MainWindowView(frame: NSRect(origin: .zero, size: size))
        let window = ResizableWindow(contentRect: NSRect(origin: NSPoint(x: 200, y: 200), size: size))
        window.contentView = view
        window.orderFront(nil)
        addTeardownBlock { window.orderOut(nil) }
        view.displayIfNeeded()
        return (window, view)
    }

    private func marquee(in view: MainWindowView) throws -> MarqueeLayer {
        try XCTUnwrap(view.layer?.sublayers?.compactMap { $0 as? MarqueeLayer }.first)
    }

    private func expectedScale(_ window: NSWindow, _ view: MainWindowView) -> CGFloat {
        let windowScale = min(view.bounds.width / Skin.baseMainSize.width,
                              view.bounds.height / Skin.baseMainSize.height)
        return window.backingScaleFactor * max(windowScale, 1)
    }

    func testMarqueeRendersAtTheScaledWindowSize() throws {
        let (window, view) = makeShownWindow()
        XCTAssertEqual(try marquee(in: view).contentsScale, expectedScale(window, view), accuracy: 0.001)

        var frame = window.frame
        frame.size = NSSize(width: Skin.baseMainSize.width * 2, height: Skin.baseMainSize.height * 2)
        window.setFrame(frame, display: true)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        XCTAssertEqual(try marquee(in: view).contentsScale, expectedScale(window, view), accuracy: 0.001)
    }

    func testMarqueeGlyphsAreNotSmoothed() throws {
        let (_, view) = makeShownWindow()
        let content = try XCTUnwrap(try marquee(in: view).sublayers?.first)
        XCTAssertEqual(content.magnificationFilter, .nearest)
    }
}
