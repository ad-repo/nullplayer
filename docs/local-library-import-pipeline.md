# Local Library Import Pipeline (Current State)

Last updated: 2026-03-13 (incremental batch flushing added; post-import UI hang fixed)

This document captures the current implementation status for local-library scanning/import and NAS responsiveness work so another agent can continue without re-discovery.

## Scope Covered

- Unified local file/folder discovery for library + playlist/main-window flows
- Incremental local library scanning (`discover -> diff -> process`)
- Fast ingest with asynchronous metadata enrichment
- Reduced UI churn (debounced reloads, throttled progress notifications)
- Save/write coalescing for bulk import
- NAS responsiveness fixes for local playback transitions (WAV -> MP3 beachball path)

## Implemented Architecture

### 1) Shared discovery utility

File: `Sources/NullPlayer/Utilities/LocalFileDiscovery.swift`

Implemented:

- Shared supported-content checks:
  - `hasSupportedDropContent(...)`
  - `isSupportedAudioFile`, `isSupportedVideoFile`, `isSupportedPlaylistFile`
- Shared discovery:
  - recursive + shallow directory traversal
  - one-pass resource-key reads (`isRegularFile`, `fileSize`, `contentModificationDate`)
  - dedupe by normalized path
- Background helper:
  - `discoverMediaURLsAsync(...)` (sorted callback on main thread)

### 2) Incremental MediaLibrary scan pipeline

File: `Sources/NullPlayer/Data/Models/MediaLibrary.swift`

Implemented:

- New signature model: `FileScanSignature` (`fileSize`, `contentModificationDate`)
- Persisted signature map in library JSON:
  - `scanSignaturesByPath: [String: FileScanSignature]`
  - backward-compatible decode default (`decodeIfPresent ?? [:]`)
- Scan flow in `importMedia(...)`:
  1. Discover (`LocalFileDiscovery.discoverMedia`)
  2. Diff:
     - remove missing items inside scanned watch folders
     - skip unchanged files by signature
     - queue changed/new files
  3. Process:
     - fast-track insertion (`makeFastTrack`) for audio
     - async metadata parse pool (bounded workers) with `autoreleasepool` per file
     - incremental 500-track SQLite flushes during enrichment (rolling buffer)
     - video classification refresh
- APIs now using this path:
  - `scanFolder`
  - `rescanWatchFolder`
  - `rescanWatchFolders`
  - `addTracks(urls:)` via `importMedia(...)`
- Worker policy:
  - non-local volumes -> 2 workers
  - local volumes -> CPU-based bounded worker count

### 3) Fast ingest Track path

File: `Sources/NullPlayer/Data/Models/Track.swift`

Implemented:

- `init(lightweightURL:)` to avoid eager AVFoundation metadata reads during bulk enqueue/import.

### 4) UI entry points switched to shared async discovery

Files:

- `Windows/MainWindow/MainWindowView.swift`
- `Windows/ModernMainWindow/ModernMainWindowView.swift`
- `Windows/Playlist/PlaylistView.swift`
- `Windows/ModernPlaylist/ModernPlaylistView.swift`
- `Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift`
- `Windows/PlexBrowser/PlexBrowserView.swift`
- `Audio/AudioEngine.swift` (`loadFolder`)

Implemented:

- Replaced synchronous recursive enumeration with `LocalFileDiscovery` async discovery.
- Unified extension filtering and directory behavior across classic + modern paths.
- Drop acceptance now uses shared supported-content checks.

### 5) UI/persistence churn reduction

Files:

- `Data/Models/MediaLibrary.swift`
- `Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift`
- `Windows/PlexBrowser/PlexBrowserView.swift`

Implemented:

- Debounced local-library reload on `MediaLibraryDidChange` in both browsers (0.30s work-item debounce).
- Mode-aware `loadLocalData()` in both browsers (load only required datasets for current mode).
- Scan progress throttling:
  - emit when delta >= 0.02 or >= 0.20s elapsed, plus forced boundary emits.
- Incremental batch flushing (replaces old JSON save coalescing):
  - Metadata enrichment uses a rolling 500-track `pendingMetadata` buffer
  - Each full batch is flushed immediately to SQLite and in-memory state via `flushPendingMetadata()`
  - Remaining tracks flushed after `metadataGroup.wait()`
  - `autoreleasepool` wraps `parseMetadata` per file to release AVAsset objects promptly
  - Prevents unbounded memory accumulation for large libraries (60k+ tracks)
- SQLite is the persistence layer — no JSON library file.

## NAS Playback Responsiveness State

### Implemented

Files:

- `Sources/NullPlayer/Audio/AudioEngine.swift`
- `Sources/NullPlayer/Waveform/BaseWaveformView.swift`

Implemented:

- Background deferred I/O queue for non-critical file operations (`deferredIOQueue`).
- Token-guarded async operations:
  - normalization analysis
  - gapless pre-open
  - direct local track load (`deferredLocalTrackLoadToken`)
- `playTrack(at:)` now routes direct local audio selections through async open:
  - `loadLocalTrackForImmediatePlayback(_:at:)`
  - stale completion dropped unless token + index + track ID still match
- Shared local-load preparation/commit/failure helpers:
  - `prepareForLocalTrackLoad`
  - `commitLoadedLocalTrack`
  - `handleLocalTrackLoadFailure`
- Cue-sheet parsing moved off main in waveform base view:
  - async/cancellable cue parse task (`cueLoadTask`)

### Known Remaining Risk

- Some non-direct local transitions still use synchronous `loadTrack -> loadLocalTrack` (for example parts of auto-advance/crossfade paths).  
  If NAS stalls are still observed outside direct playlist clicks, migrate those paths to deferred open with the same token model.

## Verification State

Latest run (2026-03-13, post incremental-flush):

- Command: `swift test --filter NullPlayerTests`
- Result: 317 tests executed, 0 failures

Added tests:

- `Tests/NullPlayerTests/LocalFileDiscoveryTests.swift`

## Fixed: Post-Import UI Freeze (60k+ libraries)

Root cause: `buildLocalArtistItems()` called `store.albumsForArtist(name)` once per artist on the current page (200 calls). Each query used `WHERE coalesce(album_artist, artist, 'Unknown Artist') = ?` which could not use the existing `idx_tracks_artist` column index — SQLite cannot index through a coalesce() expression. Each query was a full table scan of 60k rows. 200 queries × full scan = ~12M row reads on the main thread → minutes-long UI freeze.

Fixes applied:
- `MediaLibraryStore`: schema v2 migration adds expression index `idx_tracks_artist_expr ON library_tracks (coalesce(album_artist, artist, 'Unknown Artist'))`. New DBs created at v2. Existing v1 DBs migrated automatically on next open.
- `MediaLibraryStore.albumsForArtistsBatch(_:)`: new method that fetches album summaries for a full page of artists in a single SQL query (using IN clause) instead of one per artist. Reduces 200 queries → 1.
- Both `ModernLibraryBrowserView.buildLocalArtistItems()` and `PlexBrowserView.buildLocalArtistItems()` (including the scroll/load-more paths) use the batch method.

## Resume Checklist For Next Agent

1. Reproduce on NAS:
   - direct click switch large WAV -> MP3
   - keyboard next/previous
   - auto-advance and Sweet Fades transitions
2. If any remaining stall appears:
   - instrument open-time logs in the transition path
   - migrate that path to deferred open + token cancellation (pattern already in `loadLocalTrackForImmediatePlayback`)
3. Add/expand tests:
   - incremental scan correctness (unchanged skip, changed re-enrich, removed prune)
   - watch-folder overlap edge cases after incremental pruning
4. Keep final-save guarantees:
   - coalesced writes during bulk work
   - forced flush at terminal state.
