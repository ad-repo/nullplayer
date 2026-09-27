# `cyberchannel`

## What it is

A 2000 WMP7 skin by sign define, cp1252 markup (`iconv -f CP1252`, not UTF-16). One 524x430 player
view drawn entirely from full-canvas bitmaps — `back.bmp`, `hover.bmp`, `disabled.bmp` and `map.bmp`
are all 524x430 — with every control but the two sliders living in one `<BUTTONGROUP>` of 15 mapping
colours. A `<VIDEO>` and an `<EFFECTS>` share the screen rect, swapped by `StartVideo()`/`EndVideo()`
in `cyberchannel.js`. Its second view, `playview`, is a bare `<PLAYLIST/>` with no size (see *Ruled
out*).

## What it exercises that little else does

- A `<PROGRESSBAR>` as the seek bar, committing through its own
  `onmouseup="player.controls.currentPosition = progress.value;"`, beside
  `<PLAYER><CONTROLS currentPosition_onchange="progress.value = …">` — the write-back runs every tick.
- A `<VIDEO backgroundColor>`, so every render builds the W312 whole-canvas paint mask.
- Full-canvas artwork at 2x makes every rebuild expensive, so it is where a slow render shows first.

## Defects it found

Reported 2026-09-26 as *"track time display has 0:00 while track is running"* and *"it might have
dead buttons too"*. Three unrelated defects:

1. **The clock never left `0:00`.** The bindings were right — `position.value` resolved to `0:01`,
   `0:02`… each tick — but the render took ~90 ms (debug, 2x) against the 100 ms clock tick, so every
   transaction was cancelled by the next one before it presented. Cause: `WMPRenderer.paintedMask`
   copied alpha out a pixel at a time. See `../input.md` § the release-build bullet and
   `../rendering/video.md`.
2. **The seek bar was dead.** `<PROGRESSBAR>` was not treated as a slider, so a press never moved
   `value` and the skin's own handler seeked to the live position. See `../input.md` § *A
   `<PROGRESSBAR>` is a slider*.
3. **A press on a disabled Play seeked the track.** The release went out untargeted and ran every
   `onmouseup` in the view. See `../input.md` § *A release with nothing pressed*.

## What was ruled out

- **The binding path.** `WMP_RENDER_HOST=playing` headless draws `1:03` correctly; the defect is
  live-only, in presentation, not in `wmpprop:` resolution.
- **A seek loop pinning playback at 0.** The per-tick `currentPosition_onchange` write posts no host
  command; `currentTime` advances normally.
- **Missing button hits.** `OCCLUDED … masks=1 of 3 hits` looks alarming but the group is one hit
  carrying 15 mapping targets. Every mapping colour is present in `map.bmp`, and `WMP_RENDER_CLICK`
  reaches all of them.
- **Next and Previous "dead".** They carry `enabled="wmpenabled:player.controls.next"`/`previous`;
  `launch.sh` queues one track, so both are correctly disabled. With three tracks both work.
- **Fast forward / rewind "dead".** They are `beginScan` on press, `endScan` on release — a quick
  click scans for a moment and looks inert. Hold to test.
- **The Playlist button opens nothing.** It calls `theme.openView('playview')`, and `playview`
  authors no size and no image, so WMP's own arithmetic makes it 0x0 (W200,
  `../harness-history.md`). Accepted as WMP behaviour, not fixed.

## How to drive it

`skills/app-control/scripts/launch.sh cyberchannel`. The window opens at 524x430; controls by
`map.bmp` median pixel (skin coordinates, add the window's top-left):

| control | x,y | control | x,y |
|---|---|---|---|
| play | 332,239 | pause | 299,234 |
| stop | 366,241 | next | 412,285 |
| prev | 253,269 | ffwd | 392,255 |
| rew | 272,267 | open file | 406,180 |
| playlist | 370,180 | close | 420,85 |
| minimize | 401,85 | next / prev vis | 261,165 / 250,164 |

Seek bar: `left=67 top=179` 164x13, `borderSize=8`. Clock readout: 384,124 30x16. The two
`launchURL` buttons (34,151 and 331,361) open external sites — do not click them in a test.
