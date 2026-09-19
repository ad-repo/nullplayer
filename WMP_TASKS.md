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

**A row with a defect in the *row* goes to [`LOW_QUALITY_TASKS.md`](LOW_QUALITY_TASKS.md), which is
neither the archive nor a rejection of the work.** Six went there on 2026-09-19 in a single audit —
W68, W239, W73, W111, W135 and W67 — for being stale past the point of trust, not a unit of work,
stripped of their own stated justification, a bundle assembled to game the ranking, or
self-described as not worth doing. **Two of them left real work behind and it is ranked here**:
W242 is what W68's evidence actually supported, and W241 is what the audit found under the top of
`starved.tsv` once the phantoms were cleared. Check that file before re-opening any number, and
re-measure before reviving anything from it.

**Every table on this page is in rank order, top down, and the tiers themselves are ranked by the
order they appear.** Take the first row of the highest tier that is not blocked. A row whose Reach is
explicitly *unmeasured* is placed provisionally and says so in its own Notes; measure it before
letting it outrank a measured row.

## Ranking

### How a row is ranked

Reach is corpus demand across the 14-skin corpus installed in
`~/Library/Application Support/NullPlayer/WMPSkins/`, not severity. Every Reach number must be
reproducible by a command recorded next to it.

**Two numbers on this page are now produced by the census itself rather than by hand, and the file
it writes them to outranks any row here that disagrees.** `starved.tsv` ranks every view by
`unresolved / declared` (W70) and `appkit.tsv` ranks every hosted view by how much an AppKit overlay
painted outside any widget frame (W71). Take work from the top of those, not from the top of a
paragraph. Measured 2026-09-08 over 179 archives and **607 views**: 41 starved views across 36 skins,
79 with no hit target across 49, 75 drawing nothing across 45, and **two** views painting outside a
widget frame. **That last number is now zero** — both were `Revert`, both closed 2026-09-19 as W74,
re-measured over 184 archives / 629 views. `appkit.tsv` ranks nothing until a new archive lands.

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
declares none at all — see W241/W242 and `skills/wmp-skin-guide/reference/harness.md` § *After the
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

**A third collision was found 2026-09-19 and needs no renumber: `WMPMainView.swift` and
`WMPMainWindowController.swift` stamp `W235` on the AppKit edge-wedge work of commit `f5552068`,
which is not the (now closed) W235 in the archive. Those comments mean that defect.**

**Two IDs were issued twice by different sessions, and the open halves were renumbered 2026-09-17.**
The `.wmz` placement/recovery audit moved **W196 → W217** and the `Colorchooser` transport row moved
**W171 → W218**; the archived, *closed* W196 (a view's resize limits read from markup only) and W171
(a `clippingImage` with no `clippingColor`) keep their numbers, and every reference in
`Sources/`, `Tests/` and `skills/` to those two numbers means the closed rows. Check
`docs/wmp-skin/wmp-backlog-archive.md` before reusing any number: the next free one is **W243** — the note that said W237 was written before another session issued and closed **W238**, and W237/W239 were opened 2026-09-19 (**W237 closed 2026-09-19**)
(W211 was never issued; W219-W224 were opened and closed the same day, 2026-09-17, and W225, W226,
W228 and W232-W233 on 2026-09-18, and all are archived; W236 was opened 2026-09-19 out of W195's
closure). **W99 closed 2026-09-19** — a view resolved against a size nothing is drawn at, which is
also part of the answer to what was W68 (moved 2026-09-19; see `LOW_QUALITY_TASKS.md`); see the
archive before taking any row whose evidence is a frame
measured before that date. **W179 closed 2026-09-19** and issued no new number: the donor a skin
lends is now chosen per view rather than by document order, and the three symptoms the row was named
for had already been closed by the hosted-frame work that landed after its report.

The corpus grew from 14 archives to 180 on 2026-09-07, so **every number taken against the 14-skin
denominator is stale and none of them were rewritten in place.** A count here without the 180-archive
stamp has not been re-measured; re-measure it rather than scaling it. Two byte-identical archives were
deleted; five *name*-similar pairs (`Ginger Man`/`Ginger_man`, `QuickSilver`/`(2)`, `Revert`/`(1)`,
`Project Gotham Racing 2`/`(1)`, `The Unit`/`TheUnit`) are different releases of the same skin with
differing `.wms` and `.js`, and are kept deliberately as separate test cases.

## Tier 1 — views that load and then draw nothing

**Empty, and both halves of it are closed.** Tier 1a held the loading rejections (W33 closed the
last); no view in the corpus fails to lay out (W6, W8). Nothing comes back here unless a *new*
archive is rejected or a view starts drawing nothing — which is indistinguishable from a rejection
to anyone using the app, and is why the tier stays.

## Tier 1c — live-reported, not yet reproduced headlessly

**The 2026-09-08 live-QA list was never captured, and that is still the largest known hole on this
page.** The reporter drove Phase 5, reported "tons of issues", and the session ended before the list
was written down — so no count here includes them and every Phase 5 closure in the archive is
*harness-verified only*. Phase 6 narrowed it without recovering it: 545 of 607 views were hosted
through the real `NSView` stack and **exactly two** paint where the scene does not (both W74, closed
2026-09-19 — the corpus now reads `outside=0` everywhere), so
whatever was seen is mostly scene-side starvation (now W241/W242; W68 ranked this automatically by
`starved.tsv` and was moved to `LOW_QUALITY_TASKS.md` on 2026-09-19 when its numbers proved false)
or driven by a hover, a timer or live playback, which no headless instrument here reaches — the
caveat W73 carried, now prose in `harness.md` § *The probe flags*. `corona` is the
control from that session — "all its sliders and buttons for the most part" — and is why the rest
read as defects rather than as the engine being broken. **Capture a reporter's list before ranking
further Phase 5 work.**

**Build a baseline worktree at the parent commit before attributing a live report to the change in
front of you.** Three reports on 2026-09-09 were assumed to be W55's and behaved identically at the
parent; it cost one build and moved all three out of that change's ledger.

**A NullPlayer surface wearing a borrowed `.wmz` ring is not the scene.** W177-W179 were reported
together on 2026-09-15 and **all three are now closed** — W179 on 2026-09-19. None of them was
reachable from `WMP_RENDER_APPKIT`, which measures a skin's *own* views against their scene; W179's
evidence was a `WMP_HOSTED_FRAME` line, a `WMP_HOSTED_FRAME_DUMP` PNG and a capture of the live
library window, in that order. **Two of W179's lessons outlived it and are in the skill**: the ring
a window wears is chosen per *view*, so a defect in the bottom bar can be a defect in donor
selection two steps upstream; and a row's own starting instruction can be stale — W179's named the
client hole, which was already correct. Re-drive a screen-only row before taking it.

**W68 was this tier's only row and was moved to [`LOW_QUALITY_TASKS.md`](LOW_QUALITY_TASKS.md) on
2026-09-19.** Its central number was false — it quoted `ALXMorph/mainView` at 15 unresolved against
15 nodes, and the view carries **3**, all of them in classes since proven phantom (W111, W231,
W232). Twelve of the fifteen were string-table text. **Do not re-derive anything from that row's
figures**; what survived it is W242 below.

Rows are in rank order, top down.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W242 | `ALXMorph/mainView` draws its whole shell and offers **5 hit targets** | 6 skins in the Alienware/ALX family; `ALXMorph`, `AlienMorph`, `AlienwareTeleport` measured 2026-09-19, the rest unmeasured | **All that survives of W68, restated as the question its own evidence supports.** That row argued from a starvation number that has since evaporated (15 unresolved → 3, all phantom), but the observation underneath it was never disproved: the view a skin *opens on* dispatches five hit targets where its `eqView` dispatches 24, and the family was live-reported as "ALXMorph does nothing — no animation and nothing reacts". **Ask it as a hits question, not an unresolved one** — the nodes resolve, the commands draw (7 of them), and the shell is on screen, so whatever is missing is hit construction or occlusion, not layout. `WMP_RENDER_OCCLUDED=1` is the instrument W149 uses for exactly this and it has never been pointed at this family; check it before opening the markup. The animation half of W68 is **closed** (W38, W75, W76) and the AppKit half is **cleared** (W71) — do not re-open either. Dossier: `skills/wmp-skin-guide/reference/skins/alienmorph.md`. |

## Tier 1d — what the Phase 6 instruments do and do not reach

**Manual testing does not scale to this corpus** — 179 skins times sliders, drawers, drags and
animation is not a human-scale job, and Phase 5 shipped its AppKit half unmeasured for that reason.
One row is what is left of that gap; the other is about the instruments themselves, which belongs
here because a probe that reports work already done is a gap in reach exactly as a missing probe is.
**W215 ranked first here because it corrupted the ranking inputs every other tier is taken from,
and it closed 2026-09-19: the corpus's unimplemented-tag demand was 1,197 uses and is 258. Re-read
any row below whose Reach is a `COMPAT`/`UNKNOWN tag` number taken before that date — it is not
merely stale, it is inflated, and the tags it inflated with were the transport pairs, `customslider`
and `effects`. The member half of that row did not close and is the larger number now: see the
archive.**

**Empty as of 2026-09-19.** Both rows moved to [`LOW_QUALITY_TASKS.md`](LOW_QUALITY_TASKS.md):
W239 measured the instrument rather than the app and was half-withdrawn on the day it opened, and
W73 was a standing caveat about instrument reach that could never be closed. **The caveat is still
true and still matters** — a clean sweep proves only the default state, and a tab, a hover, a
drawer, the window's shape and anything driven by live playback remain outside every headless
instrument here. It is prose in `skills/wmp-skin-guide/reference/harness.md`, which is where a
reader meets it before trusting a capture. The tier stays because a genuine gap in instrument reach
still ranks above a skin-side defect when one is found.

## Tier 1f — the residue of the starvation classes

| ID | Item | Reach | Notes |
|---|---|---|---|
| W241 | **An attribute authored with an empty value is dropped, and it is taking whole control groups with it** | **21 nodes across 4 archives** (`Beck` 11, `Revert` and `Revert (1)` 8 each, `STALKER` 1, `WWC` 1), measured 2026-09-19 over 185 archives; the corpus-wide count of `<attr>=""` in markup is **unmeasured and is the first thing to take** | Not blocked. Count `=""` across the corpus's markup with a decoder-faithful scan, then decide what WMP does with one; take it together with W240, and verify on `Beck`. Evidence: `harness.md` § *The empty-value class, and why a coercion to zero is not the fix*. |
| W240 | **An unresolved node that carries a bitmap takes zero instead of the image's size** | **7 `<SUBVIEW>` nodes across 6 archives**, inside a wider class of **33 of the corpus's 458 unresolved nodes** that carry a bitmap, measured 2026-09-19 over 185 archives with the W231-extended `WMP_RENDER_UNRESOLVED` | Not blocked. Count the 33 first, then settle the rule together with W123 — `Radio` is in both. Not a one-line fallback, and `jsa:` is not part of it and must not be implemented. Evidence: `harness.md` § *After the subview class*. |
| W236 | **Two ids are read as a `fontFace` and a `scrollingDirection`, and answering them with the empty string is not the same as answering them** | **12 uses / 2 ids across 2 archives** (`Revert`, `Revert (1)`), measured 2026-09-19 by the W195 census | Found while closing W195, not from a report. `netgen.wms` sets `fontFace="res://-/RT_STRING/#1888"` on all three metadata readouts and `scrollingDirection="jscript:theme.loadString('res://wmploc/RT_STRING/#1910');"` beside them. These are **localisation plumbing, not labels** — `wmploc.dll` holds the font family and the scroll direction for the shipping language, which is how one markup file serves an RTL locale. `WMPResourceStrings` correctly declines to invent a label for them, but the value that reaches the scene is `""`, and a font face and a scroll direction are attributes with real defaults rather than text that can be absent. **Nobody has looked at what the scene does with an empty `fontFace`**, which is the first thing to measure: if it falls back to the view font this costs nothing and the row closes as a note, and if it does not, three readouts on both `Revert` releases are drawing in the wrong face. Not a W195 defect — that row is about text a user reads. |

## Tier 1g — the window system, not the scene

Opened 2026-09-16 by an audit of `.wmz` window placement against the `.wal` rules. **The tier exists
because every other tier on this page ranks a skin's own drawing, and nothing here is about a skin at
all.** A row lands in Tier 1g when the defect is in `App/WindowManager.swift` or
`App/AppStateManager.swift` — where a window is placed, restored, rescued and reset — and would
reproduce identically on a skin that renders perfectly. Tier 1e is its nearest neighbour and is
deliberately separate: that tier is about *which* window a surface belongs in, this one is about
*where the window is*.

Three consequences follow from that, and they are why these rows do not rank against a starved view:

**And one lesson the tier's first closed step taught, which is why the tier is ranked where it is:**
a row here names the seam an audit found, and the seam the *user* hits may be a different one in the
same family. W217's G4 was written against Snap To Default; the defect reported from the running app
was `positionSubWindow`, four lines away and never audited, and no amount of reading found it — the
app was launched, ten windows were opened and their frames were read back. Measure the moment the
user described, not only the seam the row names.

- **Reach is not a corpus number.** A gate on `uiMode.controllerFamily` affects every `.wmz` session
  equally, so `scripts/wmp_skin_census.sh` says nothing about it and a Reach column quoting archives
  would be measuring the wrong thing. Both rows below reach every `.wmz` session; they are ranked
  against each other by what a user can do about the result, and a stranded borderless window has no
  route back at all.
- **No headless instrument reaches it.** `WMP_PLACE_TRACE` sees the one moment a window is *placed*;
  a render dump has no screen, no second display and no restore. Every row here is verified by
  driving the app — `skills/live-ui-testing`, and `reference/harness.md` § *Debugging a live defect*.
- **The blast radius is the other three families.** These seams are shared code, so the binding rule
  in `CLAUDE.md` applies at its strictest: a change here is gated on the mode, never justified as a
  no-op, and Classic and Original must come out byte-identical.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W217 | `.wmz` shares the `.wal` *placement* seams but none of its *recovery* seams, so a stranded WMP window has no route back | **every `.wmz` session**; the gaps are structural, not per-skin (code audit 2026-09-16, no corpus sweep needed) | **G4 closed 2026-09-18. Three gaps remain, and the audit's step 2 takes G2 and G3 together.** (G1) `WMPWindowRestorePolicy.safeFrame` (`WMPMainWindowController.swift:2621`) is a second, weaker definition of "on screen" — an 80pt strip and a 24pt bottom margin rather than `WindowPlacement`'s top-left-corner rule. (G2) `correctedRestoredFrames` is gated `appliesWinampModernPlacement` (`AppStateManager.swift:955`), so WMP gets neither the whole-session group offset nor the `savedScreenIsMissing` force. (G3) `ensureAllWindowsOnScreen()` returns early in WMP and all six call sites re-guard, so a display or resolution change strands WMP windows **permanently**. First step: read `~/.claude/plans/wmp-window-placement-compliance.md` — the rule-by-rule table, the line numbers and the four-step plan. **Verify live** (`WMP_PLACE_TRACE=1`, `Halo 2` as the load case, `Corona` as the control), reading frames back through `app-control`'s `winhelper windows`; Classic and Original must be byte-identical. Evidence: `SKILL.md` § *Window placement and recovery*. |
| W214 | **`isRunningModernUI` is a two-way switch in a four-family world, so every `!isRunningModernUI` branch treats a `.wmz` window as Classic** | 4 sites, every `.wmz` session (code audit 2026-09-17; no corpus sweep can see this) | **This is W217's G4 generalized, and one instance of it has already cost a full live-QA cycle.** `WindowManager.isRunningModernUI` answers `false` for `WMPMainWindowController` by construction (`WindowManager.swift:388`), so a guard written to mean *"Classic, not Modern"* silently admits WMP and `.wal` too. `tightenClassicCenterStackIfNeeded` was one such branch: it grew `circle`'s 192x82 borderless player to `Skin.mainWindowSize.height` on the mouse-up of the first click, and **closed with W213** by gating on `isRunningWMPUI`. The remaining four, in the order they are worth taking: (1) **`handleCenterStackWindowWillClose`** (`:2036`) slides windows and re-docks children on Classic geometry, and is reachable in WMP mode because our fallback EQ/playlist/spectrum windows do open there — **confirmed live by W237**, which closed 2026-09-19 by gating the library resize it reached through `updateDockedChildWindows`; the slide and the re-dock it also performs are still ungated, so this stays open; (2) **`normalizedCenterStackRestoredFrame`** (`:5501`) rewrites restored PeppyMeter and NetworkMonitor heights by Classic rules — *exactly* the windows that wear a skin's borrowed frame in WMP mode, and `HostedWindowBorderLayout` already records an analyser coming back `387x219` where its siblings came back `321x145`, so these two rules may already be fighting; (3) `applyClassicVisualizationDefaults` (`:4610`) writes Classic visualization defaults during a WMP session; (4) `expectedMainHeightForCurrentHT` (`:5534`). **Do not gate them in one sweep.** Each is a shared-`App/` path and CLAUDE.md's rule binds: gate on the mode, prove Classic and Original are byte-identical, and measure each separately — (2) in particular needs `WMP_BORDER_TRACE=1` beside it, because whichever of the two rules currently wins is load-bearing for someone. Verify with `WMP_SIZE_TRACE=1` (its `MISMATCH` line fires exactly when a window is about to be forced off its own scene) and `WMP_PLACE_TRACE=1`. |

## Tier 1h — the borrowed window frame

**Reopened 2026-09-18 by W230 and still open for W234.** W230 was the first row here about *when* the
donor's pixels arrive rather than what they are; it closed 2026-09-19 and left W238 behind it — the
same seam once more than one window is open — which closed the same day. Both are in the archive,
and W238 is where the rule that measuring a hosted window must not move it or cost a render was
established. W207 closed the frame's geometry, W208 its slot rules, and W209,
W210 and W212 closed the pixels: the borrowed frame is the donor view drawn whole with the skin's
own content subtracted, a donor's furniture is told from its border by the order it paints them,
and a rack is reclaimed only as far as the donor leaves it unpainted. All of them are in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md); the rules are in
`skills/wmp-skin-guide/SKILL.md` § *Every NullPlayer window in WMP mode is the skin's or is themed*,
and the case studies in
[`back-to-the-future-trilogy.md`](skills/wmp-skin-guide/reference/skins/back-to-the-future-trilogy.md)
and [`alienware-invader.md`](skills/wmp-skin-guide/reference/skins/alienware-invader.md).

| ID | Item | Reach | Notes |
|---|---|---|---|
| W234 | **Broken borders and content in the wrong rectangle, on every hosted window at once, while the skin's own window is right** | unmeasured — reported 2026-09-18 as the standing condition of the hosted windows, not as one skin's defect; the population is every hosted window under a skin that lends a frame, ~120 of 185 archives (88 rings + 32 panels, W207's measurement) | **The reporter's framing is the finding: "the main windows are fine, it is all the other windows", "broken borders, misplaced center data", "all the same UI look over and over."** Ten windows failing the same way against a player view that never does is one contract unhonoured at ten call sites, not ten defects. Not blocked; W230 was the same seam at first open and may share a cause. First step is one capture, not a matrix: read `WMP_HOSTED_FRAME_DUMP` against the live window on one skin the reporter names. Evidence: `SKILL.md` § *Triage a hosted-window defect before choosing a seam* and § *Evidence proportional to a hosted-window change*. |

A new row belongs here when it is about the pixels a donor lends and how they compose against
NullPlayer's own content — not about which window a surface lives in (Tier 1e) or where that window
is (Tier 1g). **Verify it by driving the app and capturing the live window**: a `HOSTED-FRAME` line
alone has twice measured clean while the window was visibly wrong (`back-to-the-future-trilogy.md`
§ *Process lessons this skin taught*). It ranks below Tier 1g and above Tier 1e.

## Tier 1e — a surface the skin owns and this engine does not host

The corpus declares six surfaces; four are hosted. The tier's rule is that **a surface recognised for
*routing* and not hosted draws the user an empty drawer**, so a hosting row always lands before the
routing that stands NullPlayer's own window aside. The playlist kinds rule is in
`skills/wmp-skin-guide/reference/object-model.md` § *Playlist kinds*.

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
| W103 | `<VIDEOSETTINGS>` binds 94 skins' sliders to controls this player does not have | **94 uses across 94 of 177 archives**, one per skin, 93 of them in a view of their own | The brightness / contrast / hue / saturation panel — and the tooltip vocabulary is unambiguous about what the sliders are (`brightness` 80, `hue` 80, `saturation` 79, `contrast` 78, plus `reset …` ×20 each across the corpus's `toolTip` attributes). NullPlayer's video path exposes none of the four, so **this is a decision, not drawing work**: either `inert()` — the trap `INERT` exists for — or add the four controls to the video path and bind them honestly. Do not resolve them to a value this player never applies; a slider that moves and changes nothing is the worse of the two outcomes. **Answerable since W102 landed**: the video path exists, so this is a decision about what to bind, not a question about whether there is anything to bind to. |
| W104 | `<NETWORK>` answers nothing, and Flow is not what it means | **6 uses across 4 of 177 archives**; the smallest surface in the corpus | `<NETWORK>` is an object, not a control — it authors no attributes at all in the whole corpus, so `WMPSceneBuilder.isNonLayout` treating it as non-layout is correct and stays. What a skin reads off it is stream state: `player.network.downloadProgress` and `player.network.bufferingProgress` already resolve in `WMPPropertyRegistry.swift:126`, and `bandwidth`, `receivedPackets` and `lostPackets` are the members behind the `network bandwidth` (12) and `buffering progress` (10) tooltips. **Feed it from the streaming player's own statistics, never from Flow**: `Windows/NetworkMonitor` measures *interface* throughput for the whole machine, which is a different quantity from this stream's bitrate and buffer, and wiring one to the other would draw a confident wrong number. Flow is still the right *window* for it — 4 skins declare a network view and nothing else in this app claims that menu slot — but the object and the window are two separate answers. |


## Tier 2 — the script runtime, after Phase 3

The runtime is one persistent `JSContext` per skin session with a native Swift object model
(`skills/wmp-skin-guide/reference/object-model.md`). **Everything below is re-measured at rev
`c8a843e4` over the 180-archive corpus**, with the harness now driving each view's own `onLoad` the
way the app does. Reproduce with `scripts/wmp_skin_census.sh /tmp/wmp/census` and rank the
`SCRIPT-DIAG [handler-error]` lines in `render.txt`; the pre-Phase-3 table that stood here was
measured against a runtime that could not run a handler to its second statement, and every number in
it is void.

Rows are in rank order, top down.

Corpus effect of the change: **228 handler errors remain, from a state where Corona's `OnLoad` could
not reach its second line**; expressions are now essentially solved — **1 `expression-error` and 8
`invalid-geometry` across all 482 views**. Commands drawn 9,120 → **9,186**, widgets 1,396 →
**1,436**, unresolved nodes 2,393 → **2,352**, and 40 of 482 dumped PNGs changed with **none lost and
none blank** (`scripts/wmp_render_sweep.sh compare`).

### 2a. What still stops a handler, ranked by reach

**Re-measured 2026-09-08 over the 179 archives after W37 closed, against a same-tree baseline
worktree.** Runtime member errors **252 → 127**, skins carrying a dead handler **119 → 70**, and the
159 `Can't find variable: mediacenter` that were 63% of the class are **gone**. Reproduce with
`scripts/wmp_render_sweep.sh capture <dir> --allow-dirty` and tally
`WMP: unimplemented <member>` and `Can't find variable: <name>` in `<dir>/raw.txt` by name and by
containing `SKIN` block. The queue behaved exactly as `reference/object-model.md` rule 2 says it
would: closing the biggest row let handlers run further and **raised** the rows behind it, so the
numbers below are the post-W37 ones and the pre-W37 ones are void.

**W216 is first and its Reach is unmeasured.** It is placed on the W100 precedent — the census drives
`onLoad` and this demand is in `onClick`, which is how W100 read as 2 skins when the true number was
162 — and it is the only row here that stops a *click* rather than a load. Measure it the way
`harness.md` § *Auditing one authored control across the whole corpus* prescribes before it is taken;
if it comes back small it drops below W39.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W216 | **An unqualified call in an event handler does not resolve against the element the handler is on** | 2 archives known, corpus reach unmeasured | `circle`'s `<EFFECTS onClick="previous();">` throws `ReferenceError: Can't find variable: previous` and `pharaoh` authors the same idiom as `next();` — so clicking either skin's visualizer does nothing. In WMP an event handler's unqualified names resolve against its own element first, which is why the same file writes `visEffects.next()` in one place and a bare `next()` in another and expects both to work. **Measure the reach before sizing it**, and measure it the way `harness.md` § *Auditing one authored control across the whole corpus* prescribes — the demand is in `onClick`, which the census never drives, and this is the blind spot that recorded W100 at 2 skins when the true number was 162. Scan the decoded script text for a bare call whose name is an element method (`next`, `previous`, `play`, `pause`, `stop`, `close`, `minimize`), and print the encoding breakdown. Verify with `WMP_RENDER_CLICK` on `circle` at `vMain@69,68` (the visualizer's fringe) — the handler error is on the `CLICK` line. |
| W39 | `eq.speakerSize` | 18 skins | Plus `eq.enableSplineTension` and `eq.enhancedAudio` at 1 each. WMP's speaker/spatial settings; the engine has no equivalent, so this is an honest `inert()` candidate rather than a feature. |
| W42 | A skin function is missing because its program never registered | ~12 skins, 1–2 each | `skin_init`, `loadVidPrefs`, `UpdateMetaData`, `checkForContent`, `Init`, `gears`… Each is one skin's own function, so the cause is upstream: a `.js` that failed to resolve, evaluated with an error, or is a `res://` entry. Diagnose from `SCRIPT`/`SCRIPTS` lines before writing any object-model code. |
| W136 | SDK element methods this engine does not implement, now that they are tallied at all (W128) | `plListBox1/2.deleteAll()` **10 skins** (7 of them visible to the census), `playlist2.copy()` 8, `playlist2.abortCopy()` 8, `playlist1.deleteSelected()` 5, `fileList.insertItem()` 3. `view.returnToMediaCenter()` was tracked separately as W100 and is **closed 2026-09-13**, so it has left this tally — its census-visible 7 against a true 162 skins is the sharpest measure of this row's blind spot: the sweep drives `onLoad` and these names sit in `onClick` | **Opened 2026-09-11 by W128 closing**, which is the row's whole purpose: these were counted `INERT` — Tier 2b, the tier you do not take runtime work from — and are now `UNRECOGNISED` where they belong. Reproduce with `scripts/wmp_skin_census.sh /tmp/wmp/census` and tally `UNRECOGNISED` in `render.txt` by name and by containing `SKIN` block. **The census sees only `deleteAll`**: the others sit in click handlers and the headless sweep drives `onLoad`, so measure the rest through the live loop or a click-driving sweep before ranking them against each other. Every one of the `deleteAll` calls is inside the skin's own `try`/`catch` (`fillListBox()`, `warcraft.js:1584`), so implementing it changes a screen only in company with W66 — the box has nothing to put in it until `player.mediaCollection` answers. Take W66's media-collection decision first; this row is what that decision would let the skins actually do. |
| W40 | An element the skin names is in another view | 8 + 4 + 2 + 2 + 2 skins | `Can't find variable: vidinfo` (8, new behind W37), `Can't find variable: pl` (4), `playlistframe.setColumnResizeMode (no such element)` (2), `pl.setColumnWidth` (2), `vidZoom`/`videoWin` (2 each, also new behind W37). Handlers are now scoped per view, but a script's *globals* are the current view's elements only. Find out what WMP does with a cross-view reference before choosing. |
| W41 | `player.currentMedia.sourceURL` | 4 skins | Small and real. **`theme.closeView` was the other half of this row and closed 2026-09-11 with W141**; what is left is the source URL. |

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

An entry here is markup asking for something. Two things make it work: classification (one line) and
a dispatch site (the real cost, and different per event). Do not add a name to `handlerNames` or
`supportedEvents` without its dispatch site — a recognised event nothing raises drops out of this
table while still doing nothing, which is exactly the state `onResize` was in.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W53 | Keyboard events (now reachable: the window could not take the keyboard at all until W79) | `onkeydown` 501/78, `onkeypress` 409/72, `onkeyup` 94/30 | `WMPMainView.keyDown` handles focus traversal and activation and raises no authored handler. Needs a key-code/character contract at the object-model boundary — decide what a skin may see of a keystroke before implementing. |
| W56 | Video and playback-position events | `onvideostart` 190/140, `onvideoend` 132/130, `onpositionchange` 147/41, `currentposition_onchange` 103/80 | **`currentposition_onchange` closed with W129** (amended 2026-09-11): it was one instance of the general `<attribute>_onchange` mechanism, and it is now raised from the host snapshot diff. It changed no pixel and that is the measured finding, not a disappointment — 96 of its 105 uses are `seek.value = player.controls.currentPosition`, and **W120 already supplies that number** from the slider's declared range. Do not re-open it as a rendering row. W102 supplies the hosted video surface and W124 supplies the live/event-state split, so the remaining `onvideostart`/`onvideoend` half is directly measurable rather than blocked. |
| W121 | A handler that reads the `event` object | **30 handlers across the Skins Factory equaliser family**, measured 2026-09-09 as `value_onchange: ReferenceError: Can't find variable: event`; unmeasured for the other event kinds | Surfaced by W51 rather than caused by it: those handlers had never run at all before the host-driven direction was raised. `value_onchange="toolTip = Math.round(value); if (!event.shiftKey) eq.gainLevel9 = value;"` is the shape — an equaliser band that skips its write while shift is held, which is how that family links its ten bands — and the same gap applies to the user-driven direction and to `onkeydown`/`onkeypress`, where W53 already needs a key. WMP binds one `event` object per handler with the modifier and key state on it. Bind it the way `WMPScriptContext` already binds the bare `value` and an event's named arguments: for the duration of that one handler, then cleared, so a stale one cannot be read by an unrelated later handler. Count the whole class first — sweep the corpus's handler attributes for `event.` and split by event kind, since the modifier state a mouse handler wants and the `keyCode` a key handler wants come from different places. |

**Verified *not* gaps — check before opening a row here.** The SDK conformance audit (2026-09-11)
disproved nine candidate gaps, including the author-typo list (`scrollingAmmount`,
`horizontalAlignemnt`, `donwImage`…) that is the largest single false lead in the whole scan. They
rank nothing, so they are in `skills/wmp-skin-guide/reference/object-model.md` § *Verified **not**
gaps*.

**`INERT` — recognised, answered, and nothing behind them — ranks nothing either** and is in that
same file, § *Recognised, answered, and nothing behind them*. It is Phase 5 rendering work, not
runtime work.

## Tier 3 — drawing the skin's own controls (Phase 5)

**Reach here is `scripts/wmp_markup_census.sh` output, measured 2026-09-07 over the 177 archives it
could read** — the 180 in `WMPSkins/` less `Darkling.wmz` (excluded) and the two whose local header
signature is overwritten, which `unzip` cannot open and the engine can (`Need_for_Speed_Underground`,
`SplinterCellWMPSkin`). So every number below is short by at most two skins, never long. Reproduce
with `scripts/wmp_markup_census.sh /tmp/wmp/markup`.

This is authored demand, not result: the census says a skin asks for an attribute, never that the
engine draws it right. Only a dumped PNG says that. Rows are in rank order, top down — corpus reach
first, and the single-skin rows at the bottom are kept because each names a *visible* readout, not
because they rank with the rest.

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
| W133 | Hosted `PLAYLIST` chrome attributes are unread | `columnsVisible="true"` **74 skins** (with `columns` in 131), `toolbarVisible="true"` 12, `leftStatus`/`rightStatus` 27, `dropDownImage`/`dropDownBackgroundImage` 27/25, `toolbarMargin` 14, `disabledItemColor` 74 | `playlist-element` defines 37 attributes; the engine reads background/foreground/itemPlaying colours via `WMPSurfacePalette` and nothing else. **Verification halves this row, and that is most of its value**: the corpus mostly authors values that *agree* with what the overlay already does — `playlistItemsVisible="false"` is 3 skins against 117 authoring `"true"`, `moveButtonsVisible` is `"false"` in all 57 skins that author it, `checkboxesVisible` is `"false"` in 24 of 32. The reach column above is only what genuinely differs, and `disabledItemColor`'s 74 have no meaning here at all — there are no disabled tracks. The substance is column headers, which the overlay draws none of. **`dropDownVisible="true"` (114 skins) is explicitly not part of this row**: it is a documented deliberate refusal in `object-model.md` pending W66. |
| W132 | `hoverDownImage` is never selected | **126 nodes across 62 skins** (`BUTTON` 86, `BUTTONGROUP` 38, `MUTEBUTTON` 2) | `button-element`: "the image displayed when the **BUTTON** is in the down state and the user hovers over it with the mouse pointer." `WMPSceneBuilder.swift:490-493` resolves `.down` to `["downImage", "image"]` and never consults `hoverDownImage`. **Deliberately ranked low: every one of the 126 nodes also authors `downImage`** (checked, zero exceptions), so the fallback is the correct down artwork missing only its hover lighting — cosmetic. It is here rather than dropped because the sticky case is the one a user looks at for seconds at a time: repeat/shuffle/mute left toggled on. **The fix is not just a name.** `WMPInteractionState.swift:63` collapses a pressed node and a sticky-down node into the same `.down`, so this needs a distinct hover-down face in the state machine before the attribute has anywhere to go. **Needs the live loop** for the same reason as W131. |
| W202 | An `<EFFECTS visible="false">` that a script later makes visible never gets a hosted surface | **57 nodes in 54 archives** declare `visible="false"` on an `<EFFECTS>`/`<WMPEFFECTS>` (`Erektorset`, `Plus! SlimLine` and `Sports` twice each); how many of those are turned on by script is the number to measure next | Opened 2026-09-16 by the pharaoh report. `pharaoh`'s scarab mode is the reproduction: `<effects id="visScarab" zIndex="-1" visible="false" left="1" top="7" width="129" height="79">`, made visible by `ToggleScarab(true)`, and the 903 px of `#FF00FF` its `scarab.bmp` cuts for it stay black. **Measured live after W199**: the sphinx view's surface mounts and animates (`VisualizationGLView: Setting up ProjectM with viewport 174x148`, 1,595 of 1,608 hole pixels changing between captures) and no second `Setting up ProjectM` line is ever logged for the scarab, so the surface is never created rather than created and hidden. Drive it with `defaults write NullPlayer wmpSkinName -string pharaoh`, the debug build, and a click at the window's `262,107` — then read the log, not the screen. The scarab's hole is small; rank this on the corpus population, not on pharaoh. |
| W201 | An animated GIF whose frame image blocks are smaller than its logical screen is drawn at the screen's size | **27 files in 12 archives** of the 4,303 GIFs in the corpus, and `pharaoh/pyrevolver.gif` is the extreme — a 140x128 logical screen whose 16 frames are each a 21x16 block at 0,0, i.e. 6.7% of the declared area. The rest are within a few pixels of their screen (`Age_of_Mythology` 198x173 vs 193x172, `bruteforce` 289x111 vs 289x101, `xsn_sports` 205x70 vs 191x70, `Official_Xbox_MP71` 23x18 vs 16x10 ×6). Header scan of every `.gif` entry, first frame's image block against the screen descriptor | Opened 2026-09-16 by the pharaoh report. Its scarab mode's only route back to the player is `<button left="56" top="17" width="21" height="16" upToolTip="Sphinx mode" image="pyrevolver.gif" onClick="ToggleScarab(false);">`, and it draws as an **opaque black box measured at 21x30** over the scarab's face — the authored height is 16, and the area the frame block does not cover is painted rather than left alone. **The button still clicks** (driven live: a click at `66,25` returns to the sphinx view), so this is artwork, not input, and it is why the reporter read the scarab as a dead end. The cause is stated as an observation, not a diagnosis: the two candidates are the screen-versus-block size and the GIF's uninitialised screen area, and neither has been isolated. Check `Age_of_Mythology`'s `open_shutter.gif` before changing anything — it is already load-bearing for the one-shot terminator rule (`reference/skins/README.md`). |
| W66 | A `LISTBOX` has a control and nothing to put in it | **8 skins**, 16 uses, measured 2026-09-07 over 177 archives | Every one is `plListBox1`/`plListBox2`, a playlist chooser the skin fills from script by walking WMP's media collection (`getSelPlaylist()`). The control now exists, draws, and reports its selection; what it cannot do is have rows, because the object model answers nothing for `player.mediaCollection` — so a skin's `onLoad` appends nothing and the box is empty. That is a host-surface decision (what a `.wmz` may see of this player's library), not drawing work, and it is deliberately **not** faked with rows this player invented. Rank it with whatever answers the media-collection question. |
| W204 | Every view in a skin shares one script scope, so a second `scriptFile` silently overwrites the first's functions | **7 of 185 archives** declare two or more `scriptFile` programs that define the same top-level function name — `Plus! SlimLine`, `Sports` and `holiday_skin` collide on six each (`Init`, `OnOpenStateChange`, `OnPlayStateChange`, `EndVideo`, `StartVideo`/`OnClose`, `OnTimerTick`), `pharaoh` on two, `9SeriesDefault` and `corona` on `OpenMedia`, `portals` on `init`/`shutdown`. Scan of every `function <name>(` in each program a `scriptFile` names, decoded as `WMPTextDecoder` does; re-run it before ranking | Opened 2026-09-16 by the pharaoh report (W199/W200), which is the skin that makes it visible. One `JSContext` serves every view by design — `WMPScriptContext.restoreElements(for:)` swaps each window's live elements in for the length of its own transaction, because every view root is called `view` — but **a program's top-level functions are not swapped**, so the last `scriptFile` evaluated wins for the whole skin. `pharaoh.js` and `pharaoh_ros.js` each define `OnOpenStateChange`, `UpdateMetadata` and `vidIsRunning`; the rosetta's wins, so the *player's* `player.OpenState_onchange` runs the rosetta's handler and dies on the first identifier that view does not have: `SCRIPT-DIAG view-2 [handler-error] onLoad[0]: ReferenceError: Can't find variable: bgVid (line 50)`, reproducible with `WMP_SKIN=…/pharaoh.wmz WMP_RENDER_HOST=playing`. **It is invisible with a stopped player**, which is why no sweep has ever shown it — the handler's `else` branch touches nothing view-specific — so the three WMP7-scaffold skins above are the population to measure and a default-state capture cannot do it. `pharaoh`'s own symptom is bounded (its video pane never auto-opens) and the row is ranked on the other six. The shape of the fix is per-view function scope; what that costs a skin whose views deliberately share a helper is the question to answer first. |
| W149 | Controls still unreachable after W148, each for a different reason | `Sports` 7, `anime`, `STALKER`, `T3-Skynet_Media_Player`, `Plus! Professional` (container) — **11 total**, re-measured 2026-09-12 after W150 (was 16; `Gold`'s five containers and four others were the position-map half) | **Opened by W148 closing**, and it is the residue that rule does not explain rather than a regression from it: reproduce with `WMP_SKIN=<corpus> WMP_RENDER_HOST=playing WMP_RENDER_OCCLUDED=1` and read the `reached=rect-only` lines. **10 of the 16 are `<BUTTONGROUP>` *containers* with no mapping children** (`Gold`'s five stacked `drawerButton*` at one 144x123 rect, `The_Doobie_Brothers`, `Plus! SlimLine`, `Plus! Professional`), and a group with no `<BUTTONELEMENT>` dispatches nothing however it is ranked — **decide whether those should be hit targets at all before counting them as work**. The six that are real: `Sports`'s `eq2`–`eq8` sliders answer to `pl2`/`pl3`/`pl4` `<TEXT>` nodes drawn over them, which is the same question in reverse (a `<TEXT>` keeps its box because glyphs are not a hit shape — see `WMPHitCoverageBuilder`), and that skin trades 7 sliders for the 3 texts it gained; `anime`'s `plHandle` answers to `closepl`; `STALKER`'s `blankRate4` to a plain `<BUTTON>` while its other four stars work; `T3-Skynet_Media_Player`'s `timeSign` is authored at `x=-25` and is mostly off its own canvas. **Name the node before ranking the count** — the same rule `../harness.md` states for `unresolved`. |
| W203 | `<DURATIONTEXT>` never renders | **2 nodes in 2 archives** — `pharaoh` and `circle` — so this is a one-line row kept only because it is a *visible* readout on a shipped Microsoft skin | Opened 2026-09-16 by the pharaoh report. Its face reads `1:03 /` with nothing after the slash: `<currentPositionText>` at `57,86` and the literal `/` at `103,86` both draw and `<durationText left="108" top="86" width="45" fontSize="8" justification="Left">` produces no `PROBE` line at all, which is the view's single `unresolved`. `WMP_SKIN=…/pharaoh.wmz WMP_RENDER_UNRESOLVED=1 WMP_RENDER_HOST=playing` names the dimension: `UNRESOLVED view-2/11 durationText id=- size=missing literal geometry (height)`. **`<currentPositionText>` beside it declares no `height` either and resolves to 45x10**, so the missing piece is a glyph-height fallback this one tag does not get, not anything the skin failed to author — which also means a `<DURATIONTEXT>` anywhere is dead, not just this one. |
| W123 | A stretched `backgroundImage` and a natural-size foreground image draw the same bitmap at two different sizes | **1 view measured** (`Ice/videoView`) out of the 545-image corpus capture; the wider class is every `backgroundImage` whose frame is not its bitmap, unmeasured. Reproduce with `WMP_SKIN=…/Ice.wmz WMP_RENDER_PROBE=videoView` | **Opened 2026-09-09 by W122 closing.** `Ice` authors `<button image="Pl-xp.bmp" width="196" height="144">` over a bitmap that is really 196x**44**, inside `<subview id="Drawerbutton2" backgroundimage="Pl-xp.bmp" width="313" height="144">`. Both were stretched and therefore agreed; the button is now drawn at its own 196x44 and a seam appears in the lower shell. The question this row exists to settle is **what WMP does with a background whose frame is not its bitmap**, and it cannot be answered by extending W122: `Ice`'s own frame tiles all author `backgroundtiled="true"`, which suggests WMP does not stretch and a skin tiles deliberately — but `Vidcolorbox` is `horizontalAlignment="stretch" verticalAlignment="stretch"` with an untiled `Vid-bg.bmp`, and `LostPlanet`'s stretch tiles are 61 px of window frame that would punch through. Measure the class before changing the rule, and check `reference/skins/README.md`'s counter-evidence table first. |
| W145 | A borrowed window frame is rendered from markup, so it never follows the theme the skin is *set* to | **xsn_sports** measured 2026-09-12; the pattern is stacked variants, unmeasured across the corpus | `WMPHostedFrameTemplate` lends NullPlayer's own windows the skin's eight-piece ring (86 of 180 archives declare one), built through `WMPSceneBuilder` from markup alone. A skin whose colour scheme is a *script* decision therefore always gets its opening one. `xsn_sports` stacks all eight frame variants in `plView` (`pl1_1`…`pl1_8`, 2-8 at `alphaBlend="0"`) and cross-fades between them from `htcpStartupPl()`, reading the `htcpID`/`winAlpha` preferences in the view's own `onLoad` — "Hyper-Transient Color Phasing", per the notice in `xsn.js`. Reported as "the NullPlayer window does not follow the colour theme selected in xsn". **The fix is to run the donor view's `load` off-screen** (`WMPScriptRuntime.transact`, whose overrides `dispatch` deliberately discards) and build the ring with the overrides it commits, re-running when the skin's preferences change; the template must then keep *every* candidate per ring role rather than the first declaration. It settles on the chosen colour and does not animate the phase — running a closed window's timer to match a cross-fade is out of proportion to what it buys. |

## Closed

Closed entries live in [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md),
verbatim and with their evidence. Move a row there in the same change that closes it — one left here
reads as open work.
