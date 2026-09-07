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
`733d3631` over the 14 archives in `WMPSkins/`, all 14 of which now load.** Reproduce with
`scripts/wmp_skin_census.sh /tmp/wmp/census`. A number still quoted against the earlier
**10**-archive denominator is marked as such; never rewrite an old numerator against a new
denominator. They replaced the recovery plan's inherited hand
measurement, which was taken from the phase handoff docs and was wrong in both directions — see
`skills/wmp-skin-guide/reference/harness.md` § "What the harness measured" for the corrections.

## Tier 1 — the corpus loads; views still black out (14 of 14 archives load)

Phase 2 closed the loading blocker. What is left in this tier is a view that loads and then draws
nothing, which is indistinguishable from a rejection to anyone using the app.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W6 | A view whose size is computed in script must still lay out | **9 views across 6 skins** (`WMP0032`; was 7 across 5 on the 10-archive denominator) | "View requires positive literal width and height for static layout" — the view renders *nothing*, so `claw.wmz` and `iconic.wmz` still produce **zero** layouts. Also `Alienware Invader` ×2, `Half-Life_2` ×2, and now `Official_Xbox_XP` ×3. Phase 4 work, ranked here because it is a total blackout, not a cosmetic gap. |
| W7 | An **empty** resource attribute must warn, not kill the view | **3 views** (`WMP0024`; was 2) | `Resource path '' is absolute, drive-qualified, or invalid` rejects the whole view: `9SeriesDefault/mainView`, `Half-Life_2/infoView`, `Official_Xbox_XP/playlist`. Degrade with a diagnostic; never fail the skin. |
| W8 | `Alpine7618_v09` draws its transparency key instead of keying it | 1 skin, newly measurable | `census/png/Alpine7618_v09/view-2@1x.png`: the skin's art occupies the lower ~150 px of a 517×412 view and everything above it is flat `#FF00FF`. Class B — the view loads, lays out and renders; the colour key is simply not applied to the uncovered background. Only visible because the skin now loads. |
| W9 | `Official_Xbox_XP` paints an opaque black `VIDEO` placeholder over its own art | 1 skin measured, 18 `VIDEO` elements corpus-wide | `census/png/Official_Xbox_XP/mainBox@1x.png`. This is `WMPWidgetViews`' placeholder reaching a render dump; the fix is the hosted video surface in Phase 5. |

## Tier 2 — the script runtime cannot hold state (Phase 3)

Ranked from the harness's own output, not from the plan's prose.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W20 | One persistent `JSContext` per skin session, replacing the fresh-process-per-transaction model | all 14 skins ship JScript | `WMP_RENDER_SCRIPTS=1` on Corona shows the shape today. Retire `Sources/WMPScriptIsolationHelper/` and its `Package.swift`/`assemble_app.sh`/packaging-check wiring **in the same change** — see the recovery plan's Phase 3. |
| W21 | The probe pass evaluates expressions with no scripts loaded | Corona: every `eq*.left` fails `ReferenceError: Can't find variable: GetEqSliderLeft` | `WMPPhase5Session.transact` sends `scripts: []` in its topology probe, so an expression calling a function the skin defines can never resolve — and one failure empties the whole ordered list, so **no** expression evaluates. Visible as `live=-` / `#-` on every `EXPR` line for `vPlayer`. |
| W22 | `theme.loadString` | Corona `OnLoad` aborts on it | `TypeError: theme.loadString is not a function`. Measured demand ranked it 10th; it is the first member that actually stops a handler. |

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
