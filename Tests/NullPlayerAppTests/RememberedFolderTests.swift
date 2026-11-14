import XCTest
@testable import NullPlayer

final class RememberedFolderTests: XCTestCase {
    private let key = "test.rememberedFolder.\(UUID().uuidString)"

    override func tearDown() {
        let folder = RememberedFolder(pathKey: key)
        UserDefaults.standard.removeObject(forKey: folder.pathKey)
        UserDefaults.standard.removeObject(forKey: folder.bookmarkKey)
        super.tearDown()
    }

    func testRemembersAFolderThroughItsBookmarkAndForgetsIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        RememberedFolder(pathKey: key).set(dir)
        XCTAssertNotNil(UserDefaults.standard.data(forKey: key + ".bookmark"))

        // A fresh instance stands in for the next launch.
        let relaunched = RememberedFolder(pathKey: key)
        XCTAssertEqual(relaunched.url?.resolvingSymlinksInPath().path, dir.resolvingSymlinksInPath().path)

        relaunched.set(nil)
        XCTAssertNil(relaunched.url)
    }

    func testFallsBackToAPathSavedBeforeBookmarks() {
        UserDefaults.standard.set("/tmp/legacy-presets", forKey: key)
        XCTAssertEqual(RememberedFolder(pathKey: key).path, "/tmp/legacy-presets")
    }
}
