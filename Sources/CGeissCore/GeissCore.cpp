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
extern int            SoundReady;
extern int            SoundActive;
extern int            SoundEmpty;
extern float          current_vol;
extern int            BOOL_g_rush_map_dummy; // (unused — keeps the comment block honest)

// `g_rush_map` is declared `BOOL` in geiss_port.cpp, which `win_compat.h`
// typedef's to `int`. Match here.
extern int g_rush_map;

// Mode-lock flag (bLocked in geiss_port.cpp) — prevents auto-cycling
extern bool bLocked;

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
    void geiss_port_get_config(GeissCoreConfig *out);
    void geiss_port_set_config(const GeissCoreConfig *cfg);
    void geiss_port_randomize_palette(void);
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
// Upstream reserves a large top/bottom mask band (`FX_YCUT` is 90 at
// 640x480). NullPlayer displays the indexed framebuffer directly inside a
// resizable window, so keeping that band creates visible letterboxing. Use a
// one-pixel guard instead: several upstream effects address `FX_YCUT - 1`, so
// zero would risk negative offsets.
// ---------------------------------------------------------------------------
static void geiss_set_geometry(int width, int height) {
    FXW                = width;
    FXH                = height;
    FX_YCUT            = 1;
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
    bool isValid;
    char effectName[32];
    char indexedEffectName[32];
};

static GeissCore gSingletonCore{};
static GeissCore *gActiveCore = nullptr;
static int gActiveCoreRefCount = 0;

static bool geiss_core_is_valid(const GeissCore *core) {
    return core != nullptr && core == gActiveCore && core->isValid;
}

static void geiss_seed_palette() {
    FX_Random_Palette(false);
    while (iBlendsLeftInPal > 0) {
        PutPalette();
    }
}

static GeissCoreConfig geiss_default_config() {
    GeissCoreConfig cfg{};
    cfg.sensitivity = 0.20f;
    cfg.gamma = 10;
    cfg.beatDetection = 1;
    cfg.syncColorToSound = 0;
    cfg.slideShift = 1;
    cfg.modeLocked = 0;
    cfg.paletteLocked = 0;
    cfg.autoSwitchSeconds = 15;
    cfg.visMode = 0;
    return cfg;
}

static void geiss_reset_runtime_state() {
    mode = 5;
    new_mode = 5;
    y_map_pos = -1;
    frames_this_mode = 0;
    intframe = 0;
    g_rush_map = 0;
    bLocked = false;
}

static void geiss_pick_next_auto_mode() {
    const int previousMode = mode;
    FX_Pick_Random_Mode();
    if (new_mode == previousMode) {
        new_mode = (previousMode % 25) + 1;
        y_map_pos = -1;
    }
}

static void geiss_advance_auto_map() {
    const int prev_y_map_pos = y_map_pos;
    GenerateChunkOfNewMap(false, 0);
    if (prev_y_map_pos != -1 && y_map_pos == -1 && !bLocked) {
        // Map just finished applying — queue the next mode.
        geiss_pick_next_auto_mode();
    }
}

extern "C" {

GeissCore *GeissCore_create(int width, int height) {
    if (width <= 0 || height <= 0) return nullptr;

    if (geiss_core_is_valid(gActiveCore)) {
        ++gActiveCoreRefCount;
        return gActiveCore;
    }

    GeissCore *core = &gSingletonCore;
    memset(core, 0, sizeof(*core));
    core->width  = width;
    core->height = height;
    core->isValid = false;

    geiss_set_geometry(width, height);
    geiss_reset_runtime_state();
    geiss_port_init_module();

    if (!FX_Init()) {
        return nullptr;
    }
    GeissCoreConfig defaultConfig = geiss_default_config();
    geiss_port_set_config(&defaultConfig);

    // Upstream's `doInit()` (Win32 surface, not in the build) seeds the
    // initial palette before the first frame; `FX_Init`'s rush-map loop
    // runs at intframe==0, so the palette-refresh path inside
    // `GenerateChunkOfNewMap` (gated `intframe > 0`) is skipped. Force a
    // palette generation here, then run the 18-frame cross-fade pump
    // synchronously so the first call to `GeissCore_palette` returns
    // something other than all-black.
    geiss_seed_palette();
    core->isValid = true;
    gActiveCore = core;
    gActiveCoreRefCount = 1;
    return core;
}

void GeissCore_destroy(GeissCore *core) {
    if (!geiss_core_is_valid(core)) return;
    if (gActiveCoreRefCount > 1) {
        --gActiveCoreRefCount;
        return;
    }
    FX_Fini();
    core->isValid = false;
    gActiveCore = nullptr;
    gActiveCoreRefCount = 0;
}

void GeissCore_resize(GeissCore *core, int width, int height) {
    if (!geiss_core_is_valid(core) || width <= 0 || height <= 0) return;
    if (core->width == width && core->height == height) return;

    FX_Fini();
    core->width  = width;
    core->height = height;
    geiss_set_geometry(width, height);
    if (!FX_Init()) {
        core->isValid = false;
        gActiveCore = nullptr;
        gActiveCoreRefCount = 0;
        return;
    }
    geiss_seed_palette();
}

void GeissCore_addPCM(GeissCore *core, const float *samples, int count) {
    if (!geiss_core_is_valid(core) || !samples || count <= 0) return;
    geiss_port_set_pcm(samples, count);
}

void GeissCore_setSpectrum(GeissCore *core, const float *mags, int count) {
    if (!geiss_core_is_valid(core) || !mags || count <= 0) return;
    geiss_port_set_spectrum(mags, count);
}

void GeissCore_render(GeissCore *core, unsigned char *indexBuf) {
    if (!geiss_core_is_valid(core) || !indexBuf) return;
    if (VS1 == nullptr || VS2 == nullptr) return;

    if (SoundEmpty) {
        const size_t pixelCount = (size_t)(FXW * FXH);
        for (size_t i = 0; i < pixelCount; ++i) {
            VS1[i] = (VS1[i] > 4) ? (unsigned char)(VS1[i] - 4) : 0;
            VS2[i] = (VS2[i] > 4) ? (unsigned char)(VS2[i] - 4) : 0;
        }
        geiss_advance_auto_map();
        memcpy(indexBuf, VS1, pixelCount);
        return;
    }

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
    geiss_advance_auto_map();

    // Output VS1 into the caller's indexBuf. Upstream's "back-buffer
    // merge" paths (`Merge_All_VS_To_Backbuffer`, songtitle GDI text,
    // ratings overlay) are dead code on macOS — the indexed framebuffer
    // is the final output.
    memcpy(indexBuf, VS1, (size_t)(FXW * FXH));
}

void GeissCore_palette(GeissCore *core, unsigned char *rgbaOut) {
    if (!geiss_core_is_valid(core) || !rgbaOut) return;
    geiss_port_get_palette(rgbaOut);
}

void GeissCore_nextEffect(GeissCore *core) {
    if (!geiss_core_is_valid(core)) return;
    new_mode = (new_mode % 25) + 1;
    y_map_pos  = -1;
    g_rush_map = 1;
}

void GeissCore_prevEffect(GeissCore *core) {
    if (!geiss_core_is_valid(core)) return;
    new_mode = ((new_mode - 2 + 25) % 25) + 1;
    y_map_pos  = -1;
    g_rush_map = 1;
}

void GeissCore_randomEffect(GeissCore *core) {
    if (!geiss_core_is_valid(core)) return;
    FX_Pick_Random_Mode();
    g_rush_map = 1;
}

void GeissCore_selectEffect(GeissCore *core, int index) {
    if (!geiss_core_is_valid(core)) return;
    if (index < 0 || index >= 25) return;
    new_mode = index + 1;
    y_map_pos  = -1;
    g_rush_map = 1;
}

int GeissCore_effectCount(GeissCore *core) {
    return geiss_core_is_valid(core) ? 25 : 0;
}

const char *GeissCore_effectName(GeissCore *core, int index) {
    if (!geiss_core_is_valid(core) || index < 0 || index >= 25) return "";
    snprintf(core->indexedEffectName, sizeof(core->indexedEffectName), "Mode %d", index + 1);
    return core->indexedEffectName;
}

const char *GeissCore_currentEffectName(GeissCore *core) {
    if (!geiss_core_is_valid(core)) return "Mode 0";
    int active = new_mode > 0 ? new_mode : mode;
    snprintf(core->effectName, sizeof(core->effectName), "Mode %d", active);
    return core->effectName;
}

void GeissCore_diag(GeissCore *core, GeissCoreDiag *out) {
    if (!geiss_core_is_valid(core) || !out) return;
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
    out->sound_ready  = SoundReady;
    out->sound_active = SoundActive;
    out->sound_empty  = SoundEmpty;
    out->current_vol  = current_vol;
}

void GeissCore_getConfig(GeissCore *core, GeissCoreConfig *out) {
    if (!geiss_core_is_valid(core) || !out) return;
    geiss_port_get_config(out);
}

void GeissCore_setConfig(GeissCore *core, const GeissCoreConfig *cfg) {
    if (!geiss_core_is_valid(core) || !cfg) return;
    geiss_port_set_config(cfg);
}

void GeissCore_randomizePalette(GeissCore *core) {
    if (!geiss_core_is_valid(core)) return;
    geiss_port_randomize_palette();
}

} // extern "C"
