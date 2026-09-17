# `Compact.wmz`

Microsoft's own *Compact* skin, shipped with Windows Media Player 7 (`compact.wms` dated August
2001, its scripts March/April 2001). A 422x378 hand-held-looking player with a 320x240 screen, a
`titleBar="false"` window, and **two drawers that slide out of the body** — a playlist to the right
(179 px) and a three-tab settings pane below (102 px). It is a Microsoft SDK sample in everything but
name, so its idioms are the ones the corpus copies.

## Why it has a file

**Nine unrelated engine defects from one report** (W184-W192, 2026-09-16), **three of which no
headless probe could see**. Reported as *"drawer controls dont work in compact wmp skin"* and every
fault sat behind the one before it.

## What it exercises that little else does

| | |
|---|---|
| **The `event` object** | `view.maxWidth = event.screenWidth` in both drawer handlers, and `if (!event.shiftKey)` on each of ten equaliser sliders. 84 of 185 archives name `event.*`, but this is the only one whose *layout* depends on it |
| **A script-assigned alignment** | 20 writes, and **it is the only archive in the corpus that assigns one** (`horizontalAlignment`/`verticalAlignment` from script; decoded `.wms`+`.js` scan, 2026-09-16). W185 and W192 are both its consequences |
| **A one-axis window resize** | `view.width += rightMove` for one drawer, `view.height += bottomMove` for the other — never both (W186) |
| **`res://wmploc.dll` strings written into readouts** | its settings tab title and both on/off switches; 133 uses of 50 ids across 6 archives (W189) |
| **A `<RETURNBUTTON>` with no `onClick`** | `id="toggle"`, bottom right of the video. 19 uses across 15 archives and 15 author nothing (W191) |
| **A resize grip that calls `view.size('bottomright')`** | `onmousedown="DoSize();"`. Live since W193, and this is the skin it was closed on |

## Defects it found

Full rows, with the evidence each was closed on, are in
[`docs/wmp-skin/wmp-backlog-archive.md`](../../../../docs/wmp-skin/wmp-backlog-archive.md)
§ *W184-W192*. In the reporter's own words, in the order they arrived:

| Reported | Cause |
|---|---|
| *"drawer controls dont work in compact wmp skin"* | `event` undefined — the handler died on its first line (W184). The equaliser sliders and the EQ on/off switch inside the settings drawer died the same way and on `eq.bypass` |
| *"the drawers do not slide out they change the size/shape of the player"* | a script-assigned alignment anchored at the markup, so `playerView` stretched over the drawer (W185) — **and** a one-axis resize was not treated as a resize at all, so the window never moved (W186) |
| *"stretching the player can loose the right drawer"* | the same W185, plus a script transaction rebuilding at the last scene's canvas after a user resize (W187) |
| *"the right side drawer keeps stretching the window and releasing the stretch"* | the cumulative overrides re-asserting a stale axis (W188) |
| *"the srs text is misaligned"* | **not a layout defect** — the raw `res://wmploc.dll/RT_STRING/#1846` was 200 px of text in a box authored 110 wide for the word *On* (W189) |
| *"a big UI flash when the drawer opens"* | the window resized ahead of the picture that fits it (W190) |
| *"the library button does not call the library"* | `<RETURNBUTTON>` had no behaviour (W191) |
| *"the drawers disappear … stuck in a bad state that you cannot escape"* | **not reproduced from the reporter's steps.** The mechanism that provably strands a drawer is the pin/resize/unpin idiom (W192) |

## What was ruled out

- **The click never missed.** `WMP_RENDER_CLICK` answered `hit=playlistToggle#11 handlers=1` from
  the first attempt; every round of this report was a handler that ran and stopped, never a hit-test
  or occlusion fault.
- **`<RETURNBUTTON id="toggle">` does not touch the drawers.** Pressed with one drawer open, both
  open and both shut, live, on the build that fixed W184-W190: the window and the layout are
  unchanged every time. Neither does `shuffle`, the other button the reporter suspected.
- **Audio never triggers `DoSnapToSize`.** `player.currentMedia.imageSourceWidth/Height` answer
  `snapshot.video.*`, which is 0 with no video session, and the skin's own `h != g_lastVideoHeight`
  guard then stops after the first call. Only real video reaches `SnapToVideoSize`.
- **NullPlayer's own Compact Mode is not reachable here.** `ContextMenuBuilder` suppresses both
  Compact items for `controllerFamily == .wmp`, in the context menu and the Windows menu alike.
- **The EQ is not missing.** It is the second of the settings drawer's three tabs
  (`SRSSettings`, `AudioSettings`, `VideoSettings`, cycled by `ChangeSettingsTab`); the ◀ ▶ buttons
  switch it and all ten sliders are drawn and live.

## How to drive it

Scene coordinates, from `WMP_RENDER_PROBE=all`. The window is its own top-left origin, so a live
click is the window's origin plus the point.

| Control | Closed-state point | Notes |
|---|---|---|
| Playlist drawer tab | `409,158` | `frame=403,140 13x36`. With the drawer **open** it is at `587,158` |
| Settings drawer tab | `221,365` | `frame=202,359 38x13`; unchanged by the playlist drawer |
| Settings *next tab* (▶) | `120,437` | only while the settings drawer is open |
| Library / return to full mode | `384,294` | `<RETURNBUTTON id="toggle">`; `horizontalAlignment="right"`, so add the playlist drawer's 179 when it is open |
| Resize grip | `385,340` | `DoSize()` → `view.size('bottomright')`. **Not drivable headlessly**: `WMP_RENDER_CLICK` raises `onClick` only and this is an `onMouseDown`, so it reports `handlers=0`. Drag it in the app (Route C) |

```bash
# the whole report, headlessly
WMP_SKIN=~/Library/Application\ Support/NullPlayer/WMPSkins/Compact.wmz \
  WMP_RENDER_CLICK='compact@409,158' WMP_CALL_TRACE=1 \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus
```

**Read `viewSize=` on the `CLICK` line, not the picture.** W186 is the reason: the capture after the
click is correct whether or not the window would ever have moved, because the builder takes its
canvas from the overrides. `viewSize=601x378` (playlist) and `viewSize=422x480` (settings) are the
only headless evidence that the *window* follows.

## Still open

- **`DoSize()`'s brackets run before the drag, not around it.** W193 made the grip resize the window,
  but WMP's `view.size` blocks until the drag ends and this engine's cannot: a script transaction
  completes before its host commands are applied, so the pin *and* the unpin have both landed by the
  time the first pixel moves. The resize is right; what the skin does around it is early.
- **`moveTo(x, y, duration)` ignores the duration.** The endpoint is written at the end of the
  handler and `onEndMove` is raised immediately, so both drawers jump rather than slide. Reported as
  *"its not a smooth opening"*. Making it slide means moving `onEndMove` from *end of handler* to
  *end of tween*, and **36 corpus views chain their next step from that callback** — it is the
  drawer template Microsoft shipped — so it wants a corpus sweep either side.
- **44 of the 50 `res://wmploc.dll` string ids are blank**, including this skin's buffering and
  status format strings.
