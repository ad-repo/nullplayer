# `Back to the Future Trilogy.wmz`

**The case study for W209 — why a borrowed frame is *rendered*, not *assembled*.** This skin is the
one that broke the piece-selecting frame builder, and every symptom it produced was a symptom of the
selection rather than of the skin. Read this before changing `WMPHostedFrameTemplate`.

## What it is

A 2002 Skins Factory skin for WMP 9, `theme.author="TheSkinsFactory.com"`. Eight views; the player
is 490x260 and `plView` — the donor every NullPlayer window borrows from — is authored 515x308 with
`minWidth="560" minHeight="260"`. **Its declared floor is wider than its own authored width**, which
is not a defect in the skin (WMP clamps on resize, not on open) and is the fact the whole case turns
on.

```bash
# the markup is UTF-16; decode before reading it
unzip -p ~/Library/Application\ Support/NullPlayer/WMPSkins/Back\ to\ the\ Future\ Trilogy.wmz bttf.wms \
  | python3 -c "import sys;sys.stdout.write(sys.stdin.buffer.read().decode('utf-16'))" > /tmp/bttf.wms
sed -n '/<view id="plView"/,/<\/view>/p' /tmp/bttf.wms
```

## What it exercises that little else does

`plView` violates **five** assumptions of the piece-selecting assembler at once, which is why it was
the skin that ended it. All five are in the markup above:

1. **Its outer right rail is not a direct child of the view.** The window's right edge is drawn by
   `leftPlDrawer`'s *nested* subviews (`f_drawer_top.png` 158x194, `f_drawer_s.png` 158x12 tiled,
   `f_drawer_bot.png` 158x102). The assembler walked direct children only — deliberately, so a
   nested panel that happens to stretch would not be mistaken for frame — so those pieces were never
   candidates and every hosted window had **no outer right rail**.
2. **It spells transport as an untyped `<buttongroup>`.** Its loop and shuffle pair is
   `<subview backgroundImage="pl_shuff_no.png">` wrapping `<buttonelement onClick="player.settings.setMode('loop',down)">`
   — no `<REPEATBUTTON>`, no `<SHUFFLEBUTTON>` — declared **six nodes before** `f_top_left.png`, so
   first-declaration-wins handed it the top-left corner slot. Reported as yellow glyphs in the
   corner of every NullPlayer window.
3. **It paints every window control twice.** The wrapper subview's `backgroundImage` *is* the
   button's `image` (`pl_shuff_no.png`, `f_close_no.png`, `f_resize.png`). Dropping the control node
   alone leaves the wrapper's copy, and the glyph survives.
4. **It plates a join in its bottom bar.** `f_logo.png` (223x46) covers the seam between
   `f_bot_left.png` (138x86, at `top=view.height-86`) and `f_bot_s.png` (65x93 tiled, at
   `left=138 top=view.height-93`) — a 7px step. Refuse the plate and the step is a black tab. **This
   is the counter-example to rule 3 and it is the whole reason that rule is written the way it is**:
   the logo subview carries `f_logo.png` and wraps a button drawn from `f_logo_no.png`. *Different*
   images, so it is a plate, not a backing. It stays.
5. **It has a declared floor above the size our windows open at.** The flow window is 357x238.

## The reports, and the one that was decisive

All from the reporter driving the app, 2026-09-16/17:

1. *"back to the future skin has broken nullplayer border similar to the ice skin ones we fixed"*
2. *"there is a notch on the bottom and the content does not fit smoothly on the left. the
   border/pane should sit on top of the content in the z order"*
3. *"you are creating this notch. it is not in the art"* / *"the playlist has no notch why are you
   making one here"*
4. *"the left and right are not equal, you are missing the far border"*
5. *"why the playlist window cannot be used as a template for the frame … most other skins can draw
   these nullplayer windows just fine"*

**Report 3 is the one that mattered and it was correct.** It is a *testable* claim — compare the
frame against the skin's own playlist at the skin's own size — and the test is what showed the notch
was manufactured. **Report 5 named the fix.** The playlist has none of these defects because the
playlist is not reassembled; it is simply drawn.

## What the fix was

Inverting the default. The assembler asked *"is this piece frame?"* and answered **no** unless the
piece proved otherwise — so a rail in a drawer, a tile sized by script, and a plate over a join all
fell out, and everything downstream existed to cope: an extent crop, a bare-edge measurement, a
`ringDoesNotClose` refusal, a second "repairing" build, and a decoration pass composited after
measurement so it would not perturb the crop.

The whole-view path asks the opposite question and **subtracts** — see § *Shape* in `../../SKILL.md`
for the four subtractions. None of that downstream machinery has a question to answer any more,
because a view drawn whole cannot come apart.

Corpus, all 185 installed archives at the flow window's 357x238:

```bash
WMP_SKIN=~/Library/Application\ Support/NullPlayer/WMPSkins \
  WMP_HOSTED_FRAME=357x238 WMP_HOSTED_FRAME_SCALE=2 \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus
```

| | assembled (`WMP_HOSTED_FRAME_WHOLE=0`) | drawn whole (default) |
|---|---:|---:|
| rings drawn | 67 | **88** |
| refused `ring-open` | 21 | **0** |
| panels sliced | 40 | 40 |
| refused `panel-unslicable` | 6 | 6 |
| lends nothing | 51 | 51 |

## The notch was **not** caused by the assembler, and that is the finding worth keeping

It survived the whole-view render. It is a **sub-floor layout artifact**, and the sizes are the
proof — same skin, same code, `WMP_HOSTED_FRAME_DUMP` at each:

| size | notch |
|---|---|
| 600x300 | none |
| 560x260 (its declared floor) | none |
| 515x308 (its own authored size) | none |
| **420x260** | **none** |
| 380x238 | ~13x20pt black tab left of the logo |
| 357x238 (the flow window) | same tab |

Height 260 is the boundary and it is exactly `minHeight`. Below it the bottom pieces — placed at
`view.height-86` and `view.height-93` against an `f_top_left.png` that is **215 tall** — no longer
land where the logo plate covers them.

**The assembler's answer was to unclamp**: `WMPHostedFrameTemplate.unclamped` forces the donor
view's `minwidth`/`minheight` to 1 for the frame build, so the skin was laid out at a size its
author never laid it out for, and its pieces fell where they may. The whole-view path builds at the
donor's own floor instead and scales the finished picture down
(`wholeDonorViewObeysFloor`). The scale is non-uniform — 0.64 x 0.92 at 357x238 — so the corners
soften. **That trade was shown to the reporter and accepted**; do not revisit it without doing the
same.

Note what this does **not** license: W207's recorded rejection stands — *growing every hosted window
to the donor's declared floor moves windows the user placed*. The floor is obeyed by the **build**,
never by the window.

## What was ruled out — do not re-try any of these

Each was implemented, swept, and backed out. All but the last were also shipped to the reporter and
reported wrong.

| Approach | Why it failed |
|---|---|
| Grow the client hole to the flood-filled fill's bounding box | A donor whose border shares the content colour gives the flood nothing to stop at — `Alienware_Darkstar` returned the whole 550x464 window as its hole. Guarded against reaching the edge it still overhangs: content ran over the bar and the logo |
| Erase the fill only where it reaches outside the client rect | Leaves a gap the window's backing shows through — a black tab |
| …then fill that gap from the nearest surviving pixel | Paints it with the black *above* it. **This is what created the trapezoid the reporter called "you are making the notch"** |
| …then fill it with the palette background | A coloured patch. Not a bar |
| Loosen the fill match to a colour tolerance | The 5.8% leftover is real bezel art, not an antialias fringe — tolerance 12→72 moved it 0.0577→0.0553 |
| Take the client hole from the erased fill's bounding box rather than the client subview | Borders go lopsided — 43pt left against 16pt right here, because the left bezel dips into the subview and the right does not. Reported as *"the left and right are not equal"* |
| Admit every extra edge-anchored piece in the assembler's first pass | Re-broke six rings that measured clean (`AlienMorph`, `ALXMorph`, `ALXVortex`, `AlienwareTeleport`, `Harry_Potter…`, `Project Gotham Racing 2`) |
| Refuse anything clickable from a corner | Costs 7 of 88 rings — a resize grip and a close box are frame furniture. Moot now: the whole-view path drops controls without needing slots |

## Process lessons this skin taught

1. **Capture the live window, not a probe dump.** Three rounds of fixes measured clean in the
   harness while the app on screen was unchanged — once because an animation tick was erasing the
   chrome (nothing in a dump can show that), once because the probe size (550x464) and the window
   size (357x238) put this skin either side of the `minHeight` threshold.
   ```bash
   osascript -e 'tell application "System Events" to tell process "NullPlayer" \
     to get {position, size} of (first window whose name is "flow")'
   screencapture -x -R <x>,<y>,<w>,<h> /tmp/live.png
   ```
2. **Measure at the window's real size, and at `WMP_HOSTED_FRAME_SCALE=2`.** The harness defaults to
   1x; the screen is 2x, and connectivity and threshold rules do not survive the difference.
3. **"It is not in the art" is a testable claim.** Compare against a size where the frame is not
   scaled, and against the skin's own window, *before* touching the artwork path.
4. **A clean corpus diff is not evidence when the rule changed what "clean" means.** The assembler's
   66 byte-identical rings were the safety net the previous sessions steered by, and the whole-view
   path moves all of them on purpose. Verification here is visual, across a sample, not a byte
   compare.
