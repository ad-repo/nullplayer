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

All rows here were opened 2026-09-23 out of a single live report — *"the anika nilles clips in the
playlist wont play, there is something wrong with playlist playback"*.

## What the report actually was

Established 2026-09-23 from the pre-repair `UPDATE` statement, recovered from the session that ran
it. **The rows had been hand-repaired in SQL before any live-library measurement in this file was
taken**, so every reading of the database describes the repaired state; the statement itself is the
only surviving evidence of the original one, and it is exact:

```sql
UPDATE library_tracks        SET url = replace(url, OLD, NEW) WHERE url LIKE OLD || '%';
UPDATE library_playlists     SET url = replace(url, OLD, NEW) WHERE …;
UPDATE library_watch_folders SET url = NEW                    WHERE url = OLD;
--  OLD = file:///Users/ad/Library/Mobile%20Documents/com~apple~CloudDocs/music/
--  NEW = file:///Users/ad/iCloud%20Drive%20(Archive)/music/
```

**A watch root moved and nothing noticed.** `~/Library/Mobile Documents/com~apple~CloudDocs/` no
longer exists at all — the tree now lives at `~/iCloud Drive (Archive)/`, which is the name macOS
gives the local copy it leaves behind when iCloud Drive is turned off. Every row under that root
went stale at once: the track rows, the playlist row, **and the `library_watch_folders` row itself**,
which is why the repair had to re-point three tables and why a rescan could not have healed it —
the root it would have rescanned was the one that had gone.

So the chain was: relocated watch root → rows pointing at paths that no longer exist → the file
fails to open → **L1** ends the queue and, outside Classic, says nothing. That is **L2 plus L1**.
It is not L3, and L3's diagnosis does not survive the pre-repair evidence — see Closed.

## Open

| ID | Item | Evidence | Notes |
|---|---|---|---|
| L2 | Nothing ever re-resolves a track that is not at its recorded path | **Measured 2026-09-23**: no bookmark, no relocation pass, no path re-resolution anywhere. `grep` over `Sources/` for `UPDATE library_tracks`, `SET url` and `relocat` returns **nothing**. **Reproduced, on the report itself**: a watch root moved from `~/Library/Mobile Documents/com~apple~CloudDocs/music/` to `~/iCloud Drive (Archive)/music/` and orphaned every row beneath it — tracks, the playlist row, and the watch-folder row. Only a hand-written SQL `replace()` across three tables recovered them | **This is the row the report was actually about, and it is now the top of the file.** The reach is not "iCloud" — it is any watch folder on a detached drive, an unmounted NAS, or a directory the user reorganised — but the instance in hand is a real relocated root, not a hypothetical, and it argues for **re-resolution over a locate/forget affordance**: the user's own remedy was a prefix rewrite, which is exactly what a relocation pass would do automatically. **Any fix must re-point `library_watch_folders` too**, or the next scan runs against a root that is no longer there and finds nothing. **The second class, still real and different**: 60 absent track rows measured in the live library, all outside every watch root (57 under a deleted `~/Downloads/` folder, 3 scratchpad `.mp4`s in `library_movies`) — one-off `Add Files…` entries whose source was later cleaned up, which relocation cannot help and which want a forget affordance instead. The post-repair "0 absent inside a watch root" reading is **worthless as evidence** and is recorded here only so it is not re-derived: the repair is what made it zero |
| L4 | `removeMissingItemsInWatchedFolders` has no callers | **Measured 2026-09-23**: `Sources/NullPlayer/Data/Models/MediaLibrary.swift:2602`, declared `private`, and the only occurrence of the name in `Sources/` and `Tests/` is its own declaration. It has never run | **Do not simply call it — that is the trap this row exists to record, and the pre-repair evidence confirms it rather than softening it.** It deletes a track, movie or episode whose file is absent from a watched folder. Before the repair the two reported rows were *exactly* that: absent at their recorded path, and inside a watch folder — the stale one. Had this function ever run, it would have deleted two rows whose files were fine all along, sitting untouched one directory rename away. **An unmounted NAS, a signed-out iCloud Drive and a deleted folder are indistinguishable to `fileExists`**, and there is already volume-mount awareness beside it (`MediaLibrary.swift:2287`) that any live version has to be gated on. **A post-repair count of "0 rows would be deleted today" was taken and is not evidence** — the repair had already removed what it would have eaten. **Rank it behind L2**: deletion is the wrong response to "not at the recorded path" until re-resolution exists to rule out relocation first |

## Closed

| ID | Item | Evidence | Notes |
|---|---|---|---|
| L1 | A track that fails to load halts the playlist, and says nothing outside the Classic skin | **Measured 2026-09-23**: `AudioEngine.handleLocalTrackLoadFailure` (`Sources/NullPlayer/Audio/AudioEngine.swift:4658`) calls `stopPlaybackOnError()`, which clears `currentTrack`, sets `state = .stopped` and stops the time updates. A tree-wide grep for a skip-on-failure path returns **nothing** | **This is the row that turned two bad rows into "playlist playback is broken".** The failure is announced once, as `.audioTrackDidFailToLoad`, and has exactly one user-visible consumer: `Windows/MainWindow/MainWindowView.swift:245`, the **Classic** skin's marquee. `App/AppDelegate.swift:689` logs it and explicitly defers the UI to that notification. `Windows/WMPSkin/`, `Windows/ModernMainWindow/` and `Windows/WinampModern/` register **no observer at all**, so in three of the four skin modes the player stops dead and reports nothing. **Two separable halves — do not fold them**: whether an unreadable track should advance rather than end the queue (shared `AudioEngine`, blast radius across all four skin modes and casting), and whether the other three engines should surface the message Classic already has. The second is the smaller and safer one. |

**Closed by** `Say a track failed to load in every skin mode, not only Classic (L1)` and `Advance past a
track that will not open, instead of ending the queue (L1)`, kept as the two separate halves the row
asked for. **Correction to the row's own evidence**, from reading the code rather than the database,
so the hand-repair does not bear on it: the grep missed one — `loadTrack(at:)` already skipped on a
`false` return from `loadLocalTrack`. It was the asynchronous `loadLocalTrackForImmediatePlayback` —
the path `playTrack` and the natural end-of-track advance both use — that dead-ended, and that is the
one the user hits. The synchronous skip had its own defect: the failure handler sets `.stopped` on the
way through it, so `next()`'s `if state == .playing` never fired and the queue sat paused on the track
it had just skipped to. `Windows/WMPSkin/` does not exist on `main`, so the surfacing half landed in
the two modes that do.

| ID | Item | Evidence | Notes |
|---|---|---|---|
| L3 | A relative-path playlist resolves its entries against the playlist's own recorded directory, and nothing validates the result | **Reproduced 2026-09-23** on the report's own data: `Those Hills - Anika Nilles.m3u` lists `01 - … .flac` and `02 - … .flac` with **no directory**, and both library rows carry the playlist row's root. `file_size`, `duration` (298.21 s) and `bitrate` (1019 kbps) were all written | **One wrong root on the playlist file silently poisons every track it lists**, and the rows look fully populated afterwards — real sizes, real durations, real bitrates — so nothing downstream can tell them from good ones. **The rows are written without ever checking that the resolved file exists.** That check is the cheap half of this row and is worth taking on its own. **Unmeasured and the number to take next**: how many playlists in the corpus library use relative entries, and whether any other rows were written the same way. |

**Closed as a misdiagnosis, not as fixed.** The pre-repair `UPDATE` shows the rows carried the **old
watch root**, not the playlist file's root — they coincide only because the playlist sits in the same
relocated tree, and the row read that coincidence as causation. The rows were written correctly by
the ordinary scanner, against a root that later moved; that is L2. Two things in the row do not
survive: no library row is ever written from a playlist *entry* (a tree-wide search found no such
writer — `addTracks` validates existence through `AudioFileValidator.quickValidate`, and
`importMedia` persists only the playlist **file** location, never its contents), and the fully
populated `file_size`/`duration`/`bitrate` were evidence of a *good* scan, not a poisoned one. The
existence check the row asked for shipped anyway, under L5, because it is worth having on its own.

| ID | Item | Evidence | Notes |
|---|---|---|---|
| L5 | Every playlist loader read a relative entry as a URL, not a path, so relative entries loaded as something unplayable | **Probed directly 2026-09-23**, independent of any library state and so unaffected by the hand-repair: on current Foundation `URL(string: "01 - Those Hills.flac")` returns a **schemeless, non-file URL** — `isFileURL` false, `scheme` nil — rather than nil. Absolute paths with spaces come back the same way | Found while investigating L3 and real on its own terms, but **not the cause of the report**: those tracks were queued fresh from library rows, whose URLs were absolute and stale, so they never went through a playlist loader. Five loaders each tested `URL(string:)` for nil to decide "absolute or relative", so the absolute branch ran for **every** entry and the relative branch was dead code in all five; the resulting URLs matched neither `isFileURL` nor an `http` scheme at load time and could not open. `Playlist.resolveEntry` is now the one answer to what an entry means, shared by all five; only a scheme longer than one character counts, so a Windows drive letter is not read as a `c:` URL. Both library browsers now check the resolved file exists and report what does not through `AudioFileValidator`, which as of L1 reaches the marquee in every skin mode |

**Closed by** `Resolve a playlist entry as a path, and check the file is there (L3)` — filed against
L3 before the hand-repair was known, which is why the commit message argues it corrected L3's
diagnosis. It did not: it fixed an unrelated defect that would have produced a similar symptom.
