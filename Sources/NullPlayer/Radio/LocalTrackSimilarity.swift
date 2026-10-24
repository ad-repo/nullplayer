import Foundation

/// Tag-based similarity between a seed track and the rest of the local library.
///
/// The local library has no server behind it to answer "what sounds like this?", so this scores
/// what the tags can tell us: shared artist, overlapping genres, nearby release years, close
/// tempo and key, and a shared grouping. Higher is more alike. Build one per seed and call
/// `ranked` (or `rank` on a single candidate); the seed's tags are normalized once, here, not
/// per candidate. `ranked` adds a little randomness when it sorts, so the same seed does not
/// always produce the same queue.
struct LocalTrackSimilarity {

    // MARK: - Weights

    static let artistWeight = 2.0
    static let genreWeight = 4.0
    static let yearWeight = 1.5
    static let bpmWeight = 1.5
    static let keyWeight = 0.75
    static let groupingWeight = 1.5

    /// A year gap at or beyond this many years earns no year credit.
    static let yearHorizon = 15.0
    /// Tempo gaps beyond this fraction of the seed's tempo earn no tempo credit.
    static let bpmTolerance = 0.15

    /// A track must be at least this similar to count as "like" the seed. One shared artist or
    /// one fully shared genre clears it; a year match alone, even an exact one, does not.
    static let minimumScore = 2.0

    /// Randomness added to each rank so near-ties reorder between runs. Matches more than this
    /// far apart keep their order.
    static let jitter = 0.75

    // MARK: - Seed

    private let seedID: UUID
    private let artists: Set<String>
    private let genres: Set<String>
    private let year: Int?
    private let bpm: Int?
    private let key: String?
    private let grouping: String?

    init(seed: LibraryTrack) {
        seedID = seed.id
        artists = Self.artistSet(seed)
        genres = Self.genreTokens(seed.genre)
        year = seed.year
        bpm = seed.bpm
        key = Self.normalizedKey(seed.musicalKey)
        grouping = Self.normalizedText(seed.grouping)
    }

    // MARK: - Rank

    /// The candidates alike enough to follow the seed, best first. The seed itself is left out.
    func ranked(_ candidates: [LibraryTrack]) -> [LibraryTrack] {
        candidates
            .filter { $0.id != seedID }
            .compactMap { candidate in
                rank(candidate).map { (track: candidate, rank: $0 + Double.random(in: 0..<Self.jitter)) }
            }
            .sorted { $0.rank > $1.rank }
            .map(\.track)
    }

    /// The candidate's sort score, or nil when its tags are not alike enough to belong in the
    /// seed's queue. Admission is judged on tag similarity alone: the listener's rating and play
    /// count reorder the matches but can never create one.
    func rank(_ candidate: LibraryTrack) -> Double? {
        let alike = similarity(candidate)
        guard alike >= Self.minimumScore else { return nil }
        return alike + Self.preference(for: candidate)
    }

    /// How alike the tags are, before the listener's taste is considered.
    func similarity(_ candidate: LibraryTrack) -> Double {
        var total = 0.0

        if !artists.isDisjoint(with: Self.artistSet(candidate)) {
            total += Self.artistWeight
        }

        total += Self.genreWeight * Self.overlap(genres, Self.genreTokens(candidate.genre))

        if let a = year, let b = candidate.year, a > 0, b > 0 {
            let gap = Double(abs(a - b))
            total += Self.yearWeight * max(0, 1 - gap / Self.yearHorizon)
        }

        total += Self.bpmWeight * Self.tempoCloseness(bpm, candidate.bpm)

        if let a = key, let b = Self.normalizedKey(candidate.musicalKey), a == b {
            total += Self.keyWeight
        }

        if let a = grouping, let b = Self.normalizedText(candidate.grouping), a == b {
            total += Self.groupingWeight
        }

        return total
    }

    // MARK: - Signals

    /// Jaccard overlap (0...1) of two genre tag strings. A tag such as "Rock; Blues" counts as
    /// the two genres Rock and Blues. Either side missing a genre scores 0.
    static func genreOverlap(_ a: String?, _ b: String?) -> Double {
        overlap(genreTokens(a), genreTokens(b))
    }

    /// 1 for the same tempo, falling to 0 at `bpmTolerance` apart. Half and double time count as
    /// the same tempo, since tag and detector disagreements about the beat are common.
    static func tempoCloseness(_ a: Int?, _ b: Int?) -> Double {
        guard let a, let b, a > 0, b > 0 else { return 0 }
        let seed = Double(a)
        let candidates = [Double(b), Double(b) * 2, Double(b) / 2]
        let bestGap = candidates.map { abs(seed - $0) / seed }.min() ?? 1
        return max(0, 1 - bestGap / bpmTolerance)
    }

    /// A small nudge toward tracks the listener rated well or plays often, and away from ones
    /// they rated low. Ratings use the library's 0-10 scale.
    static func preference(for track: LibraryTrack) -> Double {
        var nudge = 0.0
        if let rating = track.rating {
            if rating >= 8 { nudge += 0.5 }
            else if rating > 0 && rating <= 3 { nudge -= 1.5 }
        }
        nudge += 0.5 * Double(min(max(track.playCount, 0), 20)) / 20.0
        return nudge
    }

    // MARK: - Normalizing

    /// Every credited artist, split the way the library splits them ("feat." and list
    /// separators), lowercased.
    private static func artistSet(_ track: LibraryTrack) -> Set<String> {
        Set(track.artistNames.compactMap { normalizedText($0) })
    }

    private static func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }

    private static func genreTokens(_ genre: String?) -> Set<String> {
        guard let genre else { return [] }
        let separators = CharacterSet(charactersIn: ";/,\\|")
        return Set(
            genre.components(separatedBy: separators)
                .compactMap { normalizedText($0) }
        )
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedKey(_ key: String?) -> String? {
        normalizedText(key)?.replacingOccurrences(of: " ", with: "")
    }
}
