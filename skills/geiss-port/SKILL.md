---
name: geiss-port
description: Implementation reference for NullPlayer's Geiss visualization engine — the BSD-3-Clause port of Ryan Geiss's Win32/DirectDraw/Winamp-2 visualizer onto macOS as a ProjectM-peer engine. Covers the CGeissCore C ABI, upstream-vs-port file split, indexed-framebuffer + palette-LUT render pipeline, Accelerate-based spectrum push, threading model, persistence, and the architectural deviation around upstream/main.cpp. Use when modifying anything under Sources/CGeissCore/, GeissEngine.swift, the spectrum/PCM path in VisualizationGLView for Geiss, or the engine-conditional Geiss menu in ModernProjectMView.
---

# Geiss Port Guide

Geiss is a second visualization engine in NullPlayer's modern visualizer window, switchable from the right-click **Visualization Engine** submenu alongside ProjectM. It is a port of the BSD-3-Clause upstream at `https://github.com/geissomatik/geiss` (HEAD pinned at `816f3f6a5ca70592da7583be70c06f6e3425d306`).

The port inherits the visualizer window's CVDisplayLink-driven render cadence, fullscreen toggle, and engine-switch lifecycle. It is **not** available in CLI/headless mode — `VisualizationType` is not exposed there, and a saved Geiss state on a CLI launch is ignored.

## File Layout

### `Sources/CGeissCore/`

| Path | Role |
|------|------|
| `include/GeissCore.h` | C ABI consumed by Swift. `GeissCore_create`, `_destroy`, `_resize`, `_addPCM`, `_setSpectrum`, `_render`, `_palette`, `_nextEffect`/`_prevEffect`/`_randomEffect`/`_selectEffect`, `_effectCount`/`_effectName`/`_currentEffectName`, plus `GeissCore_diag` for tests. |
| `include/win_compat.h` | Typedefs (BOOL/BYTE/DWORD/LONG/HWND/etc.), MSVC keyword shims (__forceinline/__declspec/__cdecl/WINAPI), helper macros (RGB/TEXT/_T/MAKEINTRESOURCE/min/max), inline no-op stubs for Win32 APIs the kept code paths reference. Lowercase `far`/`near` for 16-bit-memory-model leftovers in Effects.h. |
| `include/winamp_vis_stub.h` | Minimal API-compatible `winampVisModule` / `winampVisHeader` so upstream declarations parse. |
| `GeissCore.cpp` | C++ glue. Owns the `GeissCore` struct, the `geiss_now_ms()` monotonic clock (`mach_absolute_time` on Apple), the `geiss_set_geometry` helper, and all C ABI dispatch into the port translation unit. |
| `upstream/` | Verbatim BSD-3 source — `main.cpp`, `Effects.h`, `helper.{cpp,h}`, `proc_map.cpp`, `Proc_map.h`, `video.h`, `DEFINES.H`, `LICENSE`, `README.md`. Each retains its original copyright header. |
| `upstream_port/geiss_port.cpp` | Owns every global the upstream visual code expects (FXW/FXH/VS1/VS2/effect[]/mode/gXC/gYC/floatframe/intframe/etc.); `#include`s `Effects.h` directly; contains line-for-line ports of `FX_Init`, `FX_Pick_Random_Mode`, `FX_Fini`, `GenerateChunkOfNewMap`, `RenderFX`, `GetWaveData`, `RenderDots`, `RenderWave`, `FX_Random_Palette`, `PutPalette`, `CrankPal` from upstream `main.cpp` / `video.h`. |
| `PORT_NOTES.md` | Developer-only port log (asm audit, Win32 audit, file classification, phase status). **Not shipped in the .app.** |

### Compiled vs excluded

`Package.swift` excludes `upstream/main.cpp`, `upstream/LICENSE`, and `upstream/README.md` from the `CGeissCore` C++ target. Everything else under `upstream/` and all of `upstream_port/` is in the build.

`cxxSettings`: `headerSearchPath("upstream")`, `headerSearchPath("upstream_port")`, `headerSearchPath("include")`, `define("__APPLE__")`, `define("PLUGIN", "1")`, `define("GRFX", "0")`, `unsafeFlags(["-fno-strict-aliasing", "-fwrapv"])`.

`-fcxx-exceptions` is intentionally **not** set — `nm -u` confirmed `__cxa_throw` / `__cxa_allocate_exception` are not referenced.

## Architectural deviation: `upstream/main.cpp`

The plan's literal phase-4 exit criterion was "all upstream files compile". The port deviates: `upstream/main.cpp` (9557 lines, ~85% Win32 dialog procs / registry I/O / Winamp DLL entry / DirectDraw setup / screensaver shell) is in the tree but **excluded from compilation**.

The platform-neutral subset — `FX_Init`, `FX_Pick_Random_Mode`, `FX_Fini`, `GenerateChunkOfNewMap`, `RenderFX`, `GetWaveData`, `RenderDots`, `RenderWave`, plus all of `Effects.h` and the palette routines from `video.h` — is reproduced verbatim in `upstream_port/geiss_port.cpp` (which `#include`s `Effects.h`).

Why not `#ifdef`-gate `main.cpp`: the Win32 surface is interleaved with visual code throughout (the frame loop in `render1()` calls `lpDDSPrimary->Flip` mid-function; the auto-mode-switch logic sits inside `WindowProc2`'s message pump). Carving it cleanly with `#ifdef`s would still produce a translation unit that does nothing useful on macOS.

License compliance is preserved — `main.cpp` retains its BSD-3 header and ships with the source. Compilation status is not a license requirement.

## Render Pipeline

Geiss writes 8-bit palette indices into a CPU framebuffer; Swift uploads that buffer + the 256-entry RGBA palette as GL textures and resolves the final color in a fullscreen fragment shader.

### Per-frame sequence (`GeissCore_render`)

Mirrors upstream `main.cpp:3756 render1()`:

1. `RenderFX()` — effect overlays into VS1
2. `Process_Map(VS1, VS2)` — bilinear-blend warp through DATA_FX (portable C; the upstream MSVC `__asm` dispatcher in `proc_map.cpp` is gated `#if 0`)
3. `GetWaveData()` — populate `g_power[]` / `g_power_smoothed[]`, beat-detect, smoothing, centroid
4. `RenderDots(VS2)` — audio-driven dot bursts (NUCLIDE)
5. `RenderWave(VS2)` — 7 waveform-render modes + beat detect + slide-shift
6. Swap `VS1 ↔ VS2`
7. `memcpy(indexBuf, VS1, FXW*FXH)` — copy to caller buffer
8. `GenerateChunkOfNewMap(false, 0)` — advance warp-map generation by one row of pixels; when chunk completes (`y_map_pos` returns to -1), call `FX_Pick_Random_Mode()` to auto-cycle modes (the role upstream's GeissProc thread played)

### Swift side (`GeissEngine`)

- 256-entry RGBA palette texture (`256x1 GL_RGBA8`, LINEAR filter)
- `width × height` index texture (`GL_R8`, NEAREST filter, written via `glTexSubImage2D` each frame)
- Fullscreen-quad GLSL: `frag = texture(palette, vec2(texture(indices, uv).r, 0.5))`
- Vertex layout flips V so framebuffer y=0 is at top of screen

## Audio path

### PCM (waveform)

`VisualizationGLView` forwards mono PCM from the audio engine to `GeissEngine.addPCMMono` → `GeissCore_addPCM` → `geiss_port_set_pcm`, which clamps float samples to Winamp's signed-8-bit-biased convention (`128 == silence`, `0/255 == extremes`) and writes into the stub `winampVisModule.waveformData`.

### Spectrum

Geiss has no internal FFT — upstream consumes spectrum from the Winamp host. The Swift side computes it:

- `VisualizationGLView` allocates one Accelerate FFT setup per view: `vDSP_create_fftsetup(log2N=9, kFFTRadix2)`, plus a Hann window and split-complex scratch buffers (size 256 each), all reused — no per-frame allocation.
- 256-bin magnitude spectrum from a 512-sample real FFT via `vDSP_fft_zrip`. Magnitudes normalized with `2/N` scaling (`geissSpectrumScale = 2.0/512.0`), then a `sqrt` response curve so quiet treble stays visible without clipping bass peaks.
- `projectMPCMGain` is applied **before** the FFT, so the existing audio-sensitivity control affects Geiss too.
- Push happens from the audio callback only when `currentEngineType == .geiss`. The push uses `engineLock.try()` to avoid blocking the audio thread behind render or engine-swap work; on contention, Geiss keeps its previous host spectrum until the next callback.

### Threading model

- Audio thread → `addPCMMono` / `setSpectrum`: each takes `coreLock` (NSLock) on the C core. `engineLock.try()` is the outer guard against engine-swap; `coreLock` is the inner guard against render.
- Render thread (CVDisplayLink) → `renderFrame`: takes `coreLock`. Framebuffer is never reallocated mid-stream and never accessed from any other thread.
- Main actor → `setViewportSize`: takes `coreLock`, calls `GeissCore_resize` (which is permitted to reallocate the framebuffer via `FX_Fini` + `FX_Init`), then resizes the GL index texture.
- Engine swap (`switchEngine` in `VisualizationGLView`): take `engineLock`, make the view's GL context current, `cleanup()` the old engine (`GeissCore_destroy` + GL teardown), then defer construction of the new engine to the next render. No frame is rendered between the two.

The C core is **not** thread-safe; `coreLock` is the only barrier.

## Effect catalog

25 user-reachable effect modes (1–25), enumerated by index 0–24 over the C ABI. Names are formatted on demand as `"Mode N"` into a per-core static buffer — there is no name table. The active mode is `new_mode` if non-zero, else `mode`.

`GeissCore_nextEffect` / `_prevEffect` set `new_mode` and force `y_map_pos = -1`, `g_rush_map = 1` so the next `GenerateChunkOfNewMap` rebuilds the warp map immediately. `GeissCore_randomEffect` calls `FX_Pick_Random_Mode()`.

Auto-cycling: on every render, when the current chunk finishes applying (`y_map_pos` transitions to -1), `FX_Pick_Random_Mode()` is called. There is no explicit cycle interval — cadence is governed by chunk completion.

### Hidden modes in upstream

`upstream/main.cpp` actually contains warp-map branches for **33 modes**: 1–30, 34, 35, 37. Modes 26–30, 34, 35, 37 are dead code in upstream too — unreachable because:

1. `#define NUM_MODES 25` (`upstream/main.cpp:1191`) caps `FX_Pick_Random_Mode`'s roll at `[1, 25]`.
2. `char_to_mode[]` (`upstream/main.cpp:3987-4006`) only binds keyboard shortcuts to modes 1–20.

The inline comment `25//16//19` shows the cap moved up over upstream releases (19 → 16 → 25), so these look like work-in-progress / abandoned modes Ryan left behind the gate. The port's hard-coded `25` in `GeissCore_effectCount` matches upstream's user-facing behavior exactly. **Do not raise the cap without first auditing modes 26–30/34/35/37** — they may rely on globals or assets that no longer exist, or produce visibly broken output.

## Palette pipeline

- `FX_Random_Palette(bLoadPal)` generates the next palette into `ape2[]`, either by replaying one of 4 monotone REMAP/REMAP2/REMAP3 LUTs or by blending three `CrankPal` curves with the current `gamma`. Sets `iBlendsLeftInPal = 18`.
- `PutPalette()` runs the per-frame cross-fade from `ape[]` toward `ape2[]`. Upstream's `lpDDPal->SetEntries(...)` (gated `#if (GRFX==1)`) is replaced by a copy from `apetemp[]` into a port-owned 256×4 RGBA buffer `s_geiss_palette_rgba`.
- `geiss_port_get_palette(out)` returns a snapshot. **Note**: Geiss's `PALETTEENTRY` uses `peRed/peBlue/peGreen` ordering (not Win32's standard `peRed/peGreen/peBlue`). The port preserves that ordering for fidelity but swaps green/blue when packing into the RGBA snapshot so the GL fragment shader sees true RGB.
- `GeissCore_create` seeds the initial palette synchronously: calls `FX_Random_Palette(false)` then runs the 18-frame cross-fade pump (`while (iBlendsLeftInPal > 0) PutPalette();`) so the first `GeissCore_palette` returns non-black. Upstream's `doInit()` did this; `doInit` is part of the excluded Win32 surface.

## Persistence

- UserDefaults key `visualizationEngineType` stores the active engine raw value (`"Geiss"` or `"ProjectM"`).
- The saved `AppState.v2` session model intentionally does not persist the engine type; UserDefaults is the single source of truth. Old saved states that contain `visualizationEngineType` still decode because unknown keys are ignored.
- Restore order: `restoreSettingsState` leaves the UserDefaults key intact, then defers to the visualizer window construction, then calls `wm.switchVisualizationEngine(to:)` using the current UserDefaults value. Preset index restoration is gated on `visualizationEngineType == .projectM`.

## Engine-conditional UI

`Sources/NullPlayer/Windows/ModernProjectM/ModernProjectMView.swift`:

- ProjectM-specific submenus (Presets, Preset Cycle, Beat Sensitivity, ratings overlay, preset-change notifications) are wrapped behind `currentEngineType == .projectM`.
- When Geiss is active, `addGeissEffectsMenuItems(to:)` adds Next / Previous / Random Effect plus an Effects submenu listing modes 1–25 with the active mode checkmarked.
- Keyboard handlers for `→` / `←` / `r` route to `nextGeissEffect` / `previousGeissEffect` / `randomGeissEffect` when Geiss is active, or the ProjectM equivalents otherwise.

## Diagnostic accessor

`GeissCore_diag(core, &out)` populates a `GeissCoreDiag` with `active_mode`, `new_mode`, `y_map_pos`, `frames_this_mode`, `effects[9]`, `gXC`, `gYC`, `iDispBits`, `FXW`, `FXH`. Used by `Tests/NullPlayerAppTests/GeissEngineSmokeTests.swift` to verify the lifecycle (`create → addPCM → setSpectrum → render×N → palette → destroy`) accumulates non-zero pixels and that `nextEffect` advances the active mode within 60 frames.

## Licensing

- `Sources/NullPlayer/Resources/ThirdPartyLicenses/GEISS_LICENSE.txt` ships in `NullPlayer.app/Contents/Resources/`.
- About box / Credits: "Geiss visualization © Ryan M. Geiss, BSD-3-Clause".
- Each `.cpp` / `.h` under `upstream/` retains its original BSD-3 copyright header unmodified.
- `PORT_NOTES.md` is developer-only and **not** shipped in the .app.

## Gotchas

- **The `GeissCore_render` loop must stay in the order RenderFX → Process_Map → GetWaveData → RenderDots → RenderWave → swap → memcpy → GenerateChunkOfNewMap.** Reordering breaks upstream parity in subtle ways — `Process_Map` reads VS1 and writes VS2; `RenderDots`/`RenderWave` overlay onto VS2; the swap puts the just-rendered frame into VS1 for next frame's warp source.
- **Strict-aliasing UB is intentional.** `GenerateChunkOfNewMap` writes `*((int *)(DATA_FX2 + A_offset + 4)) = R_offset_rel * bytewidth;` with byte-stride pointer arithmetic. `DATA_FX2` is 16-byte-aligned; `A_offset` is always a multiple of 8, so `+4` lands on 4-byte alignment — clean on ARM64. `Package.swift` sets `-fno-strict-aliasing` to make the alias well-defined for clang.
- **`FX_Fini` calls `free()`, not `delete`.** Upstream's `FX_Fini` had a `delete malloc-buffer` mismatch that was UB-but-worked on MSVC. The port corrects this — pair `malloc` with `free`.
- **16-byte alignment uses `uintptr_t`.** Upstream cast pointers through `unsigned long` (32-bit on Win64, 64-bit on macOS — accidental). The port uses `uintptr_t` correctly.
- **`bMMX = false`** unconditionally in `geiss_port.cpp`. Apple Silicon has no MMX; the upstream MMX dispatcher in `proc_map.cpp` is `#if 0`-gated.
- **DirectDraw blit paths in `video.h` are dead code** (`#if (GRFX==1)`, defined as 0). The 6 MMX `__asm` blocks there have no portable replacement — the indexed framebuffer is the final output on macOS. `video.h` is kept in tree for BSD-3 redistribution + reference, but no part of it is `#include`d by `geiss_port.cpp`.
- **REMAP / REMAP2 / REMAP3 pointers** must be wired to `_REMAP_VALUES[0..512]` early in `FX_Init`. Upstream relied on `doInit()` to do this; the macOS port has no `doInit`.
- **`g_rush_map` is `BOOL`-typed** in `geiss_port.cpp`, which `win_compat.h` typedef's to `int`. Match that linkage in any new `extern` declarations.
- **`GeissCore_resize` reallocates the framebuffer** via `FX_Fini` + `FX_Init`. The Swift render thread's `indexBuf` pointer must be re-fetched after resize — `GeissEngine.setViewportSize` reallocates `indexBuf` and re-uploads `glTexImage2D` storage for the index texture.
- **Spectrum push is best-effort.** The audio callback uses `engineLock.try()`, not `lock()`. If contended (engine swap, render in flight), Geiss keeps its previous host spectrum. This is intentional — the audio thread must not stall.

## Key files

- `Sources/CGeissCore/include/GeissCore.h` — C ABI
- `Sources/CGeissCore/GeissCore.cpp` — C++ glue, geometry helper, monotonic clock
- `Sources/CGeissCore/upstream_port/geiss_port.cpp` — port translation unit, owns globals, ports of FX_*/RenderFX/GetWaveData/RenderDots/RenderWave/palette
- `Sources/CGeissCore/upstream/Effects.h` — verbatim effect routines, compiled via `#include` from `geiss_port.cpp`
- `Sources/CGeissCore/upstream/proc_map.cpp` — `Process_Map` portable-C bilinear-blend warp; asm dispatcher `#if 0`-gated
- `Sources/CGeissCore/PORT_NOTES.md` — developer log
- `Sources/NullPlayer/Visualization/GeissEngine.swift` — `VisualizationEngine` conformance, GL textures, fullscreen-quad shader, `coreLock`
- `Sources/NullPlayer/Visualization/VisualizationGLView.swift` — engine selection, FFT/spectrum compute, PCM forwarding, `engineLock`
- `Sources/NullPlayer/Visualization/VisualizationEngine.swift` — `VisualizationType.geiss` case
- `Sources/NullPlayer/Windows/ModernProjectM/ModernProjectMView.swift` — engine-conditional menu, Geiss Effects submenu
- `Sources/NullPlayer/App/AppStateManager.swift` — ProjectM preset index session restore; engine type remains a UserDefaults preference
- `Tests/NullPlayerAppTests/GeissEngineSmokeTests.swift` — lifecycle smoke test
- `Sources/NullPlayer/Resources/ThirdPartyLicenses/GEISS_LICENSE.txt` — bundled license

## Configuration Levers (Phase 1)

User-facing controls for Geiss parameters are exposed via a two-level ABI: C ABI (`GeissCoreConfig` struct + getters/setters in `geiss_port.cpp`), wrapped by Swift (`GeissEngine.Config` + accessors in `GeissEngine.swift`), persisted in `UserDefaults`, and surfaced via context-menu toggles and submenus in `ModernProjectMView` and `ProjectMView`.

### C ABI surface

| Symbol | Role | Notes |
|--------|------|-------|
| `GeissCoreConfig` (struct) | Packed config container, 9 fields | See `GeissCore.h:69-78` |
| `GeissCore_getConfig(core, &out)` | Read current file-scope statics | Implemented in `geiss_port.cpp:2404` |
| `GeissCore_setConfig(core, &cfg)` | Write file-scope statics; trigger side effects | `gamma` rebuild, `autoSwitchSeconds` → frames, etc. |
| `GeissCore_randomizePalette(core)` | Trigger immediate palette shuffle | Extracted from `FX_Random_Palette` body (mirrored upstream `main.cpp`'s hotkey logic) |

### Port edits (§0)

1. **`GeissCore.cpp:246`** — gate `FX_Pick_Random_Mode()` on `!bLocked` so user-set mode lock survives chunk completion.
2. **`geiss_port.cpp:1622`** — guard `bLocked = FALSE;` so mode lock is not automatically cleared on mode change.
3. **`geiss_port.cpp:213` (registry write)** — `setConfig` converts user seconds value to frames using live `fps`, writes to `frames_til_auto_switch__registry`. The existing render path picks it up.

### Upstream symbol mapping

| Field | Upstream symbol | Type | Default |
|-------|-----------------|------|---------|
| `sensitivity` | `volscale` (`geiss_port.cpp:281`) | float | `0.20f` |
| `gamma` | `gamma` (`geiss_port.cpp:214`) | int 0–200 | `10` |
| `beatDetection` | `g_bUseBeatDetection` (`geiss_port.cpp:334`) | BOOL | TRUE |
| `syncColorToSound` | `g_bSyncColorToSound` (`geiss_port.cpp:335`) | BOOL | FALSE |
| `slideShift` | `g_bSlideShift` (`geiss_port.cpp:300`) | bool | true |
| `modeLocked` | `bLocked` (`geiss_port.cpp:315`) | bool | false |
| `paletteLocked` | `bPalLocked` (`geiss_port.cpp:316`) | bool | false |
| `autoSwitchSeconds` | `frames_til_auto_switch__registry` (`geiss_port.cpp:213`) | int, seconds | derived from `550` / fps |
| `visMode` | `visMode` (`geiss_port.cpp:373`) | visModeEnum (0=wave, 1=spectrum) | wave (0) |

### UserDefaults keys

```text
geiss.sensitivity       (Float)
geiss.gamma             (Int)
geiss.beatDetection     (Bool)
geiss.syncColorToSound  (Bool)
geiss.slideShift        (Bool)
geiss.modeLocked        (Bool)
geiss.paletteLocked     (Bool)
geiss.autoSwitchSeconds (Int)
geiss.visMode           (Int)
```

Read with `object(forKey:)` in `VisualizationGLView.loadGeissConfigFromDefaults()` so missing keys ≠ zero. Applied to `GeissEngine` immediately after construction in `.geiss` case of `createEngine(type:width:height:)`.

### Menu surface

Context-menu items (right-click in visualization window) added via `GeissMenuBuilder.addGeissConfigMenuItems(to:target:visualizationView:)`:

- **Toggles** (checkmark on click): Beat Detection, Sync Color to Sound, Slide Shift, Mode Lock, Palette Lock
- **Submenus**:
  - "Geiss Sensitivity": 0.25×, 0.5×, 1.0×, 2.0×, 3.0×, 4.0× (checkmark on current closest value)
  - "Gamma": 1.00×, 1.25×, 1.50×, 2.00×, 2.50×, 3.00× (0, 25, 50, 100, 150, 200)
  - "Auto-Switch": 5s, 15s, 30s, 60s, 120s (no "Off" — use Mode Lock to stop)
  - "Waveform Mode": Wave, Spectrum
- **Action**: "Randomize Palette" (triggers `GeissCore_randomizePalette`)

Both `ProjectMView` (classic) and `ModernProjectMView` (modern) conform to `GeissMenuTarget` protocol and invoke the builder from `addGeissEffectsMenuItems(to:)` (after the Effects submenu). Menu state reflects `VisualizationGLView.getGeissConfig()` at render time.

### Deferred to future phases

- Per-mode effect probability/limit tables (`modeprefs`)
- Palette frequency controls (`solar_pal_freq`, `coarse_pal_freq`)
- Per-shape waveform selection (requires gating `geiss_port.cpp:1605` mode-change path)
