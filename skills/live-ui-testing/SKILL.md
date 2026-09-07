---
name: live-ui-testing
description: How to debug a defect that only exists on screen — instrument first, drive the app yourself, and measure what is actually drawn. Cross-subsystem process skill. Use when a bug reproduces in the running app but not in tests, when a headless sweep says a subsystem is fine and the user says it is not, before claiming any visual fix works, or when a GUI-only report has already survived two wrong hypotheses.
---

# Debugging a live UI defect

## Read the subsystem's own debugging reference first

**`skills/winamp-modern-skin-guide/reference/harness.md` § *Debugging a live defect* is the reference
implementation of this whole workflow**, earned over thirty-odd phases of the most successful
reverse-engineering effort in this repo. Its rules are normative there and transferable everywhere;
`skills/winamp-modern-skin-guide/SKILL.md` § *Rules for extending this subsystem* is the one-line
index into them.

This file exists because a 2026-09-07 `.wmz` session spent hours rediscovering five of those rules
the hard way, having never opened them:

| Rediscovered painfully | Already written down |
|---|---|
| `kill_build_run.sh` piped to `tail` never completes | harness.md §*The measurement loop* step 2 — the script **stays attached to the app it launched** |
| `System Events` clicks silently did nothing useful | §*Driving clicks in the running app: `CGEvent`, never System Events* |
| Raising the app by name launched the installed build | §*Raise the build under test with System Events by unix id* |
| A green headless sweep proved nothing about the screen | §*A structural probe is not a picture* |
| "Fixed" announced twice on an unverified change | §*A number that moved is not the symptom that was reported* |

**So: before diagnosing anything, open the owning subsystem's harness/debugging reference and read
its process section.** The cost of not doing so is measured in hours, twice now. If the subsystem has
no such section, this file is the fallback and your findings belong in that subsystem's skill
afterwards.

## Pick your working mode first

Borrowed from `winamp-modern-skin-guide`, and it applies to any skinnable/corpus-shaped subsystem.

| You are… | Start with | Not |
|---|---|---|
| Debugging one reported defect | the repro, driven by you, plus the subsystem's live probe | reading engine source |
| Measuring what a input/skin/file contains | the subsystem's census/report tool | ad-hoc dumps whose findings evaporate |
| Deciding what to build next | the subsystem's backlog + corpus census | fixing whatever the last report named |

Two habits those exist to break: **a test case is not a milestone** (one fix that unblocks 200 inputs
beats ten that unblock one), and **an input's default state is not the input** (the defect may be in
a view, pane or mode the thing does not open with — see the `viewTiny` trap in `wmp-skin-guide`).

## Instrument before you reason

The always-paid rule. Deducing a mechanism from source produced three wrong answers in a row on one
`.wal` defect and **four** on the `.wmz` one; a live trace settled each in a single launch.

- **Ask for — or build — the live trace after the *first* failed retest, not the fourth.**
- **Decide the full probe set before launching.** Probes are `ProcessInfo…environment[...]` read once
  in a `static let` at process start. You cannot turn one on later, and an already-running app reports
  nothing no matter what you export. Prefer too many probes over a relaunch.
- **Instrument the whole path, not the point you suspect.** Tracing three of four `present` call
  sites yielded one misleading line and a confident wrong conclusion built on it; the untraced site
  was the one that mattered.
- **Prove the instrument runs before believing what it does not say.** A trace silent because its env
  var never reached the process is indistinguishable from one silent because the code never ran.
  `ps eww -p <pid>` shows what the process actually got. See harness.md §*A blind instrument reads as
  a working feature*.

## Drive it yourself

**If you can launch it, click it and photograph it, do not ask the user to.** Get the repro steps
from them, then run those steps yourself. Every hypothesis routed through a human costs a round trip,
and most hypotheses are wrong.

Where live QA genuinely needs a human (judging "does it look right"), treat it as an interactive
session, not blocked work — harness.md §*The measurement loop that works: mark, window, control*
defines the division of labour: **the agent owns the process and the log; the reporter owns the mouse.**

### Launching

`./scripts/kill_build_run.sh --debug` builds, ad-hoc signs the vendored frameworks, and launches.

- **It does not exit.** It stays attached to the app it launched. Piping it into `tail`/`head` means
  the pipe never closes and the task never reports completion — it looks like an eternal build. Sat
  "building" for eight minutes after finishing. Redirect to a file.
- **A binary launched from the agent shell inherits background QoS** (`nice` 5): the UI throttles,
  timers defer, and the spectrum analyzer stops animating — which reads exactly like a rendering bug.
  `skin-screenshots` hard-fails on this. Un-throttle after launch (`-B` needs `-p`, it is not a prefix):

```bash
WMP_TRACE=1 nohup ./.build/arm64-apple-macosx/debug/NullPlayer > /tmp/app.log 2>&1 &
sleep 5; taskpolicy -B -p "$(pgrep -f 'debug/NullPlayer' | head -1)"
```

- **The bare binary has no bundle identifier**, so its `UserDefaults` live in the `NullPlayer` domain,
  not `com.nullplayer.app`. A preference written to the wrong domain silently does nothing and reads
  as the app ignoring it. Check both.

### Driving

`skills/skin-screenshots/scripts/` already solves this — use it rather than writing AppleScript.

| Need | Use |
|---|---|
| Window rect | `./winhelper windows` → `layer x y w h alpha title` |
| A real click | `./winhelper click <screenX> <screenY>` — **`CGEvent`, never System Events** |
| Switch skin system | `osascript menu.applescript mode "<submenu>"` |
| Select a skin | `osascript menu.applescript skin "<submenu>" "<item>"` |
| Close aux windows | `osascript menu.applescript closeaux` |

- **Raise the build under test by unix id**, never by name — by name launches the *installed* app:
  `osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $P) to true"`
- **A CGEvent click goes to the screen, not the app.** If the app is not frontmost the click lands in
  whatever window is there; one went into a browser and produced a silent null result.
- **Clicking a submenu name does not switch skin system** — that needs its "Switch to …" item, which
  `menu.applescript mode` finds. See `skin-screenshots` rule 1.
- **Confirm the target before clicking it** with the subsystem's headless click probe (for `.wmz`,
  `WMP_RENDER_CLICK="<view>@x,y"`), or you will click the wrong control and misread the result.
- Playback is a precondition for many visual defects. Drive the skin's own Open button, then
  `Cmd+Shift+G`, path, Return, Return — and **check the track's length**: a 5-second file ends
  mid-diagnosis and the resulting `AudioEngine.stop()` looks like a bug.

### Mark the log, and take a control

Straight from harness.md, and both were skipped in the `.wmz` session:

- **Mark the log before every run** (`wc -l` into a file, then `tail -n +N`). One log accumulates many
  runs and "the last N lines" is not a window.
- **Always take a control.** One window proves nothing: change exactly one variable and re-run. A
  before/after on the identical setup is what turns "fixed" into a measurement.

## Measure; do not eyeball

Eyeballing screenshots produced three wrong conclusions in one session, including "the app is in a
different view" (it was not) and "the window is oversized" (it was exactly right).

```bash
./winhelper windows | awk -F'\t' '$2==0 && $7>0 {print $3,$4,$5,$6; exit}'
screencapture -x -R $X,$Y,$W,$H /tmp/win.png     # the window only
```

**The measurement that ends renderer-versus-AppKit arguments:** dump the image the renderer produced
and compare it to a screen capture of the same rect. Same size, so points correspond.

- They agree → the bug is in the renderer/scene; go back to the headless harness.
- They disagree → the renderer is innocent; the bug is a view's `draw`, the hierarchy, layer backing,
  or window compositing.

That single comparison ended a multi-hour hunt in which every prior step was speculation about which
half was at fault.

**Colour arithmetic names the culprit.** A translucent fill over a known background yields an exact
value: `calibratedWhite 0.04, alpha 0.9` over white is `0.04·0.9 + 1·0.1 = 0.136` → `(34,34,34)`, and
over black `(9,9,9)`. Both matched observed pixels to the digit, which found the offending `draw` by
grepping for that one colour. Compare with harness.md §*The measurement that finds scale bugs*.

Two checks that rule out whole families of cause before theorizing: `winhelper windows` (a stale
window from a mode switch explains a lot) and a recursive hierarchy dump behind `#if DEBUG` — class,
`frame`, `bounds`, `layer != nil`, `isOpaque`, `isHidden`, `layer?.backgroundColor`.

Report **distributions, never samples**, for anything timing-shaped, and **read whole log lines,
never independently-grepped halves** — pairing two `grep -o` results from different windows
manufactured a false causal claim once already.

## Reading a result without fooling yourself

- **A structural probe is not a picture.** "The widget exists at frame X" says nothing about what is
  drawn there. Render it or run it. harness.md §*A structural probe is not a picture*.
- **A number that moved is not the symptom that was reported.** Fixing the measurable fault while the
  reporter's actual complaint survives produces a confident false "fixed". Reproduce the reporter's
  steps end to end. harness.md §*A number that moved…*.
- **Check what a handler is *handed*, not just that it ran.** A method being called proves nothing;
  its arguments are the finding.
- **Verify the state before diagnosing the behaviour.** Confirm which skin, view, mode and build are
  on screen — persisted selections lie. Hours went into diagnosing a view that was not the one
  displayed, while the user said twice that the two modes looked identical, which *was* the finding.
- **When a fix changes nothing on screen, look for the next fault before reverting.** Faults stack.
- **Geometry has no useful armchair form.** Measure it in the running app; see the `testing` skill,
  §*Window geometry: measure it, never reason about it*.

## Reporting, and landing what you learn

- **Never write "fixed" for something you have not observed working.** Label it "attempted".
- Separate what you verified from what you inferred, every time.
- **Hand the fix back for on-screen judgment before writing anything down** — tests, docs, changelog
  and backlog come after the user says it looks right (`verify-before-investing`).
- **When the user contradicts you, check their claim before defending yours.** They are reporting the
  screen; you are reporting a model of it.
- **Land the finding in the owning subsystem's skill**, not here and not in `CLAUDE.md`. An ad-hoc
  dump nobody wrote down gets re-derived — two `.wal` phases were lost that way. Keep measured
  numbers next to the command that produces them; a number pasted into prose goes stale silently
  (harness.md §*A measured value written into a doc goes stale silently*).
