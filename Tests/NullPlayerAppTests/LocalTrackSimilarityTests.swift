import XCTest
@testable import NullPlayer

/// Tests for the tag-based scoring and ranking behind local Track Radio. They never touch the
/// library or radio-history singletons, which open the user's real databases.
/// Only `ranked` is random, by less than `jitter`, so order tests use larger score gaps.
final class LocalTrackSimilarityTests: XCTestCase {

    /// Tag similarity of `candidate` to `seed`, before taste.
    private func similarity(_ seed: LibraryTrack, _ candidate: LibraryTrack) -> Double {
        LocalTrackSimilarity(seed: seed).similarity(candidate)
    }

    private func rank(_ seed: LibraryTrack, _ candidate: LibraryTrack) -> Double? {
        LocalTrackSimilarity(seed: seed).rank(candidate)
    }

    private func track(_ title: String,
                       artist: String? = nil,
                       albumArtist: String? = nil,
                       genre: String? = nil,
                       year: Int? = nil,
                       playCount: Int = 0,
                       rating: Int? = nil,
                       grouping: String? = nil,
                       bpm: Int? = nil,
                       key: String? = nil) -> LibraryTrack {
        LibraryTrack(url: URL(fileURLWithPath: "/music/\(title).mp3"),
                     title: title,
                     artist: artist,
                     albumArtist: albumArtist,
                     genre: genre,
                     year: year,
                     playCount: playCount,
                     rating: rating,
                     grouping: grouping,
                     bpm: bpm,
                     musicalKey: key)
    }

    // MARK: - Genre

    func testGenreOverlapSplitsOnSeparators() {
        XCTAssertEqual(LocalTrackSimilarity.genreOverlap("Rock; Blues", "Blues"), 0.5, accuracy: 0.0001)
        XCTAssertEqual(LocalTrackSimilarity.genreOverlap("Rock/Blues", "blues , rock"), 1.0, accuracy: 0.0001)
    }

    func testGenreOverlapIsZeroWhenEitherSideHasNoGenre() {
        XCTAssertEqual(LocalTrackSimilarity.genreOverlap(nil, "Rock"), 0)
        XCTAssertEqual(LocalTrackSimilarity.genreOverlap("Rock", "  "), 0)
    }

    func testSharedGenreOutranksUnrelatedGenre() {
        let seed = track("Seed", artist: "A", genre: "Southern Rock", year: 1973)
        let near = track("Near", artist: "B", genre: "Southern Rock", year: 1975)
        let far = track("Far", artist: "C", genre: "Jazz", year: 1973)
        XCTAssertGreaterThan(similarity(seed, near), similarity(seed, far))
    }

    // MARK: - Artist

    func testSharesArtistMatchesAlbumArtistAndIgnoresCase() {
        let seed = track("Seed", artist: "Lynyrd Skynyrd")
        let other = track("Other", artist: "Various", albumArtist: " lynyrd skynyrd ")
        XCTAssertEqual(similarity(seed, other), LocalTrackSimilarity.artistWeight, accuracy: 0.0001)
        XCTAssertEqual(similarity(seed, track("Else", artist: "ZZ Top")), 0, accuracy: 0.0001)
    }

    func testFeaturedCreditStillSharesTheArtist() {
        let seed = track("Seed", artist: "Lynyrd Skynyrd")
        var credited = track("Credited", artist: "Lynyrd Skynyrd feat. Someone")
        credited.rebuildArtistRoles()
        XCTAssertEqual(similarity(seed, credited), LocalTrackSimilarity.artistWeight, accuracy: 0.0001)
    }

    func testTracksWithNoArtistTagDoNotShareAnArtist() {
        var seed = track("Seed")
        var other = track("Other")
        seed.rebuildArtistRoles()
        other.rebuildArtistRoles()
        XCTAssertEqual(similarity(seed, other), 0, accuracy: 0.0001)
    }

    func testSameArtistAloneClearsTheMinimum() {
        let seed = track("Seed", artist: "A")
        XCTAssertNotNil(rank(seed, track("Sibling", artist: "A")))
    }

    func testUnrelatedTrackIsNotRanked() {
        let seed = track("Seed", artist: "A", genre: "Rock", year: 1973)
        XCTAssertNil(rank(seed, track("Stranger", artist: "B", genre: "Jazz", year: 2009)))
    }

    // MARK: - Year

    func testYearGapBeyondHorizonEarnsNothing() {
        let seed = track("Seed", year: 1970)
        let distant = track("Distant", year: 1970 + Int(LocalTrackSimilarity.yearHorizon) + 5)
        XCTAssertEqual(similarity(seed, distant), 0, accuracy: 0.0001)
    }

    func testYearAloneIsNotRanked() {
        let seed = track("Seed", artist: "A", genre: "Rock", year: 1970)
        XCTAssertNil(rank(seed, track("Same Year", artist: "B", genre: "Jazz", year: 1970)))
    }

    func testPreferenceCannotLiftYearOnlyMatchIntoTheQueue() {
        let seed = track("Seed", artist: "A", genre: "Rock", year: 1970)
        let favorite = track("Favorite", artist: "B", genre: "Jazz", year: 1970, playCount: 50, rating: 10)
        XCTAssertLessThan(similarity(seed, favorite), LocalTrackSimilarity.minimumScore)
        XCTAssertNil(rank(seed, favorite))
    }

    func testSameYearEarnsFullYearWeight() {
        let seed = track("Seed", year: 1970)
        XCTAssertEqual(similarity(seed, track("Twin", year: 1970)),
                       LocalTrackSimilarity.yearWeight, accuracy: 0.0001)
    }

    // MARK: - Tempo and key

    func testHalfAndDoubleTimeCountAsTheSameTempo() {
        XCTAssertEqual(LocalTrackSimilarity.tempoCloseness(120, 60), 1, accuracy: 0.0001)
        XCTAssertEqual(LocalTrackSimilarity.tempoCloseness(60, 120), 1, accuracy: 0.0001)
    }

    func testTempoOutsideToleranceScoresZero() {
        XCTAssertEqual(LocalTrackSimilarity.tempoCloseness(100, 130), 0, accuracy: 0.0001)
    }

    func testMissingTempoScoresZero() {
        XCTAssertEqual(LocalTrackSimilarity.tempoCloseness(nil, 120), 0)
        XCTAssertEqual(LocalTrackSimilarity.tempoCloseness(120, 0), 0)
    }

    func testMatchingKeyIgnoresCaseAndSpaces() {
        let seed = track("Seed", key: "A m")
        XCTAssertEqual(similarity(seed, track("Match", key: "am")),
                       LocalTrackSimilarity.keyWeight, accuracy: 0.0001)
    }

    // MARK: - Listener preference

    func testLowRatingIsPenalizedAndHighRatingBoosted() throws {
        let seed = track("Seed", artist: "A")
        let base = try XCTUnwrap(rank(seed, track("Unrated", artist: "A")))
        XCTAssertEqual(try XCTUnwrap(rank(seed, track("Disliked", artist: "A", rating: 2))), base - 1.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(rank(seed, track("Loved", artist: "A", rating: 9))), base + 0.5, accuracy: 0.0001)
    }

    func testPlayCountNudgeIsCapped() throws {
        let seed = track("Seed", artist: "A")
        XCTAssertEqual(try XCTUnwrap(rank(seed, track("Often", artist: "A", playCount: 20))),
                       try XCTUnwrap(rank(seed, track("Absurd", artist: "A", playCount: 5_000))), accuracy: 0.0001)
    }

    // MARK: - Ranking

    private func ranked(_ seed: LibraryTrack, _ candidates: [LibraryTrack]) -> [String] {
        LocalTrackSimilarity(seed: seed).ranked(candidates).map(\.title)
    }

    func testRankedLeavesOutTheSeedAndTracksThatAreNotAlike() {
        let seed = track("Seed", artist: "A", genre: "Rock")
        let alike = track("Alike", artist: "B", genre: "Rock")
        let stranger = track("Stranger", artist: "C", genre: "Jazz")
        XCTAssertEqual(ranked(seed, [alike, seed, stranger]), ["Alike"])
    }

    func testRankedPutsCloserMatchesFirst() {
        // Same artist + genre scores 6.0; genre alone scores 4.0. The gap is larger than
        // `jitter`, so the order is the same on every run.
        let seed = track("Seed", artist: "A", genre: "Rock")
        let weaker = track("Weaker", artist: "B", genre: "Rock")
        let closer = track("Closer", artist: "A", genre: "Rock")
        XCTAssertEqual(ranked(seed, [weaker, closer]), ["Closer", "Weaker"])
    }

    func testRankedIsEmptyWhenNothingIsAlike() {
        let seed = track("Seed", artist: "A", genre: "Rock")
        XCTAssertEqual(ranked(seed, [track("Other", artist: "B", genre: "Jazz")]), [])
    }
}
