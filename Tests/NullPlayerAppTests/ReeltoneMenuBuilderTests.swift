import AppKit
import XCTest
@testable import NullPlayer

final class ReeltoneMenuBuilderTests: XCTestCase {
    func testInactiveModeMenuOffersSwitchAndImport() {
        let item = ReeltoneMenuBuilder.buildModeMenuItem(
            activeMode: .classic,
            discovery: ReeltoneDiscoveryResult(installations: [], diagnostics: []),
            selectedIdentity: nil
        )

        XCTAssertEqual(item.title, "Reeltone")
        XCTAssertEqual(item.state, .off)
        XCTAssertNotNil(item.submenu?.items.first { $0.title == "Switch to Reeltone" })
        let importItem = item.submenu?.items.first { $0.title == "Import Reeltone Skin…" }
        XCTAssertNotNil(importItem)
        XCTAssertTrue(importItem?.isEnabled ?? false)
    }

    func testActiveModeMenuMarksReeltoneWithoutOfferingRedundantSwitch() {
        let item = ReeltoneMenuBuilder.buildModeMenuItem(
            activeMode: .reeltone,
            discovery: ReeltoneDiscoveryResult(installations: [], diagnostics: []),
            selectedIdentity: nil
        )

        XCTAssertEqual(item.state, .on)
        XCTAssertNil(item.submenu?.items.first { $0.title == "Switch to Reeltone" })
        XCTAssertEqual(
            item.submenu?.items.first { $0.title == "Default Reeltone Theme" }?.state,
            .on
        )
    }

    func testInstalledSkinIsSelectableAndCheckedByStableIdentity() {
        let identity = UUID().uuidString.lowercased()
        let installation = ReeltoneInstalledSkin(
            record: ReeltoneInstallationRecord(
                identity: identity,
                manifestID: "com.example.menu",
                name: "Menu Fixture",
                manifestVersion: "1",
                installedAt: Date()
            ),
            rootURL: URL(fileURLWithPath: "/tmp/menu-fixture")
        )

        let item = ReeltoneMenuBuilder.buildModeMenuItem(
            activeMode: .reeltone,
            discovery: ReeltoneDiscoveryResult(installations: [installation], diagnostics: []),
            selectedIdentity: identity
        )
        let skinItem = item.submenu?.items.first { $0.title == "Menu Fixture" }

        XCTAssertEqual(skinItem?.state, .on)
        XCTAssertEqual(skinItem?.representedObject as? String, identity)
        XCTAssertEqual(skinItem?.action, #selector(ReeltoneMenuActions.selectInstalledSkin(_:)))
    }
}
