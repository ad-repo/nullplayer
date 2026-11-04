import AppKit
import XCTest
@testable import NullPlayer

/// `PlaylistMenuBuilder`'s REM / SEL / MISC menus, lifted from `.wal`'s `PE_*` buttons: the rows,
/// their order, their actions, their target and which are enabled must be what `.wal` built itself.
@MainActor
final class PlaylistSectionMenuTests: XCTestCase {

    private final class Target: NSObject, PlaylistMenuTarget {
        func playSelected(_ sender: Any?) {}
        func removeSelected(_ sender: Any?) {}
        func removeAll(_ sender: Any?) {}
        func removeDeadFiles(_ sender: Any?) {}
        func selectAll(_ sender: Any?) {}
        func selectNone(_ sender: Any?) {}
        func invertSelection(_ sender: Any?) {}
        func cropSelection(_ sender: Any?) {}
        func sortByTitle(_ sender: Any?) {}
        func sortByArtist(_ sender: Any?) {}
        func sortByAlbum(_ sender: Any?) {}
        func sortByFilename(_ sender: Any?) {}
        func sortByPath(_ sender: Any?) {}
        func reverse(_ sender: Any?) {}
        func randomize(_ sender: Any?) {}
        func showFileInfo(_ sender: Any?) {}
        func selectForMenu(_ row: Int) {}
    }

    private func rows(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "-" : "\($0.title)\($0.isEnabled ? "" : " (off)")" }
    }

    func testRemoveMenuGreysSelectionRowsWithNothingSelected() {
        let target = Target()
        let menu = PlaylistMenuBuilder.removeMenu(target: target, hasSelection: false)
        XCTAssertEqual(menu.title, "Remove")
        XCTAssertFalse(menu.autoenablesItems)
        XCTAssertEqual(rows(menu), ["Remove Selected (off)", "Crop Selection (off)", "Remove All", "Remove Dead Files"])
        XCTAssertEqual(menu.items.map(\.action), [#selector(PlaylistMenuTarget.removeSelected(_:)),
                                                  #selector(PlaylistMenuTarget.cropSelection(_:)),
                                                  #selector(PlaylistMenuTarget.removeAll(_:)),
                                                  #selector(PlaylistMenuTarget.removeDeadFiles(_:))])
        XCTAssertTrue(menu.items.allSatisfy { $0.target === target })
        XCTAssertEqual(rows(PlaylistMenuBuilder.removeMenu(target: target, hasSelection: true)),
                       ["Remove Selected", "Crop Selection", "Remove All", "Remove Dead Files"])
    }

    func testSelectMenu() {
        let target = Target()
        let menu = PlaylistMenuBuilder.selectMenu(target: target)
        XCTAssertEqual(menu.title, "Select")
        XCTAssertEqual(rows(menu), ["Select All", "Select None", "Invert Selection"])
        XCTAssertTrue(menu.items.allSatisfy { $0.target === target && $0.keyEquivalent.isEmpty })
    }

    func testMiscMenuCarriesWinampsSortOrderAndFileInfo() throws {
        let target = Target()
        let menu = PlaylistMenuBuilder.miscMenu(target: target, selectedRows: [], canShowFileInfo: false)
        XCTAssertEqual(menu.title, "Misc")
        XCTAssertEqual(Array(rows(menu).prefix(3)), ["Sort", "-", "File Info... (off)"])
        let sort = try XCTUnwrap(menu.items.first?.submenu)
        XCTAssertFalse(sort.autoenablesItems)
        XCTAssertEqual(rows(sort), ["Sort by Title", "Sort by Filename", "Sort by Path", "Randomize", "Reverse"])
        XCTAssertTrue(sort.items.allSatisfy { $0.target === target })
        XCTAssertTrue(PlaylistMenuBuilder.miscMenu(target: target, selectedRows: [0], canShowFileInfo: true)
            .items[2].isEnabled)
    }
}
