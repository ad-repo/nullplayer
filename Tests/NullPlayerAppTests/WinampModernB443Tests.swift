import XCTest
@testable import NullPlayer

/// B443 — Client_V2 declares black list text and a black column colour and nothing else, so its
/// unselected playlist rows drew black on black. The plate falls to white when neither the borrowed
/// links nor Winamp's black can be read under the text.
final class WinampModernB443Tests: XCTestCase {
    private func skin(_ identifier: String) -> NSColor? {
        switch identifier {
        case "studio.list.text", "studio.list.column.background": return NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
        default: return nil
        }
    }

    func testDarkTextOnUndeclaredPlateGetsAWhitePlate() {
        let palette = WasabiPalette.make(resolve: skin)
        XCTAssertEqual(palette.contentBackground, NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1))
    }

    func testAnUndeclaredSkinKeepsWinampsBlack() {
        XCTAssertEqual(WasabiPalette.make(resolve: { _ in nil }), WasabiPalette.fallback)
    }
}
