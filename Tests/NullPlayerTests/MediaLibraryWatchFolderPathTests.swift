import XCTest
@testable import NullPlayer

final class MediaLibraryWatchFolderPathTests: XCTestCase {
    func testIsPathInsideFolder() {
        XCTAssertTrue(MediaLibrary.isPath("/Users/test/Music/song.mp3", insideFolderPath: "/Users/test/Music"))
        XCTAssertTrue(MediaLibrary.isPath("/Users/test/Music", insideFolderPath: "/Users/test/Music"))
        XCTAssertFalse(MediaLibrary.isPath("/Users/test/Music2/song.mp3", insideFolderPath: "/Users/test/Music"))
    }

    func testIsPathInsideAnyFolder() {
        let folders = ["/Users/test/Music", "/Volumes/Media"]
        XCTAssertTrue(MediaLibrary.isPath("/Volumes/Media/Movies/file.mp4", insideAnyFolderPaths: folders))
        XCTAssertFalse(MediaLibrary.isPath("/Users/test/Desktop/file.mp3", insideAnyFolderPaths: folders))
    }

    func testShouldRemovePathWhenRemovingFolderWithOverlap() {
        let removedFolder = "/Users/test/Music"
        let remaining = ["/Users/test/Music/Jazz"]

        XCTAssertFalse(
            MediaLibrary.shouldRemovePath(
                "/Users/test/Music/Jazz/song.mp3",
                whenRemovingFolderPath: removedFolder,
                remainingFolderPaths: remaining
            )
        )

        XCTAssertTrue(
            MediaLibrary.shouldRemovePath(
                "/Users/test/Music/Rock/song.mp3",
                whenRemovingFolderPath: removedFolder,
                remainingFolderPaths: remaining
            )
        )
    }

    func testNormalizedPathResolvesSymlink() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NullPlayerWatchFolderTests-\(UUID().uuidString)", isDirectory: true)
        let realFolder = root.appendingPathComponent("real", isDirectory: true)
        let symlinkFolder = root.appendingPathComponent("link", isDirectory: true)

        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: realFolder, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: symlinkFolder, withDestinationURL: realFolder)

        let normalized = MediaLibrary.normalizedPath(for: symlinkFolder)
        XCTAssertEqual(normalized, realFolder.standardizedFileURL.resolvingSymlinksInPath().path)
    }
}
