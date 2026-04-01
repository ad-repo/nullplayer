import Foundation
import SQLite

actor GenreDiscoveryService {
    static let shared = GenreDiscoveryService()

    private let musicBrainzClient = MusicBrainzTaggingClient()
    private let discogsClient = DiscogsTaggingClient()

    // MARK: - Public API

    /// Resolve genre from title/artist/album using three-tier lookup:
    /// 1. Local DB (existing play_events with known genre)
    /// 2. MusicBrainz recording search
    /// 3. Discogs release search
    func discoverGenre(title: String?, artist: String?, album: String?) async -> String? {
        let label = "\(artist ?? "?") – \(title ?? "?") [\(album ?? "?")]"
        let (resolvedTitle, resolvedArtist) = preprocessRadioMetadata(title: title, artist: artist)

        if resolvedArtist != artist {
            NSLog("GenreDiscovery: radio split '%@' → artist='%@' title='%@'",
                  title ?? "", resolvedArtist ?? "", resolvedTitle ?? "")
        }

        // Tier 1: local DB — check existing play_events for same artist+album
        if let genre = lookupGenreInHistory(artist: resolvedArtist, album: album) {
            NSLog("GenreDiscovery: [%@] tier 1 (local DB) → '%@'", label, genre)
            return genre
        }
        // Tier 1b: artist-only fallback (weaker signal, useful for radio with no album)
        if album == nil || album?.isEmpty == true,
           let genre = lookupGenreInHistory(artist: resolvedArtist, album: nil) {
            NSLog("GenreDiscovery: [%@] tier 1b (artist-only) → '%@'", label, genre)
            return genre
        }

        // Build query for external APIs
        guard let query = buildQuery(title: resolvedTitle, artist: resolvedArtist, album: album) else {
            NSLog("GenreDiscovery: [%@] no query terms, skipping", label)
            return nil
        }

        NSLog("GenreDiscovery: [%@] querying APIs with: '%@'", label, query)

        // Tier 2: MusicBrainz
        if let genre = await searchMusicBrainz(query: query) {
            NSLog("GenreDiscovery: [%@] tier 2 (MusicBrainz) → '%@'", label, genre)
            return genre
        }

        // Tier 3: Discogs
        if let genre = await searchDiscogs(query: query) {
            NSLog("GenreDiscovery: [%@] tier 3 (Discogs) → '%@'", label, genre)
            return genre
        }

        NSLog("GenreDiscovery: [%@] no genre found", label)
        return nil
    }

    /// Fire-and-forget: enrich a single play event by ID.
    func enrichPlayEvent(id: Int64, title: String?, artist: String?, album: String?) async {
        NSLog("GenreDiscovery: enriching event %lld (%@ – %@)", id, artist ?? "?", title ?? "?")
        guard let genre = await discoverGenre(title: title, artist: artist, album: album) else { return }
        NSLog("GenreDiscovery: updating event %lld → '%@'", id, genre)
        MediaLibraryStore.shared.updatePlayEventGenre(id: id, genre: genre)
    }

    /// Batch backfill all NULL/empty-genre events. Returns count resolved.
    func backfillNullGenres(progress: @MainActor @Sendable (Int, Int) -> Void) async -> Int {
        let events = MediaLibraryStore.shared.fetchPlayEventsWithNullGenre()
        let total = events.count
        NSLog("GenreDiscovery: backfill starting — %d events with no genre", total)
        guard total > 0 else { return 0 }

        // Cache by (lowercased artist, lowercased album) to deduplicate API calls.
        // Value is String? — nil means "already tried, not found".
        var genreCache: [String: String?] = [:]
        var resolved = 0

        for (idx, event) in events.enumerated() {
            if Task.isCancelled { break }

            let cacheKey = "\(event.artist?.lowercased() ?? "")||\(event.album?.lowercased() ?? "")"
            let genre: String?

            if let cached = genreCache[cacheKey] {
                genre = cached
            } else {
                genre = await discoverGenre(title: event.title, artist: event.artist, album: event.album)
                genreCache[cacheKey] = genre
            }

            if let g = genre {
                MediaLibraryStore.shared.updatePlayEventGenre(id: event.id, genre: g)
                resolved += 1
            }

            await progress(idx + 1, total)
        }
        NSLog("GenreDiscovery: backfill complete — resolved %d of %d events", resolved, total)
        return resolved
    }

    // MARK: - Radio Metadata Preprocessing

    /// Radio tracks often have "Song Name - Artist Name" in title with nil artist.
    private func preprocessRadioMetadata(title: String?, artist: String?) -> (title: String?, artist: String?) {
        guard let title, (artist == nil || artist?.isEmpty == true) else {
            return (title, artist)
        }
        for separator in [" - ", " – ", " — "] {
            let parts = title.components(separatedBy: separator)
            if parts.count == 2 {
                let t = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let a = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty && !a.isEmpty {
                    return (t, a)
                }
            }
        }
        return (title, artist)
    }

    // MARK: - Tier 1: Local DB Lookup

    private func lookupGenreInHistory(artist: String?, album: String?) -> String? {
        guard let artist, !artist.isEmpty,
              let db = MediaLibraryStore.shared.analyticsConnection else { return nil }

        do {
            let sql: String
            let params: [Binding?]
            if let album, !album.isEmpty {
                sql = """
                    SELECT event_genre FROM play_events
                    WHERE LOWER(event_artist) = LOWER(?)
                      AND LOWER(event_album) = LOWER(?)
                      AND event_genre IS NOT NULL AND event_genre != ''
                    LIMIT 1
                    """
                params = [artist as Binding, album as Binding]
            } else {
                sql = """
                    SELECT event_genre FROM play_events
                    WHERE LOWER(event_artist) = LOWER(?)
                      AND event_genre IS NOT NULL AND event_genre != ''
                    LIMIT 1
                    """
                params = [artist as Binding]
            }
            let stmt = try db.prepare(sql, params)
            return stmt.makeIterator().next()?[0] as? String
        } catch {
            return nil
        }
    }

    // MARK: - Query Building

    private func buildQuery(title: String?, artist: String?, album: String?) -> String? {
        var terms: [String] = []
        if let a = artist?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty { terms.append(a) }
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { terms.append(t) }
        if let al = album?.trimmingCharacters(in: .whitespacesAndNewlines), !al.isEmpty { terms.append(al) }
        return terms.isEmpty ? nil : terms.joined(separator: " ")
    }

    // MARK: - Tier 2: MusicBrainz

    private func searchMusicBrainz(query: String) async -> String? {
        do {
            let results = try await musicBrainzClient.searchRecordings(query: query, limit: 1)
            if let genre = results.first?.genre, !genre.isEmpty {
                return genre
            }
        } catch {
            NSLog("GenreDiscoveryService: MusicBrainz search failed: %@", error.localizedDescription)
        }
        return nil
    }

    // MARK: - Tier 3: Discogs

    private func searchDiscogs(query: String) async -> String? {
        do {
            let results = try await discogsClient.searchReleases(query: query, limit: 1)
            guard let firstResult = results.first else { return nil }
            guard let release = try await discogsClient.fetchRelease(id: firstResult.id) else { return nil }
            if let genre = release.primaryGenre, !genre.isEmpty {
                return genre
            }
        } catch {
            NSLog("GenreDiscoveryService: Discogs search failed: %@", error.localizedDescription)
        }
        return nil
    }
}
