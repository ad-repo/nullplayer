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

    func testTransferStagedFileUsesCollisionFreeNameAndPreservesExistingFile() throws {
        let source = tempDirectory.appendingPathComponent("staged.flac")
        let destination = tempDirectory.appendingPathComponent("Track.flac")
        try Data("new".utf8).write(to: source)
        try Data("old".utf8).write(to: destination)

        let result = try StreamRipper.transferStagedFile(
            from: source,
            to: destination,
            replaceExisting: false
        )

        XCTAssertEqual(result, tempDirectory.appendingPathComponent("Track 1.flac"))
        XCTAssertEqual(try Data(contentsOf: destination), Data("old".utf8))
        XCTAssertEqual(try Data(contentsOf: result), Data("new".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testTransferFailureLeavesExistingDestinationUntouched() throws {
        let missingSource = tempDirectory.appendingPathComponent("missing.cue")
        let destination = tempDirectory.appendingPathComponent("Track.cue")
        try Data("existing cue".utf8).write(to: destination)

        XCTAssertThrowsError(
            try StreamRipper.transferStagedFile(
                from: missingSource,
                to: destination,
                replaceExisting: true
            )
        )

        XCTAssertEqual(try Data(contentsOf: destination), Data("existing cue".utf8))
    }

    func testTransferFailurePreservesCompletedStagingFile() throws {
        let source = tempDirectory.appendingPathComponent("staged.flac")
        let unavailableDestination = tempDirectory
            .appendingPathComponent("missing-directory", isDirectory: true)
            .appendingPathComponent("Track.flac")
        try Data("completed download".utf8).write(to: source)

        XCTAssertThrowsError(
            try StreamRipper.transferStagedFile(
                from: source,
                to: unavailableDestination,
                replaceExisting: false
            )
        )

        XCTAssertEqual(try Data(contentsOf: source), Data("completed download".utf8))
    }

    func testRecoveryMovesStagingContentsToVisibleDirectoryAndRemovesStaging() throws {
        let staging = tempDirectory.appendingPathComponent("staging", isDirectory: true)
        let recovery = tempDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let stagedFile = staging.appendingPathComponent("Track.flac")
        try Data("completed download".utf8).write(to: stagedFile)

        let result = StreamRipper.recoverStagingContents(
            from: staging,
            to: recovery
        )

        XCTAssertNil(result.remainingStagingURL)
        XCTAssertEqual(result.recoveredURLs, [recovery.appendingPathComponent("Track.flac")])
        XCTAssertEqual(
            try Data(contentsOf: recovery.appendingPathComponent("Track.flac")),
            Data("completed download".utf8)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }

    func testRecoveryUsesCollisionFreeFilename() throws {
        let staging = tempDirectory.appendingPathComponent("staging", isDirectory: true)
        let recovery = tempDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        try Data("recovered".utf8).write(to: staging.appendingPathComponent("Track.flac"))
        try Data("existing".utf8).write(to: recovery.appendingPathComponent("Track.flac"))

        let result = StreamRipper.recoverStagingContents(
            from: staging,
            to: recovery
        )

        XCTAssertEqual(
            result.recoveredURLs,
            [recovery.appendingPathComponent("Track 1.flac")]
        )
        XCTAssertEqual(
            try Data(contentsOf: recovery.appendingPathComponent("Track.flac")),
            Data("existing".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: recovery.appendingPathComponent("Track 1.flac")),
            Data("recovered".utf8)
        )
    }

    func testTransferReplacesExistingOnlyAfterCopyCompletes() throws {
        let source = tempDirectory.appendingPathComponent("staged.cue")
        let destination = tempDirectory.appendingPathComponent("Track.cue")
        try Data("new cue".utf8).write(to: source)
        try Data("old cue".utf8).write(to: destination)

        let result = try StreamRipper.transferStagedFile(
            from: source,
            to: destination,
            replaceExisting: true
        )

        XCTAssertEqual(result, destination)
        XCTAssertEqual(try Data(contentsOf: destination), Data("new cue".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }
}
