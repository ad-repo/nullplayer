# Windows Media Player (`.wmz`) — ranked open backlog

This is the only live backlog for the WMP skin subsystem. It is the `.wmz` counterpart to
[`WINAMP5_TASKS.md`](WINAMP5_TASKS.md), and the two never share entries: a `.wmz` item goes here, a
`.wal` item goes there. Read `skills/wmp-skin-guide/SKILL.md` before picking anything up.

A skin is a test case, not a milestone: take measured capability work from the top down.

## Ranking

Reach is corpus demand across the 14-skin corpus installed in
`~/Library/Application Support/NullPlayer/WMPSkins/`, not severity. Every Reach number must be
reproducible by a command recorded next to it.

**The numbers below are inherited from the recovery plan's 2026-09-07 hand measurement, taken before
this subsystem had a census of its own.** They are starting estimates, not census output. Phase 1
builds `scripts/wmp_skin_census.sh`; re-measure and replace these with its output before ranking any
further work on them.

## Tier 1 — the corpus does not load (4 of 14 archives load today)

| ID | Item | Reach | Notes |
|---|---|---|---|
| W1 | `WMPTextDecoder`: add cp1252 and a BOM-less UTF-16 sniff | 7 of 10 rejections (`WMP0025`) | Measured spread: UTF-16-BOM ×8, UTF-8 ×3, cp1252 ×3. Sniff null density and byte position; do not trust `iconv`-style guessing, which produced null-interleaved text on 3 of 14 archives. The same gap exists in `WalXML.decodeText` (`isoLatin1` fallback, already paid for once as B93). |
| W2 | Replace `WMPXML`'s `XMLParser` wrapper with a port of `WalLenientXMLParser` | 3 of 10 rejections (`WMP0027`) | libxml2 aborts on a duplicate attribute before the delegate runs, and `[String: String]` cannot carry one regardless — the parser has to be replaced, not softened. Preserve attribute **document order** (`WalXMLNode.attributeOrder`: alphabetising silently dropped four style properties). Duplicates collapse last-wins with a `WMP00xx` warning, never a rejection. |
| W3 | `WMPNode`: confirm the case-insensitive tag fold covers every comparison, not just the lookup index | `<THEME>` and `<theme>` both occur | |
| W4 | `WMPAttributeValue`: skip an unresolvable `res://wmploc.dll/RT_TEXT/#132` entry with a diagnostic, load its siblings | Corona | Never reject the whole attribute. |
| W5 | Wire the installed corpus into `swift test` as a **default-on** target | — | Skip only when `WMPSkins/` is absent, so a plain `swift test` measures the real corpus instead of reporting green over synthetic fixtures. |

## Tier 2 — no instruments (Phase 1)

| ID | Item | Notes |
|---|---|---|
| W10 | `WMP_SKIN=<path>` accepts a **directory**, sweeping the corpus in one process | The `.wal` sweep does 79 archives in ~5 min where a shell loop took 25. |
| W11 | `WMP_RENDER_DUMP`, `WMP_RENDER_PROBE`, `WMP_RENDER_BITMAPS`, `WMP_RENDER_SCRIPTS`, `WMP_RENDER_CLICK`, `WMP_RENDER_EXPR`, `WMP_CALL_TRACE`, `WMP_RENDER_SETTLE`, `WMP_RENDER_SIZE` | Canonical reference goes in `skills/wmp-skin-guide/reference/harness.md` in the same change that adds each flag. |
| W12 | `scripts/wmp_skin_census.sh` and `scripts/wmp_render_sweep.sh` | Modelled on `wal_skin_census.sh` / `wal_render_sweep.sh`. Refuse a dirty tree without `--allow-dirty`; compare PNGs in RGB, not RGBA. |

## Tier 3 — script runtime, layout, and drawing (Phases 3–5)

Tracked in the recovery plan until Phase 1's census can rank them by measured reach. Do not start
these before W10–W12 land: you cannot rank work you cannot measure.

## Closed

_(none yet)_
