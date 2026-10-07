---
name: album-art-visualizer
description: The Art window — the playing track's cover, its star rating, and 30 Core Image GPU effects (VIS) that transform the cover with the audio. Use when changing the Art window, its effects, intensity, keys, menu, rating, artwork source, sizing, or its place in the window stack and skin families.
---

# Art Window

A sub-window that follows the **playing** track: its cover, a star rating, and the VIS effects.
It replaced the Library Browser's ART mode (M10, 2026-10). The browsers have no art view and no
ART button any more.

## Opening it

- **Windows → Art** in every family.
- Original's main-window toggle row: **AR** (`btn_art`, between PM and EQ).
- It is a centre-stack window like PeppyMeter: it opens docked under the player, at the player's
  width (`nativeWindowDefaultWidth`), with its height cut to the cover's aspect ratio
  (`ArtView.preferredAspectRatio`, clamped 0.5–2, square when nothing is loaded). The chrome is
  measured from the frame the window view really draws (`ArtWindowChrome.chromeSize`, its
  `contentAreaRect()`), so Hide Title Bars and a `.wmz` gloss frame still open with the cover
  filling the hole (`ArtWindowController.defaultHeight(forWidth:)`, arithmetic in
  `ArtView.windowHeight`). It never opens below the window's minimum (Original: the single-height
  floor). A `.wal` skin opens it square, from the hosted registry's fixed default.
- Open state and frame persist through `app-state` (`isArtVisible`, `artWindowFrame`) and every
  window snapshot (Compact Mode, UI switch, UI Size).

## Using it

| Input | VIS off | VIS on |
|---|---|---|
| Click | star rating panel (held for the double-click interval) | next effect |
| Double-click | next embedded picture (a local file with several) | — |
| ← → | — | previous / next effect |
| ↑ ↓ | — | intensity ±0.25 (0.5–2.0) |
| V | VIS on | VIS off |
| R / C | — | random-on-beat / auto-cycle |
| F | fullscreen | fullscreen |
| Esc | leaves fullscreen | leaves fullscreen, else VIS off |
| 1–5, Delete | rate / clear while the rating panel is up | — |

Right-click: VIS toggle, effect navigation, Random / Auto-Cycle / Cycle Interval / Intensity,
**Effects** (grouped, with Set Current as Default), **Rate**, Fullscreen, Close.

## Effects (30)

Rotation & Scaling: Psychedelic, Kaleidoscope, Vortex, Endless Spin, Fractal Zoom, Time Tunnel.
Distortion: Acid Melt, Ocean Wave, Glitch, RGB Split, Twist, Fisheye, Shatter, Rubber Band.
Motion: Zoom Pulse, Earthquake, Bounce, Feedback Loop, Strobe, Jitter.
Copies & Mirrors: Infinite Mirror, Tile Grid, Prism Split, Double Vision, Flipbook, Mosaic.
Pixel: Pixelate, Scanlines, Datamosh, Blocky.

## How it works

- **One content view for every family.** `Art/ArtView.swift` draws, rates, animates and owns the
  menu and keys. The window views only frame it: `Windows/Art/ArtWindowView.swift` (Classic chrome;
  also the `.wal` hosted surface and the `.wmz` palette/borrowed frame) and
  `Windows/ModernArt/ModernArtWindowView.swift` (Original). Both conform to `ArtWindowChrome`.
- **One controller.** `Art/ArtWindowController.swift` owns show, default size, the F-key
  fullscreen and the window delegate for every family; each family adds only a factory beside its
  view (`ArtWindowController.classic()`, `.modern()`) that builds the window. `ArtView` reaches its
  fullscreen and close through `ArtViewHost`: the controller, or the hosted `ArtWindowView` inside
  a `.wal` skin.
- **The cover is `NowPlayingManager`'s** (`currentArtwork` + `artworkDidLoadNotification`) — the one
  fetch the app runs per track, the same image Control Center and a `.wal` `<AlbumArt>` show. A
  stream with an http `artworkThumb` (a radio station's logo) is fetched there too. The previous
  cover stays up until the next arrives. A local file with more than one embedded picture also
  loads them all (`ArtView.embeddedArtwork(of:)`) for double-click cycling.
- **Rating** goes through `TrackRatingService` (`isRateable`, `rating(for:)`, `setRating`), which
  all dispatch on one private `Source`, so `isRateable` is exactly "a write would land": a stream or
  a file outside the library is not rateable, and a click on it drags the window. Stars, keys and
  the menu all submit through `ArtView.submitRating`, debounced 0.5 s; only a newer rating cancels
  a pending one — hiding the panel, closing the window or a track change does not. The panel is `Windows/Shared/RatingOverlayView.swift` (shared with ProjectM); its stars
  shrink to fit a narrow window.
- **Effects**: `Art/ArtVisEffect.swift` — `ArtVisEffect` (cases, menu groups, wrap-around stepping)
  and `ArtVisRenderer` (one `CIContext` on the Metal device). The spectrum's 75 bands split 0–9
  bass, 10–39 mid, 40–74 treble.
- **Animation** runs at 30 fps only while VIS is on, a cover is loaded and the window is on screen
  and not occluded or minimized — one predicate, `ArtView.syncVisTimer()`. The spectrum consumer is
  `artWindowVisualizer`. During silence on a stopped/paused engine it stops redrawing after ~0.5 s.
- **Preferences**: VIS on/off `artWindowVisualizing`; effect, default effect and intensity keep the
  browser-era keys `browserVisEffect`, `browserVisDefaultEffect`, `browserVisIntensity`.
- **Skin families**: Classic and Original have their own chrome. `.wal` hosts it through the
  hosted-window registry (`WinampModernHostedWindowID.art`); a skin with no frame for it gets the
  Classic window in the palette's gloss frame, as PeppyMeter does. `.wmz` gets NullPlayer's window.

## Tests

`Tests/NullPlayerAppTests/ArtWindowTests.swift`: the height arithmetic, effect stepping and
grouping, every effect rendering a frame, saved-state round trip, rateability. To rate in a live
check, play a track that is in the local library (`library_tracks` in `library.db`) and put its
rating back afterwards; the test-data files are not in the library, so they are not rateable.

## Debugging a live defect

Read `live-ui-testing` first; `winamp-modern-skin-guide/reference/harness.md` § *Debugging a live
defect* is the reference workflow. To drive it: `skills/app-control/scripts/launch.sh <skin>` with
`NULLPLAYER_PLAY` set to `scripts/testdata.sh path audio-tagged` (it has a cover), open it with
`menu.applescript toggle <pid> <index> Art`, click or key it with `winhelper` and System Events, and
capture it with `winhelper capture`. VIS is proven by two captures a second apart differing. A size
question: `WMP_BORDER_TRACE=1` logs the interior and border `HostedWindowBorderLayout` decided.
