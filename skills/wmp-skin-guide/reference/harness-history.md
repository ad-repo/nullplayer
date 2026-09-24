# `.wmz` harness history — past corpus measurements

Moved verbatim from `harness.md` on 2026-09-24. Each section is a dated measurement at a named rev and
corpus; the probe flags, scripts and traps they refer to are in `harness.md`. A `§` reference here
without a file names a section of this file or of `harness.md`.

## What the harness measured on 2026-09-07 (14-skin corpus, rev `055063ed`)

Recorded here because it **contradicts the recovery plan's inherited hand measurement**, which came
from the branch's own phase handoff docs. Those docs are unverified narrative — phase 7 asserts a
release capability gate that its own `AppCapabilities.swift` does not implement — so check every
number from them against the code before relying on it. This is census output.

| Claim in the plan | Census |
|---|---|
| 4 of 14 archives load | **10 of 14 load** |
| 7 of 10 rejections are `WMP0025` (text encoding) | **0 encoding rejections.** The decoder already resolves the corpus: utf16LE ×11, windows1252 ×2 |
| 3 of 10 rejections are `WMP0027` (duplicate attribute) | **all 4 rejections are `WMP0027`** — Alpine7618_v09, anemone, Official_Xbox_XP, The Unit, exactly the four skins measured as carrying duplicate attributes |

So the whole of the Tier-1 loading blocker was the lenient-XML-parser work (`W2`), and the decoder
work (`W1`) was not ranked ahead of it. Two further clusters the census surfaced, which the plan had
folded into later phases:

- **`WMP0032`, 7 views across 5 skins** — "View requires positive literal width and height for
  static layout". A view whose size is computed in script renders nothing at all, which is why
  `claw.wmz` and `iconic.wmz` load cleanly and produce **zero** layouts.
- **`WMP0024`, 2 views** — an *empty* resource attribute rejected as "absolute, drive-qualified, or
  invalid", killing the whole view.

Every count above carries the corpus it was measured against. Do not rewrite an old numerator
against a new denominator.

## After Phase 2 (14-skin corpus, rev `733d3631`)

`load ok=14`. The four `WMP0027` rejections are gone; see `reference/loading.md` for what replaced
the parser and what it now tolerates. Re-measured against the **new 14-archive denominator**, so
these are not comparable line-for-line with the numbers above:

| | rev `055063ed` (10 loading) | rev `733d3631` (14 loading) |
|---|---|---|
| archives loaded | 10 | **14** |
| rejections | 4 × `WMP0027` | **0** |
| `WMP0032` blacked-out views | 7 across 5 skins | 9 across 6 skins |
| `WMP0024` killed views | 2 | 3 |
| `WMP0034` duplicate attributes | — (the code did not exist) | 19 across 4 skins |
| render dumps | 18 PNGs | 25 PNGs |

**What the sweep proved about collateral damage.** All 18 pre-existing PNGs are byte-identical. The
only invariant lines that moved are diagnostic *locations*, and they moved because the new parser
points at a tag's opening `<` where libxml2 reported the position the tag ended at — verified by hand
against `corona.wms`, where `svTop` opens on line 42 and its closing `>` is on line 46. Nothing else
in any block changed: no counts, no node ids, no bitmap resolution, no layout shapes.

**Two Class B defects became visible only because the skins now load** — a probe cannot see a defect
in a skin it rejects, and neither can you:

- `Alpine7618_v09/view-2@1x.png` renders its art in the lower ~150 px of a 517×412 view and flat
  `#FF00FF` everywhere else: the transparency key is not applied to the uncovered background (`W8`).
- `Official_Xbox_XP/mainBox@1x.png` has `WMPWidgetViews`' opaque black `VIDEO` placeholder painted
  over the skin's own artwork (`W9`).

Both were found by *looking at the PNGs*. The census reports both skins as clean loads with resolved
bitmaps, which is exactly the blind spot the harness notes warn about: a structural probe says a node
exists, never that it is drawn right.

## After Phase 3 (180-archive corpus, rev `c8a843e4`)

The script runtime became one persistent `JSContext` per skin session. Loading did not change and
was not expected to; what changed is what runs after it. The census's default pass now drives each
view's own `onLoad`, the way the app does — a harness that skipped it was measuring a skin nobody
sees.

| | rev `ada068ff` | rev `c8a843e4` |
|---|---|---|
| archives loaded | 171 of 180 | 171 of 180 |
| views laid out | 482 | 482 |
| paint commands | 9,120 | **9,186** |
| widgets | 1,396 | **1,436** |
| unresolved nodes | 2,393 | **2,352** |
| `expression-error` corpus-wide | every expression in most skins | **1**, plus 8 `invalid-geometry` |
| distinct `UNRECOGNISED` members | (not comparable — measured statically) | **6** |

`compare`: **442 images identical, 40 differing, none lost, none new.** Every difference is script
state now being applied, and they were looked at rather than counted: `Plus! Aquarium/view-2` went
from a **blank page** to the whole skin; `WoW/videoView` gained the logo its `onLoad` sets;
`Grinch/view-2` and `Plus! SlimLine/perfectVSkin` *lost* pixels because their scripts hide a video
pane and a stray close box when nothing is playing, which is what WMP does.

The remaining 228 handler errors are ranked in `WMP_TASKS.md`, and 102 of them are one missing host
object (`mediacenter`). *(W37 closed that object in Phase 6; see* § After W37 *below for the
re-measurement, and note the count here is a Phase 3 number kept as written.)*

---

## After Phase 6 (179-archive corpus, rev `824261d4` + the Phase 6 change)

Phase 6 is where the corpus tooling stops being a description of the corpus and starts ranking work
by itself. Three instruments and one capability landed; every number below is
`scripts/wmp_skin_census.sh /tmp/wmp/census`, measured 2026-09-08 over 179 archives and **607 views**.

**What the instruments found on their first run.**

* **Starvation (W70).** 41 views across 36 skins resolve less than half the nodes they declare;
  79 views across 49 skins have no hit target at all; 65 across 37 draw no command. The worst are
  not the ones anybody had named: `Disney_Mix_Central/mainView` resolves **2 of 25**,
  `Batman Begins/mainView` 2 of 21, `Alienware Invader/mainView` 2 of 20, and
  `Cablemusic/mainview` 35 of 98. ALXMorph — the skin live QA reported as dead — sits at exactly
  0.50 and is one of the *milder* cases. The ranking is in `starved.tsv` every run.
* **AppKit hosting (W71).** 545 of the 607 views were hosted through the real `NSView` stack and
  diffed. **Exactly two paint outside any widget frame** — `Revert.wmz` and `Revert (1).wmz`, both
  releases of the same skin, `vwPL`, 4,000 px at delta 196, in a 250x4 band at `3,256` where the
  playlist overlay's frame (`3,14 250x257`) runs past the 260-tall view's own bottom edge. That is
  the entire W43 class in the corpus's default state, and it is one defect in one skin. The
  reporter's "tons of issues" are therefore, on this evidence, mostly *scene*-side (the starvation
  class above) or driven by something a default-state sweep still cannot reach.
  **Both closed 2026-09-19 as W74 and the corpus now reads `outside=0` everywhere**, re-measured at
  184 archives / 629 views: `layout()` places an overlay at frame ∩ clip ∩ bounds instead of at the
  authored frame. The sweep that proved it is not the one `wmp_render_sweep.sh capture` runs —
  `outside=` is not in `INVARIANT_PATTERN` — so an AppKit-hosting change needs its own capture:
  run `WMP_SKIN=<farm> WMP_RENDER_APPKIT=1 swift test --filter
  WMPRenderDumpTests/testSweepsSkinOrCorpus` in a baseline worktree and in the working tree, and
  diff the `^APPKIT ` lines. **`blit=` is not stable enough to diff that way**: `Scooby-Doo_2`'s
  `infoView` reads 5070, 5042 and 5021 on the same binary depending on what ran before it in the
  sweep, while being byte-stable at 5021 when the skin is run alone. Diff `outside=`, and read
  `blit=` only within one run.
* **Drag (W72).** Every slider in the corpus is now drivable headlessly. See *Proving the drag
  probe* above for the two worked axes.

**What one capability change drained.** `value_onchange`, `OpenState_onchange` and
`PlayState_onchange` are WMP's other spelling for three events the engine already dispatches, and
the corpus writes them by an order of magnitude more than the spellings that worked: 175 of 179
archives, 144 and 139, against 11 and 7. Accepting both spellings in the one matcher every dispatch
site already goes through took measured event demand from **6,823 uses to 4,114** — 2,709 uses, 40%
of everything the corpus asks for in this class, in one change with no new dispatch site. It also
removed a phantom `UNKNOWN member player.settings.volume = value;updatevoltooltip()`, which was a
handler body being read as a member path.

`scripts/wmp_render_sweep.sh compare` across the change: **545 images identical, 0 differing, 0 lost,
0 new**, and 2,070 green tests. The distinct-event vocabulary reads 140 → 142 rather than 140 → 137;
36 blocks were damaged in both captures (W35), so the edges of that vocabulary move between runs and
the *uses* figure is the one to quote.

**What Phase 6 did not touch.** Everything the ranked lists now point at. Draining A/C/D
automatically was the job; the lists are the output, not the fixes.

---

## After the cascade (179-archive corpus, rev `df4a8c75` + the probe fix, 2026-09-08)

The Phase 6 sweep above left one open question — *why do 82% of the corpus's geometry expressions
never reach the live evaluator* — and the answer is that they do. **The 82% was this file's own
instrument.**

Re-run the capture the claim came from:

```bash
WMP_SKIN="$HOME/Library/Application Support/NullPlayer/WMPSkins" WMP_RENDER_EXPR=1 \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus > /tmp/wmp/expr-all.txt 2>&1
```

| | before | after |
|---|---|---|
| `EXPR` rows, 179 archives | 42,015 | **7,569** |
| reached the live evaluator (an order number and a `live=` value) | 7,700 (18%) | **7,569 (100%)** |
| `#-` with `live=-` | 34,314 (82%) | **0** |
| static evaluator `unknown geometry object 'X'` | 10,188 uses / 85 skins | **0** |

**What the old rows were.** Both evaluators are scoped to one `VIEW`; the probe was not. Of the
34,314 rows that reported nothing, **34,300 were another view's expression printed under this view's
name** — every one of them already ordered and evaluated under its own view — and the remaining 14
are one skin whose view node is keyed `view.*` in its own dump and by its authored id everywhere
else. The dominant "failure reason", `unknown geometry object`, was `WMPInitialLayoutResolver`
correctly refusing a reference that leaves the view it was built for: the object was never missing,
the question was addressed to the wrong evaluator. The collision ran the other way too — a duplicate
id across two views credited a sibling's order number to 131 rows that were never evaluated, so the
7,700 was wrong as well as the 34,314.

The handoff's worked case is the whole defect in one line. `Alienware Invader` was reported as
`EXPR mainView/plLeftStretch.top #-: plLeftCenter.top -> UNRESOLVED(unknown geometry object …)`, and
`plLeftStretch` and `plLeftCenter` are both in **`plView`**, where the same expression reads
`EXPR plView/plLeftStretch.top #17: plLeftCenter.top -> 0 live=7`. A node "that exists in the markup
and appears in no `PROBE` output" was a node in a view nobody was probing.

**What the corrected sweep leaves.** Two rows in one skin, and one error:

* `digitaldj.wmz` `DigitalDJ` `view.width` / `view.height` evaluate to the **empty string**:
  `(theme.loadPreference('WD') == '--') ? 640 : theme.loadPreference('WD')`. `loadPreference` returns
  `''` for a key that was never written, so the `'--'` sentinel never matches and the ternary yields
  the empty value rather than the authored default (W76). The view still draws at 640x458 because
  the static grammar answered.
* `Compact.wmz` `myeffect.top` is `ReferenceError: Can't find variable: mediacenter` — W37, since
  closed; that expression now evaluates.

**What it does not touch: the starvation class.** `starved.tsv` is unchanged at **41 starved views
across 36 skins**, and re-measuring it after the fix was the point: expressions are not what starves
a view. The three skins the handoff named were opened and looked at, and none of them is an
expression defect —

| Skin / view | expressions | what the dump shows |
|---|---|---|
| `Cablemusic` / `mainview` | **zero** | 63 unresolved nodes, no geometry expressions at all, no missing bitmaps — and it draws a nearly complete player |
| `ALXMorph` / `mainView` | 4, all live-resolved | draws its whole shell; "does nothing" is interaction and animation, not layout |
| `Alienware Invader` / `mainView` | 6, all live-resolved | genuinely blank, and for its own reason: `toggleShutter()` plays a **568-frame** intro off a 50 ms timer and only at frame 568 sets `mainBack.backgroundImage = "main_back.png"` and `mainBackGroup1.visible = true`. Frame 0 of an intro is what the default-state sweep measures |

That last one turned up W75 — a script assignment to `backgroundImage` never reaches the scene —
**and W75 is now closed.** `WMPSceneBuilder.resolveResource` read the authored attribute only and
consulted `overrides.properties` for nothing, so `mainBack` resolved its 406x380 frame, was handed a
real existing PNG on every tick of a `WMP_RENDER_SETTLE=32` run, and still emitted **zero paint
commands**. Artwork was the one property class the override path skipped.

### What closing it measured

**Reach, from the call trace** (`WMP_SKIN=<skins dir> WMP_CALL_TRACE=1`, tallying
`CALL … <member> write` lines whose member ends in `image`, by skin, over the 179-archive corpus):
**45 skins** write an artwork property from script in the default state — 55 writes, of which
`backgroundImage` is 49, `image` 4 and `downImage` 2. **36 of the 45 write `""`**: that is the
store-thumbnail collapse (`view.width = 0; view.height = 0; view.backgroundImage = "";
theme.currentViewID = …`), not artwork being swapped. **Nine write a real path** — `Alienware
Invader`, `Alienware_Darkstar_WMP11`, `Crimson_Skies`, `Frostbite`, `Scooby-Doo_2`, `STALKER`,
`T3-Skynet_Media_Player`, `The_Last_Samurai`, `tubeframe` — and that is the class the row was
about. A settled run reaches more of them; the default state is what this number is.

**Result, `scripts/wmp_render_sweep.sh compare` over 179 archives / 545 hosted PNGs.** 533
identical, **12 changed, none of them a loss**:

* 10 `mediaSwitcherView`s (`Combat_Flight_Simulator_3`, both `Plus!` skins, both `QuickSilver`
  releases, both `TripleX`, both `WWN`, `xXx_night_vision_redx`) go `1 command` → `0` and draw
  nothing, which is the view obeying its own `backgroundImage = ""` before it redirects. This is why
  the corpus's "draws nothing" tally moves **65 → 75 views / 37 → 45 skins**: a collapse that now
  works reads as a blank view, and the ranking cannot tell the two apart. It is the one number this
  fix makes worse and the reason it is written down here.
* `Scooby-Doo_2/infoView` draws the character its `onLoad` picks instead of the authored one.
* `tubeframe/TubeFrameView` gains a scripted button image (34 → 35 commands).

`Alienware Invader/mainView` itself is unchanged in the default sweep — frame 0 of a 568-frame intro
is still frame 0 — and under `WMP_RENDER_SETTLE=32` it goes from **0 commands and an empty PNG** to
its full 406x380 player artwork.

**The sweep caught a regression that no unit test would have.** The first version resolved the
override with `try`, and `WMPArchive.resolve` *throws* for a path outside the provider rather than
returning `nil`. A skin assigning a `res://wmploc/RT_IMAGE/#2024` it had read back off its own markup
therefore took its whole view down with `WMP0024`: **5 views across 3 skins** — `corona` and
`9SeriesDefault` each lost `vPlayer` *and* `viewTiny`, plus `Compact/compact`. `try?` and the same
warning path as a missing file. An override is runtime data; nothing it carries may reject a view.

---

## After the string table (184-archive corpus, rev `bc1b777f`, 2026-09-18)

**The top of `starved.tsv` was not a list of starved views, and it had never been checked against
its own PNGs.** Taking W68's first instruction literally — take the top row, dump the view, look at
it — the two views ranked 0.90 both draw their whole player:

| ratio | view | what the PNG shows |
|---|---|---|
| 0.90 | `Batman Begins/mainView` | blank at frame 0; **complete** at `WMP_RENDER_SETTLE=160` |
| 0.90 | `Alienware Invader/mainView` | frame 0 of a 568-frame intro (already known, W75) |
| 0.76 | `Constantine/mainView` | its full shield |
| 0.72 | `Disney_Mix_Central/mainView` | its full banner |

Batman is Alienware Invader's shape exactly: `onViewTimer()` walks `intro_f1…154.png` into
`mainBack.backgroundImage` off a 500 ms→50 ms timer and only at frame 154 sets
`mainBackGroup1.visible = true`. `2 nodes, 0 commands, 0 hits` → `40 nodes, 29 commands, 27 hits,
3 widgets` once it has run. **An intro skin at the top of this ranking is the ranking working
correctly and saying nothing** — always settle a `0 commands` row before opening its markup.

**What the numerator was actually counting is a string table.** `WMP_RENDER_UNRESOLVED` on Batman's
19: one `<controls>` (W111) and **seventeen `<TEXT>` nodes that were never boxes** —

```xml
<subview id="locSub">
  <text id="locShowPl"   toolTip="Show Playlist" />
  <text id="timeElapsed" toolTip="Click to show remaining time" />
```

— the Skins Factory house style for string constants, read back by script as `locShowPl.toolTip`.
No `value` to measure and no artwork to fall back on, so every one recorded `unresolved`. That is
**733 of 1,183 unresolved nodes across 87 of the 184 archives**, led by the ALX/Alienware family
(26 each), `Batman Begins` and `Alienware Invader` (25), `Star Wars`, `STALKER`, `LostPlanet` (23).

`WMPSceneBuilder.isStringTableText` now excludes them, and the rule is narrower than "text with no
size" for three reasons each of which is a real population:

* a node the **script** fills resolves when it is filled — `literalString` reads the scene overrides
  before the markup, so asking for the override too is what keeps this from swallowing one;
* a `value` authored as a `wmpprop:`/`jscript:` binding answers nil from `literalString` and is not
  literal text, so the raw attribute is tested as well;
* only `.text` qualifies — `<STATUSTEXT>`, `<CURRENTPOSITIONTEXT>` and `<DURATIONTEXT>` take their
  content from the player, so an unsized one genuinely has nowhere to draw.

**What the census pair said.** Two `wmp_skin_census.sh` runs over 184 archives:

| | before | after |
|---|---:|---:|
| unresolved nodes | 1,181 | **456** |
| of which `text` | 786 | **61** |
| every other tag | — | **not one node moved** |
| `starved(>=50%)` | 14 views / 14 skins | **2 / 2** |
| PNGs | 553 | **553 identical** |

The single differing PNG is `Scooby-Doo_2/infoView`, the corpus's one nondeterministic view. The
invariant files are byte-identical apart from `loadms` timings and that view's blit count, so no
node, command, hit or widget moved anywhere — which is what a tally-only change must look like.

**This is a measurement-only change and has no UI signature.** Nothing to click, nothing to see in
the app; the census pair is the whole verification, and a live pass would be a weaker version of it.

### What the residue is, and where this ranking now starts

The 456 unresolved nodes left, by authored tag, over the 629 views of the 184-archive sweep:

| tag | nodes | ranked as |
|---|---:|---|
| `subview` | 180 | W231 — opened by this change and **closed 2026-09-19**: 171 of 178 author no placement and carry no bitmap, so they are grouping wrappers and not starved views; **zero** have an unresolved parent. W232's sharpening was right — a subview whose every child is a string constant is a string table. The 7 that carry a bitmap are **W240**. See § *After the subview class* |
| `controls` | 104 | W111 |
| `text` | 61 | what the string-table rule correctly leaves: a bound `value`, a `<TEXT>` declared twice, a node authoring one dimension |
| `button` | 49 | unranked |
| `videosettings` | 29 | W111 |
| `slider` 10, `statusText` 7, `automenu` 4, and 12 others | 33 | unranked |

**`starved.tsv` is four rows deep now and bottoms out at 0.000 below them**, and **all four have
been taken as of 2026-09-18; not one of them was a starved view.** Measured at that date:
`Disney_Mix_Central/mainView` 0.60, `Batman Begins/mainView` 0.50, `cyberchannel/playview` 0.50,
`Alienware Invader/mainView` 0.33.

* The two intro skins are explained above: settle them.
* `cyberchannel/playview` is the whole view — `<VIEW id="playview"><PLAYLIST/></VIEW>`, a bare list
  in a view that states no size (cp1252 archive; `iconv -f CP1252`, not UTF-16). WMP's ambient
  `width`/`height` default is *zero or the size of the image*, and there is no image on either node,
  so the view is 0x0 in WMP's arithmetic too and the row is a phantom. The defect it hid was in
  routing, not in the scene (`49f64442`).
* `Disney_Mix_Central/mainView`'s **`0 hits` is frame 0 of a 31-frame intro** — `mainBack` is
  `visible="false"` until `onViewTimer` finishes it, and `WMP_RENDER_SETTLE=6` takes the view from
  `7 nodes, 0 commands, 0 hits` to `39 / 24 / 14` with every control dispatching under
  `WMP_RENDER_CLICK`. **Settle a `0 hits` row before opening its markup, exactly as with a
  `0 commands` one.** Its *real* defect was in the same picture and nothing ranked it: five `<TEXT>`
  string constants drawn stacked at `0,0` over the artwork, closed as W232.

**W232 moved this file's top row the wrong way on purpose, and that is worth reading before ranking
from it again.** The ratio is `unresolved / declared`; removing five string constants from
`Disney_Mix_Central/mainView` left the numerator at 3 and took the denominator to 5, so a view that
got strictly better went 0.300 → **0.600 and to the top**. Corpus starved views 2 → 3, for that
reason and no other. The three nodes it still counts are the string subviews' own **parents**, which
is W231: a container whose every child is a string constant is a string table too.

**`WMP_RENDER_UNRESOLVED` prints the node and its missing dimension and nothing else, and that is
the gap that left the `<TEXT>` class unexamined for two phases.** Print the parent and the authored
geometry attributes before taking W231: the question there is whether an unresolved `<SUBVIEW>` is
the *parent* of nodes already counted, which neither the count nor the ratio can currently say.

---

## After the subview class (185-archive corpus, 2026-09-19, W231)

The probe was extended as the section above prescribes and the class was measured. **It is a
phantom, 171 of 178 — and the 7 it is not are one rule, not seven skins.**

Reproduce with `WMP_SKIN=<corpus> WMP_RENDER_UNRESOLVED=1 swift test --filter
WMPRenderDumpTests/testSweepsSkinOrCorpus`, then split the `UNRESOLVED` lines on the new fields.
The corpus reads **458** unresolved nodes over 185 archives, of which `subview` is **178** (the 456
and 180 in W231 were 184 archives at rev `8935e4c8`).

**The cascade theory is dead, and it was the reason the row was ranked at all.** W231 argued a
`<SUBVIEW>` is a box, so an unresolved one is likelier than a `<controls>` to be a container that
really failed, and a container that fails takes every child with it — worth more than its own count.
Measured in both directions, it takes nothing with it:

| | nodes |
|---|---:|
| whose **parent** is itself unresolved | **0 of 178** |
| that drag any child into the tally | **5** |
| whose children all resolve | 149 |
| with no children at all | 24 |

So the 178 are 178 distinct entries, never a chain, and the ratio does not double-count. The engine
is already why: `WMPSceneBuilder` keeps walking a container it could not size, carrying its known
origin forward (*"a script-sized container can still have a literal origin and independently literal
descendants"*), so the container is recorded unresolved and **costs nothing**.

**What the geometry field says is that they were never boxes**, which is W111's finding reached by a
different route:

| authored | nodes |
|---|---:|
| no placement attribute whatsoever | **131** |
| an origin only (`left`/`top`, no size) | 36 |
| a `width` or `height` | 11 |
| — of which a **bitmap** to take a size from | **7** |

131 of 178 author nothing and 171 of 178 carry no image, so WMP's ambient default — zero *or the
size of the image* — gives them zero too, exactly as it does `cyberchannel/playview`. A grouping
wrapper the skin never meant to size is not a starved view, and counting it as one is the same
misclassification the string table was. **Named/anonymous does not separate anything**: 128 named,
50 anonymous, and both distribute the same way.

### The residue is a size fallback, and it was one node — W240, closed 2026-09-20

**Everything between the heading and here was re-measured when the row was taken, and the numbers
below replace the ones that ranked it.** The section as first written said seven image-bearing nodes
inside a wider class of *33 of 458*; the row was then re-counted on 2026-09-20 over the 185 installed
archives, against a pre-W241 baseline (`72a6bee2`) built in a worktree, and both numbers were wrong
in ways worth keeping on the page.

Reproduce with `WMP_SKIN=<corpus> WMP_RENDER_UNRESOLVED=1 swift test --filter
WMPRenderDumpTests/testSweepsSkinOrCorpus`, then classify the `bg=` field.

| | pre-W241 (`72a6bee2`) | after W241 (`1f092489`) |
|---|---:|---:|
| `UNRESOLVED` lines | **458** | **446** |
| — `bg=` names a bitmap | 18 lines / 17 nodes / 13 archives | **17 lines / 16 nodes / 12 archives** |
| — `bg=` authored **empty** | 15 | **5** |
| — no `bg=` at all | 425 | 424 |

The 458 reproduces this section's original figure exactly, so the instrument and the corpus agree
with the archive across a month.

**`33 of 458` was a miscount, not a ceiling, and the arithmetic says how.** `18 + 15 = 33`: the
original tally read the field with a pattern like `bg=(\S+)`, and a node authoring
`backgroundImage=""` prints `bg= kids=none`, so the pattern captured `kids=none` and counted it as a
bitmap. W241's own class was therefore counted inside the bitmap class — which is also exactly why
the number *looked* like a pre-W241 ceiling that W241 would lower. It lowered it by one node.
**The general rule is that a probe field which can be empty must be parsed to its delimiter**, and a
count that moves when a neighbouring row closes is a count to re-derive rather than annotate.

**Naming a bitmap is not having one.** Of the 16, only 3 name a bitmap that resolves —
`WMP_RENDER_BITMAPS=1` says so: 5 `QualityIcon` nodes (`9SeriesDefault` ×2, `corona` ×2, `Compact`)
name `res://wmploc/RT_IMAGE/…`, a wmploc.dll resource nothing here can ever resolve, and 8 name a
skin-local file that is **absent from its own archive** — `nprlogo.gif`, `pl_resizer.png` (both
QuickSilver releases, two views each), `corner_pieces.bmp`, `shim.bmp`, `presets.bmp` — verified
against each archive's own entry list rather than inferred from a resolver miss. Those 13 have no
size available to WMP either, so they are phantoms of the kind the section above cleared. **`Radio`
left the row that way**, and with it the tie to W123 that had been holding both.

**And having one is not keeping it.** Two of the surviving three are `Age_of_Mythology_MP7` and
`_MPXP`'s `shutterSub`, and `aom.js:188` does `shutterSub.backgroundImage = ""` inside
`initShutter()` — so at measure time the skin has deliberately cleared its own artwork and there is
nothing to take a size from. Its sibling `shutterTrigger`, same origin and same file, resolves to
198x173 through the intrinsic-size fallback that already existed, which is the proof both that the
fallback works and that the row's premise — *"the image's size we refuse to take"* — was wrong.
**Read the effective resource, not the markup: the `bg=` field prints what the node authored, and a
script override is consulted ahead of it.**

**So the whole corpus was `XBOX`'s `xLogo`, and its cause was statedness rather than the fallback.**
`xLogo` authors `width="jsa:centerBox.width"` where the `<video>` two lines above it in the same
`centerBox` authors `jscript:centerBox.width` — `jsa:` is **6 uses / 3 archives**, all the Xbox
family, all this one node, never in script text (decoder-faithful scan, encodings 158 UTF-16-BOM /
146 cp1252 / 89 UTF-8 / 9 UTF-8-BOM over 402 files, `Need_for_Speed_Underground` and
`SplinterCellWMPSkin` unreadable as always). WMP cannot parse it either — so this is **not** a
dialect to implement, and matching the typo would be less faithful, not more, exactly as with
`scrollingAmmount`. What WMP *does* do is fall back to the ambient default, and the bitmap is there.
The intrinsic-size gate is `statedAttribute(named:) == nil`, and `jsa:…` **is** stated, so the typo
closed the same gate an empty value closed before W241.

**The fix is W241's rule one step out: a geometry value the grammar rejects outright states
nothing.** `WMPInitialLayoutResolver.Resolution.unresolved` carries `interpretable:`, the parser's
own failures come back `false`, and dependency failures — unknown object, cycle, depth, a reference
whose target failed — stay `true`, because a script may still satisfy those and stamping a bitmap
over one is the `corona`/`svVideo` regression the builder's intrinsic-size comment warns about.
**Extents only.** The first cut applied it to `left`/`top` as well and
`WMPGeometryTests.testInitialLayoutExpressionsResolveReferencesAliasesForwardReadsAndRejectCode`
caught it: `left="JScript:danger();"` silently became 0. An origin has no content-derived default,
so an unreadable one stays a rejection — which is the engine's refusal to evaluate code in a
geometry slot, and is not something to trade for a corpus of one.

Corpus sweep either side: **one changed invariant line** — `XBOX/videoBox` 28→29 nodes, 26→27
commands, 2 unresolved→1 — and two removed `UNRESOLVED` lines, both `xLogo`. `x_logo.jpg` now draws
at 167x153 centred at 116,81 where `videoBox@1x.png` was an empty black `centerBox`.
`WMPUnreadableGeometryValueTests` holds it down, 3 of its 5 cases failing at `1f092489`.

**Two process lessons this row cost, both cheap to reuse.** A sweep through
`scripts/wmp_render_sweep.sh` reported **48 of 184 archives damaged by interleaved writes**, which
puts a skin into `compare`'s *not compared* list — `XBOX` among them, so the one line this change
moves would have been dropped from the diff. The direct `swift test` invocation above dumps no PNGs,
printed no damage, and is the right instrument for an invariants diff. **Those 48 were false
positives, were ranked as W245, and it closed on 2026-09-20**: the detector compared a block's
`views=` against its `RENDER-DUMP ` line count, and a 0x0 canvas printed two of those lines — the
dump and then a `FAILED [WMP0035]` when the PNG write refused the empty canvas. 76 views
corpus-wide, 48 archives, and the same set on every run, which is the tell: interleaving is not
deterministic. Nothing was actually being lost — the single `UNRESOLVED` line that separates a dump
sweep (445) from a direct run (446) is `Darkling.wmz`, the sole entry in
`wmp_corpus_exclusions.txt`, which the sweep farms out and the direct run does not. And the pre-W241 baseline had to be built in a worktree —
`git worktree add` plus symlinks for `Frameworks/` **and** for the frameworks and dylibs under
`.build/arm64-apple-macosx/debug/`, without which the test bundle builds and then fails to `dlopen`
VLCKit.

**W231 itself was a measurement-only change with no UI signature.** The probe is emitted only under
its own flag, so no sweep output, invariant or PNG moved for it; `swift test` was 2,454 passing and
the corpus capture was the verification. W240, above, is the change that followed it and does move a
pixel.

### What was under the phantoms, once they were cleared

**The same sweep answers a question two phases of `starved.tsv` work never reached: what does the
ranking say after its documented phantoms?** The top three are all explained —
`Disney_Mix_Central/mainView` 0.600 (string-table parents, W231/W232), `cyberchannel/playview` 0.500
(a bare `<PLAYLIST>` in a view with no size, 0x0 in WMP's arithmetic too), `Batman Begins/mainView`
0.500 (frame 0 of a 154-frame intro). **Immediately below them are two views nobody has ever
opened**, and neither is a phantom:

| ratio | view | what `WMP_RENDER_UNRESOLVED` says |
|---|---|---|
| 0.381 | `Revert/vwPL`, `Revert (1)/vwPL` | seven anonymous `<BUTTON>` nodes, each alone in its own `<SUBVIEW>`, authoring `horizontalAlignment="stretch" verticalAlignment="stretch"` and no size |
| 0.316 | `Beck/view-2` | **ten `<slider>` EQ bands, `eq1`…`eq10`, each authoring `height=""`** — an empty value, not a missing attribute — plus a `<text>` with `width=""` and a `statusText` |

These are controls a user reaches for, which is what separates them from everything else in the
residue. **The ranking was working; nobody had read past row three.** Ranked as W241, together with
the two empty-value cases W240 split off as malformed authoring (`STALKER`'s `vidBack`, `WWC`'s
`introAnim`).

**`<controls>` appears nowhere in that tail**, which is what retired W111: its only stated
justification was that it distorts this ranking, and it does not distort the part of it that ranks
anything. See `LOW_QUALITY_TASKS.md`.

### The empty-value class: an empty attribute is not an attribute (W241, closed 2026-09-20)

An attribute authored with an **empty value** was dropped, and the nodes it cost were controls
rather than wrappers. Measured 2026-09-19 over 185 archives with the W231-extended
`WMP_RENDER_UNRESOLVED`: **21 nodes across 4 archives** — `Beck` 11 (the ten `eq1`…`eq10` bands plus
a `<text width="">`), `Revert` and `Revert (1)` 8 each (one shared node plus the seven `vwPL`
buttons), `STALKER` 1 (`vidBack`, an empty `backgroundImage`), `WWC` 1 (`introAnim`, an empty
`top`).

**The corpus-wide count the row demanded first is 970 uses across 135 of the 182 measured
archives**, and it is the number that scoped the fix. Taken 2026-09-20 by the decoder-faithful scan
in § *Counting a tag across the corpus*, reconciled against `wmp_markup_census.sh`'s flat files —
both sides 970/135 exactly. The leaders are `tooltip` 299 / 85 skins, `backgroundImage` 101 / 46,
`value` 101 / 22, `upToolTip` 54 / 13, `clippingColor` and `clippingImage` 38 / 3 each,
`transparencyColor` 37 / 5, `height` **36 / 3**, `fontStyle` 27 / 6.

**Read that distribution before touching anything: 970 is the denominator, not the blast radius.**
Almost all of it is authored absence that already behaved correctly. `tooltip=""` is a tooltip the
skin declined to write; `value=""` is a readout that starts blank. The *resource* half was already
right too and needed no change — `WMPArchive.resolve` returns nil for an empty path and
`resolveResource` falls through to the next name, so `backgroundImage=""` does not shadow the
`foregroundImage` behind it. That is why the fix is geometry-only.

**Where it actually broke: statedness, not parsing.** Every "did the skin state this dimension?"
test in `WMPSceneBuilder` is `attribute(named:) == nil`, so a *present-but-empty* `height` closed the
intrinsic-size gate that an *absent* `height` opens. The value parsed fine and then **counted as a
statement**, the node resolved no size, and it was never painted. The seam is
`WMPNode.statedAttribute(named:)` — the attribute only if a value was actually stated — routed
through the geometry gates and `WMPInitialLayoutResolver`, and through nothing else. Strings,
handlers and colours are deliberately untouched.

**It was never a parse-level coercion of `""` to zero**, and the reason is worth keeping: a
zero-height slider is exactly as invisible as an unresolved one, so that fix would have closed the
row and changed no pixel. The two guards the tests hold are the same statement from both sides — an
authored `height="0"` **is** a statement and still outranks the artwork (`corona`'s compact view
collapses a pane deliberately), and `height="abc"` is still a finding rather than an absence.

**What moved, over the full 184-archive sweep:** 10 changed invariant lines of 4,069; **551 images
identical, 2 differing, none lost, none new**. `Beck/view-2` 26→37 nodes, 25→46 commands, 20→31
hits, 4→15 widgets, **12 unresolved → 1**. `WWC/mainView` 3→2 unresolved. `Revert`/`Revert (1)` did
not move, exactly as predicted — their seven buttons author no size *at all* and are a different
rule. `STALKER`'s `vidBack` did not move either; it is the W240 split-off.

**`Beck`'s PNG is byte-identical across the fix, and that is not a failed fix — it is the limit of
the dump.** The ten bands are `<SLIDER>`s, so they became **AppKit-hosted widgets the scene image
does not contain**, and `WMP_RENDER_APPKIT` reports `hosted=0/15` because the headless host paints
no widget at all. The backlog row's own instruction — "a correct fix is unmistakable in the PNG" —
was wrong about which instrument could see it. **Read `WMP_RENDER_PROBE`'s `WIDGET` lines for a
control that is a widget, and then run the app**; the bands land at 10x134 on the authored 22 px
pitch, and the equalizer tray goes from ten empty slots to ten working sliders on screen. Reaching
it takes a click: Beck's tray opens on the `eqb.gif` button at `view-2@27,157`, which widens the
window to 636x304.

The shape is the same one W240 split off as malformed authoring, which is why the two were ranked
together: W240 is the node that has a size available and refuses it, this was the node whose size was
authored as nothing at all. **W240 is still open** and this change does not touch it.

---

## After the starvation classes (179-archive corpus, 2026-09-09)

`starved.tsv` had ranked views for two phases and nothing had been taken off the top of it, because
the number it ranks on names no node. `WMP_RENDER_UNRESOLVED` names them, and the first corpus-wide
run said the ranking was not a list of skins at all — **83% of the corpus's 2,380 unresolved nodes
were three rules**:

| what the tag was | nodes | skins | why it resolved nothing |
|---|---:|---:|---|
| `<TEXT>` | 1,441 | 127 | no intrinsic size; 1,058 were missing width *and* height |
| `<PLAYELEMENT>` / `<STOPELEMENT>` / `<NEXTELEMENT>` / `<PREVELEMENT>` / `<PAUSEELEMENT>` / `<REWELEMENT>` / `<FFWDELEMENT>` | 494 | ~90 | laid out as controls; they are colour regions of a `BUTTONGROUP`'s mapping image |
| `<BUTTONGROUP>` | 31 | 16 | no intrinsic size; the group's normal state is usually the window's own artwork, so it authors no `image` and no geometry |

**The reporter's skin was one skin with all three, plus two more.** `Cablemusic` — "most buttons
don't work, there is no track display" — is `35 nodes, 42 commands, 20 hits, 63 unresolved` before
and `89 / 87 / 66 / 8` after. The remaining 8 are the eight `<TEXT>` nodes it declares **twice**; the
second declaration wins the id and the first is never written, which is WMP's own outcome and not a
defect. The two beyond the table:

* **`<PLAYBUTTON>`, `<NEXTBUTTON>`, `<PREVBUTTON>`, `<STOPBUTTON>`, `<MUTEBUTTON>`, `<REPEATBUTTON>`
  and `<PAUSEELEMENT>` were not element kinds at all.** WMP spells every transport control twice and
  only one half of each pair was in the table. Measured with `scripts/wmp_markup_census.sh`:
  `PAUSEELEMENT` 80 uses / 69 skins, `PLAYBUTTON` 50 / 45, `PREVBUTTON` 50 / 45, `NEXTBUTTON` 49 /
  44, `STOPBUTTON` 48 / 42, `MUTEBUTTON` 10 / 9, `REPEATBUTTON` 5 / 4. An unknown kind still paints
  its `image`, so the button **drew and did nothing**, and `WMP_RENDER_CLICK` on `Cablemusic`'s play
  button returned `hit=ffw` — the pointer fell through to the neighbour whose frame overlapped it.
  That is what "the wrong button responds" looks like from the other side of § *"The wrong button
  responds" is two questions*.
* **An origin the markup never stated could not be written by script.** `left`/`top` default to 0
  when unauthored, and the check was `attribute == nil ? 0 : resolve` — short-circuiting *before*
  the scene overrides were consulted. Size never had it. So a handler that positions an element
  from nothing moved it nowhere: `Cablemusic`'s two drawers are seventeen station rows each, laid
  out entirely by `InitPrograms()` writing `pr<N>.top`, and all thirty-four drew on top of one
  another in the corner of the drawer — the right width, in the wrong place.

**What the sweep said.** `scripts/wmp_render_sweep.sh compare` over 179 archives / 545 PNGs: **422
identical, 123 differing, none lost, none new**, and exactly one image lost any coverage (2 px on
`SplinterCellWMPSkin/videoView`). Summed over every view: nodes 11,284 → **11,973**, paint commands
9,459 → **10,070**, hit targets 3,996 → **4,249**, widgets 1,650 → **2,259**, and unresolved nodes
2,210 → **1,067**. 268 views improved and **one** decreased — `LostPlanet/infoView`, 5 hits → 1, and
that one is the origin fix working: its four gallery thumbnails are `moveTo`'d off-stage by
`onLoadInfo()` and used to be pinned at the gallery's corner as four invisible stacked hit targets.
`GEOM` says thumb1 now resolves to `-143,43`, outside its parent's clip.

**Two rules came back narrower after the sweep disagreed with them**, and neither was findable any
other way:

* **`mappingColor` alone does not mean "a region, not a box".** The first version exempted any node
  declaring one from layout. `polygon` authors `<subview id="ToggleButton" left="75" top="27"
  width="18" height="18" mappingImage="Toggle_MAP.bmp" mappingColor="#FF0000">` — a mask on the
  subview itself — and lost its geometry, which dropped the panel it draws and moved the
  `returnButton` inside it to the window's corner. The test is the attribute **under a
  `BUTTONGROUP`**, which is the same pair the group's own `mappingTargets` are built from.
* **Two children can declare the same `mappingColor`, and `Dictionary(uniqueKeysWithValues:)` traps
  the process.** `Cablemusic` authors `bnpb6` and `bnpb7` both as `#00C0FF`. Nothing had ever
  reached that code for this skin because its groups resolved no frame at all, so sizing the group
  from its mapping image turned a dead control into a **crash on load**. First in document order
  wins, as WMP does. Expect this shape whenever a fix makes previously-dead code reachable.

### The second report on the same skin, and what only the running app could say

The first round left `Cablemusic` drawing a whole player and four defects still on the screen:
"when you click the compact button there is a large overlay, the track information does not appear
and the track text is shifted up too high in the track window, the playlist is always showing."
**Two of the four were reachable headlessly and two were not**, and the two that were not are why a
live script diagnostic mattered at the time (the `INPUT` trace that carried it was removed on
2026-09-11; see above).

* **Headless, one command each.** `WMP_RENDER_CLICK='mainview@384,390;579,390'` opens the playlist
  drawer and closes it again: the second click printed `changed=[subPlayList.left=178]` and
  `61 widgets[… playlist×1 …]` — the drawer shut and the playlist stayed. `moveTo` applied its
  endpoint inside the call, so `HidePlist()`'s `if (subPlayList.left == 373)` read the destination
  instead of the origin (W112). The label geometry was the same shape: `WMP_RENDER_PROBE` said
  `frame=50,350 55x12` against a `fontSize` the script had set to 7, which is a 10 pt box (W114).
* **Live, and invisible to every probe here.** The readouts were empty with a track playing and
  nothing in the corpus sweep could say why, because the sweep has no snapshot. `INPUT script-diag`
  named it in one launch — `unimplemented player.network.bitrate (network member)` — and then, with
  that closed, named the next one behind it: `unimplemented player.currentmedia.sourceurl`. **Both
  are in `handlePlayStateChange`'s path *before* the function that fills every readout**, so one
  missing member cost the whole block. This is § *After W37*'s rule arriving twice in one session:
  close the biggest row and re-measure, because the row behind it was never visible.
* **Live, and the fix moved twice.** Compact mode resized the *scene* on the first attempt and left
  the window at 593x600 whenever a track was playing — `status_onchange` lands five times a second
  and cancels the click's task after its render (W88), so the present that carried the resize never
  happened while the overrides that carried the compact layout already had. The size had to move
  into the uncancellable half of the transaction, beside the host commands (W113). **A live QA pass
  with playback running is a different test from one without**, and this is the second defect in
  this engine that only appears in the first.

**What the sweep said, in three rounds.** Every engine change here went through
`scripts/wmp_render_sweep.sh`, and it rejected two versions of one rule before accepting the third:

| round | change | images |
|---|---|---|
| 1 | scripted view size + tween deferral | 443 identical, 92 differing, **10 lost** |
| 2 | …with `ownAuthoredSize` kept at the markup's | 500 identical, 35 differing, 0 lost |
| 3 | override-aware `fontSize` + the ascent floor | 393 identical, 142 differing, 0 lost, **no view row changed at all** |
| 4 | `sourceURL` + `bitRate` | 532 identical, **3 differing**, 0 lost |

Round 1's ten losses were `LostPlanet/infoView` shattering and the `mediaSwitcherView` class; round
3 changed 142 images and not one node, command, hit or widget count, which is what a pure text-metrics
change should look like. Round 4's three are skins whose readouts came back: `Thomas/main` draws
`0 kbps` and `0%` where a dead handler used to leave blanks. Corpus totals across the whole session:
nodes 11,284 → **11,972**, commands 9,459 → **10,049**, hits 3,996 → **4,248**, widgets 1,650 →
**2,259**, unresolved 2,210 → **1,067**.

**And a fifth, on a follow-up report, that no sweep here can see.** "When you mouse over the compact
button there is a huge overlay" is a `BUTTONGROUP` whose `hoverImage` is the whole 593x600 player
and which authors no normal `image`, so the sheet was painted unmasked over the window (W116).
`scripts/wmp_render_sweep.sh compare` across that fix is **535 identical, 0 differing** — a
default-state capture never enters a hover or a down state, which is W73 stated as a number.
`WMP_RENDER_HOVER` and `WMP_RENDER_CLICK` are the instruments for it, and a live hover is what found
it. **Read a byte-identical sweep across an interaction-state change as "unmeasured", never as
"unchanged".**

**What it does not close.** `<controls>` (103 nodes / 67 skins) and `<VIDEOSETTINGS>` (28 / 24) are
still counted as unresolved and are objects rather than controls — phantom rows in `starved.tsv`
that cost no pixels. `currentPositionText`, `durationText`, `statusText` and `automenu` are unknown
tags in the same shape. See `WMP_TASKS.md`.

---

## After W37 (179-archive corpus, 2026-09-08)

One host object, `mediacenter`, and the reason it is worth its own section is what closing the
biggest row on the page does to the rest of the page.

**Method, and the part that was most of the work.** The tree already carried unrelated uncommitted
changes, so a baseline against `HEAD` would have measured those too. The baseline is a
`git worktree` holding **the same working tree with only this change reverted** — the four files
that were clean before restored from `HEAD`, and the one hunk in a file that was already dirty
removed by hand. A fresh worktree also needs `Frameworks/` and the framework bundles staged into
`.build/<triple>/debug/` before `swift test` can even load the test bundle; without them the capture
writes an empty `raw.txt` that diffs as "every skin regressed".

| | baseline | with `mediacenter` |
|---|---|---|
| `Can't find variable: mediacenter` | **159**, across **110 skins** | **0** |
| runtime member errors, all causes | 252 | **127** |
| skins carrying a dead handler | 119 | **70** |
| distinct causes | 41 | **55** |
| views dumped / failed | 669 / 62 | 669 / 62 (unchanged) |
| images | — | **490 identical, 55 differing, 0 lost, 0 new** |

**Distinct causes went up, and that is the instrument working.** Rule 2 in
`reference/object-model.md` — "unimplemented is a queue, not a set" — is visible here as a number for
the first time: handlers that used to die on their first `mediacenter` line now run to their
*second* missing member. `alphaBlendTo` went 18 → 26 skins and is now the largest row in the backlog;
`player.dvd`, `eq.bypass` and three cross-view element names are new. **Never read a fall in one row
as progress without re-measuring the rest of the table in the same capture.**

**The 55 differing images were looked at, not counted**, and they split three ways:

* **Gained.** `WALL-E/mainView` went from a blank frame to its **entire artwork**; a dozen
  `videoView`s gained content their `OnLoad` sets.
* **Lost, and correct.** `Gorillaz/noodle` ends its `OnLoad` with
  `screen.visible = video.visible = effects.visible = false`, and the Rave-MP and
  Back-to-the-Future drawers close because nothing is playing. A script that finally runs is a
  script that finally hides things, which is what WMP does. This is the same finding as Phase 3's
  `Grinch/view-2`, and it means **net ink is not a quality signal**: this change is −15,152 px
  overall and every one of those losses is right.
* **Lost, and a different row's fault.** `Plus! Professional/videoView` lost its right drawer tab,
  and the cause is W76: `loadVidPrefs` tests `theme.loadPreference('vidRightDrawer') != '--'`, an
  unset key answers `''`, and the inverted sentinel closes the drawer. W37 closing is what turned
  W76 from two expressions in one skin into drawn pixels. **When a sweep loses pixels, find the
  statement that hid them before filing the change that ran it.**

A useful cheap instrument for the third case: count non-transparent pixels per differing PNG and
sort. It separates "gained a background" from "hid a pane" in one pass and points at the handful
worth opening.

## The transport audit (180-archive corpus, 2026-09-14)

Run from *"button test these skins"*, and the baseline for any later claim about the transport.
It is the § *Auditing one authored control across the whole corpus* route applied to play/pause,
and its headline number is a **negative** one worth keeping: the transport is healthy, and the
defect the same session found (W170) is invisible to every line of it.

**Method.** `WMP_RENDER_PROBE=all` over the corpus for resolved frames; then, per skin, decode each
`<PLAYELEMENT>`/`<PAUSEELEMENT>`/`<PLAYBUTTON>`/`<PAUSEBUTTON>` (and the `player.controls.play()` /
`pause()` button elements) to a click point — a drawn node's frame centre, or the **median pixel**
of a `<BUTTONELEMENT>`'s `mappingColor` inside its group's mapping bitmap, plus the group's probed
origin. Drive them with `WMP_RENDER_CLICK`, once against `WMP_RENDER_HOST=playing` (pause must
answer) and once against `state=paused` (play must answer). 284 points across 149 skins per state.

| | playing host | paused host |
|---|---|---|
| point answers `pause` | 139 | 46 |
| point answers `play` | 54 | 138 |
| the *other* transport answers (overlapping controls) | 79 | 89 |
| `MISS` | 10 | 9 |

**Every `MISS` was explained and none was an engine defect.** Play disabled while playing and pause
disabled while paused are the bulk; `digitaldj`'s whole strip is `refused=… disabled` by its own
splash gate. **Two traps in the point decode produced the rest, and both look exactly like a dead
control:**

- **A frame centre can be a transparent pixel.** `Cubist`'s `cubist_pause.bmp` is 18.2% white and
  `transparencyColor="white"` — its centre is the gap *between* the two bars, so the centre click
  returns `refused=… not-drawn-here` while every pixel a user aims at hits. **`WMP_RENDER_OCCLUDED`
  is the authority on reachability** (it samples a 17x17 grid and did not flag Cubist); a single
  driven point is the authority on *what the click does*. Use both, in that order.
- **A median over a non-contiguous colour region lands between the blobs.** That is what the two
  `unmapped-pixel` rows (`Utomjording`, `activate`) are. The median rule in § *Auditing one authored
  control* fixes the first-scanline trap and not this one.

**What it did find**, beyond confirming the population: `Colorchooser`'s transport. Its five buttons
are `<TEXT>` nodes chained `left="jscript:<prev>.left+<prev>.width"`, and a text node that measures
itself from its own glyphs reported `width` as **0** before any layout existed — so `stopbutton`,
`pausebutton`, `nextbutton` and `prevbutton` all resolved to `103,29 12x12`, the glyphs overprinted,
and the first click anywhere in that row fired **previous**. `WMP_RENDER_EXPR` printed it as four
`live=16` rows where 16/28/40/52 was authored. It is the only skin in the corpus that chains off a
text node's width (8 expressions, all here), which is why it survived every earlier expression
sweep. **Closed as W218 on 2026-09-19, and the way it was nearly missed is the part to keep.**

- **The row read as a standing condition and was one click deep.** The relayout the misfiring click
  triggers is the first layout there is, so from the second click on, every button is correct. The
  reporter tried to reproduce it by hand and could not, and `reference/skins/colorchooser.md` had
  already filed it under *What was ruled out* with the words *"the running app lays all five out
  correctly"* — inferred from the mechanism, never measured.
- **The instrument that settles it is a cold `WMP_RENDER_CLICK`, one point per process.** Five
  separate invocations, one first click each: before the fix, `view-2@109,35` (the stop glyph)
  answered `hit=prevbutton#14 … command=previous` and `view-2@145,35` answered `MISS`; after, each
  of the five points hits its own button. Driving all five points in *one* invocation hides the
  defect completely, because the first click repairs the row for the other four.
- **`WMP_RENDER_SETTLE=1` does not repair it.** Settling drives `onTimer` and pumps the run loop; it
  does not create a layout. Do not read a clean settled capture as a clean first frame.

**And the thing it could not see.** The same session's report — *"pressing pause does not pause the
stream"* — was true while every row above was green, because the defect is in the event the engine
raises 16 ms *after* the click (W170) and a sweep seeds one host snapshot and never transitions.
A click audit proves a control dispatches. It says nothing about what the host does next.
