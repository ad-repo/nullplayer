import XCTest
@testable import NullPlayer

final class StreamRipperTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NullPlayerStreamRipperTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    func testCompatibleVideoOutputPathRemovesSourceSuffixAndUsesMP4() {
        let source = tempDirectory.appendingPathComponent("Artist - Title [source].webm").path

        let output = StreamRipper.compatibleVideoOutputPath(forIntermediatePath: source)

        XCTAssertEqual(output, tempDirectory.appendingPathComponent("Artist - Title.mp4").path)
    }

    func testCompatibleVideoOutputPathAvoidsOverwritingExistingMP4() throws {
        let existing = tempDirectory.appendingPathComponent("Artist - Title.mp4")
        FileManager.default.createFile(atPath: existing.path, contents: Data())
        let source = tempDirectory.appendingPathComponent("Artist - Title [source].mkv").path

        let output = StreamRipper.compatibleVideoOutputPath(forIntermediatePath: source)

        XCTAssertEqual(output, tempDirectory.appendingPathComponent("Artist - Title 1.mp4").path)
    }
}
