# `.wmz` harness: probes that are not in the test binary

Moved verbatim from `reference/harness.md` on 2026-09-25; that file is the router. Read it first.

### The probes that are not in the test binary

`WMP_PLACE_TRACE=1` is read by **the app** (`WMPViewWindowMaterializer.place`) and prints one
`[wmp/place] <viewID> <frame>` line per auxiliary window, at the moment it is placed and never
again — placement happens once per window, so a window the user has moved is never yanked back.
It is the `.wmz` counterpart of `WINAMP_MODERN_PLACE_TRACE`, and it exists for one question a
screenshot answers badly: **a skin that opens five panels at load has five windows to fit**.

**Since W217 a stranded `.wmz` window is recoverable — Snap To Default has a `.wmz` routine, and
since G2/G3 (2026-09-20) the off-screen safety net and the session restore correction run in `.wmz`
too — so a `[wmp/place]` frame outside every screen is a defect and not merely a warning.** It is
also now transient rather than permanent: the sweep runs after a display change, a UI Size change, a
skin load and the post-restore settle, so a trace taken at placement time can show a frame the app
has already corrected by the time you look at the window. **Read the window back with
`winhelper windows` before calling a `[wmp/place]` line a live defect** — placement and the settled
layout are two different measurements, and only the second is what the user sees. The same flag now
also prints `[place/tile] hosted <frame>` for NullPlayer's own windows opening in WMP mode (they
share the `.wal` tiling branch of `positionSubWindow`) and one `snap-to-default` line per window on
each press. Read the frames back with `app-control`'s `winhelper windows`, never off a screenshot,
and check idempotency by `diff`ing two presses.
`Halo 2`'s `onLoadSkin` opens four from its own preferences plus `mainView`, and the failure mode
is not a wrong-looking window but an invisible one — the tiler walking off the bottom of its column.
A line whose frame is outside every screen is the `rescuedOrigin` fallback failing; a line that
repeats for the same view is placement running twice, which is the bug this flag exists to catch.

```bash
WMP_PLACE_TRACE=1 skills/app-control/scripts/launch.sh <skin>        # log: /tmp/np.log
```

`WMP_SIZE_TRACE=1` is read by **the app** (`WMPMainWindowController.windowDidResize`, DEBUG, through
`NSLog`) and prints one line per resize of a `.wmz` window — the view, the new frame, whether it is
our own scene size landing (`applying=true`), and **the call stack that asked for it**:

```
[wmp/size] <viewID> -> (<W>, <H>) applying=<bool>
<14 frames of backtrace>
```

**The backtrace is the whole instrument, because the question this flag exists for is not what size
the window is — every other probe answers that — but *who* chose it.** W213's third defect was a
`.wmz` player that opened at the skin's 192x82 and was 192x145 a click later, and the size alone is
compatible with four unrelated causes: the skin's own script, a stored size, the scene builder's
clamp, or a pass in `App/` that has no idea a skin is loaded. It was the fourth — one frame named
`WindowManager.tightenClassicCenterStackIfNeeded`, reached from `windowDidFinishDragging`, growing
the window to `Skin.mainWindowSize.height` because `isRunningModernUI` answers false for the WMP
controller. **Two days of reasoning had already produced a guard against the stored size**, which is
a real rule and was not this bug; the trace found the cause on its first run. Reach for it before
theorising about any `.wmz` window that is not the size its markup says, and note the pairing: a
line with `applying=true` is ours settling and is not evidence of anything.

It prints a second kind of line, and that one is a **detector rather than a trace**:
`[wmp/size] MISMATCH <view> canvas=… floor=… verdict=below-floor|above-ceiling` whenever the limits
the app is about to give a window would force it away from its own scene. `WMP_RENDER_LIMITS`
enumerates the scenes where that is structurally possible; this fires when it actually happens, which
is the half no corpus sweep can own.

`WMP_ANIM_TRACE=1` is read by **the app** (`WMPMainWindowController.startAnimation`) and prints what
the repaint loop *achieved* over the last second, once a second per animating window:

```
[wmp/anim] <viewID> want=<n>fps got=<n>fps frames=<n> restarts=<n> sleep=<ms> render=<ms> present=<ms>
```

**`got` against `want` is the whole instrument, and `restarts` is what usually explains the gap.**
A frame rate is not a thing `ANIMATION` or a render dump can show: a dump is a still, and the
cadence line reports what the scene *asked for*, so an engine delivering 60% of it looks identical
to one delivering all of it. This found W142 on the first run — `want=25.0fps got=20.0fps frames=21
restarts=10 sleep=42.3ms render=4.5ms` — and the line carries its own diagnosis: ten restarts a
second is a rebuild cancelling the loop mid-sleep, `sleep` above the requested period is
`Task.sleep` overshoot, and `render` is what a serial render adds to every frame interval.

```bash
WMP_ANIM_TRACE=1 skills/app-control/scripts/launch.sh <skin>        # log: /tmp/np.log
```

**Once a second, never once a frame** — and `restarts` is *why* it can be. The first version reset
its window inside `startAnimation`, which is called by every rebuild, so on `AlienMorph` no window
ever reached a second and **27 seconds of capture produced zero `got=` lines** while printing 267
useless start lines. That is the `INPUT` trace's removal repeating itself inside a new instrument:
a per-frame line in a subsystem that repaints 25x/s is not a trace. Counters live on the
presentation and survive a restart; the restart is counted rather than narrated.

`WMP_SEEK_TRACE=1` is read by **the app** (`WMPMainView`, `WMPMainWindowController`) and prints the
value a dragged slider carries from the pointer to the host command — three lines per *gesture*,
which is what makes it usable where the removed `INPUT` trace was not:

```
[wmp/seek] performSlider seekMain mapped=Optional(0.451) min=0.0 max=1155.23 value=520.99
[wmp/seek] release seekMain#48 value=Optional(520.99) pendingSeek=Optional(...number(0.451))
[wmp/seek] hostCommand seekSeconds=18.95 duration=1155.23      ← the defect, in one line
```

`pendingSeek` on the release line is the seek the whole gesture is asking for, and since W156 it is
the **only** one: a drag prints its `performSlider` lines and then exactly one commit, either the
skin's `hostCommand seekSeconds` or the engine's own. **Count the commits, not the moves** — a
capture with a commit per `performSlider` line is the W156 regression, and it is what a 200 px drag
looked like before: 21 of them in half a second.

**Read the last line against the second.** They disagreed by the whole track on W151, because an
implicit binding settled over the user's value between the release and the handler that read it.
Every link in that chain is plausible in isolation, so this is the instrument for "the control moves
and nothing happens".

**Three traps, each of which looks exactly like "the fix did not work":**

- **A redirected `print` is block-buffered.** The first capture of this trace produced an empty log
  while the app was working perfectly. Live traces write to **stderr** — `WMP_PLACE_TRACE` and
  `WMP_ANIM_TRACE` are read on a terminal, which is why they get away with `print`.
- **The first click on an inactive window is consumed activating it**, so the first whole drag
  raises nothing. `AXRaise` the window, drive one throwaway gesture, then the real one. **And when
  the reporter is at the machine, a posted `CGEvent` reaches nothing at all while their app is
  frontmost** — it fails silently and reads exactly like a dead control, which cost several rounds
  on 2026-09-16. `set frontmost to true` on the debug build's pid immediately before each gesture,
  and re-read the window origin every time: a session shared with a live reporter moves the window
  under you, and a click computed from a stale origin lands on the desktop.
- **A short track cannot show a seek.** Pair it with `NULLPLAYER_PLAY` and something long.
- **Launch a skin with `skills/app-control/scripts/launch.sh <name>`, never by hand.** It prints a
  verified `LAUNCH PASS`. Hand-rolled launches came up on the wrong skin repeatedly: `NULLPLAYER_SKIN`
  is the classic loader and loads nothing for a `.wmz`, and session restoration rewrites
  `wmpSkinName` before the window opens (2026-09-12, 2026-09-23, 2026-09-25).

```bash
WMP_SEEK_TRACE=1 skills/app-control/scripts/launch.sh "Plus! Pulsar"     # log: /tmp/np.log
```

`WMP_WIDGET_TRACE=1` is read by **the app** (`WMPMainView`, `WMPWidgetViews`, `#if DEBUG`, stderr)
and prints the lifetime of every AppKit-hosted widget against the presents that carry it: one
`present src=<initial|load|interaction|transaction|timer|animation> canvas=<W>x<H> bounds=<W>x<H>
widgets=[<kind>:<stableID>,…]` line per present, a `create`/`drop` line per hosted view, and a `playlist draw rows=…` line per
redraw of a playlist surface.

**It exists because a pane that opens and then closes itself is invisible to every other
instrument.** `WMP_RENDER_CLICK` rebuilds one scene from one event and says the switch was
requested; nothing headless can see a *second* present, from a different code path, landing 11 ms
later with the state the first one replaced. `claw`'s playlist was reported as "it displays, then
goes black, then displays" and the whole defect is three lines:

```
946.471 present src=transaction  widgets=[playlist:6,text:25]   ← the click: the list opens
946.483 present src=interaction  widgets=[effects:4,text:25]    ← stale overrides: list dropped
946.785 present src=transaction  widgets=[playlist:6,text:25]   ← the list comes back
```

**`canvas=` differing from `bounds=` is the same class on the size axis** — a picture built for
one window size drawn into another, which AppKit stretches. `gadget`'s drawer closing (2026-09-26):
the transaction presented `canvas=336x246`, then the press repaint of the × that was already in
flight presented `canvas=336x333 bounds=336x246` and handed that scene to the animation loop. Playing,
the next metadata transaction corrected it ~75 ms later — reported as the skin "jumping"; stopped,
nothing followed and the player stayed squashed. `renderInteraction` now reads the canvas per attempt
and re-checks it after rendering, as it already did the overrides. Count mismatched lines across a
few open/close cycles; zero is the pass.

**`src=` is the field to read, and a `drop` followed by a `create` of a different kind is the
signature.** The black frame is not a paint bug: dropping a hosted view and building a new
`WMPEffectsSurfaceView` in its place shows an empty GL surface until its first frame. Read the
sources against each other — an `interaction` or `animation` present that contradicts the last
`transaction` is a repaint built on overrides a script transaction has already replaced
(W223: `renderInteraction` re-checks them, closed 2026-09-17).
**The presents are also a rate measurement**, and `structure=` is what makes them cheap (W224):
`claw` with the list open and no visualizer re-presents 11.8x/s off its scrolling `<TEXT>`, and
before the gate every one of those frames rebuilt the hit tester, re-synced the widgets, reset the
tooltips and cursor rects, rebuilt the accessibility tree and **redrew the whole playlist** — 106
list redraws in 9 s with the list unchanged. A present whose `hits` and `widgets` both equal the
last one's is a new *picture* and nothing else, so all of that is skipped and only the renderer's
frame remains; `WMPPlaylistSurfaceView.update` likewise marks itself dirty only when the rows, the
play marker, the highlight or the scroll position moved. **Read the two together**: with the list
open, `structure=same` on every present and **zero** `playlist draw` lines is the correct capture,
and one `playlist draw` with a changed `selected=` on a track change is the control that proves the
guard is not simply stuck (measured 2026-09-17 on the 3-track cue row).

`NULLPLAYER_PLAY=<audio file>` is read by **the app** (`AppDelegate`, `#if DEBUG`) and enqueues and
plays that file at launch through the same `application(_:openFiles:)` a Finder open takes. **Live QA
needs playback**, and every readout a skin binds to the host — the clock, the seek thumb, the
duration, the title — reads its resting value with an empty playlist; without this, getting a track
into a launched debug build costs a Local Library window and a CGEvent double-click per launch, and
WMP mode's own route to a track is a file dialog. It is the live counterpart of `WMP_RENDER_HOST`:

```bash
skills/app-control/scripts/launch.sh <skin>        # log: /tmp/np.log
```

**`WMP_TRACE_INPUT` and the `INPUT` trace were removed on 2026-09-11.** The instrument had become
unusable as a *live* one and that is the lesson worth keeping: the lines were emitted per present
and per pointer crossing, and a skin repaints at its own cadence — an animated view presents 20x/s,
each present re-running `synchronizeWidgetViews` and the position-change transaction — so three
identical lines a frame buried everything that carried news, and a hover edge with no authored
handler wrote "nothing happened" for every button the pointer passed over on the way to the one it
wanted. Reported live as unreadable log noise, twice, and the second time the answer was to take it
out rather than to filter it.

It *did* find real defects — `hosted=0` through a whole track settled Corona's "no visualization",
and no `hover` lines at all while `dispatch click` worked settled the window-never-key defect on
2026-09-08. **Both were answered by a state that never changed, not by a stream.** If a question
like that comes back, build the instrument that way: a counter, a one-shot, or a line that prints
only on a *change*. Never one per frame, and never one per pointer move. What follows is kept
because the distinctions it records are about the app, not about the trace.

**`action` and `command` are two different inputs and only one of them was ever traced.** `command`
is a host command a *script transaction* posted, so a skin that commits through JScript is visible —
Cablemusic's seek slider posts `seekSeconds` from an `onDragEnd`. A plain transport button goes
`WMPMainView.onAction` → `host.perform` and posted nothing, so it left no line at all. Reading an
absent `command play` as "play was never pressed" is therefore wrong for every skin that binds its
buttons directly, which is most of them. `action` closes that gap; **check both before concluding an
input never arrived.**

`script-diag` is the headless `SCRIPT-DIAG` line, in the app. Without it a handler that throws in
the running app is indistinguishable from one that ran and did nothing — which is the first fork to
close whenever a live defect looks like "the script did not fire". It is also how W86 was separated
from W46: `9SeriesDefault`'s compact-mode handler raises **no** diagnostic, so the handler is fine
and the loss is downstream of it.

`view-timer` is the line that found the dead `onTimer` class: `1000ms` from `apply`, then `0ms` one
line later because `scheduleTimers` cancelled it.

**`animation`'s `clock=` is the line that found the restarting-animation class (2026-09-08), and it
is only readable because it prints the clock rather than the frame.** Reported live as "the
animations keep opening and closing constantly… when you try to interact they are just opening and
closing all the time". `startAnimation` rewound `animationEpoch` on every call, and it is called by
every scene rebuild — a hover repaint, a script transaction, an `onTimer` tick. The trace showed
`epoch-was=0.008s-old` on a view whose script had set `timerInterval="100"`: a 2.16s one-shot intro
restarted ten times a second and never reached its second frame. The second half was invisible until
the epoch was fixed — every rebuild also rendered at the default `clock: 0`, so a transaction painted
frame zero even with the epoch preserved. The clock now belongs to the **view**
(`animationEpochViewID`), and every render of a view that is already animating passes
`animationClock(for:)`. Confirmed live: the clock advances 176.4 → 179.5s across a hover sweep and
two clicks, and four window captures during continuous hover activity are byte-identical.

It is the instrument that found every one of the 2026-09-08 live defects, and each was invisible to
every headless probe here: the window was never key (no `hover` lines at all while `dispatch click`
worked), a script present erased the hover artwork, `<TEXT>` rows were not hit targets, `Halo 2`
presented a thumbnail view its own `onLoad` had blanked, and no view timer in the corpus had ever
fired (`view-timer 1000ms` immediately followed by `view-timer 0ms`). Read once at process start like every other
probe — exporting it at a running app reports nothing.

`WMP_TEST_WMZ` and `WMP_RENDER_DUMP_DIR` are accepted aliases for `WMP_SKIN` and `WMP_RENDER_DUMP`
so the Phase 0–8 handoff docs' invocations still run. Use the names in the table.

One archive:

```bash
WMP_SKIN=~/Library/Application\ Support/NullPlayer/WMPSkins/corona.wmz \
WMP_RENDER_EXPR=1 WMP_CALL_TRACE=1 WMP_RENDER_SCRIPTS=1 \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus > /tmp/wmp/corona.txt 2>&1
```

**`WMP_SKIN` takes a directory and sweeps it inside one process invocation.** The `.wal` sweep does
79 archives in ~5 minutes where a shell loop over them took 25, and the test-binary startups were
nearly all of the difference. One invocation also cannot be invalidated halfway — a sweep is a
build, and an edit landing mid-loop silently wrote *empty* captures that then diffed as "everything
changed".

A skin that fails to load prints `SKIN <file> FAILED <error>` and the sweep carries on. One broken
archive must not abandon the rest.

---
