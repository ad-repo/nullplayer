import Foundation

/// Roles an artist can have relative to a track.
enum ArtistRole: String {
    case primary     = "primary"
    case featured    = "featured"
    case albumArtist = "album_artist"
}

/// Splits raw multi-artist strings into individual artist entries.
/// Pure function — no external dependencies.
enum ArtistSplitter {

    /// Split a raw artist tag string into individual (name, role) pairs.
    ///
    /// - Parameters:
    ///   - raw: The raw tag value (e.g. "Drake feat. Future" or "Foo; Bar").
    ///   - isAlbumArtist: If true, all results get `.albumArtist` role;
    ///     if false, the primary part gets `.primary` and feat. parts get `.featured`.
    static func split(_ raw: String, isAlbumArtist: Bool) -> [(name: String, role: ArtistRole)] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        // Step 1: Split on ; and / — unambiguous list separators.
        let segments = splitOnListSeparators(trimmed)

        // Step 2: Within each segment, detect feat./ft. and split further.
        var results: [(name: String, role: ArtistRole)] = []
        for segment in segments {
            let primaryRole: ArtistRole = isAlbumArtist ? .albumArtist : .primary
            let featuredRole: ArtistRole = isAlbumArtist ? .albumArtist : .featured

            if let (before, after) = splitOnFeat(segment) {
                if !before.isEmpty { results.append((name: before, role: primaryRole)) }
                if !after.isEmpty  { results.append((name: after,  role: featuredRole)) }
            } else {
                if !segment.isEmpty { results.append((name: segment, role: primaryRole)) }
            }
        }
        return results
    }

    // MARK: - Private helpers

    /// Split on `;` and `/`, trimming whitespace, discarding empty segments.
    private static func splitOnListSeparators(_ s: String) -> [String] {
        s.components(separatedBy: CharacterSet(charactersIn: ";/"))
         .map { $0.trimmingCharacters(in: .whitespaces) }
         .filter { !$0.isEmpty }
    }

    /// Detect `feat.`, `feat`, `ft.`, `ft` preceded by space or `(`.
    /// Returns (before, after) trimmed, or nil if no match.
    private static func splitOnFeat(_ s: String) -> (String, String)? {
        // Pattern: (space or open-paren) followed by feat./feat/ft./ft (case-insensitive)
        let pattern = #"(?i)(?<=[ (])(feat\.|feat|ft\.|ft)(?=[ ]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(s.startIndex..., in: s)
        guard let match = regex.firstMatch(in: s, range: nsRange),
              let matchRange = Range(match.range, in: s) else { return nil }

        // Walk back from the match start to include the preceding space or (
        var cutIndex = matchRange.lowerBound
        if cutIndex > s.startIndex {
            let prev = s.index(before: cutIndex)
            let prevChar = s[prev]
            if prevChar == " " || prevChar == "(" {
                cutIndex = prev
            }
        }

        let before = String(s[s.startIndex..<cutIndex]).trimmingCharacters(in: .whitespaces)
        var after  = String(s[matchRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        // Strip surrounding parens from the "after" segment
        if after.hasPrefix("(") && after.hasSuffix(")") {
            after = String(after.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        } else if after.hasSuffix(")") {
            after = String(after.dropLast()).trimmingCharacters(in: .whitespaces)
        }

        return (before, after)
    }
}
