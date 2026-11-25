import XCTest
@testable import NullPlayer

/// The Winamp playlist style's bottom bar: controls land where PLEDIT.BMP draws them, the right-hand
/// ones follow the window's right edge, and no two controls overlap.
final class WinampPlaylistBarTests: XCTestCase {
    typealias Editor = SkinElements.Playlist.Editor

    func testControlsAtMinimumAndStretchedSizes() {
        let min = NSSize(width: 275, height: 116)
        XCTAssertEqual(Editor.control(at: NSPoint(x: 20, y: 95), size: min), .add)
        XCTAssertEqual(Editor.control(at: NSPoint(x: 110, y: 95), size: min), .misc)
        XCTAssertEqual(Editor.control(at: NSPoint(x: 240, y: 95), size: min), .list)
        XCTAssertEqual(Editor.control(at: NSPoint(x: 145, y: 104), size: min), .play)
        XCTAssertNil(Editor.control(at: NSPoint(x: 100, y: 50), size: min))

        let wide = NSSize(width: 500, height: 300)
        XCTAssertEqual(Editor.control(at: NSPoint(x: 465, y: 279), size: wide), .list)
        XCTAssertEqual(Editor.control(at: NSPoint(x: 405, y: 288), size: wide), .eject)
    }

    func testControlsDoNotOverlap() {
        let size = NSSize(width: 275, height: 116)
        let rects = Editor.Control.allCases.map { Editor.rect(for: $0, size: size) }
        for (i, a) in rects.enumerated() {
            for b in rects[(i + 1)...] { XCTAssertFalse(a.intersects(b), "\(a) overlaps \(b)") }
        }
    }

    func testHotkeys() {
        typealias H = WinampPlaylistBar.Hotkey
        XCTAssertEqual(H(characters: "x", keyCode: 7, flags: []), .transport(.play))
        XCTAssertEqual(H(characters: "l", keyCode: 37, flags: .shift),
                       .command(#selector(PlaylistFileCommands.addDirectory(_:))))
        XCTAssertEqual(H(characters: "", keyCode: 51, flags: .command),
                       .command(#selector(PlaylistMenuTarget.cropSelection(_:))))
        // Shift turns 2 into "@"; the key code still says Sort by Filename.
        XCTAssertEqual(H(characters: "@", keyCode: 19, flags: [.command, .shift]),
                       .command(#selector(PlaylistMenuTarget.sortByFilename(_:))))
        // Arrows carry .numericPad and .function, which must not stop the match.
        XCTAssertEqual(H(characters: "", keyCode: 126, flags: [.option, .numericPad, .function]), .move(-1))
        // Left to their existing owners.
        XCTAssertNil(H(characters: "a", keyCode: 0, flags: .command))
        XCTAssertNil(H(characters: "", keyCode: 51, flags: []))
        XCTAssertNil(H(characters: "#", keyCode: 20, flags: [.command, .shift]))
        XCTAssertNil(H(characters: "x", keyCode: 7, flags: .command))
    }

    func testClock() {
        XCTAssertEqual(PlaylistView.clock(0, hours: true), "0:00")
        XCTAssertEqual(PlaylistView.clock(754, hours: true), "12:34")
        XCTAssertEqual(PlaylistView.clock(3725, hours: true), "1:02:05")
        XCTAssertEqual(PlaylistView.clock(3725, hours: false), "62:05")
    }

    /// The close hit area covers the close glyph and stops short of the shade glyph left of it.
    func testCloseHitCoversOnlyTheCloseGlyph() {
        let glyph = Editor.closeGlyph(width: 275)
        XCTAssertEqual(glyph.maxX + 2, 275)
        XCTAssertEqual(275 - Editor.closeWidth, glyph.minX - 1)
    }
}
