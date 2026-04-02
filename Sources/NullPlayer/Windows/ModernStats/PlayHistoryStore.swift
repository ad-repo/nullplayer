import Foundation
import SQLite

// MARK: - Result Types

struct TopDimensionRow: Identifiable, Sendable {
    let id: String
    let displayName: String
    let playCount: Int
    let totalMinutes: Double
}

struct TimeSeriesRow: Identifiable, Sendable {
    let id: String
    let bucket: String
    let date: Date
    let source: String
    let playCount: Int
    let totalMinutes: Double

    var sourceDisplayName: String {
        PlayHistorySource.displayName(for: source)
    }
}

struct RecentEventRow: Identifiable, Sendable {
    let id: Int64
    let title: String
    let artist: String
    let album: String
    let genre: String
    let source: String
    let playedAt: Date
    let durationListened: Double
    let skipped: Bool

    var sourceDisplayName: String {
        PlayHistorySource.displayName(for: source)
    }
}

// MARK: - Store

final class PlayHistoryStore: Sendable {

    func fetchTopDimension(dimension: StatsDimension, filter: StatsFilterState) throws -> [TopDimensionRow] {
        let col: String
        switch dimension {
        case .artist: col = "event_artist"
        case .album:  col = "event_album"
        case .genre:  col = "event_genre"
        case .source: col = "source"
        }
        let (whereStr, params) = whereClause(for: filter)
        let sql = """
            SELECT COALESCE(\(col), 'Unknown'), COUNT(*), COALESCE(SUM(duration_listened), 0.0) / 60.0
            FROM play_events
            \(whereStr)
            GROUP BY 1
            ORDER BY 2 DESC
            LIMIT 25
            """
        guard let db = MediaLibraryStore.shared.analyticsConnection else { return [] }
        let stmt = try db.prepare(sql, params)
        return stmt.map { row in
            let name = row[0] as? String ?? "Unknown"
            let count = Int(row[1] as? Int64 ?? 0)
            let mins = row[2] as? Double ?? 0
            let displayName = dimension == .source ? PlayHistorySource.displayName(for: name) : name
            return TopDimensionRow(id: name, displayName: displayName, playCount: count, totalMinutes: mins)
        }
    }

    func fetchTimeSeries(filter: StatsFilterState, granularity: StatsGranularity) throws -> [TimeSeriesRow] {
        let fmt: String
        switch granularity {
        case .day:   fmt = "%Y-%m-%d"
        case .week:  fmt = "%Y-%W"
        case .month: fmt = "%Y-%m"
        }
        let (whereStr, params) = whereClause(for: filter)
        let sql = """
            SELECT strftime('\(fmt)', played_at, 'unixepoch', 'localtime'),
                   source,
                   COUNT(*),
                   COALESCE(SUM(duration_listened), 0.0) / 60.0
            FROM play_events
            \(whereStr)
            GROUP BY 1, 2
            ORDER BY 1 ASC, 2 ASC
            """
        guard let db = MediaLibraryStore.shared.analyticsConnection else { return [] }
        let stmt = try db.prepare(sql, params)
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        let weekFormatter = DateFormatter()
        weekFormatter.dateFormat = "yyyy-ww"   // ISO week (%Y-%W maps to week-of-year)
        weekFormatter.locale = Locale(identifier: "en_US_POSIX")
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        let bucketFormatter: DateFormatter
        switch granularity {
        case .day:   bucketFormatter = dayFormatter
        case .week:  bucketFormatter = weekFormatter
        case .month: bucketFormatter = monthFormatter
        }
        return stmt.compactMap { row in
            guard let bucket = row[0] as? String else { return nil }
            let source = row[1] as? String ?? PlayHistorySource.local.rawValue
            let count = Int(row[2] as? Int64 ?? 0)
            let mins = row[3] as? Double ?? 0
            let date = bucketFormatter.date(from: bucket) ?? Date(timeIntervalSince1970: 0)
            return TimeSeriesRow(
                id: "\(bucket)-\(source)",
                bucket: bucket,
                date: date,
                source: source,
                playCount: count,
                totalMinutes: mins
            )
        }
    }

    func fetchGenreBreakdown(filter: StatsFilterState) throws -> [TopDimensionRow] {
        let (whereStr, params) = whereClause(for: filter)
        let sql = """
            SELECT COALESCE(event_genre, 'Unknown'), COUNT(*), COALESCE(SUM(duration_listened), 0.0) / 60.0
            FROM play_events
            \(whereStr)
            GROUP BY 1
            ORDER BY 2 DESC
            LIMIT 15
            """
        guard let db = MediaLibraryStore.shared.analyticsConnection else { return [] }
        let stmt = try db.prepare(sql, params)
        return stmt.map { row in
            let name = row[0] as? String ?? "Unknown"
            let count = Int(row[1] as? Int64 ?? 0)
            let mins = row[2] as? Double ?? 0
            return TopDimensionRow(id: name, displayName: name, playCount: count, totalMinutes: mins)
        }
    }

    func fetchRecentEvents(filter: StatsFilterState) throws -> [RecentEventRow] {
        let (whereStr, params) = whereClause(for: filter)
        let sql = """
            SELECT id, event_title, event_artist, event_album, event_genre,
                   source, played_at, duration_listened, skipped
            FROM play_events
            \(whereStr)
            ORDER BY played_at DESC
            LIMIT 200
            """
        guard let db = MediaLibraryStore.shared.analyticsConnection else { return [] }
        let stmt = try db.prepare(sql, params)
        return stmt.compactMap { row in
            guard let id = row[0] as? Int64 else { return nil }
            let title  = row[1] as? String ?? ""
            let artist = row[2] as? String ?? ""
            let album  = row[3] as? String ?? ""
            let genre  = row[4] as? String ?? ""
            let source = row[5] as? String ?? ""
            let ts     = row[6] as? Double ?? 0
            let dur    = row[7] as? Double ?? 0
            let skip   = (row[8] as? Int64 ?? 0) != 0
            return RecentEventRow(id: id, title: title, artist: artist, album: album,
                                  genre: genre, source: source,
                                  playedAt: Date(timeIntervalSince1970: ts),
                                  durationListened: dur, skipped: skip)
        }
    }

    // MARK: - WHERE clause builder

    private func whereClause(for filter: StatsFilterState) -> (String, [Binding?]) {
        var conditions: [String] = []
        var params: [Binding?] = []

        let now = Date().timeIntervalSince1970
        switch filter.timeRange {
        case .last7Days:
            conditions.append("played_at >= ?")
            params.append(now - 7 * 86400)
        case .last30Days:
            conditions.append("played_at >= ?")
            params.append(now - 30 * 86400)
        case .last90Days:
            conditions.append("played_at >= ?")
            params.append(now - 90 * 86400)
        case .last365Days:
            conditions.append("played_at >= ?")
            params.append(now - 365 * 86400)
        case .allTime:
            break
        case .custom(let start, let end):
            conditions.append("played_at >= ?")
            params.append(start.timeIntervalSince1970)
            conditions.append("played_at <= ?")
            params.append(end.timeIntervalSince1970)
        }

        if let artist = filter.selectedArtist {
            conditions.append("event_artist = ?")
            params.append(artist)
        }
        if let album = filter.selectedAlbum {
            conditions.append("event_album = ?")
            params.append(album)
        }
        if let genre = filter.selectedGenre {
            conditions.append("event_genre = ?")
            params.append(genre)
        }
        if let source = filter.selectedSource {
            conditions.append("source = ?")
            params.append(source)
        }
        if filter.excludeSkipped {
            conditions.append("skipped = 0")
        }

        if conditions.isEmpty {
            return ("", params)
        }
        return ("WHERE " + conditions.joined(separator: " AND "), params)
    }
}
