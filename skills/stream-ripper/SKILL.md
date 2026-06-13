---
name: stream-ripper
description: Rip a media URL to FLAC/MP3/MP4 via yt-dlp — quality-first format selection, metadata tagging, cover art, metadata-based filenames, .cue from chapters, and the main-window activity band. Use when working on the Stream Ripper, yt-dlp/ffmpeg integration, or the Output → Streaming menu.
---

# Stream Ripper

Paste a URL and download it to a local file: lossless **FLAC**, **MP3**, or an **MP4 video at a chosen resolution** (720p/1080p/1440p/4K-best). Implemented entirely in `Sources/NullPlayer/StreamRipper/StreamRipper.swift`, wired into the menu via `App/ContextMenuBuilder.swift`, with progress shown via `App/MainWindowProviding.swift`.

## Quick Start (user)

1. **Output → Streaming → Rip URL…** (right-click anywhere, or the menu bar **Output** menu)
2. Paste a URL (the field pre-fills from the clipboard when it holds an `http(s)` link)
3. Pick an output type: **Audio — FLAC (lossless)**, **Audio — MP3**, or video at **1080p** / **720p** / **1440p** / **4K-best**
4. Choose a destination folder (defaults to Downloads)
5. A spinner + message appears at the top of the main window during the rip
6. When done: **Play Now**, **Reveal in Finder**, or **Done**

## Requirements

Ripping shells out to a **system-installed** `yt-dlp` (+ `ffmpeg`) — nothing is bundled (deliberately, to avoid the helper-binary machinery). `StreamRipper.resolveYtDlp()` searches `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`, `/usr/bin`. If `yt-dlp` isn't found the dialog short-circuits with an install hint (`brew install yt-dlp ffmpeg`). The child process's `PATH` is set to those dirs so `yt-dlp` can find `ffmpeg` even when launched without a login shell.

## Architecture

- **`StreamRipper`** (`@MainActor final class`, `.shared` singleton) owns the whole flow:
  `promptForInput()` (URL + format popup) → `promptForDestinationFolder()` (NSOpenPanel) → `rip(...)`.
- **Menu**: `ContextMenuBuilder.buildMenuBarStreamingSubmenu` adds the single **Rip URL…** item (sibling to the **Sonos** streaming submenu). Action: `MenuActions.ripURL()` → `MainActor.assumeIsolated { StreamRipper.shared.promptAndRip() }` (menu clicks are already on the main thread).
- **The rip runs off the main thread** (`DispatchQueue.global`); UI (alerts, activity band) is dispatched back to main.

## yt-dlp invocation (quality-first)

Common: `--no-playlist --embed-metadata`, output template `"<folder>/%(artist|)s%(artist& - |)s%(title)s.%(ext)s"` (→ `Artist - Title.ext`, or just `Title.ext` when no artist), and `--print-to-file after_move:filepath <tmp>` so the **actual** final path (extension depends on the native codec) is read back for "Reveal in Finder" / "Play Now".

- **Audio** (`-f bestaudio/best -x --audio-format {flac|mp3} --audio-quality 0 --embed-thumbnail --convert-thumbnails jpg`):
  grabs the best audio-only source, transcodes to the chosen format (FLAC = lossless encode of the decoded source; MP3 = top-VBR). Thumbnail is converted to JPEG before embedding (YouTube serves WebP, which doesn't embed cleanly into FLAC/MP3). Also adds `--print-to-file after_move:%(chapters)j <tmp>` for the cue sheet.
- **Video** — `Mode.video(maxHeight: Int?)` carries the user-chosen resolution cap. With a cap: `-f "bv*[height<=N]+ba/b[height<=N]/bv*+ba"`; uncapped (4K-best): `-f "bv*+ba/b"`. Sort is `-S res,fps,vcodec,br,acodec` and `--remux-video mp4` (only swaps the container, **no quality-losing re-encode**). `vcodec` is ranked **before** `br`, and yt-dlp's default vcodec order prefers **av1 > vp9 > h264**, so at a given resolution it picks the more efficient (smaller) stream rather than the fattest h264 one.
  - **Why the cap matters:** uncapped "best" pulls 4K/high-bitrate streams — a 2.5h video ballooned to ~28GB. The user picks 720p / 1080p (default-recommended) / 1440p / 4K-best per rip; the height filter is a hard cap, not just a sort preference.

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
- **video** → `WindowManager.shared.playVideoTrack(Track(url:))` (opens the video player window; routes to an active video-cast device if set)

## Gotchas

- `--print-to-file after_move:…` only fires after a real download/move — it won't write in `--skip-download` test runs. Use plain `--print "%(chapters)j" --skip-download` to inspect chapter output manually.
- `start_time` in the chapter JSON can be an integer (`0`); `JSONSerialization` → `NSNumber` bridges to `Double` regardless, so `entry["start_time"] as? Double` is fine.
- The output extension is **not** fixed for audio when keeping native containers would apply — always trust the `after_move:filepath` value, not an assumed `.flac`/`.mp3`/`.mp4`.
- No Spotify/Apple/Amazon sources (project policy) — this is a generic URL ripper backed by yt-dlp.
