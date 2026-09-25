# `Alienware Invader.wmz`

**W210, W212, W228 and the open-resize defect are all closed (W228 on 2026-09-18).** Nothing here is
open. Read § *W212* and § *W228* before touching the borrowed frame: all four of those rules were
paid for on this archive, and three of them are measurements rather than markup.

Part of the six-archive Alienware/ALX family that already holds two counter-evidence rows (see
[`alienmorph.md`](alienmorph.md) and the `center`-is-not-a-margin row in
[`README.md`](README.md)). This file is about `plView` as a **frame donor**, which is a different
question from anything in those.

## What it is

Eight views (`previewView`, `controlView`, `mainView`, `metaView`, `eqView`, `plView`, `visView`,
`videoView`). `plView` is authored 331x277 with `minWidth="531" minHeight="291"` — a declared floor
well above its own authored size, as in [`back-to-the-future-trilogy.md`](back-to-the-future-trilogy.md).

```bash
unzip -p ~/Library/Application\ Support/NullPlayer/WMPSkins/Alienware\ Invader.wmz awi.wms \
  | python3 -c "import sys;sys.stdout.write(sys.stdin.buffer.read().decode('utf-16'))" > /tmp/awi.wms
sed -n '/<view id="plView"/,/<view id="visView"/p' /tmp/awi.wms
```

## What it exercises that little else does

**A donor whose left border is a furnished column, not a border.** `plView` puts an album-art well,
a search field and the top of a list rack in that margin, as three ordinary decorated subviews at
`left="18"`:

| node | bitmap | size | position |
|---|---|---|---|
| album well + search box + rack top | `pl_top_left2.png` | 116x160 | `left=18 top=32` |
| rack body | `pl_left_tile3.png` | 116x23, tiled | `left=18 top=192`, `verticalAlignment=stretch` |
| rack foot | `pl_bot_left2.png` | 116x28 | `left=18 top=view.height-62`, bottom-aligned |

They are **nodes, not pixels** — an earlier handoff recorded them as "baked into one 190pt corner
bitmap", and that is wrong; `pl_top_left.png` is 99x60 and carries none of it. A node rule *can*
reach them. That correction is the main reason this file exists.

It also states its rails in three pieces per side and sizes the lower ones in its own
`onResize="resizeListBox();onPlResize();"`, which the frame build never runs — the defect that
`stretchedDownNodeIDs` existed for under the old assembler. **The whole-view render does not answer
this for free, and an earlier version of this file said it did.** A view drawn whole cannot come
*apart*, but it can still be drawn *short*: the frame build is a private builder outside the script
runtime, so the tile `onPlResize()` sizes was still one bitmap tall and the borrowed frame carried
the same 20.1% bare run down each side that the skin's own window had before the open-resize fix
(`gaps=0.000/0.201/0.000/0.201`). Closed by the guarded span repair in § *W212*; the unguarded
version of it is the dead end that row recorded.

## W210, closed 2026-09-17 — the rack no longer reaches our windows

The defect was two correct rules disagreeing. At the donor's floor (531x291) the client subview
resolves to `134,34 374x221`, so the three rack nodes at `18..134` are legitimately *outside* the
hole and `ringRender`'s furniture test was right not to fire on them;
`WMPHostedFrameTemplate.reclaimingSideRacks` then judged a 134pt left margin against a 15pt right one
to be a rack and handed that strip to our content; and the frame is painted **over** the content
(W209), so the rack landed on the library's rows.

**The fix the row proposed does not work, and the reason is worth keeping.** Running the furniture
test against the *reclaimed* rect alone removes this rack and takes `Ice`'s right rail with it
(`Vid-righttile.bmp`, `431..468` of the 157pt margin the same rule reclaims): its left gap went
`0.082` → `0.595` and the inner right border vanished from the frame. Both pieces sit in the
reclaimed strip, touch no edge, and are more than half inside the widened hole — position alone
cannot separate them.

**What separates them is paint order**, which is the donor's own answer to the same question: a piece
drawn *before* the client subview is behind the skin's own list — a rail, a bezel, a background — and
is behind ours for the same reason; a piece drawn *after* it is over the skin's content, and over
ours. `Ice` paints its rail at `zIndex=5` under a `zIndex=50` list; this skin paints its racks at
`zIndex=10` over a list with no `zIndex` at all. Read off `scene.commands` (the render order), never
off `zIndex`, which `WMPScene` documents as ordered among siblings only.

Measured at 357x238 scale 2: the corpus sweep over 185 archives moves **one** line
(`LostPlanet whole=no → yes`); the rule reaches 7 archives, of which `Alienware Invader`,
`Batman Begins` and `LostPlanet` change pixels and `livin_it_skate`, `STALKER`, `Star Wars` and `WoW`
are byte-identical — their dropped nodes are AppKit widgets with no paint command. `Ice`, `Star Wars`
and `Halo 2` are untouched, line and frame both.

## The open-resize defect, closed 2026-09-17 — this skin's *own* playlist window

Not a borrowed-frame defect at all, and reported separately: a 58pt band of bare window through both
side rails of `plView` itself.

`plView` is authored 331x277 with `minWidth="531" minHeight="291"`, and states each rail in three
pieces — a top, a centred piece, and a tile whose height only `onPlResize()` ever sets
(`plLeftStretch.height = view.height / 2`). The window opens at the floor, the app's view-open path
raised no `onResize` there, and that tile kept its bitmap's own 51pt. Left column covered `0..173.5`
and `232..291`; bare `173.5..232`.

Proof, before any change: the open path printed `RESIZE plView: 531x291 -> 531x291, handlers=0`,
while a harness pass that *does* resize (`WMP_RENDER_SIZE=560x320`, `handlers=1`) drew both rails
continuous.

**The rule:** a view laid out at a size it was never authored at has already been resized, and its
`onResize` runs before anyone sees it — `WMPMainWindowController.opensResized`, applied on both the
player-view and auxiliary-view open paths. The before-layout is the authored one with the floor
lifted (`unclampedOverrides`), so `resizeEvent`'s existing rule decides the dispatch exactly as it
does on a user drag. Gated on the view declaring an `onResize`, so the 161 of 180 archives that do
not still open on one scene build. Only the overrides are taken from that transaction: the load's own
host commands and timer set are what the open path applies, and a second transaction's empty
`timerRequests` would cancel the timers `onLoad` had just registered.

**Reach: 14 views in 11 archives** — scan the corpus for a view that declares `onResize` and whose
authored `width`/`height` is below its own `minWidth`/`minHeight`:

| archive | view | authored | floor |
|---|---|---|---|
| `ALXMorph`, `ALXVortex` | `infoView` | 389x247 | 389x317 |
| `AlienMorph`, `AlienwareTeleport` | `infoView` | 389x247 | 389x366 |
| `Alienware Invader` | `plView` | 331x277 | 531x291 |
| `Alienware Invader` | `videoView` | 331x432 | 341x412 |
| `Batman Begins` | `plView` | 358x239 | 468x239 |
| `Frostbite` | `plView` | 194x259 | 300x290 |
| `LostPlanet` | `plView` | 376x216 | 565x310 |
| `Project Gotham Racing 2 (1)` | `videoView` | 348x464 | 410x464 |
| `Star Wars` | `plView` | 472x256 | 500x256 |
| `T3-Skynet_Media_Player` | `upgradeView`, `plView`, `infoView` | 279x245 | 414x237 / 461x302 |

`Batman Begins`, `LostPlanet` and `Frostbite` playlists were opened live and are intact.
**The harness cannot express this pass**: its first build already clamps to the floor, so
`WMP_RENDER_SIZE` at the floor prints `handlers=0` and compares a no-op against a no-op. Check it in
the running app, or not at all.

## W212, closed 2026-09-17 — the white blocks and the grey column

Three defects on the borrowed frame, one cause each. All three are visible only on **NullPlayer's
own** windows; the skin's own `plView` was correct throughout, and that asymmetry is the clue each
time.

### The white blocks — a `wmpprop:` read the frame build could not answer

`plView` hangs each side column off a centred piece and states the tile beside it as
`top="wmpprop:plLeftCenter.top"`. Centring computes a coordinate the markup does not carry, so
`WMPInitialLayoutResolver` — which reads the target's *authored* attribute — answered **0**, and
both stretch tiles painted at the top of the window over the corner pieces. The white those bitmaps
carry for the skin's own list to cover then landed in the caption band's right end.

**Why only our windows:** WMP answers that read from the live object model, and the skin's own
window does the same through the script runtime. `WMPHostedFrameTemplate`'s builder is outside the
runtime and had no other source. Fixed in `WMPSceneBuilder.parseDimension`: a `wmpprop:` geometry
read answers from the target's resolved frame, or — when the paint-order walk has not reached it
yet, which is this skin (`zIndex=6` reads `zIndex=10`) — from the coordinate its centring computes.
Pinned by `WMPAlignmentTests`, three cases including the authored-coordinate counter-evidence.

### The grey column — a rail is not a rack

`reclaimingSideRacks` handed all 134pt of the left margin to our content; 99pt of it is an opaque
three-piece rail, and the frame paints over content (W209), so 54pt of every hosted window was laid
out under it. Neither position nor paint order separates the rail from the rack — W210 established
that both sit in the reclaimed strip and this donor paints both after its list.

**What separates them is that the rail is artwork and the dropped rack leaves bare canvas.**
`clearOfTheDonorsOwnRail` measures how far in from each edge the donor paints something that is
neither transparent nor its **interior fill**. Excluding the fill is load-bearing: `f_right_tile` is
96px wide and its inner 73 are opaque `(255,255,255,255)`, so a run measured on alpha alone reads a
96pt right border and takes back the width the donor gives its own content. Two more details the
corpus forced — the run tolerates a gap (this rail carries a one-pixel pure-white highlight 15px in,
which read as fill and answered 13pt for a 99pt rail, so the test is *density* behind the point
rather than an unbroken run), and it ends on the last painted pixel rather than on the slack the
density test allows past it. `borderInsets` now **composes** the frame at the reference size instead
of deriving insets from markup, so the window is grown by the border it will actually wear.

### The bare band — the span repair, reachable and guarded

With the rail at its true 99pt, the 20.1% bare run down each side (the tiles `onPlResize()` sizes,
which the frame build never runs) became a 99pt notch of desktop. The repair pass is now reachable
under the whole-view render, under the three guards that answer this row's own recorded dead end:

- **Furniture is classified on the first pass.** A stretched rack reaches the bottom edge and the
  furniture test exempts edge-touching pieces — that is exactly how the rack came back last time.
- **Only the axis that came out bare is spanned.** `edgeGaps` is `[top, left, bottom, right]`;
  spanning the top tile as well painted its white filler straight over both rails, because the tile
  is drawn after them.
- **The window's content rect may not move.** Stretching a tile down grows the alpha bounding box
  and the hole rides the crop: `KungFuChaos` and `The_Last_Samurai` are both that shape, three edges
  closer to closed and 47pt of interior taken by a border that is not there. Refused.

### What it measured

Corpus at 357x238 over 185 archives: **4 of 167 frame lines move, every one an improvement**, each
checked as a frame dump against its baseline.

| archive | before → after |
|---|---|
| `Alienware` | `gaps=0.000/0.201/0.000/0.201` → `0.000` all four; left inset 27.8 → 66.6 (the rail) |
| `T3-Skynet_Media_Player` | broken caption band and bottom bar close; `whole=no` → `yes` |
| `Frostbite` | bottom gap `0.235` → `0.134` |
| `livin_it_skate` | right inset 33 → 64: content no longer laid out under its opaque green button rail |

`Ice`, `Star Wars`, `Halo 2` and `Back to the Future Trilogy` are untouched. The 553-image render
sweep is **552 identical, 1 differing** — `Scooby-Doo_2/infoView`, the run-to-run one — with zero
`RENDER-DUMP`, `FINDING`, `COMPAT` or `BITMAPS` lines changed, which is the measurement that says
the scene-builder change moves nothing that already had a script runtime. Verified live on
PeppyMeter, Waveform and flow with a track playing, and cross-checked on `Ice` and `anemone`.

**PeppyMeter's black bars are not this row.** The meter template keeps its own aspect and
letterboxes inside whatever hole it is given; it does that identically with no skin loaded.

## W228, closed 2026-09-18 — the same rail, open on one window only

The bare run W212 closed came back on **the library browser and nowhere else**, reported as *"alien
invader media library window draws broken. the other nullplayer windows draw ok"* — a 99pt notch of
desktop down the left of the window and 23pt down the right, 107pt tall, with whatever was behind
the app showing through it.

**Nothing about the frame differed between that window and the nine that were right.** The rails
stop the same 107pt short at every size — the span repair is what closes them, and the gate on that
repair was a *fraction* of the edge:

```
HOSTED-FRAME view=plView ring=18 size=669x640 … gaps=0.000/0.000/0.000/0.000   ← Waveform: repaired
HOSTED-FRAME view=plView ring=18 size=710x810 … gaps=0.000/0.132/0.000/0.132   ← the library: not
```

107pt is **0.231** of a 464pt-tall window and trips `ringEdgeGapLimit`; it is **0.132** of the
library's 810 and does not. The library is the only hosted window that opens taller than
107 / 0.15 = **713pt**, which is why it is the only one that showed it. A fraction is a property of
the window as much as of the ring, and the repair gate needs the property of the ring.

**The gate is now either test** — `edgeCameOutBare`: the run is too large a share of its edge, **or**
longer than `ringEdgeGapPointLimit` = 40pt, measured along its own edge. Forty is picked out of the
same empty middle 0.15 sits in: over the 185 installed archives at 710x810 the rings that close run
**0 to 24.3pt** and the ones with a piece missing measure **49.7** (`Half-Life_2`), **85.2**
(`Combat_Flight_Simulator_3`) and **106.9** (this skin), with nothing between.

| measurement | result |
|---|---|
| corpus at 710x810, before → after | **one** `HOSTED-FRAME` line moves: this skin, `gaps 0.132 → 0.000`. Insets, `content=99,34 588x740`, `whole=` and every other line byte-identical |
| corpus at 550x464 | unchanged. The only line in the band the point limit newly reaches is `Half-Life_2` (0.091, 50pt), and its repair is rejected, so the line reads the same either side |
| this skin at 550/640/760/810/931 tall | `gaps=0.000` at all five; `content` identical to before at each |
| live, library at 746x931 | zero bare pixels on all four edges (`screencapture -o` alpha scan). Before: `y=1288..1501`, left 198px and right 46px fully transparent at 2x |

**The repair's own guards are what make widening the gate cheap**: it is accepted only if it closes
the gap *and* leaves the window's content rect where the first pass put it, so the two skins the
point limit newly reaches attempt a repair and keep their frames. `Tests/NullPlayerAppTests/WMPHostedRingSpanTests.swift`
pins the gate against these numbers.

**What the `gaps=` number cannot tell you, and this row is the worked case.** The fraction printed
on the line is the *frame's* defect divided by the *window's* size, so the same broken rail reads as
five different numbers on five windows and as nothing at all once it is repaired. When a defect
appears on one hosted window and not the others, read the run in **points** before concluding the
window is at fault: `sidePoints = gaps[1] × height`.

## W274, 2026-09-25 — the library chooser against Local Files and Jellyfin

Driven live, reporter-accepted. `plView` fills its chooser in `onLoadPl()` (the `WoW` shape, so a
source switch reloads the view rather than raising `CdromMediaChange`), and it opens from `btnPl`
in `mainView`'s `m_top_map.png` group — `#0033ff`, window point `154,132`. Fill, source-switch
refill, preview, play and search all work on Local Files and on Jellyfin's 1,850 playlists with no
`terminated` line, **except play of any playlist after the first**: the proxy cache in
`object-model.md` § *Pitfalls this surface taught* handed `playSelPlaylist()` the first playlist
ever previewed. Fixed there.

Seen and not fixed, both filed as lower priority: `playSelPlaylist()` ends with
`plListBox1.selectedItem = 0`, and the chooser keeps the played row highlighted rather than moving
to "Now Playing" (W300); and after a relaunch `btnPl` needs two clicks, because `onLoadSkin()`'s
`theme.openView('plView')` opens nothing while the saved `plViewer` says it is open (W299).

## What is already ruled out

| Theory | Why it is wrong |
|---|---|
| The rack is painted into a corner bitmap and no node rule can reach it | False. Three separate subviews, listed above. `pl_top_left.png` is 99x60 and carries none of it |
| The old piece-selecting assembler handled this better | No — it showed the same rack *and* lost the right rail *and* tore the bottom bar. Compare `WMP_HOSTED_FRAME_WHOLE=0` against the default; the whole-view render is strictly better on this skin |
| Its rails needed the script-driven span (`stretchedDownNodeIDs`) | True for the **borrowed frame** and false for the skin's own window, which the open-resize rule above fixed. The span is now applied under the whole-view render, but only with the three guards in § *W212* — the unguarded version re-admits the rack, and that is what made it a dead end the first time |
| The white is a hole in the frame | No. It is opaque `(255,255,255,255)` that a PNG viewer draws identically to transparency, and reading the picture rather than the alpha cost two wrong diagnoses. It was never a hole and never a colour problem either: the tiles carrying it were simply drawn in the wrong place (§ *W212*) |
| The library window has a layout defect of its own (W228) | No. Its frame carried the identical 107pt bare rail every other hosted window did; it is the only one taller than 713pt, which is where that run stops being 15% of the edge. Read a `gaps=` fraction back into points before blaming the window |
| The furniture test in `ringRender` is simply not firing | It is firing correctly. The rack is outside the donor's own hole; the hole is moved *afterwards* |

## Also true of this skin, from elsewhere in the guide

- It is one of the six archives holding the **`center` is not a margin** rule (`README.md`).
- It is one of three holding **`<EFFECTS>` and `<VIDEO>` rank last, never by paint order**
  (`README.md`).
