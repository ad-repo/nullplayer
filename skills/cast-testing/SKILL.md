---
name: cast-testing
description: Live CLI casting checks against a real Chromecast, DLNA TV and (opt-in) Sonos on the LAN — device discovery and naming, --cast resolution by name or id, a receiver-rejected video, sidecar subtitles, video routing by extension, DLNA playback, and cast exit codes. Use after changing Chromecast discovery, Cast media-status handling, LocalMediaServer responses, CLI cast resolution or CLI cast exits.
---

# Cast testing

```bash
swift build --build-system native              # the script never builds
skills/cast-testing/scripts/cast-test.sh       # [--chromecast <name>] [--dlna <name>] [--sonos <room>]
```

One `PASS`/`FAIL` line per check, then a summary; exit 0 only if every check passed. Logs (raw
and `\r`→newline `.txt`) land in `tmp/cast-test/`. About 3 minutes. It puts video on both TVs;
`--sonos <room>` adds a 5 s tone in that room and is the only way the Sonos check runs.
How the CLI ends *local* playback (exit codes, skipping bad files, repeat-all) is
`skills/cli/scripts/cli-end-test.sh`, which needs no devices.

**Needs:** the TVs on and discoverable (`--list-devices` sees them), and port 8765 free — the CLI's
`LocalMediaServer` serves the local files there, so a GUI NullPlayer that is casting blocks it
(the preflight says so; it never kills the app). Fixtures come from `scripts/testdata.sh`
(`video-short`, `video-srt`, `video-vtt`, `audio-short`) plus two written into `tmp/cast-test/`.

## What each check proves

| Check | Proves |
|---|---|
| list-devices fields | every row carries `name`, `type`, `id`, `supportsVideo`, `address`, `port` |
| Chromecast by its fn | the name is the TXT `fn`, not the service instance name (`…-<32 hex>`), and the id is `chromecast:<TXT id>` — i.e. discovery browses with TXT records |
| `.mpg` routes to video | `.mpg`/`.mpeg` go through `detectContentType` as video (a text file named `.mpg` is enough: routing is by extension) |
| `--cast` × name / `chromecast:<id>` / bare id | each form resolves, and a video the receiver rejects exits 1 with *the cast device could not play this video* |
| Chromecast plays the clip | a good cast still exits 0 when the video ends |
| no sidecar, no text track | a video with nothing beside it sends a LOAD with no `tracks` |
| sidecar `.srt` / `.vtt` | the sidecar (an `.srt` converted to WebVTT) rides the LOAD as a text track, and the receiver fetches it with `Origin`, which `LocalMediaServer` answers with `Access-Control-Allow-Origin`. Whether the TV draws it is visual: each cue names its format (*NullPlayer SRT cue one*) — confirmed on "Living Room TV 2" 2026-11-03 |
| DLNA runs past 30 s | the 30 s never-started timeout is Chromecast-only; DLNA quits on `q` with 0 |
| DLNA TV range-requests the index | the TV will play the file. DLNA reports no status, so this is read from its requests: `video-short` keeps its `moov` index after `mdat`, and a renderer that plays it range-requests past byte 0. Without the DLNA feature headers (`sonos-casting` § *DLNA feature headers*) the Samsung QN90BA never did, and showed *format not supported* while the check above still passed |
| Sonos plays a local file (`--sonos`) | a local-file audio cast reaches `Sonos poll — state=PLAYING` and quits on `q`. It also prints, as `INFO`, whether Sonos asked for the DLNA feature headers: measured 2026-10-31 on "Dining Room", it does not, so its responses are unchanged |

**Measured receiver behaviour** (Chromecast "Living Room TV 2", 2026-10-31): a LOAD of garbage
bytes served as `.mp4` gets `LOAD_FAILED`, then `MEDIA_STATUS` `IDLE` with `idleReason: ERROR`,
0.4 s after the pre-load `IDLE`. The rejection check depends on that `IDLE`/`ERROR`.

## Not covered

- The Chromecast 30 s *never reached PLAYING/BUFFERING* timeout: no fixture makes a receiver
  hang deterministically.
- Chromecast audio casting (a rejected audio cast is `MISC_TASKS.md` M57), and Sonos grouping.
- The GUI: the Cast menu's friendly names, the *Casting Error* alert on a rejected video, and a
  persisted `preferredVideoCastDeviceID` from before TXT ids (re-picked once).
