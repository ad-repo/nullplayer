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

**Two IDs were issued twice by different sessions, and the open halves were renumbered 2026-09-17.**
The `.wmz` placement/recovery audit moved **W196 → W217** and the `Colorchooser` transport row moved
**W171 → W218**; the archived, *closed* W196 (a view's resize limits read from markup only) and W171
(a `clippingImage` with no `clippingColor`) keep their numbers, and every reference in
`Sources/`, `Tests/` and `skills/` to those two numbers means the closed rows. Check
`docs/wmp-skin/wmp-backlog-archive.md` before reusing any number: the next free one is **W219**
(W211 was never issued).

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
through the real `NSView` stack and **exactly two** paint where the scene does not (both W74), so
whatever was seen is mostly scene-side starvation (W68, ranked automatically by `starved.tsv`) or
driven by a hover, a timer or live playback, which W73 records as still unreachable. `corona` is the
control from that session — "all its sliders and buttons for the most part" — and is why the rest
read as defects rather than as the engine being broken. **Capture a reporter's list before ranking
further Phase 5 work.**

**Build a baseline worktree at the parent commit before attributing a live report to the change in
front of you.** Three reports on 2026-09-09 were assumed to be W55's and behaved identically at the
parent; it cost one build and moved all three out of that change's ledger.

**A NullPlayer surface wearing a borrowed `.wmz` ring is not the scene.** W177-W179 were reported
together on 2026-09-15; W177 and W178 closed, and what is left (W179) lives in
`App/Skinning/SkinnedSurfaceChrome.swift` and `PlexBrowserView`, where `WMP_RENDER_APPKIT` — which
measures a skin's *own* views against their scene — cannot see it.

Rows are in rank order, top down.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W193 | `view.size(corner)` is unimplemented, so a skin's own resize grip is dead | **88 of 185 archives, 235 calls** (decoded `.wms`+`.js` scan, 2026-09-16) — `Revert` ×7, `The Unit` ×6, `QuickSilver` ×5, the whole Alienware/ALX family, `Halo 2`, `Star Wars`, `xsn_sports`, `Tomb Raider 2`, the Plus! skins, `Compact` | Found while closing W184-W192 (`reference/skins/compact.md`), not from a report of its own — though it is what makes the *stretch* half of that report behave oddly. `onMouseDown="view.size('bottomright')"` is the corpus's standard grip and **a `.wmz` window has no OS frame**, so in WMP it is the only resize the window has. Here it is inert and the user drags the macOS window edge instead, which skips whatever the skin does *around* its own resize: `Compact`'s `DoSize()` pins both drawers to their edges for the duration and unpins them after, and without that a widened window leaves the drawer behind. The implementation is a modal drag loop in `WMPMainWindowController` driven from a host command, honouring the view's `minWidth`/`maxWidth` — and with W192 landed, the alignment dance the skins wrap around the call already works. Corners authored: `bottomright` overwhelmingly, plus `topleft` (`Revert`), `topright` (`The Unit`) and `right` (`Alienware Invader`). |
| W194 | `moveTo`/`resizeTo`/`alphaBlendTo` ignore their duration, so nothing in the corpus ever animates | **the duration form is corpus-wide**; the completion callbacks it would move are **36 views** (`onEndMove`, the drawer template Microsoft shipped) | Reported 2026-09-16 as *"its not a smooth opening"* against `Compact`'s drawers, which jump rather than slide. `WMPObjectModel.flushPendingTweens` writes the endpoint at the end of the handler and `WMPScriptContext.raiseCompletionHandlers` raises `onEndMove` immediately, so a 1,000 ms slide takes one frame. **The tween is the easy half; the callback is the risk.** Moving `onEndMove` from *end of handler* to *end of tween* changes when 36 views' sequences chain — W55 is the row that made that callback load-bearing, and `Compact` itself shrinks its window inside `Playlist_OnEndMove`, so a real tween means the window shrinks a second after the drawer starts closing, which is what WMP does. Sweep the corpus either side and drive at least `Compact`, `xsn_sports` and `corona` live; a render dump cannot see motion (`WMP_RENDER_CLOCK` pins frames for GIFs only). |
| W68 | The Alienware/ALX family draws a shell and nothing in it reacts | 6 skins named below, inside a corpus-wide class of **41 views across 36 skins** resolving under half the nodes they declare, **79 views / 49 skins** with no hit target and **65 / 37** drawing nothing, measured 2026-09-08 over the 607 views of the 179-archive sweep. **The ranking is now automatic** (W70): `starved.tsv`, every census run | Reported as "ALXMorph does nothing — no animation and nothing reacts". **This is not an AppKit defect and it did not need a live session to find: the sweep has been printing it all along.** `RENDER-DUMP mainView` for `ALXMorph` is `339x329, 15 nodes, 8 commands, 5 hits, 0 widgets, **15 unresolved**` — as many nodes failed to resolve geometry as laid out, and five hit targets is a whole player's worth of buttons missing. `AlienMorph` and `AlienwareTeleport` are identical at `368x426`; `Alienware Invader` is worse still at `2 nodes, 0 commands, 0 hits, 18 unresolved` — it draws nothing whatsoever. The absent animation is the same cause, not a separate one: the family's big `m_anim_*` GIFs hang off subviews that are either unresolved or authored `alphaBlend="0"` and faded in by script (`mainAnimCoolantChamber` is the one confirmed by hand), so W38 `alphaBlendTo` was expected to be load-bearing here. **It was not, and W38 is now closed**: with the call implemented, `ALXMorph`/`AlienMorph`/`AlienwareTeleport` `mainView` goes 8 commands → **7**, because `alienware.js` fades `mainAnimCoolantChamber` *out* in the handler that used to abort at the call. **The artwork comes back on a click, and the preference-default path, now closed as W76, not W53/W54**: `toggleCoolantChamberAnim()` is raised by `animTrigger`'s `onClick`, and which branch it takes is decided by `theme.loadPreference("coolAnim") == "true"` — before W76, an unset key answered `''` and took the `else` branch; it now answers `"--"` and preserves the authored default. Clicks already dispatch, so the animation half of this row is one preference read away, not an unraised event. Hover is load-bearing elsewhere in the same skin — `volumeText` and `seekText` fade in and out of `onMouseOver`/`onMouseOut` in `alx_dl.wms` — so W54 buys those readouts, not the coolant chamber. **W54 closed 2026-09-08** — hover now dispatches, and with W79 the window can receive a pointer at all — so this row's hover half is testable live rather than pending. **It is one view, not the skin.** `ALXMorph`'s other seven views are healthy — `eqView` is `45 nodes, 44 commands, 26 hits, 8 unresolved` and `videoView` `35/33/12/6` — so only `mainView`, the view it opens on, is starved. That is why the skin reads as dead while its equaliser and playlist would work if you could reach them. **W70's ranking disagrees with this row about where to start.** ALXMorph scores exactly 0.50 and is one of the *milder* cases; the worst in the corpus are `Disney_Mix_Central/mainView` (2 of 25 nodes resolved), `Batman Begins/mainView` (2 of 21), `Alienware Invader/mainView` (2 of 20) and `Cablemusic/mainview` (35 of 98). Take the top of `starved.tsv`, not the top of this row. **The AppKit half is cleared**: `ALXMorph/mainView` diffs to zero against its own hosted render (W71), so nothing here is an overlay defect and the whole of it is scene-side. **The expression-cascade theory is dead — measured 2026-09-08 and it was the probe.** `WMP_RENDER_EXPR` used to report 34,314 of 42,015 rows corpus-wide reaching no evaluator (82%), which was read here as the cause; 34,300 of those were **another view's** expression printed under this view's name, each already ordered and evaluated under its own view. With the probe scoped the way both evaluators are (`WMPHarness.expressionLines`), the corpus reads **7,569 / 7,569 reaching the live evaluator, zero unreached**, and `starved.tsv` does not move: 41 views / 36 skins, unchanged. Expressions are not what starves a view. All three named skins were opened and looked at: `Cablemusic/mainview` declares **no geometry expressions at all** yet carries 63 unresolved nodes and draws a nearly complete player; `ALXMorph/mainView` has 4 and all of them resolve live, and it draws its whole shell — so "does nothing" is interaction and animation (W38, W53/W54), not layout; `Alienware Invader/mainView` has 6 and all of them resolve live, and it is blank because `toggleShutter()` plays a **568-frame intro** off a 50 ms timer and only at frame 568 sets `mainBack.backgroundImage` and `mainBackGroup1.visible = true`. **Start from what `unresolved` actually counts, not from `EXPR`** — and note that a high ratio does not mean a blank view: two of the three worst-ranked views in `starved.tsv` render substantially. The evidence is `skills/wmp-skin-guide/reference/harness.md` § *After the cascade*. **W75 came out of it, was load-bearing here, and is now closed**: a script assignment to `backgroundImage` never reached the scene, which is exactly what Alienware's intro is made of — `Alienware Invader/mainView` now draws its full 406x380 player under `WMP_RENDER_SETTLE=32` instead of an empty PNG. Its `2 nodes / 0 hits` in the *default* state is unchanged and is not that defect: frame 0 of a 568-frame intro is still frame 0. The worst of the wider class are `digitaldj/DigitalDJ` (**91** unresolved against 101 nodes), `Cablemusic/mainview` (63 against 35), `WALL-E/mainView` (35 against 37) and `NVIDIA/mainView` (32 against 43); `Disney_Mix_Central`, `Batman Begins` and `Alienware Invader` all draw a `mainView` of 2 nodes and 0 hits. **W143 closed this family's other five windows and did not touch this row, which is the sharpest statement of what it is about.** Reported 2026-09-12 as "the playlist and eq windows are not properly contructed … there are large gaps": their nine-piece frames were collapsing both 175-wide side columns onto the corner bitmaps that carry the title bar, because `verticalAlignment="center"` was offset like a margin. Every `mainView` in the family is **byte-identical** across that fix — a non-resizable player authors no centred pieces — so `plView`/`eqView`/`visView`/`videoView`/`infoView` now draw their frames correctly while the player this row names is exactly as starved as it was. Do not read the family being "fixed" as this row moving; the dossier is `skills/wmp-skin-guide/reference/skins/alienmorph.md`. |
| W195 | 44 of the 50 `res://wmploc.dll` string ids draw as empty | **133 uses of 50 ids across 6 archives**, of which `WMPResourceStrings` names 9 (decoded scan, 2026-09-16) | The remainder are mostly *format* strings a skin builds a sentence from — `transport.js`'s buffering tooltip (`#2099`), its status strings (`#2077`, `#2078`, `#2063`) and the DVD chapter format (`#2086`) — plus the reception-quality tooltips (`#2079`-`#2081`, `#2092`). They are blank rather than wrong, which is where `theme.loadString` has always been. **Add a row to the table only when something in the corpus states the text** (a tooltip on the same control, a markup default the script replaces); the alternative is inventing Microsoft's wording, which was explicitly declined when this was opened. |
| W99 | A drawer's own toggle button drifts out from under the pointer once the view's timer runs | `xsn_sports` confirmed both live and headlessly; **every skin with a timer and a moved drawer is a candidate — count it** | Reported live 2026-09-09 as "it opens and closes right away, it is resistant to opening", and **reproduced against a baseline worktree at the parent commit, where it behaves identically** — so it is not W55, which only made it visible by correctly hiding a shut drawer's contents. `vidDrawerButton` in `xsn_sports/videoView` is drawn at `61,291` on the first frame and at `61,271` after `WMP_RENDER_SETTLE=2` runs the view's own 500 ms timer; a click at the first position returns `CLICK … MISS`, and a click at the settled one hits and opens the drawer to `4 widgets[slider×4]`. So the drawer works and the *target moves*. Twenty pixels, on a rebuild driven by a timer that only calls `htcpVid()` — which alpha-blends artwork and moves nothing — so find what re-resolves that subtree's geometry between ticks before assuming the handler did it. The old scripted-`view.height` theory is closed by W113; reproduce with `WMP_SKIN=…/xsn_sports.wmz WMP_RENDER_SETTLE=2 WMP_RENDER_PROBE=videoView`. |
| W176 | `WALL-E` presents its `upgradeView` nag panel as the player, and its real `mainView` opens beside it | **1 archive confirmed live, 2026-09-15**; the wider class is the 3 archives already named for declaring `upgradeView` ahead of their real view (`xsn_sports`, `Halo 2`, `T3-Skynet_Media_Player`) | Found while verifying W175, not from a report, and **not caused by it** — the dispatcher posts no `openView` at load at all, so the successor list is empty under the old `last` rule and under the new ranking alike and the walk falls through to document order either way. (Reasoned from the commands, not measured against a baseline build; a worktree at the parent commit would settle it.) `WALL-E`'s dispatcher is the corpus's only one that opens its player from its *timer* rather than its `onLoad`: `checkRemoteViewStatus()` calls `theme.openView('mainView')` on the first tick where `delayPop` is true, so at the moment the candidate walk runs the dispatcher has posted **no** view to go to and the walk falls through to document order — which reaches `upgradeView`, the "your Windows Media Player is too old" panel WMP never shows. Measured: `defaults delete NullPlayer wmpSkinViewID`, launch `-uiMode wmp`, and the window list is player 382x298 + `mainView` 392x298, with `wmpSkinViewID` persisting as `upgradeView`. The donor ranking in `SKILL.md` § *Every NullPlayer window in WMP mode* already refuses `upgradeView` when borrowing a **frame**; the candidate walk does not, and that is the smallest form of this fix. The second half is harder and should be decided first: **a player that arrives one tick late has no way to claim the app's window**, because the first view with a canvas binds it (W96). |
| W74 | A playlist overlay paints below the view it lives in | **2 views / 1 skin** (`Revert.wmz` and `Revert (1).wmz`, two releases of the same skin), the *only* two in the corpus, measured 2026-09-08 by `WMP_RENDER_APPKIT` over the 545 hosted views of the 179-archive sweep | 4,000 px at delta 196, in a 250x4 band at `3,256` of a 260-tall view. `ctrlPlaylist` is authored `3,14 250x257`, which ends at y=271 — eleven pixels past the view's own bottom edge — and `WMPMainView.layout()` positions the overlay from that frame without clipping it to `bounds`, so the `NSView` paints where the scene has nothing. **This is the whole W43 class in the corpus's default state**: 543 of the 545 hosted views agree with their scene exactly. Establish what WMP does with a control authored past its view's edge before choosing between clipping the overlay to `bounds` and clipping it to the widget's own `clipRect` — the scene already carries a `clipRect` the overlay ignores, which is the cheaper of the two and may be the correct one. Reproduce with `WMP_SKIN=…/Revert.wmz WMP_RENDER_APPKIT=1`, and `WMP_RENDER_APPKIT_DUMP=<dir>` to see both bitmaps. |
| W218 | `Colorchooser`'s transport buttons stack on one pixel, so pause, stop and next all fire **previous** | **1 skin, 8 expressions** — the only archive in the corpus that chains geometry off a `<TEXT>` node's own measured width, measured 2026-09-14 with `WMP_RENDER_EXPR` over the 180-archive sweep | Found by the transport audit (`skills/wmp-skin-guide/reference/harness.md` § *The transport audit*), not by a report. Its five transport buttons are `<TEXT>` nodes chained `left="jscript:<prev>.left+<prev>.width"`, and a text node sized from its own glyphs answers **0** for `width` in an expression — so `stopbutton`, `pausebutton`, `nextbutton` and `prevbutton` all resolve to `103,29 12x12` where 16/28/40/52 was authored, the webdings glyphs overprint, and only the last in z-order answers the pointer. `WMP_RENDER_OCCLUDED` prints the consequence as three controls `reached=neither by=[prevbutton#14:text]`. `playbutton` is correct because **its** geometry is authored rather than derived, which is the shape of the fix: publish a measured size to the evaluator before the nodes that depend on it resolve. Reproduce with `WMP_SKIN=…/Colorchooser.wmz WMP_RENDER_EXPR=1` and read the four `live=16` rows. |
| W179 | `Combat_Flight_Simulator_3` lends the library a ring whose corners land on the rows | **1 archive, screen capture 2026-09-15**; unmeasured against the rest of the corpus | Reported with the capture: red corner wedges printed over the list at the top-right and across both bottom corners, the A-Z index column sitting on the artwork rather than beside it, and the bottom row clipped by the frame. This is the *hole*, where W178 is the caption. The skin builds every panel from `jscript:`-sized stretch tiles — `centerBox` is `left="10" top="37" width="jscript:view.width-20" height="jscript:view.height-(56+55)"` and `plcenterBox` the same shape against `plView` (`cfs3.wms:869`, `:1023`) — so the client hole `WMPHostedFrameTemplate` derives is the value those expressions take **at the donor view's own size**, not at the library window's. Start by dumping the resolved `contentRect` at the library's actual size and comparing it with the ring bitmap's opaque region; do not assume the corner pieces are misplaced until that number is wrong. Note that `WMPHostedFrameTemplate` re-renders per window size (`SkinnedSurfaceFrameArtwork.matches(size:)` is exact), so a stale frame is not the explanation. |

## Tier 1d — what the Phase 6 instruments do and do not reach

**Manual testing does not scale to this corpus** — 179 skins times sliders, drawers, drags and
animation is not a human-scale job, and Phase 5 shipped its AppKit half unmeasured for that reason.
One row is what is left of that gap; the other is about the instruments themselves, which belongs
here because a probe that reports work already done is a gap in reach exactly as a missing probe is.
**W215 ranks first because it corrupts the ranking inputs every other tier is taken from.**

| ID | Item | Reach | Notes |
|---|---|---|---|
| W215 | **The sweep's own `supportedTags` list is a stale private copy, and overstates unimplemented demand by 78%** | 944 of 1,203 reported uses, corpus-wide (measured 2026-09-17) | `WMPRenderDumpTests.supportedTags` (`:2095`) duplicates `WMPCorpusReport.supportedTags` and has drifted to 34 entries against 47. The 13 it is missing are all implemented: `customslider` (**403 uses**), `effects` (188), `pauseelement` (86), the `*button` halves of the transport pairs (~213), `progressbar`, `statustext`, `currentpositiontext` (16), `durationtext` (W213), `mutebutton`, `repeatbutton`. Genuinely unimplemented demand is **259**, not 1,203. This is precisely what `WMPCorpusReport`'s own comment warns about — *"A tally that is wrong in this direction ranks work that is already done"* — and it has been doing it to every `COMPAT`/`UNKNOWN tag` reading taken off this harness. Reproduce by extracting both lists and intersecting with the `UNKNOWN tag` totals of a `WMP_RENDER_PROBE=all` corpus run. **The fix is to delete the copy**, not to sync it: expose the engine's set and read it, exactly as `WMPWindowSizeLimits` is now shared between the app and `WMP_RENDER_LIMITS` for the same reason. **The member half is the same shape and is not measured**: `supportsMember` cannot classify an element member at all, so `circle` reports `UNKNOWN member metadata.value ×4` while element `.value` writes are implemented (`WMPScriptRuntime.setWidgetText`, `onElementTextChanged`). Quantify that before trusting any `unknown-members` count. **Landing this moves the sweep's invariants file**, so capture a fresh baseline in the same change. |
| W73 | A clean sweep still proves only the default state | every skin | **The playback half is now instrumented, 2026-09-09**: `WMP_RENDER_HOST` seeds a playing host for a whole sweep (and `NULLPLAYER_PLAY` starts a live debug launch on a track), which is what found W119 and W120 — two defects in the one state every transport readout in the corpus is authored for and no capture here had ever entered. Read the `HOST` line of such a capture before anything else in it. Narrowed by W71 and W72, not closed by them. The AppKit *overlay* class is now measured — 545 hosted views, two defects, both in W74 — and every slider in the corpus is drivable. What no sweep here still says anything about: a tab, a setting, a **hover**, a drawer, the window's shape and its shadow (those live in the window server and stay a short, genuinely manual list), and anything driven by live playback. W69's flicker is in that remainder, which is why it needs its own instrumentation rather than another sweep. |

## Tier 1f — the residue of the starvation classes

| ID | Item | Reach | Notes |
|---|---|---|---|
| W111 | Objects a skin declares inside `<PLAYER>` are laid out as controls, and count as starved | `<controls>` **103 nodes / 67 of 179 skins**, `<VIDEOSETTINGS>` 28 / 24, plus `durationText` 2 / 2 and `automenu` 4 / 3 as unknown tags, measured 2026-09-09 with `WMP_RENDER_UNRESOLVED=1` over the 179-archive sweep | **Costs no pixels and distorts the ranking**, which is the only reason it is a row: `starved.tsv` scores `unresolved / declared`, and ~154 of the 1,067 unresolved nodes left in the corpus are objects that were never boxes. `<controls>` is a child of `<PLAYER>` carrying nothing but `currentPosition_onchange` handlers — `aom.wms` is the worked case — and `WMPSceneBuilder.isNonLayout` already treats `.player` and `.network` exactly that way, so this is the same one-line rule applied to two more kinds. `STATUSTEXT` and `CURRENTPOSITIONTEXT` are no longer part of this row: both are implemented as native text controls. `durationText` and `automenu` remain separate questions and need a census before a kind: decide whether each is a `<TEXT>` WMP fills in for the skin (which is drawing work, not classification) or an object. Do **not** batch them with `<controls>`. |

## Tier 1g — the window system, not the scene

Opened 2026-09-16 by an audit of `.wmz` window placement against the `.wal` rules. **The tier exists
because every other tier on this page ranks a skin's own drawing, and nothing here is about a skin at
all.** A row lands in Tier 1g when the defect is in `App/WindowManager.swift` or
`App/AppStateManager.swift` — where a window is placed, restored, rescued and reset — and would
reproduce identically on a skin that renders perfectly. Tier 1e is its nearest neighbour and is
deliberately separate: that tier is about *which* window a surface belongs in, this one is about
*where the window is*.

Three consequences follow from that, and they are why these rows do not rank against a starved view:

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
| W217 | `.wmz` shares the `.wal` *placement* seams but none of its *recovery* seams, so a stranded WMP window has no route back | **every `.wmz` session**; the four gaps are structural, not per-skin (code audit 2026-09-16, no corpus sweep needed) | Audit written to `~/.claude/plans/wmp-window-placement-compliance.md` — read it before taking this row; it carries the rule-by-rule table, the line numbers, and a four-step plan. **What already complies and must not be touched**: `WMPViewWindowMaterializer.place` is a faithful copy of the `.wal` recipe (`tiledOrigin` → `rescuedOrigin` backstop, placed once), WMP panels are in `managedWindowRecords` as snap targets, and every WMP resize is top-left anchored so growth cannot strand the reachable corner. **The four gaps**: (G1) `WMPWindowRestorePolicy.safeFrame` (`WMPMainWindowController.swift:2621`) is a second, weaker definition of "on screen" — an 80pt strip and a 24pt bottom margin rather than `WindowPlacement`'s top-left-corner rule, and `first(where: intersects)` rather than `hostScreen`; a borderless `.wmz` window's preserved strip can be artwork with no drag handle. (G2) `correctedRestoredFrames` is gated `appliesWinampModernPlacement` (`AppStateManager.swift:955`), so WMP never gets the whole-session group offset nor the `savedScreenIsMissing` force — a docked cluster restored onto a smaller desktop comes back overlapping instead of touching. (G3) `ensureAllWindowsOnScreen()` (`WindowManager.swift:5738`) returns early in WMP and all six call sites re-guard, so an unplugged display, a resolution change or a resized Dock strands WMP windows **permanently**. (G4) `snapToDefaultPositions()` branches only on `.winampModern`; `.wmp` falls through to the Classic stack, which measures against `screen.frame` not `visibleFrame`, builds its stack from the per-feature controllers the skin's own windows are not on, and has no final `isReachable` pass — **this is B81 verbatim**, in the one mode where the windows are borderless and cannot be dragged back. The `.wmp` case in `fallbackMainSize` makes it look supported. Take step 1 (the Snap To Default branch) first: highest impact, lowest risk, and the only recovery a borderless window can be given today. Two doc rows ride with it — `ui-guide/SKILL.md:1034` claims the sweep "runs in all three modes deliberately" and the code says the opposite, and `wmp-skin-guide` states no recovery contract at all. **Verify live** (`WMP_PLACE_TRACE=1`, `Halo 2` as the load case, `Corona` as the control); Classic and Original must be byte-identical across every step. |
| W214 | **`isRunningModernUI` is a two-way switch in a four-family world, so every `!isRunningModernUI` branch treats a `.wmz` window as Classic** | 4 sites, every `.wmz` session (code audit 2026-09-17; no corpus sweep can see this) | **This is W217's G4 generalized, and one instance of it has already cost a full live-QA cycle.** `WindowManager.isRunningModernUI` answers `false` for `WMPMainWindowController` by construction (`WindowManager.swift:388`), so a guard written to mean *"Classic, not Modern"* silently admits WMP and `.wal` too. `tightenClassicCenterStackIfNeeded` was one such branch: it grew `circle`'s 192x82 borderless player to `Skin.mainWindowSize.height` on the mouse-up of the first click, and **closed with W213** by gating on `isRunningWMPUI`. The remaining four, in the order they are worth taking: (1) **`handleCenterStackWindowWillClose`** (`:2036`) slides windows and re-docks children on Classic geometry, and is reachable in WMP mode because our fallback EQ/playlist/spectrum windows do open there; (2) **`normalizedCenterStackRestoredFrame`** (`:5501`) rewrites restored PeppyMeter and NetworkMonitor heights by Classic rules — *exactly* the windows that wear a skin's borrowed frame in WMP mode, and `HostedWindowBorderLayout` already records an analyser coming back `387x219` where its siblings came back `321x145`, so these two rules may already be fighting; (3) `applyClassicVisualizationDefaults` (`:4610`) writes Classic visualization defaults during a WMP session; (4) `expectedMainHeightForCurrentHT` (`:5534`). **Do not gate them in one sweep.** Each is a shared-`App/` path and CLAUDE.md's rule binds: gate on the mode, prove Classic and Original are byte-identical, and measure each separately — (2) in particular needs `WMP_BORDER_TRACE=1` beside it, because whichever of the two rules currently wins is load-bearing for someone. Verify with `WMP_SIZE_TRACE=1` (its `MISMATCH` line fires exactly when a window is about to be forced off its own scene) and `WMP_PLACE_TRACE=1`. |

## Tier 1h — the borrowed window frame

**Empty.** W207 closed the frame's geometry, W208 its slot rules, and W209, W210 and W212 closed the
pixels: the borrowed frame is the donor view drawn whole with the skin's own content subtracted, a
donor's furniture is told from its border by the order it paints them, and a rack is reclaimed only
as far as the donor leaves it unpainted. All of them are in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md); the rules are in
`skills/wmp-skin-guide/SKILL.md` § *Every NullPlayer window in WMP mode is the skin's or is themed*,
and the case studies in
[`back-to-the-future-trilogy.md`](skills/wmp-skin-guide/reference/skins/back-to-the-future-trilogy.md)
and [`alienware-invader.md`](skills/wmp-skin-guide/reference/skins/alienware-invader.md).

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
| W135 | Small, real, individually cheap — the SDK audit's S4 table as one row | Per item below, measured 2026-09-11 over the 177 archives | Kept as one row because each item is an `inert()` or a read-through of a few lines, and splitting them would rank nine one-line changes above work that moves a screen. `<AUTOMENU>` (own element, **4 skins**) — the Quick Access Panel, no counterpart here, so `inert` rather than `unknown`. `authorVersion` on `THEME` (16) — metadata the skin chooser could show. `toolbarMargin` on `PLAYLIST` (14) — rides with W133. `scrollingDirection` on `TEXT` (13) — the marquee axis; W94 implemented one direction. `wordWrap` on `TEXT` (10) — W94 deliberately left the vertical clip open, so decide these two together. `effectCanGoFullScreen` on `EFFECTS` (10) — no full screen for the hosted rect, `inert`. `fontWeight` on `TEXT` (10) — the engine reads `fontStyle` only. `textLimit` and `editStyle` on `EDITBOX` (8 each) — one EDITBOX use case in the corpus, `plSearchEdit`. `showBackground` on `EFFECTS` (7) — interacts with W101's "do not fill the widget's rectangle". |
| W201 | An animated GIF whose frame image blocks are smaller than its logical screen is drawn at the screen's size | **27 files in 12 archives** of the 4,303 GIFs in the corpus, and `pharaoh/pyrevolver.gif` is the extreme — a 140x128 logical screen whose 16 frames are each a 21x16 block at 0,0, i.e. 6.7% of the declared area. The rest are within a few pixels of their screen (`Age_of_Mythology` 198x173 vs 193x172, `bruteforce` 289x111 vs 289x101, `xsn_sports` 205x70 vs 191x70, `Official_Xbox_MP71` 23x18 vs 16x10 ×6). Header scan of every `.gif` entry, first frame's image block against the screen descriptor | Opened 2026-09-16 by the pharaoh report. Its scarab mode's only route back to the player is `<button left="56" top="17" width="21" height="16" upToolTip="Sphinx mode" image="pyrevolver.gif" onClick="ToggleScarab(false);">`, and it draws as an **opaque black box measured at 21x30** over the scarab's face — the authored height is 16, and the area the frame block does not cover is painted rather than left alone. **The button still clicks** (driven live: a click at `66,25` returns to the sphinx view), so this is artwork, not input, and it is why the reporter read the scarab as a dead end. The cause is stated as an observation, not a diagnosis: the two candidates are the screen-versus-block size and the GIF's uninitialised screen area, and neither has been isolated. Check `Age_of_Mythology`'s `open_shutter.gif` before changing anything — it is already load-bearing for the one-shot terminator rule (`reference/skins/README.md`). |
| W66 | A `LISTBOX` has a control and nothing to put in it | **8 skins**, 16 uses, measured 2026-09-07 over 177 archives | Every one is `plListBox1`/`plListBox2`, a playlist chooser the skin fills from script by walking WMP's media collection (`getSelPlaylist()`). The control now exists, draws, and reports its selection; what it cannot do is have rows, because the object model answers nothing for `player.mediaCollection` — so a skin's `onLoad` appends nothing and the box is empty. That is a host-surface decision (what a `.wmz` may see of this player's library), not drawing work, and it is deliberately **not** faked with rows this player invented. Rank it with whatever answers the media-collection question. |
| W204 | Every view in a skin shares one script scope, so a second `scriptFile` silently overwrites the first's functions | **7 of 185 archives** declare two or more `scriptFile` programs that define the same top-level function name — `Plus! SlimLine`, `Sports` and `holiday_skin` collide on six each (`Init`, `OnOpenStateChange`, `OnPlayStateChange`, `EndVideo`, `StartVideo`/`OnClose`, `OnTimerTick`), `pharaoh` on two, `9SeriesDefault` and `corona` on `OpenMedia`, `portals` on `init`/`shutdown`. Scan of every `function <name>(` in each program a `scriptFile` names, decoded as `WMPTextDecoder` does; re-run it before ranking | Opened 2026-09-16 by the pharaoh report (W199/W200), which is the skin that makes it visible. One `JSContext` serves every view by design — `WMPScriptContext.restoreElements(for:)` swaps each window's live elements in for the length of its own transaction, because every view root is called `view` — but **a program's top-level functions are not swapped**, so the last `scriptFile` evaluated wins for the whole skin. `pharaoh.js` and `pharaoh_ros.js` each define `OnOpenStateChange`, `UpdateMetadata` and `vidIsRunning`; the rosetta's wins, so the *player's* `player.OpenState_onchange` runs the rosetta's handler and dies on the first identifier that view does not have: `SCRIPT-DIAG view-2 [handler-error] onLoad[0]: ReferenceError: Can't find variable: bgVid (line 50)`, reproducible with `WMP_SKIN=…/pharaoh.wmz WMP_RENDER_HOST=playing`. **It is invisible with a stopped player**, which is why no sweep has ever shown it — the handler's `else` branch touches nothing view-specific — so the three WMP7-scaffold skins above are the population to measure and a default-state capture cannot do it. `pharaoh`'s own symptom is bounded (its video pane never auto-opens) and the row is ranked on the other six. The shape of the fix is per-view function scope; what that costs a skin whose views deliberately share a helper is the question to answer first. |
| W149 | Controls still unreachable after W148, each for a different reason | `Sports` 7, `anime`, `STALKER`, `T3-Skynet_Media_Player`, `Plus! Professional` (container) — **11 total**, re-measured 2026-09-12 after W150 (was 16; `Gold`'s five containers and four others were the position-map half) | **Opened by W148 closing**, and it is the residue that rule does not explain rather than a regression from it: reproduce with `WMP_SKIN=<corpus> WMP_RENDER_HOST=playing WMP_RENDER_OCCLUDED=1` and read the `reached=rect-only` lines. **10 of the 16 are `<BUTTONGROUP>` *containers* with no mapping children** (`Gold`'s five stacked `drawerButton*` at one 144x123 rect, `The_Doobie_Brothers`, `Plus! SlimLine`, `Plus! Professional`), and a group with no `<BUTTONELEMENT>` dispatches nothing however it is ranked — **decide whether those should be hit targets at all before counting them as work**. The six that are real: `Sports`'s `eq2`–`eq8` sliders answer to `pl2`/`pl3`/`pl4` `<TEXT>` nodes drawn over them, which is the same question in reverse (a `<TEXT>` keeps its box because glyphs are not a hit shape — see `WMPHitCoverageBuilder`), and that skin trades 7 sliders for the 3 texts it gained; `anime`'s `plHandle` answers to `closepl`; `STALKER`'s `blankRate4` to a plain `<BUTTON>` while its other four stars work; `T3-Skynet_Media_Player`'s `timeSign` is authored at `x=-25` and is mostly off its own canvas. **Name the node before ranking the count** — the same rule `../harness.md` states for `unresolved`. |
| W67 | `.cur` and `.ani` cursors | **~70 uses**, a handful of skins (`resize.cur` 26, `over.ani` 23, `sizetopright.cur` 12, `size2_m.cur` 6) | The remainder after the named cursors landed: Windows cursor formats, which no macOS decoder reads. They resolve to no cursor rather than to a wrong one. Worth doing only with a `.cur`/`.ani` decoder, and worth almost nothing without one. |
| W203 | `<DURATIONTEXT>` never renders | **2 nodes in 2 archives** — `pharaoh` and `circle` — so this is a one-line row kept only because it is a *visible* readout on a shipped Microsoft skin | Opened 2026-09-16 by the pharaoh report. Its face reads `1:03 /` with nothing after the slash: `<currentPositionText>` at `57,86` and the literal `/` at `103,86` both draw and `<durationText left="108" top="86" width="45" fontSize="8" justification="Left">` produces no `PROBE` line at all, which is the view's single `unresolved`. `WMP_SKIN=…/pharaoh.wmz WMP_RENDER_UNRESOLVED=1 WMP_RENDER_HOST=playing` names the dimension: `UNRESOLVED view-2/11 durationText id=- size=missing literal geometry (height)`. **`<currentPositionText>` beside it declares no `height` either and resolves to 45x10**, so the missing piece is a glyph-height fallback this one tag does not get, not anything the skin failed to author — which also means a `<DURATIONTEXT>` anywhere is dead, not just this one. |
| W123 | A stretched `backgroundImage` and a natural-size foreground image draw the same bitmap at two different sizes | **1 view measured** (`Ice/videoView`) out of the 545-image corpus capture; the wider class is every `backgroundImage` whose frame is not its bitmap, unmeasured. Reproduce with `WMP_SKIN=…/Ice.wmz WMP_RENDER_PROBE=videoView` | **Opened 2026-09-09 by W122 closing.** `Ice` authors `<button image="Pl-xp.bmp" width="196" height="144">` over a bitmap that is really 196x**44**, inside `<subview id="Drawerbutton2" backgroundimage="Pl-xp.bmp" width="313" height="144">`. Both were stretched and therefore agreed; the button is now drawn at its own 196x44 and a seam appears in the lower shell. The question this row exists to settle is **what WMP does with a background whose frame is not its bitmap**, and it cannot be answered by extending W122: `Ice`'s own frame tiles all author `backgroundtiled="true"`, which suggests WMP does not stretch and a skin tiles deliberately — but `Vidcolorbox` is `horizontalAlignment="stretch" verticalAlignment="stretch"` with an untiled `Vid-bg.bmp`, and `LostPlanet`'s stretch tiles are 61 px of window frame that would punch through. Measure the class before changing the rule, and check `reference/skins/README.md`'s counter-evidence table first. |
| W145 | A borrowed window frame is rendered from markup, so it never follows the theme the skin is *set* to | **xsn_sports** measured 2026-09-12; the pattern is stacked variants, unmeasured across the corpus | `WMPHostedFrameTemplate` lends NullPlayer's own windows the skin's eight-piece ring (86 of 180 archives declare one), built through `WMPSceneBuilder` from markup alone. A skin whose colour scheme is a *script* decision therefore always gets its opening one. `xsn_sports` stacks all eight frame variants in `plView` (`pl1_1`…`pl1_8`, 2-8 at `alphaBlend="0"`) and cross-fades between them from `htcpStartupPl()`, reading the `htcpID`/`winAlpha` preferences in the view's own `onLoad` — "Hyper-Transient Color Phasing", per the notice in `xsn.js`. Reported as "the NullPlayer window does not follow the colour theme selected in xsn". **The fix is to run the donor view's `load` off-screen** (`WMPScriptRuntime.transact`, whose overrides `dispatch` deliberately discards) and build the ring with the overrides it commits, re-running when the skin's preferences change; the template must then keep *every* candidate per ring role rather than the first declaration. It settles on the chosen colour and does not animate the phase — running a closed window's timer to match a cross-fade is out of proportion to what it buys. |

## Closed

Closed entries live in [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md),
verbatim and with their evidence. Move a row there in the same change that closes it — one left here
reads as open work.
