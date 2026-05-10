# Geiss Upstream Port Notes

Developer-only running log for the Geiss port. Not shipped in the .app.

## Upstream commit pinned

- Repo: https://github.com/geissomatik/geiss
- HEAD SHA at vendor time: `816f3f6a5ca70592da7583be70c06f6e3425d306`
- License: BSD-3-Clause (see `LICENSE` in this directory)

## Phase status

- Phase 1: complete (stub engine, protocol seam, no upstream code in build).
- Phase 2 (this file): complete — vendored upstream verbatim into `Sources/CGeissCore/upstream/`,
  added `exclude: ["upstream"]` in `Package.swift` so nothing here is compiled yet,
  and recorded the audit below. **No upstream files were modified.**
- Phase 3+: pending.

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
