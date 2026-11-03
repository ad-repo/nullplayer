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

            engine.videoTrackDidEnd(.finished)

            wait(for: [exhausted], timeout: 1)
            XCTAssertEqual(engine.state, .stopped)
            XCTAssertEqual(engine.currentIndex, count - 1, "EOF must not wrap to the first video")
            XCTAssertEqual(engine.currentTrack?.id, tracks.last?.id)
        }
    }

    /// Reverse, Sort and Randomize keep the current index on the entry that was playing when every
    /// entry shares one URL, as a cue sheet's tracks do. Matched by URL, it jumped to the first row.
    func testReorderingKeepsTheCurrentEntryWhenTracksShareAURL() {
        let engine = AudioEngine()
        engine.setPlaylistTracks(makePlaceholderTracks(count: 4))
        engine.debugStartShuffleCycleForTesting(at: 1)
        let playing = engine.playlist[1].id

        engine.reversePlaylist()
        XCTAssertEqual(engine.currentIndex, 2)
        engine.sortPlaylist(by: .title, ascending: false)
        XCTAssertEqual(engine.playlist[engine.currentIndex].id, playing)
        engine.shufflePlaylist()
        XCTAssertEqual(engine.playlist[engine.currentIndex].id, playing)
    }

    /// A playlist drag (M69) shifts a selection with gaps in it as one block, clamped at the ends,
    /// and the playing entry is followed wherever it lands, inside the selection or out of it.
    func testMoveTracksShiftsTheSelectionAndFollowsTheCurrentEntry() {
        XCTAssertEqual(AudioEngine.shiftedOrder(count: 6, moving: [1, 3], by: 1), [0, 2, 1, 4, 3, 5])
        XCTAssertEqual(AudioEngine.shiftedOrder(count: 6, moving: [4, 5], by: -4), [4, 5, 0, 1, 2, 3])

        let engine = AudioEngine()
        engine.setPlaylistTracks(makePlaceholderTracks(count: 6))
        let ids = engine.playlist.map(\.id)
        engine.debugStartShuffleCycleForTesting(at: 2)

        XCTAssertEqual(engine.moveTracks([1, 3], by: 10), [3, 5], "clamped at the end")
        XCTAssertEqual(engine.playlist.map(\.id), [0, 2, 4, 1, 5, 3].map { ids[$0] })
        XCTAssertEqual(engine.playlist[engine.currentIndex].id, ids[2])

        XCTAssertEqual(engine.moveTracks([1], by: -1), [0], "the playing row itself")
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.moveTracks([0], by: -1), [0], "already at the top")
    }

    /// A drag crosses many rows, one `moveTracks` each; the upcoming shuffle order must follow the
    /// tracks through every step, not be drawn again at each one.
    func testMoveTracksCarriesTheShuffleOrderThroughTheMove() {
        let engine = AudioEngine()
        engine.setPlaylistTracks(makePlaceholderTracks(count: 6))
        engine.shuffleEnabled = true
        engine.debugStartShuffleCycleForTesting(at: 2)
        let upcomingIDs = { engine.upcomingIndices.map { engine.playlist[$0].id } }
        let before = upcomingIDs()

        engine.moveTracks([0, 4], by: 1)
        engine.moveTracks([1, 5], by: -1)
        engine.moveTracks([2], by: 3)

        XCTAssertEqual(upcomingIDs(), before)
        XCTAssertEqual(engine.debugPeekNextShuffleIndexForPlayback().map { engine.playlist[$0].id }, before.first)
    }

    /// The press, drag and release a playlist view runs, over a stand-in for `moveTracks`.
    func testPlaylistRowDragMovesAndCollapsesTheSelection() {
        var rows = Array(0..<6)
        let move = { (selection: Set<Int>, offset: Int) -> Set<Int> in
            let order = AudioEngine.shiftedOrder(count: rows.count, moving: selection,
                                                 by: min(max(offset, -selection.min()!), rows.count - 1 - selection.max()!))
            let landed = Set(order.indices.filter { selection.contains(order[$0]) })
            rows = order.map { rows[$0] }
            return landed
        }

        var single = PlaylistRowDrag(pressing: 4, in: [1, 2])
        XCTAssertEqual(single.selection, [4], "a press outside the selection selects the row alone")
        XCTAssertEqual(single.releasedSelection, [4])

        var kept = PlaylistRowDrag(pressing: 2, in: [1, 2])
        XCTAssertEqual(kept.selection, [1, 2], "a press inside it keeps it for the drag")
        XCTAssertEqual(kept.releasedSelection, [2], "and a release that moved nothing collapses it")

        kept.drag(to: 9, move: move)
        XCTAssertEqual(kept.selection, [4, 5], "clamped at the end")
        XCTAssertEqual(kept.row, 5, "the held row follows the clamp")
        XCTAssertEqual(kept.releasedSelection, [4, 5])
        XCTAssertEqual(rows, [0, 3, 4, 5, 1, 2])

        single.drag(to: 4, move: move)
        XCTAssertEqual(single.selection, [4], "no move onto its own row")
    }

    /// Next onto a restored placeholder makes it current, so `play()` resolves it. Skipped, the
    /// outgoing track stayed current and Next resumed it while the highlight moved on (#583).
    func testNextMakesAPlaceholderCurrent() {
        let engine = AudioEngine()
        engine.setPlaylistTracks(makePlaceholderTracks(count: 3))
        engine.debugStartShuffleCycleForTesting(at: 0)

        engine.next()
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.currentTrack?.id, engine.playlist[1].id)
    }

    private func makePlaceholderTracks(count: Int) -> [Track] {
        let placeholderURL = URL(string: "about:blank")!
        return (0..<count).map { index in
            Track(url: placeholderURL, title: "Track \(index)")
        }
    }
}
