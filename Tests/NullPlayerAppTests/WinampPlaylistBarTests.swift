import XCTest
@testable import NullPlayer

/// The Winamp playlist style's bottom bar: controls land where PLEDIT.BMP draws them, the right-hand
/// ones follow the window's right edge, and no two controls overlap.
final class WinampPlaylistBarTests: XCTestCase {

    func testControlsAtMinimumAndStretchedSizes() {
        let min = NSSize(width: 275, height: 116)
        XCTAssertEqual(WinampPlaylistBar.control(at: NSPoint(x: 20, y: 95), size: min), .add)
        XCTAssertEqual(WinampPlaylistBar.control(at: NSPoint(x: 110, y: 95), size: min), .misc)
        XCTAssertEqual(WinampPlaylistBar.control(at: NSPoint(x: 240, y: 95), size: min), .list)
        XCTAssertEqual(WinampPlaylistBar.control(at: NSPoint(x: 145, y: 104), size: min), .play)
        XCTAssertNil(WinampPlaylistBar.control(at: NSPoint(x: 100, y: 50), size: min))

        let wide = NSSize(width: 500, height: 300)
        XCTAssertEqual(WinampPlaylistBar.control(at: NSPoint(x: 465, y: 279), size: wide), .list)
        XCTAssertEqual(WinampPlaylistBar.control(at: NSPoint(x: 405, y: 288), size: wide), .eject)
    }

    func testControlsDoNotOverlap() {
        let size = NSSize(width: 275, height: 116)
        let rects = WinampPlaylistBar.Control.allCases.map { WinampPlaylistBar.rect(for: $0, size: size) }
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

    func testFormat() {
        XCTAssertEqual(WinampPlaylistBar.format(0), "0:00")
        XCTAssertEqual(WinampPlaylistBar.format(754), "12:34")
        XCTAssertEqual(WinampPlaylistBar.format(3725), "1:02:05")
    }
}
