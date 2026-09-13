# `portals.wmz`

## What it is

A 2001-era "Pedestal Magazine" promotional skin built around a brass-and-glass porthole: a circular
portal face with a lantern, an arc of gem-like transport ovals below it, and a second view (`mode2`)
that is a narrower vertical console. Two views, `mode1` and `mode2`, each switching to the other
through a `buttonElement` posting `setCurrentView`.

**`mode1` had never been on screen until 2026-09-13.** The walk opened `mode2` until W153 taught the
engine which view a skin declares it opens in, so nothing in `mode1` had ever been looked at — and
three things were wrong in it at once. That is the reason for this file: a view nobody has opened
accumulates defects silently, and all three of these were invisible to every headless probe that
had been run against the archive.

## What it exercises that little else does

**Three `<BUTTONGROUP>`s in one view that disagree about their own dead colour**, which is what made
it settle the paint rule rather than merely demonstrate it. Decoded with Pillow from the extracted
archive:

| Group | Art's dead region | Mask's dead region | `transparencyColor` | Before W154 |
|---|---|---|---|---|
| `cbuttons_play` | 24,997 px white | 24,997 px black | `#000000` | white slab at `13,236 280x140` |
| `sysbuttons_group` | 829 px magenta | 829 px black | `#000000` | 829 px magenta patch |
| `shufrep_buttons` | 3,723 px magenta | 3,723 px magenta | `#FF00FF` | correct |

The first two say the declared key names the **map's** dead colour, not the art's. The third is the
control: when the two dead colours happen to coincide, the one declared key covers both and the skin
always rendered correctly. One rule explains all three — a group's sheet is painted through its
mapping mask — and the third is what stops that rule being mistaken for "key the art's surround".

Its `main_button` is also the corpus's clearest **decorative full-window backdrop**: a 305x400
`<BUTTON enabled="false">` covering the entire view, which is what the window drag falls through to.

## Defects it found

1. **"It draws a white rectangle at `13,236 280x140`"** (W154). `cbuttons_play`'s sheet is white
   around the transport ovals and its `transparencyColor="#000000"` keys the mask's dead colour, not
   the art's, so the surround painted opaque. The slab was also *hiding* the brass casing beneath
   it — the view gained a whole assembly when it lifted, which is why the fix reads as more than a
   removed rectangle.
2. **"A click inside that rect drags the window instead of clicking"** (W154). A different cause
   sharing one trigger: `refreshHostState` disables every transport child while
   `player.controls.play` is unavailable — an empty playlist on a cold start — and
   `WMPMainView.interactiveTarget` answered `nil` for a disabled target exactly as it does for bare
   artwork, so `mouseDown` began a window drag. Measured live: a press on play moved the window from
   `680,279` to `374,509`.
3. **The 829 px magenta patch at the top of the view.** Carried for two phases as the corpus PNG
   sweep's opaque-magenta residual and attributed to W116; it was `sysbuttons_group`, and it closed
   with (1) rather than separately. The corpus residual went from 878 px across 2 views to 49 px
   across 1.

## What was ruled out

- **Not an overlay or compositing defect.** `WMP_RENDER_APPKIT=1` reports `hosted=0/2 outside=0` on
  this view, which clears the whole overlay class and leaves the group's own paint as the only
  candidate.
- **Not live-only, though it was reported that way.** The first reading of the headless dump said
  the ovals sat on transparency and the slab was live-only. They do not: the PNG is opaque white at
  `(14,237)`, and it *looked* transparent because a white slab on a white page is invisible. Read
  the pixel, not the picture — and the dump was the instrument after all.
- **Not a hit-map defect for the drag.** `mode1@259.5,259.5` resolves headlessly to
  `buttonElement#100` and posts `command=setCurrentView value=mode2` with nothing unrecognised. The
  headless scene was right the whole time; the difference was `refreshHostState`, which only runs
  live.
- **Not W152's class.** The two were filed as possibly the same thing — a group whose mapping
  regions never reached the hit map. They are unrelated: W152 turned out to be `digitaldj`'s own
  script gate, and this one is a live host-state disable.

## How to drive it

```bash
# Headless: the view, its probe lines, and the click that switches views
WMP_SKIN=~/Library/Application\ Support/NullPlayer/WMPSkins/portals.wmz \
WMP_RENDER_PROBE=mode1 WMP_RENDER_DUMP=/tmp/wmp/portals \
WMP_RENDER_CLICK='mode1@259.5,259.5' \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus
```

Live, `mode1` opens at 550x400 with the player body in its left 305 px. The transport ovals are
inside `cbuttons` at `13,236 280x140`; `sysbuttons_group` is at `149,44 55x31`. **Check the opaque
pixel rather than the rendered picture** when judging a keyed surround here:

```python
from PIL import Image
Image.open("mode1@1x.png").convert("RGBA").getpixel((14, 237))   # (0,0,0,0) is correct
```
