import Foundation
import SQLite

/// SQLite-backed storage for Internet Radio folder organization.
final class RadioStationFoldersStore {
    static let shared = RadioStationFoldersStore()

    private var db: Connection?

    private let foldersTable = Table("radio_folders")
    private let membershipsTable = Table("radio_station_folder_memberships")
    private let historyTable = Table("radio_station_play_history")

    private let colFolderID = Expression<String>("folder_id")
    private let colFolderName = Expression<String>("name")
    private let colCreatedAt = Expression<Double>("created_at")
    private let colStationURL = Expression<String>("station_url")
    private let colLastPlayedAt = Expression<Double>("last_played_at")

    private init() {
        setupDatabase()
    }

    private func setupDatabase() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            NSLog("RadioStationFoldersStore: Cannot locate Application Support directory")
            return
        }

        let dir = appSupport.appendingPathComponent("NullPlayer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let dbPath = dir.appendingPathComponent("radio_station_folders.db").path

        do {
            let connection = try Connection(dbPath)
            db = connection
            try createTablesIfNeeded(connection)
            NSLog("RadioStationFoldersStore: Database ready at %@", dbPath)
        } catch {
            NSLog("RadioStationFoldersStore: Failed to open database: %@", error.localizedDescription)
        }
    }

    private func createTablesIfNeeded(_ connection: Connection) throws {
        try connection.run(foldersTable.create(ifNotExists: true) { t in
            t.column(colFolderID, primaryKey: true)
            t.column(colFolderName)
            t.column(colCreatedAt)
        })

        try connection.run(membershipsTable.create(ifNotExists: true) { t in
            t.column(colFolderID)
            t.column(colStationURL)
            t.column(colCreatedAt)
            t.primaryKey(colFolderID, colStationURL)
        })
        try connection.run(
            "CREATE INDEX IF NOT EXISTS idx_radio_memberships_station_url ON radio_station_folder_memberships (station_url)"
        )

        try connection.run(historyTable.create(ifNotExists: true) { t in
            t.column(colStationURL, primaryKey: true)
            t.column(colLastPlayedAt)
        })
        try connection.run(
            "CREATE INDEX IF NOT EXISTS idx_radio_play_history_last_played_at ON radio_station_play_history (last_played_at)"
        )
    }

    func folders() -> [RadioUserFolder] {
        guard let db = db else { return [] }
        do {
            var result: [RadioUserFolder] = []
            for row in try db.prepare(foldersTable.order(colFolderName.asc)) {
                guard let id = UUID(uuidString: row[colFolderID]) else { continue }
                result.append(
                    RadioUserFolder(
                        id: id,
                        name: row[colFolderName],
                        createdAt: Date(timeIntervalSince1970: row[colCreatedAt])
                    )
                )
            }
            return result
        } catch {
            NSLog("RadioStationFoldersStore: Failed to fetch folders: %@", error.localizedDescription)
            return []
        }
    }

    @discardableResult
    func createFolder(name: String) -> RadioUserFolder? {
        guard let db = db else { return nil }
        let folder = RadioUserFolder(id: UUID(), name: name, createdAt: Date())
        do {
            try db.run(foldersTable.insert(
                colFolderID <- folder.id.uuidString,
                colFolderName <- folder.name,
                colCreatedAt <- folder.createdAt.timeIntervalSince1970
            ))
            return folder
        } catch {
            NSLog("RadioStationFoldersStore: Failed to create folder '%@': %@", name, error.localizedDescription)
            return nil
        }
    }

    @discardableResult
    func renameFolder(id: UUID, name: String) -> Bool {
        guard let db = db else { return false }
        do {
            let updated = try db.run(
                foldersTable.filter(colFolderID == id.uuidString).update(colFolderName <- name)
            )
            return updated > 0
        } catch {
            NSLog("RadioStationFoldersStore: Failed to rename folder %@: %@", id.uuidString, error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func deleteFolder(id: UUID) -> Bool {
        guard let db = db else { return false }
        do {
            try db.transaction {
                _ = try db.run(membershipsTable.filter(colFolderID == id.uuidString).delete())
                _ = try db.run(foldersTable.filter(colFolderID == id.uuidString).delete())
            }
            return true
        } catch {
            NSLog("RadioStationFoldersStore: Failed to delete folder %@: %@", id.uuidString, error.localizedDescription)
            return false
        }
    }

    func stationURLs(inFolder id: UUID) -> Set<String> {
        guard let db = db else { return [] }
        do {
            let query = membershipsTable
                .select(colStationURL)
                .filter(colFolderID == id.uuidString)
            return Set(try db.prepare(query).map { $0[colStationURL] })
        } catch {
            NSLog("RadioStationFoldersStore: Failed to fetch memberships for folder %@: %@", id.uuidString, error.localizedDescription)
            return []
        }
    }

    func folderIDs(containing stationURL: URL) -> Set<UUID> {
        guard let db = db else { return [] }
        do {
            let query = membershipsTable
                .select(colFolderID)
                .filter(colStationURL == stationURL.absoluteString)
            let ids = try db.prepare(query).compactMap { UUID(uuidString: $0[colFolderID]) }
            return Set(ids)
        } catch {
            NSLog("RadioStationFoldersStore: Failed to fetch folders for %@: %@", stationURL.absoluteString, error.localizedDescription)
            return []
        }
    }

    @discardableResult
    func addStationURL(_ stationURL: URL, toFolder id: UUID) -> Bool {
        guard let db = db else { return false }
        do {
            try db.run(membershipsTable.insert(
                or: .ignore,
                colFolderID <- id.uuidString,
                colStationURL <- stationURL.absoluteString,
                colCreatedAt <- Date().timeIntervalSince1970
            ))
            return true
        } catch {
            NSLog("RadioStationFoldersStore: Failed to add %@ to folder %@: %@",
                  stationURL.absoluteString, id.uuidString, error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func removeStationURL(_ stationURL: URL, fromFolder id: UUID) -> Bool {
        guard let db = db else { return false }
        do {
            let deleted = try db.run(
                membershipsTable
                    .filter(colFolderID == id.uuidString && colStationURL == stationURL.absoluteString)
                    .delete()
            )
            return deleted > 0
        } catch {
            NSLog("RadioStationFoldersStore: Failed to remove %@ from folder %@: %@",
                  stationURL.absoluteString, id.uuidString, error.localizedDescription)
            return false
        }
    }

    func removeStationURLEverywhere(_ stationURL: URL) {
        guard let db = db else { return }
        do {
            _ = try db.run(membershipsTable.filter(colStationURL == stationURL.absoluteString).delete())
            _ = try db.run(historyTable.filter(colStationURL == stationURL.absoluteString).delete())
        } catch {
            NSLog("RadioStationFoldersStore: Failed to purge station %@: %@", stationURL.absoluteString, error.localizedDescription)
        }
    }

    func moveStationURLReferences(from oldURL: URL, to newURL: URL) {
        guard oldURL != newURL, let db = db else { return }
        do {
            let folderIDs = membershipsTable
                .select(colFolderID)
                .filter(colStationURL == oldURL.absoluteString)

            for row in try db.prepare(folderIDs) {
                try db.run(membershipsTable.insert(
                    or: .ignore,
                    colFolderID <- row[colFolderID],
                    colStationURL <- newURL.absoluteString,
                    colCreatedAt <- Date().timeIntervalSince1970
                ))
            }
            _ = try db.run(membershipsTable.filter(colStationURL == oldURL.absoluteString).delete())

            let oldHistory = historyTable.filter(colStationURL == oldURL.absoluteString)
            if let existing = try db.pluck(oldHistory) {
                try db.run(historyTable.insert(
                    or: .replace,
                    colStationURL <- newURL.absoluteString,
                    colLastPlayedAt <- existing[colLastPlayedAt]
                ))
            }
            _ = try db.run(oldHistory.delete())
        } catch {
            NSLog("RadioStationFoldersStore: Failed moving URL refs %@ -> %@: %@",
                  oldURL.absoluteString, newURL.absoluteString, error.localizedDescription)
        }
    }

    func recordPlayed(_ stationURL: URL) {
        guard let db = db else { return }
        do {
            try db.run(historyTable.insert(
                or: .replace,
                colStationURL <- stationURL.absoluteString,
                colLastPlayedAt <- Date().timeIntervalSince1970
            ))
        } catch {
            NSLog("RadioStationFoldersStore: Failed to record play for %@: %@", stationURL.absoluteString, error.localizedDescription)
        }
    }

    func lastPlayedTimestampsByURL() -> [String: Date] {
        guard let db = db else { return [:] }
        do {
            var result: [String: Date] = [:]
            for row in try db.prepare(historyTable) {
                result[row[colStationURL]] = Date(timeIntervalSince1970: row[colLastPlayedAt])
            }
            return result
        } catch {
            NSLog("RadioStationFoldersStore: Failed loading play history: %@", error.localizedDescription)
            return [:]
        }
    }
}
