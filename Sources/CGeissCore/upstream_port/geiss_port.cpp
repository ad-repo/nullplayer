// ---------------------------------------------------------------------------
// Phase 4c port translation unit.
//
// The upstream Geiss source (`upstream/main.cpp`, `upstream/Effects.h`,
// `upstream/video.h`) is written for Win32 + DirectDraw + the Winamp 2 vis
// SDK. This file is the macOS host: it owns every global symbol upstream
// expects, includes the platform-neutral upstream visual code (Effects.h)
// directly into the build via `#include`, and adds faithful ports of the
// upstream orchestration functions whose original implementations were
// tangled with Win32 calls (FX_Init, FX_Pick_Random_Mode,
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
//
// `PLUGIN` is defined here (rather than `SAVER`) so that conditional code
// in `upstream/Effects.h` and other shared headers takes the Winamp-vis
// branch — that branch reads audio from a `winampVisModule*` pointer
// (`g_this_mod`) we wire up to a stub module backed by `GeissAudioState`.
// `GRFX` is defined to 0 so the DirectDraw blit / palette-set paths in
// upstream code are gated out; the port supplies its own indexBuf and
// palette-buffer outputs through the C ABI.
// ---------------------------------------------------------------------------

#define PLUGIN 1
#define GRFX   0

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
// Compile-time constants (mirroring upstream main.cpp).
// ---------------------------------------------------------------------------

#define NUM_EFFECTS    9
#define NUM_MODES      25
#define NUM_WAVES      6
#define WAVE_5_BLEND_RANGE 50
#define FOURIER_DETAIL 24
#define SCATTERVALS    226
#define PAST_VOL_N     120
#define NUM_FREQS      3
#define FREQ_SAMPLES   192

// ---------------------------------------------------------------------------
// Enumerations and structs that upstream code references by tag.
// ---------------------------------------------------------------------------

enum visModeEnum { spectrum, wave };
enum            { CHASERS, BAR, DOTS, SOLAR, GRID, NUCLIDE, SHADE, SPECTRAL };
enum DISC_STATES { STOPPED, PLAYING, PAUSED, UNKNOWN, BUSY };
enum modesel_state { NONE_SEL, MODE_SEL_1 };
enum preset_state  { NONE, LOAD_1, LOAD_2, SAVE_1, SAVE_2 };
enum TScrMode      { smNone, smConfig, smPassword, smPreview, smSaver };

struct pal_td {
    int  lo_band;
    int  hi_band;
    bool bFXPalette;
    int  iFXPaletteNum;
    int  c1, c2, c3;
};

struct preset {
    int   iMode;
    int   iParam1;
    int   iParam2;
    int   iParam3;
    float fParam1;
    float fParam2;
    float fParam3;
};

struct VidModeInfo {
    int  iDispBits;
    int  FXW;
    int  FXH;
    BOOL VIDEO_CARD_FUCKED;
    char name[64];
};

struct DDrawDeviceInfo {
    GUID guid;
    char szDesc[256];
    char szName[256];
};

#define MAX_VID_MODES 512
#define MAX_DEVICES   16

// ---------------------------------------------------------------------------
// Globals owned by the port. These mirror the upstream main.cpp definitions
// 1:1 in name and type so `upstream/Effects.h` (and the other ported
// translation units in this file) can read/write them directly.
//
// `Proc_map.h` declares a subset of these `extern long`/`extern bool`
// without an `extern "C"` wrap, so the matching definitions here are plain
// C++-linkage globals.
// ---------------------------------------------------------------------------

// Framebuffer geometry. Initialised in FX_Init from the constructor's
// (width, height) once that ports lands in 4c-4.
long FXW                 = 0;
long FXH                 = 0;
long FX_YCUT             = 0;
long FX_YCUT_HIDE        = 0;
long FX_YCUT_NUM_LINES   = 0;
long FX_YCUT_xFXW_x8     = 0;
long FX_YCUT_xFXW        = 0;
long FX_YCUT_HIDE_xFXW   = 0;
long FXW_x_FXH           = 0;
long BUFSIZE             = 0;
int  iDispBits           = 8;
unsigned char *DATA_FX   = nullptr;
unsigned char *DATA_FX2  = nullptr;
int  initial_map_offset  = 0;
bool bBypassAssembly     = true;
bool bMMX                = false;
int  slider1             = 0;
clock_t core_clock_time  = 0;

// Display info.
int  g_nCores            = 1;
int  g_desktop_w         = 800;
int  g_desktop_h         = 600;
int  g_desktop_bpp       = 8;
int  g_desktop_hz        = 60;
int  iVSizePercent       = 100;
int  VidMode             = -1;
BOOL VidModeAutoPicked   = FALSE;
int  iNumVidModes        = 0;
VidModeInfo VidList[MAX_VID_MODES];
DDrawDeviceInfo g_device[MAX_DEVICES];
int  g_nDevices          = 0;
GUID g_DDrawDeviceGUID;

// Indexed framebuffers (allocated in FX_Init).
unsigned char *VS1                 = nullptr;
unsigned char *VS2                 = nullptr;
unsigned char *TEMPPTR             = nullptr;
unsigned char *original_VS[2]      = { nullptr, nullptr };
unsigned char *original_DATA_FX[2] = { nullptr, nullptr };

// Palette state.
unsigned char  _REMAP_VALUES[2048];
unsigned char *REMAP                 = nullptr;
unsigned char *REMAP2                = nullptr;
unsigned char *REMAP3                = nullptr;
PALETTEENTRY   ape[256]              = {};
PALETTEENTRY   ape2[256]             = {};
PALETTEENTRY   apetemp[256]          = {};
int            iBlendsLeftInPal      = 0;
int            iFramesPerPaletteTick = 7;
pal_td         old_palette           = {};
preset         g_Preset[10]          = {};

// Effect / mode state.
int   effect[NUM_EFFECTS] = {};
int   mode                = 5;
int   new_mode            = 5;
int   gXC                 = 0;
int   gYC                 = 0;
int   new_gXC             = 0;
int   new_gYC             = 0;
int   solar_max           = 60;
int   grid_dir            = 1;
float damping             = 1.0f;
float new_damping         = 1.0f;
float suggested_damping   = 1.0f;
int   weightsum           = 0;
int   weightsum_res_adjusted = 0;
int   old_weightsum       = 0;
float scale1              = 1.0f;
float scale2              = 1.0f;
float turn1               = 0.0f;
float turn2               = 0.0f;
float old_scale1          = 1.0f;
float old_scale2          = 1.0f;
float old_turn1           = 0.0f;
float old_turn2           = 0.0f;
float cos_turn1           = 1.0f;
float cos_turn2           = 1.0f;
float sin_turn1           = 0.0f;
float sin_turn2           = 0.0f;
float center_dwindle      = 0.99f;
float floatframe          = 0.0f;
long  intframe            = 0;
long  frames_this_mode    = 0;
long  frames_crunching_this_mode = 0;
long  frames_since_last_plop     = 10;
long  clearframes         = 4;
long  chaser_offset       = 0;
long  last_mousemove_frame = -5;
int   frames_til_auto_switch              = 550;
int   frames_til_auto_switch__registry    = 550;
int   gamma               = 10;
int   solar_pal_freq      = 1;
int   coarse_pal_freq     = 1;
int   waveform            = 0;
int   new_waveform        = 0;
float fps                 = 40.0f;
float fps_at_last_mode_switch = 40.0f;
int   y_map_pos           = -1;
float max_rad_inv         = 1.0f;
float rmult               = 1.0f;
float rdiv                = 1.0f;
float protective_factor   = 1.0f;

// Per-mode effect parameter tables.
float micro_f1[10] = {};
float micro_f2[10] = {};
float micro_f3[10] = {};
float micro_f4[10] = {};
float micro_c1[10] = {};
float micro_c2[10] = {};
float micro_c3[10] = {};
float micro_rad[4][10] = {};

// Map-generation parameters.
float f1 = 0.0f, f2 = 0.0f, f3 = 0.0f, f4 = 0.0f;
float old_f1 = 0.0f, old_f2 = 0.0f, old_f3 = 0.0f, old_f4 = 0.0f;
float cx[10] = {}, cy[10] = {}, ci[10] = {}, cj[10] = {}, cr[10] = {}, cr_inv[10] = {};
int   ctype[10] = {};
int   R_offset = 0, old_R_offset = 0;

// Sound state.
__int16 g_SoundBuffer[16384] = {};
float   g_fSoundBuffer[16384] = {};
LPGUID  g_lpGuid              = nullptr;
BOOL    SoundEnabled          = TRUE;
BOOL    SoundReady            = FALSE;
BOOL    SoundActive           = FALSE;
BOOL    SoundEmpty            = FALSE;
int     oldSoundBufPos        = 0;
int     oldSoundBufNum        = 0;
char    szSoundDrivers[10][1024] = {};
int     iNumSoundDrivers      = 0;
int     iCurSoundDriver       = 0;
int     frames_since_silence  = 0;
float   avg_peaks             = 100.0f;
float   current_vol           = 0.0f;
float   past_vol[PAST_VOL_N]  = {};
int     past_vol_pos          = 0;
float   avg_vol               = 1.0f;
float   avg_vol_wide          = 1.0f;
float   avg_vol_narrow        = 1.0f;
unsigned long iVolumeSum      = 1;
float   debug_param           = 1.0f;
float   damped_std_dev        = 5.0f;
bool    bBeatMode             = false;
bool    bBigBeat              = false;
float   fBigBeatThreshold     = 1.10f;

float   g_phase_inc[NUM_FREQS] = {};
float   rand_array[2345]       = {};
float   sqrt_tab[21][21]       = {};
int     rand_array_pos         = 0;
float   g_power[FOURIER_DETAIL] = {};
float   g_power_smoothed[FOURIER_DETAIL] = {};

// Volume control.
int   volpos    = 10;
float volscale  = 0.20f;

// Title state.
char     g_song_title[256]              = {};
int      g_song_tooltip_frames          = 20;
HFONT    g_title_font                   = nullptr;
int      g_song_title_y                 = 0;
int      g_song_title_x                 = 0;
int      g_title_R                      = 200;
int      g_title_G                      = 200;
int      g_title_B                      = 200;
bool     g_LastMessageWasCustom         = false;

// Frame-loop globals.
int      last_frame_v                   = 0;
int      last_frame_slope               = 0;
int      last_mouse_x                   = -1;
int      last_mouse_y                   = -1;
int      g_FramesSinceShift             = 0;
bool     g_bSlideShift                  = true;
int      g_SlideShiftFreq               = 33;
int      g_SlideShiftMinFrames          = 5;
float    g_ShiftMaxVol                  = 0.0f;

int      g_hit                          = 0;
int      AUTOMIN                        = 0;
float    gF[6]                          = {};
float    fScatter[SCATTERVALS]          = {};
int      g_iScatterPos                  = 0;
int      iTrack                         = 0;
int      iNumTracks                     = 0;
DISC_STATES eDiscState                  = UNKNOWN;
int      iRegistryDelay                 = 0;
bool     bExitOnMouse                   = false;
bool     bLocked                        = false;
bool     bPalLocked                     = false;
modesel_state eModeSelState             = NONE_SEL;
preset_state  ePresetState              = NONE;
preset_state  eCustomMsgState           = NONE;
int      iModeSelection                 = 0;
int      iPresetNum                     = 0;
int      iCustomMsgNum                  = 0;
BOOL     g_rush_map                     = FALSE;
BOOL     g_QuitASAP                     = FALSE;
BOOL     g_GeissProcFinished            = FALSE;
BOOL     g_bFirstRun                    = FALSE;
BOOL     g_bDumpFileCleared             = FALSE;
BOOL     g_bDebugMode                   = FALSE;
BOOL     g_bSuppressHelpMsg             = FALSE;
BOOL     g_bSuppressAllMsg              = FALSE;
BOOL     g_DisclaimerAgreed             = TRUE;
BOOL     g_ConfigAccepted               = FALSE;
BOOL     g_Capturing                    = FALSE;
BOOL     g_bUseBeatDetection            = TRUE;
BOOL     g_bSyncColorToSound            = FALSE;
bool     g_bLoadPreset                  = false;
int      g_iPresetNum                   = -1;
bool     g_bLost                        = false;
int      modeprefs[128]                 = {};
int      modeprefs_total                = -1;
float    time_array[30]                 = {};
int      time_array_pos                 = 0;
bool     time_array_ready               = false;
clock_t  start_clock                    = 0;
clock_t  clock_debt                     = 0;
clock_t  blit_clock_time                = 0;
clock_t  flip_clock_time                = 0;
char     inifile[512]                   = {};
char     szDEBUG[512]                   = {};
char     szMisc[512]                    = {};
char     winpath[512]                   = {};
unsigned char SHOW_DEBUG          = 0;
unsigned char SHOW_MOUSECLICK_MSG = 0;
unsigned char SHOW_LOCKED_MSG     = 0;
unsigned char SHOW_UNLOCKED_MSG   = 0;
unsigned char SHOW_TRACK_MSG      = 0;
unsigned char SHOW_MODEPREFS_MSG  = 0;
unsigned char SHOW_MISC_MSG       = 0;
bool          SHOW_FPS            = false;
bool          SHOW_HELP_MSG       = false;
unsigned char VIDEO_CARD_FUCKED   = 0;
unsigned char RND                 = 1;

// Chasers (used by Two_Chasers / RenderWave).
int           chaser_x[20]    = {};
int           chaser_y[20]    = {};
int           chaser_ptr      = 0;
unsigned char chaser_r[20]    = {};
unsigned char chaser_g[20]    = {};
unsigned char chaser_b[20]    = {};

// PLUGIN-only state.
visModeEnum visMode = wave;
BOOL g_bDisableSongTitlePopups = FALSE;
BOOL g_WinampMinimizedByHand   = FALSE;
BOOL g_bMinimizeWinamp         = FALSE;
HCURSOR hOldCursor             = nullptr;
WINDOWPLACEMENT wp_winamp      = {};
int  g_random_songtitle_freq   = 0;

// Winamp-host stub: a fake module backed by GeissAudioState. Audio data
// flows through GeissCore_addPCM / GeissCore_setSpectrum into the global
// GeissAudioState (defined in GeissCore.cpp); we mirror the address here
// into the Winamp-style struct so unmodified upstream code that reads
// `g_this_mod->waveformData[...]` and `g_this_mod->spectrumData[...]`
// resolves to the real audio.
struct GeissAudioState {
    unsigned char waveformData[2][576];
    unsigned char spectrumData[2][576];
};
extern "C" GeissAudioState *geiss_audio_state(void);

static winampVisModule s_geiss_stub_module;
struct winampVisModule *g_this_mod        = nullptr;
HWND      this_mod_hwndParent             = nullptr;
HINSTANCE this_mod_hDllInstance           = nullptr;
HWND      hMainWnd                        = nullptr;
TScrMode  ScrMode                         = smNone;

// Misc globals referenced from Effects.h / video.h that we keep zero-init.
HINSTANCE     hInstance                   = nullptr;
HWND          hScrWindow                  = nullptr;
LARGE_INTEGER m_high_perf_timer_freq      = {};
LARGE_INTEGER m_prev_end_of_frame         = {};

// Forward declarations for functions that Effects.h calls but that the
// surrounding port translation unit defines (or will define in subsequent
// sub-phases).
void  FX_Random_Palette(bool bLoadPal = false);
void  PutPalette();
float CrankPal(unsigned int curve_id, int z);
void  GenerateChunkOfNewMap(bool bLoadPreset = false, int iPresetNum = 0);
void  FX_Pick_Random_Mode();
void  dumpmsg(const char *format, ...);
float AdjustRateToFPS(float per_frame_decay_rate_at_fps1, float fps1, float actual_fps);

// Direct port of upstream main.cpp:548 — converts a per-frame decay rate
// authored at one FPS into the equivalent rate at the running FPS.
inline float AdjustRateToFPS(float per_frame_decay_rate_at_fps1, float fps1, float actual_fps) {
    float per_second_decay_rate_at_fps1 = powf(per_frame_decay_rate_at_fps1, fps1);
    float per_frame_decay_rate_at_fps2  = powf(per_second_decay_rate_at_fps1, 1.0f / actual_fps);
    return per_frame_decay_rate_at_fps2;
}

// ---------------------------------------------------------------------------
// CModeInfo — direct port of the upstream class (main.cpp:1258-1330). Used
// by FX_Init to populate per-mode effect-frequency tables and by RenderFX
// to clip the active effect set to the mode's min/max bounds.
// ---------------------------------------------------------------------------
class CModeInfo {
public:
    CModeInfo();

    int   effect_freq[NUM_EFFECTS];
    int   solar_max;
    float center_dwindle;
    int   max_effects;
    int   min_effects;

    void  Clip_Num_Effects();

protected:
    static int Get_Num_Effects();
};

CModeInfo::CModeInfo() {
    min_effects    = 1;
    max_effects    = 2;
    solar_max      = 60;
    center_dwindle = 0.99f;
    for (int i = 0; i < NUM_EFFECTS; ++i)
        effect_freq[i] = 1000 / NUM_EFFECTS;
}

int CModeInfo::Get_Num_Effects() {
    int n = 0;
    for (int i = 0; i < NUM_EFFECTS; ++i)
        if (effect[i] > 0) ++n;
    return n;
}

void CModeInfo::Clip_Num_Effects() {
    int n = Get_Num_Effects();
    int j;
    BOOL bGotOne;

    if (!SoundActive || SoundEmpty)
    while (n < min_effects) {
        bGotOne = FALSE;
        for (j = 0; j < NUM_EFFECTS; ++j)
            if ((effect[j] == -1) && (rand() % 1000 < effect_freq[j]) && (bGotOne == FALSE)) {
                effect[j] = 1;
                bGotOne = TRUE;
                ++n;
            }
    }

    for (j = 0; j < NUM_EFFECTS; ++j)
        if (effect_freq[j] >= 1000)
            effect[j] = 1;

    while (n > max_effects) {
        j = rand() % NUM_EFFECTS;
        if (effect[j] == 1 && effect_freq[j] < 1000) {
            effect[j] = -1;
            --n;
        }
    }
}

CModeInfo modeInfo[NUM_MODES + 1]; // array starts at 1

// ---------------------------------------------------------------------------
// Mode-property tables from upstream main.cpp:1223-1255. These are *file
// scope* in upstream; geiss_port.cpp owns the canonical copies and
// `Effects.h` uses them indirectly via `modeInfo` / mode-related branches.
// ---------------------------------------------------------------------------
bool mode_motion_dampened[] = {
    true,  true,  true,  false, true,  true,  false, true,  true,  true,
    true,  true,  true,  true,  true,  true,  true,
    false, false, false,
    false, false, false, false, false,
    false, false, false, false, false,
    false, false, false, false, false,
    false, false, false, false, false,
};
bool rotation_dither[] = {
    false, true,  false, false, false, false, false, false, false, true,
    false, true,  false, false, false,
    false, false, false, false, false,
    false, false, false, false, false,
    false, false, false, false, false,
    false, false, false, false, false,
    false, false, false, false, false,
};
bool custom_motion_vectors[] = {
    false, false, false, false, false, false, true,  false, false, false,
    true,  false, true,  false, false,
    false, false, false, false, false,
    false, false, false, false, false,
    false, false, false, false, false,
    false, false, false, false, false,
    false, false, false, false, false,
};

// ---------------------------------------------------------------------------
// Compatibility helpers used by Effects.h that have to be C++-callable but
// must not collide with any STL/Foundation symbols on macOS.
// ---------------------------------------------------------------------------

// `__int16 abs_*` etc. — Effects.h calls plain `abs(int)`; that's already in
// <cstdlib>. No work needed here.

// dumpmsg is upstream's lightweight printf-to-debugfile; on macOS we discard.
void dumpmsg(const char * /*format*/, ...) { }

// ---------------------------------------------------------------------------
// Phase 4c-7: FX_Random_Palette / PutPalette / CrankPal — direct ports of
// upstream video.h:1390-1645.
//
// CrankPal is a pure float→float curve evaluator; ports verbatim.
//
// FX_Random_Palette generates the next palette into ape2[], by either:
//   (b == 0) replaying the four "FX-style monotone" palettes via
//            REMAP/REMAP2/REMAP3 lookup tables, or
//   (b != 0) blending three CrankPal curves with the current `gamma`.
// `iBlendsLeftInPal` is reset to 18 so the next 18 frames cross-fade
// from the previous palette (`ape[]`) into the new one (`ape2[]`).
//
// PutPalette runs the cross-fade interpolation each frame; the upstream
// `lpDDPal->SetEntries(...)` call site is gated out under `#if (GRFX==1)`
// (geiss_port.cpp defines `GRFX 0`). The port adds an extra step at the
// end: copy `apetemp[]` (the just-blended frame palette) into a port-
// owned RGBA buffer that `GeissCore_palette` returns through the C ABI.
// ---------------------------------------------------------------------------

static unsigned char s_geiss_palette_rgba[256 * 4] = {};

extern "C" void geiss_port_get_palette(unsigned char *rgbaOut) {
    if (!rgbaOut) return;
    memcpy(rgbaOut, s_geiss_palette_rgba, sizeof(s_geiss_palette_rgba));
}

float CrankPal(unsigned int curve_id, int z) {
    float xx = (float)z;
    switch (curve_id) {
        case 1: return sqrtf(xx) * 22.6f;
        case 2: return xx * 2.0f;
        case 3: return xx * xx / 64.0f;
        case 4: return 255.0f * sinf(xx / 256.0f * 0.5f * 3.1415927f);
        case 5: return xx * 3.5f;
        case 6: return powf(1.5f, xx / 20.0f) - 1.0f;
        case 7: return xx * 1.5f + 128.0f * 0.25f + 128.0f * 0.25f * sinf(z * 0.3f);
    }
    return 255.0f;
}

void FX_Random_Palette(bool bLoadPal) {
    if (bPalLocked) return;
    if (iDispBits != 8) return;

    int n, a, b;

    if (!bLoadPal) {
        old_palette.lo_band       = -1;
        old_palette.hi_band       = -1;
        old_palette.bFXPalette    = false;
        old_palette.iFXPaletteNum = -1;
        old_palette.c1            = -1;
        old_palette.c2            = -1;
        old_palette.c3            = -1;

        if (rand() % 10 < coarse_pal_freq) {
            old_palette.lo_band = 7  + rand() % 6;
            old_palette.hi_band = 17 + rand() % 6;
        }
    }

    iBlendsLeftInPal = 18;

    b = rand() % 6;
    if (bLoadPal) {
        b = (old_palette.bFXPalette) ? 0 : 1;
    }

    if (b == 0) {
        old_palette.bFXPalette = true;
        if (!bLoadPal) old_palette.iFXPaletteNum = rand() % 4;

        if (old_palette.iFXPaletteNum == 0) {
            for (a = 0; a < 128; ++a) {
                REMAP [a] = (unsigned char)(a * a / 64.0f);
                REMAP2[a] = (unsigned char)(a * 2);
                REMAP3[a] = (unsigned char)(sqrtf((float)a) * 22.6f);
            }
        } else if (old_palette.iFXPaletteNum == 1) {
            for (a = 0; a < 128; ++a) {
                REMAP [a] = (unsigned char)(a * a / 64.0f);
                REMAP2[a] = (unsigned char)(sqrtf((float)a) * 22.6f);
                REMAP3[a] = (unsigned char)(a * 2);
            }
        } else if (old_palette.iFXPaletteNum == 2) {
            for (a = 0; a < 128; ++a) {
                REMAP [a] = (unsigned char)(sqrtf((float)a) * 22.6f);
                REMAP2[a] = (unsigned char)(a * 2);
                REMAP3[a] = (unsigned char)(a * a / 64.0f);
            }
        } else if (old_palette.iFXPaletteNum == 3) {
            for (a = 0; a < 128; ++a) {
                REMAP [a] = (unsigned char)(a * 2);
                REMAP2[a] = (unsigned char)(a * a / 64.0f);
                REMAP3[a] = (unsigned char)(sqrtf((float)a) * 22.6f);
            }
        }

        for (n = 128; n < 256; ++n) {
            REMAP [n] = REMAP [127];
            REMAP2[n] = REMAP2[127];
            REMAP3[n] = REMAP3[127];
        }

        for (n = 0; n < 256; ++n) {
            ape[n]          = ape2[n];
            ape2[n].peRed   = REMAP [n];
            ape2[n].peBlue  = REMAP2[n];
            ape2[n].peGreen = REMAP3[n];
        }
    } else {
        if (!bLoadPal) {
            int temp;
            do {
                if (rand() % 5 < solar_pal_freq) {
                    old_palette.c1 = rand() % 7 + 1;
                    old_palette.c2 = rand() % 7 + 1;
                    old_palette.c3 = rand() % 7 + 1;
                } else {
                    old_palette.c1 = rand() % 6 + 1;
                    old_palette.c2 = rand() % 6 + 1;
                    old_palette.c3 = rand() % 6 + 1;
                }
                temp = 0;
                if (old_palette.c1 == 6) ++temp;
                if (old_palette.c2 == 6) ++temp;
                if (old_palette.c3 == 6) ++temp;
            } while (temp > 1);
        }

        float xv, yv, zv;
        float gamma_factor = 1.0f + gamma * 0.01f;
        if (SoundEmpty) gamma_factor += 0.3f;

        for (n = 0; n < 256; ++n) {
            ape[n] = ape2[n];

            xv = CrankPal(old_palette.c1, (unsigned char)n);
            yv = CrankPal(old_palette.c2, (unsigned char)n);
            zv = CrankPal(old_palette.c3, (unsigned char)n);

            xv *= gamma_factor;
            yv *= gamma_factor;
            zv *= gamma_factor;

            if (n > old_palette.lo_band && n < old_palette.hi_band) {
                xv *= 2.0f;
                yv *= 2.0f;
                zv *= 2.0f;
            }

            ape2[n].peRed   = (unsigned char)min(255.0f, xv);
            ape2[n].peBlue  = (unsigned char)min(255.0f, yv);
            ape2[n].peGreen = (unsigned char)min(255.0f, zv);
        }
    }
}

void PutPalette() {
    float xv, yv;
    int   n;

    if (iDispBits == 8) {
        --iBlendsLeftInPal;

        xv = (iBlendsLeftInPal / 18.0f);
        yv = 1.0f - xv;

        for (n = 0; n < 256; ++n) {
            apetemp[n].peRed   = (unsigned char)(ape[n].peRed   * xv + ape2[n].peRed   * yv);
            apetemp[n].peBlue  = (unsigned char)(ape[n].peBlue  * xv + ape2[n].peBlue  * yv);
            apetemp[n].peGreen = (unsigned char)(ape[n].peGreen * xv + ape2[n].peGreen * yv);
        }

        // Upstream then calls `lpDDPal->SetEntries(...)` under `#if (GRFX==1)`;
        // we route to the port-owned RGBA buffer instead. Note Geiss's
        // PALETTEENTRY uses `peRed / peBlue / peGreen` (not the standard
        // RGB ordering) — preserve the upstream ordering for fidelity.
        for (n = 0; n < 256; ++n) {
            s_geiss_palette_rgba[n * 4 + 0] = apetemp[n].peRed;
            s_geiss_palette_rgba[n * 4 + 1] = apetemp[n].peGreen;
            s_geiss_palette_rgba[n * 4 + 2] = apetemp[n].peBlue;
            s_geiss_palette_rgba[n * 4 + 3] = 255;
        }
    }
}

// ---------------------------------------------------------------------------
// Sub-phase 4c-3: pull upstream Effects.h into the build. The header defines
// LoadCustomMsg, LoadPreset, SavePreset, ShadeBobs, Diminish_Center,
// Drop_Solar_Particles_320, Drop_Solar_Particles, Solid_Line, Two_Chasers,
// Nuclide, Neutrons, One_Dotty_Chaser, Mode6Edges, Grid, DoCrystals — all
// platform-neutral algorithms. The non-rendering Win32 calls inside
// (Get/WritePrivateProfileString) resolve to no-op inline stubs in
// `win_compat.h`.
// ---------------------------------------------------------------------------

#include "Effects.h"

// ---------------------------------------------------------------------------
// Phase 4c-4: FX_Init / FX_Fini / FX_Pick_Random_Mode — direct ports of
// upstream main.cpp lines 3869-4304. The Win32 calls in upstream's FX_Init
// (`GetWindowsPath`, `finiObjects`) are replaced with no-ops; everything
// else is preserved verbatim. The `delete` calls in upstream FX_Fini are
// changed to `free()` so they pair with FX_Init's `malloc()`. The 16-byte
// pointer realignment fix-up in FX_Init was a Win32 SSE workaround; we
// keep it because it's harmless and several downstream effects assume the
// alignment.
// ---------------------------------------------------------------------------

static void GeissPort_GetWindowsPath() {
    // Upstream sets a global `winpath` to "C:\Windows\". macOS port leaves
    // it empty — the only thing that reads it is dialog/registry code we
    // do not exercise.
    winpath[0] = '\0';
}

static void GeissPort_finiObjects() {
    // Upstream's finiObjects releases DirectDraw + window handles. The
    // macOS port has nothing to release here — buffers are torn down in
    // FX_Fini, and we have no DDraw / window state to begin with.
}

BOOL FX_Init() {
    unsigned long z, x;

    dumpmsg("Starting FX_Init()");

    GeissPort_GetWindowsPath();

    if (RND == 1) srand((unsigned)time(NULL));
    chaser_offset = rand() % 40000L;

    // PORT(phase4c-4): upstream uses the bare REMAP/REMAP2/REMAP3 pointers
    // assuming `doInit()` set them to point into `_REMAP_VALUES`. We don't
    // run doInit, so wire the pointers up here.
    REMAP  = &_REMAP_VALUES[0];
    REMAP2 = &_REMAP_VALUES[256];
    REMAP3 = &_REMAP_VALUES[512];

    if (iDispBits == 8) {
        VS1 = (unsigned char *)malloc(FXW * FXH + 1024);
        if (VS1 == nullptr) { dumpmsg("Out of memory"); GeissPort_finiObjects(); return 1; }
        VS2 = (unsigned char *)malloc(FXW * FXH + 1024);
        if (VS2 == nullptr) { dumpmsg("Out of memory"); GeissPort_finiObjects(); return 1; }
        memset(VS1, 0, FXW * FXH);
        memset(VS2, 0, FXW * FXH);
    } else {
        VS1 = (unsigned char *)malloc(FXW * FXH * 4 + 1024);
        if (VS1 == nullptr) { dumpmsg("Out of memory"); GeissPort_finiObjects(); return 1; }
        VS2 = (unsigned char *)malloc(FXW * FXH * 4 + 1024);
        if (VS2 == nullptr) { dumpmsg("Out of memory"); GeissPort_finiObjects(); return 1; }
        memset(VS1, 0, FXW * FXH * 4);
        memset(VS2, 0, FXW * FXH * 4);
    }
    DATA_FX = (unsigned char *)malloc(FXW * FXH * 8 + 1024);
    if (DATA_FX == nullptr) { dumpmsg("Out of memory"); GeissPort_finiObjects(); return 1; }
    DATA_FX2 = (unsigned char *)malloc(FXW * FXH * 8 + 1024);
    if (DATA_FX2 == nullptr) { dumpmsg("Out of memory"); GeissPort_finiObjects(); return 1; }

    original_VS[0]      = VS1;
    original_VS[1]      = VS2;
    original_DATA_FX[0] = DATA_FX;
    original_DATA_FX[1] = DATA_FX2;

    // 16-byte alignment fix-up, preserved verbatim from upstream — uses
    // uintptr_t instead of `unsigned long` (which is 32-bit on Win64 and
    // 64-bit on macOS, so the upstream cast worked accidentally).
    if (((uintptr_t)VS1) % 16 != 0) {
        dumpmsg("align VS1");
        VS1 = (unsigned char *)((((uintptr_t)VS1) / 16 + 1) * 16);
    }
    if (((uintptr_t)VS2) % 16 != 0) {
        dumpmsg("align VS2");
        VS2 = (unsigned char *)((((uintptr_t)VS2) / 16 + 1) * 16);
    }
    if (((uintptr_t)DATA_FX) % 16 != 0) {
        dumpmsg("align DATA_FX");
        DATA_FX = (unsigned char *)((((uintptr_t)DATA_FX) / 16 + 1) * 16);
    }
    if (((uintptr_t)DATA_FX2) % 16 != 0) {
        dumpmsg("align DATA_FX2");
        DATA_FX2 = (unsigned char *)((((uintptr_t)DATA_FX2) / 16 + 1) * 16);
    }

    memset(g_power,          0, sizeof(float) * FOURIER_DETAIL);
    memset(g_power_smoothed, 0, sizeof(float) * FOURIER_DETAIL);

    if (iDispBits == 16) {
        for (z = 0; z < 256; ++z) REMAP[z]  = (unsigned char)(min(255UL, z * 2) >> 3);
        for (z = 0; z < 256; ++z) REMAP2[z] = (unsigned char)(min(255UL, z * 2) >> 2);
    } else {
        for (z = 0; z < 256; ++z) REMAP[z]  = (unsigned char)min(255UL, z * 2);
    }

    for (z = 0; z < SCATTERVALS; ++z)
        fScatter[z] = 0.05f - 0.025f * ((rand() % 1000) * 0.001f);

    frames_since_last_plop = 1;

    for (z = 0; z < 20; ++z) { chaser_x[z] = 1; chaser_y[z] = 1; }

    for (x = 0; x <= 20; ++x)
        for (z = 0; z <= 20; ++z)
            sqrt_tab[x][z] = (float)sqrtf(float((x - 10) * (x - 10) + (z - 10) * (z - 10)));

    for (z = 0; z < 10; ++z) {
        micro_c1[z] = 0.08f + 0.09f * (rand() % 1000) * 0.001f;
        micro_c2[z] = 0.08f + 0.09f * (rand() % 1000) * 0.001f;
        micro_c3[z] = 0.08f + 0.09f * (rand() % 1000) * 0.001f;
        micro_f1[z] = 0.1f  + 0.05f * (rand() % 1000) * 0.001f;
        micro_f2[z] = 0.1f  + 0.05f * (rand() % 1000) * 0.001f;
        micro_f3[z] = 0.1f  + 0.05f * (rand() % 1000) * 0.001f;
        micro_f4[z] = 0.1f  + 0.05f * (rand() % 1000) * 0.001f;
        micro_rad[0][z] = 2.0f + 2.8f * (rand() % 1000) * 0.001f;
        micro_rad[1][z] = 2.0f + 2.8f * (rand() % 1000) * 0.001f;
        micro_rad[2][z] = 2.0f + 2.8f * (rand() % 1000) * 0.001f;
        micro_rad[3][z] = 2.0f + 2.8f * (rand() % 1000) * 0.001f;
    }

    for (z = 0; z < 6;    ++z) gF[z]         = ((rand() % 1000) * 0.001f) * 0.01f + 0.02f;
    for (z = 0; z < 2345; ++z) rand_array[z] = (rand() % 100) * 0.0005f;

    // Per-mode effect-frequency tables (modeInfo[1..16], modeInfo[17..NUM_MODES]),
    // verbatim from upstream main.cpp:4009-4243.
    z = 1;
    modeInfo[z].effect_freq[CHASERS] = 220;
    modeInfo[z].effect_freq[BAR    ] = 150;
    modeInfo[z].effect_freq[DOTS   ] =  10;
    modeInfo[z].effect_freq[SOLAR  ] = 680;
    modeInfo[z].effect_freq[GRID   ] =   4;
    modeInfo[z].effect_freq[NUCLIDE] = 170;
    modeInfo[z].effect_freq[SHADE  ] = 400;
    modeInfo[z].effect_freq[SPECTRAL]=   0;
    modeInfo[z].solar_max = (iDispBits == 8) ? 400 : 800;
    modeInfo[z].center_dwindle = 1.0f;

    z = 2;
    modeInfo[z].effect_freq[CHASERS] = 750;
    modeInfo[z].effect_freq[BAR    ] = 500;
    modeInfo[z].effect_freq[DOTS   ] = 750;
    modeInfo[z].effect_freq[SOLAR  ] = 750;
    modeInfo[z].effect_freq[GRID   ] =   0;
    modeInfo[z].effect_freq[NUCLIDE] =   0;
    modeInfo[z].effect_freq[SHADE  ] =   0;
    modeInfo[z].effect_freq[SPECTRAL]=   0;
    modeInfo[z].solar_max = 35;
    modeInfo[z].center_dwindle = 1.0f;
    modeInfo[z].max_effects = 5;

    z = 3;
    modeInfo[z].effect_freq[CHASERS] = 100;
    modeInfo[z].effect_freq[BAR    ] = 100;
    modeInfo[z].effect_freq[DOTS   ] = 100;
    modeInfo[z].effect_freq[SOLAR  ] = 500;
    modeInfo[z].effect_freq[GRID   ] =  10;
    modeInfo[z].effect_freq[NUCLIDE] =   0;
    modeInfo[z].effect_freq[SHADE  ] = 300;
    modeInfo[z].effect_freq[SPECTRAL]=   0;
    modeInfo[z].solar_max = 60;
    modeInfo[z].center_dwindle = 0.99f;

    z = 4;
    modeInfo[z].effect_freq[CHASERS] = 500;
    modeInfo[z].effect_freq[BAR    ] = 100;
    modeInfo[z].effect_freq[DOTS   ] = 100;
    modeInfo[z].effect_freq[SOLAR  ] = 100;
    modeInfo[z].effect_freq[GRID   ] =  30;
    modeInfo[z].effect_freq[NUCLIDE] =   0;
    modeInfo[z].effect_freq[SHADE  ] =   0;
    modeInfo[z].effect_freq[SPECTRAL]=   0;
    modeInfo[z].solar_max = 34;
    modeInfo[z].center_dwindle = 0.98f;

    z = 5;
    modeInfo[z].effect_freq[CHASERS] = 100;
    modeInfo[z].effect_freq[BAR    ] = 350;
    modeInfo[z].effect_freq[DOTS   ] = 100;
    modeInfo[z].effect_freq[SOLAR  ] = 500;
    modeInfo[z].effect_freq[GRID   ] =  15;
    modeInfo[z].effect_freq[NUCLIDE] = 180;
    modeInfo[z].effect_freq[SHADE  ] = 500;
    modeInfo[z].effect_freq[SPECTRAL]=   0;
    modeInfo[z].solar_max = 60;
    modeInfo[z].center_dwindle = 0.99f;

    z = 6;
    modeInfo[z].effect_freq[CHASERS] = 400;
    modeInfo[z].effect_freq[BAR    ] = 120;
    modeInfo[z].effect_freq[DOTS   ] = 200;
    modeInfo[z].effect_freq[SOLAR  ] =   0;
    modeInfo[z].effect_freq[GRID   ] =   0;
    modeInfo[z].effect_freq[NUCLIDE] =   0;
    modeInfo[z].effect_freq[SHADE  ] =   0;
    modeInfo[z].effect_freq[SPECTRAL]=   0;
    modeInfo[z].solar_max = 60;
    modeInfo[z].center_dwindle = 1.0f;

    z = 7;
    modeInfo[z].effect_freq[CHASERS] =  50;
    modeInfo[z].effect_freq[BAR    ] = 200;
    modeInfo[z].effect_freq[DOTS   ] =   0;
    modeInfo[z].effect_freq[SOLAR  ] = 300;
    modeInfo[z].effect_freq[GRID   ] =   0;
    modeInfo[z].effect_freq[NUCLIDE] = 600;
    modeInfo[z].effect_freq[SHADE  ] = 350;
    modeInfo[z].effect_freq[SPECTRAL]=   0;
    modeInfo[z].solar_max = 65;
    modeInfo[z].center_dwindle = 0.985f;

    z = 8;
    modeInfo[z].effect_freq[CHASERS] = 150;
    modeInfo[z].effect_freq[BAR    ] = 150;
    modeInfo[z].effect_freq[DOTS   ] = 150;
    modeInfo[z].effect_freq[SOLAR  ] = 150;
    modeInfo[z].effect_freq[GRID   ] =  25;
    modeInfo[z].effect_freq[NUCLIDE] =   0;
    modeInfo[z].effect_freq[SHADE  ] =
    modeInfo[z].effect_freq[SPECTRAL]=   0;
    modeInfo[z].solar_max = 60;
    modeInfo[z].center_dwindle = 0.96f;

    z = 9;
    modeInfo[z].effect_freq[CHASERS] = 450;
    modeInfo[z].effect_freq[BAR    ] = 200;
    modeInfo[z].effect_freq[DOTS   ] =  50;
    modeInfo[z].effect_freq[SOLAR  ] = 200;
    modeInfo[z].effect_freq[GRID   ] =   0;
    modeInfo[z].effect_freq[NUCLIDE] = 100;
    modeInfo[z].effect_freq[SHADE  ] = 200;
    modeInfo[z].effect_freq[SPECTRAL]=   0;
    modeInfo[z].solar_max = 50;
    modeInfo[z].center_dwindle = 0.985f;

    z = 10;
    modeInfo[z].effect_freq[CHASERS] = 150;
    modeInfo[z].effect_freq[BAR    ] =  20;
    modeInfo[z].effect_freq[DOTS   ] =  80;
    modeInfo[z].effect_freq[SOLAR  ] =   0;
    modeInfo[z].effect_freq[GRID   ] =   0;
    modeInfo[z].effect_freq[NUCLIDE] =  80;
    modeInfo[z].effect_freq[SHADE  ] =   0;
    modeInfo[z].effect_freq[SPECTRAL]=   0;
    modeInfo[z].solar_max      = 0;
    modeInfo[z].center_dwindle = 1.0f;
    modeInfo[z].min_effects    = 0;
    modeInfo[z].max_effects    = 2;

    z = 11;
    modeInfo[z].effect_freq[CHASERS] = 360;
    modeInfo[z].effect_freq[BAR    ] = 200;
    modeInfo[z].effect_freq[DOTS   ] = 230;
    modeInfo[z].effect_freq[SOLAR  ] = 550;
    modeInfo[z].effect_freq[GRID   ] =  10;
    modeInfo[z].effect_freq[NUCLIDE] = 330;
    modeInfo[z].effect_freq[SHADE  ] = 150;
    modeInfo[z].effect_freq[SPECTRAL]=   0;
    modeInfo[z].solar_max      = 750;
    modeInfo[z].center_dwindle = 1.0f;
    modeInfo[z].min_effects    = 0;
    modeInfo[z].max_effects    = 4;

    z = 12; // sideways splitter
    modeInfo[z].effect_freq[CHASERS] = 360;
    modeInfo[z].effect_freq[BAR    ] = 200;
    modeInfo[z].effect_freq[DOTS   ] = 230;
    modeInfo[z].effect_freq[SOLAR  ] =   0;
    modeInfo[z].effect_freq[GRID   ] =   0;
    modeInfo[z].effect_freq[NUCLIDE] = 330;
    modeInfo[z].effect_freq[SHADE  ] =   0;
    modeInfo[z].effect_freq[SPECTRAL]=   0;
    modeInfo[z].solar_max      = 500;
    modeInfo[z].center_dwindle = 0.915f;
    modeInfo[z].min_effects    = 0;
    modeInfo[z].max_effects    = 2;

    z = 13;
    modeInfo[z].effect_freq[CHASERS] = 500;
    modeInfo[z].effect_freq[BAR    ] =   0;
    modeInfo[z].effect_freq[DOTS   ] = 100;
    modeInfo[z].effect_freq[SOLAR  ] =   0;
    modeInfo[z].effect_freq[GRID   ] =  30;
    modeInfo[z].effect_freq[NUCLIDE] =   0;
    modeInfo[z].effect_freq[SHADE  ] =   0;
    modeInfo[z].effect_freq[SPECTRAL]=   0;
    modeInfo[z].solar_max = 34;
    modeInfo[z].center_dwindle = 0.98f;

    z = 14;
    modeInfo[z].effect_freq[CHASERS] = 500;
    modeInfo[z].effect_freq[BAR    ] =   0;
    modeInfo[z].effect_freq[DOTS   ] = 100;
    modeInfo[z].effect_freq[SOLAR  ] =   0;
    modeInfo[z].effect_freq[GRID   ] =  30;
    modeInfo[z].effect_freq[NUCLIDE] =   0;
    modeInfo[z].effect_freq[SHADE  ] =   0;
    modeInfo[z].effect_freq[SPECTRAL]=   0;
    modeInfo[z].solar_max = 34;
    modeInfo[z].center_dwindle = 0.98f;

    z = 15;
    modeInfo[z].effect_freq[CHASERS] =   0;
    modeInfo[z].effect_freq[BAR    ] =   0;
    modeInfo[z].effect_freq[DOTS   ] =   0;
    modeInfo[z].effect_freq[SOLAR  ] =   0;
    modeInfo[z].effect_freq[GRID   ] =   0;
    modeInfo[z].effect_freq[NUCLIDE] = 200;
    modeInfo[z].effect_freq[SHADE  ] =   0;
    modeInfo[z].effect_freq[SPECTRAL]=   0;
    modeInfo[z].center_dwindle = 1.0f;
    modeInfo[z].min_effects    = 0;
    modeInfo[z].max_effects    = 1;

    z = 16;
    modeInfo[z].effect_freq[CHASERS] = 500;
    modeInfo[z].effect_freq[BAR    ] = 100;
    modeInfo[z].effect_freq[DOTS   ] = 100;
    modeInfo[z].effect_freq[SOLAR  ] = 100;
    modeInfo[z].effect_freq[GRID   ] =  30;
    modeInfo[z].effect_freq[NUCLIDE] =   0;
    modeInfo[z].effect_freq[SHADE  ] =   0;
    modeInfo[z].effect_freq[SPECTRAL]=   0;
    modeInfo[z].solar_max = 34;
    modeInfo[z].center_dwindle = 0.98f;

    for (z = 17; z <= NUM_MODES; ++z) {
        modeInfo[z].effect_freq[CHASERS] = 150;
        modeInfo[z].effect_freq[BAR    ] = 150;
        modeInfo[z].effect_freq[DOTS   ] = 150;
        modeInfo[z].effect_freq[SOLAR  ] = 150;
        modeInfo[z].effect_freq[GRID   ] =  12;
        modeInfo[z].effect_freq[NUCLIDE] =   0;
        modeInfo[z].effect_freq[SHADE  ] =  50;
        modeInfo[z].effect_freq[SPECTRAL]=   0;
        modeInfo[z].solar_max      = 600;
        modeInfo[z].min_effects    = 1;
        modeInfo[z].max_effects    = 3;
        modeInfo[z].center_dwindle = 1.0f;
    }

    for (z = 1; z <= NUM_MODES; ++z) {
        if (iDispBits > 8) {
            modeInfo[z].effect_freq[NUCLIDE] = max(0, min(900, (int)(modeInfo[z].effect_freq[NUCLIDE] * 1.3f)));
            modeInfo[z].effect_freq[CHASERS] = max(0, min(900, modeInfo[z].effect_freq[CHASERS] -  50));
            modeInfo[z].effect_freq[DOTS]    = max(0, min(900, modeInfo[z].effect_freq[DOTS   ] + 220));
            modeInfo[z].effect_freq[BAR ]    = max(0, min(900, modeInfo[z].effect_freq[BAR    ] + 220));
            modeInfo[z].effect_freq[SHADE]   = max(0, min(900, modeInfo[z].effect_freq[SHADE  ] + 150));
        }
        modeInfo[z].effect_freq[GRID] = min(1000, modeInfo[z].effect_freq[GRID] + 8);
    }

    modeInfo[20].center_dwindle = 0.98f;
    modeInfo[21].center_dwindle = 0.98f;
    modeInfo[22].center_dwindle = 0.98f;
    modeInfo[23].center_dwindle = 0.98f;

    dumpmsg("  Calling initial FX_Pick_Random_Mode() and GenerateChunkOfNewMap() loop...");

    FX_Pick_Random_Mode();
    g_rush_map  = TRUE;
    y_map_pos   = -1;
    do {
        GenerateChunkOfNewMap();
    } while (y_map_pos != -1);

    dumpmsg("Finished with FX_Init().");

    return TRUE;
}

void FX_Fini() {
    // Upstream uses `delete` for buffers allocated via `malloc()` — undefined
    // behaviour in C++ that happens to work on MSVC. We use the matching
    // `free()`. The pointer-realignment fix-up in FX_Init means VS1/VS2/
    // DATA_FX/DATA_FX2 may differ from `original_*` by up to 15 bytes; we
    // free the *originals*.
    if (original_VS[0]      != nullptr) { free(original_VS[0]);      original_VS[0]      = nullptr; VS1      = nullptr; }
    if (original_VS[1]      != nullptr) { free(original_VS[1]);      original_VS[1]      = nullptr; VS2      = nullptr; }
    if (original_DATA_FX[0] != nullptr) { free(original_DATA_FX[0]); original_DATA_FX[0] = nullptr; DATA_FX  = nullptr; }
    if (original_DATA_FX[1] != nullptr) { free(original_DATA_FX[1]); original_DATA_FX[1] = nullptr; DATA_FX2 = nullptr; }
    // Upstream's PLUGIN-only `DeleteObject(g_title_font)` is dead-code on
    // macOS — there is no GDI font to release.
    g_title_font = nullptr;
}

void FX_Pick_Random_Mode() {
    if (modeprefs_total <= 0) {
        new_mode = 1 + rand() % NUM_MODES;
        if (rand() % 25 == 0) new_mode = 7;
        if (rand() % 25 == 0) new_mode = 5;
        y_map_pos = -1;
    } else {
        int a = rand() % modeprefs_total;
        int b = 0;
        int i = 1;
        while (i <= NUM_MODES) {
            b += modeprefs[i];
            if (a < b) {
                new_mode = i;
                i = 9999;
                y_map_pos = -1;
            }
            ++i;
        }
    }
}

// ---------------------------------------------------------------------------
// Phase 4c-5: GenerateChunkOfNewMap — direct port of upstream main.cpp:4312-5411.
// Builds DATA_FX2 incrementally, one row of pixels per call, until the full
// frame's worth of warp-map weights + per-pixel cumulative-delta lookat
// offsets is written. When the chunk is complete (`y_map_pos` reaches
// `(FXH-FX_YCUT)*FXW`) the buffer is swapped with the active DATA_FX so
// the new map takes effect on the next Process_Map invocation.
//
// Win32-only call sites (Get/WritePrivateProfileString) survive but route
// through the no-op stubs in `win_compat.h`. The float-to-int reinterpret
// `((int *)(DATA_FX2))[(A_offset + 4)/4] = ...` is permitted because
// `-fno-strict-aliasing` is set in `Package.swift`'s cxxSettings; this
// matches upstream's relied-upon behaviour.
// ---------------------------------------------------------------------------

void GenerateChunkOfNewMap(bool bLoadPreset, int iPresetNum) {
    if (y_map_pos == -1) {
        y_map_pos = FX_YCUT * FXW;
    }
    if (y_map_pos < FX_YCUT * FXW || y_map_pos > (FXH - FX_YCUT) * FXW) {
        dumpmsg("FATAL ERROR: GenerateChunkOfNewMap(): received y_map_pos that was out of range");
        exit(99);
    }

    unsigned long a, b;
    long          k;
    float         newx, newy, newx2, newy2;
    long          x, y, n;
    float         tx, ty, d, e, f, r;
    int           A_offset, R_offset_rel;
    float         inv_FXW   = 2.0f / FXW;
    float         half_FXW  = 0.5f * FXW;
    int           bytewidth = (iDispBits == 8) ? 1 : 4;
    (void)e;

    if (y_map_pos == FX_YCUT * FXW) {
        g_bLoadPreset = bLoadPreset;
        g_iPresetNum  = iPresetNum;

        if (!bLoadPreset) {
            new_gXC = FXW / 2 - 1 + rand() % 60 - 30;
            new_gYC = FXH / 2 - 1 + rand() % 30 - 15;

            weightsum = 256;

            new_damping = suggested_damping;
            if (new_damping < 0.50f) new_damping = 0.50f;
            if (new_damping > 1.00f) new_damping = 1.00f;
            if (mode_motion_dampened[new_mode]) new_damping *= 0.5f;

            do {
                new_waveform = (rand() % (NUM_WAVES * 3 - 1)) / 3 + 1;
            } while ((new_mode == 6 && new_waveform == 5) ||
                     (new_mode == 12 && (new_waveform == 4 || new_waveform == 6)) ||
                     (new_mode == 14 && (new_waveform == 3 || new_waveform == 4)) ||
                     ((new_mode == 8 || new_mode == 23 || new_mode == 24) && new_waveform == 6));
        }
        fBigBeatThreshold          = 1.10f;
        frames_this_mode           = 0;
        frames_crunching_this_mode = 0;

        if (new_mode == 1) {
            scale1 = 0.985f - 0.12f * powf((rand() % 1000) * 0.001f, 2.0f);
            scale2 = scale1;
            turn1  = 0.01f + 0.01f * ((rand() % 1000) * 0.001f);
            turn2  = turn1;
            if (scale1 > 0.97f && rand() % 3 == 1) turn1 *= -1;
        } else if (new_mode == 2) {
            scale1 = 1.00f + 0.02f * ((rand() % 1000) * 0.001f);
            turn1  = 0.02f + 0.07f * ((rand() % 1000) * 0.001f);
        } else if (new_mode == 3) {
            scale1 = 0.85f + 0.1f * ((rand() % 1000) * 0.001f);
            scale2 = scale1;
            turn1  = 0.01f + 0.015f * ((rand() % 1000) * 0.001f);
            turn2  = turn1;
        } else if (new_mode == 4) {
            turn1 = 0.007f + 0.02f * ((rand() % 1000) * 0.001f);
            turn2 = turn1;
        } else if (new_mode == 5) {
            turn1 = 0.01f + 0.03f * ((rand() % 1000) * 0.001f);
            turn2 = turn1;
        } else if (new_mode == 6) {
            f = 0;
            int iNumPushTypes = 3;
            for (x = 0; x < 10; ++x) {
                cx[x]      = (rand() % (FXW * 10)) * 0.1f;
                cy[x]      = FX_YCUT + (rand() % ((FXH - FX_YCUT * 2) * 10)) * 0.1f;
                d          = (rand() % 628) * 0.01f;
                f          = 1.0f + (rand() % 80) * 0.01f;
                ci[x]      = cosf(d) * f;
                cj[x]      = sinf(d) * f;
                ctype[x]   = rand() % iNumPushTypes;
                cr[x]      = 80.0f + (rand() % 1200) * 0.1f;
                cr_inv[x]  = 1.0f / cr[x];
            }
        } else if (new_mode == 7) {
            turn1 = 0.01f + 0.01f * ((rand() % 1000) * 0.001f);
            turn2 = turn1;
        } else if (new_mode == 8) {
            turn1 = 0.05f * (0.001f * (rand() % 1000));
            turn2 = turn1;
        } else if (new_mode == 9) {
            scale1 = 0.8f + 0.25f * ((rand() % 1000) * 0.001f);
            scale1 = (scale1 - 1) * protective_factor + 1;
            scale2 = scale1;
            turn1  = 0.01f + 0.03f * ((rand() % 1000) * 0.001f);
            turn2  = turn1;
        } else if (new_mode == 10) {
            // no init
        } else if (new_mode == 11) {
            scale1 = 1.008f + 0.008f * ((rand() % 1000) * 0.001f);
            scale2 = scale1;
            turn1  = 0.12f + 0.06f * ((rand() % 1000) * 0.001f);
            turn2  = turn1;
            turn1  *= -0.6f;
            turn2  *= 0.1f;
            scale1 *= 0.99f;
            scale2 *= 1.01f;
        } else if (new_mode == 12) {
            weightsum = (int)(weightsum * 0.98f);
        } else if (new_mode == 13) {
            turn1 = 0.007f + 0.02f * ((rand() % 1000) * 0.001f);
            turn2 = turn1;
        } else if (new_mode == 14) {
            turn1 = 0.007f + 0.02f * ((rand() % 1000) * 0.001f);
            turn2 = turn1;
        } else if (new_mode == 15) {
            turn1 = 0.04f * ((rand() % 1000) * 0.001f) +
                    0.045f * ((rand() % 1000) * 0.001f);
            turn2 = turn1;
        } else if (new_mode == 16) {
            turn1 = 0.007f + 0.02f * ((rand() % 1000) * 0.001f);
            turn2 = turn1;
        } else if (new_mode >= 17) {
            turn1 = 0.007f + 0.02f * ((rand() % 1000) * 0.001f);
            turn2 = turn1;
        }

        if (rand() % 2 == 1) { turn1 *= -1; turn2 *= -1; }

        f1 = 0.92f + 0.05f * ((rand() % 1000) * 0.001f);
        f2 = 0.0009f + 0.0012f * ((rand() % 1000) * 0.001f);

        if (new_mode == 5) {
            f1 = 0.05f + 0.05f * ((rand() % 1000) * 0.001f) + 0.07f * ((rand() % 1000) * 0.001f);
            f2 = 0.99f - 0.01f * ((rand() % 1000) * 0.001f) - 0.02f * ((rand() % 1000) * 0.001f);
        } else if (new_mode == 7) {
            f1 = 0.92f + 0.01f * ((rand() % 1000) * 0.001f);
            f2 = 0.0006f + 0.0005f * ((rand() % 1000) * 0.001f);
        } else if (new_mode == 8) {
            f1 = (0.001f * (rand() % 1000));
            f1 *= f1;
            f1 *= f1;
            f1 *= 8.0f;
            f1 += 1.5f;
        } else if (new_mode == 9) {
            f1 = 0.98f + 0.01f * ((rand() % 1000) * 0.001f);
            f2 = 0.0009f + 0.0012f * ((rand() % 1000) * 0.001f);
        } else if (new_mode == 13) {
            f1 = 0.92f + 0.16f * ((rand() % 1000) * 0.001f);
        } else if (new_mode == 15) {
            f1 = (float)(rand() % 5 + 2);
            f2 = 0.92f + 0.06f * ((rand() % 1000) * 0.001f);
            f3 = 0.05f + 0.05f * ((rand() % 1000) * 0.001f);
        } else if (new_mode == 17) {
            f1 = 0.01f + 0.09f * ((rand() % 1000) * 0.001f);
            f2 = 0.01f + 0.09f * ((rand() % 1000) * 0.001f);
            f3 = 0.01f + 0.09f * ((rand() % 1000) * 0.001f);
            f4 = 0.01f + 0.09f * ((rand() % 1000) * 0.001f);
        }

        turn1 *= 0.6f;
        turn2 *= 0.6f;

        R_offset = 0;

        max_rad_inv       = 1.0f / sqrtf(float(FXW * FXW + FXH * FXH));
        rmult             = 640.0f / (float)FXW;
        rdiv              = 1.0f / rmult;
        protective_factor = (FXW > 640) ? 640.0f / (float)FXW : 1.0f;

        if (bLoadPreset) {
            char section[64];
            snprintf(section, sizeof(section), "PRESET %d", iPresetNum);
            char temp[64];
            GetPrivateProfileString(section, "t1", "1", temp, 64, inifile); sscanf(temp, "%f", &turn1);
            GetPrivateProfileString(section, "t2", "1", temp, 64, inifile); sscanf(temp, "%f", &turn2);
            GetPrivateProfileString(section, "s1", "1", temp, 64, inifile); sscanf(temp, "%f", &scale1);
            GetPrivateProfileString(section, "s2", "1", temp, 64, inifile); sscanf(temp, "%f", &scale2);
            GetPrivateProfileString(section, "f1", "1", temp, 64, inifile); sscanf(temp, "%f", &f1);
            GetPrivateProfileString(section, "f2", "1", temp, 64, inifile); sscanf(temp, "%f", &f2);
            GetPrivateProfileString(section, "f3", "1", temp, 64, inifile); sscanf(temp, "%f", &f3);
            GetPrivateProfileString(section, "f4", "1", temp, 64, inifile); sscanf(temp, "%f", &f4);
        }

        cos_turn1 = cosf(turn1);
        sin_turn1 = sinf(turn1);
        cos_turn2 = cosf(turn2);
        sin_turn2 = sinf(turn2);

        if (FXW * FXH <= 320 * 240)
            weightsum_res_adjusted = weightsum * 250 / 256;
        else if (FXW * FXH <= 400 * 300)
            weightsum_res_adjusted = weightsum * 251 / 256;
        else if (FXW * FXH <= 512 * 384)
            weightsum_res_adjusted = weightsum * 252 / 256;
        else if (FXW * FXH <= 800 * 600)
            weightsum_res_adjusted = weightsum * 253 / 256;
        else if (FXW * FXH <= 1280 * 960)
            weightsum_res_adjusted = weightsum * 254 / 256;
        else
            weightsum_res_adjusted = weightsum * 255 / 256;

        frames_til_auto_switch = frames_til_auto_switch__registry;
        if (fps >= 10.0f && fps < 120.0f)
            frames_til_auto_switch = (int)(frames_til_auto_switch__registry * fps / 30.0f);

        if (bLoadPreset) dumpmsg("preset loaded... applying");
    }

    if (y_map_pos < (FXH - FX_YCUT) * FXW) {
        float i_unused, j_unused, z_local;
        (void)i_unused; (void)j_unused;
        float xxyy;

        frames_crunching_this_mode++;

        float new_damping_temp = new_damping;
        if (fps_at_last_mode_switch >= 10.0f && fps_at_last_mode_switch <= 120.0f)
            new_damping_temp *= 30.0f / fps_at_last_mode_switch;

        int end_pos = (int)(FXW * (FX_YCUT + ((float)frames_crunching_this_mode / (float)frames_til_auto_switch) * (float)(FXH - FX_YCUT * 2)));
        if (g_rush_map || end_pos > FXW * (FXH - FX_YCUT)) {
            end_pos = FXW * (FXH - FX_YCUT);
        }

        y = y_map_pos / FXW;
        x = y_map_pos % FXW;

        for ( ; y_map_pos < end_pos; ++y_map_pos) {
            A_offset = (int)(((long)y * FXW + (long)x) * 8);
            old_R_offset = R_offset;

            newx2 = (float)(x - new_gXC);
            newy2 = (float)(y - new_gYC);

            if (new_mode <= 16) {
                half_FXW = 1.0f;

                if (new_mode == 3) {
                    scale1 = 0.95f - (newy2 * (480.0f / FXH)) * 0.0005f;
                } else if (new_mode == 4) {
                    r = sqrtf(newx2 * newx2 + newy2 * newy2);
                    r *= rmult;
                    scale1 = 0.9f + r * 0.0025f * 0.14f;
                } else if (new_mode == 5) {
                    r = sqrtf(newx2 * newx2 + newy2 * newy2);
                    r *= (1.0f / 200.0f);
                    r *= rmult;
                    if (effect[NUCLIDE] == -1)
                        r = sqrtf(r);
                    else
                        r *= 1.7f;
                    scale1 = f2 - f1 * r;
                    scale1 = (scale1 - 1) * protective_factor + 1;
                } else if (new_mode == 7) {
                    r = sqrtf(newx2 * newx2 + newy2 * newy2) * f2;
                    r *= rmult;
                    scale1 = (f1 - r);
                    scale1 = (scale1 - 1) * protective_factor + 1;
                    scale1 += rand_array[rand_array_pos++];
                    if (rand_array_pos >= 2345) rand_array_pos = 0;
                } else if (new_mode == 8) {
                    r = sqrtf(newx2 * newx2 + newy2 * newy2);
                    r *= rmult;
                    scale1 = 0.85f + 0.1f * sinf(sqrtf(r) * f1);
                } else if (new_mode == 9) {
                    r = sqrtf(newx2 * newx2 + newy2 * newy2) * f2;
                    r *= rmult;
                    scale1 = f1 - r;
                    scale1 = (scale1 - 1) * protective_factor + 1;
                } else if (new_mode == 13) {
                    r = sqrtf(newx2 * newx2 + newy2 * newy2);
                    r *= rmult;
                    scale1 = 1.04f - r * sqrtf(r) * 0.00025f * 0.14f;
                    scale1 = (scale1 - 1) * f1 + 1;
                } else if (new_mode == 14) {
                    scale1 = 0.9f + 0.2f * cosf(newy2 * 12.0f / (float)(FXH + (rand() & 1023) / 1024.0f));
                } else if (new_mode == 15) {
                    scale1 = f2 + f3 * sinf(atan2f(newy2, newx2) * f1);
                } else if (new_mode == 16) {
                    r = sqrtf(newx2 * newx2 + newy2 * newy2);
                    r *= rmult;
                    scale1 = 1.05f - r * r * 0.00025f * 0.09f;
                    if (scale1 < -1.5f) scale1 = -1.5f;
                }
            } else { // new_mode >= 17
                newx2 *= inv_FXW;
                newy2 *= inv_FXW;

                if (new_mode == 17) {
                    scale1 = 0.97f - newy2 * newy2 * 0.40f;
                } else if (new_mode == 18) {
                    scale1 = 0.97f - newx2 * newx2 * 0.40f;
                } else if (new_mode == 19) {
                    scale1 = 1.04f - 0.25f * sqrtf(newx2 * newx2 + newy2 * newy2);
                } else if (new_mode == 20) {
                    scale1 = 1.15f - sqrtf(newy2 + 1.4f) * 0.20f;
                } else if (new_mode == 21) {
                    scale1 = 0.95f - ((int)(fabsf(newx2) * 10)) * 0.03f - ((int)(fabsf(newy2) * 10)) * 0.03f;
                } else if (new_mode == 22) {
                    scale1 = 0.95f - ((int)(sqrtf(newx2 * newx2 + newy2 * newy2) * 10)) * 0.04f;
                } else if (new_mode == 23) {
                    scale1 = 0.95f - (((int)(sqrtf(newx2 * newx2 + newy2 * newy2) * 20)) % 4) * 0.12f;
                } else if (new_mode == 24) {
                    scale1    = 0.96f;
                    turn1     = 0.05f;
                    cos_turn1 = cosf(turn1);
                    sin_turn1 = sinf(turn1);
                } else if (new_mode == 25) {
                    scale1 = 3.0f / (3.0f + sqrtf(newx2 * newx2 + newy2 * newy2));
                }
            }

            if (custom_motion_vectors[new_mode]) {
                if (new_mode == 6) {
                    tx = 0;
                    ty = 0;
                    f  = 0;
                    for (n = 0; n < 5; ++n) {
                        if (ctype[n] == 0) {
                            newx = cx[n] - x;
                            newy = cy[n] - y;
                            d    = (newx * newx + newy * newy);
                            d    = 1.0f / (d + 0.1f);
                            f   += d;
                            tx  += ci[n] * d;
                            ty  += cj[n] * d;
                        } else if (ctype[n] == 1) {
                            newx    = cx[n] - x;
                            newy    = cy[n] - y;
                            xxyy    = (newx * newx + newy * newy);
                            d       = xxyy;
                            d       = 1.0f / (d + 0.1f);
                            f      += d;
                            z_local = sqrtf(xxyy);
                            z_local = 1.0f / (z_local + 0.01f);
                            d      += d;
                            tx     += d * (-newy) * z_local;
                            ty     += d * (newx)  * z_local;
                        } else if (ctype[n] == 2) {
                            newx    = cx[n] - x;
                            newy    = cy[n] - y;
                            xxyy    = (newx * newx + newy * newy);
                            d       = xxyy;
                            d       = 1.0f / (d + 0.1f);
                            f      += d;
                            z_local = sqrtf(xxyy);
                            z_local = 1.0f / (z_local + 0.01f);
                            d      += d;
                            tx     += d * (newy)  * z_local;
                            ty     += d * (-newx) * z_local;
                        }
                    }
                    if (f > 0.000001f) {
                        f  = 1.9f / f;
                        tx = tx * f;
                        ty = ty * f;
                    } else {
                        tx = 0;
                        ty = 0;
                    }
                    newx = x + tx - 0.1f;
                    newy = y + ty + 0.6f;
                } else if (new_mode == 10) {
                    newx = newx2 * (1.03f + 0.03f * (y / (float)FXH)) + new_gXC;
                    newy = y * 1.04f;
                } else if (new_mode == 12) {
                    if (newx2 < -0.5f)
                        newx = -sqrtf(-newx2) + new_gXC + 0.9f;
                    else if (newx2 > 0.5f)
                        newx = sqrtf(newx2) + new_gXC - 0.9f;
                    else
                        newx = (float)new_gXC;
                    newy = newy2 + new_gYC;
                }
            } else if (rotation_dither[new_mode]) {
                if ((x % 2) == (y % 2)) {
                    newx = newx2 * cos_turn1 - newy2 * sin_turn1;
                    newy = newx2 * sin_turn1 + newy2 * cos_turn1;
                    newx = newx * scale1 * half_FXW + new_gXC;
                    newy = newy * scale1 * half_FXW + new_gYC;
                } else {
                    newx = newx2 * cos_turn2 - newy2 * sin_turn2;
                    newy = newx2 * sin_turn2 + newy2 * cos_turn2;
                    newx = newx * scale2 * half_FXW + new_gXC;
                    newy = newy * scale2 * half_FXW + new_gYC;
                }
            } else {
                newx = newx2 * cos_turn1 - newy2 * sin_turn1;
                newy = newx2 * sin_turn1 + newy2 * cos_turn1;
                newx = newx * scale1 * half_FXW + new_gXC;
                newy = newy * scale1 * half_FXW + new_gYC;
            }

            // Damping mix + horizontal wraparound — verbatim.
            newx = x * (1.0f - new_damping_temp) + newx * new_damping_temp;
            newy = y * (1.0f - new_damping_temp) + newy * new_damping_temp;
            while (newx < 0.0f)      newx += FXW - 1;
            while (newx > FXW - 1)   newx -= FXW - 1;

            a = (unsigned long)(int)newx;
            b = (unsigned long)(int)newy;
            R_offset = (int)(b * FXW + a);

            if (R_offset < FXW * 2)
                R_offset = (int)(FXW * 2);
            if (R_offset >= FXW * (FXH - 3) - 1)
                R_offset = (int)(FXW * (FXH - 3) - 1);

            R_offset_rel = R_offset - old_R_offset;

            int weightsum_this_pixel = weightsum_res_adjusted;

            newx2 = (newx - a);
            newy2 = (newy - b);

            DATA_FX2[A_offset + 0] = (unsigned char)((1 - newx2) * (1 - newy2) * weightsum_this_pixel);
            DATA_FX2[A_offset + 1] = (unsigned char)((  newx2)  * (1 - newy2) * weightsum_this_pixel);
            DATA_FX2[A_offset + 2] = (unsigned char)((1 - newx2) * (  newy2)  * weightsum_this_pixel);
            DATA_FX2[A_offset + 3] = (unsigned char)((  newx2)  * (  newy2)  * weightsum_this_pixel);
            // The cumulative-delta lookat offset is stored as a 32-bit signed
            // int at byte offset (A_offset+4). Upstream uses an aliased int*
            // write which is UB under strict aliasing — `Package.swift` sets
            // `-fno-strict-aliasing` so this is the same behaviour as MSVC.
            *((int *)(DATA_FX2 + A_offset + 4)) = R_offset_rel * bytewidth;

            old_R_offset = R_offset;

            ++x;
            if (x == FXW) { x = 0; ++y; }
        }
    }

    if (y_map_pos == (FXH - FX_YCUT) * FXW &&
        !g_rush_map &&
        bBeatMode &&
        !bBigBeat) {
        fBigBeatThreshold -= 0.2f / (float)frames_til_auto_switch;
    } else if (y_map_pos == (FXH - FX_YCUT) * FXW &&
               (g_rush_map || (!bBeatMode || (bBeatMode && bBigBeat)))) {
        bLoadPreset = g_bLoadPreset;
        iPresetNum  = g_iPresetNum;

        y_map_pos = -1;

        mode     = new_mode;
        damping  = new_damping;
        gXC      = new_gXC;
        gYC      = new_gYC;
        waveform = new_waveform;

        if (fps >= 5.0f && fps <= 120.0f)
            fps_at_last_mode_switch = fps;

        if (bLoadPreset) dumpmsg("preset map generated.");

        old_f1        = f1;
        old_f2        = f2;
        old_f3        = f3;
        old_f4        = f4;
        old_weightsum = weightsum;
        old_turn1     = turn1;
        old_turn2     = turn2;
        old_scale1    = scale1;
        old_scale2    = scale2;

        // Don't clear user-set mode lock on effect change (see Plan §0.2)
        // bLocked = FALSE;

        // Clear off-screen edge bands for the new mode.
        if (mode != 6) {
            k = max(0L, (long)FX_YCUT_HIDE - 6);
            x = min(6L, (long)FX_YCUT_HIDE);
            if (iDispBits == 8) {
                memset(&VS1[k * FXW],             0, FXW * x);
                memset(&VS1[(FXH - 1 - k - x) * FXW], 0, FXW * x);
                memset(&VS2[k * FXW],             0, FXW * x);
                memset(&VS2[(FXH - 1 - k - x) * FXW], 0, FXW * x);
            } else {
                memset(&VS1[k * FXW * 4],             0, FXW * x * 4);
                memset(&VS1[(FXH - 1 - k - x) * FXW * 4], 0, FXW * x * 4);
                memset(&VS2[k * FXW * 4],             0, FXW * x * 4);
                memset(&VS2[(FXH - 1 - k - x) * FXW * 4], 0, FXW * x * 4);
            }
        }

        if (bLoadPreset) {
            char section[64];
            snprintf(section, sizeof(section), "PRESET %d", iPresetNum);
            effect[CHASERS]  = GetPrivateProfileInt(section, "effect_chasers",   0, inifile);
            effect[BAR]      = GetPrivateProfileInt(section, "effect_bar",       0, inifile);
            effect[DOTS]     = GetPrivateProfileInt(section, "effect_dots",      0, inifile);
            effect[SOLAR]    = GetPrivateProfileInt(section, "effect_solar",     0, inifile);
            effect[GRID]     = GetPrivateProfileInt(section, "effect_grid",      0, inifile);
            effect[NUCLIDE]  = GetPrivateProfileInt(section, "effect_nuclide",   0, inifile);
            effect[SHADE]    = GetPrivateProfileInt(section, "effect_shadebobs", 0, inifile);
            effect[SPECTRAL] = GetPrivateProfileInt(section, "effect_spectral",  0, inifile);
            g_bSlideShift    = GetPrivateProfileInt(section, "shift",            0, inifile);
        } else {
            g_bSlideShift = (rand() % 100 + 1) <= g_SlideShiftFreq;

            for (x = 0; x < NUM_EFFECTS; ++x) {
                int thresh = modeInfo[mode].effect_freq[x];
                if (SoundActive && !SoundEmpty) thresh = (int)(thresh * 0.7f);
                effect[x] = (rand() % 1000 < thresh) ? 1 : -1;
            }
            modeInfo[mode].Clip_Num_Effects();

            if (effect[CHASERS] == 1) {
                effect[CHASERS] = 1 + rand() % 2;
            }
            if (effect[GRID] == 1) effect[BAR] = -1;

            if (mode == 1 && rand() % 2 == 0) Drop_Solar_Particles(500);

            grid_dir = (rand() % 2) * 2 - 1;
            if (effect[NUCLIDE] > 0 && rand() % 7 > 2) waveform = 0;

            visMode = wave;

            if (new_mode == 10) {
                waveform = 1;
                if (rand() % 4 > 0) visMode = spectrum;
            }
            if (new_mode == 15 && rand() % 5 == 0)
                waveform = 5;
            if (effect[SPECTRAL] == 1)
                waveform = 0;
        }

        if (!g_bSlideShift) { slider1 = 0; }

        solar_max      = modeInfo[mode].solar_max;
        center_dwindle = modeInfo[mode].center_dwindle;

        // Swap DATA_FX <-> DATA_FX2 so the just-built map becomes active.
        unsigned char *pFX = DATA_FX;
        DATA_FX  = DATA_FX2;
        DATA_FX2 = pFX;

        if (!bLoadPreset && intframe > 0) {
            FX_Random_Palette();
        }

        g_rush_map = false;
    }

    bLoadPreset = false;
}

// ---------------------------------------------------------------------------
// Phase 4c-6: GetWaveData / RenderDots / RenderWave / RenderFX
//
// GetWaveData is the audio-analysis pipeline — level trigger, FFT-based
// fourier analysis, smoothing, centroid normalisation. Its upstream PLUGIN
// branch reads from `g_this_mod->waveformData[ch][i]` (8-bit, biased by
// 128) and `g_this_mod->spectrumData[ch][i]` (8-bit). The port fills those
// arrays from `GeissAudioState` via `geiss_port_set_pcm` /
// `geiss_port_set_spectrum` (called by `GeissCore_addPCM` /
// `GeissCore_setSpectrum`); the PLUGIN branch is then preserved verbatim.
//
// RenderDots, RenderWave, and RenderFX are pure visual / DSP code with
// almost no Win32 surface (a `SetCursor(NULL)` in RenderFX, a `sprintf`
// of debug text in RenderWave); the port preserves the algorithms
// line-for-line.
// ---------------------------------------------------------------------------

extern "C" void geiss_port_set_pcm(const float *samples, int count) {
    if (!samples || count <= 0) return;
    const int n = (count > 576) ? 576 : count;
    float absSum = 0.0f;
    float peak = 0.0f;
    // Geiss expects 8-bit samples biased by +128 (Winamp vis convention):
    // a value of 128 == silence, 0 / 255 == extreme negative / positive.
    for (int i = 0; i < n; ++i) {
        float s = samples[i];
        if (s >  1.0f) s =  1.0f;
        if (s < -1.0f) s = -1.0f;
        float a = fabsf(s);
        absSum += a;
        peak = max(peak, a);
        unsigned char b = (unsigned char)(int)(128.0f + s * 127.0f);
        s_geiss_stub_module.waveformData[0][i] = b;
        s_geiss_stub_module.waveformData[1][i] = b;
    }
    for (int i = n; i < 576; ++i) {
        s_geiss_stub_module.waveformData[0][i] = 128;
        s_geiss_stub_module.waveformData[1][i] = 128;
    }

    const float avgAbs = absSum / (float)n;
    SoundEnabled = TRUE;
    SoundReady = TRUE;
    SoundActive = TRUE;
    SoundEmpty = (avgAbs < 0.0015f && peak < 0.010f) ? TRUE : FALSE;
}

extern "C" void geiss_port_set_spectrum(const float *mags, int count) {
    if (!mags || count <= 0) return;
    const int n = (count > 576) ? 576 : count;
    for (int i = 0; i < n; ++i) {
        float m = mags[i];
        if (m < 0.0f) m = 0.0f;
        if (m > 1.0f) m = 1.0f;
        unsigned char b = (unsigned char)(int)(m * 255.0f);
        s_geiss_stub_module.spectrumData[0][i] = b;
        s_geiss_stub_module.spectrumData[1][i] = b;
    }
    for (int i = n; i < 576; ++i) {
        s_geiss_stub_module.spectrumData[0][i] = 0;
        s_geiss_stub_module.spectrumData[1][i] = 0;
    }
}

extern "C" void geiss_port_init_module(void) {
    // Wire g_this_mod to the stub module so upstream reads of
    // `g_this_mod->waveformData[...]` / `spectrumData[...]` work.
    s_geiss_stub_module.description    = (char *)"NullPlayer-Geiss";
    s_geiss_stub_module.hwndParent     = nullptr;
    s_geiss_stub_module.hDllInstance   = nullptr;
    s_geiss_stub_module.sRate          = 44100;
    s_geiss_stub_module.nCh            = 2;
    s_geiss_stub_module.latencyMs      = 0;
    s_geiss_stub_module.delayMs        = 0;
    s_geiss_stub_module.spectrumNch    = 2;
    s_geiss_stub_module.waveformNch    = 2;
    for (int i = 0; i < 576; ++i) {
        s_geiss_stub_module.waveformData[0][i] = 128;
        s_geiss_stub_module.waveformData[1][i] = 128;
        s_geiss_stub_module.spectrumData[0][i] = 0;
        s_geiss_stub_module.spectrumData[1][i] = 0;
    }
    SoundEnabled = TRUE;
    SoundReady = TRUE;
    SoundActive = TRUE;
    SoundEmpty = TRUE;
    g_this_mod = &s_geiss_stub_module;
}

void GetWaveData() {
    float fDiv   = (1.0f / (64.0f * (640.0f / (float)FXW)));
    float billy  = volscale * fDiv;
    int   i;

    if (SoundReady && SoundActive) {
        // PLUGIN branch — reads waveform / spectrum from g_this_mod.
        int FXW_DIV_4 = FXW / 4;
        int x = 0;
        int y = 5;
        int v;
        int old_v;

        if (visMode != spectrum) {
            y += FXW_DIV_4;

            while (y < (511 - 365 + FXW_DIV_4)) {
                old_v = ((int)(g_this_mod->waveformData[0][y - 5] ^ 128) - 128);
                v     = ((int)(g_this_mod->waveformData[0][y]     ^ 128) - 128);
                if ((abs(v - last_frame_v) <= 1) &&
                    (last_frame_slope * (v - old_v) >= 0)) {
                    last_frame_slope = v - old_v;
                    last_frame_v     = v;
                    break;
                }
                ++y;
            }

            if (y >= (511 - 365 + FXW_DIV_4)) {
                y = 5 + FXW_DIV_4;
                old_v = ((int)(g_this_mod->waveformData[0][y - 5] ^ 128) - 128);
                v     = ((int)(g_this_mod->waveformData[0][y]     ^ 128) - 128);
                last_frame_slope = v - old_v;
                last_frame_v     = v;
            }

            y -= FXW_DIV_4;
        }

        if (visMode == spectrum) {
            __int16 nL, nR;
            int decamt = 2200;
            for (x = 0, y = 0; x < BUFSIZE && y < 512; x += 2, ++y) {
                nL = (((int)(256 - g_this_mod->spectrumData[0][y])) << 10);
                nR = (((int)(256 - g_this_mod->spectrumData[1][y])) << 10);
                nL *= (int)(0.4f + 5.6f * (y / 512.0f));
                nR *= (int)(0.4f + 5.6f * (y / 512.0f));
                g_SoundBuffer[x]     = (__int16)min((int)nL, g_SoundBuffer[x]     + decamt);
                g_SoundBuffer[x + 1] = (__int16)min((int)nR, g_SoundBuffer[x + 1] + decamt);
            }
        } else {
            for ( ; x < BUFSIZE && y < 512; x += 2, ++y) {
                g_SoundBuffer[x]     = (__int16)((((int)(g_this_mod->waveformData[0][y] ^ 128)) - 128) << 8);
                g_SoundBuffer[x + 1] = (__int16)((((int)(g_this_mod->waveformData[1][y] ^ 128)) - 128) << 8);
            }
        }

        // Smoothing + scaling + centroid normalisation, verbatim.
        float center[2];

        for (i = 0; i < BUFSIZE - 2; ++i)
            g_fSoundBuffer[i] = 0.8f * g_SoundBuffer[i] + 0.2f * g_SoundBuffer[i + 2];

        for (i = 0; i < BUFSIZE; ++i)
            g_fSoundBuffer[i] *= billy;

        if (visMode != spectrum) {
            center[0] = 0;
            center[1] = 0;
            for (i = 0; i < BUFSIZE; i += 8) center[0] += g_fSoundBuffer[i];
            for (i = 1; i < BUFSIZE; i += 8) center[1] += g_fSoundBuffer[i];
            center[0] /= (float)FXW * 0.125f;
            center[1] /= (float)FXW * 0.125f;
            for (i = 0; i < BUFSIZE; i += 2) g_fSoundBuffer[i]     -= center[0];
            for (i = 1; i < BUFSIZE; i += 2) g_fSoundBuffer[i]     -= center[1];
        }

        if (iDispBits > 8) {
            int n;
            float theta;
            float a, b;
            float old_power;
            float net_power_change = 1.0f;

            for (n = 1; n < FOURIER_DETAIL; ++n) {
                a = 0;
                b = 0;
                float w = 6.28f * (20.0f * powf(2.0f, n / (float)FOURIER_DETAIL * 10.0f) / 44100.0f);
                for (i = 0; i < 256; ++i) {
                    theta = w * i;
                    a += g_fSoundBuffer[i * 2] * cosf(theta);
                    b += g_fSoundBuffer[i * 2] * sinf(theta);
                }
                old_power           = g_power[n];
                g_power[n]          = sqrtf(a * a + b * b);
                g_power_smoothed[n] = g_power_smoothed[n] * 0.94f + 0.06f * g_power[n];
                net_power_change   += fabsf(old_power - g_power[n]);
            }

            net_power_change /= (float)(iVolumeSum / (intframe + 1));
            net_power_change *= 0.01f;
            if (intframe < 50)
                suggested_damping = 1.0f;
            else
                suggested_damping = suggested_damping * 0.98f + net_power_change * 0.02f;

            suggested_damping = 1.0f; // upstream forces this; map damping is disabled
            debug_param       = suggested_damping;
        }
    }
}

void RenderDots(unsigned char *VS1) {
    if (SoundReady && SoundActive) {
        int   peaks = 0, i = 0, high, low;
        float vol = 0;

        low  = g_SoundBuffer[0];
        high = g_SoundBuffer[0];
        i = BUFSIZE - 4;
        while (i > 0) {
            low  = min((int)low,  (int)g_SoundBuffer[i]);
            high = max((int)high, (int)g_SoundBuffer[i]);
            i -= 4;
        }
        vol = (high - low) / 256.0f;

        past_vol_pos          = (past_vol_pos + 1) % PAST_VOL_N;
        past_vol[past_vol_pos]= current_vol;

        float rate;
        current_vol = vol;
        rate = AdjustRateToFPS(0.30f, 30.0f, fps_at_last_mode_switch); avg_vol_narrow = avg_vol_narrow * rate + vol * (1 - rate);
        rate = AdjustRateToFPS(0.85f, 30.0f, fps_at_last_mode_switch); avg_vol        = avg_vol        * rate + vol * (1 - rate);
        rate = AdjustRateToFPS(0.96f, 30.0f, fps_at_last_mode_switch); avg_vol_wide   = avg_vol_wide   * rate + vol * (1 - rate);
        rate = AdjustRateToFPS(0.90f, 30.0f, fps_at_last_mode_switch); avg_peaks      = avg_peaks      * rate + peaks * (1 - rate);

        iVolumeSum += (int)avg_vol;

        g_hit = max(g_hit - 1, -1);

        if (!g_bDisableSongTitlePopups && g_hit == -1 &&
            (rand() % 7000) < g_random_songtitle_freq * g_random_songtitle_freq * 30.0f / fps_at_last_mode_switch) {
            g_hit = (int)(g_song_tooltip_frames * fps_at_last_mode_switch / 30.0f);
            g_title_R = 128 + rand() % 99;
            g_title_G = 128 + rand() % 99;
            g_title_B = 128 + rand() % 99;
        }

        if (effect[NUCLIDE] > 0 && !SoundEmpty) {
            if (vol > avg_vol_narrow * 1.1f) {
                int nodes = 3 + rand() % 5;
                int n;
                int phase = rand() % 1000;
                int rad;
                int x, y, cxv, cyv, str;
                int val;
                int r;
                if (FXW == 320)
                    r = (int)(2 + 40 * (vol / avg_vol_narrow - 1.1f));
                else
                    r = (int)(3 + 40 * (vol / avg_vol_narrow - 1.1f));
                if (r < 1) r = 1;
                if (FXW == 320 && r >  7) r = 7;
                if (FXW != 320 && r > 10) r = 10;

                if (FXW == 320) {
                    rad = 22 + rand() % 6;
                } else {
                    rad = 34 + rand() % 8;
                    if (FXW > 1024) rad = (int)(rad * FXW / 1024.0f);
                }

                float crv = 1.0f, cgv = 1.0f, cbv = 1.0f;
                if (iDispBits > 8) {
                    int   intfram = intframe + chaser_offset;
                    float fv = 7 * sinf(intfram * 0.007f + 29) + 5 * cosf(intfram * 0.0057f + 27);
                    crv = 0.58f + 0.21f * sinf(intfram * gF[0] + 20 - fv) + 0.21f * cosf(intfram * gF[3] + 17 + fv);
                    cgv = 0.58f + 0.21f * sinf(intfram * gF[1] + 42 + fv) + 0.21f * cosf(intfram * gF[4] + 26 - fv);
                    cbv = 0.58f + 0.21f * sinf(intfram * gF[2] + 57 - fv) + 0.21f * cosf(intfram * gF[5] + 35 + fv);
                }

                long T_offset;
                int  pixelsize = (iDispBits == 8) ? 1 : 4;

                for (n = 0; n < nodes; ++n) {
                    cxv = (int)(gXC + rad * cosf(n / (float)nodes * 6.28f + phase));
                    cyv = (int)(gYC + rad * sinf(n / (float)nodes * 6.28f + phase));

                    for (y = -10; y <= 10; ++y) {
                        T_offset = ((cyv + y) * FXW + (cxv - 10)) * pixelsize;
                        for (x = -10; x <= 10; ++x) {
                            val = (int)((r - sqrt_tab[x + 10][y + 10]) * 25);
                            if (val > 0) {
                                if (iDispBits == 8) {
                                    str = VS1[T_offset] + val;
                                    VS1[T_offset] = (unsigned char)min(255, str);
                                } else {
                                    str = (int)(VS1[T_offset    ] + val * cbv); VS1[T_offset    ] = (unsigned char)min(255, str);
                                    str = (int)(VS1[T_offset + 1] + val * cgv); VS1[T_offset + 1] = (unsigned char)min(255, str);
                                    str = (int)(VS1[T_offset + 2] + val * crv); VS1[T_offset + 2] = (unsigned char)min(255, str);
                                }
                            }
                            T_offset += pixelsize;
                        }
                    }
                }
            }
        }
    }
}

void RenderWave(unsigned char *VS1) {
    int   xL, xR, yL, yR, i;
    float zL, prev_zL, zR, prev_zR;
    long  D_offset;
    int   base = 150;

    base = (int)(current_vol * 4 + avg_vol * 0.4f) - 10;

    past_vol[past_vol_pos] = avg_vol_narrow;

    float avg_vol_uniform = 0;
    for (i = 0; i < PAST_VOL_N; ++i) avg_vol_uniform += past_vol[i];
    avg_vol_uniform /= (float)PAST_VOL_N;

    float beat_strength = 0;
    for (i = 1; i < PAST_VOL_N; ++i)
        beat_strength += max(0.0f, fabsf(past_vol[i] - past_vol[i - 1]) - avg_vol_uniform * 0.15f);
    beat_strength /= avg_vol_uniform;
    beat_strength *= 10;
    if (avg_vol_uniform < 10) beat_strength = 0;

    if (beat_strength > 90 + 19) bBeatMode = true;
    if (beat_strength < 90 - 19) bBeatMode = false;

    float variance = 0;
    float temp_var;
    for (i = 0; i < PAST_VOL_N; ++i) {
        temp_var = (past_vol[i] - avg_vol_uniform);
        variance += temp_var * temp_var;
    }
    variance /= (float)(PAST_VOL_N - 1);
    float std_dev = sqrtf(variance);
    (void)std_dev;

    float max_vol = 0;
    for (i = 0; i < PAST_VOL_N / 3; ++i) max_vol = max(max_vol, past_vol[i]);
    bBigBeat = (avg_vol_narrow > max_vol * fBigBeatThreshold);

    float brite_scale = (current_vol - avg_vol_uniform) / (std_dev * 0.5f);
    if (brite_scale < 0.0f) brite_scale = 0.0f;
    if (brite_scale > 1.0f) brite_scale = 1.0f;

    if (bBeatMode && g_bUseBeatDetection && visMode != spectrum && waveform != 6) {
        base = (int)(base * brite_scale);
    }

    int old_slider1 = slider1;
    if (bBeatMode && g_bSlideShift) {
        if (current_vol > g_ShiftMaxVol) {
            g_ShiftMaxVol = current_vol * 1.05f;
            if (g_FramesSinceShift > 2) {
                g_FramesSinceShift = 0;
                slider1 = ((rand() % (FXW / 2)) + 50) / 145;
                if (old_slider1 > 0) slider1 *= -1;
                slider1 += (rand() % 3 - 1) * FXW;
            }
        } else {
            float rate2 = AdjustRateToFPS(0.975f, 30.0f, fps);
            float limit_vol = avg_vol_uniform * 1.43f;
            g_ShiftMaxVol = g_ShiftMaxVol * rate2 + limit_vol * (1 - rate2);
            ++g_FramesSinceShift;
        }
    }

    snprintf(szDEBUG, sizeof(szDEBUG), "%5.3f ", debug_param);
    if (bBeatMode) strncat(szDEBUG, ", beat mode", sizeof(szDEBUG) - strlen(szDEBUG) - 1);
    if (bBigBeat ) strncat(szDEBUG, ", BIGBEAT",  sizeof(szDEBUG) - strlen(szDEBUG) - 1);

    if (base > 155) base = 155;
    if (base <   0) base = 0;

    unsigned char r, g, b;
    r = (unsigned char)base;
    g = (unsigned char)base;
    b = (unsigned char)base;
    if (iDispBits > 8) {
        if (g_bSyncColorToSound) {
            float ir2, ig2, ib2;
            int   intfram = intframe + chaser_offset;
            float fv = 7 * sinf(intfram * 0.006f + 59) + 5 * cosf(intfram * 0.0077f + 17);
            ir2 = base * 1.07f * (1 + 0.3f * sinf(intfram * gF[0] + 10 - fv)) * (1 + 0.20f * cosf(intfram * gF[1] + 37 + fv));
            ig2 = base * 1.07f * (1 + 0.3f * sinf(intfram * gF[2] + 32 + fv)) * (1 + 0.20f * cosf(intfram * gF[3] + 16 - fv));
            ib2 = base * 1.07f * (1 + 0.3f * sinf(intfram * gF[4] + 87 - fv)) * (1 + 0.20f * cosf(intfram * gF[5] + 25 + fv));

            int a;
            float ir = 0, ig = 0, ib = 0;
            for (a = 0; a < (int)(FOURIER_DETAIL * 0.31f); ++a)                                              ir += g_power_smoothed[a];
            for (a = (int)(FOURIER_DETAIL * 0.30f); a < (int)(FOURIER_DETAIL * 0.59f); ++a)                  ig += g_power_smoothed[a];
            for (a = (int)(FOURIER_DETAIL * 0.56f); a < FOURIER_DETAIL; ++a)                                 ib += g_power_smoothed[a];
            ir *= 0.93f;
            ig *= 1.18f;
            ib *= 2.40f;
            ir -= ib * 0.4f;
            float fnorm = base / sqrtf(ir * ir + ig * ig + ib * ib);
            ir *= fnorm; ig *= fnorm; ib *= fnorm;

            ir = (ir * 0.97f + ir2 * 0.03f) * 1.35f;
            ig = (ig * 0.97f + ig2 * 0.03f) * 1.35f;
            ib = (ib * 0.97f + ib2 * 0.03f) * 1.35f;
            if (ir < 0) ir = 0; if (ir > 255) ir = 255;
            if (ig < 0) ig = 0; if (ig > 255) ig = 255;
            if (ib < 0) ib = 0; if (ib > 255) ib = 255;
            r = (unsigned char)ir; g = (unsigned char)ig; b = (unsigned char)ib;
        } else {
            float ir, ig, ib;
            float intfram = (float)(intframe + chaser_offset) * 30.0f / fps_at_last_mode_switch;
            float fv = 7 * sinf(intfram * 0.006f + 59) + 5 * cosf(intfram * 0.0077f + 17);
            float c1 = 0.55f;
            float c2 = 0.50f;
            ir = base * 1.07f * (1 + c1 * sinf(intfram * gF[0] + 10 - fv)) * (1 + c2 * cosf(intfram * gF[1] + 37 + fv));
            ig = base * 1.07f * (1 + c1 * sinf(intfram * gF[2] + 32 + fv)) * (1 + c2 * cosf(intfram * gF[3] + 16 - fv));
            ib = base * 1.07f * (1 + c1 * sinf(intfram * gF[4] + 87 - fv)) * (1 + c2 * cosf(intfram * gF[5] + 25 + fv));
            if (ir < 0) ir = 0; if (ir > 255) ir = 255;
            if (ig < 0) ig = 0; if (ig > 255) ig = 255;
            if (ib < 0) ib = 0; if (ib > 255) ib = 255;
            r = (unsigned char)ir; g = (unsigned char)ig; b = (unsigned char)ib;
        }
    }

    if (SoundReady && SoundActive && !SoundEmpty) {
        int passes = 0;
        if (waveform == 1 || waveform == 2) {
            if (FXW >= 1920)      passes = 2;
            else if (FXW > 1024)  passes = 1;
        } else {
            if (FXW >= 1440)      passes = 1;
        }
        float amp_scale_per_pass = 1.14f;
        for (int pass = 0; pass < passes; ++pass) {
            float fSoundBufTemp[16384];
            memcpy(fSoundBufTemp, g_fSoundBuffer, sizeof(float) * min(16384, FXW * 4));
            float sL = fSoundBufTemp[0];
            float sR = fSoundBufTemp[1];
            for (int idx = 0; idx < FXW * 2; idx += 2) {
                float tL = fSoundBufTemp[idx + 2] * amp_scale_per_pass;
                float tR = fSoundBufTemp[idx + 3] * amp_scale_per_pass;
                float* p = &g_fSoundBuffer[idx * 2];
                p[0] = sL; p[1] = sR;
                p[2] = 0.5f * (sL + tL);
                p[3] = 0.5f * (sR + tR);
                sL = tL; sR = tR;
            }
        }

        if (waveform == 1) {
            int y_center = gYC;
            int start    = 0;
            int end      = FXW;
            if (mode == 10) {
                y_center = (int)(((FXH - FX_YCUT) + (FXH * 0.5f)) * 0.5f);
                if (visMode == spectrum)
                    y_center = (int)(0.9f * (FXH - FX_YCUT) + 0.1f * (FXH * 0.5f));
                start += 10;
                end   -= 10;
                if (FXW >= 640) { start += 5; end -= 5; }
            }
            zL = g_fSoundBuffer[start & 0xFFFFFFFE] + y_center;
            for (i = start; i < end; ++i) {
                prev_zL = zL;
                zL = g_fSoundBuffer[(i & 0xFFFFFFFE)] + y_center;
                zL = prev_zL * 0.9f + zL * 0.1f;
                yL = (int)zL;
                if (yL >= FX_YCUT_HIDE && yL < FXH - FX_YCUT_HIDE) {
                    D_offset = FXW * yL + i;
                    if (iDispBits == 8) { if (VS1[D_offset] < r) VS1[D_offset] = r; }
                    else { D_offset *= 4;
                        if (VS1[D_offset    ] < b) VS1[D_offset    ] = b;
                        if (VS1[D_offset + 1] < g) VS1[D_offset + 1] = g;
                        if (VS1[D_offset + 2] < r) VS1[D_offset + 2] = r; }
                }
            }
        } else if (waveform == 2) {
            float fDiv = 0.7f;
            float h1   = gYC - FXH * 0.12f;
            float h2   = gYC + FXH * 0.12f;
            zL = g_fSoundBuffer[0] * fDiv + h1;
            zR = g_fSoundBuffer[1] * fDiv + h2;
            for (i = 0; i < FXW; ++i) {
                prev_zL = zL; prev_zR = zR;
                zL = g_fSoundBuffer[(i & 0xFFFFFFFE)]     * fDiv + h1;
                zR = g_fSoundBuffer[(i & 0xFFFFFFFE) + 1] * fDiv + h2;
                zL = prev_zL * 0.9f + zL * 0.1f;
                zR = prev_zR * 0.9f + zR * 0.1f;
                yL = (int)zL; yR = (int)zR;
                if (yL > FX_YCUT_HIDE && yL < FXH - FX_YCUT_HIDE) {
                    D_offset = FXW * yL + i;
                    if (iDispBits == 8) { if (VS1[D_offset] < r) VS1[D_offset] = r; }
                    else { D_offset *= 4;
                        if (VS1[D_offset    ] < b) VS1[D_offset    ] = b;
                        if (VS1[D_offset + 1] < g) VS1[D_offset + 1] = g;
                        if (VS1[D_offset + 2] < r) VS1[D_offset + 2] = r; }
                }
                if (yR > FX_YCUT_HIDE && yR < FXH - FX_YCUT_HIDE) {
                    D_offset = FXW * yR + i;
                    if (iDispBits == 8) { if (VS1[D_offset] < r) VS1[D_offset] = r; }
                    else { D_offset *= 4;
                        if (VS1[D_offset    ] < b) VS1[D_offset    ] = b;
                        if (VS1[D_offset + 1] < g) VS1[D_offset + 1] = g;
                        if (VS1[D_offset + 2] < r) VS1[D_offset + 2] = r; }
                }
            }
        } else if (waveform == 3) {
            zL = g_fSoundBuffer[FX_YCUT_HIDE ^ (FX_YCUT_HIDE & 1)] + gXC;
            for (i = FX_YCUT_HIDE; i < FXH - FX_YCUT_HIDE; ++i) {
                prev_zL = zL;
                zL = g_fSoundBuffer[(i & 0xFFFFFFFE)] + gXC;
                zL = prev_zL * 0.9f + zL * 0.1f;
                xL = (int)zL;
                if (xL >= 0 && xL < FXW) {
                    D_offset = FXW * i + xL;
                    if (iDispBits == 8) { if (VS1[D_offset] < r) VS1[D_offset] = r; }
                    else { D_offset *= 4;
                        if (VS1[D_offset    ] < b) VS1[D_offset    ] = b;
                        if (VS1[D_offset + 1] < g) VS1[D_offset + 1] = g;
                        if (VS1[D_offset + 2] < r) VS1[D_offset + 2] = r; }
                }
            }
        } else if (waveform == 4) {
            float fDiv = 0.9f;
            zL = g_fSoundBuffer[FX_YCUT_HIDE ^ (FX_YCUT_HIDE & 1)] * fDiv;
            zR = g_fSoundBuffer[(FX_YCUT_HIDE ^ (FX_YCUT_HIDE & 1)) + 1] * fDiv;
            for (i = FX_YCUT_HIDE; i < FXH - FX_YCUT_HIDE; ++i) {
                prev_zL = zL; prev_zR = zR;
                zL = g_fSoundBuffer[(i & 0xFFFFFFFE)]     * fDiv;
                zR = g_fSoundBuffer[(i & 0xFFFFFFFE) + 1] * fDiv;
                zL = prev_zL * 0.9f + zL * 0.1f;
                zR = prev_zR * 0.9f + zR * 0.1f;
                xL = (int)zL + i;
                xR = (int)zR + i + (FXW - FXH);
                if (xL >= 0 && xL < FXW) {
                    D_offset = FXW * i + xL;
                    if (iDispBits == 8) { if (VS1[D_offset] < r) VS1[D_offset] = r; }
                    else { D_offset *= 4;
                        if (VS1[D_offset    ] < b) VS1[D_offset    ] = b;
                        if (VS1[D_offset + 1] < g) VS1[D_offset + 1] = g;
                        if (VS1[D_offset + 2] < r) VS1[D_offset + 2] = r; }
                }
                if (xR >= 0 && xR < FXW) {
                    D_offset = FXW * i + xR;
                    if (iDispBits == 8) { if (VS1[D_offset] < r) VS1[D_offset] = r; }
                    else { D_offset *= 4;
                        if (VS1[D_offset    ] < b) VS1[D_offset    ] = b;
                        if (VS1[D_offset + 1] < g) VS1[D_offset + 1] = g;
                        if (VS1[D_offset + 2] < r) VS1[D_offset + 2] = r; }
                }
            }
        } else if (waveform == 5) {
            int   px, py;
            float range_inv = 1.0f / WAVE_5_BLEND_RANGE;
            float amt;
            float rad;
            float base_rad = (FXW == 320) ? 40.0f : FXW / 640.0f * 60.0f;
            float fDiv = 0.7f;

            for (i = 0; i < WAVE_5_BLEND_RANGE; ++i) {
                amt = i * range_inv;
                g_fSoundBuffer[(i & 0xFFFFFFFE)] = g_fSoundBuffer[(i & 0xFFFFFFFE)] * amt
                                                 + (1 - amt) * g_fSoundBuffer[(i + 314) ^ ((i + 314) & 1)];
            }

            rad = base_rad + g_fSoundBuffer[0] * fDiv;
            for (i = 0; i < 314; ++i) {
                rad = rad * 0.5f + 0.5f * (base_rad + g_fSoundBuffer[(i & 0xFFFFFFFE)] * fDiv);
                if (rad >= 5) {
                    px = (int)((float)gXC + rad * cosf(i * 0.02f));
                    py = (int)((float)gYC + rad * sinf(i * 0.02f));
                    if (px >= 0 && px < FXW && py >= FX_YCUT && py < FXH - FX_YCUT) {
                        D_offset = FXW * py + px;
                        if (iDispBits == 8) { if (VS1[D_offset] < r) VS1[D_offset] = r; }
                        else { D_offset *= 4;
                            if (VS1[D_offset    ] < b) VS1[D_offset    ] = b;
                            if (VS1[D_offset + 1] < g) VS1[D_offset + 1] = g;
                            if (VS1[D_offset + 2] < r) VS1[D_offset + 2] = r; }
                    }
                }
            }
        } else if (waveform == 6) {
            int   px, py;
            float fDiv = 1.2f;
            float px2, py2;
            float ang = sinf(intframe * 0.01f);
            float cosang = cosf(ang);
            float sinang = sinf(ang);

            px2 = g_fSoundBuffer[0];
            py2 = g_fSoundBuffer[1];
            for (i = 0; i < 314; ++i) {
                px2 = px2 * 0.5f + 0.5f * g_fSoundBuffer[i * 2]     * fDiv;
                py2 = py2 * 0.5f + 0.5f * g_fSoundBuffer[i * 2 + 1] * fDiv;
                px = (int)(px2 * cosang + py2 * sinang);
                py = (int)(px2 * -sinang + py2 * cosang);
                px += gXC; py += gYC;
                if (px >= 0 && px < FXW && py >= FX_YCUT && py < FXH - FX_YCUT) {
                    D_offset = FXW * py + px;
                    if (iDispBits == 8) { if (VS1[D_offset] < r) VS1[D_offset] = r; }
                    else { D_offset *= 4;
                        if (VS1[D_offset    ] < b) VS1[D_offset    ] = b;
                        if (VS1[D_offset + 1] < g) VS1[D_offset + 1] = g;
                        if (VS1[D_offset + 2] < r) VS1[D_offset + 2] = r; }
                }
            }
        } else if (waveform == 7) {
            float dx = cosf(intframe * 0.03f);
            float dy = sinf(intframe * 0.03f);
            int   x_, y_;
            float t;

            if (fabsf(dx) > 0.001f) {
                float m = dy / dx;
                if (fabsf(dx) > fabsf(dy)) {
                    float bb = gYC - m * gXC;
                    for (x_ = 0; x_ < FXW; ++x_) {
                        y_ = (int)(m * x_ + bb);
                        if (y_ > FX_YCUT && y_ < FXH - FX_YCUT) {
                            D_offset = FXW * y_ + x_;
                            t = min(1.0f, fabsf(g_fSoundBuffer[x_ ^ (x_ & 1)] / 64.0f));
                            if (iDispBits == 8) { if (VS1[D_offset] < r * t) VS1[D_offset] = (unsigned char)(r * t); }
                            else { D_offset *= 4;
                                if (VS1[D_offset    ] < r * t) VS1[D_offset    ] = (unsigned char)(b * t);
                                if (VS1[D_offset + 1] < g * t) VS1[D_offset + 1] = (unsigned char)(g * t);
                                if (VS1[D_offset + 2] < b * t) VS1[D_offset + 2] = (unsigned char)(r * t); }
                        }
                    }
                } else {
                    m = dx / dy;
                    float bb = gXC - m * gYC;
                    for (y_ = FX_YCUT; y_ < FXH - FX_YCUT; ++y_) {
                        x_ = (int)(m * y_ + bb);
                        if (x_ >= 0 && x_ < FXW) {
                            D_offset = FXW * y_ + x_;
                            t = min(1.0f, fabsf(g_fSoundBuffer[y_ ^ (y_ & 1)] / 64.0f));
                            if (iDispBits == 8) { if (VS1[D_offset] < r * t) VS1[D_offset] = (unsigned char)(r * t); }
                            else { D_offset *= 4;
                                if (VS1[D_offset    ] < r * t) VS1[D_offset    ] = (unsigned char)(b * t);
                                if (VS1[D_offset + 1] < g * t) VS1[D_offset + 1] = (unsigned char)(g * t);
                                if (VS1[D_offset + 2] < b * t) VS1[D_offset + 2] = (unsigned char)(r * t); }
                        }
                    }
                }
            }
        }
    }
}

void RenderFX() {
    unsigned int fx;

    // SetCursor(NULL) is upstream's hack to suppress the Winamp cursor —
    // dead code on macOS; the no-op stub in win_compat.h handles it.
    SetCursor(NULL);

    floatframe += 1.6f * min(1.0f, 47.0f / fps);
    intframe++;
    frames_this_mode++;

    if ((intframe % 11) == 0)
        clearframes = 1;

    if (iBlendsLeftInPal > 0) {
        --iBlendsLeftInPal;
        PutPalette();
    }

    if (effect[SHADE]   > 0) ShadeBobs();
    if (effect[CHASERS] >= 1) Two_Chasers(floatframe + chaser_offset);
    if (effect[BAR] == 1) {
        float speed_mult           = 0.6f;
        float chromatic_dispersion = 4.0f;
        if (iDispBits == 8) {
            Solid_Line(floatframe + chaser_offset * speed_mult, VS1);
        } else {
            Solid_Line(floatframe + chaser_offset * speed_mult,                                                                              VS1);
            Solid_Line(floatframe + chaser_offset * speed_mult + 3.5f * chromatic_dispersion * (sinf(floatframe * 0.03f + 1) + cosf(floatframe * 0.04f + 3)), &VS1[1]);
            Solid_Line(floatframe + chaser_offset * speed_mult - 3.5f * chromatic_dispersion * (cosf(floatframe * 0.05f + 2) + sinf(floatframe * 0.06f + 4)), &VS1[2]);
        }
    }
    if (effect[DOTS]    == 1) One_Dotty_Chaser(floatframe);
    if (effect[NUCLIDE] == 1) Nuclide();
    if (effect[GRID]    == 1) Grid();

    if (effect[SOLAR] == 1) {
        if (FXW == 320) {
            fx = (unsigned int)(3 + solar_max * (2.4f + 0.35f * sinf(intframe * 0.05f) + 0.4f * sinf(intframe * 0.038f + 1)));
            Drop_Solar_Particles_320((int)(fx * 0.01f));
        } else {
            fx = (unsigned int)(3 + solar_max * 1.6f + solar_max * 0.43f * sinf(intframe * 0.05f) + solar_max * 0.43f * sinf(intframe * 0.038f + 1));
            Drop_Solar_Particles((int)(fx * 0.05f));
        }
    }

    Diminish_Center(VS1);
}

// ---------------------------------------------------------------------------
// Phase 1c-1: Configuration lever ABI
// ---------------------------------------------------------------------------
// Getters/setters for user-facing Geiss control levers, exposed to Swift
// via GeissEngine.swift. All operate on file-scope statics in this unit.
// See also: plan §1 in skills/geiss-port/SKILL.md.

extern "C" void geiss_port_get_config(GeissCoreConfig *out);
extern "C" void geiss_port_get_config(GeissCoreConfig *out) {
    if (!out) return;
    out->sensitivity = volscale;
    out->gamma = gamma;
    out->beatDetection = g_bUseBeatDetection ? 1 : 0;
    out->syncColorToSound = g_bSyncColorToSound ? 1 : 0;
    out->slideShift = g_bSlideShift ? 1 : 0;
    out->modeLocked = bLocked ? 1 : 0;
    out->paletteLocked = bPalLocked ? 1 : 0;
    out->autoSwitchSeconds = frames_til_auto_switch__registry / 30;
    out->visMode = (int)visMode;
}

extern "C" void geiss_port_set_config(const GeissCoreConfig *cfg);
extern "C" void geiss_port_set_config(const GeissCoreConfig *cfg) {
    if (!cfg) return;

    // sensitivity: pure read, applies next frame.
    volscale = cfg->sensitivity;

    // gamma: requires palette rebuild (mirrors upstream's gamma hotkey path).
    // Since FX_Random_Palette is the only palette mutation, trigger it.
    if (gamma != cfg->gamma) {
        gamma = cfg->gamma;
        FX_Random_Palette(true);  // true = don't shuffle c1/c2/c3, just recompute with new gamma
    }

    // beatDetection: pure read, applies next frame.
    g_bUseBeatDetection = cfg->beatDetection ? TRUE : FALSE;

    // syncColorToSound: pure read, applies next frame.
    g_bSyncColorToSound = cfg->syncColorToSound ? TRUE : FALSE;

    // slideShift: pure read, applies next frame.
    g_bSlideShift = cfg->slideShift;

    // modeLocked: applies at next chunk-completion (requires §0.1, §0.2).
    bLocked = cfg->modeLocked ? true : false;

    // paletteLocked: gated at palette mutation (line 579).
    bPalLocked = cfg->paletteLocked ? true : false;

    // autoSwitchSeconds: store in upstream's 30fps registry basis; map
    // generation scales this to the live fps when each mode starts.
    // (§0.3: the existing chunk-detection path picks it up from the registry)
    frames_til_auto_switch__registry = cfg->autoSwitchSeconds * 30;

    // visMode: pure read, applies next frame.
    visMode = (visModeEnum)cfg->visMode;
}

// geiss_port_randomize_palette(): trigger an immediate palette mutation,
// extracted from FX_Random_Palette's palette-generation logic.
// Mirrors upstream main.cpp's random-palette hotkey path (~lines 2900–2950
// in the original, though the exact line range drifts across versions).
// This is the user-facing "Randomize Palette" action called from the menu.
extern "C" void geiss_port_randomize_palette(void);
extern "C" void geiss_port_randomize_palette(void) {
    if (bPalLocked) return;
    if (iDispBits != 8) return;

    // Randomize the palette-generation parameters and regenerate.
    // This is the palette-shuffle path from FX_Random_Palette(false).

    int n, a, b;

    old_palette.lo_band       = -1;
    old_palette.hi_band       = -1;
    old_palette.bFXPalette    = false;
    old_palette.iFXPaletteNum = -1;
    old_palette.c1            = -1;
    old_palette.c2            = -1;
    old_palette.c3            = -1;

    if (rand() % 10 < coarse_pal_freq) {
        old_palette.lo_band = 7  + rand() % 6;
        old_palette.hi_band = 17 + rand() % 6;
    }

    iBlendsLeftInPal = 18;

    b = rand() % 6;

    if (b == 0) {
        old_palette.bFXPalette = true;
        old_palette.iFXPaletteNum = rand() % 4;

        if (old_palette.iFXPaletteNum == 0) {
            for (a = 0; a < 128; ++a) {
                REMAP [a] = (unsigned char)(a * a / 64.0f);
                REMAP2[a] = (unsigned char)(a * 2);
                REMAP3[a] = (unsigned char)(sqrtf((float)a) * 22.6f);
            }
        } else if (old_palette.iFXPaletteNum == 1) {
            for (a = 0; a < 128; ++a) {
                REMAP [a] = (unsigned char)(a * a / 64.0f);
                REMAP2[a] = (unsigned char)(sqrtf((float)a) * 22.6f);
                REMAP3[a] = (unsigned char)(a * 2);
            }
        } else if (old_palette.iFXPaletteNum == 2) {
            for (a = 0; a < 128; ++a) {
                REMAP [a] = (unsigned char)(sqrtf((float)a) * 22.6f);
                REMAP2[a] = (unsigned char)(a * 2);
                REMAP3[a] = (unsigned char)(a * a / 64.0f);
            }
        } else if (old_palette.iFXPaletteNum == 3) {
            for (a = 0; a < 128; ++a) {
                REMAP [a] = (unsigned char)(a * 2);
                REMAP2[a] = (unsigned char)(a * a / 64.0f);
                REMAP3[a] = (unsigned char)(sqrtf((float)a) * 22.6f);
            }
        }

        for (n = 128; n < 256; ++n) {
            REMAP [n] = REMAP [127];
            REMAP2[n] = REMAP2[127];
            REMAP3[n] = REMAP3[127];
        }

        for (n = 0; n < 256; ++n) {
            ape[n]          = ape2[n];
            ape2[n].peRed   = REMAP [n];
            ape2[n].peBlue  = REMAP2[n];
            ape2[n].peGreen = REMAP3[n];
        }
    } else {
        int temp;
        do {
            if (rand() % 5 < solar_pal_freq) {
                old_palette.c1 = rand() % 7 + 1;
                old_palette.c2 = rand() % 7 + 1;
                old_palette.c3 = rand() % 7 + 1;
            } else {
                old_palette.c1 = rand() % 6 + 1;
                old_palette.c2 = rand() % 6 + 1;
                old_palette.c3 = rand() % 6 + 1;
            }
            temp = 0;
            if (old_palette.c1 == 6) ++temp;
            if (old_palette.c2 == 6) ++temp;
            if (old_palette.c3 == 6) ++temp;
        } while (temp > 1);

        float xv, yv, zv;
        float gamma_factor = 1.0f + gamma * 0.01f;
        if (SoundEmpty) gamma_factor += 0.3f;

        for (n = 0; n < 256; ++n) {
            ape[n] = ape2[n];

            xv = CrankPal(old_palette.c1, (unsigned char)n);
            yv = CrankPal(old_palette.c2, (unsigned char)n);
            zv = CrankPal(old_palette.c3, (unsigned char)n);

            xv *= gamma_factor;
            yv *= gamma_factor;
            zv *= gamma_factor;

            if (n > old_palette.lo_band && n < old_palette.hi_band) {
                xv *= 2.0f;
                yv *= 2.0f;
                zv *= 2.0f;
            }

            ape2[n].peRed   = (unsigned char)min(255.0f, xv);
            ape2[n].peBlue  = (unsigned char)min(255.0f, yv);
            ape2[n].peGreen = (unsigned char)min(255.0f, zv);
        }
    }
}

// ---------------------------------------------------------------------------
// Phase 4c-6 marker.
// ---------------------------------------------------------------------------
extern "C" int geiss_port_step(void);
extern "C" int geiss_port_step(void) { return 6; }
