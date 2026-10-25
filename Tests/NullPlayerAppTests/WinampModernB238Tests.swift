import XCTest
@testable import NullPlayer

/// B238 — a skin's `setScale` raised UI Size for every skin loaded after it.
///
/// `layout.setScale(f)` is answered by the global UI Size (Phase 46), and that level outlived the
/// skin: Alpha Media Player X5 raises UI Size to 135% on load, and Nitrous Audio opened at 135%
/// after it. Winamp's scale belongs to the layout, so it dies with the skin. `WindowManager` keeps
/// the level the user chose beneath the one a skin asked for, and that user level is what a skin
/// switch goes back to, what a mode switch carries and what Save State persists.
final class WinampModernB238Tests: XCTestCase {
    private var manager: WindowManager { WindowManager.shared }

    override func setUp() {
        super.setUp()
        let originalMode = manager.uiMode
        manager.uiMode = .winampModern
        manager.uiScaleLevel = .p100
        addTeardownBlock { [manager] in
            manager.uiScaleLevel = .p100
            manager.uiMode = originalMode
        }
    }

    func testASkinsLevelEndsWithTheSkin() {
        manager.setUIScaleLevelForSkin(.p135)
        XCTAssertEqual(manager.uiScaleLevel, .p135)
        XCTAssertEqual(manager.userUIScaleLevel, .p100, "the user's level is kept beneath it")

        manager.endSkinUIScaleLevel()
        XCTAssertEqual(manager.uiScaleLevel, .p100)
    }

    /// Defix asks once per button click; the level to go back to is the one before the first ask.
    func testRepeatedSkinRequestsKeepTheLevelBeforeTheFirst() {
        manager.setUIScaleLevelForSkin(.p135)
        manager.setUIScaleLevelForSkin(.p150)
        XCTAssertEqual(manager.userUIScaleLevel, .p100)

        manager.endSkinUIScaleLevel()
        XCTAssertEqual(manager.uiScaleLevel, .p100)
    }

    /// A level picked while the skin's is showing is the user's, and survives the switch.
    func testAUserPickReplacesTheSkinsLevel() {
        manager.setUIScaleLevelForSkin(.p135)
        manager.uiScaleLevel = .p150
        XCTAssertEqual(manager.userUIScaleLevel, .p150)

        manager.endSkinUIScaleLevel()
        XCTAssertEqual(manager.uiScaleLevel, .p150)
    }

    /// Picking the very level the skin chose is still a pick: the write is a no-op for the windows,
    /// but the level becomes the user's.
    func testPickingTheSkinsOwnLevelMakesItTheUsers() {
        manager.setUIScaleLevelForSkin(.p135)
        manager.uiScaleLevel = .p135

        manager.endSkinUIScaleLevel()
        XCTAssertEqual(manager.uiScaleLevel, .p135)
    }

    /// With no skin request the user level is the level, and ending a skin changes nothing — the
    /// path every other mode runs.
    func testWithoutASkinRequestNothingChanges() {
        manager.uiScaleLevel = .p125
        XCTAssertEqual(manager.userUIScaleLevel, .p125)

        manager.endSkinUIScaleLevel()
        XCTAssertEqual(manager.uiScaleLevel, .p125)
    }
}
