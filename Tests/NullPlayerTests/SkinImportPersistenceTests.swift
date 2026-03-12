import Foundation
import XCTest
@testable import NullPlayer

final class SkinImportPersistenceTests: XCTestCase {

    func testClassicImportCopiesSkinToPersistentDirectoryAndListsIt() throws {
        let workspace = try makeTempDirectory(named: "ClassicImportList")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let externalDir = workspace.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        let sourceURL = externalDir.appendingPathComponent("ImportedClassic.wsz")
        try FileManager.default.copyItem(at: bundledClassicSkinURL(), to: sourceURL)

        let persistentSkinsDir = workspace.appendingPathComponent("AppSupport/Skins", isDirectory: true)
        let importedURL = try WindowManager.importClassicSkin(from: sourceURL, to: persistentSkinsDir)

        XCTAssertEqual(importedURL.path, persistentSkinsDir.appendingPathComponent("ImportedClassic.wsz").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))

        let available = WindowManager.availableClassicSkins(in: persistentSkinsDir)
        XCTAssertTrue(available.contains(where: {
            $0.name == "ImportedClassic"
                && $0.url.standardizedFileURL.path == importedURL.standardizedFileURL.path
        }))
    }

    func testClassicImportedSkinRemainsLoadableAfterOriginalRemoved() throws {
        let workspace = try makeTempDirectory(named: "ClassicImportLoad")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let externalDir = workspace.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        let sourceURL = externalDir.appendingPathComponent("PortableClassic.wsz")
        try FileManager.default.copyItem(at: bundledClassicSkinURL(), to: sourceURL)

        let persistentSkinsDir = workspace.appendingPathComponent("AppSupport/Skins", isDirectory: true)
        let importedURL = try WindowManager.importClassicSkin(from: sourceURL, to: persistentSkinsDir)

        try FileManager.default.removeItem(at: sourceURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))

        XCTAssertNoThrow(try SkinLoader.shared.load(from: importedURL))
    }

    func testModernBundleImportIsDiscoverableByAvailableSkins() throws {
        let workspace = try makeTempDirectory(named: "ModernImportDiscover")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let defaults = makeTestDefaults(suite: "SkinImportPersistenceTests.ModernDiscover")
        let userSkinsDir = workspace.appendingPathComponent("ModernSkins", isDirectory: true)
        let bundleURL = try makeValidModernBundle(named: "ModernPersist", in: workspace)

        let importedName = try ModernSkinEngine.shared.importSkinBundle(
            from: bundleURL,
            destinationDirectory: userSkinsDir,
            userDefaults: defaults
        )

        XCTAssertEqual(importedName, "ModernPersist")
        XCTAssertEqual(defaults.string(forKey: "modernSkinName"), "ModernPersist")

        let available = ModernSkinLoader.shared.availableSkins(includeBundled: false, userDirectory: userSkinsDir)
        XCTAssertTrue(available.contains(where: {
            $0.name == "ModernPersist" && $0.path.lastPathComponent == "ModernPersist.nsz"
        }))
    }

    func testClassicImportReplacesExistingSkinWithSameFilename() throws {
        let workspace = try makeTempDirectory(named: "ClassicImportReplace")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let firstSourceDir = workspace.appendingPathComponent("SourceA", isDirectory: true)
        let secondSourceDir = workspace.appendingPathComponent("SourceB", isDirectory: true)
        try FileManager.default.createDirectory(at: firstSourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondSourceDir, withIntermediateDirectories: true)

        let filename = "ConflictSkin.wsz"
        let firstSource = firstSourceDir.appendingPathComponent(filename)
        let secondSource = secondSourceDir.appendingPathComponent(filename)
        let firstData = Data([0x01, 0x02, 0x03])
        let secondData = Data([0x09, 0x08, 0x07, 0x06])
        try firstData.write(to: firstSource)
        try secondData.write(to: secondSource)

        let persistentSkinsDir = workspace.appendingPathComponent("AppSupport/Skins", isDirectory: true)
        _ = try WindowManager.importClassicSkin(from: firstSource, to: persistentSkinsDir)
        let importedURL = try WindowManager.importClassicSkin(from: secondSource, to: persistentSkinsDir)

        let persistedData = try Data(contentsOf: importedURL)
        XCTAssertEqual(persistedData, secondData)
    }

    func testInvalidInputsDoNotOverwriteSelectionKeys() throws {
        let workspace = try makeTempDirectory(named: "InvalidSelectionKeys")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let defaults = makeTestDefaults(suite: "SkinImportPersistenceTests.InvalidKeys")
        defaults.set("ExistingModernSkin", forKey: "modernSkinName")
        defaults.set("/tmp/existing-classic.wsz", forKey: "lastClassicSkinPath")

        let invalidModernBundle = workspace.appendingPathComponent("BrokenModern.nsz")
        try Data("not-a-zip".utf8).write(to: invalidModernBundle)

        XCTAssertThrowsError(
            try ModernSkinEngine.shared.importSkinBundle(
                from: invalidModernBundle,
                destinationDirectory: workspace.appendingPathComponent("ModernSkins", isDirectory: true),
                userDefaults: defaults
            )
        )
        XCTAssertEqual(defaults.string(forKey: "modernSkinName"), "ExistingModernSkin")

        let invalidClassicSkin = workspace.appendingPathComponent("BrokenClassic.wsz")
        try Data("not-a-wsz".utf8).write(to: invalidClassicSkin)

        let didLoadClassic = WindowManager.shared.loadSkin(from: invalidClassicSkin, userDefaults: defaults)
        XCTAssertFalse(didLoadClassic)
        XCTAssertEqual(defaults.string(forKey: "lastClassicSkinPath"), "/tmp/existing-classic.wsz")
    }

    private func makeTempDirectory(named name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NullPlayerTests_\(name)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeTestDefaults(suite: String) -> UserDefaults {
        let suiteName = "\(suite).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func bundledClassicSkinURL() -> URL {
        repoRootURL().appendingPathComponent("dist/Skins/NullPlayer-Silver.wsz")
    }

    private func makeValidModernBundle(named name: String, in workspace: URL) throws -> URL {
        let sourceSkinJSON = repoRootURL().appendingPathComponent("Sources/NullPlayer/Resources/Skins/SmoothGlass/skin.json")
        let sourceSkinDir = workspace.appendingPathComponent("SkinPayload", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceSkinDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourceSkinJSON, to: sourceSkinDir.appendingPathComponent("skin.json"))

        let bundleURL = workspace.appendingPathComponent("\(name).\(ModernSkinLoader.bundleExtension)")
        try createZipArchive(containing: sourceSkinDir, at: bundleURL)
        return bundleURL
    }

    private func createZipArchive(containing directory: URL, at archiveURL: URL) throws {
        if FileManager.default.fileExists(atPath: archiveURL.path) {
            try FileManager.default.removeItem(at: archiveURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", directory.path, archiveURL.path]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "SkinImportPersistenceTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Failed to create modern skin bundle: \(output)"]
            )
        }
    }

    private func repoRootURL() -> URL {
        let testFileURL = URL(fileURLWithPath: #filePath)
        return testFileURL
            .deletingLastPathComponent() // NullPlayerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
    }
}
