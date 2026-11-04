import XCTest
@testable import NullPlayer

/// An AIMP skin's own playlist and library windows (`SkinDrawnLists`): the skin draws those it has its
/// own of, and a show waits for the first skin. Skins are synthesized; nothing launches the app.
@MainActor
final class AIMPSkinOwnWindowsTests: XCTestCase {

    func testASkinDrawsTheListsItHasItsOwnOf() throws {
        let folder = try Self.temporaryFolder()
        let controller = AIMPSkinMainWindowController(importer: Self.importer(folder))
        defer { controller.prepareForUITeardown() }
        for list in [SkinDrawnList.playlist, .library] {
            XCTAssertFalse(controller.drawsOwnWindow(list), "the unskinned panel draws none: \(list)")
        }
        XCTAssertFalse(controller.deferUntilSkinLoads { XCTFail("held") }, "the panel is up")

        let url = folder.appendingPathComponent("Own Playlist.acs5")
        controller.present((try AIMPSkinLoader.load(data: Self.skinWithOwnPlaylist()), url), error: nil)
        XCTAssertTrue(controller.drawsOwnWindow(.playlist))
        XCTAssertFalse(controller.drawsOwnWindow(.library))

        controller.revealOwnWindow(.playlist, toggle: true)
        XCTAssertTrue(controller.isShowingOwnWindow(.playlist))
        controller.revealOwnWindow(.playlist, toggle: false)
        XCTAssertTrue(controller.isShowingOwnWindow(.playlist), "a show leaves it open")
        controller.revealOwnWindow(.playlist, toggle: true)
        XCTAssertFalse(controller.isShowingOwnWindow(.playlist))
    }

    /// A launch restores the playlist before the selected skin has loaded: the show waits for it,
    /// then runs once, after the skin is up.
    func testAListShowWaitsForTheFirstSkin() throws {
        let folder = try Self.temporaryFolder()
        let importer = Self.importer(folder)
        try Self.skinWithOwnPlaylist().write(to: folder.appendingPathComponent("Own Playlist.acs5"))
        importer.selection.select("Own Playlist")
        let controller = AIMPSkinMainWindowController(importer: importer)
        defer { controller.prepareForUITeardown() }

        var opened: [Bool] = []
        XCTAssertTrue(controller.deferUntilSkinLoads { opened.append(controller.drawsOwnWindow(.playlist)) })
        XCTAssertEqual(opened, [])

        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in controller.loadedSkinURL != nil }, object: nil)
        wait(for: [loaded], timeout: 10)
        XCTAssertEqual(opened, [true], "replayed once, with the skin's own playlist to route to")
        XCTAssertFalse(controller.deferUntilSkinLoads { XCTFail("held") })
    }

    /// A skin switch neither opens nor closes the skin's own playlist; its window is the skin's,
    /// made with it, gone with it, and its events go to the deck's controller.
    func testASkinSwitchCarriesWhetherItsOwnPlaylistIsOpen() throws {
        let folder = try Self.temporaryFolder()
        let controller = AIMPSkinMainWindowController(importer: Self.importer(folder))
        defer { controller.prepareForUITeardown() }
        let url = folder.appendingPathComponent("Own Playlist.acs5")
        func switchSkin() throws { controller.present((try AIMPSkinLoader.load(data: Self.skinWithOwnPlaylist()), url), error: nil) }

        try switchSkin()
        XCTAssertFalse(controller.isShowingOwnWindow(.playlist), "the first skin carries NullPlayer's closed playlist")
        XCTAssertEqual(controller.managedAuxiliaryWindows.count, 1)
        XCTAssertTrue(controller.managedAuxiliaryWindows.first?.delegate === controller)
        controller.revealOwnWindow(.playlist, toggle: false)
        try switchSkin()
        XCTAssertTrue(controller.isShowingOwnWindow(.playlist), "open across the switch")
        controller.revealOwnWindow(.playlist, toggle: true)
        try switchSkin()
        XCTAssertFalse(controller.isShowingOwnWindow(.playlist), "closed across the switch")

        controller.present(nil, error: nil)
        XCTAssertFalse(controller.drawsOwnWindow(.playlist))
        XCTAssertEqual(controller.managedAuxiliaryWindows.count, 0, "gone with the skin")
    }

    // MARK: - Helpers

    private static func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aimp-own-windows-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func importer(_ folder: URL) -> AIMPSkinImporter {
        let suite = "AIMPSkinOwnWindowsTests-\(UUID().uuidString)"
        return AIMPSkinImporter(directoryURL: folder, defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    /// A project file (`ACSJ`): an empty main form, and a playlist window of the skin's own.
    nonisolated static func skinWithOwnPlaylist() -> Data {
        func utf16LE(_ text: String) -> Data {
            Data([UInt8(text.utf16.count & 0xFF), UInt8(text.utf16.count >> 8)]) + (text.data(using: .utf16LittleEndian) ?? Data())
        }
        func u32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
        let entries = [
            ("AIMPMainForm.xml", #"<form name="AIMPMainForm"/>"#),
            ("Schema.xml", #"<schema><forms><form name="PlaylistWindow" master="AIMPMainForm"/></forms></schema>"#),
            ("PlaylistWindow.xml", #"<form name="PlaylistWindow"><control name="List" class="Playlist" link="Playlist"/></form>"#),
        ]
        let meta = utf16LE("Test") + utf16LE("") + utf16LE("") + [0]
        var data = Data("ACSJ".utf8) + Data(count: 9) + u32(meta.count) + meta + u32(entries.count)
        for (name, text) in entries {
            let body = Data(text.utf8)
            data += utf16LE(name) + u32(body.count) + body
        }
        return data
    }
}
