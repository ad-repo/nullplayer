import XCTest
@testable import NullPlayer

final class CueSheetTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NullPlayerCueSheetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    // MARK: - parseCueTimestamp Round-trip Tests

    func testParseCueTimestampRoundTripsWithStreamRipperFormat() {
        // Test the round-trip: write a timestamp via cueTimestamp, parse it back, verify equality
        let testValues: [Double] = [
            0.0,           // 00:00:00
            1.5,           // 00:01:00 (1.5 frames)
            60.0,          // 01:00:00 (exactly 1 minute)
            61.0,          // 01:01:00 + offset
            3661.0,        // 01:01:01 (1 hour, 1 minute, 1 second)
            3661.75,       // With fractional frame
            10.5,          // 10.5 frames (partial second)
        ]

        for originalSeconds in testValues {
            // Format via cueTimestamp logic
            let totalFrames = Int((originalSeconds * 75).rounded())
            let frames = totalFrames % 75
            let totalSeconds = totalFrames / 75
            let formatted = String(format: "%02d:%02d:%02d", totalSeconds / 60, totalSeconds % 60, frames)

            // Parse it back
            let parsed = CueSheet.parseCueTimestamp(formatted)

            // Should match within frame tolerance (1/75 = ~13.3ms)
            XCTAssertNotNil(parsed, "Failed to parse timestamp: \(formatted)")
            let tolerance = 1.0 / 75.0
            XCTAssertEqual(parsed ?? 0, Double(totalFrames) / 75.0, accuracy: tolerance,
                          "Round-trip failed for \(formatted) (original \(originalSeconds)s)")
        }
    }

    func testParseCueTimestampConvertsMMSSFFCorrectly() {
        // Test specific MM:SS:FF values at 75fps
        // 00:01:30 = 0 minutes 1 second 30 frames = 1 + 30/75 = 1.4 seconds
        let result = CueSheet.parseCueTimestamp("00:01:30")
        XCTAssertNotNil(result)
        XCTAssertEqual(result ?? 0, 1.4, accuracy: 0.01)

        // 01:00:00 = 75*60 frames = 60 seconds
        let result2 = CueSheet.parseCueTimestamp("01:00:00")
        XCTAssertNotNil(result2)
        XCTAssertEqual(result2 ?? 0, 60.0, accuracy: 0.01)

        // 00:30:50 = (30*75) + 50 = 2300 frames = 30.6667 seconds
        let result3 = CueSheet.parseCueTimestamp("00:30:50")
        XCTAssertNotNil(result3)
        XCTAssertEqual(result3 ?? 0, 2300.0 / 75.0, accuracy: 0.01)
    }

    func testParseCueTimestampReturnsNilOnInvalidFormat() {
        XCTAssertNil(CueSheet.parseCueTimestamp("invalid"))
        XCTAssertNil(CueSheet.parseCueTimestamp("01:02"))  // Missing frames
        XCTAssertNil(CueSheet.parseCueTimestamp("01:02:03:04"))  // Too many parts
        XCTAssertNil(CueSheet.parseCueTimestamp("xx:yy:zz"))  // Non-numeric
        XCTAssertNil(CueSheet.parseCueTimestamp(""))
    }

    func testParseCueTimestampRejectsOutOfRangeFields() throws {
        XCTAssertNil(CueSheet.parseCueTimestamp("00:60:00"))  // SS must be 0–59
        XCTAssertNil(CueSheet.parseCueTimestamp("00:00:75"))  // FF must be 0–74 (75 fps)
        XCTAssertNil(CueSheet.parseCueTimestamp("00:99:99"))  // both out of range
        XCTAssertNil(CueSheet.parseCueTimestamp("-1:00:00"))  // negative minutes
        XCTAssertEqual(try XCTUnwrap(CueSheet.parseCueTimestamp("00:59:74")), (59.0 * 75 + 74) / 75.0, accuracy: 0.0001)  // max valid
    }

    // MARK: - CueSheet.parse Tests

    func testParseMultiTrackCueSheetExtractsMetadata() throws {
        let cueContent = """
        PERFORMER "Album Artist"
        TITLE "Album Title"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            PERFORMER "Track Performer One"
            INDEX 01 00:00:00
        TRACK 02 AUDIO
            TITLE "Track Two"
            PERFORMER "Track Performer Two"
            INDEX 01 02:30:50
        TRACK 03 AUDIO
            TITLE "Track Three"
            PERFORMER "Track Performer Three"
            INDEX 01 05:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("multi.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let cue = try CueSheet.parse(from: cueURL)

        XCTAssertEqual(cue.performer, "Album Artist")
        XCTAssertEqual(cue.title, "Album Title")
        XCTAssertEqual(cue.fileName, "backing.flac")
        XCTAssertEqual(cue.entries.count, 3)

        // Track 1
        XCTAssertEqual(cue.entries[0].number, 1)
        XCTAssertEqual(cue.entries[0].title, "Track One")
        XCTAssertEqual(cue.entries[0].performer, "Track Performer One")
        XCTAssertEqual(cue.entries[0].startTime, 0.0, accuracy: 0.01)

        // Track 2 (02:30:50 = 150 seconds + 50/75 frames = 150.667 seconds)
        XCTAssertEqual(cue.entries[1].number, 2)
        XCTAssertEqual(cue.entries[1].title, "Track Two")
        XCTAssertEqual(cue.entries[1].performer, "Track Performer Two")
        XCTAssertEqual(cue.entries[1].startTime, 150.66666666666666, accuracy: 0.01)

        // Track 3
        XCTAssertEqual(cue.entries[2].number, 3)
        XCTAssertEqual(cue.entries[2].title, "Track Three")
        XCTAssertEqual(cue.entries[2].performer, "Track Performer Three")
        XCTAssertEqual(cue.entries[2].startTime, 300.0, accuracy: 0.01)
    }

    func testParseStripsSurroundingQuotes() throws {
        // Surrounding double quotes are stripped; apostrophes inside the value are preserved
        // verbatim (NOT rewritten to double quotes — that would corrupt titles like "Don't").
        let cueContent = """
        PERFORMER "Don't Stop"
        TITLE "Rock 'n' Roll"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            INDEX 01 00:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("quotes.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let cue = try CueSheet.parse(from: cueURL)

        XCTAssertEqual(cue.performer, "Don't Stop")
        XCTAssertEqual(cue.title, "Rock 'n' Roll")
    }

    func testParseIndex00FallbackWhenIndex01Missing() throws {
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            INDEX 00 00:00:00
        TRACK 02 AUDIO
            TITLE "Track Two"
            INDEX 01 02:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("index00.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let cue = try CueSheet.parse(from: cueURL)

        // Track 1 should use INDEX 00 as fallback
        XCTAssertEqual(cue.entries[0].startTime, 0.0, accuracy: 0.01)
        // Track 2 prefers INDEX 01
        XCTAssertEqual(cue.entries[1].startTime, 120.0, accuracy: 0.01)
    }

    func testParseMultipleFileEntriesWarnsAndUsesFirst() throws {
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "first.flac" WAVE
        FILE "second.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            INDEX 01 00:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("multifile.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let cue = try CueSheet.parse(from: cueURL)

        // Should use first FILE only
        XCTAssertEqual(cue.fileName, "first.flac")
        XCTAssertEqual(cue.entries.count, 1)
    }

    func testParseRequiresFileEntry() throws {
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        TRACK 01 AUDIO
            TITLE "Track One"
            INDEX 01 00:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("nofile.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        // Should throw because no FILE entry exists
        XCTAssertThrowsError(try CueSheet.parse(from: cueURL))
    }

    func testParseIgnoresCommentsAndBlankLines() throws {
        let cueContent = """
        REM This is a comment
        PERFORMER "Artist"

        REM Another comment
        TITLE "Album"
        FILE "backing.flac" WAVE

        TRACK 01 AUDIO
            REM Track comment
            TITLE "Track One"
            INDEX 01 00:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("comments.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let cue = try CueSheet.parse(from: cueURL)

        XCTAssertEqual(cue.performer, "Artist")
        XCTAssertEqual(cue.title, "Album")
        XCTAssertEqual(cue.entries.count, 1)
        XCTAssertEqual(cue.entries[0].title, "Track One")
    }

    func testParseDefaultsTrackTitleWhenMissing() throws {
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            INDEX 01 00:00:00
        TRACK 02 AUDIO
            TITLE "Track Two"
            INDEX 01 02:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("default_title.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let cue = try CueSheet.parse(from: cueURL)

        // Track without explicit TITLE should default to "Track N"
        XCTAssertEqual(cue.entries[0].title, "Track 1")
        XCTAssertEqual(cue.entries[1].title, "Track Two")
    }

    // MARK: - CueSheet.expandToTracks Tests

    func testExpandToTracksCreatesVirtualTracks() throws {
        let cueContent = """
        PERFORMER "Album Artist"
        TITLE "Album Title"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            PERFORMER "Track Performer One"
            INDEX 01 00:00:00
        TRACK 02 AUDIO
            TITLE "Track Two"
            PERFORMER "Track Performer Two"
            INDEX 01 02:00:00
        TRACK 03 AUDIO
            TITLE "Track Three"
            INDEX 01 04:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("expand.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let cue = try CueSheet.parse(from: cueURL)
        let tracks = CueSheet.expandToTracks(cue: cue, cueFileURL: cueURL)

        XCTAssertEqual(tracks.count, 3)

        // Track 1: 00:00:00 = 0s, next at 02:00:00 = 120s
        XCTAssertEqual(tracks[0].title, "Track One")
        XCTAssertEqual(tracks[0].artist, "Track Performer One")
        XCTAssertEqual(tracks[0].album, "Album Title")
        XCTAssertEqual(tracks[0].cueStartOffset ?? 0, 0.0, accuracy: 0.01)
        XCTAssertEqual(tracks[0].cueEndOffset ?? 0, 120.0, accuracy: 0.01)
        XCTAssertEqual(tracks[0].duration ?? 0, 120.0, accuracy: 0.01)
        XCTAssertEqual(tracks[0].cueSourceURL, cueURL)

        // Track 2: 02:00:00 = 120s, next at 04:00:00 = 240s
        XCTAssertEqual(tracks[1].title, "Track Two")
        XCTAssertEqual(tracks[1].artist, "Track Performer Two")
        XCTAssertEqual(tracks[1].album, "Album Title")
        XCTAssertEqual(tracks[1].cueStartOffset ?? 0, 120.0, accuracy: 0.01)
        XCTAssertEqual(tracks[1].cueEndOffset ?? 0, 240.0, accuracy: 0.01)
        XCTAssertEqual(tracks[1].duration ?? 0, 120.0, accuracy: 0.01)

        // Track 3 (last): 04:00:00 = 240s, no end offset
        XCTAssertEqual(tracks[2].title, "Track Three")
        XCTAssertEqual(tracks[2].artist, "Album Artist")  // Falls back to top-level
        XCTAssertEqual(tracks[2].album, "Album Title")
        XCTAssertEqual(tracks[2].cueStartOffset ?? 0, 240.0, accuracy: 0.01)
        XCTAssertNil(tracks[2].cueEndOffset)  // Last track has no end offset
        XCTAssertNil(tracks[2].duration)  // Duration nil for last track
    }

    func testExpandToTracksArtistFallback() throws {
        // Entry performer overrides top-level
        let cueContent = """
        PERFORMER "Album Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            PERFORMER "Track Artist"
            INDEX 01 00:00:00
        TRACK 02 AUDIO
            TITLE "Track Two"
            INDEX 01 02:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("artist_fallback.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let cue = try CueSheet.parse(from: cueURL)
        let tracks = CueSheet.expandToTracks(cue: cue, cueFileURL: cueURL)

        XCTAssertEqual(tracks[0].artist, "Track Artist")
        XCTAssertEqual(tracks[1].artist, "Album Artist")  // Fallback
    }

    func testExpandToTracksRelativeBackingPath() throws {
        // Create a cue in a subdirectory
        let subdir = tempDirectory.appendingPathComponent("subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            INDEX 01 00:00:00
        """

        let cueURL = subdir.appendingPathComponent("album.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let cue = try CueSheet.parse(from: cueURL)
        let tracks = CueSheet.expandToTracks(cue: cue, cueFileURL: cueURL)

        // URL should be resolved relative to cue's directory
        let expectedBackingURL = subdir.appendingPathComponent("backing.flac")
        XCTAssertEqual(tracks[0].url, expectedBackingURL)
    }

    func testExpandToTracksAbsoluteBackingPath() throws {
        // Absolute path in cue
        let absPath = "/some/absolute/path/backing.flac"
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "\(absPath)" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            INDEX 01 00:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("absolute.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let cue = try CueSheet.parse(from: cueURL)
        let tracks = CueSheet.expandToTracks(cue: cue, cueFileURL: cueURL)

        XCTAssertEqual(tracks[0].url.path, absPath)
    }

    func testExpandToTracksEmptyEntriesReturnsEmpty() throws {
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        """

        let cueURL = tempDirectory.appendingPathComponent("empty.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let cue = try CueSheet.parse(from: cueURL)
        let tracks = CueSheet.expandToTracks(cue: cue, cueFileURL: cueURL)

        XCTAssertEqual(tracks.count, 0)
    }

    func testExpandToTracksSingleTrackCueDoesNotCrash() throws {
        // Single-track cue: the guard for i+1 < count is critical
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Single Track"
            INDEX 01 00:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("single.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let cue = try CueSheet.parse(from: cueURL)
        let tracks = CueSheet.expandToTracks(cue: cue, cueFileURL: cueURL)

        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].title, "Single Track")
        XCTAssertEqual(tracks[0].cueStartOffset ?? 0, 0.0, accuracy: 0.01)
        XCTAssertNil(tracks[0].cueEndOffset)  // Last (and only) track
    }

    func testExpandToTracksPopulatesCueSourceURL() throws {
        let cueContent = """
        PERFORMER "Artist"
        TITLE "Album"
        FILE "backing.flac" WAVE
        TRACK 01 AUDIO
            TITLE "Track One"
            INDEX 01 00:00:00
        """

        let cueURL = tempDirectory.appendingPathComponent("source.cue")
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)

        let cue = try CueSheet.parse(from: cueURL)
        let tracks = CueSheet.expandToTracks(cue: cue, cueFileURL: cueURL)

        XCTAssertEqual(tracks[0].cueSourceURL, cueURL)
    }

    // MARK: - CueSheet.siblingCue Tests

    func testSiblingCueDetectsCueNextToAudioFile() throws {
        let audioURL = tempDirectory.appendingPathComponent("album.flac")
        let cueURL = tempDirectory.appendingPathComponent("album.cue")

        // Create dummy files
        try "audio".write(to: audioURL, atomically: true, encoding: .utf8)
        try "cue".write(to: cueURL, atomically: true, encoding: .utf8)

        let foundCue = CueSheet.siblingCue(for: audioURL)

        XCTAssertEqual(foundCue, cueURL)
    }

    func testSiblingCueReturnsNilWhenCueMissing() throws {
        let audioURL = tempDirectory.appendingPathComponent("album.flac")

        // Create audio file but no cue
        try "audio".write(to: audioURL, atomically: true, encoding: .utf8)

        let foundCue = CueSheet.siblingCue(for: audioURL)

        XCTAssertNil(foundCue)
    }

    func testSiblingCueHandlesDifferentExtensions() throws {
        // Test with .wav, .mp3, etc.
        let mp3URL = tempDirectory.appendingPathComponent("album.mp3")
        let cueURL = tempDirectory.appendingPathComponent("album.cue")

        try "audio".write(to: mp3URL, atomically: true, encoding: .utf8)
        try "cue".write(to: cueURL, atomically: true, encoding: .utf8)

        let foundCue = CueSheet.siblingCue(for: mp3URL)

        XCTAssertEqual(foundCue, cueURL)
    }

    // MARK: - CueSheet.resolveBackingFile Tests

    func testResolveBackingFileRelativePath() throws {
        let cueURL = tempDirectory.appendingPathComponent("cues").appendingPathComponent("album.cue")
        let fileName = "backing.flac"

        let resolved = CueSheet.resolveBackingFile(for: cueURL, fileName: fileName)

        let expected = tempDirectory.appendingPathComponent("cues").appendingPathComponent("backing.flac")
        XCTAssertEqual(resolved, expected)
    }

    func testResolveBackingFileAbsolutePath() throws {
        let cueURL = tempDirectory.appendingPathComponent("album.cue")
        let absPath = "/var/audio/backing.flac"

        let resolved = CueSheet.resolveBackingFile(for: cueURL, fileName: absPath)

        XCTAssertEqual(resolved.path, absPath)
    }

    func testResolveBackingFileRejectsParentTraversal() throws {
        let cueURL = tempDirectory.appendingPathComponent("cues").appendingPathComponent("album.cue")
        let fileName = "../../../../etc/passwd"

        let resolved = CueSheet.resolveBackingFile(for: cueURL, fileName: fileName)

        // Escaping path is neutralized: it must NOT resolve outside the cue's directory.
        XCTAssertFalse(resolved.standardizedFileURL.path.hasSuffix("/etc/passwd"))
        XCTAssertEqual(resolved.deletingLastPathComponent().standardizedFileURL.path,
                       cueURL.deletingLastPathComponent().standardizedFileURL.path)
    }

    func testParseRejectsExcessiveTrackCount() throws {
        var lines = ["FILE \"backing.flac\" WAVE"]
        for n in 1...(CueSheet.maxEntries + 1) {
            lines.append("TRACK \(n) AUDIO")
            lines.append("INDEX 01 00:00:00")
        }
        let cueURL = tempDirectory.appendingPathComponent("huge.cue")
        try lines.joined(separator: "\n").write(to: cueURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CueSheet.parse(from: cueURL))
    }
}
