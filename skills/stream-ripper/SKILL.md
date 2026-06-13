---
name: stream-ripper
description: Rip a media URL to FLAC/MP3/MP4 via yt-dlp — quality-first format selection, metadata tagging, cover art, metadata-based filenames, .cue from chapters, and the main-window activity band. Use when working on the Stream Ripper, yt-dlp/ffmpeg integration, or the Output → Streaming menu.
---

# Stream Ripper

Paste a URL and download it to a local file: lossless **FLAC**, **MP3**, or a playback-safe **H.264/AAC MP4 video at a chosen resolution/bitrate profile** (720p/2.5 Mbps, 1080p/4 Mbps recommended, 1080p/8 Mbps high quality, 1440p/16 Mbps, 4K/35 Mbps, Full/50 Mbps max). Implemented entirely in `Sources/NullPlayer/StreamRipper/StreamRipper.swift`, wired into the menu via `App/ContextMenuBuilder.swift`, with progress shown via `App/MainWindowProviding.swift`.

## Quick Start (user)

1. **Output → Streaming → Rip URL…** (right-click anywhere, or the menu bar **Output** menu)
2. Paste a URL (the field pre-fills from the clipboard when it holds an `http(s)` link)
3. Pick an output type: **Audio — FLAC (lossless)**, **Audio — MP3**, or video at **1080p / 4 Mbps** / **720p / 2.5 Mbps** / **1080p / 8 Mbps** / **1440p / 16 Mbps** / **4K / 35 Mbps** / **Full / 50 Mbps**
4. Choose a destination folder (defaults to Downloads)
5. A spinner + message appears at the top of the main window during the rip
6. When done: **Play Now**, **Reveal in Finder**, or **Done**

## Requirements

Ripping shells out to a **system-installed** `yt-dlp` (+ `ffmpeg`) — nothing is bundled (deliberately, to avoid the helper-binary machinery). `StreamRipper.resolveYtDlp()` searches `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`, `/usr/bin`. If `yt-dlp` isn't found the dialog short-circuits with an install hint (`brew install yt-dlp ffmpeg`). The child process's `PATH` is set to those dirs so `yt-dlp` can find `ffmpeg` even when launched without a login shell.

## Architecture

- **`StreamRipper`** (`@MainActor final class`, `.shared` singleton) owns the whole flow:
  `promptForInput()` (URL + format popup) → `promptForDestinationFolder()` (NSOpenPanel) → `rip(...)`.
- **Menu**: `ContextMenuBuilder.buildMenuBarStreamingSubmenu` includes **Rip URL…** alongside other streaming actions. Action: `MenuActions.ripURL()` → `MainActor.assumeIsolated { StreamRipper.shared.promptAndRip() }` (menu clicks are already on the main thread).
- **The rip runs off the main thread** (`DispatchQueue.global`); UI (alerts, activity band) is dispatched back to main.

## yt-dlp invocation (quality-first)

Common: `--no-playlist --embed-metadata`, output template `"<folder>/%(artist|)s%(artist& - |)s%(title)s.%(ext)s"` (→ `Artist - Title.ext`, or just `Title.ext` when no artist), and `--print-to-file after_move:filepath <tmp>` so the **actual** final path (extension depends on the native codec) is read back for "Reveal in Finder" / "Play Now".

- **Audio** (`-f bestaudio/best -x --audio-format {flac|mp3} --audio-quality 0 --embed-thumbnail --convert-thumbnails jpg`):
  grabs the best audio-only source, transcodes to the chosen format (FLAC = lossless encode of the decoded source; MP3 = top-VBR). Thumbnail is converted to JPEG before embedding (YouTube serves WebP, which doesn't embed cleanly into FLAC/MP3). Also adds `--print-to-file after_move:%(chapters)j <tmp>` for the cue sheet.
- **Video** — `Mode.video(VideoProfile)` carries the user-chosen resolution/bitrate profile. yt-dlp first downloads the best source video+audio within the selected height cap (`720p`, `1080p`, `1440p`, `2160p`; uncapped for Full) into a temporary `Artist - Title [source].ext` file, using `--merge-output-format mkv` so WebM/MP4 source combinations are accepted. Then ffmpeg creates the final `Artist - Title.mp4` as H.264/AAC with `yuv420p`, `+faststart`, and profile bitrates:
  - 720p: 2.5 Mbps video / 128 kbps audio
  - 1080p recommended: 4 Mbps video / 160 kbps audio
  - 1080p high quality: 8 Mbps video / 192 kbps audio
  - 1440p: 16 Mbps video / 192 kbps audio
  - 4K: 35 Mbps video / 192 kbps audio
  - Full/max: 50 Mbps video / 256 kbps audio, with no height cap
  - **Why this transcode exists:** YouTube can serve MP4 files using codec/pixel-format combinations VLC accepts but NullPlayer's video/cast paths may not. The compatibility pass trades extra encode time for predictable playback.
  - **Why 1080p/4 Mbps is recommended:** 1080p/8 Mbps produced a ~671 MB file for a 10-minute source, which is expected at that bitrate but too large for a default. The 4 Mbps profile is roughly half that size while keeping a playback-safe MP4.
  - **Why the cap matters:** unconstrained "best" can pull oversized 4K+/high-bitrate streams — a 2.5h video ballooned to ~28GB. The user picks 720p / 1080p (default-recommended) / 1440p / 4K per rip; the height filter is a hard cap, not just a sort preference. Pick **Full / 50 Mbps** only when you explicitly want the maximum source resolution.

### Quality caveat

Web sources (YouTube etc.) only serve **lossy** audio. **FLAC** losslessly wraps the decoded lossy audio — no quality is *recovered* (large files), but no further generational loss either. **MP3** adds a *second* lossy pass (tandem coding) so it degrades further. FLAC is the no-further-degradation option of the two; the only truly zero-loss + small choice would be keeping native Opus (not currently offered).

## CUE sheets from chapters

Audio rips capture the source chapter list via `%(chapters)j` (JSON array of `{start_time, end_time, title}`). When there are **≥ 2** chapters, `writeCueFile` emits a `.cue` next to the audio:

- `FILE "<name>" WAVE` (or `MP3` for mp3)
- one `TRACK NN AUDIO` per chapter, each with `TITLE` and `INDEX 01 MM:SS:FF`
- `cueTimestamp` converts seconds → `MM:SS:FF` at **75 frames/second** (CUE standard)
- album/performer derived from the `Artist - Title` filename; quotes in titles are sanitized to `'`

`readChapters` / `writeCueFile` / `cueTimestamp` are `nonisolated static` (pure, no UI) so they run safely in the background completion block.

## Progress band (main window)

`MainWindowProviding` gained `showActivity(_:)` / `hideActivity()` with **default implementations** (so both classic and modern UIs get it free, without either window referencing the other). It overlays a 22px bar at the **top** of `window.contentView` (`y = height - barHeight`, autoresizing `[.width, .minYMargin]`) with a spinning `NSProgressIndicator` + white label on translucent black, found/removed by `NSUserInterfaceItemIdentifier`. `StreamRipper` calls `showActivity` before launching and `hideActivity` on every completion path.

## Play Now

`presentSuccess(outputPath:mode:cueTrackCount:)` branches by `mode`:
- **audio** → `audioEngine.loadFiles([url]); audioEngine.play()` (same path as opening a file from Finder)
- **video** → `WindowManager.shared.showVideoPlayer(url:title:allowCasting: false)` using the final compatibility-transcoded `.mp4` (opens the local video player window; it deliberately bypasses active/preferred cast routing because the user just clicked **Play Now** for a local rip)

## Gotchas

- `--print-to-file after_move:…` only fires after a real download/move — it won't write in `--skip-download` test runs. Use plain `--print "%(chapters)j" --skip-download` to inspect chapter output manually.
- `start_time` in the chapter JSON can be an integer (`0`); `JSONSerialization` → `NSNumber` bridges to `Double` regardless, so `entry["start_time"] as? Double` is fine.
- The output extension is **not** fixed for audio when keeping native containers would apply — always trust the `after_move:filepath` value, not an assumed `.flac`/`.mp3`/`.mp4`.
- During video compatibility encoding, ffmpeg may leave a hidden dot temp file/folder visible near the destination while it finalizes the MP4, especially during the `+faststart` metadata rewrite. This can last minutes even for a ~10-minute source, then clean itself up after ffmpeg exits. Treat it as in-progress scratch unless it remains after the rip has completed or failed.
- Do not call `WindowManager.playVideoTrack` from Stream Ripper's **Play Now** path unless you intend to cast. `playVideoTrack` is playlist-oriented and routes to `targetVideoCastDevice` when a video-capable cast session or preferred video cast device exists. Use `showVideoPlayer(..., allowCasting: false)` for local Play Now.
- No Spotify/Apple/Amazon sources (project policy) — this is a generic URL ripper backed by yt-dlp.
