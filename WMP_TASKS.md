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
`891d5f85` over the 180 archives in `WMPSkins/`.** Reproduce with
`scripts/wmp_skin_census.sh /tmp/wmp/census`. **159 of 180 load.**

The corpus grew from 14 archives to 180 on 2026-09-07, so **every number taken against the 14-skin
denominator is stale and none of them were rewritten in place.** A count here without the 180-archive
stamp has not been re-measured; re-measure it rather than scaling it. Two byte-identical archives were
deleted; five *name*-similar pairs (`Ginger Man`/`Ginger_man`, `QuickSilver`/`(2)`, `Revert`/`(1)`,
`Project Gotham Racing 2`/`(1)`, `The Unit`/`TheUnit`) are different releases of the same skin with
differing `.wms` and `.js`, and are kept deliberately as separate test cases.

## Tier 1 — loading, and views that load then draw nothing (159 of 180 archives load)

### 1a. The 21 rejections

| ID | Item | Reach | Notes |
|---|---|---|---|
| W30 | `WMP0005` compression-ratio bound rejects flat-colour BMPs | **13 of 21 rejections** | `anime`, `Crystalball`, `cyberchannel`, `iMusica`, `Israeli`, `Jaws`, `Kids`, `Main_Street`, `Mandalay`, `Primitive`, `The_Doobie_Brothers`, `Thomas`, `Utomjording`. Every one is an uncompressed BMP of a flat colour — a blank background or a mapping image — which naturally compresses 240:1 to 850:1. Measured worst case: `anime/background_blank.bmp` at 847:1 expanding to **244 KB**, in an archive expanding to 2.5 MB. **A ratio is the wrong quantity for a decompression bomb; absolute expanded size is, and `WMP0003`/`WMP0004` already bound it.** `WMPPhase0Limits` and `WMP0001`–`WMP0020` are locked by the Phase 0 decision record, so this needs a recorded decision, not an edit — but the evidence says the limit is mis-specified against its own threat model, not that these 13 skins are hostile. |
| W31 | `WMP0021` "one `.wms` at root or inside one wrapper directory" is too narrow | 4 | `bruteforce`, `Need_for_Speed_Underground`, `QuantumRedshiftWMPSkin`, `SplinterCellWMPSkin`. Inspect the actual layouts before widening the rule; two wrapper levels and a `.wms` beside a subdirectory are both plausible. |
| W32 | `WMP0022` multiple `.wms` in one archive has no selection rule | 2 | `Nautical`, `Sports`. WMP does pick one. Find out how before inventing a rule. |
| W33 | `WMP0015` oversized image | 2 | `Ice`, `pharaoh`. |

### 1b. Views that load and then draw nothing

Still the largest single class, and indistinguishable from a rejection to anyone using the app.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W6 | A view whose size is computed in script must still lay out | **84 views** (`WMP0032`) | "View requires positive literal width and height for static layout." **17 skins load and produce zero layouts.** Phase 4 work; ranked in Tier 1 because it is a total blackout. |
| W7 | An **empty** resource attribute must warn, not kill the view | **41 views** (`WMP0024`) | `Resource path '' is absolute, drive-qualified, or invalid` rejects the whole view. The cheapest large win in the tier: degrade with a diagnostic. |
| W34 | `WMP0033` image decode failed | 4 | |
| W8 | `Alpine7618_v09` draws its transparency key instead of keying it | 1 skin measured | `census/png/Alpine7618_v09/view-2@1x.png`: art in the lower ~150 px of a 517×412 view, flat `#FF00FF` above. Class B. |
| W9 | `Official_Xbox_XP` paints an opaque black `VIDEO` placeholder over its own art | 1 skin measured | `census/png/Official_Xbox_XP/mainBox@1x.png`. Fixed by Phase 5's hosted video surface. |

### 1c. The harness eats its own output

| ID | Item | Reach | Notes |
|---|---|---|---|
| W35 | `WMP_CALL_TRACE` lines interleave with the sweep's own records | 1 line per run, **deterministic** | In the 180-archive run, `CALL v` and `SKIN Windows_XP_Media_Center_Edition.wmz` landed inside one another as `CALL vSKIN Windows_XP_Media_Center_Edition.wmz`. One lost line cost **two** rows: the containing block is flagged `damaged` and the swallowed skin reads `not-run`. It reproduces identically across runs on a 3-archive corpus, so it is buffering, not a race — the trace writer and the record writer flush independently. Phase 3 adds far more tracing; fix this before it does. The census flagging it is the instrument working, but the rows are still lost. |

## Tier 2 — the script runtime cannot hold state (Phase 3)

**Ranked host-member demand, measured over the 180-archive corpus** (`UNKNOWN member` tallies from
`WMP_CALL_TRACE=1`). This list *is* the Phase 3 backlog; work it top-down and re-measure after every
change, because each member added lets the scripts run further and surfaces the next one.

| Member | Skins | | Member | Skins |
|---|---|---|---|---|
| `view.close` | 148 | | `theme.savePreference` | 92 |
| `player.openState` | 145 | | `metadata.textWidth` | 91 |
| `player.currentMedia.imageSourceWidth` | 144 | | `metadata.scrolling` | 91 |
| `player.launchURL` | 121 | | `theme.loadPreference` | 90 |
| `view.returnToMediaCenter` | 116 | | `player.currentMedia.imageSourceHeight` | 90 |
| `view.minimize` | 115 | | `metadata.width` | 90 |
| `eq.reset` | 112 | | `eq.previousPreset` | 88 |
| `metadata.value` | 98 | | `theme.openView` | 85 |
| `player.URL` | 95 | | `view.size` | 81 |
| `theme.openDialog` | 93 | | `player.controls.isAvailable` | 80 |
| `eq.nextPreset` | 93 | | `theme.closeView` | 79 |
| `eq.currentPresetTitle` | 93 | | `mediacenter.effectType` / `.effectPreset` | 73 each |

`vidset.brightness` / `.contrast` / `.hue` / `.saturation` (52–64 each) and `player.settings.volume`
(56) follow. Note `metadata.*` and `vidset.*` are **element-id globals**, not host objects — more
evidence for the "every element id is a global" contract.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W20 | One persistent `JSContext` per skin session, replacing the fresh-process-per-transaction model | all skins ship JScript; `script_runtime=available` on all 158 measured | Retire `Sources/WMPScriptIsolationHelper/` and its `Package.swift`/`assemble_app.sh`/packaging-check wiring **in the same change**. |
| W21 | The probe pass evaluates expressions with no scripts loaded | Corona: every `eq*.left` fails `ReferenceError: Can't find variable: GetEqSliderLeft` | `WMPPhase5Session.transact` sends `scripts: []` in its topology probe, and one failure empties the whole ordered list, so **no** expression evaluates. |
| W22 | `theme.loadString` | Corona `OnLoad` aborts on it | The first member that actually stops a handler. |

### Unimplemented elements, same corpus

`effects` 150 · `videosettings` 87 · `customslider` 84 · `controls` 74 · `pauseelement` 66 ·
`prevbutton` 47 · `playbutton` 47 · `nextbutton` 46 · `stopbutton` 44 · `currentpositiontext` 14 ·
`itemsplaylist` 12 · `progressbar` 11 · `editbox` 10 · `listbox` 9 · `statustext` 7 · `mutebutton` 7.

The four transport buttons are one cluster of ~45 skins each and are probably one fix.

## Tier 3 — drawing the skin's own controls (Phase 5)

Tracked in the recovery plan until the corpus loads and the census can rank these by measured reach.

## Closed

| ID | Item | Landed |
|---|---|---|
| W10 | `WMP_SKIN=<path>` accepts a **directory**, sweeping the corpus in one process | Phase 1 |
| W11 | The nine probe flags, documented canonically in `skills/wmp-skin-guide/reference/harness.md` | Phase 1 |
| W12 | `scripts/wmp_skin_census.sh` and `scripts/wmp_render_sweep.sh` | Phase 1 — 14 rows, 18 PNGs, both halves of `compare` proven against a change that can be seen |
| W2 | `WMPXML`: the `XMLParser` wrapper replaced with a port of `WalLenientXMLParser` | Phase 2 — **14 / 14 archives load**, from 10. Attributes keep document order and authored spelling; duplicates collapse last-wins with a `WMP0034` warning (19 occurrences corpus-wide — a hand-written regex over the same four files found 3, which is the argument for the instrument); a tag left open at EOF is a `WMP0036` warning that keeps its children. All 18 pre-existing PNGs byte-identical; the only invariant movement is that diagnostic locations now point at the `<` rather than at the end of the tag, verified against `corona.wms:42`. |
| W1 | `WMPTextDecoder`: cp1252 (already present) plus a BOM-less UTF-16 sniff | Phase 2 — added to **both** engines, positional rather than statistical, because an `iconv`-style density guess cannot tell the two byte orders apart. It claims nothing in either corpus today and is not why anything loads. It is there because neither fallback can *fail*: Windows-1252 and `isoLatin1` accept every byte sequence, so such a file decodes into null-interleaved mojibake instead of reporting a wrong guess (`.wal` B93). `.wal` is a shipped mode, so that half is measured, not reasoned about: across all 80 installed `.wal` archives, 827 of 2,384 XML and script entries are not valid UTF-8 and so reach the changed fallback, and the sniff claims **none** — the `.wal` decode path is byte-identical. |
| W3 | `WMPNode`: the case-insensitive tag fold covers every comparison | Phase 2 — verified, no change needed. Every consumer routes through `WMPElementKind(tagName:)` (which lowercases), `WMPPath.fold` for ids, or `caseInsensitiveCompare` for attributes; `authoredTagName` is only ever displayed or counted. |
| W4 | `WMPAttributeValue`: an unresolvable `res://` entry skipped with a diagnostic, siblings still loaded | Phase 2 — verified already working. `WMPSkinLoader` splits a `scriptFile` list on `;` and tests each entry, so Corona's `res://wmploc.dll/RT_TEXT/#132` warns as `WMP0029` and its four real programs still register. |
| W5 | The installed corpus wired into `swift test` as a **default-on** target | Phase 2 — `WMPCorpusLoadTests` reads `WMPSkins/` and skips only when it is absent. It asserts whole-corpus, naming every rejected archive with its diagnostic, and a second test asserts the deterministic graph dump is identical across two loads. `swift test`: 1998 passed, 0 skipped. |
| W36 | The corpus gate converted from an absolute to a **ratchet** | Phase 2 — the corpus grew to 180 and 21 rejections turned the suite red. `Fixtures/WMPSkin/corpus-baseline.tsv` records the outcome per sha256; a recorded `ok` that now fails is a regression and fails the suite, a recorded `failed` that now loads asks for a re-record, an unrecorded archive never fails the build. Re-record with `scripts/wmp_corpus_baseline.py <census outdir>` **only after improving the loader**. Proven against a regression it should catch, not just observed passing. |
