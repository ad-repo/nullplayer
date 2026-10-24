import XCTest
@testable import NullPlayer

/// Tests for the tag-based scoring behind local Track Radio. The scoring is pure and
/// deterministic; the randomness lives in `MediaLibrary.createLocalTrackRadio(from:)`.
final class LocalTrackSimilarityTests: XCTestCase {

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
        XCTAssertGreaterThan(LocalTrackSimilarity.score(seed: seed, candidate: near),
                             LocalTrackSimilarity.score(seed: seed, candidate: far))
    }

    // MARK: - Artist

    func testSharesArtistMatchesAlbumArtistAndIgnoresCase() {
        let seed = track("Seed", artist: "Lynyrd Skynyrd")
        let other = track("Other", artist: "Various", albumArtist: " lynyrd skynyrd ")
        XCTAssertTrue(LocalTrackSimilarity.sharesArtist(seed, other))
        XCTAssertFalse(LocalTrackSimilarity.sharesArtist(seed, track("Else", artist: "ZZ Top")))
    }

    func testSameArtistAloneClearsTheMinimum() {
        let seed = track("Seed", artist: "A")
        let sibling = track("Sibling", artist: "A")
        XCTAssertGreaterThanOrEqual(LocalTrackSimilarity.score(seed: seed, candidate: sibling),
                                    LocalTrackSimilarity.minimumScore)
    }

    func testUnrelatedTrackStaysBelowTheMinimum() {
        let seed = track("Seed", artist: "A", genre: "Rock", year: 1973)
        let stranger = track("Stranger", artist: "B", genre: "Jazz", year: 2009)
        XCTAssertLessThan(LocalTrackSimilarity.score(seed: seed, candidate: stranger),
                          LocalTrackSimilarity.minimumScore)
    }

    // MARK: - Year

    func testYearGapBeyondHorizonEarnsNothing() {
        let seed = track("Seed", year: 1970)
        let distant = track("Distant", year: 1970 + Int(LocalTrackSimilarity.yearHorizon) + 5)
        XCTAssertEqual(LocalTrackSimilarity.score(seed: seed, candidate: distant), 0, accuracy: 0.0001)
    }

    func testYearAloneStaysBelowTheMinimum() {
        let seed = track("Seed", artist: "A", genre: "Rock", year: 1970)
        let sameYear = track("Same Year", artist: "B", genre: "Jazz", year: 1970)
        XCTAssertLessThan(LocalTrackSimilarity.score(seed: seed, candidate: sameYear),
                          LocalTrackSimilarity.minimumScore)
    }

    func testPreferenceCannotLiftYearOnlyMatchOverTheMinimum() {
        let seed = track("Seed", artist: "A", genre: "Rock", year: 1970)
        let favorite = track("Favorite", artist: "B", genre: "Jazz", year: 1970, playCount: 50, rating: 10)
        XCTAssertGreaterThanOrEqual(LocalTrackSimilarity.score(seed: seed, candidate: favorite),
                                    LocalTrackSimilarity.minimumScore)
        XCTAssertLessThan(LocalTrackSimilarity.similarity(seed: seed, candidate: favorite),
                          LocalTrackSimilarity.minimumScore)
    }

    func testSameYearEarnsFullYearWeight() {
        let seed = track("Seed", year: 1970)
        let twin = track("Twin", year: 1970)
        XCTAssertEqual(LocalTrackSimilarity.score(seed: seed, candidate: twin),
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
        let match = track("Match", key: "am")
        XCTAssertEqual(LocalTrackSimilarity.score(seed: seed, candidate: match),
                       LocalTrackSimilarity.keyWeight, accuracy: 0.0001)
    }

    // MARK: - Listener preference

    func testLowRatingIsPenalizedAndHighRatingBoosted() {
        let seed = track("Seed", artist: "A")
        let unrated = track("Unrated", artist: "A")
        let disliked = track("Disliked", artist: "A", rating: 2)
        let loved = track("Loved", artist: "A", rating: 9)
        let base = LocalTrackSimilarity.score(seed: seed, candidate: unrated)
        XCTAssertEqual(LocalTrackSimilarity.score(seed: seed, candidate: disliked), base - 1.5, accuracy: 0.0001)
        XCTAssertEqual(LocalTrackSimilarity.score(seed: seed, candidate: loved), base + 0.5, accuracy: 0.0001)
    }

    func testPlayCountNudgeIsCapped() {
        let seed = track("Seed", artist: "A")
        let often = track("Often", artist: "A", playCount: 20)
        let absurd = track("Absurd", artist: "A", playCount: 5_000)
        XCTAssertEqual(LocalTrackSimilarity.score(seed: seed, candidate: often),
                       LocalTrackSimilarity.score(seed: seed, candidate: absurd), accuracy: 0.0001)
    }
}
