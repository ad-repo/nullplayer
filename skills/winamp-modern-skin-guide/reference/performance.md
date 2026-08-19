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

The main thread still carries what genuinely belongs to it: MAKI timer ticks and the interpreter (the
VM and the graph are single-threaded by construction), and the warp's pixel loop inside `draw`
(~1.9 ms for Defix's two 264×264 reels). Both are measured, bounded and, at 30 Hz, comfortably inside
the frame. What is *not* allowed there is arithmetic that could have happened elsewhere:
`WinampModernLevelMeter` and `PeppyMeterLevelModel` both measure on the audio-posting thread and hop
two doubles, and the FX mesh is evaluated by the animation clock before it invalidates rather than by
the paint that follows.

