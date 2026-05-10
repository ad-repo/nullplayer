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
void  dumpmsg(const char *format, ...);

// ---------------------------------------------------------------------------
// Compatibility helpers used by Effects.h that have to be C++-callable but
// must not collide with any STL/Foundation symbols on macOS.
// ---------------------------------------------------------------------------

// `__int16 abs_*` etc. — Effects.h calls plain `abs(int)`; that's already in
// <cstdlib>. No work needed here.

// dumpmsg is upstream's lightweight printf-to-debugfile; on macOS we discard.
void dumpmsg(const char * /*format*/, ...) { }

// Provisional stubs so the file links cleanly at the 4c-3 checkpoint.
// Real implementations land in sub-phases 4c-5 (GenerateChunkOfNewMap) and
// 4c-7 (FX_Random_Palette / PutPalette / CrankPal).
void FX_Random_Palette(bool /*bLoadPal*/) { }
void PutPalette() { }
float CrankPal(unsigned int /*curve_id*/, int /*z*/) { return 255.0f; }
void GenerateChunkOfNewMap(bool /*bLoadPreset*/, int /*iPresetNum*/) { }

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
// Phase 4c-3 marker.
// ---------------------------------------------------------------------------
extern "C" int geiss_port_step(void);
extern "C" int geiss_port_step(void) { return 3; }
