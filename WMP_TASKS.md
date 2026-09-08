# Windows Media Player (`.wmz`) — ranked open backlog

This is the only live backlog for the WMP skin subsystem. It is the `.wmz` counterpart to
[`WINAMP5_TASKS.md`](WINAMP5_TASKS.md), and the two never share entries: a `.wmz` item goes here, a
`.wal` item goes there. Read `skills/wmp-skin-guide/SKILL.md` before picking anything up.

A skin is a test case, not a milestone: take measured capability work from the top down. Closed
entries move to [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) in the
same change that closes them, so this file stays a list of work that is still open.

## Ranking

**Tier 0 is the top of this page** and everything below is ranked under it: W78, the implicit
magenta transparency key, reported live on 2026-09-08 as visible "all over the place" and not yet
measured anywhere.


Reach is corpus demand across the 14-skin corpus installed in
`~/Library/Application Support/NullPlayer/WMPSkins/`, not severity. Every Reach number must be
reproducible by a command recorded next to it.

**Two numbers on this page are now produced by the census itself rather than by hand, and the file
it writes them to outranks any row here that disagrees.** `starved.tsv` ranks every view by
`unresolved / declared` (W70) and `appkit.tsv` ranks every hosted view by how much an AppKit overlay
painted outside any widget frame (W71). Take work from the top of those, not from the top of a
paragraph. Measured 2026-09-08 over 179 archives and **607 views**: 41 starved views across 36 skins,
79 with no hit target across 49, 75 drawing nothing across 45, and **two** views painting outside a
widget frame.

**"Draws nothing" counts an authored blank the same as a starved one, and closing W75 moved it the
wrong way on purpose.** It was 65 views / 37 skins until a scripted `backgroundImage` started
reaching the scene; ten `mediaSwitcherView`s then began obeying their own `view.backgroundImage = ""`
collapse before redirecting, and a view that correctly draws nothing is indistinguishable from a
starved one in this tally. Read the PNG before ranking a `0 commands` row, exactly as with
`starved.tsv`.

**`starved.tsv` ranks declared-but-unresolved nodes, not missing pixels, and the two are not the
same view.** Its top rows were opened and looked at on 2026-09-08: `Cablemusic/mainview` (ratio 0.64,
63 unresolved) draws a nearly complete player, and `ALXMorph/mainView` draws its whole shell. A high
ratio ranks a view as *worth dumping*; only the PNG says whether anything is missing. **Dump the view
before taking the row.** The same session established what does *not* explain the ratio: geometry
expressions. Corpus-wide **7,569 of 7,569** reach the live evaluator, and `Cablemusic/mainview`
declares none at all — see W68 and `skills/wmp-skin-guide/reference/harness.md` § *After the
cascade*.

**Reach numbers below are `scripts/wmp_skin_census.sh` output, measured 2026-09-07 at rev
`1d7e63bd` over the 180 archives in `WMPSkins/`.** Reproduce with
`scripts/wmp_skin_census.sh /tmp/wmp/census`. **Re-measured 2026-09-07 after W6 closed: 608 views
dumped and not one `RENDER-DUMP … FAILED`.** A row below that still cites 579, 574, 567, 515, 508,
506 or 482 views was not re-measured then. **`WMP0032` and `WMP0033` are both zero corpus-wide**, so
neither a layout rejection nor a decode failure can rank anything any more.

**The measured corpus is 179, not 180.** `scripts/wmp_corpus_exclusions.txt` is the blacklist both
scripts read, and it holds `Darkling.wmz`: a Party Mode skin, authored against a WMP host this
player has no equivalent of and will not grow one, whose own `OnLoad` draws a "designed for Party
Mode" panel when that host is absent — which is what real WMP shows too. An excluded archive is not
a defect and never ranks work here. Reasons live in that file; removing a line is a decision.

**There are no loading rejections left in the corpus.** Load level is now a constant, so it can no
longer rank anything: every entry below is a rendering or runtime defect, and only a dumped PNG or a
`SCRIPT-DIAG` line can see one. A row whose evidence is a census column is by that fact measuring
structure, not result.

Numbers taken before rev `61f8955a` were measured with an instrument that dropped three blocks of
its own output (W35), so a count from an earlier capture is short by an unknown amount rather than
merely stale.

The corpus grew from 14 archives to 180 on 2026-09-07, so **every number taken against the 14-skin
denominator is stale and none of them were rewritten in place.** A count here without the 180-archive
stamp has not been re-measured; re-measure it rather than scaling it. Two byte-identical archives were
deleted; five *name*-similar pairs (`Ginger Man`/`Ginger_man`, `QuickSilver`/`(2)`, `Revert`/`(1)`,
`Project Gotham Racing 2`/`(1)`, `The Unit`/`TheUnit`) are different releases of the same skin with
differing `.wms` and `.js`, and are kept deliberately as separate test cases.

## Tier 0 — take this first

**One row, put here on 2026-09-08 because the reporter sees it "all over the place" and every other
tier is ranked below it until it is measured.**

| ID | Item | Reach | Notes |
|---|---|---|---|
| W78 | Magenta shows through wherever a sprite has no alpha and its markup names no `transparencyColor` | **unmeasured, and measuring it is half the row** — the count wanted is: sprites referenced by markup that (a) carry no alpha channel, (b) contain `#FF00FF` pixels, and (c) hang off a node declaring no `transparencyColor`, per skin and per view. Nothing on this page has that number and no existing script produces it; `scripts/wmp_input_kinds.py` is the nearest shape to copy | Found while confirming the `Halo 2` shutter, and reported live as everywhere. `m_trans_no.png` — the transport cluster at `205,172`, 99x98, **no alpha channel, 1,084 `#FF00FF` pixels** — hangs off a `<BUTTONGROUP>` that declares no `transparencyColor`, while its siblings `mainBack`, `shutterSub` and `shutterStatic` all declare `#ff00ff`. So the engine draws the key colour and the skin shows magenta triangles in the bottom-right of the window and beside the transport row. **The hypothesis to test first, before writing any code: WMP treats magenta as the implicit transparency colour for a bitmap that carries no alpha of its own**, which is what the author of this skin plainly relied on — they keyed three siblings by hand and left this one to the default. Confirm it against a second skin before defaulting anything: a sprite that legitimately paints magenta would lose those pixels, and this is an engine-wide default, not a per-skin fix. **Measure the class, then fix, then re-render the corpus** — `scripts/wmp_render_sweep.sh capture` before and `compare` after is the check that a default this broad changed only what it should. It is at the top of this page rather than in Tier 1c because it is not one skin: it is one rule, and the reporter is seeing it everywhere. |

## Tier 1 — views that load and then draw nothing (all 180 archives load)

Tier 1a held the loading rejections and is **empty**: W33 closed the last of them and moved to the
archive. Nothing goes back in this tier unless a *new* archive is rejected.

### 1b. Views that load and then draw nothing

Indistinguishable from a rejection to anyone using the app. W8, the largest entry this tier ever
held, closed on 2026-09-07, and W6 — the last entry that could reject a view outright — closed the
same day. **No view in the corpus now fails to lay out.** What is left is W48, a smaller and
differently-caused set: views that lay out and then paint the wrong pixels.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W48 | A view paints a flat colour its markup never declares as a key | **28 views across 26 skins** at or above 5% of view area, measured 2026-09-07 over the 580 dumped PNGs of the 180-archive corpus | What is left after W8 closed, and it is **two different defects**, neither of them a missing key attribute — every node that declares one is now keyed. Score it the way `reference/harness.md` says: against the colours each skin's own `.wms` declares, never a hard-coded palette. (a) **A `BUTTONGROUP` blits its whole sheet.** It draws `image=` across the group's frame, so the filler colour between the mapped regions is painted wherever no element covers it; in WMP the mapping image is what says which parts of that sheet are drawn at all. `The_Doobie_Brothers/view-2` (50.4%) is the clearest case — its group additionally misspells the attribute as `tranparencyColor`, and `Alpine7618_v09`'s two groups write `transparencyColor="FF00FF"` with no `#`, which the color parser rejects; **fix the blit before deciding either of those is worth accepting**, because if the sheet is drawn through its mapping the key never matters. (b) **Artwork whose flat colour is keyed nowhere in the markup.** `Main_Street` (mini 40.5%, slim 20.2%, normal 14.6%) authors exactly one `transparencyColor` in the whole file and none on the three subviews that show magenta, so WMP is removing it for some reason not written in the `.wms` — find out what that is before implementing anything. Reproduce by dumping the corpus (`WMP_SKIN=<skins dir> WMP_RENDER_DUMP=<dir>`) and scoring each PNG against its skin's declared keys. |
| W57 | A playlist frame's own black backing shows through once the view is made taller | WoW `plView`, found by dragging the real window; not yet counted corpus-wide | `plFrame` is `<SUBVIEW backgroundColor="#000000" height="JScript:view.height-74">` and the playlist drawn over it does not cover all of it: at the authored 453x264 there is no gap, at 653x364 a ~265x105 black band opens inside it. **Reproduces headlessly** — `WMP_SKIN=…/WoW.wmz WMP_RENDER_SIZE=653x364 WMP_RENDER_DUMP=<dir>` — so it is a scene defect, not the AppKit overlay: the dumped PNG and a screen capture of the same window rect agree. Not a resize-plumbing defect (the frames all resolve correctly; `PROBE` shows `plFrame` at `40,44 466x290` as authored) and not the alignment double-count W-fix above. Establish what WMP draws over that backing — `playlist1.height` is `plFrame.height` and `playlist2.height` is `plFrame.height-20`, so the band is likely the difference between the two playlist elements rather than a missing fill. Count the corpus reach before ranking it: every skin with a `backgroundColor` subview under a playlist is a candidate. |

## Tier 1c — live-reported, not yet reproduced headlessly

**Six of the reporter's defects were captured, reproduced and closed on 2026-09-08** — a borderless
window that was never key (so no `hoverImage` in the corpus ever drew), a script repaint that erased
hover artwork, `<TEXT>` rows that were not hit targets, a tooltip showing the view's `description`,
`Halo 2` opening on a thumbnail view its own `onLoad` blanks, and every GIF looping forever over a
view timer that had never once fired. All six are in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) § *Phase 7*, and the
instrument that found all of them is `WMP_TRACE_INPUT=1`. **The list below still predates them.**

**Live QA of Phase 5 on 2026-09-08 found multiple defects that are not yet written down.** The
reporter drove the app and reported "tons of issues"; the list was not captured before the session
ended, so **nothing below enumerates them and they are not in any count on this page.** Until they
are, read every Phase 5 closure in `docs/wmp-skin/wmp-backlog-archive.md` as *harness-verified only*
— a full corpus sweep with 272 of 545 images changed, none lost, none new, and 2,068 green tests,
which is exactly the evidence the harness notes say does not extend to AppKit, the window's shape
and shadow, a timer, a drag, or a pointer. That is the same gap that produced W43-W46. Capture the
reporter's list into this tier before ranking any further Phase 5 work.

**Phase 6 answered part of that question without the list.** The AppKit blind spot the reporter's
session was assumed to be full of is now measured (W71): 545 of 607 views hosted through the real
`NSView` stack, and **exactly two** paint anywhere the scene does not — both in one skin, both
W74. So whatever the reporter saw is, on this evidence, mostly *scene*-side (the starvation class
W68 sits in, now ranked automatically by W70) or driven by a hover, a timer or live playback, which
W73 records as still unreachable. That narrows the gap; it does not substitute for the list.

**What the reporter did report, 2026-09-08.** Three skins, three different classes. `corona` is the
control: it "works well, has all its sliders and buttons for the most part", which is the reference
result and the reason the other two are legible as defects rather than as the engine being broken.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W68 | The Alienware/ALX family draws a shell and nothing in it reacts | 6 skins named below, inside a corpus-wide class of **41 views across 36 skins** resolving under half the nodes they declare, **79 views / 49 skins** with no hit target and **65 / 37** drawing nothing, measured 2026-09-08 over the 607 views of the 179-archive sweep. **The ranking is now automatic** (W70): `starved.tsv`, every census run | Reported as "ALXMorph does nothing — no animation and nothing reacts". **This is not an AppKit defect and it did not need a live session to find: the sweep has been printing it all along.** `RENDER-DUMP mainView` for `ALXMorph` is `339x329, 15 nodes, 8 commands, 5 hits, 0 widgets, **15 unresolved**` — as many nodes failed to resolve geometry as laid out, and five hit targets is a whole player's worth of buttons missing. `AlienMorph` and `AlienwareTeleport` are identical at `368x426`; `Alienware Invader` is worse still at `2 nodes, 0 commands, 0 hits, 18 unresolved` — it draws nothing whatsoever. The absent animation is the same cause, not a separate one: the family's big `m_anim_*` GIFs hang off subviews that are either unresolved or authored `alphaBlend="0"` and faded in by script (`mainAnimCoolantChamber` is the one confirmed by hand), so W38 `alphaBlendTo` was expected to be load-bearing here. **It was not, and W38 is now closed**: with the call implemented, `ALXMorph`/`AlienMorph`/`AlienwareTeleport` `mainView` goes 8 commands → **7**, because `alienware.js` fades `mainAnimCoolantChamber` *out* in the handler that used to abort at the call. **The artwork comes back on a click, and the row that gates it is W76, not W53/W54**: `toggleCoolantChamberAnim()` is raised by `animTrigger`'s `onClick`, and which branch it takes is decided by `theme.loadPreference("coolAnim") == "true"` — an unset key answers `''`, so a first run takes the `else` and fades the animation *in* to 255. Clicks already dispatch, so the animation half of this row is one preference read away, not an unraised event. Hover is load-bearing elsewhere in the same skin — `volumeText` and `seekText` fade in and out of `onMouseOver`/`onMouseOut` in `alx_dl.wms` — so W54 buys those readouts, not the coolant chamber. **W54 closed 2026-09-08** — hover now dispatches, and with W79 the window can receive a pointer at all — so this row's hover half is testable live rather than pending. **It is one view, not the skin.** `ALXMorph`'s other seven views are healthy — `eqView` is `45 nodes, 44 commands, 26 hits, 8 unresolved` and `videoView` `35/33/12/6` — so only `mainView`, the view it opens on, is starved. That is why the skin reads as dead while its equaliser and playlist would work if you could reach them. **W70's ranking disagrees with this row about where to start.** ALXMorph scores exactly 0.50 and is one of the *milder* cases; the worst in the corpus are `Disney_Mix_Central/mainView` (2 of 25 nodes resolved), `Batman Begins/mainView` (2 of 21), `Alienware Invader/mainView` (2 of 20) and `Cablemusic/mainview` (35 of 98). Take the top of `starved.tsv`, not the top of this row. **The AppKit half is cleared**: `ALXMorph/mainView` diffs to zero against its own hosted render (W71), so nothing here is an overlay defect and the whole of it is scene-side. **The expression-cascade theory is dead — measured 2026-09-08 and it was the probe.** `WMP_RENDER_EXPR` used to report 34,314 of 42,015 rows corpus-wide reaching no evaluator (82%), which was read here as the cause; 34,300 of those were **another view's** expression printed under this view's name, each already ordered and evaluated under its own view. With the probe scoped the way both evaluators are (`WMPRenderDumpTests.expressionLines`), the corpus reads **7,569 / 7,569 reaching the live evaluator, zero unreached**, and `starved.tsv` does not move: 41 views / 36 skins, unchanged. Expressions are not what starves a view. All three named skins were opened and looked at: `Cablemusic/mainview` declares **no geometry expressions at all** yet carries 63 unresolved nodes and draws a nearly complete player; `ALXMorph/mainView` has 4 and all of them resolve live, and it draws its whole shell — so "does nothing" is interaction and animation (W38, W53/W54), not layout; `Alienware Invader/mainView` has 6 and all of them resolve live, and it is blank because `toggleShutter()` plays a **568-frame intro** off a 50 ms timer and only at frame 568 sets `mainBack.backgroundImage` and `mainBackGroup1.visible = true`. **Start from what `unresolved` actually counts, not from `EXPR`** — and note that a high ratio does not mean a blank view: two of the three worst-ranked views in `starved.tsv` render substantially. The evidence is `skills/wmp-skin-guide/reference/harness.md` § *After the cascade*. **W75 came out of it, was load-bearing here, and is now closed**: a script assignment to `backgroundImage` never reached the scene, which is exactly what Alienware's intro is made of — `Alienware Invader/mainView` now draws its full 406x380 player under `WMP_RENDER_SETTLE=32` instead of an empty PNG. Its `2 nodes / 0 hits` in the *default* state is unchanged and is not that defect: frame 0 of a 568-frame intro is still frame 0. The worst of the wider class are `digitaldj/DigitalDJ` (**91** unresolved against 101 nodes), `Cablemusic/mainview` (63 against 35), `WALL-E/mainView` (35 against 37) and `NVIDIA/mainView` (32 against 43); `Disney_Mix_Central`, `Batman Begins` and `Alienware Invader` all draw a `mainView` of 2 nodes and 0 hits. |
| W69 | `Xbox Live Skin` animates and flickers | 1 skin confirmed live; the flicker class covers **90 of 180 archives** that carry a multi-frame GIF | Reported as "xbox live skin animated/flickers", so the clock and the repaint loop both work and the compositing does not. Its `mainView` is also in W68's class — `19 nodes, 15 commands, 11 hits, 15 unresolved` — so some of what looks like flicker may be a starved layout rather than the repaint loop; separate the two before diagnosing either. It reports `ANIMATION shortestDelay=0.030 bounds=23,9 248x195` — a **33 fps full-scene re-render** with a sub-rect invalidation, which is the most demanding case in the corpus and therefore the right one to fix against. Candidates, none of them confirmed and all of them cheap to distinguish: (a) `present()` replaces the whole `NSImage` while `setNeedsDisplay` invalidates only the animated bounds, so the untouched region keeps older pixels against a newer image; (b) the animated `bounds` union is computed once at `startAnimation` from the scene's commands and never revisited, so a node that moves leaves its old frame un-erased; (c) 145 frames of `intro_anim.gif` decoded and cached separately may be thrashing the image store's 64 MiB LRU, forcing re-decodes mid-loop. **Instrument before reasoning**: the loop is the only thing in this engine that repaints without a script transaction, so log what it presents and what it invalidates before changing either. |
| W74 | A playlist overlay paints below the view it lives in | **2 views / 1 skin** (`Revert.wmz` and `Revert (1).wmz`, two releases of the same skin), the *only* two in the corpus, measured 2026-09-08 by `WMP_RENDER_APPKIT` over the 545 hosted views of the 179-archive sweep | 4,000 px at delta 196, in a 250x4 band at `3,256` of a 260-tall view. `ctrlPlaylist` is authored `3,14 250x257`, which ends at y=271 — eleven pixels past the view's own bottom edge — and `WMPMainView.layout()` positions the overlay from that frame without clipping it to `bounds`, so the `NSView` paints where the scene has nothing. **This is the whole W43 class in the corpus's default state**: 543 of the 545 hosted views agree with their scene exactly. Establish what WMP does with a control authored past its view's edge before choosing between clipping the overlay to `bounds` and clipping it to the widget's own `clipRect` — the scene already carries a `clipRect` the overlay ignores, which is the cheaper of the two and may be the correct one. Reproduce with `WMP_SKIN=…/Revert.wmz WMP_RENDER_APPKIT=1`, and `WMP_RENDER_APPKIT_DUMP=<dir>` to see both bitmaps. |




Found by the reporter driving the real app on `corona.wmz` during Phase 3 live QA, after the drawers
and the file-open button were confirmed working. **None of these is visible to the harness**: the
headless render of `vPlayer` and `viewTiny` is correct in every state tested, including with the view
timer running and with the equaliser drawer open. That is the whole point of the entries — the
sweep's blind spots are AppKit hosting, hit testing under the pointer, and anything driven by live
playback. Reproduce by driving the app; a census row will not show any of them.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W43 | **~~The player goes black while a track plays~~ — FIXED** | corona, live | Root cause was neither of the two suspects recorded here. `WMPEffectsSurfaceView.draw` and `WMPPlaylistSurfaceView.draw` filled `dirtyRect` rather than `bounds`; AppKit hands a view a dirty rect larger than itself (measured: `{{-269, -26}, {596, 468}}` against `bounds` `320x240`) and a layer-backed view does not clip it, so the overlay's translucent wash covered the whole window. Not playback-specific and not `WMPVideoPlaceholderView` — no video widget is ever built for corona. Found by comparing the renderer's own output against a screen capture of the same rect; see `live-ui-testing`. |
| W44 | **Four different buttons in the top cluster all open the file dialog** | corona, live | `bOpenFile`, `bPlaylist`, `bVis` and `bEq` are `BUTTONELEMENT`s inside one `BUTTONGROUP`, separated only by their `mappingColor` in `player_top_controls_left_map.bmp`. A coordinate scan along `y=12` resolves them correctly and distinctly (`WMP_RENDER_CLICK="vPlayer@366,12;400,12;420,12;444,12"` gives `bOpenFile`, `bPlaylist`, `bVis`, `bEq`), so the mapping table is right at that row — check other rows before assuming the sampler is wrong. The other candidate is dispatch rather than hit testing: `dispatchScriptEvent(name:targetID:)` filters handlers by `xmlID`, and a `nil` `targetID` runs **every** `onClick` in the view, one of which is `OpenMedia()`. Confirm which by clicking each button once with `WMP_RENDER_CLICK` and reading the `handlers=` count. |
| W45 | **No way to reach the compact view from the skin** | corona, live | `ToggleSuperCompact()` sets `theme.currentViewID = "viewTiny"`, which the object model maps to a `setCurrentView` host command, and `switchView(to:)` implements it. It is reached from a button that is probably one of W44's, so W44 may be the whole of this. The menu route — **Skins → Windows Media Player → Views → viewTiny** — does work and is the fallback while this is open. |
| W46 | **`viewTiny` is indistinguishable from `vPlayer`, and the switch is a trap** | corona, live | Corona's compact-view button is an unnamed `<BUTTON>` inside the equaliser drawer drawn with `minimize_button.bmp` (tooltip "Mini Player"), the selected view is persisted on every present, and the two views render almost identically — so a user lands in the compact view, cannot tell, and finds the playlist/equaliser drawers gone with no way back except **Skins → Windows Media Player → Views**. Reported as "the playlist and eq drawers no longer open". The dispatch half is fixed (an unnamed node no longer runs every `onClick` in the view); the indistinguishable render and the absent affordance are open. |

## Tier 1d — what the Phase 6 instruments do and do not reach

**W71, W72 and W70 landed and are in the archive.** The harness now hosts every scene in the real
`NSView` stack and diffs it (`WMP_RENDER_APPKIT`), drives a captured drag along a slider's own axis
(`WMP_RENDER_CLICK` with a `>`-joined path), and ranks every view by how much of it failed to
resolve (`starved.tsv`, every census run). What they measured on their first run is in
`skills/wmp-skin-guide/reference/harness.md` § *After Phase 6*; the two findings are W74 and the
re-ranking of W68.

**Manual testing still does not scale to this corpus.** 179 skins times sliders, drawers, drags and
animation is not a human-scale job, and Phase 5 shipped its AppKit half unmeasured because of it.
What is left of that gap is one row.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W73 | A clean sweep still proves only the default state | every skin | Narrowed by W71 and W72, not closed by them. The AppKit *overlay* class is now measured — 545 hosted views, two defects, both in W74 — and every slider in the corpus is drivable. What no sweep here still says anything about: a tab, a setting, a **hover**, a drawer, the window's shape and its shadow (those live in the window server and stay a short, genuinely manual list), and anything driven by live playback. W69's flicker is in that remainder, which is why it needs its own instrumentation rather than another sweep. |

## Tier 2 — the script runtime, after Phase 3

The runtime is one persistent `JSContext` per skin session with a native Swift object model
(`skills/wmp-skin-guide/reference/object-model.md`). **Everything below is re-measured at rev
`c8a843e4` over the 180-archive corpus**, with the harness now driving each view's own `onLoad` the
way the app does. Reproduce with `scripts/wmp_skin_census.sh /tmp/wmp/census` and rank the
`SCRIPT-DIAG [handler-error]` lines in `render.txt`; the pre-Phase-3 table that stood here was
measured against a runtime that could not run a handler to its second statement, and every number in
it is void.

Corpus effect of the change: **228 handler errors remain, from a state where Corona's `OnLoad` could
not reach its second line**; expressions are now essentially solved — **1 `expression-error` and 8
`invalid-geometry` across all 482 views**. Commands drawn 9,120 → **9,186**, widgets 1,396 →
**1,436**, unresolved nodes 2,393 → **2,352**, and 40 of 482 dumped PNGs changed with **none lost and
none blank** (`scripts/wmp_render_sweep.sh compare`).

### 2a. What still stops a handler, ranked by skins

**Re-measured 2026-09-08 over the 179 archives after W37 closed, against a same-tree baseline
worktree.** Runtime member errors **252 → 127**, skins carrying a dead handler **119 → 70**, and the
159 `Can't find variable: mediacenter` that were 63% of the class are **gone**. Reproduce with
`scripts/wmp_render_sweep.sh capture <dir> --allow-dirty` and tally
`WMP: unimplemented <member>` and `Can't find variable: <name>` in `<dir>/raw.txt` by name and by
containing `SKIN` block. The queue behaved exactly as `reference/object-model.md` rule 2 says it
would: closing the biggest row let handlers run further and **raised** the rows behind it, so the
numbers below are the post-W37 ones and the pre-W37 ones are void.

**W38 then closed against the same 179 archives and did it again.** `WMP: unimplemented` calls
corpus-wide fall **83 → 43** — the 42 that went are its own 40 `alphaBlendTo` and 2
`setColumnWidth` — while `Can't find variable` / `TypeError` stays at 45, because this row was never
a name the runtime could not find. Thirty views changed on screen and none of them is a fade: they
are the rest of those `onLoad` handlers running. The rows below are otherwise unmoved; W77 is the
one it raised.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W39 | `eq.speakerSize` | 18 skins | Plus `eq.enableSplineTension` and `eq.enhancedAudio` at 1 each. WMP's speaker/spatial settings; the engine has no equivalent, so this is an honest `inert()` candidate rather than a feature. |
| W40 | An element the skin names is in another view | 8 + 4 + 2 + 2 + 2 skins | `Can't find variable: vidinfo` (8, new behind W37), `Can't find variable: pl` (4), `playlistframe.setColumnResizeMode (no such element)` (2), `pl.setColumnWidth` (2), `vidZoom`/`videoWin` (2 each, also new behind W37). Handlers are now scoped per view, but a script's *globals* are the current view's elements only. Find out what WMP does with a cross-view reference before choosing. |
| W41 | `theme.closeView` | 5 skins | Also `player.currentMedia.sourceURL` (4). Both are small and both are real. |
| W42 | A skin function is missing because its program never registered | ~12 skins, 1–2 each | `skin_init`, `loadVidPrefs`, `UpdateMetaData`, `checkForContent`, `Init`, `gears`… Each is one skin's own function, so the cause is upstream: a `.js` that failed to resolve, evaluated with an error, or is a `res://` entry. Diagnose from `SCRIPT`/`SCRIPTS` lines before writing any object-model code. |
| W50 | `theme.openViewRelative` is not implemented | **2 skins** (`Revert.wmz`, `Revert (1).wmz`, the two releases of the same skin), measured 2026-09-07 over the 180 archives in `WMPSkins/` | `UNKNOWN member theme.openviewrelative ×4`. WMP's placing variant of `openView`: `theme.openViewRelative('vwEQ', 0, 130)` opens the view as a window offset from the current one's top-left, which is how Revert hangs its EQ under the player and its playlist beside it. Found while closing W49 and **deliberately left out of it**: aliasing it to `openView` would present the view in the one window, drop the offset, and disappear from the tally — the trap `INERT` exists for. It is only worth doing with somewhere for a second window to go, so rank it with whatever answers that question, not before. Reproduce by sweeping the corpus and reading `UNKNOWN member` lines. |
| W76 | `theme.loadPreference` returns `''`, so a `'--'` default sentinel never fires | **Raised by W37 closing, and now a drawn-pixel defect rather than two expressions.** `digitaldj.wmz` (2 expressions) plus the `Plus!` family, where the handler that reads the sentinel only started running once `mediacenter` existed; corpus reach still unmeasured | **`Plus! Professional/videoView` lost its right drawer tab to this on 2026-09-08**, which is how it was found: `loadVidPrefs` reads `theme.loadPreference('vidRightDrawer')`, tests it `!= '--'`, and an unset key answering `''` takes the branch that closes the drawer. That is the same inverted sentinel as below, costing artwork rather than a number, and it means the row's reach must be re-measured across every `!= '--'` in the corpus before it is ranked. **W38 closing added a second drawn case and it is not a `'--'` sentinel**: `ALXMorph`'s `toggleCoolantChamberAnim()` branches on `theme.loadPreference("coolAnim") == "true"`, so the re-measure is every comparison against a `loadPreference` result, not only the `'--'` spelling. It is also the row standing between W68 and its missing animation, which is why that row now points here rather than at W53/W54 (W54 closed 2026-09-08). The only two rows in the corrected 179-archive `EXPR` sweep that reach the live evaluator and come back with nothing usable: `view.width` and `view.height` are `(theme.loadPreference('WD') == '--') ? 640 : theme.loadPreference('WD')`, and a key that was never written answers `''`, which is not `'--'`, so the ternary yields the empty string instead of the authored 640/458. Real WMP returns `'--'` for an unset preference — that is what the sentinel is testing for — so the defect is in what `loadPreference` answers for a missing key, not in the skin. The view still draws at 640x458 because the static grammar answered independently, which is what hides it. Establish WMP's actual unset-key return before changing it, and check `reference/object-model.md` records whichever answer lands. |
| W77 | A script write to `view.width` / `view.height` reaches no window | **77 skins, 692 assignments** across the 179 archives (`view.(width|height) =` in every `.js`/`.wms`, decoded utf-16/utf-8/cp1252) | **Raised by W38 closing, and it is a drawn-pixel defect.** `WMPMainWindowController` rebuilds after every transaction at `activeScene.canvasSize` — every one of its ten `build(viewID:requestedSize:)` call sites passes the size it already had — so a scripted resize commits to `overrides.geometry` for the view root and is then discarded. It was invisible while the handlers carrying it aborted earlier. `ALXMorph/videoView` is the clean case: `alienware.js` closes the brightness/saturation drawer when `isAvailable("Stop")` is false and then writes `view.width = 297; view.height = 316;`, so the view now correctly draws no drawer and incorrectly keeps a 389x357 canvas with 60 px of nothing under it. Fix is the controller, not the builder: the builder already clamps `requestedSize` against `minWidth`/`maxWidth`, so the work is deciding when a scripted size outranks the user's own window size and whether it persists across a view switch. |

### 2c. Events the markup declares and nothing ever raises

`WMPAttributeParser.handlerNames` decides what becomes a `.handler` at all, and
`WMPCorpusReportHarness.supportedEvents` decides what counts as implemented — an event needs a name
in the first **and a dispatch site** to be either. Neither list was ever printed by the harness, so
this whole class was invisible: `WMPCompatibilityReport` collected the counts and compared them and
`compatibilityLines` emitted only tags and members. That is how `onResize` sat unrecognised through
three phases. It is now `UNKNOWN event <name> ×<n>`, and the numbers below come from it.

**Reproduce**: `scripts/wmp_render_sweep.sh capture <dir> --allow-dirty`, then tally
`UNKNOWN event` in `<dir>/raw.txt` by name and by containing `SKIN` block. Measured 2026-09-08 over
the 179 measured archives: **4,114 uses**, down from 6,823 — W52 closed and took the user-driven half
of W51 with it, draining 2,709 uses, 40% of the class, in one change. `onresize` is absent from this
list because it closed in the same change that added the instrument; `value_onchange`,
`openstate_onchange` and `playstate_onchange` are absent because they are now accepted spellings of
events this engine dispatches. The distinct-name count reads 140 → 142 rather than 140 → 137: **36
blocks were damaged in both captures** (W35), so the *edges* of that vocabulary move between runs and
the uses figure is the one to quote.

An entry here is markup asking for something. Two things make it work: classification (one line) and
a dispatch site (the real cost, and different per event). Do not add a name to `handlerNames` or
`supportedEvents` without its dispatch site — a recognised event nothing raises drops out of this
table while still doing nothing, which is exactly the state `onResize` was in.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W51 | Nothing raises `value_onchange` when the **host** moves a control | **the remainder of 2,170 uses across 175 of 179 archives**; the user-driven half closed 2026-09-08 | Half of this closed with W52: `value_onchange` is the `change` event's other spelling, accepted by `WMPMainWindowController.handlers(in:event:…)`, so a skin's handler now runs when the user moves the slider. **What is left is the other direction.** A `<SLIDER value="wmpprop:eq.gainLevel1" value_onchange="…">` is bound both ways in WMP: the handler also runs when the *host* property moves, which is how a seek bar's readout follows playback and how a preset changing the ten equaliser gains re-runs each band's handler. This engine has no per-property observation path, so nothing raises it. That is a real gap and it is recorded here rather than left to look implemented — the trap `INERT` exists for. The `_onchange` family is confirmed **general** rather than 140 separate events (the corpus also writes `width_onchange`, `left_onchange`, `height_onchange`, `visible_onchange`, `enabled_onchange`, `down_onchange`), so whatever answers this answers `currentposition_onchange` (103/80) and `selecteditem_onchange` (20) too. Rank it with `WMPObservablePropertyRegistry`, which already knows which paths a scene depends on. |
| W53 | Keyboard events (now reachable: the window could not take the keyboard at all until W79) | `onkeydown` 501/78, `onkeypress` 409/72, `onkeyup` 94/30 | `WMPMainView.keyDown` handles focus traversal and activation and raises no authored handler. Needs a key-code/character contract at the object-model boundary — decide what a skin may see of a keystroke before implementing. |
| W55 | Animation and drag completion callbacks | `onendmove` 244/114, `ondragend` 138/86, `onendalphablend` 57/22 | The completion half of `moveTo`/`resizeTo`/`alphaBlendTo`, all three of which are implemented as immediate endpoints (W38, closed). A skin chains its next step from these, so an unimplemented one is a sequence that stops after step one. **W38 closing is what makes this the next piece**: the endpoints now land, so what is missing is the tween between them and the callback that starts the next step. |
| W56 | Video and playback-position events | `onvideostart` 190/140, `onvideoend` 132/130, `onpositionchange` 147/41, `currentposition_onchange` 103/80 | `onvideostart`/`onvideoend` reach 140 and 130 skins because the standard WMP template wires them; both need the hosted video surface (Phase 5, W9) before they can be honest. The position pair may fall out of W51 if `_onchange` is general. |

### 2b. Recognised, answered, and nothing behind them (`INERT`)

These do **not** stop a handler; they are the ranked list of "properties skins set that nothing
renders", which is Phase 5 rendering work rather than runtime work. Top by skins:
`playlist1.itemPlayingColor` / `.itemPlayingBackgroundColor` / `.disabledItemColor` (15 each),
`timeN.upToolTip` (10 each), the `playlist1.itemSelected*` family (9 each). Full column:
`inert_calls` in `census.tsv`. `vidback.alphaBlendTo` (14) was the second row here and is gone:
W38 made it live, and `setColumnWidth` joined this tier in its place — recognised so it stops
aborting its handler, counted `inert()` because nothing draws playlist columns.

## Tier 3 — drawing the skin's own controls (Phase 5)

**Reach here is `scripts/wmp_markup_census.sh` output, measured 2026-09-07 over the 177 archives it
could read** — the 180 in `WMPSkins/` less `Darkling.wmz` (excluded) and the two whose local header
signature is overwritten, which `unzip` cannot open and the engine can (`Need_for_Speed_Underground`,
`SplinterCellWMPSkin`). So every number below is short by at most two skins, never long. Reproduce
with `scripts/wmp_markup_census.sh /tmp/wmp/markup`.

This is authored demand, not result: the census says a skin asks for an attribute, never that the
engine draws it right. Only a dumped PNG says that.

**What Phase 5 closed** is in the archive. It closed the whole of the phase *as the harness measures
it*, and live QA on 2026-09-08 found defects that are not yet enumerated — see Tier 1c before
treating any of this as done: the slider family
draws its own thumbs and progress (163 skins), `CUSTOMSLIDER` reads its `positionImage` (93),
animated GIFs run (90 of 180 archives), `cursor` (145), `tabStop` (119), `alphaBlend` (38),
`passthrough` (82), `clippingImage` (28), `TEXT`'s `fontFace`/`fontStyle`/`fontSmoothing`
(109/139/95), real `POPUP` and `EDITBOX` controls, `EQUALIZERSETTINGS` stopped being a widget (163),
and the opaque `VIDEO` placeholder is gone (W9, 166). Two rows below are what it could **not**
close, and both are blocked on something other than drawing.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W66 | A `LISTBOX` has a control and nothing to put in it | **8 skins**, 16 uses, measured 2026-09-07 over 177 archives | Every one is `plListBox1`/`plListBox2`, a playlist chooser the skin fills from script by walking WMP's media collection (`getSelPlaylist()`). The control now exists, draws, and reports its selection; what it cannot do is have rows, because the object model answers nothing for `player.mediaCollection` — so a skin's `onLoad` appends nothing and the box is empty. That is a host-surface decision (what a `.wmz` may see of this player's library), not drawing work, and it is deliberately **not** faked with rows this player invented. Rank it with whatever answers the media-collection question. |
| W67 | `.cur` and `.ani` cursors | **~70 uses**, a handful of skins (`resize.cur` 26, `over.ani` 23, `sizetopright.cur` 12, `size2_m.cur` 6) | The remainder after the named cursors landed: Windows cursor formats, which no macOS decoder reads. They resolve to no cursor rather than to a wrong one. Worth doing only with a `.cur`/`.ani` decoder, and worth almost nothing without one. |


## Closed

Closed entries live in [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md),
verbatim and with their evidence. Move a row there in the same change that closes it — one left here
reads as open work.
