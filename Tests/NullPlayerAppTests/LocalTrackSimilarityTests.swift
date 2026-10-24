import XCTest
@testable import NullPlayer

/// Tests for the tag-based scoring behind local Track Radio, and for the queue it builds. The
/// scoring is pure and deterministic; the randomness lives in
/// `MediaLibrary.createLocalTrackRadio(from:)`.
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

    // MARK: - The queue

    func testQueueStartsWithSeedOnceAndKeepsOnlyAlikeTracks() {
        let seed = track("Seed", artist: "A", genre: "Rock")
        let alike = track("Alike", artist: "B", genre: "Rock")
        let stranger = track("Stranger", artist: "C", genre: "Jazz")
        let queue = MediaLibrary.shared.createLocalTrackRadio(from: seed, among: [alike, seed, stranger],
                                                              limit: 10, maxPerArtist: 0)
        XCTAssertEqual(queue.map(\.title), ["Seed", "Alike"])
    }

    func testQueueAppliesThePerArtistCap() {
        let seed = track("Seed", artist: "A", genre: "Rock")
        let crowd = (1...5).map { track("Crowd \($0)", artist: "B", genre: "Rock") }
        let other = track("Other", artist: "C", genre: "Rock")
        let queue = MediaLibrary.shared.createLocalTrackRadio(from: seed, among: crowd + [other],
                                                              limit: 20, maxPerArtist: 2)
        XCTAssertEqual(queue.first?.title, "Seed")
        XCTAssertEqual(queue.filter { $0.artist == "B" }.count, 2)
        XCTAssertTrue(queue.contains { $0.title == "Other" })
    }

    func testQueueStopsAtTheLimit() {
        let seed = track("Seed", artist: "A", genre: "Rock")
        let others = (1...8).map { track("Other \($0)", artist: "Band \($0)", genre: "Rock") }
        let queue = MediaLibrary.shared.createLocalTrackRadio(from: seed, among: others,
                                                              limit: 4, maxPerArtist: 0)
        XCTAssertEqual(queue.count, 4)
        XCTAssertEqual(queue.first?.title, "Seed")
    }

    func testSeedWithNoMatchesYieldsJustTheSeed() {
        let seed = track("Seed", artist: "A", genre: "Rock")
        let queue = MediaLibrary.shared.createLocalTrackRadio(from: seed, among: [track("Else", artist: "B", genre: "Jazz")],
                                                              limit: 10, maxPerArtist: 0)
        XCTAssertEqual(queue.map(\.title), ["Seed"])
    }
}
