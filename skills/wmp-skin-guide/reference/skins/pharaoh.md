# `pharaoh`

## What it is

Microsoft's own June 2000 WMP7 sample — the same fortnight as `Colorchooser` and `Compact`, and
authored to the same house idiom. A 400x249 window that is **not a rectangle**: a photographic
sphinx in front of a pyramid, with everything outside the animal keyed away. It carries four views
and three script programs in an archive of 49 entries, and almost nothing about it is ordinary:

- **Two modes in one view.** `sSphinx` (400x249) and `sScarab` (132x117) are sibling `<SUBVIEW>`s of
  the same canvas, toggled by `ToggleScarab()`. The window does not resize — the scarab is simply a
  smaller silhouette inside the same 400x249 frame, which is what a `clippingColor` region means.
- **Two ghost views.** `vGhost` and `vGhostAutoDetect` are `width="0" height="0"` and exist only to
  read a preference and decide what to open. They are the corpus's **only** explicitly zero-canvas
  `openView` targets.
- **A fourth view that is a real panel.** `vRos`, 197x194, the "rosetta" — a playlist, a video box
  and a bass/treble/balance pane stacked in one hole, switched by a three-element `<BUTTONGROUP>`.

## What it exercises that little else does

| Thing | Number | How it was measured |
|---|---|---|
| A container with a `backgroundColor` **and** keys **and** a background image | **10 nodes in 9 archives**, and `pharaoh` is 2 of them | scan of every `<VIEW>`/`<SUBVIEW>` over the 185 installed archives, decoded as `WMPTextDecoder` does (158 UTF-16, 146 cp1252, 89 UTF-8, 9 UTF-8-BOM) |
| An `<EFFECTS zIndex="-1">` behind a `transparencyColor` hole in its container's artwork | **5 of those 9** — `aoe`, `bluegrid`, `claw`, `gadget`, `pharaoh` | each rect compared against the hole's bounds in the container's bitmap; every one within 2 px |
| An `openView` target with **no canvas** | **2 of 185 archives** — `pharaoh` (twice) and `cyberchannel`'s `playView` | every `openView`/`openViewRelative` target resolved against its own `<VIEW>` declaration |
| Two `scriptFile` programs defining the same top-level function names | **6 of 184 archives** (the first count said 7 and included `Sports`, whose second `.wms` never loads); `pharaoh` collides on `OnOpenStateChange` and `UpdateMetadata` | every `function <name>(` in each program the **loaded** definition names |
| A GIF whose frame image blocks are far smaller than its logical screen | **27 files in 12 archives** of 4,303 GIFs, and `pyrevolver.gif` is the extreme at 6.7% — and the only one of the 27 with **no global colour table** (W201) | every image block against the screen descriptor, and the screen descriptor's global-table flag |
| `<DURATIONTEXT>` | **2 nodes in 2 archives** — this and `circle` | tag census |
| The widest filmstrip in the corpus | `seek_steps.bmp`, 15990x20 | `reference/loading.md`; it is why the axis bound is 32,768 (W33) |

The first three rows are why it found what it found. It is also the skin that **states its own
control**: `vRos` is the same markup as `sSphinx` with `backgroundColor="none"` instead of
`"black"`, so every claim about the fill has a within-archive comparison.

## Defects it found

### The 2026-09-16 report — *"pharoh skin has 3 issues"*

> *"first is w199 the second is you can get trapped in the mini winodws with no way back to the main
> window. also no visulixation displays"*

Three reported, two causes.

| # | Reported | Cause | Row |
|---|---|---|---|
| 1, 3 | the window is a rectangle; no visualizer | the container's `backgroundColor` fill was painted as a bare rectangle **under** its own colour-keyed artwork, filling in both the `clippingColor` matte outside the silhouette and the `transparencyColor` hole the visualizer shows through | W199 |
| 2 | trapped in the mini windows | a windowless view opened by `theme.openView` ran its window-scoped commands against **the opener**, so a ghost's redirect replaced the player and a ghost's `view.close()` closed it | W200 |

**Why 1 and 3 are one defect.** `sphinx.bmp` is 400x249 and carries 53,252 px of `#FF0000` (its
`clippingColor`) and 1,608 px of `#FF00FF` (its `transparencyColor`). The magenta is *all* inside
the 87x37 visible part of the `<effects id="visSphinx" zIndex="-1" left="114" top="-37">` rect — it
is the pyramid apex, cut out of the artwork so the visualizer shows through it. The black fill
covered both, so the render came back **0 transparent px of 99,600**, and the visualizer was hosted
and running under it the whole time (`VisualizationGLView: Setting up ProjectM with viewport
174x148`, which is the 87x74 rect at 2x). `vRos`, same markup, `backgroundColor="none"`: 1,462
transparent px, exactly `rosetta.bmp`'s `#FF0000` count.

**Why 2 survived a relaunch, which is the half that matters.** `OnLoad()` calls
`theme.openView("vGhost")` on **every** launch, and `vGhost`'s whole body is
`if(theme.loadPreference('paneOpen')=='true')theme.currentViewID='vRos';else view.close();`. The
skin saves `paneOpen` itself — `CloseRos()` writes `false`, `vGhostAutoDetect` writes `true` — so
whichever branch the user left it on, the next launch either closed the player before it was seen or
replaced it with the 197x194 panel. There is no route out of that inside the skin, and restarting
does not clear it.

### Still open

**`W201` — the `pyrevolver.gif` back button drawing as a black box — closed 2026-09-24.**
`pyrevolver.gif` is a 140x128 logical screen whose 16 frames are each a 21x16 block at 0,0, and it
is the corpus's only GIF with frames smaller than the canvas **and no global colour table**. That
leaves the canvas outside the frames undefined, ImageIO decodes it as opaque black, and the 21x16
`<BUTTON>` had the whole canvas stretched into it. Such a GIF is now trimmed to its frames
(`WMPGIFCanvas`); the other 26 undersized-frame GIFs all carry a global colour table, decode
transparent, and keep their canvas. Closure: `docs/wmp-skin/wmp-backlog-archive.md` § *W201*.

**`W202` — the scarab's visualizer never appearing — closed 2026-09-24 as not reproducing.**
Driven live, the click logs `create id=27 kind=effects frame=1,7 129x79` under `WMP_WIDGET_TRACE=1`
and the wing lattice animates. Two traps made it look broken. **A `Setting up ProjectM` line is not
evidence of a surface**: the effect is shared across skins, and with any other effect selected
neither view logs it. And **the first click on an inactive window only activates it**, so the
scarab does not open. Closure: `docs/wmp-skin/wmp-backlog-archive.md` § *W202*.

**`W203` — `<DURATIONTEXT>` never renders**, so the face reads `1:03 /` with nothing after the slash.
`<currentPositionText>` at `57,86` and the literal `/` at `103,86` both draw;
`<durationText left="108" top="86" width="45" fontSize="8" justification="Left">` produces no `PROBE`
line at all and is the view's single `unresolved`.
`WMP_SKIN=…/pharaoh.wmz WMP_RENDER_UNRESOLVED=1 WMP_RENDER_HOST=playing` names the dimension:
`UNRESOLVED view-2/11 durationText id=- size=missing literal geometry (height)`.
**`<currentPositionText>` beside it declares no `height` either and resolves to 45x10**, so the
missing piece is a glyph-height fallback this one tag does not get, not anything the skin failed to
author — **which means a `<DURATIONTEXT>` anywhere is dead**, not just this one. Only 2 nodes in 2
archives (`pharaoh`, `circle`), kept as a row because it is a *visible* readout on a shipped
Microsoft skin.

**`W204` — every view in a skin shared one script scope — closed 2026-09-24.** The function half
closed with W257: the rosetta's `OnOpenStateChange` no longer runs in the main view. A playing-host
`WMP_CALL_TRACE=1` sweep, A/B'd with `WMP_VIEW_SCRIPT_SCOPE=0`, shows the main view writing
`visSphinx`/`visScarab` (its own handler) where the old binding wrote `bgVid.enabled`. The one
shared value, `vidIsRunning`, is derived from the same player state in both views, so one variable
serves both. The old `ReferenceError: bgVid` no longer appears even with `=0`: since W40 every
view's elements are bound, so the wrong handler now runs silently rather than throwing. Closure:
`docs/wmp-skin/wmp-backlog-archive.md` § *W204*.

## What was ruled out

- **The visualizer was never missing, disabled or unmounted.** Two `Setting up ProjectM` lines are in
  the log for the two modes at the sizes the markup asks for, and the `WIDGET` line reports
  `shape=sphinx.bmp… offshape=1524` rather than a dropped widget. Every instrument said the surface
  was fine, because it was; something opaque was drawn over it. **`offshape>0` is a rect to check,
  not a defect** — it measures what the skin authored.
- **W198 was not the cause and its fix was not wrong.** Confining the surface to the window's shape
  is right; it was simply not the whole of it. `pharaoh` was already recorded as W198's
  counter-evidence for exactly this reason.
- **Scarab mode is not the trap.** The `pyrevolver.gif` button draws as a black box and looks dead,
  and it is not: a click at `66,25` returns to the sphinx view. The trap is `vRos`.
- **`view.returnToMediaCenter()` is not the trap either.** It is `UNRECOGNISED` (the cyan transport
  element, *"Return to Full Mode"*) and always has been, but it is not the route the report is about.
- **The black behind the dithered apex is not the visualizer rendering black.** `tip.bmp` is an 85x36
  half-dithered pyramid drawn *over* the rect, so roughly half the hole's pixels are the surface.
  With a track playing, **1,595 of the 1,608 hole pixels change between two captures 0.7 s apart and
  0 of the 87 artwork pixels do.** That diff is the measurement; the still is not.

## How to drive it

```bash
defaults write NullPlayer wmpSkinName -string "pharaoh"
defaults delete NullPlayer wmpSkinViewID
NULLPLAYER_PLAY=/abs/path/track.mp3 \
  nohup ./.build/arm64-apple-macosx/debug/NullPlayer -uiMode wmp > /tmp/app.log 2>&1 &
```

Decoded coordinates, in the player window's own top-left points. The transport is one
`<BUTTONGROUP>` at `248,181` over `transport_colormap.bmp`; each element below is the **median**
pixel of its mapping colour, never the first (`reference/harness.md` says why).

| Control | Point | What it does |
|---|---|---|
| Scarab mode | `271,119` | `ToggleScarab(true)` — swaps to the 132x117 silhouette in the same window |
| Sphinx mode (back) | `66,25` | `ToggleScarab(false)`, in scarab mode only. The animated red-gem pyramid (W201 closed) |
| Audio controls/Playlist/Video | `358,212` | `theme.openView('vGhostAutoDetect')` → opens `vRos` beside the player |
| Return to Full Mode | `365,200` | `view.returnToMediaCenter()`, `UNRECOGNISED` |
| Previous / Next | `258,208` / `270,222` | |
| Stop / Minimize / Close | `305,228` / `382,196` / `392,189` | |
| Close rosetta | `98,13` in the `vRos` window | `CloseRos()` — saves `paneOpen=false`, then `vRos.close()` |

**Playback is not optional here.** `OnOpenStateChange` only reaches the branch that throws
(`bgVid`, W204) when `player.openState == osMediaOpen`, and the visualizer cannot be told from a
black fill without frames to diff. `WMP_RENDER_HOST=playing` does it headlessly:

```bash
WMP_SKIN=~/Library/Application\ Support/NullPlayer/WMPSkins/pharaoh.wmz \
WMP_RENDER_DUMP=/tmp/wmp/ph WMP_RENDER_PROBE=all WMP_RENDER_UNRESOLVED=1 WMP_RENDER_HOST=playing \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus > /tmp/wmp/pharaoh.txt 2>&1
```

Two traps in reading that capture. `vGhost` and `vGhostAutoDetect` print
`PNG … FAILED [WMP0035] Canvas and backing scale must be positive` — a `RENDER-DUMP … FAILED` line
before W245 — and **that is correct**: they are windowless by construction (W6), they report their
`0x0` stats on their own `RENDER-DUMP` line, and only the *write* is refused. And a scene with an `<EFFECTS>` is **two rasters**
(W139): `render(scene:).image` is only the layer below the surface, so the container's keyed artwork
is in `overlayImage` and a test that reads the first one alone sees a window that is not there.
