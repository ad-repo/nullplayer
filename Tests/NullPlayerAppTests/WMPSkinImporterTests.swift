import Foundation
import XCTest
@testable import NullPlayer

final class WMPSkinImporterTests: XCTestCase {
    func testImportValidatesEnumeratesSelectsAndReplacesAtomically() async throws {
        let root = try WMPSkinTestSupport.temporaryDirectory()
        let installed = root.appendingPathComponent("installed", isDirectory: true)
        let suite = "WMPSkinImporterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let importer = WMPSkinImporter(directoryURL: installed, defaults: defaults)
        let first = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("<THEME><VIEW id=\"one\" width=\"10\" height=\"10\"/></THEME>".utf8))
        ], filename: "Player.wmz")

        let imported = try await importer.importSkin(from: first)
        XCTAssertEqual(imported.name, "Player")
        XCTAssertEqual(importer.selectedSkinName, "Player")
        XCTAssertEqual(importer.installedSkins().map(\.name), [imported.name])
        XCTAssertEqual(importer.installedSkins().first?.url.resolvingSymlinksInPath().path,
                       imported.url.resolvingSymlinksInPath().path)

        let replacement = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("<THEME><VIEW id=\"two\" width=\"20\" height=\"10\"/></THEME>".utf8))
        ], filename: "Player.wmz")
        _ = try await importer.importSkin(from: replacement)
        let loaded = try await WMPSkinLoader().load(from: try XCTUnwrap(importer.selectedSkinURL()))
        XCTAssertEqual(loaded.views.map(\.id), ["two"])
        XCTAssertFalse((try FileManager.default.contentsOfDirectory(atPath: installed.path))
            .contains { $0.hasPrefix(".incoming-") })
    }

    func testRejectedReplacementLeavesInstalledArchiveAndSelectionUntouched() async throws {
        let root = try WMPSkinTestSupport.temporaryDirectory()
        let installed = root.appendingPathComponent("installed", isDirectory: true)
        let suite = "WMPSkinImporterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let importer = WMPSkinImporter(directoryURL: installed, defaults: defaults)
        let valid = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("<THEME><VIEW id=\"safe\" width=\"10\" height=\"10\"/></THEME>".utf8))
        ], filename: "Player.wmz")
        let installedSkin = try await importer.importSkin(from: valid)
        let original = try Data(contentsOf: installedSkin.url)

        let corrupt = root.appendingPathComponent("Player.wmz")
        try Data("not a zip".utf8).write(to: corrupt)
        await XCTAssertThrowsErrorAsync { try await importer.importSkin(from: corrupt) }

        XCTAssertEqual(try Data(contentsOf: installedSkin.url), original)
        XCTAssertEqual(importer.selectedSkinName, "Player")
    }

    func testMissingSelectionHasActionableFailureAndResetPath() throws {
        let root = try WMPSkinTestSupport.temporaryDirectory()
        let suite = "WMPSkinImporterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("Deleted", forKey: WMPSkinImporter.selectedSkinNameKey)
        let importer = WMPSkinImporter(directoryURL: root, defaults: defaults)

        XCTAssertThrowsError(try importer.selectedSkinURL()) { error in
            XCTAssertTrue(error.localizedDescription.contains("no longer installed"))
        }
        importer.resetSelection()
        XCTAssertNil(importer.selectedSkinName)
        XCTAssertNil(try importer.selectedSkinURL())
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {}
}
