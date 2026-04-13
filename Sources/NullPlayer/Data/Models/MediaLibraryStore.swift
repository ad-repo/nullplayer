import Foundation
import SQLite
import NullPlayerCore

struct PlayEventGenreStub: Sendable {
    let id: Int64
    let title: String?
    let artist: String?
    let album: String?
}

/// SQLite-backed storage for the local media library.
/// Replaces library.json with a proper relational database for scalable performance.
final class MediaLibraryStore {
    static let shared = MediaLibraryStore()
    static let playHistoryDidChangeNotification = Notification.Name("PlayHistoryDidChange")

    private var db: Connection?

    // MARK: - Table definitions

    private let tracksTable     = Table("library_tracks")
    private let moviesTable     = Table("library_movies")
    private let episodesTable   = Table("library_episodes")
    private let watchFoldersTable = Table("library_watch_folders")
    private let albumRatingsTable = Table("library_album_ratings")
    private let artistRatingsTable = Table("library_artist_ratings")

    // MARK: - Shared columns

    private let colID           = Expression<String>("id")
    private let colURL          = Expression<String>("url")
    private let colTitle        = Expression<String>("title")
    private let colDateAdded    = Expression<Double>("date_added")
    private let colDuration     = Expression<Double>("duration")
    private let colFileSize     = Expression<Int64>("file_size")
    private let colScanFileSize = Expression<Int64?>("scan_file_size")
    private let colScanModDate  = Expression<Double?>("scan_mod_date")
    private let colAddedAt      = Expression<Double>("added_at")
    private let colRating       = Expression<Int?>("rating")

    // MARK: - Track-specific columns

    private let colArtist       = Expression<String?>("artist")
    private let colAlbum        = Expression<String?>("album")
    private let colAlbumArtist  = Expression<String?>("album_artist")
    private let colGenre        = Expression<String?>("genre")
    private let colYear         = Expression<Int?>("year")
    private let colTrackNumber  = Expression<Int?>("track_number")
    private let colDiscNumber   = Expression<Int?>("disc_number")
    private let colBitrate      = Expression<Int?>("bitrate")
    private let colSampleRate   = Expression<Int?>("sample_rate")
    private let colChannels     = Expression<Int?>("channels")
    private let colLastPlayed   = Expression<Double?>("last_played")
    private let colPlayCount    = Expression<Int>("play_count")
    private let colComposer     = Expression<String?>("composer")
    private let colComment      = Expression<String?>("comment")
    private let colGrouping     = Expression<String?>("grouping")
    private let colBPM          = Expression<Int?>("bpm")
    private let colMusicalKey   = Expression<String?>("musical_key")
    private let colISRC         = Expression<String?>("isrc")
    private let colCopyright    = Expression<String?>("copyright")
    private let colMBRecordingID = Expression<String?>("musicbrainz_recording_id")
    private let colMBReleaseID   = Expression<String?>("musicbrainz_release_id")
    private let colDiscogsReleaseID = Expression<Int?>("discogs_release_id")
    private let colDiscogsMasterID  = Expression<Int?>("discogs_master_id")
    private let colDiscogsLabel     = Expression<String?>("discogs_label")
    private let colDiscogsCatalogNumber = Expression<String?>("discogs_catalog_number")
    private let colArtworkURL       = Expression<String?>("artwork_url")

    // MARK: - Episode-specific columns

    private let colShowTitle      = Expression<String>("show_title")
    private let colSeasonNumber   = Expression<Int>("season_number")
    private let colEpisodeNumber  = Expression<Int?>("episode_number")

    // MARK: - Rating table columns

    private let colAlbumID  = Expression<String>("album_id")
    private let colArtistID = Expression<String>("artist_id")
    private let colRatingVal = Expression<Int>("rating")

    // MARK: - Init

    private init() {}

    #if DEBUG
    static func makeForTesting() -> MediaLibraryStore { MediaLibraryStore() }
    var testDB: Connection? { db }
    #endif

    // MARK: - Lifecycle

    func open() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            NSLog("MediaLibraryStore: Cannot locate Application Support directory")
            return
        }
        let dir = appSupport.appendingPathComponent("NullPlayer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let dbPath = dir.appendingPathComponent("library.db").path

        do {
            let connection = try Connection(dbPath)
            db = connection
            try setupSchema(connection)
            NSLog("MediaLibraryStore: Database ready at %@", dbPath)

            // Migrate from JSON if needed
            let jsonURL = dir.appendingPathComponent("library.json")
            migrateFromJSONIfNeeded(jsonURL: jsonURL)
        } catch {
            NSLog("MediaLibraryStore: Failed to open database: %@", error.localizedDescription)
        }
    }

    /// Opens the database at a custom path (for testing). Skips JSON migration.
    func open(at url: URL) {
        do {
            let connection = try Connection(url.path)
            try setupSchema(connection)
            db = connection
        } catch {
            NSLog("MediaLibraryStore: Failed to open at %@: %@", url.path, error.localizedDescription)
        }
    }

    func close() {
        db = nil
    }

    /// Checkpoint the WAL file into the main database file, ensuring a file copy captures all committed data.
    func checkpoint() {
        guard let db = db else { return }
        do {
            try db.run("PRAGMA wal_checkpoint(FULL)")
        } catch {
            NSLog("MediaLibraryStore: WAL checkpoint failed: %@", error.localizedDescription)
        }
    }

    // MARK: - Schema

    private func setupSchema(_ connection: Connection) throws {
        // WAL mode: allows readers and writers to proceed concurrently. Without WAL, the main
        // thread's SELECT queries (artistCount, artistNames, etc.) block on background INSERT
        // transactions during import, causing visible UI freezes.
        try connection.run("PRAGMA journal_mode=WAL")
        // NORMAL sync is safe with WAL and dramatically reduces fsync overhead during bulk import.
        try connection.run("PRAGMA synchronous=NORMAL")
        // 5-second busy timeout so background/main thread contention doesn't hard-fail.
        connection.busyTimeout = 5
        // Enable FK enforcement so ON DELETE CASCADE fires on track_artists.
        // Must be set on every connection open — SQLite resets it per connection.
        try connection.run("PRAGMA foreign_keys = ON")

        var currentVersion = try connection.scalar("PRAGMA user_version") as? Int64 ?? 0
        if currentVersion == 0 {
            try createTablesIfNeeded(connection)
            try migrateToV5(connection)
            try connection.run("PRAGMA user_version = 5")
            currentVersion = 5
        }
        if currentVersion == 1 {
            // Add expression index so artistNames GROUP BY and albumsForArtist WHERE queries
            // use an index instead of full table scans. Without this, buildLocalArtistItems()
            // runs 200+ unindexed full-table scans on the main thread, causing minutes-long
            // UI freezes on large libraries (60k+ tracks).
            try connection.run("CREATE INDEX IF NOT EXISTS idx_tracks_artist_expr ON library_tracks (coalesce(album_artist, artist, 'Unknown Artist'))")
            try connection.run("PRAGMA user_version = 2")
            currentVersion = 2
        }
        if currentVersion == 2 {
            try connection.run("""
                CREATE TABLE IF NOT EXISTS track_artists (
                    track_url   TEXT NOT NULL REFERENCES library_tracks(url) ON DELETE CASCADE,
                    artist_name TEXT NOT NULL,
                    role        TEXT NOT NULL CHECK(role IN ('primary', 'featured', 'album_artist')),
                    PRIMARY KEY (track_url, artist_name, role)
                )
                """)
            try connection.run("CREATE INDEX IF NOT EXISTS idx_track_artists_name ON track_artists(artist_name)")
            try connection.run("CREATE INDEX IF NOT EXISTS idx_track_artists_url ON track_artists(track_url)")
            try connection.run("PRAGMA user_version = 3")
            UserDefaults.standard.set(false, forKey: "trackArtistsBackfillComplete")
            currentVersion = 3
        }
        if currentVersion == 3 {
            try migrateTrackMetadataSchemaToV4(connection)
            try connection.run("PRAGMA user_version = 4")
            currentVersion = 4
        }
        if currentVersion == 4 {
            try migrateToV5(connection)
            try connection.run("PRAGMA user_version = 5")
        }
    }

    private func migrateTrackMetadataSchemaToV4(_ connection: Connection) throws {
        try addTrackColumnIfMissing(connection, name: "composer", sqlType: "TEXT")
        try addTrackColumnIfMissing(connection, name: "comment", sqlType: "TEXT")
        try addTrackColumnIfMissing(connection, name: "grouping", sqlType: "TEXT")
        try addTrackColumnIfMissing(connection, name: "bpm", sqlType: "INTEGER")
        try addTrackColumnIfMissing(connection, name: "musical_key", sqlType: "TEXT")
        try addTrackColumnIfMissing(connection, name: "isrc", sqlType: "TEXT")
        try addTrackColumnIfMissing(connection, name: "copyright", sqlType: "TEXT")
        try addTrackColumnIfMissing(connection, name: "musicbrainz_recording_id", sqlType: "TEXT")
        try addTrackColumnIfMissing(connection, name: "musicbrainz_release_id", sqlType: "TEXT")
        try addTrackColumnIfMissing(connection, name: "discogs_release_id", sqlType: "INTEGER")
        try addTrackColumnIfMissing(connection, name: "discogs_master_id", sqlType: "INTEGER")
        try addTrackColumnIfMissing(connection, name: "discogs_label", sqlType: "TEXT")
        try addTrackColumnIfMissing(connection, name: "discogs_catalog_number", sqlType: "TEXT")
        try addTrackColumnIfMissing(connection, name: "artwork_url", sqlType: "TEXT")
    }

    private func migrateToV5(_ connection: Connection) throws {
        try connection.execute("""
            CREATE TABLE IF NOT EXISTS play_events (
                id                INTEGER PRIMARY KEY AUTOINCREMENT,
                track_id          TEXT,
                track_url         TEXT,
                event_title       TEXT,
                event_artist      TEXT,
                event_album       TEXT,
                event_genre       TEXT,
                played_at         REAL NOT NULL,
                duration_listened REAL NOT NULL DEFAULT 0,
                source            TEXT NOT NULL CHECK(source IN
                                  ('local','plex','subsonic','jellyfin','emby','radio')),
                skipped           INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_play_events_played_at ON play_events(played_at);
            CREATE INDEX IF NOT EXISTS idx_play_events_track_id  ON play_events(track_id);
            CREATE INDEX IF NOT EXISTS idx_play_events_source_time ON play_events(source, played_at);
            """)
    }

    private func addTrackColumnIfMissing(_ connection: Connection, name: String, sqlType: String) throws {
        let pragmaSQL = "PRAGMA table_info(library_tracks)"
        for row in try connection.prepare(pragmaSQL) {
            if let existingName = row[1] as? String, existingName == name {
                return
            }
        }
        try connection.run("ALTER TABLE library_tracks ADD COLUMN \(name) \(sqlType)")
    }

    private func createTablesIfNeeded(_ connection: Connection) throws {
        // library_tracks
        try connection.run(tracksTable.create(ifNotExists: true) { t in
            t.column(colID, primaryKey: true)
            t.column(colURL, unique: true)
            t.column(colTitle)
            t.column(colArtist)
            t.column(colAlbum)
            t.column(colAlbumArtist)
            t.column(colGenre)
            t.column(colYear)
            t.column(colTrackNumber)
            t.column(colDiscNumber)
            t.column(colDuration)
            t.column(colBitrate)
            t.column(colSampleRate)
            t.column(colChannels)
            t.column(colFileSize)
            t.column(colDateAdded)
            t.column(colLastPlayed)
            t.column(colPlayCount)
            t.column(colRating)
            t.column(colScanFileSize)
            t.column(colScanModDate)
            t.column(colComposer)
            t.column(colComment)
            t.column(colGrouping)
            t.column(colBPM)
            t.column(colMusicalKey)
            t.column(colISRC)
            t.column(colCopyright)
            t.column(colMBRecordingID)
            t.column(colMBReleaseID)
            t.column(colDiscogsReleaseID)
            t.column(colDiscogsMasterID)
            t.column(colDiscogsLabel)
            t.column(colDiscogsCatalogNumber)
            t.column(colArtworkURL)
        })
        try connection.run("CREATE INDEX IF NOT EXISTS idx_tracks_artist ON library_tracks (album_artist, artist)")
        // Expression index covering artistNames GROUP BY and albumsForArtist/albumsForArtistsBatch WHERE clauses.
        // Without this, queries using coalesce(album_artist, artist, 'Unknown Artist') do full table scans.
        try connection.run("CREATE INDEX IF NOT EXISTS idx_tracks_artist_expr ON library_tracks (coalesce(album_artist, artist, 'Unknown Artist'))")
        try connection.run("CREATE INDEX IF NOT EXISTS idx_tracks_album ON library_tracks (album)")
        try connection.run("CREATE INDEX IF NOT EXISTS idx_tracks_genre ON library_tracks (genre)")
        try connection.run("CREATE INDEX IF NOT EXISTS idx_tracks_year ON library_tracks (year)")

        // library_movies
        try connection.run(moviesTable.create(ifNotExists: true) { t in
            t.column(colID, primaryKey: true)
            t.column(colURL, unique: true)
            t.column(colTitle)
            t.column(colYear)
            t.column(colDuration)
            t.column(colFileSize)
            t.column(colDateAdded)
            t.column(colScanFileSize)
            t.column(colScanModDate)
        })

        // library_episodes
        try connection.run(episodesTable.create(ifNotExists: true) { t in
            t.column(colID, primaryKey: true)
            t.column(colURL, unique: true)
            t.column(colTitle)
            t.column(colShowTitle)
            t.column(colSeasonNumber)
            t.column(colEpisodeNumber)
            t.column(colDuration)
            t.column(colFileSize)
            t.column(colDateAdded)
            t.column(colScanFileSize)
            t.column(colScanModDate)
        })
        try connection.run("CREATE INDEX IF NOT EXISTS idx_episodes_show ON library_episodes (show_title, season_number)")

        // library_watch_folders
        try connection.run(watchFoldersTable.create(ifNotExists: true) { t in
            t.column(colURL, primaryKey: true)
            t.column(colAddedAt)
        })

        // library_album_ratings
        try connection.run(albumRatingsTable.create(ifNotExists: true) { t in
            t.column(colAlbumID, primaryKey: true)
            t.column(colRatingVal)
        })

        // library_artist_ratings
        try connection.run(artistRatingsTable.create(ifNotExists: true) { t in
            t.column(colArtistID, primaryKey: true)
            t.column(colRatingVal)
        })

        // track_artists: join table linking tracks to individual artist names.
        // FK references url (UNIQUE) not id (PK) — url is the natural key in all queries.
        try connection.run("""
            CREATE TABLE IF NOT EXISTS track_artists (
                track_url   TEXT NOT NULL REFERENCES library_tracks(url) ON DELETE CASCADE,
                artist_name TEXT NOT NULL,
                role        TEXT NOT NULL CHECK(role IN ('primary', 'featured', 'album_artist')),
                PRIMARY KEY (track_url, artist_name, role)
            )
            """)
        try connection.run("CREATE INDEX IF NOT EXISTS idx_track_artists_name ON track_artists(artist_name)")
        try connection.run("CREATE INDEX IF NOT EXISTS idx_track_artists_url ON track_artists(track_url)")
    }

    // MARK: - JSON Migration

    private struct LibraryData: Codable {
        let tracks: [LibraryTrack]
        let watchFolders: [URL]
        let movies: [LocalVideo]
        let episodes: [LocalEpisode]
        let albumRatings: [String: Int]
        let artistRatings: [String: Int]
        let scanSignaturesByPath: [String: FileScanSignature]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tracks = try container.decode([LibraryTrack].self, forKey: .tracks)
            watchFolders = try container.decode([URL].self, forKey: .watchFolders)
            movies = try container.decodeIfPresent([LocalVideo].self, forKey: .movies) ?? []
            episodes = try container.decodeIfPresent([LocalEpisode].self, forKey: .episodes) ?? []
            albumRatings = try container.decodeIfPresent([String: Int].self, forKey: .albumRatings) ?? [:]
            artistRatings = try container.decodeIfPresent([String: Int].self, forKey: .artistRatings) ?? [:]
            scanSignaturesByPath = try container.decodeIfPresent([String: FileScanSignature].self, forKey: .scanSignaturesByPath) ?? [:]
        }
    }

    private func migrateFromJSONIfNeeded(jsonURL: URL) {
        guard trackCount() == 0,
              FileManager.default.fileExists(atPath: jsonURL.path) else { return }

        NSLog("MediaLibraryStore: Migrating library.json -> library.db")
        do {
            let data = try Data(contentsOf: jsonURL)
            let decoder = JSONDecoder()
            let libraryData = try decoder.decode(LibraryData.self, from: data)

            guard let connection = db else { return }
            try connection.transaction {
                for track in libraryData.tracks {
                    let sig = libraryData.scanSignaturesByPath[track.url.path]
                    try self.upsertTrackInternal(track, sig: sig, connection: connection)
                }
                for movie in libraryData.movies {
                    let sig = libraryData.scanSignaturesByPath[movie.url.path]
                    try self.upsertMovieInternal(movie, sig: sig, connection: connection)
                }
                for episode in libraryData.episodes {
                    let sig = libraryData.scanSignaturesByPath[episode.url.path]
                    try self.upsertEpisodeInternal(episode, sig: sig, connection: connection)
                }
                for folder in libraryData.watchFolders {
                    try connection.run(self.watchFoldersTable.insert(
                        or: .ignore,
                        self.colURL <- folder.absoluteString,
                        self.colAddedAt <- Date().timeIntervalSince1970
                    ))
                }
                for (albumId, rating) in libraryData.albumRatings {
                    try connection.run(self.albumRatingsTable.insert(
                        or: .replace,
                        self.colAlbumID <- albumId,
                        self.colRatingVal <- rating
                    ))
                }
                for (artistId, rating) in libraryData.artistRatings {
                    try connection.run(self.artistRatingsTable.insert(
                        or: .replace,
                        self.colArtistID <- artistId,
                        self.colRatingVal <- rating
                    ))
                }
            }

            // Rename migrated JSON file
            let migratedURL = jsonURL.deletingPathExtension().appendingPathExtension("json.migrated")
            try? FileManager.default.moveItem(at: jsonURL, to: migratedURL)
            NSLog("MediaLibraryStore: Migration complete. Tracks: %d, Movies: %d, Episodes: %d",
                  libraryData.tracks.count, libraryData.movies.count, libraryData.episodes.count)
        } catch {
            NSLog("MediaLibraryStore: Migration failed: %@", error.localizedDescription)
        }
    }

    // MARK: - Bulk Read (startup)

    func allTracks() -> [LibraryTrack] {
        guard let db = db else { return [] }
        do {
            var result: [LibraryTrack] = []
            for row in try db.prepare(tracksTable) {
                if let track = trackFromRow(row) {
                    result.append(track)
                }
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: allTracks failed: %@", error.localizedDescription)
            return []
        }
    }

    func allMovies() -> [LocalVideo] {
        guard let db = db else { return [] }
        do {
            var result: [LocalVideo] = []
            for row in try db.prepare(moviesTable) {
                if let movie = movieFromRow(row) {
                    result.append(movie)
                }
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: allMovies failed: %@", error.localizedDescription)
            return []
        }
    }

    func allEpisodes() -> [LocalEpisode] {
        guard let db = db else { return [] }
        do {
            var result: [LocalEpisode] = []
            for row in try db.prepare(episodesTable) {
                if let ep = episodeFromRow(row) {
                    result.append(ep)
                }
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: allEpisodes failed: %@", error.localizedDescription)
            return []
        }
    }

    func allWatchFolders() -> [URL] {
        guard let db = db else { return [] }
        do {
            var result: [URL] = []
            for row in try db.prepare(watchFoldersTable) {
                let urlString = row[colURL]
                if let url = Self.urlFromStoredString(urlString) {
                    result.append(url)
                }
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: allWatchFolders failed: %@", error.localizedDescription)
            return []
        }
    }

    func albumRatings() -> [String: Int] {
        guard let db = db else { return [:] }
        do {
            var result: [String: Int] = [:]
            for row in try db.prepare(albumRatingsTable) {
                result[row[colAlbumID]] = row[colRatingVal]
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: albumRatings failed: %@", error.localizedDescription)
            return [:]
        }
    }

    func artistRatings() -> [String: Int] {
        guard let db = db else { return [:] }
        do {
            var result: [String: Int] = [:]
            for row in try db.prepare(artistRatingsTable) {
                result[row[colArtistID]] = row[colRatingVal]
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: artistRatings failed: %@", error.localizedDescription)
            return [:]
        }
    }

    func allSignatures() -> [String: FileScanSignature] {
        guard let db = db else { return [:] }
        do {
            var result: [String: FileScanSignature] = [:]

            for row in try db.prepare(tracksTable.select(colURL, colScanFileSize, colScanModDate)) {
                let urlString = row[colURL]
                if let url = Self.urlFromStoredString(urlString) {
                    let sig = FileScanSignature(
                        fileSize: row[colScanFileSize] ?? 0,
                        contentModificationDate: row[colScanModDate].map { Date(timeIntervalSince1970: $0) }
                    )
                    result[url.path] = sig
                }
            }
            for row in try db.prepare(moviesTable.select(colURL, colScanFileSize, colScanModDate)) {
                let urlString = row[colURL]
                if let url = Self.urlFromStoredString(urlString) {
                    let sig = FileScanSignature(
                        fileSize: row[colScanFileSize] ?? 0,
                        contentModificationDate: row[colScanModDate].map { Date(timeIntervalSince1970: $0) }
                    )
                    result[url.path] = sig
                }
            }
            for row in try db.prepare(episodesTable.select(colURL, colScanFileSize, colScanModDate)) {
                let urlString = row[colURL]
                if let url = Self.urlFromStoredString(urlString) {
                    let sig = FileScanSignature(
                        fileSize: row[colScanFileSize] ?? 0,
                        contentModificationDate: row[colScanModDate].map { Date(timeIntervalSince1970: $0) }
                    )
                    result[url.path] = sig
                }
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: allSignatures failed: %@", error.localizedDescription)
            return [:]
        }
    }

    // MARK: - Alphabet Index Queries

    /// Returns a map of sort-letter → first DB offset for that letter, across all artists.
    func artistLetterOffsets(sort: ModernBrowserSortOption) -> [String: Int] {
        guard let db = db else { return [:] }
        // IMPORTANT: query structure must be identical to artistNames (without LIMIT/OFFSET)
        // so offsets align exactly with artistNames page row positions.
        let sql: String
        switch sort {
        case .nameAsc:
            sql = """
                SELECT DISTINCT ta.artist_name
                FROM track_artists ta
                WHERE ta.role = 'album_artist'
                ORDER BY ta.artist_name ASC
                """
        case .nameDesc:
            sql = """
                SELECT DISTINCT ta.artist_name
                FROM track_artists ta
                WHERE ta.role = 'album_artist'
                ORDER BY ta.artist_name DESC
                """
        case .dateAddedDesc:
            sql = """
                SELECT ta.artist_name
                FROM track_artists ta
                JOIN library_tracks t ON t.url = ta.track_url
                WHERE ta.role = 'album_artist'
                GROUP BY ta.artist_name
                ORDER BY max(t.date_added) DESC, ta.artist_name ASC
                """
        case .dateAddedAsc:
            sql = """
                SELECT ta.artist_name
                FROM track_artists ta
                JOIN library_tracks t ON t.url = ta.track_url
                WHERE ta.role = 'album_artist'
                GROUP BY ta.artist_name
                ORDER BY min(t.date_added) ASC, ta.artist_name ASC
                """
        case .yearDesc:
            sql = """
                SELECT ta.artist_name
                FROM track_artists ta
                JOIN library_tracks t ON t.url = ta.track_url
                WHERE ta.role = 'album_artist'
                GROUP BY ta.artist_name
                ORDER BY max(t.year) DESC NULLS LAST, ta.artist_name ASC
                """
        case .yearAsc:
            sql = """
                SELECT ta.artist_name
                FROM track_artists ta
                JOIN library_tracks t ON t.url = ta.track_url
                WHERE ta.role = 'album_artist'
                GROUP BY ta.artist_name
                ORDER BY min(t.year) ASC NULLS LAST, ta.artist_name ASC
                """
        }
        do {
            var result: [String: Int] = [:]
            var offset = 0
            for row in try db.prepare(sql) {
                if let name = row[0] as? String {
                    let letter = Self.sortLetterForString(name)
                    if result[letter] == nil { result[letter] = offset }
                    offset += 1
                }
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: artistLetterOffsets failed: %@", error.localizedDescription)
            return [:]
        }
    }

    /// Returns a map of sort-letter → first DB offset for that letter, across all albums.
    func albumLetterOffsets(sort: ModernBrowserSortOption) -> [String: Int] {
        guard let db = db else { return [:] }
        let orderClause: String
        switch sort {
        case .nameAsc:
            orderClause = "ORDER BY coalesce(album, 'Unknown Album') ASC"
        case .nameDesc:
            orderClause = "ORDER BY coalesce(album, 'Unknown Album') DESC"
        case .dateAddedDesc:
            orderClause = "ORDER BY min(date_added) DESC"
        case .dateAddedAsc:
            orderClause = "ORDER BY min(date_added) ASC"
        case .yearDesc:
            orderClause = "ORDER BY min(year) DESC NULLS LAST"
        case .yearAsc:
            orderClause = "ORDER BY min(year) ASC NULLS LAST"
        }
        let sql = """
            SELECT
                coalesce(album, 'Unknown Album') as album_name,
                album_artist
            FROM library_tracks
            GROUP BY coalesce(album_artist, '') || '|' || coalesce(album, 'Unknown Album')
            \(orderClause)
            """
        do {
            var result: [String: Int] = [:]
            var offset = 0
            for row in try db.prepare(sql) {
                if let albumName = row[0] as? String {
                    let artistName = row[1] as? String
                    let displayName: String
                    if let artist = artistName, !artist.isEmpty {
                        displayName = "\(artist) - \(albumName)"
                    } else {
                        displayName = albumName
                    }
                    let letter = Self.sortLetterForString(displayName)
                    if result[letter] == nil { result[letter] = offset }
                    offset += 1
                }
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: albumLetterOffsets failed: %@", error.localizedDescription)
            return [:]
        }
    }

    private static func sortLetterForString(_ title: String) -> String {
        let sortTitle = LibraryTextSorter.normalized(title, ignoreLeadingArticles: true).uppercased()
        guard let firstChar = sortTitle.first else { return "#" }
        return firstChar.isLetter ? String(firstChar) : "#"
    }

    // MARK: - Paginated Queries (display layer)

    func artistCount() -> Int {
        guard let db = db else { return 0 }
        do {
            let count = try db.scalar(
                "SELECT COUNT(DISTINCT artist_name) FROM track_artists WHERE role = 'album_artist'"
            ) as? Int64 ?? 0
            return Int(count)
        } catch {
            NSLog("MediaLibraryStore: artistCount failed: %@", error.localizedDescription)
            return 0
        }
    }

    func artistNames(limit: Int, offset: Int, sort: ModernBrowserSortOption) -> [String] {
        guard let db = db else { return [] }
        let sql: String
        switch sort {
        case .nameAsc:
            sql = """
                SELECT DISTINCT ta.artist_name
                FROM track_artists ta
                WHERE ta.role = 'album_artist'
                ORDER BY ta.artist_name ASC
                LIMIT \(limit) OFFSET \(offset)
                """
        case .nameDesc:
            sql = """
                SELECT DISTINCT ta.artist_name
                FROM track_artists ta
                WHERE ta.role = 'album_artist'
                ORDER BY ta.artist_name DESC
                LIMIT \(limit) OFFSET \(offset)
                """
        case .dateAddedDesc:
            sql = """
                SELECT ta.artist_name
                FROM track_artists ta
                JOIN library_tracks t ON t.url = ta.track_url
                WHERE ta.role = 'album_artist'
                GROUP BY ta.artist_name
                ORDER BY max(t.date_added) DESC, ta.artist_name ASC
                LIMIT \(limit) OFFSET \(offset)
                """
        case .dateAddedAsc:
            sql = """
                SELECT ta.artist_name
                FROM track_artists ta
                JOIN library_tracks t ON t.url = ta.track_url
                WHERE ta.role = 'album_artist'
                GROUP BY ta.artist_name
                ORDER BY min(t.date_added) ASC, ta.artist_name ASC
                LIMIT \(limit) OFFSET \(offset)
                """
        case .yearDesc:
            sql = """
                SELECT ta.artist_name
                FROM track_artists ta
                JOIN library_tracks t ON t.url = ta.track_url
                WHERE ta.role = 'album_artist'
                GROUP BY ta.artist_name
                ORDER BY max(t.year) DESC NULLS LAST, ta.artist_name ASC
                LIMIT \(limit) OFFSET \(offset)
                """
        case .yearAsc:
            sql = """
                SELECT ta.artist_name
                FROM track_artists ta
                JOIN library_tracks t ON t.url = ta.track_url
                WHERE ta.role = 'album_artist'
                GROUP BY ta.artist_name
                ORDER BY min(t.year) ASC NULLS LAST, ta.artist_name ASC
                LIMIT \(limit) OFFSET \(offset)
                """
        }
        do {
            var result: [String] = []
            for row in try db.prepare(sql) {
                if let name = row[0] as? String { result.append(name) }
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: artistNames failed: %@", error.localizedDescription)
            return []
        }
    }

    func albumCount() -> Int {
        guard let db = db else { return 0 }
        do {
            let count = try db.scalar(
                "SELECT COUNT(DISTINCT coalesce(album_artist, '') || '|' || coalesce(album, 'Unknown Album')) FROM library_tracks"
            ) as? Int64 ?? 0
            return Int(count)
        } catch {
            NSLog("MediaLibraryStore: albumCount failed: %@", error.localizedDescription)
            return 0
        }
    }

    func albumSummaries(limit: Int, offset: Int, sort: ModernBrowserSortOption) -> [AlbumSummary] {
        guard let db = db else { return [] }
        let orderClause: String
        switch sort {
        case .nameAsc:
            orderClause = "ORDER BY coalesce(album, 'Unknown Album') ASC"
        case .nameDesc:
            orderClause = "ORDER BY coalesce(album, 'Unknown Album') DESC"
        case .dateAddedDesc:
            orderClause = "ORDER BY min(date_added) DESC"
        case .dateAddedAsc:
            orderClause = "ORDER BY min(date_added) ASC"
        case .yearDesc:
            orderClause = "ORDER BY min(year) DESC NULLS LAST"
        case .yearAsc:
            orderClause = "ORDER BY min(year) ASC NULLS LAST"
        }

        let sql = """
            SELECT
                coalesce(album_artist, '') || '|' || coalesce(album, 'Unknown Album') as album_id,
                coalesce(album, 'Unknown Album') as album_name,
                album_artist,
                min(year) as yr,
                count(*) as cnt
            FROM library_tracks
            GROUP BY album_id
            \(orderClause)
            LIMIT \(limit) OFFSET \(offset)
            """
        do {
            var result: [AlbumSummary] = []
            for row in try db.prepare(sql) {
                guard let albumId = row[0] as? String,
                      let albumName = row[1] as? String else { continue }
                let artistName = row[2] as? String
                let year = (row[3] as? Int64).map(Int.init)
                let count = (row[4] as? Int64).map(Int.init) ?? 0
                result.append(AlbumSummary(id: albumId, name: albumName, artist: artistName, year: year, trackCount: count))
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: albumSummaries failed: %@", error.localizedDescription)
            return []
        }
    }

    func albumsForArtist(_ artistName: String) -> [AlbumSummary] {
        guard let db = db else { return [] }
        let sql = """
            SELECT
                coalesce(t.album_artist, '') || '|' || coalesce(t.album, 'Unknown Album') as album_id,
                coalesce(t.album, 'Unknown Album') as album_name,
                t.album_artist,
                min(t.year) as yr,
                count(*) as cnt
            FROM library_tracks t
            JOIN track_artists ta ON ta.track_url = t.url
            WHERE ta.artist_name = ? AND ta.role = 'album_artist'
            GROUP BY album_id
            ORDER BY min(t.year) ASC NULLS LAST, coalesce(t.album, 'Unknown Album') ASC
            """
        do {
            var result: [AlbumSummary] = []
            for row in try db.prepare(sql, artistName) {
                guard let albumId = row[0] as? String,
                      let albumName = row[1] as? String else { continue }
                let artistNameVal = row[2] as? String
                let year = (row[3] as? Int64).map(Int.init)
                let count = (row[4] as? Int64).map(Int.init) ?? 0
                result.append(AlbumSummary(id: albumId, name: albumName, artist: artistNameVal, year: year, trackCount: count))
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: albumsForArtist failed: %@", error.localizedDescription)
            return []
        }
    }

    /// Fetch album summaries for a page of artists in a single query.
    /// Returns a dict keyed by artist_name (the split name, same as artistNames() returns).
    func albumsForArtistsBatch(_ names: [String]) -> [String: [AlbumSummary]] {
        guard let db = db, !names.isEmpty else { return [:] }
        let placeholders = names.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            SELECT
                ta.artist_name as artist_key,
                coalesce(t.album_artist, '') || '|' || coalesce(t.album, 'Unknown Album') as album_id,
                coalesce(t.album, 'Unknown Album') as album_name,
                t.album_artist,
                min(t.year) as yr,
                count(*) as cnt
            FROM library_tracks t
            JOIN track_artists ta ON ta.track_url = t.url
            WHERE ta.artist_name IN (\(placeholders)) AND ta.role = 'album_artist'
            GROUP BY ta.artist_name, album_id
            ORDER BY ta.artist_name, min(t.year) ASC NULLS LAST, coalesce(t.album, 'Unknown Album') ASC
            """
        do {
            var result: [String: [AlbumSummary]] = [:]
            let bindings = names.map { $0 as Binding? }
            for row in try db.prepare(sql, bindings) {
                guard let artistKey = row[0] as? String,
                      let albumId = row[1] as? String,
                      let albumName = row[2] as? String else { continue }
                let artistNameVal = row[3] as? String
                let year = (row[4] as? Int64).map(Int.init)
                let count = (row[5] as? Int64).map(Int.init) ?? 0
                result[artistKey, default: []].append(
                    AlbumSummary(id: albumId, name: albumName, artist: artistNameVal, year: year, trackCount: count)
                )
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: albumsForArtistsBatch failed: %@", error.localizedDescription)
            return [:]
        }
    }

    /// Fetch all track_artists rows for the given track URLs.
    /// Returns a dict keyed by track URL absolute string.
    func artistsForURLs(_ urls: [String]) -> [String: [(name: String, role: ArtistRole)]] {
        guard let db = db, !urls.isEmpty else { return [:] }
        var result: [String: [(name: String, role: ArtistRole)]] = [:]
        // Chunk into 500 to avoid SQLite IN clause limits
        let chunkSize = 500
        for chunkStart in stride(from: 0, to: urls.count, by: chunkSize) {
            let chunk = Array(urls[chunkStart..<min(chunkStart + chunkSize, urls.count)])
            let placeholders = chunk.map { _ in "?" }.joined(separator: ", ")
            let sql = "SELECT track_url, artist_name, role FROM track_artists WHERE track_url IN (\(placeholders))"
            let bindings = chunk.map { $0 as Binding? }
            do {
                for row in try db.prepare(sql, bindings) {
                    guard let trackUrl = row[0] as? String,
                          let artistName = row[1] as? String,
                          let roleStr = row[2] as? String,
                          let role = ArtistRole(rawValue: roleStr) else { continue }
                    result[trackUrl, default: []].append((name: artistName, role: role))
                }
            } catch {
                NSLog("MediaLibraryStore: artistsForURLs failed: %@", error.localizedDescription)
            }
        }
        return result
    }

    func tracksForAlbum(_ albumId: String) -> [LibraryTrack] {
        guard let db = db else { return [] }
        // albumId = "albumArtist|albumName" — split on first | only; albumArtist may be empty
        let pipeIdx = albumId.firstIndex(of: "|") ?? albumId.endIndex
        let albumArtist = String(albumId[albumId.startIndex..<pipeIdx])
        let albumName: String
        if pipeIdx < albumId.endIndex {
            albumName = String(albumId[albumId.index(after: pipeIdx)...])
        } else {
            albumName = albumId
        }

        let sql: String
        let bindings: [Binding?]
        if albumArtist.isEmpty {
            sql = """
                SELECT * FROM library_tracks
                WHERE (album_artist IS NULL OR album_artist = '')
                AND coalesce(album, 'Unknown Album') = ?
                ORDER BY disc_number ASC NULLS LAST, track_number ASC NULLS LAST, title ASC
                """
            bindings = [albumName]
        } else {
            sql = """
                SELECT * FROM library_tracks
                WHERE album_artist = ?
                AND coalesce(album, 'Unknown Album') = ?
                ORDER BY disc_number ASC NULLS LAST, track_number ASC NULLS LAST, title ASC
                """
            bindings = [albumArtist, albumName]
        }
        do {
            var result: [LibraryTrack] = []
            for row in try db.prepare(sql, bindings) {
                if let track = trackFromStatement(row) {
                    result.append(track)
                }
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: tracksForAlbum failed: %@", error.localizedDescription)
            return []
        }
    }

    func trackCount() -> Int {
        guard let db = db else { return 0 }
        do {
            let count = try db.scalar(tracksTable.count)
            return count
        } catch {
            NSLog("MediaLibraryStore: trackCount failed: %@", error.localizedDescription)
            return 0
        }
    }

    func movieCount() -> Int {
        guard let db = db else { return 0 }
        do {
            let count = try db.scalar(moviesTable.count)
            return count
        } catch {
            NSLog("MediaLibraryStore: movieCount failed: %@", error.localizedDescription)
            return 0
        }
    }

    func episodeCount() -> Int {
        guard let db = db else { return 0 }
        do {
            let count = try db.scalar(episodesTable.count)
            return count
        } catch {
            NSLog("MediaLibraryStore: episodeCount failed: %@", error.localizedDescription)
            return 0
        }
    }

    func searchTracks(query: String, limit: Int, offset: Int) -> [LibraryTrack] {
        guard let db = db else { return [] }
        let sql = """
            SELECT * FROM library_tracks
            WHERE title LIKE ? OR artist LIKE ? OR album LIKE ? OR album_artist LIKE ?
            ORDER BY title ASC
            LIMIT \(limit) OFFSET \(offset)
            """
        let pattern = "%\(query)%"
        do {
            var result: [LibraryTrack] = []
            for row in try db.prepare(sql, pattern, pattern, pattern, pattern) {
                if let track = trackFromStatement(row) {
                    result.append(track)
                }
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: searchTracks failed: %@", error.localizedDescription)
            return []
        }
    }

    func searchArtistNames(query: String) -> [String] {
        guard let db = db else { return [] }
        let sql = """
            SELECT DISTINCT ta.artist_name
            FROM track_artists ta
            WHERE ta.role = 'album_artist'
            AND ta.artist_name LIKE ?
            ORDER BY ta.artist_name ASC
            LIMIT 100
            """
        let pattern = "%\(query)%"
        do {
            var result: [String] = []
            for row in try db.prepare(sql, pattern) {
                if let name = row[0] as? String { result.append(name) }
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: searchArtistNames failed: %@", error.localizedDescription)
            return []
        }
    }

    func searchAlbumSummaries(query: String) -> [AlbumSummary] {
        guard let db = db else { return [] }
        let sql = """
            SELECT
                coalesce(nullif(album_artist, ''), artist, '') || '|' || coalesce(album, 'Unknown Album') as album_id,
                coalesce(album, 'Unknown Album') as album_name,
                coalesce(nullif(album_artist, ''), artist) as album_artist,
                min(year) as yr,
                count(*) as cnt
            FROM library_tracks
            WHERE album LIKE ? OR album_artist LIKE ?
            GROUP BY album_id
            ORDER BY album_name ASC
            LIMIT 100
            """
        let pattern = "%\(query)%"
        do {
            var result: [AlbumSummary] = []
            for row in try db.prepare(sql, pattern, pattern) {
                guard let albumId = row[0] as? String,
                      let albumName = row[1] as? String else { continue }
                let artistName = row[2] as? String
                let year = (row[3] as? Int64).map(Int.init)
                let count = (row[4] as? Int64).map(Int.init) ?? 0
                result.append(AlbumSummary(id: albumId, name: albumName, artist: artistName, year: year, trackCount: count))
            }
            return result
        } catch {
            NSLog("MediaLibraryStore: searchAlbumSummaries failed: %@", error.localizedDescription)
            return []
        }
    }

    // MARK: - Single-row mutations

    func upsertTrack(_ track: LibraryTrack, sig: FileScanSignature?) {
        guard let db = db else { return }
        do {
            try db.transaction {
                try self.upsertTrackInternal(track, sig: sig, connection: db)
            }
            NSLog("MediaLibraryStore: upsertTrack url=%@ title=%@ artist=%@ album=%@ albumArtist=%@",
                  track.url.absoluteString,
                  track.title,
                  track.artist ?? "nil",
                  track.album ?? "nil",
                  track.albumArtist ?? "nil")
        } catch {
            NSLog("MediaLibraryStore: upsertTrack failed: %@", error.localizedDescription)
        }
    }

    func track(forURL url: URL) -> LibraryTrack? {
        guard let db = db else { return nil }
        let urlString = url.absoluteString
        do {
            let query = tracksTable.filter(colURL == urlString || colURL == url.path)
            guard let row = try db.pluck(query) else { return nil }
            return trackFromRow(row)
        } catch {
            NSLog("MediaLibraryStore: track(forURL:) failed: %@", error.localizedDescription)
            return nil
        }
    }

    func upsertMovie(_ movie: LocalVideo, sig: FileScanSignature?) {
        guard let db = db else { return }
        do {
            try upsertMovieInternal(movie, sig: sig, connection: db)
        } catch {
            NSLog("MediaLibraryStore: upsertMovie failed: %@", error.localizedDescription)
        }
    }

    func upsertEpisode(_ episode: LocalEpisode, sig: FileScanSignature?) {
        guard let db = db else { return }
        do {
            try upsertEpisodeInternal(episode, sig: sig, connection: db)
        } catch {
            NSLog("MediaLibraryStore: upsertEpisode failed: %@", error.localizedDescription)
        }
    }

    func deleteTrackByPath(_ path: String) {
        guard let db = db else { return }
        let urlString = URL(fileURLWithPath: path).absoluteString
        do {
            try db.run(tracksTable.filter(colURL == urlString || colURL == path).delete())
        } catch {
            NSLog("MediaLibraryStore: deleteTrackByPath failed: %@", error.localizedDescription)
        }
    }

    func deleteMovieByPath(_ path: String) {
        guard let db = db else { return }
        let urlString = URL(fileURLWithPath: path).absoluteString
        do {
            try db.run(moviesTable.filter(colURL == urlString || colURL == path).delete())
        } catch {
            NSLog("MediaLibraryStore: deleteMovieByPath failed: %@", error.localizedDescription)
        }
    }

    func deleteEpisodeByPath(_ path: String) {
        guard let db = db else { return }
        let urlString = URL(fileURLWithPath: path).absoluteString
        do {
            try db.run(episodesTable.filter(colURL == urlString || colURL == path).delete())
        } catch {
            NSLog("MediaLibraryStore: deleteEpisodeByPath failed: %@", error.localizedDescription)
        }
    }

    func updatePlayStats(trackId: UUID, playCount: Int, lastPlayed: Date) {
        guard let db = db else { return }
        do {
            try db.run(
                tracksTable
                    .filter(colID == trackId.uuidString)
                    .update(
                        colPlayCount <- playCount,
                        colLastPlayed <- lastPlayed.timeIntervalSince1970
                    )
            )
        } catch {
            NSLog("MediaLibraryStore: updatePlayStats failed: %@", error.localizedDescription)
        }
    }

    @discardableResult
    func insertPlayEvent(trackId: String?, trackURL: String?, title: String?, artist: String?,
                         album: String?, genre: String?, playedAt: Date,
                         durationListened: Double, source: String, skipped: Bool) -> Int64? {
        guard let db = db else { return nil }
        do {
            let bindings: [Binding?] = [
                trackId as Binding?,
                trackURL as Binding?,
                title as Binding?,
                artist as Binding?,
                album as Binding?,
                genre as Binding?,
                playedAt.timeIntervalSince1970 as Binding,
                durationListened as Binding,
                source as Binding,
                (skipped ? 1 : 0) as Binding
            ]
            try db.run("""
                INSERT INTO play_events
                  (track_id, track_url, event_title, event_artist, event_album, event_genre,
                   played_at, duration_listened, source, skipped)
                VALUES (?,?,?,?,?,?,?,?,?,?)
                """, bindings)
            NotificationCenter.default.post(name: Self.playHistoryDidChangeNotification, object: nil)
            return db.lastInsertRowid
        } catch {
            NSLog("MediaLibraryStore: Failed to insert play event: %@", error.localizedDescription)
            return nil
        }
    }

    func updatePlayEventGenre(id: Int64, genre: String) {
        guard let db = db else { return }
        do {
            try db.run(
                "UPDATE play_events SET event_genre = ? WHERE id = ? AND (event_genre IS NULL OR event_genre = '')",
                [genre as Binding, id as Binding])
            NotificationCenter.default.post(name: Self.playHistoryDidChangeNotification, object: nil)
        } catch {
            NSLog("MediaLibraryStore: updatePlayEventGenre failed: %@", error.localizedDescription)
        }
    }

    func fetchPlayEventsWithNullGenre() -> [PlayEventGenreStub] {
        guard let db = db else { return [] }
        do {
            let stmt = try db.prepare("""
                SELECT id, event_title, event_artist, event_album
                FROM play_events
                WHERE event_genre IS NULL OR event_genre = ''
                ORDER BY played_at DESC
                """)
            return stmt.compactMap { row in
                guard let id = row[0] as? Int64 else { return nil }
                return PlayEventGenreStub(
                    id: id,
                    title: row[1] as? String,
                    artist: row[2] as? String,
                    album: row[3] as? String
                )
            }
        } catch {
            NSLog("MediaLibraryStore: fetchPlayEventsWithNullGenre failed: %@", error.localizedDescription)
            return []
        }
    }

    var analyticsConnection: Connection? { db }

    func updateTrackRating(trackId: UUID, rating: Int?) {
        guard let db = db else { return }
        do {
            try db.run(
                tracksTable
                    .filter(colID == trackId.uuidString)
                    .update(colRating <- rating)
            )
        } catch {
            NSLog("MediaLibraryStore: updateTrackRating failed: %@", error.localizedDescription)
        }
    }

    func setAlbumRating(albumId: String, rating: Int?) {
        guard let db = db else { return }
        do {
            if let rating = rating {
                try db.run(albumRatingsTable.insert(or: .replace,
                    colAlbumID <- albumId,
                    colRatingVal <- rating
                ))
            } else {
                try db.run(albumRatingsTable.filter(colAlbumID == albumId).delete())
            }
        } catch {
            NSLog("MediaLibraryStore: setAlbumRating failed: %@", error.localizedDescription)
        }
    }

    func setArtistRating(artistId: String, rating: Int?) {
        guard let db = db else { return }
        do {
            if let rating = rating {
                try db.run(artistRatingsTable.insert(or: .replace,
                    colArtistID <- artistId,
                    colRatingVal <- rating
                ))
            } else {
                try db.run(artistRatingsTable.filter(colArtistID == artistId).delete())
            }
        } catch {
            NSLog("MediaLibraryStore: setArtistRating failed: %@", error.localizedDescription)
        }
    }

    func insertWatchFolder(_ url: URL) {
        guard let db = db else { return }
        do {
            try db.run(watchFoldersTable.insert(
                or: .ignore,
                colURL <- url.absoluteString,
                colAddedAt <- Date().timeIntervalSince1970
            ))
        } catch {
            NSLog("MediaLibraryStore: insertWatchFolder failed: %@", error.localizedDescription)
        }
    }

    func deleteWatchFolder(_ path: String) {
        guard let db = db else { return }
        let urlString = URL(fileURLWithPath: path).absoluteString
        do {
            // Also try the path directly for already-stored absolute strings
            try db.run(watchFoldersTable.filter(colURL == urlString).delete())
        } catch {
            NSLog("MediaLibraryStore: deleteWatchFolder failed: %@", error.localizedDescription)
        }
    }

    // MARK: - Bulk Insert (scan batches)

    func upsertTracks(_ items: [(track: LibraryTrack, sig: FileScanSignature?)]) {
        guard let db = db, !items.isEmpty else { return }
        do {
            try db.transaction {
                for item in items {
                    try self.upsertTrackInternal(item.track, sig: item.sig, connection: db)
                }
            }
        } catch {
            NSLog("MediaLibraryStore: upsertTracks batch failed: %@", error.localizedDescription)
        }
    }

    func upsertMovies(_ items: [(movie: LocalVideo, sig: FileScanSignature?)]) {
        guard let db = db, !items.isEmpty else { return }
        do {
            try db.transaction {
                for item in items {
                    try self.upsertMovieInternal(item.movie, sig: item.sig, connection: db)
                }
            }
        } catch {
            NSLog("MediaLibraryStore: upsertMovies batch failed: %@", error.localizedDescription)
        }
    }

    func upsertEpisodes(_ items: [(episode: LocalEpisode, sig: FileScanSignature?)]) {
        guard let db = db, !items.isEmpty else { return }
        do {
            try db.transaction {
                for item in items {
                    try self.upsertEpisodeInternal(item.episode, sig: item.sig, connection: db)
                }
            }
        } catch {
            NSLog("MediaLibraryStore: upsertEpisodes batch failed: %@", error.localizedDescription)
        }
    }

    // MARK: - Clear Operations

    func deleteAllTracks() {
        guard let db = db else { return }
        do {
            try db.transaction {
                try db.run(self.tracksTable.delete())
                try db.run(self.albumRatingsTable.delete())
                try db.run(self.artistRatingsTable.delete())
            }
        } catch {
            NSLog("MediaLibraryStore: deleteAllTracks failed: %@", error.localizedDescription)
        }
    }

    func deleteAllMovies() {
        guard let db = db else { return }
        do {
            try db.run(moviesTable.delete())
        } catch {
            NSLog("MediaLibraryStore: deleteAllMovies failed: %@", error.localizedDescription)
        }
    }

    func deleteAllEpisodes() {
        guard let db = db else { return }
        do {
            try db.run(episodesTable.delete())
        } catch {
            NSLog("MediaLibraryStore: deleteAllEpisodes failed: %@", error.localizedDescription)
        }
    }

    func deleteAllMedia() {
        guard let db = db else { return }
        do {
            try db.transaction {
                try db.run(self.tracksTable.delete())
                try db.run(self.moviesTable.delete())
                try db.run(self.episodesTable.delete())
                try db.run(self.albumRatingsTable.delete())
                try db.run(self.artistRatingsTable.delete())
            }
        } catch {
            NSLog("MediaLibraryStore: deleteAllMedia failed: %@", error.localizedDescription)
        }
    }

    // MARK: - Track Artists Backfill (v2 → v3 migration)

    /// Backfills `track_artists` from existing `artist`/`albumArtist` columns.
    /// Safe to call multiple times — uses INSERT OR IGNORE.
    /// Calls `completion` on the main thread when done.
    func backfillTrackArtistsIfNeeded(completion: @escaping () -> Void = {}) {
        guard let db = db else { completion(); return }
        // Use DispatchQueue (not Task.detached) — SQLite.Connection is not Sendable.
        // This matches how other background DB work is done in MediaLibraryStore.
        DispatchQueue.global(qos: .utility).async {
            // Crash-recovery: delete any partial rows from a previously interrupted backfill.
            // Safe to delete all track_artists here because the batch loop re-inserts for every
            // library_tracks row (including tracks upserted after migration).
            do {
                try db.run("DELETE FROM track_artists")
            } catch {
                NSLog("MediaLibraryStore: backfill pre-clear failed: %@", error.localizedDescription)
            }
            let batchSize = 500
            var offset = 0
            while true {
                var rows: [(url: String, artist: String?, albumArtist: String?)] = []
                do {
                    for row in try db.prepare(
                        "SELECT url, artist, album_artist FROM library_tracks LIMIT \(batchSize) OFFSET \(offset)"
                    ) {
                        let url = row[0] as? String ?? ""
                        let artist = row[1] as? String
                        let albumArtist = row[2] as? String
                        rows.append((url, artist, albumArtist))
                    }
                } catch {
                    NSLog("MediaLibraryStore: backfill read failed: %@", error.localizedDescription)
                    break
                }
                if rows.isEmpty { break }

                do {
                    try db.transaction {
                        for (url, artist, albumArtist) in rows {
                            // primary/featured from artist tag
                            let primaryEntries = ArtistSplitter.split(artist ?? "", isAlbumArtist: false)
                            for entry in primaryEntries {
                                try db.run(
                                    "INSERT OR IGNORE INTO track_artists (track_url, artist_name, role) VALUES (?, ?, ?)",
                                    url, entry.name, entry.role.rawValue
                                )
                            }
                            // album_artist rows — mirrors coalesce(albumArtist, artist, 'Unknown Artist')
                            let albumArtistEntries: [(name: String, role: ArtistRole)]
                            if let aa = albumArtist, !aa.isEmpty {
                                albumArtistEntries = ArtistSplitter.split(aa, isAlbumArtist: true)
                            } else if let a = artist, !a.isEmpty {
                                albumArtistEntries = ArtistSplitter.split(a, isAlbumArtist: true)
                            } else {
                                albumArtistEntries = [(name: "Unknown Artist", role: .albumArtist)]
                            }
                            for entry in albumArtistEntries {
                                try db.run(
                                    "INSERT OR IGNORE INTO track_artists (track_url, artist_name, role) VALUES (?, ?, ?)",
                                    url, entry.name, entry.role.rawValue
                                )
                            }
                        }
                    }
                } catch {
                    NSLog("MediaLibraryStore: backfill write batch failed: %@", error.localizedDescription)
                }
                offset += batchSize
            }
            UserDefaults.standard.set(true, forKey: "trackArtistsBackfillComplete")
            DispatchQueue.main.async { completion() }
        }
    }

    // MARK: - Internal helpers

    @discardableResult
    private func upsertTrackInternal(_ track: LibraryTrack, sig: FileScanSignature?, connection: Connection) throws -> Int64 {
        let rowid = try connection.run(tracksTable.insert(
            or: .replace,
            colID <- track.id.uuidString,
            colURL <- track.url.absoluteString,
            colTitle <- track.title,
            colArtist <- track.artist,
            colAlbum <- track.album,
            colAlbumArtist <- track.albumArtist,
            colGenre <- track.genre,
            colYear <- track.year,
            colTrackNumber <- track.trackNumber,
            colDiscNumber <- track.discNumber,
            colDuration <- track.duration,
            colBitrate <- track.bitrate,
            colSampleRate <- track.sampleRate,
            colChannels <- track.channels,
            colFileSize <- track.fileSize,
            colDateAdded <- track.dateAdded.timeIntervalSince1970,
            colLastPlayed <- track.lastPlayed.map { $0.timeIntervalSince1970 },
            colPlayCount <- track.playCount,
            colRating <- track.rating,
            colScanFileSize <- sig?.fileSize,
            colScanModDate <- sig?.contentModificationDate.map { $0.timeIntervalSince1970 },
            colComposer <- track.composer,
            colComment <- track.comment,
            colGrouping <- track.grouping,
            colBPM <- track.bpm,
            colMusicalKey <- track.musicalKey,
            colISRC <- track.isrc,
            colCopyright <- track.copyright,
            colMBRecordingID <- track.musicBrainzRecordingID,
            colMBReleaseID <- track.musicBrainzReleaseID,
            colDiscogsReleaseID <- track.discogsReleaseID,
            colDiscogsMasterID <- track.discogsMasterID,
            colDiscogsLabel <- track.discogsLabel,
            colDiscogsCatalogNumber <- track.discogsCatalogNumber,
            colArtworkURL <- track.artworkURL
        ))
        // INSERT OR REPLACE on library_tracks cascades DELETE on track_artists (FK + PRAGMA foreign_keys = ON),
        // so old rows are already gone. Use INSERT OR IGNORE to avoid duplicate-key errors on edge cases.
        let urlStr = track.url.absoluteString
        for entry in derivedArtistEntries(for: track) {
            try connection.run("""
                INSERT OR IGNORE INTO track_artists (track_url, artist_name, role)
                VALUES (?, ?, ?)
                """, urlStr, entry.name, entry.role.rawValue)
        }
        return rowid
    }

    private func derivedArtistEntries(for track: LibraryTrack) -> [(name: String, role: ArtistRole)] {
        var entries = ArtistSplitter.split(track.artist ?? "", isAlbumArtist: false)

        let albumArtistEntries: [(name: String, role: ArtistRole)]
        if let albumArtist = track.albumArtist, !albumArtist.isEmpty {
            albumArtistEntries = ArtistSplitter.split(albumArtist, isAlbumArtist: true)
        } else if let artist = track.artist, !artist.isEmpty {
            albumArtistEntries = ArtistSplitter.split(artist, isAlbumArtist: true)
        } else {
            albumArtistEntries = [(name: "Unknown Artist", role: .albumArtist)]
        }

        entries.append(contentsOf: albumArtistEntries)
        return entries
    }

    @discardableResult
    private func upsertMovieInternal(_ movie: LocalVideo, sig: FileScanSignature?, connection: Connection) throws -> Int64 {
        try connection.run(moviesTable.insert(
            or: .replace,
            colID <- movie.id.uuidString,
            colURL <- movie.url.absoluteString,
            colTitle <- movie.title,
            colYear <- movie.year,
            colDuration <- movie.duration,
            colFileSize <- movie.fileSize,
            colDateAdded <- movie.dateAdded.timeIntervalSince1970,
            colScanFileSize <- sig?.fileSize,
            colScanModDate <- sig?.contentModificationDate.map { $0.timeIntervalSince1970 }
        ))
    }

    @discardableResult
    private func upsertEpisodeInternal(_ episode: LocalEpisode, sig: FileScanSignature?, connection: Connection) throws -> Int64 {
        try connection.run(episodesTable.insert(
            or: .replace,
            colID <- episode.id.uuidString,
            colURL <- episode.url.absoluteString,
            colTitle <- episode.title,
            colShowTitle <- episode.showTitle,
            colSeasonNumber <- episode.seasonNumber,
            colEpisodeNumber <- episode.episodeNumber,
            colDuration <- episode.duration,
            colFileSize <- episode.fileSize,
            colDateAdded <- episode.dateAdded.timeIntervalSince1970,
            colScanFileSize <- sig?.fileSize,
            colScanModDate <- sig?.contentModificationDate.map { $0.timeIntervalSince1970 }
        ))
    }

    // MARK: - URL parsing helper

    /// Parse a URL stored in the database, with a fallback for plain absolute paths
    /// that were stored without the file:// scheme (e.g. from older library formats).
    /// `URL(string:)` rejects paths containing unencoded spaces or special characters,
    /// so plain paths like "/Music/My Track.mp3" must be reconstructed via fileURLWithPath.
    private static func urlFromStoredString(_ urlString: String) -> URL? {
        if let url = URL(string: urlString) { return url }
        if urlString.hasPrefix("/") {
            NSLog("MediaLibraryStore: repairing plain-path URL: %@", urlString)
            return URL(fileURLWithPath: urlString)
        }
        NSLog("MediaLibraryStore: skipping unparseable URL: %@", urlString)
        return nil
    }

    // MARK: - Row -> Model conversions (typed Table queries)

    private func trackFromRow(_ row: Row) -> LibraryTrack? {
        guard let id = UUID(uuidString: row[colID]),
              let url = Self.urlFromStoredString(row[colURL]) else { return nil }
        return LibraryTrack(
            id: id,
            url: url,
            title: row[colTitle],
            artist: row[colArtist],
            album: row[colAlbum],
            albumArtist: row[colAlbumArtist],
            genre: row[colGenre],
            year: row[colYear],
            trackNumber: row[colTrackNumber],
            discNumber: row[colDiscNumber],
            duration: row[colDuration],
            bitrate: row[colBitrate],
            sampleRate: row[colSampleRate],
            channels: row[colChannels],
            fileSize: row[colFileSize],
            dateAdded: Date(timeIntervalSince1970: row[colDateAdded]),
            lastPlayed: row[colLastPlayed].map { Date(timeIntervalSince1970: $0) },
            playCount: row[colPlayCount],
            rating: row[colRating],
            composer: row[colComposer],
            comment: row[colComment],
            grouping: row[colGrouping],
            bpm: row[colBPM],
            musicalKey: row[colMusicalKey],
            isrc: row[colISRC],
            copyright: row[colCopyright],
            musicBrainzRecordingID: row[colMBRecordingID],
            musicBrainzReleaseID: row[colMBReleaseID],
            discogsReleaseID: row[colDiscogsReleaseID],
            discogsMasterID: row[colDiscogsMasterID],
            discogsLabel: row[colDiscogsLabel],
            discogsCatalogNumber: row[colDiscogsCatalogNumber],
            artworkURL: row[colArtworkURL]
        )
    }

    private func movieFromRow(_ row: Row) -> LocalVideo? {
        guard let id = UUID(uuidString: row[colID]),
              let url = Self.urlFromStoredString(row[colURL]) else { return nil }
        var movie = LocalVideo(url: url)
        // Override generated UUID with stored one
        return LocalVideo(
            id: id,
            url: url,
            title: row[colTitle],
            year: row[colYear],
            duration: row[colDuration],
            fileSize: row[colFileSize],
            dateAdded: Date(timeIntervalSince1970: row[colDateAdded])
        )
    }

    private func episodeFromRow(_ row: Row) -> LocalEpisode? {
        guard let id = UUID(uuidString: row[colID]),
              let url = Self.urlFromStoredString(row[colURL]) else { return nil }
        return LocalEpisode(
            id: id,
            url: url,
            title: row[colTitle],
            showTitle: row[colShowTitle],
            seasonNumber: row[colSeasonNumber],
            episodeNumber: row[colEpisodeNumber],
            duration: row[colDuration],
            fileSize: row[colFileSize],
            dateAdded: Date(timeIntervalSince1970: row[colDateAdded])
        )
    }

    // MARK: - Statement row conversions (raw SQL queries)

    private func trackFromStatement(_ row: Statement.Element) -> LibraryTrack? {
        // Columns in SELECT * from library_tracks order:
        // id, url, title, artist, album, album_artist, genre, year, track_number, disc_number,
        // duration, bitrate, sample_rate, channels, file_size, date_added, last_played, play_count, rating,
        // scan_file_size, scan_mod_date, composer, comment, grouping, bpm, musical_key, isrc, copyright,
        // musicbrainz_recording_id, musicbrainz_release_id, discogs_release_id, discogs_master_id,
        // discogs_label, discogs_catalog_number, artwork_url
        guard let idStr = row[0] as? String,
              let id = UUID(uuidString: idStr),
              let urlStr = row[1] as? String,
              let url = Self.urlFromStoredString(urlStr),
              let title = row[2] as? String else { return nil }

        let artist = row[3] as? String
        let album = row[4] as? String
        let albumArtist = row[5] as? String
        let genre = row[6] as? String
        let year = (row[7] as? Int64).map(Int.init)
        let trackNumber = (row[8] as? Int64).map(Int.init)
        let discNumber = (row[9] as? Int64).map(Int.init)
        let duration = row[10] as? Double ?? 0
        let bitrate = (row[11] as? Int64).map(Int.init)
        let sampleRate = (row[12] as? Int64).map(Int.init)
        let channels = (row[13] as? Int64).map(Int.init)
        let fileSize = (row[14] as? Int64) ?? 0
        let dateAdded = Date(timeIntervalSince1970: row[15] as? Double ?? 0)
        let lastPlayedTs = row[16] as? Double
        let playCount = (row[17] as? Int64).map(Int.init) ?? 0
        let rating = (row[18] as? Int64).map(Int.init)
        let composer = row[21] as? String
        let comment = row[22] as? String
        let grouping = row[23] as? String
        let bpm = (row[24] as? Int64).map(Int.init)
        let musicalKey = row[25] as? String
        let isrc = row[26] as? String
        let copyright = row[27] as? String
        let musicBrainzRecordingID = row[28] as? String
        let musicBrainzReleaseID = row[29] as? String
        let discogsReleaseID = (row[30] as? Int64).map(Int.init)
        let discogsMasterID = (row[31] as? Int64).map(Int.init)
        let discogsLabel = row[32] as? String
        let discogsCatalogNumber = row[33] as? String
        let artworkURL = row[34] as? String

        return LibraryTrack(
            id: id,
            url: url,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            genre: genre,
            year: year,
            trackNumber: trackNumber,
            discNumber: discNumber,
            duration: duration,
            bitrate: bitrate,
            sampleRate: sampleRate,
            channels: channels,
            fileSize: fileSize,
            dateAdded: dateAdded,
            lastPlayed: lastPlayedTs.map { Date(timeIntervalSince1970: $0) },
            playCount: playCount,
            rating: rating,
            composer: composer,
            comment: comment,
            grouping: grouping,
            bpm: bpm,
            musicalKey: musicalKey,
            isrc: isrc,
            copyright: copyright,
            musicBrainzRecordingID: musicBrainzRecordingID,
            musicBrainzReleaseID: musicBrainzReleaseID,
            discogsReleaseID: discogsReleaseID,
            discogsMasterID: discogsMasterID,
            discogsLabel: discogsLabel,
            discogsCatalogNumber: discogsCatalogNumber,
            artworkURL: artworkURL
        )
    }
}
