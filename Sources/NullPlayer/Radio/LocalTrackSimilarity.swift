import Foundation

/// Tag-based similarity between a seed track and the rest of the local library.
///
/// The local library has no server behind it to answer "what sounds like this?", so this scores
/// what the tags can tell us: shared artist, overlapping genres, nearby release years, close
/// tempo and key, and a shared grouping. Higher is more alike. The score is deterministic;
/// `MediaLibrary.createLocalTrackRadio(from:)` adds a little randomness when it ranks, so the
/// same seed does not always produce the same queue.
enum LocalTrackSimilarity {

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

    /// A track must score at least this to be considered "like" the seed. One shared artist or
    /// one fully shared genre clears it; a year match alone, even an exact one, does not.
    static let minimumScore = 2.0

    // MARK: - Score

    static func score(seed: LibraryTrack, candidate: LibraryTrack) -> Double {
        var total = 0.0

        if sharesArtist(seed, candidate) {
            total += artistWeight
        }

        total += genreWeight * genreOverlap(seed.genre, candidate.genre)

        if let a = seed.year, let b = candidate.year, a > 0, b > 0 {
            let gap = Double(abs(a - b))
            total += yearWeight * max(0, 1 - gap / yearHorizon)
        }

        total += bpmWeight * tempoCloseness(seed.bpm, candidate.bpm)

        if let a = normalizedKey(seed.musicalKey), let b = normalizedKey(candidate.musicalKey), a == b {
            total += keyWeight
        }

        if let a = normalizedText(seed.grouping), let b = normalizedText(candidate.grouping), a == b {
            total += groupingWeight
        }

        total += preference(for: candidate)
        return total
    }

    // MARK: - Signals

    /// Same artist or album artist, ignoring case and surrounding whitespace.
    static func sharesArtist(_ a: LibraryTrack, _ b: LibraryTrack) -> Bool {
        let aNames = Set([a.artist, a.albumArtist].compactMap { normalizedText($0) })
        let bNames = Set([b.artist, b.albumArtist].compactMap { normalizedText($0) })
        return !aNames.isDisjoint(with: bNames)
    }

    /// Jaccard overlap (0...1) of two genre tag strings. A tag such as "Rock; Blues" counts as
    /// the two genres Rock and Blues. Either side missing a genre scores 0.
    static func genreOverlap(_ a: String?, _ b: String?) -> Double {
        let aSet = genreTokens(a)
        let bSet = genreTokens(b)
        guard !aSet.isEmpty, !bSet.isEmpty else { return 0 }
        let shared = aSet.intersection(bSet).count
        let union = aSet.union(bSet).count
        return Double(shared) / Double(union)
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
