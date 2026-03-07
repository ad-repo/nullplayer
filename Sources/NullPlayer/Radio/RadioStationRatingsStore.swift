import Foundation
import SQLite

/// SQLite-backed storage for Internet Radio station ratings.
final class RadioStationRatingsStore {
    static let shared = RadioStationRatingsStore()

    private var db: Connection?

    private let table = Table("radio_station_ratings")
    private let colStationURL = Expression<String>("station_url")
    private let colRating = Expression<Int>("rating")
    private let colUpdatedAt = Expression<Double>("updated_at")

    private init() {
        setupDatabase()
    }

    private func setupDatabase() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            NSLog("RadioStationRatingsStore: Cannot locate Application Support directory")
            return
        }
        let dir = appSupport.appendingPathComponent("NullPlayer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("radio_station_ratings.db").path

        do {
            let connection = try Connection(dbPath)
            db = connection
            try createTableIfNeeded(connection)
            NSLog("RadioStationRatingsStore: Database ready at %@", dbPath)
        } catch {
            NSLog("RadioStationRatingsStore: Failed to open database: %@", error.localizedDescription)
        }
    }

    private func createTableIfNeeded(_ connection: Connection) throws {
        try connection.run(table.create(ifNotExists: true) { t in
            t.column(colStationURL, primaryKey: true)
            t.column(colRating)
            t.column(colUpdatedAt)
        })
        try connection.run(
            "CREATE INDEX IF NOT EXISTS idx_radio_station_ratings_updated_at ON radio_station_ratings (updated_at)"
        )
    }

    private func clamp(_ rating: Int) -> Int {
        min(5, max(0, rating))
    }

    func rating(for stationURL: URL) -> Int {
        guard let db = db else { return 0 }
        do {
            let query = table.select(colRating).filter(colStationURL == stationURL.absoluteString)
            guard let row = try db.pluck(query) else { return 0 }
            return clamp(row[colRating])
        } catch {
            NSLog("RadioStationRatingsStore: Failed to fetch rating for %@: %@", stationURL.absoluteString, error.localizedDescription)
            return 0
        }
    }

    func setRating(_ rating: Int, for stationURL: URL) {
        guard let db = db else { return }
        let clamped = clamp(rating)
        do {
            if clamped == 0 {
                try db.run(table.filter(colStationURL == stationURL.absoluteString).delete())
                return
            }
            try db.run(table.insert(
                or: .replace,
                colStationURL <- stationURL.absoluteString,
                colRating <- clamped,
                colUpdatedAt <- Date().timeIntervalSince1970
            ))
        } catch {
            NSLog("RadioStationRatingsStore: Failed to set rating for %@: %@", stationURL.absoluteString, error.localizedDescription)
        }
    }

    func moveRating(from oldURL: URL, to newURL: URL) {
        guard oldURL != newURL else { return }
        let existing = rating(for: oldURL)
        if existing > 0 {
            setRating(existing, for: newURL)
        }
        removeRating(for: oldURL)
    }

    func removeRating(for stationURL: URL) {
        guard let db = db else { return }
        do {
            try db.run(table.filter(colStationURL == stationURL.absoluteString).delete())
        } catch {
            NSLog("RadioStationRatingsStore: Failed to remove rating for %@: %@", stationURL.absoluteString, error.localizedDescription)
        }
    }
}
