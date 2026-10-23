---
name: skin-intake
description: Runs a corpus intake batch end to end — admit, hand over, the triage pass, promote, PR — owns the only route to editing docs/winamp-modern/corpus-runner-plan.md, and owns the one place intake progress is recorded, the per-intake ledger docs/winamp-modern/intakes/intake-<n>.tsv, read with scripts/wal_intake_status.sh. Use when starting, resuming or closing an intake, before any edit to the corpus-runner plan, when asked where an intake stands or which skin is next, or when a loop drives an intake unattended.
---

# Running an intake

An intake is a batch of up to 25 skins taken from Bronze into Silver, worked in the app, and promoted
to Gold. This file owns the **lifecycle** and **where progress is recorded**. Each step's mechanics
live elsewhere and are not restated here:

| Step | Owner |
|---|---|
| Crawl, rate, admit (`wal_intake.sh`), the hand-over copy | `winamp-modern-skin-guide/reference/harness.md` § *Growing the corpus* |
| Why the budget is ≤ 25 and gain ≥ 3; the tiers | `docs/winamp-modern/corpus-runner-plan.md` §8 *Decisions* |
| The per-skin pass, Phases 0–9 | `skills/skin-triage` (its § *A batch is one pass*) |
| Backlog rows the pass files | `tasks/WINAMP5_TASKS.md`, closed into `backlog-archive.md` |
| Grades after promotion | `docs/winamp-modern/skin-compatibility.md`, rubric in `/wal-skin-report` |

`.wal` is the only family with a corpus and intakes today. A family that gains a corpus adds its
manifest and status script here; it does not get a second intake skill.

## The ledger is the only progress record

`docs/winamp-modern/intakes/intake-<n>.tsv`, committed, one row per skin in the batch:

| Column | Holds |
|---|---|
| `file` | archive name, as in `corpus-manifest.tsv` |
| `sha256` | must match the manifest |
| `stage` | `admitted` → `headless` → `live` → `accepted` → `promoted` |
| `updated` | the date the stage last moved |
| `rows` | backlog ids this skin filed or was fixed under (`B254`, `B261(open)`), or `-` |
| `note` | one line — where an unfinished stage stopped (`Phase 5: next B262`), what blocks it, or `-` |

| Stage | Means | Set when |
|---|---|---|
| `admitted` | in Silver, copied into `WinampModernSkins/` | `wal_intake.sh --admit` ran (seed the ledger from its picks) |
| `headless` | the skin's Phases 1–4 rows all have a verdict | its fix list exists |
| `live` | its Phases 5–8 are done: inventory all `works`/D/H, sweep classified | Phase 8's *Confirm it took* holds |
| `accepted` | the user tried it and said it works | Phase 9 |
| `promoted` | manifest tier `gold`, file in `WinampModernCorpus/gold/`, `skin-compatibility.md` row | the promotion commit |

**Move a stage only on its evidence, in the same commit as the work.** Nothing else records intake
progress — not the plan, not a commit message, not a summary in chat. Prose that says "the pass is
done" while the ledger says otherwise is wrong; intake #2's plan said "closed" with 11 skins
unworked. A stage never moves back silently: a skin that regresses goes back with a `note` naming why.

```sh
scripts/wal_intake_status.sh [n]    # counts per stage, the next skin, exit 1 on any disagreement
```

It checks every row against the manifest (sha256, tier `silver` until `promoted`, then `gold`) and
the corpus folder on disk, and prints the next skin's note. Run it before a PR; a loop takes `next:`
as its work item and stops on a non-zero exit.

## A session

A batch takes many sessions, and no session remembers the last one. Everything the next session
needs is in the committed ledger, the backlog and the branch — never in the scratchpad, a chat
summary or a handover note. One session works an intake at a time.

**Start:**
1. On `feat/wal-intake-<n>` with a clean tree; `git fetch origin` and merge `origin/main` in if it
   has been a few days.
2. `scripts/wal_intake_status.sh`. Exit 1: fix the ledger first, nothing else. All skins at
   `accepted` or later: go to promotion (lifecycle step 6).
3. Take the `next:` skin. Read its `note` and its `rows` in `tasks/WINAMP5_TASKS.md`.
4. Copy `skills/skin-triage/template.md` to the scratchpad and resume at the phase the note names.
   Re-run that skin's Phase 2–3 dump before trusting a verdict an earlier session recorded — it is
   seconds, and the engine has moved since.

**Work** one skin to its next stage. Step 3 of the lifecycle is the exception: the whole batch's
headless pass is one session.

**End**, in the commit that carries the work:
1. Stage reached: move it and set `note` to `-`. Not reached: keep the stage and write the `note`
   as `Phase <k>: <the next action>`, specific enough to start on without re-reading the session.
2. Every fix-list entry not done becomes a backlog row (or is already one) and its id goes in `rows`
   — the scratchpad record dies with the session, the backlog does not.
3. Any edit the plan takes, by § *Changing the plan*.
4. `scripts/wal_intake_status.sh` exits 0. Report the session as "skin X: stage A → B, N rows fixed,
   M open", and the `next:` line.

## The lifecycle

1. **Branch** `feat/wal-intake-<n>` from `origin/main`. Only the batch rides on it: the re-weighting
   or rule change (if any), the intake run, the manifest update, the ledger, and the batch's fixes.
   An unrelated row gets its own `fix/…` branch. Push with `git push -u origin <branch>`.
2. **Admit**: `wal_intake.sh <bronze> <out> --admit`, copy the picks into `WinampModernSkins/`, seed
   the ledger at `admitted`, record the gain curve and post-admission sweep in the plan's §8
   *Progress* (that is history, not progress — one bullet per intake).
3. **Headless, whole batch at once**: `skin-triage` Phases 1–4 over one directory holding the batch;
   rank failures across skins. Move each skin to `headless`. A skin with fixes but no recorded
   inventory is still `admitted` and goes through this step: a fix for a defect seen on screen is not
   a pass.
4. **Fix and go live**, skin by skin by `next:`: Phases 5–8. Move each to `live`.
5. **Hand over** (Phase 9) the `live` skins in one list; the user's verdicts move them to
   `accepted`, or back with a note.
6. **Promote** the `accepted` skins in one commit: manifest tier `gold`, move the file to
   `WinampModernCorpus/gold/`, add the `skin-compatibility.md` row, stage `promoted`.
   `wal_intake_status.sh` must exit 0.
7. **PR**, after the branch's code-quality review. Confirm `gh pr view <N> --json files` matches.

A batch that runs past about a week PRs its `promoted` skins and continues on a fresh branch with the
same ledger. Merge `origin/main` in every few days; never rebase a pushed branch.

## Changing the plan

`docs/winamp-modern/corpus-runner-plan.md` changes **only** by the edits below, for intakes and for
the backlog loop alike. It is design and history; it never holds progress.

| When | Edit | Where |
|---|---|---|
| An intake is admitted (step 2) | one bullet: rev, tier counts, run time, gain curve, post-admission sweep, the batch's files | §8 *Progress* |
| An intake is promoted (step 6) | a *Done: intake #n* block: one row per skin that needed a fix — what was wrong, the fix and where; then what was left open, by row id | after the last *Done* block |
| A measurement changes a decision | the decision, the measurement, its date and rev — **proposed to the user first** | §8 *Decisions* |
| A parked instrument is built | move it from *Parked* to *Built* in §7; its commands go in `harness.md` | §7 |
| The loop's order or the queue it reads changes | the changed step | § *The loop* |

The **Next:** line stays a pointer to this skill and `wal_intake_status.sh`; it is never rewritten
with a status. Anything else — a session's progress, what is half-done, a rewrite or reorganisation
— is not a plan edit: progress goes in the ledger or the backlog, knowledge goes in the owning
skill, and a restructuring is proposed to the user, not done. Make the plan edit in the same commit
as the work that earned it.

**When to stop running intakes:** while a batch clears the gain floor. Once it does not, the rest is
certified by the census and the pre-merge render sweep (plan §8), not by an intake.
