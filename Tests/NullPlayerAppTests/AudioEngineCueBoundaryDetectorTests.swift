import XCTest
@testable import NullPlayer

final class AudioEngineCueBoundaryDetectorTests: XCTestCase {

    // MARK: - shouldAdvanceCueTrackAtBoundary Pure Logic Tests

    func testShouldAdvanceCueTrackAtBoundaryCrossesBoundaryWithSameFile() {
        // Create tracks from the same cue (same backing file)
        let cueURL = URL(fileURLWithPath: "/tmp/album.cue")
        let backingURL = URL(fileURLWithPath: "/tmp/backing.flac")

        let track1 = Track(
            url: backingURL,
            title: "Track 1",
            cueStartOffset: 0.0,
            cueEndOffset: 120.0,
            cueSourceURL: cueURL
        )

        let track2 = Track(
            url: backingURL,
            title: "Track 2",
            cueStartOffset: 120.0,
            cueEndOffset: 240.0,
            cueSourceURL: cueURL
        )

        let playlist = [track1, track2]
        let currentIndex = 0

        // At the boundary
        let nextIndex = AudioEngine.shouldAdvanceCueTrackAtBoundary(
            currentIndex: currentIndex,
            currentTime: 120.0,  // Reached cue end
            currentTrack: track1,
            playlist: playlist,
            shuffleEnabled: false,
            repeatEnabled: false
        )

        XCTAssertEqual(nextIndex, 1)
    }

    func testShouldAdvanceCueTrackAtBoundaryBeforeBoundaryReturnsNil() {
        let cueURL = URL(fileURLWithPath: "/tmp/album.cue")
        let backingURL = URL(fileURLWithPath: "/tmp/backing.flac")

        let track1 = Track(
            url: backingURL,
            title: "Track 1",
            cueStartOffset: 0.0,
            cueEndOffset: 120.0,
            cueSourceURL: cueURL
        )

        let track2 = Track(
            url: backingURL,
            title: "Track 2",
            cueStartOffset: 120.0,
            cueEndOffset: 240.0,
            cueSourceURL: cueURL
        )

        let playlist = [track1, track2]

        // Before the boundary
        let nextIndex = AudioEngine.shouldAdvanceCueTrackAtBoundary(
            currentIndex: 0,
            currentTime: 119.9,
            currentTrack: track1,
            playlist: playlist,
            shuffleEnabled: false,
            repeatEnabled: false
        )

        XCTAssertNil(nextIndex)
    }

    func testShouldAdvanceCueTrackAtBoundaryShuffleEnabledReturnsNil() {
        let cueURL = URL(fileURLWithPath: "/tmp/album.cue")
        let backingURL = URL(fileURLWithPath: "/tmp/backing.flac")

        let track1 = Track(
            url: backingURL,
            title: "Track 1",
            cueStartOffset: 0.0,
            cueEndOffset: 120.0,
            cueSourceURL: cueURL
        )

        let track2 = Track(
            url: backingURL,
            title: "Track 2",
            cueStartOffset: 120.0,
            cueEndOffset: 240.0,
            cueSourceURL: cueURL
        )

        let playlist = [track1, track2]

        // Boundary crossed, but shuffle is enabled
        let nextIndex = AudioEngine.shouldAdvanceCueTrackAtBoundary(
            currentIndex: 0,
            currentTime: 120.0,
            currentTrack: track1,
            playlist: playlist,
            shuffleEnabled: true,  // SHUFFLE ON
            repeatEnabled: false
        )

        XCTAssertNil(nextIndex)
    }

    func testShouldAdvanceCueTrackAtBoundaryRepeatSingleReturnsNil() {
        let cueURL = URL(fileURLWithPath: "/tmp/album.cue")
        let backingURL = URL(fileURLWithPath: "/tmp/backing.flac")

        let track1 = Track(
            url: backingURL,
            title: "Track 1",
            cueStartOffset: 0.0,
            cueEndOffset: 120.0,
            cueSourceURL: cueURL
        )

        let track2 = Track(
            url: backingURL,
            title: "Track 2",
            cueStartOffset: 120.0,
            cueEndOffset: 240.0,
            cueSourceURL: cueURL
        )

        let playlist = [track1, track2]

        // Boundary crossed, but repeat-single is enabled
        let nextIndex = AudioEngine.shouldAdvanceCueTrackAtBoundary(
            currentIndex: 0,
            currentTime: 120.0,
            currentTrack: track1,
            playlist: playlist,
            shuffleEnabled: false,
            repeatEnabled: true  // REPEAT ON (assume repeat-single)
        )

        XCTAssertNil(nextIndex)
    }

    func testShouldAdvanceCueTrackAtBoundaryLastEntryReturnsNil() {
        let cueURL = URL(fileURLWithPath: "/tmp/album.cue")
        let backingURL = URL(fileURLWithPath: "/tmp/backing.flac")

        let track1 = Track(
            url: backingURL,
            title: "Track 1",
            cueStartOffset: 0.0,
            cueEndOffset: 120.0,
            cueSourceURL: cueURL
        )

        let track2 = Track(
            url: backingURL,
            title: "Track 2 (Last)",
            cueStartOffset: 120.0,
            cueEndOffset: nil,  // Last track has no end offset
            cueSourceURL: cueURL
        )

        let playlist = [track1, track2]

        // At track2's boundary (which is at EOF), currentIndex+1 is out of range
        let nextIndex = AudioEngine.shouldAdvanceCueTrackAtBoundary(
            currentIndex: 1,  // Already on last track
            currentTime: 240.0,
            currentTrack: track2,
            playlist: playlist,
            shuffleEnabled: false,
            repeatEnabled: false
        )

        XCTAssertNil(nextIndex)  // No next entry
    }

    func testShouldAdvanceCueTrackAtBoundaryCurrentIndexOutOfRangeReturnsNil() {
        let cueURL = URL(fileURLWithPath: "/tmp/album.cue")
        let backingURL = URL(fileURLWithPath: "/tmp/backing.flac")

        let track1 = Track(
            url: backingURL,
            title: "Track 1",
            cueStartOffset: 0.0,
            cueEndOffset: 120.0,
            cueSourceURL: cueURL
        )

        let playlist = [track1]

        // currentIndex+1 >= playlist.count
        let nextIndex = AudioEngine.shouldAdvanceCueTrackAtBoundary(
            currentIndex: 0,
            currentTime: 120.0,
            currentTrack: track1,
            playlist: playlist,
            shuffleEnabled: false,
            repeatEnabled: false
        )

        XCTAssertNil(nextIndex)  // No room for next
    }

    func testShouldAdvanceCueTrackAtBoundaryNoCueEndOffsetReturnsNil() {
        // Track without cue end offset (not a cue track, or last in cue)
        let normalTrack = Track(url: URL(fileURLWithPath: "/tmp/file.flac"), title: "Normal Track")

        let track2 = Track(
            url: URL(fileURLWithPath: "/tmp/file.flac"),
            title: "Track 2",
            cueSourceURL: nil
        )

        let playlist = [normalTrack, track2]

        let nextIndex = AudioEngine.shouldAdvanceCueTrackAtBoundary(
            currentIndex: 0,
            currentTime: 120.0,
            currentTrack: normalTrack,
            playlist: playlist,
            shuffleEnabled: false,
            repeatEnabled: false
        )

        XCTAssertNil(nextIndex)  // Current track has no cue end offset
    }

    func testShouldAdvanceCueTrackAtBoundaryDifferentBackingFilesReturnsNil() {
        // Two cue tracks from different backing files
        let cueURL1 = URL(fileURLWithPath: "/tmp/album1.cue")
        let cueURL2 = URL(fileURLWithPath: "/tmp/album2.cue")
        let backingURL1 = URL(fileURLWithPath: "/tmp/backing1.flac")
        let backingURL2 = URL(fileURLWithPath: "/tmp/backing2.flac")

        let track1 = Track(
            url: backingURL1,
            title: "Album1 Track 1",
            cueStartOffset: 0.0,
            cueEndOffset: 120.0,
            cueSourceURL: cueURL1
        )

        let track2 = Track(
            url: backingURL2,
            title: "Album2 Track 1",
            cueStartOffset: 0.0,
            cueEndOffset: 120.0,
            cueSourceURL: cueURL2  // Different source
        )

        let playlist = [track1, track2]

        let nextIndex = AudioEngine.shouldAdvanceCueTrackAtBoundary(
            currentIndex: 0,
            currentTime: 120.0,
            currentTrack: track1,
            playlist: playlist,
            shuffleEnabled: false,
            repeatEnabled: false
        )

        XCTAssertNil(nextIndex)  // Next track is from a different cue
    }

    func testShouldAdvanceCueTrackAtBoundaryWithoutCueSourceReturnsNil() {
        // Current track is not a cue track (cueSourceURL is nil)
        let track1 = Track(
            url: URL(fileURLWithPath: "/tmp/file.flac"),
            title: "Normal Track",
            cueStartOffset: nil,
            cueEndOffset: nil,
            cueSourceURL: nil  // Not a cue track
        )

        let track2 = Track(
            url: URL(fileURLWithPath: "/tmp/file.flac"),
            title: "Track 2"
        )

        let playlist = [track1, track2]

        let nextIndex = AudioEngine.shouldAdvanceCueTrackAtBoundary(
            currentIndex: 0,
            currentTime: 100.0,
            currentTrack: track1,
            playlist: playlist,
            shuffleEnabled: false,
            repeatEnabled: false
        )

        XCTAssertNil(nextIndex)  // Current track has no cueSourceURL
    }

    func testShouldAdvanceCueTrackAtBoundaryMultipleBoundaries() {
        // Verify behavior across multiple tracks in a cue
        let cueURL = URL(fileURLWithPath: "/tmp/album.cue")
        let backingURL = URL(fileURLWithPath: "/tmp/backing.flac")

        let track1 = Track(
            url: backingURL,
            title: "Track 1",
            cueStartOffset: 0.0,
            cueEndOffset: 120.0,
            cueSourceURL: cueURL
        )

        let track2 = Track(
            url: backingURL,
            title: "Track 2",
            cueStartOffset: 120.0,
            cueEndOffset: 240.0,
            cueSourceURL: cueURL
        )

        let track3 = Track(
            url: backingURL,
            title: "Track 3",
            cueStartOffset: 240.0,
            cueEndOffset: 360.0,
            cueSourceURL: cueURL
        )

        let playlist = [track1, track2, track3]

        // Cross first boundary
        var nextIndex = AudioEngine.shouldAdvanceCueTrackAtBoundary(
            currentIndex: 0,
            currentTime: 120.0,
            currentTrack: track1,
            playlist: playlist,
            shuffleEnabled: false,
            repeatEnabled: false
        )
        XCTAssertEqual(nextIndex, 1)

        // Cross second boundary. currentTime is track-relative (reset to 0 at each advance),
        // and track 2 is 120s long (cueEnd 240 − cueStart 120), so it crosses at 120s — NOT
        // at the absolute cueEnd of 240s.
        nextIndex = AudioEngine.shouldAdvanceCueTrackAtBoundary(
            currentIndex: 1,
            currentTime: 120.0,
            currentTrack: track2,
            playlist: playlist,
            shuffleEnabled: false,
            repeatEnabled: false
        )
        XCTAssertEqual(nextIndex, 2)

        // Last track, no third boundary (no next entry, so returns nil regardless of time)
        nextIndex = AudioEngine.shouldAdvanceCueTrackAtBoundary(
            currentIndex: 2,
            currentTime: 120.0,
            currentTrack: track3,
            playlist: playlist,
            shuffleEnabled: false,
            repeatEnabled: false
        )
        XCTAssertNil(nextIndex)
    }

    func testShouldAdvanceCueTrackAtBoundaryBoundaryExactMatch() {
        // Test at exact boundary
        let cueURL = URL(fileURLWithPath: "/tmp/album.cue")
        let backingURL = URL(fileURLWithPath: "/tmp/backing.flac")

        let track1 = Track(
            url: backingURL,
            title: "Track 1",
            cueStartOffset: 0.0,
            cueEndOffset: 123.456,
            cueSourceURL: cueURL
        )

        let track2 = Track(
            url: backingURL,
            title: "Track 2",
            cueStartOffset: 123.456,
            cueEndOffset: 240.0,
            cueSourceURL: cueURL
        )

        let playlist = [track1, track2]

        // Exact boundary crossing
        let nextIndex = AudioEngine.shouldAdvanceCueTrackAtBoundary(
            currentIndex: 0,
            currentTime: 123.456,
            currentTrack: track1,
            playlist: playlist,
            shuffleEnabled: false,
            repeatEnabled: false
        )

        XCTAssertEqual(nextIndex, 1)
    }

    func testShouldAdvanceCueTrackAtBoundaryBoundarySlightlyAfter() {
        // Test just after boundary
        let cueURL = URL(fileURLWithPath: "/tmp/album.cue")
        let backingURL = URL(fileURLWithPath: "/tmp/backing.flac")

        let track1 = Track(
            url: backingURL,
            title: "Track 1",
            cueStartOffset: 0.0,
            cueEndOffset: 120.0,
            cueSourceURL: cueURL
        )

        let track2 = Track(
            url: backingURL,
            title: "Track 2",
            cueStartOffset: 120.0,
            cueEndOffset: 240.0,
            cueSourceURL: cueURL
        )

        let playlist = [track1, track2]

        // Just after boundary
        let nextIndex = AudioEngine.shouldAdvanceCueTrackAtBoundary(
            currentIndex: 0,
            currentTime: 120.001,
            currentTrack: track1,
            playlist: playlist,
            shuffleEnabled: false,
            repeatEnabled: false
        )

        XCTAssertEqual(nextIndex, 1)
    }

    func testShouldAdvanceCueTrackAtBoundaryCurrentTrackNil() {
        // Edge case: currentTrack is nil
        let track2 = Track(
            url: URL(fileURLWithPath: "/tmp/backing.flac"),
            title: "Track 2"
        )

        let playlist = [track2]

        let nextIndex = AudioEngine.shouldAdvanceCueTrackAtBoundary(
            currentIndex: 0,
            currentTime: 120.0,
            currentTrack: nil,
            playlist: playlist,
            shuffleEnabled: false,
            repeatEnabled: false
        )

        XCTAssertNil(nextIndex)  // currentTrack is nil, guard fails
    }
}
