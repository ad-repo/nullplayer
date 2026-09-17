# `circle.wmz`

Microsoft's WMP7 sample, 192x82, and the corpus's purest case of a skin that is **drawn by its
visualizer**. Five unrelated defects across one report and its three follow-ups (W213), none of
which any render dump shows; one of them was a rule this file previously held as *counter-evidence
in the opposite direction*, and one arrived as two separate complaints that are the same window
state. That is why it has a dossier.

## What it is

A dial. `vMain` is `backgroundColor="none"` with no artwork of its own; everything is hung off one
full-canvas `<SUBVIEW backgroundImage="visfield.bmp" transparencyColor="#FF00FF"
clippingColor="#FF0000">` — the *vis field* — with an `<EFFECTS zIndex="-1">` behind it sized
`jscript:vMain.width` by `jscript:vMain.height`. Three more views: `vVid` (314x216), `vPl`
(171x182), `vSettings` (171x92, its own `scriptFile`). None declares `resizAble`.

## What it exercises that little else does

**The skin is a stencil and the visualizer is the ink.** `visfield.bmp` is 192x82 in three
populations — 6,010 px of opaque body, 4,022 px of `clippingColor` matte, 1,122 px of
`transparencyColor` — and the last two are *both* the surface's. The matte is not an outline: it is
the right-hand third of the player, where the readouts, the next/prev buttons and the track number
all sit.

**The track number is drawn by the visualizer and by nothing else.** `sHundreds`/`sTens`/`sOnes` at
`137,24` / `153,24` / `169,24` cycle `num0.bmp`-`num9.bmp` from `UpdateTrackNumber()`
(`circle07.js:59`), and **all ten bitmaps are made entirely of the two key colours** — a magenta
glyph cut out of a red matte, zero pixels of ink:

```bash
python3 - <<'EOF'
from PIL import Image
for i in range(10):
    im = Image.open(f'num{i}.bmp').convert('RGB')
    print(i, len([p for p in im.getdata() if p not in ((255,0,255),(255,0,0))]))
EOF
# 0 through 9, every one: 0
```

So the digit *is* whatever the surface paints behind it. Any rule that stops the surface reaching
those pixels deletes the readout, and no headless probe can see that it has.

**Its `<EFFECTS>` is the whole window**, which is what makes it the input case as well: 51 corpus
skins wire `onClick` on the surface, and this is the one where the rect is the entire player.

## Defects it found — W213, reported 2026-09-17

> *"the circle skin has multiple issues, it cannt be dragged and looks to be missing parts of the
> UI. also the vizulization opens below it"*, then *"it is still missing hte backing on the volume
> and the vizulization still pops under it"*, then *"the only thing fixed was the drag"*, then
> *"the volume doesnt seem to work. when i streched the window the visulization popped out and
> stretched bu the app didnt"*.

1. **The window could not be dragged anywhere.** The `<EFFECTS>` hit covered the whole rect, so
   every press on the skin's body answered `visEffects` and never reached `beginWindowDrag`. Fixed
   by `WMPHitCoverageBuilder.surfaceCoverage` — a hosted surface is reachable only where the skin
   has not painted over it, which is this skin's 1,122 px of fringe and its digit glyphs.
2. **"the visualization opens below it" — the window was 63 px too tall.**
   `WindowManager.tightenClassicCenterStackIfNeeded` is Classic's stack repair and
   `isRunningModernUI` answers false for the WMP controller, so it ran over a borderless skin window
   and grew it to `Skin.mainWindowSize.height`. It fires from `windowDidFinishDragging` — so the
   *first click* did it, a press on bare artwork being a window drag — and the extra 63 px filled
   with the skin's own `jscript:vMain.height` effects rect as a bar spectrum hanging off the bottom.
   `WMP_SIZE_TRACE=1` named it in one launch after two days of reasoning had produced a guard
   against the wrong cause.
3. **"missing the backing" — the visualizer had no backdrop, so the window had holes in it.**
   `WMPEffectsGround` was granted only where an *ancestor* states a shape; `vMain` states none, so
   the rect took no ground and every pixel the artwork keys away showed the desktop. See below.
4. **Stretching the window left the visualizer stretched and the skin behind, and every control
   stopped answering.** `window.minSize` was `WMPMainWindowController.unskinnedSize` — 440x170 —
   and nothing ever moved it, so this 192x82 player carried a floor four times its own size. AppKit
   enforces `minSize` *after* the delegate answers, so the first edge drag snapped the window to
   440x170 with the scene still 192x82. The artwork is rasterized at the scene's size and sits in
   the corner; the hosted surfaces and `skinPoint(from:sceneSize:)` both come from
   `bounds / canvasSize` and followed the window. **That is one defect reported as two** — *"the
   volume doesnt seem to work"* is the hit map stretched off its own artwork. `applyWindowSizeLimits`
   now tracks the presented scene.
5. **`<DURATIONTEXT>` was not an element**, so the track length never drew: no host value, no
   glyphs, and a `<TEXT>` is sized by its glyphs, so `WMP_RENDER_UNRESOLVED` reported
   `missing literal geometry (height)` and the node was dropped. `circle` and `pharaoh` are the
   corpus's two uses (`scripts/wmp_markup_census.sh <out> DURATIONTEXT`).

## What was ruled out

- **The stored size was not the cause of (2).** `WMPViewFrameStore` did have `192x145` on record,
  and a fixed view taking a size from outside itself is a real defect that was fixed — but clearing
  the record and relaunching still gave 192x82, and the window still grew on the first click. **A
  plausible cause that reproduces the symptom is not the cause.** Read the `WMP_SIZE_TRACE`
  backtrace before believing any size story about a `.wmz` window.
- **The volume slider was never broken.** Its hit resolves (`WMP_RENDER_CLICK vMain@23,18` →
  `hit=volume#11`), its position map tracks (`vMain@23,18>20,33>25,53` → 100 / 53.3 / 0), and its
  filmstrip follows the host (`crop` x = 0 / 152 / 285 at `vol=0` / `0.5` / `1`). It was defect (4)
  all along — the control had moved out from under the pointer. **Stop playback before measuring
  anything in its rect**: the visualizer idles at ~1,800 px of change between two captures window-
  wide, and 0 inside the volume's rect, which is the only reason a 758 px drag reads as signal.
- **`visClassicTransparentBg.wmpEffects` was not the cause of (3).** Setting it false changed
  nothing; the hole was the absent ground, not the visualizer's own alpha.
- **The `clippingColor` matte is not a window outline.** Confining the surface to `visfield.bmp`'s
  keep region was built, measured **clean across the whole corpus** — 550 of 553 images identical,
  `rect-only` unchanged, the only `shape=` population change being `circle` itself and an
  `offshape=0` no-op on `polygon` — and is wrong: it deletes the track-number readout. A corpus
  sweep cannot see a defect whose evidence is what a *surface* paints, and this is the sharpest
  example in the corpus of `harness.md`'s rule that a clean sweep is not a proof of correctness.
- **The black right-hand field is not a defect.** It is the visualizer's, and it reads as a black
  slab whenever nothing is playing — which is the state every capture in the first report was taken
  in.

## How to drive it

```bash
defaults write NullPlayer wmpSkinName -string "circle"
defaults delete NullPlayer wmpSkinViewID
WMP_SIZE_TRACE=1 NULLPLAYER_PLAY="$(scripts/testdata.sh path audio-long)" \
  nohup ./.build/arm64-apple-macosx/debug/NullPlayer -uiMode wmp > /tmp/app.log 2>&1 &
```

Scene coordinates in `vMain`, decoded from `trans_colormap.bmp` at the group's `24,19` (take the
**median** pixel of each colour, never the first):

| Target | Point | Notes |
|---|---|---|
| play / pause / stop | `41,36` / `77,36` / `113,36` | `<PLAYELEMENT>` etc. in one `<BUTTONGROUP>` |
| next visualization | `82,66` | `visEffects.next()` |
| playlist (`vPl`) | `104,66` | `theme.openView` |
| audio controls (`vSettings`) | `126,66` | |
| bare body — the drag test | `160,70` | must `MISS`; anything else and the window is stuck |
| the visualizer's own fringe | `69,68` | must hit `visEffects` |
| volume arc, full → zero | drag `23,18>20,33>25,53` | `vol_map.bmp`'s greys are 255 / 136 / 0 there |

**`onClick="previous();"` on the `<EFFECTS>` still throws** `ReferenceError: Can't find variable:
previous`. WMP resolves an unqualified call in a handler against the element the handler is on;
`pharaoh` authors the same idiom as `next();`. Open, and not part of W213.
