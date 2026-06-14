import XCTest
@testable import NullPlayer

final class CueAlbumSplitterTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NullPlayerCueAlbumSplitterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    // MARK: - expectedOutputPaths Tests

    func testExpectedOutputPathsComputeFilenames() throws {
        let cueContent = """
        PERFORMER "Album Artist"
        TITLE "Album Title"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "First Track"
            INDEX 01 00:00:00
        TRACK 02 AUDIO
            TITLE "Second Track"
            INDEX 01 02:00:00
        TRACK 03 AUDIO
            TITLE "Third Track"
            INDEX 01 04:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("album.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let paths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)

        XCTAssertNotNil(paths)
        XCTAssertEqual(paths?.count, 3)

        // Paths should be in the same directory as the cue
        let cueDir = cueURL.deletingLastPathComponent()
        XCTAssertEqual(paths?[0].deletingLastPathComponent(), cueDir)
        XCTAssertEqual(paths?[1].deletingLastPathComponent(), cueDir)
        XCTAssertEqual(paths?[2].deletingLastPathComponent(), cueDir)

        // Filenames should be numbered and include titles
        XCTAssertTrue(paths?[0].lastPathComponent.hasPrefix("1 -") ?? false)
        XCTAssertTrue(paths?[1].lastPathComponent.hasPrefix("2 -") ?? false)
        XCTAssertTrue(paths?[2].lastPathComponent.hasPrefix("3 -") ?? false)

        // All should have .flac extension (always re-encode)
        XCTAssertEqual(paths?[0].pathExtension, "flac")
        XCTAssertEqual(paths?[1].pathExtension, "flac")
        XCTAssertEqual(paths?[2].pathExtension, "flac")
    }

    func testExpectedOutputPathsIncludesSanitizedTitles() throws {
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track / With \\ Illegal : Chars"
            INDEX 01 00:00:00
        TRACK 02 AUDIO
            TITLE "Normal Track"
            INDEX 01 02:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("sanitize.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let paths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)

        XCTAssertNotNil(paths)
        XCTAssertEqual(paths?.count, 2)

        // First track should have sanitized filename (illegal chars replaced)
        let firstFilename = paths?[0].lastPathComponent ?? ""
        XCTAssertFalse(firstFilename.contains("/"))
        XCTAssertFalse(firstFilename.contains("\\"))
        XCTAssertFalse(firstFilename.contains(":"))
        XCTAssertTrue(firstFilename.contains("_"))  // Replacement char
    }

    func testExpectedOutputPathsReturnsNilForInvalidCue() throws {
        let invalidCueURL = tempDirectory.appendingPathComponent("invalid.cue")
        try "INVALID CUE CONTENT".write(to: invalidCueURL, atomically: true, encoding: .utf8)

        let paths = CueAlbumSplitter.expectedOutputPaths(for: invalidCueURL)

        XCTAssertNil(paths)
    }

    func testExpectedOutputPathsReturnsNilForEmptyCue() throws {
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        """

        let cueURL = tempDirectory.appendingPathComponent("empty.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let paths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)

        XCTAssertNil(paths)
    }

    // MARK: - shouldPerformSplit Tests

    func testShouldPerformSplitReturnsTrueWhenOutputsMissing() throws {
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            INDEX 01 00:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("split.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let shouldSplit = CueAlbumSplitter.shouldPerformSplit(cueURL: cueURL)

        // No output files exist yet
        XCTAssertEqual(shouldSplit, true)
    }

    func testShouldPerformSplitReturnsFalseWhenAllOutputsExist() throws {
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            INDEX 01 00:00:00
        TRACK 02 AUDIO
            TITLE "Track Two"
            INDEX 01 02:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("idempotent.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        // Create expected output files
        let outputPaths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)
        for path in outputPaths ?? [] {
            try "dummy".write(to: path, atomically: true, encoding: .utf8)
        }

        let shouldSplit = CueAlbumSplitter.shouldPerformSplit(cueURL: cueURL)

        // All outputs exist
        XCTAssertEqual(shouldSplit, false)
    }

    func testShouldPerformSplitReturnsTrueWhenSomeOutputsMissing() throws {
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            INDEX 01 00:00:00
        TRACK 02 AUDIO
            TITLE "Track Two"
            INDEX 01 02:00:00
        TRACK 03 AUDIO
            TITLE "Track Three"
            INDEX 01 04:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("partial.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        // Create only first two expected output files
        let outputPaths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)
        for i in 0..<min(2, outputPaths?.count ?? 0) {
            try "dummy".write(to: outputPaths![i], atomically: true, encoding: .utf8)
        }

        let shouldSplit = CueAlbumSplitter.shouldPerformSplit(cueURL: cueURL)

        // Third output is missing
        XCTAssertEqual(shouldSplit, true)
    }

    func testShouldPerformSplitReturnsNilForInvalidCue() throws {
        let invalidCueURL = tempDirectory.appendingPathComponent("bad.cue")
        try "INVALID".write(to: invalidCueURL, atomically: true, encoding: .utf8)

        let shouldSplit = CueAlbumSplitter.shouldPerformSplit(cueURL: invalidCueURL)

        XCTAssertNil(shouldSplit)
    }

    // MARK: - Filename Sanitization Tests

    func testFilenameReplacesIllegalCharacters() throws {
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track / \\ : * ? \" < > | Name"
            INDEX 01 00:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("illegal.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let paths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)
        let filename = paths?[0].lastPathComponent ?? ""

        // Illegal characters should be replaced with underscore
        XCTAssertFalse(filename.contains("/"))
        XCTAssertFalse(filename.contains("\\"))
        XCTAssertFalse(filename.contains(":"))
        XCTAssertFalse(filename.contains("*"))
        XCTAssertFalse(filename.contains("?"))
        XCTAssertFalse(filename.contains("\""))
        XCTAssertFalse(filename.contains("<"))
        XCTAssertFalse(filename.contains(">"))
        XCTAssertFalse(filename.contains("|"))
    }

    func testFilenameTrimsPaddingAndDots() throws {
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "   Track Name   "
            INDEX 01 00:00:00
        TRACK 02 AUDIO
            TITLE "Track..."
            INDEX 01 02:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("trim.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let paths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)

        let filename1 = paths?[0].lastPathComponent ?? ""
        let filename2 = paths?[1].lastPathComponent ?? ""

        // First should have whitespace trimmed
        XCTAssertTrue(filename1.contains("Track Name"))
        XCTAssertFalse(filename1.contains("   "))

        // Second should have dots trimmed
        XCTAssertTrue(filename2.contains("Track"))
        XCTAssertFalse(filename2.hasSuffix("..."))
    }

    func testFilenameCollapsesWhitespaceRuns() throws {
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track    With    Multiple    Spaces"
            INDEX 01 00:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("spaces.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let paths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)
        let filename = paths?[0].lastPathComponent ?? ""

        // Should collapse multiple spaces to single space
        XCTAssertFalse(filename.contains("    "))
        XCTAssertTrue(filename.contains("Track With Multiple Spaces"))
    }

    func testFilenameTruncatesLongTitles() throws {
        let longTitle = String(repeating: "A", count: 300)  // Well over 200 bytes
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "\(longTitle)"
            INDEX 01 00:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("long.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let paths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)
        let filename = paths?[0].lastPathComponent ?? ""

        // Filename should be truncated to reasonable length
        // "1 - " prefix (4 chars) + ~200 byte title + ".flac" (5 chars) ≈ 209 bytes max
        let filenameData = filename.data(using: .utf8) ?? Data()
        XCTAssertLessThanOrEqual(filenameData.count, 250)  // Some buffer for UTF-8
    }

    func testFilenameIncludesTrackNumber() throws {
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "First"
            INDEX 01 00:00:00
        TRACK 02 AUDIO
            TITLE "Second"
            INDEX 01 02:00:00
        TRACK 03 AUDIO
            TITLE "Third"
            INDEX 01 04:00:00
        TRACK 10 AUDIO
            TITLE "Tenth"
            INDEX 01 06:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("numbered.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let paths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)

        // Each output should have a track number prefix
        XCTAssertTrue(paths?[0].lastPathComponent.hasPrefix("1 - ") ?? false)
        XCTAssertTrue(paths?[1].lastPathComponent.hasPrefix("2 - ") ?? false)
        XCTAssertTrue(paths?[2].lastPathComponent.hasPrefix("3 - ") ?? false)
        XCTAssertTrue(paths?[3].lastPathComponent.hasPrefix("4 - ") ?? false)
    }

    func testFilenameAlwaysUsesFlacExtension() throws {
        // Even if source is MP3, output should be FLAC
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.mp3" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            INDEX 01 00:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("flac_output.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let paths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)
        let filename = paths?[0].lastPathComponent ?? ""

        XCTAssertTrue(filename.hasSuffix(".flac"))
    }

    // MARK: - Integration Tests

    func testExpectedOutputPathsIdempotentWithShouldPerformSplit() throws {
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            INDEX 01 00:00:00
        TRACK 02 AUDIO
            TITLE "Track Two"
            INDEX 01 02:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("consistency.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        // Before any output files exist
        let shouldSplit1 = CueAlbumSplitter.shouldPerformSplit(cueURL: cueURL)
        XCTAssertEqual(shouldSplit1, true)

        // Create the expected outputs
        let paths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)
        for path in paths ?? [] {
            try "dummy audio".write(to: path, atomically: true, encoding: .utf8)
        }

        // After outputs exist
        let shouldSplit2 = CueAlbumSplitter.shouldPerformSplit(cueURL: cueURL)
        XCTAssertEqual(shouldSplit2, false)

        // Delete one output
        try? FileManager.default.removeItem(at: paths?[0] ?? URL(fileURLWithPath: "/dev/null"))

        // Should now want to split again
        let shouldSplit3 = CueAlbumSplitter.shouldPerformSplit(cueURL: cueURL)
        XCTAssertEqual(shouldSplit3, true)
    }
}
