# Multi-Artist Parsing Design

**Date:** 2026-03-17
**Status:** Approved
**Scope:** Local library — scan-time artist splitting and schema migration

---

## Problem

The local library stores `artist` and `albumArtist` as single raw strings. Tags like `"Drake feat. Future"` or `"Foo; Bar"` cause those tracks to be grouped under a single synthetic artist name rather than the individual real artists. The library browser ends up with entries like `"Drake feat. Future"` instead of separate entries for `Drake` and `Future`.

---

## Goal

Split multi-artist strings at scan time and store the results in a join table. The artist browser continues to work album-artist-first (same as today) but now expands collab-tagged albums into individual artist entries.

---

## Non-Goals

- Splitting `&`, `,`, `and`, `with`, `x` — too ambiguous; legitimate band names use these.
- Changing how Plex, Subsonic, Jellyfin, or Emby server content is browsed.
- Changing playback, casting, or any non-library-browser code path.
- Migrating existing `library_artist_ratings` keys — ratings stored under the old unsplit key (e.g. `"Drake feat. Future"`) become orphaned after migration. This is an acceptable cut; no ratings migration is performed.
- Updating `searchAlbumSummaries` — album text search still queries the raw `coalesce(album_artist, artist)` column in `library_tracks`. After migration, searching albums for `"Drake"` may not find albums tagged `albumArtist = "Drake feat. Future"`. This asymmetry between artist browser (split) and album search (unsplit) is an acceptable cut for this iteration.

---

## Approach: Join table, keep `artist` as primary (Approach A)

Add a `track_artists` join table. Keep the existing `artist` and `albumArtist` columns unchanged so the existing expression index and all non-browser queries are untouched. The artist browser switches to query `track_artists`.

---

## Section 1: Data Model & Schema Migration

### New table (schema v3)

```sql
-- Enable FK enforcement at DB open time (add to setupSchema / db open, called every connection open)
PRAGMA foreign_keys = ON;

CREATE TABLE track_artists (
    -- FK references url (UNIQUE constraint on library_tracks), not id (PK). Intentional:
    -- url is the natural key used everywhere in the scan pipeline and all queries,
    -- avoiding a UUID lookup on every insert.
    track_url   TEXT NOT NULL REFERENCES library_tracks(url) ON DELETE CASCADE,
    artist_name TEXT NOT NULL,
    role        TEXT NOT NULL CHECK(role IN ('primary', 'featured', 'album_artist')),
    PRIMARY KEY (track_url, artist_name, role)
);
CREATE INDEX idx_track_artists_name ON track_artists(artist_name);
CREATE INDEX idx_track_artists_url  ON track_artists(track_url);
```

`PRAGMA foreign_keys = ON` must be executed every time a database connection is opened (SQLite resets it per connection). Add it to the existing DB-open path in `MediaLibraryStore`. **Every database connection that issues writes or deletes against `library_tracks` must set this pragma** — including any future background connections. Currently `MediaLibraryStore` uses a single `db` connection for all operations; if a second connection is ever introduced, it must also set this pragma or cascade will silently not fire on deletions through that connection.

With the pragma set, `ON DELETE CASCADE` fires on all deletion paths:

- `deleteAllTracks()` — `tracksTable.delete()` issues `DELETE FROM library_tracks`; cascade deletes all `track_artists` rows. This relies on the cascade from the same `db` connection that had the pragma set at open. No explicit `DELETE FROM track_artists` needed.
- `deleteAllMedia()` — same
- `deleteTrackByPath(_:)` — single-row `DELETE FROM library_tracks WHERE url = ?` → cascade deletes that URL's `track_artists` rows. No changes needed to this method.

**Important — `INSERT OR REPLACE` cascade interaction:** `upsertTrack` / `upsertTracks` use `INSERT OR REPLACE INTO library_tracks`. With `PRAGMA foreign_keys = ON`, SQLite treats `INSERT OR REPLACE` as DELETE + INSERT, so the FK cascade fires automatically and deletes the old `track_artists` rows for that URL before the new row is inserted. The code must therefore **not** issue an explicit `DELETE FROM track_artists` — the cascade handles it. Insert the new `track_artists` rows immediately after the track upsert, within the same transaction.

### Roles

| Role | Source | Used by browser |
|---|---|---|
| `primary` | `artist` tag, before `feat.`/`;`/`/` | No (available for future use) |
| `featured` | `artist` tag, after `feat.`/`ft.` | No (available for future use) |
| `album_artist` | `albumArtist` tag (or `artist` fallback — see insert rule) | **Yes** |

**`album_artist` fallback semantics:** When a track has no `albumArtist` tag, the `artist` tag is split and all results (including any `featured` artists) are inserted as `album_artist` role. This means a track tagged only `artist = "Foo feat. Bar"` will show both `Foo` and `Bar` as top-level browser artists. This is intentional — it mirrors today's `coalesce(album_artist, artist)` fallback, extended with splitting.

### `ArtistRole` enum

```swift
enum ArtistRole: String {
    case primary      = "primary"
    case featured     = "featured"
    case albumArtist  = "album_artist"
}
```

`ArtistRole` is not `Codable` — it is only used in the transient `artists` field.

### `LibraryTrack` model change

```swift
var artists: [(name: String, role: ArtistRole)] = []
```

This field is transient — excluded from `Codable` synthesis by adding an explicit `CodingKeys` enum to `LibraryTrack` that lists every existing stored property except `artists`. **The `CodingKeys` enum must enumerate all current stored properties exactly** — omitting any existing property will silently break `AppStateManager` session restore, which round-trips `LibraryTrack` through `Codable`.

The `artists` field is populated from `track_artists` as part of loading tracks from the database (see "Loading `track.artists`" below).

### Loading `track.artists`

`track.artists` must be populated whenever tracks are loaded from the database. There are two load paths:

**Bulk path (`allTracks()` / `loadLibrary()`):**
After `trackFromRow()` constructs all `LibraryTrack` objects from `library_tracks`, execute a single batch query:
```sql
SELECT track_url, artist_name, role FROM track_artists WHERE track_url IN (...)
```
and set `track.artists` for each track. Issue this in chunks of 500 URLs to avoid SQLite `IN` clause limits.

**Single-row path (after `upsertTrack`):**
`upsertTrack(_:)` returns `Void` and `LibraryTrack` is a value type. Population of `track.artists` happens in the `MediaLibrary` layer (not the store): after calling `store.upsertTrack(track, ...)`, re-query `track_artists WHERE track_url = ?` and update the local `track` copy before adding it to `tracksSnapshot`. This is the same layer where `tracksSnapshot` is managed.

**`tracksForAlbum(_:)` — no population needed:**
`tracksForAlbum` returns tracks for display in an album track list. None of the in-memory consumer paths (`allArtists()`, `filteredTracks()`, `createLocalArtistRadio()`) use its return value as input. `track.artists` need not be populated on tracks returned by `tracksForAlbum`.

Without population on the bulk and single-row paths, all in-memory consumer paths (`allArtists()`, `filteredTracks(filter:)`, `createLocalArtistRadio(artist:)`, `LibraryFilter`) will operate on empty `artists` arrays and silently produce wrong results.

**JSON migration path:** `migrateFromJSONIfNeeded` decodes `LibraryTrack` via `Codable`, producing objects with `artists == []`. `upsertTrackInternal` will therefore write zero `track_artists` rows for these tracks. This is expected — the v3 backfill reads the raw `artist`/`albumArtist` columns directly from `library_tracks` and will populate `track_artists` for these tracks. No special handling is needed in `migrateFromJSONIfNeeded`.

**Transient quick-add state:** The scan pipeline has two passes — a fast "quick add" pass (metadata-less stubs, `artists == []`) followed by a metadata enrichment pass. Between these two passes, `allArtists()` will return empty results for the newly added stubs. This is expected and unchanged from existing incremental scan behavior.

### Fresh install (schema v0 → v3)

The `currentVersion == 0` branch in `setupSchema` calls `createTablesIfNeeded` and sets `user_version`. Update `createTablesIfNeeded` to include the `track_artists` DDL and set `user_version = 3`. No backfill is needed for fresh installs (no pre-existing rows).

### Migration v3 (existing installs: v2 → v3)

1. DDL: `CREATE TABLE track_artists ...` and indexes inside the v2→v3 migration transaction.
2. After the migration transaction commits, set `UserDefaults` flag `trackArtistsBackfillComplete = false` and enqueue a backfill task.
3. **Backfill:** A single background `Task` iterates all `library_tracks` rows in 500-row batches, parses each row's `artist` and `albumArtist` columns using `ArtistSplitter`, and inserts into `track_artists` using `INSERT OR IGNORE`. Each batch is its own write transaction.
4. On completion set `trackArtistsBackfillComplete = true`.
5. **Crash recovery:** On launch, if `trackArtistsBackfillComplete == false`, issue `DELETE FROM track_artists` and restart the backfill from the beginning. Rows previously written by a concurrent scan are wiped but will be repopulated when those files are next rescanned; all other tracks will be covered by the restarted backfill. This transient inconsistency is acceptable.
6. **Concurrent scan:** `upsertTracks` cascade + re-insert handles its URLs correctly regardless of whether the backfill is in progress. The backfill uses `INSERT OR IGNORE` so it does not overwrite scan-fresh rows written after the backfill started processing a batch.

---

## Section 2: Artist Splitting Logic

A new `ArtistSplitter` enum — pure, no external dependencies.

```swift
enum ArtistSplitter {
    static func split(_ raw: String, isAlbumArtist: Bool) -> [(name: String, role: ArtistRole)]
}
```

### Algorithm

1. Split on `;` and `/` first — these are unambiguous list separators. All resulting segments get `primary` role (or `album_artist` if `isAlbumArtist: true`).
2. Within each segment, detect `feat.`, `feat`, `ft.`, `ft` (case-insensitive, word-boundary — must be preceded by a space or `(` to avoid matching inside words like "defeat").
   - Part before → `primary` / `album_artist`
   - Part after → `featured` / `album_artist`
3. Strip surrounding parentheses from the `feat.`/`ft.` segment: `Drake (feat. Future)` → `Future`.
4. Trim whitespace from all names. Discard empty strings.

### Examples

| Input | `isAlbumArtist` | Results |
|---|---|---|
| `Drake feat. Future` | false | `Drake` (primary), `Future` (featured) |
| `Drake (feat. Future)` | false | `Drake` (primary), `Future` (featured) |
| `Foo; Bar` | false | `Foo` (primary), `Bar` (primary) |
| `Foo / Bar` | false | `Foo` (primary), `Bar` (primary) |
| `Foo / Bar` | true | `Foo` (album_artist), `Bar` (album_artist) |
| `A; B feat. C` | false | `A` (primary), `B` (primary), `C` (featured) |
| `A / B feat. C` | false | `A` (primary), `B` (primary), `C` (featured) |
| `Drake feat. Future` | true | `Drake` (album_artist), `Future` (album_artist) |
| `Various Artists` | true | `Various Artists` (album_artist) |
| `Simon & Garfunkel` | false | `Simon & Garfunkel` (primary) — no split |
| `Adele` | true | `Adele` (album_artist) |

---

## Section 3: Scan-time Integration

### `parseMetadata(for:)` in `MediaLibrary.swift`

After reading `artist` and `albumArtist` from AVFoundation metadata:

1. Call `ArtistSplitter.split(artist, isAlbumArtist: false)` → append to `track.artists`
2. Apply `album_artist` insert rule (see below) → append `album_artist` results to `track.artists`
3. Keep `track.artist` = first `primary` result (unchanged semantics for non-browser code)
4. Keep `track.albumArtist` = first `album_artist` result (unchanged semantics for non-browser code)

### Insert rule for `album_artist` rows

This mirrors today's `coalesce(album_artist, artist, 'Unknown Artist')` fallback:

- If `albumArtist` tag is set → `ArtistSplitter.split(albumArtist, isAlbumArtist: true)`, insert all results as `album_artist` role
- If `albumArtist` tag is absent and `artist` tag is set → `ArtistSplitter.split(artist, isAlbumArtist: true)`, insert those as `album_artist` role
- If both `albumArtist` and `artist` are nil → insert a single `album_artist` row with `artist_name = "Unknown Artist"` to match the existing `coalesce` fallback; `artistCount()` and `artistNames()` will include these tracks under "Unknown Artist" as before

### `MediaLibraryStore.upsertTrackInternal(_:db:)` — correct insertion layer

The `track_artists` inserts belong inside `upsertTrackInternal`, not in the public callers (`upsertTracks`, `upsertTrack`, or `migrateFromJSONIfNeeded`). This ensures that every call path that inserts a track row — batch scan, single-track update, and JSON migration — automatically inserts the corresponding `track_artists` rows without requiring each caller to be updated individually.

`upsertTrackInternal` already receives a `Connection` parameter that is always inside a transaction at the call site. Add the `track_artists` insert steps there:

1. `INSERT OR REPLACE INTO library_tracks ...` — cascade automatically deletes old `track_artists` rows for the replaced URL
2. For each entry in `track.artists`: `INSERT OR IGNORE INTO track_artists (track_url, artist_name, role) VALUES (?, ?, ?)`

(No explicit `DELETE FROM track_artists` needed — cascade handles it.)

### `MediaLibraryStore.upsertTrack(_:)` — transaction wrapper

`upsertTrack(_:)` currently calls `upsertTrackInternal` without a `db.transaction {}` wrapper. Wrap it in a transaction so that the track row insert and `track_artists` inserts are atomic. `upsertTracks(_:)` and `migrateFromJSONIfNeeded` already manage their own transactions; no changes needed there beyond the `upsertTrackInternal` update above.

---

## Section 4: Store Queries & Display Layer

The artist browser queries only `role = 'album_artist'` — preserving today's album-artist-first behavior.

### Updated methods in `MediaLibraryStore`

**`artistNames(limit:offset:sort:)` and `artistLetterOffsets(sort:)`**

These two methods must use **identical** query structure and sort expressions — `artistLetterOffsets` is the same query without LIMIT/OFFSET, used to compute jump-bar positions. Any divergence in sort order or GROUP BY between the two will cause jump-bar navigation to wrong positions.

All six sort modes, with secondary sort tiebreak on `artist_name ASC` to ensure deterministic ordering:

```sql
-- nameAsc: DISTINCT sufficient — artist_name is the only column and is the sort key; no GROUP BY needed
SELECT DISTINCT ta.artist_name
FROM track_artists ta
WHERE ta.role = 'album_artist'
ORDER BY ta.artist_name ASC

-- nameDesc:
SELECT DISTINCT ta.artist_name
FROM track_artists ta
WHERE ta.role = 'album_artist'
ORDER BY ta.artist_name DESC

-- dateAddedDesc (most recently added track per artist, newest first):
SELECT ta.artist_name
FROM track_artists ta
JOIN library_tracks t ON t.url = ta.track_url
WHERE ta.role = 'album_artist'
GROUP BY ta.artist_name
ORDER BY max(t.date_added) DESC, ta.artist_name ASC

-- dateAddedAsc (earliest added track per artist, oldest first):
SELECT ta.artist_name
FROM track_artists ta
JOIN library_tracks t ON t.url = ta.track_url
WHERE ta.role = 'album_artist'
GROUP BY ta.artist_name
ORDER BY min(t.date_added) ASC, ta.artist_name ASC

-- yearDesc (most recent year per artist, newest first; artists with no year sort last):
SELECT ta.artist_name
FROM track_artists ta
JOIN library_tracks t ON t.url = ta.track_url
WHERE ta.role = 'album_artist'
GROUP BY ta.artist_name
ORDER BY max(t.year) DESC NULLS LAST, ta.artist_name ASC

-- yearAsc (earliest year per artist, oldest first; artists with no year sort last):
SELECT ta.artist_name
FROM track_artists ta
JOIN library_tracks t ON t.url = ta.track_url
WHERE ta.role = 'album_artist'
GROUP BY ta.artist_name
ORDER BY min(t.year) ASC NULLS LAST, ta.artist_name ASC
```

`artistLetterOffsets` uses the same SQL without `LIMIT ? OFFSET ?` and wraps results to compute letter bucket positions.

| Method | Change |
|---|---|
| `artistCount()` | `SELECT COUNT(DISTINCT artist_name) FROM track_artists WHERE role = 'album_artist'` |
| `searchArtistNames(_:)` | `SELECT DISTINCT ta.artist_name FROM track_artists ta WHERE ta.role = 'album_artist' AND ta.artist_name LIKE ?` (note: searching for `"feat"` will no longer match `"Drake feat. Future"` — it matches only artist names containing "feat" as a substring, which is the correct new behavior) |
| `albumsForArtist(_:)` | Join `track_artists` on `t.url = ta.track_url WHERE ta.artist_name = ? AND ta.role = 'album_artist'`; dict keyed by `ta.artist_name` |
| `albumsForArtistsBatch(_:)` | Same with `IN` clause; dict keyed by `ta.artist_name` (not by `coalesce(album_artist, artist)`) so callers using split artist names resolve correctly |
| `createLocalArtistRadio(artist:)` | Match on `track.artists.contains { $0.role == .albumArtist && $0.name.localizedCaseInsensitiveCompare(artist) == .orderedSame }` instead of `track.albumArtist ?? track.artist` |

**Album id key:** `albumsForArtist` / `albumsForArtistsBatch` still compute `album_id` as `coalesce(album_artist, artist, 'Unknown Artist') || '|' || album` (the raw unsplit value from `library_tracks`). For a track with `albumArtist = "Drake feat. Future"`, both the Drake and Future artist entries return `album_id = "Drake feat. Future|Some Album"`. `tracksForAlbum` resolves this correctly via `WHERE coalesce(album_artist, artist, 'Unknown Artist') = 'Drake feat. Future'`. For a track with no `albumArtist` and `artist = "Foo feat. Bar"`, the album_id is `"Foo feat. Bar|Some Album"`, resolved the same way. The album_id key is not changing.

**In-memory path (`allArtists()`):** Expand `track.artists` filtered to `role == .albumArtist` instead of `track.albumArtist ?? track.artist`. For a track with `albumArtist = "Drake feat. Future"`, this produces two `Artist` entries: `Artist(id: "Drake", name: "Drake", ...)` and `Artist(id: "Future", name: "Future", ...)`. Each entry's albums are found by filtering `tracksSnapshot` for tracks where `track.artists` contains that artist name with `albumArtist` role, then grouping by album. The album navigation flow (`Artist → Album → tracksForAlbum`) still works because the album_id key is derived from the raw `library_tracks` columns, not the split names.

### `LibraryFilter.artists` (in-memory filter path)

`filteredTracks(filter:)` currently matches on `track.albumArtist ?? track.artist`. Update to: a track passes the artist filter if `track.artists.filter { $0.role == .albumArtist }.map(\.name)` contains any value in `filter.artists`.

### Unchanged

- `artist` and `albumArtist` columns on `library_tracks`
- The existing expression index `idx_tracks_artist_expr` — still valid for search, playlist, CLI, and casting paths
- `deleteAllTracks()`, `deleteAllMedia()`, `deleteTrackByPath(_:)` — cascade handles `track_artists` via `PRAGMA foreign_keys = ON`; no code changes needed in these methods
- `library_artist_ratings` — see Non-Goals

---

## Testing

- Unit tests for `ArtistSplitter` covering all patterns, edge cases (parentheses, word boundaries, empty input, single artist, `/` with `isAlbumArtist: false`, `feat` without period)
- Unit test: `ArtistRole` is excluded from `LibraryTrack` `Codable` encode/decode; all other fields round-trip correctly
- Unit test: `albumsForArtistsBatch` dict keys are split artist names, not raw coalesce strings
- Migration test: library with pre-v3 rows backfills `track_artists` correctly; re-run after simulated mid-backfill crash (flag reset) produces correct results
- Migration test: fresh install (`currentVersion == 0`) creates `track_artists` without backfill
- Integration: `track.artists` is populated after `allTracks()` / `loadLibrary()` (not empty)
- Integration: track tagged `albumArtist = "Drake feat. Future"` appears under both Drake and Future in the artist browser
- Integration: `artistCount()` matches `artistNames` total page count after split
- Integration: `artistLetterOffsets` jump-bar positions align exactly with `artistNames` rows for all sort modes
- Integration: `LibraryFilter(artists: ["Drake"])` correctly matches a track tagged `albumArtist = "Drake feat. Future"`
- Integration: `createLocalArtistRadio(artist: "Drake")` returns tracks tagged `albumArtist = "Drake feat. Future"`
- Integration: sort-by-date and sort-by-year in the artist browser produce correct order after `track_artists` migration
- Regression: track with no `albumArtist` tag still appears under its `artist` name
- Regression: `Simon & Garfunkel` is not split
- Regression: `deleteAllTracks()` leaves `track_artists` empty (cascade fires with `PRAGMA foreign_keys = ON`)
- Regression: `deleteTrackByPath` removes corresponding `track_artists` rows (cascade)
- Regression: existing expression index queries (search, CLI filter) still work correctly after migration
