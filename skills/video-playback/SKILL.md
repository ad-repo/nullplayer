---
name: video-playback
description: The shared video path — how a video track is routed from the playlist to the video player window, the VLCKit-backed `VideoPlayerView`, and how its output is sized. Use when working on or debugging video playback, the video player window, a video drawn at the wrong size or position, or anything that plays a video file or stream outside a skin's own video surface.
---

# Video Playback

Video plays in its own window through VLCKit (libVLC 3.0.12.1, vendored in
`Frameworks/VLCKit.framework`), never through the audio engine's graph. Skin-hosted video surfaces
(`.wal` `<VIDEO>`, `.wmz` video panes) have their own guides: `winamp-modern-skin-guide`
(`reference/components/video.md`) and `wmp-skin-guide` (`reference/rendering/video.md`).

## Key files

| File | Role |
|---|---|
| `Data/Models/Track.swift` | `mediaType` is `.video` when the asset has a video track **or** the extension is a video one (`AudioFileValidator.isVideoFile`); AVFoundation cannot parse `.mkv`/`.avi`/`.webm`, hence the fallback |
| `Audio/AudioEngine.swift` | `loadTrack(at:)` routes a `.video` track to `WindowManager.playVideoTrack` and stops audio; `playTrack(at:)` and the natural end-of-track advance (`advanceToLocalTrackAsync`) take that path |
| `App/WindowManager.swift` | `playVideoTrack(_:)` — video cast routing, then creates `VideoPlayerWindowController` lazily and plays (Plex / Jellyfin / Emby tracks get server-aware playback) |
| `Windows/VideoPlayer/VideoPlayerView.swift` | the VLCKit player, controls, track selection; `play(url:title:)` is the **only** place a `VLCMediaPlayer` is created |
| `Windows/VideoPlayer/VLCVideoHostView.swift` | the player's `drawable`: keeps VLC's view filling it, re-reports the drawing size (below), and the `VIDEO_LAYOUT_TRACE` instrument |

## Routing rules

- **Every way into a video goes through `loadTrack` routing.** A path that opens a playlist item
  with `AVAudioFile` directly plays the video's audio with no window. Sweet Fades does this today:
  `startCrossfade()` never checks `mediaType` (MISC_TASKS M3).
- **The vendored VLCKit reports the end of a film as `.paused`, never `.ended`** — see the
  `mediaPlayerStateChanged` comment; end-of-film handling keys off that pause.
- **Windows → Video Player is inert until a video has been opened** — the controller is created on
  first play (`app-control/reference/launch-recipes.md`).

## Video output sizing (VLC)

`VideoPlayerView` hands VLCKit a `VLCVideoHostView` as the player's `drawable`. VLCKit inserts a
`VLCVideoLayerView` whose layer is a `VLCCAOpenGLLayer`, and the host keeps that view filling its
bounds.

- **Sizing the view is not sizing the video.** `VLCCAOpenGLLayer` tells VLC's video output the
  drawing size only from `layoutSublayers`, as visible size × `contentsScale`, and drops the report
  while the output does not exist yet (VLC `modules/video_output/caopengllayer.m`). The layer is
  attached at scale 1.0 and only later gets the window's Retina 2.0, and nothing lays it out again.
  So a correctly sized view drew the video either at its own pixel size, cropped to the bottom-left
  (a 4K file in an 854×480 pt window showed only a corner), or into the bottom-left quarter.
  `reportSizeToVideoOutput()` lays the layer out again on the first time update with a non-zero
  `videoSize` (the output exists by then) and on `viewDidChangeBackingProperties`. A new way of
  starting playback must still go through `play(url:title:)`, which resets the once-per-media flag.
- Fixed 2026-10-06; measured on 360p–2160p H.264 and VP9 files, in a fresh and a reused window.

## Debugging a live defect

Read **`skills/live-ui-testing`** before diagnosing anything that only reproduces on screen, and
`winamp-modern-skin-guide/reference/harness.md` § *Debugging a live defect*, the reference
implementation of that workflow. Launch with `skills/app-control/scripts/launch.sh <skin>`; a video
reaches the window only from a browser (`app-control/reference/launch-recipes.md` § *Local video*).

- **`VIDEO_LAYOUT_TRACE=1`** (debug builds) logs `VIDEO_LAYOUT` lines with the host's view and layer
  tree (frames, layer bounds, `contentsScale`) on subview insertion, host resize, each size report,
  and 0.3 / 1 / 3 s after every `play`, plus VLC's `videoSize`. Frames that match the window while
  the picture is wrong put the fault in VLC's drawing size, not our layout.
- **Judge the picture against the file, not by eye.** Capture the window
  (`winhelper capture`) and compare it with `ffmpeg -ss <t> -i <file> -frames:v 1` from the same
  file; a talking-head frame shows a crop at a glance, a title card does not.
- **Test fresh and reused windows separately.** A video played into the already-open window and one
  played after closing it go through different first-layout timing.
