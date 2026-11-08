---
name: skin-intake
description: Processes the .wal candidate corpus in batches of 25 — pick, an automated live scan (main-window controls, the Library, every window's look), one fix pass, the user's go, promote — and owns the batch ledger docs/winamp-modern/intakes/intake-<n>.tsv, the pick and status scripts (scripts/wal_intake_pick.sh, scripts/wal_intake_status.sh), and the only route to editing docs/winamp-modern/corpus-runner-plan.md. Use at the start of any intake session, when asked where the corpus or a batch stands or what is next, before any edit to the corpus-runner plan, or when a loop drives intakes unattended.
---

# Processing the corpus

| Level | Is | Done when | Recorded in |
|---|---|---|---|
| **Corpus** | ~750 candidates in Bronze | every candidate is Gold or quarantined | `corpus-manifest.tsv` tiers |
| **Batch** | 25 skins, one branch, one ledger | every skin `promoted` and the PR merged | `docs/winamp-modern/intakes/intake-<n>.tsv` |

**One batch is open at a time.** The next is picked only when the last is merged.

```sh
scripts/wal_intake_status.sh      # corpus counts, the open batch per stage, the next step
```

Every session starts with it and does the `next:` line. It exits 1 when the ledger disagrees with
the manifest or the corpus on disk (sha256, tier, file); then the work is fixing the ledger.

**Why the batch is lean (2026-11-07).** Intakes #2–#4 ran a headless pass per skin (dump,
inventory, interaction and motion sweeps, a ranked fix list) because whole features were missing.
By #5 and #6 that pass found no real defect (B317–B319, B361: all class H or not defects); every
fix came from the live census and the user's round. Rank no longer orders anything either: by #6
every remaining candidate's gain was 2 or less, and no crawl had quarantined a skin. So a batch is
picked, not crawled, and checked live by the tools below, not phase by phase.

## The ledger

One row per skin, committed. **It is the only progress record**: not the plan, not a commit
message, not a chat summary.

| Column | Holds |
|---|---|
| `file`, `sha256` | as in `corpus-manifest.tsv` |
| `stage` | below |
| `updated` | the date the stage last moved |
| `rows` | backlog ids this skin filed or was fixed under (`B254`, `B261(open)`), or `-` |
| `note` | one line: the scan's verdict (`scan clean: main 18/18, library skin-frame closed, visual clean (5 windows)`), or what is open |

| Stage | Means |
|---|---|
| `admitted` | in Silver and in the skin menu (`WinampModernSkins/`) |
| `filed` | the scan found a defect the user would notice; its row is in `rows` |
| `live` | scan clean, or its rows fixed and re-checked, or deferred to a row the user would not notice |
| `accepted` | the user gave the batch their go (or tried this skin and said it works) |
| `promoted` | manifest tier `gold`, file in `WinampModernCorpus/gold/`, a `skin-compatibility.md` row |

A stage moves only on its evidence, in the commit that carries it; it moves back only with a
`note` saying why.

## The batch

| Lowest stage | Next step | Moves |
|---|---|---|
| — (no open batch) | **Pick**: branch `feat/wal-intake-<n>` from `origin/main`; `scripts/wal_intake_pick.sh`; commit the ledger and manifest with the §8 *Progress* bullet | all → `admitted` |
| `admitted` | **The scan** (below), by the orchestrator, no worker | clean → `live`, the rest → `filed` |
| `filed` | **One fix pass** (below), one worker | → `live` |
| `live` | **Hand over** (below) | → `accepted` on the user's go |
| `accepted` | **Promote** every skin in one commit, then the pre-PR code-quality review (CLAUDE.md) and the PR | → `promoted` |
| `promoted` | **Close** once the PR is merged: `rm -rf WinampModernCorpus/runs`, then pick batch n+1 | — |

`wal_intake_pick.sh` takes the next 25 still-bronze skins in the newest `intakes/*.ranking.tsv`'s
order. A crawl of *new* candidates still goes through `wal_intake.sh` (about 47 minutes; run it with
`run_in_background`, check for its `wal_intake: … -> intake.tsv` line, not the exit code), which
writes a fresh ranking.

Only the batch rides on its branch; an unrelated backlog row gets its own `fix/…` branch. Push with
`git push -u origin <branch>`; never rebase a pushed branch.

## The scan

Two checks per skin, plus the look, all live with a track playing, all by script:

1. **The main window's buttons and functions**, and 2. **the Library opens, works and closes**:
   `scripts/wal_live_smoke.sh <skin>… --out <dir>`. It clicks and drags every main-window control
   (volume, transport, seek, track, EQ, layout, windows), then opens the Library from the Windows
   menu, clicks its controls and presses its own close. Its summary line per skin reads
   `main <n> clicked, <k> nochange, …; library <kind>, …, close <closed|nochange>`; the TSV has a
   row per control (`harness.md` § *Driving a click in the running app*).
3. **The look of every window**: `skills/app-control/scripts/window-census.sh <skin>… --shots --out
   <dir>`, in chunks that fit a 10-minute call (about 35 s a skin), then `scripts/review_sheet.py`
   per skin, `--ref` from `scripts/wal_skin_src.sh <skin>`'s `references:` line. Open every sheet
   and judge it (§ *The visual review*).

Read the smoke table, not the app. What counts as a defect:

- A control bound to an action or script that should move something the snapshot sees (volume,
  play, position, track, EQ, layout, a window) and reads `nochange`. Before filing, look at the
  binding (`wal_skin_src.sh`, the skin's script): intake #6's two smoke-only rows (B370, B371) were
  the sweep aiming before a drawer moved and a click blocker the skin lays itself. A control whose
  only effect is pixels (a lamp, a readout) reads `nochange` and is judged on the sheet instead.
- `library plain-chrome` where the skin declares a library frame, `not-opened`, or `close nochange`
  / `no-close-control` on a skin-frame Library.

The smoke cannot see right-click menus, double-clicks, drags on non-slider layers, or the main
window's own close, minimize, quit and eject (skipped so the run survives). Those are not checked
by an intake.

The scan files every defect as a row in `tasks/WINAMP5_TASKS.md` and fixes nothing. **Fix before
the go** what the user would notice in ordinary use: a control that does nothing or the wrong
thing, a Library that will not open or close, any visual class they would see at a glance. **Defer
to a row**, with the skin at `live` and the row in `note`, a pixel or two at an edge, a difference
only a reference shows, or a defect whose right behaviour needs evidence the corpus lacks.

## The visual review

A clean sweep is a regression result, not a look; intake #3's round still found see-through panes,
text over text and controls run into each other, and #5's found Bubble_Tea's spectrum outside its
cup (B323). The census captures every window after 10 s of play (skins cross-fade and fill texts
from timers; earlier captures filed `updating...` placeholders as defects, B301/B302).

`review_sheet.py <sheet.png> <shots>/*.png --ref <screenshot.png> --scale <s>`, with `<s>` the
census `meta.tsv`'s `screen0_scale`, draws each window over magenta under the author's screenshot.
Judge every window against four classes:

- **Transparent background**: magenta inside the body that the reference fills. Open every `HOLES`
  line first; a mostly-magenta window has no enclosed hole, so read its `transparent=` share too.
- **Jumbled text**: strings over each other or their art, cut off, the wrong size or font, or
  ids/`@TOKEN@` drawn as text.
- **Layout**: controls overlapping or out of place against the reference, gaps, content past the
  edge, a window cut short or stretched.
- **Visualization**: every spectrum or vis inside the area the skin gives it, aligned to it.

A skin with no `screenshot.png` is judged against its own artwork, and the note says `no ref`.

## The fix pass

**One worker** (`model: "sonnet"`; never two at once, since two builds or launches break each
other and the user's app) over every open row of the batch, never split by row group: a split pays
for every sweep twice. Brief it with the rows, these rules, and `skin-triage` Phase 5 onward:

- Fix each row at its root, general and named after the skin that showed it; commit with the
  ledger row moved.
- Run `scripts/wal_fix_check.sh <base> <out>` once, after all the fixes: it picks only the sweeps
  the diff can reach and serves the baseline from the run store. A difference in a skin that varies
  between runs of one build (OrbFace, -MfS3-, CopperdeckII, Aria_of_the_Soul, Invicta,
  winampmodern566, Cpro_Winamp_Modern, Quadelic, CPro_Winamp_for_Mac_Sync, WinampAzenis2,
  4-dreliction, cPro_T2T, Winamp_Single_GUI, LG_Free's clock frame; Symplicipod's `tLayer`;
  hatsune_miku_5's `visual.trigger` aim point; HALOAMP's `cont.clear.*` and `PLEdit` sizes;
  GlassAMPfinal's `DLibrary` size, 200x152 or 330x220 across dumps of one build;
  Official_Honda_Element_Skin's time-of-day seek dial; B296) is noise unless that skin is in the
  batch; where the list names a field, only that field is.
- Re-check only what a fix touched, with the scan's own tools on only those skins: the smoke for a
  control or Library fix, the census for a window or drawing fix. A window-layer fix also runs the
  census on every batch skin with that window, since nothing headless sees that layer.
- Do not spawn agents. Report in at most 10 lines: rows fixed and open, stages moved, `next:`.

Check the report: the status script exits 0 and `git log -1` is the worker's commit.

## Hand over

One message to the user: per skin, the scan's verdict in one line, and the few worth a look by eye
(deferred rows, judgment calls on a sheet, anything the smoke cannot see that the skin leans on).
**The user is not asked to test every skin.** Their go accepts the batch; a defect they report
puts that skin back to `filed` with the defect in its note.

## Running it

The orchestrator runs the scan itself and starts one worker for the fix pass; nothing else needs
a worker. Every call re-sends the whole context, so use the one-call scripts, never click by hand
(one hand-driven click is one tool call), and never run `window-interaction-matrix.sh` on an
intake skin (its close search blind-clicks every window's corner). Carry on from step to step
without asking; the turn ends while a worker runs, on a blocker, or at the hand-over.

## What this skill routes to

| Need | Owner |
|---|---|
| Phase 5 onward for one row | `skills/skin-triage` |
| `wal_intake.sh`, the run store, every sweep, the smoke | `winamp-modern-skin-guide/reference/harness.md` |
| Budget (25, no gain floor), tiers, why | `corpus-runner-plan.md` §8 *Decisions* |
| Backlog rows | `tasks/WINAMP5_TASKS.md`, closed into `backlog-archive.md` |
| Grades after promotion | `docs/winamp-modern/skin-compatibility.md`, rubric in `/wal-skin-report` |

## Changing the plan

`docs/winamp-modern/corpus-runner-plan.md` changes **only** by these edits. It is design and
history, never progress.

| When | Edit | Where |
|---|---|---|
| A batch is picked | one bullet: rev, the 25 names | §8 *Progress* |
| A batch is promoted | a *Done: intake #n* block: per skin that needed a fix, what was wrong and the fix; open rows by id | after the last *Done* block |
| A measurement changes a decision | the decision, measurement, date and rev — **proposed to the user first** | §8 *Decisions* |
| A parked instrument is built | *Parked* → *Built*; commands in `harness.md` | §7 |
| The backlog loop changes | the changed step | § *The loop* |

The plan's **Next:** line stays a pointer here.
