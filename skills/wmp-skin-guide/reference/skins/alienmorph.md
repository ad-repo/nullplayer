# `AlienMorph.wmz` — and the Alienware/ALX frame family

## What it is

A 2004 Alienware promotional skin, and the most-shared markup in the corpus: `AlienMorph`,
`ALXMorph`, `ALXVortex`, `AlienwareTeleport`, `Alienware_Darkstar_WMP11` and `Alienware Invader` are
the same player re-skinned, driven by one 50 KB `alienware.js` and one `alienware_dl.wms`. The
player is a 368x426 `mainView` with a long GIF intro; **everything else it does is in five separate
resizable windows** — `plView`, `eqView`, `visView`, `videoView`, `infoView`, each 389 wide, each
opened by `theme.openView` from a windowless `controlView` dispatcher (`timerInterval="100"`,
`onTimer="checkRemoteViewStatus()"`).

Those five windows are built out of a **nine-piece stretch frame**: two 175x76 corner bitmaps, a
tiled top and bottom tile, and two 175-wide side columns made of a centre piece plus a tile above and
below it, positioned off each other through `top="wmpprop:plLeftCenter.top"` and resized by
`onPlResize()` writing `plLeftTile.height = (view.height / 2) + 30`. The corner bitmaps carry the
window's *title bar* and the top of its *inner border*, not just a corner.

## What it exercises that little else does

- **The frame family is the corpus's densest use of `verticalAlignment="center"` with no authored
  coordinate.** Corpus-wide the attribute is 101 uses across 27 skins vertically and 283 across 67
  horizontally (`python3` scan over the installed corpus, alignment attribute values); this family
  puts two of them in every one of its five windows and then hangs two more subviews off each one's
  resolved `top`.
- **A sound effect in the middle of a state transition.** `toggleShutter()` opens the shutter, calls
  `theme.playSound('intro.wav')`, then stops its own intro timer — see `SKILL.md`, "a skin sound
  effect must not abort its state transition".
- **A 119-frame 0-centisecond GIF shutter**, which is what made it the named case for W142's
  animation floor.
- **Four `<BUTTON>`s authored the width of a ten-digit strip** (`time1.png` is 250x23) inside 25px
  clipping subviews, repainted per tick by `drawSeekDigits()` — the case W122's natural-size rule was
  measured against.

## Defects it found

| Reported as | Cause | Row |
|---|---|---|
| "the animation fps is low in general" | Every rebuild restarted the repaint loop — this skin's own 100 ms view timer restarted it ten times a second — and a 0/1-cs GIF delay was clamped to 0.1s | W142 |
| "the playlist and eq windows are not properly constructed and the window border and details are not correct and there are large gaps" | `verticalAlignment="center"` was read as a margin, so both side columns of all five windows collapsed to `top=0` and painted over the corner pieces that carry the title bar and inner border | W143 |
| "ALXMorph does nothing — no animation and nothing reacts" | The `mainView` starvation class; `alphaBlendTo` (W38), `backgroundImage` from script (W75) and an unset-preference default (W76) were each load-bearing | W68 (open) |
| "in all the alien type skins the numeric display is illegible" | A `<BUTTON>`'s `image` was scaled to its authored frame, blowing one tenth of one digit up ten times | W122 |

## What was ruled out

- **Not the resize path.** The W143 frame was broken at the view's own authored `389x247`, before any
  resize — which is the whole distinction that identified it, since at the authored size a margin
  alignment is a no-op and only `center` is not. `WMP_RENDER_SIZE=700x450` was checked afterwards and
  holds.
- **Not the hosted `PLAYLIST` overlay, and not AppKit.** The gaps are in the scene's own artwork;
  the missing column headers and `Selected:` / `Total Time:` footer in the same window are a
  different, still-open thing (W133).
- **Not the top tile's 100x170 artwork.** `f_top_tile.png` really is 170 tall against a 76px bar, and
  drawing it at its natural size is correct — everything below the bar is black, over a black
  `plFrame`, and WMP composites the same way. It reads as a defect in a screenshot and is not one.
- **Not `mainView`.** Byte-identical across W143; a non-resizable player authors no centred pieces.

## How to drive it

```bash
# The five windows, at their own size and resized, with every drawn node's frame:
WMP_SKIN=~/Library/Application\ Support/NullPlayer/WMPSkins/AlienMorph.wmz \
  WMP_RENDER_PROBE=plView WMP_RENDER_DUMP=/tmp/wmp/alien \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus
WMP_SKIN=…/AlienMorph.wmz WMP_RENDER_SIZE=700x450 WMP_RENDER_DUMP=/tmp/wmp/alien-big …
```

The frame pieces to read in a `PROBE` capture, in `plView` (`389x247`): `f_top_left.png` at `0,0
175x76`, `f_top_right.png` at `214,0`, `plLeftCenter` at `0,77 175x92` and `plRightCenter` at
`214,77` — **a `plLeftCenter` at `0,0` is W143 regressing.** The equaliser's preset label
(`txtEqPreset`, `value="wmpprop:eq.currentPresetTitle"`) paints an empty string headlessly; that is
the harness's stopped host, so read it live before filing it.
