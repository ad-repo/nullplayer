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

**The return guard.** A commit that changes exactly one ledger row counts as a session spent on that
skin. At 2 (one fix, one re-check), the script stops naming the skin in `next:` and lists it under `budget spent`. That skin
goes to the user's round as it is, marked `live` with its open rows in `note`, and no session works
on it again unless the user asks. Intake #4 spent 9 sessions on Ryoko and 7 on StarTrek, most of
them re-running cycles on a skin that already worked.

## The batch ledger

One row per skin, committed. **It is the only progress record**: not the plan, not a commit message,
not a chat summary, not a scratchpad — a record outside it is lost with the session that wrote it.

| Column | Holds |
|---|---|
| `file`, `sha256` | as in `corpus-manifest.tsv` |
| `stage` | below |
| `updated` | the date the stage last moved |
| `rows` | backlog ids this skin filed or was fixed under (`B254`, `B261(open)`), or `-` |
| `note` | one line: where an unfinished stage stopped (`Phase 5: next B262`), what blocks it, or `-`. A `headless` skin with an empty fix list starts its note with `headless clean`, which the status script reads. A skin at `live` carries its visual-review result (`visual: clean (6 windows)`) |

| Stage | Means |
|---|---|
| `admitted` | in Silver and in the user's skin menu (`WinampModernSkins/`) |
| `headless` | `skin-triage` Phases 1–4 done: every row has a verdict, the fix list is in `note`/`rows`. A fix for a defect seen on screen is not this pass. Also: a skin sent back by the user's round, the defect in its `note` |
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
| `admitted` | **The batch pass** (below); reorder the ledger rows by its rank, since `next:` takes the first unfinished row | all → `headless` |
| `headless` | **A group of skins at once** (below, § *Running it*): a live pass over about four skins, then one fix pass over every row they filed, then one live re-check of the skins a fix touched. Skins whose note says `headless clean` go through the same live passes; each still gets the visual review | a group → `live` |
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

## The batch pass

`skin-triage` is the pass for one skin; a batch runs it once, not 25 times.¹

1. **Phases 1–3 over the whole batch at once**: one folder holding the batch, one dump, one
   interaction sweep, one motion sweep, each a single invocation (`--corpus <batch dir>`).
2. **Phase 4 ranked across the batch**: group every non-`works` row from every skin by its failing
   line. A group that spans skins is the unlocker; fix it once and re-run the batch.
3. **Live per skin only for the residual**: rows marked H, every class W check, and menus. A skin
   whose headless pass is clean gets one live smoke pass, not a full re-drive.
4. **One pass per skin**: do not leave a skin until its inventory is complete.
5. **Reviews, refactors and changelog regrouping** happen once at the end, not between skins.

¹ Intake #1 went skin by skin, live first, over three passes; most of what it found was visible in
a headless dump (`corpus-runner-plan.md` § *Done: the B169 intake*).

## The visual review

No skin moves to `live` without it, whether or not it says `headless clean`. A clean sweep is a
regression result. Intake #3's user round still found see-through panes, text drawn over text and
controls run into each other (`corpus-runner-plan.md` § *Done: intake #3*). This review exists to
catch those three.

1. Run `skills/app-control/scripts/window-census.sh <skin> --shots` with a track playing. That
   captures every window live, main included, with hosted components and cover art, after the skin
   has played for 10 s. Skins cross-fade and fill their texts from timers. In intake #4, an early
   capture's `updating...` placeholders and half-faded ghost strings were filed as B301/B302, and
   both closed as not defects.
2. Run `scripts/review_sheet.py <sheet.png> <shots>/*.png --ref <screenshot.png> --scale <s>`, with `<s>` the
   `screen0_scale` in the census's `meta.tsv` (2 on Retina), then
   **open the sheet**. Each window is drawn over magenta under the author's screenshot.
3. Judge every window against the three classes, and write one verdict per class:
   - **Transparent background**: magenta inside the body that the reference fills. Open every
     `HOLES` line first. A window that is mostly magenta has no enclosed hole, so read its
     `transparent=` share as well.
   - **Jumbled text**: strings overlapping each other or their art, cut off, in the wrong size or
     font, or ids/`@TOKEN@` drawn as text.
   - **Layout**: controls overlapping or out of place against the reference, gaps, content past the
     edge, a window cut short or stretched.
4. Each defect is a fix-list entry: Phase 5, then review again. The stage moves only when all three
   classes read clean. The commit's ledger `note` says so: `visual: clean (<n> windows)`.

A skin with no `screenshot.png` is judged against its own artwork, and the note says `no ref`.

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
1. Stage reached: move it, `note` `-` (at `live`, the visual-review result). Not reached: keep it, `note` `Phase <k>: <next action>`,
   specific enough to start on without reading the session.
2. A fix-list entry not done is a backlog row, its id in `rows`.
3. Any plan edit, by § *Changing the plan*.
4. The status script exits 0. Report "skin X: stage A → B, N rows fixed, M open" and the `next:` line.

## Running it: one worker per phase

An intake is run by an orchestrator. The main session does no phase work itself: it starts one
worker per phase and keeps only the workers' reports. Cost is calls × context: every call re-sends
the whole context, so a long session pays again for everything it has read. Intake #3's longest
session made 1,505 calls and averaged 212k tokens of context per call. That came to 319M
cache-read tokens against under 1M of actual tool output. A worker starts small and is discarded
when it finishes, so no session needs compacting.

**A phase**, for the worker's scope, is one row of the batch table's work, cut where the work
naturally stops:

| Stage | Phases, one worker each |
|---|---|
| no open batch | Admit: the orchestrator runs the crawl, then one worker does the rest (below) |
| `admitted` | Phases 1–2 over the batch (dump, inventory) · Phase 3 (interaction and motion sweeps) · Phase 4 (ranked fix list; ledger → `headless`) |
| `headless`, a group | **Live pass**: Phase 7 and the visual review over about four skins in one launch (switch skins from the menu). It files defects as rows and fixes nothing. A skin with no defect moves to `live` in the same commit. **Fix before the user's round** what they would notice in ordinary use: a control that does not work or does the wrong thing, and any of the three visual-review classes they would see at a glance. **Defer to a row**, and move the skin to `live` with the row in its `note`, what they would not: a pixel or two at an edge, a difference only a reference comparison shows, or a defect whose right behaviour needs evidence the corpus lacks. Judge which it is; neither hold a skin for a pixel nor hand over one that looks broken. **Fix pass**: Phase 5 over every row the group filed, one set of sweeps for all of them. **Re-check**: only the defect itself, on only the skins that filed it: the one window or control, not the skin's whole drive or review again. A skin or window that read clean is never reviewed again, and a fix's sweep diff in another skin is classified from the sweep, not by reopening that skin; Phase 8 is that classification, done in the fix pass, with no worker of its own. Phase 6 runs in the live pass when it has not run |
| `accepted` | Promote · the code-quality review · the PR |

**The loop:**

1. Run `scripts/wal_intake_status.sh`; its `next:` line and the ledger row name the phase.
2. Start **one** worker, with `model: "sonnet"`. The environment's default subagent model is
   Haiku, which has misjudged a review sheet before. Opus workers cost several times more, and the
   orchestrator's own look at every sheet (step 4) is the judgment that has to hold. Never run two at once,
   because two builds or launches break each other and the user's running app.
3. The worker's prompt is the phase and skin, plus these rules:
   - Do this one phase of `skills/skin-intake` / `skills/skin-triage`, read from the ledger, the
     backlog and the branch. Read only the skill sections the phase needs.
   - Write each result into the ledger as soon as it is known. Commit the work, and the ledger,
     before reporting.
   - Do not spawn agents.
   - Use the one-call scripts instead of their hand recipes: `scripts/wal_dump.sh` for a skin's
     dump or probe run, and `scripts/wal_skin_src.sh` for its source and reference images. Each
     extra call re-sends the whole context.
   - A live phase (7 and the visual review) runs with a track playing and drives the skin's own
     controls (`skin-triage` Phase 7 step 2). The census does not replace that. Never run
     `window-interaction-matrix.sh` on an intake skin: its close search blind-clicks the corner
     of every window.
   - Interaction and motion sweeps have no noise file, and a full corpus run costs about 10
     minutes. Never take a `--fresh` run of either for a phase. Compare against the stored
     capture, and rerun only the skins that differ, on both revs (`--corpus` on a folder of just
     those). A difference in a skin that varies between runs of one build (OrbFace, -MfS3-,
     CopperdeckII, Aria_of_the_Soul, Invicta, winampmodern566, Cpro_Winamp_Modern, Quadelic,
     CPro_Winamp_for_Mac_Sync, WinampAzenis2, 4-dreliction, cPro_T2T, Winamp_Single_GUI,
     LG_Free's clock frame; B296) is noise unless it is in that
     phase's skin. A `--rev` baseline missing from the store is the one full run a phase may
     take.
   - Report in at most 10 lines: skin, phase, stage before → after, rows fixed and open, the
     visual-review verdicts where they ran, the sheet's path, and the `next:` line.
4. Check the report before passing it on. The status script must exit 0, and `git log -1` must
   be the worker's commit. After a visual review, **open the sheet yourself**: a second look at
   the three classes is the reason the review exists.
5. Pass the report to the user.
6. **Start the next phase's worker as soon as the report checks out.** Do not stop at phase
   or skin boundaries, and never ask the user whether to continue. The turn ends only while a
   worker is running (its notification resumes the loop), on a blocker, at the Admit crawl, or
   when the batch reaches `live` and goes to the user's UI round.

**The Admit crawl is not a worker's job.** `wal_intake.sh --admit` takes about 47 minutes, longer
than a foreground call's 10-minute limit. A worker cannot wait on a background run either, because
its report ends the run. So the orchestrator starts the crawl itself with `run_in_background`, with
its output in the scratchpad. When the run ends, check for its `wal_intake: … -> intake.tsv` line;
the exit code proves nothing (`harness.md` § *Growing the corpus*). Then **end the turn**: the
crawl is a phase boundary, and the user compacts or starts a fresh session there. The last message
gives the output dir's full absolute path, the one thing the next session cannot find without it.
In the next session, one worker takes that dir and does the rest of Admit: copy the picks, commit the ranking and the ledger, and add
the plan bullet. Never tell a worker to run the crawl in the foreground.

A blocker the worker cannot clear (a decision for the user, a defect it cannot reproduce) comes
back in its report and ends the turn the same way.

## What this skill routes to

| Need | Owner |
|---|---|
| The per-skin pass, Phases 0–9 | `skills/skin-triage` (its record, `template.md`, lives in the scratchpad: what must outlive the session goes in the ledger, the backlog and the run store) |
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
