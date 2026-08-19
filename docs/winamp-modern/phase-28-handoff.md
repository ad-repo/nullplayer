# Winamp Modern (`.wal`) — Phase 28 Handoff

**For:** the agent continuing **Layer FX** — the animation now runs, but it is *choppy*, and the VU
meters still answer the music weakly

**From:** Phase 28 (Layer FX, MAKI math library, unary-minus fix, targeted repaints)

**Date:** 2026-08-19

Read first:

- `docs/winamp-modern/phase-27-handoff.md` — how the frozen meters were root-caused to Layer FX
- `skills/winamp-modern-skin-guide/SKILL.md` — engine architecture and the render-dump harness
- `TASKS.md` §28 — the checklist this phase worked from

---

## 0. Where it stands (live report, user, 2026-08-19)

> "the cassette is still very choppy … the VU meters still do not react very well and only work
> slightly better."

Every display style now **moves** — that part is done and confirmed. What is left is *quality of
motion*, and it is two separate problems that must not be conflated:

| Symptom | Nature | State |
|---|---|---|
| All eight Defix styles animate at all | Layer FX implemented | **fixed, confirmed live** |
| The song ticker scrolls | side effect of the same repaint work | **fixed, confirmed live** |
| Cassette reels are choppy | **cadence** — frames, not the script | open, see §3 |
| Needles answer the music weakly | **scale** — the level fed to the skin | open, see §4 |

---

## 0.5 Do this first: get the work off the main thread

**Start here, before touching the warp, the level scale, or anything else in this document.** This
repo's standing rule is that the main thread draws and handles input and does nothing else, and
violations of it do not announce themselves — they surface as unrelated-looking symptoms: an
animation that stutters, a meter that "lags", a window that feels heavy while a track loads, a UI
that is fine until playback starts. Both open problems below (§3 choppy, §4 weak) sit downstream of
it, and tuning either one against a main thread that is already saturated will produce a
measurement that means nothing and a "fix" that is really just a different load.

Two offenders were removed in Phase 28 — they are the pattern to look for:

- `PeppyMeterLevelModel` ran `AudioAnalysisDSP.rmsDBFS` **inside** its `DispatchQueue.main.async`
  hop: a vDSP pass over every PCM buffer, twice, on the main thread at audio-buffer rate. The
  measurement now runs on the posting thread and only two doubles cross. The notification is
  deliberately received with `queue: nil` (registering with `queue: .main` delivers *synchronously*
  and blocks the real-time audio tap) — the trap is doing the arithmetic after the hop instead of
  before it.
- `WinampModernMainView.updateSpectrum` set `needsDisplay = true` on the **whole window** at tap
  rate, i.e. a 19.3 ms full repaint per spectrum update. It now invalidates only the `<vis>`/`<eqvis>`
  rects.

Still on the main thread, known and **not** addressed:

1. **The Layer FX mesh evaluation runs inside `draw`** — 49 vertices × 2 layers × 30 Hz through the
   MAKI interpreter, on the paint path. It could be evaluated when the skin calls `fx_update()`
   (which is where the value actually changes) rather than when the frame is painted, or moved off
   the paint path entirely.
2. **The warp resample runs inside `draw`** — a CPU resample of every warped layer, per frame
   (`WasabiLayerFXMesh.resample`). Small today (~0.4 ms for Defix's two layers) but it is on the same
   thread as everything else in this list, and it grows with layer area.
3. **The whole scene is re-walked and re-drawn per frame** — `sceneNodes()` rebuilds the node list on
   every call, and `draw` is called for repaints that only needed one rect.
4. **Every MAKI timer tick, and every script event it fires, runs on the main queue**
   (`MakiTimerService` schedules on `.main`). Defix has several; each tick runs interpreted bytecode
   between the frame the user is watching and the next one.

Audit these with `WINAMP_MODERN_RENDER_TIME` / `WINAMP_MODERN_DRAW_PROFILE` (§2) and with a dirty-rect
log in `draw(_:)`, and fix what the measurement names — then re-read §3 and §4, whose numbers may
change underneath you.

---

## 1. What Phase 28 landed

- **Layer FX** (`Sources/NullPlayer/WinampModern/WasabiLayerFX.swift`, new). The skin's
  `fx_onGetPixel*` callbacks are evaluated at each grid vertex into a source-coordinate mesh; the
  renderer resamples the layer through it. `WasabiLayerFXMesh.resample(source:width:height:)` is the
  pixel loop and is unit-testable on its own.
  - **The naming is Winamp's and it is a trap**: `fx_onGetPixelR` answers with the source **angle**
    (R for rotation) and `fx_onGetPixelD` with the source **distance**. Measured from Defix's needle
    and cassette scripts, which return `argument0 + rotation` where the rotation is degrees ÷ 57.295.
  - Coordinates are normalized 0…1 with a top-left origin, centre (0.5, 0.5), angle growing clockwise
    (`WasabiLayerFXCoordinates`). A rotation is affine in x/y, which is why Defix's 1×1 reel grid
    reproduces one exactly.
  - Per-object state in `WinampModernScriptRuntime` (`invokeLayerFX`, `layerFXMesh(for:)`), meshes
    cached until `fx_update()` (or always, under `fx_setRealtime(1)`), vertex count bounded.
- **A script handler's return value** now leaves the interpreter (`MakiInterpreter.execute` returns
  the value at `return`), surfaced as `WinampModernScriptRuntime.call(object:event:arguments:)`.
  `dispatch` still returns a handler count — every existing caller is unchanged.
- **`onSetVisible` on window show** (`notifyContainerVisibility(containerID:visible:)`, called from
  `WinampModernMainView.setSceneVisible`). This is what *switches the reels on*: Defix enables their
  FX and starts their timer from `onSetVisible(1)`, and `orderFront` never touched the graph. Same
  mechanism the speaker cones were waiting on (Phase 27 §5.1 hypothesis 1 — **confirmed**).
- **MAKI's math library** — `sqrt, pow, sin, cos, tan, asin, acos, atan2, log, log10, exp, abs`.
  Defix's needle `onTimer` aborted on `sqrt` **every tick**, so the needles could not have moved
  whatever the FX code did.
- **Unary minus was integer-truncating** (`MakiBytecode.swift`, opcode 76). `range * -(level/127)`
  became `-0` or `-1`, so the needle had exactly two positions. This is the single highest-impact fix
  in the phase and it was invisible to every existing test.
- **Targeted repaints** — see §3.
- **Off-main measurement** — `PeppyMeterLevelModel` ran `AudioAnalysisDSP.rmsDBFS` *inside* its
  `DispatchQueue.main.async` hop, i.e. a vDSP pass over every PCM buffer, twice, on the main thread
  at audio-buffer rate. It now measures on the posting thread and hops two doubles. (Kept in
  PeppyMeter; it is that window's bug too.)
- **`.wal` VU decoupled from PeppyMeter** — new `WinampModernLevelMeter` owns the skin's tap.
  Phase 27.5 had routed `getLeftVUMeter`/`getRightVUMeter` through `PeppyMeterLevelModel`, which
  wears PeppyMeter's calibration; the two surfaces want different measurements of the same audio.

Suite: **735 pass, 0 failures**, 9 opt-in skipped. No Phase 28 tests written yet — see §6.

---

## 2. The harness probes this phase added (all opt-in, all in `WinampModernRenderDumpTests`)

```bash
export WINAMP_MODERN_WAL="$HOME/Library/Application Support/NullPlayer/WinampModernSkins/Defix Hi-END 200.WAL"
export WINAMP_MODERN_RENDER_DUMP=/tmp/defix

WINAMP_MODERN_RENDER_FX=play        # which layers are warped, their flags, their mesh corners
WINAMP_MODERN_RENDER_FX_SPIN=2      # per-update dt + angle step for 2s — is the *script* smooth?
WINAMP_MODERN_RENDER_VU=0.4         # inject a program level; `sweep` oscillates 0…1 at 0.5 Hz
WINAMP_MODERN_RENDER_CONFIG='<section>;<key>=<value>[|…]'   # pick a skin option before load
WINAMP_MODERN_RENDER_TIME=60        # ms/frame, whole scene
WINAMP_MODERN_RENDER_TIME_SCALE=2   #   …at Retina backing scale (this is the real number)
WINAMP_MODERN_RENDER_TIME_CLIP=1    #   …clipped to the warped layers' rects
WINAMP_MODERN_DRAW_PROFILE=1        # per-node draw cost, top 8
WINAMP_MODERN_FX_TRACE=1            # every fx_* call with its receiver
WINAMP_MODERN_CALL_TRACE=1          # every MAKI method call with arguments and result
WINAMP_MODERN_MAKI_TRACE=<program>  # every bytecode instruction + stack top (found the op76 bug)
```

Run them with `swift test -Xswiftc -O --filter WinampModernRenderDumpTests` when timing — a debug
build is ~6× slower and will mislead you. (`swift test -c release` does **not** compile: the test
target uses `#if DEBUG` hooks.)

Two gotchas that cost time here: `cd`-ing out of the repo before `swift test` fails silently under
`grep`, and the harness's skin configuration **persists** in the xctest UserDefaults domain between
runs (`defaults delete com.apple.dt.xctest.tool` to reset; Defix's style also lives in a private
value, `CurVuVis`).

---

## 3. Open problem A — the cassette is choppy

**It is not the script.** Measured with `WINAMP_MODERN_RENDER_FX_SPIN`, the reels advance a fixed
0.0875 rad (5°) and 0.14 rad (8°) every ~33 ms, perfectly evenly, and the needle updates every
~17 ms. The skin's own timers are healthy.

**It is the frame budget.** Measured with `WINAMP_MODERN_RENDER_TIME=60`, optimized:

| what | ms/frame |
|---|---|
| Defix main window, 1× | 3.1 |
| Defix main window, **2× (Retina)** | **19.3** |
| same, clipped to the warped layers' rects | 6.9 |

An 8°-per-33 ms step cannot look smooth at 19 ms/frame plus everything else on the main thread. Per
`WINAMP_MODERN_DRAW_PROFILE`, the cost is ordinary bitmap drawing: unnamed `layer` nodes 6.7 ms,
`layout#normal` 3.7 ms, `Display3BG2` 1.5 ms — full-window background art, resampled at 2×.

What Phase 28 already did about it (**and it was not enough**):

- `fx_update` invalidates only that layer's rect (`objectRepaintRequested` → `setNeedsDisplay(for:)`)
- the 30 Hz fallback clock invalidates only animating/FX rects, not the whole view
- `updateSpectrum` invalidates only `<vis>`/`<eqvis>` rects (it was repainting everything at tap rate)
- `draw` clears `dirtyRect` rather than `bounds`
- `fx_update` no longer runs a full layout + surface-reconciliation pass (it did, 30×/sec)

**Do §0.5 first** — every number in this section was measured on a main thread that still carries the
work listed there, so the ceiling may move once that is fixed.

**Ranked hypotheses for what is still costing frames — all unverified:**

1. **Something else is still invalidating the whole view every frame.** There are ~31
   `needsDisplay = true` sites in `WinampModernMainView`; the periodic ones (`updateTime`,
   `updatePlaybackState`, volume/title polling) are the suspects — a per-tick full invalidation
   silently defeats every targeted repaint above. **Measure before optimizing**: log the dirty rect
   in `draw(_:)` for a few seconds and see whether it is the window or a meter.
2. **The bitmap draws themselves.** Even clipped, 6.9 ms is a lot; the same art is re-decoded and
   re-resampled per frame. A per-object cached `CGLayer`/pre-scaled bitmap for static background
   nodes would remove most of it. Check what `WasabiResourceCache` caches (decoded image vs
   scaled-for-this-frame).
3. **The warp resamples on the main thread inside `draw`.** 264×264 ×2 layers ≈ 0.4 ms at 1× — small,
   but it is on the paint path, and the mesh evaluation (49 vertices × 2 layers × 30 Hz through the
   interpreter) is main-thread work too.
4. **The window is `isOpaque = false` + layer-backed**; partial invalidation on a transparent
   borderless window may still recomposite more than expected.

---

## 4. Open problem B — the VU meters answer weakly

Defix maps the byte it gets through `73.813 · x^¼ − 100`, clamps at 0, and applies its own attack and
decay before turning the needle. The host must therefore hand it **the same thing Winamp does** and
nothing more.

Phase 27.5 fed it PeppyMeter's perceptual volume (dBFS over a −42 dB floor, ×100, plus VU
ballistics) — the same signal compressed and smoothed twice. Phase 28 replaced that with
`WinampModernLevelMeter`: **linear RMS amplitude, unsmoothed**. The user reports this is "slightly
better" but still not right.

**What is measurably true today** (`WINAMP_MODERN_RENDER_VU`, needle angle in rad, after the op76
fix): 0.0 → +0.908, 0.1 → +0.431, 0.3 → +0.060, 0.5 → −0.152, 0.7 → −0.307, 1.0 → −0.486. The sweep
is monotone and uses the full artwork, so **the geometry is right and the input scale is what is
wrong.**

**Do §0.5 first** here too: a level that arrives late or in bursts because the main thread was busy
reads exactly like a level that is scaled wrongly, and you cannot tell them apart by looking at the
needle.

Ranked next steps:

1. **Measure what the meter actually receives during playback.** Log
   `WinampModernLevelMeter.levels` against a known track. If typical music sits at 0.05–0.15 linear,
   the needle lives in the bottom sixth of its sweep and every fix below is guesswork until this is
   on paper.
2. **RMS vs peak.** Winamp's vis data is a waveform; a VU byte taken from it is closer to a **peak**
   (or a short-window mean of |x|) than an RMS over a whole buffer. RMS reads ~3 dB lower than peak
   for music and much lower for percussive material, which flattens exactly the dynamics the user is
   missing. Try peak, or mean-|x| × a constant.
3. **Window length.** The tap's buffer may be long enough to average transients away. A VU has a
   ~300 ms integration by convention, but the *skin* supplies that; the host should be quick.
4. Only after 1–3: consider a gain constant, and record it in `skins.md` with the measurement that
   justified it. Do not invent a curve — the skin already has one.

---

## 5. Files this phase touched

| Concern | File |
|---|---|
| FX model, coordinates, resampler | `Sources/NullPlayer/WinampModern/WasabiLayerFX.swift` (new) |
| FX state, mesh evaluation, `call`, `notifyContainerVisibility`, math library | `Sources/NullPlayer/WinampModern/WinampModernScriptRuntime.swift` |
| Handler return value, opcode 76, bytecode trace | `Sources/NullPlayer/WinampModern/MakiBytecode.swift` |
| Warped draw, source raster cache, draw profile | `Sources/NullPlayer/WinampModern/WasabiRenderer.swift` |
| Targeted repaints, animation clock, `setSceneVisible` | `Sources/NullPlayer/Windows/WinampModern/WinampModernMainView.swift` |
| `setSceneVisible` call sites, `layerFXProvider` wiring | `Sources/NullPlayer/Windows/WinampModern/WinampModernMainWindowController.swift` |
| `.wal` VU tap | `Sources/NullPlayer/WinampModern/WinampModernLevelMeter.swift` (new) |
| Off-main RMS | `Sources/NullPlayer/PeppyMeter/PeppyMeterLevelModel.swift` |
| Harness probes | `Tests/NullPlayerAppTests/WinampModernRenderDumpTests.swift` |

---

## 6. Owed work (nothing here is done)

- [ ] **§0.5 — main-thread work on the paint and audio paths. Do this before §3 and §4.**

- [ ] **Tests**: `WinampModernPhase28Tests` — the interpreter's return value, unary minus on a
      double (the regression that would have caught the needle bug), the `fx_set*` state, a mesh from
      a synthetic rotation, `WasabiLayerFXMesh.resample` geometry, and `notifyContainerVisibility`
      dispatching `onsetvisible` once per change
- [ ] **Docs**: `compatibility.md` (Layer FX + the math library as supported surface),
      `skins.md` (Defix: all eight styles animate; what is still rough), `SKILL.md` (the probes in
      §2), CHANGELOG under **Unreleased** — no version bump
- [ ] `TASKS.md` §28 checkboxes are still unticked even where the work landed
- [ ] Auxiliary windows never install `graphDidMutate`/`repaintRequested` (`drivesScripts: false`),
      so a script mutation in a speaker window repaints the *main* view instead. Related: the speaker
      cones now get their `onSetVisible`, but whether they animate is **unverified**
- [ ] `fx_onGetPixelA` (alpha), `fx_setBgFx(1)` (warping the backdrop) and `fx_onFrame`/`fx_setSpeed`
      as a host-driven clock are all accepted and inert; nothing measured asks for them yet
