# Windows Media Player (`.wmz`) — ranked open backlog

This is the only live backlog for the WMP skin subsystem. It is the `.wmz` counterpart to
[`WINAMP5_TASKS.md`](WINAMP5_TASKS.md), and the two never share entries: a `.wmz` item goes here, a
`.wal` item goes there. Read `skills/wmp-skin-guide/SKILL.md` before picking anything up.

A skin is a test case, not a milestone: take measured capability work from the top down.

## Ranking

Reach is corpus demand across the 14-skin corpus installed in
`~/Library/Application Support/NullPlayer/WMPSkins/`, not severity. Every Reach number must be
reproducible by a command recorded next to it.

**Reach numbers below are `scripts/wmp_skin_census.sh` output, measured 2026-09-07 at rev
`1d7e63bd` over the 180 archives in `WMPSkins/`.** Reproduce with
`scripts/wmp_skin_census.sh /tmp/wmp/census`. **171 of 180 load, and 482 views lay out.**

Numbers taken before rev `61f8955a` were measured with an instrument that dropped three blocks of
its own output (W35), so a count from an earlier capture is short by an unknown amount rather than
merely stale.

The corpus grew from 14 archives to 180 on 2026-09-07, so **every number taken against the 14-skin
denominator is stale and none of them were rewritten in place.** A count here without the 180-archive
stamp has not been re-measured; re-measure it rather than scaling it. Two byte-identical archives were
deleted; five *name*-similar pairs (`Ginger Man`/`Ginger_man`, `QuickSilver`/`(2)`, `Revert`/`(1)`,
`Project Gotham Racing 2`/`(1)`, `The Unit`/`TheUnit`) are different releases of the same skin with
differing `.wms` and `.js`, and are kept deliberately as separate test cases.

## Tier 1 — loading, and views that load then draw nothing (171 of 180 archives load)

### 1a. The 9 rejections

| ID | Item | Reach | Notes |
|---|---|---|---|
| W31 | `WMP0021` "one `.wms` at root or inside one wrapper directory" is too narrow | **4 of 9 rejections** | `bruteforce`, `Need_for_Speed_Underground`, `QuantumRedshiftWMPSkin`, `SplinterCellWMPSkin`. Inspect the actual layouts before widening the rule; two wrapper levels and a `.wms` beside a subdirectory are both plausible. |
| W32 | `WMP0022` multiple `.wms` in one archive has no selection rule | 2 | `Nautical`, `Sports`. WMP does pick one. Find out how before inventing a rule. |
| W33 | `WMP0015` oversized image | 3 | `Ice`, `pharaoh`, and `The_Doobie_Brothers`, which reached this only once W30 stopped rejecting it earlier: `vol_anim.bmp` declares 9152×45, past the 8,192 bound. A filmstrip that wide is an ordinary WMP authoring idiom, so check what the bound is protecting against a *strip* before widening it — 9152×45 is 412 Kpx, nowhere near the 32 Mpx area bound that sits beside it. |

### 1b. Views that load and then draw nothing

Still the largest single class, and indistinguishable from a rejection to anyone using the app.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W6 | A view whose size is computed in script must still lay out | **84 views across 46 skins** (`WMP0032`) | "View requires positive literal width and height for static layout." **12 skins load and produce zero layouts** (`aoe`, `bluegrid`, `cerulean`, `circle`, `claw`, `cyberchannel`, `Darkling`, `digitaldj`, `iconic`, `Miniplayer`, `Radio`, `YIL!OMA2K`) — 17 before W7 landed, then 11, then 12 as W30 let `cyberchannel` in far enough to reach this. It is now the **only** cause left of a skin that loads and draws nothing, and the count will keep rising as the remaining nine rejections clear: a probe cannot see a defect in a skin it rejects. Phase 4 work; ranked in Tier 1 because it is a total blackout. |
| W34 | `WMP0033` image decode failed | 4 views, 4 skins | |
| W8 | A view draws its transparency key instead of keying it out | **23 views across 21 skins** | Re-measured at rev `1d7e63bd` by counting opaque `#FF00FF` in every dumped PNG, not by reading a census column — a structural probe cannot see this. Worst: `Plus! Mecha/mediaSwitcherView` 44.6%, `Main_Street/mini` 40.5%, `Plus! Professional/mediaSwitcherView` 33.1%, `polygon/view-2` 33.0%, `deepbluesomething/MainPlayer` 31.8%, `Ducky/view-2` 28.3%; threshold 5% of view area. `Alpine7618_v09/view-2` was the first case found and is below that threshold. Class B, and much larger than the single skin it was filed as. |
| W9 | `Official_Xbox_XP` paints an opaque black `VIDEO` placeholder over its own art | 1 skin measured | `census/png/Official_Xbox_XP/mainBox@1x.png`. Fixed by Phase 5's hosted video surface. |

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

| ID | Item | Landed |
|---|---|---|
| W20 | One persistent `JSContext` per skin session, replacing the fresh-process-per-transaction model | Phase 3 — `WMPScriptRuntime` + `WMPObjectModel`, with `Sources/WMPScriptIsolationHelper/` and its `Package.swift`/`assemble_app.sh`/signing/verification wiring retired in the same change, recorded as **Amendment 2** to the Phase 0 decision record including what the process boundary bought that is genuinely weaker now. Proven on Corona: `OnLoad` runs to completion (ten `eq.presetTitle`, ten `popupPreset.appendItem`, `ipl.setColumnResizeMode` ×3, `theme.loadPreference` ×3) with **zero** script diagnostics, and two clicks on `bPlaylist` open the playlist pane and then close it again — state held between events, which the old model could not do at all. |
| W21 | The probe pass evaluated expressions with no scripts loaded | Phase 3 — expressions now run in the same context the skin's programs were evaluated in, so `JScript:GetEqSliderLeft(1)` resolves; a failing expression costs itself alone instead of emptying the ordered list, and a cycle costs only the keys inside it. Corpus-wide the whole class is down to **1 `expression-error` and 8 `invalid-geometry` across 482 views**. Three semantics came out of measuring rather than reasoning: the owning element is in scope (`svBottomLeft.width-left`), the `with` proxy must answer `has` only for properties the element genuinely owns (claiming every name swallowed `GetEqSliderLeft` and cost all ten equaliser sliders their geometry), and the corpus authors a trailing `;` inside the attribute. |
| W22 | `theme.loadString` | Phase 3 — implemented as `inert()`: every corpus use names a string inside `wmploc.dll`, which does not exist on macOS, so the empty string is the whole of what can honestly be answered. It gets its own `INERT` word in the call trace and its own `inert_calls` census column, because a stub that reads as working is worse than a missing member. |
| W10 | `WMP_SKIN=<path>` accepts a **directory**, sweeping the corpus in one process | Phase 1 |
| W11 | The nine probe flags, documented canonically in `skills/wmp-skin-guide/reference/harness.md` | Phase 1 |
| W12 | `scripts/wmp_skin_census.sh` and `scripts/wmp_render_sweep.sh` | Phase 1 — 14 rows, 18 PNGs, both halves of `compare` proven against a change that can be seen |
| W2 | `WMPXML`: the `XMLParser` wrapper replaced with a port of `WalLenientXMLParser` | Phase 2 — **14 / 14 archives load**, from 10. Attributes keep document order and authored spelling; duplicates collapse last-wins with a `WMP0034` warning (19 occurrences corpus-wide — a hand-written regex over the same four files found 3, which is the argument for the instrument); a tag left open at EOF is a `WMP0036` warning that keeps its children. All 18 pre-existing PNGs byte-identical; the only invariant movement is that diagnostic locations now point at the `<` rather than at the end of the tag, verified against `corona.wms:42`. |
| W1 | `WMPTextDecoder`: cp1252 (already present) plus a BOM-less UTF-16 sniff | Phase 2 — added to **both** engines, positional rather than statistical, because an `iconv`-style density guess cannot tell the two byte orders apart. It claims nothing in either corpus today and is not why anything loads. It is there because neither fallback can *fail*: Windows-1252 and `isoLatin1` accept every byte sequence, so such a file decodes into null-interleaved mojibake instead of reporting a wrong guess (`.wal` B93). `.wal` is a shipped mode, so that half is measured, not reasoned about: across all 80 installed `.wal` archives, 827 of 2,384 XML and script entries are not valid UTF-8 and so reach the changed fallback, and the sniff claims **none** — the `.wal` decode path is byte-identical. |
| W3 | `WMPNode`: the case-insensitive tag fold covers every comparison | Phase 2 — verified, no change needed. Every consumer routes through `WMPElementKind(tagName:)` (which lowercases), `WMPPath.fold` for ids, or `caseInsensitiveCompare` for attributes; `authoredTagName` is only ever displayed or counted. |
| W4 | `WMPAttributeValue`: an unresolvable `res://` entry skipped with a diagnostic, siblings still loaded | Phase 2 — verified already working. `WMPSkinLoader` splits a `scriptFile` list on `;` and tests each entry, so Corona's `res://wmploc.dll/RT_TEXT/#132` warns as `WMP0029` and its four real programs still register. |
| W5 | The installed corpus wired into `swift test` as a **default-on** target | Phase 2 — `WMPCorpusLoadTests` reads `WMPSkins/` and skips only when it is absent. It asserts whole-corpus, naming every rejected archive with its diagnostic, and a second test asserts the deterministic graph dump is identical across two loads. `swift test`: 1998 passed, 0 skipped. |
| W30 | `WMP0005`'s ratio bound applies only above a 1 MiB size floor | Phase 3 — recorded as **Amendment 1** to the Phase 0 decision record, not edited in. 200:1 and `WMP0005`'s meaning both stand; the bound is simply not asked about entries below `entryCompressionRatioFloorBytes`. A ratio is not the quantity a bomb is dangerous in — expanded bytes is, and `WMP0003`/`WMP0004` already cap it — while below the floor a ratio measures how *uniform* a file is, and an uncompressed flat-colour BMP squashes 240:1 to 850:1 by being boring. Every entry over 200:1 in all 180 archives is a `.bmp`; largest expands to **842,636 bytes** (`Israeli/map.bmp`), worst ratio **847:1** (`anime/background_blank.bmp`), against a 32 MiB entry bound. Effect: archives loading **159 → 171**, layouts **469 → 482**, 12 of the 13 draw. Collateral: all 469 pre-existing PNGs byte-identical, 13 new, none lost. `The_Doobie_Brothers` trades `WMP0005` for a genuine `WMP0015` the rejection had been hiding (W33). Both halves proven by fixture: `small-high-ratio.wmz` (64 KiB, ~830:1) admitted, `excess-ratio.wmz` (2 MiB, ~1000:1) still rejected. Baseline re-recorded — 180 rows now, from 177, because W35 was dropping three of them. |
| W7 | An **empty** resource attribute costs one image, not the whole view | Phase 3 — `WMPResourceProviding.resolve` now returns nil for an empty authored path instead of throwing `WMP0024`. An empty attribute names no entry, which is what every caller already means by "no such resource"; it is an authoring omission, not a sandbox escape, and the loader has always warned `WMP0023 Optional image resource is empty` for the same attribute — only the view's survival was missing. Measured over 180 archives: **`WMP0024` 40 → 0**, layouts **429 → 469**, and six skins that drew literally nothing (`Beck`, `Melvin`, `MSN`, `Spider-man`, `springflower`, `tubeframe`) now draw. Collateral: all **429** pre-existing PNGs byte-identical, 40 new, none lost; `WMP0032` unmoved at 82. Not taken on trust — `springflower/base@1x.png` and `tubeframe/TubeFrameView@1x.png` were opened and show real skins. `testAnEmptyResourceAttributeCostsOneImageAndNotTheView` was proven by reverting the one-line guard and watching it fail on `[WMP0024]`. |
| W35 | The harness stopped losing its own measurements | Phase 3 — every harness line is now one unbuffered `write(2)` (`WMPHarnessOutput.emit`) instead of `print`. The 180-archive run lost **three** blocks, not one: `CALL vSKIN Windows_XP_Media_Center_Edition.wmz` cost the Enhanced_for_XPS9 block and swallowed the next skin's, and `amped2` and `Plus! Hard Boiled` were truncated with **no splice at all** — the collision consumes the record prefix a prefix-scan needs, so the detector saw one of three. Byte-identical across two full sweeps and absent on a two-archive corpus, so it was the buffered stream, not the content. After: `load failed=21, ok=159`, zero damaged, zero not-run, and the recovered blocks match their solo runs line for line. Both scripts additionally now check each loaded block's `RENDER-DUMP` count against the `views=` its own `LOAD` declares, which flags `amped2` on the old capture and nothing on the new one. `testEmitsEveryLineWholeUnderConcurrentWriters` proves the emitter, and was itself proven by splitting one write in two and watching it fail. |
| W36 | The corpus gate converted from an absolute to a **ratchet** | Phase 2 — the corpus grew to 180 and 21 rejections turned the suite red. `Fixtures/WMPSkin/corpus-baseline.tsv` records the outcome per sha256; a recorded `ok` that now fails is a regression and fails the suite, a recorded `failed` that now loads asks for a re-record, an unrecorded archive never fails the build. Re-record with `scripts/wmp_corpus_baseline.py <census outdir>` **only after improving the loader**. Proven against a regression it should catch, not just observed passing. |
