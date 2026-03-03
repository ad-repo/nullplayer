import Foundation
import SQLite

// MARK: - Retention Interval Enum

enum PlexRadioHistoryInterval: String, CaseIterable {
    case off = "off"
    case twoWeeks = "2weeks"
    case oneMonth = "1month"
    case threeMonths = "3months"
    case sixMonths = "6months"

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .twoWeeks: return "2 Weeks"
        case .oneMonth: return "1 Month"
        case .threeMonths: return "3 Months"
        case .sixMonths: return "6 Months"
        }
    }

    var timeInterval: TimeInterval? {
        switch self {
        case .off: return nil
        case .twoWeeks: return 14 * 24 * 3600
        case .oneMonth: return 30 * 24 * 3600
        case .threeMonths: return 90 * 24 * 3600
        case .sixMonths: return 180 * 24 * 3600
        }
    }
}

// MARK: - History Entry Struct

struct PlexRadioHistoryEntry {
    let id: Int64
    let plexRatingKey: String
    let title: String
    let artist: String?
    let album: String?
    let plexServerId: String?
    let playedAt: Date
}

// MARK: - PlexRadioHistory

class PlexRadioHistory {
    static let shared = PlexRadioHistory()

    private var db: Connection?

    // Table
    private let table = Table("plex_radio_history")

    // Columns
    private let colId = Expression<Int64>("id")
    private let colRatingKey = Expression<String>("plex_rating_key")
    private let colTitle = Expression<String>("title")
    private let colArtist = Expression<String?>("artist")
    private let colAlbum = Expression<String?>("album")
    private let colServerId = Expression<String>("plex_server_id")
    private let colPlayedAt = Expression<Double>("played_at")
    private let colNormalizedKey = Expression<String>("normalized_key")

    private init() {
        setupDatabase()
    }

    // MARK: - Setup

    private func setupDatabase() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            NSLog("PlexRadioHistory: Cannot locate Application Support directory")
            return
        }
        let dir = appSupport.appendingPathComponent("NullPlayer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("plex_radio_history.db").path

        do {
            let connection = try Connection(dbPath)
            db = connection
            try createTableIfNeeded(connection)
            NSLog("PlexRadioHistory: Database ready at %@", dbPath)
        } catch {
            NSLog("PlexRadioHistory: Failed to open database: %@", error.localizedDescription)
        }
    }

    private func createTableIfNeeded(_ connection: Connection) throws {
        try connection.run(table.create(ifNotExists: true) { t in
            t.column(colId, primaryKey: .autoincrement)
            t.column(colRatingKey)
            t.column(colTitle)
            t.column(colArtist)
            t.column(colAlbum)
            t.column(colServerId)
            t.column(colPlayedAt)
            t.column(colNormalizedKey)
            t.unique(colRatingKey, colServerId)
        })
        try connection.run(
            "CREATE INDEX IF NOT EXISTS idx_history_played_at ON plex_radio_history (played_at)"
        )
        try connection.run(
            "CREATE INDEX IF NOT EXISTS idx_history_normalized_key ON plex_radio_history (normalized_key)"
        )
    }

    // MARK: - Retention Interval

    var retentionInterval: PlexRadioHistoryInterval {
        get {
            let raw = UserDefaults.standard.string(forKey: "plexRadioHistoryInterval") ?? PlexRadioHistoryInterval.oneMonth.rawValue
            return PlexRadioHistoryInterval(rawValue: raw) ?? .oneMonth
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "plexRadioHistoryInterval")
        }
    }

    var isEnabled: Bool { retentionInterval != .off }

    // MARK: - Normalized Key

    static func normalizedKey(title: String?, artist: String?) -> String {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let a = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(a)|\(t)"
    }

    // MARK: - Record

    func recordTrackPlayed(_ track: Track) {
        guard let db = db,
              let ratingKey = track.plexRatingKey else { return }

        let serverId = track.plexServerId ?? PlexManager.shared.currentServer?.id ?? ""
        let nKey = PlexRadioHistory.normalizedKey(title: track.title, artist: track.artist)
        let playedAt = Date().timeIntervalSince1970

        do {
            try db.run(table.insert(
                or: .replace,
                colRatingKey <- ratingKey,
                colTitle <- (track.title ?? ""),
                colArtist <- track.artist,
                colAlbum <- track.album,
                colServerId <- serverId,
                colPlayedAt <- playedAt,
                colNormalizedKey <- nKey
            ))
        } catch {
            NSLog("PlexRadioHistory: Failed to record track: %@", error.localizedDescription)
        }
    }

    // MARK: - Filter

    func filterOutHistoryTracks(_ tracks: [Track]) -> [Track] {
        guard isEnabled, let db = db else { return tracks }

        let cutoff: Double
        if let interval = retentionInterval.timeInterval {
            cutoff = Date().timeIntervalSince1970 - interval
        } else {
            return tracks
        }

        do {
            let rows = try db.prepare(
                table.select(colRatingKey, colNormalizedKey)
                     .filter(colPlayedAt >= cutoff)
            )
            var ratingKeys = Set<String>()
            var normalizedKeys = Set<String>()
            for row in rows {
                ratingKeys.insert(row[colRatingKey])
                normalizedKeys.insert(row[colNormalizedKey])
            }

            return tracks.filter { track in
                if let rk = track.plexRatingKey, ratingKeys.contains(rk) {
                    NSLog("PlexRadioHistory: Filtered out '%@' by '%@' (rating key match: %@)",
                          track.title ?? "", track.artist ?? "", rk)
                    return false
                }
                let nk = PlexRadioHistory.normalizedKey(title: track.title, artist: track.artist)
                if normalizedKeys.contains(nk) {
                    NSLog("PlexRadioHistory: Filtered out '%@' by '%@' (normalized key match: %@)",
                          track.title ?? "", track.artist ?? "", nk)
                    return false
                }
                return true
            }
        } catch {
            NSLog("PlexRadioHistory: Failed to query history for filtering: %@", error.localizedDescription)
            return tracks
        }
    }

    // MARK: - Fetch

    func fetchHistory() -> [PlexRadioHistoryEntry] {
        guard let db = db else { return [] }
        do {
            let rows = try db.prepare(table.order(colPlayedAt.desc))
            return rows.map { row in
                PlexRadioHistoryEntry(
                    id: row[colId],
                    plexRatingKey: row[colRatingKey],
                    title: row[colTitle],
                    artist: row[colArtist],
                    album: row[colAlbum],
                    plexServerId: row[colServerId],
                    playedAt: Date(timeIntervalSince1970: row[colPlayedAt])
                )
            }
        } catch {
            NSLog("PlexRadioHistory: Failed to fetch history: %@", error.localizedDescription)
            return []
        }
    }

    // MARK: - Remove

    func removeEntry(id: Int64) {
        guard let db = db else { return }
        do {
            try db.run(table.filter(colId == id).delete())
        } catch {
            NSLog("PlexRadioHistory: Failed to remove entry %lld: %@", id, error.localizedDescription)
        }
    }

    func clearHistory() {
        guard let db = db else { return }
        do {
            try db.run(table.delete())
        } catch {
            NSLog("PlexRadioHistory: Failed to clear history: %@", error.localizedDescription)
        }
    }

    // MARK: - Web

    var historyPageURL: URL? { URL(string: "http://127.0.0.1:8765/radio-history") }

    func generateHistoryHTML() -> String {
        let entries = fetchHistory()
        let interval = retentionInterval
        let count = entries.count

        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short

        var rows = ""
        for entry in entries {
            let title = htmlEscape(entry.title)
            let artist = htmlEscape(entry.artist ?? "—")
            let album = htmlEscape(entry.album ?? "—")
            let trackId = htmlEscape(entry.plexRatingKey)
            let date = htmlEscape(df.string(from: entry.playedAt))
            let id = entry.id
            rows += """
            <tr id="row-\(id)">
              <td>\(title)</td>
              <td>\(artist)</td>
              <td>\(album)</td>
              <td class="track-id">\(trackId)</td>
              <td>\(date)</td>
              <td><button class="remove-btn" onclick="removeEntry(\(id))">Remove</button></td>
            </tr>
            """
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Plex Radio History</title>
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { background: #1a1a2e; color: #e0e0e0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; padding: 24px; }
          h1 { color: #00d4ff; font-size: 1.5rem; margin-bottom: 8px; }
          .meta { color: #888; font-size: 0.85rem; margin-bottom: 20px; }
          table { width: 100%; border-collapse: collapse; }
          th { background: #12122b; color: #00d4ff; text-align: left; padding: 10px 12px; cursor: pointer; user-select: none; white-space: nowrap; }
          th:hover { background: #1c1c3a; }
          th::after { content: " ⇅"; opacity: 0.4; font-size: 0.75em; }
          th.asc::after { content: " ↑"; opacity: 1; }
          th.desc::after { content: " ↓"; opacity: 1; }
          td { padding: 9px 12px; border-bottom: 1px solid #2a2a4a; vertical-align: middle; }
          tr:hover td { background: #1e1e38; }
          .remove-btn { background: #3a0a0a; border: 1px solid #7a1a1a; color: #ff7070; padding: 4px 10px; border-radius: 4px; cursor: pointer; font-size: 0.8rem; }
          .remove-btn:hover { background: #5a1a1a; }
          .empty { text-align: center; color: #555; padding: 40px; font-size: 1.1rem; }
          .track-id { color: #888; font-size: 0.82rem; font-variant-numeric: tabular-nums; }
        </style>
        </head>
        <body>
        <h1>Plex Radio History</h1>
        <div class="meta">Retention: \(interval.displayName) &nbsp;·&nbsp; \(count) track\(count == 1 ? "" : "s")</div>
        <table id="historyTable">
          <thead>
            <tr>
              <th onclick="sortTable(0)">Track</th>
              <th onclick="sortTable(1)">Artist</th>
              <th onclick="sortTable(2)">Album</th>
              <th onclick="sortTable(3)">Track ID</th>
              <th onclick="sortTable(4)">Played</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
          \(rows.isEmpty ? "<tr><td colspan=\"6\" class=\"empty\">No history yet.</td></tr>" : rows)
          </tbody>
        </table>
        <script>
        var sortCol = -1, sortAsc = true;
        function sortTable(col) {
          var table = document.getElementById('historyTable');
          var ths = table.querySelectorAll('th');
          var tbody = table.querySelector('tbody');
          var rows = Array.from(tbody.querySelectorAll('tr'));
          if (sortCol === col) { sortAsc = !sortAsc; } else { sortCol = col; sortAsc = true; }
          ths.forEach(function(th, i) { th.classList.remove('asc','desc'); });
          ths[col].classList.add(sortAsc ? 'asc' : 'desc');
          rows.sort(function(a, b) {
            var aText = a.cells[col] ? a.cells[col].innerText : '';
            var bText = b.cells[col] ? b.cells[col].innerText : '';
            return sortAsc ? aText.localeCompare(bText) : bText.localeCompare(aText);
          });
          rows.forEach(function(r) { tbody.appendChild(r); });
        }
        function removeEntry(id) {
          fetch('/radio-history/delete/' + id, {method: 'POST'})
            .then(function(r) { if (r.ok) { var row = document.getElementById('row-' + id); if (row) row.remove(); } });
        }
        </script>
        </body>
        </html>
        """
    }

    private func htmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
