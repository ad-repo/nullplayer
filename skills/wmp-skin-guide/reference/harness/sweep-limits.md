# `.wmz` harness: what a sweep or dump cannot see

Moved verbatim from `reference/harness.md` on 2026-09-25; that file is the router. Read it first.

### A sweep draws each view once, so it cannot see a per-frame cost

**W155 is the worked case and it cost a live session.** W154 gave every `<BUTTONGROUP>`'s base sheet
a mapping mask; the render sweep said 125 views changed, every structural invariant byte-identical,
and every changed view reviewed as an improvement. All of that was true, and the change still made
the app unusable — because `WMPRenderer` rebuilt the derived mask **per draw**, and a sweep renders
each view exactly once. The second frame is where the cost lives and the sweep never draws one.

The instrument that could see it is `sample` on the running app, and the reading that matters is
*which* thread:

```bash
sample $(pgrep -f "debug/NullPlayer$") 5 -f /tmp/hang.txt
```

**The main thread was idle** — 3513 of 3565 samples in `mach_msg` — while six
`com.apple.root.user-initiated-qos.cooperative` threads sat at 3565/3565 with one symbol at 3510 of
them. `WMPRenderer` runs off-main by design, so a renderer this expensive does not block the UI
thread: it **starves the cooperative pool**, and everything else awaiting that pool stalls behind
it. Reported as the app stuttering and hanging; a main-thread trace would have exonerated the
renderer and sent the search somewhere else entirely. Count the outermost occurrence of a symbol,
never the sum across frames — see the `sample` aggregation rule.

Whenever a change makes work happen on **more** commands, more nodes or more often, the sweep's
green is about correctness only. Time a repeated render of one heavy view before believing it is
free: twenty renders after a warm pass took 173.1 ms each before the cache and 0.3 ms after.

### A dump cannot see a **tween** at all, at any clock (W194)

`WMP_RENDER_CLOCK` pins the *animation* clock — GIF frames — and a tween is not on it. A
`moveTo`/`resizeTo`/`alphaBlendTo` duration animates only for a caller that passes
`animatesTweens`, and every headless path here deliberately does not: a dump, a census sweep and the
windowless dispatcher all get the endpoint applied at the handler boundary and the completion raised
in the same transaction, exactly as before that row. **That is the point** — it is what keeps every
number on this page valid across the change — but it means no capture, at any clock value, can tell
a skin that slides from one that jumps. Drive the running app; `Compact`'s drawers are the case.
`Tests/NullPlayerAppTests/WMPTweenTests.swift` is where the motion itself is falsifiable, because
the runtime's frame step can be called directly.

### A dump cannot see *when* a GIF was entered, and `WMP_RENDER_CLOCK` cannot either

`WMP_RENDER_CLOCK` is what makes an animation falsifiable at all, and it still answers only "what is
drawn at the clock I named". The question it cannot take is whether the engine handed that GIF the
right clock in the first place — which is a whole defect class, because `animationClock` is per
**view** and a skin that assigns a `backgroundImage` GIF from script enters it at whatever the view's
clock already reads (**W182**).

`AlienMorph` is the worked case. Its scene is correct at every settle value — `WMP_RENDER_SETTLE` at
1, 3, 5 and 8s all hold `m_anim_shutter_open.gif`, the view timer does not re-fire — and the
animation still plays from 1.1s in, or not at all, depending on whether anything animated in that
view first. Every instrument on this page reports it healthy.

**Drive the app and measure the span of motion**, not the frames: screen-capture the window's rect
in a tight loop, diff consecutive crops of the animated region, and read the first and last interval
above the noise floor. A full run and a truncated one are 9.80s against 1.73s and unmistakable.
Matching a capture back to a GIF frame index is the tempting version and it misreports — the closing
shutter's last dozen frames are visually identical, so a run that had plainly animated came back as
"frame 91 throughout". The recipe is in `reference/skins/alienmorph.md` § *How to drive it*.

**Closed as W182 on 2026-09-15** — the clock is now per slot (node + resource), and an empty slot
table still renders at the scene clock, which is why every flag on this page is unaffected. The
section stays because the *method* is the reusable part: a timing defect is invisible to everything
here, and the before/after that settles one is a motion span off the running app.

`WMP_ANIM_TRACE=1` is next to this and answers a different question — the rate the loop *achieved*
once it was running (`want=25.0fps got=24.1fps … restarts=1`). It says nothing about which frame the
loop started on, and a truncated animation traces as a perfectly healthy one.

### A sweep runs a stopped player, and a skin can be correct only while stopped

W166 is the worked example and it is the sharpest form of the rule above. `Colorchooser`'s
`checkForContent()` reorders its scene from `playstatechange`, so the defect — an opaque panel
reclassified as artwork over a windowed visualizer, and punched out of a non-opaque window as a
click-through hole — exists **only while a track is playing**. The corpus sweep draws every one of
its 535 images against the default stopped host, which is the one state in which that skin is right.
A clean sweep said nothing at all about it, and would have said the same after the fix.

**`WMP_RENDER_HOST=playing` is not the escape hatch it looks like.** It seeds the snapshot, so every
readout bound to a transport path answers as if a track were open — but it does not raise the
skin's `playstatechange`, and that is where the write lives. The headless capture rendered the panel
correctly while the running window did not, and the gap between those two is what named the cause.

So: **a defect the reporter describes with a verb — *when a track plays*, *after I click*, *once it
opens* — is a live measurement**, and the sweep's role is only to say that nothing else moved.
`NULLPLAYER_PLAY` plus `screencapture` of the window is the instrument; see `harness/live-loop.md` § *Driving the app*.

### A named skin outranks a corpus sweep

The same report was unfalsifiable until the reporter named one: *"catwoman skin is not fixed"*. A
seeded corpus sweep had already said **88 of the 89 archives that author the elapsed binding draw the
right string**, which is a true measurement and was the wrong question — Catwoman authors no
`currentPositionString` anywhere. Its clock is four digit filmstrips positioned by
`value_onchange="drawSeekDigits(value)"` off a `<CUSTOMSLIDER>` whose value nothing bound, so the
whole readout lived in two mechanisms the sweep was not looking at. **Ask for a skin name before
sweeping**, then read that skin's `.wms` — the markup says what the readout is made of, and the two
defects behind it (W120, W51) were both visible in a single 200-character tag.

### The residue `WMP_RENDER_OCCLUDED` does not explain (W149)

Reproduce with `WMP_SKIN=<corpus> WMP_RENDER_HOST=playing WMP_RENDER_OCCLUDED=1` and read the
`reached=rect-only` lines. **W149 closed every row it named as not a defect** (2026-09-24, 10 rows in
4 archives; `STALKER`'s `blankRate4` had already gone). **The probe tests the load-time layout,
before any script has moved, clipped or swapped a node**, so a `rect-only` row is a question, not a
lost control. Before ranking one, rule out the four shapes W149 found:

- **A closed drawer.** `Sports`' `eq2`–`eq8` sit in `EqVid`, parked behind the main panel under
  `pl2`–`pl4`; `ToggleEqVidView()` moves it clear. Read the container's `moveto` targets.
- **A stacked twin running the same handler.** `anime`'s `plHandle`/`closepl` share a frame and both
  run `togglePlView()`; whichever is on top answers and the click does the same thing.
- **A `<BUTTONGROUP>` container whose element still answers.** `Plus! Professional`'s pause group:
  `WMP_RENDER_CLICK` at its centre reaches the `pauseElement`, `action=pause`. A group with no
  element of its own dispatches nothing however it is ranked.
- **A clipped sprite frame.** `T3-Skynet_Media_Player`'s `timeSign` is a 168-wide strip shown
  through a 14x15 cell; outside the cell it is `clipped`, and inside it the elapsed-time frame is
  all transparency colour, so `not-drawn-here` is right.

Confirm with `WMP_RENDER_CLICK` at the control's drawn pixels and read `hit=`/`refused=`. **Name the
node before ranking the count**, the same rule this file states for `unresolved`.

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

### Two hosted-frame fixtures that differ only in pixels are the same skin

`WMPHostedFrameTemplate` is `Equatable` and `WMPHostedFrameProvider.configure(skin:playerViewID:)`
short-circuits on an equal one — `if derived == template, builder != nil { return }` — because a
re-presentation of the skin already loaded must not throw its cache away. A template is identified
by the **node ids** it names, so two test fixtures that differ only in their corner geometry and
their bitmaps derive the *same* template: `configure` returns true, nothing is reset, and the
provider answers the first skin's cached frame. The first draft of `WMPHostedFrameTransitionTests`
did exactly this and failed as *"the new skin's frame never replaced the one held over"*, which
reads like a defect in the code under test and is a defect in the fixture. **A fixture that has to
be a different skin must rename its nodes**, and a test that turns on a skin *change* should assert
the change happened — the incoming frame's `CGImage` is not the outgoing one — rather than trusting
`configure` to have done it. `SkinnedSurfaceFrameArtwork` compares its image by identity, so that
assertion is available and cheap.

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

### `gaps=` cannot see a hosted frame that is wrong everywhere but its edges

`HOSTED-FRAME`'s `gaps=` is the longest unbroken **bare** run in a 6pt band at each of the four
edges. Two things follow, and both were learned the expensive way on 2026-09-17.

- **It cannot see anything further in than 6pt.** `Alienware Invader` read
  `gaps=0.000/0.000/0.000/0.000` at 472x290 while the window on screen carried three white blocks and
  a 54pt opaque column over its content (W212, closed 2026-09-17). A clean `gaps=` is not a clean
  frame — and the mirror holds: `gaps=` was the *only* field that could see the bare band down the
  same skin's rails, which the same fix closed, so neither reading substitutes for the other.
- **Bare means transparent, and a PNG viewer draws transparent and opaque white identically.** This
  donor's border bitmaps carry its interior colour baked in — `f_top_right.png` is a silver band over
  opaque `(255,255,255,255)` — so `WMP_HOSTED_FRAME_DUMP`'s picture looked like a frame full of holes
  and was a frame full of white paint. Two diagnoses were drawn from the picture and both were wrong;
  the third came off the alpha *and* off a node-by-node trace of what the frame build actually drew,
  and found a tile 117pt from where the skin's own window puts it. Read the alpha:

```bash
python3 -c "
from PIL import Image
im=Image.open('/tmp/f/plView-frame.png').convert('RGBA')
print(im.getpixel((950,40)))   # (255,255,255,255) is paint; (0,0,0,0) is a hole
"
```

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

**A fix that resolves the report and moves things outside it has raised a question, not answered
one.** Here the answer was "wrong fix"; in W143 below it was "right fix, reaching every skin that
needed it". The baseline is the engine's own previous guess, not WMP, so neither reading is the
default — `skin-subsystem-blueprint` § *A sweep diff is unclassified, not a regression* is the method.
Sweep before believing a fix, not only before believing a refactor — and read the `RENDER-DUMP`
counts in the invariants diff, not just the image count: `33 commands / 15 hits → 28 / 8` named the
regressed view before any PNG was opened.

**W143 moved 139 of 535 and was right.** The two are distinguishable without taste, by two things
measured in the same
capture. First, **the invariants**: W87's collateral announced itself as changed `RENDER-DUMP`
counts, and W143's 514 changed invariant lines are *entirely* `loadms` timings and `SCRIPT inline:`
tie-ordering — no view gained or lost a node, command, hit target or canvas, so nothing stopped
resolving and nothing started. A wide image diff with a still invariants diff is a layout rule
reaching everything that authored it. **Both of those noise sources were removed on 2026-09-19, so
a capture taken today cannot produce W143's 514 lines at all**; the rule survives, its reading does
not — see *A sweep has one nondeterministic output* below. Second, **sample across skins unrelated to the report and to
each other, and open them side by side** — ten of the 139, and each one had to be a repair on its own
evidence (a badge centred under its own pointer arrow, a clipped readout made whole, a frame that
had been half its window's width). "Every one I opened looks better" is the claim to make, and it is
only worth anything if the ten were chosen before they were looked at. Neither check is the PNG
count, and the count is what both fixes have in common.

### A sweep has one nondeterministic output, and it is an image

Measured 2026-09-14 by capturing the **same build twice** and comparing the pair — which is the
cheap move that turns "my change did this" into "the harness does this", and costs one 45-second
capture.

- **`Scooby-Doo_2/infoView` differs run to run.** Its `loadInfoPrefs` calls `randomPic()`, which is
  `parseInt(Math.random() * 10)` over five character PNGs. It is the only image in the 535 that
  moves on its own, and it will read as collateral damage from whatever you just changed.
  **Still the only one at 553 images (W241, 2026-09-20)**, where it cost a round of investigation
  anyway: the confirmation is one capture of the *same* tree twice, and it is faster than reasoning
  about why the change could have reached that view.
- **The invariants half used to be mostly noise and is not any more, as of 2026-09-19
  (`d72c3970`).** A no-op change reported hundreds of "changed lines" that were entirely `loadms`
  timings and `SCRIPT inline:` tally **ordering** — the same counts printed in a different sequence,
  from unstable dictionary iteration. Both are fixed: `loadms=` is stripped when `invariants.txt` is
  written (it stays in `raw.txt`/`render.txt`, where the census's per-skin `LOAD` parse reads it,
  and `compare` strips it from both sides so an older baseline is still usable), and the tally
  breaks ties on the name. **Two captures of one unchanged binary now differ by 2 lines**, both the
  `HARNESS` line naming the output directory. A changed invariant line is now evidence.

  Two consequences. **A capture taken before that commit diffs ~39 `SCRIPT inline:` lines against
  any capture taken after it** — a one-time reordering into the new canonical order, not a
  regression. And **the old advice was the wrong half of the problem**: "read the counts, never the
  line total" is how a real regression hides in 500 lines of noise. Read the line total now.

**Predict the diff before running the compare.** For W162 the prediction was "7 archives, the ones
with a markup `wmpprop:player.status` binding"; the answer was 14, and the extra 7 were skins whose
`onLoad` reaches a metadata updater. A prediction that is wrong in the *smaller* direction is
information; being unable to predict at all means the change's reach was never measured.

### Attributing a live report to the change in front of you

**Build a baseline worktree at the parent commit before attributing a live report to your change.**
Three reports on 2026-09-09 were assumed to be W55's and behaved identically at the parent; it cost
one build and moved all three out of that change's ledger.

**A NullPlayer surface wearing a borrowed `.wmz` ring is not the scene, and no scene probe reaches
it.** W177-W179 were reported together on 2026-09-15 and all three closed by 2026-09-19. None was
reachable from `WMP_RENDER_APPKIT`, which measures a skin's *own* views against their scene. W179's
evidence was a `WMP_HOSTED_FRAME` line, a `WMP_HOSTED_FRAME_DUMP` PNG and a capture of the live
library window, **in that order**. Two of its lessons outlived it and are in `SKILL.md`: the ring a
window wears is chosen per *view*, so a defect in the bottom bar can be a defect in donor selection
two steps upstream; and a row's own starting instruction can be stale — W179's named the client
hole, which was already correct. **Re-drive a screen-only row before taking it.**

### A baseline worktree needs the vendored frameworks linked in

**Use `scripts/baseline_worktree.sh [<dir>] [<rev>]`** (defaults `../nullplayer-base`, `HEAD`). It
creates or re-points the worktree, links every `Frameworks/` entry git does not carry, mirrors the
build products the test bundle loads from beside itself, and refuses to finish unless
`git status -- Sources Tests scripts` is clean. The traps it encodes are in its header comment:
`Frameworks/` is only partly tracked, so a fresh worktree fails `no such module 'VLCKit'`; once it
links it dies in `dlopen` because the test bundle's rpath looks beside itself; and **linking the
directory rather than its entries** either lands inside the tracked one as `Frameworks/Frameworks`
or deletes twelve tracked files so `capture` refuses the tree — which reads as a capture that will
not start rather than as a link done wrong (measured 2026-09-21 capturing W216's baseline).

Whether a capture then needs `--allow-dirty` depends on the clone's ignore rules — `.gitignore`'s
`Frameworks/VLCKit.framework/` matches a directory, not the symlink, so the link reads as untracked
unless `.git/info/exclude` covers `Frameworks/` — and the script prints which, listing whatever makes
the tree dirty. When it is needed it is safe **for the baseline worktree only** — the untracked
thing making it dirty is a symlink to a framework. Never pass it to hide real edits.
