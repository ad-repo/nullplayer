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

---

## Approach: Join table, keep `artist` as primary (Approach A)

Add a `track_artists` join table. Keep the existing `artist` and `albumArtist` columns unchanged so the existing expression index and all non-browser queries are untouched. The artist browser switches to query `track_artists`.

---

## Section 1: Data Model & Schema Migration

### New table (schema v3)

```sql
CREATE TABLE track_artists (
    track_url   TEXT NOT NULL REFERENCES library_tracks(url) ON DELETE CASCADE,
    artist_name TEXT NOT NULL,
    role        TEXT NOT NULL CHECK(role IN ('primary', 'featured', 'album_artist')),
    PRIMARY KEY (track_url, artist_name, role)
);
CREATE INDEX idx_track_artists_name ON track_artists(artist_name);
CREATE INDEX idx_track_artists_url  ON track_artists(track_url);
```

### Roles

| Role | Source | Used by browser |
|---|---|---|
| `primary` | `artist` tag, before `feat.`/`;`/`/` | No (available for future use) |
| `featured` | `artist` tag, after `feat.`/`ft.` | No (available for future use) |
| `album_artist` | `albumArtist` tag (or `artist` fallback) | **Yes** |

### `LibraryTrack` model change

```swift
var artists: [(name: String, role: ArtistRole)] = []
```

This field is transient — not persisted via `Codable`, always re-derived from the database.

### Migration v3

On first launch after upgrade, a background task iterates all existing `library_tracks` rows, parses the `artist` and `albumArtist` columns using `ArtistSplitter`, and bulk-inserts into `track_artists`. Same background queue pattern as the incremental scan.

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
3. Strip surrounding parentheses from the `feat.`/`ft.` portion: `Drake (feat. Future)` → `Future`.
4. Trim whitespace from all names. Discard empty strings.

### Examples

| Input | `isAlbumArtist` | Results |
|---|---|---|
| `Drake feat. Future` | false | `Drake` (primary), `Future` (featured) |
| `Drake (feat. Future)` | false | `Drake` (primary), `Future` (featured) |
| `Foo; Bar` | false | `Foo` (primary), `Bar` (primary) |
| `Foo / Bar` | true | `Foo` (album_artist), `Bar` (album_artist) |
| `A; B feat. C` | false | `A` (primary), `B` (primary), `C` (featured) |
| `Various Artists` | true | `Various Artists` (album_artist) |
| `Simon & Garfunkel` | false | `Simon & Garfunkel` (primary) — no split |
| `Adele` | true | `Adele` (album_artist) |

---

## Section 3: Scan-time Integration

### `parseMetadata(for:)` in `MediaLibrary.swift`

After reading `artist` and `albumArtist` from AVFoundation metadata:

1. Call `ArtistSplitter.split(artist, isAlbumArtist: false)` → append to `track.artists`
2. Call `ArtistSplitter.split(albumArtist, isAlbumArtist: true)` → append to `track.artists`
3. Keep `track.artist` = first `primary` result (unchanged semantics)
4. Keep `track.albumArtist` = first `album_artist` result (unchanged semantics)

### Insert rule for `album_artist` rows

This mirrors today's `coalesce(album_artist, artist)` fallback:

- If `albumArtist` tag is set → split it, insert all results as `album_artist` role
- If `albumArtist` tag is absent → split the `artist` tag, insert those as `album_artist` role
- Always insert `artist` tag results as `primary`/`featured` regardless

### `MediaLibraryStore.upsertTracks(_:)`

Within the same transaction as the track upsert:

1. `DELETE FROM track_artists WHERE track_url IN (...)` for the batch
2. Bulk-insert all `track.artists` entries

---

## Section 4: Store Queries & Display Layer

The artist browser queries only `role = 'album_artist'` — preserving today's album-artist-first behavior.

### Updated methods in `MediaLibraryStore`

| Method | Change |
|---|---|
| `artistNames(limit:offset:sort:)` | Query `DISTINCT artist_name FROM track_artists WHERE role = 'album_artist'` |
| `searchArtistNames(_:)` | Same with `LIKE` filter on `artist_name` |
| `albumsForArtist(_:)` | Join `track_artists` on `url = track_url WHERE artist_name = ? AND role = 'album_artist'` |
| `albumsForArtistsBatch(_:)` | Same with `IN` clause |
| `artistLetterOffsets(sort:)` | Query `track_artists WHERE role = 'album_artist'` |

### `MediaLibrary.allArtists()` (in-memory path)

Expand `track.artists` filtered to `role == .albumArtist` instead of using `track.albumArtist ?? track.artist`.

### Unchanged

- `LibraryFilter`, search, playlist, CLI, casting, and all non-library-browser code
- The existing expression index `idx_tracks_artist_expr` — still valid for those paths
- `artist` and `albumArtist` columns on `library_tracks`

---

## Testing

- Unit tests for `ArtistSplitter` covering all patterns, edge cases (parentheses, word boundaries, empty input, single artist)
- Migration test: library with pre-v3 rows backfills `track_artists` correctly
- Integration: track tagged `albumArtist = "Drake feat. Future"` appears under both Drake and Future in the artist browser
- Regression: track with no `albumArtist` tag still appears under its `artist` name
- Regression: `Simon & Garfunkel` is not split
