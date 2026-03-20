import Foundation
import SQLite

/// SQLite-backed storage for projectM preset ratings.
/// Ratings are stored on a 0-5 scale (0 = unrated/cleared).
final class ProjectMPresetRatingsStore {
    static let shared = ProjectMPresetRatingsStore()

    private var db: Connection?
    private let queue = DispatchQueue(label: "NullPlayer.ProjectMPresetRatingsStore")

    private let table = Table("projectm_preset_ratings")
    private let colPresetPath = Expression<String>("preset_path")
    private let colPresetName = Expression<String>("preset_name")
    private let colRating = Expression<Int>("rating")
    private let colUpdatedAt = Expression<Double>("updated_at")

    private init() {
        setupDatabase()
    }

    private func setupDatabase() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            NSLog("ProjectMPresetRatingsStore: Cannot locate Application Support directory")
            return
        }

        let dir = appSupport.appendingPathComponent("NullPlayer")
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let dbPath = dir.appendingPathComponent("projectm_preset_ratings.db").path

        do {
            let connection = try Connection(dbPath)
            db = connection
            try createTableIfNeeded(connection)
            NSLog("ProjectMPresetRatingsStore: Database ready at %@", dbPath)
        } catch {
            NSLog("ProjectMPresetRatingsStore: Failed to open database: %@", error.localizedDescription)
        }
    }

    private func createTableIfNeeded(_ connection: Connection) throws {
        try connection.run(table.create(ifNotExists: true) { t in
            t.column(colPresetPath, primaryKey: true)
            t.column(colPresetName)
            t.column(colRating)
            t.column(colUpdatedAt)
        })
        try connection.run(
            "CREATE INDEX IF NOT EXISTS idx_projectm_preset_ratings_updated_at ON projectm_preset_ratings (updated_at)"
        )
    }

    private func clamp(_ rating: Int) -> Int {
        min(5, max(0, rating))
    }

    private func normalizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    func rating(forPresetPath path: String) -> Int {
        let normalized = normalizedPath(path)
        guard !normalized.isEmpty else { return 0 }

        return queue.sync {
            guard let db = db else { return 0 }
            do {
                let query = table.select(colRating).filter(colPresetPath == normalized)
                guard let row = try db.pluck(query) else { return 0 }
                return clamp(row[colRating])
            } catch {
                NSLog("ProjectMPresetRatingsStore: Failed to fetch rating for %@: %@", normalized, error.localizedDescription)
                return 0
            }
        }
    }

    func ratings(forPresetPaths presetPaths: [String]) -> [String: Int] {
        let pathSet = Set(presetPaths.map(normalizedPath).filter { !$0.isEmpty })
        guard !pathSet.isEmpty else { return [:] }

        return queue.sync {
            guard let db = db else { return [:] }
            do {
                var result: [String: Int] = [:]
                for row in try db.prepare(table.select(colPresetPath, colRating)) {
                    let path = row[colPresetPath]
                    guard pathSet.contains(path) else { continue }
                    result[path] = clamp(row[colRating])
                }
                return result
            } catch {
                NSLog("ProjectMPresetRatingsStore: Failed to fetch preset ratings map: %@", error.localizedDescription)
                return [:]
            }
        }
    }

    func setRating(_ rating: Int, forPresetPath path: String, presetName: String) {
        let normalized = normalizedPath(path)
        guard !normalized.isEmpty else { return }
        let clamped = clamp(rating)

        queue.sync {
            guard let db = db else { return }
            do {
                if clamped == 0 {
                    try db.run(table.filter(colPresetPath == normalized).delete())
                    return
                }
                try db.run(table.insert(
                    or: .replace,
                    colPresetPath <- normalized,
                    colPresetName <- presetName,
                    colRating <- clamped,
                    colUpdatedAt <- Date().timeIntervalSince1970
                ))
            } catch {
                NSLog("ProjectMPresetRatingsStore: Failed to set rating for %@: %@", normalized, error.localizedDescription)
            }
        }
    }
}
