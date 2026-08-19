# Winamp Modern (`.wal`) — Phase 27 Handoff

**For:** the agent implementing **Phase 28 — Layer FX (the frozen meters)**

**From:** Phase 27 (Skin Settings sheet, `getVisBand`, `isLoading`, VU level scale)

**Date:** 2026-08-18

Read first:

- `skills/winamp-modern-skin-guide/SKILL.md` — engine architecture and the render-dump harness
- `skills/winamp-modern-skin-guide/compatibility.md` — the supported/unsupported surface
- `skills/winamp-modern-skin-guide/skins.md` — the per-skin record, Defix section
- `TASKS.md` — Phase 27 is closed except its live items; this doc is Phase 28's brief

---

## 0. The headline: what the live run said

The user ran Defix Hi-End 200 in the app after Phase 27 (2026-08-18) and reported:

> **P-402 VU and Technics VU work. All others are frozen.**

That single sentence is the most useful measurement in this document, because the two styles that
work and the six that do not split **exactly** along one mechanism. This is not a "some skins are
flaky" problem; it is one unimplemented feature.

| Defix display style | Motion mechanism | State |
|---|---|---|
| P-402 VU (`LAYOUT1/LVL/RT_*.png`, 180×494) | `<animatedlayer>` frame strip + `gotoFrame(level)` | **works** |
| Technics VU (`LAYOUT1/LVL/Technics1_*.png`, 180×570) | `<animatedlayer>` frame strip + `gotoFrame(level)` | **works** |
| Left Right VU (`SCALE2DEFLR` + `DEFProNeedle`) | needle **rotated** through Layer FX | frozen |
| BASS TRIPLE VU (`SCALE1DEFBT`) | needle rotated through Layer FX | frozen |
| McIntosh MC2KW (`SCALE3MC` + `NEEDLE1MC`) | needle rotated through Layer FX | frozen |
| Ovis 1 / Ovis 2 (`SCALENEON` + `NEONNeedle`) | needle rotated through Layer FX | frozen |
| Audio cassette (the shipped default, `LAYOUT1/CAS/`) | reels (`CASROLL`/`CASROLR`) **rotated** through Layer FX | frozen |

**Everything that works is a sprite strip we already animate. Everything frozen is a rotation, and
every rotation in this skin is done with Winamp's Layer FX callbacks, which we accept and ignore.**

So: **Phase 28 is Layer FX.** It is the top priority the user named, and it is one feature, not six
bugs.

---

## 1. Why the frozen ones are frozen — the evidence

`fx_*` has been accepted-and-inert since Phase 25 (`WinampModernScriptRuntime.swift`: signatures
~line 840, dispatch ~line 1732, "Configuration for a per-pixel layer warp we do not run"). That was
the right call at the time — *refusing* the methods aborted the whole handler, which cost Defix its
entire display area. But inert means the artwork draws undistorted, i.e. **static**.

Measured with `strings` over the skin's compiled scripts:

```
SCRIPTS/VU_LAYOUT_1.maki        fx_onGetPixelR  fx_setBgFx fx_setBilinear fx_setClear
                                fx_setEnabled fx_setGridSize fx_setLocalized fx_setRealtime
                                fx_setRect fx_setWrap fx_update
                                getLeftVuMeter getRightVuMeter getVisBand gotoFrame setXMLparam onTimer
SCRIPTS/MAIN_LAYOUT_1_SCRIPT.maki   fx_onGetPixelR + the same setters, CASROLL, CASROLR   ← the cassette reels
SCRIPTS/SPEAKER.maki            getVisBand, gotoFrame, setDelay/start/stop, onSetVisible   ← no fx at all
```

`fx_onGetPixelR` is a **callback the host calls**, not a method the script calls. The skin implements
it; Winamp invokes it per grid vertex and uses the returned `Double` to warp the layer. We never call
it, so the needle image sits exactly where it was drawn. Nothing fails, nothing is recorded — which
is precisely why the compatibility report says Defix is clean (`degraded`, zero script findings, zero
unsupported methods) while six of its eight displays do not move.

Confirmed with the harness (`WINAMP_MODERN_RENDER_SCRIPTS=1`, Defix):

```
SCRIPT MAIN_LAYOUT_1.xml owner=group#player.display.VU2 param=needle/VUBtn2/0/40/0/0
       handlers=fx_ongetpixelr,ondatachanged,onleftbuttondown,onscriptloaded,onscriptunloading,onsetvisible,ontimer
       ran=onscriptloaded  failed=-
```

The needle script loads cleanly and declares `fx_ongetpixelr`. It is bound and never called.

---

## 2. The API to implement (from `std.mi`, Winamp 5.66 — `lib/std.mi` ~line 2333)

```
extern Layer.fx_onInit();
extern Layer.fx_onFrame();
extern Double Layer.fx_onGetPixelR(double r, double d, double x, double y);
extern Double Layer.fx_onGetPixelD(double r, double d, double x, double y);
extern Double Layer.fx_onGetPixelX(double r, double d, double x, double y);
extern Double Layer.fx_onGetPixelY(double r, double d, double x, double y);
extern Double Layer.fx_onGetPixelA(double r, double d, double x, double y);
extern Layer.fx_setEnabled/getEnabled(Boolean)      // master switch
extern Layer.fx_setWrap/getWrap(Boolean)            // sample wraps at the edges vs clamps
extern Layer.fx_setRect/getRect(Boolean)            // rectangular (X/Y) vs polar (R/D) callbacks
extern Layer.fx_setBgFx/getBgFx(Boolean)            // warp what is behind the layer, not its own image
extern Layer.fx_setClear/getClear(Boolean)          // clear the target each frame
extern Layer.fx_setSpeed/getSpeed(Int msperframe)
extern Layer.fx_setRealtime/getRealtime(Boolean)    // re-evaluate every frame vs cache the grid
extern Layer.fx_setLocalized/getLocalized(Boolean)  // coordinates local to the layer vs the canvas
extern Layer.fx_setBilinear/getBilinear(Boolean)    // interpolate samples
extern Layer.fx_setAlphaMode/getAlphaMode(Boolean)
extern Layer.fx_setGridSize(Int x, Int y);
extern Layer.fx_update();
extern Layer.fx_restart();
```

**The model** (this is the part to get right before writing code): the layer is covered by a grid of
`fx_setGridSize(x, y)` **vertices**. For each vertex the host passes the point's polar coordinates
`(r, d)` — radius and angle, normalized about the layer's centre — and its rectangular `(x, y)`, and
the script returns the coordinate to **sample from**. In polar mode (`fx_setRect(0)`) it calls
`fx_onGetPixelR` for the radius and `fx_onGetPixelD` for the angle; in rectangular mode
`fx_onGetPixelX`/`fx_onGetPixelY`. `fx_onGetPixelA` supplies alpha. The image is then drawn as that
warped mesh, interpolating between vertices — so the callback runs **per vertex per frame, not per
pixel**. Defix's needles set small grids (the `fx_setGridSize` call sites take variables; disassemble
with `WINAMP_MODERN_RENDER_DISASM=fx_setgridsize` to read the actual values), which is what makes
this tractable at 30–60 Hz through an interpreted VM.

A needle rotation is the degenerate case: the script returns `d + angle` from `fx_onGetPixelD` with
`r` unchanged, where `angle` comes from `getLeftVuMeter()`. Getting *only* the polar path working
would light up every frozen style in this skin.

---

## 3. The blocking prerequisite — a script handler's **return value**

`MakiInterpreter.execute(program:at:arguments:)` returns `Void`
(`Sources/NullPlayer/WinampModern/MakiBytecode.swift:510`), and
`WinampModernScriptRuntime.dispatch(object:event:arguments:)` returns a **handler count**
(`WinampModernScriptRuntime.swift:516`). Nothing in the engine has ever needed a value *back* from a
script — every event so far is a notification.

Layer FX is the first host→script call whose **return value is the whole point**. So Phase 28 starts
with an interpreter change:

1. Surface the value a handler returns (what is left when the program hits its return) out of
   `execute`, and thread it through `dispatch`/a new `call(object:event:arguments:) -> MakiValue`.
   Keep the existing `dispatch` signature intact — every current caller wants the count.
2. Keep it inside the existing budgets: the instruction budget, the re-entrancy guard, and the
   per-binding `WalFailure` catch (a script that throws mid-warp must degrade to "no warp", never
   take the skin down).
3. Add a **per-frame call ceiling** for FX specifically. `gridX × gridY × frames/sec × layers` is the
   first thing in this engine that can put the interpreter on the hot path; measure it
   (Phase 7.7-style `measure`) before enabling it by default, and consider caching the grid unless
   `fx_setRealtime(1)`.

That ordering matters: (3) is the reason to build this as a mesh warp rather than a naive per-pixel
loop. Do not write the per-pixel version "just to see it work" — 264×264 pixels × two needles × 30 Hz
through the VM will hang the UI thread and the measurement will be worthless.

---

## 4. Where it lands in the code

| Concern | File |
|---|---|
| `fx_*` signatures + the current inert dispatch | `Sources/NullPlayer/WinampModern/WinampModernScriptRuntime.swift` (~840, ~1732) |
| Per-object FX state (enabled, grid, flags, speed) | new — keep it beside the object's other runtime state, not in XML attributes, unless you want it in the graph dump |
| Interpreter return value | `Sources/NullPlayer/WinampModern/MakiBytecode.swift` (`execute`, ~510) |
| Where a layer is drawn | `Sources/NullPlayer/WinampModern/WasabiRenderer.swift` — `drawImage(_:in:context:)` ~1020, the layer branch ~1060–1081, `drawAnimated` ~1377 |
| Repaint cadence | `Sources/NullPlayer/Windows/WinampModern/WinampModernMainView.swift` — the 30 Hz animation timer already exists for animated layers; FX layers must join it |

Mesh drawing in CoreGraphics: there is no free-form mesh primitive, so the practical shapes are
(a) draw the image into a scratch `CGContext` per warped quad with a clip + affine transform per grid
cell, or (b) recognise the affine special case (rotation about the centre — which is what every
needle in this corpus actually is) and apply a `CGAffineTransform`, falling back to (a) for a genuine
warp. Option (b) first is defensible **if** the general path follows and is documented as the fallback
— but decide it from a measurement of what the corpus asks for, not from convenience. Check T800 and
Winamp Modern too (`rectrgn`/fx usage counts are in TASKS §22.5).

---

## 5. Also open, in priority order after FX

1. **The speaker cones are a confirmed second defect — and it is not Layer FX.** Live check by the
   user, 2026-08-18, with the windows now openable (27.7): **the cones do not animate.**

   `animatedlayer#SpeakerVis` uses no FX at all. `SPEAKER.maki` reads `getVisBand` (implemented in
   Phase 27) and calls `gotoFrame`, and it starts its own `Timer` (`new Timer` → `setDelay` →
   `start`) from **`onSetVisible`**. Ranked hypotheses, in the order worth testing — the
   investigation was stopped here, so treat all three as unverified:

   1. **`onSetVisible` is never dispatched when the window is shown** (most likely, and a consequence
      of how 27.7 opens them). `WinampModernMainWindowController.toggleSkinWindow` calls
      `window.orderFront(nil)` — an AppKit operation that never touches the Wasabi graph, so no
      `onsetvisible` reaches that container's layout script and the timer is never started. Confirm
      by logging `onsetvisible` dispatch on show; the fix is to dispatch it to the container/layout
      the way `show`/`hide` already do for a graph object (Phase 24 wired that for objects, not for a
      native window being ordered in).
   2. **The script's mutation may never repaint that window.** `scripts.graphDidMutate` is installed
      only by the view that owns the runtime (`drivesScripts: true`); auxiliary views are built with
      `drivesScripts: false`, so a `gotoFrame` from the speaker's timer marks the *main* view dirty,
      not the speaker window. The aux view does start its own 30 Hz animation timer when its scene
      contains an `animatedlayer` (which `SpeakerVis` is) and that block appears ungated — so this
      alone probably would not freeze them, but rule it out rather than assume it.
   3. **`getVisBand` may read zero in that window.** The host instance is shared with the main view
      and `host.spectrumLevels` is fed by `WinampModernMainView.updateSpectrum`, so it should be
      populated — but confirm `beginVisualizationConsumption()` is in effect for this skin, and see
      the scale caveat in item 2 below.

   Related known gap: `default_visible="1"` on an auxiliary container is still not honoured
   (TASKS §26.11), so Defix's `Config` does not open *with* the skin as it does in Winamp — it is
   merely reachable from the menu now.
2. **`getVisBand` calibration is deliberately unverified** (TASKS §27.5). It resamples the bar-display
   tap, which is normalised so bars fill their window; Winamp's vis bytes are raw FFT magnitude. If
   the cones (or any spectrum-fed meter) read as pinned or twitchy once they move at all, that is the
   next thing to measure — against the reference video, at a known loudness.
3. **`getcurrentindex`** — Defix's `PLAYLIST_WINDOW.ontargetreached` still aborts on it
   (`failed=ontargetreached: … does not support method 'getcurrentindex'`). Part of the playlist-editor
   script API in TASKS §27.4; small and self-contained.
4. The rest of TASKS §27.4 (`setScale`, `rightclickaction`/`dblclickaction`, the host menu actions
   including `colorthemes_switch`, `VISCON` never listed by `RENDER-DUMP containers`).

---

## 6. What Phase 27 landed (context you inherit)

- **`System.getVisBand(channel, band)`** — vis byte 0…255 off the shared mono spectrum tap, band
  resampled into Winamp's fixed 0…75 scale. Both channels answer from the one tap.
- **`<AlbumArt>.isLoading()`** — from `NowPlayingManager.isLoadingArtwork`; stopped Defix's playlist
  window aborting its `ontimer` every tick.
- **`getLeftVUMeter`/`getRightVUMeter` re-based on the stereo RMS level model** (27.5) — they used to
  take a peak band off the mono spectrum tap and call the halves left/right, which pinned every
  needle. They now share `PeppyMeterLevelModel` (its consumer id is injectable so two surfaces can
  hold the tap). **This is what made P-402 and Technics work**, and it is the reason those two are
  the proof that the level path is sound and the *rotation* path is what is missing.
- **Skin Settings window** (`WinampModernSkinSettingsWindowController`) — lists what a skin registered
  with `newAttribute`, grouped by item, written back through the one `setConfigAttribute` route. This
  is how the eight display styles above became selectable at all; without it only the shipped default
  was ever reachable. Probe with `WINAMP_MODERN_RENDER_SETTINGS=1`.
- **Skin Windows menu** (27.7, from the live report *"there is no way to open the speaker windows"*).
  A `.wal` skin declares windows it binds no button to and expects **Winamp's** Windows menu to open
  them. Defix's two speaker cabinets and its configurator were built, rendered, ordered out, and
  unreachable. The listing rule is the skin's own markup, not a heuristic: a container is offered when
  it carries `name=` and does **not** carry `nomenu="1"` — Defix marks its `browserpro`, `notifier`
  and two `searchresults` popups `nomenu="1"`, and leaves `SUI`/`VISCON` unnamed because its own
  buttons reach those. Containers the surface catalog already routes are excluded too, or the playlist
  would have two entry points (`WinampModernSurfaceCatalog.routedContainerIDs` — kind alone is not
  enough, since Defix's `pledit` declares no component GUID and is recognized from the inventory).
  Measured across the corpus: Defix → `SPEAKER 1`, `SPEAKER 2`, `Skin Settings`; mmd3 → `ColorThemes`;
  cPro-Bento → `Widgets Manager`; CornerAmp → `Color Themes`; T800 → `Quadhelix Home`; stock Winamp
  Modern → none. Probe with `RENDER-DUMP skin windows:` in the harness.
- Tests: `WinampModernPhase27Tests` (13) + one in `WinampModernPhase5Tests`. Suite green (735).

## 7. How to reproduce the frozen meters

```bash
# 1. Headless: confirm the needle script binds fx_onGetPixelR and never runs it
WINAMP_MODERN_WAL="$HOME/Library/Application Support/NullPlayer/WinampModernSkins/Defix Hi-END 200.WAL" \
WINAMP_MODERN_RENDER_DUMP=/tmp/defix-dump \
WINAMP_MODERN_RENDER_SCRIPTS=1 WINAMP_MODERN_RENDER_SETTLE=1.5 \
swift test --filter WinampModernRenderDumpTests

# 2. What the skin registers (the styles are here)
WINAMP_MODERN_RENDER_SETTINGS=1 …same…

# 3. The grid sizes the needles ask for
WINAMP_MODERN_RENDER_DISASM=fx_setgridsize …same…

# 4. Which windows the Skin Windows menu offers (grep the same run)
#    RENDER-DUMP skin windows: ["SPEAKER 1", "SPEAKER 2", "Skin Settings"]

# 5. Live: Winamp Modern → Skin Settings…, pick a style under "Visualizer", play something.
#    P-402 and Technics move; the needle styles and the cassette reels do not.
#    Winamp Modern → Skin Windows → SPEAKER 1 / 2 opens the cabinets (27.7).
```

The render harness has **no audio**, so it can never show a meter moving. Every FX/level check ends
in the app, under playback. Budget for that: the loop is edit → build → run → watch, not `swift test`.
