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
`055063ed` over the 14 archives in `WMPSkins/`.** Reproduce with
`scripts/wmp_skin_census.sh /tmp/wmp/census`. They replaced the recovery plan's inherited hand
measurement, which was taken from the phase handoff docs and was wrong in both directions — see
`skills/wmp-skin-guide/reference/harness.md` § "What the harness measured" for the corrections.

## Tier 1 — the corpus does not load (10 of 14 archives load today)

| ID | Item | Reach | Notes |
|---|---|---|---|
| W2 | Replace `WMPXML`'s `XMLParser` wrapper with a port of `WalLenientXMLParser` | **4 of 4 rejections** (`WMP0027`) | The entire loading blocker. Alpine7618_v09, anemone, Official_Xbox_XP, The Unit — exactly the four archives carrying a duplicate attribute. libxml2 aborts on one before the delegate runs, and `[String: String]` cannot carry one regardless, so the parser has to be replaced, not softened. Preserve attribute **document order** (`WalXMLNode.attributeOrder`: alphabetising silently dropped four style properties). Duplicates collapse last-wins with a `WMP00xx` warning, never a rejection. |
| W6 | A view whose size is computed in script must still lay out | **7 views across 5 skins** (`WMP0032`) | "View requires positive literal width and height for static layout" — the view renders *nothing*, so `claw.wmz` and `iconic.wmz` load cleanly and produce zero layouts. Also `Alienware Invader` ×2, `Half-Life_2` ×2. Phase 4 work, ranked here because it is a total blackout, not a cosmetic gap. |
| W7 | An **empty** resource attribute must warn, not kill the view | **2 views** (`WMP0024`) | `Resource path '' is absolute, drive-qualified, or invalid` rejects the whole view. Degrade with a diagnostic; never fail the skin. |
| W3 | `WMPNode`: confirm the case-insensitive tag fold covers every comparison, not just the lookup index | `<THEME>` and `<theme>` both occur | |
| W4 | `WMPAttributeValue`: skip an unresolvable `res://wmploc.dll/RT_TEXT/#132` entry with a diagnostic, load its siblings | Corona (confirmed: `SCRIPT res://wmploc.dll/RT_TEXT/#132: status=unsupported`) | Never reject the whole attribute. |
| W5 | Wire the installed corpus into `swift test` as a **default-on** target | — | Skip only when `WMPSkins/` is absent, so a plain `swift test` measures the real corpus instead of reporting green over synthetic fixtures. |

### Not ranked any more

| ID | Item | Why |
|---|---|---|
| W1 | `WMPTextDecoder`: cp1252 and a BOM-less UTF-16 sniff | **0 encoding rejections in the corpus.** The decoder already resolves all 14: utf16LittleEndian ×11, windows1252 ×2 (claw, Cubist), and the two remaining archives are rejected before decoding for `WMP0027`. The plan ranked this first on a hand measurement of 7 of 10 rejections; the census found none. Revisit only if a new archive rejects with `WMP0025`. |

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
