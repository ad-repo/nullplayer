# The `.wmz` harness — canonical probe reference

**This file is the only place a `.wmz` probe flag or corpus command is documented.** Every other
file, comment and handoff points here and never restates a command. When you add a flag, add it
here in the same change.

Everything below runs headlessly through `swift test`. Nothing here is compiled into the app.

---

## Why the harness exists

Structural and load-time cleanliness measure almost nothing. The `.wal` subsystem paid for that
first: *a vertical-flip and a wrong crop origin survived 490+ green tests because nothing ever
rendered a frame.* `.wmz` reached 6,044 lines of engine with every real-skin test `XCTSkip`ped, so
`swift test` stayed green while 4 of 14 corpus archives were being rejected outright.

So: **you cannot rank work you cannot measure**, and a probe is not trusted about an absence until
it has been shown reporting a presence.

---

## The corpus

Installed skins live outside the repo, matching the `.wal` convention:

```
~/Library/Application Support/NullPlayer/WMPSkins/
```

`WMPSkinImporter.swift` installs there. Archives are never committed; only per-skin `.md` notes are.

**Enumeration rule.** `*.[wW][mM][zZ]`, `-type f`. A bare `*.wmz` drops an upper-case spelling and a
bare `*` picks up directories. Every script **prints the count it measured and never asserts a fixed
one** — the corpus moves, and a document quoting a frozen number goes wrong in a way that looks
right. Each row carries a sha256 so byte-identical archives under two filenames are visible as
duplicates instead of counted twice.

### Counting a tag across the corpus

`scripts/wmp_markup_census.sh <outdir> <tag-or-attribute ...>` is the instrument, and it is the only
one to use. It matches `<NAME[[:space:]/>]`, so `VIDEO` does not catch `<VIDEOSETTINGS>`, and it
strips each `.wms` to ASCII first for the two traps in its own header comment (grep goes silent on a
UTF-16 file; a tag is spread over many lines).

**Do not write your own scanner for this, and distrust any number that came from one.** The surface
inventory in `SKILL.md` was first measured by an ad-hoc Python scan trying `utf-8-sig`, then
`utf-16`, then `cp1252` — and **`bytes.decode('utf-16')` does not fail on Windows-1252 text**. Any
even-length cp1252 `.wms` decodes to silent garbage, so the tag is simply absent from the result:
`activate.wmz` reported zero `<EFFECTS>` elements and has one, and the corpus totals came out
**151 / 138 skins where the census says 183 / 166**. Every count was low, none was obviously wrong,
and the error was invisible until two instruments were compared. If a scan of your own is genuinely
unavoidable, decode the way `WMPTextDecoder` does — BOM first, then a **positional** BOM-less UTF-16
sniff, then Windows-1252 — and reconcile it against the census before recording a number anywhere.

**Grepping the corpus's *script text* is a different job, and the same decode trap ends it.**
Neither census reads `.wms`/`.js` as program text, so a question like "is this name ever read as a
property rather than called as a method" needs its own scan — that is the check that made W128 safe
to land. Extract with Python's `zipfile` (it refuses `Need_for_Speed_Underground.wmz` and
`SplinterCellWMPSkin.wmz`, whose local headers `WMPArchiveHeaderRepair` exists to fix, so **177 of
180**, and every count is a floor), then decode each file the way `WMPTextDecoder` does before
matching anything. The W128 scan was run twice because the first pass decoded as
`utf-8, errors="replace"`: **153 of the 392 script files are UTF-16**, they became null-interleaved
mojibake, no pattern matched in any of them, and the result — 141 uses — looked entirely plausible
beside the correct 376. The mix, for calibration: 153 UTF-16-with-BOM, 143 cp1252, 87 UTF-8, 9
UTF-8-with-BOM. **A scan of script text that did not print its own encoding breakdown has not earned
its number.**

**Views are the one thing the census does not count**, so the per-view numbers in `SKILL.md`
§ *Ask what the skin provides* (595 views across 179 archives; which surface lives in which view;
`openView` targets by name) came from splitting each `.wms` on `<VIEW` with that decoder. Re-derive
them the same way and state the denominator, exactly as every other count on this page does.

---

## The probe flags

All of them are read by `WMPRenderDumpTests/testSweepsSkinOrCorpus`
(`Tests/NullPlayerAppTests/WMPRenderDumpTests.swift`).

| Flag | Value | What it prints |
|---|---|---|
| `WMP_SKIN` | file **or directory** | the archive(s) to measure — required |
| `WMP_RENDER_DUMP` | directory | one PNG per view; per-skin subdirectory in a sweep |
| `WMP_RENDER_PROBE` | `all` or a view id | `PROBE` — every drawn node's type, id, resolved frame, clip, z, paint and authored attributes; plus a `WIDGET` line per widget — the AppKit-hosted surfaces the scene image does **not** contain. Two fields appear on a `WIDGET` line only when they are not the default, and both are about whether the surface is hosted at all and in what shape: `alpha=` is the container's inherited `alphaBlend` (`alpha=0` is a pane the skin has faded shut — `WMPMainView` hosts no view for it, and without the field such a widget read identically to a live one), and `mask=` names the container artwork a windowless `<EFFECTS>` is clipped to, with its frame and keyed colours. `WMP_RENDER_APPKIT` installs the same mask provider the controller does, so its `outside=` reading covers the masked surface rather than an unclipped rect |
| `WMP_RENDER_BITMAPS` | `1` | `BITMAPS` — resolved count and every path that failed to load, with `missing=` |
| `WMP_RENDER_OCCLUDED` | `1` | `OCCLUDED` — every control the pointer cannot reach **anywhere in its own frame**, plus a per-view tally. A target is unreachable when no sample of its rect hit-tests back to it: something in front answers everywhere, so the control draws, hovers nothing and clicks nothing. Each line names what answered instead (`by=[…]`) and which rule reached it — `covered-only` is a control the current rule recovered, `rect-only` is one it **lost**, `neither` is dead under both. **`rect-only` is the column that ranks work**: it is the flat-`zIndex`, whole-rectangle hit testing this engine did before W148, and a change that populates it is taking controls away. Sampling is a 17x17 grid over the frame plus, for a `<BUTTONELEMENT>`, the first pixel its mapping colour owns — a mapping child holds an arbitrary region and a grid alone misses a thin one. No headless probe saw this class before it existed: a starved view is `starved.tsv`'s subject, and a *fully laid out* view whose controls are buried is invisible to every count in `RENDER-DUMP`. **What this probe cannot see is a control with no hit entry at all** (W152): it enumerates targets that *have* one and asks who answers instead, so a group whose mapping regions never reached the hit map reads as a clean view here — `digitaldj/DigitalDJ` reports `unreachable-either-way=4 of 92 hits` while its entire transport strip misses every click. Pair it with `WMP_RENDER_CLICK` on a control you decoded yourself before believing a clean line |
| `WMP_RENDER_UNRESOLVED` | `1` | `UNRESOLVED` — one line per node the scene could not place: authored tag, id, and **which dimension** was missing (`width`, `height` or `width+height`). `RENDER-DUMP`'s `unresolved` count is the numerator `starved.tsv` ranks on and it names nothing, so every use of it had been followed by opening the `.wms` and guessing. It is what separated the three populations that count conflates — a `<TEXT>` sized by its own glyphs, a `<BUTTONGROUP>` sized by its mapping image, and a `<PLAYELEMENT>` that is a colour region and was never a box — and each was a rule rather than a skin |
| `WMP_RENDER_SCRIPTS` | `1` | `SCRIPTS`/`SCRIPT` — per program: bytes, declared handlers, and the runtime's availability |
| `WMP_RENDER_EXPR` | `1` | `EXPR` — every `JScript:` geometry expression, its source, both evaluators' values, its dependency order and deps |
| `WMP_CALL_TRACE` | `1` | `CALL`/`CALLS` — every host object-model access with receiver, member, value, and how it resolved: `ok`, `INERT` or `UNRECOGNISED` |
| `WMP_RENDER_CLICK` | `<view>@x,y[;x,y…]`, any entry may be a `>`-joined path | `CLICK` — the object hit, handler count, every attribute changed anywhere in the graph, the host command reached, **`viewSize=<W>x<H>` when the handler resized its own window**, and the state after. The size line is not a host command and had to be printed separately: **a `.wmz` compact mode is a script resizing its own window** (W113), carried on `WMPScriptOutput.viewSize`, so before it existed a click that shrank the player printed no command at all and read exactly like an inert one — `Cablemusic`'s Shrink, `Goo`'s and `iconic`'s small-skin toggles and `Melvin`'s all resolve through it and none of them through `command=`. **An entry written `x,y>x,y>x,y` is a drag**: press at the first point, move through the rest, release at the last, with the pointer captured on the object the press landed on. `DRAG` reports the control's direction, range and border, the value and drawn thumb frame at every step, and then the two claims the flag exists to settle — `follows-pointer=yes\|no\|flat` and `thumb-travel=<px>`. `flat` is the one to read for: a value that never moves is trivially monotonic, and a `yes/no` answer alone would call it a pass. **It rebuilds the same `viewID` and never follows a view switch**, so `command=setCurrentView` here proves the switch was requested and nothing about what the user would be looking at afterwards — see § *A live pass is a window frame* |
| `WMP_RENDER_HOVER` | `<view>@x,y[;x,y…]` | `HOVER` — walk the pointer through the points in order and raise the edges each move crosses: an `onMouseOut` on the node left, then an `onMouseOver` on the node entered, through `WMPMainWindowController.handlers(in:event:…)`, the same call the app dispatches through. A move that stays inside the same node prints `inside=… — no edge` and raises nothing, which is the claim worth falsifying: a hover fired per mouse-moved event would be a script transaction per pixel. Separate from `WMP_RENDER_CLICK`'s `>` drag form on purpose — a drag holds a capture and asks what the *value* did, a hover holds nothing and asks which handlers the crossing raised (W54) |
| `WMP_RENDER_APPKIT` | `1` | `APPKIT` — host the scene in the **real `NSView` stack** and report what the AppKit layer adds over the artwork. `outside=` is the number that ranks: an overlay drawing inside its own widget frame is the hosting working, and one drawing anywhere else is the W43 class. `blit=`/`blit-max-delta=` is a second, separate comparison of the renderer's own image against the view's blit of it. Set `WMP_RENDER_APPKIT_DUMP=<dir>` alongside it to write both bitmaps as `<view>-scene.png` and `<view>-hosted.png` when isolating one view. **A scene with an `<EFFECTS>` is two rasters** either side of `WMPScene.effectsCommandSplitIndex` (W139), and this probe presents both: the baseline pass hides only `WMPMainView.hostedWidgetViews`, never the artwork overlay, because artwork a skin draws *above* its visualizer is the skin's picture and not something AppKit added over it. `blit=` compares the view against the two layers flattened back together, and a split scene with partially transparent artwork above the effects node reads a small non-zero there — the intermediate premultiplied buffer quantizes, measured at 0.11% of pixels and max-delta 16 on `Plus! Professional/mainView`. Read the shape, as the line has always said |
| `WMP_RENDER_SETTLE` | seconds | run the **view's own timer loop** for that long before measuring — at the period the skin asks for, honouring every `setViewTimerInterval` its handlers post back, rebuilding the scene between ticks |
| `WMP_RENDER_CLOCK` | `<s>[;<s>…]` | seconds into an animation to draw, one PNG per value (suffixed `@t<s>`; a zero clock keeps the original filename). **A render dump is a still, so this flag is the only way an animation is falsifiable** — frame zero is indistinguishable from an engine that never animates. Two pinned values, diffed, are the proof. `ANIMATION <view>: shortestDelay=… bounds=…` reports what the scene actually animates |
| `WMP_RENDER_HOST` | `playing`, or a `key=value` list | seed a **playing** host for the whole run instead of the default stopped one, and print `HOST` per skin saying what was seeded. Everything else in the harness measures a stopped player with an empty playlist, which is the one state a `.wmz`'s transport readouts never show a user: the elapsed readout of **108 archives** is `<TEXT value="wmpprop:player.controls.currentPositionString">` and **89** hang a seek slider off `player.controls.currentPosition` with `max="wmpprop:player.currentMedia.duration"`, and against the default snapshot every one of those resolves to `0:00` on a zero-length track — indistinguishable from an engine that never answers the path at all. Defaults are a track 1:03 into 3:33, one of three in the playlist, half volume, centred, with a title/artist/album; `WMP_RENDER_HOST='t=42,dur=137,state=paused,vol=0.8,title=X'` overrides any field (`state`, `t`/`time`/`position`, `dur`, `vol`, `bal`, `mute`, `shuffle`, `repeat`, `buffering`, `bitrate`, `title`, `artist`, `album`, `tracks`, `index`, `eq`). **Read the `HOST` line before reading anything else in such a capture** — a seeded run misread as a default-state one is wrong about every readout in it |
| `WMP_RENDER_SIZE` | `<W>x<H>` | `RESIZE` — lay the view out at its **own** size first, run `onLoad` there, then resize to this and re-drive `onResize`, which is the order a user produces. An expression-driven layout is a *different* layout, not the same one scaled. The transaction runs whether or not the view declares an `onResize`, because an expression re-reads `view.width` either way; `handlers=` is how many the changed-object set actually raised, and `handlers=0` with a skin you know authors one means nothing moved |

### The probes that are not in the test binary

`WMP_PLACE_TRACE=1` is read by **the app** (`WMPViewWindowMaterializer.place`) and prints one
`[wmp/place] <viewID> <frame>` line per auxiliary window, at the moment it is placed and never
again — placement happens once per window, so a window the user has moved is never yanked back.
It is the `.wmz` counterpart of `WINAMP_MODERN_PLACE_TRACE`, and it exists for one question a
screenshot answers badly: **a skin that opens five panels at load has five windows to fit**.
`Halo 2`'s `onLoadSkin` opens four from its own preferences plus `mainView`, and the failure mode
is not a wrong-looking window but an invisible one — the tiler walking off the bottom of its column.
A line whose frame is outside every screen is the `rescuedOrigin` fallback failing; a line that
repeats for the same view is placement running twice, which is the bug this flag exists to catch.

```bash
WMP_PLACE_TRACE=1 NULLPLAYER_PLAY=/abs/path/track.mp3 \
  nohup ./.build/arm64-apple-macosx/debug/NullPlayer -uiMode wmp > /tmp/app.log 2>&1 &
```

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
WMP_ANIM_TRACE=1 NULLPLAYER_PLAY=/abs/path/track.mp3 \
  nohup ./.build/arm64-apple-macosx/debug/NullPlayer -uiMode wmp > /tmp/app.log 2>&1 &
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
[wmp/seek] release seekMain#48 value=Optional(520.99)
[wmp/seek] hostCommand seekSeconds=18.95 duration=1155.23      ← the defect, in one line
```

**Read the last line against the second.** They disagreed by the whole track on W151, because an
implicit binding settled over the user's value between the release and the handler that read it.
Every link in that chain is plausible in isolation, so this is the instrument for "the control moves
and nothing happens".

**Three traps, each of which looks exactly like "the fix did not work":**

- **A redirected `print` is block-buffered.** The first capture of this trace produced an empty log
  while the app was working perfectly. Live traces write to **stderr** — `WMP_PLACE_TRACE` and
  `WMP_ANIM_TRACE` are read on a terminal, which is why they get away with `print`.
- **The first click on an inactive window is consumed activating it**, so the first whole drag
  raises nothing. `AXRaise` the window, drive one throwaway gesture, then the real one.
- **A short track cannot show a seek.** Pair it with `NULLPLAYER_PLAY` and something long.
- **`NULLPLAYER_SKIN` does not select a `.wmz`.** `AppDelegate` hands it to `WindowManager.loadSkin`, which is the **classic** `.wsz` loader, so a `.wmz` path there loads nothing and the launch comes up on the unskinned WMP view (440x170) — which reads as the skin failing to load. A `.wmz` is selected the way step 1 of the live loop says, `defaults write NullPlayer wmpSkinName`, and **session restoration overwrites that key from the saved state before the window opens**, so a launch that keeps coming up on the wrong skin wants `defaults write NullPlayer rememberStateEnabled -bool false` for the duration. Both cost a launch each on 2026-09-12. Put the user's values back afterwards.

```bash
defaults write NullPlayer wmpSkinName -string "Plus! Pulsar"
WMP_SEEK_TRACE=1 NULLPLAYER_PLAY=/abs/path/long.m4a \
  nohup ./.build/arm64-apple-macosx/debug/NullPlayer -uiMode wmp > /tmp/app.log 2>&1 &
```

`NULLPLAYER_PLAY=<audio file>` is read by **the app** (`AppDelegate`, `#if DEBUG`) and enqueues and
plays that file at launch through the same `application(_:openFiles:)` a Finder open takes. **Live QA
needs playback**, and every readout a skin binds to the host — the clock, the seek thumb, the
duration, the title — reads its resting value with an empty playlist; without this, getting a track
into a launched debug build costs a Local Library window and a CGEvent double-click per launch, and
WMP mode's own route to a track is a file dialog. It is the live counterpart of `WMP_RENDER_HOST`:

```bash
NULLPLAYER_PLAY=/abs/path/track.mp3 \
  nohup ./.build/arm64-apple-macosx/debug/NullPlayer -uiMode wmp > /tmp/app.log 2>&1 &
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

## Driving the app: the loop that found the compact-mode class

Three of the four defects in the compact-mode report were invisible to every flag above, because a
**view switch is an app path** — the sweep renders each view independently and never performs one.
The loop below is what reproduced them, and it is cheap enough to be the default response to a
screen-only report rather than a last resort. Nothing in it is committed; rebuild it as needed.

1. **Select the skin and launch the debug build with the trace on.** A bare binary launch does not
   use the bundle's defaults domain — it uses `NullPlayer`, not `com.nullplayer.NullPlayer`, and
   writing the wrong one silently loads a different skin:

   ```bash
   defaults write NullPlayer wmpSkinName -string "9SeriesDefault"
   defaults delete NullPlayer wmpSkinViewID
   nohup ./.build/arm64-apple-macosx/debug/NullPlayer -uiMode wmp > /tmp/app.log 2>&1 &
   ```

   `-uiMode wmp` is `PlayerUIMode.argumentOverride`, and it works in release builds too. **Restore
   whatever you changed afterwards** — it is the user's skin selection, not yours.

2. **Ask the probe where the control is, then click that frame.** `WMP_RENDER_PROBE` prints every
   drawn node's resolved frame in scene coordinates, which are the window's own top-left
   coordinates — so a `frame=540,304 20x19` is clicked at `(550, 313)` with a `CGEvent` posted at
   the window's origin plus that offset, found through `CGWindowListCopyWindowInfo` filtered on
   owner `NullPlayer`. Guessing from a screenshot wastes a launch per miss; a `BUTTONELEMENT` inside
   a `BUTTONGROUP` has no frame of its own at all and is resolved instead by decoding its
   `mappingColor` out of the group's mapping bitmap and adding the group's origin.

3. **Read `/tmp/app.log`, then capture the window.** `screencapture -o -x -l <windowid>` takes the
   window alone, transparency included. It is far too slow to film a 250 ms animation — capture the
   *settled* state and use `WMP_RENDER_SETTLE` for the frames in between.

**What the trace settles that a screenshot cannot.** The compact-mode report read as one defect and
was three, and the `INPUT` lines separated them in one launch each: `dispatch load` missing said the
switch never loaded the view (W46); `setViewTimerInterval value=50` immediately followed by
`value=4000` said a chained timer had registered and then been dropped (W86); and `script-diag`
staying silent through all of it said no handler ever threw, which is what moved the search out of
the script and into the engine's own semantics.

### Auditing one authored control across the whole corpus

*"Every skin has this button and it does nothing"* is a shape of report the census cannot answer,
and W100 is the worked example: it stood **unmeasured for three days** at a recorded reach of 2
skins and the true number was **162 of 180**. The route that produced it, in order, because each
step exists to survive a trap the previous one hides:

1. **Scan the script text, not the census.** `wmp_skin_census.sh` drives `onLoad`; a control's
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
owner `NullPlayer`, read before the click and after it. It is objective, it is two lines of Swift,
and it scales to a skin per launch — eleven skins were audited this way in one pass. A screenshot
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

### A named skin outranks a corpus sweep

The same report was unfalsifiable until the reporter named one: *"catwoman skin is not fixed"*. A
seeded corpus sweep had already said **88 of the 89 archives that author the elapsed binding draw the
right string**, which is a true measurement and was the wrong question — Catwoman authors no
`currentPositionString` anywhere. Its clock is four digit filmstrips positioned by
`value_onchange="drawSeekDigits(value)"` off a `<CUSTOMSLIDER>` whose value nothing bound, so the
whole readout lived in two mechanisms the sweep was not looking at. **Ask for a skin name before
sweeping**, then read that skin's `.wms` — the markup says what the readout is made of, and the two
defects behind it (W120, W51) were both visible in a single 200-character tag.

### Read the probe for what is *absent*

**A widget is not in the PNG, so a sweep that compares only images cannot see one appear or go.**
W55 changed 57 views' widget counts corpus-wide — 1,863 to 1,711 — while moving **22 images**, and
the two facts are not in conflict: playlists, sliders, popups, edit boxes and effects surfaces are
AppKit overlays the scene image never contains. Read `widgets` out of `RENDER-DUMP` and the
`CLICK … after:` tally alongside the image diff, or a drawer that opens onto nothing reads as a
clean sweep. That is the same blind spot W71 measured for overlay *painting*, in a different
direction: W71 asked whether an overlay painted where the scene did not, this asks whether it exists
at all. `CLICK … after:` names the kinds for that reason — Corona's drawer turns on a `PLAYLIST` and
a `DROPDOWNPLAYLIST` in one handler, and a bare count cannot say which one the engine hosted.

**A drag that stops at the last move measures a different engine than the app.** `WMPMainView.mouseUp`
raises `dragend` for a captured slider, so the harness's drag does too, and the host command on that
line is the seek the drag asked for (W55). With no media loaded the snapshot's duration is 0, so the
value is 0 and `follows-pointer` reads `flat`: that is the empty snapshot, not the dispatch. Read
`handlers=` and `commands=[…]` to tell a handler that ran from one that was never found.

`WMP_RENDER_PROBE` is normally read as "is this node's frame right". W95 was found by reading it the
other way: `WoW`'s `plView` printed a `WIDGET` line for its edit box and its list box and **no line
at all** for `playlist1` — no `PROBE` row either, so the node was not merely mispositioned, it was
never in the scene. That is a different class from every defect the probe was built for, and it is
invisible in a screen capture, where a missing control and a control drawn empty look the same: the
authored `backgroundImage` still painted a white slab where the rows should have been.

The check is cheap and worth making the first move on any "this control does nothing" report: grep
the probe for the element's authored id. Nothing back means the walk dropped it, and the reasons it
can are few — a falsy `visible` (an override, a `wmpprop:` binding, or the literal), an empty frame,
or an ancestor that went first. `RENDER-DUMP`'s `N nodes, N commands, N hits, N widgets` counts are
the same signal one level up; a `widgets` count lower than the controls you can see in the markup is
the same finding without needing the id.

**Shorten a long intro with the skin's own preference rather than waiting it out.** `Alienware
Invader` plays 568 frames before it reveals anything, which is minutes per launch in a debug build.
Its own script skips to frame 362 when `theme.loadPreference('soundFX')` is `"false"`, and skin
preferences are plain `UserDefaults` under `wmp.preferences.<sha256 of the .wmz>` in the `NullPlayer`
domain, so `defaults write NullPlayer "wmp.preferences.$SHA" -dict-add soundFX false` cuts the loop
to about a minute. Read the skin's script for the shortcut it already has; do not add an engine flag
for one. **Restore what you changed** — `defaults delete NullPlayer "wmp.preferences.$SHA"` resets
that skin's preferences — and remember the preference dictionary is *evidence* as well as state:
`Alienware Invader`'s held `remoteCallPl/Eq/Vis/Meta = true`, four flags written by buttons and read
by nothing, which is W89 recorded in the user's own defaults.

### Reducing a skin's script to a standalone repro

W86 was a JScript-versus-JavaScriptCore difference inside 200 lines of the skin's own code, and
reading it was not going to settle anything. Extracting it was:

```bash
unzip -p <skin>.wmz corona_tiny.js | iconv -f UTF-16LE -t UTF-8 > tiny.js
```

then evaluating `tiny.js` in a bare `JSContext` under a ~20-line stub of the host objects it
touches (`view`, `theme`, the two subviews) plus a **controllable clock** — override
`Date.prototype.getTime` so the driver, not the wall, decides when a timer event fires — and a loop
that calls the skin's own `TimerDispatch()` at the interval it asks for. That reproduced the defect
exactly (`svVideo.height` stuck at 241, `currentViewID` never set), and changing one `for-in` to an
index loop produced the correct result. **Both halves matter**: a repro that only fails proves you
have *a* bug, not *the* bug. Afterwards the same rig runs the engine's real rewrite output, which is
how the fix was confirmed before the app was ever rebuilt.

### An `INERT` row may be a misclassified `UNRECOGNISED` one

`INERT` means "recognised, answered, and nothing behind it" — Tier 2b, explicitly the tier you do
*not* take runtime work from. But the **open property surface** answers any unknown element property
with `""`/`0` and counts it `inert()`, and a *method* name that is not in
`WMPObjectModel.elementMethodVocabulary` lands there too. So an unimplemented method can sit in the
census as an inert property, and the row that should be ranking real demand ranks nothing.

W128 is the measured case: `plListBox1.deleteAll()` read as `CALL plView pllistbox1.deleteall read
value= INERT` in seven skins, and the audit that found it predicted it would appear *nowhere*. Both
readings were wrong in the same direction — the demand was visible but filed under the tier that
means "ignore me". **When you check whether the engine measures demand for a name, read which word
the trace gives it, not just whether the name appears.** An `INERT` on something that is spelled like
a verb is the shape to distrust.

### The dump is flat, so it cannot answer a layering question

`WMPRenderer.dump` passes `splitAtEffects: false` **on purpose**: a PNG is a picture of the skin's
artwork, the effects surface is an AppKit view that never appears in one, and splitting the list
there would drop everything above the visualizer out of the file. Every dump therefore shows the
whole scene flattened in one pass — including artwork that the running app does *not* draw, because
in the app it lands on the overlay raster hosted above the surface.

W144 cost three rounds of "still broken" to that. The reported defect was a skin drawer's artwork
showing through a windowed visualization; the fix was correct on the second attempt and the dump kept
showing the drawer, because the dump always shows the drawer. **`WMP_RENDER_APPKIT` with
`WMP_RENDER_APPKIT_DUMP=<dir>` is the instrument for anything about layering**: it hosts the real
`NSView` stack and writes `<view>-hosted.png`, which is what the user sees. Combine it with
`WMP_RENDER_CLICK` to capture a state the skin only reaches through a handler.

The general form, which is not only about `<EFFECTS>`: **before believing a render dump has
falsified a fix, ask whether the thing you changed is something a dump can represent at all.**

### A single-transaction sweep cannot measure a per-transaction rule

`wmp_render_sweep.sh` renders each view once, after `onLoad`. A change to what happens on the
*second* and later transactions is therefore invisible to it, and the sweep reports it as a clean
no-op rather than as unmeasured.

W144's expression-stickiness change — an authored `JScript:` geometry expression no longer
re-applies unless its value changed — came out **485 identical, 50 differing, 0 lost, 0 gained**
against the baseline both with and without it, byte for byte, because every one of those 50 came
from the alignment change sitting beside it. The rule it fixed only bites on a view with an
`onTimer`, which the sweep never ticks.

`WMP_RENDER_SETTLE=<seconds>` is the instrument: it runs the view's own timer loop at the period the
skin asks for, and it reproduced the defect on the first run (`visDrawer1` back at its authored
`y=215` after two seconds, having been slid to `265` by `onLoad`). This is the same shape as the
"live QA needs playback" rule — **a byte-identical sweep across a change to timers, hover, drag or
playback is unmeasured, not unchanged.**

### The sweep is the arbiter, including against your own fix

W87 had an obvious general fix — re-resolve the view's `JScript:` geometry expressions after the
handlers run — which closed the reported defect completely and **moved 175 of 545 corpus images**,
shattering two skins that had nothing to do with it. Those attributes are an initial layout, not a
live binding, and several read the property they write. The narrow fix that shipped raises only the
`_onchange` handlers the skin itself declared, and sweeps to 544 of 545 identical.

**A fix that resolves the report and moves things outside it is telling you it is the wrong fix.**
Sweep before believing a fix, not only before believing a refactor — and read the `RENDER-DUMP`
counts in the invariants diff, not just the image count: `33 commands / 15 hits → 28 / 8` named the
regressed view before any PNG was opened.

**And the mirror case, so the rule is not read as "a big diff is a bad fix": W143 moved 139 of 535
and was right.** The two are distinguishable without taste, by two things measured in the same
capture. First, **the invariants**: W87's collateral announced itself as changed `RENDER-DUMP`
counts, and W143's 514 changed invariant lines are *entirely* `loadms` timings and `SCRIPT inline:`
tie-ordering — no view gained or lost a node, command, hit target or canvas, so nothing stopped
resolving and nothing started. A wide image diff with a still invariants diff is a layout rule
reaching everything that authored it. Second, **sample across skins unrelated to the report and to
each other, and open them side by side** — ten of the 139, and each one had to be a repair on its own
evidence (a badge centred under its own pointer arrow, a clipped readout made whole, a frame that
had been half its window's width). "Every one I opened looks better" is the claim to make, and it is
only worth anything if the ten were chosen before they were looked at. Neither check is the PNG
count, and the count is what both fixes have in common.

### A baseline worktree needs the vendored frameworks linked in

`capture` refuses a dirty tree and tells you to use a worktree, which is right — but `Frameworks/`
is only partly tracked, so a fresh worktree has no `VLCKit.framework` and the build fails with
`no such module 'VLCKit'`, or links and then dies in `dlopen`. Symlink the real ones in before
capturing, into both the source directory and the build's own framework directory:

```bash
git worktree add /tmp/base HEAD
for f in VLCKit.framework libprojectM-4.dylib libprojectM-4.4.dylib libaubio.dylib; do
  ln -sfn "$PWD/Frameworks/$f" "/tmp/base/Frameworks/$f"
done
mkdir -p /tmp/base/.build/arm64-apple-macosx/{Frameworks,debug}
# …and link VLCKit.framework into both of those too; the test bundle's rpath looks beside itself.
```

The `--allow-dirty` this then needs is safe **for the baseline worktree only** — the untracked thing
making it dirty is a symlink to a framework. Never pass it to hide real edits.

## The line grammar

Machine-readable, one fact per line, inside a `SKIN <file.wmz>` block. `scripts/wmp_skin_census.sh`
and `scripts/wmp_render_sweep.sh` parse these; do not reword one without updating both.

```
HARNESS <n> archive(s) from <path>
SKIN <file.wmz>
SKIN <file.wmz> FAILED <error>
LOAD definition=<p> encoding=<e> entries=<n> bytes=<n> views=<n> nodes=<n> scripts=<n> resources=<n> loadms=<x>
FINDING [<severity>] <WMP00xx> ×<n> <message>
COMPAT unknown-tags=<n> unknown-members=<n> unknown-events=<n> resources-missing=<n> resources-unsupported=<n>
UNKNOWN tag <name> ×<n>
UNKNOWN event <name> ×<n>
UNKNOWN member <path> ×<n>
SCRIPTS programs=<n> bytes=<n> runtime=<available|unavailable (why)>
SCRIPT <path>: bytes=<n> handlers=[…]
SCRIPT inline: <event>×<n> …
SCRIPT-DIAG <view> [<code>] <message>
RESIZE <view>: <W>x<H> -> <W>x<H>, handlers=<n>
RENDER-DUMP <view>: <W>x<H>, <n> nodes, <c> commands, <h> hits, <w> widgets, <u> unresolved
RENDER-DUMP <view> FAILED <error>
ANIMATION <view>: shortestDelay=<s> bounds=<rect>
WIDGET <view>/<stableID> <kind> id=<id> frame=<f> clip=<c> visible=<f|none>
PROBE <view>/<stableID> <kind> id=<id> frame=<f> clip=<c> z=<n> paint=<…> attrs=[…]
BITMAPS <view>: resolved=<n> missing=<space-separated paths>
EXPR <view>/<id>.<prop> #<order>: <source> -> <static> live=<live> deps=[…]
CALL <view> <path> <read|write|invoke> value=<v> <ok|INERT|UNRECOGNISED>
CALLS <view> <path> ×<n> <ok|INERT|UNRECOGNISED>
CLICK <view>@x,y hit=<id>#<stableID> kind=<k> action=<a> sticky=<b> handlers=<n>
CLICK <view>@x,y changed=[…] | command=<…> | unrecognised=[…] | MISS
CLICK <view>@x,y after: <n> commands, <n> widgets[<kind>×<n> …], <n> unresolved
DRAG <view>@x,y>x,y hit=<id>#<sid> kind=<k> slider=<b> direction=<d> min=<m> max=<M> border=<b> steps=<n>
DRAG <view>@x,y>x,y step=<i> at=<x>,<y> value=<v> drawn=<v> thumb=<rect>
DRAG <view>@x,y>x,y dragend handlers=<n> commands=[<action>=<value>,…]
DRAG <view>@x,y>x,y value <v> -> <v> follows-pointer=<yes|no|flat> thumb-travel=<px>
DRAG <view>@x,y>x,y MISS | not-a-slider — no value tracking to measure
HOVER <view>@x,y <onMouseOut|onMouseOver> <id>#<stableID> kind=<k> handlers=<n>
HOVER <view>@x,y <event> changed=[…] | [<code>] <message> | unrecognised=[…] | after: <…>
HOVER <view>@x,y inside=<id>#<stableID> — no edge
HOVER <view>@x,y MISS
APPKIT <view>: <W>x<H>@<n>x differing=<n>/<n> (<pct>) hosted=<n>/<n> outside=<n> (<pct>) max-delta=<n> blit=<n> (<pct>) blit-max-delta=<n> [worst=<rect>]
APPKIT <view>/<stableID> <kind> id=<id> frame=<rect> differing=<n> (<pct>)
APPKIT <view>: SKIPPED <why>
PNG <view>: <filename>
```

`APPKIT` is the only line that has run an `NSView.draw`. Everything else in this file measures the
scene; this measures the window. Two things make its numbers trustworthy and both were wrong first:

* **The baseline is a second AppKit pass with the overlays hidden, not the renderer's image.**
  `cacheDisplay` composites through the display's colour space and the renderer's context does not,
  so comparing the two directly is a colour conversion as much as a measurement — it read 6.8% of
  Corona (the control skin) as differing, and 61% of a four-colour fixture, at deltas up to 64. Two
  passes through the *same* path cancel that exactly, and the corpus-wide noise floor is then **zero**,
  not "small".
* **Only a widget that actually hosts an `NSView` explains a difference.** `WMPMainView` builds
  overlays for `playlist`, `dropdownPlaylist`, `popup`, `editBox`, `listBox` and `effects` and no
  others — a slider and a text are drawn by the renderer into the image the view blits — so a
  difference inside a *slider's* frame is a defect, not hosting, and attributing it to the widget it
  happens to sit inside would file it as expected. Keep that list in step with
  `WMPMainView.synchronizeWidgetViews`.

The rep comes back at the display's backing scale, not the view's point size, and so does the image
the app presents (`WMPMainWindowController.renderBackingScale`). Indexing a 2x rep in points reads
the top-left quarter and calls it the window; presenting a 1x image into a 2x rep diffs AppKit's
upscaler against the renderer. Both were made on the way to this line and both look exactly like a
defect in the app.

**`dispatch` prints only when the transaction actually runs.** A gated hover edge with no authored
handler returns without doing anything, and the pointer crosses a whole row of buttons on the way to
the one it wants — tracing before the gate wrote a line per crossing that said "nothing happened".
The `hover <id> -> <id>` crossing line went with it for the same reason. What this costs is the
signature that found the window-never-key defect on 2026-09-08 (*no `hover` lines at all while
`dispatch click` worked*); if that question comes back, the way to ask it is a counter or a
one-shot, not a line per pointer move.

**Three more lines were removed on 2026-09-11, and the reason is worth keeping**:
`widgets hosted=…`, `present <event> …` and `animation <view> …` were printed on every present, and
a skin repaints at its own cadence — an animated view presents 20×/s, and each present re-runs
`synchronizeWidgetViews` and the position-change transaction. Interleaved, they wrote three
identical lines forty times a second and buried every line that carried news, which is the opposite
of what a trace is for. `widgets hosted=` had earned its place once — `hosted=0` through a whole
track settled Corona's "no visualization" by saying the pane was never built — so if that question
comes up again, ask it with a line that prints when the hosted set *changes*, never one per frame.
`WIDGET` still answers the same question from the harness side.

`menu at=` prints the point a right-click landed on and every `<EFFECTS>` frame it was tested
against, which is what decides whether the visualization's own context menu opens.

`WIDGET` is the only line about the AppKit overlays — playlist, equaliser, popup, effects, video —
and they are **not in the dumped PNG at all**: the renderer draws the scene, and these are `NSView`s
hosted over it. A skin can therefore dump a perfect frame and look wrong on screen, which is exactly
what happened on 2026-09-07 (W43, W9). `visible=none` means the scene clipped the widget out; the
overlay is positioned from `frame`, so a widget with `visible=none` that still shows on screen is a
defect in the hosting, not in the scene.

`INERT` is a member that is recognised, answers, and has nothing behind it — `theme.loadString` can
only ever return the empty string, because there is no `wmploc.dll` on macOS. It gets its own word
and its own census column (`inert_calls`) because a stub that reads as working is the most expensive
bug this engine can carry; `reference/object-model.md` is the contract.

`EXPR` reports **both** evaluators: `->` is the static grammar in `WMPInitialLayoutExpression` that
the scene builder uses, and `live=` is the value the real script context produced. `live=-` with
`#-` means the live pass produced nothing for that key. A skin whose static column resolves and whose
live column is empty is not a working skin.

**`EXPR` is scoped to the dumped view, and reading it any other way is how this line lied.** WMP ids
belong to a `VIEW` and so do both evaluators — `WMPScriptViewPlan` collects the view's own subtree,
and `WMPInitialLayoutResolver` refuses a reference that leaves the view it was built for. The probe
used to walk `graph.allNodes`, so every *other* view's expressions were printed under this view's
name, asked of an evaluator that by construction cannot answer them, once per view in the skin.
Corpus-wide that manufactured **34,300 rows** reading `#-` / `live=-` against 7,700 real ones — 82%,
read for a day as an engine defect starving half the corpus — and the same collision by *name* also
credited a sibling's order number to 131 rows that were not evaluated at all, so it lied in both
directions. See § *After the cascade* below for what the corrected sweep says, and
`testExpressionProbeReportsOnlyTheDumpedViewsOwnExpressions` for the check that holds it.

---

## Input and tooltips the markup authors

Two counts the census does not produce, both measured 2026-09-08, both with a command next to them.

**Nodes that author input on a kind the builder does not treat as a control** — `537` across `143`
of the 179 archives, which is what `WMPSceneBuilder.authorsInputHandler` exists for: `326` `<TEXT>`
across 69 skins, `90` `<EFFECTS>` across 81, `21` `<VIDEO>` across 21, then `stopbutton`,
`progressbar`, `prevbutton`, `playbutton` and `nextbutton` at 12-13 each — transport spellings this
engine still parses as *unknown* kinds, so they are hit targets now and carry no transport action.
`Sports` is the reason it was written: ten `<TEXT>` playlist rows whose `onmouseover` could never
fire because nothing registered them as targets.

```bash
python3 scripts/wmp_input_kinds.py
```

**Tooltips.** Measured with the markup census, whose denominator is 177 — the two repaired-header
archives `unzip` cannot open are outside it:

```bash
scripts/wmp_markup_census.sh /tmp/wmp/markup toolTip upToolTip downToolTip
```

| Attribute | Uses | Skins |
|---|---|---|
| `upToolTip` | 4,712 | 175 of 177 |
| `toolTip` | 3,749 | 174 of 177 |
| `downToolTip` | 517 | 104 of 177 |

None of them reached the screen before 2026-09-08: only widgets answered `stringForToolTip`, and a
skin's controls are `<BUTTON>`s. The tip is resolved per drawn state in `WMPSceneBuilder.toolTip` —
`downToolTip` while the control is down, `upToolTip` otherwise, plain `toolTip` behind both — and
read through the scene overrides, so a script assignment (`alx_dl.wms` writes `toolTip='Volume'`
from its slider's `onMouseUp`) wins over the authored attribute.

## The committed scripts

### `scripts/wmp_skin_census.sh <outdir> [--corpus <dir>] [--allow-dirty] [--parse-only]`

*What is the state of the corpus?* One TSV row per archive: sha256, whether it loaded, the codes it
was rejected for, encoding, view/node/script counts, findings by code, per-view node/command/hit
counts, resolved and missing artwork, the unimplemented tags and host members it demands, and the
git rev it was measured at. This is the only honest source for the reach numbers in `WMP_TASKS.md`
**for anything a view reaches on load**.

**It drives `onLoad` and nothing else, and that bounds every demand number it produces.** A member
called from an `onClick` is invisible here, so a row ranked on this alone is ranked on the subset
of the corpus that runs before the user touches anything: `view.returnToMediaCenter` counted **7**
and is authored by **162 of 180 archives** (W100), and W136 still carries that pair as its own
warning. When a row is about a *control*, the census gives you a floor and § *Auditing one authored
control across the whole corpus* gives you the number.

`--parse-only` re-derives the TSV from a previous run's logs without paying the sweep again — it is
how a parsing change is checked against a capture that is already known-good.

**Check `render.txt` is non-empty before believing a single number out of a capture.** The script
exits **0** on a run that was killed part-way through its own `swift test`, leaving an output
directory that looks exactly like a successful one — `corpus/`, `render.txt`, `render.stderr.txt`
— with `render.txt` at zero lines and no `census.tsv`. Reproduced twice on 2026-09-11 by starting
it detached (`nohup … &`): `render.stderr.txt` ends mid-build (`[1/6] Write swift-version…`), not
after it. The script's header already warns that *a binary that will not compile* writes an empty
capture that diffs as "everything changed"; **a killed run is the same failure with a clean exit
status**, which is worse, because nothing anywhere says so. `wc -l <outdir>/render.txt` and the
presence of `census.tsv` are the two-second check. Run it in the foreground and wait for the
`done — <outdir>/census.tsv` line; that line is the only thing that means it finished.

It also writes two **ranked promotion files**, every run, and names the worst rows on stdout where
the person who ran it is already looking. Both exist because a number the instrument already
measured and nobody ranked is worse than one it cannot see:

* `starved.tsv` — every view by `unresolved / (nodes + unresolved)`, plus `hits == 0` and
  `commands == 0`. **The rule has to be a ratio, not a count** (W70): `unresolved > 0` is true of
  most views in the corpus, so a raw count ranks nothing. Corona — the skin the reporter called
  working — carries 8 unresolved against 66 nodes on `vPlayer`; ALXMorph carries 15 against 15 and
  draws a shell nothing reacts to. A promoted view is one worth dumping and looking at, never a
  defect on its own: `hits == 0` is correct for a view that is pure artwork.
* `appkit.tsv` — every hosted view by how much of the window an AppKit overlay painted **outside**
  any widget frame (W71), with the magnitude of the worst pixel and the separate blit comparison.
  This is the class that produced W43-W46, and it was invisible to every other instrument here.

### `scripts/wmp_markup_census.sh <outdir> [--corpus <dir>] [name ...]`

*How many skins would this element or attribute reach?* One row per name: uses, skins, and the
denominator it measured. It reads the `.wms` files straight out of the archives rather than through
the engine, so it measures **authored demand** and nothing about the result.

It exists because nothing else can see the Class A case that matters most here: **an attribute the
graph parses and the engine then ignores.** That is not an unknown tag, not an unknown member and
not a diagnostic — it is markup that loads cleanly, reports clean, and changes nothing on screen.
Ranking Phase 5's drawing work needed exactly this number, and `fontFace` is the example that pays
for the script: 109 skins author it, 21 author `fontType`, and the builder read only `fontType`.

Two traps it enforces, both of which produced a confident wrong answer first:

- **`grep` goes silent on these files.** A `.wms` is usually UTF-16 and carries bytes `grep` calls
  binary, and a binary file matched with `-o` prints **nothing at all**. The first run of this census
  returned a full table of zeros that read exactly like "the corpus never uses this". Every file is
  stripped to ASCII before it is counted, and `-a` is passed anyway. This generalizes: any ad-hoc
  scan of `.wms` text needs both.
- **A tag spans many lines.** Corpus markup routinely opens `<SLIDER` and closes `>` six lines
  later, so a per-line scan finds neither the attributes nor the tag. Newlines fold to spaces first.

Its denominator is smaller than the sweep's: `unzip` cannot open the two archives whose local header
signature is overwritten (`WMPArchiveHeaderRepair` handles those and `unzip` does not), so a count
here is short by at most two skins and never long. It prints which ones it dropped.

### `scripts/wmp_corpus_exclusions.txt`

The blacklist both scripts read before anything measures. Each script links the in-scope archives
into `<outdir>/corpus` (a hard link, because the harness enumerates with `isRegularFile` and a
symlink is not one) and sweeps *that*, so an excluded skin cannot reach a log, a PNG, or a column —
filtering afterwards would still let its diagnostics rank work. Both print what they dropped and the
count they actually measured; the corpus denominator in `WMP_TASKS.md` is that number, not the
directory listing.

A skin belongs here when no work in this engine changes its outcome — not when it is merely broken.
The standing entry is `Darkling.wmz`, authored against WMP's Party Mode host (`PartyMode.*`), which
this player has no equivalent of; its own `OnLoad` catches the missing host and draws a "designed for
Party Mode" panel, exactly as real WMP does outside Party Mode. Record the reason in the file next to
the entry, and treat removing a line as a decision.

### `python3 scripts/wmp_implicit_key.py [--corpus <dir>] [--color RRGGBB] [--tsv <file>] [--alpha only|none|any]`

*How much artwork relies on WMP's implicit transparency colour?* Counts drawn sprites that hold
opaque `#FF00FF` pixels and hang off a node declaring neither `transparencyColor` nor
`clippingColor` — the W78 class, and the measurement that had to exist before anything defaulted a
key engine-wide. It reads `.wms` and artwork straight out of the archives, so it measures authored
demand, never a render result.

Measured 2026-09-08 over the 179-archive corpus: **603 node/attribute references across 80 skins and
499 distinct sprites**, of 22,649 drawn artwork references of which 8,833 declare a key themselves.
`--tsv` writes every row, sorted by how many key pixels the sprite holds, which is the order to open
them in. What it does *not* count is a mapping/clipping/position image — read for its colours, never
blitted, and an implicit key there would delete a mapping colour from its own map.

**`--alpha only|none|any` splits the class by whether the sprite authored an alpha channel, and that
split is W78a.** W78 shipped keying only `none` (527 refs / 66 skins / 437 sprites), on the reasoning
that a sprite carrying alpha has already said what is see-through. `--alpha only` measures what that
left behind — **76 references across 21 skins and 62 sprites** — and the falsifying check is not the
count but the pairing: **11 of those nodes hold two states of the same button, one exported without
an alpha channel and one with, with identical magenta counts** (`Half-Life_2`
`m_pause_no.png`/`m_pause_hov.gif`, both 1,394). Under the veto the normal state keyed and the hover
state did not, so the button turned magenta under the pointer. The engine now keys `any`, which is
this script's default so that what it counts is what the engine does. A `key_pixels` count is of
**opaque** key pixels: a partially transparent one is composited paint, and the corpus holds none.

`WoW/mainView`, the residual's headline at 3.5%, was the same thing seen through a `CUSTOMSLIDER`:
`volume_1.png` is a 31-frame filmstrip against an 86x84 `volume_map.png`, and every frame carries the
same flat magenta wedge beside a genuinely antialiased knob. The crop was already correct; only the
wedge was paint that should not have been.

**After the veto came off, the corpus residual is 878 opaque magenta pixels across 2 of 545 views,
and neither is an implicit-key case.** `portals/mode1` (829 px, 0.38%) is a `BUTTONGROUP` declaring
`transparencyColor="#000000"` whose sheet's magenta filler is blitted whole instead of drawn through
its mapping — that is W48(a). `Plus! Pulsar/mainView` (49 px, 0.04%) is a `<button
id="shutterButton">` declaring `transparencyColor="#ffffff"`, so the implicit key correctly stands
aside and real WMP draws the same corner.

**One corpus view is nondeterministic and a PNG-diff sweep will flag it forever.**
`Scooby-Doo_2/infoView` picks its character at random in `scooby.js`: three runs of one binary give
two hashes. Do not read it as collateral from a change.

The companion number, from the markup census's own attribute counts: **4,979 of the 6,076
`transparencyColor` declarations in the corpus (82%, 142 skins) are `#ff00ff`.** That is why the
default is that colour and not another.

### `scripts/wmp_render_sweep.sh capture|compare`

*Did my change move anything?* `capture` writes the invariant lines **and** every PNG; `compare`
diffs both. Every engine-wide change from Phase 2 onward passes through this.

```bash
git worktree add ../nullplayer-base HEAD
(cd ../nullplayer-base && scripts/wmp_render_sweep.sh capture /tmp/wmp-sweep/base)
# …make the change…
scripts/wmp_render_sweep.sh capture  /tmp/wmp-sweep/curr
scripts/wmp_render_sweep.sh compare  /tmp/wmp-sweep/base /tmp/wmp-sweep/curr
```

**Never capture the baseline with `git stash`** — it relinks `.build` under the user's running app.

**A before/after `wmp_skin_census.sh` pair *is* a render sweep — do not run both.** The census
writes every PNG to `<outdir>/png/<skin>/` with every probe on, so comparing the two `png/` trees by
`sha256` answers the same question `compare` answers, off captures you already paid for. W128 needed
the `UNRECOGNISED` tally *and* proof that nothing moved; one census pair gave both, and a second pair
of sweeps would have been ~10 minutes of rebuild for a duplicate answer. Use `wmp_render_sweep.sh`
when the pixels are the whole question; use the census when you also need the counts.

**A fresh worktree cannot build: `Frameworks/` is not in git.** `swift build` fails with `no such
module 'VLCKit'`, and even once it links, the test bundle refuses to load without the frameworks
`swift build` copies next to it. Link both from the working repo, then capture with `--allow-dirty`.

**But `Frameworks/` is *partly* tracked, so do not symlink the directory.** `libaubio/`,
`libkeyfinder/`, `libprojectm-4/` and `libaubio.5.dylib` are in git, so the worktree already has a
real `Frameworks/` and `ln -s "$PWD/Frameworks" ../nullplayer-base/Frameworks` silently lands
*inside* it as `Frameworks/Frameworks` — the build then fails with the same `no such module
'VLCKit'` it would have without the link, which reads as the link not working rather than as the
link going somewhere else. Link the four **entries** git does not carry, then the build directory:

```bash
for f in VLCKit.framework libaubio.dylib libprojectM-4.dylib libprojectM-4.4.dylib; do
  ln -sfn "$PWD/Frameworks/$f" "../nullplayer-base/Frameworks/$f"
done
# `swift build` in the worktree now compiles and links, and dies in dlopen: the test bundle's rpath
# resolves beside itself. Run it once to create the directory, then mirror what the working repo has
# there — ogg/vorbis are real directories, the rest are links.
for f in "$PWD"/.build/arm64-apple-macosx/debug/*.framework "$PWD"/.build/arm64-apple-macosx/debug/*.dylib; do
  ln -sfn "$(readlink "$f" || echo "$f")" "../nullplayer-base/.build/arm64-apple-macosx/debug/$(basename "$f")"
done
```

`git status -- Sources Tests scripts` staying clean is the check that the baseline really is HEAD;
the framework links are what make it dirty. Confirmed working 2026-09-11 for W128's before/after
census — the W76 note in the archive records a pixel comparison that could not run for exactly this
reason, and that is the gap this paragraph closes.

---

## Traps the scripts enforce, inherited rather than re-earned

- **A sweep is a build — freeze the tree.** `capture` and the census refuse a dirty tree without
  `--allow-dirty`. A binary that will not compile writes an *empty* capture that diffs as
  "everything changed". Never run either while the user may be building: SwiftPM lock contention
  stalls both.
- **Redirect to a file and grep the file.** Piping a long `swift test` into a filter drops lines
  silently. stderr gets its own file.
- **Every harness line is one `write(2)`, never `print`.** `WMPHarnessOutput.emit` takes a lock,
  flushes stdio so XCTest's own lines stay ordered against ours, and writes the line and its
  terminator in a single unbuffered call. It exists because `print` did not: in the 180-archive
  sweep at rev `171cf89a` a `CALL` line and the `SKIN` line opening the next archive landed inside
  one another (`CALL vSKIN Windows_XP_Media_Center_Edition.wmz`) and the **5,087 bytes** that should
  have followed — the rest of that skin's trace, two `PNG` lines and a `RENDER-DUMP` — never reached
  the file. It was byte-identical across two full sweeps and did not reproduce on a two-archive
  corpus, so it was the buffered stream, not the content: what is lost is whatever `stdout` was
  holding. Removing the buffer removes the loss. Do not reintroduce `print` here.
- **The damage detectors stay, and one of them is arithmetic.** A splice is only the *visible* half
  of a lost write, and the invisible half is the common one: that same run lost three blocks and the
  prefix scan saw **one**, because the splice consumes the record prefix that would have betrayed
  it. So both scripts also check each loaded block's `RENDER-DUMP` count against the `views=` its own
  `LOAD` line declares (a view that fails still emits `RENDER-DUMP <view> FAILED`), and flag a
  second `LOAD` inside one block. **Count distinct view ids, not lines.** A view that lays out and
  then fails to rasterize emits *both* — the stats dump and the `FAILED` one — so when W32 admitted
  `Nautical` (one view, laid out, then `WMP0015` on `vol_slider.bmp`) the arithmetic read 2 against
  `views=1` and called the block damaged when nothing had been lost. Reading a live defect as a lost
  log block is this check's own failure mode, pointed the wrong way, and it survived a solo re-run —
  which is what distinguishes it from a real splice. Damaged skins are listed in `damaged.txt`, get a row carrying
  identity and nothing else, and are left out of the diff. Re-run one alone with
  `--corpus <a directory holding just that archive>`. Their PNGs are unaffected and still compare.
- **Compare pixels, not alpha.** Pillow 9.5 made `getbbox()` on an RGBA image consider the alpha
  channel alone, and every dump carries alpha, so a change that moved a visible control but left
  alpha untouched came back "identical" across 590 `.wal` images. `alpha_only=False` in
  `wmp_render_sweep.sh` is load-bearing, not tidiness.
- **A `maxdelta` of 1** is an LSB rounding difference, not a regression. The script reports the
  number; a human reads it.
- **The alpha trap has a second door: `ImageChops.difference` on RGBA.** `wmp_render_sweep.sh`
  passes `alpha_only=False` and is safe, but an ad-hoc Pillow comparison written beside it is not:
  `getbbox()` on the *difference image* looks at alpha alone for the same reason, so a colour-only
  change reports "identical". During the Phase 5 sweep that scan found 3 changed images where the
  script found 198. Split the bands: `any(band.getbbox() for band in diff.split())`.
- **`SCRIPT inline:` is emitted in dictionary order and is not stable between runs** — the same
  archive reports the same handler tally in a different order each time. It inflates the invariants
  diff with churn that is not a change; open as W64. Until it is fixed, read a large invariants diff
  by what the `RENDER-DUMP`, `BITMAPS` and `LOAD` lines say, not by the line count.
- **A large image diff is read by looking, and by which way it went.** 198 of 545 changed in the
  Phase 5 sweep. Counting the *drawn* (alpha > 8) pixels in each pair and sorting sorts the whole
  set into "changed colour within the same silhouette" and "lost or gained content", and the second
  list was one skin long — which is the list worth opening.

---

## Driving the GUI yourself: two traps that produced wrong conclusions (2026-09-10)

Both cost a stated, confident, wrong answer during W102's live QA. Neither is about the app.

**A synthetic click must set `mouseEventClickState`, or it is not a click.** A `CGEvent` pair of
`.leftMouseDown`/`.leftMouseUp` posted without `e.setIntegerValueField(.mouseEventClickState, 1)`
arrives with `clickCount == 0`. The pointer moves, the hover artwork follows it, `mouseDown` may
even dispatch — and no click is ever synthesised. This was read as *"the skin's play button is dead"*
when it was the tool. **Prove the input arrives before concluding the app ignored it**: click
something with a known trace (`INPUT action <transport>` on any transport button) and see the line
appear. Same rule as every other instrument on this page. A double-click additionally needs
`clickState` 1 then 2 on consecutive down/up pairs.

**A synthetic right-click does not open a contextual menu at all, `clickState` or not.** It produced
no menu and no `INPUT menu` line against `WMPMainView.menu(for:)` — a method a *real* right-click
drives correctly, as the reporter confirmed the same day by using the subtitle menu it serves. That
absence was written up as W125, "no right-click on a `.wmz` reaches `menu(for:)`", and withdrawn:
**the engine defect did not exist.** `INPUT menu` is a fine instrument for a real pointer and worth
nothing under a posted event. Verify menus by hand, or by asking the reporter.

**`screencapture -R <region>` photographs the screen, not the window** — including whatever is on
top of it, which during agent-driven QA is routinely your own terminal. Use `screencapture -l
<windowid>` (id from `CGWindowListCopyWindowInfo`) to capture a window's **own** content regardless
of occlusion. That single distinction is what settled the "video goes black" defect: the window's own
content was the movie, playing, so nothing was wrong with decoding or sizing and the whole question
became compositing. Pair it with the front-to-back order from
`CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])` — **pass
`.optionOnScreenOnly`**, because `.optionAll` includes offscreen windows and its ordering means
nothing; reading order out of an `.optionAll` list said the video was in front when it was behind.

**A parked video window is a child window, so two invariants are free and worth asserting**: a child
is always drawn above its parent, and it moves with its parent atomically. If the picture is behind
the skin, or trails a drag, the parent-child link is gone — do not go looking at VLC. See
`SKILL.md` § the `.wmz` video loan.

## Proving the instrument

*When a probe reports nothing, check the probe can see the thing at all.* Three `.wal` harness blind
spots each made a real defect look absent. Four checks run on every plain `swift test`
(`WMPRenderDumpTests`) and are the reason the corresponding sweep columns can be believed:

| Test | Proves |
|---|---|
| `testRenderBitmapsProbeReportsAMissingAsset` | `BITMAPS` names a deliberately renamed asset — the Class C detector actually notices an absence |
| `testRenderProbeReportsResolvedFramesForEveryDrawnNode` | `PROBE` reports the frame a node was *drawn at*, not the one it was authored with |
| `testExpressionProbeReportsSourceAndResolvedValue` | `EXPR` reports both the source text and the value it resolved to |
| `testExpressionProbeReportsOnlyTheDumpedViewsOwnExpressions` | `EXPR` answers for the dumped view **and no other** — a two-view skin reports one row per view. Without it the probe asked one view's evaluator about another view's nodes and printed the refusal as a defect, 34,300 times |
| `testUprightCropColorKeyNestedClipZOrderAndBackingScale` | the renderer's own pixels, at 1× and 2× — the check that nothing else in this table substitutes for |
| `testEmitsEveryLineWholeUnderConcurrentWriters` | eight concurrent writers and 9 KB lines all arrive whole and exactly once — the emitter cannot splice or drop a measurement |
| `testAppKitProbeSeesAnOverlayAndReportsNothingWithoutOne` | `APPKIT` in both directions: a scene with nothing hosted over it diffs to **exactly zero**, and a scene carrying a `PLAYLIST` diffs inside that widget's frame and nowhere else. Without the first half, "no defect" and "blind instrument" print the same line |

`compare` was checked the same way on 2026-09-07: a one-pixel **colour-only** change (alpha
untouched) to one dumped PNG and a one-character change to one invariant line, each reported.

**Measuring a transparency key: read the keys out of the markup.** The class W8 counted is scored by
scanning every dumped PNG for *opaque* pixels holding a key colour and reporting any view over 5% of
its area — a census column cannot see it, because a view that draws its key is structurally perfect.
The trap is assuming which colour that is. A magenta-only scan gave 23 views across 21 skins; adding
`#FF0000` gave 37 across 34, with 11 views pure red and no magenta at all. Neither is the rule.
**Score against the set of colours each skin's own `.wms` declares** — `clippingColor` and
`transparencyColor`, both of which a single node commonly carries with *different* values — and
never against a hard-coded palette. Closing W8 under that rule leaves **28 views across 26 skins at
or above 5%**, and every one of them is now a different defect (see W48): artwork whose flat colour
is keyed nowhere in the markup, or a `BUTTONGROUP` blitting its whole sheet.

**Proving `WMP_RENDER_CLOCK` itself.** It was checked the way the table above demands, before any
claim was made from it: `Xbox Live Skin` (whose `intro_anim.gif` is 145 frames) dumped at 0, 1.5 and
3 seconds gives three different images — 4,475 pixels change between the first two and 3,917 between
the second two — and the logo visibly moves. A flag that reported the same PNG three times would
have looked exactly like a working one on the `ANIMATION` line alone.

**Proving the drag probe.** Same rule, and its negative answers are reachable: a drag along Corona's
horizontal volume slider (`vPlayer@415,318>430,318>450,318>475,318`) gives `value 0 -> 100
follows-pointer=yes thumb-travel=48`, and its vertical `eq1` (`286,250>286,230>286,200`) gives
`-14 -> 14 follows-pointer=yes thumb-travel=34` — both axes, value and drawn thumb tracking
together. A drag that never leaves its start point reports `follows-pointer=flat thumb-travel=0`,
and one that starts on a button reports `not-a-slider`, so a mis-aimed probe reads as mis-aimed
rather than as a passing slider. The handler lookup goes through
`WMPMainWindowController.handlers(in:event:…)` — **the app's own matcher, never a second one**: 175
of 179 archives author `value_onchange` rather than `onChange`, and a private lookup here would
report every one of those sliders as having no handler.

**Three things a clean sweep does not prove.** It measures the default state and nothing else — not a
tab, a setting, a drag, a hover, or anything driven by live playback. A structural probe is not a
picture: a node existing says nothing about where it is drawn. And **a correct dumped frame is not a
correct window**: the AppKit overlays, the window's shape and its shadow, and every repaint decision
live outside the renderer. On 2026-09-07 the headless `vPlayer` and `viewTiny` frames were correct in
every state tested while the live app showed a dark box the size of the window, drawers that were
never erased, and a black panel during playback. Only the reporter driving the app found any of them.

`WMP_RENDER_APPKIT` (W71) closes the *overlay* part of that third gap and none of the rest. Window
shape and shadow live in the window server and stay a short, genuinely manual list; so do hover, a
tab, a setting and live playback.

---

## What the harness measured on 2026-09-07 (14-skin corpus, rev `055063ed`)

Recorded here because it **contradicts the recovery plan's inherited hand measurement**, which came
from the branch's own phase handoff docs. Those docs are unverified narrative — phase 7 asserts a
release capability gate that its own `AppCapabilities.swift` does not implement — so check every
number from them against the code before relying on it. This is census output.

| Claim in the plan | Census |
|---|---|
| 4 of 14 archives load | **10 of 14 load** |
| 7 of 10 rejections are `WMP0025` (text encoding) | **0 encoding rejections.** The decoder already resolves the corpus: utf16LE ×11, windows1252 ×2 |
| 3 of 10 rejections are `WMP0027` (duplicate attribute) | **all 4 rejections are `WMP0027`** — Alpine7618_v09, anemone, Official_Xbox_XP, The Unit, exactly the four skins measured as carrying duplicate attributes |

So the whole of the Tier-1 loading blocker was the lenient-XML-parser work (`W2`), and the decoder
work (`W1`) was not ranked ahead of it. Two further clusters the census surfaced, which the plan had
folded into later phases:

- **`WMP0032`, 7 views across 5 skins** — "View requires positive literal width and height for
  static layout". A view whose size is computed in script renders nothing at all, which is why
  `claw.wmz` and `iconic.wmz` load cleanly and produce **zero** layouts.
- **`WMP0024`, 2 views** — an *empty* resource attribute rejected as "absolute, drive-qualified, or
  invalid", killing the whole view.

Every count above carries the corpus it was measured against. Do not rewrite an old numerator
against a new denominator.

## After Phase 2 (14-skin corpus, rev `733d3631`)

`load ok=14`. The four `WMP0027` rejections are gone; see `reference/loading.md` for what replaced
the parser and what it now tolerates. Re-measured against the **new 14-archive denominator**, so
these are not comparable line-for-line with the numbers above:

| | rev `055063ed` (10 loading) | rev `733d3631` (14 loading) |
|---|---|---|
| archives loaded | 10 | **14** |
| rejections | 4 × `WMP0027` | **0** |
| `WMP0032` blacked-out views | 7 across 5 skins | 9 across 6 skins |
| `WMP0024` killed views | 2 | 3 |
| `WMP0034` duplicate attributes | — (the code did not exist) | 19 across 4 skins |
| render dumps | 18 PNGs | 25 PNGs |

**What the sweep proved about collateral damage.** All 18 pre-existing PNGs are byte-identical. The
only invariant lines that moved are diagnostic *locations*, and they moved because the new parser
points at a tag's opening `<` where libxml2 reported the position the tag ended at — verified by hand
against `corona.wms`, where `svTop` opens on line 42 and its closing `>` is on line 46. Nothing else
in any block changed: no counts, no node ids, no bitmap resolution, no layout shapes.

**Two Class B defects became visible only because the skins now load** — a probe cannot see a defect
in a skin it rejects, and neither can you:

- `Alpine7618_v09/view-2@1x.png` renders its art in the lower ~150 px of a 517×412 view and flat
  `#FF00FF` everywhere else: the transparency key is not applied to the uncovered background (`W8`).
- `Official_Xbox_XP/mainBox@1x.png` has `WMPWidgetViews`' opaque black `VIDEO` placeholder painted
  over the skin's own artwork (`W9`).

Both were found by *looking at the PNGs*. The census reports both skins as clean loads with resolved
bitmaps, which is exactly the blind spot the harness notes warn about: a structural probe says a node
exists, never that it is drawn right.

## After Phase 3 (180-archive corpus, rev `c8a843e4`)

The script runtime became one persistent `JSContext` per skin session. Loading did not change and
was not expected to; what changed is what runs after it. The census's default pass now drives each
view's own `onLoad`, the way the app does — a harness that skipped it was measuring a skin nobody
sees.

| | rev `ada068ff` | rev `c8a843e4` |
|---|---|---|
| archives loaded | 171 of 180 | 171 of 180 |
| views laid out | 482 | 482 |
| paint commands | 9,120 | **9,186** |
| widgets | 1,396 | **1,436** |
| unresolved nodes | 2,393 | **2,352** |
| `expression-error` corpus-wide | every expression in most skins | **1**, plus 8 `invalid-geometry` |
| distinct `UNRECOGNISED` members | (not comparable — measured statically) | **6** |

`compare`: **442 images identical, 40 differing, none lost, none new.** Every difference is script
state now being applied, and they were looked at rather than counted: `Plus! Aquarium/view-2` went
from a **blank page** to the whole skin; `WoW/videoView` gained the logo its `onLoad` sets;
`Grinch/view-2` and `Plus! SlimLine/perfectVSkin` *lost* pixels because their scripts hide a video
pane and a stray close box when nothing is playing, which is what WMP does.

The remaining 228 handler errors are ranked in `WMP_TASKS.md`, and 102 of them are one missing host
object (`mediacenter`). *(W37 closed that object in Phase 6; see* § After W37 *below for the
re-measurement, and note the count here is a Phase 3 number kept as written.)*

---

## After Phase 6 (179-archive corpus, rev `824261d4` + the Phase 6 change)

Phase 6 is where the corpus tooling stops being a description of the corpus and starts ranking work
by itself. Three instruments and one capability landed; every number below is
`scripts/wmp_skin_census.sh /tmp/wmp/census`, measured 2026-09-08 over 179 archives and **607 views**.

**What the instruments found on their first run.**

* **Starvation (W70).** 41 views across 36 skins resolve less than half the nodes they declare;
  79 views across 49 skins have no hit target at all; 65 across 37 draw no command. The worst are
  not the ones anybody had named: `Disney_Mix_Central/mainView` resolves **2 of 25**,
  `Batman Begins/mainView` 2 of 21, `Alienware Invader/mainView` 2 of 20, and
  `Cablemusic/mainview` 35 of 98. ALXMorph — the skin live QA reported as dead — sits at exactly
  0.50 and is one of the *milder* cases. The ranking is in `starved.tsv` every run.
* **AppKit hosting (W71).** 545 of the 607 views were hosted through the real `NSView` stack and
  diffed. **Exactly two paint outside any widget frame** — `Revert.wmz` and `Revert (1).wmz`, both
  releases of the same skin, `vwPL`, 4,000 px at delta 196, in a 250x4 band at `3,256` where the
  playlist overlay's frame (`3,14 250x257`) runs past the 260-tall view's own bottom edge. That is
  the entire W43 class in the corpus's default state, and it is one defect in one skin. The
  reporter's "tons of issues" are therefore, on this evidence, mostly *scene*-side (the starvation
  class above) or driven by something a default-state sweep still cannot reach.
* **Drag (W72).** Every slider in the corpus is now drivable headlessly. See *Proving the drag
  probe* above for the two worked axes.

**What one capability change drained.** `value_onchange`, `OpenState_onchange` and
`PlayState_onchange` are WMP's other spelling for three events the engine already dispatches, and
the corpus writes them by an order of magnitude more than the spellings that worked: 175 of 179
archives, 144 and 139, against 11 and 7. Accepting both spellings in the one matcher every dispatch
site already goes through took measured event demand from **6,823 uses to 4,114** — 2,709 uses, 40%
of everything the corpus asks for in this class, in one change with no new dispatch site. It also
removed a phantom `UNKNOWN member player.settings.volume = value;updatevoltooltip()`, which was a
handler body being read as a member path.

`scripts/wmp_render_sweep.sh compare` across the change: **545 images identical, 0 differing, 0 lost,
0 new**, and 2,070 green tests. The distinct-event vocabulary reads 140 → 142 rather than 140 → 137;
36 blocks were damaged in both captures (W35), so the edges of that vocabulary move between runs and
the *uses* figure is the one to quote.

**What Phase 6 did not touch.** Everything the ranked lists now point at. Draining A/C/D
automatically was the job; the lists are the output, not the fixes.

---

## After the cascade (179-archive corpus, rev `df4a8c75` + the probe fix, 2026-09-08)

The Phase 6 sweep above left one open question — *why do 82% of the corpus's geometry expressions
never reach the live evaluator* — and the answer is that they do. **The 82% was this file's own
instrument.**

Re-run the capture the claim came from:

```bash
WMP_SKIN="$HOME/Library/Application Support/NullPlayer/WMPSkins" WMP_RENDER_EXPR=1 \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus > /tmp/wmp/expr-all.txt 2>&1
```

| | before | after |
|---|---|---|
| `EXPR` rows, 179 archives | 42,015 | **7,569** |
| reached the live evaluator (an order number and a `live=` value) | 7,700 (18%) | **7,569 (100%)** |
| `#-` with `live=-` | 34,314 (82%) | **0** |
| static evaluator `unknown geometry object 'X'` | 10,188 uses / 85 skins | **0** |

**What the old rows were.** Both evaluators are scoped to one `VIEW`; the probe was not. Of the
34,314 rows that reported nothing, **34,300 were another view's expression printed under this view's
name** — every one of them already ordered and evaluated under its own view — and the remaining 14
are one skin whose view node is keyed `view.*` in its own dump and by its authored id everywhere
else. The dominant "failure reason", `unknown geometry object`, was `WMPInitialLayoutResolver`
correctly refusing a reference that leaves the view it was built for: the object was never missing,
the question was addressed to the wrong evaluator. The collision ran the other way too — a duplicate
id across two views credited a sibling's order number to 131 rows that were never evaluated, so the
7,700 was wrong as well as the 34,314.

The handoff's worked case is the whole defect in one line. `Alienware Invader` was reported as
`EXPR mainView/plLeftStretch.top #-: plLeftCenter.top -> UNRESOLVED(unknown geometry object …)`, and
`plLeftStretch` and `plLeftCenter` are both in **`plView`**, where the same expression reads
`EXPR plView/plLeftStretch.top #17: plLeftCenter.top -> 0 live=7`. A node "that exists in the markup
and appears in no `PROBE` output" was a node in a view nobody was probing.

**What the corrected sweep leaves.** Two rows in one skin, and one error:

* `digitaldj.wmz` `DigitalDJ` `view.width` / `view.height` evaluate to the **empty string**:
  `(theme.loadPreference('WD') == '--') ? 640 : theme.loadPreference('WD')`. `loadPreference` returns
  `''` for a key that was never written, so the `'--'` sentinel never matches and the ternary yields
  the empty value rather than the authored default (W76). The view still draws at 640x458 because
  the static grammar answered.
* `Compact.wmz` `myeffect.top` is `ReferenceError: Can't find variable: mediacenter` — W37, since
  closed; that expression now evaluates.

**What it does not touch: the starvation class.** `starved.tsv` is unchanged at **41 starved views
across 36 skins**, and re-measuring it after the fix was the point: expressions are not what starves
a view. The three skins the handoff named were opened and looked at, and none of them is an
expression defect —

| Skin / view | expressions | what the dump shows |
|---|---|---|
| `Cablemusic` / `mainview` | **zero** | 63 unresolved nodes, no geometry expressions at all, no missing bitmaps — and it draws a nearly complete player |
| `ALXMorph` / `mainView` | 4, all live-resolved | draws its whole shell; "does nothing" is interaction and animation, not layout |
| `Alienware Invader` / `mainView` | 6, all live-resolved | genuinely blank, and for its own reason: `toggleShutter()` plays a **568-frame** intro off a 50 ms timer and only at frame 568 sets `mainBack.backgroundImage = "main_back.png"` and `mainBackGroup1.visible = true`. Frame 0 of an intro is what the default-state sweep measures |

That last one turned up W75 — a script assignment to `backgroundImage` never reaches the scene —
**and W75 is now closed.** `WMPSceneBuilder.resolveResource` read the authored attribute only and
consulted `overrides.properties` for nothing, so `mainBack` resolved its 406x380 frame, was handed a
real existing PNG on every tick of a `WMP_RENDER_SETTLE=32` run, and still emitted **zero paint
commands**. Artwork was the one property class the override path skipped.

### What closing it measured

**Reach, from the call trace** (`WMP_SKIN=<skins dir> WMP_CALL_TRACE=1`, tallying
`CALL … <member> write` lines whose member ends in `image`, by skin, over the 179-archive corpus):
**45 skins** write an artwork property from script in the default state — 55 writes, of which
`backgroundImage` is 49, `image` 4 and `downImage` 2. **36 of the 45 write `""`**: that is the
store-thumbnail collapse (`view.width = 0; view.height = 0; view.backgroundImage = "";
theme.currentViewID = …`), not artwork being swapped. **Nine write a real path** — `Alienware
Invader`, `Alienware_Darkstar_WMP11`, `Crimson_Skies`, `Frostbite`, `Scooby-Doo_2`, `STALKER`,
`T3-Skynet_Media_Player`, `The_Last_Samurai`, `tubeframe` — and that is the class the row was
about. A settled run reaches more of them; the default state is what this number is.

**Result, `scripts/wmp_render_sweep.sh compare` over 179 archives / 545 hosted PNGs.** 533
identical, **12 changed, none of them a loss**:

* 10 `mediaSwitcherView`s (`Combat_Flight_Simulator_3`, both `Plus!` skins, both `QuickSilver`
  releases, both `TripleX`, both `WWN`, `xXx_night_vision_redx`) go `1 command` → `0` and draw
  nothing, which is the view obeying its own `backgroundImage = ""` before it redirects. This is why
  the corpus's "draws nothing" tally moves **65 → 75 views / 37 → 45 skins**: a collapse that now
  works reads as a blank view, and the ranking cannot tell the two apart. It is the one number this
  fix makes worse and the reason it is written down here.
* `Scooby-Doo_2/infoView` draws the character its `onLoad` picks instead of the authored one.
* `tubeframe/TubeFrameView` gains a scripted button image (34 → 35 commands).

`Alienware Invader/mainView` itself is unchanged in the default sweep — frame 0 of a 568-frame intro
is still frame 0 — and under `WMP_RENDER_SETTLE=32` it goes from **0 commands and an empty PNG** to
its full 406x380 player artwork.

**The sweep caught a regression that no unit test would have.** The first version resolved the
override with `try`, and `WMPArchive.resolve` *throws* for a path outside the provider rather than
returning `nil`. A skin assigning a `res://wmploc/RT_IMAGE/#2024` it had read back off its own markup
therefore took its whole view down with `WMP0024`: **5 views across 3 skins** — `corona` and
`9SeriesDefault` each lost `vPlayer` *and* `viewTiny`, plus `Compact/compact`. `try?` and the same
warning path as a missing file. An override is runtime data; nothing it carries may reject a view.

---

## After the starvation classes (179-archive corpus, 2026-09-09)

`starved.tsv` had ranked views for two phases and nothing had been taken off the top of it, because
the number it ranks on names no node. `WMP_RENDER_UNRESOLVED` names them, and the first corpus-wide
run said the ranking was not a list of skins at all — **83% of the corpus's 2,380 unresolved nodes
were three rules**:

| what the tag was | nodes | skins | why it resolved nothing |
|---|---:|---:|---|
| `<TEXT>` | 1,441 | 127 | no intrinsic size; 1,058 were missing width *and* height |
| `<PLAYELEMENT>` / `<STOPELEMENT>` / `<NEXTELEMENT>` / `<PREVELEMENT>` / `<PAUSEELEMENT>` / `<REWELEMENT>` / `<FFWDELEMENT>` | 494 | ~90 | laid out as controls; they are colour regions of a `BUTTONGROUP`'s mapping image |
| `<BUTTONGROUP>` | 31 | 16 | no intrinsic size; the group's normal state is usually the window's own artwork, so it authors no `image` and no geometry |

**The reporter's skin was one skin with all three, plus two more.** `Cablemusic` — "most buttons
don't work, there is no track display" — is `35 nodes, 42 commands, 20 hits, 63 unresolved` before
and `89 / 87 / 66 / 8` after. The remaining 8 are the eight `<TEXT>` nodes it declares **twice**; the
second declaration wins the id and the first is never written, which is WMP's own outcome and not a
defect. The two beyond the table:

* **`<PLAYBUTTON>`, `<NEXTBUTTON>`, `<PREVBUTTON>`, `<STOPBUTTON>`, `<MUTEBUTTON>`, `<REPEATBUTTON>`
  and `<PAUSEELEMENT>` were not element kinds at all.** WMP spells every transport control twice and
  only one half of each pair was in the table. Measured with `scripts/wmp_markup_census.sh`:
  `PAUSEELEMENT` 80 uses / 69 skins, `PLAYBUTTON` 50 / 45, `PREVBUTTON` 50 / 45, `NEXTBUTTON` 49 /
  44, `STOPBUTTON` 48 / 42, `MUTEBUTTON` 10 / 9, `REPEATBUTTON` 5 / 4. An unknown kind still paints
  its `image`, so the button **drew and did nothing**, and `WMP_RENDER_CLICK` on `Cablemusic`'s play
  button returned `hit=ffw` — the pointer fell through to the neighbour whose frame overlapped it.
  That is what "the wrong button responds" looks like from the other side of § *"The wrong button
  responds" is two questions*.
* **An origin the markup never stated could not be written by script.** `left`/`top` default to 0
  when unauthored, and the check was `attribute == nil ? 0 : resolve` — short-circuiting *before*
  the scene overrides were consulted. Size never had it. So a handler that positions an element
  from nothing moved it nowhere: `Cablemusic`'s two drawers are seventeen station rows each, laid
  out entirely by `InitPrograms()` writing `pr<N>.top`, and all thirty-four drew on top of one
  another in the corner of the drawer — the right width, in the wrong place.

**What the sweep said.** `scripts/wmp_render_sweep.sh compare` over 179 archives / 545 PNGs: **422
identical, 123 differing, none lost, none new**, and exactly one image lost any coverage (2 px on
`SplinterCellWMPSkin/videoView`). Summed over every view: nodes 11,284 → **11,973**, paint commands
9,459 → **10,070**, hit targets 3,996 → **4,249**, widgets 1,650 → **2,259**, and unresolved nodes
2,210 → **1,067**. 268 views improved and **one** decreased — `LostPlanet/infoView`, 5 hits → 1, and
that one is the origin fix working: its four gallery thumbnails are `moveTo`'d off-stage by
`onLoadInfo()` and used to be pinned at the gallery's corner as four invisible stacked hit targets.
`GEOM` says thumb1 now resolves to `-143,43`, outside its parent's clip.

**Two rules came back narrower after the sweep disagreed with them**, and neither was findable any
other way:

* **`mappingColor` alone does not mean "a region, not a box".** The first version exempted any node
  declaring one from layout. `polygon` authors `<subview id="ToggleButton" left="75" top="27"
  width="18" height="18" mappingImage="Toggle_MAP.bmp" mappingColor="#FF0000">` — a mask on the
  subview itself — and lost its geometry, which dropped the panel it draws and moved the
  `returnButton` inside it to the window's corner. The test is the attribute **under a
  `BUTTONGROUP`**, which is the same pair the group's own `mappingTargets` are built from.
* **Two children can declare the same `mappingColor`, and `Dictionary(uniqueKeysWithValues:)` traps
  the process.** `Cablemusic` authors `bnpb6` and `bnpb7` both as `#00C0FF`. Nothing had ever
  reached that code for this skin because its groups resolved no frame at all, so sizing the group
  from its mapping image turned a dead control into a **crash on load**. First in document order
  wins, as WMP does. Expect this shape whenever a fix makes previously-dead code reachable.

### The second report on the same skin, and what only the running app could say

The first round left `Cablemusic` drawing a whole player and four defects still on the screen:
"when you click the compact button there is a large overlay, the track information does not appear
and the track text is shifted up too high in the track window, the playlist is always showing."
**Two of the four were reachable headlessly and two were not**, and the two that were not are why a
live script diagnostic mattered at the time (the `INPUT` trace that carried it was removed on
2026-09-11; see above).

* **Headless, one command each.** `WMP_RENDER_CLICK='mainview@384,390;579,390'` opens the playlist
  drawer and closes it again: the second click printed `changed=[subPlayList.left=178]` and
  `61 widgets[… playlist×1 …]` — the drawer shut and the playlist stayed. `moveTo` applied its
  endpoint inside the call, so `HidePlist()`'s `if (subPlayList.left == 373)` read the destination
  instead of the origin (W112). The label geometry was the same shape: `WMP_RENDER_PROBE` said
  `frame=50,350 55x12` against a `fontSize` the script had set to 7, which is a 10 pt box (W114).
* **Live, and invisible to every probe here.** The readouts were empty with a track playing and
  nothing in the corpus sweep could say why, because the sweep has no snapshot. `INPUT script-diag`
  named it in one launch — `unimplemented player.network.bitrate (network member)` — and then, with
  that closed, named the next one behind it: `unimplemented player.currentmedia.sourceurl`. **Both
  are in `handlePlayStateChange`'s path *before* the function that fills every readout**, so one
  missing member cost the whole block. This is § *After W37*'s rule arriving twice in one session:
  close the biggest row and re-measure, because the row behind it was never visible.
* **Live, and the fix moved twice.** Compact mode resized the *scene* on the first attempt and left
  the window at 593x600 whenever a track was playing — `status_onchange` lands five times a second
  and cancels the click's task after its render (W88), so the present that carried the resize never
  happened while the overrides that carried the compact layout already had. The size had to move
  into the uncancellable half of the transaction, beside the host commands (W113). **A live QA pass
  with playback running is a different test from one without**, and this is the second defect in
  this engine that only appears in the first.

**What the sweep said, in three rounds.** Every engine change here went through
`scripts/wmp_render_sweep.sh`, and it rejected two versions of one rule before accepting the third:

| round | change | images |
|---|---|---|
| 1 | scripted view size + tween deferral | 443 identical, 92 differing, **10 lost** |
| 2 | …with `ownAuthoredSize` kept at the markup's | 500 identical, 35 differing, 0 lost |
| 3 | override-aware `fontSize` + the ascent floor | 393 identical, 142 differing, 0 lost, **no view row changed at all** |
| 4 | `sourceURL` + `bitRate` | 532 identical, **3 differing**, 0 lost |

Round 1's ten losses were `LostPlanet/infoView` shattering and the `mediaSwitcherView` class; round
3 changed 142 images and not one node, command, hit or widget count, which is what a pure text-metrics
change should look like. Round 4's three are skins whose readouts came back: `Thomas/main` draws
`0 kbps` and `0%` where a dead handler used to leave blanks. Corpus totals across the whole session:
nodes 11,284 → **11,972**, commands 9,459 → **10,049**, hits 3,996 → **4,248**, widgets 1,650 →
**2,259**, unresolved 2,210 → **1,067**.

**And a fifth, on a follow-up report, that no sweep here can see.** "When you mouse over the compact
button there is a huge overlay" is a `BUTTONGROUP` whose `hoverImage` is the whole 593x600 player
and which authors no normal `image`, so the sheet was painted unmasked over the window (W116).
`scripts/wmp_render_sweep.sh compare` across that fix is **535 identical, 0 differing** — a
default-state capture never enters a hover or a down state, which is W73 stated as a number.
`WMP_RENDER_HOVER` and `WMP_RENDER_CLICK` are the instruments for it, and a live hover is what found
it. **Read a byte-identical sweep across an interaction-state change as "unmeasured", never as
"unchanged".**

**What it does not close.** `<controls>` (103 nodes / 67 skins) and `<VIDEOSETTINGS>` (28 / 24) are
still counted as unresolved and are objects rather than controls — phantom rows in `starved.tsv`
that cost no pixels. `currentPositionText`, `durationText`, `statusText` and `automenu` are unknown
tags in the same shape. See `WMP_TASKS.md`.

---

## After W37 (179-archive corpus, 2026-09-08)

One host object, `mediacenter`, and the reason it is worth its own section is what closing the
biggest row on the page does to the rest of the page.

**Method, and the part that was most of the work.** The tree already carried unrelated uncommitted
changes, so a baseline against `HEAD` would have measured those too. The baseline is a
`git worktree` holding **the same working tree with only this change reverted** — the four files
that were clean before restored from `HEAD`, and the one hunk in a file that was already dirty
removed by hand. A fresh worktree also needs `Frameworks/` and the framework bundles staged into
`.build/<triple>/debug/` before `swift test` can even load the test bundle; without them the capture
writes an empty `raw.txt` that diffs as "every skin regressed".

| | baseline | with `mediacenter` |
|---|---|---|
| `Can't find variable: mediacenter` | **159**, across **110 skins** | **0** |
| runtime member errors, all causes | 252 | **127** |
| skins carrying a dead handler | 119 | **70** |
| distinct causes | 41 | **55** |
| views dumped / failed | 669 / 62 | 669 / 62 (unchanged) |
| images | — | **490 identical, 55 differing, 0 lost, 0 new** |

**Distinct causes went up, and that is the instrument working.** Rule 2 in
`reference/object-model.md` — "unimplemented is a queue, not a set" — is visible here as a number for
the first time: handlers that used to die on their first `mediacenter` line now run to their
*second* missing member. `alphaBlendTo` went 18 → 26 skins and is now the largest row in the backlog;
`player.dvd`, `eq.bypass` and three cross-view element names are new. **Never read a fall in one row
as progress without re-measuring the rest of the table in the same capture.**

**The 55 differing images were looked at, not counted**, and they split three ways:

* **Gained.** `WALL-E/mainView` went from a blank frame to its **entire artwork**; a dozen
  `videoView`s gained content their `OnLoad` sets.
* **Lost, and correct.** `Gorillaz/noodle` ends its `OnLoad` with
  `screen.visible = video.visible = effects.visible = false`, and the Rave-MP and
  Back-to-the-Future drawers close because nothing is playing. A script that finally runs is a
  script that finally hides things, which is what WMP does. This is the same finding as Phase 3's
  `Grinch/view-2`, and it means **net ink is not a quality signal**: this change is −15,152 px
  overall and every one of those losses is right.
* **Lost, and a different row's fault.** `Plus! Professional/videoView` lost its right drawer tab,
  and the cause is W76: `loadVidPrefs` tests `theme.loadPreference('vidRightDrawer') != '--'`, an
  unset key answers `''`, and the inverted sentinel closes the drawer. W37 closing is what turned
  W76 from two expressions in one skin into drawn pixels. **When a sweep loses pixels, find the
  statement that hid them before filing the change that ran it.**

A useful cheap instrument for the third case: count non-transparent pixels per differing PNG and
sort. It separates "gained a background" from "hid a pane" in one pass and points at the handful
worth opening.
