# Local Library Skill

Reference for local media library: scanning, persistence, NAS responsiveness, and display-layer queries.

## Key Files

| Area | File |
|------|------|
| DB layer | `Data/Models/MediaLibraryStore.swift` |
| Library model + scan | `Data/Models/MediaLibrary.swift` |
| Track model | `Data/Models/Track.swift` |
| File discovery | `Utilities/LocalFileDiscovery.swift` |
| Audio engine (NAS paths) | `Audio/AudioEngine.swift` |
| Waveform (cue-sheet) | `Waveform/BaseWaveformView.swift` |
| Play history (Data tab) | `Windows/ModernStats/PlayHistoryStore.swift`, `Windows/ModernStats/PlayHistoryAgent.swift`, `Windows/ModernStats/StatsContentView.swift` |

## Database Schema

**Library**: `MediaLibraryStore` (SQLite via the `SQLite.swift` package). Replaced legacy `library.json`.

**PRAGMA settings**
- `journal_mode=WAL` — readers and writers proceed concurrently; prevents main-thread SELECT from blocking background INSERT during import.
- `synchronous=NORMAL` — safe with WAL, reduces fsync overhead during bulk import.
- `busyTimeout = 5s` — prevents hard failure on background/main thread contention.

**Schema version** (`PRAGMA user_version`)
- v0 → v6: fresh install creates all tables, runs `migrateToV5` then `migrateToV6`.
- v1 → v2: migration adds `idx_tracks_artist_expr` expression index (see Indexes below).
- v2 → v3: migration adds `track_artists` table with `ON DELETE CASCADE` FK (see Tables below).
- v3 → v4: migration adds extended metadata columns (`composer`, `comment`, `grouping`, `bpm`, `musical_key`, `isrc`, `copyright`, `musicbrainz_recording_id`, `musicbrainz_release_id`, `discogs_*`, `artwork_url`) via `ALTER TABLE … ADD COLUMN`.
- v4 → v5: migration adds `play_events` table and indexes (see Tables below).
- v5 → v6: migration adds `content_type` column to `play_events` (TEXT, nullable); backfills `'radio'` for source=radio rows, `'music'` for everything else.
- v6 → v7: migration adds `output_device` column to `play_events` (TEXT, nullable). Records the active CoreAudio output device name, or the cast target name (Chromecast/Sonos/DLNA device) when a cast session is active. NULL for legacy rows. Supplied via `CastManager.currentPlaybackDeviceName` at call sites in `AudioEngine` and `VideoPlayerWindowController`.

### Tables

#### `library_tracks`
| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PK | UUID string |
| `url` | TEXT UNIQUE | Absolute file path |
| `title` | TEXT | |
| `artist` | TEXT? | |
| `album` | TEXT? | |
| `album_artist` | TEXT? | |
| `genre` | TEXT? | |
| `year` | INT? | |
| `track_number` | INT? | |
| `disc_number` | INT? | |
| `duration` | REAL | Seconds |
| `bitrate` | INT? | kbps |
| `sample_rate` | INT? | Hz |
| `channels` | INT? | |
| `file_size` | INT | Bytes |
| `date_added` | REAL | Unix timestamp |
| `last_played` | REAL? | Unix timestamp |
| `play_count` | INT | Not nullable; defaults to 0 |
| `rating` | INT? | 0–10 scale |
| `scan_file_size` | INT? | Snapshot at last scan |
| `scan_mod_date` | REAL? | Snapshot at last scan |

**Indexes on `library_tracks`**
- `idx_tracks_artist (album_artist, artist)` — sort/filter by artist.
- `idx_tracks_artist_expr (coalesce(album_artist, artist, 'Unknown Artist'))` — expression index required for `artistNames` GROUP BY and `albumsForArtist`/`albumsForArtistsBatch` WHERE clauses. Without this, those queries do full table scans (caused minutes-long UI freezes on 60k-track libraries). **Must not be removed.**
- `idx_tracks_album (album)`, `idx_tracks_genre (genre)`, `idx_tracks_year (year)`.

#### `library_movies`
`id`, `url` (UNIQUE), `title`, `year`, `duration`, `file_size`, `date_added`, `scan_file_size`, `scan_mod_date`.

#### `library_episodes`
`id`, `url` (UNIQUE), `title`, `show_title`, `season_number`, `episode_number`, `duration`, `file_size`, `date_added`, `scan_file_size`, `scan_mod_date`.
Index: `idx_episodes_show (show_title, season_number)`.

#### `library_watch_folders`
`url` (PK), `added_at`.

#### `library_album_ratings` / `library_artist_ratings`
`album_id`/`artist_id` (PK), `rating`.

#### `track_artists` (added v3)
| Column | Type | Notes |
|--------|------|-------|
| `track_url` | TEXT | FK → `library_tracks(url)` ON DELETE CASCADE |
| `artist_name` | TEXT | |
| `role` | TEXT | `'primary'`, `'featured'`, or `'album_artist'` |
PK: `(track_url, artist_name, role)`. Indexes: `idx_track_artists_name`, `idx_track_artists_url`.

#### `play_events` (added v5, extended v6)
| Column | Type | Notes |
|--------|------|-------|
| `id` | INTEGER PK | AUTOINCREMENT |
| `track_id` | TEXT? | Library UUID if local track |
| `track_url` | TEXT? | File path if local track |
| `event_title` | TEXT? | |
| `event_artist` | TEXT? | |
| `event_album` | TEXT? | |
| `event_genre` | TEXT? | |
| `played_at` | REAL | Unix timestamp, NOT NULL |
| `duration_listened` | REAL | Seconds, NOT NULL, default 0 |
| `source` | TEXT | `'local'`, `'plex'`, `'subsonic'`, `'jellyfin'`, `'emby'`, or `'radio'` |
| `skipped` | INTEGER | 0/1, NOT NULL, default 0 |
| `content_type` | TEXT? | Added v6. Values: `'music'`, `'movie'`, `'tv'`, `'radio'`, `'video'`. NULL treated as `'music'` in queries. Derived from `Track.playHistoryContentType`; video playback records from `VideoPlayerWindowController` set this explicitly via `beginPlaybackAnalyticsSession(contentType:)`. |
| `output_device` | TEXT? | Added v7. Name of active audio output device (CoreAudio) or cast target device. NULL for legacy rows. |
Indexes: `idx_play_events_played_at`, `idx_play_events_track_id`, `idx_play_events_source_time`.
Queried by `PlayHistoryStore` (in `Windows/ModernStats/`) to power the Data tab in both the modern Library Browser and the classic `PlexBrowserView`.

**`insertPlayEvent` signature** (in `MediaLibraryStore`): takes `contentType: String = "music"` and `outputDevice: String? = nil` as trailing parameters — both default so all existing callers work unchanged. Pass `track.playHistoryContentType` and `CastManager.currentPlaybackDeviceName` at call sites. Internet radio sessions pass `outputDevice` from `CastManager.currentPlaybackDeviceName` at the time the event is recorded.

### Key API Methods (MediaLibraryStore)

- **Paginated queries**: `artistNames(limit:offset:sort:)`, `albumSummaries(...)`, `tracksForAlbum(...)`, `searchTracks(...)`, `searchArtistNames(...)`, `searchAlbumSummaries(...)`
- **Batch query**: `albumsForArtistsBatch(_:)` — fetches album summaries for a full page of artists in **one** SQL query (IN clause). Use this instead of per-artist `albumsForArtist(_:)` to avoid N×full-table-scan on the main thread.
- **Bulk insert**: `upsertTracks(_:)`, `upsertMovies(_:)`, `upsertEpisodes(_:)` — wrap rows in a transaction; call in 500-row batches during enrichment.
- **Alphabet index**: `artistLetterOffsets(sort:)`, `albumLetterOffsets(sort:)` — used by scroll jump-bar.
- **Signatures**: `allSignatures()` → `[String: FileScanSignature]` — loaded once at startup and diffed during incremental scan.

## Scan Pipeline

### Flow: `importMedia(...)` in `MediaLibrary.swift`

1. **Discover** — `LocalFileDiscovery.discoverMedia` (recursive + shallow, one-pass resource-key reads).
2. **Diff**
   - Remove items inside scanned watch folders that are now missing.
   - Skip unchanged files: compare `(fileSize, contentModificationDate)` signature.
   - Queue changed/new files.
3. **Process**
   - Fast-track insertion: `makeFastTrack` / `Track.init(lightweightURL:)` — avoids eager AVFoundation reads during bulk enqueue.
   - Async metadata enrichment pool: bounded workers (`2` on non-local volumes, CPU-based on local).
   - `autoreleasepool` wraps `parseMetadata` per file to release AVAsset objects promptly.
   - Incremental 500-track SQLite flushes via `flushPendingMetadata()` rolling buffer — prevents unbounded memory accumulation on 60k+ libraries.
   - Video classification refresh after audio enrichment completes.

### Entry Points
`scanFolder`, `rescanWatchFolder`, `rescanWatchFolders`, `addTracks(urls:)` all route through `importMedia(...)`.

### Scan Signatures
`FileScanSignature` (`fileSize: Int64`, `contentModificationDate: Date`) — stored per path in SQLite (`scan_file_size`, `scan_mod_date`). Fast-track insertions do **not** persist a signature; signature is written only after enrichment completes.

### Progress Throttling
Emitted when delta >= 0.02 or >= 0.20s elapsed, plus forced boundary emits.

### UI Reload Debouncing
Both `ModernLibraryBrowserView` and `PlexBrowserView` debounce `MediaLibraryDidChange` reloads (0.30s work-item debounce) and use mode-aware `loadLocalData()` to load only required datasets.

## LocalFileDiscovery Utility

`Utilities/LocalFileDiscovery.swift` — shared for all local file/folder discovery, drag-and-drop, and library scanning.

- `isSupportedAudioFile(_:)`, `isSupportedVideoFile(_:)`, `isSupportedPlaylistFile(_:)`, `hasSupportedDropContent(...)`
- `discoverMediaURLsAsync(...)` — background discovery, sorted callback on main thread.
- `discoverMedia(...)` — synchronous, used inside scan workers.
- Deduplication by normalized path; one-pass `isRegularFile`, `fileSize`, `contentModificationDate` resource-key reads.

## NAS Responsiveness

All local `AVAudioFile(forReading:)` calls are async on `deferredIOQueue` (background serial queue in `AudioEngine`).

### Deferred Paths (all covered)
| Trigger | Function |
|---------|----------|
| Direct click (`playTrack`) | `loadLocalTrackForImmediatePlayback(_:at:)` |
| Auto-advance (`trackDidFinish`) | `advanceToLocalTrackAsync` → `loadLocalTrackForImmediatePlayback` |
| Sweet Fades (`startLocalCrossfade`) | inline `deferredIOQueue.async` with `crossfadeFileLoadToken` |
| Gapless pre-schedule | `scheduleNextTrackForGapless` — `deferredIOQueue.async` |

### Token-guard Pattern
Each async open carries a load token (`deferredLocalTrackLoadToken` or `crossfadeFileLoadToken`). Stale completions are dropped unless token + index + track ID still match at callback time.

### Helpers
- `prepareForLocalTrackLoad` / `commitLoadedLocalTrack` / `handleLocalTrackLoadFailure` — shared setup/commit/failure.
- Cue-sheet parsing is async/cancellable (`cueLoadTask`) in `BaseWaveformView`.

## Critical Gotchas

### Never call `normalizedPath(for:)` in a loop over library items
`resolvingSymlinksInPath()` is a filesystem call — a network round-trip on NFS/SMB. Pre-compute folder paths once outside any loop, then compare against `url.path` directly (already resolved at scan time via `normalizedWatchFolderURL`). Violating this caused the Manage Folders window to hang permanently on 60k-track libraries (300k filesystem calls).

Reference pattern: `watchFolderSummaries()` in `MediaLibrary.swift`.

### Use `albumsForArtistsBatch` not per-artist queries in the display layer
`albumsForArtist(_:)` does one SQL query per artist. In `buildLocalArtistItems()` on a 200-artist page this means 200 queries, each a full table scan without the expression index (before v2 schema). Always use `albumsForArtistsBatch(_:)`.

### Expression index is load-bearing
`idx_tracks_artist_expr` uses `coalesce(album_artist, artist, 'Unknown Artist')` — the same expression used in `artistNames` GROUP BY and WHERE clauses. If the expression in a query doesn't exactly match the index expression, SQLite won't use the index. Keep query expressions consistent with the index definition.

### Fast-track scan signatures
`makeFastTrack` does **not** persist a scan signature. The signature (`scan_file_size`, `scan_mod_date`) is written only after metadata enrichment completes. This is intentional: if enrichment is interrupted, the file will be re-enriched on next scan.

## Data Tab (Play History Analytics)

Both `ModernLibraryBrowserView` and `PlexBrowserView` (classic) embed a Data tab backed by `PlayHistoryAgent` + `StatsContentView`.

In `PlexBrowserView`, the tab is the `.history` case (displayed as "Data"). It is implemented via an `NSHostingView<StatsContentView>` created in `makeHistoryHostingView()` and reused across tab switches. The agent is a private `let historyAgent = PlayHistoryAgent()` instance on the view. Skin text color is forwarded on tab selection and on skin reload.

**Charts in the Data tab overview:**
- Play Time summary (day/week/month/year/all-time)
- Top Artists (music only — excludes radio)
- Top Movies / Top TV Shows (content-type specific)
- Genre breakdown (excludes radio)
- Sources breakdown (excludes radio; shows note directing to Internet Radio section)
- Output Devices breakdown (filterable; NULL/empty device rows excluded)
- Content Types donut
- Internet Radio section (total listen time + Top Stations by play count/duration)
- Plays Over Time time series

**Output Devices chart** (`OutputDeviceChartView`): groups `play_events` by `COALESCE(NULLIF(trim(output_device), ''), 'Unknown')`, filtering out NULL/empty rows. Color assignment uses a deterministic hash of the device name mapped into a 12-color palette. Cast sessions record the Chromecast/Sonos/DLNA device name via `CastManager.currentPlaybackDeviceName`.

**`PlayHistoryStore` query isolation:**
- `fetchTopArtists` — music only (`content_type = 'music'`)
- `fetchTopMovies` — movie only
- `fetchTopTVShows` — tv only; extracts show name from `event_artist` first, falls back to parsing `"Show Name - S01E02"` title pattern
- `fetchTopRadioStations` / `fetchRadioListenSeconds` — radio only; use `whereClause(forRadio:)` which only applies time range, output device, and skip filters
- `fetchTopDimension(.artist/.source/.album/.genre)` — all exclude radio via `content_type <> 'radio'`
- `fetchGenreBreakdown` — excludes radio

## Testing

When touching local-library scanning/import or NAS performance, run these checks in addition to normal suites:

```bash
swift test --filter LocalFileDiscoveryTests
swift test --filter MediaLibraryWatchFolderPathTests
swift test --filter NullPlayerTests
```

Manual validation passes:

1. First scan of a large folder imports all supported media.
2. Second scan with unchanged files skips metadata re-parse and duplicate inserts.
3. Changed file (mtime/size) is re-enriched; removed file is pruned.
4. Drag/drop folder, add-folder, and playlist/main-window import paths produce consistent file sets.
5. NAS scenario: switching from large WAV to MP3 should keep UI responsive (no sustained beachball).
