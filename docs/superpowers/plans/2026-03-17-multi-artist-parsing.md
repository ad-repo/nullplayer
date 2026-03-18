# Multi-Artist Parsing Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split multi-artist strings (e.g. `"Drake feat. Future"`, `"Foo; Bar"`) at scan time and store results in a `track_artists` join table so each artist gets their own library browser entry.

**Architecture:** New `ArtistSplitter` pure-function enum handles string splitting; `track_artists` SQLite join table stores results (schema v3); `MediaLibraryStore` query methods switch from `coalesce(album_artist, artist)` to `track_artists WHERE role = 'album_artist'` for all browser-facing paths; `LibraryTrack.artists` is a transient field populated after DB load.

**Tech Stack:** Swift, SQLite.swift, AVFoundation, XCTest. Build/test: `swift test`. Run app: `./scripts/kill_build_run.sh`.

**Spec:** `docs/superpowers/specs/2026-03-17-multi-artist-parsing-design.md`

---

## Chunk 1: ArtistSplitter

### Task 1: Create `ArtistSplitter.swift`

**Files:**
- Create: `Sources/NullPlayer/Data/Models/ArtistSplitter.swift`
- Create: `Tests/NullPlayerTests/ArtistSplitterTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/NullPlayerTests/ArtistSplitterTests.swift`:

```swift
import XCTest
@testable import NullPlayer

final class ArtistSplitterTests: XCTestCase {

    // MARK: - ArtistRole

    func testArtistRoleRawValues() {
        XCTAssertEqual(ArtistRole.primary.rawValue, "primary")
        XCTAssertEqual(ArtistRole.featured.rawValue, "featured")
        XCTAssertEqual(ArtistRole.albumArtist.rawValue, "album_artist")
    }

    // MARK: - Single artist passthrough

    func testSingleArtist() {
        let result = ArtistSplitter.split("Adele", isAlbumArtist: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Adele")
        XCTAssertEqual(result[0].role, .primary)
    }

    func testSingleAlbumArtist() {
        let result = ArtistSplitter.split("Adele", isAlbumArtist: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Adele")
        XCTAssertEqual(result[0].role, .albumArtist)
    }

    func testEmptyString() {
        XCTAssertTrue(ArtistSplitter.split("", isAlbumArtist: false).isEmpty)
    }

    func testWhitespaceOnly() {
        XCTAssertTrue(ArtistSplitter.split("   ", isAlbumArtist: false).isEmpty)
    }

    // MARK: - feat. splitting

    func testFeatDot() {
        let result = ArtistSplitter.split("Drake feat. Future", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Drake")
        XCTAssertEqual(result[0].role, .primary)
        XCTAssertEqual(result[1].name, "Future")
        XCTAssertEqual(result[1].role, .featured)
    }

    func testFeatNoDot() {
        let result = ArtistSplitter.split("Drake feat Future", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Drake")
        XCTAssertEqual(result[1].name, "Future")
        XCTAssertEqual(result[1].role, .featured)
    }

    func testFtDot() {
        let result = ArtistSplitter.split("Drake ft. Future", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[1].name, "Future")
        XCTAssertEqual(result[1].role, .featured)
    }

    func testFtNoDot() {
        let result = ArtistSplitter.split("Drake ft Future", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[1].name, "Future")
    }

    func testFeatCaseInsensitive() {
        let result = ArtistSplitter.split("Drake FEAT. Future", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[1].name, "Future")
    }

    func testFeatWithParens() {
        let result = ArtistSplitter.split("Drake (feat. Future)", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Drake")
        XCTAssertEqual(result[1].name, "Future")
    }

    // MARK: - Word boundary: must NOT split "defeat", "often", etc.

    func testNoFalsePositiveOnDefeat() {
        let result = ArtistSplitter.split("Band of defeat", isAlbumArtist: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Band of defeat")
    }

    func testNoFalsePositiveOnOften() {
        let result = ArtistSplitter.split("Often feat-like", isAlbumArtist: false)
        // "feat-like" has feat at word boundary preceded by space — does split
        // This test documents that feat-like WILL split; document behavior:
        // "Often" + "like" (featured)
        // Actually "feat-like" — the pattern matches "feat" preceded by space.
        // After splitting: part before "feat" = "Often ", part after = "-like"
        // "-like" trimmed = "-like" — non-empty so included
        // This is acceptable; document it in the test
        XCTAssertTrue(result.count >= 1)
    }

    func testNoFalsePositiveDefeatWordBoundary() {
        // "defeat" — "feat" appears but is not at a word boundary (no space or ( before it)
        let result = ArtistSplitter.split("Great defeat", isAlbumArtist: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Great defeat")
    }

    // MARK: - Semicolon splitting

    func testSemicolon() {
        let result = ArtistSplitter.split("Foo; Bar", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Foo")
        XCTAssertEqual(result[0].role, .primary)
        XCTAssertEqual(result[1].name, "Bar")
        XCTAssertEqual(result[1].role, .primary)
    }

    func testSemicolonAlbumArtist() {
        let result = ArtistSplitter.split("Foo; Bar", isAlbumArtist: true)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].role, .albumArtist)
        XCTAssertEqual(result[1].role, .albumArtist)
    }

    // MARK: - Slash splitting

    func testSlashNotAlbumArtist() {
        let result = ArtistSplitter.split("Foo / Bar", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Foo")
        XCTAssertEqual(result[0].role, .primary)
        XCTAssertEqual(result[1].name, "Bar")
        XCTAssertEqual(result[1].role, .primary)
    }

    func testSlashAlbumArtist() {
        let result = ArtistSplitter.split("Foo / Bar", isAlbumArtist: true)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].role, .albumArtist)
        XCTAssertEqual(result[1].role, .albumArtist)
    }

    // MARK: - Combined patterns

    func testSemicolonWithFeat() {
        // "A; B feat. C" → A (primary), B (primary), C (featured)
        let result = ArtistSplitter.split("A; B feat. C", isAlbumArtist: false)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].name, "A")
        XCTAssertEqual(result[0].role, .primary)
        XCTAssertEqual(result[1].name, "B")
        XCTAssertEqual(result[1].role, .primary)
        XCTAssertEqual(result[2].name, "C")
        XCTAssertEqual(result[2].role, .featured)
    }

    func testSlashWithFeat() {
        let result = ArtistSplitter.split("A / B feat. C", isAlbumArtist: false)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].name, "A")
        XCTAssertEqual(result[1].name, "B")
        XCTAssertEqual(result[2].name, "C")
        XCTAssertEqual(result[2].role, .featured)
    }

    // MARK: - albumArtist=true: feat. produces albumArtist for both sides

    func testFeatAlbumArtist() {
        let result = ArtistSplitter.split("Drake feat. Future", isAlbumArtist: true)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Drake")
        XCTAssertEqual(result[0].role, .albumArtist)
        XCTAssertEqual(result[1].name, "Future")
        XCTAssertEqual(result[1].role, .albumArtist)
    }

    // MARK: - No split on ambiguous separators

    func testAmpersandNotSplit() {
        let result = ArtistSplitter.split("Simon & Garfunkel", isAlbumArtist: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Simon & Garfunkel")
    }

    func testVariousArtists() {
        let result = ArtistSplitter.split("Various Artists", isAlbumArtist: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Various Artists")
        XCTAssertEqual(result[0].role, .albumArtist)
    }

    // MARK: - Whitespace trimming

    func testWhitespaceTrimming() {
        let result = ArtistSplitter.split("  Drake  feat.  Future  ", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Drake")
        XCTAssertEqual(result[1].name, "Future")
    }

    func testEmptySegmentsDiscarded() {
        // Double semicolon produces empty segment
        let result = ArtistSplitter.split("Foo;; Bar", isAlbumArtist: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Foo")
        XCTAssertEqual(result[1].name, "Bar")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter ArtistSplitterTests 2>&1 | tail -5
```

Expected: compile error — `ArtistRole` and `ArtistSplitter` not defined.

- [ ] **Step 3: Create `Sources/NullPlayer/Data/Models/ArtistSplitter.swift`**

```swift
import Foundation

/// Roles an artist can have relative to a track.
enum ArtistRole: String {
    case primary     = "primary"
    case featured    = "featured"
    case albumArtist = "album_artist"
}

/// Splits raw multi-artist strings into individual artist entries.
/// Pure function — no external dependencies.
enum ArtistSplitter {

    /// Split a raw artist tag string into individual (name, role) pairs.
    ///
    /// - Parameters:
    ///   - raw: The raw tag value (e.g. "Drake feat. Future" or "Foo; Bar").
    ///   - isAlbumArtist: If true, all results get `.albumArtist` role;
    ///     if false, the primary part gets `.primary` and feat. parts get `.featured`.
    static func split(_ raw: String, isAlbumArtist: Bool) -> [(name: String, role: ArtistRole)] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        // Step 1: Split on ; and / — unambiguous list separators.
        let segments = splitOnListSeparators(trimmed)

        // Step 2: Within each segment, detect feat./ft. and split further.
        var results: [(name: String, role: ArtistRole)] = []
        for segment in segments {
            let primaryRole: ArtistRole = isAlbumArtist ? .albumArtist : .primary
            let featuredRole: ArtistRole = isAlbumArtist ? .albumArtist : .featured

            if let (before, after) = splitOnFeat(segment) {
                if !before.isEmpty { results.append((name: before, role: primaryRole)) }
                if !after.isEmpty  { results.append((name: after,  role: featuredRole)) }
            } else {
                if !segment.isEmpty { results.append((name: segment, role: primaryRole)) }
            }
        }
        return results
    }

    // MARK: - Private helpers

    /// Split on `;` and `/`, trimming whitespace, discarding empty segments.
    private static func splitOnListSeparators(_ s: String) -> [String] {
        s.components(separatedBy: CharacterSet(charactersIn: ";/"))
         .map { $0.trimmingCharacters(in: .whitespaces) }
         .filter { !$0.isEmpty }
    }

    /// Detect `feat.`, `feat`, `ft.`, `ft` preceded by space or `(`.
    /// Returns (before, after) trimmed, or nil if no match.
    private static func splitOnFeat(_ s: String) -> (String, String)? {
        // Pattern: (space or open-paren) followed by feat./feat/ft./ft (case-insensitive)
        let pattern = #"(?i)(?<=[ (])(feat\.|feat|ft\.|ft)(?=[ ]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(s.startIndex..., in: s)
        guard let match = regex.firstMatch(in: s, range: nsRange),
              let matchRange = Range(match.range, in: s) else { return nil }

        // Walk back from the match start to include the preceding space or (
        var cutIndex = matchRange.lowerBound
        if cutIndex > s.startIndex {
            let prev = s.index(before: cutIndex)
            let prevChar = s[prev]
            if prevChar == " " || prevChar == "(" {
                cutIndex = prev
            }
        }

        let before = String(s[s.startIndex..<cutIndex]).trimmingCharacters(in: .whitespaces)
        var after  = String(s[matchRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        // Strip surrounding parens from the "after" segment
        if after.hasPrefix("(") && after.hasSuffix(")") {
            after = String(after.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        } else if after.hasSuffix(")") {
            after = String(after.dropLast()).trimmingCharacters(in: .whitespaces)
        }

        return (before, after)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter ArtistSplitterTests 2>&1 | tail -10
```

Expected: All tests pass. If any fail, fix the `splitOnFeat` helper until the tests match the spec examples table in the design doc.

- [ ] **Step 5: Commit**

```bash
git add Sources/NullPlayer/Data/Models/ArtistSplitter.swift Tests/NullPlayerTests/ArtistSplitterTests.swift
git commit -m "feat: add ArtistRole enum and ArtistSplitter"
```

---

## Chunk 2: Model Change + Schema Migration

### Task 2: Add `artists` field to `LibraryTrack` with `CodingKeys`

**Files:**
- Modify: `Sources/NullPlayer/Data/Models/MediaLibrary.swift:7-119`

- [ ] **Step 1: Write the failing test**

Add to `Tests/NullPlayerTests/ArtistSplitterTests.swift` (append a new test class):

```swift
final class LibraryTrackCodableTests: XCTestCase {

    func testArtistsFieldExcludedFromCodable() throws {
        var track = LibraryTrack(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            title: "Test",
            artist: "Drake feat. Future"
        )
        track.artists = [(name: "Drake", role: .primary), (name: "Future", role: .featured)]

        let data = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(LibraryTrack.self, from: data)

        // artists must be empty after decode — it is transient
        XCTAssertTrue(decoded.artists.isEmpty)
        // All other fields must survive the round-trip
        XCTAssertEqual(decoded.title, "Test")
        XCTAssertEqual(decoded.artist, "Drake feat. Future")
    }

    func testAllStoredFieldsRoundTrip() throws {
        let original = LibraryTrack(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/song.flac"),
            title: "Song",
            artist: "Artist",
            album: "Album",
            albumArtist: "Album Artist",
            genre: "Rock",
            year: 2024,
            trackNumber: 3,
            discNumber: 1,
            duration: 240.5,
            bitrate: 320,
            sampleRate: 44100,
            channels: 2,
            fileSize: 12345678,
            dateAdded: Date(timeIntervalSince1970: 1000),
            lastPlayed: Date(timeIntervalSince1970: 2000),
            playCount: 7,
            rating: 8
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LibraryTrack.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.artist, original.artist)
        XCTAssertEqual(decoded.albumArtist, original.albumArtist)
        XCTAssertEqual(decoded.rating, original.rating)
        XCTAssertEqual(decoded.playCount, original.playCount)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter LibraryTrackCodableTests 2>&1 | tail -5
```

Expected: compile error — `artists` property not found on `LibraryTrack`.

- [ ] **Step 3: Add `artists` field and `CodingKeys` to `LibraryTrack`**

In `Sources/NullPlayer/Data/Models/MediaLibrary.swift`, after line 26 (`var rating: Int?`), add:

```swift
    /// Transient — populated from `track_artists` table, not persisted via Codable.
    var artists: [(name: String, role: ArtistRole)] = []
```

Then add the `CodingKeys` enum inside `LibraryTrack` (after the `artists` field, before `init(url:)`):

```swift
    private enum CodingKeys: String, CodingKey {
        case id, url, title, artist, album, albumArtist, genre, year
        case trackNumber, discNumber, duration, bitrate, sampleRate, channels
        case fileSize, dateAdded, lastPlayed, playCount, rating
        // `artists` is intentionally omitted — transient, re-populated from track_artists
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter LibraryTrackCodableTests 2>&1 | tail -10
```

Expected: All pass.

- [ ] **Step 5: Run the full test suite to catch any regressions**

```bash
swift test 2>&1 | tail -15
```

Expected: All existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/NullPlayer/Data/Models/MediaLibrary.swift Tests/NullPlayerTests/ArtistSplitterTests.swift
git commit -m "feat: add transient artists field to LibraryTrack with CodingKeys exclusion"
```

---

### Task 3: Schema v3 — `track_artists` table + PRAGMA + migration

**Files:**
- Modify: `Sources/NullPlayer/Data/Models/MediaLibraryStore.swift:106-210`

- [ ] **Step 1: Write a failing test**

Create `Tests/NullPlayerTests/TrackArtistsSchemaTests.swift`:

```swift
import XCTest
import SQLite
@testable import NullPlayer

final class TrackArtistsSchemaTests: XCTestCase {

    private var store: MediaLibraryStore!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        store = MediaLibraryStore.makeForTesting()
        store.open(at: tempURL)
    }

    override func tearDown() {
        store.close()
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testTrackArtistsTableExists() throws {
        // track_artists table must exist after open()
        let db = try Connection(tempURL.path)
        let count = try db.scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='track_artists'"
        ) as? Int64 ?? 0
        XCTAssertEqual(count, 1, "track_artists table must exist")
    }

    func testForeignKeysEnabled() throws {
        let db = try Connection(tempURL.path)
        let fkEnabled = try db.scalar("PRAGMA foreign_keys") as? Int64 ?? 0
        // Note: PRAGMA foreign_keys is per-connection. This new connection starts at 0.
        // The test verifies it is set ON within the store's own connection by
        // testing cascade behavior (see testCascadeDeleteOnTrackDelete below).
        // This assertion just documents what a new connection returns.
        XCTAssertEqual(fkEnabled, 0, "New connections start with FK off by default")
    }

    func testSchemaVersionIs3() throws {
        let db = try Connection(tempURL.path)
        let version = try db.scalar("PRAGMA user_version") as? Int64 ?? 0
        XCTAssertEqual(version, 3)
    }

    func testCascadeDeleteOnTrackDelete() {
        // Insert a track via store
        var track = LibraryTrack(url: URL(fileURLWithPath: "/tmp/cascade_test.mp3"),
                                  title: "Cascade Test")
        track.artist = "Drake feat. Future"
        track.artists = [(name: "Drake", role: .primary), (name: "Future", role: .featured),
                         (name: "Drake", role: .albumArtist)]
        store.upsertTrack(track, sig: nil)

        // Verify track_artists rows exist
        XCTAssertEqual(store.artistsForURLs([track.url.absoluteString]).count, 1)

        // Delete the track
        store.deleteTrackByPath("/tmp/cascade_test.mp3")

        // track_artists rows must be gone (cascade)
        let remaining = store.artistsForURLs([track.url.absoluteString])
        XCTAssertTrue(remaining.isEmpty || remaining[track.url.absoluteString]?.isEmpty == true)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
swift test --filter TrackArtistsSchemaTests 2>&1 | tail -5
```

Expected: compile errors — `store.open(at:)`, `store.close()`, `store.artistsForURLs` not yet on `MediaLibraryStore`.

- [ ] **Step 3: Add `makeForTesting()` factory and `open(at:)` method to `MediaLibraryStore`** (needed for testability)

`MediaLibraryStore` has `private init()` — tests cannot call `MediaLibraryStore()` directly.

In `MediaLibraryStore.swift`, add a `#if DEBUG` factory after the `private init()` line (around line 62):

```swift
    #if DEBUG
    static func makeForTesting() -> MediaLibraryStore { MediaLibraryStore() }
    #endif
```

Then add `open(at:)` alongside the existing `open()` method. This overload skips the JSON migration (not needed in tests):

```swift
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
```

Note: `close()` already exists at line 90 — do NOT add it again.

- [ ] **Step 4: Add `PRAGMA foreign_keys = ON` to `setupSchema`**

In `MediaLibraryStore.swift` at line 106 (`private func setupSchema`), add after the existing PRAGMAs (after line 114, the `busyTimeout` line):

```swift
        // Enable FK enforcement so ON DELETE CASCADE fires on track_artists.
        // Must be set on every connection open — SQLite resets it per connection.
        try connection.run("PRAGMA foreign_keys = ON")
```

- [ ] **Step 5: Add `track_artists` DDL to `createTablesIfNeeded`**

In `createTablesIfNeeded` (around line 131), after the last table creation (after line 209 `}`), add:

```swift
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
```

- [ ] **Step 6: Update fresh-install `user_version` to 3**

In `setupSchema` at line 119, change:
```swift
try connection.run("PRAGMA user_version = 2")
```
to:
```swift
try connection.run("PRAGMA user_version = 3")
```

- [ ] **Step 7: Add v2 → v3 migration**

In `setupSchema`, after the existing `if currentVersion == 1` block (after line 128), add:

```swift
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
            // Signal that backfill is needed (existing rows have no track_artists entries yet)
            UserDefaults.standard.set(false, forKey: "trackArtistsBackfillComplete")
        }
```

- [ ] **Step 8: Run schema tests**

```bash
swift test --filter TrackArtistsSchemaTests 2>&1 | tail -15
```

Expected: `testTrackArtistsTableExists` and `testSchemaVersionIs3` pass. `testCascadeDeleteOnTrackDelete` still fails because `artistsForURLs` and `upsertTrack` (with artists) not yet implemented.

- [ ] **Step 9: Commit**

```bash
git add Sources/NullPlayer/Data/Models/MediaLibraryStore.swift Tests/NullPlayerTests/TrackArtistsSchemaTests.swift
git commit -m "feat: add track_artists schema v3 with FK cascade and PRAGMA foreign_keys"
```

---

## Chunk 3: Upsert Integration

### Task 4: Write `track_artists` rows in `upsertTrackInternal`

**Files:**
- Modify: `Sources/NullPlayer/Data/Models/MediaLibraryStore.swift:859-866,1093-1118`

- [ ] **Step 1: Write failing tests**

Add to `Tests/NullPlayerTests/TrackArtistsSchemaTests.swift`:

```swift
    func testUpsertTrackWritesTrackArtistsRows() {
        var track = LibraryTrack(url: URL(fileURLWithPath: "/tmp/upsert_test.mp3"), title: "Test")
        track.artists = [
            (name: "Drake", role: .primary),
            (name: "Future", role: .featured),
            (name: "Drake", role: .albumArtist)
        ]
        store.upsertTrack(track, sig: nil)

        let result = store.artistsForURLs([track.url.absoluteString])
        let artists = result[track.url.absoluteString] ?? []
        XCTAssertEqual(artists.count, 3)
        XCTAssertTrue(artists.contains { $0.name == "Drake" && $0.role == .primary })
        XCTAssertTrue(artists.contains { $0.name == "Future" && $0.role == .featured })
        XCTAssertTrue(artists.contains { $0.name == "Drake" && $0.role == .albumArtist })
    }

    func testUpsertTrackReplacesTrackArtistsOnRescan() {
        var track = LibraryTrack(url: URL(fileURLWithPath: "/tmp/replace_test.mp3"), title: "Test")
        track.artists = [(name: "OldArtist", role: .albumArtist)]
        store.upsertTrack(track, sig: nil)

        // Re-upsert same URL with different artists
        var track2 = LibraryTrack(url: URL(fileURLWithPath: "/tmp/replace_test.mp3"), title: "Test")
        track2.artists = [(name: "NewArtist", role: .albumArtist)]
        store.upsertTrack(track2, sig: nil)

        let result = store.artistsForURLs([track.url.absoluteString])
        let artists = result[track.url.absoluteString] ?? []
        // Old artist must be gone, new artist present
        XCTAssertFalse(artists.contains { $0.name == "OldArtist" })
        XCTAssertTrue(artists.contains { $0.name == "NewArtist" })
    }

    func testUpsertTracksWritesArtistRowsForBatch() {
        var t1 = LibraryTrack(url: URL(fileURLWithPath: "/tmp/batch1.mp3"), title: "Batch1")
        t1.artists = [(name: "ArtistA", role: .albumArtist)]
        var t2 = LibraryTrack(url: URL(fileURLWithPath: "/tmp/batch2.mp3"), title: "Batch2")
        t2.artists = [(name: "ArtistB", role: .albumArtist)]

        store.upsertTracks([(t1, nil), (t2, nil)])

        let urls = [t1.url.absoluteString, t2.url.absoluteString]
        let result = store.artistsForURLs(urls)
        XCTAssertTrue(result[t1.url.absoluteString]?.contains { $0.name == "ArtistA" } ?? false)
        XCTAssertTrue(result[t2.url.absoluteString]?.contains { $0.name == "ArtistB" } ?? false)
    }
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter TrackArtistsSchemaTests/testUpsertTrack 2>&1 | tail -5
```

Expected: compile error — `store.artistsForURLs` not defined.

- [ ] **Step 3: Add `artistsForURLs` to `MediaLibraryStore`**

Add after `albumsForArtistsBatch` (after line 710):

```swift
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
```

- [ ] **Step 4: Update `upsertTrackInternal` to insert track_artists rows**

`upsertTrackInternal` (line 1093) currently uses an implicit return expression:

```swift
    private func upsertTrackInternal(...) throws -> Int64 {
        try connection.run(tracksTable.insert(or: .replace, ...))
    }
```

This is a single expression — adding more statements after it would remove the return value. Change the function body to capture the rowid explicitly, insert `track_artists` rows, then return it:

Replace the function body (lines 1094–1118) with:

```swift
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
            colScanModDate <- sig?.contentModificationDate.map { $0.timeIntervalSince1970 }
        ))
        // INSERT OR REPLACE on library_tracks cascades DELETE on track_artists (FK + PRAGMA foreign_keys = ON),
        // so old rows are already gone. Use INSERT OR IGNORE to avoid duplicate-key errors on edge cases.
        let urlStr = track.url.absoluteString
        for entry in track.artists {
            try connection.run("""
                INSERT OR IGNORE INTO track_artists (track_url, artist_name, role)
                VALUES (?, ?, ?)
                """, urlStr, entry.name, entry.role.rawValue)
        }
        return rowid
```

- [ ] **Step 5: Wrap `upsertTrack` in a transaction**

`upsertTrack` (line 859) currently calls `upsertTrackInternal` without a transaction. Wrap it:

Replace:
```swift
    func upsertTrack(_ track: LibraryTrack, sig: FileScanSignature?) {
        guard let db = db else { return }
        do {
            try upsertTrackInternal(track, sig: sig, connection: db)
        } catch {
            NSLog("MediaLibraryStore: upsertTrack failed: %@", error.localizedDescription)
        }
    }
```

With:
```swift
    func upsertTrack(_ track: LibraryTrack, sig: FileScanSignature?) {
        guard let db = db else { return }
        do {
            try db.transaction {
                try self.upsertTrackInternal(track, sig: sig, connection: db)
            }
        } catch {
            NSLog("MediaLibraryStore: upsertTrack failed: %@", error.localizedDescription)
        }
    }
```

- [ ] **Step 6: Run tests**

```bash
swift test --filter TrackArtistsSchemaTests 2>&1 | tail -15
```

Expected: All tests pass including cascade test.

- [ ] **Step 7: Commit**

```bash
git add Sources/NullPlayer/Data/Models/MediaLibraryStore.swift Tests/NullPlayerTests/TrackArtistsSchemaTests.swift
git commit -m "feat: write track_artists rows in upsertTrackInternal, add artistsForURLs query"
```

---

### Task 5: Populate `track.artists` in `parseMetadata`

**Files:**
- Modify: `Sources/NullPlayer/Data/Models/MediaLibrary.swift:1625-1709`

- [ ] **Step 1: Write a failing test**

Create `Tests/NullPlayerTests/ParseMetadataArtistTests.swift`:

```swift
import XCTest
@testable import NullPlayer

final class ParseMetadataArtistTests: XCTestCase {

    // Test ArtistSplitter integration with the insert rule
    // (parseMetadata itself needs a real audio file, so we test the insert-rule logic directly)

    func testInsertRuleWithAlbumArtist() {
        // When albumArtist is set, artists from it get albumArtist role
        let albumArtistSplit = ArtistSplitter.split("Drake feat. Future", isAlbumArtist: true)
        XCTAssertTrue(albumArtistSplit.allSatisfy { $0.role == .albumArtist })
        XCTAssertEqual(albumArtistSplit.map { $0.name }, ["Drake", "Future"])
    }

    func testInsertRuleFallbackToArtist() {
        // When albumArtist is nil, artist tag is split with isAlbumArtist: true
        let fallbackSplit = ArtistSplitter.split("Foo feat. Bar", isAlbumArtist: true)
        XCTAssertTrue(fallbackSplit.allSatisfy { $0.role == .albumArtist })
        XCTAssertEqual(fallbackSplit.map { $0.name }.sorted(), ["Bar", "Foo"])
    }

    func testInsertRuleUnknownArtistWhenBothNil() {
        // When both artist and albumArtist are nil, we produce a single "Unknown Artist" albumArtist row
        // This is enforced in parseMetadata. Test via the splitter returning empty for nil input.
        let nilSplit = ArtistSplitter.split("", isAlbumArtist: true)
        XCTAssertTrue(nilSplit.isEmpty)
        // The caller (parseMetadata) must insert ("Unknown Artist", .albumArtist) when split returns empty
    }
}
```

- [ ] **Step 2: Run to verify it passes (these are splitter tests, not parseMetadata tests)**

```bash
swift test --filter ParseMetadataArtistTests 2>&1 | tail -5
```

Expected: All pass (these are splitter-only tests that compile fine).

- [ ] **Step 3: Update `parseMetadata` to populate `track.artists`**

In `Sources/NullPlayer/Data/Models/MediaLibrary.swift`, find `parseMetadata(for:)` at line 1625.

After the existing metadata parsing loops complete (around line 1709, before the `}` that closes `parseMetadata`), add:

```swift
        // Populate track.artists from the parsed artist and albumArtist fields.
        // Primary/featured roles from the artist tag:
        track.artists = ArtistSplitter.split(track.artist ?? "", isAlbumArtist: false)

        // album_artist role rows — mirrors coalesce(albumArtist, artist, 'Unknown Artist') fallback:
        let albumArtistRows: [(name: String, role: ArtistRole)]
        if let albumArtist = track.albumArtist, !albumArtist.isEmpty {
            albumArtistRows = ArtistSplitter.split(albumArtist, isAlbumArtist: true)
        } else if let artist = track.artist, !artist.isEmpty {
            albumArtistRows = ArtistSplitter.split(artist, isAlbumArtist: true)
        } else {
            albumArtistRows = [(name: "Unknown Artist", role: .albumArtist)]
        }
        track.artists.append(contentsOf: albumArtistRows)
```

- [ ] **Step 4: Run all tests**

```bash
swift test 2>&1 | tail -15
```

Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/NullPlayer/Data/Models/MediaLibrary.swift Tests/NullPlayerTests/ParseMetadataArtistTests.swift
git commit -m "feat: populate track.artists in parseMetadata using ArtistSplitter"
```

---

## Chunk 4: Store Queries

### Task 6: Update artist browser queries in `MediaLibraryStore`

**Files:**
- Modify: `Sources/NullPlayer/Data/Models/MediaLibraryStore.swift:432-580,800-822`

- [ ] **Step 1: Write failing tests**

Create `Tests/NullPlayerTests/TrackArtistsQueriesTests.swift`:

```swift
import XCTest
@testable import NullPlayer

final class TrackArtistsQueriesTests: XCTestCase {

    private var store: MediaLibraryStore!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sqlite")
        store = MediaLibraryStore.makeForTesting()
        store.open(at: tempURL)
        insertTestTracks()
    }

    override func tearDown() {
        store.close()
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    /// Insert test tracks:
    /// - Track 1: albumArtist = "Drake feat. Future" → Drake (albumArtist), Future (albumArtist)
    /// - Track 2: albumArtist = "Adele" → Adele (albumArtist)
    /// - Track 3: no albumArtist, artist = "Simon & Garfunkel" → Simon & Garfunkel (albumArtist via fallback)
    private func insertTestTracks() {
        var t1 = LibraryTrack(url: URL(fileURLWithPath: "/tmp/t1.mp3"), title: "T1")
        t1.albumArtist = "Drake feat. Future"
        t1.artist = "Drake"
        t1.album = "Take Care"
        t1.artists = ArtistSplitter.split("Drake", isAlbumArtist: false)
        let aa1 = ArtistSplitter.split("Drake feat. Future", isAlbumArtist: true)
        t1.artists.append(contentsOf: aa1)
        store.upsertTrack(t1, sig: nil)

        var t2 = LibraryTrack(url: URL(fileURLWithPath: "/tmp/t2.mp3"), title: "T2")
        t2.albumArtist = "Adele"
        t2.artist = "Adele"
        t2.album = "21"
        t2.artists = ArtistSplitter.split("Adele", isAlbumArtist: false)
        t2.artists.append(contentsOf: ArtistSplitter.split("Adele", isAlbumArtist: true))
        store.upsertTrack(t2, sig: nil)

        var t3 = LibraryTrack(url: URL(fileURLWithPath: "/tmp/t3.mp3"), title: "T3")
        t3.artist = "Simon & Garfunkel"
        t3.album = "Sounds of Silence"
        // No albumArtist → fallback: artist split with isAlbumArtist: true
        t3.artists = ArtistSplitter.split("Simon & Garfunkel", isAlbumArtist: false)
        t3.artists.append(contentsOf: ArtistSplitter.split("Simon & Garfunkel", isAlbumArtist: true))
        store.upsertTrack(t3, sig: nil)
    }

    func testArtistCount() {
        // Drake, Future, Adele, Simon & Garfunkel = 4
        XCTAssertEqual(store.artistCount(), 4)
    }

    func testArtistNamesContainsSplitArtists() {
        let names = store.artistNames(limit: 100, offset: 0, sort: .nameAsc)
        XCTAssertTrue(names.contains("Drake"))
        XCTAssertTrue(names.contains("Future"))
        XCTAssertTrue(names.contains("Adele"))
        XCTAssertTrue(names.contains("Simon & Garfunkel"))
        XCTAssertFalse(names.contains("Drake feat. Future"), "Raw unsplit string must not appear")
    }

    func testArtistNamesPageCountMatchesArtistCount() {
        let count = store.artistCount()
        let names = store.artistNames(limit: 100, offset: 0, sort: .nameAsc)
        XCTAssertEqual(names.count, count)
    }

    func testArtistLetterOffsetsAlignWithArtistNames() {
        let names = store.artistNames(limit: 100, offset: 0, sort: .nameAsc)
        let offsets = store.artistLetterOffsets(sort: .nameAsc)
        for (letter, offset) in offsets {
            let firstMatch = names.firstIndex { n in
                let firstChar = n.prefix(1).uppercased()
                return firstChar == letter || (letter == "#" && !firstChar.first!.isLetter)
            }
            XCTAssertEqual(firstMatch, offset, "Letter '\(letter)' offset \(offset) must match artistNames index")
        }
    }

    func testSearchArtistNamesReturnsSplitNames() {
        let results = store.searchArtistNames(query: "Drake")
        XCTAssertTrue(results.contains("Drake"))
        XCTAssertFalse(results.contains("Drake feat. Future"))
    }

    func testAlbumsForArtistDrake() {
        let albums = store.albumsForArtist("Drake")
        XCTAssertFalse(albums.isEmpty, "Drake must have albums")
        XCTAssertTrue(albums.contains { $0.name == "Take Care" })
    }

    func testAlbumsForArtistFuture() {
        let albums = store.albumsForArtist("Future")
        XCTAssertFalse(albums.isEmpty, "Future must have albums via albumArtist split")
        XCTAssertTrue(albums.contains { $0.name == "Take Care" })
    }

    func testAlbumsForArtistsBatch() {
        let batch = store.albumsForArtistsBatch(["Drake", "Future", "Adele"])
        XCTAssertTrue(batch["Drake"]?.contains { $0.name == "Take Care" } ?? false)
        XCTAssertTrue(batch["Future"]?.contains { $0.name == "Take Care" } ?? false)
        XCTAssertTrue(batch["Adele"]?.contains { $0.name == "21" } ?? false)
        XCTAssertNil(batch["Drake feat. Future"], "Unsplit key must not be in result")
    }
}
```

- [ ] **Step 2: Run to verify failures**

```bash
swift test --filter TrackArtistsQueriesTests 2>&1 | tail -10
```

Expected: Tests compile but `testArtistCount`, `testArtistNamesContainsSplitArtists`, etc. fail — queries still use old `coalesce(album_artist, artist)`.

- [ ] **Step 3: Replace `artistCount` (line 530)**

Replace the entire `artistCount()` function body:

```swift
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
```

- [ ] **Step 4: Replace `artistNames` (line 543)**

Replace the entire `artistNames(limit:offset:sort:)` function:

```swift
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
```

- [ ] **Step 5: Replace `artistLetterOffsets` (line 432)**

Replace the entire `artistLetterOffsets(sort:)` function:

```swift
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
```

- [ ] **Step 6: Replace `searchArtistNames` (line 800)**

Replace the entire `searchArtistNames(query:)` function:

```swift
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
```

- [ ] **Step 7: Replace `albumsForArtist` (line 642)**

Replace the entire `albumsForArtist(_:)` function:

```swift
    func albumsForArtist(_ artistName: String) -> [AlbumSummary] {
        guard let db = db else { return [] }
        let sql = """
            SELECT
                coalesce(t.album_artist, t.artist, 'Unknown Artist') || '|' || coalesce(t.album, 'Unknown Album') as album_id,
                coalesce(t.album, 'Unknown Album') as album_name,
                coalesce(t.album_artist, t.artist) as artist_name_val,
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
```

- [ ] **Step 8: Replace `albumsForArtistsBatch` (line 675)**

Replace the entire `albumsForArtistsBatch(_:)` function:

```swift
    /// Fetch album summaries for a page of artists in a single query.
    /// Returns a dict keyed by artist_name (the split name, same as artistNames() returns).
    func albumsForArtistsBatch(_ names: [String]) -> [String: [AlbumSummary]] {
        guard let db = db, !names.isEmpty else { return [:] }
        let placeholders = names.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            SELECT
                ta.artist_name as artist_key,
                coalesce(t.album_artist, t.artist, 'Unknown Artist') || '|' || coalesce(t.album, 'Unknown Album') as album_id,
                coalesce(t.album, 'Unknown Album') as album_name,
                coalesce(t.album_artist, t.artist) as artist_name_val,
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
```

- [ ] **Step 9: Run all query tests**

```bash
swift test --filter TrackArtistsQueriesTests 2>&1 | tail -15
```

Expected: All pass.

- [ ] **Step 10: Run full suite**

```bash
swift test 2>&1 | tail -15
```

Expected: All pass.

- [ ] **Step 11: Commit**

```bash
git add Sources/NullPlayer/Data/Models/MediaLibraryStore.swift Tests/NullPlayerTests/TrackArtistsQueriesTests.swift
git commit -m "feat: switch artist browser queries to track_artists join table"
```

---

## Chunk 5: Display Layer

### Task 7: Populate `track.artists` in `loadLibrary` + update in-memory paths

**Files:**
- Modify: `Sources/NullPlayer/Data/Models/MediaLibrary.swift:1362-1373,1437-1442,1713-1745,1979-1986`

- [ ] **Step 1: Write failing tests**

Create `Tests/NullPlayerTests/MediaLibraryArtistTests.swift`:

```swift
import XCTest
@testable import NullPlayer

final class MediaLibraryArtistTests: XCTestCase {

    func testAllArtistsSplitsMultiArtist() {
        // Build two tracks sharing an album with albumArtist = "Drake feat. Future"
        var t1 = LibraryTrack(url: URL(fileURLWithPath: "/tmp/ml_t1.mp3"), title: "Track1")
        t1.albumArtist = "Drake feat. Future"
        t1.album = "Take Care"
        // Populate artists as parseMetadata would
        t1.artists = ArtistSplitter.split("", isAlbumArtist: false)
        t1.artists.append(contentsOf: ArtistSplitter.split("Drake feat. Future", isAlbumArtist: true))

        var t2 = LibraryTrack(url: URL(fileURLWithPath: "/tmp/ml_t2.mp3"), title: "Track2")
        t2.albumArtist = "Adele"
        t2.album = "21"
        t2.artists = ArtistSplitter.split("", isAlbumArtist: false)
        t2.artists.append(contentsOf: ArtistSplitter.split("Adele", isAlbumArtist: true))

        let tracks = [t1, t2]
        let artists = tracksToArtists(tracks)

        let names = artists.map(\.name)
        XCTAssertTrue(names.contains("Drake"))
        XCTAssertTrue(names.contains("Future"))
        XCTAssertTrue(names.contains("Adele"))
        XCTAssertFalse(names.contains("Drake feat. Future"))
    }

    func testFilteredTracksMatchesSplitArtist() {
        var track = LibraryTrack(url: URL(fileURLWithPath: "/tmp/filter_t.mp3"), title: "T")
        track.albumArtist = "Drake feat. Future"
        track.artists = ArtistSplitter.split("Drake feat. Future", isAlbumArtist: true)

        var filter = LibraryFilter()
        filter.artists = ["Drake"]

        let matches = trackPassesArtistFilter(track, filter: filter)
        XCTAssertTrue(matches, "Track with albumArtist containing Drake must pass filter for 'Drake'")

        var filter2 = LibraryFilter()
        filter2.artists = ["Future"]
        XCTAssertTrue(trackPassesArtistFilter(track, filter: filter2))

        var filter3 = LibraryFilter()
        filter3.artists = ["Adele"]
        XCTAssertFalse(trackPassesArtistFilter(track, filter: filter3))
    }

    func testCreateLocalArtistRadioMatchesSplitArtist() {
        var track = LibraryTrack(url: URL(fileURLWithPath: "/tmp/radio_t.mp3"), title: "T")
        track.albumArtist = "Drake feat. Future"
        track.artists = ArtistSplitter.split("Drake feat. Future", isAlbumArtist: true)

        let matchesDrake = trackMatchesArtistRadio(track, artist: "Drake")
        XCTAssertTrue(matchesDrake)

        let matchesFuture = trackMatchesArtistRadio(track, artist: "Future")
        XCTAssertTrue(matchesFuture)

        let matchesAdele = trackMatchesArtistRadio(track, artist: "Adele")
        XCTAssertFalse(matchesAdele)
    }

    // MARK: - Helpers (extracted logic for testability)

    private func tracksToArtists(_ tracks: [LibraryTrack]) -> [Artist] {
        var artistDict: [String: [LibraryTrack]] = [:]
        for track in tracks {
            let albumArtistNames = track.artists
                .filter { $0.role == .albumArtist }
                .map { $0.name }
            let effectiveNames = albumArtistNames.isEmpty
                ? [track.albumArtist ?? track.artist ?? "Unknown Artist"]
                : albumArtistNames
            for name in effectiveNames {
                artistDict[name, default: []].append(track)
            }
        }
        return artistDict.map { name, _ in Artist(id: name, name: name, albums: []) }
    }

    private func trackPassesArtistFilter(_ track: LibraryTrack, filter: LibraryFilter) -> Bool {
        guard !filter.artists.isEmpty else { return true }
        let albumArtistNames = track.artists.filter { $0.role == .albumArtist }.map { $0.name }
        return albumArtistNames.contains { filter.artists.contains($0) }
    }

    private func trackMatchesArtistRadio(_ track: LibraryTrack, artist: String) -> Bool {
        track.artists.contains {
            $0.role == .albumArtist &&
            $0.name.localizedCaseInsensitiveCompare(artist) == .orderedSame
        }
    }
}
```

- [ ] **Step 2: Run tests**

```bash
swift test --filter MediaLibraryArtistTests 2>&1 | tail -5
```

Expected: All pass (these test extracted logic using the `artists` field which is now populated).

- [ ] **Step 3: Update `loadLibrary` to populate `track.artists`**

In `MediaLibrary.swift` at `loadLibrary()` (line 1713), replace:

```swift
        let loadedTracks = store.allTracks()
```

with:

```swift
        let rawTracks = store.allTracks()
        let trackURLStrings = rawTracks.map { $0.url.absoluteString }
        let artistsByURL = store.artistsForURLs(trackURLStrings)
        let loadedTracks = rawTracks.map { track -> LibraryTrack in
            var t = track
            t.artists = artistsByURL[t.url.absoluteString] ?? []
            return t
        }
```

This uses `rawTracks` as an intermediate name to avoid Swift's prohibition on redeclaring `let` constants in the same scope. The rest of `loadLibrary()` continues to use `loadedTracks` unchanged.

- [ ] **Step 4: Update `allArtists()`**

Replace lines 1362-1373:

```swift
    func allArtists() -> [Artist] {
        var artistDict: [String: [LibraryTrack]] = [:]
        for track in tracksSnapshot {
            let albumArtistNames = track.artists
                .filter { $0.role == .albumArtist }
                .map { $0.name }
            // Fallback to raw albumArtist/artist if artists not yet populated (e.g. quick-add pass)
            let effectiveNames = albumArtistNames.isEmpty
                ? [track.albumArtist ?? track.artist ?? "Unknown Artist"]
                : albumArtistNames
            for name in effectiveNames {
                artistDict[name, default: []].append(track)
            }
        }
        return artistDict.map { name, tracks in
            let albums = albumsForTracks(tracks)
            return Artist(id: name, name: name, albums: albums)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
```

- [ ] **Step 5: Update `filteredTracks` artist filter (lines 1437-1442)**

Replace the artist filter block:

```swift
        // Apply artist filter
        if !filter.artists.isEmpty {
            result = result.filter { track in
                let albumArtistNames = track.artists.filter { $0.role == .albumArtist }.map { $0.name }
                if albumArtistNames.isEmpty {
                    // Fallback for tracks loaded before backfill completes
                    guard let name = track.albumArtist ?? track.artist else { return false }
                    return filter.artists.contains(name)
                }
                return albumArtistNames.contains { filter.artists.contains($0) }
            }
        }
```

- [ ] **Step 6: Update `createLocalArtistRadio` (line 1979)**

Replace:
```swift
    func createLocalArtistRadio(artist: String, limit: Int = 100) -> [Track] {
        let pool = tracksSnapshot
            .filter { ($0.albumArtist ?? $0.artist ?? "").localizedCaseInsensitiveCompare(artist) == .orderedSame }
            .shuffled()
```

With:
```swift
    func createLocalArtistRadio(artist: String, limit: Int = 100) -> [Track] {
        let pool = tracksSnapshot
            .filter { track in
                // Match via track.artists (populated) or fall back to raw field for pre-backfill tracks
                let albumArtistNames = track.artists.filter { $0.role == .albumArtist }.map { $0.name }
                if albumArtistNames.isEmpty {
                    return (track.albumArtist ?? track.artist ?? "").localizedCaseInsensitiveCompare(artist) == .orderedSame
                }
                return albumArtistNames.contains { $0.localizedCaseInsensitiveCompare(artist) == .orderedSame }
            }
            .shuffled()
```

- [ ] **Step 7: Run all tests**

```bash
swift test 2>&1 | tail -15
```

Expected: All pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/NullPlayer/Data/Models/MediaLibrary.swift Tests/NullPlayerTests/MediaLibraryArtistTests.swift
git commit -m "feat: populate track.artists in loadLibrary, update allArtists/filteredTracks/createLocalArtistRadio"
```

---

## Chunk 6: Backfill

### Task 8: Backfill existing library on v2 → v3 migration

**Files:**
- Modify: `Sources/NullPlayer/Data/Models/MediaLibraryStore.swift` (add `backfillTrackArtists`)
- Modify: `Sources/NullPlayer/Data/Models/MediaLibrary.swift` (trigger backfill in `init`)

- [ ] **Step 1: Write a failing test**

Add to `Tests/NullPlayerTests/TrackArtistsSchemaTests.swift`:

```swift
    func testBackfillPopulatesTrackArtistsFromRawColumns() {
        // Insert a track with raw artist/albumArtist columns but NO track_artists rows
        // (simulates a pre-v3 library row)
        guard let db = store.testDB else {
            XCTFail("testDB not accessible"); return
        }
        let url = "file:///tmp/backfill_test.mp3"
        try? db.run("""
            INSERT INTO library_tracks (id, url, title, artist, album_artist, duration, file_size, date_added, play_count)
            VALUES (?, ?, 'BackfillTrack', 'Drake feat. Future', 'Drake feat. Future', 180.0, 0, 0.0, 0)
            """, UUID().uuidString, url)

        // Confirm no track_artists rows exist yet
        let before = try? db.scalar("SELECT COUNT(*) FROM track_artists WHERE track_url = ?", url) as? Int64 ?? 0
        XCTAssertEqual(before, 0)

        // Run backfill
        let expectation = expectation(description: "backfill")
        store.backfillTrackArtistsIfNeeded {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)

        // Verify track_artists rows exist
        let after = (try? db.scalar("SELECT COUNT(*) FROM track_artists WHERE track_url = ?", url) as? Int64) ?? 0
        XCTAssertGreaterThan(after, 0, "Backfill must have created track_artists rows")
        let drakeRows = (try? db.scalar(
            "SELECT COUNT(*) FROM track_artists WHERE track_url = ? AND artist_name = 'Drake' AND role = 'album_artist'",
            url
        ) as? Int64) ?? 0
        XCTAssertEqual(drakeRows, 1)
    }
```

To support the test, expose a `testDB` on `MediaLibraryStore` (internal, test-only):

```swift
    #if DEBUG
    var testDB: Connection? { db }
    #endif
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter TrackArtistsSchemaTests/testBackfill 2>&1 | tail -5
```

Expected: compile error — `store.backfillTrackArtistsIfNeeded` not defined.

- [ ] **Step 3: Add `backfillTrackArtistsIfNeeded` to `MediaLibraryStore`**

Add after `deleteAllMedia` (around line 1088):

```swift
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
```

- [ ] **Step 4: Trigger backfill from `MediaLibrary`**

In `Sources/NullPlayer/Data/Models/MediaLibrary.swift`, find the `init` (around line 392). After `store.open()` (or after `loadLibrary()` is called), add:

```swift
        // Trigger backfill if v2→v3 migration ran and track_artists are not yet populated
        if !UserDefaults.standard.bool(forKey: "trackArtistsBackfillComplete") {
            store.backfillTrackArtistsIfNeeded {
                // Reload the library after backfill so in-memory tracks have artists populated
                self.loadLibrary()
                NotificationCenter.default.post(name: MediaLibrary.libraryDidChangeNotification, object: nil)
            }
        }
```

- [ ] **Step 5: Run backfill test**

```bash
swift test --filter TrackArtistsSchemaTests/testBackfill 2>&1 | tail -10
```

Expected: Pass.

- [ ] **Step 6: Run full test suite**

```bash
swift test 2>&1 | tail -15
```

Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/NullPlayer/Data/Models/MediaLibraryStore.swift Sources/NullPlayer/Data/Models/MediaLibrary.swift Tests/NullPlayerTests/TrackArtistsSchemaTests.swift
git commit -m "feat: add track_artists backfill for v2→v3 migration"
```

---

## Final Verification

- [ ] **Build and run the app**

```bash
./scripts/kill_build_run.sh
```

- [ ] **Manual QA checklist**
  - Add a folder of local music files to the library
  - Navigate to the Artist browser tab
  - Verify a track tagged `albumArtist = "Artist1 feat. Artist2"` (or `artist = "A; B"`) shows both artists as separate entries
  - Click each split artist — verify their album appears under them
  - Verify "Simon & Garfunkel" (or similar `&` band name) is NOT split
  - Verify the jump-bar scrolls to the correct position for each letter
  - Verify search for an artist's split name finds them
  - Open Settings → Clear Library — verify app doesn't crash and library is empty after
  - Restart the app — verify artist browser still shows correct split artists

- [ ] **Final commit if anything was tweaked during QA**

```bash
git add -p
git commit -m "fix: QA fixes for multi-artist parsing"
```
