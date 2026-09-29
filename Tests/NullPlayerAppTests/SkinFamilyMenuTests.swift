import AppKit
import XCTest
@testable import NullPlayer

/// The Skins menu's shared shape, and what "Remove …" may take away.
final class SkinFamilyMenuTests: XCTestCase {

    private func item(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    /// Every family reads the same way: "Switch to" outside its own mode, the options, one divider,
    /// then the skins.
    func testAFamilyMenuPutsItsOptionsAboveOneDividerAndItsSkinsBelow() {
        let menu = ContextMenuBuilder.buildSkinFamilyMenu(
            switchItem: item("Switch to X"),
            options: [item("Load Skin..."), item("Open Skins Folder...")],
            skins: [item("A"), item("B")])
        XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? "---" : $0.title },
                       ["Switch to X", "---", "Load Skin...", "Open Skins Folder...", "---", "A", "B"])
    }

    func testTheFamilyOnScreenHasNoSwitchRow() {
        let menu = ContextMenuBuilder.buildSkinFamilyMenu(
            switchItem: nil, options: [item("Load Skin...")], skins: [item("A")])
        XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? "---" : $0.title },
                       ["Load Skin...", "---", "A"])
    }

    func testAnEmptyLibrarySaysSoInsteadOfEndingOnADivider() throws {
        let menu = ContextMenuBuilder.buildSkinFamilyMenu(
            switchItem: nil, options: [item("Load Skin...")], skins: [])
        let last = try XCTUnwrap(menu.items.last)
        XCTAssertEqual(last.title, "No skins installed")
        XCTAssertFalse(last.isEnabled)
    }

    // MARK: - Removing a `.wal` skin

    /// Deletes where the app would trash, so a test run never fills the user's Trash.
    private final class DeletingFileManager: FileManager {
        override func trashItem(at url: URL, resultingItemURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws {
            try removeItem(at: url)
        }
    }

    func testTheSelectedInstalledSkinIsRemovableAndRemovingItLeavesNothingToRemove() throws {
        let key = WinampModernSkinImporter.selectedSkinNameKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkinFamilyMenuTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("Mine.wal")
        try Data().write(to: archive)

        let importer = WinampModernSkinImporter(destinationDirectory: directory,
                                                fileManager: DeletingFileManager())
        UserDefaults.standard.set("Mine", forKey: key)
        let removable = try XCTUnwrap(importer.removableSelectedSkin())
        XCTAssertEqual(removable.archiveURL.standardizedFileURL, archive.standardizedFileURL)

        try importer.trashSkin(removable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
        // What is selected now is the bundled placeholder, or nothing: neither is removable.
        XCTAssertNil(importer.removableSelectedSkin())
    }
}
