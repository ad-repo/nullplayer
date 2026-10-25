import XCTest
@testable import NullPlayer

final class SkinInstallFolderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SkinInstallFolderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func file(_ name: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    func testAFailedValidationLeavesTheInstalledSkinAndNoStagingCopy() async throws {
        let folder = SkinInstallFolder("Skins", at: root.appendingPathComponent("Skins"))
        let destination = folder.url.appendingPathComponent("a.skin")
        try await folder.commit(try file("good", "old"), to: destination) { _ in }
        struct Rejected: Error {}
        do {
            try await folder.commit(try file("bad", "new"), to: destination) { _ in throw Rejected() }
            XCTFail("the commit should have thrown")
        } catch is Rejected {}
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "old")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.url.path), ["a.skin"])
    }

    func testValidationReadsTheCopyAndACommitReplaces() async throws {
        let folder = SkinInstallFolder("Skins", at: root.appendingPathComponent("Skins"))
        let destination = folder.url.appendingPathComponent("a.skin")
        try folder.commit(try file("one", "1"), to: destination)
        var validated: URL?
        try await folder.commit(try file("two", "2"), to: destination, suffix: ".skin") { validated = $0 }
        XCTAssertEqual(validated?.deletingLastPathComponent().standardizedFileURL, folder.url.standardizedFileURL)
        XCTAssertTrue(validated?.lastPathComponent.hasPrefix(".incoming-") == true)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "2")
        try await folder.remove(destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}
