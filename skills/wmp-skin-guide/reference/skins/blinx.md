# `Blinx.wmz`

## What it is

A game tie-in (Blinx: The Time Sweeper, Xbox, 2002): a bright orange wedge with a purple bezel round
a grey list, an antenna up the right side with the close × on it, and a yellow spiral in the bottom
bar. Five views — `mainView` 393x285, `plView`/`videoView` 475x332 (`minWidth=475 minHeight=332
resizAble="true"`), `infoView`, `eqView` — one `blinx.js`.

**Its `plView` is the donor NullPlayer borrows for every hosted window**, and the dossier exists for
that: its player views are correct and what it lends is not.

```bash
WMP_SKIN="$HOME/Library/Application Support/NullPlayer/WMPSkins/Blinx.wmz" \
  WMP_HOSTED_FRAME=553x402 swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus 2>&1 | grep '^HOSTED-FRAME'
# HOSTED-FRAME view=plView ring=10 size=553x402 min=475x332 caption=104 corner=40.712
#   left=150.407 right=41.843 bottom=76 content=150.407,104 360.751x222 scaled=yes
#   gaps=0.953/0.968/0.656/0.749 whole=no
```

## What it exercises that little else does

**A ring whose edges are 1-pixel tiled rails, and a donor whose art is authored short of its own
canvas.** The four fillers are `f_left_s.png` 271x1, `f_bot_s.png` 6x18, `f_right_s.png` 19x6 and
`f_top_s.png` 2x190, each `backgroundTiled="true"` with a `stretch` alignment, spanning between four
fixed corner bitmaps (`f_top_left.png` 375x255, `f_bot_left.png` 271x76, `f_top_right.png` 36x250,
`f_bot_right.png` 13x76). **At the donor's authored 475x332 every rail spans one or two points**, so
anything that drops them is invisible; at 553x402 they span 71 and 80 points and are the whole of the
bezel's lower and right sides.

**`gaps=` is ~0.95 at every size, including the size where the frame is correct.** Measured at
475x332 (`gaps=0.952/0.961/0.646/0.696`) and at 480x366 (`0.952/0.964/0.650/0.724`) — this skin's
silhouette is a diagonal wedge that never runs along the window's edges, so the bare-edge metric
cannot separate its good sizes from its bad ones. **Do not reach for `gaps=` on this donor.**

**Its client node is not its list.** `clientNodeID` resolves to `plBoxCover` — a `zIndex="1"` black
backing plate — while the list (`plBox`/`plFrame`, `zIndex="20"`) is painted last, with the rails
between the two at `zIndex="4"`. Any rule that reads "before or after the client" gets the wrong
answer about those rails.

## Defects it found

| Reported | Cause | Row |
|---|---|---|
| *"broken borders, misplaced center data"*, *"the main windows are fine, it is all the other windows"*, and on 2026-09-20 *"the windows open to a size that breaks the border… sometimes they look correct and other times they are split"* | **Open.** The donor's own view renders a whole frame at the same size the borrowed frame comes apart at. Not the scene, not the window size on its own — the extraction. | W234 |

The two halves of that report are one measurement apart:

```bash
# the donor's own view at the size the window is: correct, full orange surround, list inset
WMP_SKIN=…/Blinx.wmz WMP_RENDER_SIZE=553x402 WMP_RENDER_DUMP=/tmp/b/views \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus
# the frame taken from that same view at that same size: split
WMP_SKIN=…/Blinx.wmz WMP_HOSTED_FRAME=553x402 WMP_HOSTED_FRAME_DUMP=/tmp/b/frame \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus
```

## What was ruled out (2026-09-20)

Three fixes were built, measured and reverted. None of them is the answer, and each is cheap to
re-build if new evidence arrives — the exact edits are in the session, the verdicts are here.

- **The shortfall rebuild is not the cause.** `composeRing` re-renders the donor on a canvas grown by
  its shortfall (W207's `Ice` rule) and that *is* a re-layout rather than a bigger picture — at
  480x366 it moves `f_top_right` 58pt out and the frame comes apart. Gating it on the content rect
  not moving (the span repair's own `sameHole` discipline) makes 480x366 coherent **and changes
  nothing at 553x402**, where the frame is just as split. A real defect, not this one.
- **Re-admitting the dropped rails changes nothing on screen.** `derivedFurniture`
  (`WMPHostedFrameTemplate.swift:1331`) drops any piece more than half inside the client hole that
  touches no view edge, and it really does drop two of the four rails — traced, at 553x402:
  `f_left_s.png` at `96,255 271x71` and `f_top_s.png` at `375,60 80x190`. Keeping a piece the donor
  paints *under* its own content restores them, and composing the result with a stand-in content
  rectangle is **pixel-identical** to the current build: our content covers exactly the region those
  rails paint. The rails also carry the list's black baked in, so keeping them paints black in the
  hole — harmless (`whole=no`, the frame is drawn under the content) and invisible.
- **Keeping the donor's canvas instead of cropping to its extent is worse.** The art covers 489x402
  of a 553x402 window, so `composeRing` crops and stretches it 13% horizontally, which is why the
  content rect leaves the donor's `134,104 319x222` and lands at `150,104 360x222`. Skipping the crop
  puts the content back in the donor's own hole and the frame back at 1:1 — and then the content
  overlaps the right column and the bottom bar, because the window is 62pt wider than anything the
  donor paints. Both answers are wrong in opposite directions; **that disagreement is the defect**,
  and the untested third answer is sizing the hosted window to the extent the donor's art covers
  (`HostedWindowBorderLayout` already records why forcing a window to the donor's *floor* was
  rejected — `Ice`'s 585x308 on a 321x145 analyser — which is a different rule from this one).

## How to drive it

Two traps cost a whole session on 2026-09-20, both of which hand back a confident wrong picture:

- **Confirm the skin from the app's own trace, never from `defaults` alone.** State restoration
  rewrote `wmpSkinName` at launch, so a `defaults write` before `kill_build_run.sh` was silently
  discarded and the run landed on whatever the app restored (it landed on `AlienMorph` twice).
  `launch.sh Blinx` turns restoration off and verifies the load; the border line below is still the
  Blinx-specific check. The check is
  `[wmp/border] run donorBorder=104/154/76/43` in the log — Blinx's insets. `AlienMorph`'s are
  `42/30/26/30`, and its frame looks nothing like this one, which is the only reason it was caught.
- **A window near 475x332 looks right whatever the code does.** The defect scales with the distance
  from the donor's authored size, so a capture of a 393x254 window proves nothing. Drive it at
  480x366 or larger, and read the window's size out of `winhelper windows` before reading the
  picture.

```bash
WMP_BORDER_TRACE=1 WMP_FRAME_TRACE=1 WMP_HOSTED_FRAME_DUMP=/tmp/b/live \
  skills/app-control/scripts/launch.sh Blinx --no-play --log /tmp/b/app.log
```

**Restore the persisted interior after any live run.** A resize taken while the donor's border is in
play writes `hostedInteriorSize2.<window>` and it follows that window across skins for ever:
`PeppyMeterWindow` was left at 195x74 this way (it is 308x186), which reads exactly like a window the
fix shrank.

## The parked backlog row (W234)

**Taken out of `tasks/WMP_TASKS.md` on 2026-09-21 so it is not picked up by ranking.** It is not a
low-quality row and it is not closed: it reproduces, the triage is done, and the only direction left
changes how every hosted window is sized, which is a decision rather than a fix. Revive it
deliberately — and re-measure first, because everything below is a reading from one day.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W234 | **Broken borders and content in the wrong rectangle, on every hosted window at once, while the skin's own window is right** | unmeasured across the corpus; **localised on `Blinx` 2026-09-20** — the population is every hosted window under a skin that lends a frame, ~120 of 185 archives (88 rings + 32 panels, W207's measurement) | **The reporter's framing is the finding: "the main windows are fine, it is all the other windows", "broken borders, misplaced center data", and on 2026-09-20 "the windows open to a size that breaks the border… sometimes they look correct and other times they are split".** **Triaged on `Blinx`, and the fork is settled: the donor's own `plView` renders a whole frame at 553x402 while the frame taken from that same view at that same size is split — so this is extraction, not the scene and not the window size alone.** **Three fixes were built, measured and reverted on 2026-09-20; do not re-propose one without reading why.** (1) Gating `composeRing`'s shortfall rebuild on the content rect not moving fixes 480x366 and changes nothing at 553x402. (2) Keeping the bezel rails `derivedFurniture` drops (`WMPHostedFrameTemplate.swift:1331`, traced: `f_left_s` and `f_top_s`) composes pixel-identical — our content covers exactly that region. (3) Skipping the extent crop puts the content back in the donor's hole and then overlaps the right column and bottom bar, because the window is 62pt wider than anything the donor paints. **The two answers are wrong in opposite directions and that disagreement is the defect**; the untested one is sizing the window to the extent the donor's art covers, which is *not* the donor-floor rule `HostedWindowBorderLayout` already rejected. Evidence and the two live-QA traps that cost a session (restoration rewrites `wmpSkinName`; a window near 475x332 looks right whatever the code does): [`skins/blinx.md`](skills/wmp-skin-guide/reference/skins/blinx.md), plus `SKILL.md` § *Triage a hosted-window defect before choosing a seam* and § *Evidence proportional to a hosted-window change*. |
