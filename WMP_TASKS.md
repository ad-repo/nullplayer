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
`scripts/wmp_skin_census.sh /tmp/wmp/census`. **180 of 180 load, and 515 views lay out**, re-measured
at rev `9939e871` after W33; a row below that still cites 177/508, 175/506 or 171/482 was not
re-measured then.

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

Still the largest single class, and indistinguishable from a rejection to anyone using the app.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W6 | A view whose size is computed in script must still lay out | **89 views across 48 skins** (`WMP0032`), re-measured at rev `9939e871` | "View requires positive literal width and height for static layout." **12 skins load and produce zero layouts** (`aoe`, `bluegrid`, `cerulean`, `circle`, `claw`, `cyberchannel`, `Darkling`, `digitaldj`, `iconic`, `Miniplayer`, `Radio`, `YIL!OMA2K`) — 17 before W7 landed, then 11, then 12 as W30 let `cyberchannel` in far enough to reach this. It is now the **only** cause left of a skin that loads and draws nothing, and the count rose every time the remaining rejections cleared: a probe cannot see a defect in a skin it rejects. W31 alone added two views (`Need_for_Speed_Underground/mediaSwitcherView`, `controlView`) and one skin; W32 moved neither number, since both archives it admitted lay their views out; W33 added **3 views and 1 skin**, all of them `pharaoh` (3 of its 4 views fail; `Ice` and `The_Doobie_Brothers` lay every view out). That inflation is over — there are no rejections left to clear, so from rev `9939e871` this count only moves when the defect itself does. Phase 4 work; ranked in Tier 1 because it is a total blackout. |
| W34 | `WMP0033` image decode failed | 4 views, 4 skins | |
| W8 | A view draws its transparency key instead of keying it out | **37 views across 34 skins** | Re-measured at rev `9939e871` over all 515 dumped PNGs by counting *opaque* key-coloured pixels, not by reading a census column — a structural probe cannot see this, because a view that draws its key is structurally perfect. Threshold 5% of view area. **The key is not always magenta**, which is why the previous figure of 23 views across 21 skins was short by a third: scanning `#FF00FF` **and** `#FF0000` separately finds **11 views that are pure red with no magenta at all**. Worst overall: `v2_underworld/start` 74.7% red, `Cubist/view-2` 54.2% red, `pharaoh/view-2` 51.0% red, `The_Doobie_Brothers/view-2` 50.4% magenta, `Plus! Mecha/mediaSwitcherView` 44.6%, `Main_Street/mini` 40.5%, `Plus! Professional/mediaSwitcherView` 33.1%, `polygon/view-2` 33.0%, `gadget/view-2` 32.8% red, `Tomb Raider 2/view-2` 32.0% red. `Alpine7618_v09/view-2` was the first case found and is below the threshold. W33 added three of these (`pharaoh`, `The_Doobie_Brothers`, `Ice`) by admitting the skins at all. Do not hard-code the two colours into the fix or the next measurement — the key is whatever the markup declares. Class B, and far larger than the single skin it was filed as. |
| W9 | `Official_Xbox_XP` paints an opaque black `VIDEO` placeholder over its own art | 1 skin measured | `census/png/Official_Xbox_XP/mainBox@1x.png`. Fixed by Phase 5's hosted video surface. |

## Tier 1c — live-reported, 2026-09-07, not yet reproduced headlessly

Found by the reporter driving the real app on `corona.wmz` during Phase 3 live QA, after the drawers
and the file-open button were confirmed working. **None of these is visible to the harness**: the
headless render of `vPlayer` and `viewTiny` is correct in every state tested, including with the view
timer running and with the equaliser drawer open. That is the whole point of the entries — the
sweep's blind spots are AppKit hosting, hit testing under the pointer, and anything driven by live
playback. Reproduce by driving the app; a census row will not show any of them.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W43 | **The player goes black while a track plays** | corona, live | The skin draws correctly until playback starts. Suspects, in order: `WMPEffectsSurfaceView` fills its whole bounds with `calibratedWhite: 0.04, alpha: 0.9` before drawing bars, so a wrong or oversized effects frame paints a near-opaque box; `WMPVideoPlaceholderView` is opaque black and is created for any `VIDEO`/`WMPVIDEO` widget whose frame resolves, which is [W9] in another skin; and the widget overlays ignore `WMPWidget.clipRect` entirely, so a pane clipped out of the scene still shows its AppKit view. Start by dumping the widget frames — `WMP_RENDER_PROBE` now emits a `WIDGET` line per widget with `frame`, `clip` and the resolved `visible` rect — and compare them against what is on screen. A script's `visible` now outranks the markup in the builder, which was one cause and is fixed; this is what is left. |
| W44 | **Four different buttons in the top cluster all open the file dialog** | corona, live | `bOpenFile`, `bPlaylist`, `bVis` and `bEq` are `BUTTONELEMENT`s inside one `BUTTONGROUP`, separated only by their `mappingColor` in `player_top_controls_left_map.bmp`. A coordinate scan along `y=12` resolves them correctly and distinctly (`WMP_RENDER_CLICK="vPlayer@366,12;400,12;420,12;444,12"` gives `bOpenFile`, `bPlaylist`, `bVis`, `bEq`), so the mapping table is right at that row — check other rows before assuming the sampler is wrong. The other candidate is dispatch rather than hit testing: `dispatchScriptEvent(name:targetID:)` filters handlers by `xmlID`, and a `nil` `targetID` runs **every** `onClick` in the view, one of which is `OpenMedia()`. Confirm which by clicking each button once with `WMP_RENDER_CLICK` and reading the `handlers=` count. |
| W45 | **No way to reach the compact view from the skin** | corona, live | `ToggleSuperCompact()` sets `theme.currentViewID = "viewTiny"`, which the object model maps to a `setCurrentView` host command, and `switchView(to:)` implements it. It is reached from a button that is probably one of W44's, so W44 may be the whole of this. The menu route — **Skins → Windows Media Player → Views → viewTiny** — does work and is the fallback while this is open. |

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
