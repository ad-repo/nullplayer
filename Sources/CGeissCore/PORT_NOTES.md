# Geiss Upstream Port Notes

Developer-only running log for the Geiss port. Not shipped in the .app.

## Upstream commit pinned

- Repo: https://github.com/geissomatik/geiss
- HEAD SHA at vendor time: `816f3f6a5ca70592da7583be70c06f6e3425d306`
- License: BSD-3-Clause (see `LICENSE` in this directory)

## Phase status

- Phase 1: complete (stub engine, protocol seam, no upstream code in build).
- Phase 2: complete — vendored upstream verbatim into `Sources/CGeissCore/upstream/`,
  added `exclude: ["upstream"]` in `Package.swift` so nothing here is compiled yet,
  and recorded the audit below. **No upstream files were modified.**
- Phase 3 (this file): complete — Win32-shell files deleted from `upstream/`;
  remaining files have all `<windows.h>`, `<ddraw.h>`, `<dsound.h>`, `<vis.h>`,
  etc. include directives stripped (replaced with `// PORT(phase3): stripped …`
  marker comments — angle brackets are intentionally absent so the exit-criterion
  grep stays clean); all three `GetTickCount()` calls in `main.cpp` rewritten
  to `geiss_now_ms()`; `helper.cpp` rewritten with POSIX (`sysctlbyname` on
  Apple, `sysconf` elsewhere) replacing `GetLogicalProcessorInformation`;
  `geiss_now_ms()` and a `GeissAudioState` struct (replacing Winamp `vis.h`'s
  host audio buffers) added in `GeissCore.cpp`; `GeissCore_addPCM` /
  `GeissCore_setSpectrum` now populate `GeissAudioState`. **Upstream files
  remain excluded from the build** — phase 4 wires them in. The body deletions
  for dialog procs, registry I/O, and Winamp plugin entry described in the
  plan's Phase-3 work list are deferred to phase 4 as part of the
  compile-and-fix walk; only the strict exit-criterion grep is enforced now
  (`<windows.h>|<ddraw.h>|GetTickCount` → no hits).
- Phase 4c-6 (this commit): direct ports of `GetWaveData`, `RenderDots`,
  `RenderWave`, `RenderFX` from upstream main.cpp:7948-9481.
  * `GetWaveData` implements only the PLUGIN branch (DirectSound capture
    is not in the build path); reads `g_this_mod->waveformData` /
    `spectrumData` for level-trigger, smoothing, centroid normalisation,
    and FFT-based fourier analysis (`g_power[]`, `g_power_smoothed[]`).
  * `RenderDots` is the audio-driven dot-bursts (NUCLIDE effect).
  * `RenderWave` covers all 7 waveform-render modes verbatim, plus beat
    detection (`bBeatMode`/`bBigBeat` thresholds) and slide-shift
    triggering.
  * `RenderFX` is the per-frame effect dispatcher — calls ShadeBobs,
    Two_Chasers, Solid_Line, One_Dotty_Chaser, Nuclide, Grid,
    Drop_Solar_Particles* (all already compiled via Effects.h),
    Diminish_Center, plus PutPalette via the iBlendsLeftInPal blend
    pipeline.
  * `geiss_port_set_pcm` / `geiss_port_set_spectrum` populate the
    Winamp-stub module's audio arrays (8-bit unsigned, biased by 128 per
    Winamp vis convention) — `GeissCore.cpp` will delegate
    `GeissCore_addPCM` / `GeissCore_setSpectrum` through these in 4c-8.
  * `geiss_port_init_module` wires `g_this_mod = &s_geiss_stub_module`.
  * `AdjustRateToFPS` (upstream main.cpp:548) lands as an inline helper.
- Phase 4c-5: direct port of `GenerateChunkOfNewMap`
  (upstream `main.cpp:4312-5411`). The function builds DATA_FX2
  incrementally — one row of pixels per call — until a full frame's
  worth of warp-map weights + per-pixel cumulative-delta lookat offsets
  is written. When the chunk completes (`y_map_pos` reaches
  `(FXH-FX_YCUT)*FXW`) DATA_FX and DATA_FX2 swap so the new map takes
  effect on the next `Process_Map` invocation. All 25 modes (1–25) and
  the rotation-dither / custom-motion-vector branches are preserved
  verbatim. Win32-only call sites (`Get/WritePrivateProfileString`)
  survive but route through no-op stubs in `win_compat.h`. The
  cumulative-delta lookat offset write
  `*((int *)(DATA_FX2 + A_offset + 4)) = R_offset_rel * bytewidth;`
  relies on `-fno-strict-aliasing` (set in `Package.swift`'s
  cxxSettings) — same behaviour as upstream MSVC.
- Phase 4c-4: direct ports of `FX_Init`,
  `FX_Pick_Random_Mode`, `FX_Fini` from upstream `main.cpp:3869-4304`. The
  CModeInfo class (upstream `main.cpp:1258-1330`) and the
  `mode_motion_dampened` / `rotation_dither` / `custom_motion_vectors`
  arrays land here verbatim. The Win32 `GetWindowsPath` and `finiObjects`
  calls are replaced with no-op port helpers; `delete` calls in upstream
  `FX_Fini` are corrected to `free()` to pair with `FX_Init`'s `malloc`
  (the upstream code's `delete malloc-buffer` mismatch was undefined
  behaviour that happened to work on MSVC). The 16-byte alignment fix-up
  uses `uintptr_t` instead of upstream's `unsigned long` (which is 32-bit
  on Win64 but 64-bit on macOS — the original cast worked accidentally).
  REMAP / REMAP2 / REMAP3 pointers are wired to `_REMAP_VALUES[0..512]`
  early in `FX_Init` (upstream relies on `doInit()` to do this; the macOS
  port has no `doInit`).
- Phase 4c-3: `upstream/Effects.h` is now compiled directly
  into the build via `geiss_port.cpp`'s `#include`. ~1000 lines of real
  Geiss visual algorithms (`ShadeBobs`, `Diminish_Center`,
  `Drop_Solar_Particles_320`, `Drop_Solar_Particles`, `Solid_Line`,
  `Two_Chasers`, `Nuclide`, `Neutrons`, `One_Dotty_Chaser`, `Mode6Edges`,
  `Grid`, `DoCrystals`, `LoadPreset`, `SavePreset`, `LoadCustomMsg`)
  link cleanly. The file's full set of upstream globals (FXW/FXH/VS1/VS2/
  effect[]/mode/gXC/gYC/floatframe/intframe/center_dwindle/old_palette/…)
  is defined in `geiss_port.cpp` mirroring the upstream main.cpp 540–1330
  range. `PLUGIN=1` is defined so PLUGIN-conditional branches take the
  Winamp-vis path; `GRFX=0` is defined so DirectDraw blit paths in
  upstream code are gated out. `win_compat.h` gains lowercase `far` /
  `near` defines for 16-bit-memory-model leftovers (`unsigned char far *`
  parameters in `Solid_Line` etc.). Provisional stubs for
  `FX_Random_Palette` / `PutPalette` / `CrankPal` / `GenerateChunkOfNewMap`
  keep the link clean — real ports land in 4c-5 / 4c-7.
- Phase 4c-1+2: introduces the port scaffolding for
  preserving the *real* Geiss visual algorithms on macOS without trying to
  carve up upstream/main.cpp's 9557 lines of mixed Win32 + visual code.
  New files:
  * `include/win_compat.h` — typedefs (BOOL/BYTE/DWORD/LONG/HWND/HFONT/etc.),
    calling-convention macro stubs (WINAPI/CALLBACK/__cdecl/__forceinline/
    __declspec/FAR/PASCAL), helper macros (RGB, TEXT, _T, MAKEINTRESOURCE,
    min/max), inline no-op stubs for Win32 APIs the kept-but-non-rendering
    code paths reference (SetCursor, OutputDebugString, MessageBox,
    Get/WritePrivateProfileString, GetWindowText, GetCursorPos).
  * `include/winamp_vis_stub.h` — minimal API-compatible
    `winampVisModule`/`winampVisHeader` so upstream declarations parse.
  * `upstream_port/geiss_port.cpp` — owner of every global the upstream
    visual code expects (FXW, FXH, FX_YCUT_*, DATA_FX, VS1, VS2, iDispBits,
    slider1, bMMX, bBypassAssembly, core_clock_time, initial_map_offset).
    Currently only provides the global-definition site; subsequent
    sub-phases (4c-3..4c-8) include `upstream/Effects.h` directly into
    this translation unit and add ports of FX_Init / GenerateChunkOfNewMap /
    RenderFX / GetWaveData / RenderDots / RenderWave / FX_Random_Palette /
    PutPalette / CrankPal.
  Build wiring: `Package.swift` adds `headerSearchPath("upstream_port")`,
  drops `GEISS_PHASE_4B_STUBS` (geiss_port.cpp is now the authoritative
  global-definition site), and `proc_map.cpp`'s phase-4b stub block is
  removed. `upstream/main.cpp` stays excluded from the build but in tree —
  BSD-3 source-redistribution + canonical reference for the ports.
- Phase 4b: `upstream/proc_map.cpp` now compiles. The 24
  inline-`__asm` naked-function blocks (the runtime-pasted x86-32 dispatcher)
  are gated behind `#if 0`. `Process_Map` is rewritten as a portable C
  bilinear-blend warp — a direct port of the upstream `bBypassAssembly`
  fallback the original code already shipped (just commented out).
  `proc_map.cpp` defines stub globals (`FXW`, `FXH`, `DATA_FX`, etc.) under
  `#ifdef GEISS_PHASE_4B_STUBS`; the define is set in `Package.swift`'s
  `cxxSettings` and will be removed when `main.cpp` joins the build in a
  later sub-phase. Asm-block annotations from the phase-2 audit can now read
  "replaced by portable C in `Process_Map`" for all 18 `_proc_map_*` blocks
  and the 3 in-body filter passes; the 6 `video.h` MMX blocks are still
  pending (they'll be deleted with the surrounding DDraw-blit code).
  Header-include case fixed: `"proc_map.h"` → `"Proc_map.h"` to match the
  on-disk filename and silence clang's `-Wnonportable-include-path`.
- Phase 4a: `upstream/helper.cpp` is now in the compile set
  (`Package.swift` narrows the `exclude` list from `["upstream"]` to just
  `main.cpp`, `proc_map.cpp`, `LICENSE`, `README.md`). `helper.h` is on the
  internal header search path via `cxxSettings: [.headerSearchPath("upstream")]`.
  This is the proof-of-build for upstream files; the real engine wiring waits
  on subsequent sub-phases.
- Phase 4b–4z: pending — upstream `main.cpp` Win32-body deletion, `proc_map.cpp`
  asm rewrite (24 blocks → portable C dispatcher), `video.h` MMX/blit prune,
  effect-core wiring through the C ABI, then first real Geiss render.

## File classification

Each upstream file is marked KEEP (effect core, will be ported in phase 3+) or
DELETE-IN-PHASE-3 (Win32 shell — Winamp plugin glue, screensaver entry points,
DirectDraw / DirectSound / DirectInput, Win32 dialogs, registry, MFC, CPU
detection, Win32 resource scripts).

| File | Class | Notes |
|---|---|---|
| `main.cpp` | KEEP (heavy strip) | 9557 lines. Contains the frame loop, palette/beat/effect-switch logic that we need, but also Win32 shell, dialogs, registry, Winamp plugin entry. Phase 3 strips Win32 includes and dialog/reg/Winamp-entry function bodies; keeps frame/palette/beat code. |
| `Effects.h` | KEEP | 1069 lines of pure effect routines. No `__asm`, no Win32. Should compile under clang nearly as-is (audit casts in phase 4). |
| `proc_map.cpp` | KEEP (asm rewrite) | Per-pixel transformation engine. 24 `__asm` blocks (see "Asm blocks" below) — must be replaced with portable C in phase 4. |
| `Proc_map.h` | KEEP | Includes `<time.h>` only; no Win32. Should compile clean. |
| `video.h` | KEEP (asm rewrite) | Effect routines with 6 MMX/`__asm` blocks (memcpy/blit variants). Replace with portable C in phase 4. |
| `helper.cpp` | KEEP (strip) | Utility helpers; pulls in `<windows.h>`, `<malloc.h>`, `<tchar.h>`. Strip Win32 / use plain C runtime in phase 3. |
| `helper.h` | KEEP | No Win32 in the header itself. |
| `DEFINES.H` | KEEP | Pure `#define`s; review for any Win-typedef leaks. |
| `Sysstuff.h` | DELETE-IN-PHASE-3 | CPU detection, MMX `emms`, `__try`/SEH, `<dinput.h>`. Replace any required helpers (CPU feature flags) with stubs returning the macOS truth — Apple Silicon has no MMX. 22 Win32 hits, 4 `__asm` blocks. |
| `SOUND.CPP` / `SOUND.H` | DELETE-IN-PHASE-3 | DirectSound *input* (audio capture). NullPlayer supplies PCM via `GeissCore_addPCM`; no replacement needed. |
| `outsound.cpp` / `outsound.h` | DELETE-IN-PHASE-3 | DirectSound *output*. Not used — NullPlayer owns audio out. |
| `VIS.H` | DELETE-IN-PHASE-3 | Winamp 2 vis SDK header. Replaced by our own `GeissAudioState` in phase 3. |
| `GETDXVER.H` | DELETE-IN-PHASE-3 | DirectX version probe (`<dinput.h>`). |
| `CPU_MHZ.H`, `CPU_TYPE.H`, `CYRIX.H` | DELETE-IN-PHASE-3 | x86 CPU detection. Irrelevant on Apple Silicon. |
| `AFXRES.H` | DELETE-IN-PHASE-3 | MFC resource header. |
| `resource.h` | DELETE-IN-PHASE-3 | Win32 .rc resource IDs. |
| `LICENSE` | KEEP | Required by BSD-3 redistribution; also bundled in phase 8. |
| `README.md` | KEEP | Upstream docs; useful reference. |

## Asm blocks

All 33 `__asm` hits (file:line). Phase 4 will replace each with portable C and
annotate the new function name here. **Format**: `<file>:<line>` — `<original snippet>`.

### `proc_map.cpp` (24 blocks — per-pixel map dispatch + filter MMX)

The 18 `_proc_map_*` blocks form a hand-rolled function-table dispatch where each
function is `__declspec(naked)` and falls through into the next via address
arithmetic. Phase 4 replaces this with a plain C inner loop using a `switch` on
the operation tag — losing the no-prologue micro-optimization in exchange for
portability.

- `proc_map.cpp:147` — `__declspec ( naked ) void _return_baby(void) { __asm {`
- `proc_map.cpp:163` — `_proc_map_8bit_part01` naked + `__asm {`
- `proc_map.cpp:202` — `_proc_map_8bit_part02` naked + `__asm {`
- `proc_map.cpp:226` — `_proc_map_8bit_part03` naked + `__asm {`
- `proc_map.cpp:238` — `_proc_map_8bit_part04` naked + `__asm {`
- `proc_map.cpp:271` — `_proc_map_8bit_part05` naked + `__asm {`
- `proc_map.cpp:283` — `_proc_map_8bit_part06` naked + `__asm {`
- `proc_map.cpp:296` — `_proc_map_8bit_part07` naked + `__asm {`
- `proc_map.cpp:314` — `_proc_map_8bit_part08` naked + `__asm {`
- `proc_map.cpp:335` — `_proc_map_8bit_part09` naked + `__asm {`
- `proc_map.cpp:362` — `_proc_map_32bit_part01` naked + `__asm {`
- `proc_map.cpp:408` — `_proc_map_32bit_part02` naked + `__asm {`
- `proc_map.cpp:436` — `_proc_map_32bit_part03` naked + `__asm {`
- `proc_map.cpp:447` — `_proc_map_32bit_part04` naked + `__asm {`
- `proc_map.cpp:478` — `_proc_map_32bit_part05` naked + `__asm {`
- `proc_map.cpp:489` — `_proc_map_32bit_part06` naked + `__asm {`
- `proc_map.cpp:520` — `_proc_map_32bit_part07` naked + `__asm {`
- `proc_map.cpp:532` — `_proc_map_32bit_part08` naked + `__asm {`
- `proc_map.cpp:552` — `_proc_map_32bit_part09` naked + `__asm {`
- `proc_map.cpp:653` — `__asm` (smoothing/filter pass — non-naked, in function body)
- `proc_map.cpp:718` — `__asm` (filter pass)
- `proc_map.cpp:730` — `__asm // MMX version. Works 100%, except you must write the weights in the order +2+3+0+1 (vs. +0+1+2+3).`

### `video.h` (6 blocks — MMX memcpy/blit variants)

These are MMX-accelerated copies from the 8-bit indexed framebuffer to the 16/24/32-bit
DirectDraw surface. We render through OpenGL / a fragment shader instead, so most
of these can simply be deleted along with the surrounding "blit-to-DDraw" path
rather than ported. Confirm during phase 4 strip.

- `video.h:489` — `__asm` (blit variant)
- `video.h:544` — `__asm        // use MMX over memcpy()`
- `video.h:680` — `__asm`
- `video.h:753` — `__asm`
- `video.h:833` — `__asm`
- `video.h:960` — `__asm`

### `Sysstuff.h` (4 blocks — CPU/MMX detection, RDTSC)

Goes away with the file (DELETE-IN-PHASE-3). Listed for completeness.

- `Sysstuff.h:47` — `__asm {` (likely RDTSC)
- `Sysstuff.h:62` — `__try { __asm emms }          // try executing the MMX instruction "emms"`
- `Sysstuff.h:84` — `__asm`
- `Sysstuff.h:137` — `__asm`

## Win32 / DDraw / Winamp symbols

Per-file count of hits for `GetTickCount|RegOpen|LoadString|HWND|HINSTANCE|DirectDraw|IDirectDraw|<windows.h>|<ddraw.h>|<dsound.h>|<dinput.h>|<mmsystem.h>|<commctrl.h>|<shellapi.h>|<regstr.h>|<tchar.h>|<vis.h>` (case-insensitive on the angle-bracket includes):

| File | Hits | Phase 3 disposition |
|---|---|---|
| `main.cpp` | 99 | Strip Win32 includes (lines 498, 499, 506, 524, 525, 532, 533, 536, 537), `vis.h` include (line 592), and dialog/registry/Winamp-entry function bodies. Replace 3 `GetTickCount()` calls (lines 1587, 1594, 1638) with `geiss_now_ms()` (defined in `GeissCore.cpp` via `mach_absolute_time`). |
| `Sysstuff.h` | 22 | File deleted. |
| `GETDXVER.H` | 19 | File deleted. |
| `helper.cpp` | 2 | Drop `<windows.h>`, `<tchar.h>`; replace `_T(...)` macros with plain literals. |
| `outsound.h` | 2 | File deleted. |
| `VIS.H` | 2 | File deleted. |
| `proc_map.cpp` | 1 | Drop `<ddraw.h>` and `<memoryapi.h>`. |
| `outsound.cpp` | 1 | File deleted. |
| `SOUND.CPP` | 1 | File deleted. |

`main.cpp` line refs for the most disruptive symbols:

- `#include <windows.h>` — line 498
- `#include <regstr.h>` — line 499
- `#include <mmsystem.h>` — line 506
- `#include <windowsx.h>` — line 524
- `#include <ddraw.h>` — line 525
- `#include <mmreg.h>` — line 532
- `#include <dsound.h>` — line 533
- `#include <commctrl.h>` — line 536
- `#include <shellapi.h>` — line 537
- `#include "vis.h"` — line 592
- `GetTickCount()` — lines 1587, 1594, 1638

## Phase-3 deletion list (canonical)

Delete these files outright in phase 3:

- `Sysstuff.h`
- `SOUND.CPP`, `SOUND.H`
- `outsound.cpp`, `outsound.h`
- `VIS.H`
- `GETDXVER.H`
- `CPU_MHZ.H`, `CPU_TYPE.H`, `CYRIX.H`
- `AFXRES.H`
- `resource.h`

## Phase-3 strip-but-keep list

These remain in the build set after phase 3 but with Win32 surface removed:

- `main.cpp` — strip Win32 includes; remove dialog procs, registry I/O, Winamp plugin entry, screensaver `WinMain`; keep frame/palette/beat/effect-switch code. Route `GetTickCount` → `geiss_now_ms()`.
- `helper.cpp`, `helper.h` — strip `<windows.h>`/`<tchar.h>`/`<malloc.h>`.
- `proc_map.cpp`, `Proc_map.h` — strip `<ddraw.h>`/`<memoryapi.h>`; asm blocks remain (replaced in phase 4).
- `video.h` — Win32-clean already, but the DDraw blit code paths around the asm blocks become dead and should be pruned in phase 4 alongside the asm rewrite.
- `Effects.h`, `DEFINES.H` — keep as-is, audit only.
