# `cerulean.wmz`

## What it is

A Microsoft sample from June 2000 — the same fortnight as `colorchooser`, and among the oldest
authoring in the corpus. A 237x412 blue head: a display panel across the forehead, a transport
strip under it, and the player's whole lower two thirds is one `<subview top="170">` whose
`backgroundImage="face.bmp"` is the face itself. The visualizer is the left eye.

## What it exercises that little else does

**It confines a hosted surface by *paint*, and it is the corpus's reference case for that.**
`face.bmp` is 237x242 of opaque artwork with a `#FF00FF` hole cut for the eye — 4,264 px of key,
13,438 px of `#FF0000` matte, 0 px of genuine transparency — and its `<effects zIndex="-1">` is
drawn *under* it through `WMPWidget.commandSplitIndex`. Nothing shapes the surface; the face simply
covers everything but the hole. That is the opposite of the `Plus!` idiom, where the container's
artwork *is* a mask, and getting the two the wrong way round on this skin does not distort its
visualizer, it erases it — see `plus-family.md` and § *A container shapes its windowless
`<EFFECTS>`* in `SKILL.md`.

It is also the corpus's proof that **`zIndex` is ordered among siblings, not flat across the view**:
`<statusText zIndex="2">` inside `<subview zIndex="4">` has to draw over the seek slider beside it,
while `<effects zIndex="-1">` sits under the face with `<button id="bEye" zIndex="-2">` under that.
Flattening the order to WMP's documented "z-order within the view" breaks the first, and it is not
what W144 needed anyway — the answer there was `windowed`, not z. **W166 does not change this**: a
script-assigned `zIndex` now supplies the number, and the number is still sorted among a node's own
siblings. `xsn-sports.md` states the same rule from the other side and says so by name.

```bash
WMP_SKIN="$HOME/Library/Application Support/NullPlayer/WMPSkins/cerulean.wmz" \
  WMP_RENDER_PROBE=all swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus 2>&1 \
  | grep '^WIDGET'
# WIDGET view-2/29 effects id=visEffects frame=118,204 103x75 clip=0,170 237x242
#   visible=118,204 103x75 shape=face.bmp@0,170 237x242 keys=#FF0000 offshape=104
```

## Defects it found

- **W198 — *"the visualization is sticking out of the right side of the face by a few pixels … I
  have seen similar on other skins"* (2026-09-16).** Paint can only occlude where the window
  exists. `face.bmp`'s last three columns inside the `<EFFECTS>` rect are `#FF0000`, its
  `clippingColor` — pixels the skin cut out of its own silhouette, where nothing is painted and so
  nothing hid the surface. Fixed by carrying the container's `clippingColor` region onto the widget
  as `WMPWidget.clippingShape`. **No headless probe could see it**: the surface is an `NSView` that
  no render dump contains, and the leak is *inside* the widget's own rect, so `WMP_RENDER_APPKIT`'s
  `outside=` reads 0. `offshape=` was added for it. The reporter was right that it was not one skin
  — 6 of the 96 `<EFFECTS>` the sweep places overhang their silhouette.
- **W139** — its bars drew across the whole face on the first attempt at hosting the surface, which
  is what established the two-raster split. See the W139 row in the backlog archive.

## What was ruled out

- **Its `face.bmp` is not a shape mask and must never be read as one.** `WMPImageStore
  .shapesChildrenByRegion` is the guard, and it excludes this skin on purpose: reading `#FF00FF` as
  "outside" would keep the surface only where the face already covers it and clip it away inside
  the hole. 28 of the corpus's 30 keyed `<EFFECTS>` containers are two-state like this one; only
  `Plus! Bionic Dot` and `Plus! Professional` are the three-state case.
- **It is not one of the skins that need an `<EFFECTS>` ground suppressed** (W174). It takes one and
  the ground is correct, because the black is behind a hole in opaque artwork; `circle` and
  `Plus! BubbleSkin` are the skins that hold that rule down, not this one.
- **W198 was not an off-by-one in the widget frame.** The rect is `118,204 103x75` and the view is
  237 wide, so it ends 16 px short of the window edge; the leaked pixels were at x 218-220, inside
  the authored rect and outside the drawn face.

## How to drive it

The window is 237x412 and the skin is not resizable, so screen coordinates are window origin plus
scene coordinates at 1x. Measured 2026-09-16 with `screencapture -l <id>` at 2x:

| Target | Scene rect |
|---|---|
| `<EFFECTS>` (the eye) | `118,204 103x75`; the `#FF00FF` lens is 4,264 px of it |
| The clipped columns W198 was about | x 218-220, y 204-253 |
| Transport strip | see `PROBE` lines for `transport_map.bmp` |

```bash
skills/app-control/scripts/launch.sh cerulean
```

**Nothing playing draws nothing at all**, so a capture with a stopped player shows the skin's own
`vis_area_default.bmp` and says nothing about the surface. Play something before measuring it.
