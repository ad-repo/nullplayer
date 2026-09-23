# Local library and playlist playback — open backlog

The two skin backlogs in this repo — [`WMP_TASKS.md`](../../WMP_TASKS.md) for `.wmz` and
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
| L1 | A track that fails to load halts the playlist, and says nothing outside the Classic skin | **Measured 2026-09-23**: `AudioEngine.handleLocalTrackLoadFailure` (`Sources/NullPlayer/Audio/AudioEngine.swift:4658`) calls `stopPlaybackOnError()`, which clears `currentTrack`, sets `state = .stopped` and stops the time updates. A tree-wide grep for a skip-on-failure path returns **nothing** | **This is the row that turned two bad rows into "playlist playback is broken".** The failure is announced once, as `.audioTrackDidFailToLoad`, and has exactly one user-visible consumer: `Windows/MainWindow/MainWindowView.swift:245`, the **Classic** skin's marquee. `App/AppDelegate.swift:689` logs it and explicitly defers the UI to that notification. `Windows/WMPSkin/`, `Windows/ModernMainWindow/` and `Windows/WinampModern/` register **no observer at all**, so in three of the four skin modes the player stops dead and reports nothing. **Two separable halves — do not fold them**: whether an unreadable track should advance rather than end the queue (shared `AudioEngine`, blast radius across all four skin modes and casting), and whether the other three engines should surface the message Classic already has. The second is the smaller and safer one. |
| L2 | Nothing ever re-resolves a track that is not at its recorded path | **Measured 2026-09-23**: no bookmark, no relocation pass, no path re-resolution anywhere. `grep` over `Sources/` for `UPDATE library_tracks`, `SET url` and `relocat` returns **nothing** | A moved, renamed or re-rooted folder orphans its rows permanently, and the only signal the user gets is L1's silent stop. **The reach is not "iCloud"** — it is any watch folder on a detached drive, an unmounted NAS, or a directory the user reorganised. **Measure the class before designing the fix**: count rows in the live library whose file is absent, grouped by watch root, before deciding between re-resolution, security-scoped bookmarks, or a user-facing "locate" affordance. |
| L3 | A relative-path playlist resolves its entries against the playlist's own recorded directory, and nothing validates the result | **Reproduced 2026-09-23** on the report's own data: `Those Hills - Anika Nilles.m3u` lists `01 - … .flac` and `02 - … .flac` with **no directory**, and both library rows carry the playlist row's root. `file_size`, `duration` (298.21 s) and `bitrate` (1019 kbps) were all written | **One wrong root on the playlist file silently poisons every track it lists**, and the rows look fully populated afterwards — real sizes, real durations, real bitrates — so nothing downstream can tell them from good ones. **The rows are written without ever checking that the resolved file exists.** That check is the cheap half of this row and is worth taking on its own. **Unmeasured and the number to take next**: how many playlists in the corpus library use relative entries, and whether any other rows were written the same way. |
| L4 | `removeMissingItemsInWatchedFolders` has no callers | **Measured 2026-09-23**: `Sources/NullPlayer/Data/Models/MediaLibrary.swift:2602`, declared `private`, and the only occurrence of the name in `Sources/` and `Tests/` is its own declaration. It has never run | **Do not simply call it — that is the trap this row exists to record.** It deletes a track, movie or episode whose file is absent from a watched folder, and the report that opened this backlog is precisely the case where that would have been wrong: two rows whose files are fine would have been permanently deleted along with their play counts and ratings. **An unmounted NAS and a deleted folder are indistinguishable to `fileExists`**, and there is already volume-mount awareness beside it (`MediaLibrary.swift:2287`) that any live version has to be gated on. **Rank it behind L2**: deletion is the wrong response to "not at the recorded path" until re-resolution exists to rule out relocation first. |

## Closed

Nothing yet. A closed row moves here with the change that closes it, verbatim and with its evidence.
