// ---------------------------------------------------------------------------
// Phase 4c port translation unit.
//
// The upstream Geiss source (`upstream/main.cpp`, `upstream/Effects.h`,
// `upstream/video.h`) is written for Win32 + DirectDraw + the Winamp 2 vis
// SDK. This file is the macOS host: it owns every global symbol upstream
// expects, includes the platform-neutral upstream visual code (Effects.h,
// portions of video.h) directly into the build via `#include`, and provides
// faithful ports of the upstream orchestration functions whose original
// implementations were tangled with Win32 calls (FX_Init, FX_Pick_Random_Mode,
// GenerateChunkOfNewMap, RenderFX, GetWaveData, RenderDots, RenderWave) and
// the palette pipeline (FX_Random_Palette, PutPalette, CrankPal).
//
// Algorithms are the upstream Geiss algorithms, line-for-line; only Win32
// surface (DirectDraw blits, GDI text, registry I/O, dialog plumbing,
// Winamp module pointer plumbing) is replaced.
//
// `upstream/main.cpp` itself is NOT in the build (it is gated out in
// `Package.swift`); it is retained in the tree because the BSD-3 licence
// requires source redistribution and because it is the canonical reference
// for these ports.
// ---------------------------------------------------------------------------

#include "GeissCore.h"
#include "win_compat.h"
#include "winamp_vis_stub.h"

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <new>

#include "Proc_map.h"

// ---------------------------------------------------------------------------
// Globals owned by the port. Exposed with C linkage so `proc_map.cpp` (which
// declares them `extern`) and any later additions can link against them.
//
// The phase-4b stub block in `proc_map.cpp` (under `GEISS_PHASE_4B_STUBS`)
// defined a parallel set of these for the standalone-proc_map case; that
// `#define` is removed in the same Package.swift change that brings
// `geiss_port.cpp` into the build, so there is exactly one definition site
// in the final binary.
// ---------------------------------------------------------------------------

// Framebuffer geometry. Set in FX_Init from the constructor's (width,height).
// `Proc_map.h` declares these `extern long`/`extern bool` without an
// `extern "C"` wrap, so we match: plain C++-linkage definitions here.
long FXW                 = 0;
long FXH                 = 0;
long FX_YCUT             = 0;   // see FX_Init for default
long FX_YCUT_HIDE        = 0;
long FX_YCUT_NUM_LINES   = 0;
long FX_YCUT_xFXW_x8     = 0;
long FX_YCUT_xFXW        = 0;
long FX_YCUT_HIDE_xFXW   = 0;
long FXW_x_FXH           = 0;
long BUFSIZE             = 0;
int  iDispBits           = 8;   // Geiss only renders the 8-bit indexed path here
unsigned char *DATA_FX   = nullptr;
int  initial_map_offset  = 0;
bool bBypassAssembly     = true; // we have no asm path on macOS
bool bMMX                = false;
int  slider1             = 0;
clock_t core_clock_time  = 0;

// Indexed framebuffers (VS1, VS2). Allocated in FX_Init.
unsigned char *VS1     = nullptr;
unsigned char *VS2     = nullptr;
unsigned char *TEMPPTR = nullptr;

// Phase 4c-2 marker: the file currently scaffolds globals only — no
// upstream visual code is included yet. Effects.h is brought in by 4c-3.
// `geiss_port_step` is exported solely so the linker keeps this translation
// unit alive while later sub-phases land.
extern "C" int geiss_port_step(void);
extern "C" int geiss_port_step(void) { return 1; }
