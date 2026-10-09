# `.wmz` harness: trusting the instrument

Moved verbatim from `reference/harness.md` on 2026-09-25; that file is the router. Read it first.

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
nothing; reading order out of an `.optionAll` list said the video was in front when it was behind. `winhelper capture` is the checked form of
`-l`, and `winhelper windows` already passes `.optionOnScreenOnly`.

**A parked video window is a child window, so two invariants are free and worth asserting**: a child
is always drawn above its parent, and it moves with its parent atomically. If the picture is behind
the skin, or trails a drag, the parent-child link is gone — do not go looking at VLC. See
`reference/rendering/video.md` § the `.wmz` video loan.

## Why an instrument gap outranks a skin-side defect

**Manual testing does not scale to this corpus.** 179 skins times sliders, drawers, drags and
animation is not a human-scale job, and Phase 5 shipped its AppKit half unmeasured for exactly that
reason. So **a genuine gap in instrument reach ranks above a skin-side defect when one is found** —
and a probe that reports work already done is a gap in reach exactly as a missing probe is. That is
how a row is ranked in `WMP_TASKS.md`: an instrument gap goes above the skin-side rows, not among them.

## Numbers that are void, and why

A stale number copied forward reads as fresh, and this corpus has produced five classes of number
that must not be scaled, quoted or re-derived. Re-measure instead.

* **Anything measured against the 14-skin denominator.** The corpus grew to 180 on 2026-09-07 and
  none of the earlier numbers were rewritten in place. A count without an archive stamp has not been
  re-measured; re-measure it rather than scaling it.
* **Anything captured before rev `61f8955a`.** The instrument dropped three blocks of its own output
  (W35), so an earlier count is short by an unknown amount rather than merely stale. The distinct-name
  count of the `UNKNOWN event` vocabulary is the visible symptom: **36 blocks were damaged in both
  captures**, so the *edges* of that vocabulary move between runs and the uses figure is the one to
  quote.
* **Any `COMPAT` / `UNKNOWN tag` number taken before 2026-09-19.** W215 closed that day: the corpus's
  unimplemented-tag demand read **1,197 uses and is 258**. Those counts are not merely stale, they
  are *inflated*, and the tags they inflated with were the transport pairs, `customslider` and
  `effects`. The member half of that row did not close and is the larger number now; see the archive.
* **Any view count of 579, 574, 567, 515, 508, 506 or 482.** Re-measured 2026-09-09 over 179
  archives.
* **Any coverage claim made from a sweep `compare` before 2026-09-20.** W245 closed that day: the
  damage detector was flagging **48 of 184 archives** as damaged on every run and `compare` leaves a
  damaged skin's lines out, so an invariants diff from before it saw three quarters of the corpus.
  The PNG comparison was never affected — only the lines.
* **`WMP0035` is harness noise, not a defect, and since W245 it is not a `RENDER-DUMP` line
  either.** Re-measured 2026-09-09: **62 `RENDER-DUMP … FAILED [WMP0035]`** across the 179-archive
  sweep, and every one is a view with no window — `controlView` ×25, `previewView` ×16,
  `mediaSwitcherView` ×12, `view-2` ×3, `versionView` ×3, and
  `vGhost`/`vGhostAutoDetect`/`playview` ×1. **The current number is 76 over 184 archives**
  (2026-09-20), and they print as **`PNG <view> FAILED [WMP0035]`**: the view reports its stats on
  its own `RENDER-DUMP` line and the refused *write* is a `PNG` outcome. Grep the old prefix and you
  will now count zero of them, which is a renamed line rather than a fixed class. That is the windowless class `SKILL.md` describes, whose
  honest size is `0x0` and which `WMPRenderer` correctly refuses; the 25 matches the 25 archives that
  author a `controlView` exactly. A FAILED line on a view that *does* have a canvas is still worth
  chasing. **`WMP0032` and `WMP0033` are both zero corpus-wide** (2026-09-09), so neither a layout
  rejection nor a decode failure can rank anything any more.

**There are no loading rejections left in the corpus.** Load level is a constant, so it cannot rank
anything: every open defect is a rendering or runtime one, and only a dumped PNG or a `SCRIPT-DIAG`
line can see one. A row whose evidence is a census column is by that fact measuring structure, not
result.

### What the ranking files rank, and what they do not

`starved.tsv` and `appkit.tsv` are produced by the census itself rather than by hand, and they
outrank any prose that disagrees. Measured 2026-09-08 over 179 archives and **607 views**: 41 starved
views across 36 skins, 79 with no hit target across 49, 75 drawing nothing across 45, and **two**
views painting outside a widget frame. **That last number is now zero** — both were `Revert`, both
closed 2026-09-19 as W74, re-measured over 184 archives / 629 views. `appkit.tsv` ranks nothing until
a new archive lands.

**`starved.tsv` ranks declared-but-unresolved nodes, not missing pixels, and the two are not the same
view.** Its top rows were opened on 2026-09-08: `Cablemusic/mainview` (ratio 0.64, 63 unresolved)
draws a nearly complete player, and `ALXMorph/mainView` draws its whole shell. A high ratio ranks a
view as *worth dumping*; only the PNG says whether anything is missing. **Dump the view before taking
the row.** The same session ruled out the explanation everyone reaches for first: geometry
expressions. Corpus-wide **7,569 of 7,569** reach the live evaluator, and `Cablemusic/mainview`
declares none at all — see `harness-history.md` § *After the cascade*.

**"Draws nothing" counts an authored blank the same as a starved one, and closing W75 moved it the
wrong way on purpose.** It was 65 views / 37 skins until a scripted `backgroundImage` started
reaching the scene; ten `mediaSwitcherView`s then began obeying their own `view.backgroundImage = ""`
collapse before redirecting, and a view that correctly draws nothing is indistinguishable from a
starved one in this tally. **Settle a `0 commands` view by reading its PNG before opening its
markup**, exactly as with `starved.tsv`.

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
| `HarnessOutputTests.testEmitsEveryLineWholeUnderConcurrentWriters` (the shared emitter's own file) | eight concurrent writers and 9 KB lines all arrive whole and exactly once — the emitter cannot splice or drop a measurement |
| `testAppKitProbeSeesAnOverlayAndReportsNothingWithoutOne` | `APPKIT` in both directions: a scene with nothing hosted over it diffs to **exactly zero**, and a scene carrying a `PLAYLIST` diffs inside that widget's frame and nowhere else. Without the first half, "no defect" and "blind instrument" print the same line |

`compare` was checked the same way on 2026-09-07: a one-pixel **colour-only** change (alpha
untouched) to one dumped PNG and a one-character change to one invariant line, each reported.

**Measuring an over-keyed artwork: key each bitmap against its own declared colour (W169).** The
instrument that found the largest defect this engine has had was not a probe flag and not the sweep.
For every node declaring both a `clippingImage` and a `clippingColor`, decode its artwork, count the
pixels matching that colour at the *format's* tolerance (64 components for a JPEG,
`WMPColorKey.jpegComponentTolerance`; exact otherwise), and report the share. It ranks the class in
one pass: `Plus! Plasma Ball/eq_panel_normal.jpg` 85.7%, `Plus! HueShifter/hueshifter_top.bmp` 76%,
`TDK/info_bg.jpg` 52.1%, `Plus! SlimLine/perfect_body_normal.jpg` 47.5%, `elvis/elvis_tray.jpg` 39%,
`Plus! Hard Boiled/Egg_Body_Normal.jpg` 27%. **A render dump shows the hole and names nothing**, and
the hole reads as bad artwork or a bad upscale — W160 spent a phase on the second reading. Reach for
this shape whenever a skin looks *degraded* rather than *misplaced*: ask what the engine is deleting
before asking how well it is resampling.

**Two capture traps, both paid for on 2026-09-14.**

* **A 1x render dump is not evidence about Retina sharpness.** The sweep captures at 1x by design,
  so a dump posted beside a reporter's 2x window capture is two different scales compared as if they
  were one — it sent a whole round of this report down a resampling path that had nothing wrong with
  it. For anything about crispness, capture the *same window frame* at 2x before and after, from a
  baseline built in a worktree (`scripts/baseline_worktree.sh`). `plus-family.md` says "never from a 1x render dump" and it means it.
* **`first process whose name is "NullPlayer"` picks the wrong window when two are running.** The
  user's own build is usually up, both restore the same window frame, and three captures in a row
  came back showing the stale one. Get the pid (`pgrep -n -f "uiMode wmp"`), then raise and query by
  `unix id`: `tell application "System Events" to set frontmost of (first process whose unix id is
  <pid>) to true`, read `{position, size}` of its `window 1`, and `screencapture -o -x -R` that rect.
  (`winhelper raise <pid>` and `winhelper capture <id> --pid <pid>` now do both, checked.)
  A bare-binary worktree build also needs `VLCKit.framework` and the vendored dylibs symlinked into
  `.build/arm64-apple-macosx/debug/` beside the binary, or dyld kills it on launch.

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

**The playback half is instrumented and the rest is not.** `WMP_RENDER_HOST` seeds a playing host
for a whole sweep and `NULLPLAYER_PLAY` starts a live debug launch on a track — that pair found W119
and W120, two defects in the one state every transport readout in the corpus is authored for and
that no capture had ever entered. **Read the `HOST` line of a capture before anything else in it.**
The AppKit overlay class is now measured and closed (545 hosted views, two defects, both W74, fixed
2026-09-19) and every slider in the corpus is drivable. What no sweep says anything about is still a
tab, a setting, a hover, a drawer, the window's shape and its shadow, and anything driven by live
playback; W69's flicker is in that remainder, which is why it needs its own instrumentation rather
than another sweep.

*(This paragraph and the one above it are what `WMP_TASKS.md`'s W73 carried as a backlog row. It was
moved to `LOW_QUALITY_TASKS.md` on 2026-09-19 because it was a permanently-open caveat rather than a
unit of work — the caveat is true, and this is where it belongs.)*

---
