import Foundation

/// Content identity for Plex music. One artist, album or track can exist as several records — a
/// copy per library section, or duplicate artist records in one section — each with its own
/// section-scoped `ratingKey`, so lists that combine records dedupe on normalized names instead.
public enum PlexIdentity {
    /// Trimmed, case- and diacritic-folded.
    public static func normalizedName(_ name: String?) -> String {
        (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    /// `albums` in order, keeping the first of each `identityKey`.
    public static func unique(_ albums: [PlexAlbum]) -> [PlexAlbum] {
        unique(albums, by: \.identityKey)
    }

    /// `tracks` in order, keeping the first of each `identityKey`.
    public static func unique(_ tracks: [PlexTrack]) -> [PlexTrack] {
        unique(tracks, by: \.identityKey)
    }

    private static func unique<T>(_ items: [T], by key: (T) -> String) -> [T] {
        var seen = Set<String>()
        return items.filter { seen.insert(key($0)).inserted }
    }
}

extension PlexAlbum {
    /// artist|title|year, so distinct editions that share a title stay separate.
    public var identityKey: String {
        "\(PlexIdentity.normalizedName(parentTitle))|\(PlexIdentity.normalizedName(title))|\(year.map { String($0) } ?? "")"
    }
}

extension PlexTrack {
    /// artist|album|title|disc|track.
    public var identityKey: String {
        "\(PlexIdentity.normalizedName(grandparentTitle))|\(PlexIdentity.normalizedName(parentTitle))|\(PlexIdentity.normalizedName(title))|\(parentIndex ?? 1)|\(index ?? 0)"
    }
}
