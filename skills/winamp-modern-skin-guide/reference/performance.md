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

**Was the biggest thing inside `draw`:** text. `drawText` was 339 of 1148 draw samples, with
`WasabiResourceCache.font(identifier:size:traits:)` alone at 96 — an `NSAttributedString` attribute
dictionary was built and `NSString.draw` entered per string, per frame, and the embedded playlist did
it per row. The font lookup is fixed by B103 and the drawing by *The drawing half of `drawText`*
below.

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


#### Big Bento Modern's 30 ms frame is a *repaint*, not a frame rate (2026-09-02)

`WINAMP_MODERN_RENDER_TIME` reports **30.3 ms/frame** for `main/normal` at `RENDER_TIME_SCALE=2`
(10.5 at 1×), six times cPro Bento's. That number is real and it is not a performance problem, and
the difference is worth understanding before anyone spends a day on it — this section exists because
someone already did.

**The running app, in the same skin, is nearly idle.** Release build, playing, window frontmost and
unoccluded at 1400×850:

| main thread | |
|---|---:|
| busy | **23.7%** |
| `WinampModernMainView.draw` | 16.0% |
| `drawVisualization` (of which `drawAnalyzer` 3.7%) | 5.6% |
| `drawText` | 3.3% |
| `CGContextDrawImage` | **0.8%** |

`RENDER_TIME` draws the **whole scene** every iteration. The app does not: B51's vis clock and B52's
targeted invalidation mean a steady-state frame repaints the vis rects and the readouts, not 198
nodes. So the benchmark answers *"what does a full repaint cost?"* — the price of a resize, a layout
switch or a theme change — and the profiler answers *"is this thread the constraint?"*. They are
different questions and the second one is the one users feel. **Do not tune against `RENDER_TIME`
without sampling the app first.**

**What the full repaint is made of,** for when a resize does feel slow (headless, scale 2):
`CGContextDrawImage` **75%** — `ripc_` → `argb32`, plain CPU compositing — with `drawGrid` 30% of the
thread inside it, `drawText` 4.9%, and the pre-scale cache healthy at 1% (`prescaled` 1.08%,
`resized` 0.83%; it is not re-resampling anything).

Two things that make the arithmetic misleading:

- **Overdraw is 1.33×, not 4.3×.** Count every bitmap-bearing node and Big Bento appears to paint the
  window 4.31 times over, with three near-full-window background layers stacked. Eighteen of those
  nodes carry `alpha=0` — 2.98× of window area — and the renderer already skips them. Only nodes with
  `alpha > 0` are composited, and those come to **1.33×**. There is no occlusion problem to fix here.
- **Per-pixel cost varies ~25× between an opaque copy and a translucent blend**, so area is not a
  proxy for cost. `window.background.center` is a 10×6 crop stretched over 1526×845 and opaque:
  5.16 M device pixels in **1.57 ms** (~3.3 Gpx/s). `shade.left` is a 500×500 RGBA crop of
  `shades.png` drawn into 500×178 with real alpha: 356 K device pixels in **2.64 ms**
  (~135 Mpx/s). The five `shade.*` overlays are ~4% of the painted pixels and ~31% of the frame.

**A hypothesis worth recording because it was wrong:** the pre-scale cache flushes *entirely*
(`prescaledCache.removeAll()`) when `maximumPrescaledCachePixels` is exceeded, which looks exactly
like per-frame thrash on a window this size. Raising the budget 32× moved the frame from 30.28 ms to
**29.86 ms**. Not it — and one `sed` and one test run is what that cost to find out, against an
afternoon of reasoning.

**What is genuinely still redone per frame,** both found in the release profile and both *deliberately
not fixed* — they are the B103–B106 defect class but an order of magnitude smaller than the items
that pass reached, and the thread is 23.7% busy:

- `WasabiVisStyle.decode(attributes:color:)` — **1.71%**. The visualizer's style is parsed out of XML
  attributes on every frame.
- `WasabiTextMetrics.digitCell` — inside `clockRun`'s **1.25%**. It measures all ten digits with
  uncached `NSString.size(withAttributes:)` calls, per clock object, per frame. It is a `static func`,
  so it cannot reach the instance-level width memo B106 added.

One more was measured beside them and is a **visual decision rather than a free win**, which is why
it is recorded here and not scheduled: every blit runs through the **16-bit float** pipeline
(`ripc_DrawImage` → `RGBAf16_image` → `RGBAf16_sample_RGBAf_inner`, plus
`vCGCompositePixelShape_ARGB16F_vec`), ~7% on cPro Bento. Nothing in the app sets `contentsFormat`,
`colorSpace` or a depth limit, so that is the system default on a wide-gamut display. Skin art is
8-bit PNG and `RGBA8Uint` would be lossless *for the artwork* — but the renderer also synthesizes
gradients (`$gradient`), which could band. Measure and look at it before adopting.

Fixing both would plausibly move 23.7% to ~20%, which nobody can perceive. Take them if you are in
these files anyway; do not schedule them.

#### Profile the build the user runs (2026-09-01)

A cPro report — "the skins feel slower, low fps, not smooth" — was chased through five rounds of
optimization on a **debug** build. The first four found real defects; the fifth was chasing an
artifact, and the measurement that would have said so cost ten minutes and was run last.

Main-thread **busy** fraction, cPro Bento with the drawer visualization up and audio playing:

| build | busy | idle |
|---|---:|---:|
| debug, before | 98.6% | 1.4% |
| debug, after the fixes below | 94.4% | 5.6% |
| **release, same tree** | **60.7%** | **39.3%** |

The split that matters is **algorithmic vs. merely hot**. A table rebuilt per call, a `CharacterSet`
built per character, a CoreText pass re-answering a constant — the optimizer fixes none of those, and
they are worth fixing from a debug profile alone. Ordinary code executed often is the opposite: that
is where debug-vs-release decides whether there is a problem at all. Once the named defects are gone
and what is left is `draw` and the interpreter doing genuine work, **stop and measure release** before
spending another round.

Two instrument traps this session hit, both worth knowing:

- **`WINAMP_MODERN_VIS_STALL` is `#if DEBUG`.** A release run reports zero stalls whether or not any
  occurred. A silent instrument is "not running" until proven otherwise.
- **`sample` aggregation must not sum a recursive symbol.** Counting every frame that carries a name
  counts each level of a recursion separately: `append` read as **73%** of the main thread against a
  true **12.2%**, and `normalize` as 28.3% against 14.6%. Inclusive share counts only the *outermost*
  occurrence on each stack. Substring matching is unsafe for the same reason —
  `refreshWaveformDemand` also appears as `closure #4 in …` and `partial apply for closure #4 in …`
  on the same stack. The cross-build metric that does work is the busy fraction: leaf frames in
  `mach_msg2_trap` / `semaphore_wait` / `__psynch_cvwait` are idle, everything else is busy.

#### Five tables rebuilt per call (B103–B106, 2026-09-01)

All found by `sample` on cPro, whose graph — ClassicPro engine + CentroSUI + tabs + widgets + drawer —
is the corpus's largest. **None of the defects is cPro-specific; the reach is.** Each cost is per
object or per call, so the skin with the most objects is where an invisible cost becomes the profile.

| where | what | share |
|---|---|---:|
| `WinampModernScriptRuntime.signature(for:classGUID:)` | its 311-entry table was a **local**, rebuilt on every method invocation the interpreter makes; the class GUID was canonicalized five times in one call | 10.4% → 0.4% |
| `MakiClassGUID.canonical` | `index(_:offsetBy:)` from the start per byte pair, 16 substrings and a join: O(n²) and ~20 allocations for a 32-character constant | 5.1% → 0.3% |
| `WasabiTextMetrics.font` | cached the raw `CGFont` only, so `CTFontCreateWithGraphicsFont`, the trait conversion and the `NSFontManager`/CoreText descriptor match ran per string, per frame | 5.7% → 1.2% |
| `WalResourceRegistry.resolved` | `String.folding(options:locale:)` — a full ICU pass — per resource id, per frame, plus a `Set` allocated for a cycle guard most lookups never need | 3.4% → 0.6% |
| `WinampModernComponentRegistry.normalize` | built `CharacterSet(charactersIn:)` **inside** its filter closure, so CoreFoundation sorted a string and freed it once per character | 14.6% → 0.0% |
| `WinampModernConfiguration.safeComponent` | rebuilt `CharacterSet.alphanumerics.union(_:)` per call — that union materializes Unicode bitmap planes — twice per `storageKey`, one `storageKey` per config read | 2.5% → 0.2% |

**A `CharacterSet` built inside a frequently-called function is the recurring trap here** — two
independent instances in one profile. `CharacterSet.alphanumerics.union(_:)` and
`CharacterSet(charactersIn:)` are both allocating constructors, not constants.

Two structural fixes alongside them:

- **`refreshWaveformDemand` walked `allObjectsUnordered` twice**, asking `componentKind(of:)` about
  every object for two booleans. One pass answers both. With `surfaceID(of:)` now memoized on the
  object — dropped by `setAttribute` for the five attributes it reads, and stamped with a new graph
  `structureGeneration` so a reparent invalidates a subtree at once — the whole gate went
  **32.8% → 1.7%**.
- **`autoWidth(of:)` is reached from `append`**, so every `<text>` sized from its own content was
  measured with a full CoreText typesetting pass on every scene rebuild.
  `WasabiTextMetrics.measuredWidth(of:font:)` memoizes it. Applied only to the two sites that measure
  with exactly `[.font:]`, which is what makes the key provably complete.

#### The drawing half of `drawText` (2026-09-02)

Done, and it wanted the sweep rather than a careful reading — a careful reading got the vertical
arithmetic wrong twice.

Text now draws from **cached CoreText lines**. `WasabiTextMetrics.line(for:font:)` holds them beside
the B106 width memo, built **colourless** (`kCTForegroundColorFromContextAttributeName`) with the
colour set on the context, so a playlist row does not get one cached line per selection state. Three
of `drawText`'s four branches take it — ticker, clock cells, general non-wrapping — plus
`drawFlippedText`, the per-row playlist path. Ahead of that, four tables that were rebuilt per call
became memos or `static let`s: the attribute dictionary (keyed on font, colour, alignment and
line-break mode), `drawBitmapText`'s glyph table, the two clock-cell paragraph styles — which were
computed *properties*, so a seconds field allocated one per cell per frame — and `drawText`'s own
`measured`, which joins the B106 width memo now that the memo's key is established as complete
rather than believed.

**Every horizontal origin is unchanged.** They already were origins, computed from `measured` and
`cell.width`, so cPro2's 4px tuck and Big Bento's clock columns keep the exact arithmetic they had.
The change is only *how* the glyphs reach the screen.

**The baseline formula, which is the whole of the vertical arithmetic:**

```swift
baseline = drawFrame.maxY - NSLayoutManager().defaultBaselineOffset(for: font)   // cached per font
```

drawn **inside the local flip `drawText` already establishes**. Two things reading got wrong and a
pixel comparison settled (`WinampModernTextDrawingTests`):

- **The flip stays.** CoreText draws upright in a y-up space, and the scene's own transform is
  top-origin — so `drawText`'s mirror is what *makes* it y-up, not something to undo. Dropping it
  draws every string mirrored, and a mirrored `Ayg|H` has almost the same ink bounding box as an
  upright one. Only a pixel comparison sees it; an ink-box assertion passes.
- **The offset is TextKit's, not the font's.** Not `ascender`: at 8pt all four faces tested want 8
  while their ascenders run 6.03…7.73, and Helvetica at 17.6pt wants 18 against an ascender of
  13.55. `defaultBaselineOffset(for:)` — what AppKit's own drawing asks — agrees exactly everywhere.

**What `NSString.draw`'s rect provided besides layout,** and what became of each half:

| the rect did | now |
|---|---|
| scissored **vertically** at `drawFrame` | an explicit clip, inside the mirror. Load-bearing: a 24pt line in a 16px box differs by ~350 pixels without it |
| scissored each **clock cell** at its own cell (`.byClipping` was set for this) | an explicit per-cell clip |
| scissored **horizontally** | *deliberately not restored.* The rect was only ever widened to `max(drawFrame.width, measured)` to defeat it — B87's widened context clip was always meant to be the bound. The widening is gone |

**Two branches keep `NSString.draw`, and both say why in the code.** The **wrapping** branch: the
rect *is* the line-breaking width and `boundingRect` on the same attributes decides the block's
height, so replacing it means re-implementing line breaking to keep draw and measure agreeing, for a
case that is rare and never in a per-row loop. And **a `drawFlippedText` row too long for its
column**: `.byTruncatingTail` is not just a cut — AppKit tightens inter-character spacing by up to
`tighteningFactorForTruncation` (0.05) before truncating, and a `CTLine` reproduces the cut and not
the tightening. Measured against `NSString.draw`, the first dozen columns of an over-long row match
to the byte and the rest diverge steadily, ~85% of the ink.

**Measured** (`WINAMP_MODERN_RENDER_TIME=60 WINAMP_MODERN_RENDER_TIME_SCALE=2`, three runs after,
spread ≤1%):

| layout | before | after |
|---|---:|---:|
| cPro Bento `main/normal` | 5.51 ms/frame | **5.06–5.11** (−8%) |
| cPro Bento `notifier/normal` | 0.53 | **0.31** (−41%) |
| cPro Bento `widgets.manager/normal` | 1.25 | **1.07** (−14%) |
| Big Bento Modern `main/normal` | 30.47 | 30.14–30.32 (−0.7%, at the edge of noise) |

Big Bento Modern's main layout is the honest caveat: it is 30 ms/frame and text is not what it is
spending it on. Reach for the next win there elsewhere.

**In the build the user runs** (release, cPro Bento, drawer visualization up, playing, `sample` 10 s,
7802 main-thread samples). No release *baseline* was captured before the change, so these are shares
of the state after it, read by the outermost occurrence of each symbol — the headless table above is
the controlled before/after:

| main thread | share |
|---|---:|
| busy | 51.5% |
| `WinampModernMainView.draw` | 25.4% |
| `drawText` | **2.5%** |
| `drawSurfaceText` → `__NSStringDrawingEngine` | **3.2%** |
| `refreshLayerFXMeshes` | 1.8% |
| `textAttributes` / `measuredWidth` / `boundingRect` / `drawBitmapText` | 0.4 / 0.3 / 0.4 / 0.2% |

`drawCachedLine` and `CTLineDraw` do not appear (inlined, 1 sample) — the drawing half of `drawText`
has stopped being a cost.

**What that leaves, and it is worth naming:** *every one of those 3.2% samples is the
`drawFlippedText` truncation fallback*, reached from `drawPlaylistComponent` → `drawSurfaceText`.
Winamp draws a playlist row's title and its time into the **same** rect (`rowRect.insetBy(dx: 3)`,
one left-aligned and one right-aligned), so the title's box is the whole row and any title longer
than the row takes the exact-but-slow path. In a normally-filled playlist that is most rows, so
`drawFlippedText`'s conversion buys much less than its call count suggests.

Closing it means giving up the tightening: set `tighteningFactorForTruncation = 0` on that path and a
truncated `CTLine` matches exactly, at the cost of rows that AppKit currently squeezes to fit
truncating one character earlier instead. That is a visible change to the playlist and a decision to
take deliberately, not a free win — which is why it was not taken here.

**Sweep result** (`scripts/wal_render_sweep.sh`, all 69 installed archives): 1993 of 1993 comparable
invariant lines identical, 585 of 590 PNGs byte-identical. The 5 that differ are antialiasing — two
skins (Formamp, K-jr, the latter shipped twice), at most 10 pixels each, at most **5/255**, with
every full-coverage and every empty pixel unchanged, so no glyph moved. The same residue shows in
the unit test on **Courier** alone, one or two pixels per string: AppKit's string drawing and a bare
`CTLineDraw` rasterize a glyph edge slightly differently. `CGContext`'s
`setShouldSubpixelQuantizePositions` closes it and is not in the public CoreGraphics headers, which
is not a trade worth making for one pixel of one face.
