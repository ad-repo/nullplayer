---
name: cue-sheets
description: .cue sheet support — direct-play virtual split (open a .cue or an audio file with a sibling .cue → N playlist rows from one backing file, gapless) and library physical split-on-import (ffmpeg per-track files, off by default). Use when working on cue parsing, the AudioEngine cue boundary detector, in-file offset playback, or CueAlbumSplitter.
---

# .cue Sheet Support

Two **independent** code paths that consume `.cue` sheets. The Stream Ripper *writes* cues (one TRACK per chapter — see the **stream-ripper** skill); this feature *reads* them.

- **Part A — Direct play (virtual split):** open a `.cue`, or an audio file with a sibling `.cue`, and the single backing file is played **virtually split** into its cue tracks → N rows in the now-playing playlist. Nothing is written to disk; nothing is added to the Local Library. Satisfies issue #273.
- **Part B — Library split-on-import (off by default):** when the toggle is on, a `.cue` encountered by the Local Library scan causes the backing file to be **physically split into per-track FLACs** via ffmpeg; those are added to the library and the original is excluded. When off, the scan ignores `.cue` files entirely and imports the backing file as one normal track.

The two paths share only the parser. Part A is unaffected by the Part B toggle.

## Key files

| Area | File |
|------|------|
| Shared parser | `Data/Models/CueSheet.swift` |
| Track cue fields | `Data/Models/Track.swift` (`cueStartOffset`, `cueEndOffset`, `cueSourceURL`, `isCueTrack`) |
| Playback + boundary detector + entry helper | `Audio/AudioEngine.swift` |
| Part B discovery | `Utilities/LocalFileDiscovery.swift` (`cueExtensions` / `cueFiles` bucket) |
| Part B splitter | `Utilities/CueAlbumSplitter.swift` |
| Part B scan pre-pass + exclusion + pref threading | `Data/Models/MediaLibrary.swift` |
| Part B toggle UI | `App/ContextMenuBuilder.swift` (`cueSplitOnImportEnabled`) |
| Entry points (Part A) | `App/AppDelegate.swift`, `Windows/MainWindow/MainWindowView.swift`, `Windows/ModernMainWindow/ModernMainWindowView.swift`, `Windows/Playlist/PlaylistView.swift`, `Windows/ModernPlaylist/ModernPlaylistView.swift`, `Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift`, `Windows/PlexBrowser/PlexBrowserView.swift` |
| Tests | `Tests/NullPlayerAppTests/CueSheetTests.swift`, `AudioEngineCueBoundaryDetectorTests.swift`, `CueAlbumSplitterTests.swift` |

## Shared parser — `CueSheet.swift`

`CueSheet` holds top-level `performer` (→ artist fallback), `title` (→ album), `fileName` (first FILE only), and `[Entry]` (`number`, `title`, `performer?`, `startTime`).

- `parse(from:) throws` — line scan; top-level vs track-level `PERFORMER`/`TITLE` are disambiguated by whether `FILE` has been seen yet. `INDEX 01` preferred, `INDEX 00` as fallback. Multiple `FILE` entries → warn, use first only. Throws if no `FILE`, or if `entries.count > CueSheet.maxEntries` (10 000 — DoS guard against a pathological cue spawning unbounded jobs/rows).
- `parseCueTimestamp(_:)` — inverse of the writer's `cueTimestamp`: `MM:SS:FF` @ **75 fps** → seconds. Must round-trip with `StreamRipper.cueTimestamp`.
- `resolveBackingFile(for:fileName:)` — absolute paths honored; relative resolved against the cue's directory. **Untrusted-input guard:** a relative path that escapes the cue's own directory (`../../…`) is treated as missing (returns a non-existent sentinel) rather than reading an arbitrary file. A `.cue` travels with downloaded media — treat it as untrusted.
- `siblingCue(for:)` — returns `<basename>.cue` next to an audio file if present.
- `expandToTracks(cue:cueFileURL:)` — virtual `[Track]` for Part A. Empty cue → `[]`. For entry *i*: `cueStartOffset = entries[i].startTime`, `cueEndOffset = entries[i+1].startTime` (**guarded** `i+1 < count`; `nil` for the last entry → play to EOF). A missing backing file is just a cue track whose `url` doesn't exist → the engine's load-failure skip shows it as an unplayable row.

## Part A — playback (`AudioEngine.swift`)

- **Entry helper** `tracksForCueOrSibling(url:) -> [Track]?` — every entry point calls this before the normal Track-from-URL path: returns expanded tracks for a `.cue`, or for an audio file with a sibling cue, else `nil`.
- **Load:** a cue track schedules `scheduleSegment` from `cueStart*sr` **to EOF** (not to `cueEnd`), `.dataPlayedBack`, generation-guarded — the continuous schedule is what makes gapless possible. `_currentTime`/`lastReportedTime` reset to 0 so the clock is 0-relative; the boundary base index resets.
- **`duration` getter:** `cueEnd - cueStart`, or `fileDuration - cueStart` when `cueEnd == nil`.
- **Seek:** clamps to `[0, duration]`, then offsets by `cueStart` and reschedules to EOF.
- **Gapless boundary detector** `advanceCueTrackIfBoundaryCrossed()` (called from the 0.1 s time-update timer) wraps the pure, unit-tested decision `shouldAdvanceCueTrackAtBoundary(...)`. When `currentTime >= cueEnd` and the next playlist entry is a **same-`cueSourceURL`** cue track, it advances `currentIndex`/`currentTrack`, resets `_currentTime`/`lastReportedTime`, and **resets `playbackStartDate = Date()`** (without this the 0-relative clock keeps climbing). Audio is untouched → no gap; `currentTrack` didSet posts the change so title/seek-bar/Now Playing update.

  **Gapless is provided only with shuffle off and repeat-single off.** The detector returns early under shuffle or repeat-single (it assumes the next track is `playlist[currentIndex+1]`, which is false under shuffle) and guards `currentIndex+1 < playlist.count`. In those modes the schedule runs to real EOF and the normal `trackDidFinish` path advances (a gap is acceptable — documented limitation).

## Part B — library split (`CueAlbumSplitter.swift`, off by default)

Gated by UserDefaults bool **`cueSplitOnImportEnabled`** (default `false`, mirrors the `includeLegacyWMA` scan-flag pattern). When off, `LocalFileDiscovery` does not collect `.cue` files and `MediaLibrary` excludes nothing.

`LocalFileDiscovery` exposes a **separate** `cueExtensions = ["cue"]` / `cueFiles` bucket — do **not** reuse `playlistExtensions` (that would make cues into `LocalPlaylist` browser nodes). The `MediaLibrary` scan runs a pre-pass before the cleanup loop: for each cue, `CueAlbumSplitter.splitIfNeeded(cueURL:)` returns a `SplitOutcome { backingFileToExclude, trackFiles }`:

1. `shouldPerformSplit` compares the **deterministic** expected output paths (`computeOutputPath(..., checkFilesystem: false)`) against disk. All present → idempotent skip, returns the backing file + existing track files. Any missing → split.
2. **Per-album subdirectory:** outputs go into `<cueDir>/<Artist - Album>/` — named from the **source file's own `ALBUM`/`ARTIST` tags** read via `ffprobe` (`sourceTags`), falling back to the cue's `PERFORMER`/`TITLE`, then the cue filename. (The cue's `TITLE` from the Stream Ripper is the video/show title — the *track* name — not the album, so the file tags are preferred.) `sourceTags` is deterministic, so `expectedOutputPaths` and `performSplit` compute the **same** folder → idempotency holds.
3. **Output is always re-encoded FLAC** (`-c:a flac`, not `-c copy` — copy isn't sample-accurate at cut points) for both lossless and lossy sources, as `NN - <sanitized title>.flac`.
4. Filenames/folder are sanitized via `sanitizeFilenameComponent`: replace `/ \ : * ? " < > |` + control chars with `_`, collapse whitespace, trim leading/trailing spaces+dots, NFC-normalize, truncate ~200 UTF-8 bytes; track filenames also de-dup with ` (2)`, ` (3)`.
5. ffmpeg args (mirroring `StreamRipper`'s Process/`[String]` pattern — never a shell string): `-ss`/`-to` (last track omits `-to`), **`-map_metadata 0`** (inherit the source's date/genre/cover-art tags), then override per-track `title` + `track=N/total`, and `artist`/`album`/`album_artist` from the **source tags** (`sourceTags`), falling back to cue values, only writing non-empty values so an inherited field is never blanked. **Cover art is conditional** — the `-map 0:v:0 -c:v copy -disposition:v attached_pic` group is added **only if** `ffprobe` finds a video/attached-pic stream.
6. **Skip+warn** when ffmpeg is absent, or on any write/permission/space failure: do **not** split, do **not** exclude the original, post a one-time notice. The original is excluded **iff** its split tracks actually exist.

`MediaLibrary` then: (a) removes any backing file in the "successfully split" set from `tracks`/`tracksByPath`/store **and from `audioMetadataTasks`** (critical — the enrichment pass would otherwise re-insert the backing under its own tags), and (b) adds the returned `trackFiles` to the library in-scan (they're written into a subdir created *after* discovery enumerated audio, so discovery didn't see them). Cue files are never upserted as tracks or playlists.

**Reading FLAC/M4A tags (`MediaLibrary.parseMetadata`):** AVFoundation exposes `title`/`artist`/`album` via common keys, but **album-artist** and **track/disc number** are not common keys — they were only read from ID3 (`TPE2`/`TRCK`/`TPOS`), so FLAC/M4A came back nil. `parseMetadata` now scans all metadata formats for Vorbis `ALBUMARTIST`/`TRACKNUMBER`/`DISCNUMBER` (and iTunes `aART`/`trkn`/`disk`), parsing the leading int from `"1/10"`. Without these, cue-split FLAC albums fragmented by per-track artist and lost their track ordering.

## Gotchas

- **Idempotency seeding:** `performSplit` seeds the de-dup set with the cue's *full* deterministic canonical path set up front, so an already-split track on a partial re-run is recognized as our own output and reused — never re-encoded into a `(2)` duplicate. (Trade-off: two *different* cues in the same folder producing identically-named tracks will overwrite rather than `(2)`; idempotency is the priority.)
- **Outputs land in a subdir of the cue's directory** (`<cueDir>/<Artist - Album>/`), never relative to the backing file — there is no write-side path traversal.
- **MAS sandbox:** writing split files next to a scanned `.cue` needs the containing folder covered by a writable security-scoped bookmark. If watch folders aren't writable under the sandbox, Part B no-ops via skip+warn. Confirm before relying on Part B in the MAS build, or treat it as DMG-only.
- **`Sources/NullPlayerCore/Models/Track.swift` is NOT modified** — the cue fields live only on the Data/Models `Track` used by `AudioEngine.playlist`.
- Out of scope: embedded FLAC `CUESHEET`/Vorbis tags; multiple `FILE` entries per cue (first only); `INDEX 00` pregap beyond the start-time fallback.
