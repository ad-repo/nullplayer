import Foundation

extension LibraryTrack {
    /// Every artist this track is credited to. Uses the split `artists` rows ("feat." and list
    /// separators already handled); a row not yet backfilled falls back to its raw fields. A track
    /// with no artist tags has none, rather than the "Unknown Artist" placeholder the split rows
    /// carry, so two untagged tracks do not read as the same artist.
    var artistNames: [String] {
        guard !(artist ?? "").isEmpty || !(albumArtist ?? "").isEmpty else { return [] }
        let split = artists.map(\.name)
        return split.isEmpty ? [artist, albumArtist].compactMap { $0 } : split
    }
}
