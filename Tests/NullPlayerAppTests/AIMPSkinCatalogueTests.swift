import XCTest
@testable import NullPlayer

/// The installed AIMP skins (`AIMPSkinImporter`): what the selection resolves to, the errors' wording,
/// and that a name is one skin across AIMP's extensions.
final class AIMPSkinCatalogueTests: XCTestCase {
    private var folder: URL!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("aimp-catalogue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "AIMPSkinCatalogueTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func touch(_ names: String...) throws {
        for name in names { try Data("x".utf8).write(to: folder.appendingPathComponent(name)) }
    }

    private var files: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    func testAMissingSelectionAndAnUnknownRemovalNameTheFamily() async throws {
        let importer = AIMPSkinImporter(directoryURL: folder, defaults: defaults)
        importer.selection.select("Gone")
        XCTAssertThrowsError(try importer.selectedSkinURL()) { error in
            XCTAssertEqual(error.localizedDescription,
                           "The selected AIMP skin “Gone” is no longer installed. Load it again or choose another skin.")
        }
        do {
            try await importer.removeSkin(named: "Gone")
            XCTFail("removed nothing")
        } catch {
            XCTAssertEqual(error.localizedDescription, "No AIMP skin named “Gone” is installed.")
        }
    }

    /// Two files of one name were two menu rows called the same, and the selection and removal took
    /// whichever came first. The name is one skin: `.acs5` ahead of `.acs4`, both removed together.
    func testANameIsOneSkinAcrossExtensions() async throws {
        try touch("Deck.acs4", "Deck.acs5", "Other.acs3", ".hidden.acs5", "notes.txt")
        let importer = AIMPSkinImporter(directoryURL: folder, defaults: defaults)
        XCTAssertEqual(importer.installedSkins().map(\.name), ["Deck", "Other"])
        XCTAssertNil(importer.skin(named: "../Deck"))
        importer.selection.select("Deck")
        XCTAssertEqual(try importer.selectedSkinURL()?.lastPathComponent, "Deck.acs5")
        try await importer.removeSkin(named: "Deck")
        XCTAssertEqual(files, ["Other.acs3", "notes.txt"])
        XCTAssertNil(importer.selection.name)
    }

    func testInstallingASkinUnderAnotherExtensionReplacesIt() async throws {
        try touch("Deck.acs5")
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("aimp-catalogue-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let file = source.appendingPathComponent("Deck.acs4")
        try AIMPSkinOwnWindowsTests.skinWithOwnPlaylist().write(to: file)

        let importer = AIMPSkinImporter(directoryURL: folder, defaults: defaults)
        let installed = try await importer.importSkins(from: file)
        XCTAssertEqual(installed.map(\.url.lastPathComponent), ["Deck.acs4"])
        XCTAssertEqual(files, ["Deck.acs4"])
        XCTAssertEqual(importer.selection.name, "Deck")
    }
}
