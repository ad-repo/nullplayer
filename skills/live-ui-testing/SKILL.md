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
its process section.** For the *mechanics* — how to launch into a state, drive a control, and
capture a window — go to **`app-control`**; this file is about not fooling yourself with what comes
back. The cost of not doing so is measured in hours, twice now. If the subsystem has
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

### A silent trace after a synthetic click usually means you missed the control

Posting `CGEvent`s from the agent shell works — the cursor really moves, and `CGEvent(source: nil)`
read back after a post proves it. What does not work is guessing where to click. A pointer sweep and
four clicks across a `.wmz` skin produced **zero** trace lines, which reads exactly like dead input
handling; the skin was circular and every point had landed on transparent pixels outside its shell.

So before filing "input does not reach the app": **take the target's frame from the subsystem's own
probe and click its centre**, never a coordinate estimated from a screenshot. `WMP_RENDER_PROBE`
prints `frame=40,189 20x20` per node; screen point = window origin (from
`CGWindowListCopyWindowInfo`, top-left origin, same space as the event) + the frame's centre. Done
that way the same app answered on the first try, with `INPUT hover -#- -> mute#33`.

Two cheap checks that separate the three failure modes, in order: is the cursor actually moving
(post, then read the location back); is the build under test frontmost (by unix id, never by name);
and is the point inside a node rather than inside the window. Only after all three should the app's
input path be suspect.

### Launching and driving — see `app-control`

**`app-control` owns the mechanics**: Rule zero (the app under test is always the local debug
build), the Route B state matrix for launching straight into a mode / skin / playback state with a
"Confirm it took" observable per row, the `winhelper` and `menu.applescript` verb tables, and the
canonical test-data targets. It owns the tools, too — they live in
`skills/app-control/scripts/`.

Three of its rules are load-bearing for everything below and are restated here because a wrong
answer to any of them invalidates the whole session:

- **`./scripts/kill_build_run.sh --debug` is the build-and-run command, and it stays attached to
  the app it launched.** Piping it into `tail`/`head` means the pipe never closes and the task
  never reports completion — it looks like an eternal build. Use its `--log <path>`.
- **Never drive the installed app.** Not `nullplayer`, not `open -a`, not
  `activate application "NullPlayer"`. Raise and address the build under test by unix id.
- **A CGEvent pair without `mouseEventClickState` is not a click.** It arrives `clickCount == 0`:
  the pointer moves, hover traces update, and no click is ever synthesised. This produced a
  confident wrong conclusion in one session — "the skin's play button is dead" — and it was the
  tool, not the app. `winhelper click` and `drag` set it for you.

Two boundaries `app-control` cannot cross, which are epistemic and therefore this file's:

- **A synthetic right-click does not open a contextual menu, even with `clickState` set.** A
  `CGEvent` `.rightMouseDown`/`.rightMouseUp` pair produced no menu and no `menu(for:)` entry trace
  against a menu a real right-click opens fine. That absence was written up as an engine defect —
  "no right-click reaches `menu(for:)`" — filed in a subsystem backlog, and withdrawn the same day
  when the reporter simply used the feature. **A menu is the one interaction to verify by hand.**
  Absence of a menu under synthetic input is evidence about your tool and nothing else.
- **Confirm the target before clicking it** with the subsystem's headless click probe (for `.wmz`,
  `WMP_RENDER_CLICK="<view>@x,y"`), or you will click the wrong control and misread the result.

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
skills/app-control/scripts/winhelper windows | awk -F'\t' '$2==0 && $7>0 {print $3,$4,$5,$6; exit}'
screencapture -x -R $X,$Y,$W,$H /tmp/win.png     # the screen there — WHATEVER is on top
screencapture -x -o -l $WINDOWID /tmp/win.png    # that window's OWN content, occlusion ignored
```

**`-R` photographs the screen, not the window.** During agent-driven QA the thing on top is routinely
your own terminal, and the capture then shows the terminal while you reason about the app. `-l
<windowid>` (id from `CGWindowListCopyWindowInfo`) captures the window's own content regardless of
what covers it, and **the difference between the two is itself the measurement**: window content
correct + screen wrong ⇒ nothing is wrong with drawing or sizing, and the whole question is
compositing. That is what settled a "the video goes black" defect in one step — the window was full
of playing movie the entire time; it had simply fallen behind its own parent window.

**For z-order, pass `.optionOnScreenOnly`.** `CGWindowListCopyWindowInfo([.optionOnScreenOnly,
.excludeDesktopElements], kCGNullWindowID)` returns front-to-back. `.optionAll` includes offscreen
windows and its ordering means nothing — reading order out of an `.optionAll` list reported a window
as frontmost when it was behind, and cost a wrong diagnosis.

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

Two checks that rule out whole families of cause before theorizing: `app-control`'s `winhelper windows` (a stale
window from a mode switch explains a lot) and a recursive hierarchy dump behind `#if DEBUG` — class,
`frame`, `bounds`, `layer != nil`, `isOpaque`, `isHidden`, `layer?.backgroundColor`.

Report **distributions, never samples**, for anything timing-shaped, and **read whole log lines,
never independently-grepped halves** — pairing two `grep -o` results from different windows
manufactured a false causal claim once already.

## What a green sweep does not cover

A corpus sweep renders every skin in its **default state**. That is a real proof and a narrow one,
and reading it as a general one has now cost two sessions.

- **A byte-identical sweep across an interaction-state change means *unmeasured*, not *unchanged*.**
  A default capture never enters a hover, a down state, a drag, a timer tick or live playback. A
  `.wmz` `BUTTONGROUP` painting its entire 593x600 hover sheet over the window swept **535 identical,
  0 differing** — because nothing in the sweep hovers. Say which of the two you have before quoting
  the number.
- **Live QA without playback is a different test from live QA with it.** Two `.wmz` defects lived
  only in the `psPlaying` branch — a host member that aborted the handler filling every readout —
  and a third appeared *only* while a status transaction was landing five times a second and
  cancelling the click's task. A pass without a track playing found none of the three and looked
  clean. If the subsystem has a playing state, drive one.
- **A fix that makes dead code reachable is where latent traps fire.** Giving a node a frame for the
  first time reached, in the same change, a `Dictionary(uniqueKeysWithValues:)` that trapped the
  process on a skin with two identical keys, and a paint path that had never had a caller. Neither
  was a regression in the new code; both were waiting. When a change turns a class of nodes from
  ignored into drawn, budget a pass for what it uncovers rather than treating the first crash as
  proof the change was wrong.
- **Close the biggest abort and re-measure the whole table.** A handler dies on its *first*
  unrecognised member, so one missing name hides every one behind it. Two host members were found
  this way, one per launch, each invisible until the one in front of it was implemented — the same
  shape as the `.wmz` `mediacenter` row. Never read one row falling as progress without re-measuring.

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
- **A skin, theme or preset that produced two or more unrelated defects earns a dossier**, not just
  backlog rows: what it exercises that nothing else does, what it found, **what was ruled out**, and
  the coordinates that reach its controls. The ruled-out section is what saves the next session and
  the one always left out. `skills/wmp-skin-guide/reference/skins/` is the worked example. Record
  beside it the *counter-evidence* — the cases that disagreed with a fix that looked right, one rule
  each. A sweep tells you that once and nothing else remembers it.
- **Land the finding in the owning subsystem's skill**, not here and not in `CLAUDE.md`. An ad-hoc
  dump nobody wrote down gets re-derived — two `.wal` phases were lost that way. Keep measured
  numbers next to the command that produces them; a number pasted into prose goes stale silently
  (harness.md §*A measured value written into a doc goes stale silently*).
