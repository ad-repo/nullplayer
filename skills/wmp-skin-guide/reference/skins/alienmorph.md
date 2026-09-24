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
| "ALXMorph does nothing — no animation and nothing reacts" | The animation half was `alphaBlendTo` (W38), `backgroundImage` from script (W75) and an unset-preference default (W76), all closed. The starvation half was never real and the 5-hit half was an intro (W242, retired) — the reacting half was the engine dispatching one click twice | W68 (moved to `LOW_QUALITY_TASKS.md` 2026-09-19), **W243** |
| "when i start the video the video player window does not open" + "the video adjustment drawer is open by default" | One handler, two symptoms: `onChangeVidPlayerState()` reads `player.fullScreen`, which was unrecognised on the Player object and therefore **threw** — taking `toggleVidDrawer('0')` with it — and before that, in the interval where `playState` said 3 and `imageSourceWidth` was still 0, its `view.close()` shut the video window inside 200 ms of the app opening it | closed 2026-09-20, `player.fullScreen` + `State.transitioning`; see `reference/object-model.md` § *What a property read answers* rule 8 |
| "in all the alien type skins the numeric display is illegible" | A `<BUTTON>`'s `image` was scaled to its authored frame, blowing one tenth of one digit up ten times | W122 |
| "the animation sometimes does not fully run when first opened — it runs what appears to be half" | The animation clock was per **view**, not per image: the epoch was set on the first animated GIF in the view and `AlienMorph` assigns its shutter a second later from `timerInterval="1000"`, so anything that animated first stole that much off the head | W182 (closed 2026-09-15) |
| "ALXMorph's animation runs so quickly, it is basically the same animation as AlienMorph" | Not the engine — the two archives author the same shutter at 0 cs and 2 cs, and only 0/1 cs was being floored | closed 2026-09-15, `WMPImageStore.asFastAsPossibleCentiseconds` |

## The five hit targets (W242, closed as measured — and what it found instead)

**W242 asked a question its own instrument answered no.** `WMP_RENDER_OCCLUDED=1` had never been
pointed at this family; run over all six archives it reports `recovered=0 lost=0
unreachable-either-way=0` on every view of every skin. Nothing here is occluded.

**The 5 hits are the authored resting state, not a loss.** This player keeps its whole transport —
volume, seek, mute, the vis/eq/pl buttons, the metadata line — inside `mainBackGroup1`, authored
`visible="false"`, and `alienware.js`'s `toggleShutter()` sets it visible off the view's own 800 ms
intro timer. The census measures at t=0, before that. With `WMP_RENDER_SETTLE=3`, `ALXMorph`,
`AlienMorph`, `AlienwareTeleport` and `ALXVortex` all report **14 hits**, and driving the twelve
points decoded from `m_set1/2/3_map.png` hits twelve different elements. `Alienware Invader`'s 0 is
honest too: its `mainView` is a 568-frame PNG sequence at 50 ms — **~28 seconds of intro** — before
either of its groups is revealed, short-circuited only by `player.playState==3`. `Darkstar` authors 4.
**Retired 2026-09-20; do not re-derive a defect from the 5-vs-24 comparison** — it compares a view
behind an intro with one that has none.

**What the live run found in its place is W243**, and it is not this family's defect but the
engine's: a `<NEXTELEMENT>` whose own `onClick` calls `player.controls.next()` was dispatched twice,
so one click on Next advanced two tracks. `SKILL.md` § *Which control a click reaches* carries the
rule and its 73-element reach; this skin is the case it was measured on because its transport is
authored in exactly that shape.

### What W68 left behind

**What survives of W68, restated as the question its own evidence supports.** That row argued from a
starvation number that has since evaporated — `ALXMorph/mainView` quoted at 15 unresolved of 15
nodes, re-measured 2026-09-19 as **3**, all in classes since proven phantom (`<controls>` W111, a
`locSub` string table W232, an anonymous wrapper whose children all resolve W231). Twelve of the
fifteen were string-table text. **Do not re-derive anything from that row's figures**; the full
re-measurement is in `LOW_QUALITY_TASKS.md` § W68.

**The observation underneath it was that the view the skin opens on dispatches 5 hit targets where
its own `eqView` dispatches 24**, with the family live-reported as "ALXMorph does nothing — no
animation and nothing reacts". Both halves are now answered above: the 5 is an intro, and the
"nothing reacts" was W243, found by driving the app rather than by counting hits.

**The lesson the row leaves is about the counting.** A hit tally taken at t=0 is a tally of a scene
the user never sees in a skin that opens behind an animation, and comparing two views' tallies
compares their authoring as much as the engine. **Settle before ranking a `hits` count**, exactly as
`harness.md` says to dump a view before taking a `starved.tsv` row.

**Two halves of W68 are settled and must not be re-opened.** The animation half is **closed**
(W38, W75, W76). The AppKit half is **cleared** — `ALXMorph/mainView` diffs to zero against its own
hosted render (W71), so nothing here is an overlay defect and the whole of it is scene-side.

## What was ruled out

- **Not the routing, and not `controlView`'s event-only `<VIDEO>`.** The obvious reading of "the
  video window does not open" is that `WMPSkinSurfaces` picked the windowless dispatcher over
  `videoView`; it does not — an anonymous, unsized `<VIDEO>` is refused by `matches`, and a probe
  on the live reveal printed `provides=1 ids=videoView open=mainView player=1` followed by
  `openView=videoView`. The window *was* opened every time. What closed it was the skin, one
  transaction later, and only a log of the host commands coming **back out of `videoView`** showed
  that.

- **Not the resize path.** The W143 frame was broken at the view's own authored `389x247`, before any
  resize — which is the whole distinction that identified it, since at the authored size a margin
  alignment is a no-op and only `center` is not. `WMP_RENDER_SIZE=700x450` was checked afterwards and
  holds.
- **Not the hosted `PLAYLIST` overlay, and not AppKit.** The gaps are in the scene's own artwork;
  the missing column headers and `Selected:` / `Total Time:` footer in the same window are a
  different thing (W133, closed 2026-09-24 as unreadable at these widths — see the backlog archive).
- **Not the top tile's 100x170 artwork.** `f_top_tile.png` really is 170 tall against a 76px bar, and
  drawing it at its natural size is correct — everything below the bar is black, over a black
  `plFrame`, and WMP composites the same way. It reads as a defect in a screenshot and is not one.
- **Not `mainView`.** Byte-identical across W143; a non-resizable player authors no centred pieces.
- **Not the view timer re-firing, for W182.** The obvious reading of "runs half" is `introStart()`
  being raised twice and `toggleShutter()` toggling back — the shape of the `Alienware Invader`
  defect in `SKILL.md`. It is not that: `WMP_RENDER_SETTLE` at 1, 3, 5 and 8s all hold
  `m_anim_shutter_open.gif`, so the scripted `view.timerInterval = 0` sticks and the scene is
  correct at every value. The scene was never the defect; the clock was.

**And the floor change is what exposed it, which is the lesson worth keeping.** Slowing `ALXMorph`'s
shutter from 3.9s to 10.1s was reported as making W182 *worse*. It did not: at 4.69s the close
animation was shorter than the view clock's head start almost always, so the loop took its
already-played-out early return and the shutter snapped shut in one frame — a total truncation, which
looks deliberate. At 9.64s the clock lands inside the animation and it visibly starts from the
middle. **A defect that is total can be invisible; making it partial is what surfaced it.**

## The pair that sets the animation floor's boundary

**This family is the corpus's only A/B of one animation authored twice**, and it is why
`WMPImageStore.asFastAsPossibleCentiseconds` is 2 cs rather than a browser's 1. `AlienMorph` and
`AlienwareTeleport` ship `m_anim_shutter_open.gif` as 119 frames with 108 of them authored **0 cs**;
`ALXMorph` and `ALXVortex` ship the same shutter as 138 frames with 134 authored **2 cs**. With the
trigger at 1 cs only the first pair was floored, so one ran 9.8s and the other 3.9s.

Measured 2026-09-15 by parsing every corpus GIF's Graphic Control Extension blocks — 2,170
multi-frame GIFs across 91 archives, which agrees with the 2,166/90 already in `WMPImageStore`, so
the parser is cross-checked. Minimum authored delay: **0 cs 494, 1 cs 278, 2 cs 28, 3 cs 62, 5 cs
859**. Moving the trigger reaches 28 GIFs across 9 archives and leaves the 772 already floored
untouched; 3 cs stays outside it because 62 GIFs author it as a real rate.

**Do not re-derive that boundary from authored delays in aggregate** — that argument produced 0.04
and was rejected by eye. Re-run *this comparison*: the two files draw the same shutter, so whatever
the rule is, they have to come out the same length. Verified live at 9.80s and 10.05s of motion.

## How to drive it

```bash
# The five windows, at their own size and resized, with every drawn node's frame:
WMP_SKIN=~/Library/Application\ Support/NullPlayer/WMPSkins/AlienMorph.wmz \
  WMP_RENDER_PROBE=plView WMP_RENDER_DUMP=/tmp/wmp/alien \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus
WMP_SKIN=…/AlienMorph.wmz WMP_RENDER_SIZE=700x450 WMP_RENDER_DUMP=/tmp/wmp/alien-big …
```

**To measure an animation you must drive the app** — a render dump is a still and `WMP_RENDER_CLOCK`
pins a clock you chose, so neither can see when a GIF was *entered*. The W182 numbers came from
frame-differencing a `screencapture` series over the shutter's own 282x282 region:

```bash
# park the pointer off the window (or on the button group, which is the failing case), then:
defaults write NullPlayer wmpSkinName -string "AlienMorph"
defaults delete NullPlayer wmpSkinViewID
./scripts/kill_build_run.sh --debug -- -uiMode wmp
# poll `winhelper windows` for the 368x426 window, then screencapture -R its rect in a tight loop
# and diff consecutive crops: the span of intervals above the noise floor is the animation's length.
```

Read the **span**, not the frame indices — matching a capture back to a GIF frame is unreliable on
the closing shutter, whose last dozen frames are visually identical, and it reported "frame 91" for
a run that had plainly animated. The span is assumption-free and was what separated a full 9.80s run
from a truncated 1.73s one.

The frame pieces to read in a `PROBE` capture, in `plView` (`389x247`): `f_top_left.png` at `0,0
175x76`, `f_top_right.png` at `214,0`, `plLeftCenter` at `0,77 175x92` and `plRightCenter` at
`214,77` — **a `plLeftCenter` at `0,0` is W143 regressing.** The equaliser's preset label
(`txtEqPreset`, `value="wmpprop:eq.currentPresetTitle"`) paints an empty string headlessly; that is
the harness's stopped host, so read it live before filing it.
