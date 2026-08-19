# Winamp Modern (`.wal`) — Phase 29 Handoff

**For:** the agent who picks up `.wal` motion and performance next

**From:** Phase 29 (frame budget, repaint discipline, the VU scale) — **all of it confirmed live**

**Date:** 2026-08-19

Read first:

- `docs/winamp-modern/phase-28-handoff.md` — the diagnosis this phase acted on, and the harness probes
- `skills/winamp-modern-skin-guide/SKILL.md` § *The frame budget: what repaints, and what it costs*
- `TASKS.md` §29

---

## 0. What was wrong, and what it actually was

Phase 28 made every Defix display style *move*. The user's report on it was two sentences, and they
turned out to be two unrelated bugs that had nothing to do with Layer FX:

> "the cassette is still very choppy … the VU meters still do not react very well and only work
> slightly better."

| Symptom | Cause | Fix |
|---|---|---|
| Choppy cassette | Every bitmap re-filtered to the Retina backing scale **every frame** | Pre-scaled artwork cache — 18.3 → 3.5 ms/frame at 2× |
| Choppy cassette | `updateTime` repainted the **whole window** at the audio clock's 10 Hz | It names the rects that actually follow the clock |
| Weak needles | The host measured **RMS**; Winamp's VU byte is a **peak** | `WinampModernLevelMeter` measures peak amplitude |

The script was never at fault in either case, and Phase 28 had already proved it:
`WINAMP_MODERN_RENDER_FX_SPIN` measured the reels stepping 5° and 8° every ~33 ms, perfectly evenly.
When the cadence measurement is clean and the motion still looks wrong, the frames are the problem.

---

## 1. The measurements

Defix Hi-End 200, main window, optimized build
(`swift test -Xswiftc -O --filter WinampModernRenderDumpTests`):

| what | before | after |
|---|---|---|
| full repaint, 1× | 3.1 ms | — |
| full repaint, **2× (Retina)** | **19.3 / 18.3 ms** | **3.46 ms** |
| full repaint, 2×, both reels warping | — | 5.40 ms |
| clipped to the warped layers' rects, 2× | 6.9 ms | 4.37 ms |
| its SUI (tabs + library) window, 2× | 39.4 ms | 3.37 ms |

Per-node, at 2× (`WINAMP_MODERN_DRAW_PROFILE=1`): unnamed `layer` nodes 6.72 → 0.49 ms,
`layout#normal` 3.75 → 0.21 ms, `Display3BG2` 1.54 → below the top eight.

**Every dumped window is pixel-identical to the pre-change baseline.** That check is the whole
licence for the caching below and it is worth repeating whenever you touch the draw path:

```bash
export WINAMP_MODERN_WAL="$HOME/Library/Application Support/NullPlayer/WinampModernSkins/Defix Hi-END 200.WAL"
WINAMP_MODERN_RENDER_DUMP=/tmp/after WINAMP_MODERN_RENDER_FX=play WINAMP_MODERN_RENDER_VU=sweep \
  swift test -Xswiftc -O --filter WinampModernRenderDumpTests
# …then compare /tmp/after against a dump taken before the change, per pixel — PNG *bytes* differ
# between runs even when the pixels do not, so `cmp` will lie to you.
```

---

## 2. What landed

### 2.1 Pre-scaled artwork (`WasabiSceneRenderer.prescaled`)

A `.wal` scene is laid out in skin pixels and drawn through a scaled CTM. `CGContext.draw` was
therefore running a `.high` resample of every bitmap in the window on every frame, for artwork that
had not changed. It is now scaled once, at the size the context will put it on screen, and kept. The
same interpolation runs — just not sixty times a second.

- Only a genuine rescale is cached, so a 1× non-Retina display pays nothing.
- Art below 1024 destination pixels is not cached: a button face is microseconds, and the entry would
  crowd out the backgrounds this exists for.
- Bounded by a pixel budget (~32 MB), not an entry count, and dropped on a theme switch and teardown.

### 2.2 Stable crops (`WasabiSceneRenderer.cropped`)

`CGImage.cropping(to:)` allocates a **fresh** image on every call. Bitmap-font glyphs and animated
layer frames were therefore a different object identity every frame, so every cache keyed on that
identity — the pre-scaled raster, the warp's source raster — missed *and* churned. Crops are memoized
now, which is what makes 2.1 work for a skin that draws text or animation at all.

Related: the `ObjectIdentifier`-keyed caches (`warpSourceCache`, `warpedImageCache`, `prescaledCache`)
each hold their source image with the entry. An `ObjectIdentifier` is an address, and a freed address
comes back attached to a different image; retaining the source makes the key sound rather than
merely lucky.

### 2.3 The scene walk is memoized (`WasabiSceneRenderer.sceneNodes`)

It re-solved every object's geometry for *every* caller — the draw, the animating-rect scan, the
visualization-rect scan, every hit test — several times a frame. It is now memoized against the
graph's own `mutationGeneration`, which any attribute write bumps.

**The trap, and it cost a test failure to find:** a node's *geometry* is a function of the graph, but
its *bitmap* is not. `<status>` play/pause artwork, the shuffle and repeat lamps, the EQ on/auto
buttons and every `cfgattrib`-bound switch resolve from the host and the configuration store, neither
of which touches the graph. A memoized node has its image re-resolved on the way out
(`withRefreshedBitmapID`), and only for the kinds that can vary.

### 2.4 `updateTime` stops repainting the world

Ten times a second, for as long as a track plays, it ended in `needsDisplay = true`. That is a
whole-window repaint at the audio engine's clock rate, and it silently defeated every targeted
repaint Phase 28 added. It now invalidates only what the renderer draws from `host.currentTime`: a
`display="time"` readout, a `seek` slider, a seek `progressgrid`.

An **empty** set is a real answer, not a classification failure — those three are the only things the
renderer draws from the clock. A readout a *script* maintains (a bitmap-font clock filled with
`setText`) repaints through `graphDidMutate` when the script writes it, which is when it changes.

### 2.5 The mesh is built off the paint path

`WinampModernScriptRuntime.refreshLayerFXMeshes()` is called by the window's 30 Hz clock *before* it
invalidates. Evaluating a warp runs the skin's callbacks per grid vertex through the interpreter
(49 vertices × 2 layers × 30 Hz for Defix); it is still main-thread work, because MAKI and the graph
are single-threaded, but the frame AppKit is composing is no longer the one waiting for the VM.
`fx_setRealtime(1)` is honoured by marking the layer stale on each pass rather than re-evaluating
inside the draw.

The animation clock also runs in `.common` runloop mode now, so the reels do not freeze while AppKit
tracks a window drag or an open menu and then lurch forward when it ends.

### 2.6 The VU scale (`WinampModernLevelMeter`)

Winamp's VU byte comes off a waveform: it is an **excursion**. RMS is an energy average, and the two
are not interchangeable at this scale — music that peaks at full scale measures 0.05–0.15 RMS, and
against Defix's own artwork that is the bottom sixth of the needle's sweep (measured with
`WINAMP_MODERN_RENDER_VU`: 0.1 → 34%, 0.3 → 60%, 1.0 → 100%). Peak puts loud material at 0.5–1.0,
which is the swing the artwork is cut for, and it keeps the transients a mean-square averages away.

The skin still owns the curve and the ballistics — Defix maps the byte through `73.813 · x^¼ − 100`
and applies its own attack and decay. Do not add a gain constant or a smoothing stage here without a
measurement that names the skin it is for.

**Live follow-up, same day.** Peak alone was reported as *better, but still not responsive to peaks
and valleys, and it does not go to 0 when the audio stops.* Both are real, and neither is the scale:

- **Peak over a whole tap buffer is nearly a constant.** The buffer is 50–100 ms and something in it
  is always loud, so the needle sat high and still. Winamp measures a 576-sample vis block (~13 ms at
  44.1 kHz) — that is where the dynamics are. Each arriving buffer is now split into blocks of that
  length and **played out one at a time as real time passes**, so a skin polling every 17 ms sees
  successive blocks instead of the same number five times over. It costs one buffer of latency.
  The cadence comes from the **interval between arrivals**: the buffer carries no duration of its own
  (the local tap decimates to a fixed 512 samples, the streaming path posts a different length), and
  a new arrival resets the playout clock, so it cannot drift however wrong one estimate is.
- **Nothing ever said "silence".** The tap stops posting when playback stops, pauses, ends or moves
  to a cast device — there is no zero notification — so the last value stuck and the needles hung
  wherever the music left them. Running off the end of the played-out blocks *is* the signal: the
  last block is held for 150 ms to ride out jitter between buffers, and after that the meter reads 0.
  Source-agnostic on purpose — it covers pause, stop, end of track and casting without wiring any of
  them.

`WINAMP_MODERN_VU_LOG=1` prints, once a second, the buffer's peak and RMS, the tap cadence, the block
count, and the byte **range** across the blocks. `peak` against `blockRange` is the whole diagnosis:
a wide block range with a flat needle is a skin-side ballistics question, a narrow one is a
measurement question. `RENDER_VU` injects a level and exercises only the half of the path *above* the
meter.

---

## 3. Files this phase touched

| Concern | File |
|---|---|
| Pre-scaled art, stable crops, scene memo, warped-raster cache | `Sources/NullPlayer/WinampModern/WasabiRenderer.swift` |
| `refreshLayerFXMeshes`, `layerFXMeshIsPending` | `Sources/NullPlayer/WinampModern/WinampModernScriptRuntime.swift` |
| Targeted `updateTime`, animation tick, `invalidateRectCaches`, `.common` mode | `Sources/NullPlayer/Windows/WinampModern/WinampModernMainView.swift` |
| Peak measurement, block playout, silence, `WINAMP_MODERN_VU_LOG` | `Sources/NullPlayer/WinampModern/WinampModernLevelMeter.swift` |
| Tests (16 cases, both phases) | `Tests/NullPlayerAppTests/WinampModernPhase28Tests.swift` |

Suite: **754 pass, 0 failures**, 9 opt-in skipped.

---

## 4. Open

- [x] **Confirmed live** (user, 2026-08-19), in three passes: the cassette animation "looks very
      good" after §2.1–2.5; peak alone (§2.6) was "better but not fully responsive" and never fell to
      rest; the block playout and silence timeout that answer that report were confirmed on the pass
      after. All three symptoms in the Phase 28 report are closed.

      If a VU question comes back, start with `WINAMP_MODERN_VU_LOG=1` rather than with this class:
      `blockRange` should span a good part of 0…255 on ordinary music. If it is wide and the needle
      is still flat, the remaining smoothing is the *skin's* (Defix's own attack/decay in
      `VU_LAYOUT_1.maki`), not ours — that is where to look, not at a gain constant here.
- [ ] **The speaker cones are still unverified** (Phase 28 owed this too). They now get their
      `onSetVisible`, so their `getVisBand` timer starts; whether they animate has never been seen.
- [ ] **Auxiliary windows never install `graphDidMutate`/`repaintRequested`** (`drivesScripts: false`),
      so a script mutation in a speaker window repaints the *main* view instead. This is the most
      likely reason a cone would still look dead, and it is a small fix: give every container view its
      own object-scoped repaint hook rather than routing through the single-owner callbacks.
- [ ] **The rest of the window layer.** `WinampModernMainView` still has ~30 `needsDisplay = true`
      sites. The periodic ones are gone; the remainder are input and state changes, which are fine —
      but `graphDidMutate` is a full-window repaint on *any* script mutation, and a skin that writes an
      attribute on a timer pays 3.5 ms for it. The graph already records *which* objects were
      invalidated (`consumeInvalidations()`); routing that into per-object rects is the next real win,
      and it is the last thing on the paint path that scales with what the skin does rather than with
      what changed.
- [ ] `fx_onGetPixelA` (alpha), `fx_setBgFx(1)` (warping the backdrop) and `fx_onFrame`/`fx_setSpeed`
      as a host-driven clock remain accepted and inert; nothing measured asks for them.
