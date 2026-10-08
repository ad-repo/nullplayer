---
name: video-playback
description: The shared video path — how a video reaches the video player window (playlist routing, browser rows, drops), the VLCKit-backed `VideoPlayerView` and its output sizing, the window's cast routing and lifetime, and Plex / Jellyfin / Emby progress reporting. Use when working on or debugging video playback, the video player window, a video drawn at the wrong size or position, or anything that plays a video file or stream outside a skin's own video surface.
---

# Video Playback

Video plays in its own window through VLCKit (libVLC 3.0.12.1, vendored in
`Frameworks/VLCKit.framework`), never through the audio engine's graph. Skin-hosted video surfaces
(`.wal` `<VIDEO>`, `.wmz` video panes) have their own guides: `winamp-modern-skin-guide`
(`reference/components/video.md`) and `wmp-skin-guide` (`reference/rendering/video.md`). Headless
video casting (`--movie`, `--episode`, `--file` with a video) is in `cli`.

## Key files

| File | Role |
|---|---|
| `Data/Models/Track.swift` | `mediaType` is `.video` when the asset has a video track **or** the extension is a video one (`AudioFileValidator.isVideoFile`). AVFoundation cannot parse `.mkv`/`.avi`/`.webm`/`.flv`/`.ts` (the reason playback uses VLCKit), so the probe comes back empty for them and the extension keeps them off the audio engine. Audio extensions are never in the video set |
| `Audio/AudioEngine.swift` | `loadTrack(at:)` routes a `.video` track to `WindowManager.playVideoTrack` and stops audio; `playTrack(at:)` and the natural end-of-track advance (`advanceToLocalTrackAsync`) take that path |
| `App/WindowManager.swift` | the entry points (below); each creates `VideoPlayerWindowController` lazily |
| `Windows/VideoPlayer/VideoPlayerWindowController.swift` | the window: what is loaded (Plex / Jellyfin / Emby movie or episode, local URL), cast state, server progress reporting, end-of-media |
| `Windows/VideoPlayer/VideoPlayerView.swift` | the VLCKit player, controls, track selection; `play(url:title:)` is the **only** place a `VLCMediaPlayer` is created |
| `Windows/VideoPlayer/VLCVideoHostView.swift` | the player's `drawable`: keeps VLC's view filling it, re-reports the drawing size (below), and the `VIDEO_LAYOUT_TRACE` instrument |

## Routing rules

- **Every playlist path into a video goes through `loadTrack` routing.** A path that opens a playlist item
  with `AVAudioFile` directly plays the video's audio with no window. Sweet Fades and gapless are
  the two that pre-load the next track; both ask `AudioEngine.canHandOff(to:fromStreaming:)` first,
  which refuses a video, so a new pre-load path must too. It reads `Track.playbackRoute`, the same
  classification `loadTrack` routes on, so a new route is added in one place.
- **Routing a video halts the audio through `haltAudioOutput()`**, which invalidates
  `playbackGeneration` before stopping. Stopping a node fires its track's completion, and a live
  one ran as a natural end: double-clicking a video over playing audio loaded the next row behind
  the window. It also stops the crossfade node, which holds the audio after a completed fade.
- **A playlist film's end advances by natural-end rules, in every family.**
  `onVideoFinishedForPlaylist` calls `AudioEngine.videoTrackDidFinish` → `advanceAfterNaturalTrackEnd`,
  never `next()`. By then `videoPlaybackDidReachEndOfMedia` has stopped the engine (paused when the
  film started), and `next()` resumes only a `.playing` engine, so it loaded the next row and never
  played it (M13). `next()` also wraps at the end of the playlist where a natural end stops.
  Measured 2026-10-07 on Classic: `1-audio.m4a`, `2-video.mp4`, `3-audio.m4a` play through and stop.
- **An audio load closes the film before it takes its token and generation.**
  `stopVideoBeforeLoadingAudio` runs first in `loadTrack` and `loadLocalTrackForImmediatePlayback`:
  closing the film stops the engine it paused (`videoPlaybackDidStop` → `AudioEngine.stop()`), which
  bumps `deferredLocalTrackLoadToken` and `playbackGeneration`. Captured before it, the async open
  was dropped and the audio never started (M14). Measured 2026-10-07 on Classic: double-clicking
  `audio-long` mid-film closes the window and plays it.
- **`play()` never runs the audio pipeline for a `.video` track; it routes it once.** `loadTrack`
  hands a video to the window on the next main-queue turn, so a `play()` straight behind it
  (`loadTracks`, the playlist's double-click) saw no active video, found no audio pipeline for the
  URL, reloaded and routed the film a second time, with a Plex stop at 0:00 in between (M22).
  `pendingVideoHandOffTrackID` marks the video on its way, and `play()` leaves it alone; with
  nothing pending (the film was closed or ran out) it calls `loadTrack` once. Falling through also
  restarted the previous song: `haltAudioOutput` leaves `audioFile` set, so the local branch found
  a file to play. Measured 2026-10-08 on Classic: Replace Queue with a Plex, Emby and local film,
  a playlist double-click, and Play after closing the film each log one `Routing video track`.
- **The vendored VLCKit reports the end of a film as `.paused`, never `.ended`** — see the
  `mediaPlayerStateChanged` comment; end-of-film handling keys off that pause.
- **Windows → Video Player is inert until a video has been opened** — the controller is created on
  first play, and `WindowManager.toggleVideoPlayer` returns early while it is nil.
- **A play call moves key focus to the picture** (`revealVideoOutput`): the free window is meant
  to take it itself (in Classic it does not, M28), a `.wal` skin's video window takes it in `setAuxiliaryWindow`, and a `.wmz` skin window
  takes it through `revealSkinSurface(_:switchingViews:activate:)`. Both skin paths go through
  `WindowManager.hostVideoOutputInSkin`. A `.wmz` video view that is not open yet is built in a
  `Task`, so `loadView` makes it key once it exists; focusing right after the reveal call would find
  no window. Without that,
  focus stayed on the Library Browser that started the film, where Return replays the selected row:
  a keystroke meant for the film restarted it from 0 and discarded the position (M5, measured
  2026-10-07). It goes to the skin window, never the parked video window: under `.wmz`, Esc there
  falls through to `close()` and stops the film. Hence the video keys do not reach a parked film
  (M18).

## Entry points

Every `WindowManager` entry point first offers the video to `routeToVideoCastIfNeeded` (see
*Casting* below), then creates the controller if needed and plays. The direct ones (every row
below except `playVideoTrack`) go through `playDirectVideo`, which first calls
`TrackVerb.supersedePendingPlays()`: a library **Play** still fetching (a show resolves season by
season) would otherwise replace the film double-clicked after it when its fetch lands.
`playVideoTrack` must not, since the verbs themselves reach it.

| Entry point | Called by | Notes |
|---|---|---|
| `playVideoTrack(_:)` | `AudioEngine.loadTrack` (any playlist video) | the **only** one that sets `onVideoFinishedForPlaylist`, so the only one whose end advances the playlist. Picks `play(plexTrack:)` / `play(jellyfinTrack:)` / `play(embyTrack:)` from `plexRatingKey` / `jellyfinId` / `embyId`, else `play(url:title:)` |
| `showVideoPlayer(url:title:allowCasting:)` | double-click / Return on a local movie or episode row in both browsers, Stream Ripper **Play Now** | `allowCasting: false` skips cast routing: Play Now opens the file just ripped in the local window even while a video cast runs |
| `playMovie` / `playEpisode`, `playJellyfinMovie` / `playJellyfinEpisode`, `playEmbyMovie` / `playEmbyEpisode` | double-click / Return on a server movie or episode row | load the server item into `play(movie:)`, `play(jellyfinMovie:)`, `play(embyEpisode:)` … so its reporter runs |

**Library menu verbs.** A video row's **Play** · **Play and Replace Queue** · **Play Next** · **Add to
Queue** (and Shift+Enter / Option+Enter) queue it through `TrackVerb` like a music row:
`LibraryPlayable` turns a movie, episode, season or show of any source into `.video` tracks, which
reach the window through `loadTrack` → `playVideoTrack`. That track path still differs from the
row path above: it passes no Plex external subtitle streams, and while a video cast runs it casts
the track's URL (`castVideoURL`) where a row casts the server item (`castPlexMovie` …), so
double-click cannot simply become `TrackVerb.play` (M23).

**Drag and drop.** The main window and the playlist each have their own drop handler, in Classic
(`MainWindowView`, `PlaylistView`) and Modern (`ModernMainWindowView`, `ModernPlaylistView`). Each
must pass `includeVideo: true` to `hasSupportedDropContent` and `discoverMediaURLsAsync`, or
dragging a video does nothing. The `.wal` playlist's **Add Directory** does the same
(`WinampModernHostActionMenus`). Discovered videos join the playlist and play through `loadTrack`.
A drop on a Library Browser imports instead (`local-library` § *Video import*).

## Window lifetime

- **The controller is mode-independent.** `reloadUI(to:)`'s teardown keeps
  `videoPlayerWindowController`, since closing it stops playback and casts, so a film keeps playing
  across a skin-family switch.
- **The video player is exempt from Compact Mode hiding** and stays visible throughout. The compact
  mini-player floats at `.statusBar`, so a video that starts while compact calls
  `yieldFrontForVideoPlayer()` and brings the player to the front instead of opening behind it.

## Server progress reporting

What the window has loaded is one value, `loadedVideo: LoadedVideo` (`Windows/VideoPlayer/LoadedVideo.swift`):
a local file, a server movie or episode, or a queued server item by id. Its `reporter` is the
server that hears pause, resume, position and stop (`VideoPlaybackReporting`, which
`PlexVideoPlaybackReporter`, `JellyfinVideoPlaybackReporter` and `EmbyVideoPlaybackReporter`
conform to); a local file has none and reports nothing. Its `playHistorySource` is the play
event's source, and `performCast` switches on it to cast a server movie or episode as itself.
Every `play(…)` starts with `endPreviousVideo()` (drop a stale cast, report the previous item
stopped with `finished: false`, record its play) and loads through `startVideo(…)`, which sets
`loadedVideo` in one assignment, so a new item cannot inherit the previous one's server. A new
source is a new `LoadedVideo` case; the compiler then names every switch it must join. A queued
video carries only its id on the `Track`, so `play(plexTrack:)` / `play(jellyfinTrack:)` /
`play(embyTrack:)` load `.plexItem` / `.jellyfinItem` / `.embyItem` and start the reporter with
`videoTrackDidStart`, taking episode-or-movie from `playHistoryContentType`. The three
reporters share their rules: scrobble at 90% (audio
uses 50%), only after 60 s of play, with a timeline update every 10 s. Each server's API details
are in its own integration skill.

## Casting

Cast protocols are in `chromecast-casting`; this is the video player's side.

- **Video goes to a cast device only while a video cast is already running.**
  `targetVideoCastDevice` is the active session's device when `currentCast == .video` and the device
  supports video; otherwise it is nil and the video plays in the local window.
  `preferredVideoCastDeviceID` is a UI preference, not playback ownership. It may pick the default
  device in an explicit cast-menu action, but no entry point may use it to cast on its own, whether
  after relaunch or after an earlier cast. This holds for local files, HTTP streams, Plex, Jellyfin,
  Emby and mixed playlists. The local window is also what carries the video metadata and a
  stop-casting control.
- **A routed cast stops the local film only once the cast succeeds**, so a failed cast leaves local
  playback running. A video cast already running from the window is closed first
  (`closeForCastTransition`).
- **Closing the window stops the cast only if the window started it.** `didInitiateCast` is true only
  for a cast from the window's own cast button, and `windowWillClose` stops the cast only if
  `currentCast == .video` and `didInitiateCast` is true. A library-menu cast survives closing an
  unrelated player window. Video controls must cover both: the window's path uses `isCastingVideo`,
  while a library cast may have no window and goes through `CastManager.shared.isVideoCasting` /
  `currentCast == .video`.
- **An audio cast that replaces a video cast closes the window.** `CastManager` (`castNewTrack` and
  `cast()`) calls `WindowManager.closeVideoPlayerForCastTransition(wasVideoCast:)`. On the
  `castNewTrack` path `isCastingVideo` is still true. On the `cast()` path
  `stopCastingAndAwaitTeardown()` has already cleared it, so the check falls back to
  `wasVideoCast`, `isVideoCasting` or `currentCast == .video`, not to whether the window is
  visible. `closeForCastTransition()` does **not** call `CastManager.stopCasting()`, because the
  audio cast is already running. It sets `isClosing` before `close()` so that `windowWillClose`
  skips its cleanup.

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
- **Drive a film without the video keys.** In Classic the free window never becomes key (M28), so
  Space / arrows / Esc posted to the app go to the Library Browser. Park the film off the main
  window (`winhelper park <pid> "<film title>" 0 650`) and use the main window's transport, which
  routes to the film while one plays: Play, Pause (pause and resume), Stop (`stop()`), a click on the
  position bar (seek); Next skips 10 s. A row's double-click is the row path;
  `winhelper key <pid> 36 option` on a selected row queues it (Add to Queue), and Play then takes
  the track path. Measured 2026-10-08 (M17): the reporter lines of that sequence on Plex and Emby
  matched before and after a refactor except for timing values and async completion order.
- **Test fresh and reused windows separately.** A video played into the already-open window and one
  played after closing it go through different first-layout timing.
