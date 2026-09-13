# Windows Media Player (`.wmz`) — ranked open backlog

This is the only live backlog for the WMP skin subsystem. It is the `.wmz` counterpart to
[`WINAMP5_TASKS.md`](WINAMP5_TASKS.md), and the two never share entries: a `.wmz` item goes here, a
`.wal` item goes there. Read `skills/wmp-skin-guide/SKILL.md` before picking anything up.

A defect in the **shared video path** belongs to neither and goes in
[`docs/video-playback/backlog.md`](docs/video-playback/backlog.md) — opened 2026-09-10 because
hosting `<VIDEO>` (W102) surfaced one that had nowhere to go. **V1 there is worth reading before any
`.wmz` video work**: a playing film is silently re-opened from the start and the reload hangs, and
because the picture simply stops it reads as a skin or decoder defect when it is neither.

A skin is a test case, not a milestone: take measured capability work from the top down. Closed
entries move to [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) in the
same change that closes them, so this file stays a list of work that is still open.

## Ranking

**Tier 1b has no remaining open row.** W103, W104, and W105 are deferred. **W124 closed 2026-09-10** — `<VIDEO>` readiness now keeps its
event state across a same-media output rebuild while leaving the live surface state empty, so the
skin receives a matching `videostart` after a transient teardown without losing button input.
**W102 closed 2026-09-10** — `<VIDEO>` is hosted, the picture is
parked in the authored rect at the authored scale, and W105's `.video` routing went in with it, so
the Windows-menu item no longer opens our window over a skin that declares its own box. What it left
behind is ranked here: W103 is now answerable: the video path exists, so `<VIDEOSETTINGS>`'s four
sliders are a decision about what to bind, not a question about whether there is anything to bind to.

**Tier 0 is empty and the magenta class is closed.** W78 landed on 2026-09-08, **W78a closed the
same day**, and W125 closed the one remaining declared-key JPEG rounding case on 2026-09-11. The
former residual was `portals/mode1` (829 px, 0.38%), resolved by W116, plus `Plus! Pulsar/mainView`
(49 px, 0.04%), a button that declares `transparencyColor="#ffffff"`, where standing aside is
correct. **Do not open another magenta row without a screen to point at.** Their closure notes are
in [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md).

**W129 closed 2026-09-11 and it closes the largest row of the SDK conformance audit.** It also
produced the rule that should govern every remaining row of that audit: *reading a handler's reach
is not reading its result*. Of its four host attributes only `currentEffectType_onchange` moves a
pixel — 96 of the 105 `currentPosition_onchange` uses write a number **W120 already supplies**, and
all 9 `currentMedia_onchange` uses are the album-art call that became W137. The census delta,
the corpus sweep and the live verification are in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md).

**W144 closed 2026-09-12 and it is four rules, not one defect.** One live report against
`xsn_sports`' settings drawer produced four unrelated engine defects — centring beaten by a scripted
`left`, an authored `JScript:` geometry expression re-applying every transaction and undoing the
script that moved the node, skin artwork drawn over a **windowed** `<EFFECTS>`, and `onClose` having
no dispatch site at all (**373 handlers across 133 of 180 archives**, all dead). The last two are
capability rows in their own right and neither was on this page. Its two process lessons are in
[`reference/harness.md`](skills/wmp-skin-guide/reference/harness.md): a render dump is flat and
cannot answer a layering question, and a single-transaction sweep cannot measure a per-transaction
rule. Closure note and the ruled-out list are in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) § *Phase 20*; dossier
at [`reference/skins/xsn-sports.md`](skills/wmp-skin-guide/reference/skins/xsn-sports.md).

**W128 closed 2026-09-11 and it is the row the rest of the SDK conformance audit hangs off.** That
audit is the first time this engine was read against Microsoft's Skin Programming Reference as a
*specification* rather than against a corpus sweep, and its point is that a corpus scan can only
find what some skin already calls. W128 brought `elementMethodVocabulary` up to the SDK's
element-method list, which changed what every later measurement can see: an unimplemented SDK method
was being counted `INERT` — Tier 2b, the tier you do not take runtime work from — and is now
`UNRECOGNISED` where it belongs. **W136 and W132–W133/W135 are that audit's remaining rows, ranked
 in that order** (W136 in § 2a; W132–W133 and W135 in Tier 3), and § *2c-note* is its
disproved list: read that before opening a row that came from reading the SDK against a scan. The
closure note, with the census delta and the render-sweep result, is in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md).

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
dumped and not one `RENDER-DUMP … FAILED`.** **That last clause is no longer true and was re-measured
2026-09-09: 62 `RENDER-DUMP … FAILED [WMP0035]` across the 179-archive sweep, and every one of them
is a view with no window.** The tally is `controlView` ×25, `previewView` ×16, `mediaSwitcherView`
×12, `view-2` ×3, `versionView` ×3, `vGhost`/`vGhostAutoDetect`/`playview` ×1 — the windowless class
`SKILL.md` describes, whose honest size is `0x0` and which `WMPRenderer` correctly refuses. The 25
matches the 25 archives that author a `controlView` exactly. **So a `WMP0035` line is harness noise
here, not a defect**, and the sentence it replaced would have you read it as one; a FAILED line on a
view that *does* have a canvas is still worth chasing. A row below that still cites 579, 574, 567, 515, 508,
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

## Tier 1 — views that load and then draw nothing (all 180 archives load)

Tier 1a held the loading rejections and is **empty**: W33 closed the last of them and moved to the
archive. Nothing goes back in this tier unless a *new* archive is rejected.

### 1b. Views that load and then draw nothing

Indistinguishable from a rejection to anyone using the app. W8, the largest entry this tier ever
held, closed on 2026-09-07, and W6 — the last entry that could reject a view outright — closed the
same day. **No view in the corpus now fails to lay out, and no Tier 1b row remains open.**

| ID | Item | Reach | Notes |
|---|---|---|---|

## Tier 1c — live-reported, not yet reproduced headlessly

**Six of the reporter's defects were captured, reproduced and closed on 2026-09-08** — a borderless
window that was never key (so no `hoverImage` in the corpus ever drew), a script repaint that erased
hover artwork, `<TEXT>` rows that were not hit targets, a tooltip showing the view's `description`,
`Halo 2` opening on a thumbnail view its own `onLoad` blanks, and every GIF looping forever over a
view timer that had never once fired. All six are in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) § *Phase 7*, and the
instrument that found all of them is `WMP_TRACE_INPUT=1`.

**A seventh closed on 2026-09-08, and it was made visible by the sixth.** Once the view timers ran,
every animation restarted from frame zero on every scene rebuild — reported as "the animations keep
opening and closing constantly… when you try to interact they are just opening and closing all the
time". `startAnimation` rewound its epoch on every call and is called by every rebuild, so a view
declaring `timerInterval="100"` restarted a 2.16s one-shot intro ten times a second, and a hover
crossing did it again. Archived as **W85** in § *Phase 8*; the mechanism and the `INPUT animation` trace line
that found it are in `reference/harness.md` § *The one probe that is not in the test binary*.

**Live QA of Phase 5 on 2026-09-08 found multiple defects that are not yet written down.** The
reporter drove the app and reported "tons of issues"; the list was not captured before the session
ended, so **nothing below enumerates them and they are not in any count on this page.** Until they
are, read every Phase 5 closure in `docs/wmp-skin/wmp-backlog-archive.md` as *harness-verified only*
— a full corpus sweep with 272 of 545 images changed, none lost, none new, and 2,068 green tests,
which is exactly the evidence the harness notes say does not extend to AppKit, the window's shape
and shadow, a timer, a drag, or a pointer. That is the same gap that produced W43-W46. Capture the
reporter's list into this tier before ranking any further Phase 5 work.

**Three more were captured on 2026-09-09 and none of them was the change that surfaced them.** W55
made drawers hide their contents when shut, which is correct and which removed an accidental
compensation: controls that had been drawn stranded outside an already-closed drawer stopped being
drawn, so a drawer that fails to open for its own reasons is now visibly empty. Each report was
reproduced against a **baseline worktree at the parent commit and behaved identically there** —
`xsn_sports`'s drifting drawer button is now **W99**, `BlueCrush`'s dead title-bar button was
**W100** (closed 2026-09-13), and `Ginger Man`'s missing track display is its `mainView` being starved (10 nodes, 2
widgets, 6 unresolved), which `starved.tsv` already ranks under W68 and which earns no row of its
own. **Build the baseline worktree before attributing a live report to the change in front of you**;
it took one build and it moved all three out of this change's ledger.

**Phase 6 answered part of that question without the list.** The AppKit blind spot the reporter's
session was assumed to be full of is now measured (W71): 545 of 607 views hosted through the real
`NSView` stack, and **exactly two** paint anywhere the scene does not — both in one skin, both
W74. So whatever the reporter saw is, on this evidence, mostly *scene*-side (the starvation class
W68 sits in, now ranked automatically by W70) or driven by a hover, a timer or live playback, which
W73 records as still unreachable. That narrows the gap; it does not substitute for the list.

**Three more closed on 2026-09-09, all from one report on `WoW`** — "wow skin is empty and shows no
player or skin windows", then "adding to the playlist does not work", then "why does the now playing
look like this? it should fit and marquee". They were three unrelated engine defects, each of which
hid the other two: a panel opened with `theme.openView` was persisted as the session's view (**W96**),
an unanswerable `wmpprop:` on `visible` deleted the playlist control outright (**W95**), and a
`<TEXT>` was drawn unclipped while no skin in the corpus could turn its marquee on (**W94**). All
three are in [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md)
§ *Phase 12*, with the sweep that bounded the second. One thing the report did **not** turn out to be:
"launching a track from library does not play it" did not reproduce — playback started every time
from the Plex browser, and the queue reached the engine; what was missing was any way to *see* it.

**Two more closed on 2026-09-09, and the reason neither had ever been captured is that no probe
here could render a playing player.** "The timer display and seek/progress are broken in wmp for all
skins" was **W119** — a 100 ms position tick dispatched as `status_onchange`, which is WMP's *status
string changed* event, so 70 of the 177 measurable archives re-ran their metadata handler ten times
a second (all 75 authored sources are metadata updaters; 35 of them blank the readout with the inert
`player.status`) and every script timer in the skin was cancelled inside 100 ms of pressing play —
and **W120**, a seek slider whose `max` is the media duration and whose `value` no skin states,
which is 73 sliders across 61 archives sitting on frame 0 for the length of the track. Both are in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) § *Phase 14 (fifth
pass)*. **The instruments came first and they are the transferable part**: `WMP_RENDER_HOST` seeds a
playing host for a whole sweep and `NULLPLAYER_PLAY` starts a debug launch on a track, so the
playback half of W73 is now measurable rather than argued about. With the first of them seeded, 88 of
the 89 measurable archives that author the elapsed binding draw the right string, which is what moved
the search out of the scene and into the app's event dispatch. **The clock half of the same report closed the same
day as W51** — a control is bound both ways, so the host moving it raises `value_onchange` too, and
`Catwoman`'s digit strips now count the track down. That one carries new measured demand with it: 42
handlers that had never run now run, and 30 abort on an **`event` object in a handler** that nothing
binds on either direction of `change`.

**What the reporter did report, 2026-09-08.** Three skins, three different classes. `corona` is the
control: it "works well, has all its sliders and buttons for the most part", which is the reference
result and the reason the other two are legible as defects rather than as the engine being broken.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W68 | The Alienware/ALX family draws a shell and nothing in it reacts | 6 skins named below, inside a corpus-wide class of **41 views across 36 skins** resolving under half the nodes they declare, **79 views / 49 skins** with no hit target and **65 / 37** drawing nothing, measured 2026-09-08 over the 607 views of the 179-archive sweep. **The ranking is now automatic** (W70): `starved.tsv`, every census run | Reported as "ALXMorph does nothing — no animation and nothing reacts". **This is not an AppKit defect and it did not need a live session to find: the sweep has been printing it all along.** `RENDER-DUMP mainView` for `ALXMorph` is `339x329, 15 nodes, 8 commands, 5 hits, 0 widgets, **15 unresolved**` — as many nodes failed to resolve geometry as laid out, and five hit targets is a whole player's worth of buttons missing. `AlienMorph` and `AlienwareTeleport` are identical at `368x426`; `Alienware Invader` is worse still at `2 nodes, 0 commands, 0 hits, 18 unresolved` — it draws nothing whatsoever. The absent animation is the same cause, not a separate one: the family's big `m_anim_*` GIFs hang off subviews that are either unresolved or authored `alphaBlend="0"` and faded in by script (`mainAnimCoolantChamber` is the one confirmed by hand), so W38 `alphaBlendTo` was expected to be load-bearing here. **It was not, and W38 is now closed**: with the call implemented, `ALXMorph`/`AlienMorph`/`AlienwareTeleport` `mainView` goes 8 commands → **7**, because `alienware.js` fades `mainAnimCoolantChamber` *out* in the handler that used to abort at the call. **The artwork comes back on a click, and the preference-default path, now closed as W76, not W53/W54**: `toggleCoolantChamberAnim()` is raised by `animTrigger`'s `onClick`, and which branch it takes is decided by `theme.loadPreference("coolAnim") == "true"` — before W76, an unset key answered `''` and took the `else` branch; it now answers `"--"` and preserves the authored default. Clicks already dispatch, so the animation half of this row is one preference read away, not an unraised event. Hover is load-bearing elsewhere in the same skin — `volumeText` and `seekText` fade in and out of `onMouseOver`/`onMouseOut` in `alx_dl.wms` — so W54 buys those readouts, not the coolant chamber. **W54 closed 2026-09-08** — hover now dispatches, and with W79 the window can receive a pointer at all — so this row's hover half is testable live rather than pending. **It is one view, not the skin.** `ALXMorph`'s other seven views are healthy — `eqView` is `45 nodes, 44 commands, 26 hits, 8 unresolved` and `videoView` `35/33/12/6` — so only `mainView`, the view it opens on, is starved. That is why the skin reads as dead while its equaliser and playlist would work if you could reach them. **W70's ranking disagrees with this row about where to start.** ALXMorph scores exactly 0.50 and is one of the *milder* cases; the worst in the corpus are `Disney_Mix_Central/mainView` (2 of 25 nodes resolved), `Batman Begins/mainView` (2 of 21), `Alienware Invader/mainView` (2 of 20) and `Cablemusic/mainview` (35 of 98). Take the top of `starved.tsv`, not the top of this row. **The AppKit half is cleared**: `ALXMorph/mainView` diffs to zero against its own hosted render (W71), so nothing here is an overlay defect and the whole of it is scene-side. **The expression-cascade theory is dead — measured 2026-09-08 and it was the probe.** `WMP_RENDER_EXPR` used to report 34,314 of 42,015 rows corpus-wide reaching no evaluator (82%), which was read here as the cause; 34,300 of those were **another view's** expression printed under this view's name, each already ordered and evaluated under its own view. With the probe scoped the way both evaluators are (`WMPHarness.expressionLines`), the corpus reads **7,569 / 7,569 reaching the live evaluator, zero unreached**, and `starved.tsv` does not move: 41 views / 36 skins, unchanged. Expressions are not what starves a view. All three named skins were opened and looked at: `Cablemusic/mainview` declares **no geometry expressions at all** yet carries 63 unresolved nodes and draws a nearly complete player; `ALXMorph/mainView` has 4 and all of them resolve live, and it draws its whole shell — so "does nothing" is interaction and animation (W38, W53/W54), not layout; `Alienware Invader/mainView` has 6 and all of them resolve live, and it is blank because `toggleShutter()` plays a **568-frame intro** off a 50 ms timer and only at frame 568 sets `mainBack.backgroundImage` and `mainBackGroup1.visible = true`. **Start from what `unresolved` actually counts, not from `EXPR`** — and note that a high ratio does not mean a blank view: two of the three worst-ranked views in `starved.tsv` render substantially. The evidence is `skills/wmp-skin-guide/reference/harness.md` § *After the cascade*. **W75 came out of it, was load-bearing here, and is now closed**: a script assignment to `backgroundImage` never reached the scene, which is exactly what Alienware's intro is made of — `Alienware Invader/mainView` now draws its full 406x380 player under `WMP_RENDER_SETTLE=32` instead of an empty PNG. Its `2 nodes / 0 hits` in the *default* state is unchanged and is not that defect: frame 0 of a 568-frame intro is still frame 0. The worst of the wider class are `digitaldj/DigitalDJ` (**91** unresolved against 101 nodes), `Cablemusic/mainview` (63 against 35), `WALL-E/mainView` (35 against 37) and `NVIDIA/mainView` (32 against 43); `Disney_Mix_Central`, `Batman Begins` and `Alienware Invader` all draw a `mainView` of 2 nodes and 0 hits. **W143 closed this family's other five windows and did not touch this row, which is the sharpest statement of what it is about.** Reported 2026-09-12 as "the playlist and eq windows are not properly contructed … there are large gaps": their nine-piece frames were collapsing both 175-wide side columns onto the corner bitmaps that carry the title bar, because `verticalAlignment="center"` was offset like a margin. Every `mainView` in the family is **byte-identical** across that fix — a non-resizable player authors no centred pieces — so `plView`/`eqView`/`visView`/`videoView`/`infoView` now draw their frames correctly while the player this row names is exactly as starved as it was. Do not read the family being "fixed" as this row moving; the dossier is `skills/wmp-skin-guide/reference/skins/alienmorph.md`. |
| W99 | A drawer's own toggle button drifts out from under the pointer once the view's timer runs | `xsn_sports` confirmed both live and headlessly; **every skin with a timer and a moved drawer is a candidate — count it** | Reported live 2026-09-09 as "it opens and closes right away, it is resistant to opening", and **reproduced against a baseline worktree at the parent commit, where it behaves identically** — so it is not W55, which only made it visible by correctly hiding a shut drawer's contents. `vidDrawerButton` in `xsn_sports/videoView` is drawn at `61,291` on the first frame and at `61,271` after `WMP_RENDER_SETTLE=2` runs the view's own 500 ms timer; a click at the first position returns `CLICK … MISS`, and a click at the settled one hits and opens the drawer to `4 widgets[slider×4]`. So the drawer works and the *target moves*. Twenty pixels, on a rebuild driven by a timer that only calls `htcpVid()` — which alpha-blends artwork and moves nothing — so find what re-resolves that subtree's geometry between ticks before assuming the handler did it. The old scripted-`view.height` theory is closed by W113; reproduce with `WMP_SKIN=…/xsn_sports.wmz WMP_RENDER_SETTLE=2 WMP_RENDER_PROBE=videoView`. |
| W152 | A skin's whole control strip takes no clicks until some *other* handler has run | `digitaldj/DigitalDJ` measured 2026-09-12 — `bgToggle` (3 mapping regions), `bgTransport` (5) and `bgFull`, which is the view's entire transport plus its mode switch; **unmeasured corpus-wide, and no existing instrument ranks it** | Found by the compact-mode audit: `digitaldj`'s Mini/Player-mode buttons are in `bgToggle`, and clicking any of them does nothing. **In the initial state every one of the strip's decoded mapping points misses** — `WMP_SKIN=…/digitaldj.wmz WMP_RENDER_CLICK='DigitalDJ@271.5,435.5;289.5,435.5;303.5,435.5;330.5,426.5'` is four `MISS` lines, and so is an 8-point spread across the rest of the view. Live it is the same and worse: pinned to the view with `defaults write NullPlayer wmpSkinViewID DigitalDJ`, a `CGEvent` click on the mini button and then on play leaves the window **byte-identical** — no hover, no down state, no action. **Then it starts working, and that is the whole of the row**: after the four `y=394.5` `<TEXT>` handlers have run, `DigitalDJ@330.5,426.5` hits `playElement#201`. Reproduce the flip with `WMP_RENDER_CLICK='DigitalDJ@210.5,394.5;290.5,394.5;330.5,394.5;410.5,394.5;330.5,426.5'`. **It is not a decode race and not a settle**: `WMP_RENDER_SETTLE=1` on the same click still misses, so a rebuild alone does not do it — it takes the overrides a handler committed. Find what those overrides move about `transport_sv` before theorising: it is authored `top="jscript:query_sv.height" left="255" width="jscript:view.width - left" height="jscript:view.height - 72" verticalAlignment="bottom"` and resolves to `255,386 385x386` — a box whose bottom edge is 314 px below a 458-tall canvas — while its children draw correctly at `262,426`. **`WMP_RENDER_OCCLUDED` cannot see this class and reports the view clean** (`recovered=0 lost=0 unreachable-either-way=4 of 92 hits`, none of them these): that probe enumerates targets that *have* a hit entry and asks who answers instead, so a control contributing **no hit entry at all** is invisible to it. W149 is the `rect-only` residue and this is the other half — do not fold them together. |
| W154 | `portals/mode1` draws a white slab over its transport and its controls drag the window instead of clicking | **1 view**, `portals/mode1`, opened 2026-09-13 by W153 closing; unmeasured against the rest of the corpus | **This view had never been on screen** — the walk opened `mode2` until W153 — so none of it has ever been looked at, and two things are wrong at once. **It draws a white rectangle at `13,236 280x140`**, which is exactly `cbuttons_play`'s frame: live, the group's `transparencyColor="#000000"` does not take and its five transport ovals sit on a white field, while the headless dump of the same view draws them on transparency. So this is live-only and the render dump is not the instrument — `WMP_RENDER_APPKIT` says `hosted=0/2 outside=0`, which clears the overlay class and leaves the group's own paint. **And a click inside that rect drags the window**: `mode1@259.5,259.5` resolves headlessly to `buttonElement#100` and posts `command=setCurrentView value=mode2` with nothing unrecognised, but live the same point leaves `wmpSkinViewID` on `mode1` and moves the window from `680,279` to `374,509`. The transport is in the same group, so this is play/pause too, not one button. Read the two together before splitting them: a group whose key failed live is a group whose mapping regions may not have reached the hit map either, which is **W152**'s subject on a different skin — and the magenta patch this view still carries at its top is a third (829 px, the residue the Tier 0 note calls resolved by W116). Reproduce live with `defaults write NullPlayer wmpSkinName portals` and a debug launch; headlessly with `WMP_SKIN=…/portals.wmz WMP_RENDER_DUMP=<dir> WMP_RENDER_APPKIT=1 WMP_RENDER_PROBE=mode1`. |
| W74 | A playlist overlay paints below the view it lives in | **2 views / 1 skin** (`Revert.wmz` and `Revert (1).wmz`, two releases of the same skin), the *only* two in the corpus, measured 2026-09-08 by `WMP_RENDER_APPKIT` over the 545 hosted views of the 179-archive sweep | 4,000 px at delta 196, in a 250x4 band at `3,256` of a 260-tall view. `ctrlPlaylist` is authored `3,14 250x257`, which ends at y=271 — eleven pixels past the view's own bottom edge — and `WMPMainView.layout()` positions the overlay from that frame without clipping it to `bounds`, so the `NSView` paints where the scene has nothing. **This is the whole W43 class in the corpus's default state**: 543 of the 545 hosted views agree with their scene exactly. Establish what WMP does with a control authored past its view's edge before choosing between clipping the overlay to `bounds` and clipping it to the widget's own `clipRect` — the scene already carries a `clipRect` the overlay ignores, which is the cheaper of the two and may be the correct one. Reproduce with `WMP_SKIN=…/Revert.wmz WMP_RENDER_APPKIT=1`, and `WMP_RENDER_APPKIT_DUMP=<dir>` to see both bitmaps. |

**The Phase 3 `corona` live-QA pair is closed and both are in the archive** (§ *Phase 13*). W43 —
the player going black while a track played — was fixed when the two overlay views were found
filling `dirtyRect` rather than `bounds`. W44 — four buttons in the top cluster all opening the file
dialog — was closed on the test the row itself nominated: `WMP_RENDER_CLICK="vPlayer@366,12;400,12;420,12;444,12"`
now resolves `bOpenFile`, `bPlaylist`, `bVis` and `bEq` distinctly with **`handlers=1` each**, and
only `bOpenFile` posts `openFileDialog`. That disproves the row's own suspicion of a `nil`
`targetID` fanning one click out across every `onClick` in the view: dispatch carries the exact
`targetStableID` from both the app and the harness, and an exact node beats an authored id.

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
| W73 | A clean sweep still proves only the default state | every skin | **The playback half is now instrumented, 2026-09-09**: `WMP_RENDER_HOST` seeds a playing host for a whole sweep (and `NULLPLAYER_PLAY` starts a live debug launch on a track), which is what found W119 and W120 — two defects in the one state every transport readout in the corpus is authored for and no capture here had ever entered. Read the `HOST` line of such a capture before anything else in it. Narrowed by W71 and W72, not closed by them. The AppKit *overlay* class is now measured — 545 hosted views, two defects, both in W74 — and every slider in the corpus is drivable. What no sweep here still says anything about: a tab, a setting, a **hover**, a drawer, the window's shape and its shadow (those live in the window server and stay a short, genuinely manual list), and anything driven by live playback. W69's flicker is in that remainder, which is why it needs its own instrumentation rather than another sweep. |

## Tier 1f — the residue of the starvation classes

**W112-W116 closed 2026-09-09 too**, from the second report on the same skin — a tween endpoint
readable by the handler that started it, a script that could not resize its own window, a `fontSize`
that never reached the drawing beside a baseline that sat above its own box, and two host members
that aborted the handler filling every readout, and a `BUTTONGROUP` painting its whole hover
sheet over the window. **Two of the four were reachable headlessly and two
were not**: no sweep here has a host snapshot, so nothing but `INPUT script-diag` in the running app
could see a `psPlaying` branch dying on its first statement. They are in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) § *Phase 14 (third
pass)*.

**W107-W110 closed 2026-09-09** and are in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) § *Phase 14*: an
unsized `<TEXT>`, an unsized `<BUTTONGROUP>`, a mapping-region `<…ELEMENT>` laid out as a control,
and half of WMP's transport vocabulary missing from `WMPElementKind`. Together they were **83% of
the corpus's 2,380 unresolved nodes**, and closing them took the corpus to **1,067** while adding
689 nodes, 611 paint commands, 253 hit targets and 609 widgets. The evidence, the sweep and the two
rules that came back narrower are in `skills/wmp-skin-guide/reference/harness.md` § *After the
starvation classes*. What is left of the class is one row.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W111 | Objects a skin declares inside `<PLAYER>` are laid out as controls, and count as starved | `<controls>` **103 nodes / 67 of 179 skins**, `<VIDEOSETTINGS>` 28 / 24, plus `durationText` 2 / 2 and `automenu` 4 / 3 as unknown tags, measured 2026-09-09 with `WMP_RENDER_UNRESOLVED=1` over the 179-archive sweep | **Costs no pixels and distorts the ranking**, which is the only reason it is a row: `starved.tsv` scores `unresolved / declared`, and ~154 of the 1,067 unresolved nodes left in the corpus are objects that were never boxes. `<controls>` is a child of `<PLAYER>` carrying nothing but `currentPosition_onchange` handlers — `aom.wms` is the worked case — and `WMPSceneBuilder.isNonLayout` already treats `.player` and `.network` exactly that way, so this is the same one-line rule applied to two more kinds. `STATUSTEXT` and `CURRENTPOSITIONTEXT` are no longer part of this row: both are implemented as native text controls. `durationText` and `automenu` remain separate questions and need a census before a kind: decide whether each is a `<TEXT>` WMP fills in for the skin (which is drawing work, not classification) or an object. Do **not** batch them with `<controls>`. |

## Tier 1e — a surface the skin owns and this engine does not host

Opened 2026-09-09 by W93, emptied the same day by W97, and **re-opened 2026-09-09 with four
surfaces in it**: playlist and equaliser were the two this engine hosted, and the corpus declares
six. W101 closed the same day and made the visualization surface the third, and **W102 closed
2026-09-10** making video the fourth — which is what unblocked W105's `.video` case, landed with it.
The tier's own rule is why the routing row (W105) sits *behind* the hosting rows rather than with
them — routing stands NullPlayer's own window aside on the strength of an authored tag, so a surface
recognised for *routing* and not hosted draws the user an empty drawer. Both W97 and W93 are in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) § *Phase 13* and
§ *Phase 11*; the rule is in `skills/wmp-skin-guide/reference/object-model.md` § *Playlist kinds*.

**What the corpus declares, measured 2026-09-09 over the 179 archives and 595 views** (`skins` is
skins declaring it anywhere; `own view` is skins that put it in a view other than the one they open
on). Reproduce the element counts with `scripts/wmp_markup_census.sh <outdir> EFFECTS WMPEFFECTS
VIDEO WMPVIDEO VIDEOSETTINGS NETWORK PLAYLIST EQUALIZERSETTINGS` — **never with an ad-hoc script
that decodes the `.wms` itself**, and `skills/wmp-skin-guide/reference/harness.md` § *Counting a tag
across the corpus* is the trap that rule exists for.

| Surface | views | skins | own view | Hosted today | Row |
|---|---:|---:|---:|---|---|
| `<VIDEO>` / `<WMPVIDEO>` | 268 | 170 | 165 | yes (W102) | — |
| `<EFFECTS>` / `<WMPEFFECTS>` | 178 | 171 | 144 | yes (W101) | — |
| `<PLAYLIST>` family | 175 | 170 | 162 | yes (W93, W97) | — |
| `<EQUALIZERSETTINGS>` | 170 | 163 | 147 | yes, as the skin's own bound sliders | — |
| `<VIDEOSETTINGS>` | 94 | 94 | 93 | no | **W103** |
| `<NETWORK>` | 6 | 4 | 4 | object-only, correctly | **W104** |

| ID | Item | Reach | Notes |
|---|---|---|---|

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
are the rest of those `onLoad` handlers running. The rows below are otherwise unmoved; the
scripted-size path it exposed later closed as W113.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W39 | `eq.speakerSize` | 18 skins | Plus `eq.enableSplineTension` and `eq.enhancedAudio` at 1 each. WMP's speaker/spatial settings; the engine has no equivalent, so this is an honest `inert()` candidate rather than a feature. |
| W40 | An element the skin names is in another view | 8 + 4 + 2 + 2 + 2 skins | `Can't find variable: vidinfo` (8, new behind W37), `Can't find variable: pl` (4), `playlistframe.setColumnResizeMode (no such element)` (2), `pl.setColumnWidth` (2), `vidZoom`/`videoWin` (2 each, also new behind W37). Handlers are now scoped per view, but a script's *globals* are the current view's elements only. Find out what WMP does with a cross-view reference before choosing. |
| W41 | `player.currentMedia.sourceURL` | 4 skins | Small and real. **`theme.closeView` was the other half of this row and closed 2026-09-11 with W141**; what is left is the source URL. |
| W42 | A skin function is missing because its program never registered | ~12 skins, 1–2 each | `skin_init`, `loadVidPrefs`, `UpdateMetaData`, `checkForContent`, `Init`, `gears`… Each is one skin's own function, so the cause is upstream: a `.js` that failed to resolve, evaluated with an error, or is a `res://` entry. Diagnose from `SCRIPT`/`SCRIPTS` lines before writing any object-model code. |
| W136 | SDK element methods this engine does not implement, now that they are tallied at all (W128) | `plListBox1/2.deleteAll()` **10 skins** (7 of them visible to the census), `playlist2.copy()` 8, `playlist2.abortCopy()` 8, `playlist1.deleteSelected()` 5, `fileList.insertItem()` 3. `view.returnToMediaCenter()` was tracked separately as W100 and is **closed 2026-09-13**, so it has left this tally — its census-visible 7 against a true 162 skins is the sharpest measure of this row's blind spot: the sweep drives `onLoad` and these names sit in `onClick` | **Opened 2026-09-11 by W128 closing**, which is the row's whole purpose: these were counted `INERT` — Tier 2b, the tier you do not take runtime work from — and are now `UNRECOGNISED` where they belong. Reproduce with `scripts/wmp_skin_census.sh /tmp/wmp/census` and tally `UNRECOGNISED` in `render.txt` by name and by containing `SKIN` block. **The census sees only `deleteAll`**: the others sit in click handlers and the headless sweep drives `onLoad`, so measure the rest through the live loop or a click-driving sweep before ranking them against each other. Every one of the `deleteAll` calls is inside the skin's own `try`/`catch` (`fillListBox()`, `warcraft.js:1584`), so implementing it changes a screen only in company with W66 — the box has nothing to put in it until `player.mediaCollection` answers. Take W66's media-collection decision first; this row is what that decision would let the skins actually do. |

### 2c. Events the markup declares and nothing ever raises

`WMPAttributeValue.handlerNames` decides what becomes a `.handler` at all, and
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

**W55 closed 2026-09-09 and took 438 of those uses with it** — `onEndMove` 247, `onDragEnd` 141,
`onEndAlphaBlend` 50 — so the 4,114 above is stale by that much and the rows below are otherwise
unmoved. It also settled the shape of a *negative* answer: `onEndResize` is **zero uses corpus-wide**
and was deliberately left unimplemented rather than added for symmetry.

An entry here is markup asking for something. Two things make it work: classification (one line) and
a dispatch site (the real cost, and different per event). Do not add a name to `handlerNames` or
`supportedEvents` without its dispatch site — a recognised event nothing raises drops out of this
table while still doing nothing, which is exactly the state `onResize` was in.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W53 | Keyboard events (now reachable: the window could not take the keyboard at all until W79) | `onkeydown` 501/78, `onkeypress` 409/72, `onkeyup` 94/30 | `WMPMainView.keyDown` handles focus traversal and activation and raises no authored handler. Needs a key-code/character contract at the object-model boundary — decide what a skin may see of a keystroke before implementing. |
| W121 | A handler that reads the `event` object | **30 handlers across the Skins Factory equaliser family**, measured 2026-09-09 as `value_onchange: ReferenceError: Can't find variable: event`; unmeasured for the other event kinds | Surfaced by W51 rather than caused by it: those handlers had never run at all before the host-driven direction was raised. `value_onchange="toolTip = Math.round(value); if (!event.shiftKey) eq.gainLevel9 = value;"` is the shape — an equaliser band that skips its write while shift is held, which is how that family links its ten bands — and the same gap applies to the user-driven direction and to `onkeydown`/`onkeypress`, where W53 already needs a key. WMP binds one `event` object per handler with the modifier and key state on it. Bind it the way `WMPScriptContext` already binds the bare `value` and an event's named arguments: for the duration of that one handler, then cleared, so a stale one cannot be read by an unrelated later handler. Count the whole class first — sweep the corpus's handler attributes for `event.` and split by event kind, since the modifier state a mouse handler wants and the `keyCode` a key handler wants come from different places. |
| W56 | Video and playback-position events | `onvideostart` 190/140, `onvideoend` 132/130, `onpositionchange` 147/41, `currentposition_onchange` 103/80 | **`currentposition_onchange` closed with W129** (amended 2026-09-11): it was one instance of the general `<attribute>_onchange` mechanism, and it is now raised from the host snapshot diff. It changed no pixel and that is the measured finding, not a disappointment — 96 of its 105 uses are `seek.value = player.controls.currentPosition`, and **W120 already supplies that number** from the slider's declared range. Do not re-open it as a rendering row. W102 supplies the hosted video surface and W124 supplies the live/event-state split, so the remaining `onvideostart`/`onvideoend` half is directly measurable rather than blocked. |

### 2c-note. Verified **not** gaps — do not open a row for these

The SDK conformance audit (2026-09-11) disproved nine candidate gaps, and **that is the more valuable
half of it**: each is a plausible-looking gap that would otherwise cost a session to chase. Check
this list before opening a row that came from reading the SDK against a corpus scan.

* **`onresize` is dispatched.** `WMPMainWindowController.swift:1162` builds the event as `"resize"`;
  handler names are stored with the `on` prefix stripped, so grepping the sources for `onresize`
  finds only the census table. 47 uses / 19 skins already work.
* **`nineGridMargins`, `resizeImages`, `elementType`, `bottom`, `right`, `accDescription`** — ambient
  attributes with **zero corpus uses**. Absent from the engine and correctly so.
* **`moveSizeTo` and `slideTo`** — ambient methods, **zero calls** corpus-wide. (`resizeTo` is also
  zero and is implemented anyway.) All three are in the vocabulary after W128, which costs nothing:
  the vocabulary is the SDK's list, not a demand tally.
* **`<COLUMN>`, `<ITEM>`, `<SETTINGS>`** — SDK elements with zero corpus uses.
* **`eq.reset()` / `eq.nextPreset()` / `eq.previousPreset()`** — 104 / 91 / 87 skins, and all three
  are implemented (`WMPObjectModel.swift:811-817`). A naive receiver-filtered scan reports them as
  missing; they are not.
* **`scrollingAmmount` / `scrolingDelay` (25 skins, 54 uses), `horizontalAlignemnt` (3), `donwImage`,
  `tootip`, `hegiht`, `visilble`** — **author typos**, copy-pasted across the Plus! family. WMP
  ignores an unknown attribute too, so matching them would be *less* faithful, not more. This is the
  largest single false lead in the whole scan.
* **`transparencyColor="white"` / `clippingColor="white"` (10 / 7 skins)** — feared to be losing the
  declared key to the implicit magenta default. Traced: `colors(_:names:)`
  (`WMPSceneBuilder.swift:820`) delegates to the name-aware `color(_:names:)`, so `declared` is
  non-empty and `implicitColorKey` stays nil (`WMPSceneBuilder.swift:761`). Correct today.
* **`mediacenter.effectType` read as a property (376 uses / 192 files / 130 archives)** — checked while landing W128
  because `effectType` is an SDK `EFFECTS` *method* and the vocabulary gates reads. Every use is on
  the `mediacenter` host receiver, answered by `readMediaCenter` before the element path. Not a gap
  and not a regression risk.
* **`<CONTROLS>` (77 skins), `<VIDEOSETTINGS>` (84), `windowed` (114), `allowAll`,
  `dropDownVisible` (114)** — real gaps, but already tracked as W111, W103, and the documented
  `object-model.md` refusals. Not re-opened.

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
| W123 | A stretched `backgroundImage` and a natural-size foreground image draw the same bitmap at two different sizes | **1 view measured** (`Ice/videoView`) out of the 545-image corpus capture; the wider class is every `backgroundImage` whose frame is not its bitmap, unmeasured. Reproduce with `WMP_SKIN=…/Ice.wmz WMP_RENDER_PROBE=videoView` | **Opened 2026-09-09 by W122 closing.** `Ice` authors `<button image="Pl-xp.bmp" width="196" height="144">` over a bitmap that is really 196x**44**, inside `<subview id="Drawerbutton2" backgroundimage="Pl-xp.bmp" width="313" height="144">`. Both were stretched and therefore agreed; the button is now drawn at its own 196x44 and a seam appears in the lower shell. The question this row exists to settle is **what WMP does with a background whose frame is not its bitmap**, and it cannot be answered by extending W122: `Ice`'s own frame tiles all author `backgroundtiled="true"`, which suggests WMP does not stretch and a skin tiles deliberately — but `Vidcolorbox` is `horizontalAlignment="stretch" verticalAlignment="stretch"` with an untiled `Vid-bg.bmp`, and `LostPlanet`'s stretch tiles are 61 px of window frame that would punch through. Measure the class before changing the rule, and check `reference/skins/README.md`'s counter-evidence table first. |
| W132 | `hoverDownImage` is never selected | **126 nodes across 62 skins** (`BUTTON` 86, `BUTTONGROUP` 38, `MUTEBUTTON` 2) | `button-element`: "the image displayed when the **BUTTON** is in the down state and the user hovers over it with the mouse pointer." `WMPSceneBuilder.swift:490-493` resolves `.down` to `["downImage", "image"]` and never consults `hoverDownImage`. **Deliberately ranked low: every one of the 126 nodes also authors `downImage`** (checked, zero exceptions), so the fallback is the correct down artwork missing only its hover lighting — cosmetic. It is here rather than dropped because the sticky case is the one a user looks at for seconds at a time: repeat/shuffle/mute left toggled on. **The fix is not just a name.** `WMPInteractionState.swift:63` collapses a pressed node and a sticky-down node into the same `.down`, so this needs a distinct hover-down face in the state machine before the attribute has anywhere to go. **Needs the live loop** for the same reason as W131. |
| W133 | Hosted `PLAYLIST` chrome attributes are unread | `columnsVisible="true"` **74 skins** (with `columns` in 131), `toolbarVisible="true"` 12, `leftStatus`/`rightStatus` 27, `dropDownImage`/`dropDownBackgroundImage` 27/25, `toolbarMargin` 14, `disabledItemColor` 74 | `playlist-element` defines 37 attributes; the engine reads background/foreground/itemPlaying colours via `WMPSurfacePalette` and nothing else. **Verification halves this row, and that is most of its value**: the corpus mostly authors values that *agree* with what the overlay already does — `playlistItemsVisible="false"` is 3 skins against 117 authoring `"true"`, `moveButtonsVisible` is `"false"` in all 57 skins that author it, `checkboxesVisible` is `"false"` in 24 of 32. The reach column above is only what genuinely differs, and `disabledItemColor`'s 74 have no meaning here at all — there are no disabled tracks. The substance is column headers, which the overlay draws none of. **`dropDownVisible="true"` (114 skins) is explicitly not part of this row**: it is a documented deliberate refusal in `object-model.md` pending W66. |
| W135 | Small, real, individually cheap — the SDK audit's S4 table as one row | Per item below, measured 2026-09-11 over the 177 archives | Kept as one row because each item is an `inert()` or a read-through of a few lines, and splitting them would rank nine one-line changes above work that moves a screen. `<AUTOMENU>` (own element, **4 skins**) — the Quick Access Panel, no counterpart here, so `inert` rather than `unknown`. `authorVersion` on `THEME` (16) — metadata the skin chooser could show. `toolbarMargin` on `PLAYLIST` (14) — rides with W133. `scrollingDirection` on `TEXT` (13) — the marquee axis; W94 implemented one direction. `wordWrap` on `TEXT` (10) — W94 deliberately left the vertical clip open, so decide these two together. `effectCanGoFullScreen` on `EFFECTS` (10) — no full screen for the hosted rect, `inert`. `fontWeight` on `TEXT` (10) — the engine reads `fontStyle` only. `textLimit` and `editStyle` on `EDITBOX` (8 each) — one EDITBOX use case in the corpus, `plSearchEdit`. `showBackground` on `EFFECTS` (7) — interacts with W101's "do not fill the widget's rectangle". |
| W145 | A borrowed window frame is rendered from markup, so it never follows the theme the skin is *set* to | **xsn_sports** measured 2026-09-12; the pattern is stacked variants, unmeasured across the corpus | `WMPHostedFrameTemplate` lends NullPlayer's own windows the skin's eight-piece ring (86 of 180 archives declare one), built through `WMPSceneBuilder` from markup alone. A skin whose colour scheme is a *script* decision therefore always gets its opening one. `xsn_sports` stacks all eight frame variants in `plView` (`pl1_1`…`pl1_8`, 2-8 at `alphaBlend="0"`) and cross-fades between them from `htcpStartupPl()`, reading the `htcpID`/`winAlpha` preferences in the view's own `onLoad` — "Hyper-Transient Color Phasing", per the notice in `xsn.js`. Reported as "the NullPlayer window does not follow the colour theme selected in xsn". **The fix is to run the donor view's `load` off-screen** (`WMPScriptRuntime.transact`, whose overrides `dispatch` deliberately discards) and build the ring with the overrides it commits, re-running when the skin's preferences change; the template must then keep *every* candidate per ring role rather than the first declaration. It settles on the chosen colour and does not animate the phase — running a closed window's timer to match a cross-fade is out of proportion to what it buys. |
| W67 | `.cur` and `.ani` cursors | **~70 uses**, a handful of skins (`resize.cur` 26, `over.ani` 23, `sizetopright.cur` 12, `size2_m.cur` 6) | The remainder after the named cursors landed: Windows cursor formats, which no macOS decoder reads. They resolve to no cursor rather than to a wrong one. Worth doing only with a `.cur`/`.ani` decoder, and worth almost nothing without one. |


| W149 | Controls still unreachable after W148, each for a different reason | `Sports` 7, `anime`, `STALKER`, `T3-Skynet_Media_Player`, `Plus! Professional` (container) — **11 total**, re-measured 2026-09-12 after W150 (was 16; `Gold`'s five containers and four others were the position-map half) | **Opened by W148 closing**, and it is the residue that rule does not explain rather than a regression from it: reproduce with `WMP_SKIN=<corpus> WMP_RENDER_HOST=playing WMP_RENDER_OCCLUDED=1` and read the `reached=rect-only` lines. **10 of the 16 are `<BUTTONGROUP>` *containers* with no mapping children** (`Gold`'s five stacked `drawerButton*` at one 144x123 rect, `The_Doobie_Brothers`, `Plus! SlimLine`, `Plus! Professional`), and a group with no `<BUTTONELEMENT>` dispatches nothing however it is ranked — **decide whether those should be hit targets at all before counting them as work**. The six that are real: `Sports`'s `eq2`–`eq8` sliders answer to `pl2`/`pl3`/`pl4` `<TEXT>` nodes drawn over them, which is the same question in reverse (a `<TEXT>` keeps its box because glyphs are not a hit shape — see `WMPHitCoverageBuilder`), and that skin trades 7 sliders for the 3 texts it gained; `anime`'s `plHandle` answers to `closepl`; `STALKER`'s `blankRate4` to a plain `<BUTTON>` while its other four stars work; `T3-Skynet_Media_Player`'s `timeSign` is authored at `x=-25` and is mostly off its own canvas. **Name the node before ranking the count** — the same rule `../harness.md` states for `unresolved`. |

## Closed

Closed entries live in [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md),
verbatim and with their evidence. Move a row there in the same change that closes it — one left here
reads as open work.
