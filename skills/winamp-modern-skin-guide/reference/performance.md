# Frame budget and repaint cost

Reference for the `winamp-modern-skin-guide` skill.

#### The frame budget: what repaints, and what it costs

A `.wal` scene is laid out in **skin pixels** and drawn through a scaled CTM — ×2 on Retina, more at
a larger UI Size. Two consequences dominate everything else about how this window performs, and
neither announces itself: a stutter, a lagging meter or a "heavy" UI is what you actually see.

1. **Nothing may resample the same artwork twice.** `CGContext.draw` re-filtered every bitmap in the
   window to the backing scale on *every frame*. Measured on Defix at 2×: 18.3 ms a frame, 6.7 of it
   in unnamed layers and 3.7 in the layout's own background. `WasabiSceneRenderer` now keeps each
   image pre-scaled at the size the context will put it on screen, so the per-frame draw is a blit —
   3.5 ms, with pixels identical to before (the same `.high` resample, kept rather than repeated).
   Crops are cached too: `CGImage.cropping(to:)` allocates a *fresh* image per call, so a bitmap-font
   glyph or an animation frame had a new identity every frame and missed every cache keyed on it.
2. **Only what moved may be invalidated.** A single `needsDisplay = true` on a periodic path silently
   defeats every targeted repaint in the window. The one that caused Defix's choppy cassette was
   `updateTime`, which runs at the audio engine's 10 Hz clock: three full-window repaints for every
   ten frames of a 30 Hz animation, on the same thread. The rule is that a periodic update names its
   own rects — `updateTime` the objects the renderer draws from `host.currentTime` (a
   `display="time"` readout, a `seek` slider, a seek `progressgrid`), `updateSpectrum` the `<vis>`
   and `<eqvis>` boxes, the animation clock the animating and FX rects. A readout a *script*
   maintains is not in any of those sets and does not need to be: it repaints through
   `graphDidMutate` when the script writes it, which is when it changes.

Everything derived from the scene is cached and dropped together (`invalidateRectCaches`), and the
renderer memoizes its scene walk against the graph's own `mutationGeneration`. A node's **geometry**
is a function of the graph; its **bitmap** is not — play/pause artwork, the shuffle and repeat lamps,
the EQ buttons and every `cfgattrib` switch are resolved from the host and the config store, so a
memoized node has its image re-resolved on the way out.

#### The visualization has a clock of its own, because the audio's rate is not a frame rate (B51)

The `<vis>` boxes used to repaint only when a spectrum notification arrived. That sounds like the
right beat and is not: `AudioEngine` taps `mixerNode` with a **2048-frame buffer**, so one arrives
about every 46 ms and everything in a `<vis>` moved at **21 fps** however fast the display ran. The
1/60 throttle in `updateSpectrum` never had anything to throttle.

`WinampModernMainView` now runs its own clock, invalidating **only the vis rects**:

- **60 Hz when a `mode="2"` box is on screen** — the scope has a genuinely new 576-sample chunk every
  13 ms, and below 60 the trace visibly steps.
- **30 Hz otherwise.** An analyzer's bands only change at the FFT's ~21 Hz; frames past 30 animate
  nothing but falloff between two identical sets of bars.
- **No repaints while the window is occluded**; the timer keeps running (~0.5%) so the idle check
  still retires it.
- **It stops itself** once the audio is quiet and no bar or cap is still falling, so an idle player
  pays nothing — stricter than the old path, which re-entered on every notification.

**What that costs, measured** (`sample`, Big Bento Modern, playing, scope visible): a vis-rect repaint
is ~4 ms, so 60 Hz is ~16–24% of a core against ~8% at 21 fps. Drawing the scope itself is **7 samples
out of 3744** — the visualization is never the cost; what the repaint drags with it is.

And what it dragged with it named a bigger problem, fixed as **B52** below: in the same trace
`layout()` was ~10% of a core, **345 of its 369 samples in `browserNodes()` → `layoutNodes()` →
`append`**. The general rule it taught: before spending frames, check whether the frame is expensive
because of what you are drawing or because a cache upstream is never surviving.

#### A cache nobody trusted: 460 discarded scenes a second (B52, 2026-08-26)

The memoized scene and layout walks were being thrown away ~460 times a second on Big Bento Modern
while a track played. The report blamed `mutationGeneration` — something must be bumping it every
frame — and that was the smaller half. `WINAMP_MODERN_MUTATION_TRACE=1`, which prints writes **and
re-solves** in the same line, found two mechanisms and neither was a script writing per frame:

1. **`tickTargetAnimation` notified on every tick.** The target animation (`setTargetA` +
   `gotoTarget`) runs at 60 Hz per animating object and called `notifyGraphDidMutate()` each time —
   a whole-window `needsLayout` + `needsDisplay` — **whether or not the tick changed anything.** It
   writes rounded integers, so most ticks of a slow fade write the value the object already has.
   Big Bento rotates 17 `Bento:InfoLine` rows through a target-alpha fade that never stops while a
   track is loaded, so the skin sits in that state permanently. It now notifies only when a write
   landed, and an **alpha-only** tick takes the object-targeted repaint seam
   (`requestRepaint(for:)`) instead of a relayout.
2. **`invalidateRectCaches()` dropped the renderer's scene by hand**, on every notification, times
   every container window the notification fans out to — plus `updateAnimationTimer()` on the way
   past. That cache is keyed on the graph's own generation: a mutation invalidates it *without being
   told*, and a non-mutation must not. The drop is gone; the inputs the generation genuinely cannot
   see keep explicit calls (layout switch, resize, theme, playback state, UI Size).

Alongside them, `alpha` was given its own exemption. `append` reads it only as `inheritedAlpha`, the
multiplier handed down the tree, so it moves `mutationGeneration` but not **`sceneGeneration`**, and
`sceneNodes()` re-resolves the product over the cached nodes on the way out — the same trick
`withRefreshedBitmapID` already used for host-resolved artwork. Anything else that stops moving that
counter has to be provably invisible to `append`: `visible` decides membership, `image` and `text`
can size an object, and an unrecognised attribute is not assumed harmless.

Measured with `sample`, Big Bento Modern playing with the **scope** visible (`drawOscilloscope`
non-zero, which is the check that it was not the analyzer — two different clocks):

| main thread | before | after |
|---|---|---|
| `WinampModernMainView.layout()` | 9.9% | 1.3% |
| its `layoutNodes()` → `append` re-solve | 9.2% | 0.9% |

`renderer.draw` is untouched by this and is now the largest cost in the window — that is B51's vis
clock repainting, not a cache miss.

#### Profile the process, don't reason about the frame (2026-08-24)

`WINAMP_MODERN_RENDER_TIME` measures **`renderer.draw` and nothing else**. A report of "1–2 fps" was
chased through the draw path twice before anyone sampled the app, and the two largest costs were not
in `draw` at all. One command answers it:

```sh
sample $(pgrep -f '.build/arm64-apple-macosx/debug/NullPlayer') 6 -file /tmp/np-sample.txt
```

Read the **Main Thread** tree, aggregate the `(in NullPlayer)` frames by subtree cost, and note the
idle share: the profile that named these two showed the app **43% busy**, which is already the answer
to "is it CPU-bound?" — it was not, and the remaining question was why each repaint cost so much.
Two full graph walks were hiding in plain sight:

- **`WasabiObjectGraph.objects(xmlID:)` scanned every object and sorted the result, per call.** It is
  on the playback tick (`updateTime` looks up `HiddenVolume`), so on a skin with a few thousand
  objects it was ~10% of the app's entire busy time in one lookup. Now a lazily built id index,
  dropped in `makeObject`, `discardSubtree`, and on a script writing `id`.
- **`layoutNodes()` had no cache**, and `resolvedGeometry(of:)` goes through it — which is what
  answers every `getWidth`/`getLeft`/`getGuiW` a script asks. One event reading its own layout a few
  dozen times walked the whole graph a few dozen times, and `browserNodes()` re-walked it on every
  `layout()` pass on top. Now memoized on the same generation+canvas key `sceneNodes()` uses, and
  cleared with it in `invalidateSceneCache()`.

#### Four ways to pay full price for nothing (Big Bento Modern, 2026-08-24)

Measured at `RENDER_TIME_SCALE=2` on Big Bento Modern's main window: **238 ms/frame → 37 ms/frame**.
Each of these is a general renderer defect that one heavy skin made visible.

| Fix | ms/frame |
|---|---|
| before | 238 |
| skip fully-transparent draws | 146 |
| prescale cap large enough for window-sized art | 37 |
| native tiling; spectrum bounded to the display rate | 37 |

1. **`alpha="0"` was drawn, not skipped.** The renderer set `alpha(0)` on the context and composited
   anyway. Big Bento lays `<layer id="player.resizer.disable" move="1" alpha="0">` over its **entire**
   1526×868 window as a mousetrap: that one invisible layer cost **42.8 ms/frame**, and `focus.dummy`
   another **42.0**. `draw(_:in:pressed:hovered:)` now returns early when the effective alpha
   (object × inherited) is zero. Alpha is read per frame, so an object fading in resumes drawing the
   moment it is no longer transparent.
2. **The prescale cache had a cap smaller than a window.** `maximumPrescaledPixels` was 4 M px; a
   full-window background at 2× is 5.3 M, so the entries that matter most missed the cache and were
   `.high`-resampled *every frame*. `grid#-` went 60.5 → 7.0 ms, `two.frame.2.center` 30.4 → 2.2. The
   cap is now 16.7 M (4096², a window at 4× UI Size) and the total budget 25 M px (~100 MB). **Both
   numbers are a memory/time trade, not a constant of nature** — at 50 M it measured 34 ms instead of
   37, which was not judged worth another 100 MB.
3. **`drawTiled` blitted one tile at a time**, up to 8192 `drawImage` calls per frame. It is now a
   single `CGContext.draw(_:in:byTiling:)`; the tiling axes are chosen by the size of the rect handed
   to it, so an axis that should *stretch* gets the frame's full extent and its repeats fall outside
   the clip. **The y-flip has to be applied here too** — tiling straight through drew every tiled
   background upside down across 20 corpus skins, which the sweep caught and nothing else would have.
4. **`updateSpectrum` ran at the audio block rate (~75 Hz).** Every delivery that invalidates a box
   costs a scene traversal, because `draw(_:)` repaints the whole tree clipped to the dirty rect. Big
   Bento shows **six** `<vis>` boxes once its player pane is wide enough, so the moment its splitter
   became draggable the analyzer began asking for 75 repaints a second of a 238 ms scene. Now bounded
   to 60 Hz; a frame the display was never going to show costs nothing to drop.

**Still the biggest thing inside `draw`, and unfixed:** text. `drawText` was 339 of 1148 draw samples,
with `WasabiResourceCache.font(identifier:size:traits:)` alone at 96 — an `NSAttributedString`
attribute dictionary is built and `NSString.draw` entered per string, per frame, and the embedded
playlist does it per row.

**Sweep note:** the tiling rewrite leaves 12 of 288 corpus images differing by **maxdelta = 1** — one
LSB, from a single native tiling pass rounding differently than N individually-rounded blits. Diff in
RGB and check the magnitude before calling that a regression.

The main thread still carries what genuinely belongs to it: MAKI timer ticks and the interpreter (the
VM and the graph are single-threaded by construction), and the warp's pixel loop inside `draw`
(~1.9 ms for Defix's two 264×264 reels). Both are measured, bounded and, at 30 Hz, comfortably inside
the frame. What is *not* allowed there is arithmetic that could have happened elsewhere:
`WinampModernLevelMeter` and `PeppyMeterLevelModel` both measure on the audio-posting thread and hop
two doubles, and the FX mesh is evaluated by the animation clock before it invalidates rather than by
the paint that follows.

