#ifndef TRIPEX_WIN_COMPAT_H
#define TRIPEX_WIN_COMPAT_H

// Minimal Win32/MSVC compatibility shim for vendoring ben-marsh/tripex on
// macOS/clang. Tripex is a D3D9 + Win32 app; we replace D3D with an OpenGL
// renderer (RendererOpenGL) and stub the Win32 surface the math/effect code
// references. main.cpp + RendererDirect3d.{cpp,h} + AudioDevice.cpp are
// excluded from compilation entirely — those carry the bulk of Win32/D3D.

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#ifdef __cplusplus
#include <chrono>
#endif

// MSVC integer aliases used by Platform.h pattern (Tripex's Platform.h does
// not define these — Tripex code uses int8/uint8 etc., not MSVC __intN — but
// keep parity with the Geiss shim for safety).
typedef int8_t   __int8_compat;
typedef int16_t  __int16_compat;
typedef int32_t  __int32_compat;
typedef int64_t  __int64_compat;

// Win32 handle/type aliases referenced by retained Tripex code paths. Most
// upstream files do not actually reference these (D3D + Win32 live in the
// excluded TUs), but a handful of headers/casts mention HRESULT/DWORD.
typedef int            BOOL;
typedef unsigned char  BYTE;
typedef unsigned short WORD;
typedef uint32_t       DWORD;
typedef int32_t        LONG;
typedef uint32_t       ULONG;
typedef uint32_t       UINT;
typedef uint64_t       ULONGLONG;
typedef int32_t        HRESULT;
typedef uintptr_t      WPARAM;
typedef intptr_t       LPARAM;
typedef intptr_t       LRESULT;
typedef char           *LPSTR;
typedef const char     *LPCSTR;
typedef void           *HANDLE;
typedef void           *HWND;
typedef void           *HINSTANCE;
typedef void           *HMODULE;

typedef struct _TripexPOINT { LONG x, y; } POINT;
typedef struct _TripexRECT  { LONG left, top, right, bottom; } RECT;

#include <strings.h>
#include <math.h>
#include <float.h>
#ifndef _copysign
#define _copysign copysign
#endif

#ifndef fopen_s
static inline int fopen_s(FILE** f, const char* name, const char* mode) {
    if (!f) return 1;
    *f = fopen(name, mode);
    return (*f == NULL) ? 1 : 0;
}
#endif

#ifndef WAVE_FORMAT_PCM
#define WAVE_FORMAT_PCM 1
#endif

#ifndef __assume
#define __assume(x) ((void)0)
#endif

#ifndef ZeroMemory
#define ZeroMemory(p, sz) memset((p), 0, (sz))
#endif

#ifndef FAILED
#define FAILED(hr) (((HRESULT)(hr)) < 0)
#endif
#ifndef SUCCEEDED
#define SUCCEEDED(hr) (((HRESULT)(hr)) >= 0)
#endif

#ifndef _stricmp
#define _stricmp strcasecmp
#endif
#ifndef _strnicmp
#define _strnicmp strncasecmp
#endif

#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

#ifndef WINAPI
#define WINAPI
#endif
#ifndef CALLBACK
#define CALLBACK
#endif

// Timing shims — only needed from C++ TUs (upstream Tripex code).
// Hidden from the C-mode Swift importer, which compiles TripexCore.h
// alongside this header without <chrono> available.
#ifdef __cplusplus
static inline ULONGLONG GetTickCount64(void) {
    using clock = std::chrono::steady_clock;
    static const auto t0 = clock::now();
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(clock::now() - t0).count();
    return (ULONGLONG)ms;
}

static inline DWORD GetTickCount(void) {
    return (DWORD)GetTickCount64();
}

static inline DWORD timeGetTime(void) { return GetTickCount(); }
#endif // __cplusplus

#endif // TRIPEX_WIN_COMPAT_H
