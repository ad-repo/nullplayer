# Launch recipes

Commands that open the player straight to a given **skin family** and a given
**media type**, with no menu clicking.

**Rule zero applies**: these build and run the local debug build. `BIN` is never the `nullplayer`
shim. See `SKILL.md`.

```bash
BIN=.build/arm64-apple-macosx/debug/NullPlayer     # Intel: .build/x86_64-apple-macosx/…
```

---

## Part 1 — skin family

One line, any family. It builds, launches, plays `audio-long`, and prints a verified
`LAUNCH PASS`/`LAUNCH FAIL` — see `SKILL.md` Route B for the options.

```bash
skills/app-control/scripts/launch.sh aquamp                 # Classic — a .wsz
skills/app-control/scripts/launch.sh modern:NeonWave        # Original (menu name "Original")
skills/app-control/scripts/launch.sh "metal:Brushed Steel"  # Original-Metal
skills/app-control/scripts/launch.sh 2222-cPro__Bento       # Winamp Modern .wal (menu name "Modern")
skills/app-control/scripts/launch.sh corona                 # Windows Media Player .wmz
```

---

## Part 2 — media: audio / video × local / streaming

|  | **Local** | **Streaming** |
|---|---|---|
| **Audio** | `NULLPLAYER_PLAY` (GUI) or `"$BIN" --cli --file` | `"$BIN" --cli --source plex\|subsonic\|jellyfin\|emby …`, or `--source radio --station` |
| **Video** | library scan → browser **MOVIES** tab → double-click | Plex browser **MOVIES** tab → double-click (GUI); `--movie … --cast` (CLI only) |

**Video never goes through `NULLPLAYER_PLAY`** — `application(_:openFiles:)` takes audio and
`.cue` only. And **the Windows → Video Player menu item is inert** until a video has been opened
from a browser: `WindowManager.toggleVideoPlayer` returns early while the controller is nil
(`App/WindowManager.swift:3205`). A browser is the only way into the video window.

### Local audio

```bash
scripts/testdata.sh ensure
skills/app-control/scripts/launch.sh aquamp                                   # GUI
"$BIN" --cli --file "$(scripts/testdata.sh path audio-long)"                 # headless
```

Confirm: `loadLocalTrack: audio-long.mp3` in the log; the CLI's own progress bar.

### Local video

```bash
scripts/testdata.sh ensure    # generates tmp/testdata/video-short.mp4
```

1. **Libraries → Local Library → Manage Folders… → Add Folder…**, pick `tmp/testdata`, let the
   scan finish.
2. Library Browser → **MOVIES** → double-click `video-short` (listed at `0:10`).

Confirm: a `video-short` window, and `VideoPlayerView: Playing` in the log. Remove the watch
folder afterwards — and note it orphans the playlist row (issue #437).

### Streaming audio — a media server

```bash
"$BIN" --cli --source plex --library AD-FLAC --artist "Dead Meadow" --album "Dead Meadow"
"$BIN" --cli --source plex --library AD-FLAC --artist "Meshuggah"
```

No cast device needed: server audio streams to the local output. Confirm: the progress bar shows
a real duration (`0:38 / 7:32`), not `0:00`.

Discover what is actually installed with `scripts/testdata.sh servers`, or
`"$BIN" --cli --list-libraries --source <name> --json` then `--list-albums --artist …`.

### Streaming audio — internet radio

```bash
"$BIN" --cli --list-stations --json
"$BIN" --cli --source radio --station "Magic Radio"
```

Confirm: elapsed climbs against a `0:00` total — a stream has no duration, and that is the tell
that it is a stream rather than a stalled file.

### Streaming video — a media server

**GUI (no cast device required):** Library Browser on a Plex source → **MOVIES** → double-click
`Airplane!`. Confirm: an `Airplane!` window, and in the log
`VideoPlayerView: Playing Airplane! from http://…/file.mkv?X-Plex-Token=<redacted>`.

**CLI: casting only.** There is no headless local-playback path for video —

```bash
"$BIN" --cli --source plex --library Movies --movie "Airplane!" --cast "<device>" --cast-type chromecast
"$BIN" --cli --list-devices --json          # what is on the LAN
```

Without `--cast` it refuses: *"Video casting in CLI mode requires --cast <Chromecast or DLNA TV>."*

TV follows the same shape and needs `--show`:

```bash
"$BIN" --cli --source plex --show "30 Rock" --episode "Pilot" --cast "<device>" --cast-type chromecast
```

### Content used above

Frozen from this machine's library so the blocks run as written. Re-resolve with
`scripts/testdata.sh servers` if a title moves.

| Slot | Value | Source |
|---|---|---|
| Local audio | `audio-long` (20 min) | `scripts/testdata.sh` |
| Local video | `video-short` (10 s) | `scripts/testdata.sh` |
| Server audio | `Dead Meadow` / `Dead Meadow`, `Meshuggah` | Plex, library `AD-FLAC` |
| Server video | `Airplane!` (1980, 1:27:42) | Plex, library `Movies` |
| Server TV | `30 Rock` → `Pilot` (S01E01) | Plex, library `TV Shows` |
| Radio | `Magic Radio` | saved stations |

**The CLI's music queries return `[]` against a video library** (`cli/SKILL.md:254`), so movie and
episode titles cannot be listed that way. They come from the browser's MOVIES/TV tabs, or from
play history:

```sql
select event_title, count(*) from play_events
where source='plex' and content_type='movie' group by 1 order by 2 desc;
```
