# `xsn_sports.wmz` — XSN Sports

## What it is

A Skins Factory commercial skin for WMP 9 (2003), 180 archive entries, `xsn.wms` in UTF-16LE with
`xsn.js` in Windows-1252. Seven views — `mainView`, `plView`, `eqView`, `visView`, `videoView`,
`msgView`, `upgradeView` — all built from the **same eight-piece frame drawn eight times over**, once
per colour, with `alphaBlend` cross-fading between the copies on a 500 ms view timer. That is
"Hyper-Transient Color Phasing™", and it is why every auxiliary view of this skin carries 64
`<SUBVIEW>`s of chrome before any control.

Its auxiliary views each hang a **settings drawer** off the bottom edge: a 141x131 `<SUBVIEW>` that
slides vertically, with the visualisation timer controls on it, a tab to open and shut it, and its
open/shut state persisted through `theme.savePreference`.

## What it exercises that little else does

- **A centred piece moved by script.** `visDrawer`/`vidDrawer` are
  `horizontalAlignment="center"` with no authored `left`, slid by
  `visDrawer.moveTo(0, view.height-73, 400)`. The `0` is not a position — `moveTo` takes both axes
  and the horizontal one is the author's way of saying "unchanged".
- **A windowed visualization.** `<effects ... visible="true" windowed="true">`. 17 of 180 archives
  declare `windowed="true"`; 106 declare `false` and 46 leave it absent.
- **A view timer against a scripted position.** `visView` is
  `onTimer="htcpVis()" timerInterval="500"` while the drawer's resting place is the *authored*
  `top="jscript:view.height-123"` — so a bug in expression re-application shows up here within half
  a second and nowhere that lacks a timer.
- **State saved in `onClose`.** `onClose="saveVisPrefs()"` writes `visDrawerStatus` and the view's
  own size; `onLoad="loadVisPrefs()"` restores both, branching on the `--` absent sentinel.

Both counts are markup scans over the installed corpus and must be re-derived with the BOM-aware
decoder in `../harness.md` § *Counting a tag across the corpus* — a `grep` over these files reads
UTF-16 as mojibake and returns zero. Measured 2026-09-12 over 180 archives: `windowed="true"` 18
nodes / 17 skins, `"false"` 114 / 106, absent 52 / 46; `onClose` 373 handlers / 133 skins.

## Defects it found (all W144, 2026-09-12)

Reported live in one message: *"there is a bug with video screen on xsn sports skins and others… this
does not open reliably… when clicking this it can grow to double size on the border… there also seems
to be a mini drawer that opens into the the frame with a seconds selector, this never closes."*

1. **The drawer sat at the window's left edge while its own cover artwork stayed centred**, so the
   window drew what the reporter called two drawers, one "double size on the border". Cause: the
   `isComputed` guard W143 carried onto the `center` case let the scripted `left=0` beat the
   centring. `center` now wins unconditionally on its axis. A decoded corpus scan puts only **3**
   centred nodes with an authored expression on the centred axis — all in `Ice`, and all three are
   repaired by the same change.
2. **The drawer snapped shut again ~500 ms after every click** — *"it still does not open"*. Cause:
   an authored `JScript:` geometry expression was re-committed on every transaction, ahead of the
   mutations, so any transaction that did not touch the node put it back at
   `view.height-123`. Expressions now re-apply only when their own value changes, which keeps the
   resize case working.
3. **The retracted drawer's artwork bled through the visualization** — *"the contents still show
   when retracted"*. Cause: the skin's overlay raster was drawn over a **windowed** effects surface.
   See *What was ruled out* — this one cost the most.
4. **The drawer opened itself on every launch.** Cause: `onClose` had **no dispatch site at all**, so
   `saveVisPrefs()` never ran, nothing was ever persisted, and `loadVisPrefs` took its first-run
   branch every time. 373 `onClose` handlers across 133 of the 180 archives were dead.

## Defects it found (2026-09-12, borrowed window frames)

Reported live while testing the borrowed-frame work: *"the nullplayer window does not follow the
color theme selected in xsn"*, *"on the xsn the issue is there are 2 eq windows"*.

5. **Two equalizer windows.** Not an xsn defect at all — it is the *fallback* rule failing on a skin
   switch, and xsn is where it shows because xsn declares `<EQUALIZERSETTINGS>` (164 of the 180
   archives declare an equaliser). Loading a `.wmz` with none opens NullPlayer's; switching from
   there to xsn left ours standing beside the skin's. The reporter diagnosed it themselves — *"if
   you switch skins from a skin that has no internal eq to one that does it carries that window to
   the new skin"* — and they were right.
   `WindowManager.dismissWMPFallbackSurfacesTheSkinProvides()` now runs on every presentation.
   **The lesson generalises past the equaliser**: any "ours or the skin's" decision taken when a
   window opens has to be retaken when the skin changes.
6. **A borrowed window frame wears the skin's *opening* colour, not its selected one** (W145, open).
   xsn's colour scheme is not a palette: `plView` stacks **all eight frame variants** (`pl1_1`…
   `pl1_8`, 2-8 authored `alphaBlend="0"`) and `htcpStartupPl()` cross-fades between them from the
   `htcpID` / `winAlpha` preferences, read in the view's own `onLoad`. "Hyper-Transient Color
   Phasing", trademarked in a comment block in `xsn.js`. Anything that reads this skin's appearance
   from markup alone gets variant 1 forever.

**And xsn is the reason the donor view is ranked rather than taken.** `WMPHostedFrameTemplate` looks
for the best eight-piece ring in the skin, and xsn wraps the *same* ring around `upgradeView` — the
"your Windows Media Player is too old" nag panel — which is declared before `plView` and won on
document order, so the first implementation borrowed the frame of a window nothing was ever meant to
look at. A view that holds a `PLAYLIST`, `VIDEO`, `EFFECTS`, `LISTBOX` or `EQUALIZERSETTINGS` now
outranks one that holds nothing. `Halo 2` and `T3-Skynet_Media_Player` have the same duplicate.

## What was ruled out

- **It is not `visDrawerFrame.visible`.** That is the skin's own hide mechanism and it works: the
  hosted text and slider widgets do disappear when the drawer shuts. What remained is
  `vis_drawer_1.png`, the drawer's **background**, which *pictures* a button and a slider row. A
  screenshot of it reads exactly like live controls failing to hide.
- **It is not `onEndMove` failing to fire.** `WMP_RENDER_CLICK 'visView@189,327'` shows
  `visDrawerFrame.visible=false` and `visDrawerButton.down=false` in the same transaction.
- **It is not z-order, and `cerulean` is the skin that proves it.** The obvious reading —
  `<effects zIndex="25">` inside `<subview zIndex="15">` should beat `<subview id="visDrawer"
  zIndex="17">`, i.e. WMP's documented "z-order within the view" is flat — is wrong. Cerulean
  authors `<statusText zIndex="2">` inside `<subview zIndex="4">` and the text must draw **over**
  the seek slider beside it, which only per-parent ordering gives. A flat order would also drop
  xsn's own unauthored `visDrawer1..8` (zIndex 0) behind the video. **Do not re-open flattening
  without answering Cerulean first.**
- **It is not "make the surface opaque".** A stopped player draws no visualization, so an opaque
  surface would paint a black rectangle of ours over 17 skins' artwork. What belongs in the hole is
  whatever the skin painted *before* the effects node — here `visMask`'s own `#000000`.
- **Dropping the overlay entirely is not enough either.** The surface is transparent while idle, so
  the drawer stayed visible; and the drawer continues *below* the effects rect, where it must still
  draw. The answer is an occlusion: clear the windowed rect out of the overlay.
- **A render dump can never show any of this.** `WMPRenderer.dump` passes `splitAtEffects: false` on
  purpose, so every PNG is the whole artwork flattened in one pass and the drawer is always in it.
  Three rounds of "still broken" came from reading those PNGs. `WMP_RENDER_APPKIT` +
  `WMP_RENDER_APPKIT_DUMP` hosts the real `NSView` stack and settles it.
- **A plain render sweep does not measure the expression fix.** The sweep renders one transaction
  per view, so a timer-driven regression is invisible to it: base vs change came out **485
  identical, 50 differing, 0 lost, 0 gained** both before and after that change was added. Use
  `WMP_RENDER_SETTLE`.

## How to drive it

`visView` is 379x338. All coordinates below are at its authored size, drawer **open** (which is the
state a fresh profile loads, by the skin's own design).

| What | Where |
|---|---|
| Drawer tab, open (`toggleVisDrawer`) | `visView@189,327` |
| Drawer tab, retracted | `visView@189,277` |
| Colour-phasing pause (`htcpTimerPause`) | `visView@143,281` |
| Timer slider (`htcpAdjust`) | `visView@132,302` |
| Next / previous visualization | `visView@72,48` / `visView@47,48` |

```bash
# the closed state, in the real view stack — the only thing that shows the occlusion
WMP_SKIN="$HOME/Library/Application Support/NullPlayer/WMPSkins/xsn_sports.wmz" \
  WMP_RENDER_CLICK='visView@189,327' WMP_RENDER_APPKIT=1 WMP_RENDER_APPKIT_DUMP=/tmp/wmp/xsn \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus > /tmp/wmp/xsn.txt 2>&1

# the drawer surviving its own view timer
WMP_SKIN="$HOME/Library/Application Support/NullPlayer/WMPSkins/xsn_sports.wmz" \
  WMP_RENDER_SETTLE=2 WMP_RENDER_PROBE=visView \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus > /tmp/wmp/xsn-settle.txt 2>&1
```

`videoView` is the same drawer with a longer throw — retracted at `view.height-239` against an open
`view.height-131`, so it parks 108 px *inside* the effects rect. It is the clearer case for the
occlusion and the reason no clip or cover artwork can explain the bleed.
