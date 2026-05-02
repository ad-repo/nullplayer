import XCTest
import SQLite
@testable import NullPlayer

final class MediaLibraryStoreMigrationTests: XCTestCase {
    private var store: MediaLibraryStore!
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = MediaLibraryStore.makeForTesting()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaLibraryStoreMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        store?.close()
        store = nil

        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
            self.tempDirectoryURL = nil
        }

        try super.tearDownWithError()
    }

    func testV5ToV6MigrationAddsContentTypeAndBackfillsBySource() throws {
        let dbURL = tempDirectoryURL.appendingPathComponent("library-v5.sqlite")
        try seedLegacyPlayEventsTable(at: dbURL, withContentTypeColumn: false)

        do {
            let seedConnection = try Connection(dbURL.path)
            try insertLegacyPlayEvent(source: "local", into: seedConnection)
            try insertLegacyPlayEvent(source: "radio", into: seedConnection)
            try insertLegacyPlayEvent(source: "plex", into: seedConnection)
        }

        store.open(at: dbURL)
        let db = try XCTUnwrap(store.testDB)

        XCTAssertEqual(try db.scalar("PRAGMA user_version") as? Int64, 7)
        XCTAssertTrue(try table("play_events", hasColumn: "content_type", in: db))

        let rows = try db.prepare("SELECT source, content_type FROM play_events ORDER BY id").map {
            (($0[0] as? String) ?? "", ($0[1] as? String) ?? "")
        }

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].0, "local")
        XCTAssertEqual(rows[0].1, "music")
        XCTAssertEqual(rows[1].0, "radio")
        XCTAssertEqual(rows[1].1, "radio")
        XCTAssertEqual(rows[2].0, "plex")
        XCTAssertEqual(rows[2].1, "music")
    }

    func testV5ToV6MigrationDoesNotOverwriteExistingContentTypeValues() throws {
        let dbURL = tempDirectoryURL.appendingPathComponent("library-v5-existing-content-type.sqlite")
        try seedLegacyPlayEventsTable(at: dbURL, withContentTypeColumn: true)

        do {
            let seedConnection = try Connection(dbURL.path)
            try insertLegacyPlayEvent(source: "radio", contentType: "video", into: seedConnection)
            try insertLegacyPlayEvent(source: "local", contentType: "movie", into: seedConnection)
        }

        store.open(at: dbURL)
        let db = try XCTUnwrap(store.testDB)

        XCTAssertEqual(try db.scalar("PRAGMA user_version") as? Int64, 7)

        let rows = try db.prepare("SELECT source, content_type FROM play_events ORDER BY id").map {
            (($0[0] as? String) ?? "", ($0[1] as? String) ?? "")
        }

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].0, "radio")
        XCTAssertEqual(rows[0].1, "video")
        XCTAssertEqual(rows[1].0, "local")
        XCTAssertEqual(rows[1].1, "movie")
    }

    private func seedLegacyPlayEventsTable(at dbURL: URL, withContentTypeColumn: Bool) throws {
        let db = try Connection(dbURL.path)

        if withContentTypeColumn {
            try db.execute("""
                CREATE TABLE play_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    source TEXT NOT NULL,
                    content_type TEXT
                );
                """)
        } else {
            try db.execute("""
                CREATE TABLE play_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    source TEXT NOT NULL
                );
                """)
        }

        try db.run("PRAGMA user_version = 5")
    }

    private func insertLegacyPlayEvent(source: String, into db: Connection) throws {
        try db.run("INSERT INTO play_events (source) VALUES (?)", [source as Binding])
    }

    private func insertLegacyPlayEvent(source: String, contentType: String, into db: Connection) throws {
        try db.run(
            "INSERT INTO play_events (source, content_type) VALUES (?, ?)",
            [source as Binding, contentType as Binding]
        )
    }

    private func table(_ tableName: String, hasColumn columnName: String, in db: Connection) throws -> Bool {
        for row in try db.prepare("PRAGMA table_info(\(tableName))") {
            if (row[1] as? String) == columnName {
                return true
            }
        }
        return false
    }
}
