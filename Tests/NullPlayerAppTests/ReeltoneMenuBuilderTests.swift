import AppKit
import XCTest
@testable import NullPlayer

final class ReeltoneMenuBuilderTests: XCTestCase {
    func testInactiveModeMenuOffersSwitchAndImportShell() {
        let item = ReeltoneMenuBuilder.buildModeMenuItem(activeMode: .classic)

        XCTAssertEqual(item.title, "Reeltone")
        XCTAssertEqual(item.state, .off)
        XCTAssertNotNil(item.submenu?.items.first { $0.title == "Switch to Reeltone" })
        let importItem = item.submenu?.items.first { $0.title == "Import Reeltone Skin…" }
        XCTAssertNotNil(importItem)
        XCTAssertFalse(importItem?.isEnabled ?? true)
    }

    func testActiveModeMenuMarksReeltoneWithoutOfferingRedundantSwitch() {
        let item = ReeltoneMenuBuilder.buildModeMenuItem(activeMode: .reeltone)

        XCTAssertEqual(item.state, .on)
        XCTAssertNil(item.submenu?.items.first { $0.title == "Switch to Reeltone" })
    }
}
