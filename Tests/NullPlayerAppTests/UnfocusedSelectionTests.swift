import XCTest
@testable import NullPlayer

/// M54 — a list whose window is not key draws its selection dimmed, in the skin's own colours.
final class UnfocusedSelectionTests: XCTestCase {

    private let blue = NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
    private let white = NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
    private let green = NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)

    func testAFillDropsToHalfStrength() {
        XCTAssertEqual(UnfocusedSelection.fill(blue).alphaComponent, 0.5, accuracy: 0.001)
        XCTAssertEqual(UnfocusedSelection.fill(blue.withAlphaComponent(0.2)).alphaComponent, 0.1, accuracy: 0.001)
    }

    func testSelectedTextMovesHalfwayToTheRowColour() {
        let text = UnfocusedSelection.text(white, toward: green)
        XCTAssertEqual(text.redComponent, 0.5, accuracy: 0.001)
        XCTAssertEqual(text.greenComponent, 1, accuracy: 0.001)
        XCTAssertEqual(text.blueComponent, 0.5, accuracy: 0.001)
    }

    /// Only the selection changes: the playing and plain rows, and a style with no fill, stay as they are.
    func testAPlaylistRowStyleDimsOnlyItsSelection() {
        let rows = PlaylistView.RowStyle(font: .systemFont(ofSize: 8), selectionFill: blue, selectedText: white,
                                         playingText: white, normalText: green, scrollsTitle: true)
        let unfocused = rows.unfocused()
        XCTAssertEqual(unfocused.selectionFill?.alphaComponent ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(unfocused.textColor(selected: true, playing: false).redComponent, 0.5, accuracy: 0.001)
        XCTAssertEqual(unfocused.textColor(selected: false, playing: true), white)
        XCTAssertEqual(unfocused.textColor(selected: false, playing: false), green)

        let unfilled = PlaylistView.RowStyle(font: .systemFont(ofSize: 8), selectionFill: nil, selectedText: nil,
                                             playingText: white, normalText: green, scrollsTitle: false)
        XCTAssertNil(unfilled.unfocused().selectionFill)
        XCTAssertNil(unfilled.unfocused().selectedText)
    }

    /// The family seam: every family dims its selection while its window is not key, except `.wal`,
    /// which takes the skin's own pair instead. A key window never dims.
    func testOnlyWinampModernKeepsItsSelectionWhenUnfocused() {
        let windowManager = WindowManager.shared
        let originalMode = windowManager.uiMode
        defer { windowManager.uiMode = originalMode }
        let unfocused = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                 styleMask: .borderless, backing: .buffered, defer: true)
        XCTAssertFalse(unfocused.isKeyWindow)

        for mode in PlayerUIMode.allCases {
            windowManager.uiMode = mode
            let expected = mode.controllerFamily != .winampModern
            XCTAssertEqual(UnfocusedSelection.dims(in: unfocused), expected, "\(mode)")
            XCTAssertFalse(UnfocusedSelection.dims(in: nil), "\(mode): no window is focused by default")
        }
    }
}
