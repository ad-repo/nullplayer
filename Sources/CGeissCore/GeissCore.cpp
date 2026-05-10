#include "GeissCore.h"
#include "win_compat.h"

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>

#if defined(__APPLE__)
#include <mach/mach_time.h>
#else
#include <time.h>
#endif

// ---------------------------------------------------------------------------
// Phase 4c-8: GeissCore_* C ABI wired through to the port translation unit
// (`upstream_port/geiss_port.cpp`). Per-call dispatch into the real Geiss
// frame loop:
//
//   GeissCore_create(w, h) → set FXW/FXH/FX_YCUT_*, geiss_port_init_module,
//                            FX_Init (allocates VS1/VS2/DATA_FX, populates
//                            modeInfo[], runs initial rush-map loop)
//   GeissCore_destroy      → FX_Fini
//   GeissCore_resize       → FX_Fini + reset geometry + FX_Init
//   GeissCore_addPCM       → geiss_port_set_pcm
//   GeissCore_setSpectrum  → geiss_port_set_spectrum
//   GeissCore_render       → faithful reproduction of upstream main.cpp:3756
//                            render1() — RenderFX → Process_Map → GetWaveData
//                            → RenderDots → RenderWave → swap → memcpy(VS1,
//                            indexBuf). After a full frame, advance the
//                            warp-map generation by one chunk
//                            (GenerateChunkOfNewMap), and when the chunk
//                            completes (y_map_pos == -1) pick the next
//                            random mode so the visualization auto-cycles.
//   GeissCore_palette      → geiss_port_get_palette
//   GeissCore_nextEffect / _prevEffect — manual mode change (set new_mode,
//                            kick off rush-map regeneration).
//   GeissCore_randomEffect → FX_Pick_Random_Mode + rush-map.
//   GeissCore_currentEffectName — formats "Mode N" into a static buffer.
// ---------------------------------------------------------------------------

// External symbols defined in upstream_port/geiss_port.cpp (and
// upstream/proc_map.cpp for Process_Map). C++ linkage for the globals
// (matches Proc_map.h's plain `extern long` declarations); C linkage for
// the helper functions.
extern int            effect[9];
extern int            gXC, gYC;
extern long           frames_this_mode;
extern long           FXW;
extern long           FXH;
extern long           FX_YCUT;
extern long           FX_YCUT_HIDE;
extern long           FX_YCUT_NUM_LINES;
extern long           FX_YCUT_xFXW_x8;
extern long           FX_YCUT_xFXW;
extern long           FX_YCUT_HIDE_xFXW;
extern long           FXW_x_FXH;
extern long           BUFSIZE;
extern int            iDispBits;
extern int            new_mode;
extern int            mode;
extern int            y_map_pos;
extern long           intframe;
extern unsigned char *VS1;
extern unsigned char *VS2;
extern unsigned char *TEMPPTR;
extern int            BOOL_g_rush_map_dummy; // (unused — keeps the comment block honest)

// `g_rush_map` is declared `BOOL` in geiss_port.cpp, which `win_compat.h`
// typedef's to `int`. Match here.
extern int g_rush_map;

// `Process_Map`, `FX_*`, `RenderFX`, `GetWaveData`, `RenderDots`,
// `RenderWave`, `GenerateChunkOfNewMap` are defined in
// upstream/proc_map.cpp + upstream_port/geiss_port.cpp with C++ linkage
// (no extern "C" wrap upstream), so the matching declarations here are
// also C++ linkage. The `geiss_port_*` helpers are explicitly extern "C"
// in geiss_port.cpp, so they're declared the same way here.
void Process_Map(void *p1, void *p2);
int  FX_Init(void);
void FX_Fini(void);
void FX_Pick_Random_Mode(void);
void GenerateChunkOfNewMap(bool bLoadPreset, int iPresetNum);
void RenderFX(void);
void GetWaveData(void);
void RenderDots(unsigned char *VS1);
void RenderWave(unsigned char *VS1);
void FX_Random_Palette(bool bLoadPal);
void PutPalette(void);
extern int iBlendsLeftInPal;

extern "C" {
    void geiss_port_init_module(void);
    void geiss_port_set_pcm(const float *samples, int count);
    void geiss_port_set_spectrum(const float *mags, int count);
    void geiss_port_get_palette(unsigned char *rgbaOut);
}

// ---------------------------------------------------------------------------
// Phase 3: monotonic millisecond clock — replaces Win32 GetTickCount.
// ---------------------------------------------------------------------------

extern "C" uint32_t geiss_now_ms(void);

extern "C" uint32_t geiss_now_ms(void) {
#if defined(__APPLE__)
    static mach_timebase_info_data_t tb = {0, 0};
    if (tb.denom == 0) {
        mach_timebase_info(&tb);
    }
    uint64_t ns = mach_absolute_time() * (uint64_t)tb.numer / (uint64_t)tb.denom;
    return (uint32_t)(ns / 1000000ULL);
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)((uint64_t)ts.tv_sec * 1000ULL + (uint64_t)ts.tv_nsec / 1000000ULL);
#endif
}

// ---------------------------------------------------------------------------
// Geometry helper — populate the upstream globals before FX_Init.
// FX_YCUT (top/bottom mask band) defaults to 90 in upstream at 640x480; we
// scale it down for smaller framebuffers so it doesn't consume too much of
// the visible area on a 256x192 visualization window.
// ---------------------------------------------------------------------------
static void geiss_set_geometry(int width, int height) {
    FXW                = width;
    FXH                = height;
    // Upstream uses FX_YCUT=90 at 480 lines (~19% of height). Match that
    // ratio so the off-screen mask is consistent.
    FX_YCUT            = max(1L, (long)(height * 90 / 480));
    FX_YCUT_HIDE       = FX_YCUT + 2;
    FX_YCUT_NUM_LINES  = FXW * (FXH - FX_YCUT * 2);
    FX_YCUT_xFXW_x8    = FX_YCUT * FXW * 8;
    FX_YCUT_xFXW       = FX_YCUT * FXW;
    FX_YCUT_HIDE_xFXW  = FX_YCUT_HIDE * FXW;
    FXW_x_FXH          = FXW * FXH;
    BUFSIZE            = max((long)(FXW * 2), (long)((314 + 50) * 2 + 20));
    iDispBits          = 8;
}

struct GeissCore {
    int width;
    int height;
    char effectName[32];
};

extern "C" {

GeissCore *GeissCore_create(int width, int height) {
    if (width <= 0 || height <= 0) return nullptr;
    GeissCore *core = new (std::nothrow) GeissCore{};
    if (!core) return nullptr;
    core->width  = width;
    core->height = height;

    geiss_set_geometry(width, height);
    geiss_port_init_module();

    if (!FX_Init()) {
        delete core;
        return nullptr;
    }

    // Upstream's `doInit()` (Win32 surface, not in the build) seeds the
    // initial palette before the first frame; `FX_Init`'s rush-map loop
    // runs at intframe==0, so the palette-refresh path inside
    // `GenerateChunkOfNewMap` (gated `intframe > 0`) is skipped. Force a
    // palette generation here, then run the 18-frame cross-fade pump
    // synchronously so the first call to `GeissCore_palette` returns
    // something other than all-black.
    FX_Random_Palette(false);
    while (iBlendsLeftInPal > 0) {
        PutPalette();
    }
    return core;
}

void GeissCore_destroy(GeissCore *core) {
    if (!core) return;
    FX_Fini();
    delete core;
}

void GeissCore_resize(GeissCore *core, int width, int height) {
    if (!core || width <= 0 || height <= 0) return;
    if (core->width == width && core->height == height) return;

    FX_Fini();
    core->width  = width;
    core->height = height;
    geiss_set_geometry(width, height);
    FX_Init();
}

void GeissCore_addPCM(GeissCore * /*core*/, const float *samples, int count) {
    geiss_port_set_pcm(samples, count);
}

void GeissCore_setSpectrum(GeissCore * /*core*/, const float *mags, int count) {
    geiss_port_set_spectrum(mags, count);
}

void GeissCore_render(GeissCore *core, unsigned char *indexBuf) {
    if (!core || !indexBuf) return;
    if (VS1 == nullptr || VS2 == nullptr) return;

    // Mirror upstream main.cpp:3756 render1() — the canonical Geiss frame
    // loop. RenderFX writes effect overlays into VS1; Process_Map warps
    // VS1 through DATA_FX into VS2; RenderDots / RenderWave overlay
    // audio-driven content onto VS2; the buffers are swapped so the
    // just-rendered frame ends up in VS1 for next frame's warp source.
    RenderFX();
    Process_Map(VS1, VS2);
    GetWaveData();
    RenderDots(VS2);
    RenderWave(VS2);
    TEMPPTR = VS1; VS1 = VS2; VS2 = TEMPPTR;

    // Advance the warp-map generation by one chunk per frame. When the
    // chunk completes (y_map_pos returns to -1 inside
    // GenerateChunkOfNewMap), pick the next random mode so the
    // visualization auto-cycles — same role upstream's GeissProc thread
    // played.
    int prev_y_map_pos = y_map_pos;
    GenerateChunkOfNewMap(false, 0);
    if (prev_y_map_pos != -1 && y_map_pos == -1) {
        // Map just finished applying — queue the next mode.
        FX_Pick_Random_Mode();
    }

    // Output VS1 into the caller's indexBuf. Upstream's "back-buffer
    // merge" paths (`Merge_All_VS_To_Backbuffer`, songtitle GDI text,
    // ratings overlay) are dead code on macOS — the indexed framebuffer
    // is the final output.
    memcpy(indexBuf, VS1, (size_t)(FXW * FXH));
}

void GeissCore_palette(GeissCore *core, unsigned char *rgbaOut) {
    if (!core || !rgbaOut) return;
    geiss_port_get_palette(rgbaOut);
}

void GeissCore_nextEffect(GeissCore *core) {
    if (!core) return;
    new_mode = (new_mode % 25) + 1;
    y_map_pos  = -1;
    g_rush_map = 1;
}

void GeissCore_prevEffect(GeissCore *core) {
    if (!core) return;
    new_mode = ((new_mode - 2 + 25) % 25) + 1;
    y_map_pos  = -1;
    g_rush_map = 1;
}

void GeissCore_randomEffect(GeissCore *core) {
    if (!core) return;
    FX_Pick_Random_Mode();
    g_rush_map = 1;
}

const char *GeissCore_currentEffectName(GeissCore *core) {
    if (!core) return "Mode 0";
    snprintf(core->effectName, sizeof(core->effectName), "Mode %d", mode);
    return core->effectName;
}

void GeissCore_diag(GeissCore *core, GeissCoreDiag *out) {
    if (!core || !out) return;
    out->active_mode      = mode;
    out->new_mode         = new_mode;
    out->y_map_pos        = y_map_pos;
    out->frames_this_mode = (int)frames_this_mode;
    for (int i = 0; i < 9; ++i) {
        out->effects[i] = (int8_t)effect[i];
    }
    out->gXC       = gXC;
    out->gYC       = gYC;
    out->iDispBits = iDispBits;
    out->FXW       = (int)FXW;
    out->FXH       = (int)FXH;
}

} // extern "C"
