import XCTest
@testable import NullPlayer

/// #603 — a selected row in an unfocused window takes the skin's
/// `wasabi.list.text.selected{,.background}.inactive` pair, through `WasabiPalette.unfocused()`.
final class WinampModernUnfocusedSelectionTests: XCTestCase {

    private static let inactiveText = NSColor(deviceRed: 0.1, green: 0.1, blue: 0.1, alpha: 1)
    private static let inactiveBar = NSColor(deviceRed: 0.8, green: 0.8, blue: 0.8, alpha: 1)

    private func skin(declaresInactive: Bool) -> (String) -> NSColor? {
        { identifier in
            switch identifier {
            case "wasabi.list.text": return NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
            case "wasabi.list.background": return NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
            case "wasabi.list.text.selected": return NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
            case "wasabi.list.text.selected.background":
                return NSColor(deviceRed: 0.2, green: 0.4, blue: 0.9, alpha: 1)
            case WasabiPalette.inactiveSelectionTextIdentifier where declaresInactive: return Self.inactiveText
            case WasabiPalette.inactiveSelectionBackgroundIdentifier where declaresInactive: return Self.inactiveBar
            default: return nil
            }
        }
    }

    func testUnfocusedSwapsInTheSkinsInactivePair() {
        let palette = WasabiPalette.make(resolve: skin(declaresInactive: true))
        let unfocused = palette.unfocused()
        XCTAssertEqual(unfocused.selectionText, Self.inactiveText)
        XCTAssertEqual(unfocused.selectionBackground, Self.inactiveBar)
        XCTAssertEqual(unfocused.listText, palette.listText)
        XCTAssertEqual(unfocused.contentBackground, palette.contentBackground)
    }

    func testASkinThatDeclaresNeitherIsUnchanged() {
        let palette = WasabiPalette.make(resolve: skin(declaresInactive: false))
        XCTAssertEqual(palette.unfocused(), palette)
    }

    /// All-or-nothing: overriding either selection role keeps both active colours, so a hand-picked
    /// colour is never paired with a skin colour the panel did not preview it against (B146).
    func testOverridingEitherSelectionRoleKeepsTheActivePair() {
        let pick = NSColor(deviceRed: 0.5, green: 0, blue: 0.5, alpha: 1)
        for role in [WasabiPalette.Role.selectionText, .selectionBackground] {
            let palette = WasabiPalette.make(overrides: [role: pick], resolve: skin(declaresInactive: true))
            XCTAssertEqual(palette.unfocused(), palette, "\(role)")
        }
    }
}
