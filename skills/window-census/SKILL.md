---
name: window-census
description: Measure where every NullPlayer sub-window opens and how big it is, per skin or across the whole skin corpus (Classic, Original, Original-Metal, .wal, .wmz), and report the findings — which windows open too large, off screen, or fail to close back. Use when asked to run the window census, baseline default window sizes, compare default sizes across skins or families, or check whether a sizing change moved any skin's defaults.
---

# Window census

The instrument is `skills/app-control/scripts/window-census.sh`. Its mechanics live in `app-control`
§ *Window census*: status vocabulary, file columns, and how each skin is isolated from the last.
This skill is the **user interaction around a run**: what to confirm, how to run it, and what to
report. Read that section once before the first run in a session.

## 1. Scope the request

Turn the request into the script's arguments:

| Request | Arguments |
|---|---|
| named skins | `aquamp corona "2222-cPro__Bento"` (anything `launch.sh` takes) |
| one or more families | `--all wal` / `--all classic,original,metal` |
| the whole corpus | `--all all` |
| "with screenshots" | add `--shots` (a PNG per opened window, plus `shots.zip`) |

Run `window-census.sh --list <families>` to get the count; it launches nothing. On 2026-09-27 the
corpus was 307 skins: 26 classic, 14 Original, 7 Metal, 80 `.wal`, 180 `.wmz`. **Budget about a
minute per skin**, so the full corpus takes 5–6 hours.

## 2. Confirm before starting (anything over a handful of skins)

State all of this in one message and wait for the user's go-ahead:

- **Skin count and time estimate.**
- **It takes over the machine.** The script clicks the menu bar and raises the app for the whole run.
  The user should not use the mouse or keyboard meanwhile, or clicks land in the wrong app.
- **It quits any running debug build**, including another session's. Name the pid if one is up
  (`pgrep -lf 'debug/NullPlayer'`). The installed app is never touched.
- **Whether to clear the shared size keys first.** Until
  `~/.claude/plans/skin-window-size-isolation.md` lands, the debug domain holds
  `hostedInteriorSize2.*` sizes that every skin inherits. A true-defaults baseline needs them gone.
  Ask; don't delete on your own. If the user agrees:
  `defaults read NullPlayer | grep -o '"hostedInteriorSize2\.[^"]*"' | tr -d '"' | while read -r k; do defaults delete NullPlayer "$k"; done`,
  **before** the run, because the census saves the domain as its baseline at start.
- **The output directory.** Default `/tmp/np-window-census/<timestamp>/`. For a corpus run, pick a
  stable path such as `/tmp/np-window-census/corpus-<date>`, so an interrupted run resumes into it.

## 3. Run it

- **Freeze the tree.** Make no source edits during the run. The first launch builds, and an edit
  mid-build aborts it.
- **More than ~10 skins: hand it to a worker** (a Haiku subagent) with the exact command. It buys
  context, not time. The worker runs it **in the foreground** with the longest Bash timeout, never
  `run_in_background`, because a detached sweep is killed mid-build and still exits 0. If the
  timeout ends the call, re-run the **same command with the same `--out`**. Finished skins are
  skipped and the defaults baseline is reused, so repeat until every skin has a `CENSUS` line.
- **Handle stdout lines as follows:**
  - A `CENSUS … launch failed` line is recorded in `skins.tsv`; the run carries on.
  - `app-exited` means the app crashed during that skin. Note it and don't re-run it silently.

## 4. Report

The user wants findings, not a file dump. Read `skins.tsv` and `windows.tsv` (plain TSV with one
header row, so `awk -F'\t'` or `sqlite3 -tabs` works) and answer with:

1. **The largest default sizes.** Per window item, rank the skins by `w`×`h` among `role=item`,
   `status=opened` rows, and say which family each extreme belongs to. Compare with the classic size
   (275×`Skin.scaleFactor` = 344 pt wide at 100%); the rule in the size-isolation plan is that every
   native window defaults to it.
2. **Main window size per family**: the `main_w`/`main_h` spread from `skins.tsv`.
3. **Problems:**
   - `reachable=0` rows;
   - `residue=1` rows, where a window didn't close back to the baseline;
   - launch failures and `app-exited`;
   - enabled items that read `no-window`: skin-drawn panels the census can't see, so name them
     rather than count them as broken.
4. **The paths**: `report.md` for reading, the TSVs for queries, and `shots.zip` if taken.

Keep the per-skin tables in `report.md`. The answer is the summary and the outliers.

## Debugging a live defect

A census row is a measurement, not a diagnosis. To chase why a window opens where it does, read
`live-ui-testing` and then `app-control`, and drive that one skin by hand. The reference workflow is
`winamp-modern-skin-guide/reference/harness.md` § *Debugging a live defect*.
