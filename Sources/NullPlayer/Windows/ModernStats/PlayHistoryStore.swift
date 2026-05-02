import Foundation
import SQLite

// MARK: - Content Type Helper

enum PlayHistoryContentType: String, CaseIterable {
    case music
    case movie
    case tv
    case radio
    case video

    var displayName: String {
        switch self {
        case .music: return "Music"
        case .movie: return "Movies"
        case .tv:    return "TV Shows"
        case .radio: return "Radio"
        case .video: return "Video"
        }
    }

    static func displayName(for rawValue: String) -> String {
        PlayHistoryContentType(rawValue: rawValue)?.displayName ?? rawValue.capitalized
    }
}

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

struct PlayTimeSummaryRow: Identifiable, Sendable {
    let id: String
    let title: String
    let durationListened: Double
}

// MARK: - Store

final class PlayHistoryStore: Sendable {

    private let historyFromClause = """
        FROM play_events pe
        LEFT JOIN library_tracks lt ON pe.track_url = lt.url
        """

    private var resolvedArtistExpression: String {
        """
        CASE
            WHEN lower(trim(coalesce(lt.album_artist, ''))) = 'various artists'
                 AND nullif(trim(coalesce(lt.artist, '')), '') IS NOT NULL
            THEN lt.artist
            ELSE coalesce(nullif(trim(pe.event_artist), ''), nullif(trim(lt.artist), ''), 'Unknown')
        END
        """
    }

    func fetchTopDimension(dimension: StatsDimension, filter: StatsFilterState) throws -> [TopDimensionRow] {
        let dimensionExpr: String
        switch dimension {
        case .artist:
            dimensionExpr = resolvedArtistExpression
        case .album:
            dimensionExpr = "COALESCE(NULLIF(trim(pe.event_album), ''), 'Unknown')"
        case .genre:
            dimensionExpr = "COALESCE(NULLIF(trim(pe.event_genre), ''), 'Unknown')"
        case .source:
            dimensionExpr = "pe.source"
        case .outputDevice:
            dimensionExpr = "COALESCE(NULLIF(trim(pe.output_device), ''), 'Unknown')"
        }
        let limit = dimension == .artist ? 250 : 25
        var (whereStr, params) = whereClause(for: filter)
        if dimension == .outputDevice {
            let extra = "NULLIF(trim(pe.output_device), '') IS NOT NULL"
            whereStr = whereStr.isEmpty ? "WHERE \(extra)" : "\(whereStr) AND \(extra)"
        }
        let sql = """
            SELECT \(dimensionExpr), COUNT(*), COALESCE(SUM(pe.duration_listened), 0.0) / 60.0
            \(historyFromClause)
            \(whereStr)
            GROUP BY 1
            ORDER BY 2 DESC
            LIMIT \(limit)
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
        // Use bucket-start timestamps to avoid week-boundary mismatches between SQLite strftime and DateFormatter
        let bucketExpr: String
        switch granularity {
        case .day:
            // Start of day in local time, returned as unix epoch
            bucketExpr = "strftime('%s', strftime('%Y-%m-%d', played_at, 'unixepoch', 'localtime'), 'utc')"
        case .week:
            // Start of ISO week (Monday) in local time
            bucketExpr = "strftime('%s', date(played_at, 'unixepoch', 'localtime', 'weekday 0', '-6 days'), 'utc')"
        case .month:
            // Start of month in local time
            bucketExpr = "strftime('%s', strftime('%Y-%m-01', played_at, 'unixepoch', 'localtime'), 'utc')"
        }
        let (whereStr, params) = whereClause(for: filter)
        let sql = """
            SELECT \(bucketExpr),
                   pe.source,
                   COUNT(*),
                   COALESCE(SUM(pe.duration_listened), 0.0) / 60.0
            \(historyFromClause)
            \(whereStr)
            GROUP BY 1, 2
            ORDER BY 1 ASC, 2 ASC
            """
        guard let db = MediaLibraryStore.shared.analyticsConnection else { return [] }
        let stmt = try db.prepare(sql, params)
        let labelFormatter = DateFormatter()
        labelFormatter.locale = Locale(identifier: "en_US_POSIX")
        switch granularity {
        case .day:   labelFormatter.dateFormat = "yyyy-MM-dd"
        case .week:  labelFormatter.dateFormat = "yyyy-MM-dd"
        case .month: labelFormatter.dateFormat = "yyyy-MM"
        }
        return stmt.compactMap { row in
            guard let tsStr = row[0] as? String,
                  let ts = Double(tsStr) else { return nil }
            let date = Date(timeIntervalSince1970: ts)
            let bucket = labelFormatter.string(from: date)
            let source = row[1] as? String ?? PlayHistorySource.local.rawValue
            let count = Int(row[2] as? Int64 ?? 0)
            let mins = row[3] as? Double ?? 0
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
            SELECT COALESCE(NULLIF(trim(pe.event_genre), ''), 'Unknown'), COUNT(*), COALESCE(SUM(pe.duration_listened), 0.0) / 60.0
            \(historyFromClause)
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

    func fetchContentTypeBreakdown(filter: StatsFilterState) throws -> [TopDimensionRow] {
        let (whereStr, params) = whereClause(for: filter)
        let sql = """
            SELECT COALESCE(pe.content_type, 'music'), COUNT(*), COALESCE(SUM(pe.duration_listened), 0.0) / 60.0
            \(historyFromClause)
            \(whereStr)
            GROUP BY 1
            ORDER BY 2 DESC
            """
        guard let db = MediaLibraryStore.shared.analyticsConnection else { return [] }
        let stmt = try db.prepare(sql, params)
        return stmt.map { row in
            let raw = row[0] as? String ?? "music"
            let count = Int(row[1] as? Int64 ?? 0)
            let mins = row[2] as? Double ?? 0
            return TopDimensionRow(id: raw, displayName: PlayHistoryContentType.displayName(for: raw), playCount: count, totalMinutes: mins)
        }
    }

    func fetchRecentEvents(filter: StatsFilterState) throws -> [RecentEventRow] {
        let (whereStr, params) = whereClause(for: filter)
        let sql = """
            SELECT pe.id,
                   pe.event_title,
                   \(resolvedArtistExpression) AS resolved_artist,
                   pe.event_album,
                   pe.event_genre,
                   pe.source,
                   pe.played_at,
                   pe.duration_listened,
                   pe.skipped
            \(historyFromClause)
            \(whereStr)
            ORDER BY pe.played_at DESC
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

    func fetchPlayTimeSummaries(filter: StatsFilterState) throws -> [PlayTimeSummaryRow] {
        let calendar = Calendar(identifier: .iso8601)
        let now = Date()
        let dayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? dayStart
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? dayStart
        let yearStart = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? dayStart

        var rangeAgnosticFilter = filter
        rangeAgnosticFilter.timeRange = .allTime
        let (whereStr, params) = whereClause(for: rangeAgnosticFilter)

        let sql = """
            SELECT
                COALESCE(SUM(CASE WHEN pe.played_at >= ? THEN pe.duration_listened ELSE 0 END), 0.0),
                COALESCE(SUM(CASE WHEN pe.played_at >= ? THEN pe.duration_listened ELSE 0 END), 0.0),
                COALESCE(SUM(CASE WHEN pe.played_at >= ? THEN pe.duration_listened ELSE 0 END), 0.0),
                COALESCE(SUM(CASE WHEN pe.played_at >= ? THEN pe.duration_listened ELSE 0 END), 0.0),
                COALESCE(SUM(pe.duration_listened), 0.0)
            \(historyFromClause)
            \(whereStr)
            """
        guard let db = MediaLibraryStore.shared.analyticsConnection else { return [] }

        let statementParams: [Binding?] = [
            dayStart.timeIntervalSince1970,
            weekStart.timeIntervalSince1970,
            monthStart.timeIntervalSince1970,
            yearStart.timeIntervalSince1970
        ] + params

        let stmt = try db.prepare(sql, statementParams)
        let row = stmt.makeIterator().next()
        let durations = (0...4).map { index -> Double in
            row?[index] as? Double ?? 0
        }

        return [
            PlayTimeSummaryRow(id: "day", title: "Day", durationListened: durations[0]),
            PlayTimeSummaryRow(id: "week", title: "Week", durationListened: durations[1]),
            PlayTimeSummaryRow(id: "month", title: "Month", durationListened: durations[2]),
            PlayTimeSummaryRow(id: "year", title: "Year", durationListened: durations[3]),
            PlayTimeSummaryRow(id: "all-time", title: "All Time", durationListened: durations[4])
        ]
    }

    // MARK: - WHERE clause builder

    private func whereClause(for filter: StatsFilterState) -> (String, [Binding?]) {
        var conditions: [String] = []
        var params: [Binding?] = []

        let now = Date().timeIntervalSince1970
        switch filter.timeRange {
        case .last7Days:
            conditions.append("pe.played_at >= ?")
            params.append(now - 7 * 86400)
        case .last30Days:
            conditions.append("pe.played_at >= ?")
            params.append(now - 30 * 86400)
        case .last90Days:
            conditions.append("pe.played_at >= ?")
            params.append(now - 90 * 86400)
        case .last365Days:
            conditions.append("pe.played_at >= ?")
            params.append(now - 365 * 86400)
        case .allTime:
            break
        case .custom(let start, let end):
            conditions.append("pe.played_at >= ?")
            params.append(start.timeIntervalSince1970)
            conditions.append("pe.played_at <= ?")
            params.append(end.timeIntervalSince1970)
        }

        if let artist = filter.selectedArtist {
            conditions.append("\(resolvedArtistExpression) = ?")
            params.append(artist)
        }
        if let album = filter.selectedAlbum {
            conditions.append("COALESCE(NULLIF(trim(pe.event_album), ''), 'Unknown') = ?")
            params.append(album)
        }
        if let genre = filter.selectedGenre {
            conditions.append("COALESCE(NULLIF(trim(pe.event_genre), ''), 'Unknown') = ?")
            params.append(genre)
        }
        if let source = filter.selectedSource {
            conditions.append("pe.source = ?")
            params.append(source)
        }
        if let contentType = filter.selectedContentType {
            conditions.append("COALESCE(pe.content_type, 'music') = ?")
            params.append(contentType)
        }
        if let device = filter.selectedOutputDevice {
            conditions.append("COALESCE(NULLIF(trim(pe.output_device), ''), 'Unknown') = ?")
            params.append(device)
        }
        if filter.excludeSkipped {
            conditions.append("pe.skipped = 0")
        }

        if conditions.isEmpty {
            return ("", params)
        }
        return ("WHERE " + conditions.joined(separator: " AND "), params)
    }
}
