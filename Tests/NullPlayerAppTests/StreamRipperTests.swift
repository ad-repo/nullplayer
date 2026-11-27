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

        let result = try StreamRipper.transferStagedFile(from: source, to: destination)

        XCTAssertEqual(result, tempDirectory.appendingPathComponent("Track 1.flac"))
        XCTAssertEqual(try Data(contentsOf: destination), Data("old".utf8))
        XCTAssertEqual(try Data(contentsOf: result), Data("new".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    /// M93's done criterion at the commit: a FLAC rip, then an AAC rip of the same chaptered video
    /// into one folder, leave two cues, each naming its own audio file.
    func testTwoRipsOfOneTitleKeepACueEach() throws {
        let destination = tempDirectory.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let chapters = [StreamRipper.Chapter(start: 0, title: "One"), StreamRipper.Chapter(start: 5, title: "Two")]
        var saved: [URL] = []
        func rip(_ name: String) throws -> String {
            let staged = tempDirectory.appendingPathComponent(name)
            try Data(name.utf8).write(to: staged)
            return try StreamRipper.commitRip(staged.path, toFolder: destination.path, chapters: chapters,
                                              stagingFolder: tempDirectory, saved: &saved).get()
        }

        XCTAssertEqual(try rip("Me at the zoo.flac"), destination.appendingPathComponent("Me at the zoo.flac").path)
        XCTAssertEqual(try rip("Me at the zoo.m4a"), destination.appendingPathComponent("Me at the zoo 1.m4a").path)

        func fileLine(_ cue: String) throws -> String? {
            try String(contentsOf: destination.appendingPathComponent(cue), encoding: .utf8)
                .split(separator: "\n").first { $0.hasPrefix("FILE") }.map(String.init)
        }
        XCTAssertEqual(try fileLine("Me at the zoo.cue"), "FILE \"Me at the zoo.flac\" WAVE")
        XCTAssertEqual(try fileLine("Me at the zoo 1.cue"), "FILE \"Me at the zoo 1.m4a\" WAVE")
        XCTAssertEqual(saved.map(\.lastPathComponent),
                       ["Me at the zoo.flac", "Me at the zoo.cue", "Me at the zoo 1.m4a", "Me at the zoo 1.cue"])
    }

    /// A file that appears at the chosen name after it was picked (another process, past the
    /// transfer lock) is neither overwritten nor removed by the failed commit.
    func testCommitToATakenNameLeavesThatFileAlone() throws {
        let source = tempDirectory.appendingPathComponent("staged.flac")
        let destination = tempDirectory.appendingPathComponent("Track.flac")
        try Data("new".utf8).write(to: source)
        try Data("someone else's".utf8).write(to: destination)

        XCTAssertThrowsError(try StreamRipper.commitStagedCopy(from: source, to: destination))

        XCTAssertEqual(try Data(contentsOf: destination), Data("someone else's".utf8))
        XCTAssertEqual(try Data(contentsOf: source), Data("new".utf8))
    }

    func testTransferFailurePreservesCompletedStagingFile() throws {
        let source = tempDirectory.appendingPathComponent("staged.flac")
        let unavailableDestination = tempDirectory
            .appendingPathComponent("missing-directory", isDirectory: true)
            .appendingPathComponent("Track.flac")
        try Data("completed download".utf8).write(to: source)

        XCTAssertThrowsError(
            try StreamRipper.transferStagedFile(from: source, to: unavailableDestination)
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

    func testReapOrphanedTempItemsRemovesOnlyOldMatchingFilesAndDirectories() throws {
        let oldDate = Date().addingTimeInterval(-1_200)
        let oldNames = [
            "nullplayer-rip-\(UUID().uuidString)",
            "nullplayer-ytdl-\(UUID().uuidString)",
            "ModernSkin_\(UUID().uuidString)",
            "ClassicSkin_\(UUID().uuidString)",
        ]
        let oldDirectories = oldNames.map {
            tempDirectory.appendingPathComponent($0, isDirectory: true)
        }
        for directory in oldDirectories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: directory.path)
        }

        let oldWaveform = tempDirectory.appendingPathComponent(
            "waveform-prerender-\(UUID().uuidString).flac"
        )
        try Data("old waveform".utf8).write(to: oldWaveform)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldWaveform.path)

        let recentWaveform = tempDirectory.appendingPathComponent(
            "waveform-prerender-\(UUID().uuidString).mp3"
        )
        try Data("recent waveform".utf8).write(to: recentWaveform)

        let unrelated = tempDirectory.appendingPathComponent("unrelated-\(UUID().uuidString).flac")
        try Data("unrelated".utf8).write(to: unrelated)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: unrelated.path)

        StreamRipper.reapOrphanedTempItems(in: tempDirectory, minInactivity: 600)

        for directory in oldDirectories {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldWaveform.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentWaveform.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }
}
