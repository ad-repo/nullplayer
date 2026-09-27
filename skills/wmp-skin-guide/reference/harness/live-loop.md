# `.wmz` harness: driving the app

Moved verbatim from `reference/harness.md` on 2026-09-25; that file is the router. Read it first.

## Driving the app: the loop that found the compact-mode class

Three of the four defects in the compact-mode report were invisible to every flag in `harness/probe-flags.md`, because a
**view switch is an app path** — the sweep renders each view independently and never performs one.
The loop below is what reproduced them, and it is cheap enough to be the default response to a
screen-only report rather than a last resort. Nothing in it is committed; rebuild it as needed.

1. **Select the skin and launch the debug build with the trace on** — one line, verified, nothing
   to restore afterwards (`app-control` § Route B):

   ```bash
   WMP_SEEK_TRACE=1 skills/app-control/scripts/launch.sh 9SeriesDefault
   ```

2. **Ask the probe where the control is, then click that frame.** `WMP_RENDER_PROBE` prints every
   drawn node's resolved frame in scene coordinates, which are the window's own top-left
   coordinates — so a `frame=540,304 20x19` is clicked at `(550, 313)` with a `CGEvent` posted at
   the window's origin plus that offset, found through `CGWindowListCopyWindowInfo` filtered on
   owner `NullPlayer`. Guessing from a screenshot wastes a launch per miss; a `BUTTONELEMENT` inside
   a `BUTTONGROUP` has no frame of its own at all and is resolved instead by decoding its
   `mappingColor` out of the group's mapping bitmap and adding the group's origin.

3. **Read `/tmp/app.log`, then capture the window.** `screencapture -o -x -l <windowid>` takes the
   window alone, transparency included. **Check the capture's pixel dimensions before reading the
   picture**: given a window id that has gone stale — the app relaunched, the view switched — it
   does not fail, it silently returns a **full-screen** image, and a screen crop compared against a
   window crop reads as the skin having lost half its artwork. (`-R` is the other half of the same
   trap: it wants `x,y,w,h` with commas and rejects `WxH`.) A window whose own capture is `192x82`
   at 1x and `384x164` at 2x is the one you asked for; anything near the screen's size is not.
   **Never point-sample a 2x capture against a 1x dump either** — a 2x render is not a 1x render
   scaled, and 4,252 opaque pixels came out "differing by >40" on a window with nothing wrong with
   it. Render the dump at the capture's scale, or compare shapes rather than pixels. It is far too slow to film a 250 ms animation — capture the
   *settled* state and use `WMP_RENDER_SETTLE` for the frames in between.

**What the trace settles that a screenshot cannot.** The compact-mode report read as one defect and
was three, and the `INPUT` lines separated them in one launch each: `dispatch load` missing said the
switch never loaded the view (W46); `setViewTimerInterval value=50` immediately followed by
`value=4000` said a chained timer had registered and then been dropped (W86); and `script-diag`
staying silent through all of it said no handler ever threw, which is what moved the search out of
the script and into the engine's own semantics.

### Capturing the hosted windows, one at a time

**Two eliminations come before this loop**, both cheap, both in `SKILL.md` § *Triage a hosted-window
defect before choosing a seam*: check the skin's own window (if it is right, the whole shared engine
is cleared and the defect is hosted-only), then read the frame PNG against the live window (a broken
dump is extraction, a clean dump over a wrong window is integration). Capture the set below to
localise a defect those two steps have already placed — not to go looking for one, and never by
multiplying the skin axis, which measures donors the reporter has already cleared.

**Start with `skills/app-control/scripts/winhelper capture-all <outdir> --pid <pid>`** — one PNG
per on-screen window, each its *own* content (`-l`, so occlusion and see-through holes cannot leak
in), each size-checked, a docked group cropped back to the window, and a non-zero exit naming any
window it could not shoot honestly (`skills/app-control` § Route C). It encodes the first trap
below. The park loop after it is the fallback for the windows `capture-all` refuses as off-screen.

A report about a **borrowed frame** is a report about ten windows, and the capture step has two traps
that each hand back a confident wrong picture (W219-W222, 2026-09-17):

- **`screencapture -o -x -l <id>` returns a full-screen image for a window that is off-screen**, the
  same silent fallback as a stale id, and these windows tile down a column that runs off the bottom
  of the screen the moment more than four are open. Check the capture's pixel size against the
  window's points × the backing scale before reading it, every time.
- **`-R x,y,w,h` picks up whatever is behind the window**, and a hosted window is mostly keyed-out
  artwork, so the window behind reads as *this* window's content: a visualizer showing through a
  transparent hole reads as a ground that was never painted.

`winhelper park` + `capture` answer both: `park` puts one window at an on-screen origin and proves
it landed, and `capture` shoots that window's own content (occlusion ignored) and refuses a
full-screen or unexpected size, cropping a docked group down to the window. Nothing needs moving
out of the way:

```bash
PID=$(pgrep -x NullPlayer | head -1); WH=skills/app-control/scripts/winhelper
"$WH" windows --pid "$PID" > /tmp/wins.txt
while IFS=$'\t' read -r id layer x y w h alpha name; do
  "$WH" park "$PID" "$name" 60 60 >/dev/null && "$WH" capture "$id" "/tmp/w-${name// /_}.png" --pid "$PID"
done < /tmp/wins.txt
```

**Compare every affected window before classifying the cause.** First compare donor identity,
requested point size, backing scale, frame readiness, and resolved content geometry. Normalize bare
edge fractions into point lengths: W228 left the same approximately 107pt rail gap unrepaired only
at tall library sizes, so a one-window symptom can still be a shared frame defect. Only after those
inputs match should a differing result point toward that window's composition/layout path.
The `TheUnit` report also contained independent frame and layout defects; capture all affected
windows rather than treating the first explanation as sufficient. See
[Alienware Invader's dossier](../skins/alienware-invader.md) for the size-dependent counterexample.

Windows are moved back on-screen afterwards. They are the user's.

### Auditing one authored control across the whole corpus

*"Every skin has this button and it does nothing"* is a shape of report the census cannot answer,
and W100 is the worked example: it stood **unmeasured for three days** at a recorded reach of 2
skins and the true number was **162 of 180**. **`scripts/wmp_control_audit.py <member>` runs this
route** (`harness/scripts.md` § *`scripts/wmp_control_audit.py`* says which of its click points to trust); the steps are
kept here because each exists to survive a trap the previous one hides:

1. **Scan the script text, not the census** (`scripts/wms_grep.py` does the decoding and prints the
   breakdown). `wmp_skin_census.sh` drives `onLoad`; a control's
   demand lives in `onClick`, so the sweep never reaches it. That blind spot is *the* reason a
   title-bar button can be authored by 90% of the corpus and tallied at 4%. Decode the way
   `WMPTextDecoder` does and **print the encoding breakdown** — 153 UTF-16-BOM / 145 cp1252 /
   88 UTF-8 / 9 UTF-8-BOM over the 180 archives is the calibration a correct scan reproduces.
2. **Resolve the handler through the call graph, not by matching the attribute.** `onClick` is
   usually a function name — `SwitchSmall()`, `ToggleSuperCompact()` — so a scan for the mechanism
   in the attribute text finds a fraction of the population. Three levels of body substitution was
   enough for this corpus.
3. **Find the clickable point from `WMP_RENDER_PROBE`, per view, for the whole corpus in one
   sweep.** A node with a frame is clicked at its centre. A `<BUTTONELEMENT>` has no frame and is
   resolved through its group's mapping bitmap — and **take the median pixel of the colour, never
   the first**: the first-scanline pixel lands on a stray or an edge and resolves to the *adjacent*
   button, which reads exactly like the engine dispatching the wrong handler. Two skins were
   misdiagnosed that way before the median fixed both.
4. **A `<BUTTONGROUP>` that draws nothing has no `PROBE` line**, so step 3 finds no group to hang
   the mapping decode on — `Cablemusic`'s is invisible for exactly this reason. Fall back to the
   authored `left`/`top` chain, or to a per-skin dossier under `reference/skins/`.
5. **Drive the click and read `unrecognised=`, not the screen.** `WMP_CALL_TRACE=1` alongside
   `WMP_RENDER_CLICK` is what turns "nothing happened" into
   `[handler-error] … unimplemented view.returntomediacenter`. Sampling 15 skins was enough to
   establish the class; the population came from step 1.

**`WMP_RENDER_CLICK` does not follow a view switch.** It rebuilds the *same* `viewID` after every
gesture, so a click posting `command=setCurrentView value=viewTiny` proves the switch was
*requested* and says nothing about what the user would then be looking at. For anything about the
view a skin lands on, the running app is the only arbiter — which is what the loop above is for.

### A live pass is a window frame, before and after

For "does the button change anything", the measurement is `CGWindowListCopyWindowInfo` filtered on
owner `NullPlayer`, read before the click and after it. It is objective, it is one command —
`winhelper clickdiff <x> <y> --pid <n>` (`skills/app-control` § *Route C*), which prints both
listings, names each window that moved, resized, faded, retitled, vanished or appeared, and **exits
2 when nothing changed** — and it scales to a skin per launch — eleven skins were audited this way
in one pass. Windows are matched by id, so a view switch that swaps windows reads as `gone` + `new`,
not as a resize. Its first check on 2026-09-25 was `Cablemusic`'s Shrink:
`changed … resized 593x600->475x373`. A screenshot
diff is the second reading, for the case where the window legitimately does not resize
(`portals`'s two views are both 359x465, and byte-identical captures are what proved that click
dead).

Three traps, all of which produce a confident wrong answer:

- **Check the window size against the view's canvas before believing anything.** A launch that
  failed to select the skin comes up on the unskinned view at **440x170** and looks like a working
  app. Four skins in one loop were driven that way — `zsh` does not word-split an unquoted
  parameter, so `set -- $row` handed the whole line to the first argument — and every "before" and
  "after" agreed, which reads as *the button does nothing* rather than as *no skin is loaded*.
- **`AXRaise` and activate first.** The first click on an inactive window is consumed activating it.
- **Play something.** `NULLPLAYER_PLAY` — a `status_onchange` lands five times a second with a track
  playing and it is what cancelled the click transaction in W113.

### Number the transactions before theorising about one

W88 was diagnosed wrong twice from the trace above, and the second fix was a no-op that produced a
byte-identical run. The line that misled was two `dispatch timer` entries with no `present` between
them, which reads as *the second tick cancelled the first before it ran*. It had not: the first tick
ran and presented normally, and the transaction that died was a later one that got as far as
`render` and was then cancelled at a **second** `guard !Task.isCancelled` — a different line, in a
different half of the function, losing a different thing.

Numbering settled it in one launch. A temporary counter in `dispatchScriptTransaction`, printing a
pair per transaction:

```
INPUT txn 207 begin timer handlers=1
INPUT txn 207 ran superseded=false hostCommands=["setViewTimerInterval=0"] diagnostics=0
INPUT txn 208 begin timer handlers=1          ← 207 never presented, never applied its command
```

`ran superseded=false` with no `command` line after it is the whole diagnosis: the handler ran, was
*not* superseded when it returned, and its output still went nowhere — which points at the code
between `transact` and the present, and nowhere else. `dispatch`/`present`/`command` lines carry no
identity, so any interleaving of them is inferred; a sequence number makes it read.

**Add the counter, take the answer, remove it.** It is not a documented flag, because a permanent
one would have to be — and the thing worth keeping is the technique, not the instrument. When a
transaction-level defect resists two readings of the trace, number them rather than reason harder.

### Measure the mechanism's reach before you fix it

"The timer display and seek/progress are broken in wmp for all skins" was diagnosed three times
before it was diagnosed right, and each wrong answer was a real defect with a reach too small to be
the report. The trace showed 1,352 `status_onchange` transactions in two minutes and a script-timer
set being replaced by every one of them, which is W119 and is genuinely wrong — but the corpus drives
its readouts with `timerInterval`/`onTimer` (**442 uses / 91 skins**), not with `setTimeout`
(**9 / 2**), so "every script timer dies when you press play" could never have been what all skins
had in common. One `python3` pass over the archives' `.js` and `.wms` said so in a minute; without
it, the next hour goes into hardening a path two skins use.

**The reach number is also what makes the fix defensible in the other direction.** W120 landed
because 73 sliders across 61 archives author `max="wmpprop:player.currentMedia.duration"` and no
`value`, and W51 landed because every one of the 19 handlers on a position-bound slider is a readout
painter and none writes the position back — that second measurement is the whole argument that
raising 2,141 write-back handlers cannot loop. Both took one scan of the flattened markup.
