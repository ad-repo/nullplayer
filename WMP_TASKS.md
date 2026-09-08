# Windows Media Player (`.wmz`) — ranked open backlog

This is the only live backlog for the WMP skin subsystem. It is the `.wmz` counterpart to
[`WINAMP5_TASKS.md`](WINAMP5_TASKS.md), and the two never share entries: a `.wmz` item goes here, a
`.wal` item goes there. Read `skills/wmp-skin-guide/SKILL.md` before picking anything up.

A skin is a test case, not a milestone: take measured capability work from the top down. Closed
entries move to [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) in the
same change that closes them, so this file stays a list of work that is still open.

## Ranking

Reach is corpus demand across the 14-skin corpus installed in
`~/Library/Application Support/NullPlayer/WMPSkins/`, not severity. Every Reach number must be
reproducible by a command recorded next to it.

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
| W9 | `Official_Xbox_XP` paints an opaque black `VIDEO` placeholder over its own art | 1 skin measured | `census/png/Official_Xbox_XP/mainBox@1x.png`. Fixed by Phase 5's hosted video surface. |
| W57 | A playlist frame's own black backing shows through once the view is made taller | WoW `plView`, found by dragging the real window; not yet counted corpus-wide | `plFrame` is `<SUBVIEW backgroundColor="#000000" height="JScript:view.height-74">` and the playlist drawn over it does not cover all of it: at the authored 453x264 there is no gap, at 653x364 a ~265x105 black band opens inside it. **Reproduces headlessly** — `WMP_SKIN=…/WoW.wmz WMP_RENDER_SIZE=653x364 WMP_RENDER_DUMP=<dir>` — so it is a scene defect, not the AppKit overlay: the dumped PNG and a screen capture of the same window rect agree. Not a resize-plumbing defect (the frames all resolve correctly; `PROBE` shows `plFrame` at `40,44 466x290` as authored) and not the alignment double-count W-fix above. Establish what WMP draws over that backing — `playlist1.height` is `plFrame.height` and `playlist2.height` is `plFrame.height-20`, so the band is likely the difference between the two playlist elements rather than a missing fill. Count the corpus reach before ranking it: every skin with a `backgroundColor` subview under a playlist is a candidate. |

## Tier 1c — live-reported, 2026-09-07, not yet reproduced headlessly

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

| ID | Item | Reach | Notes |
|---|---|---|---|
| W37 | `mediacenter` is not a host object | **102 of 171 loading skins** | `ReferenceError: Can't find variable: mediacenter`. By far the largest single cause left, and it is one object: the corpus reads `mediacenter.effectType`/`.effectPreset` (73 each) and calls into it from `onLoad`. Decide what it can honestly answer before implementing — a recognised-but-stubbed object here would be invisible in the tally, which is the trap `INERT` exists for. |
| W38 | `alphaBlendTo` on an element | **~18 skins** (`vidBack` 14, `timeColon` 4, `mainBack2` 2, …) | The third of WMP's element animation methods beside `moveTo`/`resizeTo`, which are implemented as immediate endpoints; the same treatment applies — set the alpha now, track the tween as rendering work. It is already in `elementMethodVocabulary`, so it reports as `UNRECOGNISED` demand rather than dying as a bare `TypeError`. Same for `setColumnWidth` (2 skins). |
| W39 | `eq.speakerSize` | 18 skins | Plus `eq.enableSplineTension` and `eq.enhancedAudio` at 1 each. WMP's speaker/spatial settings; the engine has no equivalent, so this is an honest `inert()` candidate rather than a feature. |
| W40 | An element the skin names is in another view | 4 + 2 + 2 skins | `Can't find variable: pl`, `playlistframe.setColumnResizeMode (no such element)`, `pl.setColumnWidth`. Handlers are now scoped per view, but a script's *globals* are the current view's elements only. Find out what WMP does with a cross-view reference before choosing. |
| W41 | `theme.closeView` | 5 skins | Also `player.currentMedia.sourceURL` (4). Both are small and both are real. |
| W42 | A skin function is missing because its program never registered | ~12 skins, 1–2 each | `skin_init`, `loadVidPrefs`, `UpdateMetaData`, `checkForContent`, `Init`, `gears`… Each is one skin's own function, so the cause is upstream: a `.js` that failed to resolve, evaluated with an error, or is a `res://` entry. Diagnose from `SCRIPT`/`SCRIPTS` lines before writing any object-model code. |
| W50 | `theme.openViewRelative` is not implemented | **2 skins** (`Revert.wmz`, `Revert (1).wmz`, the two releases of the same skin), measured 2026-09-07 over the 180 archives in `WMPSkins/` | `UNKNOWN member theme.openviewrelative ×4`. WMP's placing variant of `openView`: `theme.openViewRelative('vwEQ', 0, 130)` opens the view as a window offset from the current one's top-left, which is how Revert hangs its EQ under the player and its playlist beside it. Found while closing W49 and **deliberately left out of it**: aliasing it to `openView` would present the view in the one window, drop the offset, and disappear from the tally — the trap `INERT` exists for. It is only worth doing with somewhere for a second window to go, so rank it with whatever answers that question, not before. Reproduce by sweeping the corpus and reading `UNKNOWN member` lines. |

### 2c. Events the markup declares and nothing ever raises

`WMPAttributeParser.handlerNames` decides what becomes a `.handler` at all, and
`WMPCorpusReportHarness.supportedEvents` decides what counts as implemented — an event needs a name
in the first **and a dispatch site** to be either. Neither list was ever printed by the harness, so
this whole class was invisible: `WMPCompatibilityReport` collected the counts and compared them and
`compatibilityLines` emitted only tags and members. That is how `onResize` sat unrecognised through
three phases. It is now `UNKNOWN event <name> ×<n>`, and the numbers below come from it.

**Reproduce**: `scripts/wmp_render_sweep.sh capture <dir> --allow-dirty`, then tally
`UNKNOWN event` in `<dir>/raw.txt` by name and by containing `SKIN` block. Measured 2026-09-07 over
the 179 measured archives: **140 distinct events, 6,823 uses**. `onresize` is absent from this list
because it closed in the same change that added the instrument.

An entry here is markup asking for something. Two things make it work: classification (one line) and
a dispatch site (the real cost, and different per event). Do not add a name to `handlerNames` or
`supportedEvents` without its dispatch site — a recognised event nothing raises drops out of this
table while still doing nothing, which is exactly the state `onResize` was in.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W51 | `value_onchange` is not an event | **2,170 uses across 175 of 179 archives** | The single largest piece of measured demand anywhere in this engine, and near-universal. WMP raises it when an element's `value` changes — the seek bar, the volume slider, an EDITBOX. The engine already has the change path (`onElementValueChanged` → `dispatchScriptEvent(name: "change")`), so the question is whether `value_onchange` is that same event under WMP's other spelling or a distinct per-property notification. Establish that from the corpus's own handlers before writing anything: the `_onchange` family is *property*-scoped (`height_onchange`, `enabled_onchange`, `selecteditem_onchange` all appear), which suggests a general `<property>_onchange` mechanism rather than 140 separate events. If it is general, one dispatch site closes most of this table. |
| W52 | `openstate_onchange` / `playstate_onchange` are the spellings the corpus actually uses | **293 uses / 144 skins** and **287 / 139** | The engine implements `openstatechange` and `playstatechange` — which are authored by **7** and **11** skins. The dispatch already exists and fires (`refreshHostState`); this is the two names, and it is the cheapest large win in the table. Confirm they are aliases and not a different payload before aliasing them. |
| W53 | Keyboard events | `onkeydown` 501/78, `onkeypress` 409/72, `onkeyup` 94/30 | `WMPMainView.keyDown` handles focus traversal and activation and raises no authored handler. Needs a key-code/character contract at the object-model boundary — decide what a skin may see of a keystroke before implementing. |
| W54 | Hover events are parsed and never raised | `onmouseover` 324/71, `onmouseout` 307/24 | Already `.handler`s (`WMPAttributeParser`), correctly **not** in `supportedEvents`, and no call site raises them: `WMPMainView.updateHover` changes artwork state only. The capture model is already in place, so this is a dispatch site and the hover/exit edges, not new machinery. `onmousemove` (207/16), `ondblclick` (104/50), `onfocus` (73/10), `onblur` (46/10) are the same shape. |
| W55 | Animation and drag completion callbacks | `onendmove` 244/114, `ondragend` 138/86, `onendalphablend` 57/22 | The completion half of `moveTo`/`resizeTo`/`alphaBlendTo`, which are implemented as immediate endpoints (see W38). A skin chains its next step from these, so an unimplemented one is a sequence that stops after step one. Rank with W38 — the tween and its completion are one piece of work. |
| W56 | Video and playback-position events | `onvideostart` 190/140, `onvideoend` 132/130, `onpositionchange` 147/41, `currentposition_onchange` 103/80 | `onvideostart`/`onvideoend` reach 140 and 130 skins because the standard WMP template wires them; both need the hosted video surface (Phase 5, W9) before they can be honest. The position pair may fall out of W51 if `_onchange` is general. |

### 2b. Recognised, answered, and nothing behind them (`INERT`)

These do **not** stop a handler; they are the ranked list of "properties skins set that nothing
renders", which is Phase 5 rendering work rather than runtime work. Top by skins:
`playlist1.itemPlayingColor` / `.itemPlayingBackgroundColor` / `.disabledItemColor` (15 each),
`vidback.alphaBlendTo` (14), `timeN.upToolTip` (10 each), the `playlist1.itemSelected*` family (9
each). Full column: `inert_calls` in `census.tsv`.

## Tier 3 — drawing the skin's own controls (Phase 5)

Tracked in the recovery plan until the corpus loads and the census can rank these by measured reach.

## Closed

Closed entries live in [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md),
verbatim and with their evidence. Move a row there in the same change that closes it — one left here
reads as open work.
