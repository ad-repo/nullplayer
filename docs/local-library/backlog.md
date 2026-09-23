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

## Open

| ID | Item | Evidence | Notes |
|---|---|---|---|
| L2 | Nothing ever re-resolves a track that is not at its recorded path | **Measured 2026-09-23**: no bookmark, no relocation pass, no path re-resolution anywhere. `grep` over `Sources/` for `UPDATE library_tracks`, `SET url` and `relocat` returns **nothing**. **Measured against the live library 2026-09-23** (389 track rows, 2 watch roots): **60 absent track rows, every one of them outside any watch root** — 57 under `~/Downloads/<a deleted concert folder>/` and 3 scratchpad `.mp4` rows in `library_movies`. **0 of 300 rows inside a watch root are absent** | A moved, renamed or re-rooted folder orphans its rows permanently, and the only signal the user got was L1's silent stop (now a marquee message in every mode, and the queue continues). **The reach is not "iCloud"** — it is any watch folder on a detached drive, an unmounted NAS, or a directory the user reorganised. **The one measured corpus says the live class is a different one**: not a relocated watch root, but one-off `Add Files…` entries whose source folder was later cleaned up. That is an argument for a user-facing locate/forget affordance over security-scoped bookmarks, but it is **one library, and neither of its watch roots is on a removable volume** — the NAS and detached-drive cases remain entirely unmeasured. Take a second corpus before designing |
| L4 | `removeMissingItemsInWatchedFolders` has no callers | **Measured 2026-09-23**: `Sources/NullPlayer/Data/Models/MediaLibrary.swift:2602`, declared `private`, and the only occurrence of the name in `Sources/` and `Tests/` is its own declaration. It has never run | **Do not simply call it.** The trap this row was opened to record — that it would have deleted the reported pair — **did not survive measurement**: both reported files are present on disk, their rows are correct, and they sit inside a watch root, so this function would not have touched them. On the live library it would delete **0 rows** today, because every absent row is outside a watched folder and this only walks watched ones. What stands, and is still unmeasured, is the case the row was really about: **an unmounted NAS and a deleted folder are indistinguishable to `fileExists`**, and there is already volume-mount awareness beside it (`MediaLibrary.swift:2287`) that any live version has to be gated on. **Still ranked behind L2**: deletion is the wrong response to "not at the recorded path" until re-resolution exists to rule out relocation first |

## Closed

| ID | Item | Evidence | Notes |
|---|---|---|---|
| L1 | A track that fails to load halts the playlist, and says nothing outside the Classic skin | **Measured 2026-09-23**: `AudioEngine.handleLocalTrackLoadFailure` (`Sources/NullPlayer/Audio/AudioEngine.swift:4658`) calls `stopPlaybackOnError()`, which clears `currentTrack`, sets `state = .stopped` and stops the time updates. A tree-wide grep for a skip-on-failure path returns **nothing** | **This is the row that turned two bad rows into "playlist playback is broken".** The failure is announced once, as `.audioTrackDidFailToLoad`, and has exactly one user-visible consumer: `Windows/MainWindow/MainWindowView.swift:245`, the **Classic** skin's marquee. `App/AppDelegate.swift:689` logs it and explicitly defers the UI to that notification. `Windows/WMPSkin/`, `Windows/ModernMainWindow/` and `Windows/WinampModern/` register **no observer at all**, so in three of the four skin modes the player stops dead and reports nothing. **Two separable halves — do not fold them**: whether an unreadable track should advance rather than end the queue (shared `AudioEngine`, blast radius across all four skin modes and casting), and whether the other three engines should surface the message Classic already has. The second is the smaller and safer one. |

**Closed by** `Say a track failed to load in every skin mode, not only Classic (L1)` and `Advance past a
track that will not open, instead of ending the queue (L1)`, kept as the two separate halves the row
asked for. **Correction to the row's own evidence**: the grep missed one — `loadTrack(at:)` already
skipped on a `false` return from `loadLocalTrack`. It was the asynchronous
`loadLocalTrackForImmediatePlayback` — the path `playTrack` and the natural end-of-track advance
both use — that dead-ended, and that is the one the user hits. The synchronous skip had its own
defect: the failure handler sets `.stopped` on the way through it, so `next()`'s `if state ==
.playing` never fired and the queue sat paused on the track it had just skipped to.
`Windows/WMPSkin/` does not exist on `main`, so the surfacing half landed in the two modes that do.

| ID | Item | Evidence | Notes |
|---|---|---|---|
| L3 | A relative-path playlist resolves its entries against the playlist's own recorded directory, and nothing validates the result | **Reproduced 2026-09-23** on the report's own data: `Those Hills - Anika Nilles.m3u` lists `01 - … .flac` and `02 - … .flac` with **no directory**, and both library rows carry the playlist row's root. `file_size`, `duration` (298.21 s) and `bitrate` (1019 kbps) were all written | **One wrong root on the playlist file silently poisons every track it lists**, and the rows look fully populated afterwards — real sizes, real durations, real bitrates — so nothing downstream can tell them from good ones. **The rows are written without ever checking that the resolved file exists.** That check is the cheap half of this row and is worth taking on its own. **Unmeasured and the number to take next**: how many playlists in the corpus library use relative entries, and whether any other rows were written the same way. |

**Closed by** `Resolve a playlist entry as a path, and check the file is there (L3)`. **Correction to
the row's own diagnosis**: both files are present, both library rows are correct, and both open
cleanly under `AVAudioFile` — verified on disk and by opening them. No row was poisoned. The defect
was one layer up, in the **loaders**: `URL(string:)` is not a path parser, and on current Foundation
it accepts `01 - Those Hills.flac` and returns a *schemeless, non-file* URL. Every loader tested
that initialiser for nil to decide "absolute or relative", so the absolute branch was taken for
every entry and the relative branch was dead code. Those entries reached the engine matching neither
`isFileURL` nor an `http` scheme, failed to open, and L1 then ended the queue in silence. Absolute
entries were broken the same way. `Playlist.resolveEntry` is now the single answer to what an entry
means, shared by the five loaders that each had their own, and both library browsers check the
resolved file exists and report what does not through `AudioFileValidator` — which, as of L1,
reaches the marquee in every skin mode. **Still unmeasured**: how many playlists in the corpus
library use relative entries. The live library holds exactly one playlist row, so this corpus cannot
answer it.
