import XCTest
@testable import NullPlayer

final class AudioEngineShuffleTests: XCTestCase {
    func testShufflePlaybackVisitsEveryTrackOnceBeforeStopping() throws {
        let engine = AudioEngine()
        engine.setPlaylistTracks(makePlaceholderTracks(count: 5))
        engine.shuffleEnabled = true
        engine.repeatEnabled = false
        engine.debugStartShuffleCycleForTesting(at: 0)

        var seenIndices: Set<Int> = [0]

        for _ in 0..<(engine.playlist.count - 1) {
            let nextIndex = try XCTUnwrap(engine.debugPeekNextShuffleIndexForPlayback())
            XCTAssertFalse(seenIndices.contains(nextIndex))
            seenIndices.insert(nextIndex)
            XCTAssertEqual(engine.debugAdvanceShuffleIndexForPlayback(), nextIndex)
        }

        XCTAssertEqual(seenIndices.count, engine.playlist.count)
        XCTAssertNil(engine.debugPeekNextShuffleIndexForPlayback())
    }

    func testShuffleRepeatStartsNewCycleWithoutImmediateRepeat() throws {
        let engine = AudioEngine()
        engine.setPlaylistTracks(makePlaceholderTracks(count: 5))
        engine.shuffleEnabled = true
        engine.repeatEnabled = true
        engine.debugStartShuffleCycleForTesting(at: 0)

        for _ in 0..<(engine.playlist.count - 1) {
            let nextIndex = try XCTUnwrap(engine.debugPeekNextShuffleIndexForPlayback())
            XCTAssertEqual(engine.debugAdvanceShuffleIndexForPlayback(), nextIndex)
        }

        let currentIndex = engine.currentIndex
        let wrappedIndex = try XCTUnwrap(engine.debugPeekNextShuffleIndexForPlayback())

        XCTAssertNotEqual(wrappedIndex, currentIndex)
        XCTAssertTrue(engine.playlist.indices.contains(wrappedIndex))
    }

    func testPreferredShuffleCycleStartsInsideRequestedRangeAndExhaustsItFirst() throws {
        let engine = AudioEngine()
        engine.setPlaylistTracks(makePlaceholderTracks(count: 8))
        engine.shuffleEnabled = true
        engine.repeatEnabled = false

        let preferredIndices = [2, 3, 4]
        let startingIndex = try XCTUnwrap(engine.debugStartPreferredShuffleCycleForTesting(preferredIndices))
        XCTAssertTrue(preferredIndices.contains(startingIndex))

        var seenPreferredIndices: Set<Int> = [startingIndex]
        for _ in 0..<(preferredIndices.count - 1) {
            let nextIndex = try XCTUnwrap(engine.debugPeekNextShuffleIndexForPlayback())
            XCTAssertTrue(preferredIndices.contains(nextIndex))
            XCTAssertFalse(seenPreferredIndices.contains(nextIndex))
            seenPreferredIndices.insert(nextIndex)
            XCTAssertEqual(engine.debugAdvanceShuffleIndexForPlayback(), nextIndex)
        }

        XCTAssertEqual(seenPreferredIndices, Set(preferredIndices))
    }

    func testExplicitTrackSelectionResetsShuffleCycleAroundSelectedTrack() throws {
        let engine = AudioEngine()
        engine.setPlaylistTracks(makePlaceholderTracks(count: 6))
        engine.shuffleEnabled = true
        engine.repeatEnabled = false
        engine.debugStartShuffleCycleForTesting(at: 0)

        engine.debugSelectTrackForShuffleTesting(5)

        var seenIndices: Set<Int> = [5]
        for _ in 0..<(engine.playlist.count - 1) {
            let nextIndex = try XCTUnwrap(engine.debugPeekNextShuffleIndexForPlayback())
            XCTAssertFalse(seenIndices.contains(nextIndex))
            seenIndices.insert(nextIndex)
            XCTAssertEqual(engine.debugAdvanceShuffleIndexForPlayback(), nextIndex)
        }

        XCTAssertEqual(seenIndices.count, engine.playlist.count)
        XCTAssertNil(engine.debugPeekNextShuffleIndexForPlayback())
    }

    @MainActor
    func testVideoEndExhaustsQueueWithoutWrappingWhenRepeatIsOff() {
        // Cover both the reported one-video loop and the last entry of a longer queue.
        for count in [1, 3] {
            let engine = AudioEngine()
            let tracks = (0..<count).map { index in
                Track(url: URL(string: "https://example.invalid/video-\(index).mp4")!,
                      title: "Video \(index)", mediaType: .video)
            }
            engine.setPlaylistTracks(tracks)
            engine.repeatEnabled = false
            engine.shuffleEnabled = false
            // Select without starting a decoder or making a network request.
            engine.debugSelectTrackForShuffleTesting(count - 1)

            let exhausted = expectation(description: "Video queue of \(count) exhausts at EOF")
            let observer = NotificationCenter.default.addObserver(
                forName: .audioQueueDidExhaust, object: engine, queue: nil
            ) { _ in exhausted.fulfill() }
            defer { NotificationCenter.default.removeObserver(observer) }

            engine.videoTrackDidFinish()

            wait(for: [exhausted], timeout: 1)
            XCTAssertEqual(engine.state, .stopped)
            XCTAssertEqual(engine.currentIndex, count - 1, "EOF must not wrap to the first video")
            XCTAssertEqual(engine.currentTrack?.id, tracks.last?.id)
        }
    }

    private func makePlaceholderTracks(count: Int) -> [Track] {
        let placeholderURL = URL(string: "about:blank")!
        return (0..<count).map { index in
            Track(url: placeholderURL, title: "Track \(index)")
        }
    }
}
