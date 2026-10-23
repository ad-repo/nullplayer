# Skin triage record

Copy to the scratchpad at Phase 0 of `skin-triage`; fill each block before leaving its phase. Never
commit a filled record — what it taught lands in the owning skill (Phase 9). Across sessions the
record does not survive: in an intake the fix list lives in the ledger and backlog, and Phase 5's
before/after verdicts come from the run store (`wal_interaction_sweep.sh --rev <commit>`).

## Report (Phase 0)

- Skin file:            <name> — sha256 <hash>
- Family:               Classic | Original | Metal | .wal | .wmz | Audion
- Reported state:       view/layout <>, theme <>, UI Size <>%, window <W>x<H>, docked <y/n>,
                        playing <local|stream|no>, first launch | relaunch
- Reporter's steps:     1. …
- Symptom (their words): "…"
- Hand-repaired before report: <y/n/asked>
- Screenshot scale:     1x | 2x | none

## Recall and references (Phase 1)

- Dossier / backlog row: <path/id | none> — measurement re-run: <reproduces | does not | n/a>

| Reference | Source | Window / layout | Theme / state | Usable? (missing variable) |
|---|---|---|---|---|

## Inventory (Phase 2) and verdicts (Phases 3, 7)

Counts: windows <n>, controls <n>, components <n>. Startup aborted? <no | handler, method>

| # | Window/layout | Item (type#id) | Frame | Drawn | Reachable | Gesture/state | Headless verdict | Earned by | Live verdict |
|---|---|---|---|---|---|---|---|---|---|

Verdicts: works / silent / blocked / unbound / unreachable / wrong / D / H.

## Fix list (Phase 4) — blockers first, then unlockers by rows unlocked

| Rank | Blocker/unlocker | Class | Failing line | Rows it unlocks | Corpus reach | Status |
|---|---|---|---|---|---|---|

## Fix log (Phase 5) — one block per entry

- Entry:                <rank>
- Mechanism line:       <measured, not hypothesised>
- Owning layer / gate:  <file / type> — <controllerFamily == … | family-owned file>
- A/B switch:           <ENV | none>
- Re-run:               <n> works before → <n> after; newly exposed rows: <#…>
- Ruled out:            - <hypothesis> — <measurement>

## Reference matching (Phase 6) — one row per iteration

| Iter | Reference | png_diff class / bbox | Largest region → object | Fix entry |
|---|---|---|---|---|

Residual (complete only when every row has a non-engine reason):

| Region | Difference | Reason |
|---|---|---|

## Live window checks (Phase 7)

- Launch line / family:  LAUNCH PASS: … / <menu.applescript family>
- Placement, resize, docking, shade round trip, z-order, shadow, 1x/2x, relaunch: <result each>
- Menus checked by hand: <list | handed over>

## Verification (Phase 8)

- Reporter's steps on final build: <result>
- Before / after:       <path> / <path>
- Sweep:                <command> — <N> changed: <opened> opened, <R> repairs, <G> regressions, <U> unexamined
- Interaction / motion verdict diff (.wal): <result>
- Classic / Original:   byte-identical | not touched

## Hand-over (Phase 9)

- Build handed over:    <commit / dirty tree>, labelled "attempted"
- User verdict:         …
- Landed:               tests <>, skill <>, dossier <>, backlog <>, changelog <>
