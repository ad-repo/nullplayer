import AppKit
import XCTest
@testable import NullPlayer

final class WinampModernMenuTests: XCTestCase {
    func testWindowsMenuOmitsCompactControlsAndPlacesTextSizeBesideUISize() throws {
        let windowManager = WindowManager.shared
        let originalMode = windowManager.uiMode
        windowManager.uiMode = .winampModern
        defer { windowManager.uiMode = originalMode }

        let titles = ContextMenuBuilder.buildMenuBarWindowsMenu().items.map(\.title)

        XCTAssertFalse(titles.contains("Compact Mode"),
                       "a .wal skin owns its own compact and shade layouts")
        XCTAssertFalse(titles.contains("Compact Window"),
                       "NullPlayer's compact window must not compete with the skin")
        let uiSizeIndex = try XCTUnwrap(titles.firstIndex(of: "UI Size"))
        let textSizeIndex = try XCTUnwrap(titles.firstIndex(of: "Text Size"))
        XCTAssertEqual(textSizeIndex, uiSizeIndex + 1,
                       "Text Size belongs immediately beside UI Size in the Windows menu")
    }

    func testModernSkinsMenuContainsNeitherTextSizeNorSkinWindows() throws {
        let windowManager = WindowManager.shared
        let originalMode = windowManager.uiMode
        windowManager.uiMode = .winampModern
        defer { windowManager.uiMode = originalMode }

        let skinsMenu = ContextMenuBuilder.buildMenuBarUIMenu()
        let modernItem = try XCTUnwrap(
            skinsMenu.items.first { $0.title == PlayerUIMode.winampModern.displayName })
        let modernTitles = try XCTUnwrap(modernItem.submenu).items.map(\.title)

        XCTAssertFalse(modernTitles.contains("Text Size"),
                       "window presentation controls do not belong in skin selection")
        XCTAssertFalse(modernTitles.contains("Skin Windows"),
                       "skin-owned windows are a flat section of the Windows menu")
    }

    func testSkinOwnedWindowsFormASeparatedFlatToggleSection() throws {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Debug Console", action: nil, keyEquivalent: ""))

        ContextMenuBuilder.addWinampModernSkinWindowSection(
            to: menu,
            entries: [
                .init(title: "Left Speaker", isOn: true, target: .window("speaker.left")),
                .init(title: "Configurator", isOn: false, target: .window("configurator")),
                .init(title: "Video", isOn: true, isEnabled: false, target: .tab("Video")),
            ])

        XCTAssertEqual(menu.items.map(\.title),
                       ["Debug Console", "", "Left Speaker", "Configurator", "Video"])
        XCTAssertTrue(menu.items[1].isSeparatorItem,
                      "skin windows must be separated from NullPlayer-owned windows")
        XCTAssertNil(menu.items[2].submenu, "skin windows are direct rows, not another submenu")
        guard case .window("speaker.left") = menu.items[2].representedObject as? WinampModernSkinMenuEntry.Target
        else { return XCTFail("the row carries its target") }
        XCTAssertEqual(menu.items[2].state, .on)
        XCTAssertEqual(menu.items[3].state, .off)
        XCTAssertEqual(menu.items[3].action,
                       #selector(MenuActions.toggleWinampModernSkinMenuEntry(_:)))
        XCTAssertFalse(menu.items[4].isEnabled, "the last open tab cannot be closed")
    }

    func testEmptySkinWindowListDoesNotCreateAnEmptySection() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Debug Console", action: nil, keyEquivalent: ""))

        ContextMenuBuilder.addWinampModernSkinWindowSection(to: menu, entries: [])

        XCTAssertEqual(menu.items.map(\.title), ["Debug Console"])
    }
}
