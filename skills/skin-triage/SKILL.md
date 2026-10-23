---
name: skin-triage
description: The canonical test-and-fix procedure for a skin in every skin family (Classic, Original, Original-Metal, Winamp Modern .wal, Windows Media Player .wmz, Audion faces) — headless first over every window, control and component, blockers and unlockers fixed as they are found, a reference-image matching loop run to completion, then the live UI. Fixed phase order, the technique for each phase, the evidence that closes it, and a fill-in record. Use when a user reports a skin that looks or behaves wrong, when asked to test, fix or bring up a skin, or when picking up a skin backlog row.
---

# Triaging a skin

**The pass is the whole skin, never only the reported symptom.** The report says where to start; the
skin is done when every window, control and component has a verdict and the render matches its
reference. Headless first, because it is seconds per question and covers every control; the live UI
second, for what the harness cannot see.

This file owns the **order**. The mechanics live elsewhere and are not restated:

| Need | Owner |
|---|---|
| Launch, click, drag, capture, test data | `app-control` |
| Not fooling yourself with what came back | `live-ui-testing` |
| A family's probe flags and corpus scripts | that family's `reference/harness.md` (table below) |
| Cross-skin ranking (what to build next across the corpus) | `winamp-modern-skin-guide/triage-playbook.md` |
| A graded `.wal` report (A–F), on request | `/wal-skin-report` — grading, not this pass |
| An intake batch: its lifecycle and the per-skin progress ledger | `skin-intake` |
| Backlog rows outside an intake | `docs/winamp-modern/corpus-runner-plan.md` § *The loop* |

Copy [template.md](template.md) into the scratchpad at Phase 0 and fill it as you go. Each phase ends
on a **Confirm it took** line; do not leave a phase until it holds.

## Measuring has a budget; fixing starts early

Intake #1 measured for about a day — crawler, census, index, reach, demand, two new sweeps, plan
rewrites — before the first skin fix, and only stopped when the user forced it. Thoroughness means
every row gets a verdict, not that measurement goes on until the skins run out.

- **Instruments are frozen during a pass.** Use the probes and sweeps that exist. Build a new one
  only when a row cannot be measured any other way. Build it in one step, prove it on one known
  control, and go back to the pass. No plan or doc rewriting mid-pass.
- **Every measurement answers a fix decision.** Before running one, name the row it settles and
  what you will do with each answer. If no answer would change what you do next, skip it.
- **A blocker is fixed when it is found**, not after the inventory is finished: a startup abort, or
  a harness that cannot drive a gesture, voids everything measured behind it.
- **Budget:** the headless pass (Phases 2–3) is one dump plus one interaction/motion run per skin or
  batch, plus targeted probes for the rows those leave open. If no fix has been started after that,
  stop measuring and fix the top of the list.
- **The state matrix is capped**, not exhaustive: default theme, the reference's theme, and one
  other; each declared layout; stopped and playing; 1x and 2x; UI Size 100 and 135; the reported
  size. Add a state only for a row that names it.
- **Re-measure the row, not the world**, after a fix. Re-run the full batch pass once per blocker or
  unlocker landed, not after every edit.
- **Report progress as fixes**, so a stall shows: "N rows fixed, M open". Several measurements in
  a row with no new fix is the signal to stop and fix.

## What the automated checks miss

A green automated check is a regression result, not a correctness result. Intake #1's automated
checks missed five groups of defects; each group, its examples and the check that catches it are in
[misses.md](misses.md), with the table of traps that look like defects.

## A batch is one pass, not N single-skin passes

Applies to an intake or any set of skins. Intake #1 (B169, 25 `.wal` skins, about a week in the app)
went skin by skin, in the app first, and over three passes. Most of what it found was visible in a
headless dump — blank buttons, a group id drawn as a label, a font sheet drawn as art, titles not
uppercased. The rest were states nobody drove (UI Size 135%), and a click harness that had to be
fixed mid-pass. The plan's own record: `docs/winamp-modern/corpus-runner-plan.md`.

1. **Run Phases 1–3 over the whole batch at once**: one directory holding the batch, one dump, one
   interaction sweep, one motion sweep, each a single invocation (`--corpus <batch dir>`).
2. **Rank Phase 4 across the batch**: group every non-`works` row from every skin by its failing
   line. A group that spans skins is the unlocker; fix it once and re-run the batch.
3. **Prove the instruments before the batch**: one known-good control per gesture type (click, drag,
   hover, right-click) must read `works`. An instrument fixed mid-pass voids every verdict before it.
4. **The capped state matrix per skin** (above), driven headlessly in Phase 3 rather than
   discovered live.
5. **Go live per skin only for the residual**: rows the harness marks H, every class W check, and
   menus. A skin whose headless pass is clean gets one live smoke pass, not a full re-drive.
6. **One pass per skin.** Do not leave a skin until its inventory is complete; a second and third
   pass over the same skins is the cost this order exists to remove.
7. **Before an engine-wide fix, count its reach and check it against a reference**: a fix that moves
   ~50 other skins wrong is cheaper to reject before it is built (intake #1's TrueType cap-top rollback).
8. **Keep the branch to the batch**: code-quality reviews, refactors and changelog regrouping are
   done once at the end, not between skins.

## The family decides what "wrong" means

| Family | Ground truth | A sweep diff is | Headless harness | Harness reference | Backlog / dossiers |
|---|---|---|---|---|---|
| Classic `.wsz` | Winamp 2 sprite layout, `Skin/SkinElements.swift` | a regression | none — static + live | `ui-guide`, `non-retina-fixes` | `tasks/MISC_TASKS.md` |
| Original / Metal | `skin.json` + the engine's current behaviour | a regression | none — static + live | `original-skin-guide` | `tasks/MISC_TASKS.md` |
| `.wal` | the skin's own artwork, `screenshot.png`, `.m`/MAKI | unclassified | `WinampModernRenderDumpTests`, interaction + motion sweeps | `winamp-modern-skin-guide/reference/harness.md` | `tasks/WINAMP5_TASKS.md`, `skins.md` |
| `.wmz` | the skin's own artwork, markup, JScript | unclassified | `WMPRenderDumpTests` | `wmp-skin-guide/reference/harness.md` | `tasks/WMP_TASKS.md`, `reference/skins/` |
| Audion | the FaceKit oracle | a defect unless a listed departure | `AudionFaceRenderDumpTests` | `audion-face-guide/reference/harness.md` | `tasks/AUDION_TASKS.md` |

Classic and Original are finished engines: work on any other family that moves them is a regression,
whatever the argument (CLAUDE.md § Rules). An all-modes change the user asked for is not.

## Phase 0 — Intake

Applies to every pass, before any launch.

1. Name the skin **file** and record `shasum -a 256` — skins circulate in revisions under one name.
2. Name the family and any reported **state**: view/layout, colour theme, UI Size, window size,
   docked, playing (local or stream), first launch or relaunch.
3. Write the reporter's steps and symptom verbatim. Ask whether the live state was hand-repaired.
4. Note the scale of any screenshot given (1x or 2x) — compare only at one scale.

**Confirm it took:** the template's *Report* block is filled with no "probably" in it.

## Phase 1 — Recall and references

Applies always. Two questions: has this been seen, and what should it look like?

1. Open the family's dossier for the skin; search the backlog and its archive. A row found is the
   last investigator's hypothesis — **re-run its measurement** before trusting it.
2. **Collect every reference image**, in this order of authority:
   - the reporter's own screenshot of the intended look;
   - Audion: the FaceKit oracle render of each state;
   - images shipped in the archive — `screenshot.png`, `preview*`, `*.jpg`/`*.png` at the root,
     readme images;
   - a published screenshot the user points at.
3. For each, record which window, layout, theme and state it shows. A reference of a state you
   cannot reproduce is not yet usable — note the missing variable.

```bash
grep -rniE '<skin name>|<symptom keyword>' tasks/ docs/ skills/*/skins* skills/*/reference/skins/
mkdir -p "$S/x" && unzip -o -q "/abs/Skin.wal" -d "$S/x"     # .wal/.wmz are zips; S = scratchpad
find "$S/x" -maxdepth 3 -iregex '.*\(screenshot\|preview\|readme\).*' -o -maxdepth 1 -iname '*.png'
```

**Confirm it took:** the template lists each reference with its state, or says "none found" with the
places searched.

## Phase 2 — Headless inventory: the denominator

Applies to `.wal`, `.wmz`, Audion. Classic/Original: do the static half (sprite sheets present and
the size `SkinElements` expects; `skin.json` elements against `original-skin-guide`) and go to
Phase 6.

1. Render every container/view/layout in its default state; keep the PNGs.
2. List **every** window the skin declares (including `default_visible="0"` / script-opened ones),
   every control (button, toggle, slider, knob, seek, volume, balance, text, ticker, menu entry,
   drawer, tab) and every component (playlist, EQ, library, vis, video, album art, notifier).
3. Record per item: where it is (frame), whether it is drawn, whether it is reachable (not covered,
   not clipped), and what its art resolves to (missing bitmaps).
4. Read the script/compatibility report: a startup handler that aborts empties the inventory —
   that is the first blocker, before anything else.
5. **Open every dumped PNG and look at it** against the skin's artwork and reference. Check each
   for: blank or 0-tall controls, ids or `@TOKEN@` drawn as text, a font or sprite sheet drawn as
   art, see-through areas inside the body, content past the canvas edge, wrong font size. A
   structural pass with an unread PNG is not a pass.

```bash
WINAMP_MODERN_WAL="/abs/Skin.wal" WINAMP_MODERN_RENDER_DUMP="$S/base" WINAMP_MODERN_RENDER_BITMAPS=1 \
  WINAMP_MODERN_RENDER_SCRIPTS=bindings WINAMP_MODERN_RENDER_CLICKABLE=1 \
  swift test --filter WinampModernRenderDumpTests > "$S/base.log" 2>&1
WMP_SKIN="/abs/Skin.wmz" WMP_RENDER_DUMP="$S/base" WMP_RENDER_PROBE=all WMP_RENDER_OCCLUDED=1 \
  WMP_RENDER_SCRIPTS=1 swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus > "$S/base.log" 2>&1
```

Audion: `AUDION_FACE=<folder> AUDION_RENDER_DUMP=…` per `audion-face-guide/reference/harness.md`.
Redirect, never pipe — a pipe silently drops lines.

**Confirm it took:** an inventory table with a row per window, control and component, and the count
of each — the denominator every later verdict is out of.

## Phase 3 — Headless exercise: every button, every component, every state

Applies to every inventory row. Drive each one the way its bindings call for and record a verdict:
**works / silent / blocked / unbound / unreachable / wrong** (wrong = acts, but not as intended).

1. **Every control:** click, double-click, right-click (menu built?), drag for sliders/knobs, hover
   for hover art. A second click must undo a toggle.
2. **Every window:** open each declared window and each tab/drawer/page; open and close it again.
3. **Every state in the capped matrix** (§ *Measuring has a budget*), plus motion over time (two
   clocks, compare). Add a skin setting or theme only for a row that names it.
4. **Every component:** fed with data — a queue for the playlist, EQ values, a vis/VU level.

| Family | Drive every control | States |
|---|---|---|
| `.wal` | `WINAMP_MODERN_INTERACTION_SWEEP=<dir holding only this skin>` (`harness.md` § *The interaction sweep*), then `RENDER_CLICK`/`RENDER_HOVER` per row it did not settle | `RENDER_SHOW`, `RENDER_THEME`, `RENDER_SET`, `RENDER_LAYOUTS`, `RENDER_SIZE`, `RENDER_SCALE`, `RENDER_CLOCK`, `RENDER_PLAYLIST`, `RENDER_EQ`, `RENDER_VU`, `wal_motion_sweep.sh` |
| `.wmz` | `WMP_RENDER_CLICK`/`WMP_RENDER_HOVER` at each probed frame's centre; `scripts/wmp_control_audit.py <member>` for a control's corpus-wide reach | `WMP_RENDER_HOST=playing`, `WMP_RENDER_SIZE`, `WMP_RENDER_SCALE`, `WMP_RENDER_CLOCK`, `WMP_RENDER_APPKIT=1` |
| Audion | `AUDION_RENDER_CLICK` / `AUDION_RENDER_HOVER` per button | `AUDION_RENDER_STATE`, `AUDION_RENDER_CLOCK`, `AUDION_RENDER_SCALE`, oracle per state |

**Test every button.** Every control in every window, layout, view, tab and drawer gets every gesture
it can take, and **driven rows = Phase 2 control count**. Use the sweep first. Then drive whatever
the sweep skipped with the point probes (`RENDER_CLICK`, `WMP_RENDER_CLICK`, `AUDION_RENDER_CLICK`)
at each control's frame centre. The `.wal` sweep skips controls no script listens to (plain
`action=` buttons, script-free sliders and toggles) and covers only each open window's opening
layout. Classic and Original buttons are driven live in Phase 7.

Prove each instrument with one positive line before trusting its silence, and take the noise control
the sweep documents (a second baseline run) before reading a flipped verdict as real. **A `works`
verdict means something changed, not that it changed correctly**: open the after-render of each
control's gesture and check that the result is the intended one.

**Confirm it took:** driven control rows equal the Phase 2 control count, and every row carries a
verdict and the tool output that earned it; none reads "not tried".

## Phase 4 — Blockers and unlockers: rank before fixing

Applies to the non-`works` rows. Fix order is decided here, not by which row was found first — except
a blocker, which was already fixed when Phase 2 or 3 found it.

- **Blocker** — one fault that hides others behind it: a startup handler abort, the first
  unsupported method or host member in a handler, a missing window or layout, a layer covering a
  control group, a unit error feeding every meter. Everything behind a blocker is *unmeasured*, not
  broken.
- **Unlocker** — one fix that turns many rows to `works`: the same missing method, attribute,
  action or host member behind several controls. Group rows by the line that failed; the largest
  group is the unlocker.
- Rank: **blockers first** (deepest-in-the-chain first), **then unlockers by rows unlocked**, then
  single rows. For an engine-wide unlocker, count its reach in the corpus too
  (`wal_reach.sh` / `wal_demand.sh`, `wmp_control_audit.py`) — it outranks this skin's rows.
- Classify each group A/B/C/D/W/H (table below). D is recorded once and not fixed.

| Class | It is | Detector |
|---|---|---|
| **A** Missing capability | unimplemented tag, attribute, method, host member | report **after driving**, archive scan |
| **B** Wrong semantics | implemented, behaves differently | pixels against the reference; nothing automatic |
| **C** Missing content | unresolved bitmap, `nil` host value, unrouted surface | `missing=`, holder lines |
| **D** Out of scope | sandbox or product policy | the won't-do record |
| **W** Window, not scene | placement, size, order, shadow, docking, scale | Phase 6 fork says "window" |
| **H** Harness artefact | the instrument cannot see the state | `live-ui-testing` § *What a green sweep does not cover* |

**Confirm it took:** an ordered fix list, each entry naming its class, the failing line, and the rows
(and corpus skins) it is expected to unlock.

## Phase 5 — Fix as found, re-measure the whole inventory

Applies to the top of the fix list, one entry at a time, looping until the list is empty or only D
and H remain.

1. Measure the mechanism before writing code — instrument the whole path, read what each handler is
   **handed**, read the skin's own source (`.m`, JScript, `index.json`) before disassembling.
2. Fix it in the layer that owns the concept; fix the **rule**, never a skin-name special case. In
   shared code gate on `controllerFamily == .<family>`. A unit change moves every producer and
   consumer at once. Never relax a load limit or sandbox rule — degrade with a diagnostic.
3. A mechanism change gets an env A/B kill switch, documented in the family `harness.md` in the same
   change.
4. **Re-run Phase 2 and Phase 3 in full** — not just the row. A cleared blocker exposes the next
   fault; new rows join the list and are re-ranked.
5. A fix that changes nothing: look for the next stacked fault before reverting.

**Confirm it took:** the after-run's verdict table, with the rows the entry predicted now `works` and
no row that was `works` before now worse.

## Phase 6 — Reference matching loop

Applies when Phase 1 found a usable reference. Loop until complete; "close enough" is not a stop.

1. Reproduce the reference's exact state headlessly (layout, theme, setting, size, playing) and
   render it; crop both to the same window at the same scale (1x).
2. Diff: `scripts/png_diff.py ref.png render.png` — read the class (`lost`, `gained`, `moved`,
   `recolour`, `size`) and the bbox, then look at both side by side.
3. Take the **largest** differing region, find its object (`RENDER_PROBE` / `WMP_RENDER_PROBE`
   frame inside the bbox), and treat it as a fix-list entry: measure, fix, re-run Phases 2–3.
4. Re-render and re-diff. Repeat.
5. **Complete** means every remaining difference is listed with a reason that is not the engine:
   live data (title, time, art), a font the system lacks, desktop showing through alpha, a state the
   reference shows that cannot be reproduced (named). Anything else is still a defect.
6. Never edit the render toward the picture with a skin-specific offset: every match is a rule, and
   Phase 8's sweep proves it did not cost another skin.

Classic/Original have no headless render: run this loop on window captures from Phase 7.

**Confirm it took:** the last diff, and a residual table where every region has a non-engine reason.

## Phase 7 — The live UI

Applies after the headless pass is clean. Same inventory, now on screen.

1. Launch with `skills/app-control/scripts/launch.sh <skin>` (playing by default), every probe the
   pass may need exported in front — probes are read once at start. Confirm the family with
   `menu.applescript family <pid>`; the unskinned `.wmz` view is 440x170.
2. Mark the log, then drive **every inventory row** on screen (`app-control` Route C), clicking each
   control at the centre of its probed frame. Open every window; play, pause, seek, change volume.
3. Capture the window itself (`screencapture -o -x -l <id>`). For each row, compare against the
   headless render of the same state:
   - **agree** → nothing new; a defect here is a scene defect, back to Phase 5 headless;
   - **disagree** → class W: view `draw`, hierarchy, layer backing, frame, ordering, compositing.
4. Run the automated window checks on the skin: `skills/app-control/scripts/window-census.sh <skin>
   --shots` (where every window opens and how big it is, compared with the screen) and
   `window-interaction-matrix.sh <skin> <out.tsv>` (open, stretch and close every window). Open the
   shots.
5. Window-only checks the harness never sees: placement and size on open, drag and resize, docking,
   shade/unshade round trips, z-order (`CGWindowListCopyWindowInfo` with `.optionOnScreenOnly`),
   shadow, 1x and 2x displays, relaunch with persisted state.
6. Contextual menus cannot be opened synthetically — check those by hand or hand them over (Route D).
7. Every W fix returns to Phase 5's loop and then re-runs this phase.

**Confirm it took:** each inventory row has a live verdict beside its headless one, and every
disagreement is fixed or filed.

## Phase 8 — Verify

Applies to the finished pass.

1. Re-run the reporter's own steps end to end on a fresh launch of the final build.
2. Before/after captures of the identical state.
3. Run the family sweep and **classify** its diff (`skin-subsystem-blueprint` § *A sweep diff is
   unclassified*): harness noise first, invariants before images, a sample of changed skins chosen
   before opening any. A byte-identical sweep across a hover/drag/timer/playback change is
   *unmeasured*. For `.wal`, diff the interaction and motion sweep verdicts too.
4. Change touched shared code: Classic and Original captures byte-identical.

**Confirm it took:** the reporter's symptom is gone, the inventory is all `works`/D/H, and the sweep
reads "N changed: opened, repairs, regressions, unexamined".

## Phase 9 — Hand over, then land

1. Hand the build back, naming **which build** in the same sentence, labelled "attempted", with the
   inventory and residual tables.
2. Stop driving the moment the user starts testing.
3. After the user confirms (or after Phase 8 for agent-verifiable rows): tests that fail without each
   fix; findings in the owning skill reference, numbers dated beside their command; a dossier for a
   skin with two or more unrelated defects, including **what was ruled out**; backlog rows closed
   into the archive; a changelog line at the bottom of the current version.

**Confirm it took:** the user said it works, and every artefact names the skin's sha256 or its row.
