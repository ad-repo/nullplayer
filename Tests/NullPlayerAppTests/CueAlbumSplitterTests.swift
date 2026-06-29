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

        // Paths should be in a per-album subdirectory named from metadata
        // ("Album Artist - Album Title"), inside the cue's own folder.
        let cueDir = cueURL.deletingLastPathComponent()
        let albumDir = cueDir.appendingPathComponent("Album Artist - Album Title", isDirectory: true)
        XCTAssertEqual(paths?[0].deletingLastPathComponent().standardizedFileURL, albumDir.standardizedFileURL)
        XCTAssertEqual(paths?[1].deletingLastPathComponent().standardizedFileURL, albumDir.standardizedFileURL)
        XCTAssertEqual(paths?[2].deletingLastPathComponent().standardizedFileURL, albumDir.standardizedFileURL)

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

    func testOutputSubdirectoryNamedFromMetadata() throws {
        let cueContent = """
        PERFORMER "Pink Floyd"
        TITLE "The Wall"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "In the Flesh"
            INDEX 01 00:00:00
        """
        let cueURL = tempDirectory.appendingPathComponent("wall.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let paths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)
        XCTAssertEqual(paths?.first?.deletingLastPathComponent().lastPathComponent, "Pink Floyd - The Wall")
    }

    func testOutputSubdirectoryFallsBackToCueNameWithoutMetadata() throws {
        // No PERFORMER/TITLE — must fall back to the cue's own basename.
        let cueContent = """
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Untitled"
            INDEX 01 00:00:00
        """
        let cueURL = tempDirectory.appendingPathComponent("mix-2024.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let paths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)
        XCTAssertEqual(paths?.first?.deletingLastPathComponent().lastPathComponent, "mix-2024")
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

        // Create expected output files (in their per-album subdir)
        let outputPaths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)
        for path in outputPaths ?? [] {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
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

        // Create only first two expected output files (in their per-album subdir)
        let outputPaths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)
        for i in 0..<min(2, outputPaths?.count ?? 0) {
            try FileManager.default.createDirectory(at: outputPaths![i].deletingLastPathComponent(), withIntermediateDirectories: true)
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

    // MARK: - Backing File Sibling Fallback Tests

    func testBackingResolutionFallsBackToSameBasenameSibling() throws {
        // The cue's FILE line names a file that no longer exists (the pair was renamed),
        // but a same-basename audio sibling sits next to the cue. Resolution should pick it.
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "old-name.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            INDEX 01 00:00:00
        """
        let cueURL = tempDirectory.appendingPathComponent("My Album.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        // The renamed audio file shares the cue's basename.
        let sibling = tempDirectory.appendingPathComponent("My Album.flac")
        try "audio".write(to: sibling, atomically: true, encoding: .utf8)

        let resolved = CueAlbumSplitter.resolveBackingFileWithFallback(for: cueURL, fileName: "old-name.flac")
        XCTAssertEqual(resolved.standardizedFileURL, sibling.standardizedFileURL)
    }

    func testBackingResolutionHonorsExistingFileLineOverSibling() throws {
        // When the FILE line resolves to a real file, use it — the fallback must not fire,
        // even if a same-basename sibling also exists.
        let cueContent = """
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            INDEX 01 00:00:00
        """
        let cueURL = tempDirectory.appendingPathComponent("album.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let backing = tempDirectory.appendingPathComponent("backing.flac")
        try "audio".write(to: backing, atomically: true, encoding: .utf8)
        // A same-basename sibling also exists; it must NOT win over the valid FILE line.
        let decoy = tempDirectory.appendingPathComponent("album.flac")
        try "decoy".write(to: decoy, atomically: true, encoding: .utf8)

        let resolved = CueAlbumSplitter.resolveBackingFileWithFallback(for: cueURL, fileName: "backing.flac")
        XCTAssertEqual(resolved.standardizedFileURL, backing.standardizedFileURL)
    }

    func testBackingResolutionIgnoresNonAudioSibling() throws {
        // A same-basename NON-audio file is not a valid backing; with no audio match the
        // original (missing) path is returned so callers' existence checks behave as before.
        let cueContent = """
        FILE "gone.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            INDEX 01 00:00:00
        """
        let cueURL = tempDirectory.appendingPathComponent("orphan.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        // Same basename, but not an audio file — must be ignored.
        let notAudio = tempDirectory.appendingPathComponent("orphan.txt")
        try "notes".write(to: notAudio, atomically: true, encoding: .utf8)

        let resolved = CueAlbumSplitter.resolveBackingFileWithFallback(for: cueURL, fileName: "gone.flac")
        XCTAssertFalse(FileManager.default.fileExists(atPath: resolved.path))
        XCTAssertEqual(resolved.lastPathComponent, "gone.flac")
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

        // Create the expected outputs (in their per-album subdir)
        let paths = CueAlbumSplitter.expectedOutputPaths(for: cueURL)
        for path in paths ?? [] {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
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
