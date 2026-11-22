---
name: stream-ripper
description: The Stream Ripper window — rip a media URL with yt-dlp/ffmpeg to audio (Original Opus/AAC, FLAC, MP3) or video (VP9/HEVC/H.264 MP4 at a height cap), several jobs at once, one encode at a time, a persistent history, .cue from chapters, and audio follow-ups (edit tags into the file, add to the library split by its cue). Use when working on the Stream Ripper window, RipJobCenter, yt-dlp/ffmpeg arguments, rip progress, or Output → Streaming → Rip URL….
---

# Stream Ripper

Paste a URL, pick what to save, press **Rip**. Jobs run in the background; the **Stream Ripper**
window lists them and their history, and closing it never touches a job. Shells out to a
**system-installed** `yt-dlp` + `ffmpeg` (searched in `/opt/homebrew/bin`, `/usr/local/bin`,
`/opt/local/bin`, `/usr/bin`); nothing is bundled. Missing tools → `StreamRipper.missingToolsMessage`
in the form's hint line.

## Key files

| Area | File |
|------|------|
| Choices: `RipResolution`, `RipVideoFormat`, `RipAudioFormat`, `VideoProfile` | `StreamRipper/RipRequest.swift` |
| The rip itself (`run` → `performRip`), the one yt-dlp runner (`runYtDlp`), staging, cue writer, video transcode, log | `StreamRipper/StreamRipper.swift` |
| One encode at a time, first come first served | `StreamRipper/RipEncodeQueue.swift` |
| Short tool runs read whole (ffprobe, yt-dlp query, tag rewrite) | `StreamRipper/RipProcess.swift` |
| Jobs and their thread-safe handle | `StreamRipper/RipJob.swift` |
| The one job list, failure alert, activity rows, orphan cleanup | `StreamRipper/RipJobCenter.swift` |
| History (`Application Support/NullPlayer/rip_history.json`) | `StreamRipper/RipHistoryStore.swift` |
| yt-dlp / ffmpeg progress parsing | `StreamRipper/RipProgress.swift` |
| Audio follow-ups | `StreamRipper/RipFollowUp.swift` |
| File tag read/write | `StreamRipper/RipFileTags.swift` |
| Window (center-stack, Sonos Rooms pattern) and rows | `Windows/Rip/RipWindowController.swift`, `RipJobRowView.swift`; opening/toggling in `App/WindowManager+Rip.swift` |
| Tag editor panel | `Windows/Rip/RipTagsPanel.swift` |
| Tests | `Tests/NullPlayerAppTests/RipJobTests.swift` |

## Window

A center-stack feature window (`WindowManager.CenterStackFeature.rip`, saved as `isRipVisible` /
`ripWindowFrame`), built like Sonos Rooms: `AuxiliaryWindowChrome` for Classic/Original, hosted in
a `.wal` skin via `WinampModernHostedWindows` ("Stream Ripper"). Opened from **Windows → Stream
Ripper** (shows "Stream Ripper (N running)") or **Output → Streaming → Rip URL…**, which focuses the
URL field and pre-fills it from a clipboard `http(s)` URL.

- **Form**, remembered in `UserDefaults` (`rip.*` keys, `RipChoices`):
  - Video: Type + Resolution on one line, Format below.
  - Audio: Type, Format and (MP3 only) Bitrate on one line; below it **Edit tags when done** and
    **Add to Library**.
- **Jobs / History** tabs. The view holds no job state: `resume()` observes `.ripJobsDidChange` and
  redraws every row from `RipJobCenter`; `suspend()` (hidden, occluded, miniaturized) detaches.
  Reopening the window therefore reattaches to running jobs.
- **Show in notification panel** (off by default) mirrors running jobs into `ActivityCenter` rows
  `rip-<id>`. A failure always raises an alert (Retry / Show in Stream Ripper / OK).
- A rip identical to a running one (same URL and `Mode`) is not started twice; its row flashes.

## Jobs

`RipJobCenter.shared` owns `jobs` (running and this session's finished). `startRip` registers a
`RipJob` and calls `StreamRipper.run(handle:…)`, which works on a background queue and reports
through `RipJobHandle` (`.phase`, `.progress`, `.title`). The handle owns the running `Process`;
`cancel()` terminates it **and its descendants** (`RipJobHandle.descendants`) — yt-dlp runs ffmpeg
as a child that survives a terminated yt-dlp and keeps writing into the staging the cancel deletes.
`finish` takes the file size read off the main thread by the caller (the destination can be a NAS),
records a `RipHistoryEntry`, then runs the job's `RipFollowUp` for a successful audio rip.

Every `.progress` update posts `.ripJobsDidChange`. The History tab redraws only when
`RipHistoryStore.revision` changed (its rows check their files on disk), and job rows show the
stored `sizeBytes`, so progress ticks never touch the disk.

- **Encodes run one at a time, in arrival order**: `RipEncodeQueue` keeps a FIFO of waiting job ids
  (a plain semaphore wakes waiters in any order, which made *#N in line* wrong); a job waiting shows
  *Queued for encode · #N in line*.
- **App quit** terminates every job's process (`terminateAll`). A killed instance's orphans
  (`ppid` 1, staging path in their arguments) are killed at the next launch before the temp reaper.
- `Mode` is `Codable` and stored in history for Retry. `RipAudioFormat.originalOpus` keeps raw value
  `"original"`, and its decoder reads the retired re-encoded `"aac"` as `.originalAAC`, so old
  history keeps loading — one undecodable entry would drop the whole file.

## yt-dlp invocation

Every yt-dlp run — rips and the YouTube source's downloads — goes through `runYtDlp`, which adds the
progress template and `--print-to-file after_move:filepath`, feeds progress to the job, and returns
`YtDlpRun(status, stderr, outputPath)`. The YouTube audio and video downloads share one body,
`performDownload`, and differ only in their arguments.

Common: `--no-playlist --embed-metadata`, output `"<staging>/%(artist|)s%(artist& - |)s%(title)s.%(ext)s"`,
and `--print-to-file after_move:filepath` so the real final path is read back (the extension
depends on the codec). Files download into a local staging dir (NAS-safe), then copy to a
collision-free name in the destination; on failure the staging contents go to `~/Downloads`.

**Audio** — `RipAudioFormat` reuses `YouTubeAudioFormat` for its selector and arguments:

| Choice | Selector / args | Notes |
|---|---|---|
| Original (Opus) | `bestaudio[acodec=opus]/bestaudio`, `-x --audio-format opus` | no re-encode on YouTube |
| Original (AAC) | `bestaudio[ext=m4a]/bestaudio`, `-x --audio-format m4a` | no re-encode on YouTube |
| FLAC | `bestaudio/best`, `--audio-format flac` | lossless wrap of a lossy source |
| MP3 | `--audio-format mp3 --audio-quality <N>K` | N from the Bitrate popup, capped at the source |

Bitrate cap: before an MP3 encode, `sourceAudioKbps` runs `yt-dlp --print abr` with the same
selector; a source below the request lowers it, and the log says so. A re-encoded AAC choice was
removed — it was Opus → AAC, a generation loss for no gain over the AAC original. All audio adds
`--embed-thumbnail --convert-thumbnails jpg` and `--print-to-file after_move:%(chapters)j`.

**Video** — `VideoProfile(resolution, format)`; the height cap is a hard filter. `original` asks for
VP9 + AAC first and copies into MP4 when a 4K Chromecast plays the source as is
(`copiesSource`: VP9/HEVC any height, H.264 ≤ 1080p); otherwise it encodes HEVC
(`hevc_videotoolbox`, `hvc1` tag). `hevc` / `h264` always encode. `cappedRates(sourceKbps:)` scales
the profile's rates down so an encode never exceeds the source bitrate.

## Progress

`YtDlpProgressReader` parses the `NPPROG|…` progress template. Each stream starts with a
`[download] Destination:` line; the HLS downloader prints one `100%` before a stream's first
fragment, which is ignored (it made the bar jump to 95 % at start). Video weighs the video stream
95 %, audio 5 % (`ponytail:` note in the file). `FFmpegProgressReader` reads `-progress pipe:1`
during encodes.

## CUE sheets from chapters

With ≥ 2 chapters, `writeCueFile` writes `<name>.cue` beside the audio: top-level `PERFORMER`/`TITLE`
from the `Artist - Title` filename, one `TRACK` per chapter, `INDEX 01 MM:SS:FF` at 75 fps
(`cueTimestamp`, the inverse of `CueSheet.parseCueTimestamp`). See **cue-sheets**.

## Audio follow-ups (`RipFollowUp`)

Chosen per job from the two checkboxes, carried on `RipJob.followUp` (Retry keeps them; history
Retry does not), run by `RipJobCenter.finish` for a `.done` audio rip.

- **Edit tags when done** → `RipTagsPanel` (title, artist, album, album artist, genre, year, track,
  comment) pre-filled by `RipFileTags.read` (ffprobe, stream then format tags). **Save** runs
  `RipFileTags.write`: ffmpeg stream copy into a temp sibling, then `replaceItemAt`.
  - Ogg keeps tags on the stream: `-metadata:s:a:0`.
  - Ogg's cover is read by ffmpeg as a picture stream the Ogg muxer cannot write, so only `0:a` is
    mapped and the cover is re-embedded as a base64 FLAC picture block in `METADATA_BLOCK_PICTURE`.
  - `.m4a` defaults to the ipod muxer, which rejects a cover stream; `-f mp4` writes it.
  - With a sibling `.cue`, its `PERFORMER` lines are rewritten to the new artist — the splitter
    prefers a track's cue performer to the file's artist.
- **Add to Library** → with a sibling `.cue`, `CueAlbumSplitter.splitIfNeeded` (regardless of the
  `cueSplitOnImportEnabled` pref) and the split tracks are added; otherwise the file. Both via
  `MediaLibrary.addTracks`. With both boxes, the add waits for the panel to close (Save or Cancel),
  so the split reads the edited tags.

## Debugging a live defect

Read **live-ui-testing** first, and `winamp-modern-skin-guide/reference/harness.md` § *Debugging a
live defect* for the reference workflow. Launch with `skills/app-control/scripts/launch.sh <skin>`.
Every rip logs `StreamRipper[<id>]` lines (start, phase changes, capping, follow-ups, finish with
elapsed time) — grep the log by the job id before adding instruments. `StreamRipper.log` redacts
URLs to `<url>` and absolute paths to `<path>` (tool errors quote both); the job row's error tooltip
has the full text.
To reproduce a progress defect, run the same `yt-dlp` command with the `NPPROG` template and feed
its stdout to `YtDlpProgressReader` in a test.

## Gotchas

- Always trust `after_move:filepath`, never an assumed extension.
- `--print-to-file after_move:…` writes nothing under `--skip-download`; inspect chapters with
  `--print "%(chapters)j" --skip-download`.
- `-x` with no `--audio-format` keeps whatever codec the site serves; the originals pass one so
  the file always matches its label.
- No Spotify/Apple/Amazon sources (project policy).
