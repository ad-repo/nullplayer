# Test-data targets

Canonical inputs for driving and measuring the running app. `scripts/testdata.sh` synthesizes
the local rows into `tmp/testdata/` (gitignored), so nothing large is committed and every agent
gets byte-identical media.

```bash
scripts/testdata.sh ensure            # generate anything missing (idempotent)
scripts/testdata.sh path audio-long   # absolute path, or exit 1
scripts/testdata.sh list              # the manifest with present/missing state
scripts/testdata.sh servers           # what the configured media servers hold
```

**Rule zero applies here too.** `testdata.sh servers` shells out to
`.build/<arch>-apple-macosx/debug/NullPlayer` by path. It never calls the `nullplayer` shim,
which `exec`s the installed `/Applications` build. With no debug binary it exits non-zero and
tells you to run `./scripts/kill_build_run.sh --debug`; there is no fallback.

Generation needs `ffmpeg` (`brew install ffmpeg`). The plain audio rows fall back to
`afconvert` over a python-generated waveform; MP3, tags, cover art and video need ffmpeg and
say so.

## Local rows

| Name | What | Routes it is valid for | Not valid for |
|---|---|---|---|
| `audio-short` | 5 s 440 Hz tone, AAC | B, C — start/stop, end-of-track, next-track | **Any seek, drag or timed capture.** It ends mid-diagnosis and the `stop()` reads as the bug |
| `audio-long` | 20 min 100→4000 Hz sweep, MP3 | B, C, D, E — **the default for anything timed**: seek, slider drag, elapsed readout, animation cadence, a QA session | — |
| `audio-lossless` | 30 s sweep, FLAC | B, E — lossless decode path, bit-depth readouts | Seek (too short) |
| `audio-gapless` / `-2` | two 10 s FLACs meeting at a phase boundary | B, E — gapless transition; a gap is an audible click | Anything needing tags |
| `audio-tagged` | 60 s tone, title/artist/album/track/year + embedded cover | B, C, D, E — every skin readout, album-art visualizer, browser columns | Seek (too short) |
| `audio-untagged` | the same audio, no tags, no art | B, E — fallback title rendering, missing-art placeholder | Anything asserting metadata |
| `video-short` | 10 s H.264 + AAC, 640x360 | C, E — video window; `"$BIN" --cli --file <path> --cast <device>` | **`NULLPLAYER_PLAY`** — see below. Seek; audio-only paths |
| `playlist-m3u` | extended M3U over the audio rows, absolute paths | C, D — the Playlist window's Load, drag-drop, a library browser | **`NULLPLAYER_PLAY`** — see below |
| `cue-flac` + `cue-sheet` | 7 min FLAC with a 3-index `album.cue` | B, C, E — `cue-sheets` playback and splitting | — |
| `library-dir` | 3 tagged tracks, 2 artists, 2 albums | B, E — `local-library` scan, browser grouping and sort | A scale test; it is three files |

Route letters are the ones in `SKILL.md`: **A** headless, **B** launch preconfigured, **C** drive
it yourself, **D** hand the user a loaded session, **E** measure.

## `NULLPLAYER_PLAY` does not take every row

It goes through `application(_:openFiles:)`, which accepts exactly
`mp3 m4a aac wav aiff aif flac ogg alac` and `.cue` (`App/AppDelegate.swift:340,357`).
**Anything else is dropped with no log line and no error** — the app comes up idle and reads
exactly like a playback bug. `playlist-m3u` and `video-short` are both in that set.

| Row | Reaches the app by |
|---|---|
| every audio row, and `cue-sheet` | `NULLPLAYER_PLAY="$(scripts/testdata.sh path audio-long)"` |
| `playlist-m3u` | the Playlist window's Load panel (`Windows/Playlist/PlaylistView.swift:1829`), drag-drop, or a library browser |
| `video-short` | the video window, or `"$BIN" --cli --file <path> --cast <device>`. Without `--cast` the CLI refuses: *"Video casting in CLI mode requires --cast <Chromecast or DLNA TV>."* |
| `library-dir` | a local-library scan of the folder; see `local-library` |

**The row an agent gets wrong is `audio-short`.** A seek, a drag, a two-capture comparison or any
session long enough to read a log needs `audio-long`. Five seconds is not a test; it is a race
against the track ending.

## Network rows

These cannot be synthesized. The shape is documented here; the CLI answers what is actually
installed on this machine.

| Target | Shape | How to resolve it |
|---|---|---|
| Radio stream | A stable public HTTP/Icecast MP3 stream, e.g. `https://stream.srg-ssr.ch/m/couleur3/mp3_128` | `"$BIN" --cli --play <url>`; see `radio-streaming` |
| YouTube audio | A stable, long, non-age-gated video URL | see `youtube-source` |
| Plex / Jellyfin / Emby / Subsonic | A library id and an album with several tracks | `scripts/testdata.sh servers`, or `"$BIN" --cli --list-libraries --source <name> --json` then `--list-albums` |
| Cast device | A Chromecast or Sonos on the LAN | `"$BIN" --cli --list-devices --json` (5 s discovery wait) |

where

```bash
BIN=.build/arm64-apple-macosx/debug/NullPlayer     # never `nullplayer`
```

A network row is never a regression guard: the stream can go off air and the server's contents
change. Use it to exercise a path, and assert on the local rows.
