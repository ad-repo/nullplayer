import XCTest
@testable import NullPlayer

/// A one-file-per-skin family's installed skins (`SkinFileCatalogue`): what the selection resolves to,
/// the errors' wording, and what installing and removing touch.
final class SkinFileCatalogueTests: XCTestCase {
    private struct Catalogue: SkinFileCatalogue {
        static let family = "Test"
        static let fileExtension = "skn"
        let folder: SkinInstallFolder
        let selection: SkinSelection
    }

    private var folder: URL!
    private var catalogue: Catalogue!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("skin-catalogue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SkinFileCatalogueTests-\(UUID().uuidString)"))
        catalogue = Catalogue(folder: SkinInstallFolder("unused", at: folder), selection: SkinSelection(key: "skin", defaults: defaults))
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
        catalogue.selection.select("Gone")
        XCTAssertThrowsError(try catalogue.selectedSkinURL()) { error in
            XCTAssertEqual(error.localizedDescription,
                           "The selected Test skin “Gone” is no longer installed. Load it again or choose another skin.")
        }
        do {
            try await catalogue.removeSkin(named: "Gone")
            XCTFail("removed nothing")
        } catch {
            XCTAssertEqual(error.localizedDescription, "No Test skin named “Gone” is installed.")
        }
    }

    func testSkinsAreTheFamilysVisibleFilesByName() async throws {
        try touch("Deck.skn", "Other.SKN", ".hidden.skn", "notes.txt")
        XCTAssertEqual(catalogue.installedSkins().map(\.name), ["Deck", "Other"])
        XCTAssertNil(catalogue.skin(named: "../Deck"))
        catalogue.selection.select("Deck")
        XCTAssertEqual(try catalogue.selectedSkinURL()?.lastPathComponent, "Deck.skn")
        try await catalogue.removeSkin(named: "Deck")
        XCTAssertEqual(files, ["Other.SKN", "notes.txt"])
        XCTAssertNil(catalogue.selection.name)
    }

    func testInstallingGivesTheFamilysExtensionAndReplacesTheSkinOfThatName() async throws {
        try touch("Deck.skn")
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("skin-catalogue-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        try Data("y".utf8).write(to: source.appendingPathComponent("Deck.bin"))

        var validated = 0
        let deck = try await Catalogue.install(source.appendingPathComponent("Deck.bin"), into: catalogue.folder) { _ in
            validated += 1
        }
        XCTAssertEqual(deck.url.lastPathComponent, "Deck.skn")
        XCTAssertEqual(files, ["Deck.skn"])
        XCTAssertEqual(try String(contentsOf: deck.url, encoding: .utf8), "y")
        XCTAssertEqual(validated, 1)
        XCTAssertNil(catalogue.selection.name, "selecting is the caller's")
    }
}
