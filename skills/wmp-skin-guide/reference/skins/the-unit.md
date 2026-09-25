# `TheUnit.wmz` / `The Unit.wmz`

**Four unrelated defects from one report, three of which no headless probe could see, and all four in
what a skin *lends* rather than in what it draws for itself.** Every view this skin renders for its
own windows was correct throughout; the damage was entirely in NullPlayer's own windows wearing its
frame. Read this before changing `WMPHostedFrameTemplate`'s reclaim or its subtraction rules.

The corpus holds it twice — `TheUnit.wmz` and `The Unit.wmz` are byte-different archives with
identical markup, so every sweep reports its lines twice. Both are the same skin.

## What it is

A dark industrial skin whose every window is the same organic shell: a thin bezel around a screen,
a 7px rail down each side, a 9px caption band, and a **101pt bottom bar** carrying a chrome blob with
the skin's logo in it. The donor `WMPHostedFrameTemplate` ranks first is `videoUnit` (`<WMPVIDEO>`
outranks the player), 364x350 with `minwidth=364 minheight=350`; its `playlist` view is the same
shell and would serve as well.

```bash
unzip -p ~/Library/Application\ Support/NullPlayer/WMPSkins/The\ Unit.wmz unit.wms > /tmp/unit.wms   # cp1252, no BOM
sed -n '/<view id="videoUnit"/,/<\/view>/p' /tmp/unit.wms
WMP_SKIN=~/Library/Application\ Support/NullPlayer/WMPSkins/The\ Unit.wmz WMP_HOSTED_FRAME=550x464 \
  WMP_HOSTED_FRAME_DUMP=/tmp/u swift test --filter testSweepsSkinOrCorpus 2>&1 | grep ^HOSTED-FRAME
# HOSTED-FRAME view=videoUnit ring=17 size=550x464 min=364x350 caption=9 corner=28 left=37 right=7
#   bottom=101 content=37,9 506x354 scaled=no gaps=0.062/0.800/0.847/0.000 whole=no
```

## What it exercises that little else does

Four shapes at once, and each one is a rule the corpus had never tested from this side:

1. **A border that paints on its *inner* edge.** `left_stretch.png` is 37px wide and its outer **30
   are `#ff00ff`**, keyed out for the window's curved silhouette, with the rail in the inner 7. Every
   rule that measures a border *in from the window's edge* reads zero here.
2. **A client hole with no interior fill.** The client subview is `VideoRgn`, a `<WMPVIDEO>` region
   — its contents are ours and are subtracted — so the hole renders **97% transparent** (12,480 of
   179,124 px opaque at 550x464, and that remainder is the settings drawer). Every rule that finds
   the donor's fill by counting the hole's most common opaque colour declines to answer.
3. **A caption band far shallower than its bottom border**: 9 against 101 (5.4 against 60.3 on a
   209pt-tall window). Any top/bottom confusion that is a rounding error elsewhere is 55pt here.
4. **Corner artwork authored as a resize grip**: three subviews whose `backgroundImage` is also
   their child button's `image`, with `onmousedown="view.size('topright')"` — `top2.png`,
   `top_right.png`, `right2.png`.

It also lends a **9px caption**, which with `The_Sentinel_v.1.0`'s 7px is the pair that killed the
`captionHeight >= classicCharHeight` guard: the real case is a band shorter than the lettering asks
for, not one too short to draw in.

## Defects it found — 2026-09-17, one report

Reported as *"theunit skin has broken nullplayer windows similar to past ones"*, then
*"its not fixed. every window has major defects and they vary from window to window"*, then
*"the issue is the right top corner … every window"*.

| # | What the user saw | Cause | Row |
|---|---|---|---|
| 1 | No left bezel on any hosted window; our black ground running out to the window's edge | `reclaimingSideRacks` gave the 37pt left rack to our content and `clearOfTheDonorsOwnRail` did not take it back — its run starts at the window's edge (shape 1) *and* it declines to measure a hole with no fill (shape 2). The rectangular cut (`whole=no`) then erased the rail our content had been handed | W219 |
| 2 | Visualizations showed no frame at all | The ring is derived asynchronously and lands after the view's first layout; `hostedSurfaceStyleDidChange` only repainted, so the GL subview kept the whole window and buried every piece | W220 |
| 3 | Cava, `flow` and PeppyMeter drew their ground 55pt low — the top of each hole transparent, the ground running under the bottom bar | `hostedGroundRect` returned the artwork's **top-left** `contentRect` to three views that fill it in AppKit's **bottom-left** space. Latent until a donor's caption and bottom border differed (shape 3) | W221 |
| 4 | A square notch where the rounded top-right corner should be, the right rail starting 28pt down — **on every window** | Subtraction rule 4 (a subview whose backing image is a control child's image is that control's backing) ate all three grip subviews (shape 4) | W222 |

**"Every window has it" is the signature to read for.** Defects 1, 3 and 4 are properties of the
*frame* and appear identically on every hosted window; defect 2 was one window and was a property of
that window's own layout. Sorting the report that way first would have saved a round.

## What was ruled out

- **The donor choice.** `videoUnit` outranking `playlist` looked like the whole bug — a video
  window's frame on a meter — and is not: both views are the same shell, and `playlist` renders with
  the same rail, the same blob and the same 101pt bottom bar.
- **The 101pt bottom band.** The large empty area under the bar, with the blob at its left, is the
  skin's own shape (`gaps` bottom 0.847), not a piece that failed to draw. Do not "fix" it.
- **A column-wise rail measurement** for defect 1. It fixed this skin and re-refused the racks on
  `Star Wars`, `STALKER`, `WoW` and `Halloween`, which is the 2026-09-15 *"reclaim it, we have no
  content for it"* report coming back. Skipping the bare lead-in is the form that leaves those four
  byte-identical.
- **`PeppyMeterView` filling its own bounds.** It was already filling `hostedGroundRect`; the rect
  itself was wrong (defect 3).

## How to drive it

Launch it with `skills/app-control/scripts/launch.sh "The Unit"`. Its
windows tile down a column and run off the bottom of the screen, so a capture by window id returns
a full-screen image and a `-R` capture picks up whatever is behind; park each window alone before
shooting it:

```bash
PID=$(pgrep -x NullPlayer | head -1); WH=skills/app-control/scripts/winhelper
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) \
  to tell (first window whose name is \"CAVA\") to set position to {60, 60}"
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) \
  to tell (first window whose name is \"CAVA\") to perform action \"AXRaise\""
screencapture -x -R 60,60,530,209 /tmp/cava.png
```

The corner is 80x80 points from the top-right of any hosted window; crop and magnify it rather than
reading it at 1:1 — at window scale the missing curve reads as a slightly square corner.
