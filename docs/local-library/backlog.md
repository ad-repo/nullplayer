# Local library and playlist playback — open backlog

The two skin backlogs in this repo — `WMP_TASKS.md` for `.wmz` and
[`WINAMP5_TASKS.md`](../../WINAMP5_TASKS.md) for `.wal` — each say a foreign entry does not belong
in them, and [`docs/video-playback/backlog.md`](../video-playback/backlog.md) took the shared video
path for the same reason. This file is for defects in the **local library and the playlist playback
path** — `Data/Models/MediaLibrary.swift`, `Utilities/LocalFileDiscovery.swift` and
`Audio/AudioEngine.swift`'s track-load failure handling — which belong to none of the above. Owning
skills: `local-library` for the scanner and store, `audio-system` for playback.

Same conventions as the skin backlogs: one row per reproducible defect, the evidence it was ranked
on, and **what is measured kept separate from what is inferred**. A closed row moves out with the
change that closes it.

All four rows below were opened 2026-09-23 out of a single live report — *"the anika nilles clips in
the playlist wont play, there is something wrong with playlist playback"*. **The report was right
about the symptom and the cause was none of the things it looked like**, which is why the rows are
kept separate: one bad pair of rows in a 300-track library presented as the whole playlist being
broken, and three separate gaps had to line up for that to happen.

> **The reported pair was manually repaired before any of the 2026-09-23 database measurements
> below were taken.** Every number read off the live library therefore describes the library
> *after* that repair and **cannot speak to the state the rows were in when the report was
> filed**. Rows L2, L3 and L4 all turn on that state. A measurement taken after a repair is not
> evidence about what was repaired.

## Open

| ID | Item | Evidence | Notes |
|---|---|---|---|
| L2 | Nothing ever re-resolves a track that is not at its recorded path | **Measured 2026-09-23**: no bookmark, no relocation pass, no path re-resolution anywhere. `grep` over `Sources/` for `UPDATE library_tracks`, `SET url` and `relocat` returns **nothing**. **Measured against the live library 2026-09-23, after the manual repair** (389 track rows, 2 watch roots): **60 absent track rows, every one of them outside any watch root** — 57 under `~/Downloads/<a deleted concert folder>/` and 3 scratchpad `.mp4` rows in `library_movies`; 0 of the 300 rows inside a watch root are absent | A moved, renamed or re-rooted folder orphans its rows permanently, and the only signal the user got was L1's silent stop (now a marquee message in every mode, and the queue continues). **The reach is not "iCloud"** — it is any watch folder on a detached drive, an unmounted NAS, or a directory the user reorganised. **What the 60 rows are good for and what they are not**: they are outside every watch root and were not touched by the repair, so they are real evidence of one class — one-off `Add Files…` entries whose source folder was later cleaned up, which argues for a locate/forget affordance over security-scoped bookmarks. The "0 inside a watch root" half is **post-repair and proves nothing**: the repaired pair lived inside a watch root, and the repair is exactly what would have cleared it. It is also one library with neither watch root on a removable volume, so the NAS and detached-drive cases stay unmeasured. Take a second corpus, and one that has not been hand-fixed |
| L3 | A relative-path playlist resolves its entries against the playlist's own recorded directory, and nothing validates the result | **Reproduced 2026-09-23** on the report's own data: `Those Hills - Anika Nilles.m3u` lists `01 - … .flac` and `02 - … .flac` with **no directory**, and both library rows carry the playlist row's root. `file_size`, `duration` (298.21 s) and `bitrate` (1019 kbps) were all written | **One wrong root on the playlist file silently poisons every track it lists**, and the rows look fully populated afterwards — real sizes, real durations, real bitrates — so nothing downstream can tell them from good ones. **The rows are written without ever checking that the resolved file exists.** **Status after the loader fix below**: the playback half of the reported symptom is closed, but **this row's own claim is untouched and unrefuted**. A re-measure on 2026-09-23 found both files present, both rows correct and both opening cleanly under `AVAudioFile` — but that was taken *after* the manual repair, so it says nothing about how the rows were written. **What is new and does stand**: a tree-wide search for a path that writes a `library_tracks` row from a playlist *entry* found none — `addTracks` validates existence via `AudioFileValidator.quickValidate` before importing, and `importMedia` persists only the playlist **file** location, never its contents. So either the rows were written by the ordinary scanner and the wrong root came from somewhere else, or the writer is a path that search missed. **The number to take next is unchanged and the live library cannot answer it**: it holds exactly one playlist row. Needs a corpus with relative-entry playlists that has not been hand-fixed |
| L4 | `removeMissingItemsInWatchedFolders` has no callers | **Measured 2026-09-23**: `Sources/NullPlayer/Data/Models/MediaLibrary.swift:2602`, declared `private`, and the only occurrence of the name in `Sources/` and `Tests/` is its own declaration. It has never run | **Do not simply call it — that is the trap this row exists to record.** It deletes a track, movie or episode whose file is absent from a watched folder, and the report that opened this backlog is precisely the case where that would have been wrong: two rows whose files are fine would have been permanently deleted along with their play counts and ratings. **The trap stands, and a post-repair measurement briefly appeared to retire it — it did not.** The reported pair sits under `~/iCloud Drive (Archive)/music/`, which **is** a watch root, so whatever absent path those rows carried before the repair was squarely in this function's reach. The "it would delete 0 rows today" reading was taken after the repair had already removed the rows it would have eaten. **An unmounted NAS and a deleted folder are indistinguishable to `fileExists`**, and there is already volume-mount awareness beside it (`MediaLibrary.swift:2287`) that any live version has to be gated on. **Rank it behind L2**: deletion is the wrong response to "not at the recorded path" until re-resolution exists to rule out relocation first |

## Closed

| ID | Item | Evidence | Notes |
|---|---|---|---|
| L1 | A track that fails to load halts the playlist, and says nothing outside the Classic skin | **Measured 2026-09-23**: `AudioEngine.handleLocalTrackLoadFailure` (`Sources/NullPlayer/Audio/AudioEngine.swift:4658`) calls `stopPlaybackOnError()`, which clears `currentTrack`, sets `state = .stopped` and stops the time updates. A tree-wide grep for a skip-on-failure path returns **nothing** | **This is the row that turned two bad rows into "playlist playback is broken".** The failure is announced once, as `.audioTrackDidFailToLoad`, and has exactly one user-visible consumer: `Windows/MainWindow/MainWindowView.swift:245`, the **Classic** skin's marquee. `App/AppDelegate.swift:689` logs it and explicitly defers the UI to that notification. `Windows/WMPSkin/`, `Windows/ModernMainWindow/` and `Windows/WinampModern/` register **no observer at all**, so in three of the four skin modes the player stops dead and reports nothing. **Two separable halves — do not fold them**: whether an unreadable track should advance rather than end the queue (shared `AudioEngine`, blast radius across all four skin modes and casting), and whether the other three engines should surface the message Classic already has. The second is the smaller and safer one. |

**Closed by** `Say a track failed to load in every skin mode, not only Classic (L1)` and `Advance past a
track that will not open, instead of ending the queue (L1)`, kept as the two separate halves the row
asked for. **Correction to the row's own evidence**, from reading the code rather than the database,
so the manual repair does not bear on it: the grep missed one — `loadTrack(at:)` already skipped on a
`false` return from `loadLocalTrack`. It was the asynchronous `loadLocalTrackForImmediatePlayback` —
the path `playTrack` and the natural end-of-track advance both use — that dead-ended, and that is the
one the user hits. The synchronous skip had its own defect: the failure handler sets `.stopped` on the
way through it, so `next()`'s `if state == .playing` never fired and the queue sat paused on the track
it had just skipped to. `Windows/WMPSkin/` does not exist on `main`, so the surfacing half landed in
the two modes that do.

| ID | Item | Evidence | Notes |
|---|---|---|---|
| L5 | Every playlist loader read a relative entry as a URL, not a path, so relative entries loaded as something unplayable | **Probed directly 2026-09-23**, independent of any library state: on current Foundation `URL(string: "01 - Those Hills.flac")` returns a **schemeless, non-file URL** — `isFileURL` false, `scheme` nil — rather than nil. Absolute paths with spaces come back the same way | Opened and closed together, out of L3's symptom: this is the half of "the anika nilles clips wont play" that is a playback defect rather than a library one. Five loaders each tested `URL(string:)` for nil to decide "absolute or relative", so the absolute branch ran for **every** entry and the relative branch was dead code in all five. The resulting URLs matched neither `isFileURL` nor an `http` scheme at load time, failed to open, and L1 then ended the queue in silence. `Playlist.resolveEntry` is now the one answer to what an entry means, shared by all five; only a scheme longer than one character counts, so a Windows drive letter is not read as a `c:` URL. Both library browsers now check the resolved file exists and report what does not through `AudioFileValidator`, which as of L1 reaches the marquee in every skin mode. **This does not close L3** — it is a different layer, and L3's claim is about how library rows are written |

**Closed by** `Resolve a playlist entry as a path, and check the file is there (L3)` — filed against
L3 before the manual repair was known, which is why the commit message argues it corrected L3's
diagnosis. It did not: it fixed a separate defect that produced the same symptom.
