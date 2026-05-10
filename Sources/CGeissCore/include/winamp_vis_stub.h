#ifndef GEISS_WINAMP_VIS_STUB_H
#define GEISS_WINAMP_VIS_STUB_H

// ---------------------------------------------------------------------------
// Phase 4c-1: replacement for Winamp's <vis.h>. The original header (deleted
// in phase 3) defined the `winampVisModule` / `winampVisHeader` structs the
// Geiss DLL exposed to the Winamp host. The upstream Geiss port retains
// scattered references to these structs (the global `mod1`, the `g_this_mod`
// pointer, the prototypes of `init`/`render1`/`config`/`quit`).
//
// Geiss's port file gates the actual Winamp-DLL machinery out, but the *type
// declarations* still need to exist so the surrounding code parses. This
// header provides a minimal API-compatible struct definition.
// ---------------------------------------------------------------------------

#include "win_compat.h"

#define VIS_HDRVER 0x101

#ifdef __cplusplus
extern "C" {
#endif

typedef struct winampVisModule
{
    char       *description;
    HWND        hwndParent;
    HINSTANCE   hDllInstance;
    int         sRate;
    int         nCh;
    int         latencyMs;
    int         delayMs;
    int         spectrumNch;
    int         waveformNch;
    unsigned char spectrumData[2][576];
    unsigned char waveformData[2][576];
    void      (*Config)(struct winampVisModule *this_mod);
    int       (*Init)  (struct winampVisModule *this_mod);
    int       (*Render)(struct winampVisModule *this_mod);
    void      (*Quit)  (struct winampVisModule *this_mod);
    void       *userData;
} winampVisModule;

typedef struct winampVisHeader
{
    int    version;
    char  *description;
    winampVisModule *(*getModule)(int);
} winampVisHeader;

#ifdef __cplusplus
} // extern "C"
#endif

#endif // GEISS_WINAMP_VIS_STUB_H
