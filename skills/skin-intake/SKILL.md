---
name: skin-intake
description: Processes the .wal candidate corpus mechanically — ~900 skins in batches of 25, each batch worked over many sessions — and owns the batch ledger docs/winamp-modern/intakes/intake-<n>.tsv, the status script scripts/wal_intake_status.sh that picks every session's work, and the only route to editing docs/winamp-modern/corpus-runner-plan.md. Use at the start of any intake session, when asked where the corpus or a batch stands or what is next, before any edit to the corpus-runner plan, or when a loop drives intakes unattended.
---

# Processing the corpus

Three levels, each finished by the one below it:

| Level | Is | Done when | Recorded in |
|---|---|---|---|
| **Corpus** | ~900 candidates in Bronze | every candidate is Gold, or Bronze below the gain floor (certified by the census and the pre-merge sweep, plan §8) | `corpus-manifest.tsv` tiers |
| **Batch** | 25 skins, one branch, one ledger, one run store | every skin `promoted` and the PR merged | `docs/winamp-modern/intakes/intake-<n>.tsv` |
| **Session** | one unit of work on the open batch | its result is in the ledger and committed | the ledger and the commit |

**One batch is open at a time.** The next is admitted only when the last is merged.

```sh
scripts/wal_intake_status.sh      # corpus counts, the open batch per stage, the next session's work
```

Every session starts with it and does the `next:` line. It exits 1 when the ledger disagrees with the
manifest or the corpus on disk (sha256, tier, file); then the session's work is fixing the ledger.

## The batch ledger

One row per skin, committed. **It is the only progress record**: not the plan, not a commit message,
not a chat summary, not a scratchpad. Intake #2's plan said "closed" with 11 skins unworked, and its
batch record lived in a scratchpad that recovering cost a session.

| Column | Holds |
|---|---|
| `file`, `sha256` | as in `corpus-manifest.tsv` |
| `stage` | below |
| `updated` | the date the stage last moved |
| `rows` | backlog ids this skin filed or was fixed under (`B254`, `B261(open)`), or `-` |
| `note` | one line: where an unfinished stage stopped (`Phase 5: next B262`), what blocks it, or `-` |

| Stage | Means |
|---|---|
| `admitted` | in Silver and in the user's skin menu (`WinampModernSkins/`) |
| `headless` | `skin-triage` Phases 1–4 done: every row has a verdict, the fix list is in `note`/`rows` |
| `live` | Phases 5–8 done, or the user took it straight to their UI round (`note` says which) |
| `accepted` | the user tried it and said it works |
| `promoted` | manifest tier `gold`, file in `WinampModernCorpus/gold/`, a `skin-compatibility.md` row |

A stage moves only on its evidence, in the commit that carries the work; it moves back only with a
`note` saying why. A user's verdict moves a skin to `accepted` from any stage.

## The batch, as sessions

The batch's lowest stage decides the next session's work. `wal_intake_status.sh` prints it.

| Lowest stage | Next session | Moves |
|---|---|---|
| — (no open batch) | **Admit** batch n: branch `feat/wal-intake-<n>` from `origin/main`; `wal_intake.sh <bronze> <out> --admit`; copy the picks into `WinampModernSkins/`; commit `<out>/intake.tsv` as `intakes/intake-<n>.ranking.tsv` and the ledger at `admitted` | all → `admitted` |
| `admitted` | **Headless pass, whole batch at once**: `skin-triage` Phases 1–4 over one folder holding the batch, failures ranked across skins | all → `headless` |
| `headless` | **One skin**, the `next:` one: Phases 5–8. Skins whose note says `headless clean` share one live smoke session instead (one launch, switch skins from the menu) | one → `live` |
| `live` | **Hand over** the `live` skins in one list for the user's UI round; their verdicts go in | → `accepted`, or back with a note |
| `accepted` | **Promote** every skin in one commit, then the branch's code-quality review and the PR | all → `promoted` |
| `promoted` | **Close** once the PR is merged: delete the run store (`rm -rf WinampModernCorpus/runs`), then admit batch n+1 | — |

**The user may cut a batch short** at any stage and send the rest to their UI round: mark each `live`
with `note` `handed over without a pass (user, <date>)`. A defect the round finds puts that skin back
to `headless` with the defect in its note, and the next session fixes it from Phase 5.

Only the batch rides on its branch; an unrelated backlog row gets its own `fix/…` branch. Push with
`git push -u origin <branch>`. A batch past about a week PRs its `promoted` skins and continues on a
fresh branch with the same ledger. Merge `origin/main` in every few days; never rebase a pushed branch.

**Stop admitting batches** when a batch no longer clears the gain floor (plan §8 *Decisions*).

## A session

No session remembers the last. What the next one needs is in the ledger, the backlog and the
branch, so a session reads those and writes those, nothing else.

**Start:** on the batch branch, clean tree. Run the status script and take its `next:` work. Read that
skin's `note` and its `rows` in `tasks/WINAMP5_TASKS.md`, and trust them: re-measure only a row a fix
landed since `updated` could have moved.

**Work:** sweeps and baselines come from the run store, never a fresh scratchpad capture — the sweep
scripts serve what is stored for this code, and `--rev <commit>` another commit's (`harness.md` §
*The run store*). **Write each result into the ledger the moment it is known**, not at the end.

**End**, in the commit that carries the work:
1. Stage reached: move it, `note` `-`. Not reached: keep it, `note` `Phase <k>: <next action>`,
   specific enough to start on without reading the session.
2. A fix-list entry not done is a backlog row, its id in `rows`.
3. Any plan edit, by § *Changing the plan*.
4. The status script exits 0. Report "skin X: stage A → B, N rows fixed, M open" and the `next:` line.

## What this skill routes to

| Need | Owner |
|---|---|
| The per-skin pass, Phases 0–9 | `skills/skin-triage` |
| `wal_intake.sh`, the crawler, the run store, every sweep | `winamp-modern-skin-guide/reference/harness.md` |
| Budget (25, gain ≥ 3), tiers, why | `corpus-runner-plan.md` §8 *Decisions* |
| Backlog rows | `tasks/WINAMP5_TASKS.md`, closed into `backlog-archive.md` |
| Grades after promotion | `docs/winamp-modern/skin-compatibility.md`, rubric in `/wal-skin-report` |

`.wal` is the only family with a corpus today; a family that gains one adds its manifest and status
script here.

## Changing the plan

`docs/winamp-modern/corpus-runner-plan.md` changes **only** by these edits. It is design and
history, never progress.

| When | Edit | Where |
|---|---|---|
| A batch is admitted | one bullet: rev, tier counts, run time, gain curve, post-admission sweep | §8 *Progress* |
| A batch is promoted | a *Done: intake #n* block: per skin that needed a fix, what was wrong and the fix; open rows by id | after the last *Done* block |
| A measurement changes a decision | the decision, measurement, date and rev — **proposed to the user first** | §8 *Decisions* |
| A parked instrument is built | *Parked* → *Built*; commands in `harness.md` | §7 |
| The backlog loop changes | the changed step | § *The loop* |

The plan's **Next:** line stays a pointer here. Anything else (progress, session notes, rewrites)
is not a plan edit; a restructuring is proposed to the user, not done.
