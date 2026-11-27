---
name: stream-ripper
description: The Stream Ripper window — rip a media URL with yt-dlp/ffmpeg to audio (Original Opus/AAC, FLAC, MP3) or video (VP9/HEVC/H.264 MP4 at a height cap), several jobs at once, one encode at a time, a persistent history, .cue from chapters, and audio follow-ups (edit tags into the file, add to the library split by its cue). Use when working on the Stream Ripper window, RipJobCenter, yt-dlp/ffmpeg arguments, rip progress, or Libraries → YouTube → Rip URL….
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
| Choices: `Mode`, `RipResolution`, `RipVideoFormat`, `RipAudioFormat`, `VideoProfile` | `StreamRipper/RipRequest.swift` |
| The rip itself (`run` → `performRip`), cue writer, video transcode | `StreamRipper/RipPipeline.swift` |
| The one yt-dlp runner (`runYtDlp`), the YouTube source's downloads, staging, temp reaper, log | `StreamRipper/StreamRipper.swift` |
| One encode at a time, first come first served | `StreamRipper/RipEncodeQueue.swift` |
| Every tool run (`RipProcess.run`, streaming stdout for progress) and the `ps` snapshot (`ProcessTable`) | `StreamRipper/RipProcess.swift` |
| Requests, jobs and their thread-safe handle | `StreamRipper/RipJob.swift` |
| The one job list, failure alert, activity rows, orphan cleanup | `StreamRipper/RipJobCenter.swift` |
| History (`Application Support/NullPlayer/rip_history.json`) | `StreamRipper/RipHistoryStore.swift` |
| yt-dlp / ffmpeg progress parsing | `StreamRipper/RipProgress.swift` |
| Audio follow-ups | `StreamRipper/RipFollowUp.swift` |
| File tag read/write | `StreamRipper/RipFileTags.swift` |
| Window and rows | `Windows/Rip/RipWindowController.swift`, `RipJobRowView.swift` |
| Window base shared with Sonos Rooms (chrome, drag, close, hosted surface); opening/toggling | `Windows/Shared/AuxiliarySurfaceWindow.swift`; `WindowManager.showAuxiliaryWindow` |
| Tag editor panel | `Windows/Rip/RipTagsPanel.swift` |
| Tests | `Tests/NullPlayerAppTests/RipJobTests.swift` |

## Window

A center-stack feature window (`WindowManager.CenterStackFeature.rip`, saved as `isRipVisible` /
`ripWindowFrame`), built on the same base as Sonos Rooms (`AuxiliarySurfaceWindowController` /
`AuxiliarySurfaceView`): `AuxiliaryWindowChrome` in its own window, hosted in a `.wal` skin via
`WinampModernHostedWindows` ("Stream Ripper"). Its height is `CenterStackWindowKind.rip.heightMultiplier`. Opened from **Windows → Stream
Ripper** (shows "Stream Ripper (N running)") or **Libraries → YouTube → Rip URL…**, which focuses the
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

`RipJobCenter.shared` owns `jobs` (running and this session's finished). Each job carries its
`RipRequest`: the URL and a `Kind` — `.rip(Mode, folder:)` from the window, retryable, or
`.youtube(summary:)` for the YouTube source's downloads, listed but never retried. `startRip`
returns the running job for an identical request (URL, choices and folder), else registers a `RipJob` and calls `StreamRipper.run(handle:…)`, which works on a background queue and
reports through `RipJobHandle` (`.phase`, `.progress`, `.title`; the handle's `onUpdate` is fixed
at creation and hops to the main actor by job id). The handle owns the running `Process`;
`cancel()` marks it cancelled and returns at once, terminating the process **and its descendants**
(`ProcessTable.terminateTrees`, one `ps` snapshot) on a background queue — yt-dlp runs ffmpeg as a
child that survives a terminated yt-dlp and keeps writing into the staging the cancel deletes.
A cancel that lands during the copy to the folder removes the copied file (and its `.cue`); past
that last check the rip is done, and `RipJob.finish` keeps a saved file's job **Done** over a later
cancel, so History never lists a cancelled job with a file.
`finish` takes the file size read off the main thread by the caller (the destination can be a NAS),
ends the job (`RipJob.finish`, which returns its `RipHistoryEntry`), records it, then runs the
job's `RipFollowUp` (empty for video and YouTube jobs).

Every `.progress` update posts `.ripJobsDidChange`. The History tab redraws only when
`RipHistoryStore.revision` changed, and job rows show the stored `sizeBytes`, so progress ticks
never touch the disk. History rows' files are checked off the main thread (`checkHistoryFiles`; a
NAS folder can stall): a row shows *file moved or deleted* once the check finds it missing.

- **Encodes run one at a time, in arrival order**: `RipEncodeQueue` keeps the FIFO of waiting job
  ids behind an `NSCondition` (a plain semaphore wakes waiters in any order). It is the only record
  of the line: a waiting row shows *Queued for encode · #N in line* from `position(of:)`. `acquire`
  joins the line before reporting `.queuedForEncode`, so the row never draws without its place; a
  cancel wakes the waiters so a cancelled one leaves.
- **App quit** terminates every job's process tree before returning (`terminateAll` →
  `RipJobHandle.cancelAndWait`). A killed instance's orphans (`ppid` 1, staging path in their
  arguments) are killed at the next launch before the temp reaper.
- `RipRequest` is `Codable` and stored in history for Retry; `Mode.audio` carries a
  `YouTubeAudioFormat`, saved as its `rawValue`. One undecodable entry drops the whole history file.

## yt-dlp invocation

Every yt-dlp run — rips and the YouTube source's downloads — goes through `runYtDlp`, which adds the
progress template and `--print-to-file after_move:filepath`, feeds progress to the job, and returns
`YtDlpRun(status, stderr, outputPath)`. The YouTube audio and video downloads share one body,
`performDownload`, and differ only in their arguments.

Common: `--no-playlist --embed-metadata`, output `"<staging>/%(artist|)s%(artist& - |)s%(title)s.%(ext)s"`,
and `--print-to-file after_move:filepath` so the real final path is read back (the extension
depends on the codec). Files download into a local staging dir (NAS-safe), then copy to a
collision-free name in the destination; on failure the staging contents go to `~/Downloads`.

**Audio** — `Mode.audio(YouTubeAudioFormat)`; `RipAudioFormat` is only the window's picker, naming
the format (`format(kbps:)`, MP3 taking the Bitrate popup):

| Choice | Selector / args | Notes |
|---|---|---|
| Original (Opus) | `bestaudio[acodec=opus]/bestaudio`, `-x --audio-format opus` | no re-encode on YouTube |
| Original (AAC) | `bestaudio[ext=m4a]/bestaudio`, `-x --audio-format m4a` | no re-encode on YouTube |
| FLAC | `bestaudio/best`, `--audio-format flac` | lossless wrap of a lossy source |
| MP3 | `--audio-format mp3 --audio-quality <N>K` | N from the Bitrate popup, capped at the source |

Bitrate cap: before an MP3 encode, `sourceAudioKbps` runs `yt-dlp --print abr` with the same
selector; a source below the request rebuilds `.mp3(kbps:)` at the source's rate, and the log says so. A re-encoded AAC choice was
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

The cue always shares its audio file's base name — `CueSheet.siblingCue` and the tag editor find it
only that way. `commitRip` commits both under one hold of the transfer lock (`withTransferLock`):
it picks a name whose `.cue` is free too, copies the audio, then writes the cue for that final
name. A second rip of the same video in another format becomes `<name> 1.m4a` + `<name> 1.cue`
instead of replacing the first rip's cue (M93). Every destination file is created by
`commitStagedCopy` with `O_EXCL`, so no transfer replaces or removes a file it did not create —
not even one another process put at the name after it was picked.

## Audio follow-ups (`RipFollowUp`)

Chosen per job from the two checkboxes, carried on `RipJob.followUp` (Retry keeps them; history
Retry does not), run by `RipJobCenter.finish` for a `.done` audio rip.

- **Edit tags when done** → `RipTagsPanel` (title, artist, album, album artist, genre, year, track,
  comment) pre-filled by `RipFileTags.read` (ffprobe, stream then format tags). **Save** runs
  `RipFileTags.write`: ffmpeg stream copy into a temp sibling, then `replaceItemAt`. `read` returns
  nil when ffprobe is missing or fails — distinct from a file with no tags — and Save stays off,
  since saving blank fields would clear every tag. While a save runs the panel cannot close.
  - Ogg keeps tags on the stream: `-metadata:s:a:0`.
  - Ogg's cover is read by ffmpeg as a picture stream the Ogg muxer cannot write, so only `0:a` is
    mapped and the cover is re-embedded as a base64 FLAC picture block in `METADATA_BLOCK_PICTURE`.
  - `.m4a` defaults to the ipod muxer, which rejects a cover stream; `-f mp4` writes it.
  - With a sibling `.cue`, its `PERFORMER` lines are rewritten to the new artist, or removed when
    the artist is cleared — the splitter prefers a track's cue performer to the file's artist.
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
